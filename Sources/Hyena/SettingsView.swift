import SwiftUI
import HyenaCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            WhatToCleanSettings().tabItem { Label("What to Clean", systemImage: "checklist") }
            LocationsSettings().tabItem { Label("Projects", systemImage: "folder") }
            ProtectedSettings().tabItem { Label("Protected", systemImage: "lock.shield") }
            IntelligenceSettings().tabItem { Label("Intelligence", systemImage: "sparkles") }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Scan when Hyena opens", isOn: $model.scanOnOpen)
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }
            Section {
                Picker("Remind me to clean", selection: $model.reminder) {
                    ForEach(ReminderInterval.allCases) { Text($0.title).tag($0) }
                }
                Stepper("When at least \(model.reminderThresholdGB) GB can be cleaned",
                        value: $model.reminderThresholdGB, in: 1...100)
                    .disabled(model.reminder == .never)
            } footer: {
                Text("Hyena rescans quietly in the background and sends a notification. It never cleans on its own.")
            }
            Section {
                Toggle("Delete immediately instead of moving to Trash", isOn: $model.deleteImmediately)
            } footer: {
                Text("Caches, logs and builds are deleted right away. Backups, downloads and leftovers always go to Trash.")
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    if model.hasFullDiskAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") { model.openFullDiskAccessSettings() }
                    }
                }
                Text("Needed to measure Trash and some protected caches. Everything else works without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { Notifier.requestAuthorization() }
    }
}

private struct WhatToCleanSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            ForEach(CleanupGroup.allCases) { group in
                Section(group.title) {
                    ForEach(CleanupCategory.allCases.filter { $0.group == group }) { category in
                        Toggle(isOn: binding(category)) {
                            HStack(spacing: 10) {
                                CategoryIcon(category: category, size: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.title)
                                    Text(category.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ category: CleanupCategory) -> Binding<Bool> {
        Binding(
            get: { model.categories.contains(category) },
            set: { if $0 { model.categories.insert(category) } else { model.categories.remove(category) } }
        )
    }
}

private struct LocationsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(model.roots, id: \.path) { url in
                    HStack {
                        Image(nsImage: Icons.fileIcon(url)).resizable().frame(width: 18, height: 18)
                        Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        Spacer()
                        Button { model.roots.removeAll { $0 == url } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(url.path)")
                    }
                }
                HStack {
                    Button("Add Folder…") { model.addFolder() }
                    Button("Find Again") { model.rediscoverProjectFolders() }
                        .help("Look for folders that hold several projects and add any that are missing")
                    ForEach(model.suggestedRoots.prefix(3), id: \.path) { url in
                        Button("+ ~/\(url.lastPathComponent)") { model.addRoot(url) }
                    }
                }
            } header: {
                Text("Project folders")
            } footer: {
                Text("Found automatically on first launch, and yours to edit. Hyena looks inside for build outputs and dependencies, matched by markers like Cargo.toml or package.json.")
            }
            Section {
                Picker("Skip folders changed in the last", selection: $model.minimumAgeDays) {
                    Text("Don’t skip").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
            } footer: {
                Text("Keeps builds for projects you’re actively working on.")
            }
            Section("Languages and tools") {
                ForEach(ArtifactKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { model.kinds.contains(kind) },
                        set: { if $0 { model.kinds.insert(kind) } else { model.kinds.remove(kind) } }
                    )) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                    .help(kind.consequence)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProtectedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.exclusions.isEmpty {
                    Text("Nothing protected yet. Right-click any item and choose Never Clean This.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.exclusions, id: \.path) { url in
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { model.exclusions.removeAll { $0 == url } }
                    }
                }
                Button("Protect a Folder…") { model.addFolder(protect: true) }
            } footer: {
                Text("Protected folders, and anything containing them, are never offered for cleaning.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntelligenceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("On-device model") {
                    switch Assistant.status {
                    case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .unavailable(let reason): Text(reason).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
                Toggle("Use Apple Intelligence for explanations, digests and Ask Hyena", isOn: $model.useOnDeviceModel)
                    .disabled(!Assistant.status.isReady)
            } footer: {
                Text("Runs entirely on this Mac. Nothing is sent anywhere. The model only explains and suggests. You always review the selection, and the same safety checks run before anything is removed.")
            }
            Section {
                Picker("Check for suggestions", selection: $model.reminder) {
                    ForEach(ReminderInterval.allCases) { Text($0.title).tag($0) }
                }
                ForEach(Suggestion.Kind.allCases, id: \.self) { kind in
                    Toggle(isOn: Binding(
                        get: { !model.suggestionPrefs.muted.contains(kind) },
                        set: { model.setMuted(kind, !$0) }
                    )) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                Button("Reset Suggestion Preferences") { model.resetSuggestionPreferences() }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Hyena rescans quietly, picks a few ideas that fit how you work, and notifies you. Snoozed ideas come back later; ones you keep dismissing back off longer. Nothing is cleaned without you.")
            }
            Section {
                Toggle("Learn from my choices", isOn: $model.learnHabits)
                LabeledContent("Remembered items") {
                    HStack {
                        Text("\(model.habits.habits.count)").monospacedDigit().foregroundStyle(.secondary)
                        Button("Forget") { model.forgetHabits() }.disabled(model.habits.isEmpty)
                    }
                }
            } footer: {
                Text("Items you keep twice start unchecked. Review items you clean twice start checked. After three keeps, Hyena offers to protect them. Stored only on this Mac.")
            }
        }
        .formStyle(.grouped)
    }
}
