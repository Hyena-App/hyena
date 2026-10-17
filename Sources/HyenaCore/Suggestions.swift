import Foundation

/// A proactive, reviewable idea. Suggestions never clean anything: acting on
/// one selects its items (or opens a prompt) for the user to review.
public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case lowDisk, staleProjects, bigCache, growth, habitual, trash, installers, simulators, backups, protect

        public var title: String {
            switch self {
            case .lowDisk: "Low disk space"
            case .staleProjects: "Old project builds"
            case .bigCache: "Large caches"
            case .growth: "Fast-growing items"
            case .habitual: "Things you usually clean"
            case .trash: "Full Trash"
            case .installers: "Old installers"
            case .simulators: "Unusable simulators"
            case .backups: "Old device backups"
            case .protect: "Items you always keep"
            }
        }

        public var symbol: String {
            switch self {
            case .lowDisk: "exclamationmark.triangle.fill"
            case .staleProjects: "moon.zzz.fill"
            case .bigCache: "shippingbox.fill"
            case .growth: "chart.line.uptrend.xyaxis"
            case .habitual: "repeat"
            case .trash: "trash.fill"
            case .installers: "arrow.down.circle.fill"
            case .simulators: "iphone.slash"
            case .backups: "iphone.gen3"
            case .protect: "lock.shield.fill"
            }
        }
    }

    public enum Action: Equatable, Sendable {
        /// Select exactly these findings for review.
        case select([String])
        case emptyTrash
        /// Protect these finding ids so they're never offered again.
        case protect([String])
    }

    /// Stable across scans, so snoozing sticks.
    public let id: String
    public let kind: Kind
    public var title: String
    public var detail: String
    public let bytes: Int64
    public let action: Action
    /// Higher shows first when no model is available.
    public let priority: Double

    public init(id: String, kind: Kind, title: String, detail: String, bytes: Int64, action: Action, priority: Double) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.action = action
        self.priority = priority
    }
}

/// What the user told Hyena about suggestions: snoozes and muted kinds.
public struct SuggestionPreferences: Codable, Equatable, Sendable {
    public var snoozedUntil: [String: Date] = [:]
    public var muted: Set<Suggestion.Kind> = []
    /// How often each kind was acted on or dismissed; feeds ranking.
    public var accepted: [String: Int] = [:]
    public var dismissed: [String: Int] = [:]

    public init() {}

    public func allows(_ suggestion: Suggestion, now: Date = Date()) -> Bool {
        if muted.contains(suggestion.kind) { return false }
        if let until = snoozedUntil[suggestion.id], until > now { return false }
        return true
    }

    /// Snooze longer each time the same kind is dismissed, so Hyena backs off.
    public mutating func snooze(_ suggestion: Suggestion, now: Date = Date()) {
        let count = dismissed[suggestion.kind.rawValue, default: 0] + 1
        dismissed[suggestion.kind.rawValue] = count
        let days = min(60, 7 * count)
        snoozedUntil[suggestion.id] = now.addingTimeInterval(Double(days) * 86_400)
        snoozedUntil = snoozedUntil.filter { $0.value > now }
    }

    public mutating func recordAccepted(_ suggestion: Suggestion) {
        accepted[suggestion.kind.rawValue, default: 0] += 1
    }

    /// Kinds the user tends to act on rank higher; dismissed kinds sink.
    public func affinity(for kind: Suggestion.Kind) -> Double {
        let yes = Double(accepted[kind.rawValue, default: 0])
        let no = Double(dismissed[kind.rawValue, default: 0])
        return (yes + 1) / (yes + no + 2)
    }
}

public struct SuggestionContext: Sendable {
    public var findings: [Finding]
    public var habits: HabitBook
    public var baseline: ScanSnapshot?
    public var availableBytes: Int64
    public var capacityBytes: Int64
    public var now: Date

    public init(findings: [Finding], habits: HabitBook, baseline: ScanSnapshot?, availableBytes: Int64,
                capacityBytes: Int64, now: Date = Date()) {
        self.findings = findings
        self.habits = habits
        self.baseline = baseline
        self.availableBytes = availableBytes
        self.capacityBytes = capacityBytes
        self.now = now
    }
}

public enum SuggestionEngine {
    static let gigabyte: Int64 = 1_000_000_000

    public static func suggestions(_ context: SuggestionContext, preferences: SuggestionPreferences) -> [Suggestion] {
        let now = context.now
        // Never suggest something the user habitually keeps.
        let candidates = context.findings.filter { !context.habits.prefersKeeping($0) }
        var result: [Suggestion] = []

        func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

        // Low disk: everything recommended, shown first.
        if context.capacityBytes > 0 {
            let freeRatio = Double(context.availableBytes) / Double(context.capacityBytes)
            let recommended = candidates.filter(\.recommended)
            let bytes = recommended.reduce(0) { $0 + $1.bytes }
            if freeRatio < 0.10, bytes > 0 {
                result.append(Suggestion(
                    id: "lowDisk", kind: .lowDisk,
                    title: "Your Mac is almost full",
                    detail: "Only \(format(context.availableBytes)) is free. Cleaning recommended items frees about \(format(bytes)).",
                    bytes: bytes, action: .select(recommended.map(\.id)), priority: 100
                ))
            }
        }

        // Builds in projects untouched for a while.
        let staleCutoff = now.addingTimeInterval(-Double(Insights.staleDays) * 86_400)
        let stale = candidates.filter { $0.category == .projects && $0.recommended && $0.modified < staleCutoff }
        let staleBytes = stale.reduce(0) { $0 + $1.bytes }
        if staleBytes >= gigabyte {
            let projects = Set(stale.map { $0.url.deletingLastPathComponent().path }).count
            result.append(Suggestion(
                id: "staleProjects", kind: .staleProjects,
                title: "Clear builds from \(projects) idle project\(projects == 1 ? "" : "s")",
                detail: "Not touched in \(Insights.staleDays)+ days. They rebuild if you come back to them.",
                bytes: staleBytes, action: .select(stale.map(\.id)), priority: 60
            ))
        }

        // Individually large, safe caches.
        let bigCaches = candidates.filter {
            $0.recommended && $0.bytes >= 5 * gigabyte
                && [.packageCaches, .userCaches, .appSupportCaches, .xcode].contains($0.category)
        }
        for cache in bigCaches.sorted(by: { $0.bytes > $1.bytes }).prefix(2) {
            result.append(Suggestion(
                id: "bigCache:" + cache.url.path, kind: .bigCache,
                title: "\(cache.title) is \(format(cache.bytes))",
                detail: ItemFacts(finding: cache).whatHappens,
                bytes: cache.bytes, action: .select([cache.id]), priority: 50 + Double(cache.bytes / gigabyte)
            ))
        }

        // Fast growth since about a week ago.
        if let baseline = context.baseline {
            let grown = candidates.compactMap { finding -> (Finding, Int64)? in
                let before = baseline.itemBytes[finding.id] ?? 0
                let delta = finding.bytes - before
                return delta >= 2 * gigabyte && finding.recommended ? (finding, delta) : nil
            }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
            if let (finding, delta) = grown.first {
                let days = max(1, Int(now.timeIntervalSince(baseline.date) / 86_400))
                result.append(Suggestion(
                    id: "growth:" + finding.url.path, kind: .growth,
                    title: "\(finding.title) grew \(format(delta))",
                    detail: "That’s in the last \(days) day\(days == 1 ? "" : "s"). It’s safe to clear and will rebuild as needed.",
                    bytes: finding.bytes, action: .select([finding.id]), priority: 55
                ))
            }
        }

        // Things the user cleans every time.
        let habitual = candidates.filter { context.habits.prefersCleaning($0) || (habitKept($0, context) == 0 && habitCleaned($0, context) >= 2) }
        let habitualBytes = habitual.reduce(0) { $0 + $1.bytes }
        if !habitual.isEmpty, habitualBytes >= gigabyte / 2 {
            result.append(Suggestion(
                id: "habitual", kind: .habitual,
                title: "Your usual cleanup is ready",
                detail: "\(habitual.count) item\(habitual.count == 1 ? "" : "s") you clean regularly have built up again.",
                bytes: habitualBytes, action: .select(habitual.map(\.id)), priority: 45
            ))
        }

        // Trash.
        let trashBytes = context.findings.filter { $0.category == .trash }.reduce(0) { $0 + $1.bytes }
        if trashBytes >= gigabyte {
            result.append(Suggestion(
                id: "trash", kind: .trash,
                title: "Trash is holding \(format(trashBytes))",
                detail: "That space isn’t free until Trash is emptied.",
                bytes: trashBytes, action: .emptyTrash, priority: 40
            ))
        }

        // Installers left in Downloads.
        let installers = candidates.filter { $0.category == .downloads && $0.recommended }
        let installerBytes = installers.reduce(0) { $0 + $1.bytes }
        if installerBytes >= gigabyte / 2 {
            result.append(Suggestion(
                id: "installers", kind: .installers,
                title: "\(installers.count) old installer\(installers.count == 1 ? "" : "s") in Downloads",
                detail: "Disk images and packages aren’t needed once the app is installed.",
                bytes: installerBytes, action: .select(installers.map(\.id)), priority: 48
            ))
        }

        // Simulators whose runtime is gone can never boot again.
        let deadSimulators = candidates.filter { $0.category == .simulators && $0.recommended && $0.title != "Simulator caches" }
        let simulatorBytes = deadSimulators.reduce(0) { $0 + $1.bytes }
        if simulatorBytes >= gigabyte / 2 {
            result.append(Suggestion(
                id: "simulators", kind: .simulators,
                title: "Remove \(deadSimulators.count) simulator\(deadSimulators.count == 1 ? "" : "s") that can’t run",
                detail: "Their iOS versions are no longer installed, so they can’t start anymore.",
                bytes: simulatorBytes, action: .select(deadSimulators.map(\.id)), priority: 47
            ))
        }

        // Device backups older than a year: worth a look, never preselected.
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let oldBackups = candidates.filter { $0.category == .devices && !$0.recommended && $0.modified < yearAgo }
        let backupBytes = oldBackups.reduce(0) { $0 + $1.bytes }
        if backupBytes >= 2 * gigabyte {
            result.append(Suggestion(
                id: "backups", kind: .backups,
                title: "Review \(oldBackups.count) device backup\(oldBackups.count == 1 ? "" : "s") over a year old",
                detail: "Keep any you might restore from. Newer backups or iCloud Backup make these redundant.",
                bytes: backupBytes, action: .select(oldBackups.map(\.id)), priority: 30
            ))
        }

        // Items always kept: offer protection.
        let keepers = context.findings.filter { context.habits.suggestsProtecting($0) }
        if !keepers.isEmpty {
            result.append(Suggestion(
                id: "protect:" + keepers.map(\.id).sorted().joined(separator: "|"), kind: .protect,
                title: "Protect \(keepers.count) item\(keepers.count == 1 ? "" : "s") you always keep",
                detail: keepers.prefix(3).map(\.title).joined(separator: ", ") + ". They’ll never be offered again.",
                bytes: 0, action: .protect(keepers.map(\.id)), priority: 20
            ))
        }

        return result
            .filter { preferences.allows($0, now: now) }
            .sorted { $0.priority * preferences.affinity(for: $0.kind) > $1.priority * preferences.affinity(for: $1.kind) }
    }

    private static func habitKept(_ finding: Finding, _ context: SuggestionContext) -> Int {
        HabitBook.key(for: finding).flatMap { context.habits.habits[$0]?.kept } ?? 0
    }

    private static func habitCleaned(_ finding: Finding, _ context: SuggestionContext) -> Int {
        HabitBook.key(for: finding).flatMap { context.habits.habits[$0]?.cleaned } ?? 0
    }
}
