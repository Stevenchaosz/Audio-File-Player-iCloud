import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayerManager {
    var currentFile: AudioFile?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackSpeed: Float = 1.0
    var currentIndex: Int = -1

    var onTrackEnd: (() -> Void)?

    let speedOptions: [Float] = [0.25, 0.5, 1.0, 1.5, 2.0]

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var securityScopedURL: URL?

    func load(file: AudioFile, index: Int) {
        print("🎵 Attempting to load file: \(file.name)")
        
        guard let url = file.resolvedURL else {
            print("⚠️ ERROR: Could not resolve URL from bookmark for file: \(file.name)")
            print("⚠️ This usually means the file bookmark is invalid or expired")
            return
        }
        
        print("✅ URL resolved: \(url.path)")

        cleanup()

        securityScopedURL?.stopAccessingSecurityScopedResource()
        let accessing = url.startAccessingSecurityScopedResource()
        securityScopedURL = accessing ? url : nil
        
        print("🔐 Security-scoped access: \(accessing ? "granted" : "not needed")")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("⚠️ Audio session error: \(error)")
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        
        print("🎬 Creating AVPlayer with item")

        if player == nil {
            player = AVPlayer(playerItem: item)
            print("✅ New AVPlayer created")
        } else {
            player?.replaceCurrentItem(with: item)
            print("✅ Replaced current item")
        }

        currentFile = file
        currentIndex = index
        currentTime = 0
        duration = 0
        
        print("📊 Set current file and index")

        // Capture self weakly and properties we need
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let dur = CMTimeGetSeconds(observedItem.duration)
            let error = observedItem.error
            
            // Everything must happen on main thread for @MainActor class
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("📡 Item status changed: \(status.rawValue)")
                guard status == .readyToPlay else {
                    if status == .failed {
                        print("⚠️ ERROR: Player item failed to load!")
                        if let error = error {
                            print("⚠️ Error details: \(error.localizedDescription)")
                        }
                    }
                    return
                }
                print("✅ Item ready to play! Duration: \(dur)s")
                self.duration = dur.isFinite ? dur : 0
                // Start playback once ready
                if self.isPlaying {
                    self.player?.play()
                    self.player?.rate = self.playbackSpeed
                    print("▶️ Playback started (ready)")
                }
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = CMTimeGetSeconds(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("⏭️ Track ended")
                self.isPlaying = false
                self.onTrackEnd?()
            }
        }

        // Mark as playing - actual playback starts when item is ready
        isPlaying = true
        
        print("⏳ Waiting for item to be ready...")
        print("✅ Load complete!")
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            print("⏸️ Paused")
        } else {
            player?.play()
            player?.rate = playbackSpeed
            isPlaying = true
            print("▶️ Playing at \(playbackSpeed)x")
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
