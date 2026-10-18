import Foundation

/// The last line of defense. Every path is checked here immediately before it
/// is moved or deleted, independently of how it was found, so a bug in a
/// scanner, the selection model or the UI can't reach system files, personal
/// data or anything outside the category that found it.
public enum SafetyPolicy {
    /// The home folder all user-level rules are relative to. Tests point it at a fixture.
    nonisolated(unsafe) public static var home = FileManager.default.homeDirectoryForCurrentUser

    /// System locations nothing may ever be removed from.
    static let systemTrees = [
        "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/etc", "/opt", "/cores", "/dev",
        "/Network", "/private/etc", "/private/var/db", "/private/var/root", "/private/var/vm", "/private/var/log",
    ]

    /// Credentials, settings and app data inside the home folder: never touched by any category.
    static let criticalHomeTrees = [
        "Library/Keychains", "Library/Preferences", "Library/Mail", "Library/Messages", "Library/Calendars",
        "Library/Accounts", "Library/Containers", "Library/Group Containers", "Library/Cookies", "Library/Safari",
        "Library/Photos", "Library/HomeKit", "Library/IdentityServices", "Library/Application Support/AddressBook",
        "Library/Application Support/com.apple.TCC", "Library/LaunchAgents",
        ".ssh", ".gnupg", ".aws", ".kube", ".config/gh", ".netrc", ".docker/config.json",
    ]

    /// Personal folders: off limits to everything except project builds, which
    /// often live in ~/Documents and are still protected by their markers.
    static let personalHomeTrees = [
        "Documents", "Desktop", "Pictures", "Movies", "Music", "Public",
        "Library/Mobile Documents", "Library/CloudStorage",
    ]

    /// Where each category may remove things: strictly inside one of these
    /// folders, never the folder itself. Relative to the home folder.
    static func bases(for category: CleanupCategory) -> [String] {
        switch category {
        case .userCaches: ["Library/Caches"]
        case .logs: ["Library/Logs"]
        case .appSupportCaches, .appLeftovers: ["Library/Application Support"]
        case .downloads: ["Downloads"]
        case .devices: ["Library/Application Support/MobileSync/Backup", "Library/iTunes"]
        case .trash: [".Trash"]
        case .xcode: ["Library/Developer/Xcode", "Library/Developer/XCTestDevices"]
        case .simulators: ["Library/Developer/CoreSimulator"]
        case .packageCaches:
            [".npm", ".cargo", ".gradle", ".m2", ".bun", ".nuget", ".pub-cache", ".cache", "Library/Caches", "Library/pnpm"]
        case .snapshots, .projects: []
        }
    }

    /// Single folders a category may remove as a whole (home-relative).
    static func exactTargets(for category: CleanupCategory) -> [String] {
        category == .xcode ? ["Library/Developer/XCTestDevices"] : []
    }

    /// Categories whose items regenerate on their own, so "Delete immediately"
    /// may skip Trash. Backups, downloads and leftovers always go to Trash.
    public static func allowsImmediateDeletion(_ category: CleanupCategory) -> Bool {
        switch category {
        case .userCaches, .logs, .appSupportCaches, .xcode, .simulators, .packageCaches, .projects: true
        case .appLeftovers, .downloads, .devices, .trash, .snapshots: false
        }
    }

    /// Throws unless `target` may be removed for `category`.
    public static func check(_ target: URL, category: CleanupCategory, permanently: Bool = false) throws {
        if category == .snapshots { return } // not a file; guarded by the snapshot token check
        let path = normalized(target)
        let home = normalized(Self.home)
        func inHome(_ relative: String) -> String { relative.isEmpty ? home : home + "/" + relative }

        guard path.hasPrefix("/"), path.count > 1 else { throw SafetyViolation.systemLocation(path) }
        if path.split(separator: "/").contains("..") { throw SafetyViolation.systemLocation(path) }

        for tree in systemTrees where isWithin(path, tree) { throw SafetyViolation.systemLocation(path) }
        // Never the home folder, anything above it, or another user's folder.
        if isWithin(home, path) { throw SafetyViolation.essentialFolder(path) }
        if isWithin(path, "/Users"), !isWithin(path, home), !isTemporary(path) {
            throw SafetyViolation.outsideHome(path)
        }
        for tree in criticalHomeTrees {
            let protected = inHome(tree)
            if isWithin(path, protected) || isWithin(protected, path) { throw SafetyViolation.sensitiveData(path) }
        }
        if category != .projects {
            for tree in personalHomeTrees {
                let protected = inHome(tree)
                if isWithin(path, protected) || isWithin(protected, path) { throw SafetyViolation.sensitiveData(path) }
            }
            // Strictly inside one of the category's own folders.
            let allowed = bases(for: category).map(inHome)
            let exact = exactTargets(for: category).map(inHome)
            guard allowed.contains(where: { isStrictlyWithin(path, $0) }) || exact.contains(path) else {
                throw SafetyViolation.outsideCategory(path, category.title)
            }
        } else {
            // Project builds may live anywhere the user chose, but never directly in a top-level home folder.
            let shallow = ["", "Library", "Documents", "Desktop", "Developer", "Downloads"].map(inHome)
            if shallow.contains(path) { throw SafetyViolation.essentialFolder(path) }
        }
        if containsRepository(target) { throw SafetyViolation.repository(path) }
        if permanently, category != .trash, !allowsImmediateDeletion(category) {
            throw SafetyViolation.permanentNotAllowed(category.title)
        }
    }

    /// A folder that directly holds `.git` is source code, whatever its name.
    static func containsRepository(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let git = url.appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory)
    }

    static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        // /var, /tmp and /etc are symlinks into /private; compare in one form.
        for alias in ["/var", "/tmp", "/etc"] where path == alias || path.hasPrefix(alias + "/") {
            path = "/private" + path
        }
        return path
    }

    static func isTemporary(_ path: String) -> Bool {
        isWithin(path, "/private/var/folders") || isWithin(path, "/private/tmp")
    }

    static func isWithin(_ path: String, _ ancestor: String) -> Bool {
        path == ancestor || isStrictlyWithin(path, ancestor)
    }

    static func isStrictlyWithin(_ path: String, _ ancestor: String) -> Bool {
        path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
    }
}

public enum SafetyViolation: LocalizedError, Equatable {
    case systemLocation(String)
    case essentialFolder(String)
    case outsideHome(String)
    case sensitiveData(String)
    case outsideCategory(String, String)
    case repository(String)
    case permanentNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case .systemLocation: "Refused: this is a macOS system location."
        case .essentialFolder: "Refused: this folder holds your other files and is never removed."
        case .outsideHome: "Refused: this belongs to another user."
        case .sensitiveData: "Refused: this holds personal data, settings or credentials."
        case .outsideCategory(_, let category): "Refused: this is outside the folders \(category) may clean."
        case .repository: "Refused: this folder contains a Git repository."
        case .permanentNotAllowed(let category): "\(category) items always go to Trash so they can be recovered."
        }
    }
}
