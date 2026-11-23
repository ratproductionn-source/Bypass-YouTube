import Foundation

/// Turns an InnerTube response into rows. Handles both the legacy
/// `videoRenderer` shape and the newer `lockupViewModel` shape, because
/// which one comes back depends on which client answered.
enum Parse {

    static func videos(from root: Any?) -> [Video] {
        var out: [Video] = []
        var seen = Set<String>()

        for r in JSONX.matches(key: "videoRenderer", in: root) {
            guard let id = r["videoId"] as? String, seen.insert(id).inserted else { continue }
            let title = JSONX.text(r["title"]) ?? "untitled"
            let channel = JSONX.text(JSONX.dig(r, "ownerText"))
                ?? JSONX.text(JSONX.dig(r, "longBylineText"))
                ?? JSONX.text(JSONX.dig(r, "shortBylineText"))
                ?? ""
            let duration = JSONX.text(r["lengthText"]) ?? ""
            let views = JSONX.text(r["viewCountText"]) ?? ""
            let published = JSONX.text(r["publishedTimeText"]) ?? ""
            let meta = [views, published].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(Video(id: id, title: title, channel: channel,
                             thumbnail: JSONX.bestThumb(r["thumbnail"]),
                             duration: duration, meta: meta))
        }

        for l in JSONX.matches(key: "lockupViewModel", in: root) {
            guard let id = l["contentId"] as? String, seen.insert(id).inserted else { continue }
            if let type = l["contentType"] as? String, !type.hasSuffix("VIDEO") { continue }

            let meta = JSONX.dig(l, "metadata", "lockupMetadataViewModel")
            let title = JSONX.text(JSONX.dig(meta, "title")) ?? "untitled"

            var channel = ""
            var views = ""
            if let rows = JSONX.array(JSONX.dig(meta, "metadata", "contentMetadataViewModel", "metadataRows")) {
                for (index, row) in rows.enumerated() {
                    let parts = (JSONX.array(JSONX.dig(row, "metadataParts")) ?? [])
                        .compactMap { JSONX.text(JSONX.dig($0, "text")) }
                    let joined = parts.joined(separator: " · ")
                    if index == 0, channel.isEmpty { channel = joined }
                    else if views.isEmpty { views = joined }
                }
            }

            var thumb: URL?
            if let sources = JSONX.array(JSONX.dig(l, "contentImage", "thumbnailViewModel", "image", "sources")) {
                for s in sources {
                    if let u = JSONX.url(JSONX.dig(s, "url")) { thumb = u }
                }
            }
            if thumb == nil {
                thumb = JSONX.bestThumb(JSONX.dig(l, "contentImage", "thumbnailViewModel", "thumbnail", "thumbnails"))
            }

            out.append(Video(id: id, title: title, channel: channel,
                             thumbnail: thumb, duration: "", meta: views))
        }

        return out
    }
}
