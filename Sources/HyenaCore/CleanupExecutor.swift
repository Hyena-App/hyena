import Foundation

public struct CleanupPlan: Sendable {
    public let finding: Finding
    /// Exact paths to remove: the finding itself or its checked descendants.
    public let targets: [URL]
    public let bytes: Int64

    public init(finding: Finding, targets: [URL], bytes: Int64) {
        self.finding = finding
        self.targets = targets
        self.bytes = bytes
    }
}

public struct CleanupHandlers: Sendable {
    public var moveToTrash: @Sendable (URL) throws -> Void
    public var deletePermanently: @Sendable (URL) throws -> Void
    public var deleteSnapshot: @Sendable (String) throws -> Void

    public init(
        moveToTrash: @escaping @Sendable (URL) throws -> Void,
        deletePermanently: @escaping @Sendable (URL) throws -> Void,
        deleteSnapshot: @escaping @Sendable (String) throws -> Void
    ) {
        self.moveToTrash = moveToTrash
        self.deletePermanently = deletePermanently
        self.deleteSnapshot = deleteSnapshot
    }
}

public struct CleanupOutcome: Sendable {
    /// Findings whose every target was handled.
    public var movedIDs: Set<String> = []
    /// Bytes moved to Trash (still on disk until Trash is emptied).
    public var movedBytes: Int64 = 0
    /// Bytes removed permanently (emptied Trash items).
    public var freedBytes: Int64 = 0
    public var snapshotsDeleted = 0
    public var failures: [String] = []

    public init(movedIDs: Set<String> = [], movedBytes: Int64 = 0, failures: [String] = []) {
        self.movedIDs = movedIDs
        self.movedBytes = movedBytes
        self.failures = failures
    }

    public var handledCount: Int { movedIDs.count }
}

public enum CleanupExecutor {
    /// Revalidates and handles each item independently. Handlers are injected
    /// so safety behavior can be tested without changing the filesystem.
    public static func execute(
        _ plans: [CleanupPlan], exclusions: [URL], handlers: CleanupHandlers,
        progress: (Int) -> Void = { _ in }
    ) -> CleanupOutcome {
        var outcome = CleanupOutcome()
        for (index, plan) in plans.enumerated() {
            progress(index)
            let finding = plan.finding
            do {
                try Scanner.validateForCleanup(finding, exclusions: exclusions)
                switch finding.action {
                case .deleteSnapshot(let token):
                    try handlers.deleteSnapshot(token)
                    outcome.snapshotsDeleted += 1
                case .moveToTrash, .deletePermanently:
                    let whole = plan.targets == [finding.url]
                    if !whole {
                        for target in plan.targets {
                            try Scanner.validateSubpath(target, of: finding, exclusions: exclusions)
                        }
                    }
                    var failed = false
                    for target in plan.targets {
                        do {
                            if finding.action == .deletePermanently {
                                try handlers.deletePermanently(target)
                            } else {
                                try handlers.moveToTrash(target)
                            }
                        } catch {
                            failed = true
                            outcome.failures.append("\(target.path): \(error.localizedDescription)")
                        }
                    }
                    if failed { continue }
                    if finding.action == .deletePermanently {
                        outcome.freedBytes += plan.bytes
                    } else {
                        outcome.movedBytes += plan.bytes
                    }
                }
                outcome.movedIDs.insert(finding.id)
            } catch {
                outcome.failures.append("\(finding.url.path): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    /// Convenience for whole findings moved with a single operation.
    public static func execute(
        _ findings: [Finding], exclusions: [URL], move: @escaping @Sendable (URL) throws -> Void
    ) -> CleanupOutcome {
        execute(
            findings.map { CleanupPlan(finding: $0, targets: [$0.url], bytes: $0.bytes) },
            exclusions: exclusions,
            handlers: CleanupHandlers(moveToTrash: move, deletePermanently: move, deleteSnapshot: { _ in })
        )
    }
}
