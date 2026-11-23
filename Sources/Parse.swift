import Foundation

struct ChannelInfo: Hashable {
    let id: String
    let title: String
    let subtitle: String
    let avatar: URL?
}

struct Comment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let likes: String
    let published: String
    let replies: String
}

/// Turns an InnerTube response into rows. Handles every shape Google currently
/// ships: legacy `videoRenderer`/`gridVideoRenderer`, the newer
/// `lockupViewModel`, and both comment formats.
enum Parse {

    // MARK: video lists

    static func videos(from root: Any?) -> [Video] {
        var out: [Video] = []
        var seen = Set<String>()

        for r in JSONX.matches(key: "videoRenderer", in: root) {
            guard let id = r["videoId"] as? String, seen.insert(id).inserted else { continue }
            let channel = JSONX.text(JSONX.dig(r, "ownerText"))
                ?? JSONX.text(JSONX.dig(r, "longBylineText"))
                ?? JSONX.text(JSONX.dig(r, "shortBylineText"))
                ?? ""
            let meta = [JSONX.text(r["viewCountText"]) ?? "",
                        JSONX.text(r["publishedTimeText"]) ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            out.append(Video(id: id,
                             title: JSONX.text(r["title"]) ?? "untitled",
                             channel: channel,
                             thumbnail: JSONX.bestThumb(r["thumbnail"]),
                             duration: JSONX.text(r["lengthText"]) ?? "",
                             meta: meta))
        }

        for r in JSONX.matches(key: "gridVideoRenderer", in: root) {
            guard let id = r["videoId"] as? String, seen.insert(id).inserted else { continue }
            var duration = ""
            for overlay in JSONX.array(JSONX.dig(r, "thumbnailOverlays")) ?? [] {
                if let t = JSONX.text(JSONX.dig(overlay, "thumbnailOverlayTimeStatusRenderer", "text")) {
                    duration = t
                }
            }
            out.append(Video(id: id,
                             title: JSONX.text(r["title"]) ?? "untitled",
                             channel: "",
                             thumbnail: JSONX.bestThumb(r["thumbnail"]),
                             duration: duration,
                             meta: JSONX.text(r["viewCountText"]) ?? ""))
        }

        for l in JSONX.matches(key: "lockupViewModel", in: root) {
            guard let id = l["contentId"] as? String, seen.insert(id).inserted else { continue }
            if let type = l["contentType"] as? String, !type.hasSuffix("VIDEO") { continue }

            let meta = JSONX.dig(l, "metadata", "lockupMetadataViewModel")
            var channel = ""
            var views = ""
            for (index, row) in (JSONX.array(JSONX.dig(meta, "metadata", "contentMetadataViewModel", "metadataRows")) ?? []).enumerated() {
                let parts = (JSONX.array(JSONX.dig(row, "metadataParts")) ?? [])
                    .compactMap { JSONX.text(JSONX.dig($0, "text")) }
                let joined = parts.joined(separator: " · ")
                if index == 0, channel.isEmpty { channel = joined }
                else if views.isEmpty { views = joined }
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

            out.append(Video(id: id,
                             title: JSONX.text(JSONX.dig(meta, "title")) ?? "untitled",
                             channel: channel,
                             thumbnail: thumb,
                             duration: "",
                             meta: views))
        }

        return out
    }

    // MARK: channel header

    static func channel(from root: Any?, fallbackId: String) -> ChannelInfo {
        let metaRenderer = JSONX.dict(JSONX.dig(root, "metadata", "channelMetadataRenderer"))
        let title = (metaRenderer?["title"] as? String)
            ?? JSONX.text(JSONX.dig(root, "header", "pageHeaderViewModel", "title", "dynamicTextViewModel", "text"))
            ?? "channel"

        var subtitle = ""
        if let rows = JSONX.array(JSONX.dig(root, "header", "pageHeaderViewModel", "metadata", "contentMetadataViewModel", "metadataRows")) {
            for row in rows {
                let parts = (JSONX.array(JSONX.dig(row, "metadataParts")) ?? [])
                    .compactMap { JSONX.text(JSONX.dig($0, "text")) }
                if !parts.isEmpty { subtitle = parts.joined(separator: " · "); break }
            }
        }
        if subtitle.isEmpty {
            subtitle = JSONX.text(JSONX.dig(root, "header", "c4TabbedHeaderRenderer", "subscriberCountText")) ?? ""
        }

        var avatar: URL?
        if let sources = JSONX.array(JSONX.dig(root, "header", "pageHeaderViewModel", "image", "contentPreviewImageViewModel", "image", "sources")) {
            for s in sources { if let u = JSONX.url(JSONX.dig(s, "url")) { avatar = u } }
        }
        if avatar == nil {
            avatar = JSONX.bestThumb(JSONX.dig(root, "metadata", "channelMetadataRenderer", "avatar", "thumbnails"))
        }

        let id = (metaRenderer?["externalId"] as? String) ?? fallbackId
        return ChannelInfo(id: id, title: title, subtitle: subtitle, avatar: avatar)
    }

    // MARK: comments

    static func comments(from root: Any?) -> [Comment] {
        var out: [Comment] = []
        var seen = Set<String>()

        // modern shape: entity payloads sitting in frameworkUpdates
        for p in JSONX.matches(key: "commentEntityPayload", in: root) {
            let props = JSONX.dict(p["properties"])
            let id = (props?["commentId"] as? String) ?? UUID().uuidString
            guard seen.insert(id).inserted else { continue }
            let text = (JSONX.dig(props, "content", "content") as? String) ?? ""
            guard !text.isEmpty else { continue }
            out.append(Comment(
                id: id,
                author: (JSONX.dig(p, "author", "displayName") as? String) ?? "",
                text: text,
                likes: (JSONX.dig(p, "toolbar", "likeCountNotliked") as? String)
                    ?? (JSONX.dig(p, "toolbar", "likeCountLiked") as? String) ?? "",
                published: (props?["publishedTime"] as? String) ?? "",
                replies: (JSONX.dig(p, "toolbar", "replyCount") as? String) ?? ""
            ))
        }

        // legacy shape
        for r in JSONX.matches(key: "commentRenderer", in: root) {
            let id = (r["commentId"] as? String) ?? UUID().uuidString
            guard seen.insert(id).inserted else { continue }
            let text = JSONX.text(r["contentText"]) ?? ""
            guard !text.isEmpty else { continue }
            out.append(Comment(
                id: id,
                author: JSONX.text(r["authorText"]) ?? "",
                text: text,
                likes: JSONX.text(r["voteCount"]) ?? "",
                published: JSONX.text(r["publishedTimeText"]) ?? "",
                replies: JSONX.text(JSONX.dig(r, "replies", "replyCount")) ?? ""
            ))
        }

        return out
    }

    static func commentContinuation(in root: Any?) -> String? {
        // prefer the token inside the comments section, not the related-videos one
        for section in JSONX.matches(key: "itemSectionRenderer", in: root) {
            let ident = section["sectionIdentifier"] as? String ?? ""
            guard ident.contains("comment") else { continue }
            if let t = token(in: section) { return t }
        }
        return token(in: root)
    }

    private static func token(in node: Any?) -> String? {
        for c in JSONX.matches(key: "continuationItemRenderer", in: node) {
            if let t = JSONX.string(JSONX.dig(c, "continuationEndpoint", "continuationCommand", "token")) {
                return t
            }
            if let t = JSONX.string(JSONX.dig(c, "button", "buttonRenderer", "command", "continuationCommand", "token")) {
                return t
            }
        }
        return nil
    }
}
