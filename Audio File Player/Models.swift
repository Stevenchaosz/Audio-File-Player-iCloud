import Foundation

struct AudioFile: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    var bookmarkData: Data?
    var duration: TimeInterval
    var dateAdded: Date
    var lastPlayedDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data? = nil,
        duration: TimeInterval = 0,
        dateAdded: Date = Date(),
        lastPlayedDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.duration = duration
        self.dateAdded = dateAdded
        self.lastPlayedDate = lastPlayedDate
    }

    // Backward-compat: old persisted data has no dateAdded / lastPlayedDate
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        lastPlayedDate = try c.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
    }

    var resolvedURL: URL? {
        guard let data = bookmarkData else {
            print("⚠️ No bookmark data for file: \(name)")
            return nil
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { print("⚠️ Bookmark is stale for file: \(name)") }
            return url
        } catch {
            print("⚠️ Failed to resolve bookmark for \(name): \(error.localizedDescription)")
            return nil
        }
    }

    var displayName: String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }

    var formattedDuration: String { formatTime(duration) }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
    return String(format: "%d:%02d", minutes, secs)
}
