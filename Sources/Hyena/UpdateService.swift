import AppKit
import Foundation
import HyenaCore
import Observation

/// Checks GitHub Releases for a newer Hyena and installs it in one click: `brew upgrade` when
/// Homebrew installed it, otherwise download the DMG, check it's signed by the same developer and
/// notarized, swap the app in place and relaunch. Modeled on Lizard's updater.
@Observable
@MainActor
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let autoCheckKey = "checkForUpdates"
    static var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }
    private static let expectedKey = "updateExpected"
    /// Updates must be signed by the same team as the running app.
    private static let teamID = "6H728M7XQK"

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var available: AppRelease? {
        if case .available(let release) = state { release } else { nil }
    }

    /// Daily background check, the first a minute after launch. Never in demo mode.
    func start() {
        guard loop == nil, !DemoData.isActive else { return }
        verifyAfterUpdate()
        loop = Task {
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                if Self.autoCheck { await check() }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    /// Asks GitHub for the latest release. Sends nothing about this Mac.
    func check() async {
        if case .installing = state { return }
        state = .checking
        do {
            var request = URLRequest(url: AppRelease.latestAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = AppRelease.parse(data) else {
                state = .failed("Couldn’t read the latest release from GitHub.")
                return
            }
            lastChecked = .now
            state = AppRelease.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed("Couldn’t check for updates: \(error.localizedDescription)")
        }
    }

    // MARK: Install

    private var homebrew: (brew: String, caskroom: URL)? {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let caskroom = URL(fileURLWithPath: "\(prefix)/Caskroom/hyena")
            if FileManager.default.fileExists(atPath: caskroom.path),
               FileManager.default.isExecutableFile(atPath: "\(prefix)/bin/brew") {
                return ("\(prefix)/bin/brew", caskroom)
            }
        }
        return nil
    }

    /// Only an installed copy updates itself; development builds open the release page.
    private var isInstalledApp: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func install() {
        guard let release = available else { return }
        guard isInstalledApp else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        Task {
            if let cask = homebrew {
                installWithHomebrew(cask.brew, release: release)
            } else if let dmg = release.dmgURL {
                await installFromDMG(dmg, release: release)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// Homebrew quits Hyena while upgrading it, so the upgrade runs in a small script after
    /// Hyena has quit, then reopens it. The next launch checks the version and falls back to
    /// the verified DMG if Homebrew didn't deliver.
    private func installWithHomebrew(_ brew: String, release: AppRelease) {
        state = .installing("Updating with Homebrew…")
        let app = Bundle.main.bundleURL.path
        let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
            git -C "$("\(brew)" --repository hyena-app/tap)" pull --ff-only --quiet
            "\(brew)" upgrade --cask hyena-app/tap/hyena || "\(brew)" reinstall --cask hyena-app/tap/hyena
            /usr/bin/open "\(app)"
            """
        UserDefaults.standard.set(release.version, forKey: Self.expectedKey)
        launchDetached(script)
        NSApp.terminate(nil)
    }

    /// After an update restart: if this isn't the version we updated to, finish it from the DMG.
    private func verifyAfterUpdate() {
        guard let expected = UserDefaults.standard.string(forKey: Self.expectedKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.expectedKey)
        guard AppRelease.isNewer(expected, than: currentVersion) else { return }
        Task {
            await check()
            guard let release = available, let dmg = release.dmgURL, isInstalledApp else {
                state = .failed("The update to \(expected) didn’t install. Download it from GitHub instead.")
                return
            }
            await installFromDMG(dmg, release: release)
        }
    }

    private func installFromDMG(_ url: URL, release: AppRelease) async {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("hyena-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mount")
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            state = .installing("Downloading Hyena \(release.version)…")
            let (downloaded, _) = try await URLSession.shared.download(from: url)
            let dmg = work.appendingPathComponent("Hyena.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            state = .installing("Checking the download…")
            let attach = try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path])
            guard attach.status == 0 else { throw UpdateError("Couldn’t open the downloaded disk image.") }
            defer { Task.detached { _ = try? await UpdateService.runDetached("/usr/bin/hdiutil", ["detach", "-force", mount.path]) } }
            let staged = work.appendingPathComponent("Hyena.app")
            let copy = try await run("/usr/bin/ditto", [mount.appendingPathComponent("Hyena.app").path, staged.path])
            guard copy.status == 0 else { throw UpdateError("Couldn’t copy the new version.") }
            try await verify(staged)

            state = .installing("Installing…")
            UserDefaults.standard.set(release.version, forKey: Self.expectedKey)
            let current = Bundle.main.bundleURL
            let backup = work.appendingPathComponent("Hyena-old.app")
            try FileManager.default.moveItem(at: current, to: backup)
            do {
                try FileManager.default.moveItem(at: staged, to: current)
            } catch {
                try? FileManager.default.moveItem(at: backup, to: current)  // put the old one back
                throw UpdateError("Couldn’t replace the app (\(error.localizedDescription)).")
            }
            relaunch()
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    /// Same developer as the running app, sealed, and accepted by Gatekeeper (notarized).
    private func verify(_ app: URL) async throws {
        let seal = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard seal.status == 0 else { throw UpdateError("The new version’s signature doesn’t check out, so it wasn’t installed.") }
        let info = try await run("/usr/bin/codesign", ["-dv", app.path])
        guard info.output.contains("TeamIdentifier=\(Self.teamID)") else {
            throw UpdateError("The new version isn’t signed by Hyena’s developer, so it wasn’t installed.")
        }
        let gatekeeper = try await run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        guard gatekeeper.status == 0 else { throw UpdateError("macOS didn’t accept the new version (not notarized), so it wasn’t installed.") }
    }

    private func relaunch() {
        state = .installing("Restarting…")
        let path = Bundle.main.bundleURL.path
        launchDetached("while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(path)\"")
        NSApp.terminate(nil)
    }

    private func launchDetached(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
    }

    private func run(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await Self.runDetached(tool, arguments)
    }

    /// Runs a tool off the main thread so the UI never stalls.
    nonisolated static func runDetached(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    struct UpdateError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
