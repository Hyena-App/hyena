import XCTest
@testable import HyenaCore

final class IntelligenceTests: XCTestCase {
    private func finding(
        _ path: String, category: CleanupCategory = .projects, kind: ArtifactKind? = .rust,
        bytes: Int64 = 1_000_000_000, ageDays: Double = 0, recommended: Bool = true
    ) -> Finding {
        Finding(
            url: URL(fileURLWithPath: path), root: URL(fileURLWithPath: "/"), category: category, kind: kind,
            bytes: bytes, modified: Date().addingTimeInterval(-ageDays * 86_400), inode: 1, device: 1,
            recommended: recommended
        )
    }

    func testParsesAgeExclusionsAndKinds() {
        let rule = RuleParser.parse("Clean everything older than a month except my work projects")
        XCTAssertEqual(rule.olderThanDays, 30)
        XCTAssertEqual(rule.excludeKeywords, ["work"])
        XCTAssertTrue(rule.categories.isEmpty)

        let node = RuleParser.parse("remove node_modules I haven't touched in 3 months")
        XCTAssertEqual(node.kinds, [.node])
        XCTAssertEqual(node.categories, [.projects])
        XCTAssertEqual(node.olderThanDays, 90)
    }

    func testParsesSizeAndCategoriesWithWordBoundaries() {
        let rule = RuleParser.parse("only caches bigger than 500 MB")
        XCTAssertEqual(rule.largerThanBytes, 500_000_000)
        XCTAssertTrue(rule.categories.contains(.userCaches))
        XCTAssertFalse(RuleParser.parse("my blog builds").categories.contains(.logs))
        XCTAssertEqual(RuleParser.parse("xcode and package caches, but not gradle").excludeKeywords, ["gradle"])
    }

    func testRuleMatching() {
        let work = finding("/Users/me/work/api/target", ageDays: 40)
        let fun = finding("/Users/me/fun/game/target", ageDays: 40)
        let fresh = finding("/Users/me/fun/new/target", ageDays: 2)
        let review = finding("/Users/me/fun/py/.venv", kind: .pythonEnv, ageDays: 40, recommended: false)
        let rule = SelectionRule(olderThanDays: 30, excludeKeywords: ["work"])
        XCTAssertEqual([work, fun, fresh, review].filter { rule.matches($0) }.map(\.id), [fun.id])
        var withReview = rule
        withReview.includeReviewItems = true
        XCTAssertTrue(withReview.matches(review))
        XCTAssertFalse(SelectionRule(kinds: [.node]).matches(fun))
    }

    func testHabitsLearnKeepAndClean() {
        let keepMe = finding("/p/keep/target")
        let cleanMe = finding("/p/venv/.venv", kind: .pythonEnv, recommended: false)
        var book = HabitBook()
        book.record(shown: [keepMe, cleanMe], cleaned: [cleanMe.id])
        XCTAssertFalse(book.prefersKeeping(keepMe))
        book.record(shown: [keepMe, cleanMe], cleaned: [cleanMe.id])
        XCTAssertTrue(book.prefersKeeping(keepMe))
        XCTAssertTrue(book.prefersCleaning(cleanMe))
        XCTAssertEqual(Set(book.preferredSelection(for: [keepMe, cleanMe]).map(\.id)), [cleanMe.id])
        XCTAssertFalse(book.suggestsProtecting(keepMe))
        book.record(shown: [keepMe], cleaned: [])
        XCTAssertTrue(book.suggestsProtecting(keepMe))
        book.dismissSuggestion(for: keepMe)
        XCTAssertFalse(book.suggestsProtecting(keepMe))
    }

    func testInsightsReportGrowthAndStaleProjects() {
        let old = finding("/p/web/node_modules", kind: .node, bytes: 1_000_000_000)
        let baseline = ScanSnapshot(date: Date().addingTimeInterval(-7 * 86_400), findings: [old])
        let grown = finding("/p/web/node_modules", kind: .node, bytes: 3_000_000_000)
        let stale = finding("/p/legacy/target", bytes: 2_000_000_000, ageDays: 90)
        let insights = Insights.compute(findings: [grown, stale], baseline: baseline)
        let kinds = insights.map(\.kind)
        XCTAssertTrue(kinds.contains(.total))
        XCTAssertTrue(kinds.contains(.stale))
        XCTAssertTrue(insights.contains { $0.kind == .growth && $0.text.contains("node_modules in web") })
        XCTAssertEqual(Insights.baseline(in: [baseline], minimumAge: 6 * 86_400), baseline)
    }

    func testFactsDescribeKnownConsequences() {
        let facts = ItemFacts(finding: finding("/Users/me/app/target"))
        XCTAssertEqual(facts.whatHappens, ArtifactKind.rust.consequence)
        XCTAssertTrue(facts.promptDescription.contains("Rust builds"))
    }
}
