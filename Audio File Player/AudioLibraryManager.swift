
import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioLibraryManager {
    var audioFiles: [AudioFile] = []

    private let storageKey = "audioLibrary_v1"
    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "opus", "aiff", "caf", "m4b", "mp4", "m4r", "3gp"
    ]

    init() {
        loadFromStorage()
    }

    func importURLs(_ urls: [URL]) {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                importFolder(url)
            } else {
                addFile(url)
            }
        }
        saveToStorage()
    }

    private func importFolder(_ folderURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = contents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for fileURL in sorted {
            addFile(fileURL)
        }
    }

    private func addFile(_ url: URL) {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return }

        let name = url.lastPathComponent
        guard !audioFiles.contains(where: { $0.name == name }) else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let asset = AVURLAsset(url: url)
            
            Task { @MainActor in
                let duration: TimeInterval
                if let loadedDuration = try? await asset.load(.duration) {
                    let dur = CMTimeGetSeconds(loadedDuration)
                    duration = dur.isFinite ? dur : 0
                } else {
                    duration = 0
                }
                let file = AudioFile(name: name, bookmarkData: bookmark, duration: duration)
                audioFiles.append(file)
            }
        } catch {
            print("Bookmark error for \(name): \(error)")
        }
    }

    func remove(at offsets: IndexSet) {
        audioFiles.remove(atOffsets: offsets)
        saveToStorage()
    }

    func move(from source: IndexSet, to destination: Int) {
        audioFiles.move(fromOffsets: source, toOffset: destination)
        saveToStorage()
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(audioFiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromStorage() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let files = try? JSONDecoder().decode([AudioFile].self, from: data)
        else { return }
        audioFiles = files
    }
}
