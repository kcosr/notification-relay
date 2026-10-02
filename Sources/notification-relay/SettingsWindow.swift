import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onSave: (() -> Void)?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        do {
            let config = try ConfigurationStore().prepare()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Notification Relay Settings"
            window.minSize = NSSize(width: 740, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: RelaySettingsView(config: config, saved: { [weak self] in
                self?.onSave?()
            }, close: { [weak window] in window?.close() }))
            self.window = window
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load settings"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

private struct EnvironmentEntry: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

private struct RelaySettingsView: View {
    @State private var config: AppConfig
    @State private var environment: [EnvironmentEntry]
    @State private var errorMessage: String?
    let saved: () -> Void
    let close: () -> Void

    init(config: AppConfig, saved: @escaping () -> Void, close: @escaping () -> Void) {
        _config = State(initialValue: config)
        _environment = State(initialValue: (config.relay.environment ?? [:]).sorted { $0.key < $1.key }
            .map { EnvironmentEntry(key: $0.key, value: $0.value) })
        self.saved = saved
        self.close = close
    }

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                general.tabItem { Label("General", systemImage: "gearshape") }
                relay.tabItem { Label("Relay", systemImage: "terminal") }
                rules.tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease.circle") }
                advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Saved changes apply on the next monitoring check.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(16)
    }

    private var general: some View {
        Form {
            Section("Monitoring") {
                Toggle("Enable monitoring", isOn: optional($config.monitoringEnabled, default: true))
                Text("Choose a relay executable before enabling monitoring. Turn monitoring off to save settings without a script.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Check interval (seconds)", value: optional($config.pollIntervalSeconds, default: 60), format: .number)
                TextField("Look back (seconds)", value: optional($config.initialLookbackSeconds, default: 1800), format: .number)
                TextField("Maximum notifications per batch", value: optional($config.maxNotificationsPerRun, default: 50), format: .number)
            }
            Section("Notification access") {
                Text("Enable Notification Relay in Full Disk Access, then quit and reopen the app. This allows it to read the macOS Notification Center database.")
                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }.formStyle(.grouped)
    }

    private var relay: some View {
        Form {
            Section("Executable") {
                HStack {
                    TextField("Script or program", text: $config.relay.executable)
                    Button("Choose…") { chooseFile(directory: false) { config.relay.executable = $0 } }
                }
                Text("Select an executable script or program. For a script without executable permission, select its interpreter and add the script path as the first argument.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Standard input", selection: optional($config.relay.stdin, default: .none)) {
                    Text("None").tag(RelayInputMode.none)
                    Text("JSON").tag(RelayInputMode.json)
                    Text("Text summary").tag(RelayInputMode.summary)
                }
                Toggle("Skip empty batches", isOn: optional($config.relay.skipIfEmpty, default: true))
            }
            Section("Arguments") {
                StringListEditor(values: Binding(get: { config.relay.resolvedArguments }, set: { config.relay.arguments = $0 }), placeholder: "Argument")
                Text("Each row is one argument; shell quoting is unnecessary. Placeholders: {{summary}}, {{json}}, {{count}}.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Working directory") {
                HStack {
                    TextField("Default: inherited from the app", text: optionalText($config.relay.workingDirectory))
                    Button("Choose…") { chooseFile(directory: true) { config.relay.workingDirectory = $0 } }
                }
            }
            Section("Environment overrides") {
                ForEach($environment) { $entry in
                    HStack {
                        TextField("Variable", text: $entry.key)
                        TextField("Value", text: $entry.value)
                        Button { environment.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove environment variable")
                    }
                }
                Button("Add variable") { environment.append(EnvironmentEntry(key: "", value: "")) }
            }
        }.formStyle(.grouped)
    }

    private var rules: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A notification must match an include rule, unless the include list is empty (all notifications). Any matching exclude rule discards it. Within a rule, all enabled conditions must match; alternatives within one condition use OR.")
                    .font(.callout).foregroundStyle(.secondary)
                RuleListEditor(title: "Include rules", rules: optional($config.includeRules, default: []))
                RuleListEditor(title: "Exclude rules", rules: optional($config.excludeRules, default: []))
            }.padding()
        }
    }

    private var advanced: some View {
        Form {
            Section("Storage") {
                TextField("Notification database (empty uses macOS default)", text: optionalText($config.databasePath))
                TextField("Checkpoint file (empty uses app default)", text: optionalText($config.checkpointPath))
                Text("The checkpoint remembers successful deliveries. Changing it may cause older notifications to be sent again.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Configuration file", value: ConfigurationStore.defaultConfigPath).textSelection(.enabled)
            }
            Section("Text summary") {
                TextField("Maximum items", value: Binding(get: { config.resolvedSummary.resolvedMaxItems }, set: {
                    var summary = config.resolvedSummary; summary.maxItems = $0; config.summary = summary
                }), format: .number)
                TextField("Maximum body characters", value: Binding(get: { config.resolvedSummary.resolvedMaxBodyLength }, set: {
                    var summary = config.resolvedSummary; summary.maxBodyLength = $0; config.summary = summary
                }), format: .number)
                Toggle("Include delivery time", isOn: Binding(get: { config.resolvedSummary.resolvedIncludeDeliveredAt }, set: {
                    var summary = config.resolvedSummary; summary.includeDeliveredAt = $0; config.summary = summary
                }))
            }
        }.formStyle(.grouped)
    }

    private func save() {
        do {
            var updated = config
            var variables: [String: String] = [:]
            for entry in environment {
                guard !entry.key.isEmpty, !entry.key.contains("="), !entry.key.contains("\0") else {
                    errorMessage = "Environment variable names must be nonempty and cannot contain = or a null character."
                    return
                }
                guard variables[entry.key] == nil else {
                    errorMessage = "Duplicate environment variable: \(entry.key)"
                    return
                }
                variables[entry.key] = entry.value
            }
            updated.relay.environment = variables.isEmpty ? nil : variables
            try updated.validate()
            try ConfigurationStore().save(updated)
            saved()
            close()
        } catch { errorMessage = error.localizedDescription }
    }

    private func chooseFile(directory: Bool, selected: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { selected(url.path) }
    }
}

private func optional<Value: Sendable>(_ binding: Binding<Value?>, default fallback: Value) -> Binding<Value> {
    Binding(get: { binding.wrappedValue ?? fallback }, set: { binding.wrappedValue = $0 })
}

private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
    Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
}

private struct StringListEditor: View {
    @Binding var values: [String]
    var placeholder: String

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(values.indices, id: \.self) { index in
                HStack {
                    TextField(placeholder, text: Binding(get: { values.indices.contains(index) ? values[index] : "" }, set: {
                        if values.indices.contains(index) { values[index] = $0 }
                    }))
                    Button { if values.indices.contains(index) { values.remove(at: index) } } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove \(placeholder.lowercased())")
                }
            }
            Button("Add \(placeholder.lowercased())") { values.append("") }
        }
    }
}

private struct RuleListEditor: View {
    let title: String
    @Binding var rules: [NotificationRule]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rules.indices, id: \.self) { index in
                    DisclosureGroup {
                        RuleEditor(rule: Binding(get: {
                            rules.indices.contains(index) ? rules[index] : NotificationRule(name: "")
                        }, set: { if rules.indices.contains(index) { rules[index] = $0 } }))
                        Button("Remove rule", role: .destructive) {
                            if rules.indices.contains(index) { rules.remove(at: index) }
                        }.padding(.top, 8)
                    } label: {
                        Text(rules[index].name.isEmpty ? "Unnamed rule" : rules[index].name).fontWeight(.medium)
                    }
                }
                Button("Add rule") { rules.append(NotificationRule(name: "New rule")) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RuleEditor: View {
    @Binding var rule: NotificationRule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Rule name", text: $rule.name)
            Toggle("Limit to app bundle identifiers", isOn: Binding(get: { rule.bundleIdentifiers != nil }, set: {
                rule.bundleIdentifiers = $0 ? [] : nil
            }))
            if rule.bundleIdentifiers != nil {
                StringListEditor(values: optional($rule.bundleIdentifiers, default: []), placeholder: "Bundle identifier")
                Text("For example: com.apple.mail. An enabled condition with no entries matches nothing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MatcherEditor(title: "Title", matchers: $rule.title)
            MatcherEditor(title: "Subtitle", matchers: $rule.subtitle)
            MatcherEditor(title: "Body", matchers: $rule.body)
            MatcherEditor(title: "Any title, subtitle, or body", matchers: $rule.anyField)
            MatcherEditor(title: "Thread identifier", matchers: $rule.threadIdentifier)
            MatcherEditor(title: "Category", matchers: $rule.category)
        }.padding(.vertical, 8)
    }
}

private struct MatcherEditor: View {
    let title: String
    @Binding var matchers: [StringMatcher]?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(get: { matchers != nil }, set: { matchers = $0 ? [] : nil }))
            if let current = matchers {
                ForEach(current.indices, id: \.self) { index in
                    MatcherRow(matcher: Binding(get: {
                        guard let values = matchers, values.indices.contains(index) else { return StringMatcher(value: "") }
                        return values[index]
                    }, set: {
                        guard var values = matchers, values.indices.contains(index) else { return }
                        values[index] = $0; matchers = values
                    })) {
                        guard var values = matchers, values.indices.contains(index) else { return }
                        values.remove(at: index); matchers = values
                    }
                }
                Button("Add match") { matchers?.append(StringMatcher(type: .contains, value: "", caseSensitive: false)) }
                if current.isEmpty {
                    Text("No alternatives: this condition matches nothing.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MatcherRow: View {
    @Binding var matcher: StringMatcher
    let remove: () -> Void

    var body: some View {
        HStack {
            Picker("Match type", selection: optional($matcher.type, default: .contains)) {
                Text("Contains").tag(MatcherType.contains)
                Text("Equals").tag(MatcherType.equals)
                Text("Starts with").tag(MatcherType.prefix)
                Text("Ends with").tag(MatcherType.suffix)
                Text("Regex").tag(MatcherType.regex)
            }.labelsHidden().frame(width: 120)
            TextField("Text or expression", text: $matcher.value)
            Toggle("Case sensitive", isOn: optional($matcher.caseSensitive, default: false)).toggleStyle(.checkbox)
            Button(action: remove) { Image(systemName: "minus.circle") }.accessibilityLabel("Remove match")
        }
    }
}
