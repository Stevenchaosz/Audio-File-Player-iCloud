import Foundation
import AVFoundation
import Combine
import MediaPlayer

final class AudioPlayerManager: ObservableObject {
    @Published var currentFile: AudioFile?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentIndex: Int = -1

    var onTrackEnd: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
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

        currentFile = file
        currentIndex = index
        currentTime = 0
        duration = 0
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
        var info: [String: Any] = [
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
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.skip(15) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.skip(-15) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(to: e.positionTime) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onNext?() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onPrevious?() }
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
