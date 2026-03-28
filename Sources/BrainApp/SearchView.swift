import SwiftUI
import UIKit
import BrainCore

// Phase 22: Global search view with FTS5 full-text search, autocomplete,
// type/tag filters, and grouped results.

struct SearchView: View {
    let dataBridge: DataBridge
    @State private var query = ""
    @State private var results: [Entry] = []
    @State private var autocompleteResults: [Entry] = []
    @State private var contactResults: [ContactInfo] = []
    @State private var isSearching = false
    @State private var selectedType: EntryType?
    @State private var showContacts = false
    @State private var showFilters = false
    @State private var selectedEntry: Entry?
    @State private var selectedContact: ContactInfo?
    @FocusState private var isSearchFocused: Bool

    private let entryTypes: [EntryType] = [.thought, .task, .event, .note, .email, .document]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("In Brain suchen...", text: $query)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search.textField")
                    .accessibilityLabel("Suchfeld")
                    .onSubmit { performSearch() }
                    .onChange(of: query) { _, newValue in
                        if newValue.count >= 2 {
                            performAutocomplete(newValue)
                        } else {
                            autocompleteResults = []
                        }
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        autocompleteResults = []
                        contactResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showFilters.toggle()
                } label: {
                    Image(systemName: selectedType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(selectedType != nil ? BrainTheme.Colors.brandPurple : .secondary)
                }
                .accessibilityIdentifier("search.filterButton")
                .accessibilityLabel("Filter")
                .accessibilityHint("Typ-Filter ein- oder ausblenden")
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.cornerRadiusMD))
            .shadow(color: BrainTheme.Shadows.subtle, radius: 2, x: 0, y: 1)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Type filter chips
            if showFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "Alle", icon: "tray.full", isSelected: selectedType == nil) {
                            selectedType = nil
                            performSearch()
                        }
                        ForEach(entryTypes, id: \.self) { type in
                            FilterChip(
                                label: labelForType(type),
                                icon: iconForType(type),
                                isSelected: selectedType == type
                            ) {
                                selectedType = (selectedType == type) ? nil : type
                                showContacts = false
                                performSearch()
                            }
                        }
                        FilterChip(label: "Kontakte", icon: "person.crop.circle", isSelected: showContacts) {
                            showContacts.toggle()
                            selectedType = nil
                            performSearch()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Content
            if isSearching {
                ProgressView("Suche...")
                    .padding(.top, 40)
                Spacer()
            } else if !query.isEmpty && results.isEmpty && autocompleteResults.isEmpty && contactResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 52))
                        .foregroundStyle(BrainTheme.Colors.textTertiary)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text(L("search.empty"))
                        .font(.title3.weight(.semibold))
                    Text("Versuche einen anderen Suchbegriff.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                Spacer()
            } else if query.isEmpty {
                // Show recent entries on white/system background, not immediately in gray grouped list
                recentEntriesView
            } else {
                // Show results grouped by type
                searchResultsList
            }
        }
        .onAppear {
            isSearchFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "Volltextsuche über Einträge, Kontakte, Tags", screenName: "Suche")
                    BrainAvatarButton(context: .entries)
                }
            }
        }
        .animation(BrainTheme.Animations.springSnappy, value: showFilters)
        .sensoryFeedback(.selection, trigger: selectedType)
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                EntryDetailView(entry: entry, dataBridge: dataBridge, onDelete: {
                    // Remove deleted entry from results so it disappears immediately
                    results.removeAll { $0.id == entry.id }
                    autocompleteResults.removeAll { $0.id == entry.id }
                    // Dismiss the sheet after deletion
                    selectedEntry = nil
                })
                    .navigationTitle(entry.title ?? "Entry")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { selectedEntry = nil }
                        }
                    }
            }
        }
        .sheet(item: $selectedContact) { contact in
            NavigationStack {
                ContactDetailView(contact: contact)
                    .navigationTitle(contact.fullName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { selectedContact = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Results List

    private var searchResultsList: some View {
        List {
            // Contact results section
            if !contactResults.isEmpty {
                Section {
                    ForEach(contactResults, id: \.identifier) { contact in
                        Button {
                            selectedContact = contact
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.15)).frame(width: 32, height: 32)
                                    Text(contact.initials).font(.caption.bold()).foregroundStyle(.blue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.fullName).font(.body).foregroundStyle(.primary).lineLimit(1)
                                    if !contact.organization.isEmpty {
                                        Text(contact.organization).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let email = contact.emails.first {
                                        Text(email).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Kontakte (\(contactResults.count))", systemImage: "person.crop.circle")
                }
            }

            // Autocomplete suggestions (before full results)
            if !autocompleteResults.isEmpty && results.isEmpty {
                Section("Vorschläge") {
                    ForEach(autocompleteResults) { entry in
                        Button {
                            query = entry.title ?? ""
                            performSearch()
                        } label: {
                            HStack {
                                Image(systemName: iconForType(entry.type))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(entry.title ?? "Ohne Titel")
                                    .lineLimit(1)
                                Spacer()
                                Text(labelForType(entry.type))
                                    
                            }
                        }
                    }
                }
            }

            // Grouped results
            let grouped = Dictionary(grouping: filteredResults, by: { $0.type })
            let sortedTypes = grouped.keys.sorted { (grouped[$0] ?? []).count > (grouped[$1] ?? []).count }

            ForEach(sortedTypes, id: \.self) { type in
                Section {
                    ForEach(grouped[type] ?? []) { entry in
                        SearchResultRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }
                            .swipeActions(edge: .trailing) {
                                if entry.type == .task && entry.status == .active {
                                    Button {
                                        markDone(entry)
                                    } label: {
                                        Label("Erledigt", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                Button {
                                    archiveEntry(entry)
                                } label: {
                                    Label("Archiv", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                    }
                } header: {
                    Label("\(labelForType(type)) (\(grouped[type]?.count ?? 0))", systemImage: iconForType(type))
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { performSearch() }
    }

    // MARK: - Recent Entries

    private var recentEntriesView: some View {
        let entries = (try? dataBridge.listEntries(limit: 20)) ?? []
        return Group {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Suche in Brain")
                        .font(.headline)
                    Text("Gib einen Suchbegriff ein um Einträge, Mails und Kontakte zu finden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 60)
                Spacer()
            } else {
                recentEntriesList(entries)
            }
        }
    }

    private func recentEntriesList(_ entries: [Entry]) -> some View {
        List {
            Section("Letzte Einträge") {
                ForEach(entries) { entry in
                    SearchResultRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntry = entry }
                        .swipeActions(edge: .trailing) {
                            if entry.type == .task && entry.status == .active {
                                Button {
                                    markDone(entry)
                                } label: {
                                    Label("Erledigt", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                            Button {
                                archiveEntry(entry)
                            } label: {
                                Label("Archiv", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Filtered Results

    private var filteredResults: [Entry] {
        guard let type = selectedType else { return results }
        return results.filter { $0.type == type }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        if showContacts {
            // Search contacts only
            results = []
            let bridge = ContactsBridge()
            Task {
                _ = try? await bridge.requestAccess()
                let contacts = (try? bridge.search(query: query)) ?? []
                await MainActor.run {
                    contactResults = contacts
                    isSearching = false
                }
            }
        } else {
            // Search entries via FTS5
            do {
                results = try dataBridge.searchEntries(query: query, limit: 50)
                contactResults = []
                autocompleteResults = []
            } catch {
                results = []
            }
            // Also search contacts if query is long enough (include in mixed results)
            if query.count >= 3 {
                let bridge = ContactsBridge()
                Task {
                    _ = try? await bridge.requestAccess()
                    let contacts = (try? bridge.search(query: query)) ?? []
                    await MainActor.run { contactResults = Array(contacts.prefix(5)) }
                }
            } else {
                contactResults = []
            }
            isSearching = false
        }
    }

    private func performAutocomplete(_ prefix: String) {
        autocompleteResults = (try? dataBridge.autocomplete(prefix: prefix, limit: 5)) ?? []
    }

    private func markDone(_ entry: Entry) {
        guard let id = entry.id else { return }
        _ = try? dataBridge.markDone(id: id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        performSearch()
    }

    private func archiveEntry(_ entry: Entry) {
        guard let id = entry.id else { return }
        _ = try? dataBridge.archiveEntry(id: id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        performSearch()
    }

    // MARK: - Helpers

    private func iconForType(_ type: EntryType) -> String {
        type.icon
    }

    private func labelForType(_ type: EntryType) -> String {
        type.labelPlural
    }
}

// SearchContactDetailView removed — uses shared ContactDetailView(contact:) from PeopleTabView.swift

// MARK: - Search Result Row

struct SearchResultRow: View {
    let entry: Entry
    // Phase 31: Privacy zone indicator.
    var privacyLevel: PrivacyLevel = .unrestricted

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconForType(entry.type))
                    .foregroundStyle(colorForType(entry.type))
                    .font(.body)
                    .frame(width: 28)

                // Phase 31: Lock badge for privacy-restricted entries.
                if privacyLevel == .onDeviceOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .offset(x: 4, y: 2)
                } else if privacyLevel == .approvedCloudOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.title ?? "Ohne Titel")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .strikethrough(entry.status == .done, color: .secondary)

                    if entry.status == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                    }
                    if entry.priority > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                    }
                }

                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let created = entry.createdAt {
                    Text(formatDate(created))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("search.result.\(entry.id ?? 0)")
        .accessibilityLabel("\(entry.title ?? "Ohne Titel"), \(entry.type.rawValue)")
    }

    private func iconForType(_ type: EntryType) -> String {
        type.iconFilled
    }

    private func colorForType(_ type: EntryType) -> Color {
        type.color
    }

    // L18: Cached formatters (static let — Sendable in Swift 6.1+)
    private static let simpleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatDate(_ isoDate: String) -> String {
        guard let date = DateFormatters.iso8601.date(from: isoDate) else {
            guard let d = Self.simpleDateFormatter.date(from: isoDate) else { return isoDate }
            return Self.relativeDateFormatter.localizedString(for: d, relativeTo: Date())
        }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(BrainTheme.Typography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, BrainTheme.spacingMD)
                .padding(.vertical, BrainTheme.spacingSM)
                .background(isSelected ? BrainTheme.Colors.brandBlue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : BrainTheme.Colors.textPrimary)
                .clipShape(Capsule())
                .scaleEffect(isSelected ? 1.0 : 0.95)
                .animation(BrainTheme.Animations.springSnappy, value: isSelected)
        }
    }
}
