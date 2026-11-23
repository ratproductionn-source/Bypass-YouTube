import Foundation

/// InnerTube clients. The order matters: IOS hands back an HLS manifest
/// (separate audio/video, no ad breaks), ANDROID_VR hands back direct
/// progressive MP4 URLs without needing a PO token, WEB_EMBEDDED is the
/// last resort when the first two get rate-limited.
enum Client: String, CaseIterable {
    case ios, androidVR, webEmbedded

    var label: String {
        switch self {
        case .ios: return "IOS"
        case .androidVR: return "ANDROID_VR"
        case .webEmbedded: return "WEB_EMBEDDED_PLAYER"
        }
    }

    var host: String { "https://www.youtube.com" }

    /// Public InnerTube keys shipped inside the stock clients.
    var key: String {
        switch self {
        case .ios:         return "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
        case .androidVR:   return "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w"
        case .webEmbedded: return "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        }
    }

    var userAgent: String {
        switch self {
        case .ios:
            return "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)"
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
        if self == .ios { h["X-YouTube-Client-Name"] = "5" }
        if self == .androidVR { h["X-YouTube-Client-Name"] = "28" }
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

    // MARK: browse + search

    static func search(_ query: String) async throws -> [Video] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": Client.androidVR.clientContext,
            "query": trimmed,
            "params": "EgIQAQ%3D%3D"   // videos only
        ]
        let root = try await post("search", body: body, client: .androidVR)
        return Parse.videos(from: root)
    }

    static func trending() async throws -> [Video] {
        var collected: [Video] = []
        for browseId in ["FEtrending", "FEwhat_to_watch"] {
            let body: [String: Any] = [
                "context": Client.androidVR.clientContext,
                "browseId": browseId
            ]
            guard let root = try? await post("browse", body: body, client: .androidVR) else { continue }
            let videos = Parse.videos(from: root)
            if !videos.isEmpty { collected = videos; break }
        }
        if collected.isEmpty { throw BenchError.payload("empty feed") }
        return collected
    }

    // MARK: playback

    /// Walks the client ladder until one of them returns something AVPlayer can eat.
    static func playback(videoId: String) async throws -> PlaybackInfo {
        var last: Error = BenchError.noStream
        for client in Client.allCases {
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
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]
        let root = try await post("player", body: body, client: client)

        let status = JSONX.dig(root, "playabilityStatus", "status") as? String ?? "UNKNOWN"
        if status != "OK" {
            let reason = JSONX.dig(root, "playabilityStatus", "reason") as? String
            throw BenchError.unplayable(reason ?? "status \(status)")
        }

        let details = JSONX.dict(root["videoDetails"])
        let title = (details?["title"] as? String) ?? ""
        let author = (details?["author"] as? String) ?? ""
        let duration = JSONX.number(details?["lengthSeconds"]) ?? 0

        let streaming = JSONX.dict(root["streamingData"])
        var hls: URL?
        if let s = streaming?["hlsManifestUrl"] as? String {
            hls = JSONX.url(s)
        }

        var formats: [StreamFormat] = []
        for raw in JSONX.array(streaming?["formats"]) ?? [] {
            guard let d = JSONX.dict(raw),
                  let itag = JSONX.number(d["itag"]),
                  let mime = d["mimeType"] as? String,
                  mime.hasPrefix("video/mp4"),
                  let u = JSONX.url(d["url"])
            else { continue }   // signatureCipher entries are skipped: no JS decipher on device
            let height = JSONX.number(d["height"]) ?? 0
            let label = (d["qualityLabel"] as? String) ?? "\(height)p"
            let bitrate = JSONX.number(d["bitrate"]) ?? 0
            formats.append(StreamFormat(id: itag, url: u, height: height,
                                        label: label, mime: mime, bitrate: bitrate))
        }
        formats.sort { $0.height > $1.height }

        return PlaybackInfo(videoId: videoId, title: title, author: author,
                            duration: duration, hls: hls, formats: formats)
    }

    /// Related videos for the "up next" strip. Failure is non-fatal everywhere.
    static func related(videoId: String) async throws -> [Video] {
        let body: [String: Any] = [
            "context": Client.androidVR.clientContext,
            "videoId": videoId,
            "autoplay": true
        ]
        let root = try await post("next", body: body, client: .androidVR)
        return Parse.videos(from: root)
    }
}
