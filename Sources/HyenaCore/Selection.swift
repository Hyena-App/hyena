import Foundation

/// One entry inside a finding, shown when the user expands it.
public struct FileEntry: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let isDirectory: Bool
    public let bytes: Int64
    public let modified: Date
    public var name: String { url.lastPathComponent }

    public init(url: URL, isDirectory: Bool, bytes: Int64, modified: Date) {
        self.url = url
        self.isDirectory = isDirectory
        self.bytes = bytes
        self.modified = modified
    }
}

public enum DirectoryInspector {
    /// Direct children with their allocated sizes, largest first. Symbolic
    /// links are left out so a selection can never reach outside the folder.
    public static func children(of url: URL) async throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
        return try await withThrowingTaskGroup(of: FileEntry?.self) { group in
            for child in urls where child.lastPathComponent != ".DS_Store" {
                group.addTask {
                    let values = try? child.resourceValues(forKeys: Set(keys))
                    guard values?.isSymbolicLink != true else { return nil }
                    let bytes = (try? DiskUsage.allocatedSize(child, tolerant: true)) ?? 0
                    return FileEntry(
                        url: child,
                        isDirectory: values?.isDirectory == true && values?.isPackage != true,
                        bytes: bytes,
                        modified: values?.contentModificationDate ?? .distantPast
                    )
                }
            }
            var entries: [FileEntry] = []
            for try await entry in group { if let entry { entries.append(entry) } }
            return entries.sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }
        }
    }
}

public enum CheckState: Sendable { case on, off, mixed }

/// Tri-state selection over findings and any folders the user has expanded.
///
/// A finding is either excluded, fully included, or included with some
/// descendants unchecked. Unchecking always happens on a loaded entry, so the
/// cleanup plan can be computed from loaded children alone: anything not
/// explicitly unchecked is cleaned, and anything never loaded follows its parent.
public struct SelectionModel: Sendable {
    public private(set) var included: Set<String> = []
    public private(set) var excluded: Set<String> = []
    public private(set) var children: [String: [FileEntry]] = [:]
    private var entryBytes: [String: Int64] = [:]

    public init() {}

    public mutating func reset(selecting findings: [Finding]) {
        included = Set(findings.map(\.id))
        excluded = []
    }

    public mutating func setChildren(_ entries: [FileEntry], of path: String) {
        children[path] = entries
        for entry in entries { entryBytes[entry.url.path] = entry.bytes }
    }

    public func isIncluded(_ finding: Finding) -> Bool { included.contains(finding.id) }

    public mutating func set(_ finding: Finding, included on: Bool) {
        let root = finding.url.path
        excluded = excluded.filter { !Self.isWithin($0, root) }
        if on { included.insert(finding.id) } else { included.remove(finding.id) }
    }

    public func state(of finding: Finding) -> CheckState { state(of: finding.url.path, in: finding) }

    public func state(of path: String, in finding: Finding) -> CheckState {
        guard included.contains(finding.id) else { return .off }
        if excluded.contains(where: { path == $0 || Self.isWithin(path, $0) }) { return .off }
        if excluded.contains(where: { Self.isStrictlyWithin($0, path) }) { return .mixed }
        return .on
    }

    public mutating func toggle(_ path: String, in finding: Finding) {
        if state(of: path, in: finding) == .on { turnOff(path, in: finding) } else { turnOn(path, in: finding) }
    }

    private mutating func turnOff(_ path: String, in finding: Finding) {
        let root = finding.url.path
        guard path != root else { return set(finding, included: false) }
        excluded = excluded.filter { !Self.isStrictlyWithin($0, path) }
        excluded.insert(path)
        collapse(from: Self.parent(of: path), in: finding)
    }

    /// When every child of a folder is unchecked, uncheck the folder itself.
    private mutating func collapse(from path: String, in finding: Finding) {
        guard let entries = children[path], !entries.isEmpty,
              entries.allSatisfy({ excluded.contains($0.url.path) }) else { return }
        if path == finding.url.path { return set(finding, included: false) }
        for entry in entries { excluded.remove(entry.url.path) }
        excluded.insert(path)
        collapse(from: Self.parent(of: path), in: finding)
    }

    private mutating func turnOn(_ path: String, in finding: Finding) {
        let root = finding.url.path
        guard path != root else { return set(finding, included: true) }
        let lineage = Self.lineage(from: root, to: path)
        if !included.contains(finding.id) {
            set(finding, included: true)
            // Keep everything except the chosen path unchecked.
            for (ancestor, next) in zip(lineage, lineage.dropFirst()) {
                for entry in children[ancestor] ?? [] where entry.url.path != next {
                    excluded.insert(entry.url.path)
                }
            }
        } else {
            for (ancestor, next) in zip(lineage, lineage.dropFirst()) where excluded.contains(ancestor) {
                excluded.remove(ancestor)
                for entry in children[ancestor] ?? [] where entry.url.path != next {
                    excluded.insert(entry.url.path)
                }
            }
        }
        excluded = excluded.filter { $0 != path && !Self.isStrictlyWithin($0, path) }
    }

    /// Estimated bytes that will be cleaned for this finding.
    public func selectedBytes(of finding: Finding) -> Int64 {
        guard included.contains(finding.id) else { return 0 }
        let root = finding.url.path
        let mine = excluded.filter { Self.isStrictlyWithin($0, root) }
        let topmost = mine.filter { path in !mine.contains { Self.isStrictlyWithin(path, $0) } }
        let kept = topmost.reduce(Int64(0)) { $0 + (entryBytes[$1] ?? 0) }
        return max(0, finding.bytes - kept)
    }

    public func isPartial(_ finding: Finding) -> Bool { state(of: finding) == .mixed }

    /// Exact paths to clean for a finding: the finding itself when fully
    /// checked, otherwise the checked parts of the expanded tree.
    public func targets(for finding: Finding) -> [URL] {
        guard included.contains(finding.id) else { return [] }
        func collect(_ path: String, isDirectory: Bool) -> [URL] {
            if excluded.contains(path) { return [] }
            guard excluded.contains(where: { Self.isStrictlyWithin($0, path) }) else {
                return [URL(fileURLWithPath: path, isDirectory: isDirectory)]
            }
            // Something below is unchecked, so this folder must have been loaded.
            return (children[path] ?? []).flatMap { collect($0.url.path, isDirectory: $0.isDirectory) }
        }
        let root = finding.url.path
        if !excluded.contains(where: { Self.isStrictlyWithin($0, root) }) { return [finding.url] }
        return (children[root] ?? []).flatMap { collect($0.url.path, isDirectory: $0.isDirectory) }
    }

    // MARK: Path helpers

    static func isWithin(_ path: String, _ ancestor: String) -> Bool {
        path == ancestor || isStrictlyWithin(path, ancestor)
    }

    static func isStrictlyWithin(_ path: String, _ ancestor: String) -> Bool {
        path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    static func parent(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// Paths from root down to (and including) target.
    static func lineage(from root: String, to target: String) -> [String] {
        var chain = [target]
        var current = target
        while current != root, isStrictlyWithin(current, root) {
            current = parent(of: current)
            chain.append(current)
        }
        return chain.reversed()
    }
}
