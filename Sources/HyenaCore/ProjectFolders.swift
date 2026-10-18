import Foundation

/// Finds folders that hold several projects (e.g. ~/projects, ~/Documents/GitHub),
/// so project builds can be scanned without asking the user to pick folders first.
public enum ProjectFolders {
    static let markers = [
        ".git", "package.json", "Cargo.toml", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts",
        "settings.gradle", "pubspec.yaml", "go.mod", "pyproject.toml", "requirements.txt", "mix.exs",
        "Gemfile", "composer.json", "CMakeLists.txt", "build.zig", "stack.yaml", "Podfile",
    ]
    /// Home folders that never count as project folders themselves.
    static let skipped: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures", "Public", "Downloads", "Desktop", "Documents",
    ]

    /// Folders with at least `minimumProjects` projects directly inside, searched in the
    /// home folder, ~/Documents and ~/Developer. Most projects first.
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                minimumProjects: Int = 2) -> [URL] {
        var candidates = children(of: home).filter { !skipped.contains($0.lastPathComponent) }
        for nested in ["Documents", "Developer"] {
            let folder = home.appendingPathComponent(nested)
            candidates += [folder] + children(of: folder)
        }
        var seen = Set<String>()
        let scored: [(URL, Int)] = candidates.compactMap { folder in
            guard let real = try? folder.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
                  seen.insert(real.lowercased()).inserted, !isProject(folder) else { return nil }
            let count = children(of: folder).filter(isProject).count
            return count >= minimumProjects ? (folder, count) : nil
        }
        // Drop folders nested inside another chosen folder; scanning the parent covers them.
        let sorted = scored.sorted { $0.1 > $1.1 }.map(\.0)
        return sorted.filter { folder in
            !sorted.contains { $0 != folder && PathPolicy.contains($0, folder) }
        }
    }

    static func isProject(_ folder: URL) -> Bool {
        let fm = FileManager.default
        if markers.contains(where: { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }) { return true }
        return (try? fm.contentsOfDirectory(atPath: folder.path))?.contains { $0.hasSuffix(".xcodeproj") } ?? false
    }

    static func children(of folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        return ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true && values.isPackage != true
        }
    }
}
