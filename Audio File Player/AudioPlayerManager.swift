import Foundation
import AVFoundation
import Combine

// ObservableObject + @Published has no actor-isolation runtime assertions.
// @MainActor @Observable generates dispatch_assert_queue checks that conflict
// with AVFoundation's background callbacks even with every bridging technique.
final class AudioPlayerManager: ObservableObject {
    @Published var currentFile: AudioFile?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentIndex: Int = -1

    var onTrackEnd: (() -> Void)?
    let speedOptions: [Float] = [0.25, 0.5, 1.0, 1.5, 2.0]

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var securityScopedURL: URL?

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

        // KVO fires on an arbitrary thread — dispatch to main before touching @Published state.
        // With ObservableObject there are no actor assertions; DispatchQueue.main.async is enough.
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
                if self.isPlaying {
                    self.player?.play()
                    self.player?.rate = self.playbackSpeed
                }
            }
        }

        // Already on .main — update @Published directly, no wrapping needed.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
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
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
    }

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
