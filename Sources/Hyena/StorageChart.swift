import SwiftUI
import Charts
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

private struct CategoryBars: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Binding var route: Route?
    @State private var selected: String?

    struct Row: Identifiable {
        var id: String { category.rawValue }
        let category: CleanupCategory
        let bytes: Int64
        let selectedBytes: Int64
    }

    private var rows: [Row] {
        model.visibleCategories
            .map { Row(category: $0, bytes: model.totalBytes(in: $0), selectedBytes: model.selectedBytes(in: $0)) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the cleanable space is").font(.headline)
                Spacer()
                HStack(spacing: 14) {
                    legendSwatch(Theme.accent, "Selected to clean")
                    legendSwatch(Theme.accent.opacity(0.3), "Found")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text("Scan to see where space is going.").foregroundStyle(.secondary)
            } else {
                Chart(rows) { row in
                    // xStart/xEnd keeps the two bars overlapping; plain x would stack them end to end.
                    BarMark(xStart: .value("Start", 0), xEnd: .value("Found", Double(row.bytes) / 1e9),
                            y: .value("Category", row.category.title))
                        .foregroundStyle(Theme.accent.opacity(0.3))
                        .cornerRadius(4)
                    BarMark(xStart: .value("Start", 0), xEnd: .value("Selected", Double(row.selectedBytes) / 1e9),
                            y: .value("Category", row.category.title))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(4)
                        .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                            Text(space(row.bytes))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .opacity(selected == nil || selected == row.category.title ? 1 : 0.45)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                        AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB") } }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel().font(.callout) }
                }
                .chartXScale(domain: 0...(Double(rows.first?.bytes ?? 1) / 1e9 * 1.18))
                .chartOverlay { proxy in
                    // Hover highlights a bar; only a click opens its category. Scrolling never navigates.
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                selected = proxy.value(atY: location.y, as: String.self)
                            } else {
                                selected = nil
                            }
                        }
                        .onTapGesture { location in
                            guard let title = proxy.value(atY: location.y, as: String.self),
                                  let row = rows.first(where: { $0.category.title == title }) else { return }
                            route = .category(row.category)
                        }
                }
                .frame(height: CGFloat(rows.count) * 30 + 24)
                .accessibilityLabel("Cleanable space by category")
                Text("Light bars show everything found; solid bars show what’s selected. Click a bar to review it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}
