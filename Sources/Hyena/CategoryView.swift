import SwiftUI
import AppKit
import HyenaCore

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory
    @State private var expanded: Set<String> = []
    @State private var query = ""

    var body: some View {
        let items = filtered
        List {
            Section {
                CategoryHeader(category: category)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                if category == .trash && model.needsFullDiskAccess {
                    PermissionBanner().listRowSeparator(.hidden)
                }
                if category == .projects && model.roots.isEmpty {
                    ProjectFoldersPrompt().listRowSeparator(.hidden)
                }
            }

            if items.isEmpty {
                EmptyCategory(category: category).listRowSeparator(.hidden)
            } else if category == .projects {
                ForEach(groupedByKind(items), id: \.kind) { group in
                    Section {
                        rows(for: group.items)
                    } header: {
                        Label(group.kind.title, systemImage: group.kind.symbol)
                            .badge(space(group.items.reduce(0) { $0 + $1.bytes }))
                    }
                }
            } else {
                Section { rows(for: items) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .toolbar, prompt: "Filter \(category.title)")
        .navigationTitle(category.title)
        .onChange(of: category) { expanded = []; query = "" }
    }

    private var filtered: [Finding] {
        let items = model.findings(in: category)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    private func groupedByKind(_ items: [Finding]) -> [(kind: ArtifactKind, items: [Finding])] {
        Dictionary(grouping: items) { $0.kind ?? .node }
            .map { (kind: $0.key, items: $0.value) }
            .sorted { $0.items.reduce(0) { $0 + $1.bytes } > $1.items.reduce(0) { $0 + $1.bytes } }
    }

    @ViewBuilder
    private func rows(for items: [Finding]) -> some View {
        ForEach(items) { finding in
            FindingRow(finding: finding, expanded: $expanded)
            if expanded.contains(finding.url.path) {
                ChildRows(finding: finding, parent: finding.url, depth: 1, expanded: $expanded)
            }
        }
    }
}

private struct CategoryHeader: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CategoryIcon(category: category, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(category.summary).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(category == .snapshots ? "\(model.selectedCount(in: category)) selected"
                                            : space(model.selectedBytes(in: category)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Menu {
                    Button("Recommended") { model.select(.recommended, in: category) }
                    Button("Select All") { model.select(.all, in: category) }
                    Button("Select None") { model.select(.none, in: category) }
                } label: {
                    Text("\(model.selectedCount(in: category)) of \(model.findings(in: category).count) selected")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.findings(in: category).isEmpty)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 20, tint: Theme.tint(for: category))
        .animation(.smooth, value: model.selectedBytes(in: category))
    }
}

private struct EmptyCategory: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory

    var body: some View {
        Group {
            if model.scanning {
                ContentUnavailableView {
                    Label("Scanning…", systemImage: "magnifyingglass")
                } description: { Text(model.scanSummary) }
            } else if model.lastScan == nil {
                ContentUnavailableView {
                    Label("Not scanned yet", systemImage: category.symbol)
                } actions: {
                    Button("Scan My Mac") { model.scan() }.prominentButton()
                }
            } else {
                ContentUnavailableView {
                    Label("All clean", systemImage: "checkmark.seal")
                } description: {
                    Text("Nothing here right now.")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

private struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    @Binding var expanded: Set<String>
    @State private var explaining = false
    @State private var hovering = false

    var body: some View {
        let isOpen = expanded.contains(finding.url.path)
        let state = model.state(of: finding)
        HStack(spacing: 10) {
            DisclosureChevron(isOpen: isOpen, visible: canExpand) {
                if isOpen { expanded.remove(finding.url.path) } else {
                    expanded.insert(finding.url.path)
                    model.loadChildren(of: finding.url)
                }
            }
            TriStateCheckbox(state: state, label: "Select \(finding.title)") { model.toggle(finding) }
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.title).font(.body.weight(.medium)).lineLimit(1)
                    if !finding.recommended { Pill(text: "Review", color: .orange) }
                    if finding.action != .moveToTrash { Pill(text: "Permanent", color: .red) }
                    if state == .mixed { Pill(text: "Partial", color: Theme.accent) }
                    if model.learnedKeep(finding) { Pill(text: "Usually kept", color: .blue) }
                    if model.learnedClean(finding) { Pill(text: "Usually cleaned", color: .green) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let note = finding.note {
                    Label(note, systemImage: "info.circle").font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Button { explaining = true } label: {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .help("What is this?")
            .opacity(hovering || explaining ? 1 : 0)
            .accessibilityLabel("Explain \(finding.title)")
            .popover(isPresented: $explaining, arrowEdge: .trailing) {
                ExplainPopover(facts: facts)
            }
            if finding.hasKnownSize {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(space(state == .mixed ? model.selection.selectedBytes(of: finding) : finding.bytes))
                        .font(.body.weight(.semibold)).monospacedDigit()
                    if state == .mixed {
                        Text("of \(space(finding.bytes))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(finding.modified.formatted(.relative(presentation: .named)))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(state == .off ? 0.7 : 1)
        .onTapGesture(count: 2) { reveal() }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .help(finding.kind?.consequence ?? finding.url.path)
    }

    private var facts: ItemFacts {
        let contents = (model.children(of: finding.url.path) ?? []).prefix(10).map(\.name)
        let owner = finding.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { $0.deletingPathExtension().lastPathComponent }
        return ItemFacts(finding: finding, owningApp: owner, contents: Array(contents))
    }

    private var canExpand: Bool {
        guard finding.action != .moveToTrash || finding.hasKnownSize else { return false }
        if case .deleteSnapshot = finding.action { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: finding.url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var subtitle: String {
        if case .deleteSnapshot = finding.action { return "Local APFS snapshot on Macintosh HD" }
        let path = finding.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if finding.category == .projects, let kind = finding.kind { return "\(kind.shortTitle) · \(path)" }
        return path
    }

    @ViewBuilder private var icon: some View {
        if let image = Icons.icon(for: finding) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else if let kind = finding.kind {
            Image(systemName: kind.symbol).font(.title3).foregroundStyle(Theme.tint(for: .projects))
        } else if case .deleteSnapshot = finding.action {
            Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.teal)
        } else {
            Image(nsImage: Icons.fileIcon(finding.url)).resizable()
        }
    }

    @ViewBuilder private var menu: some View {
        Button("What Is This?") { explaining = true }
        if finding.hasKnownSize {
            Button("Show in Finder") { reveal() }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finding.url.path, forType: .string)
            }
            Divider()
            Button("Never Clean This") { model.protect(finding.url) }
            if finding.category == .projects {
                Button("Never Clean This Project") { model.protect(finding.url.deletingLastPathComponent()) }
            }
        }
    }

    private func reveal() {
        guard finding.hasKnownSize else { return }
        NSWorkspace.shared.activateFileViewerSelecting([finding.url])
    }
}

/// Lazily loaded contents of an expanded folder, each checkable.
private struct ChildRows: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let parent: URL
    let depth: Int
    @Binding var expanded: Set<String>

    var body: some View {
        if let entries = model.children(of: parent.path) {
            if entries.isEmpty {
                Text("Empty folder").font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, indent + 34)
            }
            ForEach(entries.prefix(500)) { entry in
                ChildRow(finding: finding, entry: entry, depth: depth, expanded: $expanded)
                if entry.isDirectory && expanded.contains(entry.url.path) {
                    // AnyView breaks the recursive opaque type.
                    AnyView(ChildRows(finding: finding, parent: entry.url, depth: depth + 1, expanded: $expanded))
                }
            }
            if entries.count > 500 {
                Text("\(entries.count - 500) more items not shown").font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, indent + 34)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring contents…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, indent + 34)
        }
    }

    private var indent: CGFloat { CGFloat(depth) * 22 }
}

private struct ChildRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let entry: FileEntry
    let depth: Int
    @Binding var expanded: Set<String>
    @State private var explaining = false

    var body: some View {
        let isOpen = expanded.contains(entry.url.path)
        let state = model.state(of: entry, in: finding)
        HStack(spacing: 10) {
            DisclosureChevron(isOpen: isOpen, visible: entry.isDirectory) {
                if isOpen { expanded.remove(entry.url.path) } else {
                    expanded.insert(entry.url.path)
                    model.loadChildren(of: entry.url)
                }
            }
            TriStateCheckbox(state: state, label: "Select \(entry.name)") { model.toggle(entry, in: finding) }
            Image(nsImage: Icons.fileIcon(entry.url)).resizable().frame(width: 18, height: 18)
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            if entry.modified > .distantPast {
                Text(entry.modified.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Text(space(entry.bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(depth) * 22)
        .opacity(state == .off ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        .popover(isPresented: $explaining, arrowEdge: .trailing) {
            ExplainPopover(facts: ItemFacts(
                entry: entry, in: finding,
                contents: (model.children(of: entry.url.path) ?? []).prefix(10).map(\.name)
            ))
        }
        .contextMenu {
            Button("What Is This?") { explaining = true }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button("Never Clean This") { model.protect(entry.url) }
        }
    }
}

private struct DisclosureChevron: View {
    let isOpen: Bool
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
        .animation(.smooth(duration: 0.2), value: isOpen)
        .accessibilityLabel(isOpen ? "Collapse" : "Show contents")
    }
}
