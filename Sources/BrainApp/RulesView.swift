import SwiftUI
import BrainCore

// Rules Engine UI: list, create, edit, toggle, and delete automation rules.
// Follows the ProposalView pattern for consistent UX.
struct RulesView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var rules: [Rule] = []
    @State private var filterCategory: String? = nil
    @State private var selectedRule: Rule?
    @State private var showCreate = false
    @State private var toast: String?

    private let categories = [
        ("behavior", "Verhalten"),
        ("prompt", "Prompt"),
        ("analysis", "Analyse"),
        ("ui", "Oberfläche"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            Picker("Kategorie", selection: $filterCategory) {
                Text("Alle").tag(String?.none)
                ForEach(categories, id: \.0) { key, label in
                    Text(label).tag(String?.some(key))
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if rules.isEmpty {
                ContentUnavailableView(
                    "Keine Regeln",
                    systemImage: "gearshape.2",
                    description: Text("Erstelle eine Regel um Brain-Verhalten zu automatisieren.")
                )
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRow(rule: rule, onToggle: { toggleRule(rule) })
                            .contentShape(Rectangle())
                            .onTapGesture { selectedRule = rule }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteRule(rule)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Regeln")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { loadRules() }
        .onChange(of: filterCategory) { _, _ in loadRules() }
        .sheet(item: $selectedRule) { rule in
            NavigationStack {
                RuleDetailView(rule: rule, onSave: { updated in
                    saveRule(updated)
                    selectedRule = nil
                }, onDelete: {
                    if let id = rule.id { deleteRuleById(id) }
                    selectedRule = nil
                })
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                RuleCreateView { newRule in
                    createRule(newRule)
                    showCreate = false
                }
            }
        }
        .brainToast($toast)
    }

    private func loadRules() {
        rules = (try? dataBridge.listRules(category: filterCategory)) ?? []
    }

    private func toggleRule(_ rule: Rule) {
        guard let id = rule.id else { return }
        if let updated = try? dataBridge.toggleRule(id: id) {
            showToast(updated.enabled ? "Regel aktiviert" : "Regel deaktiviert")
        }
        loadRules()
    }

    private func deleteRule(_ rule: Rule) {
        guard let id = rule.id else { return }
        deleteRuleById(id)
    }

    private func deleteRuleById(_ id: Int64) {
        try? dataBridge.deleteRule(id: id)
        showToast("Regel gelöscht")
        loadRules()
    }

    private func saveRule(_ rule: Rule) {
        try? dataBridge.updateRule(rule)
        showToast("Regel gespeichert")
        loadRules()
    }

    private func createRule(_ rule: Rule) {
        _ = try? dataBridge.createRule(
            category: rule.category,
            name: rule.name,
            condition: rule.condition,
            action: rule.action,
            priority: rule.priority
        )
        showToast("Regel erstellt")
        loadRules()
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { toast = nil }
        }
    }
}

// MARK: - Rule Row

struct RuleRow: View {
    let rule: Rule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Category badge
            categoryIcon(rule.category)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(categoryLabel(rule.category))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(categoryColor(rule.category), in: Capsule())

                    if rule.priority > 0 {
                        Text("P\(rule.priority)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let trigger = parseTrigger(rule.condition) {
                        Text(trigger)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: .constant(rule.enabled))
                .labelsHidden()
                .onTapGesture { onToggle() }
        }
        .opacity(rule.enabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private func categoryIcon(_ category: String) -> some View {
        let (icon, color) = categoryIconAndColor(category)
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    private func categoryIconAndColor(_ category: String) -> (String, Color) {
        switch category {
        case "behavior": return ("brain.head.profile", .purple)
        case "prompt": return ("text.bubble", .blue)
        case "analysis": return ("chart.bar.xaxis", .orange)
        case "ui": return ("paintbrush", .green)
        default: return ("gearshape", .gray)
        }
    }

    private func categoryLabel(_ category: String) -> String {
        switch category {
        case "behavior": return "Verhalten"
        case "prompt": return "Prompt"
        case "analysis": return "Analyse"
        case "ui": return "UI"
        default: return category
        }
    }

    private func categoryColor(_ category: String) -> Color {
        categoryIconAndColor(category).1
    }

    private func parseTrigger(_ conditionJSON: String?) -> String? {
        guard let json = conditionJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trigger = dict["trigger"] as? String else { return nil }
        return trigger
    }
}

// MARK: - Rule Detail View (edit)

struct RuleDetailView: View {
    @State var rule: Rule
    let onSave: (Rule) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: String = "behavior"
    @State private var priority: Int = 0
    @State private var trigger: String = ""
    @State private var entryType: String = ""
    @State private var timeFrom: String = ""
    @State private var timeTo: String = ""
    @State private var actionJSON: String = ""
    @State private var showDeleteConfirm = false

    private let categories = ["behavior", "prompt", "analysis", "ui"]
    private let categoryLabels = ["Verhalten", "Prompt", "Analyse", "Oberfläche"]

    var body: some View {
        Form {
            Section("Grundeinstellungen") {
                TextField("Name", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(Array(zip(categories, categoryLabels)), id: \.0) { key, label in
                        Text(label).tag(key)
                    }
                }
                Stepper("Priorität: \(priority)", value: $priority, in: 0...100)
            }

            Section("Bedingung (Trigger)") {
                TextField("Trigger (z.B. app_open, entry_created)", text: $trigger)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Entry-Typ (optional)", text: $entryType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    TextField("Von (HH:MM)", text: $timeFrom)
                        .keyboardType(.numbersAndPunctuation)
                    Text("–")
                    TextField("Bis (HH:MM)", text: $timeTo)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            Section("Aktion (JSON)") {
                TextEditor(text: $actionJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
            }

            Section("Info") {
                LabeledContent("Erstellt", value: rule.createdAt ?? "–")
                LabeledContent("Geändert", value: rule.modifiedAt ?? "–")
                LabeledContent("Geändert von", value: rule.modifiedBy)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Regel löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Regel bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    saveChanges()
                }
                .disabled(name.isEmpty || actionJSON.isEmpty)
            }
        }
        .onAppear { loadFromRule() }
        .confirmationDialog("Regel wirklich löschen?", isPresented: $showDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                onDelete()
                dismiss()
            }
        }
    }

    private func loadFromRule() {
        name = rule.name
        category = rule.category
        priority = rule.priority
        actionJSON = rule.action

        // Parse condition JSON into fields
        if let json = rule.condition,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            trigger = dict["trigger"] as? String ?? ""
            entryType = dict["entryType"] as? String ?? ""
            if let time = dict["time"] as? String {
                let parts = time.components(separatedBy: "-")
                if parts.count == 2 {
                    timeFrom = parts[0]
                    timeTo = parts[1]
                }
            }
        }
    }

    private func saveChanges() {
        rule.name = name
        rule.category = category
        rule.priority = priority
        rule.action = actionJSON
        rule.condition = buildConditionJSON()
        onSave(rule)
        dismiss()
    }

    private func buildConditionJSON() -> String? {
        var dict: [String: String] = [:]
        if !trigger.isEmpty { dict["trigger"] = trigger }
        if !entryType.isEmpty { dict["entryType"] = entryType }
        if !timeFrom.isEmpty && !timeTo.isEmpty { dict["time"] = "\(timeFrom)-\(timeTo)" }
        guard !dict.isEmpty else { return nil }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }
}

// MARK: - Rule Create View

struct RuleCreateView: View {
    let onCreate: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "behavior"
    @State private var priority = 0
    @State private var trigger = ""
    @State private var entryType = ""
    @State private var timeFrom = ""
    @State private var timeTo = ""
    @State private var actionJSON = "{}"

    private let categories = ["behavior", "prompt", "analysis", "ui"]
    private let categoryLabels = ["Verhalten", "Prompt", "Analyse", "Oberfläche"]

    private let exampleTriggers = ["app_open", "entry_created", "entry_updated", "email_received", "morning", "evening"]

    var body: some View {
        Form {
            Section("Grundeinstellungen") {
                TextField("Name (eindeutig)", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(Array(zip(categories, categoryLabels)), id: \.0) { key, label in
                        Text(label).tag(key)
                    }
                }
                Stepper("Priorität: \(priority)", value: $priority, in: 0...100)
            }

            Section("Bedingung") {
                Picker("Trigger", selection: $trigger) {
                    Text("Keiner").tag("")
                    ForEach(exampleTriggers, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                TextField("Entry-Typ (optional)", text: $entryType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    TextField("Von (HH:MM)", text: $timeFrom)
                        .keyboardType(.numbersAndPunctuation)
                    Text("–")
                    TextField("Bis (HH:MM)", text: $timeTo)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            Section("Aktion (JSON)") {
                TextEditor(text: $actionJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
            }

            Section {
                Text("Tipp: Brain kann auch Regeln per Chat erstellen. Sag z.B. \"Erstelle eine Regel die bei App-Start die offenen Tasks zeigt.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Neue Regel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") {
                    createRule()
                }
                .disabled(name.isEmpty || actionJSON.isEmpty)
            }
        }
    }

    private func createRule() {
        var conditionDict: [String: String] = [:]
        if !trigger.isEmpty { conditionDict["trigger"] = trigger }
        if !entryType.isEmpty { conditionDict["entryType"] = entryType }
        if !timeFrom.isEmpty && !timeTo.isEmpty { conditionDict["time"] = "\(timeFrom)-\(timeTo)" }

        let conditionJSON: String? = conditionDict.isEmpty ? nil : {
            if let data = try? JSONSerialization.data(withJSONObject: conditionDict, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return nil
        }()

        let rule = Rule(
            category: category,
            name: name,
            condition: conditionJSON,
            action: actionJSON,
            priority: priority,
            enabled: true,
            modifiedBy: "user"
        )
        onCreate(rule)
    }
}
