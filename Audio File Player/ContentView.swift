import SwiftUI

struct ContentView: View {
    @Environment(AudioLibraryManager.self) private var library
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var showingPicker = false
    @State private var showingPlayer = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if library.audioFiles.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                }

                if player.currentFile != nil {
                    MiniPlayerView(showingPlayer: $showingPlayer)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: player.currentFile?.id)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
                
                if !library.audioFiles.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPickerView { urls in
                library.importURLs(urls)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            PlayerView()
        }
    }

    private var fileList: some View {
        List {
            ForEach(Array(library.audioFiles.enumerated()), id: \.element.id) { index, file in
                AudioFileRow(
                    file: file,
                    isCurrentTrack: player.currentIndex == index,
                    isPlaying: player.currentIndex == index && player.isPlaying
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    player.load(file: file, index: index)
                    showingPlayer = true
                }
            }
            .onDelete { offsets in library.remove(at: offsets) }
            .onMove { source, dest in library.move(from: source, to: dest) }

            if player.currentFile != nil {
                Color.clear.frame(height: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.music.mic")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Audio Files")
                .font(.title2.weight(.semibold))
            Text("Tap **+** to import files or folders\nfrom iCloud Drive")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            VStack(spacing: 12) {
                // Use the normal file picker
                Button {
                    showingPicker = true
                } label: {
                    Label("Import Files (Recommended)", systemImage: "folder.badge.plus")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Text("Or copy this command to Terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                Text("xcrun simctl addmedia booted ~/Downloads/edito_b1_livre_de_leleve_audio/*.mp3")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AudioFileRow: View {
    let file: AudioFile
    let isCurrentTrack: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrentTrack ? Color.blue.gradient : Color.secondary.opacity(0.15).gradient)
                    .frame(width: 48, height: 48)
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isCurrentTrack ? .white : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isCurrentTrack ? Color.blue : .primary)
                Text(file.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.blue)
            }
        }
        .padding(.vertical, 2)
    }
}
