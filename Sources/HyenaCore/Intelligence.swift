import Foundation

// Deterministic building blocks behind Hyena's assistant features. The
// on-device model (when available) only explains, summarizes and drafts
// rules; these types decide what actually gets selected.

// MARK: - Selection rules ("Ask Hyena")

/// A structured, reviewable description of what to select.
public struct SelectionRule: Codable, Equatable, Sendable {
    /// Empty means every category.
    public var categories: Set<CleanupCategory> = []
    /// Empty means every project kind. Only applies to project builds.
    public var kinds: Set<ArtifactKind> = []
    public var olderThanDays: Int?
    public var largerThanBytes: Int64?
    /// Items whose name or path contains any of these are skipped.
    public var excludeKeywords: [String] = []
    /// When set, only items whose name or path contains one of these match.
    public var includeKeywords: [String] = []
    /// Whether items Hyena marks "Review" may be selected.
    public var includeReviewItems = false

    public init(
        categories: Set<CleanupCategory> = [], kinds: Set<ArtifactKind> = [], olderThanDays: Int? = nil,
        largerThanBytes: Int64? = nil, excludeKeywords: [String] = [], includeKeywords: [String] = [],
        includeReviewItems: Bool = false
    ) {
        self.categories = categories
        self.kinds = kinds
        self.olderThanDays = olderThanDays
        self.largerThanBytes = largerThanBytes
        self.excludeKeywords = excludeKeywords
        self.includeKeywords = includeKeywords
        self.includeReviewItems = includeReviewItems
    }

    public var isEmpty: Bool { self == SelectionRule() }

    public func matches(_ finding: Finding, now: Date = Date()) -> Bool {
        if !categories.isEmpty && !categories.contains(finding.category) { return false }
        if !kinds.isEmpty {
            guard let kind = finding.kind, kinds.contains(kind) else { return false }
        }
        if !includeReviewItems && !finding.recommended { return false }
        if let days = olderThanDays, days > 0,
           finding.modified > now.addingTimeInterval(-Double(days) * 86_400) { return false }
        if let bytes = largerThanBytes, finding.hasKnownSize, finding.bytes < bytes { return false }
        let haystack = (finding.title + " " + finding.url.path).lowercased()
        if excludeKeywords.contains(where: { haystack.contains($0.lowercased()) }) { return false }
        if !includeKeywords.isEmpty && !includeKeywords.contains(where: { haystack.contains($0.lowercased()) }) {
            return false
        }
        return true
    }

    /// Human-readable chips describing the rule.
    public var summary: [String] {
        var parts: [String] = []
        parts.append(categories.isEmpty ? "All categories"
                     : CleanupCategory.allCases.filter(categories.contains).map(\.title).joined(separator: ", "))
        if !kinds.isEmpty {
            parts.append(ArtifactKind.allCases.filter(kinds.contains).map(\.shortTitle).joined(separator: ", "))
        }
        if let days = olderThanDays, days > 0 { parts.append("Untouched \(Self.describe(days: days))") }
        if let bytes = largerThanBytes, bytes > 0 {
            parts.append("Larger than \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
        }
        if !includeKeywords.isEmpty { parts.append("Only “\(includeKeywords.joined(separator: "”, “"))”") }
        if !excludeKeywords.isEmpty { parts.append("Except “\(excludeKeywords.joined(separator: "”, “"))”") }
        if includeReviewItems { parts.append("Including Review items") }
        return parts
    }

    static func describe(days: Int) -> String {
        if days % 365 == 0 { return days == 365 ? "for a year" : "for \(days / 365) years" }
        if days % 30 == 0 { return days == 30 ? "for a month" : "for \(days / 30) months" }
        if days % 7 == 0 { return days == 7 ? "for a week" : "for \(days / 7) weeks" }
        return "for \(days) days"
    }
}

/// Understands everyday requests without a language model, so "Ask Hyena"
/// works on every Mac. The on-device model, when present, drafts richer rules.
public enum RuleParser {
    static let categoryWords: [(String, [CleanupCategory])] = [
        ("application support", [.appSupportCaches]), ("app support", [.appSupportCaches]),
        ("package cache", [.packageCaches]), ("package manager", [.packageCaches]),
        ("deriveddata", [.xcode]), ("derived data", [.xcode]), ("simulator", [.xcode]), ("xcode", [.xcode]),
        ("leftover", [.appLeftovers]), ("uninstalled", [.appLeftovers]),
        ("snapshot", [.snapshots]), ("time machine", [.snapshots]),
        ("trash", [.trash]),
        ("log", [.logs]),
        ("dependenc", [.projects]), ("build", [.projects]), ("project", [.projects]),
        ("cache", [.userCaches, .packageCaches, .appSupportCaches]),
    ]

    static let kindWords: [(String, ArtifactKind)] = [
        ("rust", .rust), ("cargo target", .rust), ("node_modules", .node), ("node", .node), ("npm deps", .node),
        ("javascript", .node), ("typescript", .node), ("js", .node), ("ts", .node), ("virtualenv", .pythonEnv), ("venv", .pythonEnv),
        ("virtual env", .pythonEnv), ("python", .python), ("swiftpm", .swift), ("swift", .swift),
        ("maven", .maven), ("gradle", .gradle), ("android", .gradle), ("cmake", .cmake), ("c++", .cmake),
        (".net", .dotnet), ("dotnet", .dotnet), ("c#", .dotnet), ("next.js", .web), ("nextjs", .web),
        ("nuxt", .web), ("svelte", .web), ("turbo", .web), ("angular", .web), ("elixir", .elixir),
        ("flutter", .dart), ("dart", .dart), ("zig", .zig), ("haskell", .haskell), ("terraform", .terraform),
        ("cocoapods", .cocoapods), ("pods", .cocoapods), ("ruby", .ruby), ("gems", .ruby), ("php", .php),
        ("composer", .php),
    ]

    static let stopWords: Set<String> = [
        "my", "the", "a", "an", "any", "all", "of", "in", "projects", "project", "folders", "folder", "files",
        "file", "stuff", "ones", "things", "repo", "repos", "directory", "directories",
    ]

    public static func parse(_ text: String) -> SelectionRule {
        var rule = SelectionRule()
        var request = text.lowercased()

        // "except/but not/excluding X" → exclusions; parse and remove first.
        let exceptPattern = #"(?:except(?: for)?|but not|excluding|apart from|other than|not touching)\s+([^,.;]+)"#
        for match in matches(exceptPattern, in: request) {
            rule.excludeKeywords += keywords(from: match)
        }
        request = request.replacingOccurrences(of: exceptPattern, with: " ", options: .regularExpression)

        // "only in X" / "inside X" / "in folder X" → inclusions.
        let onlyPattern = #"(?:only (?:in|inside|under|for)|inside|under the folder|in the folder)\s+([^,.;]+)"#
        for match in matches(onlyPattern, in: request) {
            rule.includeKeywords += keywords(from: match)
        }

        if let days = ageInDays(request) { rule.olderThanDays = days }
        if let bytes = minimumSize(request) { rule.largerThanBytes = bytes }

        let mentionsKind = kindWords.contains { mentions($0.0, in: request) }
        for (word, kind) in kindWords where mentions(word, in: request) { rule.kinds.insert(kind) }
        if mentionsKind { rule.categories.insert(.projects) }
        for (word, categories) in categoryWords where mentions(word, in: request) {
            // "build cache" means caches, not project builds.
            if word == "build" && request.contains("build cache") { continue }
            rule.categories.formUnion(categories)
        }
        if mentions("everything", in: request) || request.contains("all of it") { rule.categories = [] }
        rule.includeReviewItems = ["including review", "even risky", "review items too"].contains { request.contains($0) }
        return rule
    }

    /// Matches a word at a word start, so "log" finds "logs" but not "blog".
    static func mentions(_ word: String, in text: String) -> Bool {
        let pattern = "(?<![a-z0-9_])" + NSRegularExpression.escapedPattern(for: word)
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func ageInDays(_ text: String) -> Int? {
        let pattern = #"(?:older than|not (?:touched|used|modified|opened|changed)(?: in| for)?|untouched(?: for| in)?|over|more than|stale for|unused for|haven'?t (?:touched|used|opened)(?: in| for)?)\s+(a|an|one|two|three|four|six|\d+)?\s*(day|week|month|year)s?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            if text.contains("last year") { return 365 }
            if text.contains("last month") || text.contains("a month old") { return 30 }
            return nil
        }
        let numberText = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? "1"
        let unit = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? "day"
        let words = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "six": 6]
        let number = Int(numberText) ?? words[numberText] ?? 1
        let multiplier = ["day": 1, "week": 7, "month": 30, "year": 365][unit] ?? 1
        return number * multiplier
    }

    static func minimumSize(_ text: String) -> Int64? {
        let pattern = #"(?:bigger|larger|more|over|greater|above)\s+(?:than\s+)?(\d+(?:\.\d+)?)\s*(gb|mb|g|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numberRange]) else { return nil }
        let unit = text[unitRange].hasPrefix("g") ? 1_000_000_000.0 : 1_000_000.0
        return Int64(number * unit)
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func keywords(from phrase: String) -> [String] {
        phrase.components(separatedBy: CharacterSet(charactersIn: " /"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
            .filter { $0.count >= 2 && !stopWords.contains($0) && $0 != "and" && $0 != "or" }
    }
}

// MARK: - Habits

public struct Habit: Codable, Equatable, Sendable {
    public var kept = 0
    public var cleaned = 0
    public var lastSeen = Date.distantPast
    public var suggestionDismissed = false

    public init(kept: Int = 0, cleaned: Int = 0) {
        self.kept = kept
        self.cleaned = cleaned
    }
}

/// Learns which items the user keeps or cleans, so selections improve over time.
public struct HabitBook: Codable, Equatable, Sendable {
    public private(set) var habits: [String: Habit] = [:]

    public init() {}

    public static func key(for finding: Finding) -> String? {
        if case .deleteSnapshot = finding.action { return nil }
        if finding.category == .trash { return nil }
        return finding.category.rawValue + ":" + finding.url.path
    }

    /// Records one cleanup: every finding shown, and whether it was cleaned.
    public mutating func record(shown findings: [Finding], cleaned ids: Set<String>, at date: Date = Date()) {
        for finding in findings {
            guard let key = Self.key(for: finding) else { continue }
            var habit = habits[key] ?? Habit()
            if ids.contains(finding.id) { habit.cleaned += 1 } else if finding.recommended { habit.kept += 1 }
            habit.lastSeen = date
            habits[key] = habit
        }
        // Forget items not seen for six months so the book stays small.
        let cutoff = date.addingTimeInterval(-180 * 86_400)
        habits = habits.filter { $0.value.lastSeen >= cutoff }
    }

    /// The user keeps choosing to keep this recommended item.
    public func prefersKeeping(_ finding: Finding) -> Bool {
        guard finding.recommended, let key = Self.key(for: finding), let habit = habits[key] else { return false }
        return habit.kept >= 2 && habit.cleaned == 0
    }

    /// The user keeps cleaning this item even though Hyena marks it for review.
    public func prefersCleaning(_ finding: Finding) -> Bool {
        guard !finding.recommended, let key = Self.key(for: finding), let habit = habits[key] else { return false }
        return habit.cleaned >= 2 && habit.kept == 0
    }

    /// Kept three or more times and never cleaned: worth protecting outright.
    public func suggestsProtecting(_ finding: Finding) -> Bool {
        guard let key = Self.key(for: finding), let habit = habits[key] else { return false }
        return habit.kept >= 3 && habit.cleaned == 0 && !habit.suggestionDismissed
    }

    public mutating func dismissSuggestion(for finding: Finding) {
        guard let key = Self.key(for: finding) else { return }
        habits[key, default: Habit()].suggestionDismissed = true
    }

    /// Recommended selection adjusted by what the user usually does.
    public func preferredSelection(for findings: [Finding]) -> [Finding] {
        findings.filter { ($0.recommended && !prefersKeeping($0)) || prefersCleaning($0) }
    }

    public var isEmpty: Bool { habits.isEmpty }
}

// MARK: - Growth & insights

public struct ScanSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var categoryBytes: [String: Int64]
    /// Largest items by id, to spot what grew.
    public var itemBytes: [String: Int64]
    public var itemTitles: [String: String]

    public init(date: Date = Date(), findings: [Finding], limit: Int = 200) {
        self.date = date
        var categories: [String: Int64] = [:]
        for finding in findings { categories[finding.category.rawValue, default: 0] += finding.bytes }
        categoryBytes = categories
        let top = findings.sorted { $0.bytes > $1.bytes }.prefix(limit)
        itemBytes = Dictionary(top.map { ($0.id, $0.bytes) }, uniquingKeysWith: max)
        itemTitles = Dictionary(top.map { ($0.id, Insights.label(for: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    public var total: Int64 { categoryBytes.values.reduce(0, +) }
}

public struct Insight: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case growth, stale, largest, trash, total }
    public var id: String { kind.rawValue + text }
    public let kind: Kind
    public let text: String
    public let bytes: Int64
}

public enum Insights {
    public static let staleDays = 60
    static let meaningfulBytes: Int64 = 500_000_000

    /// The most recent snapshot at least `minimumAge` older than now, else the oldest.
    public static func baseline(in history: [ScanSnapshot], now: Date = Date(), minimumAge: TimeInterval = 6 * 86_400)
        -> ScanSnapshot? {
        let sorted = history.sorted { $0.date > $1.date }
        return sorted.first { now.timeIntervalSince($0.date) >= minimumAge }
            ?? sorted.last.flatMap { now.timeIntervalSince($0.date) > 3600 ? $0 : nil }
    }

    /// Plain facts about what changed and where space is going.
    public static func compute(findings: [Finding], baseline: ScanSnapshot?, now: Date = Date()) -> [Insight] {
        var insights: [Insight] = []
        let current = ScanSnapshot(date: now, findings: findings)

        if let baseline {
            let delta = current.total - baseline.total
            let since = baseline.date.formatted(.relative(presentation: .named, unitsStyle: .wide))
            if abs(delta) >= meaningfulBytes {
                insights.append(Insight(
                    kind: .total,
                    text: "Cleanable space \(delta > 0 ? "grew" : "shrank") by \(format(abs(delta))) since \(since).",
                    bytes: delta
                ))
            }
            let categoryGrowth = CleanupCategory.allCases.map { category in
                (category, (current.categoryBytes[category.rawValue] ?? 0) - (baseline.categoryBytes[category.rawValue] ?? 0))
            }.filter { $0.1 >= meaningfulBytes }.sorted { $0.1 > $1.1 }
            if let (category, bytes) = categoryGrowth.first {
                insights.append(Insight(kind: .growth, text: "\(category.title) grew \(format(bytes)).", bytes: bytes))
            }
            let itemGrowth = current.itemBytes.compactMap { id, bytes -> (String, Int64)? in
                let grew = bytes - (baseline.itemBytes[id] ?? 0)
                return grew >= meaningfulBytes ? (id, grew) : nil
            }.sorted { a, b in
                // Deterministic: biggest growth, then items that existed before, then by id.
                if a.1 != b.1 { return a.1 > b.1 }
                let aExisted = baseline.itemBytes[a.0] != nil, bExisted = baseline.itemBytes[b.0] != nil
                if aExisted != bExisted { return aExisted }
                return a.0 < b.0
            }
            if let (id, bytes) = itemGrowth.first, let title = current.itemTitles[id] {
                let isNew = baseline.itemBytes[id] == nil
                insights.append(Insight(
                    kind: .growth, text: isNew ? "\(title) appeared with \(format(bytes))." : "\(title) grew \(format(bytes)).",
                    bytes: bytes
                ))
            }
        }

        let staleCutoff = now.addingTimeInterval(-Double(staleDays) * 86_400)
        let stale = findings.filter { $0.category == .projects && $0.modified < staleCutoff }
        let staleProjects = Set(stale.map { $0.url.deletingLastPathComponent().path })
        if !staleProjects.isEmpty {
            let bytes = stale.reduce(0) { $0 + $1.bytes }
            if bytes >= 100_000_000 {
                insights.append(Insight(
                    kind: .stale,
                    text: "\(staleProjects.count) project\(staleProjects.count == 1 ? "" : "s") untouched for \(staleDays)+ days hold \(format(bytes)) of builds.",
                    bytes: bytes
                ))
            }
        }

        if let largest = findings.filter(\.hasKnownSize).max(by: { $0.bytes < $1.bytes }), largest.bytes >= meaningfulBytes {
            insights.append(Insight(kind: .largest, text: "Largest item: \(label(for: largest)) at \(format(largest.bytes)).",
                                    bytes: largest.bytes))
        }

        let trash = findings.filter { $0.category == .trash }.reduce(0) { $0 + $1.bytes }
        if trash >= meaningfulBytes {
            insights.append(Insight(kind: .trash, text: "Trash is holding \(format(trash)) that isn’t freed yet.", bytes: trash))
        }
        return insights
    }

    static func label(for finding: Finding) -> String {
        if finding.category == .projects, let kind = finding.kind {
            return "\(finding.url.lastPathComponent) in \(finding.title) (\(kind.shortTitle))"
        }
        return finding.title
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Explanations

/// Everything Hyena knows about an item, used both as the instant answer and
/// as grounding for the on-device model.
public struct ItemFacts: Sendable, Equatable {
    public var name: String
    public var path: String
    public var category: CleanupCategory
    public var kind: ArtifactKind?
    public var bytes: Int64?
    public var modified: Date?
    public var owningApp: String?
    public var note: String?
    public var contents: [String]
    public var recommended: Bool

    public init(finding: Finding, owningApp: String? = nil, contents: [String] = []) {
        name = finding.title
        path = finding.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        category = finding.category
        kind = finding.kind
        bytes = finding.hasKnownSize ? finding.bytes : nil
        modified = finding.modified == .distantPast ? nil : finding.modified
        self.owningApp = owningApp
        note = finding.note
        self.contents = contents
        recommended = finding.recommended
    }

    public init(entry: FileEntry, in finding: Finding, contents: [String] = []) {
        name = entry.name
        path = entry.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        category = finding.category
        kind = finding.kind
        bytes = entry.bytes
        modified = entry.modified == .distantPast ? nil : entry.modified
        owningApp = nil
        note = "Inside \(finding.title)."
        self.contents = contents
        recommended = finding.recommended
    }

    /// What Hyena can say with certainty, without a model.
    public var whatHappens: String { kind?.consequence ?? Self.consequence(for: category) }

    public static func consequence(for category: CleanupCategory) -> String {
        switch category {
        case .userCaches: "The app rebuilds its cache as needed. It may feel slower the first time you open it."
        case .logs: "Logs are only used for troubleshooting. New ones are written as apps run."
        case .appSupportCaches: "Only this cache folder is removed. The app’s settings and documents stay."
        case .appLeftovers: "This removes everything the app stored, including settings. Only clean it if the app is gone for good."
        case .trash: "Items in Trash are deleted permanently."
        case .snapshots: "This local snapshot is removed. Backups on your Time Machine disk aren’t affected."
        case .xcode: "Xcode regenerates this when needed. Expect a slower next build or device connection."
        case .simulators: "The simulator and every app and file inside it are erased. Xcode can create a fresh one."
        case .downloads: "The file goes to Trash. Installers aren’t needed once the app is installed."
        case .devices: "A backup is removed for good once Trash is emptied. Keep it unless you have a newer one or iCloud Backup."
        case .packageCaches: "Packages are downloaded again the next time a project needs them."
        case .projects: "Your next build regenerates this."
        }
    }

    /// Compact text for grounding a model prompt.
    public var promptDescription: String {
        var lines = ["Name: \(name)", "Path: \(path)", "Hyena category: \(category.title) — \(category.summary)"]
        if let kind { lines.append("Detected as: \(kind.title)") }
        if let bytes { lines.append("Size: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))") }
        if let modified { lines.append("Last modified: \(modified.formatted(date: .abbreviated, time: .omitted))") }
        if let owningApp { lines.append("Owning app: \(owningApp)") }
        if let note { lines.append("Note: \(note)") }
        if !contents.isEmpty { lines.append("Largest contents: \(contents.prefix(10).joined(separator: ", "))") }
        lines.append("Known effect of cleaning: \(whatHappens)")
        lines.append("Hyena default: \(recommended ? "recommended to clean" : "review before cleaning")")
        return lines.joined(separator: "\n")
    }
}
