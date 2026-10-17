import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import HyenaCore

struct CleanupRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let count: Int
    let bytes: Int64
    var categories: [String]? = nil
}

enum ReminderInterval: Int, CaseIterable, Identifiable {
    case never = 0, weekly = 7, monthly = 30
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .never: "Never"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum Phase: Equatable {
    case idle, scanning, cleaning
}

struct CleanResult: Equatable {
    var count = 0
    var movedBytes: Int64 = 0
    var freedBytes: Int64 = 0
    var snapshots = 0
    var failures: [String] = []
}

@MainActor
@Observable
final class AppModel {
    // MARK: Preferences (persisted)
    var roots: [URL] = [] { didSet { persist(); if !loading { invalidateScan() } } }
    var exclusions: [URL] = [] { didSet { persist(); if !loading { applyExclusions() } } }
    var kinds: Set<ArtifactKind> = Set(ArtifactKind.allCases) { didSet { persist(); if !loading { invalidateScan() } } }
    var categories: Set<CleanupCategory> = Set(CleanupCategory.allCases) { didSet { persist(); if !loading { invalidateScan() } } }
    var minimumAgeDays = 7 { didSet { persist(); if !loading { invalidateScan() } } }
    var scanOnOpen = true { didSet { persist() } }
    var deleteImmediately = false { didSet { persist() } }
    var reminder: ReminderInterval = .weekly { didSet { persist(); scheduleReminderCheck() } }
    var reminderThresholdGB = 5 { didSet { persist() } }
    var learnHabits = true { didSet { persist() } }
    var useOnDeviceModel = true { didSet { persist() } }

    // MARK: Assistant
    var habits = HabitBook()
    var snapshots: [ScanSnapshot] = []
    var insights: [Insight] = []
    var digest: String?
    var digestLoading = false
    var presentAskSheet = false
    var suggestions: [Suggestion] = []
    var suggestionsUsedModel = false
    var suggestionsLoading = false
    var suggestionPrefs = SuggestionPreferences()
    private var baseline: ScanSnapshot?

    // MARK: Scan state
    var phase: Phase = .idle
    var progressText = ""
    var findings: [Finding] = []
    var selection = SelectionModel()
    var loadingChildren: Set<String> = []
    var warnings: [String] = []
    var needsFullDiskAccess = false
    var lastScan: Date?
    /// Categories measured so far in the running scan: total bytes and item count.
    var measured: [CleanupCategory: (bytes: Int64, count: Int)] = [:]
    var cleanProgress = 0
    var cleanTotal = 0
    var lastResult: CleanResult?

    // MARK: Storage
    var available: Int64 = 0
    var capacity: Int64 = 0
    var history: [CleanupRecord] = []

    // MARK: Window routing
    var openWindowRequest = 0
    var presentCleanSheet = false

    private var loading = true
    private var scanTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var reminderTimer: Timer?
    private let defaults: UserDefaults = {
        guard DemoData.isActive, let demo = UserDefaults(suiteName: "com.hyena.demo") else { return .standard }
        demo.removePersistentDomain(forName: "com.hyena.demo")
        return demo
    }()

    init() {
        roots = (defaults.stringArray(forKey: "roots") ?? []).map { URL(fileURLWithPath: $0) }
        exclusions = (defaults.stringArray(forKey: "exclusions") ?? []).map { URL(fileURLWithPath: $0) }
        if let saved = defaults.stringArray(forKey: "kinds") {
            kinds = Set(saved.compactMap(ArtifactKind.init(rawValue:)))
            if !defaults.bool(forKey: "expandedArtifactKindsV3") {
                kinds.formUnion([.web, .elixir, .dart, .zig, .haskell, .terraform, .cocoapods, .ruby, .php, .pythonEnv])
            }
        }
        defaults.set(true, forKey: "expandedArtifactKindsV3")
        if let saved = defaults.stringArray(forKey: "categories") {
            categories = Set(saved.compactMap(CleanupCategory.init(rawValue:)))
            if !defaults.bool(forKey: "everydayCategoriesV1") {
                categories.formUnion([.downloads, .devices, .simulators])
            }
        }
        defaults.set(true, forKey: "everydayCategoriesV1")
        if defaults.object(forKey: "minimumAgeDays") != nil { minimumAgeDays = defaults.integer(forKey: "minimumAgeDays") }
        if defaults.object(forKey: "scanOnOpen") != nil { scanOnOpen = defaults.bool(forKey: "scanOnOpen") }
        deleteImmediately = defaults.bool(forKey: "deleteImmediately")
        if defaults.object(forKey: "reminder") != nil {
            reminder = ReminderInterval(rawValue: defaults.integer(forKey: "reminder")) ?? .weekly
        }
        if defaults.object(forKey: "reminderThresholdGB") != nil {
            reminderThresholdGB = defaults.integer(forKey: "reminderThresholdGB")
        }
        if defaults.object(forKey: "learnHabits") != nil { learnHabits = defaults.bool(forKey: "learnHabits") }
        if defaults.object(forKey: "useOnDeviceModel") != nil { useOnDeviceModel = defaults.bool(forKey: "useOnDeviceModel") }
        if let data = defaults.data(forKey: "habits"), let saved = try? JSONDecoder().decode(HabitBook.self, from: data) {
            habits = saved
        }
        if let data = defaults.data(forKey: "suggestionPrefs"),
           let saved = try? JSONDecoder().decode(SuggestionPreferences.self, from: data) { suggestionPrefs = saved }
        if let data = defaults.data(forKey: "snapshots"),
           let saved = try? JSONDecoder().decode([ScanSnapshot].self, from: data) { snapshots = saved }
        if let data = defaults.data(forKey: "history"),
           let saved = try? JSONDecoder().decode([CleanupRecord].self, from: data) { history = saved }
        loading = false
        NotificationRouter.shared.onOpen = { [weak self] in self?.openWindowRequest += 1 }
        refreshStorage()
        if !DemoData.isActive { scheduleReminderCheck() }
        if scanOnOpen { scan() }
    }

    // MARK: Derived values

    var busy: Bool { phase != .idle }
    var scanning: Bool { phase == .scanning }

    func findings(in category: CleanupCategory) -> [Finding] {
        findings.filter { $0.category == category }
    }

    func totalBytes(in category: CleanupCategory) -> Int64 {
        findings(in: category).reduce(0) { $0 + $1.bytes }
    }

    func selectedBytes(in category: CleanupCategory) -> Int64 {
        findings(in: category).reduce(0) { $0 + selection.selectedBytes(of: $1) }
    }

    func selectedCount(in category: CleanupCategory) -> Int {
        findings(in: category).filter { selection.isIncluded($0) }.count
    }

    var selectedFindings: [Finding] { findings.filter { selection.isIncluded($0) } }
    var selectedBytes: Int64 { findings.reduce(0) { $0 + selection.selectedBytes(of: $1) } }
    var totalBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }
    var recommendedBytes: Int64 { findings.filter(\.recommended).reduce(0) { $0 + $1.bytes } }
    var selectedSnapshotCount: Int { selectedFindings.filter { $0.category == .snapshots }.count }

    /// Categories still being measured in the running scan.
    var pendingCategories: [CleanupCategory] {
        visibleCategories.filter { measured[$0] == nil && !($0 == .projects && roots.isEmpty) }
    }

    var scanFraction: Double {
        let total = visibleCategories.filter { !($0 == .projects && roots.isEmpty) }.count
        return total == 0 ? 0 : Double(total - pendingCategories.count) / Double(total)
    }

    /// Names what's actually still running, e.g. "App Caches and Package Caches".
    var scanSummary: String {
        let names = pendingCategories.map(\.title)
        switch names.count {
        case 0: return "Wrapping up…"
        case 1: return "Still measuring \(names[0])"
        case 2: return "Still measuring \(names[0]) and \(names[1])"
        default: return "Still measuring \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    var visibleCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { categories.contains($0) }
    }

    // MARK: Selection

    func state(of finding: Finding) -> CheckState { selection.state(of: finding) }
    func state(of entry: FileEntry, in finding: Finding) -> CheckState { selection.state(of: entry.url.path, in: finding) }
    func toggle(_ finding: Finding) { selection.toggle(finding.url.path, in: finding) }
    func toggle(_ entry: FileEntry, in finding: Finding) { selection.toggle(entry.url.path, in: finding) }

    func select(_ mode: SelectMode, in category: CleanupCategory) {
        for finding in findings(in: category) {
            switch mode {
            case .recommended: selection.set(finding, included: finding.recommended)
            case .all: selection.set(finding, included: true)
            case .none: selection.set(finding, included: false)
            }
        }
    }

    enum SelectMode { case recommended, all, none }

    func children(of path: String) -> [FileEntry]? { selection.children[path] }

    func loadChildren(of url: URL) {
        let path = url.path
        guard selection.children[path] == nil, !loadingChildren.contains(path) else { return }
        if DemoData.isActive { return selection.setChildren(DemoData.children(of: path), of: path) }
        loadingChildren.insert(path)
        Task {
            let entries = (try? await Task.detached(priority: .userInitiated) {
                try await DirectoryInspector.children(of: url)
            }.value) ?? []
            selection.setChildren(entries, of: path)
            loadingChildren.remove(path)
        }
    }

    // MARK: Storage

    func refreshStorage() {
        if DemoData.isActive {
            capacity = DemoData.capacity
            available = DemoData.available
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]) else { return }
        capacity = Int64(values.volumeTotalCapacity ?? 0)
        available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
    }

    var usedBytes: Int64 { max(0, capacity - available) }
    /// Selected bytes, never shown as more than what's actually used.
    var readyToCleanBytes: Int64 { min(selectedBytes, usedBytes) }

    // MARK: Locations

    func addFolder(protect: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = protect ? "Protect" : "Add"
        panel.message = protect
            ? "These folders and everything inside them will never be cleaned."
            : "Choose folders that contain your projects. Hyena looks for build outputs and dependencies inside."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        if protect {
            exclusions = Array(Set(exclusions + panel.urls)).sorted { $0.path < $1.path }
        } else {
            roots = Array(Set(roots + panel.urls)).sorted { $0.path < $1.path }
        }
    }

    func addRoot(_ url: URL) {
        guard !roots.contains(url) else { return }
        roots = (roots + [url]).sorted { $0.path < $1.path }
    }

    /// Common project folders that exist on this Mac but aren't added yet.
    var suggestedRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ["Developer", "Projects", "projects", "Code", "code", "src", "dev", "Sites", "workspace",
                     "repos", "git", "GitHub", "Documents/GitHub", "Documents/Projects"]
        var seen = Set<String>()
        return names.compactMap { name in
            let url = home.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let real = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
                  seen.insert(real.lowercased()).inserted,
                  !roots.contains(where: { PathPolicy.contains($0, url) }) else { return nil }
            return url
        }
    }

    func protect(_ url: URL) {
        guard !exclusions.contains(url) else { return }
        exclusions.append(url)
    }

    // MARK: Scanning

    func scan() {
        guard !busy else { return }
        if DemoData.isActive { return demoScan() }
        phase = .scanning
        progressText = "Getting ready"
        measured = [:]
        warnings = []
        lastResult = nil
        let roots = roots, exclusions = exclusions, kinds = kinds, age = minimumAgeDays
        let categories = categories
        let running = NSWorkspace.shared.runningApplications
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        let runningNames = Set(running.compactMap(\.localizedName))

        scanTask = Task {
            let finished: @Sendable (CleanupCategory, ScanReport) async -> Void = { category, report in
                let bytes = report.findings.reduce(0) { $0 + $1.bytes }
                let count = report.findings.count
                await MainActor.run { [weak self] in self?.measured[category] = (bytes, count) }
            }
            let progress: @Sendable (String) async -> Void = { text in
                await MainActor.run { [weak self] in self?.progressText = text }
            }
            let worker = Task.detached(priority: .utility) { () throws -> ScanReport in
                let installed = AppCatalog.installed()
                let apps = AppInventory(
                    runningBundleIDs: runningIDs, runningNames: runningNames,
                    installedBundleIDs: installed.ids, installedNames: installed.names
                )
                async let system = SystemScanner.scan(
                    SystemScanOptions(categories: categories.subtracting([.projects]), apps: apps),
                    exclusions: exclusions, progress: progress, finished: finished
                )
                async let projects: ScanReport = {
                    guard categories.contains(.projects), !roots.isEmpty else { return ScanReport() }
                    let report = try await Scanner.scan(
                        roots: roots, exclusions: exclusions, kinds: kinds, minimumAgeDays: age, progress: progress
                    )
                    await finished(.projects, report)
                    return report
                }()
                var report = try await system
                let projectReport = try await projects
                report.findings += projectReport.findings
                report.warnings += projectReport.warnings
                report.findings = Self.removingNested(report.findings)
                return report
            }
            do {
                let report = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                findings = report.findings.sorted { $0.bytes > $1.bytes }
                selection = SelectionModel()
                selection.reset(selecting: learnHabits ? habits.preferredSelection(for: findings)
                                                       : findings.filter(\.recommended))
                warnings = report.warnings
                updateInsights()
                needsFullDiskAccess = report.needsFullDiskAccess
                lastScan = Date()
                phase = .idle
                refreshStorage()
            } catch {
                if phase == .scanning { phase = .idle }
            }
        }
    }

    /// Drops findings that sit inside another finding so nothing is counted twice.
    nonisolated static func removingNested(_ findings: [Finding]) -> [Finding] {
        let paths = Set(findings.compactMap { finding -> String? in
            if case .deleteSnapshot = finding.action { return nil }
            return finding.url.path
        })
        return findings.filter { finding in
            if case .deleteSnapshot = finding.action { return true }
            var parent = (finding.url.path as NSString).deletingLastPathComponent
            while parent.count > 1 {
                if paths.contains(parent) { return false }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return true
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        phase = .idle
        progressText = ""
    }

    /// Preference changes refresh results instead of leaving stale ones around.
    private func invalidateScan() {
        guard lastScan != nil || scanning else { return }
        if scanning { cancelScan() }
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            scan()
        }
    }

    /// Newly protected paths disappear from results right away.
    private func applyExclusions() {
        let protected = findings.filter { finding in
            if case .deleteSnapshot = finding.action { return false }
            return PathPolicy.isProtected(finding.url, by: exclusions)
        }
        for finding in protected { selection.set(finding, included: false) }
        findings.removeAll { protected.map(\.id).contains($0.id) }
        if scanning { invalidateScan() }
    }

    // MARK: Cleaning

    func clean() {
        guard !busy else { return }
        if DemoData.isActive { return demoClean() }
        let plans = selectedFindings.map { finding in
            CleanupPlan(finding: finding, targets: selection.targets(for: finding),
                        bytes: selection.selectedBytes(of: finding))
        }.filter { !$0.targets.isEmpty || $0.finding.action != .moveToTrash }
        guard !plans.isEmpty else { return }
        let exclusions = exclusions
        let permanent = deleteImmediately
        phase = .cleaning
        cleanProgress = 0
        cleanTotal = plans.count
        lastResult = nil

        Task {
            let handlers = CleanupHandlers(
                moveToTrash: { url in
                    if permanent {
                        try FileManager.default.removeItem(at: url)
                    } else {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                },
                deletePermanently: { url in try FileManager.default.removeItem(at: url) },
                deleteSnapshot: { token in
                    do { try Snapshots.delete(token) } catch { try Privileged.deleteSnapshot(token) }
                }
            )
            let outcome = await Task.detached(priority: .userInitiated) {
                CleanupExecutor.execute(plans, exclusions: exclusions, handlers: handlers) { index in
                    Task { @MainActor [weak self] in self?.cleanProgress = index + 1 }
                }
            }.value

            var result = CleanResult(
                count: outcome.handledCount,
                movedBytes: permanent ? 0 : outcome.movedBytes,
                freedBytes: outcome.freedBytes + (permanent ? outcome.movedBytes : 0),
                snapshots: outcome.snapshotsDeleted,
                failures: outcome.failures
            )
            if result.count == 0 && result.failures.isEmpty { result.failures = ["Nothing was cleaned."] }
            if learnHabits {
                habits.record(shown: findings, cleaned: outcome.movedIDs)
                saveHabits()
            }
            let cleanedCategories = Set(plans.filter { outcome.movedIDs.contains($0.finding.id) }.map(\.finding.category.title))
            findings.removeAll { outcome.movedIDs.contains($0.id) }
            for id in outcome.movedIDs { if let f = plans.first(where: { $0.finding.id == id })?.finding { selection.set(f, included: false) } }
            warnings.append(contentsOf: outcome.failures)
            if outcome.handledCount > 0 {
                history.insert(CleanupRecord(
                    date: Date(), count: outcome.handledCount, bytes: outcome.movedBytes + outcome.freedBytes,
                    categories: cleanedCategories.sorted()
                ), at: 0)
                history = Array(history.prefix(50))
                defaults.set(try? JSONEncoder().encode(history), forKey: "history")
            }
            lastResult = result
            phase = .idle
            refreshStorage()
        }
    }

    /// Asks Finder to empty the Trash; works without Full Disk Access.
    func emptyTrash() {
        if DemoData.isActive { return }
        Task {
            let error = await Privileged.emptyTrashWithFinder()
            if let error { warnings.append(error) }
            if let result = lastResult {
                lastResult?.freedBytes = result.freedBytes + result.movedBytes
                lastResult?.movedBytes = 0
            }
            try? await Task.sleep(for: .seconds(1))
            refreshStorage()
            findings.removeAll { $0.category == .trash }
        }
    }

    // MARK: Assistant

    var assistantStatus: Assistant.Status {
        useOnDeviceModel ? Assistant.status : .unavailable("The on-device model is turned off in Settings.")
    }

    /// Compares this scan with one from about a week ago and asks the
    /// on-device model to phrase the result.
    private func updateInsights() {
        let now = Date()
        baseline = Insights.baseline(in: snapshots, now: now)
        insights = Insights.compute(findings: findings, baseline: baseline, now: now)
        refreshSuggestions()
        let snapshot = ScanSnapshot(date: now, findings: findings)
        if let last = snapshots.last, now.timeIntervalSince(last.date) < 6 * 3600 {
            snapshots[snapshots.count - 1] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        snapshots = Array(snapshots.suffix(30))
        defaults.set(try? JSONEncoder().encode(snapshots), forKey: "snapshots")

        digest = nil
        guard !insights.isEmpty else { return }
        digestLoading = true
        let insights = insights, selected = selectedBytes, useModel = useOnDeviceModel
        Task {
            digest = useModel ? await Assistant.digest(insights, selectedBytes: selected)
                              : insights.prefix(2).map(\.text).joined(separator: " ")
            digestLoading = false
        }
    }

    func explain(_ facts: ItemFacts) async -> Assistant.Explanation {
        guard useOnDeviceModel else { return Assistant.fallbackExplanation(facts) }
        do { return try await Assistant.explain(facts) } catch { return Assistant.fallbackExplanation(facts) }
    }

    func interpret(_ request: String) async -> Assistant.Interpretation {
        guard useOnDeviceModel else { return .init(rule: RuleParser.parse(request), usedModel: false) }
        return await Assistant.interpret(request)
    }

    func matches(_ rule: SelectionRule) -> [Finding] {
        let now = Date()
        return findings.filter { rule.matches($0, now: now) }
    }

    /// Replaces the selection with what the reviewed rule matches.
    func apply(_ rule: SelectionRule) {
        let now = Date()
        for finding in findings { selection.set(finding, included: rule.matches(finding, now: now)) }
    }

    // MARK: Suggestions

    func refreshSuggestions() {
        if reminder != .never && !defaults.bool(forKey: "askedNotifications") {
            defaults.set(true, forKey: "askedNotifications")
            Notifier.requestAuthorization()
        }
        let context = SuggestionContext(
            findings: findings, habits: learnHabits ? habits : HabitBook(), baseline: baseline,
            availableBytes: available, capacityBytes: capacity
        )
        let candidates = SuggestionEngine.suggestions(context, preferences: suggestionPrefs)
        suggestions = Array(candidates.prefix(3))
        suggestionsUsedModel = false
        guard useOnDeviceModel, candidates.count > 1 else { return }
        suggestionsLoading = true
        let profile = userProfile
        Task {
            let result = await Assistant.personalize(candidates, profile: profile)
            suggestions = result.items
            suggestionsUsedModel = result.usedModel
            suggestionsLoading = false
        }
    }

    /// A short, local description of this user's habits, given to the on-device model.
    private var userProfile: String {
        var lines: [String] = []
        let cleaned = history.flatMap { $0.categories ?? [] }
        let counts = Dictionary(cleaned.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }
        if !counts.isEmpty { lines.append("Often cleans: " + counts.prefix(4).map { "\($0.key) (\($0.value)x)" }.joined(separator: ", ")) }
        if let last = history.first { lines.append("Last cleanup: \(last.date.formatted(.relative(presentation: .named)))") }
        let kept = findings.filter { habits.prefersKeeping($0) }.map(\.title)
        if !kept.isEmpty { lines.append("Usually keeps: " + kept.prefix(5).joined(separator: ", ")) }
        let accepted = suggestionPrefs.accepted.filter { $0.value > 0 }.map(\.key)
        let dismissed = suggestionPrefs.dismissed.filter { $0.value > 0 }.map { "\($0.key) (\($0.value)x)" }
        if !accepted.isEmpty { lines.append("Acted on suggestions about: " + accepted.joined(separator: ", ")) }
        if !dismissed.isEmpty { lines.append("Dismissed suggestions about: " + dismissed.joined(separator: ", ")) }
        lines.append("Free space: \(space(available)) of \(space(capacity))")
        return lines.joined(separator: "\n")
    }

    /// Acting on a suggestion only selects or prepares; the user still reviews.
    func act(on suggestion: Suggestion) {
        suggestionPrefs.recordAccepted(suggestion)
        saveSuggestionPrefs()
        switch suggestion.action {
        case .select(let ids):
            let wanted = Set(ids)
            for finding in findings { selection.set(finding, included: wanted.contains(finding.id)) }
            presentCleanSheet = true
        case .emptyTrash:
            emptyTrash()
        case .protect(let ids):
            for finding in findings where ids.contains(finding.id) { acceptProtectSuggestion(finding) }
        }
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func snooze(_ suggestion: Suggestion) {
        suggestionPrefs.snooze(suggestion)
        saveSuggestionPrefs()
        withAnimation(.smooth) { suggestions.removeAll { $0.id == suggestion.id } }
    }

    func mute(_ kind: Suggestion.Kind) {
        suggestionPrefs.muted.insert(kind)
        saveSuggestionPrefs()
        withAnimation(.smooth) { suggestions.removeAll { $0.kind == kind } }
    }

    func setMuted(_ kind: Suggestion.Kind, _ muted: Bool) {
        if muted { suggestionPrefs.muted.insert(kind) } else { suggestionPrefs.muted.remove(kind) }
        saveSuggestionPrefs()
        refreshSuggestions()
    }

    func resetSuggestionPreferences() {
        suggestionPrefs = SuggestionPreferences()
        saveSuggestionPrefs()
        refreshSuggestions()
    }

    private func saveSuggestionPrefs() {
        defaults.set(try? JSONEncoder().encode(suggestionPrefs), forKey: "suggestionPrefs")
    }

    func learnedKeep(_ finding: Finding) -> Bool { learnHabits && habits.prefersKeeping(finding) }
    func learnedClean(_ finding: Finding) -> Bool { learnHabits && habits.prefersCleaning(finding) }

    func acceptProtectSuggestion(_ finding: Finding) {
        protect(finding.category == .projects ? finding.url.deletingLastPathComponent() : finding.url)
    }

    func dismissProtectSuggestion(_ finding: Finding) {
        habits.dismissSuggestion(for: finding)
        saveHabits()
    }

    func forgetHabits() {
        habits = HabitBook()
        saveHabits()
    }

    private func saveHabits() {
        defaults.set(try? JSONEncoder().encode(habits), forKey: "habits")
    }

    // MARK: Demo mode (never touches the disk)

    private func demoScan() {
        phase = .scanning
        measured = [:]
        lastResult = nil
        let sample = DemoData.findings
        Task {
            for category in visibleCategories {
                try? await Task.sleep(for: .milliseconds(140))
                let items = sample.filter { $0.category == category }
                measured[category] = (items.reduce(0) { $0 + $1.bytes }, items.count)
            }
            findings = sample.sorted { $0.bytes > $1.bytes }
            if let figma = findings.first(where: { $0.title == "Figma" }) {
                habits = HabitBook()
                habits.record(shown: [figma], cleaned: [])
                habits.record(shown: [figma], cleaned: [])
            }
            selection = SelectionModel()
            selection.reset(selecting: habits.preferredSelection(for: findings))
            snapshots = [DemoData.baseline]
            needsFullDiskAccess = false
            lastScan = Date()
            phase = .idle
            updateInsights()
        }
    }

    private func demoClean() {
        let chosen = selectedFindings
        phase = .cleaning
        cleanTotal = chosen.count
        cleanProgress = 0
        Task {
            for index in chosen.indices {
                try? await Task.sleep(for: .milliseconds(40))
                cleanProgress = index + 1
            }
            let moved = chosen.filter { $0.action == .moveToTrash }.reduce(0) { $0 + selection.selectedBytes(of: $1) }
            let freed = chosen.filter { $0.action == .deletePermanently }.reduce(0) { $0 + selection.selectedBytes(of: $1) }
            lastResult = CleanResult(count: chosen.count, movedBytes: moved, freedBytes: freed,
                                     snapshots: chosen.filter { $0.category == .snapshots }.count)
            findings.removeAll { finding in chosen.contains { $0.id == finding.id } }
            phase = .idle
        }
    }

    // MARK: Permissions & system

    var hasFullDiskAccess: Bool {
        if DemoData.isActive { return true }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                warnings.append("Launch at login: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Reminders

    private func scheduleReminderCheck() {
        reminderTimer?.invalidate()
        guard reminder != .never else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkReminder() }
        }
    }

    /// Periodically rescans in the background and nudges when there's
    /// meaningful space to recover. Never cleans on its own.
    private func checkReminder() {
        let last = defaults.object(forKey: "lastReminder") as? Date ?? .distantPast
        guard reminder != .never, Date().timeIntervalSince(last) > Double(reminder.rawValue) * 86_400, !busy else { return }
        scan()
        Task {
            while busy { try? await Task.sleep(for: .seconds(2)) }
            while digestLoading || suggestionsLoading { try? await Task.sleep(for: .milliseconds(500)) }
            let threshold = Int64(reminderThresholdGB) * 1_000_000_000
            // Nudge only when there's something meaningful, led by the best suggestion.
            guard let top = suggestions.first,
                  top.kind == .lowDisk || selectedBytes >= threshold || top.bytes >= threshold else { return }
            defaults.set(Date(), forKey: "lastReminder")
            Notifier.post(title: top.title + (top.bytes > 0 && !top.title.contains("GB") && !top.title.contains("MB")
                                              ? " · \(space(top.bytes))" : ""),
                          body: top.detail)
        }
    }

    private func persist() {
        guard !loading else { return }
        defaults.set(roots.map(\.path), forKey: "roots")
        defaults.set(exclusions.map(\.path), forKey: "exclusions")
        defaults.set(kinds.map(\.rawValue), forKey: "kinds")
        defaults.set(categories.map(\.rawValue), forKey: "categories")
        defaults.set(minimumAgeDays, forKey: "minimumAgeDays")
        defaults.set(scanOnOpen, forKey: "scanOnOpen")
        defaults.set(deleteImmediately, forKey: "deleteImmediately")
        defaults.set(reminder.rawValue, forKey: "reminder")
        defaults.set(reminderThresholdGB, forKey: "reminderThresholdGB")
        defaults.set(learnHabits, forKey: "learnHabits")
        defaults.set(useOnDeviceModel, forKey: "useOnDeviceModel")
    }
}

// MARK: - Installed apps

enum AppCatalog {
    static func installed() -> (ids: Set<String>, names: Set<String>) {
        var ids = Set<String>(), names = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", home + "/Applications"] {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if enumerator.level > 2 { enumerator.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                names.insert(url.deletingPathExtension().lastPathComponent)
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return (ids, names)
    }
}

// MARK: - Privileged & scripted operations

enum Privileged {
    /// Runs `tmutil deletelocalsnapshots` with the standard administrator prompt.
    static func deleteSnapshot(_ token: String) throws {
        guard Snapshots.isValidToken(token) else { throw CleanupError.unsafePath }
        let source = "do shell script \"/usr/bin/tmutil deletelocalsnapshots \(token)\" with administrator privileges"
        let message: String? = DispatchQueue.main.sync {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            return error?[NSAppleScript.errorMessage] as? String
        }
        if let message { throw CleanupError.snapshotFailed(message) }
    }

    @MainActor
    static func emptyTrashWithFinder() async -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        guard let error else { return nil }
        return "Couldn’t empty Trash: \(error[NSAppleScript.errorMessage] as? String ?? "Finder refused the request.")"
    }
}

// MARK: - Notifications

/// Opens Hyena when the user clicks one of its notifications.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor var onOpen: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum Notifier {
    static var available: Bool {
        !DemoData.isActive && Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "hyena.reminder", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
