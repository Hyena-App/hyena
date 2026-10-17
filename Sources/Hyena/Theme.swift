import SwiftUI
import AppKit
import HyenaCore

enum Theme {
    /// Warm amber taken from the hyena's coat in the app icon.
    static let accent = Color(red: 0.93, green: 0.60, blue: 0.24)
    static let night = Color(red: 0.10, green: 0.11, blue: 0.25)

    static func tint(for category: CleanupCategory) -> Color {
        switch category {
        case .userCaches: .orange
        case .logs: .gray
        case .appSupportCaches: .indigo
        case .appLeftovers: .purple
        case .trash: .red
        case .snapshots: .teal
        case .xcode: .blue
        case .packageCaches: .brown
        case .projects: .green
        }
    }
}

func space(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

extension View {
    /// Liquid Glass on macOS 26, a matching material before that.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular,
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                }
        }
    }

    @ViewBuilder
    func prominentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).tint(.primary)
        } else {
            self.buttonStyle(.bordered).tint(.primary)
        }
    }
}

/// Rounded, colored symbol tile in the style of System Settings.
struct CategoryIcon: View {
    let category: CleanupCategory
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Theme.tint(for: category).gradient,
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Finder icon for a path or app, cached.
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for finding: Finding) -> NSImage? {
        if let bundleID = finding.bundleID, let image = appIcon(bundleID) { return image }
        if finding.category == .appSupportCaches || finding.category == .userCaches || finding.category == .appLeftovers,
           let image = appIcon(named: finding.title.components(separatedBy: " · ").first ?? finding.title) {
            return image
        }
        return nil
    }

    static func fileIcon(_ url: URL) -> NSImage {
        let key = "file:" + url.path
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = image
        return image
    }

    private static func appIcon(_ bundleID: String) -> NSImage? {
        let key = "id:" + bundleID
        if let cached = cache[key] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = image
        return image
    }

    private static func appIcon(named name: String) -> NSImage? {
        let key = "name:" + name
        if let cached = cache[key] { return cached }
        for folder in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: url.path) {
                let image = NSWorkspace.shared.icon(forFile: url.path)
                cache[key] = image
                return image
            }
        }
        return nil
    }
}

/// Native-looking tri-state checkbox.
struct TriStateCheckbox: View {
    let state: CheckState
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(state == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.accent))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? "Selected" : state == .mixed ? "Partially selected" : "Not selected")
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.circle.fill"
        case .mixed: "minus.circle.fill"
        case .off: "circle"
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}
