import SwiftUI
import AppKit
import HyenaCore

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
            exit(MainActor.assumeIsolated { IconExporter.run(output: arguments[index + 1]) })
        }
        if let index = arguments.firstIndex(of: "--ai-check") {
            // Developer check: exercises the assistant without opening the UI.
            let request = index + 1 < arguments.count ? arguments[index + 1] : "clean old rust builds except work"
            Task { @MainActor in
                print("Status:", Assistant.status)
                let interpretation = await Assistant.interpret(request)
                print("Model used:", interpretation.usedModel, "\nRule:", interpretation.rule.summary)
                let facts = ItemFacts(finding: Finding(
                    url: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/com.spotify.client"),
                    root: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches"), category: .userCaches,
                    title: "Spotify", bytes: 1_200_000_000, modified: Date(), inode: 1, device: 1
                ))
                let suggestions = [
                    Suggestion(id: "a", kind: .bigCache, title: "npm is 26.6 GB", detail: "Packages re-download on demand.",
                               bytes: 26_600_000_000, action: .select([]), priority: 70),
                    Suggestion(id: "b", kind: .staleProjects, title: "Clear builds from 4 idle projects",
                               detail: "Not touched in 60+ days.", bytes: 9_000_000_000, action: .select([]), priority: 60),
                    Suggestion(id: "c", kind: .trash, title: "Trash is holding 3 GB", detail: "Not freed until emptied.",
                               bytes: 3_000_000_000, action: .emptyTrash, priority: 40),
                    Suggestion(id: "d", kind: .growth, title: "Gradle grew 2 GB", detail: "In the last 7 days.",
                               bytes: 5_000_000_000, action: .select([]), priority: 55),
                ]
                let picked = await Assistant.personalize(
                    suggestions, profile: "Often cleans: Project Builds (5x)\nDismissed suggestions about: trash (3x)"
                )
                print("Suggestions (model: \(picked.usedModel)):")
                for item in picked.items { print(" -", item.title, "—", item.detail) }
                print("Explain:", (try? await Assistant.explain(facts)).map { "\($0)" } ?? "failed")
                exit(0)
            }
            RunLoop.main.run()
        }
        HyenaApp.main()
    }
}

struct HyenaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Hyena", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .tint(Theme.accent)
                .onAppear { DockPresence.windowDidOpen() }
                .onDisappear { DockPresence.windowDidClose() }
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Again") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.busy)
                Button("Clean Now…") { model.presentCleanSheet = true }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy || model.selectedFindings.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.accent)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Lives as long as the app, so it can open the window on request
/// (for example from the menu bar or a reminder notification).
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: HyenaGlyph.menuBarImage)
            .onChange(of: model.openWindowRequest) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// Menu-bar apps show a Dock icon only while their main window is open.
@MainActor
enum DockPresence {
    static func windowDidOpen() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowDidClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}
