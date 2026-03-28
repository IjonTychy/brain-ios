import SwiftUI
import BrainCore
import GRDB

// Native mail tab: multi-account mailbox view with folder navigation,
// email list with detail view, compose/reply/forward support.
struct MailTabView: View {
    let dataBridge: DataBridge
    @State private var isConfigured: Bool
    @State private var showSettings = false
    @State private var accounts: [EmailAccount] = []

    init(dataBridge: DataBridge) {
        self.dataBridge = dataBridge
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        _isConfigured = State(initialValue: bridge.isConfigured)
    }

    var body: some View {
        Group {
            if isConfigured {
                MailMailboxesView(dataBridge: dataBridge, accounts: accounts, showSettings: $showSettings)
            } else {
                MailConfigFormView(dataBridge: dataBridge, isConfigured: $isConfigured)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailConfigured)) { _ in
            isConfigured = true
            loadAccounts()
        }
        .tint(BrainTheme.Colors.brandPurple)
        .task {
            let bridge = EmailBridge(pool: dataBridge.db.pool)
            try? bridge.migrateFromSingleAccountIfNeeded()
            loadAccounts()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                MailAccountsSettingsView(dataBridge: dataBridge, isConfigured: $isConfigured) {
                    loadAccounts()
                }
                .navigationTitle("E-Mail Konten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") { showSettings = false }
                    }
                }
            }
        }
    }

    private func loadAccounts() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        accounts = (try? bridge.listAccounts()) ?? []
        isConfigured = !accounts.isEmpty
    }
}

// MARK: - Mailboxes View (iOS Mail style: accounts + folders)

struct MailMailboxesView: View {
    let dataBridge: DataBridge
    let accounts: [EmailAccount]
    @Binding var showSettings: Bool
    @State private var showCompose = false
    @State private var serverFolders: [String: [String]] = [:] // accountId → folder names
    @State private var expandedAccounts: Set<String> = [] // accountIds with expanded folder lists
    @State private var isSyncing = false
    @State private var unreadCounts: [String: Int] = [:] // "accountId:folder" → count

    // Standard folders with German labels and icons
    static let standardFolders: [(key: String, label: String, icon: String)] = [
        ("INBOX", "Posteingang", "tray.fill"),
        ("Sent", "Gesendet", "paperplane.fill"),
        ("Drafts", "Entwürfe", "doc.text.fill"),
        ("Archive", "Archiv", "archivebox.fill"),
        ("Junk", "Spam", "xmark.bin.fill"),
        ("Trash", "Papierkorb", "trash.fill"),
    ]

    // Map folder name → German label and icon
    static func folderDisplay(_ key: String) -> (label: String, icon: String) {
        if let match = standardFolders.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            return (match.label, match.icon)
        }
        return (key, "folder.fill")
    }

    var body: some View {
        List {
            // MARK: - Top section: Inboxes (like iOS Mail)
            Section {
                // "Alle Posteingänge" for multi-account
                if accounts.count > 1 {
                    NavigationLink {
                        LazyMailInbox(dataBridge: dataBridge, accountId: nil, folder: "INBOX")
                            .navigationTitle("Alle Posteingänge")
                    } label: {
                        Label {
                            HStack {
                                Text("Alle Posteingänge")
                                    .fontWeight(.semibold)
                                Spacer()
                                unreadBadge(totalUnread())
                            }
                        } icon: {
                            Image(systemName: "tray.2.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Per-account inbox (always visible, one line per account)
                ForEach(accounts) { account in
                    NavigationLink {
                        LazyMailInbox(dataBridge: dataBridge, accountId: account.id, folder: "INBOX")
                            .navigationTitle(accounts.count > 1 ? "Posteingang – \(account.name)" : "Posteingang")
                    } label: {
                        Label {
                            HStack {
                                Text(accounts.count > 1 ? account.name : "Posteingang")
                                Spacer()
                                unreadBadge(cachedUnread(accountId: account.id, folder: "INBOX"))
                            }
                        } icon: {
                            Image(systemName: "tray.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            } header: {
                if accounts.count > 1 {
                    Text("Posteingänge")
                }
            }

            // MARK: - Per-account collapsible folder sections
            ForEach(accounts) { account in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedAccounts.contains(account.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedAccounts.insert(account.id)
                                } else {
                                    expandedAccounts.remove(account.id)
                                }
                            }
                        )
                    ) {
                        // Standard folders (except INBOX — already shown above)
                        ForEach(Self.standardFolders.filter { $0.key != "INBOX" }, id: \.key) { folder in
                            NavigationLink {
                                let title = accounts.count > 1 ? "\(folder.label) – \(account.name)" : folder.label
                                LazyMailInbox(dataBridge: dataBridge, accountId: account.id, folder: folder.key)
                                    .navigationTitle(title)
                            } label: {
                                Label {
                                    HStack {
                                        Text(folder.label)
                                        Spacer()
                                        unreadBadge(cachedUnread(accountId: account.id, folder: folder.key))
                                    }
                                } icon: {
                                    Image(systemName: folder.icon)
                                        .foregroundStyle(folderColor(folder.key))
                                }
                            }
                        }

                        // Server-specific extra folders
                        let extras = extraFolders(for: account.id)
                        if !extras.isEmpty {
                            ForEach(extras, id: \.self) { folderName in
                                NavigationLink {
                                    LazyMailInbox(dataBridge: dataBridge, accountId: account.id, folder: folderName)
                                        .navigationTitle(folderDisplayName(folderName))
                                } label: {
                                    Label {
                                        HStack {
                                            Text(folderDisplayName(folderName))
                                            Spacer()
                                            unreadBadge(cachedUnread(accountId: account.id, folder: folderName))
                                        }
                                    } icon: {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(account.name)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Text(accounts.count > 1 ? "" : "Ordner")
                }
            }
        }
        .navigationTitle("Postfächer")
        .refreshable { await syncAllAccounts() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "E-Mail: Konten, Ordner, Nachrichten senden", screenName: "Mail")
                    BrainAvatarButton(context: .mail)
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                MailComposeView(dataBridge: dataBridge, mode: .new(accountId: accounts.first?.id))
            }
        }
        .task {
            loadUnreadCounts()
            await loadServerFolders()
            await syncAllAccounts()
        }
    }

    // MARK: - Sync

    // Sync all folders for all accounts using single IMAP connection per account
    private func syncAllAccounts() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        isSyncing = true
        defer { isSyncing = false }

        for account in accounts {
            _ = try? await bridge.syncAllFolders(accountId: account.id, limit: 50)
        }
        loadUnreadCounts()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func unreadBadge(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.blue, in: Capsule())
        }
    }

    private func folderColor(_ key: String) -> Color {
        switch key {
        case "INBOX": return .blue
        case "Sent": return .blue
        case "Drafts": return .blue
        case "Archive": return .blue
        case "Junk": return .orange
        case "Trash": return .red
        default: return .secondary
        }
    }

    private func totalUnread() -> Int {
        accounts.reduce(0) { sum, account in
            sum + cachedUnread(accountId: account.id, folder: "INBOX")
        }
    }

    // Use cached counts to avoid DB queries on every redraw
    private func cachedUnread(accountId: String, folder: String) -> Int {
        unreadCounts["\(accountId):\(folder)"] ?? 0
    }

    private func loadUnreadCounts() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        var counts: [String: Int] = [:]
        for account in accounts {
            for folder in Self.standardFolders {
                let count = (try? bridge.unreadCount(accountId: account.id, folder: folder.key)) ?? 0
                counts["\(account.id):\(folder.key)"] = count
            }
            // Also count extra folders
            for folderName in extraFolders(for: account.id) {
                let count = (try? bridge.unreadCount(accountId: account.id, folder: folderName)) ?? 0
                counts["\(account.id):\(folderName)"] = count
            }
        }
        unreadCounts = counts
    }

    // Folders from server that are not in the standard list
    private func extraFolders(for accountId: String) -> [String] {
        guard let folders = serverFolders[accountId] else { return [] }
        let standardKeys = Set(Self.standardFolders.map { $0.key.lowercased() })
        return folders.filter { !standardKeys.contains($0.lowercased()) }
            .sorted()
    }

    // Convert IMAP folder path (e.g. "INBOX.Projekte.brain") to display name ("brain")
    // Shows only the last path component for cleaner UI.
    private func folderDisplayName(_ folder: String) -> String {
        let separator: Character = folder.contains("/") ? "/" : "."
        return folder.split(separator: separator).last.map(String.init) ?? folder
    }

    private func loadServerFolders() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        for account in accounts {
            if let folders = try? await bridge.listFolders(accountId: account.id) {
                let names = folders.map(\.0)
                await MainActor.run {
                    serverFolders[account.id] = names
                }
            }
        }
    }
}

// Lazy wrapper: defers MailInboxView creation until it actually appears.
// Prevents eager evaluation of all folder destinations when MailMailboxesView renders.
private struct LazyMailInbox: View {
    let dataBridge: DataBridge
    let accountId: String?
    let folder: String
    var body: some View {
        MailInboxView(dataBridge: dataBridge, accountId: accountId, folder: folder)
    }
}

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

// MARK: - Mail Config Form (for adding a new account)

struct MailConfigFormView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    var onAccountCreated: (() -> Void)?
    @State private var accountName = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var username = ""
    @State private var password = ""
    @State private var address = ""
    @State private var isSaving = false
    @State private var saveResult: String?
    @State private var saveSuccess = false
    @FocusState private var focusedField: MailField?

    private enum MailField {
        case name, imapHost, smtpHost, username, password, address
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("E-Mail einrichten")
                    .font(.title)
                    .fontWeight(.bold)

                Text("IMAP/SMTP für E-Mail-Integration konfigurieren.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Quick setup
                HStack(spacing: 8) {
                    Button("Gmail") { prefill(name: "Gmail", imap: "imap.gmail.com", smtp: "smtp.gmail.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Outlook") { prefill(name: "Outlook", imap: "outlook.office365.com", smtp: "smtp.office365.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("iCloud") { prefill(name: "iCloud", imap: "imap.mail.me.com", smtp: "smtp.mail.me.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                VStack(spacing: 10) {
                    TextField("Konto-Name (z.B. Gmail Privat)", text: $accountName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)

                    HStack(spacing: 8) {
                        TextField("IMAP-Server", text: $imapHost)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .imapHost)
                        TextField("Port", text: $imapPort)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    HStack(spacing: 8) {
                        TextField("SMTP-Server", text: $smtpHost)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .smtpHost)
                        TextField("Port", text: $smtpPort)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    TextField("Benutzername / E-Mail", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .username)

                    SecureField("Passwort", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)

                    TextField("Absender-Adresse (optional)", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .address)
                }
                .padding(.horizontal)

                if let result = saveResult {
                    HStack {
                        Image(systemName: saveSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(saveSuccess ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(saveSuccess ? .green : .red)
                    }
                }

                Button {
                    focusedField = nil
                    Task { await saveConfig() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text("Speichern & Testen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(imapHost.isEmpty || username.isEmpty || password.isEmpty || isSaving)
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {

        }
    }

    private func prefill(name: String, imap: String, smtp: String) {
        accountName = name
        imapHost = imap
        smtpHost = smtp
        imapPort = "993"
        smtpPort = "587"
    }

    private func saveConfig() async {
        isSaving = true
        saveResult = nil
        saveSuccess = false
        defer { isSaving = false }

        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let smtp = smtpHost.isEmpty ? imapHost.replacingOccurrences(of: "imap.", with: "smtp.") : smtpHost
        let addr = address.isEmpty ? username : address
        let name = accountName.isEmpty ? (addr.components(separatedBy: "@").last?.components(separatedBy: ".").first?.capitalized ?? "E-Mail") : accountName

        do {
            // Test IMAP connection BEFORE creating the account
            try await bridge.testIMAPConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                username: username,
                password: password
            )

            // Connection OK — now create the account
            let account = try bridge.createAccount(
                name: name,
                emailAddress: addr,
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                smtpHost: smtp,
                smtpPort: Int(smtpPort) ?? 587,
                username: username,
                password: password
            )

            // Sync emails in background
            Task {
                _ = try? await bridge.sync(limit: 10, accountId: account.id)
            }

            // Show success, then notify and switch to inbox after a short delay
            await MainActor.run {
                saveResult = "Verbindung erfolgreich! Konto wurde erstellt."
                saveSuccess = true
            }
            // Give user time to see the success message
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                NotificationCenter.default.post(name: .emailConfigured, object: nil)
                isConfigured = true
                onAccountCreated?()
            }
        } catch {
            // Auth failed — account was NOT created, form stays open
            saveResult = "Fehler: \(error.localizedDescription)"
            saveSuccess = false
        }
    }
}

// MARK: - Mail Accounts Settings View (manage all accounts)

struct MailAccountsSettingsView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    let onChanged: () -> Void
    @State private var accounts: [EmailAccount] = []
    @State private var showAddAccount = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                ForEach(accounts) { account in
                    NavigationLink {
                        MailSettingsView(
                            dataBridge: dataBridge,
                            isConfigured: $isConfigured,
                            accountId: account.id,
                            onChanged: {
                                loadAccounts()
                                onChanged()
                            }
                        )
                        .navigationTitle(account.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(account.name)
                                .fontWeight(.medium)
                            Text(account.emailAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    accounts.move(fromOffsets: source, toOffset: destination)
                    saveSortOrder()
                }
            } footer: {
                if accounts.count > 1 {
                    Text("Zum Sortieren gedrückt halten und ziehen.")
                }
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
            }
        }
        .environment(\.editMode, $editMode)
        .task {
            loadAccounts()
        }
        .toolbar {
            if accounts.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddAccount) {
            NavigationStack {
                MailConfigFormView(
                    dataBridge: dataBridge,
                    isConfigured: $isConfigured,
                    onAccountCreated: {
                        loadAccounts()
                        onChanged()
                        showAddAccount = false
                    }
                )
                .navigationTitle("Konto hinzufügen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showAddAccount = false }
                    }
                }
            }
        }
    }

    private func loadAccounts() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        accounts = (try? bridge.listAccounts()) ?? []
    }

    private func saveSortOrder() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let orderedIds = accounts.map(\.id)
        try? bridge.updateSortOrders(orderedIds)
        onChanged()
    }
}

// MARK: - Mail Settings View (edit single account)

struct MailSettingsView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    let accountId: String?
    var onChanged: (() -> Void)?
    @State private var accountName = ""
    @State private var imapHost = ""
    @State private var imapPort = ""
    @State private var smtpHost = ""
    @State private var smtpPort = ""
    @State private var username = ""
    @State private var password = ""
    @State private var address = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusSuccess = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Konto") {
                TextField("Konto-Name", text: $accountName)
            }

            Section("Eingehend (IMAP)") {
                TextField("IMAP-Server", text: $imapHost)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Port", text: $imapPort)
                    .keyboardType(.numberPad)
            }

            Section("Ausgehend (SMTP)") {
                TextField("SMTP-Server", text: $smtpHost)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Port", text: $smtpPort)
                    .keyboardType(.numberPad)
            }

            Section("Anmeldedaten") {
                TextField("Benutzername / E-Mail", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Passwort", text: $password)
                TextField("Absender-Adresse", text: $address)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section("Schnelleinrichtung") {
                HStack(spacing: 8) {
                    Button("Gmail") { prefill(imap: "imap.gmail.com", smtp: "smtp.gmail.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Outlook") { prefill(imap: "outlook.office365.com", smtp: "smtp.office365.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("iCloud") { prefill(imap: "imap.mail.me.com", smtp: "smtp.mail.me.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            if let msg = statusMessage {
                Section {
                    HStack {
                        Image(systemName: statusSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(statusSuccess ? .green : .red)
                        Text(msg)
                            .font(.callout)
                    }
                }
            }

            Section {
                Button {
                    Task { await testAndSave() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Testen & Speichern")
                        Spacer()
                    }
                }
                .disabled(imapHost.isEmpty || username.isEmpty || password.isEmpty || isTesting)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("E-Mail-Konto entfernen", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("E-Mail-Konto wirklich entfernen?", isPresented: $showDeleteConfirmation) {
            Button("Entfernen", role: .destructive) {
                if let accountId {
                    let bridge = EmailBridge(pool: dataBridge.db.pool)
                    try? bridge.deleteAccount(id: accountId)
                    let remaining = (try? bridge.listAccounts()) ?? []
                    isConfigured = !remaining.isEmpty
                    onChanged?()
                }
            }
        }
        .onAppear {
            loadExistingConfig()
        }
    }

    private func prefill(imap: String, smtp: String) {
        imapHost = imap
        smtpHost = smtp
        imapPort = "993"
        smtpPort = "587"
    }

    private func loadExistingConfig() {
        guard let accountId else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        guard let (account, _) = try? bridge.loadAccountConfig(id: accountId) else { return }
        accountName = account.name
        imapHost = account.imapHost
        imapPort = "\(account.imapPort)"
        smtpHost = account.smtpHost
        smtpPort = "\(account.smtpPort)"
        username = account.username
        address = account.emailAddress
        // Don't load password for security
    }

    private func testAndSave() async {
        isTesting = true
        statusMessage = nil
        statusSuccess = false
        defer { isTesting = false }

        guard let accountId else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let smtp = smtpHost.isEmpty ? imapHost.replacingOccurrences(of: "imap.", with: "smtp.") : smtpHost
        let addr = address.isEmpty ? username : address
        let effectivePassword: String
        if password.isEmpty {
            // Use existing password from keychain
            guard let existing = try? bridge.loadAccountConfig(id: accountId).password else {
                statusMessage = "Fehler: Kein Passwort gespeichert."
                statusSuccess = false
                return
            }
            effectivePassword = existing
        } else {
            effectivePassword = password
        }

        do {
            // Test connection first
            try await bridge.testIMAPConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                username: username,
                password: effectivePassword
            )

            // Connection OK — save changes
            var account = EmailAccount(
                id: accountId,
                name: accountName.isEmpty ? "E-Mail" : accountName,
                emailAddress: addr,
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                smtpHost: smtp,
                smtpPort: Int(smtpPort) ?? 587,
                username: username
            )
            if let existing = try? bridge.loadAccountConfig(id: accountId).account {
                account.sortOrder = existing.sortOrder
            }

            try bridge.updateAccount(account, password: password.isEmpty ? nil : password)
            statusMessage = "Verbindung OK! Einstellungen gespeichert."
            statusSuccess = true
            isConfigured = true
            // Show success for 2 seconds before notifying parent
            try? await Task.sleep(for: .seconds(2))
            onChanged?()
        } catch {
            statusMessage = "Fehler: \(error.localizedDescription)"
            statusSuccess = false
        }
    }
}
