import XCTest
@testable import HyenaCore

final class ScannerTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyenaTests-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func artifact(_ root: URL, project: String = "project", name: String = "target", marker: String = "Cargo.toml") throws -> URL {
        let folder = root.appendingPathComponent(project).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folder.deletingLastPathComponent().appendingPathComponent(marker))
        try Data(repeating: 1, count: 8192).write(to: folder.appendingPathComponent("artifact.bin"))
        return folder
    }

    private func scan(_ root: URL, exclusions: [URL] = [], kinds: Set<ArtifactKind> = Set(ArtifactKind.allCases), age: Int = 0) async throws -> ScanReport {
        try await Scanner.scan(roots: [root], exclusions: exclusions, kinds: kinds, minimumAgeDays: age) { _ in }
    }

    private func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    func testContainsHonorsPathBoundary() {
        let root = URL(fileURLWithPath: "/Projects/app")
        XCTAssertTrue(PathPolicy.contains(root, root.appendingPathComponent("target")))
        XCTAssertFalse(PathPolicy.contains(root, URL(fileURLWithPath: "/Projects/application/target")))
        XCTAssertTrue(PathPolicy.contains(URL(fileURLWithPath: "/"), root))
    }

    func testProtectedChildProtectsWholeArtifact() {
        let target = URL(fileURLWithPath: "/Projects/app/target")
        XCTAssertTrue(PathPolicy.isProtected(target, by: [target.appendingPathComponent("precious")]))
        XCTAssertFalse(PathPolicy.isProtected(target, by: [URL(fileURLWithPath: "/Projects/other")]))
    }

    func testRecognizesRustAndNodeButNotArbitraryNames() async throws {
        let root = try fixture()
        let rust = try artifact(root)
        let node = try artifact(root, project: "web", name: "node_modules", marker: "package.json")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("unknown/target"), withIntermediateDirectories: true)
        let report = try await scan(root)
        XCTAssertEqual(Set(report.findings.map { canonical($0.url) }), Set([canonical(rust), canonical(node)]))
        XCTAssertTrue(report.findings.allSatisfy { $0.bytes > 0 })
        XCTAssertTrue(report.warnings.isEmpty)
    }

    func testDetectsPythonAndBuildOutputsAcrossLanguages() async throws {
        let root = try fixture()
        let fm = FileManager.default

        func makeFolder(_ project: String, _ name: String, marker: String? = nil) throws -> URL {
            let projectURL = root.appendingPathComponent(project)
            try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
            if let marker {
                try Data().write(to: projectURL.appendingPathComponent(marker))
            }
            let folder = projectURL.appendingPathComponent(name)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 256).write(to: folder.appendingPathComponent("output.bin"))
            return folder
        }

        for name in ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"] {
            _ = try makeFolder("python", name)
        }
        _ = try makeFolder("swift", ".build", marker: "Package.swift")
        _ = try makeFolder("maven", "target", marker: "pom.xml")
        _ = try makeFolder("gradle", "build", marker: "build.gradle.kts")
        let cmake = try makeFolder("cmake", "cmake-build-debug")
        try Data().write(to: cmake.appendingPathComponent("CMakeCache.txt"))
        let dotnetProject = root.appendingPathComponent("dotnet")
        try fm.createDirectory(at: dotnetProject, withIntermediateDirectories: true)
        try Data().write(to: dotnetProject.appendingPathComponent("App.csproj"))
        for name in ["bin", "obj"] {
            let folder = dotnetProject.appendingPathComponent(name)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 256).write(to: folder.appendingPathComponent("output.bin"))
        }

        let report = try await scan(root)
        XCTAssertEqual(report.findings.count, 10)
        XCTAssertEqual(
            Set(report.findings.map(\.kind)),
            Set([.python, .swift, .maven, .gradle, .cmake, .dotnet])
        )
    }

    func testAmbiguousBuildFoldersNeedProjectMarkers() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("unmarked")
        for name in ["target", "build", ".build", "bin", "obj"] {
            try FileManager.default.createDirectory(
                at: project.appendingPathComponent(name), withIntermediateDirectories: true
            )
        }

        let report = try await scan(root)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testDoesNotRecognizeArbitraryDerivedData() throws {
        let root = try fixture()
        let folder = root.appendingPathComponent("DerivedData")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(Scanner.detect(folder))
    }

    func testExclusionDoesNotHideSiblingProjects() async throws {
        let root = try fixture()
        let protected = try artifact(root, project: "keep")
        let other = try artifact(root, project: "clean")
        let report = try await scan(root, exclusions: [protected.deletingLastPathComponent()])
        XCTAssertEqual(report.findings.map { canonical($0.url) }, [canonical(other)])
    }

    func testProtectedChildExcludesArtifact() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await scan(root, exclusions: [target.appendingPathComponent("artifact.bin")])
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testCategoryPreference() async throws {
        let root = try fixture()
        try artifact(root)
        let report = try await scan(root, kinds: [.node])
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testAgePreference() async throws {
        let root = try fixture()
        let folder = try artifact(root)
        let recent = try await scan(root, age: 7)
        XCTAssertTrue(recent.findings.isEmpty)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86_400)], ofItemAtPath: folder.path)
        let old = try await scan(root, age: 7)
        XCTAssertEqual(old.findings.count, 1)
    }

    func testSkipsSymlinkArtifacts() async throws {
        let root = try fixture()
        let outside = try fixture()
        let target = try artifact(outside)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent("Cargo.toml"))
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("target"), withDestinationURL: target)
        let report = try await scan(root)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testOverlappingRootsDoNotDuplicateArtifacts() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await Scanner.scan(roots: [root, target.deletingLastPathComponent()], exclusions: [], kinds: [.rust], minimumAgeDays: 0) { _ in }
        XCTAssertEqual(report.findings.count, 1)
    }

    func testValidArtifactPassesCleanupValidationWithoutDeleting() async throws {
        let root = try fixture()
        try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertNoThrow(try Scanner.validateForCleanup(finding, exclusions: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finding.url.path))
    }

    func testNewProtectionBlocksCleanup() async throws {
        let root = try fixture()
        try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertThrowsError(try Scanner.validateForCleanup(finding, exclusions: [root]))
    }

    func testChangedFolderBlocksCleanup() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: target.path)
        XCTAssertThrowsError(try Scanner.validateForCleanup(finding, exclusions: []))
    }

    func testSymlinkReplacementBlocksCleanup() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        let relocated = target.deletingLastPathComponent().appendingPathComponent("moved-target")
        try FileManager.default.moveItem(at: target, to: relocated)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: relocated)
        XCTAssertThrowsError(try Scanner.validateForCleanup(finding, exclusions: []))
    }

    func testArtifactRootRequiresParentSelection() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await scan(target)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.warnings.count, 1)
    }

    func testMissingRootIsReportedAsWarning() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyenaMissing-" + UUID().uuidString)
        let report = try await scan(missing)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains(missing.path))
    }

    func testCancellationDuringProgressStopsScan() async throws {
        let root = try fixture()
        _ = try artifact(root)

        do {
            _ = try await Scanner.scan(
                roots: [root], exclusions: [], kinds: Set(ArtifactKind.allCases), minimumAgeDays: 0
            ) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
            XCTFail("Expected the scan to stop after cancellation")
        } catch is CancellationError {
            // Expected: cancellation is observed before directory traversal begins.
        } catch {
            XCTFail("Unexpected scan error: \(error)")
        }
    }

    func testCleanupContinuesAfterOneMoveFails() async throws {
        let root = try fixture()
        let first = try artifact(root, project: "first")
        let second = try artifact(root, project: "second")
        let report = try await scan(root, kinds: [.rust])
        XCTAssertEqual(report.findings.count, 2)

        let failedURL = canonical(first)
        let attempted = LockedSet()
        let outcome = CleanupExecutor.execute(report.findings, exclusions: []) { url in
            let path = url.resolvingSymlinksInPath().standardizedFileURL
            attempted.insert(path)
            if path == failedURL {
                throw CocoaError(.fileWriteNoPermission)
            }
        }

        let successfulFinding = try XCTUnwrap(report.findings.first { canonical($0.url) == canonical(second) })
        let failedFinding = try XCTUnwrap(report.findings.first { canonical($0.url) == failedURL })
        XCTAssertEqual(attempted.values, Set([canonical(first), canonical(second)]))
        XCTAssertEqual(outcome.movedIDs, [successfulFinding.id])
        XCTAssertEqual(outcome.movedBytes, successfulFinding.bytes)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].contains(failedFinding.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testDetectsNewEcosystemsOnlyWithMarkers() async throws {
        let root = try fixture()
        try artifact(root, project: "next", name: ".next", marker: "package.json")
        try artifact(root, project: "flutter", name: ".dart_tool", marker: "pubspec.yaml")
        try artifact(root, project: "elixir", name: "_build", marker: "mix.exs")
        try artifact(root, project: "zig", name: "zig-out", marker: "build.zig")
        try artifact(root, project: "pods", name: "Pods", marker: "Podfile")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plain/build"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plain/.next"), withIntermediateDirectories: true)
        let report = try await scan(root)
        XCTAssertEqual(Set(report.findings.compactMap(\.kind)), [.web, .dart, .elixir, .zig, .cocoapods])
        XCTAssertFalse(report.findings.first { $0.kind == .cocoapods }!.recommended)
    }

    func testVirtualEnvironmentNeedsPyvenvConfig() throws {
        let root = try fixture()
        let venv = root.appendingPathComponent("app/.venv")
        try FileManager.default.createDirectory(at: venv, withIntermediateDirectories: true)
        XCTAssertNil(Scanner.detect(venv))
        try Data().write(to: venv.appendingPathComponent("pyvenv.cfg"))
        XCTAssertEqual(Scanner.detect(venv), .pythonEnv)
    }

    func testPartialSelectionTargetsOnlyCheckedChildren() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let keep = target.appendingPathComponent("keep")
        let drop = target.appendingPathComponent("drop")
        for folder in [keep, drop] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("f.bin"))
        }
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        var selection = SelectionModel()
        selection.reset(selecting: [finding])
        XCTAssertEqual(selection.targets(for: finding), [finding.url])

        let entries = try await DirectoryInspector.children(of: finding.url)
        selection.setChildren(entries, of: finding.url.path)
        let keepPath = finding.url.appendingPathComponent("keep").path
        selection.toggle(keepPath, in: finding)
        XCTAssertEqual(selection.state(of: finding), .mixed)
        XCTAssertEqual(selection.state(of: keepPath, in: finding), .off)
        let targets = Set(selection.targets(for: finding).map(\.lastPathComponent))
        XCTAssertEqual(targets, ["drop", "artifact.bin"])
        XCTAssertLessThan(selection.selectedBytes(of: finding), finding.bytes)

        // Unchecking every child unchecks the finding itself.
        for entry in entries where entry.url.path != keepPath { selection.toggle(entry.url.path, in: finding) }
        XCTAssertEqual(selection.state(of: finding), .off)

        // Checking one child of an unchecked finding selects only that child.
        selection.toggle(keepPath, in: finding)
        XCTAssertEqual(selection.state(of: finding), .mixed)
        XCTAssertEqual(selection.targets(for: finding).map(\.lastPathComponent), ["keep"])
    }

    func testPartialCleanupMovesOnlyTargets() async throws {
        let root = try fixture()
        let target = try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        let file = finding.url.appendingPathComponent("artifact.bin")
        let moved = LockedSet()
        let outcome = CleanupExecutor.execute(
            [CleanupPlan(finding: finding, targets: [file], bytes: 1)], exclusions: [],
            handlers: CleanupHandlers(moveToTrash: { moved.insert($0) }, deletePermanently: { _ in XCTFail() },
                                      deleteSnapshot: { _ in XCTFail() })
        )
        XCTAssertEqual(moved.values, [file])
        XCTAssertEqual(outcome.movedIDs, [finding.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testSubpathOutsideFindingIsRejected() async throws {
        let root = try fixture()
        try artifact(root)
        let report = try await scan(root)
        let finding = try XCTUnwrap(report.findings.first)
        let outside = finding.url.deletingLastPathComponent().appendingPathComponent("Cargo.toml")
        XCTAssertThrowsError(try Scanner.validateSubpath(outside, of: finding, exclusions: []))
    }

    func testSnapshotParsingAcceptsOnlyTimeMachineTokens() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-15-120000.local
        com.apple.TimeMachine.2026-10-16-093015.local
        com.bombich.ccc.2026-10-16
        com.apple.TimeMachine.2026-10-16; rm -rf ~.local
        """
        XCTAssertEqual(Snapshots.parse(output).map(\.token), ["2026-10-15-120000", "2026-10-16-093015"])
        XCTAssertFalse(Snapshots.isValidToken("2026-10-16; rm -rf ~"))
    }

    func testSystemScanFindsCachesAndFlagsRunningApps() async throws {
        let home = try fixture()
        let caches = home.appendingPathComponent("Library/Caches")
        for name in ["com.example.Editor", "com.example.Idle", "Homebrew"] {
            let folder = caches.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 300_000).write(to: folder.appendingPathComponent("blob"))
        }
        let options = SystemScanOptions(
            home: home, categories: [.userCaches, .packageCaches],
            apps: AppInventory(runningBundleIDs: ["com.example.Editor"]), minimumBytes: 1
        )
        let report = try await SystemScanner.scan(options, exclusions: []) { _ in }
        let byName = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(byName["com.example.Editor"]?.recommended, false)
        XCTAssertEqual(byName["com.example.Idle"]?.recommended, true)
        XCTAssertEqual(byName["Homebrew"]?.category, .packageCaches)
        XCTAssertNoThrow(try Scanner.validateForCleanup(byName["com.example.Idle"]!, exclusions: []))
    }
}

final class LockedSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Set<URL>()
    func insert(_ url: URL) { lock.withLock { _ = storage.insert(url) } }
    var values: Set<URL> { lock.withLock { storage } }
}
