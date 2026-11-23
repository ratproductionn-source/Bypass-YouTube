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

    var display: String {
        label.isEmpty ? "\(height)p" : label
    }
}

/// Everything the player needs for one video.
struct PlaybackInfo: Hashable {
    let videoId: String
    let title: String
    let author: String
    let duration: Int
    let hls: URL?
    let formats: [StreamFormat]

    var hasPlayable: Bool { hls != nil || !formats.isEmpty }
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
