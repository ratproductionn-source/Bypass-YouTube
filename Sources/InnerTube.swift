import Foundation

/// InnerTube clients. Playback walks `playbackLadder` only — the plain
/// ANDROID client needs a PO token for media, so it is used for `next`
/// (comments, related) but never for stream resolution.
enum Client: String, CaseIterable {
    case ios, android, androidVR, webEmbedded

    static let playbackLadder: [Client] = [.ios, .androidVR, .webEmbedded]

    var label: String {
        switch self {
        case .ios:         return "IOS"
        case .android:     return "ANDROID"
        case .androidVR:   return "ANDROID_VR"
        case .webEmbedded: return "WEB_EMBEDDED_PLAYER"
        }
    }

    var host: String { "https://www.youtube.com" }

    /// Public InnerTube keys shipped inside the stock clients.
    var key: String {
        switch self {
        case .ios:         return "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
        case .android:     return "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w"
        case .androidVR:   return "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w"
        case .webEmbedded: return "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        }
    }

    var userAgent: String {
        switch self {
        case .ios:
            return "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)"
        case .android:
            return "com.google.android.youtube/19.44.38 (Linux; U; Android 11) gzip"
        case .androidVR:
            return "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
        case .webEmbedded:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        }
    }

    var clientContext: [String: Any] {
        var client: [String: Any] = ["hl": "en", "gl": "US", "utcOffsetMinutes": 0]
        client["clientName"] = label
        switch self {
        case .ios:
            client["clientVersion"] = "19.45.4"
            client["deviceMake"] = "Apple"
            client["deviceModel"] = "iPhone16,2"
            client["osName"] = "iPhone"
            client["osVersion"] = "18.1.0.22B83"
        case .android:
            client["clientVersion"] = "19.44.38"
            client["androidSdkVersion"] = 30
            client["osName"] = "Android"
            client["osVersion"] = "11"
        case .androidVR:
            client["clientVersion"] = "1.60.19"
            client["deviceMake"] = "Oculus"
            client["deviceModel"] = "Quest 3"
            client["androidSdkVersion"] = 32
            client["osName"] = "Android"
            client["osVersion"] = "12L"
        case .webEmbedded:
            client["clientVersion"] = "1.20241120.01.00"
            client["clientScreen"] = "EMBED"
        }
        return ["client": client]
    }

    var headers: [String: String] {
        var h: [String: String] = [
            "Content-Type": "application/json",
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
            "X-Goog-Api-Format-Version": "2",
            "Origin": host
        ]
        switch self {
        case .ios: h["X-YouTube-Client-Name"] = "5"
        case .android: h["X-YouTube-Client-Name"] = "3"
        case .androidVR: h["X-YouTube-Client-Name"] = "28"
        case .webEmbedded: h["X-YouTube-Client-Name"] = "56"
        }
        return h
    }
}

enum InnerTube {

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]
        return URLSession(configuration: cfg)
    }()

    // MARK: transport

    private static func post(_ endpoint: String, body: [String: Any], client: Client) async throws -> [String: Any] {
        guard let url = URL(string: "\(client.host)/youtubei/v1/\(endpoint)?key=\(client.key)&prettyPrint=false") else {
            throw BenchError.transport("bad url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in client.headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BenchError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BenchError.http(http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BenchError.payload("root is not an object")
        }
        return root
    }

    // MARK: search + browse

    static func search(_ query: String) async throws -> [Video] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": Client.androidVR.clientContext,
            "query": trimmed,
            "params": "EgIQAQ%3D%3D"      // videos only
        ]
        let root = try await post("search", body: body, client: .androidVR)
        return Parse.videos(from: root)
    }

    static func trending() async throws -> [Video] {
        for browseId in ["FEtrending", "FEwhat_to_watch"] {
            let body: [String: Any] = [
                "context": Client.androidVR.clientContext,
                "browseId": browseId
            ]
            guard let root = try? await post("browse", body: body, client: .androidVR) else { continue }
            let videos = Parse.videos(from: root)
            if !videos.isEmpty { return videos }
        }
        throw BenchError.payload("empty feed")
    }

    /// Channel page: header + first page of uploads.
    static func channel(_ channelId: String) async throws -> (ChannelInfo, [Video]) {
        let body: [String: Any] = [
            "context": Client.android.clientContext,
            "browseId": channelId,
            "params": "EgZ2aWRlb3PyBgQKAjoA"     // videos tab
        ]
        let root = try await post("browse", body: body, client: .android)
        return (Parse.channel(from: root, fallbackId: channelId), Parse.videos(from: root))
    }

    // MARK: playback

    /// Walks the ladder until one client returns something AVPlayer can eat.
    static func playback(videoId: String) async throws -> PlaybackInfo {
        var last: Error = BenchError.noStream
        for client in Client.playbackLadder {
            do {
                let info = try await playback(videoId: videoId, client: client)
                if info.hasPlayable { return info }
                last = BenchError.noStream
            } catch {
                last = error
            }
        }
        throw last
    }

    static func playback(videoId: String, client: Client) async throws -> PlaybackInfo {
        let body: [String: Any] = [
            "context": client.clientContext,
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]
            ]
        ]
        let root = try await post("player", body: body, client: client)

        let status = JSONX.dig(root, "playabilityStatus", "status") as? String ?? "UNKNOWN"
        if status != "OK" {
            let reason = JSONX.dig(root, "playabilityStatus", "reason") as? String
            throw BenchError.unplayable(reason ?? "status \(status)")
        }

        let details = JSONX.dict(root["videoDetails"])
        let micro = JSONX.dig(root, "microformat", "playerMicroformatRenderer")
        let streaming = JSONX.dict(root["streamingData"])

        var hls: URL?
        if let s = streaming?["hlsManifestUrl"] as? String { hls = JSONX.url(s) }

        var formats: [StreamFormat] = []
        for raw in JSONX.array(streaming?["formats"]) ?? [] {
            guard let d = JSONX.dict(raw),
                  let itag = JSONX.number(d["itag"]),
                  let mime = d["mimeType"] as? String,
                  mime.hasPrefix("video/mp4"),
                  let u = JSONX.url(d["url"])          // signatureCipher entries dropped: no JS decipher
            else { continue }
            let height = JSONX.number(d["height"]) ?? 0
            formats.append(StreamFormat(
                id: itag,
                url: u,
                height: height,
                label: (d["qualityLabel"] as? String) ?? "\(height)p",
                mime: mime,
                bitrate: JSONX.number(d["bitrate"]) ?? 0
            ))
        }
        formats.sort { $0.height > $1.height }

        return PlaybackInfo(
            videoId: videoId,
            title: (details?["title"] as? String) ?? "",
            author: (details?["author"] as? String) ?? "",
            channelId: (details?["channelId"] as? String) ?? "",
            description: (details?["shortDescription"] as? String) ?? "",
            viewCount: JSONX.number(details?["viewCount"]) ?? 0,
            published: (micro.flatMap { JSONX.dig($0, "publishDate") as? String }) ?? "",
            duration: JSONX.number(details?["lengthSeconds"]) ?? 0,
            isLive: (details?["isLiveContent"] as? Bool) ?? false,
            hls: hls,
            formats: formats
        )
    }

    // MARK: next (related + comments)

    static func related(videoId: String) async throws -> [Video] {
        let body: [String: Any] = [
            "context": Client.androidVR.clientContext,
            "videoId": videoId,
            "autoplay": true
        ]
        let root = try await post("next", body: body, client: .androidVR)
        return Parse.videos(from: root)
    }

    /// First page of comments plus the token for the next page.
    static func comments(videoId: String) async throws -> (comments: [Comment], token: String?) {
        let body: [String: Any] = [
            "context": Client.android.clientContext,
            "videoId": videoId
        ]
        let root = try await post("next", body: body, client: .android)
        let token = Parse.commentContinuation(in: root)
        return (Parse.comments(from: root), token)
    }

    static func comments(continuation: String) async throws -> (comments: [Comment], token: String?) {
        let body: [String: Any] = [
            "context": Client.android.clientContext,
            "continuation": continuation
        ]
        let root = try await post("next", body: body, client: .android)
        return (Parse.comments(from: root), Parse.commentContinuation(in: root))
    }

    // MARK: search suggestions

    static func suggest(_ query: String) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=en&q=\(encoded)")
        else { return [] }

        var request = URLRequest(url: url)
        request.setValue(Client.webEmbedded.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              array.count > 1,
              let items = array[1] as? [Any]
        else { return [] }
        return items.compactMap { $0 as? String }
    }
}
