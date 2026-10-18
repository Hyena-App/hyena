import Foundation

/// The latest Hyena release on GitHub, as the in-app updater sees it.
public struct AppRelease: Equatable, Sendable {
    public static let latestAPI = URL(string: "https://api.github.com/repos/Hyena-App/hyena/releases/latest")!

    public let version: String
    public let pageURL: URL
    public let dmgURL: URL?
    public let notes: String

    public init(version: String, pageURL: URL, dmgURL: URL?, notes: String) {
        self.version = version
        self.pageURL = pageURL
        self.dmgURL = dmgURL
        self.notes = notes
    }

    /// Reads GitHub's "latest release" JSON. Drafts and pre-releases are ignored.
    public static func parse(_ data: Data) -> AppRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              (json["draft"] as? Bool) != true, (json["prerelease"] as? Bool) != true,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        func asset(_ name: String) -> URL? {
            assets.first { ($0["name"] as? String) == name }
                .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        }
        // Prefer the versioned file; fall back to the stable name.
        let dmg = asset("Hyena-\(version).dmg") ?? asset("Hyena.dmg")
        return AppRelease(version: version, pageURL: page, dmgURL: dmg, notes: json["body"] as? String ?? "")
    }

    /// Numeric comparison of dotted versions; "1.0" equals "1.0.0" and suffixes are ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? version
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
