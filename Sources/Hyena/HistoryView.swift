import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView("No cleanups yet", systemImage: "clock",
                                       description: Text("Your cleanups will show up here."))
            } else {
                List {
                    Section {
                        HStack(spacing: 24) {
                            stat(space(model.history.reduce(0) { $0 + $1.bytes }), "cleaned in total")
                            stat("\(model.history.count)", "cleanups")
                        }
                        .padding(.vertical, 8)
                    }
                    Section("Recent") {
                        ForEach(model.history) { record in
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").foregroundStyle(Theme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(record.count) item\(record.count == 1 ? "" : "s")").font(.body.weight(.medium))
                                    Text((record.categories ?? []).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(space(record.bytes)).monospacedDigit().font(.body.weight(.semibold))
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
    }
}
