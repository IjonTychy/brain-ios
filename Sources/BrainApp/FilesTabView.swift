import SwiftUI
import BrainCore

// Native files tab: shows document-type entries with search and management.
struct FilesTabView: View {
    let dataBridge: DataBridge
    @State private var files: [Entry] = []
    @State private var searchQuery = ""
    @State private var selectedEntry: Entry?
    @State private var showCreate = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Dateien durchsuchen...", text: $searchQuery)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { loadFiles() }
                    .onChange(of: searchQuery) { _, _ in loadFiles() }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        loadFiles()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.cornerRadiusMD))
            .shadow(color: BrainTheme.Shadows.subtle, radius: 2, x: 0, y: 1)
            .padding(.horizontal)
            .padding(.top, 8)

            if files.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Keine Dateien")
                        .font(.title3.weight(.semibold))
                    Text("Dokumente und Notizen erscheinen hier.\nErstelle ein neues Dokument mit dem + Button.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, BrainTheme.Spacing.xl)
            } else {
                List {
                    ForEach(files) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            FileRowView(entry: entry)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteFile(entry)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button {
                                archiveFile(entry)
                            } label: {
                                Label("Archiv", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { loadFiles() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "Dateien: Dokumente und Notizen verwalten", screenName: "Dateien")
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { loadFiles() }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                EntryDetailView(entry: entry, dataBridge: dataBridge, onDelete: {
                    files.removeAll { $0.id == entry.id }
                    selectedEntry = nil
                })
                .navigationTitle(entry.title ?? "Dokument")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") { selectedEntry = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateDocumentView(dataBridge: dataBridge) { loadFiles() }
            }
        }
    }

    private func loadFiles() {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Show documents + notes
            files = ((try? dataBridge.listEntries(limit: 100)) ?? [])
                .filter { $0.type == .document || $0.type == .note }
        } else {
            files = ((try? dataBridge.searchEntries(query: searchQuery, limit: 50)) ?? [])
                .filter { $0.type == .document || $0.type == .note }
        }
    }

    private func deleteFile(_ entry: Entry) {
        guard let id = entry.id else { return }
        try? dataBridge.deleteEntry(id: id)
        files.removeAll { $0.id == id }
    }

    private func archiveFile(_ entry: Entry) {
        guard let id = entry.id else { return }
        _ = try? dataBridge.archiveEntry(id: id)
        loadFiles()
    }
}

// MARK: - File Row

private struct FileRowView: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type == .document ? "doc.fill" : "note.text")
                .foregroundStyle(entry.type == .document ? BrainTheme.Colors.accentSky : BrainTheme.Colors.accentMint)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((entry.type == .document ? BrainTheme.Colors.accentSky : BrainTheme.Colors.accentMint).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? "Ohne Titel")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let date = entry.createdAt {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "d. MMM yyyy"
        return f
    }()

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func formatDate(_ dateStr: String) -> String {
        if let date = Self.dbDateFormatter.date(from: dateStr) {
            return Self.dateFormatter.string(from: date)
        }
        return dateStr
    }
}

// MARK: - Create Document

private struct CreateDocumentView: View {
    let dataBridge: DataBridge
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var docType = "note"

    var body: some View {
        Form {
            Section("Typ") {
                Picker("Typ", selection: $docType) {
                    Text("Notiz").tag("note")
                    Text("Dokument").tag("document")
                }
                .pickerStyle(.segmented)
            }

            Section("Inhalt") {
                TextField("Titel", text: $title)
                TextEditor(text: $bodyText)
                    .frame(minHeight: 150)
            }
        }
        .navigationTitle("Neues Dokument")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") {
                    _ = try? dataBridge.createEntry(
                        title: title.isEmpty ? "Ohne Titel" : title,
                        type: docType,
                        body: bodyText.isEmpty ? nil : bodyText
                    )
                    onCreated()
                    dismiss()
                }
            }

        }
    }
}
