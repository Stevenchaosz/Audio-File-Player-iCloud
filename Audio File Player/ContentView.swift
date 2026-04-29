import SwiftUI
import UniformTypeIdentifiers

enum LibrarySortField: String, CaseIterable {
    case name           = "Name"
    case dateLastOpened = "Date Last Opened"
    case dateAdded      = "Date Added"
    case duration       = "Duration"
}

enum LibraryViewStyle: String {
    case list, icons
}

struct ContentView: View {
    @Environment(AudioLibraryManager.self) private var library
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var showingPicker = false
    @State private var showingPlayer = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []

    @AppStorage("sortField") private var sortField: LibrarySortField = .name
    @AppStorage("sortAscending") private var sortAscending: Bool = true
    @AppStorage("viewStyle") private var viewStyle: LibraryViewStyle = .list

    private var sortedFiles: [AudioFile] {
        library.audioFiles.sorted { a, b in
            let aFirst: Bool
            switch sortField {
            case .name:
                aFirst = a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            case .dateLastOpened:
                aFirst = (a.lastPlayedDate ?? .distantPast) < (b.lastPlayedDate ?? .distantPast)
            case .dateAdded:
                aFirst = a.dateAdded < b.dateAdded
            case .duration:
                aFirst = a.duration < b.duration
            }
            return sortAscending ? aFirst : !aFirst
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if library.audioFiles.isEmpty {
                        emptyState
                    } else if viewStyle == .list {
                        fileList
                    } else {
                        iconGrid
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
            .navigationTitle(
                editMode == .active
                    ? (selectedIDs.isEmpty ? "Select Items" : "\(selectedIDs.count) Selected")
                    : "Library"
            )
            .toolbar { toolbarContent }
            .environment(\.editMode, $editMode)
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.audio, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            library.importURLs(urls)
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            PlayerView()
        }
        .onAppear {
            player.onLoad = { id in library.updateLastPlayed(id: id) }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editMode == .active {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    withAnimation { editMode = .inactive; selectedIDs.removeAll() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    library.remove(ids: Array(selectedIDs))
                    withAnimation { editMode = .inactive; selectedIDs.removeAll() }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedIDs.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ellipsisMenu
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Ellipsis Menu

    private var ellipsisMenu: some View {
        Menu {
            // Select
            Button {
                withAnimation { editMode = .active }
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }

            // View style toggle
            Button {
                withAnimation { viewStyle = viewStyle == .list ? .icons : .list }
            } label: {
                if viewStyle == .list {
                    Label("Icons", systemImage: "square.grid.2x2")
                } else {
                    Label("List", systemImage: "list.bullet")
                }
            }

            Divider()

            // Sort options
            ForEach(LibrarySortField.allCases, id: \.self) { field in
                Button {
                    if sortField == field {
                        sortAscending.toggle()
                    } else {
                        sortField = field
                        sortAscending = true
                    }
                } label: {
                    if sortField == field {
                        Label(field.rawValue, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(field.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .fontWeight(.semibold)
        }
    }

    // MARK: - List View

    private var fileList: some View {
        List(selection: $selectedIDs) {
            ForEach(sortedFiles) { file in
                let isCurrentTrack = player.currentFile?.id == file.id
                AudioFileRow(
                    file: file,
                    isCurrentTrack: isCurrentTrack,
                    isPlaying: isCurrentTrack && player.isPlaying
                )
                .tag(file.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard editMode != .active else { return }
                    if let index = library.audioFiles.firstIndex(where: { $0.id == file.id }) {
                        player.load(file: file, index: index)
                        showingPlayer = true
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { sortedFiles[$0].id }
                library.remove(ids: ids)
            }

            if player.currentFile != nil {
                Color.clear.frame(height: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Icon Grid View

    private var iconGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 16)],
                spacing: 20
            ) {
                ForEach(sortedFiles) { file in
                    let isCurrentTrack = player.currentFile?.id == file.id
                    AudioFileIcon(
                        file: file,
                        isCurrentTrack: isCurrentTrack,
                        isPlaying: isCurrentTrack && player.isPlaying,
                        isSelected: selectedIDs.contains(file.id)
                    )
                    .onTapGesture {
                        if editMode == .active {
                            if selectedIDs.contains(file.id) {
                                selectedIDs.remove(file.id)
                            } else {
                                selectedIDs.insert(file.id)
                            }
                        } else {
                            if let index = library.audioFiles.firstIndex(where: { $0.id == file.id }) {
                                player.load(file: file, index: index)
                                showingPlayer = true
                            }
                        }
                    }
                }

                if player.currentFile != nil {
                    Color.clear.frame(height: 80)
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

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

            Button {
                showingPicker = true
            } label: {
                Label("Import Files", systemImage: "folder.badge.plus")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - List Row

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

// MARK: - Icon Cell

struct AudioFileIcon: View {
    let file: AudioFile
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrentTrack ? Color.blue.gradient : Color.secondary.opacity(0.15).gradient)
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isCurrentTrack ? .white : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.blue)
                        .padding(6)
                }
            }

            Text(file.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(isCurrentTrack ? Color.blue : .primary)
        }
    }
}
