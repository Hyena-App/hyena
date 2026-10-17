import SwiftUI
import HyenaCore

enum Route: Hashable {
    case overview
    case category(CleanupCategory)
    case history
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var route: Route? = .overview
    @State private var backStack: [Route] = []
    @State private var forwardStack: [Route] = []
    @State private var navigatingHistory = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(route: $route)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            Group {
                switch route ?? .overview {
                case .overview: OverviewView(route: $route)
                case .category(let category): CategoryView(category: category)
                case .history: HistoryView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if route != .history { CleanBar() }
            }
        }
        .onChange(of: route) { old, _ in
            // Sidebar clicks and tiles push history; back/forward moves through it.
            guard !navigatingHistory, let old else { navigatingHistory = false; return }
            backStack.append(old)
            backStack = Array(backStack.suffix(50))
            forwardStack.removeAll()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: goBack) { Label("Back", systemImage: "chevron.left") }
                    .help("Back (⌘[)")
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(backStack.isEmpty)
                Button(action: goForward) { Label("Forward", systemImage: "chevron.right") }
                    .help("Forward (⌘])")
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(forwardStack.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.presentAskSheet = true } label: {
                    Label("Ask Hyena", systemImage: "text.bubble")
                }
                .help("Describe what to clean (⌘K)")
                .keyboardShortcut("k")
                .disabled(model.busy || model.findings.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                if model.scanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning \(Int(model.scanFraction * 100))%").font(.callout).foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1).frame(maxWidth: 180, alignment: .leading)
                        Button("Stop") { model.cancelScan() }
                    }
                } else {
                    Button { model.scan() } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                    .help("Scan again (⌘R)")
                    .disabled(model.busy)
                }
            }
        }
        .sheet(isPresented: $model.presentCleanSheet) {
            CleanSheet()
        }
        .sheet(isPresented: $model.presentAskSheet) {
            AskHyenaSheet()
        }
    }
}

extension MainWindow {
    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = route { forwardStack.append(current) }
        navigatingHistory = true
        route = previous
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = route { backStack.append(current) }
        navigatingHistory = true
        route = next
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var route: Route?

    var body: some View {
        List(selection: $route) {
            NavigationLink(value: Route.overview) {
                Label("Smart Clean", systemImage: "sparkles")
            }

            ForEach(CleanupGroup.allCases) { group in
                let items = model.visibleCategories.filter { $0.group == group }
                if !items.isEmpty {
                    Section(group.title) {
                        ForEach(items) { category in
                            NavigationLink(value: Route.category(category)) {
                                Label { Text(category.title) } icon: { CategoryIcon(category: category, size: 20) }
                            }
                            .badge(badge(for: category))
                        }
                    }
                }
            }

            Section {
                NavigationLink(value: Route.history) {
                    Label("History", systemImage: "clock")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { StorageFooter().padding(12) }
    }

    private func badge(for category: CleanupCategory) -> Text? {
        guard model.lastScan != nil else { return nil }
        if category == .snapshots {
            let count = model.findings(in: .snapshots).count
            return count > 0 ? Text("\(count)") : nil
        }
        let bytes = model.totalBytes(in: category)
        return bytes > 0 ? Text(space(bytes)) : nil
    }
}

private struct StorageFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive")
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
            }
            StorageBar(height: 6)
            Text("\(space(model.available)) available of \(space(model.capacity))")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

/// Used, cleanable-selected and free space in one bar.
struct StorageBar: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(model.capacity), 1)
            let cleanable = min(Double(model.selectedBytes), Double(model.usedBytes))
            let used = Double(model.usedBytes) - cleanable
            HStack(spacing: 1.5) {
                Capsule().fill(.primary.opacity(0.55))
                    .frame(width: proxy.size.width * used / total)
                Capsule().fill(Theme.accent.gradient)
                    .frame(width: max(cleanable > 0 ? 3 : 0, proxy.size.width * cleanable / total))
                Spacer(minLength: 0)
            }
            .background(.primary.opacity(0.08), in: Capsule())
        }
        .frame(height: height)
        .animation(.smooth, value: model.selectedBytes)
        .accessibilityElement()
        .accessibilityLabel("Storage")
        .accessibilityValue("\(space(model.usedBytes)) used, \(space(model.selectedBytes)) selected to clean, \(space(model.available)) available")
    }
}

/// Persistent bottom bar: what's selected and the Clean Now button.
struct CleanBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedFindings.isEmpty ? "Nothing selected" : "\(space(model.selectedBytes)) selected")
                    .font(.headline).monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .cleaning {
                ProgressView(value: Double(model.cleanProgress), total: Double(max(model.cleanTotal, 1)))
                    .frame(width: 120)
            }
            Button {
                model.presentCleanSheet = true
            } label: {
                Label("Clean Now", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
            }
            .controlSize(.large)
            .prominentButton()
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.busy || model.selectedFindings.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(.smooth, value: model.selectedBytes)
    }

    private var subtitle: String {
        if model.scanning { return model.scanSummary }
        if model.lastScan == nil { return "Scan to find what you can clean." }
        let count = model.selectedFindings.count
        return "\(count) item\(count == 1 ? "" : "s") from \(Set(model.selectedFindings.map(\.category)).count) categories · you review before anything is removed"
    }
}
