import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BrainCore

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
