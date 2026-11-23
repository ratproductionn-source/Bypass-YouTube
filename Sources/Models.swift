import Foundation

/// One row in a feed or a search result.
struct Video: Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    let thumbnail: URL?
    let duration: String
    let meta: String
}

/// A progressive (muxed audio+video) rendition straight off InnerTube.
struct StreamFormat: Identifiable, Hashable {
    let id: Int          // itag
    let url: URL
    let height: Int
    let label: String
    let mime: String
    let bitrate: Int

    var display: String { label.isEmpty ? "\(height)p" : label }
}

/// Everything the player and the watch screen need for one video.
struct PlaybackInfo: Hashable {
    let videoId: String
    let title: String
    let author: String
    let channelId: String
    let description: String
    let viewCount: Int
    let published: String
    let duration: Int
    let isLive: Bool
    let hls: URL?
    let formats: [StreamFormat]

    var hasPlayable: Bool { hls != nil || !formats.isEmpty }

    var viewsText: String {
        guard viewCount > 0 else { return "" }
        if viewCount >= 1_000_000_000 { return String(format: "%.1fB views", Double(viewCount) / 1_000_000_000) }
        if viewCount >= 1_000_000 { return String(format: "%.1fM views", Double(viewCount) / 1_000_000) }
        if viewCount >= 1_000 { return String(format: "%.1fK views", Double(viewCount) / 1_000) }
        return "\(viewCount) views"
    }
}

enum BenchError: LocalizedError {
    case transport(String)
    case http(Int)
    case payload(String)
    case unplayable(String)
    case noStream

    var errorDescription: String? {
        switch self {
        case .transport(let m):  return "network: \(m)"
        case .http(let code):    return "http \(code)"
        case .payload(let m):    return "bad payload: \(m)"
        case .unplayable(let m): return m.isEmpty ? "video not playable" : m
        case .noStream:          return "no playable stream for this video"
        }
    }
}
