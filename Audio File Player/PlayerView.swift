import SwiftUI
import UIKit
@preconcurrency import Translation

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(AudioLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var transcriptionManager = SpeechTranscriptionManager()

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var artworkScale: CGFloat = 1.0
    @State private var showingTranscript = false

    @State private var showingTranslation = false
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var translationConfig: TranslationSession.Configuration?

    private var displayTime: TimeInterval { isDragging ? dragTime : player.currentTime }
    private var remaining: TimeInterval { max(0, player.duration - displayTime) }

    var body: some View {
        // Root VStack owns the layout — no ZStack siblings fighting for width.
        // Both backgrounds live in .background so they never affect content sizing.
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)

            if showingTranscript {
                transcriptContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else {
                artwork
                    .padding(.horizontal, 36)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
            }

            controlsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Backgrounds are decorative — keeping them out of the layout tree
            // prevents ignoresSafeArea from distorting content VStack widths.
            ZStack {
                background
                if showingTranscript {
                    mosaicBackground
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: showingTranscript)
        }
        .animation(.spring(duration: 0.35), value: showingTranscript)
        .translationTask(translationConfig) { session in
            do {
                isTranslating = true
                let response = try await session.translate(transcriptionManager.transcript)
                translatedText = response.targetText
            } catch {
                print("Translation error: \(error)")
            }
            isTranslating = false
        }
        .onAppear {
            player.onTrackEnd = { playNext() }
            player.onNext = { playNext() }
            player.onPrevious = { playPrevious() }
            transcriptionManager.requestAuthorization()
        }
        .onChange(of: player.currentFile?.id) {
            withAnimation(.spring(duration: 0.4)) { artworkScale = 0.9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(duration: 0.4)) {
                    artworkScale = player.isPlaying ? 1.0 : 0.88
                }
            }
            transcriptionManager.clearTranscript()
            showingTranscript = false
            showingTranslation = false
            translatedText = ""
            translationConfig = nil
        }
        .onChange(of: player.isPlaying) { _, playing in
            withAnimation(.spring(duration: 0.4)) {
                artworkScale = playing ? 1.0 : 0.88
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(hue: 0.75, saturation: 0.7, brightness: 0.5),
                    Color(hue: 0.60, saturation: 0.8, brightness: 0.35),
                    Color(hue: 0.85, saturation: 0.6, brightness: 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.55))
                .frame(width: 350)
                .blur(radius: 70)
                .offset(x: -100, y: -180)

            Circle()
                .fill(Color.blue.opacity(0.45))
                .frame(width: 280)
                .blur(radius: 60)
                .offset(x: 130, y: -60)

            Circle()
                .fill(Color.indigo.opacity(0.4))
                .frame(width: 240)
                .blur(radius: 60)
                .offset(x: -60, y: 200)
        }
    }

    // MARK: - Full-screen mosaic (Apple Music lyrics background style)

    private var mosaicBackground: some View {
        ZStack {
            // Deep purple base — not black, so blobs read against it
            Color(hue: 0.73, saturation: 0.60, brightness: 0.18)

            // Bright, large blobs — paint-wash effect
            Circle()
                .fill(Color(hue: 0.80, saturation: 1.00, brightness: 0.92))
                .frame(width: 520)
                .blur(radius: 130)
                .offset(x: -70, y: -310)

            Circle()
                .fill(Color(hue: 0.63, saturation: 0.90, brightness: 0.88))
                .frame(width: 480)
                .blur(radius: 120)
                .offset(x: 150, y: -90)

            Circle()
                .fill(Color(hue: 0.87, saturation: 0.88, brightness: 0.82))
                .frame(width: 440)
                .blur(radius: 115)
                .offset(x: -110, y: 160)

            Circle()
                .fill(Color(hue: 0.70, saturation: 0.85, brightness: 0.80))
                .frame(width: 510)
                .blur(radius: 125)
                .offset(x: 120, y: 370)

            Circle()
                .fill(Color(hue: 0.75, saturation: 0.95, brightness: 0.75))
                .frame(width: 380)
                .blur(radius: 100)
                .offset(x: -20, y: 560)

            // Light overlay — just enough for text contrast, not enough to kill the color
            Color.black.opacity(0.28)
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            // Closes transcript if open, otherwise closes the player
            Button {
                if showingTranscript {
                    withAnimation(.spring(duration: 0.35)) {
                        showingTranscript = false
                        showingTranslation = false
                    }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Now Playing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(1)
            }

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.35)) {
                    showingTranscript.toggle()
                    if !showingTranscript { showingTranslation = false }
                }
            } label: {
                Image(systemName: showingTranscript ? "text.quote.rtl" : "text.quote")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
        }
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }

            Image(systemName: player.isPlaying ? "waveform" : "music.note")
                .font(.system(size: 88, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.variableColor.iterative.reversing, isActive: player.isPlaying)
                .contentTransition(.symbolEffect(.replace))
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(artworkScale)
        .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
    }

    // MARK: - Transcript Content (full-height, Apple Music lyrics style)

    private var transcriptContent: some View {
        VStack(spacing: 0) {
            // Track header — mirroring Apple Music's compact header inside the lyrics view
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentFile?.displayName ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Transcript")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                // Explicit close-transcript button so it's always visible
                Button {
                    withAnimation(.spring(duration: 0.35)) {
                        showingTranscript = false
                        showingTranslation = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.15), in: Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Main area — transcribing spinner / empty state / scrollable text
            Group {
                if transcriptionManager.isTranscribing {
                    // Batch transcription in progress — show a spinner, no partial text
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Transcribing full audio…")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("This may take a moment")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if transcriptionManager.transcript.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("No Transcript Yet")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(transcriptionManager.authorizationStatus == .authorized
                             ? "Tap below to transcribe"
                             : "Speech recognition access required")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                        Button {
                            if let file = player.currentFile {
                                Task { await transcriptionManager.transcribe(audioFile: file) }
                            }
                        } label: {
                            Label(
                                transcriptionManager.authorizationStatus == .authorized
                                    ? "Generate Transcript"
                                    : "Enable Speech Recognition",
                                systemImage: "waveform.and.mic"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.2), in: Capsule())
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else {
                    // Full transcript — rendered once, completely, in a scroll view
                    let displayText = showingTranslation
                        ? (isTranslating ? "Translating…" : translatedText)
                        : transcriptionManager.transcript

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(displayText)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            // fixedSize prevents the text from expanding horizontally
                            // beyond its container — fixes the off-screen overflow bug
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .transaction { $0.animation = nil }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Action bar — translate / reset
            if !transcriptionManager.transcript.isEmpty && !transcriptionManager.isTranscribing {
                HStack(spacing: 12) {
                    Button {
                        if showingTranslation {
                            showingTranslation = false
                        } else {
                            if translatedText.isEmpty {
                                translationConfig = TranslationSession.Configuration(
                                    source: Locale.Language(identifier: "fr"),
                                    target: Locale.Language(identifier: "en")
                                )
                            }
                            showingTranslation = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isTranslating {
                                ProgressView().scaleEffect(0.75).tint(.white)
                            } else {
                                Image(systemName: showingTranslation ? "globe" : "translate")
                            }
                            Text(showingTranslation ? "Original" : "Translate")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(showingTranslation ? .white.opacity(0.3) : .white.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    }

                    Spacer()

                    Button {
                        transcriptionManager.clearTranscript()
                        showingTranslation = false
                        translatedText = ""
                        translationConfig = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            trackInfo
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)

            scrubber
                .padding(.horizontal, 28)
                .padding(.bottom, 28)

            transportControls
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            speedSelector
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentFile?.displayName ?? "No Track Selected")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("Audio File")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { v in dragTime = v; isDragging = true }
                ),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing { player.seek(to: dragTime); isDragging = false }
            }
            .tint(.white)

            HStack {
                Text(formatTime(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-" + formatTime(remaining))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            TrackButton(icon: "backward.end.fill", size: .medium) { playPrevious() }
            Spacer()
            SkipButton(seconds: -15, longPressSeconds: -30, player: player)
            Spacer()
            playPauseButton
            Spacer()
            SkipButton(seconds: 15, longPressSeconds: 30, player: player)
            Spacer()
            TrackButton(icon: "forward.end.fill", size: .medium) { playNext() }
        }
    }

    private var playPauseButton: some View {
        Button { player.togglePlayPause() } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: player.isPlaying ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Selector

    private var speedSelector: some View {
        HStack(spacing: 6) {
            ForEach(player.speedOptions, id: \.self) { speed in
                Button {
                    withAnimation(.spring(duration: 0.25)) { player.setSpeed(speed) }
                } label: {
                    Text(labelFor(speed))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if player.playbackSpeed == speed {
                                Capsule().fill(.white.opacity(0.25))
                                    .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                            } else {
                                Capsule().fill(.white.opacity(0.06))
                            }
                        }
                        .foregroundStyle(player.playbackSpeed == speed ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func labelFor(_ speed: Float) -> String {
        switch speed {
        case 0.25: return "¼×"
        case 0.5:  return "½×"
        case 1.0:  return "1×"
        case 1.5:  return "1.5×"
        case 2.0:  return "2×"
        default:   return "\(speed)×"
        }
    }

    private func playNext() {
        let files = library.audioFiles
        guard !files.isEmpty else { return }
        let next = (player.currentIndex + 1) % files.count
        player.load(file: files[next], index: next)
    }

    private func playPrevious() {
        let files = library.audioFiles
        guard !files.isEmpty else { return }
        let prev = player.currentIndex > 0 ? player.currentIndex - 1 : files.count - 1
        player.load(file: files[prev], index: prev)
    }
}

// MARK: - Supporting Views

struct TrackButton: View {
    enum Size { case medium }
    let icon: String
    let size: Size
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

struct SkipButton: View {
    let seconds: TimeInterval
    let longPressSeconds: TimeInterval
    let player: AudioPlayerManager

    @State private var longPressTriggered = false
    private var isForward: Bool { seconds > 0 }

    var body: some View {
        let icon = isForward ? "goforward.15" : "gobackward.15"
        Image(systemName: icon)
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !longPressTriggered else { return }
                player.skip(seconds)
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                longPressTriggered = true
                player.skip(longPressSeconds)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    longPressTriggered = false
                }
            }
    }
}
