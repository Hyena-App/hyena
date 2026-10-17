import SwiftUI
import HyenaCore

/// Review, progress and result for a cleanup, in one sheet.
struct CleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

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
        let permanent = groups.contains { $0.0.isPermanent } || model.deleteImmediately
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

            VStack(spacing: 0) {
                ForEach(groups, id: \.0) { category, count, bytes in
                    HStack(spacing: 12) {
                        CategoryIcon(category: category, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title).font(.body.weight(.medium))
                            Text(category == .snapshots ? "\(count) snapshot\(count == 1 ? "" : "s")"
                                                        : "\(count) item\(count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if category.isPermanent || model.deleteImmediately {
                            Pill(text: "Permanent", color: .red)
                        }
                        Text(category == .snapshots ? "—" : space(bytes))
                            .monospacedDigit().font(.body.weight(.semibold))
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    if category != groups.last?.0 { Divider().padding(.leading, 50) }
                }
            }
            .glassCard(cornerRadius: 14)

            Toggle(isOn: $model.deleteImmediately) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete immediately")
                    Text("Frees space right away instead of moving items to Trash. This can’t be undone.")
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

    // MARK: Progress

    private var progress: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(model.cleanProgress) / Double(max(model.cleanTotal, 1)))
                    .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: model.cleanProgress)
                HyenaMark(size: 64)
            }
            .frame(width: 130, height: 130)
            Text("Cleaning…").font(.title2.weight(.semibold))
            Text("\(model.cleanProgress) of \(model.cleanTotal)").foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(40)
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
