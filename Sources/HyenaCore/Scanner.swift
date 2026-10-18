import Foundation

/// Finds build outputs and dependencies inside user-approved project folders.
public enum Scanner {
    public static func detect(_ url: URL) -> ArtifactKind? {
        let parent = url.deletingLastPathComponent()
        let name = url.lastPathComponent

        if ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"].contains(name) {
            return .python
        }
        if name.hasPrefix("cmake-build-"), hasRegularFile("CMakeCache.txt", in: url) {
            return .cmake
        }

        // Every rule pairs a folder name with a project marker so arbitrary
        // folders that merely share a common name are never matched.
        func named(_ names: Set<String>, _ marker: @autoclosure () -> Bool) -> Bool {
            names.contains(name) && marker()
        }
        let dotnet = ["csproj", "fsproj", "vbproj"]
        if named(["target"], hasRegularFile("Cargo.toml", in: parent)) { return .rust }
        if named(["target"], hasRegularFile("pom.xml", in: parent)) { return .maven }
        if named(["node_modules"], hasRegularFile("package.json", in: parent)) { return .node }
        if named([".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular", ".docusaurus", ".astro"],
                 hasRegularFile("package.json", in: parent)) { return .web }
        if named([".venv", "venv", "env", ".env"], hasRegularFile("pyvenv.cfg", in: url)) { return .pythonEnv }
        if named([".tox"], hasRegularFile("tox.ini", in: parent) || hasRegularFile("pyproject.toml", in: parent)) {
            return .python
        }
        if named([".build"], hasRegularFile("Package.swift", in: parent)) { return .swift }
        if named(["build", ".gradle"], hasGradleMarker(in: parent)) { return .gradle }
        if named(["build", ".dart_tool"], hasRegularFile("pubspec.yaml", in: parent)) { return .dart }
        if named(["build"], hasRegularFile("CMakeCache.txt", in: url)) { return .cmake }
        if named(["bin", "obj"], hasProjectFile(in: parent, extensions: dotnet)) { return .dotnet }
        if named(["_build", "deps"], hasRegularFile("mix.exs", in: parent)) { return .elixir }
        if named([".zig-cache", "zig-cache", "zig-out"], hasRegularFile("build.zig", in: parent)) { return .zig }
        if named([".stack-work"], hasRegularFile("stack.yaml", in: parent)) { return .haskell }
        if named(["dist-newstyle"], hasRegularFile("cabal.project", in: parent)
                 || hasProjectFile(in: parent, extensions: ["cabal"])) { return .haskell }
        if named([".terraform"], hasProjectFile(in: parent, extensions: ["tf"])) { return .terraform }
        if named(["Pods"], hasRegularFile("Podfile", in: parent)) { return .cocoapods }
        if named(["bundle"], parent.lastPathComponent == "vendor"
                 && hasRegularFile("Gemfile", in: parent.deletingLastPathComponent())) { return .ruby }
        if named(["vendor"], hasRegularFile("composer.json", in: parent)) { return .php }
        return nil
    }

    static func hasRegularFile(_ name: String, in directory: URL) -> Bool {
        let file = directory.appendingPathComponent(name)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func hasGradleMarker(in directory: URL) -> Bool {
        ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
            .contains { hasRegularFile($0, in: directory) }
    }

    private static func hasProjectFile(in directory: URL, extensions: [String]) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return entries.contains { name in
            extensions.contains { name.hasSuffix("." + $0) } && hasRegularFile(name, in: directory)
        }
    }

    public static func scan(
        roots: [URL], exclusions: [URL], kinds: Set<ArtifactKind>, minimumAgeDays: Int,
        progress: @Sendable (String) async -> Void
    ) async throws -> ScanReport {
        var report = ScanReport()
        var seen = Set<String>()
        let cutoff = Date().addingTimeInterval(-Double(minimumAgeDays) * 86_400)
        for root in roots {
            try Task.checkCancellation()
            guard !PathPolicy.hasSymlinkComponent(root) else {
                report.warnings.append("Skipped symbolic-link location: \(root.path)")
                continue
            }
            guard detect(root) == nil else {
                report.warnings.append("Choose the parent folder instead of the artifact itself: \(root.path)")
                continue
            }
            await progress(root.lastPathComponent)
            try Task.checkCancellation()
            var traversalErrors: [String] = []
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    traversalErrors.append("\(url.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                report.warnings.append("Could not read \(root.path)")
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if PathPolicy.isProtected(url, by: exclusions) {
                    // An ancestor of a protected path may still contain other projects.
                    if exclusions.contains(where: { PathPolicy.contains($0, url) }) {
                        enumerator.skipDescendants()
                    }
                    if detect(url) != nil { enumerator.skipDescendants() }
                    continue
                }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isSymbolicLink != true, values.isDirectory == true else { continue }
                    guard let kind = detect(url) else {
                        // Hidden directories are only traversed when a detector
                        // explicitly recognizes the directory itself as an artifact.
                        if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants() }
                        continue
                    }
                    enumerator.skipDescendants()
                    guard kinds.contains(kind), seen.insert(url.path).inserted else { continue }
                    let modified = values.contentModificationDate ?? .distantFuture
                    guard modified <= cutoff else { continue }
                    await progress(url.deletingLastPathComponent().lastPathComponent)
                    let identity = try FileIdentity(url)
                    let bytes = try DiskUsage.allocatedSize(url)
                    report.findings.append(Finding(
                        url: url, root: root, category: .projects, kind: kind, bytes: bytes,
                        modified: modified, inode: identity.inode, device: identity.device,
                        recommended: kind.recommended
                    ))
                } catch is CancellationError { throw CancellationError() }
                catch { report.warnings.append("\(url.path): \(error.localizedDescription)") }
            }
            report.warnings.append(contentsOf: traversalErrors)
        }
        report.findings.sort { $0.bytes > $1.bytes }
        return report
    }

    // MARK: Validation

    public static func validateForCleanup(_ finding: Finding, exclusions: [URL]) throws {
        if case .deleteSnapshot(let token) = finding.action {
            guard Snapshots.isValidToken(token) else { throw CleanupError.unsafePath }
            return
        }
        // Independent last-line checks: system, personal and category fences.
        try SafetyPolicy.check(finding.url, category: finding.category,
                               permanently: finding.action == .deletePermanently)
        if finding.action == .deletePermanently, finding.category != .trash { throw CleanupError.unsafePath }
        guard finding.url != finding.root,
              PathPolicy.contains(finding.root, finding.url),
              !PathPolicy.hasSymlinkComponent(finding.url),
              !PathPolicy.isProtected(finding.url, by: exclusions) else {
            throw CleanupError.unsafePath
        }
        if finding.category == .projects {
            guard let kind = finding.kind, detect(finding.url) == kind else { throw CleanupError.unsafePath }
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: finding.url.path)
        guard finding.inode != 0,
              (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == finding.inode,
              (attrs[.systemNumber] as? NSNumber)?.uint64Value == finding.device,
              attrs[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw CleanupError.changedSinceScan
        }
        // Project artifacts are quiet between builds, so any change is a signal
        // that a tool is running. System caches change constantly by design.
        if finding.category == .projects {
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  attrs[.modificationDate] as? Date == finding.modified else {
                throw CleanupError.changedSinceScan
            }
        }
    }

    /// Checks a path the user kept selected inside a partially selected finding.
    public static func validateSubpath(_ url: URL, of finding: Finding, exclusions: [URL]) throws {
        try SafetyPolicy.check(url, category: finding.category, permanently: finding.action == .deletePermanently)
        guard url != finding.url,
              PathPolicy.contains(finding.url, url),
              !PathPolicy.hasSymlinkComponent(url),
              !PathPolicy.isProtected(url, by: exclusions),
              (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else {
            throw CleanupError.unsafePath
        }
    }
}

public enum CleanupError: LocalizedError {
    case unsafePath, changedSinceScan, snapshotFailed(String)
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "This location is protected or no longer matches an approved item."
        case .changedSinceScan: "This folder changed since the scan. Scan again before cleaning."
        case .snapshotFailed(let reason): "The snapshot could not be deleted. \(reason)"
        }
    }
}

// MARK: - Disk usage

struct FileIdentity {
    let inode: UInt64
    let device: UInt64
    init(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        device = (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

public enum DiskUsage {
    /// Allocated bytes of a file or folder tree. Symbolic links are never
    /// followed and hard-linked files are counted once. In tolerant mode,
    /// unreadable descendants are skipped instead of failing the whole item.
    public static func allocatedSize(_ url: URL, tolerant: Bool = false) throws -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        if (st.st_mode & S_IFMT) == S_IFLNK { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR { return Int64(st.st_blocks) * 512 }

        var failure: Error?
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, error in
                if tolerant { return true }
                failure = error
                return false
            }
        ) else { throw CocoaError(.fileReadNoPermission) }
        var total: Int64 = 0
        var linked = Set<[UInt64]>()
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? item.resourceValues(forKeys: keys) else {
                if tolerant { continue }
                throw CocoaError(.fileReadNoPermission)
            }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            var fileStat = stat()
            if lstat(item.path, &fileStat) == 0, fileStat.st_nlink > 1 {
                guard linked.insert([UInt64(fileStat.st_dev), UInt64(fileStat.st_ino)]).inserted else { continue }
            }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        if let failure { throw failure }
        return total
    }
}
