import SwiftUI
import HyenaCore

/// Disk composition and where the cleanable space sits.
///
/// Colors follow the chart palette validated with the dataviz checks
/// (categorical slots blue / orange / aqua, light and dark steps). Light-mode
/// segments fall under 3:1 against the surface, so every segment is also named
/// with its value in the legend: identity never rests on color alone.
struct StorageChartCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Binding var route: Route?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DiskBar()
            Divider().opacity(0.4)
            CategoryBars(route: $route)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }
}

enum ChartPalette {
    // Fixed order, never cycled: everyday → orange (closest to the brand), developer → blue, projects → aqua.
    static func color(for group: CleanupGroup, scheme: ColorScheme) -> Color {
        switch (group, scheme) {
        case (.system, .dark): Color(hex: 0xD95926)
        case (.system, _): Color(hex: 0xEB6834)
        case (.developer, .dark): Color(hex: 0x3987E5)
        case (.developer, _): Color(hex: 0x2A78D6)
        case (.projects, .dark): Color(hex: 0x199E70)
        case (.projects, _): Color(hex: 0x1BAF7A)
        }
    }
    static let otherUsed = Color.primary.opacity(0.32)
    static let free = Color.primary.opacity(0.07)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Disk composition

private struct DiskBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: String?

    struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: Int64
        let color: Color
        let isFree: Bool
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var found: Int64 = 0
        for group in CleanupGroup.allCases {
            let bytes = model.findings.filter { $0.category.group == group }.reduce(0) { $0 + $1.bytes }
            found += bytes
            guard bytes > 0 else { continue }
            result.append(Segment(id: group.rawValue, label: label(for: group), bytes: bytes,
                                  color: ChartPalette.color(for: group, scheme: scheme), isFree: false))
        }
        // Clamp so estimates never exceed what the volume reports as used.
        let used = model.usedBytes
        if found > used, used > 0 {
            let scale = Double(used) / Double(found)
            result = result.map { Segment(id: $0.id, label: $0.label, bytes: Int64(Double($0.bytes) * scale),
                                          color: $0.color, isFree: false) }
            found = used
        }
        result.append(Segment(id: "other", label: "Other used", bytes: max(0, used - found),
                              color: ChartPalette.otherUsed, isFree: false))
        result.append(Segment(id: "free", label: "Free", bytes: model.available, color: ChartPalette.free, isFree: true))
        return result
    }

    private func label(for group: CleanupGroup) -> String {
        switch group {
        case .system: "Everyday junk"
        case .developer: "Developer junk"
        case .projects: "Project builds"
        }
    }

    var body: some View {
        let segments = segments
        let total = max(Double(model.capacity), 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Macintosh HD", systemImage: "internaldrive").font(.headline)
                Spacer()
                Text("\(space(model.usedBytes)) used of \(space(model.capacity))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }

            GeometryReader { proxy in
                let gaps = CGFloat(segments.filter { $0.bytes > 0 }.count - 1) * 2
                let width = max(0, proxy.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(segments.filter { $0.bytes > 0 }) { segment in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(3, width * Double(segment.bytes) / total))
                            .opacity(hovered == nil || hovered == segment.id ? 1 : 0.35)
                            .onHover { inside in hovered = inside ? segment.id : (hovered == segment.id ? nil : hovered) }
                            .help("\(segment.label): \(space(segment.bytes))")
                    }
                }
            }
            .frame(height: 22)
            .animation(.smooth(duration: 0.25), value: hovered)
            .accessibilityElement()
            .accessibilityLabel("Disk usage")
            .accessibilityValue(segments.map { "\($0.label) \(space($0.bytes))" }.joined(separator: ", "))

            // Legend: always present, with values, so color is never the only cue.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(segment.color)
                            .overlay { if segment.isFree { RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5)) } }
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(segment.label).font(.callout)
                            Text("\(space(segment.bytes)) · \(percent(segment.bytes, of: total))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .opacity(hovered == nil || hovered == segment.id ? 1 : 0.5)
                    .onHover { inside in hovered = inside ? segment.id : nil }
                }
            }
        }
    }

    private func percent(_ bytes: Int64, of total: Double) -> String {
        let value = Double(bytes) / total * 100
        return value < 1 && bytes > 0 ? "<1%" : "\(Int(value.rounded()))%"
    }
}

// MARK: - Cleanable space by category

/// Ranked, collapsible rows: each category's bar shows found (light) and
/// selected (solid); expanding it lists its largest items.
private struct CategoryBars: View {
    @Environment(AppModel.self) private var model
    @Binding var route: Route?
    @State private var expanded: Set<CleanupCategory> = []

    struct Row: Identifiable {
        var id: CleanupCategory { category }
        let category: CleanupCategory
        let bytes: Int64
        let selectedBytes: Int64
        let count: Int
        let selectedCount: Int
    }

    private var rows: [Row] {
        model.visibleCategories
            .map { Row(category: $0, bytes: model.totalBytes(in: $0), selectedBytes: model.selectedBytes(in: $0),
                       count: model.findings(in: $0).count, selectedCount: model.selectedCount(in: $0)) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        let rows = rows
        let largest = Double(rows.first?.bytes ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the cleanable space is").font(.headline)
                Spacer()
                HStack(spacing: 14) {
                    legendSwatch(Theme.accent, "Selected to clean")
                    legendSwatch(Theme.accent.opacity(0.28), "Found")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text("Scan to see where space is going.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(rows) { row in
                        CategoryBarRow(row: row, largest: largest, isExpanded: expanded.contains(row.category),
                                       toggle: { toggle(row.category) }, open: { route = .category(row.category) })
                    }
                }
            }
        }
    }

    private func toggle(_ category: CleanupCategory) {
        withAnimation(.smooth(duration: 0.25)) {
            if expanded.contains(category) { expanded.remove(category) } else { expanded.insert(category) }
        }
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }
}

private struct CategoryBarRow: View {
    @Environment(AppModel.self) private var model
    let row: CategoryBars.Row
    let largest: Double
    let isExpanded: Bool
    let toggle: () -> Void
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    CategoryIcon(category: row.category, size: 22)
                    Text(row.category.title).font(.body.weight(.medium))
                        .frame(width: 150, alignment: .leading).lineLimit(1)
                    bar(found: Double(row.bytes), selected: Double(row.selectedBytes), height: 14)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(space(row.bytes)).font(.callout.weight(.semibold)).monospacedDigit()
                        Text("\(row.selectedCount) of \(row.count) selected")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(width: 110, alignment: .trailing)
                }
                .padding(.vertical, 8).padding(.horizontal, 8)
                .background(hovering || isExpanded ? Color.primary.opacity(0.05) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("\(row.category.title), \(space(row.bytes)) found, \(space(row.selectedBytes)) selected")
            .accessibilityHint(isExpanded ? "Collapse" : "Show largest items")

            if isExpanded {
                details.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var details: some View {
        let items = model.findings(in: row.category).sorted { $0.bytes > $1.bytes }
        let top = Array(items.prefix(5))
        let maxItem = Double(top.first?.bytes ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(top) { finding in
                HStack(spacing: 10) {
                    TriStateCheckbox(state: model.state(of: finding), label: "Select \(finding.title)") {
                        model.toggle(finding)
                    }
                    Text(finding.title).font(.callout).lineLimit(1).truncationMode(.middle)
                        .frame(width: 210, alignment: .leading)
                    bar(found: Double(finding.bytes), selected: Double(model.selection.selectedBytes(of: finding)),
                        height: 8, scale: maxItem)
                    Text(space(finding.bytes)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
            HStack {
                if items.count > top.count {
                    Text("and \(items.count - top.count) more").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review all \(items.count)…", action: open).buttonStyle(.link).font(.callout)
            }
        }
        .padding(.leading, 56).padding(.trailing, 8).padding(.bottom, 10).padding(.top, 2)
    }

    /// Found (light) with selected (solid) overlaid from the same origin.
    private func bar(found: Double, selected: Double, height: CGFloat, scale: Double? = nil) -> some View {
        GeometryReader { proxy in
            let total = max(scale ?? largest, 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 3).fill(Theme.accent.opacity(0.28))
                    .frame(width: max(height / 2, proxy.size.width * found / total))
                if selected > 0 {
                    RoundedRectangle(cornerRadius: height / 3).fill(Theme.accent)
                        .frame(width: max(height / 2, proxy.size.width * selected / total))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        .animation(.smooth, value: selected)
    }
}
