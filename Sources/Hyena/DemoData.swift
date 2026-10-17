import Foundation
import HyenaCore

/// Sample data for `Hyena --demo`, used for screenshots and the website.
/// Demo mode never reads, writes or deletes the user's files and keeps its
/// own preferences.
enum DemoData {
    static let isActive = CommandLine.arguments.contains("--demo")
    /// Passed as one token (`--demo-screen=tree`): a separate bare word would be
    /// treated as a document to open, and AppKit then skips the default window.
    static var screen: String? {
        CommandLine.arguments.first { $0.hasPrefix("--demo-screen=") }.map { String($0.dropFirst("--demo-screen=".count)) }
    }

    static let capacity: Int64 = 994_660_000_000
    static let available: Int64 = 61_400_000_000

    private static let home = NSHomeDirectory()
    private static let gb: Int64 = 1_000_000_000
    private static let mb: Int64 = 1_000_000

    private static func days(_ count: Double) -> Date { Date().addingTimeInterval(-count * 86_400) }

    private static func item(
        _ path: String, _ category: CleanupCategory, _ bytes: Int64, title: String? = nil, kind: ArtifactKind? = nil,
        age: Double = 3, recommended: Bool = true, note: String? = nil, bundleID: String? = nil,
        action: CleanupAction = .moveToTrash
    ) -> Finding {
        let url = URL(fileURLWithPath: path.hasPrefix("/") ? path : home + "/" + path)
        return Finding(
            url: url, root: url.deletingLastPathComponent(), category: category, kind: kind, title: title,
            bytes: bytes, modified: days(age), inode: 1, device: 1, recommended: recommended, note: note,
            bundleID: bundleID, action: action
        )
    }

    static var findings: [Finding] {
        [
            // Everyday
            item("Library/Caches/com.google.Chrome", .userCaches, 2_140 * mb, title: "Chrome", bundleID: "com.google.Chrome"),
            item("Library/Caches/com.spotify.client", .userCaches, 1_420 * mb, title: "Spotify", bundleID: "com.spotify.client"),
            item("Library/Caches/com.tinyspeck.slackmacgap", .userCaches, 880 * mb, title: "Slack",
                 recommended: false, note: "Open now. Quit the app before cleaning.", bundleID: "com.tinyspeck.slackmacgap"),
            item("Library/Caches/com.figma.Desktop", .userCaches, 640 * mb, title: "Figma", bundleID: "com.figma.Desktop"),
            item("Library/Caches/JetBrains", .userCaches, 1_300 * mb, title: "JetBrains"),
            item("Library/Logs/DiagnosticReports", .logs, 214 * mb, title: "DiagnosticReports"),
            item("Library/Logs/CoreSimulator", .logs, 172 * mb, title: "CoreSimulator"),
            item("Library/Application Support/Code/CachedData", .appSupportCaches, 2_380 * mb,
                 title: "Code · CachedData", bundleID: "com.microsoft.VSCode"),
            item("Library/Application Support/discord/Cache", .appSupportCaches, 1_150 * mb, title: "discord · Cache"),
            item("Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage", .appSupportCaches,
                 2_590 * mb, title: "Google · Chrome/Default/Service Worker/CacheStorage", bundleID: "com.google.Chrome"),
            item("Library/Application Support/Sketch", .appLeftovers, 3_210 * mb, title: "Sketch", recommended: false,
                 note: "No matching app found. Make sure it isn’t data you still need."),
            item("Downloads/Xcode_26.1.xip", .downloads, 4_820 * mb, age: 41, note: "Installer. Whatever it installed stays."),
            item("Downloads/Docker.dmg", .downloads, 610 * mb, age: 63, note: "Installer. Whatever it installed stays."),
            item("Downloads/Figma.dmg", .downloads, 238 * mb, age: 120, note: "Installer. Whatever it installed stays."),
            item("Downloads/conference-talk-recording.mov", .downloads, 3_900 * mb, age: 210, recommended: false,
                 note: "Untouched for 7 months. Make sure you don’t need it."),
            item("Library/Application Support/MobileSync/Backup/00008110-001A", .devices, 38_400 * mb,
                 title: "Alex’s iPhone · backed up Mar 2, 2025", age: 590, recommended: false,
                 note: "Over a year old. Keep it only if it’s your only copy."),
            item("Library/iTunes/iPhone Software Updates/iPhone15,2_18.6_Restore.ipsw", .devices, 7_900 * mb,
                 title: "iPhone15,2_18.6_Restore (iOS update file)", age: 300,
                 note: "Downloaded once to update a device. Not needed afterwards."),
            item(".Trash/old-screen-recordings", .trash, 1_740 * mb, title: "old-screen-recordings", action: .deletePermanently),
            item("/", .snapshots, 0, title: "Time Machine · Oct 16, 2026 at 9:14 PM", age: 1,
                 note: "macOS also removes these on its own when space runs low.", action: .deleteSnapshot("2026-10-16-211400")),
            // Developer
            item("Library/Developer/Xcode/DerivedData/Hyena-bxqyrhtfmzcbel", .xcode, 3_120 * mb,
                 title: "DerivedData · Hyena", bundleID: "com.apple.dt.Xcode"),
            item("Library/Developer/Xcode/DerivedData/AcmeMobile-gkzpuvfwbaqcvh", .xcode, 1_940 * mb,
                 title: "DerivedData · AcmeMobile", bundleID: "com.apple.dt.Xcode"),
            item("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5 (21F79)", .xcode, 4_210 * mb,
                 title: "iOS device support · 17.5", age: 400,
                 note: "Re-created when you connect a device on this version.", bundleID: "com.apple.dt.Xcode"),
            item("Library/Developer/CoreSimulator/Devices/7F2A", .simulators, 6_350 * mb, title: "iPhone 15 Pro · iOS 17.5",
                 age: 300, note: "Its iOS runtime is no longer installed, so it can’t run.", bundleID: "com.apple.iphonesimulator"),
            item("Library/Developer/CoreSimulator/Devices/91C0", .simulators, 4_190 * mb, title: "iPhone 17 Pro · iOS 26.2",
                 age: 2, recommended: false, note: "Erases this simulator’s apps and data.", bundleID: "com.apple.iphonesimulator"),
            item("Library/Developer/CoreSimulator/Caches", .simulators, 1_080 * mb, title: "Simulator caches",
                 bundleID: "com.apple.iphonesimulator"),
            item(".npm/_cacache", .packageCaches, 9_860 * mb, title: "npm"),
            item(".cargo/registry/cache", .packageCaches, 2_310 * mb, title: "Cargo registry downloads"),
            item(".gradle/caches", .packageCaches, 3_420 * mb, title: "Gradle"),
            item("Library/Caches/Homebrew", .packageCaches, 1_260 * mb, title: "Homebrew downloads"),
            item("Library/Caches/pip", .packageCaches, 420 * mb, title: "pip"),
            // Projects
            item("Developer/acme-web/node_modules", .projects, 1_870 * mb, kind: .node, age: 12),
            item("Developer/acme-api/target", .projects, 4_240 * mb, kind: .rust, age: 96),
            item("Developer/old-game/target", .projects, 2_610 * mb, kind: .rust, age: 180),
            item("Developer/landing/.next", .projects, 340 * mb, kind: .web, age: 75),
            item("Developer/ml-playground/.venv", .projects, 1_120 * mb, kind: .pythonEnv, age: 140, recommended: false),
            item("Developer/AcmeMobile/Pods", .projects, 780 * mb, kind: .cocoapods, age: 30, recommended: false),
        ]
    }

    /// One week ago: npm and the simulators were smaller, so "what grew" has a story.
    static var baseline: ScanSnapshot {
        let older = findings.map { finding -> Finding in
            let shrink: Int64 = finding.title == "npm" ? 3_100 * mb : 0
            return Finding(
                url: finding.url, root: finding.root, category: finding.category, kind: finding.kind,
                title: finding.title, bytes: max(0, finding.bytes - shrink), modified: finding.modified,
                inode: 1, device: 1, recommended: finding.recommended, note: finding.note,
                bundleID: finding.bundleID, action: finding.action
            )
        }
        return ScanSnapshot(date: days(7), findings: older)
    }

    /// Contents shown when a demo item is expanded.
    static func children(of path: String) -> [FileEntry] {
        let entries: [(String, Int64, Bool)]
        switch (path as NSString).lastPathComponent {
        case "node_modules":
            entries = [("next", 412 * mb, true), ("@swc", 318 * mb, true), ("typescript", 92 * mb, true),
                       ("esbuild", 74 * mb, true), ("@babel", 61 * mb, true), ("react-dom", 18 * mb, true),
                       (".cache", 640 * mb, true), ("prisma", 255 * mb, true)]
        case ".cache":
            entries = [("next", 402 * mb, true), ("babel-loader", 238 * mb, true)]
        case "target":
            entries = [("debug", 2_980 * mb, true), ("release", 1_120 * mb, true), ("doc", 140 * mb, true)]
        case "debug":
            entries = [("deps", 1_910 * mb, true), ("build", 640 * mb, true), ("incremental", 430 * mb, true)]
        default:
            entries = [("Cache_Data", 1_100 * mb, true), ("index", 12 * mb, false), ("Code Cache", 320 * mb, true)]
        }
        return entries.sorted { $0.1 > $1.1 }.map { name, bytes, isDirectory in
            FileEntry(url: URL(fileURLWithPath: path).appendingPathComponent(name), isDirectory: isDirectory,
                      bytes: bytes, modified: days(Double(name.count)))
        }
    }
}
