import Foundation

/// Local watch history with resume positions. Nothing leaves the device —
/// this is the only persistence in the app.
struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var channel: String
    var thumbnail: String?
    var seconds: Double
    var duration: Int
    var updated: Date

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / Double(duration), 0), 1)
    }
}

final class History: ObservableObject {
    static let shared = History()

    @Published private(set) var entries: [HistoryEntry] = []

    private let limit = 300
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    func record(video: Video, info: PlaybackInfo?, seconds: Double) {
        guard seconds > 3 else { return }

        var entry = entries.first(where: { $0.id == video.id }) ?? HistoryEntry(
            id: video.id,
            title: video.title,
            channel: video.channel,
            thumbnail: video.thumbnail?.absoluteString,
            seconds: 0,
            duration: info?.duration ?? 0,
            updated: Date()
        )
        entry.seconds = seconds
        entry.updated = Date()
        if let info {
            if !info.title.isEmpty { entry.title = info.title }
            if !info.author.isEmpty { entry.channel = info.author }
            if info.duration > 0 { entry.duration = info.duration }
        }

        // finished videos stay as a resume point only if there is real time left
        if entry.duration > 0, entry.seconds > Double(entry.duration) - 15 {
            entries.removeAll { $0.id == video.id }
        } else {
            entries.removeAll { $0.id == video.id }
            entries.insert(entry, at: 0)
        }

        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func resumePoint(for id: String) -> Double? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        guard entry.seconds > 5 else { return nil }
        if entry.duration > 0, entry.seconds > Double(entry.duration) - 15 { return nil }
        return entry.seconds
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
