import Foundation

/// Small recursive helpers. InnerTube responses bury everything four levels
/// deep behind renderer keys that Google renames every few months, so the
/// parser walks the tree instead of trusting one fixed path.
enum JSONX {

    static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
    static func array(_ any: Any?) -> [Any]? { any as? [Any] }
    static func string(_ any: Any?) -> String? { any as? String }
    static func number(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    /// Pulls text out of any of the shapes YouTube uses for a string field.
    static func text(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        guard let d = dict(any) else { return nil }
        if let s = d["simpleText"] as? String, !s.isEmpty { return s }
        if let s = d["content"] as? String, !s.isEmpty { return s }
        if let runs = array(d["runs"]) {
            let joined = runs
                .compactMap { dict($0).flatMap { $0["text"] as? String } }
                .joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// Path walk that refuses to crash on a missing branch.
    static func dig(_ root: Any?, _ path: String...) -> Any? {
        var node: Any? = root
        for key in path {
            guard let d = dict(node) else { return nil }
            node = d[key]
        }
        return node
    }

    static func url(_ any: Any?) -> URL? {
        guard var s = any as? String, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }

    /// Every dictionary sitting under `key`, at any depth, matched keys skipped.
    static func matches(key: String, in root: Any?) -> [[String: Any]] {
        guard let root else { return [] }
        var out: [[String: Any]] = []
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if let hit = d[key] as? [String: Any] {
                    out.append(hit)
                    return
                }
                for (k, v) in d where k != key { walk(v) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(root)
        return out
    }

    /// Largest thumbnail in a `thumbnail.thumbnails` block.
    static func bestThumb(_ any: Any?) -> URL? {
        guard let thumbs = array(any) else { return url(any) }
        var best: URL?
        var bestWidth = -1
        for t in thumbs {
            guard let u = url(dig(t, "url")) else { continue }
            let w = number(dig(t, "width")) ?? 0
            if w >= bestWidth { bestWidth = w; best = u }
        }
        return best
    }
}
