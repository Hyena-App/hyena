import SwiftUI
import HyenaCore

// MARK: - Explain

/// "What is this?" popover: instant facts, then the on-device model's take.
struct ExplainPopover: View {
    @Environment(AppModel.self) private var model
    let facts: ItemFacts
    @State private var explanation: Assistant.Explanation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: explanation == nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(facts.name).font(.headline).lineLimit(1)
                    Text(facts.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            if let explanation {
                VerdictBadge(verdict: explanation.verdict)
                section("What it is", explanation.summary)
                section("Created by", explanation.owner)
                section("If you clean it", explanation.advice)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    section("If you clean it", facts.whatHappens)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking on this Mac…").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            Label(model.assistantStatus.isReady ? "Generated on this Mac by Apple Intelligence. May be imperfect."
                                                : "Based on Hyena’s built-in knowledge.",
                  systemImage: model.assistantStatus.isReady ? "apple.intelligence" : "book.closed")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
        .animation(.smooth, value: explanation)
        .task {
            explanation = await model.explain(facts)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VerdictBadge: View {
    let verdict: Assistant.Explanation.Verdict

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch verdict {
        case .safe: ("Safe to clean", "checkmark.shield.fill", .green)
        case .caution: ("Check before cleaning", "exclamationmark.triangle.fill", .orange)
        case .keep: ("Probably keep", "hand.raised.fill", .red)
        }
        Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Insights & habits

/// Weekly digest: deterministic facts plus a model-written summary.
struct InsightsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("This week", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                if model.assistantStatus.isReady {
                    Label("On-device", systemImage: "apple.intelligence").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.digestLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…").foregroundStyle(.secondary)
                }
            } else if let digest = model.digest {
                Text(digest).font(.body).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.insights) { insight in
                    Label(insight.text, systemImage: symbol(for: insight.kind))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
        .animation(.smooth, value: model.digest)
    }

    private func symbol(for kind: Insight.Kind) -> String {
        switch kind {
        case .growth: "arrow.up.right"
        case .stale: "moon.zzz"
        case .largest: "externaldrive"
        case .trash: "trash"
        case .total: "sum"
        }
    }
}

/// Proactive ideas picked for this user. Acting on one selects items for review.
struct SuggestionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.suggestions.isEmpty || model.suggestionsLoading {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Suggested for you", systemImage: "lightbulb.max")
                        .font(.headline)
                    Spacer()
                    if model.suggestionsLoading {
                        ProgressView().controlSize(.small)
                    } else if model.suggestionsUsedModel {
                        Label("Picked on-device", systemImage: "apple.intelligence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.suggestions) { suggestion in
                    SuggestionRow(suggestion: suggestion)
                    if suggestion.id != model.suggestions.last?.id { Divider() }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)
        }
    }
}

struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let suggestion: Suggestion
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.kind.symbol)
                .font(.system(size: compact ? 13 : 16, weight: .semibold))
                .foregroundStyle(suggestion.kind == .lowDisk ? .red : Theme.accent)
                .frame(width: compact ? 18 : 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title).font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
                Text(suggestion.detail).font(compact ? .caption : .callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(compact ? 2 : nil)
            }
            Spacer(minLength: 8)
            if !compact {
                if suggestion.bytes > 0 {
                    Text(space(suggestion.bytes)).monospacedDigit().foregroundStyle(.secondary)
                }
                Menu {
                    Button("Not Now") { model.snooze(suggestion) }
                    Button("Don’t Suggest \(suggestion.kind.title)") { model.mute(suggestion.kind) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More options")
                Button(model.emptyingTrash && suggestion.action == .emptyTrash ? "Emptying…" : actionTitle) {
                    model.act(on: suggestion)
                }
                .secondaryButton()
                .disabled(model.busy || model.emptyingTrash)
            }
        }
    }

    private var actionTitle: String {
        switch suggestion.action {
        case .select: "Review"
        case .emptyTrash: "Empty Trash"
        case .protect: "Protect"
        }
    }
}

// MARK: - Ask Hyena

struct AskHyenaSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var interpretation: Assistant.Interpretation?
    @State private var thinking = false
    @FocusState private var focused: Bool

    private let examples = [
        "Clean everything older than a month except my work projects",
        "Remove node_modules I haven’t touched in 3 months",
        "Only caches bigger than 500 MB",
        "Xcode and package caches, but not Gradle",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HyenaMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Hyena").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Describe what to clean. You’ll review the selection before anything happens.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                TextField("e.g. clean old Rust builds except my work projects", text: $request)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(run)
                if thinking { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            if let interpretation {
                preview(interpretation)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Try").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(examples, id: \.self) { example in
                        Button { request = example; run() } label: {
                            Label(example, systemImage: "text.bubble").font(.callout)
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            HStack {
                Label(model.assistantStatus.isReady ? "Understood on this Mac with Apple Intelligence"
                                                    : "Using Hyena’s built-in understanding",
                      systemImage: model.assistantStatus.isReady ? "apple.intelligence" : "text.magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Select Matches") {
                    if let rule = interpretation?.rule { model.apply(rule) }
                    dismiss()
                }
                .prominentButton()
                .keyboardShortcut(.defaultAction)
                .disabled(interpretation == nil || model.matches(interpretation!.rule).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            focused = true
            if DemoData.screen == "ask" {
                request = "Clean everything older than a month except my work projects"
                run()
            }
        }
        .animation(.smooth, value: interpretation?.rule)
    }

    private func preview(_ interpretation: Assistant.Interpretation) -> some View {
        let matches = model.matches(interpretation.rule)
        let bytes = matches.reduce(0) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Hyena understood").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowChips(items: interpretation.rule.summary)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(space(bytes)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("in \(matches.count) item\(matches.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            if matches.isEmpty {
                Text("Nothing matches. Try wording it differently, or scan first.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(matches.prefix(5)) { finding in
                        HStack {
                            CategoryIcon(category: finding.category, size: 16)
                            Text(finding.title).lineLimit(1)
                            Spacer()
                            Text(space(finding.bytes)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if matches.count > 5 {
                        Text("and \(matches.count - 5) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Selecting replaces your current selection. Protected folders are never included.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private func run() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        thinking = true
        Task {
            interpretation = await model.interpret(text)
            thinking = false
        }
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { chips }
            VStack(alignment: .leading) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.accent.opacity(0.15), in: Capsule())
        }
    }
}
