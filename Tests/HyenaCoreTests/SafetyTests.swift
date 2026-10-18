import XCTest
@testable import HyenaCore

/// The guardrails that keep Hyena from harming the system or personal data.
final class SafetyTests: XCTestCase {
    private var originalHome: URL!
    private let home = URL(fileURLWithPath: "/Users/tester")

    override func setUp() {
        originalHome = SafetyPolicy.home
        SafetyPolicy.home = home
    }

    override func tearDown() { SafetyPolicy.home = originalHome }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path.hasPrefix("/") ? path : home.path + "/" + path)
    }

    private func refuses(_ path: String, _ category: CleanupCategory, permanently: Bool = false,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SafetyPolicy.check(url(path), category: category, permanently: permanently),
                             "\(path) should be refused for \(category)", file: file, line: line)
    }

    private func allows(_ path: String, _ category: CleanupCategory, permanently: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try SafetyPolicy.check(url(path), category: category, permanently: permanently),
                         "\(path) should be allowed for \(category)", file: file, line: line)
    }

    func testSystemLocationsAreNeverTouched() {
        for path in ["/", "/System/Library/Caches/x", "/Library/Caches/com.apple.x", "/Applications/Safari.app",
                     "/usr/local/lib/node_modules", "/private/var/db/x", "/etc/hosts", "/bin/zsh", "/opt/homebrew/Cellar"] {
            for category in CleanupCategory.allCases where category != .snapshots { refuses(path, category) }
        }
    }

    func testHomeAndItsAncestorsAreNeverRemoved() {
        for category in CleanupCategory.allCases where category != .snapshots {
            refuses("/Users/tester", category)
            refuses("/Users", category)
            refuses("/Users/someone-else/Library/Caches/x", category)
        }
    }

    func testCredentialsAndAppDataAreOffLimitsToEveryCategory() {
        for path in ["Library/Keychains/login.keychain-db", "Library/Preferences/com.apple.finder.plist",
                     "Library/Mail/V10", "Library/Messages/chat.db", "Library/Containers/com.apple.Notes",
                     "Library/Group Containers/group.com.apple.notes", ".ssh/id_ed25519", ".aws/credentials",
                     "Library/Application Support/AddressBook"] {
            for category in CleanupCategory.allCases where category != .snapshots { refuses(path, category) }
        }
    }

    func testPersonalFoldersAreOffLimitsExceptForProjectBuilds() {
        refuses("Documents/taxes.pdf", .downloads)
        refuses("Desktop/notes", .userCaches)
        refuses("Library/Mobile Documents/com~apple~CloudDocs/x", .appLeftovers)
        refuses("Library/CloudStorage/Dropbox/x", .userCaches)
        allows("Documents/projects/app/node_modules", .projects)
        refuses("Documents", .projects)
        refuses("Library", .projects)
    }

    func testEachCategoryStaysInsideItsOwnFolders() {
        allows("Library/Caches/com.spotify.client", .userCaches)
        refuses("Library/Caches", .userCaches)                      // the folder itself
        refuses("Library/Logs/x", .userCaches)                       // another category's folder
        allows("Library/Logs/DiagnosticReports", .logs)
        allows("Library/Application Support/Code/CachedData", .appSupportCaches)
        refuses("Library/Application Support", .appLeftovers)
        allows("Downloads/Xcode.xip", .downloads)
        refuses("Downloads", .downloads)
        refuses("Library/Caches/x", .downloads)
        allows("Library/Application Support/MobileSync/Backup/00008110", .devices)
        allows(".Trash/old", .trash, permanently: true)
        refuses("Library/Caches/x", .trash, permanently: true)
        allows("Library/Developer/Xcode/DerivedData/App-abc", .xcode)
        allows("Library/Developer/XCTestDevices", .xcode)
        refuses("Library/Developer/CoreSimulator/Devices/ABC", .xcode)
        allows("Library/Developer/CoreSimulator/Devices/ABC", .simulators)
        allows(".npm/_cacache", .packageCaches)
        refuses(".npm", .packageCaches)
    }

    func testPermanentDeletionOnlyWhereItRegenerates() {
        allows("Library/Caches/x", .userCaches, permanently: true)
        allows("Developer/app/target", .projects, permanently: true)
        refuses("Downloads/movie.mov", .downloads, permanently: true)
        refuses("Library/Application Support/MobileSync/Backup/00008110", .devices, permanently: true)
        refuses("Library/Application Support/Sketch", .appLeftovers, permanently: true)
        XCTAssertFalse(SafetyPolicy.allowsImmediateDeletion(.devices))
        XCTAssertTrue(SafetyPolicy.allowsImmediateDeletion(.packageCaches))
    }

    func testTraversalAndAliasesCannotEscape() {
        refuses("Library/Caches/../../Documents", .userCaches)
        refuses("/tmp/../etc/passwd", .projects)
        refuses("/var/db/x", .projects)
    }

    func testFoldersHoldingARepositoryAreRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HyenaSafety-" + UUID().uuidString)
        let repo = root.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try SafetyPolicy.check(repo, category: .projects)) { error in
            XCTAssertEqual(error as? SafetyViolation, .repository(SafetyPolicy.normalized(repo)))
        }
    }

    func testExecutorSendsBackupsToTrashEvenWhenDeletingImmediately() {
        SafetyPolicy.home = originalHome
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("HyenaExec-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        SafetyPolicy.home = fixture
        let backups = fixture.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let backup = backups.appendingPathComponent("DEVICE")
        try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        let attrs = try? FileManager.default.attributesOfItem(atPath: backup.path)
        let finding = Finding(
            url: backup, root: backups, category: .devices, bytes: 10, modified: Date(),
            inode: (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            device: (attrs?[.systemNumber] as? NSNumber)?.uint64Value ?? 0, recommended: false
        )
        let trashed = LockedSet(), deleted = LockedSet()
        let outcome = CleanupExecutor.execute(
            [CleanupPlan(finding: finding, targets: [backup], bytes: 10, deleteImmediately: true)], exclusions: [],
            handlers: CleanupHandlers(moveToTrash: { trashed.insert($0) }, deletePermanently: { deleted.insert($0) },
                                      deleteSnapshot: { _ in })
        )
        XCTAssertEqual(trashed.values.count, 1)
        XCTAssertTrue(deleted.values.isEmpty)
        XCTAssertEqual(outcome.movedBytes, 10)
    }
}
