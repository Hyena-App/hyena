import XCTest
@testable import HyenaCore

final class SuggestionTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000

    private func finding(
        _ path: String, category: CleanupCategory = .projects, kind: ArtifactKind? = .rust,
        bytes: Int64, ageDays: Double = 0, recommended: Bool = true
    ) -> Finding {
        Finding(
            url: URL(fileURLWithPath: path), root: URL(fileURLWithPath: "/"), category: category, kind: kind,
            bytes: bytes, modified: Date().addingTimeInterval(-ageDays * 86_400), inode: 1, device: 1,
            recommended: recommended
        )
    }

    private func context(_ findings: [Finding], habits: HabitBook = HabitBook(), baseline: ScanSnapshot? = nil,
                         available: Int64 = 200_000_000_000) -> SuggestionContext {
        SuggestionContext(findings: findings, habits: habits, baseline: baseline,
                          availableBytes: available, capacityBytes: 500_000_000_000)
    }

    func testSuggestsStaleProjectsBigCachesAndLowDiskFirst() {
        let stale = finding("/p/old/target", bytes: 3 * gb, ageDays: 90)
        let fresh = finding("/p/new/target", bytes: 3 * gb, ageDays: 1)
        let npm = finding("/Users/me/.npm/_cacache", category: .packageCaches, kind: nil, bytes: 20 * gb)
        let all = SuggestionEngine.suggestions(context([stale, fresh, npm]), preferences: .init())
        XCTAssertEqual(Set(all.map(\.kind)), [.staleProjects, .bigCache])
        XCTAssertEqual(all.first { $0.kind == .staleProjects }?.action, .select([stale.id]))

        let low = SuggestionEngine.suggestions(context([stale, npm], available: 20 * gb), preferences: .init())
        XCTAssertEqual(low.first?.kind, .lowDisk)
    }

    func testRespectsHabitsSnoozesAndMutes() {
        let npm = finding("/Users/me/.npm/_cacache", category: .packageCaches, kind: nil, bytes: 20 * gb)
        var habits = HabitBook()
        habits.record(shown: [npm], cleaned: [])
        habits.record(shown: [npm], cleaned: [])
        XCTAssertTrue(SuggestionEngine.suggestions(context([npm], habits: habits), preferences: .init())
            .allSatisfy { $0.kind != .bigCache }, "Habitually kept items aren't suggested")

        var prefs = SuggestionPreferences()
        let first = try! XCTUnwrap(SuggestionEngine.suggestions(context([npm]), preferences: prefs).first)
        prefs.snooze(first)
        XCTAssertTrue(SuggestionEngine.suggestions(context([npm]), preferences: prefs).isEmpty)
        XCTAssertFalse(prefs.allows(first, now: Date().addingTimeInterval(8 * 86_400)) == false)

        prefs = SuggestionPreferences()
        prefs.muted = [.bigCache]
        XCTAssertTrue(SuggestionEngine.suggestions(context([npm]), preferences: prefs).isEmpty)
    }

    func testDismissingBacksOffAndLowersRank() {
        let suggestion = Suggestion(id: "x", kind: .growth, title: "", detail: "", bytes: 0, action: .emptyTrash, priority: 1)
        var prefs = SuggestionPreferences()
        let now = Date()
        prefs.snooze(suggestion, now: now)
        prefs.snooze(suggestion, now: now)
        XCTAssertFalse(prefs.allows(suggestion, now: now.addingTimeInterval(10 * 86_400)), "Second dismissal snoozes 14 days")
        XCTAssertLessThan(prefs.affinity(for: .growth), prefs.affinity(for: .trash))
        prefs.recordAccepted(Suggestion(id: "y", kind: .trash, title: "", detail: "", bytes: 0, action: .emptyTrash, priority: 1))
        XCTAssertGreaterThan(prefs.affinity(for: .trash), 0.5)
    }

    func testGrowthAndHabitualSuggestions() {
        let before = finding("/Users/me/.gradle/caches", category: .packageCaches, kind: nil, bytes: 1 * gb)
        let baseline = ScanSnapshot(date: Date().addingTimeInterval(-7 * 86_400), findings: [before])
        let after = finding("/Users/me/.gradle/caches", category: .packageCaches, kind: nil, bytes: 4 * gb)
        let growth = SuggestionEngine.suggestions(context([after], baseline: baseline), preferences: .init())
        XCTAssertTrue(growth.contains { $0.kind == .growth && $0.title.contains("grew") })

        let logs = finding("/Users/me/Library/Logs/app", category: .logs, kind: nil, bytes: gb)
        var habits = HabitBook()
        habits.record(shown: [logs], cleaned: [logs.id])
        habits.record(shown: [logs], cleaned: [logs.id])
        XCTAssertTrue(SuggestionEngine.suggestions(context([logs], habits: habits), preferences: .init())
            .contains { $0.kind == .habitual })
    }
}
