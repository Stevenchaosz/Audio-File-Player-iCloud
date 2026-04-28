import SwiftUI
import UIKit
import Translation

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
        ZStack {
            background

            VStack(spacing: 0) {
                navBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                if showingTranscript {
                    transcriptView
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    artwork
                        .padding(.horizontal, 36)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                controlsPanel
                    .padding(.bottom, 0)
            }
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
            withAnimation(.spring(duration: 0.4)) {
                artworkScale = 0.9
            }
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

            // Ambient blobs for depth and translucency
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

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
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
                showingTranscript.toggle()
                if !showingTranscript {
                    showingTranslation = false
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

    // MARK: - Transcript View

    private var transcriptView: some View {
        let displayText = showingTranslation
            ? (translatedText.isEmpty ? (isTranslating ? "Translating…" : "") : translatedText)
            : transcriptionManager.transcript

        return ZStack(alignment: .bottom) {
            // Mosaic + frosted background
            ZStack {
                mosaicBackground
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.black.opacity(0.35))

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }

            VStack(spacing: 0) {
                if transcriptionManager.transcript.isEmpty {
                    emptyTranscriptPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(displayText)
                                .font(.title3.weight(.regular))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 80)
                                .animation(.none, value: transcriptionManager.transcript)
                                .id("bottom")
                        }
                        .onChange(of: transcriptionManager.transcript) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Bottom action bar (always visible, overlaps text)
            transcriptActionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 320)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
    }

    private var emptyTranscriptPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: transcriptionManager.isTranscribing ? "waveform" : "text.quote")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .symbolEffect(.variableColor.iterative.reversing, isActive: transcriptionManager.isTranscribing)

            if transcriptionManager.isTranscribing {
                Text("Transcribing…")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            } else if transcriptionManager.authorizationStatus != .authorized {
                Text("Speech Recognition Access Required")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tap below to enable")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("No Transcript Yet")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tap below to transcribe")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding()
    }

    private var transcriptActionBar: some View {
        HStack(spacing: 10) {
            if !transcriptionManager.isTranscribing && transcriptionManager.transcript.isEmpty {
                Button {
                    if let file = player.currentFile {
                        Task {
                            await transcriptionManager.transcribe(audioFile: file)
                        }
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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
            }

            if !transcriptionManager.transcript.isEmpty {
                // Translate / Original toggle
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
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.white)
                        } else {
                            Image(systemName: showingTranslation ? "globe" : "translate")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(showingTranslation ? "Original" : "Translate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(showingTranslation ? .white.opacity(0.3) : .white.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }

                Spacer()

                // Clear / re-transcribe
                if !transcriptionManager.isTranscribing {
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
            }
        }
    }

    // MARK: - Mosaic Background

    private var mosaicBackground: some View {
        Canvas { ctx, size in
            let cols = 5
            let rows = 9
            let w = size.width / CGFloat(cols)
            let h = size.height / CGFloat(rows)
            let palette: [(hue: Double, sat: Double, bri: Double)] = [
                (0.75, 0.80, 0.55),
                (0.65, 0.75, 0.45),
                (0.82, 0.70, 0.50),
                (0.60, 0.85, 0.40),
                (0.70, 0.60, 0.60),
                (0.78, 0.90, 0.35),
            ]
            for row in 0..<rows {
                for col in 0..<cols {
                    let idx = (row &* 3 &+ col &* 2) % palette.count
                    let c = palette[idx]
                    let rect = CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w + 1, height: h + 1)
                    ctx.fill(Path(rect), with: .color(Color(hue: c.hue, saturation: c.sat, brightness: c.bri)))
                }
            }
        }
        .blur(radius: 28)
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
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                topTrailingRadius: 32
            )
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    topTrailingRadius: 32
                )
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
                    set: { v in
                        dragTime = v
                        isDragging = true
                    }
                ),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing {
                    player.seek(to: dragTime)
                    isDragging = false
                }
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
            TrackButton(icon: "backward.end.fill", size: .medium) {
                playPrevious()
            }

            Spacer()

            SkipButton(seconds: -15, longPressSeconds: -30, player: player)

            Spacer()

            playPauseButton

            Spacer()

            SkipButton(seconds: 15, longPressSeconds: 30, player: player)

            Spacer()

            TrackButton(icon: "forward.end.fill", size: .medium) {
                playNext()
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
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
                    withAnimation(.spring(duration: 0.25)) {
                        player.setSpeed(speed)
                    }
                } label: {
                    Text(labelFor(speed))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if player.playbackSpeed == speed {
                                Capsule()
                                    .fill(.white.opacity(0.25))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                    }
                            } else {
                                Capsule()
                                    .fill(.white.opacity(0.06))
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
