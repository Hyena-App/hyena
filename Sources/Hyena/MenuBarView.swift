import SwiftUI
import AppKit
import HyenaCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HyenaMark(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hyena").font(.headline)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Open Hyena") { openMain() }
                    Button("Settings…") { NSApp.activate(ignoringOtherApps: true); openSettings() }
                    Divider()
                    Button("Quit Hyena") { NSApp.terminate(nil) }.disabled(model.phase == .cleaning)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            StorageSummary()

            VStack(alignment: .leading, spacing: 10) {
                if model.scanning {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.scanSummary).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 64)
                } else if model.lastScan != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(space(model.selectedBytes))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("ready to clean").foregroundStyle(.secondary)
                    }
                    ForEach(topCategories, id: \.self) { category in
                        HStack(spacing: 8) {
                            CategoryIcon(category: category, size: 18)
                            Text(category.title).font(.callout)
                            Spacer()
                            Text(space(model.selectedBytes(in: category))).font(.callout).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Find caches and build files you can clean.").foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .glassCard(cornerRadius: 14)

            if !model.scanning, let top = model.suggestions.first {
                Button {
                    openMain()
                    model.act(on: top)
                } label: {
                    SuggestionRow(suggestion: top, compact: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 12, tint: Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Review this suggestion")
            }

            if model.phase == .cleaning {
                ProgressView(value: Double(model.cleanProgress), total: Double(max(model.cleanTotal, 1))) {
                    Text("Cleaning…")
                }
            } else if model.lastScan == nil && !model.scanning {
                wideButton("Scan My Mac", symbol: "magnifyingglass") { model.scan() }
            } else {
                wideButton("Clean Now", symbol: "sparkles") {
                    openMain()
                    model.presentCleanSheet = true
                }
                .disabled(model.selectedFindings.isEmpty || model.busy)
                HStack {
                    Button("Review Items…") { openMain() }
                    Spacer()
                    Button("Sniff Again") { model.scan() }.disabled(model.busy)
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { model.refreshStorage() }
    }

    private var status: String {
        if model.scanning { return "Scanning…" }
        if model.phase == .cleaning { return "Cleaning…" }
        if let last = model.lastScan { return "Scanned \(last.formatted(.relative(presentation: .named)))" }
        return "Ready when you are"
    }

    private var topCategories: [CleanupCategory] {
        model.visibleCategories
            .filter { model.selectedBytes(in: $0) > 0 }
            .sorted { model.selectedBytes(in: $0) > model.selectedBytes(in: $1) }
            .prefix(4).map { $0 }
    }

    private func openMain() {
        model.openWindowRequest += 1
    }

    private func wideButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .controlSize(.large)
        .prominentButton()
    }
}
