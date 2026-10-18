import SwiftUI
import HyenaCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var route: Route?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Hero()
                if !model.discoveredRoots.isEmpty { DiscoveredFoldersBanner() }
                if model.lastScan != nil && !model.scanning { StorageChartCard(route: $route) }
                if !model.insights.isEmpty && !model.scanning { InsightsCard() }
                if !model.scanning { SuggestionsCard() }
                if model.needsFullDiskAccess && (model.categories.contains(.trash) || model.categories.contains(.devices)) {
                    PermissionBanner()
                }
                if model.lastScan != nil || model.scanning {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What Hyena found").font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                            ForEach(model.visibleCategories) { category in
                                CategoryTile(category: category) { route = .category(category) }
                            }
                        }
                    }
                }
                if model.categories.contains(.projects) && model.roots.isEmpty {
                    ProjectFoldersPrompt()
                }
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Smart Clean")
        .background(OverviewBackground())
    }
}

private struct OverviewBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .topTrailing,
                           startRadius: 20, endRadius: 700)
            RadialGradient(colors: [Theme.night.opacity(0.12), .clear], center: .bottomLeading,
                           startRadius: 20, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

private struct Hero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 32) {
            ZStack {
                StorageRing()
                    .frame(width: 190, height: 190)
                HyenaMark(size: 92)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    .scaleEffect(model.scanning && !reduceMotion ? 0.94 : 1)
                    .animation(model.scanning && !reduceMotion
                               ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                               value: model.scanning)
            }

            VStack(alignment: .leading, spacing: 10) {
                if model.scanning {
                    Text("Sniffing around…").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(model.scanSummary).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.opacity)
                    ProgressView(value: model.scanFraction).progressViewStyle(.linear).frame(maxWidth: 280)
                        .animation(.smooth, value: model.scanFraction)
                } else if let result = model.lastResult, result.count > 0 {
                    ResultSummary(result: result)
                } else if model.lastScan != nil {
                    Text(space(model.selectedBytes))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(model.selectedBytes > 0 ? "ready to clean · recommended items are preselected"
                                                 : "Your Mac is looking tidy.")
                        .font(.title3).foregroundStyle(.secondary)
                    StorageLegend()
                    HStack(spacing: 10) {
                        Button {
                            model.presentCleanSheet = true
                        } label: {
                            Label("Clean Now", systemImage: "sparkles")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        .controlSize(.extraLarge)
                        .prominentButton()
                        .disabled(model.selectedFindings.isEmpty || model.busy)
                        Button {
                            model.presentAskSheet = true
                        } label: {
                            Label("Ask Hyena", systemImage: "text.bubble")
                                .font(.title3)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                        .controlSize(.extraLarge)
                        .secondaryButton()
                        Button { model.scan() } label: {
                            Label("Sniff Again", systemImage: "arrow.clockwise")
                                .font(.title3)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                        .controlSize(.extraLarge)
                        .secondaryButton()
                        .help("Measure everything again (⌘R)")
                        .disabled(model.busy)
                    }
                    .padding(.top, 6)
                } else {
                    Text("Make room to build.").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Hyena finds caches, logs, leftovers and build files that pile up on a developer’s Mac. You choose what goes.")
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.scan()
                    } label: {
                        Label("Scan My Mac", systemImage: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .controlSize(.extraLarge)
                    .prominentButton()
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .glassCard(cornerRadius: 28)
        .animation(reduceMotion ? nil : .smooth, value: model.phase)
    }
}

private struct ResultSummary: View {
    @Environment(AppModel.self) private var model
    let result: CleanResult

    var body: some View {
        Label("All done", systemImage: "checkmark.seal.fill")
            .font(.headline).foregroundStyle(.green)
        Text(space(result.movedBytes + result.freedBytes))
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
        Text(result.movedBytes > 0 ? "moved to Trash. Empty it to get the space back."
                                   : "cleaned. That space is yours again.")
            .font(.title3).foregroundStyle(.secondary)
        HStack {
            if result.movedBytes > 0 {
                Button { model.emptyTrash() } label: {
                    Label("Empty Trash", systemImage: "trash")
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .controlSize(.large)
                .prominentButton()
            }
            Button("Sniff Again") { model.scan() }
                .controlSize(.large)
                .secondaryButton()
        }
        .padding(.top, 6)
    }
}

/// Donut showing used space with the selected cleanup carved out in amber.
/// Small key under the headline that ties the ring's colors to real numbers.
private struct StorageLegend: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanable = min(model.selectedBytes, model.usedBytes)
        HStack(spacing: 14) {
            // "Used" is the whole used space everywhere in the app; the ring shows the
            // ready-to-clean part of it in amber.
            item(color: .primary.opacity(0.5), label: "Used", value: model.usedBytes)
            item(color: Theme.accent, label: "Ready to clean", value: cleanable)
            item(color: .primary.opacity(0.12), label: "Free", value: model.available)
            Text("of \(space(model.capacity)) · Macintosh HD")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }

    private func item(color: Color, label: String, value: Int64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(space(value)).fontWeight(.medium)
                .contentTransition(.numericText())
        }
    }
}

private struct StorageRing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = max(Double(model.capacity), 1)
        let cleanable = min(Double(model.selectedBytes), Double(model.usedBytes)) / total
        let used = Double(model.usedBytes) / total
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: 16)
            Circle().trim(from: 0, to: used - cleanable)
                .stroke(.primary.opacity(0.5), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            Circle().trim(from: used - cleanable, to: used)
                .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
        }
        .rotationEffect(.degrees(-90))
        .animation(.smooth(duration: 0.6), value: model.selectedBytes)
        .accessibilityElement()
        .accessibilityLabel("Disk usage")
        .accessibilityValue("\(space(model.usedBytes)) of \(space(model.capacity)) used")
    }
}

private struct CategoryTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: CleanupCategory
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let interactive = !model.scanning
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    CategoryIcon(category: category, size: 36)
                    Spacer()
                    trailingAccessory
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.opacity)
                }
                Text(sizeText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isPending ? .tertiary : model.findings(in: category).isEmpty && interactive
                                     ? .secondary : .primary)
                    .contentTransition(.numericText())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, tint: hovering && interactive ? Theme.tint(for: category) : nil)
            .scaleEffect(hovering && interactive ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // Results land all at once when the scan ends; until then a tile is a status, not a link.
        .allowsHitTesting(interactive)
        .onHover { hovering = $0 }
        .onChange(of: model.scanning) { if model.scanning { hovering = false } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hovering)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: model.measured[category]?.bytes)
        .accessibilityHint(interactive ? "Shows the items in \(category.title)" : "")
    }

    /// Still being measured in the current scan.
    private var isPending: Bool {
        model.scanning && model.measured[category] == nil && !(category == .projects && model.roots.isEmpty)
    }

    @ViewBuilder private var trailingAccessory: some View {
        if isPending {
            ProgressView().controlSize(.small)
        } else if model.scanning && model.measured[category] != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        } else if !model.findings(in: category).isEmpty {
            let selected = model.selectedCount(in: category)
            let total = model.findings(in: category).count
            TriStateCheckbox(state: selected == 0 ? .off : selected == total ? .on : .mixed,
                             label: "Include \(category.title)") {
                model.select(selected == 0 ? .recommended : .none, in: category)
                if selected == 0 && model.selectedCount(in: category) == 0 { model.select(.all, in: category) }
            }
        }
    }

    private var sizeText: String {
        if model.scanning {
            guard let measured = model.measured[category] else { return "—" }
            if category == .snapshots { return measured.count == 0 ? "None" : "\(measured.count) found" }
            return measured.count == 0 ? "Clean" : space(measured.bytes)
        }
        let items = model.findings(in: category)
        if category == .snapshots { return items.isEmpty ? "None" : "\(items.count) snapshot\(items.count == 1 ? "" : "s")" }
        if category == .trash && model.needsFullDiskAccess { return "Needs access" }
        return items.isEmpty ? "Clean" : space(model.selectedBytes(in: category))
    }

    private var detail: String {
        if model.scanning {
            guard let measured = model.measured[category] else {
                return category == .projects && model.roots.isEmpty ? "No project folders yet" : "Scanning…"
            }
            return measured.count == 0 ? "Nothing to clean" : "\(measured.count) item\(measured.count == 1 ? "" : "s") found"
        }
        let items = model.findings(in: category)
        if items.isEmpty {
            return category == .projects && model.roots.isEmpty ? "Add project folders to scan" : "Nothing to clean"
        }
        return "\(model.selectedCount(in: category)) of \(items.count) selected · \(space(model.totalBytes(in: category))) found"
    }
}

struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.title).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Allow Full Disk Access to see Trash and device backups").font(.headline)
                Text("macOS protects these folders. Grant access in System Settings, then scan again. You can still empty Trash with Finder.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Empty with Finder") { model.emptyTrash() }.secondaryButton()
            Button("Open Settings") { model.openFullDiskAccessSettings() }.prominentButton()
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }
}

struct ProjectFoldersPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryIcon(category: .projects, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your project folders").font(.headline)
                    Text("Hyena finds node_modules, target, .build, DerivedData-style outputs and more inside them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                ForEach(model.suggestedRoots.prefix(4), id: \.path) { url in
                    Button { model.addRoot(url) } label: {
                        Label("~/" + url.path.replacingOccurrences(of: NSHomeDirectory() + "/", with: ""),
                              systemImage: "plus")
                    }
                    .secondaryButton()
                }
                Button("Choose Folder…") { model.addFolder() }.prominentButton()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }
}

/// Shown once after Hyena finds project folders by itself.
private struct DiscoveredFoldersBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: .projects, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hyena found your projects").font(.headline)
                Text("Scanning " + model.discoveredRoots
                        .map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                        .joined(separator: ", ") + " for build files. Add or remove folders any time.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Edit…") { NSApp.activate(ignoringOtherApps: true); openSettings() }.secondaryButton()
            Button("Got It") { withAnimation(.smooth) { model.discoveredRoots = [] } }.prominentButton()
        }
        .padding(16)
        .glassCard(cornerRadius: 18, tint: Theme.tint(for: .projects))
    }
}
