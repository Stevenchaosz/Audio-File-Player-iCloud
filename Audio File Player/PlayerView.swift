import SwiftUI
import UIKit

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(AudioLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var transcriptionManager = SpeechTranscriptionManager()

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var artworkScale: CGFloat = 1.0
    @State private var showingTranscript = false

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
        .onAppear {
            player.onTrackEnd = { playNext() }
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
            // Clear transcript when track changes
            transcriptionManager.clearTranscript()
            showingTranscript = false
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

            // Transcript button (like Apple Music lyrics button)
            Button {
                showingTranscript.toggle()
            } label: {
                Image(systemName: showingTranscript ? "text.quote.rtl" : "text.quote")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
        }
    }

    private var speedBadge: String {
        switch player.playbackSpeed {
        case 0.25: return "0.25×"
        case 0.5:  return "0.5×"
        case 1.0:  return "1×"
        case 1.5:  return "1.5×"
        case 2.0:  return "2×"
        default:   return String(format: "%.2f×", player.playbackSpeed)
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
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .overlay {
                    ScrollView {
                        VStack(spacing: 16) {
                            if transcriptionManager.transcript.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: transcriptionManager.isTranscribing ? "waveform" : "text.quote")
                                        .font(.system(size: 48, weight: .light))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .symbolEffect(.variableColor.iterative.reversing, isActive: transcriptionManager.isTranscribing)
                                    
                                    if transcriptionManager.isTranscribing {
                                        Text("Transcribing...")
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    } else if transcriptionManager.authorizationStatus != .authorized {
                                        Text("Speech Recognition Access Required")
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.8))
                                        Text("Tap the button below to enable")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    } else {
                                        Text("No Transcript Yet")
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.8))
                                        Text("Tap the button below to transcribe")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                            } else {
                                Text(transcriptionManager.transcript)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            
            // Transcribe button
            if !transcriptionManager.isTranscribing && transcriptionManager.transcript.isEmpty {
                Button {
                    if let file = player.currentFile {
                        Task {
                            await transcriptionManager.transcribe(audioFile: file)
                        }
                    }
                } label: {
                    Label(transcriptionManager.authorizationStatus == .authorized ? "Generate Transcript" : "Enable Speech Recognition",
                          systemImage: "waveform.and.mic")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 32)
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            // Track info
            trackInfo
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)

            // Scrubber
            scrubber
                .padding(.horizontal, 28)
                .padding(.bottom, 28)

            // Transport controls
            transportControls
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            // Speed selector
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
            // Previous
            TrackButton(icon: "backward.end.fill", size: .medium) {
                playPrevious()
            }

            Spacer()

            // -15s / long-press -30s
            SkipButton(seconds: -15, longPressSeconds: -30, player: player)

            Spacer()

            // Play / Pause
            playPauseButton

            Spacer()

            // +15s / long-press +30s
            SkipButton(seconds: 15, longPressSeconds: 30, player: player)

            Spacer()

            // Next
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
