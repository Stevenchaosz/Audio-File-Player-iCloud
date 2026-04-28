import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Binding var showingPlayer: Bool

    var body: some View {
        Button {
            showingPlayer = true
        } label: {
            HStack(spacing: 12) {
                artworkThumbnail

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentFile?.displayName ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(formatTime(player.currentTime) + " / " + (player.currentFile?.formattedDuration ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }

                    Button {
                        player.skip(15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: geo.size.width * progress, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var artworkThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.gradient)
                .frame(width: 42, height: 42)
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
        }
    }
}
