import Foundation

// MARK: - Project artifacts

public enum ArtifactKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case rust, node, python, pythonEnv, swift, maven, gradle, cmake, dotnet
    case web, elixir, dart, zig, haskell, terraform, cocoapods, ruby, php

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rust: "Rust builds"
        case .node: "Node dependencies"
        case .python: "Python caches"
        case .pythonEnv: "Python virtual environments"
        case .swift: "Swift package builds"
        case .maven: "Maven builds"
        case .gradle: "Gradle builds"
        case .cmake: "CMake builds"
        case .dotnet: ".NET builds"
        case .web: "Web framework caches"
        case .elixir: "Elixir builds"
        case .dart: "Dart & Flutter builds"
        case .zig: "Zig builds"
        case .haskell: "Haskell builds"
        case .terraform: "Terraform providers"
        case .cocoapods: "CocoaPods"
        case .ruby: "Ruby bundles"
        case .php: "Composer vendor"
        }
    }

    public var shortTitle: String {
        switch self {
        case .rust: "Rust"
        case .node: "Node"
        case .python: "Python"
        case .pythonEnv: "venv"
        case .swift: "Swift"
        case .maven: "Maven"
        case .gradle: "Gradle"
        case .cmake: "CMake"
        case .dotnet: ".NET"
        case .web: "Next · Nuxt · Vite"
        case .elixir: "Elixir"
        case .dart: "Flutter"
        case .zig: "Zig"
        case .haskell: "Haskell"
        case .terraform: "Terraform"
        case .cocoapods: "CocoaPods"
        case .ruby: "Ruby"
        case .php: "PHP"
        }
    }

    public var symbol: String {
        switch self {
        case .rust: "gearshape.2"
        case .node: "shippingbox"
        case .python: "curlybraces"
        case .pythonEnv: "terminal"
        case .swift: "swift"
        case .maven: "cup.and.saucer"
        case .gradle: "building.columns"
        case .cmake: "hammer"
        case .dotnet: "number"
        case .web: "globe"
        case .elixir: "drop"
        case .dart: "bird"
        case .zig: "bolt"
        case .haskell: "function"
        case .terraform: "cloud"
        case .cocoapods: "leaf"
        case .ruby: "diamond"
        case .php: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Whether findings of this kind are preselected. Kinds that may hold
    /// hand-made state (virtual environments, vendored code) start unchecked.
    public var recommended: Bool {
        switch self {
        case .pythonEnv, .cocoapods, .php: false
        default: true
        }
    }

    public var consequence: String {
        switch self {
        case .rust: "Cargo rebuilds this on the next build. Expect a slower first build."
        case .node: "Run your package manager’s install to restore it. Edits inside node_modules are lost."
        case .python: "Bytecode, test, type-checker and linter caches regenerate on demand."
        case .pythonEnv: "Recreate the environment and reinstall packages. Anything installed by hand is lost."
        case .swift: "Swift Package Manager rebuilds this .build folder."
        case .maven: "Maven recreates this target folder on the next build."
        case .gradle: "Gradle recreates this build output on the next build."
        case .cmake: "CMake must configure and rebuild this generated tree."
        case .dotnet: ".NET restores and rebuilds these bin/obj outputs."
        case .web: "The framework rebuilds this cache on the next dev or build run."
        case .elixir: "Mix refetches deps and recompiles _build."
        case .dart: "Flutter and Dart regenerate this on the next pub get or build."
        case .zig: "Zig rebuilds its cache and outputs."
        case .haskell: "Stack or Cabal rebuilds this on the next build."
        case .terraform: "Run terraform init to download providers again."
        case .cocoapods: "Run pod install to restore. Some teams commit Pods, so review first."
        case .ruby: "Run bundle install to restore vendored gems."
        case .php: "Run composer install to restore. Some projects commit vendor, so review first."
        }
    }
}

// MARK: - Cleanup categories

public enum CleanupGroup: String, CaseIterable, Sendable, Identifiable {
    case system, developer, projects
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "System"
        case .developer: "Developer"
        case .projects: "Projects"
        }
    }
}

public enum CleanupCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case userCaches, logs, appSupportCaches, appLeftovers, trash, snapshots
    case xcode, packageCaches
    case projects

    public var id: String { rawValue }

    public var group: CleanupGroup {
        switch self {
        case .userCaches, .logs, .appSupportCaches, .appLeftovers, .trash, .snapshots: .system
        case .xcode, .packageCaches: .developer
        case .projects: .projects
        }
    }

    public var title: String {
        switch self {
        case .userCaches: "App Caches"
        case .logs: "Logs"
        case .appSupportCaches: "Application Support"
        case .appLeftovers: "Leftovers"
        case .trash: "Trash"
        case .snapshots: "Snapshots"
        case .xcode: "Xcode"
        case .packageCaches: "Package Caches"
        case .projects: "Project Builds"
        }
    }

    public var symbol: String {
        switch self {
        case .userCaches: "archivebox"
        case .logs: "doc.text.magnifyingglass"
        case .appSupportCaches: "square.stack.3d.up"
        case .appLeftovers: "puzzlepiece.extension"
        case .trash: "trash"
        case .snapshots: "clock.arrow.circlepath"
        case .xcode: "hammer"
        case .packageCaches: "shippingbox"
        case .projects: "folder.badge.gearshape"
        }
    }

    public var summary: String {
        switch self {
        case .userCaches: "Temporary files apps rebuild on demand."
        case .logs: "Diagnostic logs from apps and tools."
        case .appSupportCaches: "Caches tucked inside Application Support. App data stays."
        case .appLeftovers: "Data from apps that no longer seem installed. Review carefully."
        case .trash: "Items already in Trash. Emptying is permanent."
        case .snapshots: "Local Time Machine snapshots. Your backup disk is not touched."
        case .xcode: "DerivedData, device support files, simulator caches and archives."
        case .packageCaches: "Download caches from npm, Cargo, Gradle, pip, Homebrew and others."
        case .projects: "Build outputs and dependencies inside your project folders."
        }
    }

    /// Permanent actions skip Trash; the review sheet calls these out.
    public var isPermanent: Bool { self == .trash || self == .snapshots }
}

public enum CleanupAction: Sendable, Hashable {
    /// Move to Trash (recoverable with Put Back).
    case moveToTrash
    /// Permanently remove (used only for items already in Trash).
    case deletePermanently
    /// Delete a local APFS snapshot by its Time Machine date token.
    case deleteSnapshot(String)
}

public struct Finding: Identifiable, Sendable, Hashable {
    public var id: String { url.path + (snapshotToken.map { "#" + $0 } ?? "") }
    public let url: URL
    /// The approved boundary this item must stay inside at cleanup time.
    public let root: URL
    public let category: CleanupCategory
    public let kind: ArtifactKind?
    public let title: String
    public let bytes: Int64
    public let modified: Date
    public let inode: UInt64
    public let device: UInt64
    public let recommended: Bool
    public let note: String?
    /// Bundle identifier of the owning app, used for icons and running checks.
    public let bundleID: String?
    public let action: CleanupAction

    public init(
        url: URL, root: URL, category: CleanupCategory, kind: ArtifactKind? = nil, title: String? = nil,
        bytes: Int64, modified: Date, inode: UInt64, device: UInt64, recommended: Bool = true,
        note: String? = nil, bundleID: String? = nil, action: CleanupAction = .moveToTrash
    ) {
        self.url = url
        self.root = root
        self.category = category
        self.kind = kind
        self.title = title ?? Finding.defaultTitle(url: url, kind: kind)
        self.bytes = bytes
        self.modified = modified
        self.inode = inode
        self.device = device
        self.recommended = recommended
        self.note = note
        self.bundleID = bundleID
        self.action = action
    }

    public var project: String { title }

    /// Items such as snapshots have no measurable folder size.
    public var hasKnownSize: Bool { if case .deleteSnapshot = action { false } else { true } }

    var snapshotToken: String? { if case .deleteSnapshot(let token) = action { token } else { nil } }

    static func defaultTitle(url: URL, kind: ArtifactKind?) -> String {
        kind == nil ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
    }
}

public struct ScanReport: Sendable {
    public var findings: [Finding] = []
    public var warnings: [String] = []
    /// Locations macOS refused to show us; usually needs Full Disk Access.
    public var needsFullDiskAccess = false
    public init() {}
}

// MARK: - Path policy

public enum PathPolicy {
    public static func contains(_ parent: URL, _ child: URL) -> Bool {
        let p = parent.standardizedFileURL.path
        let c = child.standardizedFileURL.path
        return c == p || c.hasPrefix(p == "/" ? "/" : p + "/")
    }

    public static func isProtected(_ url: URL, by exclusions: [URL]) -> Bool {
        // An artifact containing an excluded child is protected too.
        exclusions.contains { contains($0, url) || contains(url, $0) }
    }

    public static func hasSymlinkComponent(_ url: URL) -> Bool {
        url.standardizedFileURL.path != url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
