import SwiftUI
import BrainCore
import GRDB

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
