import SwiftUI
import BrainCore
import GRDB

// Configure which tags enforce privacy zone restrictions.
// Tags with "Nur On-Device" will never be sent to cloud LLMs.
struct PrivacyZoneSettingsView: View {
    @Environment(DataBridge.self) private var dataBridge: DataBridge?
    @State private var zones: [(tag: Tag, level: PrivacyLevel)] = []
    @State private var allTags: [Tag] = []
    @State private var showAddSheet = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Was sind Datenschutzzonen?", systemImage: "info.circle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Datenschutzzonen steuern, welche KI-Modelle auf Deine Daten zugreifen dürfen — basierend auf Tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Nur auf Gerät", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Daten mit diesem Tag werden NIE an Cloud-KI gesendet. Nur lokale Modelle (On-Device).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Label("Nur genehmigter Anbieter", systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Daten werden nur an den konfigurierten Cloud-Anbieter gesendet (z.B. Anthropic), nicht an beliebige LLMs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Label("Keine Einschränkung", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Daten können an jedes verfügbare KI-Modell gesendet werden (Standard).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            if zones.isEmpty {
                ContentUnavailableView(
                    "Keine Privacy Zones",
                    systemImage: "lock.shield",
                    description: Text("Füge Tags hinzu, deren Daten nur On-Device verarbeitet werden sollen.")
                )
            } else {
                Section {
                    ForEach(zones, id: \.tag.id) { item in
                        HStack {
                            Label(item.tag.name, systemImage: privacyIcon(item.level))
                                .foregroundStyle(privacyColor(item.level))
                            Spacer()
                            Menu {
                                Button {
                                    setLevel(.onDeviceOnly, forTag: item.tag)
                                } label: {
                                    Label("Nur On-Device", systemImage: "iphone")
                                }
                                Button {
                                    setLevel(.approvedCloudOnly, forTag: item.tag)
                                } label: {
                                    Label("Nur genehmigtes Cloud-LLM", systemImage: "cloud.fill")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    removeZone(forTag: item.tag)
                                } label: {
                                    Label("Einschränkung entfernen", systemImage: "xmark.circle")
                                }
                            } label: {
                                Text(levelLabel(item.level))
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(privacyColor(item.level).opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } header: {
                    Text("Eingeschränkte Tags")
                } footer: {
                    Text("Entries mit diesen Tags werden entsprechend der Einschränkung geroutet. \"Nur On-Device\" bedeutet: Daten verlassen NIE das Gerät.")
                }
            }

            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Privacy Zones")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Was sind Tags?", systemImage: "tag.fill")
                    .font(.caption.weight(.semibold))
                Text("Tags sind Schlagwörter, die du Einträgen zuweisen kannst (z.B. privat, arbeit, gesundheit). Privacy-Zonen nutzen diese Tags um zu steuern, welche Einträge an die KI gesendet werden dürfen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "Privacy Zones: Tags, Datenschutz-Level, On-Device Verarbeitung", screenName: "Privacy Zones")
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPrivacyZoneSheet(
                availableTags: unrestrictedTags,
                onAdd: { tag, level in
                    setLevel(level, forTag: tag)
                    showAddSheet = false
                }
            )
        }
        .task {
            loadZones()
        }
    }

    // Tags that don't yet have a privacy zone configured.
    private var unrestrictedTags: [Tag] {
        let zoneTagIds = Set(zones.compactMap(\.tag.id))
        return allTags.filter { !zoneTagIds.contains($0.id ?? -1) }
    }

    private func loadZones() {
        guard let pool = dataBridge?.db.pool else { return }
        let service = PrivacyZoneService(pool: pool)
        let tagService = TagService(pool: pool)

        do {
            allTags = try tagService.list()
            let allZones = try service.listAll()
            zones = allZones.compactMap { item in
                guard let tag = allTags.first(where: { $0.id == item.zone.tagId }) else { return nil }
                return (tag: tag, level: item.zone.level)
            }
        } catch {
            self.error = "Laden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func setLevel(_ level: PrivacyLevel, forTag tag: Tag) {
        guard let pool = dataBridge?.db.pool, let tagId = tag.id else { return }
        let service = PrivacyZoneService(pool: pool)
        do {
            try service.setLevel(level, forTagId: tagId)
            loadZones()
        } catch {
            self.error = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func removeZone(forTag tag: Tag) {
        guard let pool = dataBridge?.db.pool, let tagId = tag.id else { return }
        let service = PrivacyZoneService(pool: pool)
        do {
            try service.removeZone(forTagId: tagId)
            loadZones()
        } catch {
            self.error = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func privacyIcon(_ level: PrivacyLevel) -> String {
        switch level {
        case .onDeviceOnly: return "lock.iphone"
        case .approvedCloudOnly: return "lock.icloud"
        case .unrestricted: return "lock.open"
        }
    }

    private func privacyColor(_ level: PrivacyLevel) -> Color {
        switch level {
        case .onDeviceOnly: return .red
        case .approvedCloudOnly: return .orange
        case .unrestricted: return .green
        }
    }

    private func levelLabel(_ level: PrivacyLevel) -> String {
        switch level {
        case .onDeviceOnly: return "Nur On-Device"
        case .approvedCloudOnly: return "Genehmigte Cloud"
        case .unrestricted: return "Unbeschränkt"
        }
    }
}

// Sheet to add a new privacy zone for a tag.
private struct AddPrivacyZoneSheet: View {
    let availableTags: [Tag]
    let onAdd: (Tag, PrivacyLevel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTag: Tag?
    @State private var selectedLevel: PrivacyLevel = .onDeviceOnly

    var body: some View {
        NavigationStack {
            List {
                if availableTags.isEmpty {
                    ContentUnavailableView(
                        "Keine Tags verfügbar",
                        systemImage: "tag",
                        description: Text("Alle Tags haben bereits eine Privacy Zone.")
                    )
                } else {
                    Section("Tag auswählen") {
                        ForEach(availableTags) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTag?.id == tag.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }

                    Section("Einschränkung") {
                        Picker("Level", selection: $selectedLevel) {
                            Text("Nur On-Device").tag(PrivacyLevel.onDeviceOnly)
                            Text("Nur genehmigtes Cloud-LLM").tag(PrivacyLevel.approvedCloudOnly)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }
            .navigationTitle("Privacy Zone hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        if let tag = selectedTag {
                            onAdd(tag, selectedLevel)
                        }
                    }
                    .disabled(selectedTag == nil)
                }
            }
        }
    }
}
