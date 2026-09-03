import SwiftUI
import BrainCore
import GRDB

// MARK: - Mail Inbox View (email list with navigation to detail)

struct MailInboxView: View {
    let dataBridge: DataBridge
    let accountId: String?
    let folder: String
    @State private var emails: [EmailCache] = []
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var lastSyncCount: Int?
    @State private var showCompose = false
    @State private var emailToMove: EmailCache?
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<Int64> = []

    var body: some View {
        List(selection: $selectedIds) {
            if isSyncing && emails.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Lade E-Mails...")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = syncError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("Sync fehlgeschlagen")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Nochmal") {
                        Task { await syncEmails() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let count = lastSyncCount, count > 0, !isSyncing {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("\(count) neue E-Mail\(count == 1 ? "" : "s") geladen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(emails, id: \.id) { email in
                NavigationLink {
                    if let id = email.id {
                        MailDetailView(dataBridge: dataBridge, emailId: id)
                    }
                } label: {
                    MailRowView(email: email)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await deleteEmail(email) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    Button {
                        emailToMove = email
                    } label: {
                        Label("Verschieben", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !email.isRead {
                        Button {
                            markAsRead(email)
                        } label: {
                            Label("Gelesen", systemImage: "envelope.open")
                        .symbolEffect(.pulse, options: .speed(0.5))
                        }
                        .tint(.blue)
                    }
                    if folder != "Archive" {
                        Button {
                            Task { await moveEmail(email, to: "Archive") }
                        } label: {
                            Label("Archivieren", systemImage: "archivebox")
                        }
                        .tint(.purple)
                    }
                }
            }

            if emails.isEmpty && !isSyncing && syncError == nil {
                let display = MailMailboxesView.folderDisplay(folder)
                ContentUnavailableView(
                    "\(display.label) leer",
                    systemImage: "envelope",
                    description: Text("Keine E-Mails in diesem Ordner. Ziehe nach unten zum Aktualisieren.")
                )
            }
        }
        .refreshable {
            await syncEmails()
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                        if editMode == .inactive { selectedIds.removeAll() }
                    } label: {
                        Text(editMode == .active ? "Fertig" : "Bearbeiten")
                    }
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if editMode == .active && !selectedIds.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(role: .destructive) {
                            Task { await batchDelete() }
                        } label: {
                            Label("Loeschen (\(selectedIds.count))", systemImage: "trash")
                        }
                        Spacer()
                        Button {
                            Task { await batchMarkRead() }
                        } label: {
                            Label("Gelesen", systemImage: "envelope.open")
                        }
                        Spacer()
                        Button {
                            Task { await batchArchive() }
                        } label: {
                            Label("Archivieren", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
        .task {
            loadCachedEmails()
            await syncEmails()
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                MailComposeView(dataBridge: dataBridge, mode: .new(accountId: accountId))
            }
        }
        .sheet(isPresented: Binding(get: { emailToMove != nil }, set: { if !$0 { emailToMove = nil } })) {
            if let email = emailToMove, let id = email.id {
                NavigationStack {
                    MailFolderPickerView(dataBridge: dataBridge, emailId: id) {
                        emailToMove = nil
                        loadCachedEmails()
                    }
                }
            }
        }
    }

    private func loadCachedEmails() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        emails = (try? bridge.listEmails(folder: folder, accountId: accountId)) ?? []
    }

    private func syncEmails() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        isSyncing = true
        syncError = nil
        lastSyncCount = nil
        defer { isSyncing = false }

        do {
            let count = try await bridge.sync(folder: folder, accountId: accountId)
            lastSyncCount = count
            let cached = try bridge.listEmails(folder: folder, accountId: accountId)
            await MainActor.run { emails = cached }
        } catch {
            syncError = error.localizedDescription
            loadCachedEmails()
        }
    }

    // MARK: - Batch Actions

    private func batchDelete() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        for id in selectedIds {
            try? await bridge.deleteMessage(emailCacheId: id)
        }
        selectedIds.removeAll()
        editMode = .inactive
        loadCachedEmails()
    }

    private func batchMarkRead() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        for id in selectedIds {
            try? bridge.markRead(id: id)
            try? await bridge.markReadOnServer(messageId: emails.first { $0.id == id }?.messageId ?? "")
        }
        selectedIds.removeAll()
        editMode = .inactive
        loadCachedEmails()
    }

    private func batchArchive() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        for id in selectedIds {
            try? await bridge.moveMessage(emailCacheId: id, toFolder: "Archive")
        }
        selectedIds.removeAll()
        editMode = .inactive
        loadCachedEmails()
    }

    private func deleteEmail(_ email: EmailCache) async {
        guard let id = email.id else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        try? await bridge.deleteMessage(emailCacheId: id)
        loadCachedEmails()
    }

    private func moveEmail(_ email: EmailCache, to folder: String) async {
        guard let id = email.id else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        try? await bridge.moveMessage(emailCacheId: id, toFolder: folder)
        loadCachedEmails()
    }

    private func markAsRead(_ email: EmailCache) {
        guard let id = email.id else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        try? bridge.markRead(id: id)
        loadCachedEmails()
        Task {
            if let messageId = email.messageId {
                try? await bridge.markReadOnServer(messageId: messageId, accountId: email.accountId)
            }
        }
    }
}

// MARK: - Email Row

struct MailRowView: View {
    let email: EmailCache

    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(email.isRead ? Color.clear : BrainTheme.Colors.brandPurple)
                .frame(width: 8, height: 8)

            // Avatar
            let initials = emailInitials(email.fromAddr ?? "")
            let avatarHue: Color = {
                let colors: [Color] = [
                    BrainTheme.Colors.brandPurple, BrainTheme.Colors.accentMint,
                    BrainTheme.Colors.accentCoral, BrainTheme.Colors.accentSky,
                    BrainTheme.Colors.accentAmber,
                ]
                return colors[abs((email.fromAddr ?? "").hashValue) % colors.count]
            }()
            ZStack {
                Circle()
                    .fill(avatarHue.opacity(0.15))
                    .frame(width: 38, height: 38)
                Text(initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(avatarHue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(email.fromAddr ?? "Unbekannt")
                    .font(.subheadline)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .lineLimit(1)
                Text(email.subject ?? "Kein Betreff")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let body = email.bodyPlain, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let dateStr = email.date {
                    Text(formatEmailDate(dateStr))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if email.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(email.isRead ? 0.85 : 1.0)
    }

    private func emailInitials(_ address: String) -> String {
        let name = address.components(separatedBy: "@").first ?? address
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func formatEmailDate(_ dateStr: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: dateStr) {
            return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
        }
        return String(dateStr.prefix(10))
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.unitsStyle = .abbreviated
        return f
    }()
}
