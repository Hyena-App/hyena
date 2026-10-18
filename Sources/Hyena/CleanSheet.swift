import SwiftUI
import HyenaCore

/// Review, progress and result for a cleanup, in one sheet.
struct CleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var reviewExpanded: Set<CleanupCategory> = []

    var body: some View {
        VStack(spacing: 0) {
            if model.phase == .cleaning {
                progress
            } else if started, let result = model.lastResult {
                done(result)
            } else {
                review
            }
        }
        .frame(width: 560)
        .animation(.smooth, value: model.phase)
        .interactiveDismissDisabled(model.phase == .cleaning)
    }

    // MARK: Review

    private var review: some View {
        @Bindable var model = model
        let groups = CleanupCategory.allCases.compactMap { category -> (CleanupCategory, Int, Int64)? in
            let count = model.selectedCount(in: category)
            return count > 0 ? (category, count, model.selectedBytes(in: category)) : nil
        }
        let permanent = groups.contains { isPermanent($0.0) }
        let running = model.selectedFindings.filter { $0.note?.hasPrefix("Open now") == true || $0.note?.contains("is open") == true }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                HyenaMark(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean \(space(model.selectedBytes))?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(model.selectedFindings.count) items. Here’s what will happen.")
                        .foregroundStyle(.secondary)
                }
            }

            // The summary grows with what's expanded and scrolls only past the sheet's height.
            ViewThatFits(in: .vertical) {
                categoryList(groups)
                ScrollView { categoryList(groups) }
            }
            .frame(maxHeight: 460)

            Toggle(isOn: $model.deleteImmediately) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete immediately")
                    Text("Caches, logs and builds are deleted right away. Backups, downloads and leftovers still go to Trash so you can recover them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                if !running.isEmpty {
                    Label("\(running.count) selected item\(running.count == 1 ? " belongs" : "s belong") to an open app. Quit it first for best results.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if model.selectedSnapshotCount > 0 {
                    Label("Deleting snapshots may ask for your administrator password.", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                }
                if permanent {
                    Label("Items marked Permanent can’t be recovered.", systemImage: "exclamationmark.octagon")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Everything goes to Trash, so you can use Put Back if you change your mind.",
                          systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                Label("Each path is checked again right before it’s removed. Protected folders are never touched.",
                      systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button {
                    started = true
                    model.clean()
                } label: {
                    Text(permanent ? "Clean \(space(model.selectedBytes))" : "Move to Trash")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 10)
                }
                .controlSize(.large)
                .prominentButton()
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedFindings.isEmpty || model.busy)
            }
        }
        .padding(28)
    }

    private func categoryList(_ groups: [(CleanupCategory, Int, Int64)]) -> some View {
        VStack(spacing: 0) {
                ForEach(groups, id: \.0) { category, count, bytes in
                    let open = reviewExpanded.contains(category) || groups.count == 1
                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            if reviewExpanded.contains(category) { reviewExpanded.remove(category) }
                            else { reviewExpanded.insert(category) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(open ? 90 : 0))
                                .opacity(groups.count == 1 ? 0 : 1)
                            CategoryIcon(category: category, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title).font(.body.weight(.medium))
                                Text(category == .snapshots ? "\(count) snapshot\(count == 1 ? "" : "s")"
                                                            : "\(count) item\(count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isPermanent(category) { Pill(text: "Permanent", color: .red) }
                            Text(category == .snapshots ? "—" : space(bytes))
                                .monospacedDigit().font(.body.weight(.semibold))
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(groups.count == 1)
                    .accessibilityHint(open ? "Hide items" : "Show items")
                    if open { itemList(for: category) }
                    if category != groups.last?.0 { Divider().padding(.leading, 50) }
                }
            }
        .glassCard(cornerRadius: 14)
    }

    /// Every selected item in a category, by name, so nothing is cleaned unseen.
    private func itemList(for category: CleanupCategory) -> some View {
        let items = model.selectedFindings.filter { $0.category == category }.sorted { $0.bytes > $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(finding.title).font(.callout).lineLimit(1).truncationMode(.middle)
                                if model.state(of: finding) == .mixed { Pill(text: "Partial", color: Theme.accent) }
                            }
                            if finding.hasKnownSize {
                                Text(finding.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 8)
                        if finding.hasKnownSize {
                            Text(space(model.selection.selectedBytes(of: finding)))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, 60).padding(.trailing, 14).padding(.bottom, 10)
        }
    }

    private func isPermanent(_ category: CleanupCategory) -> Bool {
        category.isPermanent || (model.deleteImmediately && SafetyPolicy.allowsImmediateDeletion(category))
    }

    // MARK: Progress

    private var progress: some View {
        CleaningAnimation()
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity)
    }

    // MARK: Done

    private func done(_ result: CleanResult) -> some View {
        VStack(spacing: 14) {
            Image(systemName: result.count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(result.count > 0 ? .green : .orange)
                .symbolEffect(.bounce, value: result.count)
            Text(result.count > 0 ? "\(space(result.movedBytes + result.freedBytes)) cleaned" : "Nothing was cleaned")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            VStack(spacing: 4) {
                if result.freedBytes > 0 { Text("\(space(result.freedBytes)) freed right away.") }
                if result.movedBytes > 0 { Text("\(space(result.movedBytes)) moved to Trash. Empty Trash to free it.") }
                if result.snapshots > 0 { Text("\(result.snapshots) snapshot\(result.snapshots == 1 ? "" : "s") deleted.") }
            }
            .foregroundStyle(.secondary)

            if !result.failures.isEmpty {
                DisclosureGroup("\(result.failures.count) item\(result.failures.count == 1 ? "" : "s") skipped") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
                                Text(failure).font(.caption).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.horizontal, 10)
            }

            HStack {
                if result.movedBytes > 0 {
                    Button {
                        model.emptyTrash()
                        dismiss()
                    } label: { Label("Empty Trash", systemImage: "trash") }
                    .controlSize(.large)
                    .secondaryButton()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .prominentButton()
            }
            .padding(.top, 8)
        }
        .padding(28)
    }
}

/// The hyena eats each item as it's cleaned: the item's icon flies in from
/// the ring and vanishes, the mark takes a bite, and the counter ticks up.
private struct CleaningAnimation: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var morsels: [Morsel] = []
    @State private var bites = 0

    struct Morsel: Identifiable {
        let id = UUID()
        let finding: Finding
        let angle: Double
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(model.cleanProgress) / Double(max(model.cleanTotal, 1)))
                    .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: model.cleanProgress)

                ForEach(morsels) { morsel in
                    MorselView(morsel: morsel) { morsels.removeAll { $0.id == morsel.id } }
                }

                HyenaMark(size: 76)
                    .keyframeAnimator(initialValue: 1.0, trigger: bites) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        // A quick chomp: squash, snap back.
                        CubicKeyframe(0.88, duration: 0.09)
                        SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
                    }
            }
            .frame(width: 170, height: 170)

            Text("Cleaning…").font(.title2.weight(.semibold))
            Text(space(model.cleanedSoFar))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: model.cleanedSoFar)
            Text(model.cleaningCurrent?.title ?? " ")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 360)
                .contentTransition(.opacity)
            Text("\(model.cleanProgress) of \(model.cleanTotal)")
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
        }
        .onChange(of: model.cleanProgress) {
            guard !reduceMotion, let finding = model.cleaningCurrent else { return }
            morsels.append(Morsel(finding: finding, angle: Double.random(in: 0..<360)))
            if morsels.count > 12 { morsels.removeFirst(morsels.count - 12) }
            bites += 1
        }
    }
}

private struct MorselView: View {
    let morsel: CleaningAnimation.Morsel
    let done: () -> Void
    @State private var eaten = false

    var body: some View {
        let radians = morsel.angle * .pi / 180
        icon
            .frame(width: 26, height: 26)
            .offset(x: eaten ? 0 : cos(radians) * 92, y: eaten ? 0 : sin(radians) * 92)
            .scaleEffect(eaten ? 0.2 : 1)
            .opacity(eaten ? 0 : 1)
            .rotationEffect(.degrees(eaten ? 25 : 0))
            .onAppear {
                withAnimation(.easeIn(duration: 0.55)) { eaten = true } completion: { done() }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        if let image = Icons.icon(for: morsel.finding) {
            Image(nsImage: image).resizable()
        } else {
            CategoryIcon(category: morsel.finding.category, size: 26)
        }
    }
}
