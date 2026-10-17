import Foundation

/// What the system scan needs to know about apps on this Mac. Gathered by the
/// app layer (AppKit) so the scanner stays testable.
public struct AppInventory: Sendable {
    public var runningBundleIDs: Set<String>
    public var runningNames: Set<String>
    public var installedBundleIDs: Set<String>
    public var installedNames: Set<String>

    public init(
        runningBundleIDs: Set<String> = [], runningNames: Set<String> = [],
        installedBundleIDs: Set<String> = [], installedNames: Set<String> = []
    ) {
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.runningNames = Set(runningNames.map { $0.lowercased() })
        self.installedBundleIDs = Set(installedBundleIDs.map { $0.lowercased() })
        self.installedNames = Set(installedNames.map { $0.lowercased() })
    }

    /// Whether a folder named after an app (bundle ID or display name) belongs to an open app.
    public func isRunning(_ folderName: String) -> Bool {
        let name = folderName.lowercased()
        if runningBundleIDs.contains(where: { name == $0 || name.hasPrefix($0 + ".") }) { return true }
        guard name.count >= 4, !name.contains(".") else { return false }
        return runningNames.contains { $0 == name || $0.hasPrefix(name + " ") || $0.hasSuffix(" " + name) }
    }

    public func isInstalled(_ folderName: String) -> Bool {
        let name = folderName.lowercased()
        if installedBundleIDs.contains(where: { name == $0 || name.hasPrefix($0 + ".") || $0.hasPrefix(name + ".") }) {
            return true
        }
        if name.contains(".") {
            // Reverse-DNS folders: match on the vendor/product suffix too.
            let product = name.split(separator: ".").last.map(String.init) ?? name
            return installedNames.contains { $0.replacingOccurrences(of: " ", with: "") == product }
        }
        return installedNames.contains { $0 == name || $0.contains(name) || name.contains($0) }
    }
}

public struct SystemScanOptions: Sendable {
    public var home: URL
    public var categories: Set<CleanupCategory>
    public var apps: AppInventory
    /// Items smaller than this are hidden to keep lists meaningful.
    public var minimumBytes: Int64

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        categories: Set<CleanupCategory>, apps: AppInventory, minimumBytes: Int64 = 1_000_000
    ) {
        self.home = home
        self.categories = categories
        self.apps = apps
        self.minimumBytes = minimumBytes
    }
}

/// Finds caches, logs, leftovers, Trash, snapshots and developer-tool caches
/// in well-known locations. Read-only.
public enum SystemScanner {
    struct PackageCache {
        let path: String
        let title: String
        let recommended: Bool
    }

    static let packageCaches: [PackageCache] = [
        .init(path: ".npm/_cacache", title: "npm", recommended: true),
        .init(path: "Library/Caches/Yarn", title: "Yarn", recommended: true),
        .init(path: "Library/pnpm/store", title: "pnpm store", recommended: true),
        .init(path: ".bun/install/cache", title: "Bun", recommended: true),
        .init(path: ".cargo/registry/cache", title: "Cargo registry downloads", recommended: true),
        .init(path: ".cargo/registry/src", title: "Cargo registry sources", recommended: true),
        .init(path: ".cargo/git/checkouts", title: "Cargo git checkouts", recommended: true),
        .init(path: ".gradle/caches", title: "Gradle", recommended: true),
        .init(path: ".gradle/wrapper/dists", title: "Gradle wrapper distributions", recommended: false),
        .init(path: ".m2/repository", title: "Maven repository", recommended: false),
        .init(path: "Library/Caches/pip", title: "pip", recommended: true),
        .init(path: "Library/Caches/pypoetry", title: "Poetry", recommended: true),
        .init(path: ".cache/uv", title: "uv", recommended: true),
        .init(path: "Library/Caches/go-build", title: "Go build cache", recommended: true),
        .init(path: "Library/Caches/Homebrew", title: "Homebrew downloads", recommended: true),
        .init(path: "Library/Caches/CocoaPods", title: "CocoaPods", recommended: true),
        .init(path: "Library/Caches/ms-playwright", title: "Playwright browsers", recommended: false),
        .init(path: ".nuget/packages", title: "NuGet packages", recommended: true),
        .init(path: ".pub-cache", title: "Dart pub cache", recommended: false),
        .init(path: ".cache/pre-commit", title: "pre-commit", recommended: true),
        .init(path: ".cache/huggingface", title: "Hugging Face models", recommended: false),
    ]

    /// ~/Library/Caches children reported under Package Caches instead.
    static let cachesOwnedByPackageManagers: Set<String> = [
        "Yarn", "pip", "pypoetry", "go-build", "Homebrew", "CocoaPods", "ms-playwright",
    ]

    static let appSupportCacheNames: Set<String> = [
        "Cache", "Caches", "CachedData", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GrShaderCache", "GraphiteDawnCache", "ShaderCache", "CachedExtensionVSIXs",
        "CacheStorage", "Crashpad", "logs",
    ]

    /// Application Support folders that belong to macOS or hold irreplaceable
    /// data. Never offered as leftovers.
    static let protectedAppSupport: Set<String> = [
        "AddressBook", "Animoji", "App Store", "AppStore", "CallHistoryDB", "CallHistoryTransactions",
        "CloudDocs", "CrashReporter", "DiskImages", "Dock", "FaceTime", "FileProvider", "iCloud",
        "icdd", "Knowledge", "MobileSync", "networkserviceproxy", "Quick Look", "SyncServices",
        "accountsd", "audiomxd", "AppleMediaServices", "Mail", "Messages", "Photos", "Safari",
        "ScreenTime", "Shortcuts", "Wallpaper", "WallpaperAgent", "FamilyCircle", "Siri",
        "CoreParsec", "ControlCenter", "default.store", "identityservicesd", "locationaccessstored",
        "homeenergyd", "tipsd", "Ubiquity", "Stickies", "Notes", "ProApps", "Maps",
    ]

    public static func scan(
        _ options: SystemScanOptions, exclusions: [URL],
        progress: @escaping @Sendable (String) async -> Void,
        finished: @escaping @Sendable (CleanupCategory, ScanReport) async -> Void = { _, _ in }
    ) async throws -> ScanReport {
        try await withThrowingTaskGroup(of: ScanReport.self) { group in
            for category in CleanupCategory.allCases where options.categories.contains(category) {
                group.addTask {
                    await progress(category.title)
                    let report = try scan(category, options: options, exclusions: exclusions)
                    await finished(category, report)
                    return report
                }
            }
            var merged = ScanReport()
            for try await part in group {
                merged.findings += part.findings
                merged.warnings += part.warnings
                merged.needsFullDiskAccess = merged.needsFullDiskAccess || part.needsFullDiskAccess
            }
            merged.findings.sort { $0.bytes > $1.bytes }
            return merged
        }
    }

    static func scan(_ category: CleanupCategory, options: SystemScanOptions, exclusions: [URL]) throws -> ScanReport {
        let home = options.home
        let library = home.appendingPathComponent("Library")
        var report = ScanReport()

        func add(_ url: URL, root: URL, title: String? = nil, recommended: Bool = true,
                 note: String? = nil, bundleID: String? = nil, action: CleanupAction = .moveToTrash,
                 minimum: Int64? = nil) throws {
            try Task.checkCancellation()
            guard !PathPolicy.isProtected(url, by: exclusions), !PathPolicy.hasSymlinkComponent(url),
                  let identity = try? FileIdentity(url) else { return }
            let bytes = try DiskUsage.allocatedSize(url, tolerant: true)
            guard bytes >= (minimum ?? options.minimumBytes) else { return }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            report.findings.append(Finding(
                url: url, root: root, category: category, title: title, bytes: bytes, modified: modified,
                inode: identity.inode, device: identity.device, recommended: recommended, note: note,
                bundleID: bundleID, action: action
            ))
        }

        func runningCheck(_ name: String) -> (recommended: Bool, note: String?) {
            options.apps.isRunning(name) ? (false, "Open now. Quit the app before cleaning.") : (true, nil)
        }

        switch category {
        case .userCaches:
            let root = library.appendingPathComponent("Caches")
            for url in children(of: root) where !cachesOwnedByPackageManagers.contains(url.lastPathComponent) {
                let name = url.lastPathComponent
                // Apple's own caches are often privacy-protected; reading them
                // triggers macOS permission prompts (Music, Photos…). Leave them be.
                guard !name.hasPrefix("com.apple.") else { continue }
                let state = runningCheck(name)
                try add(url, root: root, title: displayName(name), recommended: state.recommended,
                        note: state.note, bundleID: bundleID(name))
            }

        case .logs:
            let root = library.appendingPathComponent("Logs")
            for url in children(of: root) {
                try add(url, root: root, title: displayName(url.lastPathComponent),
                        bundleID: bundleID(url.lastPathComponent))
            }

        case .appSupportCaches:
            let root = library.appendingPathComponent("Application Support")
            for app in children(of: root) where isCandidateAppFolder(app.lastPathComponent) {
                // Folders without a matching app are offered whole under Leftovers.
                guard options.apps.isInstalled(app.lastPathComponent) || options.apps.isRunning(app.lastPathComponent)
                else { continue }
                let state = runningCheck(app.lastPathComponent)
                for cache in nestedCaches(in: app) {
                    let relative = cache.path.dropFirst(app.path.count + 1)
                    try add(cache, root: root, title: "\(displayName(app.lastPathComponent)) · \(relative)",
                            recommended: state.recommended, note: state.note,
                            bundleID: bundleID(app.lastPathComponent))
                }
            }

        case .appLeftovers:
            let root = library.appendingPathComponent("Application Support")
            for app in children(of: root) where isCandidateAppFolder(app.lastPathComponent) {
                let name = app.lastPathComponent
                guard isDirectory(app), !options.apps.isInstalled(name), !options.apps.isRunning(name) else { continue }
                try add(app, root: root, title: displayName(name), recommended: false,
                        note: "No matching app found. Make sure it isn’t data you still need.",
                        bundleID: bundleID(name), minimum: max(options.minimumBytes, 10_000_000))
            }

        case .trash:
            let root = home.appendingPathComponent(".Trash")
            do {
                let items = try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                ).filter { $0.lastPathComponent != ".DS_Store" }
                for url in items {
                    try add(url, root: root, action: .deletePermanently, minimum: 0)
                }
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                report.needsFullDiskAccess = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.needsFullDiskAccess = true
            }

        case .snapshots:
            for snapshot in Snapshots.list() {
                report.findings.append(Finding(
                    url: URL(fileURLWithPath: "/"), root: URL(fileURLWithPath: "/"), category: .snapshots,
                    title: "Time Machine · \(snapshot.date.formatted(date: .abbreviated, time: .shortened))",
                    bytes: 0, modified: snapshot.date, inode: 0, device: 0, recommended: true,
                    note: "macOS also removes these on its own when space runs low.",
                    action: .deleteSnapshot(snapshot.token)
                ))
            }

        case .xcode:
            let developer = library.appendingPathComponent("Developer")
            let xcode = developer.appendingPathComponent("Xcode")
            let xcodeOpen = options.apps.isRunning("com.apple.dt.Xcode")
            let busy = xcodeOpen ? "Xcode is open. Quit it before cleaning." : nil
            let derived = xcode.appendingPathComponent("DerivedData")
            for url in children(of: derived) where url.lastPathComponent != "ModuleCache.noindex" {
                let project = url.lastPathComponent.split(separator: "-").dropLast().joined(separator: "-")
                try add(url, root: derived, title: "DerivedData · \(project.isEmpty ? url.lastPathComponent : project)",
                        recommended: !xcodeOpen, note: busy, bundleID: "com.apple.dt.Xcode")
            }
            let moduleCache = derived.appendingPathComponent("ModuleCache.noindex")
            try add(moduleCache, root: derived, title: "DerivedData · Module cache", recommended: !xcodeOpen,
                    note: busy, bundleID: "com.apple.dt.Xcode")
            for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
                let support = xcode.appendingPathComponent("\(platform) DeviceSupport")
                for url in children(of: support) {
                    try add(url, root: support, title: "\(platform) device support · \(url.lastPathComponent)",
                            note: "Re-created when you connect a device on this version.",
                            bundleID: "com.apple.dt.Xcode")
                }
            }
            let archives = xcode.appendingPathComponent("Archives")
            for day in children(of: archives) {
                for archive in children(of: day) where archive.pathExtension == "xcarchive" {
                    try add(archive, root: archives, title: "Archive · \(archive.deletingPathExtension().lastPathComponent)",
                            recommended: false, note: "Needed to symbolicate crash reports for this build.",
                            bundleID: "com.apple.dt.Xcode")
                }
            }
            let simulatorCaches = developer.appendingPathComponent("CoreSimulator/Caches")
            try add(simulatorCaches, root: developer, title: "Simulator caches", bundleID: "com.apple.iphonesimulator")
            let previews = xcode.appendingPathComponent("UserData/Previews")
            try add(previews, root: xcode, title: "SwiftUI preview simulators", recommended: !xcodeOpen,
                    note: busy, bundleID: "com.apple.dt.Xcode")
            let testDevices = developer.appendingPathComponent("XCTestDevices")
            try add(testDevices, root: developer, title: "Test device clones", recommended: !xcodeOpen,
                    note: busy, bundleID: "com.apple.dt.Xcode")

        case .packageCaches:
            for cache in packageCaches {
                let url = home.appendingPathComponent(cache.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                try add(url, root: url.deletingLastPathComponent(), title: cache.title,
                        recommended: cache.recommended,
                        note: cache.recommended ? nil : "Large to re-download. Review before cleaning.")
            }

        case .projects:
            break
        }
        return report
    }

    // MARK: Helpers

    static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ))?.filter { child in
            child.lastPathComponent != ".DS_Store"
                && (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        } ?? []
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func isCandidateAppFolder(_ name: String) -> Bool {
        !name.hasPrefix("com.apple.") && !name.hasPrefix(".") && !protectedAppSupport.contains(name)
    }

    /// Cache folders up to four levels inside an app's support folder.
    static func nestedCaches(in app: URL) -> [URL] {
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: app, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if appSupportCacheNames.contains(url.lastPathComponent) {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    static func bundleID(_ name: String) -> String? {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) ? name : nil
    }

    /// Turns reverse-DNS folder names into something readable.
    static func displayName(_ name: String) -> String {
        guard let id = bundleID(name) else { return name }
        let parts = id.split(separator: ".")
        let last = parts.last.map(String.init) ?? id
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

// MARK: - Snapshots

public enum Snapshots {
    public struct Snapshot: Sendable, Hashable {
        public let token: String
        public let date: Date
    }

    public static func isValidToken(_ token: String) -> Bool {
        token.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil
    }

    /// Parses `tmutil listlocalsnapshots /` output.
    public static func parse(_ output: String) -> [Snapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("com.apple.TimeMachine."), text.hasSuffix(".local") else { return nil }
            let token = String(text.dropFirst("com.apple.TimeMachine.".count).dropLast(".local".count))
            guard isValidToken(token), let date = formatter.date(from: token) else { return nil }
            return Snapshot(token: token, date: date)
        }
    }

    public static func list() -> [Snapshot] {
        guard let output = try? run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output else { return [] }
        return parse(output)
    }

    /// Deletes one local snapshot. Callers fall back to an administrator prompt on failure.
    public static func delete(_ token: String) throws {
        guard isValidToken(token) else { throw CleanupError.unsafePath }
        let result = try run("/usr/bin/tmutil", ["deletelocalsnapshots", token])
        guard result.status == 0 else { throw CleanupError.snapshotFailed(result.output) }
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
