import Foundation
import AVFoundation
import Combine
import MediaPlayer

final class AudioPlayerManager: ObservableObject, @unchecked Sendable {
    @Published var currentFile: AudioFile?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentIndex: Int = -1
    @Published var isDownloading = false

    var onTrackEnd: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onLoad: ((UUID) -> Void)?
    let speedOptions: [Float] = [0.25, 0.5, 1.0, 1.5, 2.0]

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var securityScopedURL: URL?
    private var remoteCommandsRegistered = false

    func load(file: AudioFile, index: Int) {
        guard let url = file.resolvedURL else {
            print("⚠️ Could not resolve URL from bookmark for: \(file.name)")
            return
        }

        cleanup()
        securityScopedURL?.stopAccessingSecurityScopedResource()
        let accessing = url.startAccessingSecurityScopedResource()
        securityScopedURL = accessing ? url : nil

        // Update visible state immediately so the UI shows the right track
        currentFile = file
        currentIndex = index
        currentTime = 0
        duration = 0
        let loadedID = file.id
        Task { @MainActor [weak self] in self?.onLoad?(loadedID) }

        // iCloud files that haven't been downloaded yet have status .notDownloaded.
        // Trying to play them directly fails with "operation could not be completed".
        // Trigger a download first and wait for it before handing off to AVPlayer.
        let downloadStatus = (try? url.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        ))?.ubiquitousItemDownloadingStatus

        if downloadStatus == .notDownloaded {
            isPlaying = false
            isDownloading = true
            let fileID = file.id
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    print("⚠️ Could not start iCloud download: \(error)")
                    self.isDownloading = false
                    return
                }

                var downloaded = false
                let deadline = Date().addingTimeInterval(300) // 5-minute ceiling
                while Date() < deadline {
                    let values = try? url.resourceValues(
                        forKeys: [.ubiquitousItemDownloadingStatusKey]
                    )
                    if values?.ubiquitousItemDownloadingStatus != .notDownloaded {
                        downloaded = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    // Abort if the user switched to a different track while we waited
                    guard self.currentFile?.id == fileID else { return }
                }

                guard self.currentFile?.id == fileID else { return }
                self.isDownloading = false

                if downloaded {
                    self.startPlayback(url: url, file: file, index: index)
                } else {
                    print("⚠️ iCloud download timed out for: \(file.name)")
                }
            }
            return
        }

        isDownloading = false
        startPlayback(url: url, file: file, index: index)
    }

    // MARK: - Internal playback start (called once the file is locally available)

    private func startPlayback(url: URL, file: AudioFile, index: Int) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio session error: \(error)")
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        isPlaying = true

        setupNowPlaying(file: file)
        if !remoteCommandsRegistered {
            setupRemoteCommands()
            remoteCommandsRegistered = true
        }

        itemObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let dur = CMTimeGetSeconds(observedItem.duration)
            let error = observedItem.error

            DispatchQueue.main.async { [weak self] in
                guard let self, status == .readyToPlay else {
                    if status == .failed, let error {
                        print("⚠️ Player item failed: \(error.localizedDescription)")
                    }
                    return
                }
                self.duration = dur.isFinite ? dur : 0
                self.updateNowPlayingDuration()
                if self.isPlaying {
                    self.player?.play()
                    self.player?.rate = self.playbackSpeed
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
            self?.updateNowPlayingTime()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.updateNowPlayingPlaybackState()
            self?.onTrackEnd?()
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            player?.rate = playbackSpeed
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateNowPlayingTime()
    }

    func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingPlaybackState()
    }

    // MARK: - Lock Screen / Now Playing

    private func setupNowPlaying(file: AudioFile) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: file.displayName,
            MPMediaItemPropertyArtist: "Audio File Player",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: 0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingDuration() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackSpeed) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackSpeed) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.togglePlayPause() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.togglePlayPause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.skip(15) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.skip(-15) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            DispatchQueue.main.async { @Sendable [self, position] in self?.seek(to: position) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.onNext?() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { @Sendable [self] in self?.onPrevious?() }
            return .success
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        itemObserver?.invalidate()
        itemObserver = nil
    }
}
