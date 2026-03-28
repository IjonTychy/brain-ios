import SwiftUI
import BrainCore
import os.log

// Detail view for a single entry with edit and delete support.
struct EntryDetailView: View {
    let entry: Entry
    let dataBridge: DataBridge
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var bodyText: String
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var privacyLevel: PrivacyLevel = .unrestricted
    @State private var entryTags: [Tag] = []
    @State private var newTagName = ""
    @State private var showAddTag = false
    @State private var allTags: [Tag] = []
    var onDelete: (() -> Void)?

    // H3: Input length limits
    private let maxTitleLength = 500
    private let maxBodyLength = 10_000

    init(entry: Entry, dataBridge: DataBridge, onDelete: (() -> Void)? = nil) {
        self.entry = entry
        self.dataBridge = dataBridge
        self.onDelete = onDelete
        _title = State(initialValue: entry.title ?? "")
        _bodyText = State(initialValue: entry.body ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Type badge + privacy indicator
                HStack {
                    Label(typeName(entry.type), systemImage: typeIcon(entry.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Phase 31: Privacy zone indicator
                    if privacyLevel == .onDeviceOnly {
                        Label("Nur On-Device", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.1))
                            .clipShape(Capsule())
                    } else if privacyLevel == .approvedCloudOnly {
                        Label("Genehmigte Cloud", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()
                    if let date = entry.formattedCreatedAt ?? entry.createdAt {
                        Text(date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Title
                if isEditing {
                    TextField("Titel", text: $title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityIdentifier("entry.titleField")
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxTitleLength {
                                title = String(newValue.prefix(maxTitleLength))
                            }
                        }
                } else {
                    Text(title.isEmpty ? "Ohne Titel" : title)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Divider()

                // Tags
                VStack(alignment: .leading, spacing: BrainTheme.Spacing.sm) {
                    HStack {
                        Label("Tags", systemImage: "tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrainTheme.Colors.textSecondary)
                        Spacer()
                        Button {
                            showAddTag.toggle()
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                                .foregroundStyle(BrainTheme.Colors.brandPurple)
                        }
                    }
                    if entryTags.isEmpty {
                        Text("Keine Tags")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(entryTags) { tag in
                                BrainTagView(text: tag.name, color: BrainTheme.Colors.brandPurple, removable: isEditing) {
                                    if let entryId = entry.id {
                                        try? dataBridge.removeTag(entryId: entryId, tagName: tag.name)
                                        loadTags()
                                    }
                                }
                            }
                        }
                    }
                    if showAddTag {
                        VStack(alignment: .leading, spacing: BrainTheme.Spacing.xs) {
                            HStack {
                                TextField("Neuer Tag...", text: $newTagName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                Button("Hinzufügen") {
                                    addTag(newTagName)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            // Tag suggestions from existing tags
                            let suggestions = tagSuggestions
                            if !suggestions.isEmpty {
                                FlowLayout(spacing: 4) {
                                    ForEach(suggestions) { tag in
                                        Button {
                                            addTag(tag.name)
                                        } label: {
                                            Text(tag.name)
                                                .font(.caption2)
                                                .foregroundStyle(BrainTheme.Colors.brandPurple)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(BrainTheme.Colors.brandPurple.opacity(0.08), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                // Body
                if isEditing {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 200)
                            .accessibilityIdentifier("entry.bodyEditor")
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.quaternary)
                            )
                            .onChange(of: bodyText) { _, newValue in
                                if newValue.count > maxBodyLength {
                                    bodyText = String(newValue.prefix(maxBodyLength))
                                }
                            }
                        // H3: Character counter with warning
                        Text("\(bodyText.count)/\(maxBodyLength)")
                            .font(.caption2)
                            .foregroundStyle(bodyText.count > maxBodyLength * 9 / 10 ? .red : .secondary)
                    }
                } else {
                    if self.bodyText.isEmpty {
                        Text("Kein Inhalt")
                            .foregroundStyle(.tertiary)
                            .italic()
                    } else {
                        Text(self.bodyText)
                            .textSelection(.enabled)
                    }
                }

                // Status
                HStack {
                    Label("Status", systemImage: "circle.fill")
                        .font(.caption)
                    Text(entry.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Bearbeiten" : "Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Sichern") {
                        saveChanges()
                        isEditing = false
                    }
                    .accessibilityIdentifier("entry.saveButton")
                } else {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

        }
        .confirmationDialog("Eintrag löschen?", isPresented: $showDeleteConfirmation) {
            Button("Löschen", role: .destructive) {
                deleteEntry()
            }
        }
        .task {
            loadPrivacyLevel()
            loadTags()
        }
    }

    // Phase 31: Check if this entry has tags with privacy restrictions.
    private func loadPrivacyLevel() {
        guard let entryId = entry.id else { return }
        let service = PrivacyZoneService(pool: dataBridge.db.pool)
        privacyLevel = (try? service.strictestLevel(forEntryId: entryId)) ?? .unrestricted
    }

    private func saveChanges() {
        guard let entryId = entry.id else { return }
        do {
            _ = try dataBridge.updateEntry(id: entryId, title: title, body: bodyText)
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "EntryDetail")
                .error("Save failed: \(error)")
        }
    }

    private func deleteEntry() {
        guard let entryId = entry.id else {
            dismiss()
            return
        }
        do {
            try dataBridge.deleteEntry(id: entryId)
            onDelete?()
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "EntryDetail")
                .error("Delete failed: \(error)")
        }
        dismiss()
    }

    private func loadTags() {
        guard let entryId = entry.id else { return }
        let tagService = TagService(pool: dataBridge.db.pool)
        entryTags = (try? tagService.tags(for: entryId)) ?? []
        allTags = (try? dataBridge.listTags()) ?? []
    }

    private var tagSuggestions: [Tag] {
        let currentNames = Set(entryTags.map(\.name))
        let available = allTags.filter { !currentNames.contains($0.name) }
        let query = newTagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(available.prefix(8))
        }
        return available.filter { $0.name.lowercased().contains(query) }.prefix(8).map { $0 }
    }

    private func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let entryId = entry.id {
            try? dataBridge.addTag(entryId: entryId, tagName: trimmed)
            newTagName = ""
            loadTags()
        }
    }

    private func typeName(_ type: EntryType) -> String {
        type.label
    }

    private func typeIcon(_ type: EntryType) -> String {
        type.icon
    }
}
