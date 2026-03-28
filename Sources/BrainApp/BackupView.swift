import SwiftUI
import BrainCore
import GRDB
import UniformTypeIdentifiers
import os.log

// Backup & Migration UI: export brain data as JSON, import from brain-api export.
// Accessible from Settings.
struct BackupView: View {
    @Environment(DataBridge.self) private var dataBridge
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showImportPicker = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var importStats: ImportStats?
    @State private var showImportConfirmation = false
    @State private var pendingImportURL: URL?

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "Backup")

    var body: some View {
        List {
            // MARK: Export
            Section {
                Button {
                    exportBrainData()
                } label: {
                    HStack {
                        Label("Daten exportieren", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExporting || isImporting)
            } header: {
                Text("Export")
            } footer: {
                Text("Exportiert alle Einträge, Tags, Links und Wissen als JSON-Datei. Kann zum Backup oder zur Migration verwendet werden.")
            }

            // MARK: Import
            Section {
                Button {
                    showImportPicker = true
                } label: {
                    HStack {
                        Label("Aus JSON importieren", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExporting || isImporting)
            } header: {
                Text("Import")
            } footer: {
                Text("Importiert Daten aus einer brain-ios JSON-Datei oder einem brain-api Export. Bestehende Einträge bleiben erhalten.")
            }

            // MARK: Database Info
            Section("Datenbank") {
                HStack {
                    Text("Grösse")
                    Spacer()
                    Text(dataBridge.db.approximateSize())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Einträge")
                    Spacer()
                    Text("\(dataBridge.entryCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Tags")
                    Spacer()
                    Text("\(dataBridge.tagCount)")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Import Stats
            if let stats = importStats {
                Section("Letzter Import") {
                    HStack {
                        Text("Importiert")
                        Spacer()
                        Text("\(stats.entriesImported) Einträge")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Tags")
                        Spacer()
                        Text("\(stats.tagsImported)")
                            .foregroundStyle(.secondary)
                    }
                    if stats.skipped > 0 {
                        HStack {
                            Text("Übersprungen")
                            Spacer()
                            Text("\(stats.skipped)")
                                .foregroundStyle(BrainTheme.Colors.warning)
                        }
                    }
                    if stats.errors > 0 {
                        HStack {
                            Text("Fehler")
                            Spacer()
                            Text("\(stats.errors)")
                                .foregroundStyle(BrainTheme.Colors.error)
                        }
                    }
                }
            }
        }
        .navigationTitle("Datensicherung")
        .navigationBarTitleDisplayMode(.inline)
        // Status toast
        .overlay(alignment: .bottom) {
            if let msg = statusMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(statusIsError ? Color.red.gradient : Color.green.gradient)
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: statusMessage)
        // File picker for import
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    pendingImportURL = url
                    showImportConfirmation = true
                }
            case .failure(let error):
                showStatus("Import fehlgeschlagen: \(error.localizedDescription)", isError: true)
            }
        }
        // Confirm import
        .confirmationDialog(
            "Daten importieren?",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Importieren") {
                if let url = pendingImportURL {
                    importBrainData(from: url)
                }
            }
            Button("Abbrechen", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Bestehende Einträge bleiben erhalten. Neue Einträge werden hinzugefügt.")
        }
        // Share sheet for export
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Export

    private func exportBrainData() {
        isExporting = true

        do {
            let pool = dataBridge.db.pool

            // Fetch all data
            let entries = try pool.read { db in
                try Entry.fetchAll(db, sql: "SELECT * FROM entries WHERE deletedAt IS NULL ORDER BY createdAt")
            }
            let tags = try pool.read { db in
                try Tag.fetchAll(db)
            }
            let entryTags = try pool.read { db in
                try EntryTag.fetchAll(db)
            }
            let links = try pool.read { db in
                try Link.fetchAll(db)
            }
            let facts = try pool.read { db in
                try KnowledgeFact.fetchAll(db)
            }

            // Build JSON structure
            let export: [String: Any] = [
                "version": 1,
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "source": "brain-ios",
                "entries": entries.map { entryToDict($0) },
                "tags": tags.map { ["id": $0.id as Any, "name": $0.name, "color": $0.color as Any] },
                "entryTags": entryTags.map { ["entryId": $0.entryId, "tagId": $0.tagId] },
                "links": links.map { ["id": $0.id as Any, "sourceId": $0.sourceId, "targetId": $0.targetId, "relation": $0.relation.rawValue] },
                "knowledgeFacts": facts.map { ["subject": $0.subject as Any, "predicate": $0.predicate as Any, "object": $0.object as Any, "confidence": $0.confidence] },
            ]

            let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])

            // Write to temp file
            let fileName = "brain-export-\(dateStamp()).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)

            exportURL = tempURL
            showExportShare = true
            showStatus("Export bereit: \(entries.count) Einträge", isError: false)
            logger.info("Exported \(entries.count) entries to \(fileName)")
        } catch {
            showStatus("Export fehlgeschlagen: \(error.localizedDescription)", isError: true)
            logger.error("Export failed: \(error)")
        }

        isExporting = false
    }

    private func entryToDict(_ entry: Entry) -> [String: Any] {
        var dict: [String: Any] = [
            "type": entry.type.rawValue,
            "status": entry.status.rawValue,
            "priority": entry.priority,
            "source": entry.source.rawValue,
        ]
        if let id = entry.id { dict["id"] = id }
        if let title = entry.title { dict["title"] = title }
        if let body = entry.body { dict["body"] = body }
        if let meta = entry.sourceMeta { dict["sourceMeta"] = meta }
        if let created = entry.createdAt { dict["createdAt"] = created }
        if let updated = entry.updatedAt { dict["updatedAt"] = updated }
        return dict
    }

    // MARK: - Import

    private func importBrainData(from url: URL) {
        isImporting = true
        defer { isImporting = false }

        guard url.startAccessingSecurityScopedResource() else {
            showStatus("Zugriff auf Datei nicht möglich", isError: true)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                showStatus("Ungültige JSON-Datei", isError: true)
                return
            }

            let pool = dataBridge.db.pool
            var stats = ImportStats()

            // Import entries
            if let entriesArray = json["entries"] as? [[String: Any]] {
                for entryDict in entriesArray {
                    do {
                        let type = EntryType(rawValue: entryDict["type"] as? String ?? "thought") ?? .thought
                        let title = entryDict["title"] as? String
                        let body = entryDict["body"] as? String
                        let status = EntryStatus(rawValue: entryDict["status"] as? String ?? "active") ?? .active
                        let priority = entryDict["priority"] as? Int ?? 0
                        let source = EntrySource(rawValue: entryDict["source"] as? String ?? "manual") ?? .manual
                        let sourceMeta = entryDict["sourceMeta"] as? String
                        let createdAt = entryDict["createdAt"] as? String ?? entryDict["created_at"] as? String
                        let updatedAt = entryDict["updatedAt"] as? String ?? entryDict["updated_at"] as? String

                        try pool.write { db in
                            var entry = Entry(
                                type: type,
                                title: title,
                                body: body,
                                status: status,
                                priority: priority,
                                source: source,
                                sourceMeta: sourceMeta,
                                createdAt: createdAt,
                                updatedAt: updatedAt
                            )
                            try entry.insert(db)
                        }
                        stats.entriesImported += 1
                    } catch {
                        stats.errors += 1
                    }
                }
            }

            // Import tags
            if let tagsArray = json["tags"] as? [[String: Any]] {
                for tagDict in tagsArray {
                    if let name = tagDict["name"] as? String {
                        do {
                            try pool.write { db in
                                let exists = try Tag.filter(Column("name") == name).fetchCount(db) > 0
                                if !exists {
                                    let color = tagDict["color"] as? String
                                    var tag = Tag(name: name, color: color)
                                    try tag.insert(db)
                                    stats.tagsImported += 1
                                } else {
                                    stats.skipped += 1
                                }
                            }
                        } catch {
                            stats.errors += 1
                        }
                    }
                }
            }

            importStats = stats
            showStatus("\(stats.entriesImported) Einträge importiert", isError: false)
            logger.info("Import complete: \(stats.entriesImported) entries, \(stats.tagsImported) tags")

            // Refresh dashboard
            dataBridge.refreshDashboard()

        } catch {
            showStatus("Import fehlgeschlagen: \(error.localizedDescription)", isError: true)
            logger.error("Import failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { statusMessage = nil }
        }
    }

    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.string(from: Date())
    }
}

// MARK: - Import Stats

private struct ImportStats {
    var entriesImported = 0
    var tagsImported = 0
    var skipped = 0
    var errors = 0
}

// ShareSheet is defined in SkillManagerView.swift and shared across the module.
