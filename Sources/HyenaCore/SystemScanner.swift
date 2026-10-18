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
        if installedNames.contains(where: { $0 == name || $0.contains(name) || name.contains($0) }) { return true }
        // Vendor folders: "BraveSoftware" belongs to com.brave.Browser, "Google" to com.google.Chrome.
        let generic: Set<String> = ["apple", "com", "app", "mac", "macos", "inc", "co", "io"]
        return installedBundleIDs.contains { id in
            let parts = id.split(separator: ".")
            guard parts.count >= 2 else { return false }
            let vendor = String(parts[1])
            return vendor.count >= 4 && !generic.contains(vendor) && name.contains(vendor)
        }
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
        .init(path: ".pub-cache/hosted", title: "Dart pub packages", recommended: false),
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
        "Crashpad", "logs",
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

    /// Browser folders in Application Support hold profiles, saved passwords, extensions and the
    /// bridges to password managers. Hyena never cleans inside them and never calls them leftovers.
    static let browserFolders: Set<String> = [
        "Google", "BraveSoftware", "Microsoft Edge", "Microsoft", "Mozilla", "Firefox", "Arc", "Chromium",
        "Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX", "Orion", "Zen", "Sidekick", "Comet",
        "Yandex", "Thorium", "Floorp", "Waterfox", "LibreWolf",
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
            let previews = xcode.appendingPathComponent("UserData/Previews")
            try add(previews, root: xcode, title: "SwiftUI preview simulators", recommended: !xcodeOpen,
                    note: busy, bundleID: "com.apple.dt.Xcode")
            let testDevices = developer.appendingPathComponent("XCTestDevices")
            try add(testDevices, root: developer, title: "Test device clones", recommended: !xcodeOpen,
                    note: busy, bundleID: "com.apple.dt.Xcode")

        case .simulators:
            let core = library.appendingPathComponent("Developer/CoreSimulator")
            let devices = core.appendingPathComponent("Devices")
            let availability = Simulators.availability()
            let simulatorOpen = options.apps.isRunning("com.apple.iphonesimulator")
            let staleCutoff = Date().addingTimeInterval(-90 * 86_400)
            for url in children(of: devices) where isDirectory(url) {
                guard let device = Simulators.device(at: url) else { continue }
                let unavailable = availability[device.udid] == false
                let booted = device.state == 3
                var note: String
                var recommended = false
                if booted {
                    note = "Running now. Shut it down before cleaning."
                } else if unavailable {
                    note = "Its iOS runtime is no longer installed, so it can’t run."
                    recommended = !simulatorOpen
                } else if let last = device.lastBooted, last < staleCutoff {
                    note = "Not used since \(last.formatted(date: .abbreviated, time: .omitted)). Erases its apps and data."
                } else {
                    note = "Erases this simulator’s apps and data."
                }
                try add(url, root: devices, title: "\(device.name) · \(device.runtimeName)", recommended: recommended,
                        note: note, bundleID: "com.apple.iphonesimulator")
            }
            try add(core.appendingPathComponent("Caches"), root: core, title: "Simulator caches",
                    recommended: !simulatorOpen, note: simulatorOpen ? "Simulator is open. Quit it first." : nil,
                    bundleID: "com.apple.iphonesimulator")

        case .downloads:
            let root = home.appendingPathComponent("Downloads")
            let installerCutoff = Date().addingTimeInterval(-7 * 86_400)
            let oldCutoff = Date().addingTimeInterval(-90 * 86_400)
            do {
                let items = try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: []
                )
                for url in items where url.lastPathComponent != ".DS_Store" && !url.lastPathComponent.hasPrefix(".") {
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? Date()
                    if Downloads.installerExtensions.contains(url.pathExtension.lowercased()) {
                        guard modified < installerCutoff else { continue }
                        try add(url, root: root, recommended: true,
                                note: "Installer. Whatever it installed stays.", minimum: 1_000_000)
                    } else if modified < oldCutoff {
                        let months = Int(Date().timeIntervalSince(modified) / (30 * 86_400))
                        try add(url, root: root, recommended: false,
                                note: "Untouched for \(months) months. Make sure you don’t need it.", minimum: 100_000_000)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.warnings.append("Couldn’t read Downloads: \(error.localizedDescription)")
            }

        case .devices:
            let backups = library.appendingPathComponent("Application Support/MobileSync/Backup")
            if FileManager.default.fileExists(atPath: backups.path) {
                do {
                    let items = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
                    for url in items where isDirectory(url) {
                        let info = DeviceBackups.info(at: url)
                        let age = info.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "unknown date"
                        let old = info.date.map { $0 < Date().addingTimeInterval(-365 * 86_400) } ?? false
                        try add(url, root: backups, title: "\(info.name) · backed up \(age)", recommended: false,
                                note: old ? "Over a year old. Keep it only if it’s your only copy."
                                          : "May be your only copy of this device. Review carefully.",
                                minimum: 0)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    report.needsFullDiskAccess = true
                }
            }
            for folder in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
                let updates = library.appendingPathComponent("iTunes/\(folder)")
                for url in children(of: updates) where url.pathExtension == "ipsw" {
                    try add(url, root: updates, title: "\(url.deletingPathExtension().lastPathComponent) (iOS update file)",
                            recommended: true, note: "Downloaded once to update a device. Not needed afterwards.")
                }
            }

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
        let lowered = name.lowercased()
        return !name.hasPrefix("com.apple.") && !name.hasPrefix(".") && !protectedAppSupport.contains(name)
            && !browserFolders.contains(name)
            && !SafetyPolicy.passwordManagers.contains(where: { lowered.contains($0) })
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
            // Never look inside browser extension or profile state.
            if SafetyPolicy.browserStateComponents.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
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

// MARK: - Simulators, downloads and device backups

public enum Simulators {
    public struct Device: Sendable {
        public let udid: String
        public let name: String
        public let runtimeName: String
        public let lastBooted: Date?
        public let state: Int
    }

    /// Reads a simulator's device.plist.
    public static func device(at url: URL) -> Device? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("device.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let udid = plist["UDID"] as? String, let name = plist["name"] as? String,
              (plist["isDeleted"] as? Bool) != true else { return nil }
        return Device(
            udid: udid, name: name, runtimeName: runtimeName(plist["runtime"] as? String ?? ""),
            lastBooted: plist["lastBootedAt"] as? Date, state: plist["state"] as? Int ?? 0
        )
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-2" → "iOS 26.2"
    public static func runtimeName(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last else { return "Unknown runtime" }
        let parts = last.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return String(last) }
        return "\(platform) " + parts.dropFirst().joined(separator: ".")
    }

    /// UDID → whether CoreSimulator can still run it. Empty when Xcode tools are missing.
    public static func availability() -> [String: Bool] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun"),
              let result = try? Snapshots.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]),
              result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return [:] }
        var map: [String: Bool] = [:]
        for devices in runtimes.values {
            for device in devices {
                if let udid = device["udid"] as? String { map[udid] = device["isAvailable"] as? Bool ?? true }
            }
        }
        return map
    }
}

public enum Downloads {
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]
}

public enum DeviceBackups {
    /// Device name and backup date from a backup's Info.plist.
    public static func info(at url: URL) -> (name: String, date: Date?) {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return ("Device backup", nil) }
        let name = plist["Device Name"] as? String ?? plist["Display Name"] as? String ?? "Device backup"
        return (name, plist["Last Backup Date"] as? Date)
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
