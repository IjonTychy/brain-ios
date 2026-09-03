import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BrainCore

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
