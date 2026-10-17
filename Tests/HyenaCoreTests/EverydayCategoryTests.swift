import XCTest
@testable import HyenaCore

final class EverydayCategoryTests: XCTestCase {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyenaHome-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func file(_ url: URL, bytes: Int, ageDays: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ageDays * 86_400)], ofItemAtPath: url.path)
    }

    private func scan(_ home: URL, _ categories: Set<CleanupCategory>) async throws -> ScanReport {
        try await SystemScanner.scan(
            SystemScanOptions(home: home, categories: categories, apps: AppInventory(), minimumBytes: 1),
            exclusions: []) { _ in }
    }

    func testRuntimeNames() {
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-26-2"), "iOS 26.2")
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-11-0"), "watchOS 11.0")
    }

    func testDownloadsPreselectsOldInstallersOnly() async throws {
        let home = try home()
        let downloads = home.appendingPathComponent("Downloads")
        try file(downloads.appendingPathComponent("Old.dmg"), bytes: 2_000_000, ageDays: 30)
        try file(downloads.appendingPathComponent("Fresh.pkg"), bytes: 2_000_000, ageDays: 1)
        try file(downloads.appendingPathComponent("movie.mov"), bytes: 120_000_000, ageDays: 200)
        try file(downloads.appendingPathComponent("notes.txt"), bytes: 1_000, ageDays: 200)
        let report = try await scan(home, [.downloads])
        let byName = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(byName["Old.dmg"]?.recommended, true)
        XCTAssertNil(byName["Fresh.pkg"], "Recent installers may still be in use")
        XCTAssertEqual(byName["movie.mov"]?.recommended, false, "Large old files are shown, never preselected")
        XCTAssertNil(byName["notes.txt"], "Small files are noise")
    }

    func testSimulatorsReadDevicePlistAndNeverPreselectUsableOnes() async throws {
        let home = try home()
        let device = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/ABC")
        try FileManager.default.createDirectory(at: device.appendingPathComponent("data"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: device.appendingPathComponent("data/blob"))
        let plist: [String: Any] = [
            "UDID": "ABC", "name": "iPhone 16 Pro", "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
            "state": 1, "isDeleted": false, "lastBootedAt": Date(),
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: device.appendingPathComponent("device.plist"))
        let report = try await scan(home, [.simulators])
        let finding = try XCTUnwrap(report.findings.first { $0.url.lastPathComponent == "ABC" })
        XCTAssertEqual(finding.title, "iPhone 16 Pro · iOS 18.5")
        XCTAssertFalse(finding.recommended, "A simulator that still runs holds the user's test data")
    }

    func testInstallerSuggestion() {
        let installer = Finding(
            url: URL(fileURLWithPath: "/Users/me/Downloads/Big.dmg"), root: URL(fileURLWithPath: "/Users/me/Downloads"),
            category: .downloads, bytes: 3_000_000_000, modified: Date().addingTimeInterval(-40 * 86_400),
            inode: 1, device: 1, recommended: true
        )
        let context = SuggestionContext(findings: [installer], habits: HabitBook(), baseline: nil,
                                        availableBytes: 200_000_000_000, capacityBytes: 500_000_000_000)
        XCTAssertTrue(SuggestionEngine.suggestions(context, preferences: .init()).contains { $0.kind == .installers })
    }
}
