import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BrainCore

// Skill management view: list, enable/disable, share, import, delete installed skills.
// Replaces the static Brain Admin skill with a native SwiftUI interface.
struct SkillManagerView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var selectedGroup: String = "Alle"
    @State private var editingSkill: Skill?
    @State private var editSource: String = ""
    @State private var skills: [Skill] = []
    @State private var showImporter = false
    @State private var shareItem: ShareableSkillFile?
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var skillToDelete: Skill?
    @State private var pendingImportMarkdown: String?
    @State private var showConfetti = false
    @State private var showSkillCreator = false

    // Body extracted into sections to reduce opaque type nesting depth.
    var body: some View {
        List {
            skillsListSection
            selfModifierSection
            featuresSection
            Section("System") { systemStatsView }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "Skills: Installieren, Verwalten, Teilen, Löschen", screenName: "Skills")
                    BrainAvatarButton(context: .skills)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showSkillCreator = true } label: {
                        Label("Skill erstellen", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("skills.createButton")
                    Button { showImporter = true } label: {
                        Label("Importieren", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("skills.importButton")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(isPresented: $showSkillCreator) {
            NavigationStack {
                BrainAssistantSheet(context: .skillCreator)
            }
        }
        .refreshable { loadSkills() }
        .confirmationDialog(
            "Skill löschen?",
            isPresented: Binding(get: { skillToDelete != nil }, set: { if !$0 { skillToDelete = nil } }),
            presenting: skillToDelete
        ) { skill in
            Button("Löschen", role: .destructive) { deleteSkill(skill) }
        } message: { skill in
            Text("\"\(skill.name)\" wird unwiderruflich entfernt.")
        }
        .onAppear { loadSkills() }
        .onReceive(NotificationCenter.default.publisher(for: .brainSkillsChanged)) { _ in
            loadSkills()
        }
        .sheet(isPresented: Binding(get: { pendingImportMarkdown != nil }, set: { if !$0 { pendingImportMarkdown = nil } })) {
            if let markdown = pendingImportMarkdown {
                SkillImportPreview(markdown: markdown) { confirmImport() } onCancel: { pendingImportMarkdown = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toast { toastBanner(msg, color: .green) }
            if let err = errorMessage { toastBanner(err, color: .red) }
        }
        .animation(.easeInOut, value: toast)
        .animation(.easeInOut, value: errorMessage)
        .confettiOverlay(isActive: showConfetti)
        .onChange(of: showConfetti) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showConfetti = false }
            }
        }
    }

    // MARK: - Extracted List Sections

    private var skillsListSection: some View {
        Section {
            if skills.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Keine Skills installiert")
                        .font(.title3.weight(.semibold))
                    Text("Importiere .brainskill.md Dateien oder lasse Brain neue Skills erstellen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(BrainTheme.Spacing.xl)
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                    NavigationLink {
                        SkillDetailSettingsView(
                            skill: skill,
                            onToggle: { toggleSkill(id: skill.id, enabled: $0) },
                            onShare: { shareSkill(skill) },
                            onDelete: { skillToDelete = skill }
                        )
                    } label: {
                        skillRowLabel(skill)
                    }
                }
            }
        } header: {
            HStack {
                Text("Skills")
                Spacer()
                Text("\(skills.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func skillRowLabel(_ skill: Skill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: skill.icon ?? "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill((skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue).opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder((skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue).opacity(0.2), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name).font(.body)
                if let desc = skill.description {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if skill.enabled == false {
                Text("Aus").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var selfModifierSection: some View {
        Section("Self-Modifier") {
            NavigationLink { RulesView() } label: { Label("Regeln", systemImage: "gearshape.2") }
            NavigationLink { ProposalView() } label: { Label("Verbesserungsvorschläge", systemImage: "lightbulb") }
        }
    }

    private var featuresSection: some View {
        Section("Features") {
            NavigationLink { UserProfileView() } label: { Label("Mein Profil", systemImage: "person.text.rectangle") }
            NavigationLink { BrainProfileView() } label: { Label("Brain Profil", systemImage: "brain.head.profile") }
            NavigationLink { KennenlernDialogView() } label: { Label("Kennenlernen", systemImage: "person.2.wave.2") }
            NavigationLink { OnThisDayView() } label: { Label("An diesem Tag", systemImage: "clock.arrow.circlepath") }
            NavigationLink { BackupView() } label: { Label("Datensicherung", systemImage: "externaldrive") }
        }
    }

    // MARK: - System Stats

    private var systemStatsView: some View {
        Group {
            HStack {
                Label("Einträge", systemImage: "doc.text")
                Spacer()
                Text("\(dataBridge.entryCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Tags", systemImage: "tag")
                Spacer()
                Text("\(dataBridge.tagCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Verknüpfungen", systemImage: "link")
                Spacer()
                Text("\(dataBridge.linkCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("DB Grösse", systemImage: "internaldrive")
                Spacer()
                Text(dataBridge.db.approximateSize())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toast

    private func toastBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.gradient)
            .clipShape(Capsule())
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { toast = nil; errorMessage = nil }
    }

    // MARK: - Actions

    private func loadSkills() {
        dataBridge.refreshDashboard()
        skills = (try? dataBridge.listSkills()) ?? []
    }

    private func toggleSkill(id: String, enabled: Bool) {
        do {
            // Language skills: use exclusive toggle (only one active at a time)
            if id.hasPrefix("brain-language-") {
                let locale = String(id.dropFirst("brain-language-".count))
                LocalizationService.shared.setLanguage(enabled ? locale : "de", pool: dataBridge.db.pool)
                loadSkills()
                return
            }
            try dataBridge.setSkillEnabled(id: id, enabled: enabled)
            loadSkills()
        } catch {
            showError("Fehler: \(error.localizedDescription)")
        }
    }

    private func shareSkill(_ skill: Skill) {
        do {
            let markdown = try dataBridge.exportSkill(id: skill.id)
            let fileName = "\(skill.id).brainskill.md"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            shareItem = ShareableSkillFile(url: tempURL)
        } catch {
            showError("Export fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func confirmDeleteSkills(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        skillToDelete = skills[index]
    }

    private func deleteSkill(_ skill: Skill) {
        do {
            try dataBridge.uninstallSkill(id: skill.id)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            loadSkills()
            showToast("\"\(skill.name)\" gelöscht")
        } catch {
            showError("Löschen fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                showError("Kein Zugriff auf die Datei")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                pendingImportMarkdown = markdown
            } catch {
                showError("Datei konnte nicht gelesen werden: \(error.localizedDescription)")
            }
        case .failure(let error):
            showError("Datei-Auswahl fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func confirmImport() {
        guard let markdown = pendingImportMarkdown else { return }
        do {
            let skill = try dataBridge.importSkillFromMarkdown(markdown)
            loadSkills()
            showToast("\"\(skill.name)\" importiert")
            showConfetti = true
        } catch {
            showError("Import fehlgeschlagen: \(error.localizedDescription)")
        }
        pendingImportMarkdown = nil
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { toast = nil }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { errorMessage = nil }
        }
    }
}

// MARK: - Skill Detail Settings (iPhone Settings > App style)

struct SkillDetailSettingsView: View {
    let skill: Skill
    let onToggle: (Bool) -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(DataBridge.self) private var dataBridge
    @State private var isEnabled: Bool = false

    var body: some View {
        List {
            // Header: Icon + Name + Description
            Section {
                HStack(spacing: 16) {
                    Image(systemName: skill.icon ?? "puzzlepiece.extension")
                        .font(.largeTitle)
                        .foregroundStyle(skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue)
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill((skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue).opacity(0.15))
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        if let desc = skill.description {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Metadata
            Section {
                Toggle("Aktiviert", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        if newValue != skill.enabled {
                            onToggle(newValue)
                        }
                    }
                    .onAppear { isEnabled = skill.enabled }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(skill.version)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Typ")
                    Spacer()
                    if let cap = skill.capability {
                        Text(capabilityLabel(cap))
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(capabilityColor(cap).opacity(0.15))
                            .foregroundStyle(capabilityColor(cap))
                            .clipShape(Capsule())
                    } else {
                        Text("Standard")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Erstellt von")
                    Spacer()
                    Text(creatorLabel)
                        .foregroundStyle(.secondary)
                }
            }

            // Permissions
            let perms = skill.decodedPermissions()
            if !perms.isEmpty {
                Section("Berechtigungen") {
                    ForEach(perms, id: \.self) { perm in
                        Label {
                            Text(permissionDescription(perm))
                        } icon: {
                            Image(systemName: permissionIcon(perm))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // Triggers (parsed from JSON)
            let parsedTriggers = Self.parseTriggers(skill.triggers)
            if !parsedTriggers.isEmpty {
                Section("Trigger") {
                    ForEach(parsedTriggers, id: \.type) { trigger in
                        Label {
                            VStack(alignment: .leading) {
                                Text(trigger.type.capitalized)
                                    .font(.body)
                                if !trigger.phrase.isEmpty {
                                    Text(trigger.phrase)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: trigger.type == "siri" ? "mic.fill" : "clock")
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            // Open Skill — auto-compiles if needed
            Section {
                NavigationLink {
                    if let definition = skill.toSkillDefinition() {
                        let vars = SkillContextProvider(dataBridge: dataBridge)
                            .variables(for: skill)
                        SkillView(
                            definition: definition,
                            initialVariables: vars,
                            handlers: CoreActionHandlers.all(data: dataBridge)
                        )
                        .navigationTitle(skill.name)
                    } else if let md = skill.sourceMarkdown, !md.isEmpty {
                        SkillCompilationView(skill: skill)
                            .navigationTitle(skill.name)
                    } else {
                        ContentUnavailableView(
                            "Skill nicht ladbar",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Die UI-Definition konnte nicht geladen werden.")
                        )
                    }
                } label: {
                    Label(skill.hasScreens ? "Skill öffnen" : "Skill öffnen & kompilieren",
                          systemImage: skill.hasScreens ? "play.fill" : "hammer.fill")
                        .foregroundStyle(BrainTheme.Colors.brandBlue)
                }
            }

            // Source & Transparency
            if skill.sourceMarkdown != nil && !skill.sourceMarkdown!.isEmpty {
                Section("Quelle") {
                    NavigationLink {
                        SkillSourceView(skill: skill)
                    } label: {
                        Label("Markdown anzeigen", systemImage: "doc.text.magnifyingglass")
                    }
                    if skill.hasScreens {
                        NavigationLink {
                            SkillJSONView(skill: skill)
                        } label: {
                            Label("Kompiliertes JSON anzeigen", systemImage: "curlybraces")
                        }
                    }
                }
            } else if skill.hasScreens {
                Section("Quelle") {
                    NavigationLink {
                        SkillJSONView(skill: skill)
                    } label: {
                        Label("JSON anzeigen", systemImage: "curlybraces")
                    }
                }
            }

            // Actions
            Section {
                Button {
                    onShare()
                } label: {
                    Label("Skill teilen", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Skill löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct TriggerInfo {
        let type: String
        let phrase: String
    }

    private static func parseTriggers(_ json: String?) -> [TriggerInfo] {
        guard let json,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.map { dict in
            TriggerInfo(
                type: dict["type"] as? String ?? "unbekannt",
                phrase: dict["phrase"] as? String ?? dict["cron"] as? String ?? ""
            )
        }
    }

    // Reuse helper functions from SkillRow
    private func permissionIcon(_ perm: SkillPermission) -> String {
        switch perm {
        case .calendar: "calendar"
        case .contacts: "person.crop.circle"
        case .notifications: "bell"
        case .location: "location"
        case .haptics: "iphone.radiowaves.left.and.right"
        case .camera: "camera"
        case .microphone: "mic"
        case .nfc: "wave.3.forward"
        case .speech: "waveform"
        case .email: "envelope"
        case .entries: "doc.text"
        case .knowledgeFacts: "brain.head.profile"
        case .shortcuts: "arrow.triangle.branch"
        }
    }

    private func permissionDescription(_ perm: SkillPermission) -> String {
        switch perm {
        case .calendar: "Kalender: Termine lesen und erstellen"
        case .contacts: "Kontakte: Kontaktdaten lesen"
        case .notifications: "Mitteilungen: Erinnerungen senden"
        case .location: "Standort: Aktuelle Position abfragen"
        case .haptics: "Haptik: Vibrationsrückmeldung"
        case .camera: "Kamera: Fotos und Dokumente scannen"
        case .microphone: "Mikrofon: Spracheingabe"
        case .nfc: "NFC: NFC-Tags lesen"
        case .speech: "Sprache: Spracherkennung nutzen"
        case .email: "E-Mail: Nachrichten lesen und senden"
        case .entries: "Einträge: Lesen und erstellen"
        case .knowledgeFacts: "Wissen: Fakten lesen und lernen"
        case .shortcuts: "Kurzbefehle: Automationen erstellen"
        }
    }

    private var creatorLabel: String {
        switch skill.createdBy {
        case .user: "Eigener Skill"
        case .system: "Vorinstalliert"
        case .brainAI: "Von Brain erstellt"
        case .import: "Importiert"
        }
    }

    private func capabilityLabel(_ cap: String) -> String {
        switch cap {
        case "app": "App-Skill"
        case "brain": "KI-Skill"
        case "hybrid": "Hybrid-Skill"
        default: cap
        }
    }

    private func capabilityColor(_ cap: String) -> Color {
        switch cap {
        case "app": .blue
        case "brain": .purple
        case "hybrid": .orange
        default: .gray
        }
    }

}

// MARK: - Source Viewer (Markdown "Virenschutz")

struct SkillSourceView: View {
    let skill: Skill

    var body: some View {
        ScrollView {
            Text(skill.sourceMarkdown ?? "Kein Quell-Markdown vorhanden.")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Skill-Quelle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - JSON Viewer (compiled screens)

struct SkillJSONView: View {
    let skill: Skill

    private var prettyJSON: String {
        guard let data = skill.screens.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return skill.screens }
        return str
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrainTheme.Spacing.md) {
                // Safety analysis
                let dangers = SkillSafetyAnalyzer.analyze(json: skill.screens, actions: skill.actions)
                if !dangers.isEmpty {
                    VStack(alignment: .leading, spacing: BrainTheme.Spacing.xs) {
                        Label("Sicherheitshinweise", systemImage: "exclamationmark.shield")
                            .font(.headline)
                            .foregroundStyle(BrainTheme.Colors.warning)
                        ForEach(dangers, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(BrainTheme.Colors.warning)
                        }
                    }
                    .brainCard()
                } else {
                    Label("Keine gefährlichen Aktionen erkannt", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(BrainTheme.Colors.success)
                        .padding(.horizontal)
                }

                Text(prettyJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .navigationTitle("Kompiliertes JSON")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safety Analyzer

enum SkillSafetyAnalyzer {
    // Actions that modify or delete data — flagged for user awareness.
    private static let dangerousActions: [String: String] = [
        "entry.delete": "Kann Einträge löschen",
        "file.delete": "Kann Dateien loeschen",
        "email.delete": "Kann E-Mails loeschen",
        "email.send": "Kann E-Mails senden",
        "contact.delete": "Kann Kontakte loeschen",
        "http.request": "Kann Netzwerk-Anfragen senden",
        "http.download": "Kann Dateien herunterladen",
        "calendar.delete": "Kann Kalender-Einträge löschen",
        "reminder.cancel": "Kann Erinnerungen loeschen",
    ]

    static func analyze(json: String, actions: String?) -> [String] {
        var warnings: [String] = []
        let combined = json + (actions ?? "")
        for (action, description) in dangerousActions {
            if combined.contains(action) {
                warnings.append(description)
            }
        }
        return warnings.sorted()
    }
}

// MARK: - Shareable File Wrapper

struct ShareableSkillFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Skill Import Preview

struct SkillImportPreview: View {
    let markdown: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var source: BrainSkillSource?
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let source {
                    List {
                        Section("Skill-Informationen") {
                            LabeledContent("Name", value: source.name)
                            LabeledContent("ID", value: source.id)
                            LabeledContent("Version", value: source.version)
                            if let desc = source.description, !desc.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Beschreibung")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(desc)
                                }
                            }
                        }

                        if !source.permissions.isEmpty {
                            Section("Benötigte Berechtigungen") {
                                ForEach(source.permissions, id: \.self) { perm in
                                    if let permission = SkillPermission(rawValue: perm) {
                                        Label {
                                            VStack(alignment: .leading) {
                                                Text(perm.capitalized)
                                                    .font(.body)
                                                Text(permissionNote(permission))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } icon: {
                                            Image(systemName: permissionIcon(permission))
                                                .foregroundStyle(.orange)
                                        }
                                    } else {
                                        Label(perm, systemImage: "lock.shield")
                                    }
                                }
                            }
                        }

                        if !source.triggers.isEmpty {
                            Section("Trigger") {
                                ForEach(Array(source.triggers.enumerated()), id: \.offset) { _, trigger in
                                    let type = trigger["type"] ?? "unbekannt"
                                    HStack {
                                        Image(systemName: triggerIcon(type))
                                            .foregroundStyle(.blue)
                                        Text(type)
                                        if let cond = trigger["condition"] ?? trigger["cron"] {
                                            Spacer()
                                            Text(cond)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        Section {
                            Button {
                                onConfirm()
                            } label: {
                                Label("Skill installieren", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if let error = parseError {
                    ContentUnavailableView(
                        "Ungültige Skill-Datei",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView("Wird analysiert...")
                }
            }
            .navigationTitle("Skill-Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { onCancel() }
                }
            }
            .onAppear { parseSkill() }
        }
    }

    private func parseSkill() {
        do {
            let compiler = SkillCompiler()
            source = try compiler.parseSource(markdown)
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func permissionIcon(_ perm: SkillPermission) -> String {
        switch perm {
        case .calendar: return "calendar"
        case .contacts: return "person.crop.circle"
        case .notifications: return "bell"
        case .location: return "location"
        case .haptics: return "iphone.radiowaves.left.and.right"
        case .camera: return "camera"
        case .microphone: return "mic"
        case .nfc: return "wave.3.forward"
        case .speech: return "waveform"
        case .email: return "envelope"
        case .entries: return "doc.text"
        case .knowledgeFacts: return "brain.head.profile"
        case .shortcuts: return "arrow.triangle.branch"
        }
    }

    private func permissionNote(_ perm: SkillPermission) -> String {
        switch perm {
        case .calendar: return "Zugriff auf Termine und Erinnerungen"
        case .contacts: return "Zugriff auf Kontaktdaten"
        case .notifications: return "Kann Mitteilungen senden"
        case .location: return "Kann Standort abfragen"
        case .haptics: return "Vibrationsrückmeldung"
        case .camera: return "Zugriff auf Kamera/Scanner"
        case .microphone: return "Zugriff auf Mikrofon"
        case .nfc: return "Kann NFC-Tags lesen"
        case .speech: return "Kann Spracherkennung nutzen"
        case .email: return "Zugriff auf E-Mail"
        case .entries: return "Zugriff auf Einträge"
        case .knowledgeFacts: return "Zugriff auf Wissensdatenbank"
        case .shortcuts: return "Kann Kurzbefehle erstellen"
        }
    }

    private func triggerIcon(_ type: String) -> String {
        switch type {
        case "app_open": return "app.badge"
        case "schedule": return "clock"
        case "entry_created": return "plus.circle"
        case "bluetooth_device_found": return "wave.3.right"
        default: return "bolt"
        }
    }
}

// Color(hex:) extension defined in ContentView.swift
