# Audio File Player — iCloud

An iOS audio player for files stored in iCloud Drive, built with SwiftUI and AVFoundation.

---

## Features

- **iCloud Drive import** — pick individual files or entire folders; supports MP3, M4A, WAV, AAC, FLAC, OPUS, AIFF, CAF, M4B, MP4
- **Security-scoped bookmarks** — persistent access to iCloud files across launches, no re-importing needed
- **Playback controls** — play/pause, scrubber, skip ±15 s (tap) / ±30 s (long-press), previous/next track
- **Speed control** — ¼×, ½×, 1×, 1.5×, 2× with a tap
- **Mini player** — compact bar with progress indicator, visible while browsing the library
- **Full-screen player** — large artwork area, track info, scrubber, transport controls, speed selector
- **French transcription** — on-device speech recognition via Apple's Speech framework (fr-FR locale)
- **Frosted-glass UI** — translucent materials, layered gradients, and blur effects using native iOS APIs (`UIBlurEffect` / `.ultraThinMaterial`)

---

## Design

The interface uses iOS's built-in material system:

| Element | API used |
|---|---|
| Frosted panels | `.ultraThinMaterial` / `.regularMaterial` |
| Gradient background | `LinearGradient` + layered `Circle` blurs |
| Animations | `.spring()` transitions, `symbolEffect` |
| Iconography | SF Symbols |

All visual effects are implemented with public Apple APIs. No proprietary design assets or trademarked design systems are used.

---

## Requirements

- iOS 17+
- Xcode 15+
- Swift 5.9+
- iCloud Drive enabled on device

---

## Project Structure

```
Audio File Player/
├── AudioFilePlayerApp.swift       # App entry point
├── AudioPlayerManager.swift       # AVPlayer wrapper (ObservableObject)
├── AudioLibraryManager.swift      # File library, bookmarks, UserDefaults persistence
├── SpeechTranscriptionManager.swift # Speech recognition (fr-FR)
├── Models.swift                   # AudioFile struct, formatTime()
├── ContentView.swift              # Library list, mini player
├── PlayerView.swift               # Full-screen player
├── MiniPlayerView.swift           # Compact player bar
└── DocumentPickerView.swift       # UIDocumentPickerViewController wrapper
```

---

## Concurrency Notes

Swift 5.9 introduced a runtime behavior where closures created inside `@MainActor`-isolated methods inherit actor isolation. System callbacks (TCC permission replies, AVFoundation KVO) are delivered on background threads — if those closures carry a `@MainActor` runtime check, the app crashes with `_dispatch_assert_queue_fail`.

Key patterns used here:

```swift
// Methods that pass @escaping closures to system APIs must be nonisolated
nonisolated func requestAuthorization() {
    SFSpeechRecognizer.requestAuthorization { status in
        Task { @MainActor [weak self] in   // hop to main actor explicitly
            self?.authorizationStatus = status
        }
    }
}

// AVFoundation KVO fires on arbitrary threads — dispatch to main before touching @Published state
itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
    DispatchQueue.main.async { [weak self] in
        self?.duration = ...
    }
}
```

---

## Setup

1. Clone the repo
2. Open `Audio File Player.xcodeproj` in Xcode 15+
3. Set your Team in **Signing & Capabilities**
4. Run on simulator or device (iOS 17+)
5. Tap **+** to import audio files from iCloud Drive

For speech recognition, add `NSSpeechRecognitionUsageDescription` to `Info.plist` if not already present.

---

## License

MIT
