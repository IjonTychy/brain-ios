import Foundation
import BrainCore
import GRDB
import SwiftMail

// Bridge between Action Primitives and email functionality.
// Uses SwiftMail for native IMAP/SMTP. Multi-account: metadata in DB, passwords in Keychain.
// @unchecked Sendable: pool is thread-safe (GRDB), keychain is stateless per call.
final class EmailBridge: @unchecked Sendable {
    let pool: DatabasePool
    private let keychain = KeychainService()

    // Legacy single-account keychain keys (for migration)
    private static let legacyImapHostKey = "email.imap.host"
    private static let legacyImapPortKey = "email.imap.port"
    private static let legacySmtpHostKey = "email.smtp.host"
    private static let legacySmtpPortKey = "email.smtp.port"
    private static let legacyEmailUserKey = "email.username"
    private static let legacyEmailPassKey = "email.password"
    private static let legacyEmailAddrKey = "email.address"

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // Password keychain key for a given account
    private func passwordKey(for accountId: String) -> String {
        "email.\(accountId).password"
    }

    // MARK: - Account Management

    var isConfigured: Bool {
        let hasAccounts = (try? pool.read { db in
            try EmailAccount.fetchCount(db) > 0
        }) ?? false
        if hasAccounts { return true }
        // Check legacy single-account config
        return keychain.exists(key: Self.legacyImapHostKey) && keychain.exists(key: Self.legacyEmailUserKey)
    }

    /// Migrate legacy single-account Keychain config to DB-based multi-account.
    /// Call once at startup or when isConfigured returns true but no DB accounts exist.
    func migrateFromSingleAccountIfNeeded() throws {
        let accountCount = try pool.read { db in try EmailAccount.fetchCount(db) }
        guard accountCount == 0,
              keychain.exists(key: Self.legacyImapHostKey),
              let imapHost = keychain.read(key: Self.legacyImapHostKey),
              let username = keychain.read(key: Self.legacyEmailUserKey),
              let password = keychain.read(key: Self.legacyEmailPassKey) else {
            return
        }

        let imapPort = Int(keychain.read(key: Self.legacyImapPortKey) ?? "993") ?? 993
        let smtpHost = keychain.read(key: Self.legacySmtpHostKey) ?? imapHost.replacingOccurrences(of: "imap.", with: "smtp.")
        let smtpPort = Int(keychain.read(key: Self.legacySmtpPortKey) ?? "587") ?? 587
        let address = keychain.read(key: Self.legacyEmailAddrKey) ?? username

        // Derive display name from email domain
        let domain = address.components(separatedBy: "@").last ?? "E-Mail"
        let name = domain.components(separatedBy: ".").first?.capitalized ?? "E-Mail"

        let account = EmailAccount(
            name: name,
            emailAddress: address,
            imapHost: imapHost,
            imapPort: imapPort,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            username: username
        )

        // Save password under new key (no biometry — app is FaceID-protected at launch)
        try keychain.save(key: passwordKey(for: account.id), value: password)

        // Save account to DB and assign existing cached emails
        try pool.write { db in
            try account.insert(db)
            try db.execute(
                sql: "UPDATE emailCache SET accountId = ? WHERE accountId IS NULL",
                arguments: [account.id]
            )
        }

        // Clean up legacy keys
        keychain.delete(key: Self.legacyImapHostKey)
        keychain.delete(key: Self.legacyImapPortKey)
        keychain.delete(key: Self.legacySmtpHostKey)
        keychain.delete(key: Self.legacySmtpPortKey)
        keychain.delete(key: Self.legacyEmailUserKey)
        keychain.delete(key: Self.legacyEmailPassKey)
        keychain.delete(key: Self.legacyEmailAddrKey)
    }

    func listAccounts() throws -> [EmailAccount] {
        try pool.read { db in
            try EmailAccount.order(Column("sortOrder").asc, Column("name").asc).fetchAll(db)
        }
    }

    func createAccount(
        name: String, emailAddress: String,
        imapHost: String, imapPort: Int = 993,
        smtpHost: String, smtpPort: Int = 587,
        username: String, password: String
    ) throws -> EmailAccount {
        let account = EmailAccount(
            name: name,
            emailAddress: emailAddress,
            imapHost: imapHost,
            imapPort: imapPort,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            username: username
        )
        // Email passwords stored without biometry — the app itself is FaceID-protected.
        // Using saveWithBiometry here would trigger FaceID on every IMAP operation.
        try keychain.save(key: passwordKey(for: account.id), value: password)
        try pool.write { db in try account.insert(db) }
        return account
    }

    func updateAccount(_ account: EmailAccount, password: String?) throws {
        try pool.write { db in try account.update(db) }
        if let password {
            try keychain.save(key: passwordKey(for: account.id), value: password)
        }
    }

    func deleteAccount(id: String) throws {
        keychain.delete(key: passwordKey(for: id))
        try pool.write { db in
            _ = try EmailAccount.deleteOne(db, key: id)
            // emailCache rows cascade-deleted by FK
        }
    }

    /// Test IMAP connection without creating an account. Throws on failure.
    func testIMAPConnection(
        imapHost: String, imapPort: Int, username: String, password: String
    ) async throws {
        let server = IMAPServer(host: imapHost, port: imapPort)
        try await server.connect()
        defer { Task { @Sendable in try? await server.disconnect() } }
        try await server.login(username: username, password: password)
    }

    /// Update sort orders for all accounts (used for drag-to-reorder).
    func updateSortOrders(_ orderedIds: [String]) throws {
        try pool.write { db in
            for (index, id) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE emailAccounts SET sortOrder = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    func loadAccountConfig(id: String) throws -> (account: EmailAccount, password: String) {
        guard let account = try pool.read({ db in try EmailAccount.fetchOne(db, key: id) }) else {
            throw EmailBridgeError.notConfigured
        }
        guard let password = keychain.read(key: passwordKey(for: id)) else {
            throw EmailBridgeError.notConfigured
        }
        return (account, password)
    }

    // Legacy compatibility: load first account
    struct EmailConfig: Sendable {
        let imapHost: String
        let imapPort: Int
        let smtpHost: String
        let smtpPort: Int
        let username: String
        let password: String
        let address: String
    }

    func loadConfig() throws -> EmailConfig {
        try migrateFromSingleAccountIfNeeded()
        let accounts = try listAccounts()
        guard let first = accounts.first else { throw EmailBridgeError.notConfigured }
        let (account, password) = try loadAccountConfig(id: first.id)
        return EmailConfig(
            imapHost: account.imapHost, imapPort: account.imapPort,
            smtpHost: account.smtpHost, smtpPort: account.smtpPort,
            username: account.username, password: password,
            address: account.emailAddress
        )
    }

    // Legacy compatibility for action handlers
    func saveConfig(imapHost: String, imapPort: Int = 993, smtpHost: String, smtpPort: Int = 587,
                    username: String, password: String, address: String? = nil) throws {
        let addr = address ?? username
        // Check if account with this address already exists
        let existing = try pool.read { db in
            try EmailAccount.filter(Column("emailAddress") == addr).fetchOne(db)
        }
        if let existing {
            var updated = existing
            updated.imapHost = imapHost
            updated.imapPort = imapPort
            updated.smtpHost = smtpHost
            updated.smtpPort = smtpPort
            updated.username = username
            updated.emailAddress = addr
            try updateAccount(updated, password: password)
        } else {
            let domain = addr.components(separatedBy: "@").last ?? "E-Mail"
            let name = domain.components(separatedBy: ".").first?.capitalized ?? "E-Mail"
            _ = try createAccount(
                name: name, emailAddress: addr,
                imapHost: imapHost, imapPort: imapPort,
                smtpHost: smtpHost, smtpPort: smtpPort,
                username: username, password: password
            )
        }
    }

    func deleteConfig() {
        // Delete all accounts (legacy compat)
        if let accounts = try? listAccounts() {
            for account in accounts {
                try? deleteAccount(id: account.id)
            }
        }
        // Also clean legacy keys if any
        keychain.delete(key: Self.legacyImapHostKey)
        keychain.delete(key: Self.legacyImapPortKey)
        keychain.delete(key: Self.legacySmtpHostKey)
        keychain.delete(key: Self.legacySmtpPortKey)
        keychain.delete(key: Self.legacyEmailUserKey)
        keychain.delete(key: Self.legacyEmailPassKey)
        keychain.delete(key: Self.legacyEmailAddrKey)
    }

    // MARK: - Read from local cache

    func listEmails(folder: String = "INBOX", limit: Int = 50, accountId: String? = nil) throws -> [EmailCache] {
        try pool.read { db in
            var request = EmailCache
                .filter(Column("folder") == folder)
                .order(Column("date").desc)
                .limit(limit)
            if let accountId {
                request = request.filter(Column("accountId") == accountId)
            }
            return try request.fetchAll(db)
        }
    }

    func listAllEmails(limit: Int = 100, accountId: String? = nil) throws -> [EmailCache] {
        try pool.read { db in
            var request = EmailCache
                .order(Column("date").desc)
                .limit(limit)
            if let accountId {
                request = request.filter(Column("accountId") == accountId)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchEmail(id: Int64) throws -> EmailCache? {
        try pool.read { db in
            try EmailCache.fetchOne(db, key: id)
        }
    }

    func searchEmails(query: String, limit: Int = 20) throws -> [EmailCache] {
        let escaped = query.escapedForLIKE()
        return try pool.read { db in
            try EmailCache
                .filter(
                    Column("subject").like("%\(escaped)%", escape: "\\") ||
                    Column("fromAddr").like("%\(escaped)%", escape: "\\") ||
                    Column("bodyPlain").like("%\(escaped)%", escape: "\\")
                )
                .order(Column("date").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func markRead(id: Int64) throws {
        try pool.write { db in
            if var email = try EmailCache.fetchOne(db, key: id) {
                email.isRead = true
                try email.update(db)
            }
        }
    }

    /// Cached folder names for an account
    func cachedFolders(accountId: String) throws -> [String] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT folder FROM emailCache
                WHERE accountId = ? AND folder IS NOT NULL
                ORDER BY folder
                """, arguments: [accountId])
            return rows.compactMap { $0["folder"] as? String }
        }
    }

    /// Unread count per folder for an account
    func unreadCount(accountId: String, folder: String) throws -> Int {
        try pool.read { db in
            try EmailCache
                .filter(Column("accountId") == accountId)
                .filter(Column("folder") == folder)
                .filter(Column("isRead") == false)
                .fetchCount(db)
        }
    }

    // MARK: - IMAP Operations

    // Shared ISO8601 formatter — avoid per-message allocation in sync loop.
    // nonisolated(unsafe): ISO8601DateFormatter is thread-safe after init (no config changes).
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    private func connectIMAP(accountId: String) async throws -> (IMAPServer, EmailAccount) {
        let (account, password) = try loadAccountConfig(id: accountId)
        let server = IMAPServer(host: account.imapHost, port: account.imapPort)
        // Connect with timeout to avoid hanging on unresponsive servers
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.connect() }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw EmailBridgeError.connectionTimeout
            }
            // First to finish wins; cancel the other
            try await group.next()
            group.cancelAll()
        }
        try await server.login(username: account.username, password: password)
        return (server, account)
    }

    /// List IMAP mailboxes/folders for an account
    func listFolders(accountId: String) async throws -> [(name: String, hasChildren: Bool)] {
        let (server, _) = try await connectIMAP(accountId: accountId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        let mailboxes = try await server.listMailboxes()
        return mailboxes
            .filter { $0.isSelectable }
            .map { (name: $0.name, hasChildren: $0.hasChildren) }
            .sorted { $0.name < $1.name }
    }

    func sync(folder: String = "INBOX", limit: Int = 50, accountId: String? = nil) async throws -> Int {
        // Resolve accountId: use provided, or fall back to first account
        let resolvedId: String
        if let accountId {
            resolvedId = accountId
        } else {
            try migrateFromSingleAccountIfNeeded()
            guard let first = try listAccounts().first else {
                throw EmailBridgeError.notConfigured
            }
            resolvedId = first.id
        }

        let (server, _) = try await connectIMAP(accountId: resolvedId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        let selection = try await server.selectMailbox(folder)
        guard let latest = selection.latest(limit) else {
            return 0
        }

        // Collect messages from the async stream
        var fetched: [(messageId: String, folder: String, from: String, to: String,
                        subject: String, bodyPlain: String, bodyHtml: String,
                        date: String, isRead: Bool, hasAttachments: Bool)] = []

        for try await message in server.fetchMessages(using: latest) {
            let messageId = message.header.messageId?.description ?? ""
            guard !messageId.isEmpty else { continue }

            let from = message.from ?? ""
            let to = message.to.joined(separator: ", ")
            let dateStr = message.date.map { Self.isoFormatter.string(from: $0) } ?? ""
            let isRead = message.flags.contains(.seen)
            let hasAttachments = !message.attachments.isEmpty

            fetched.append((
                messageId: messageId,
                folder: folder,
                from: from,
                to: to,
                subject: message.subject ?? "",
                bodyPlain: message.textBody ?? "",
                bodyHtml: message.htmlBody ?? "",
                date: dateStr,
                isRead: isRead,
                hasAttachments: hasAttachments
            ))
        }

        // Write to local cache, skipping previously deleted emails
        let fetchedCopy = fetched
        let acctId = resolvedId
        let folderName = folder
        let synced = try await pool.write { db -> Int in
            // Load deleted messageIds to skip them during sync
            let deletedIds = try String.fetchSet(db, sql:
                "SELECT messageId FROM emailDeletedIds WHERE accountId = ?",
                arguments: [acctId])

            // Remove local mails no longer on server (deleted in webmail/other client)
            let serverMessageIds = Set(fetchedCopy.map { $0.messageId })
            let localMails = try EmailCache
                .filter(Column("accountId") == acctId)
                .filter(Column("folder") == folderName)
                .fetchAll(db)
            for local in localMails {
                if let mid = local.messageId, !serverMessageIds.contains(mid) {
                    _ = try EmailCache.deleteOne(db, key: local.id)
                }
            }

            var count = 0
            for msg in fetchedCopy {
                // Skip emails the user has previously deleted
                if deletedIds.contains(msg.messageId) { continue }

                let existing = try EmailCache
                    .filter(Column("messageId") == msg.messageId)
                    .fetchOne(db)
                if existing != nil { continue }

                var cached = EmailCache(
                    messageId: msg.messageId,
                    folder: msg.folder,
                    fromAddr: msg.from,
                    toAddr: msg.to,
                    subject: msg.subject,
                    bodyPlain: msg.bodyPlain,
                    bodyHtml: msg.bodyHtml,
                    date: msg.date,
                    isRead: msg.isRead,
                    hasAttachments: msg.hasAttachments,
                    accountId: acctId
                )
                try cached.insert(db)
                count += 1
            }
            return count
        }
        return synced
    }

    /// Sync ALL folders for an account using a SINGLE IMAP connection.
    /// Discovers server folders via LIST, then syncs each selectable folder.
    func syncAllFolders(accountId: String, limit: Int = 50) async throws -> Int {
        let (server, _) = try await connectIMAP(accountId: accountId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        // Discover all selectable folders from the server
        let mailboxes = try await server.listMailboxes()
        let folderNames = mailboxes
            .filter { $0.isSelectable }
            .map { $0.name }

        // Sync INBOX first (highest priority), then the rest
        let sorted = folderNames.sorted { a, _ in
            a.caseInsensitiveCompare("INBOX") == .orderedSame
        }

        var total = 0
        for folder in sorted {
            do {
                let count = try await syncWithServer(server, folder: folder, limit: limit, accountId: accountId)
                total += count
            } catch {
                // Some folders may fail (permission, empty), continue with others
                continue
            }
        }
        return total
    }

    /// Internal sync using an already-connected IMAP server (avoids reconnection per folder).
    private func syncWithServer(_ server: IMAPServer, folder: String, limit: Int, accountId: String) async throws -> Int {
        let selection = try await server.selectMailbox(folder)
        guard let latest = selection.latest(limit) else { return 0 }

        var fetched: [(messageId: String, folder: String, from: String, to: String,
                        subject: String, bodyPlain: String, bodyHtml: String,
                        date: String, isRead: Bool, hasAttachments: Bool)] = []

        for try await message in server.fetchMessages(using: latest) {
            let messageId = message.header.messageId?.description ?? ""
            guard !messageId.isEmpty else { continue }
            let from = message.from ?? ""
            let to = message.to.joined(separator: ", ")
            let dateStr = message.date.map { Self.isoFormatter.string(from: $0) } ?? ""
            let isRead = message.flags.contains(.seen)
            let hasAttachments = !message.attachments.isEmpty
            fetched.append((messageId: messageId, folder: folder, from: from, to: to,
                            subject: message.subject ?? "", bodyPlain: message.textBody ?? "",
                            bodyHtml: message.htmlBody ?? "", date: dateStr,
                            isRead: isRead, hasAttachments: hasAttachments))
        }

        let fetchedCopy = fetched
        let acctId = accountId
        let folderName = folder
        return try await pool.write { db -> Int in
            let deletedIds = try String.fetchSet(db, sql:
                "SELECT messageId FROM emailDeletedIds WHERE accountId = ?", arguments: [acctId])

            // Collect server message IDs for this folder
            let serverMessageIds = Set(fetchedCopy.map { $0.messageId })

            // Remove local mails no longer on server (deleted in webmail/Outlook).
            // Always run cleanup — even when serverMessageIds is empty (all deleted on server).
            let localMails = try EmailCache
                .filter(Column("accountId") == acctId)
                .filter(Column("folder") == folderName)
                .fetchAll(db)
            for local in localMails {
                if let mid = local.messageId, !serverMessageIds.contains(mid) {
                    _ = try EmailCache.deleteOne(db, key: local.id)
                }
            }

            var count = 0
            for msg in fetchedCopy {
                if deletedIds.contains(msg.messageId) { continue }
                let existing = try EmailCache.filter(Column("messageId") == msg.messageId).fetchOne(db)
                if existing != nil { continue }
                var cached = EmailCache(
                    messageId: msg.messageId, folder: msg.folder, fromAddr: msg.from,
                    toAddr: msg.to, subject: msg.subject, bodyPlain: msg.bodyPlain,
                    bodyHtml: msg.bodyHtml, date: msg.date, isRead: msg.isRead,
                    hasAttachments: msg.hasAttachments, accountId: acctId)
                try cached.insert(db)
                count += 1
            }
            return count
        }
    }

    // MARK: - SMTP Send via SwiftMail

    func send(to: String, subject: String, body: String, accountId: String? = nil) async throws {
        let resolvedId: String
        if let accountId {
            resolvedId = accountId
        } else {
            guard let first = try listAccounts().first else {
                throw EmailBridgeError.notConfigured
            }
            resolvedId = first.id
        }

        let (account, password) = try loadAccountConfig(id: resolvedId)
        let smtp = SMTPServer(host: account.smtpHost, port: account.smtpPort)
        defer { Task { @Sendable in try? await smtp.disconnect() } }

        try await smtp.connect()
        try await smtp.login(username: account.username, password: password)

        let email = Email(
            sender: EmailAddress(address: account.emailAddress),
            recipients: [EmailAddress(address: to)],
            subject: subject,
            textBody: body
        )
        try await smtp.sendEmail(email)
    }

    // MARK: - IMAP Mark Read on Server

    func markReadOnServer(messageId: String, accountId: String? = nil) async throws {
        let resolvedId: String
        if let accountId {
            resolvedId = accountId
        } else {
            guard let first = try listAccounts().first else { return }
            resolvedId = first.id
        }

        let (server, _) = try await connectIMAP(accountId: resolvedId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        _ = try await server.selectMailbox("INBOX")
        let uids: MessageIdentifierSet<UID> = try await server.search(criteria: [.header("Message-ID", messageId)])
        if !uids.isEmpty {
            try await server.store(flags: [Flag.seen], on: uids, operation: .add)
        }
    }

    // MARK: - IMAP Move Message

    func moveMessage(emailCacheId: Int64, toFolder: String) async throws {
        guard let email = try fetchEmail(id: emailCacheId),
              let messageId = email.messageId,
              let accountId = email.accountId else {
            throw EmailBridgeError.syncFailed("E-Mail nicht gefunden")
        }

        let (server, _) = try await connectIMAP(accountId: accountId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        let sourceFolder = email.folder ?? "INBOX"
        _ = try await server.selectMailbox(sourceFolder)
        let uids: MessageIdentifierSet<UID> = try await server.search(criteria: [.header("Message-ID", messageId)])
        if !uids.isEmpty {
            try await server.move(messages: uids, to: toFolder)
        }

        // Update local cache
        try await pool.write { db in
            if var cached = try EmailCache.fetchOne(db, key: emailCacheId) {
                cached.folder = toFolder
                try cached.update(db)
            }
        }
    }

    // MARK: - IMAP Delete Message

    func deleteMessage(emailCacheId: Int64) async throws {
        guard let email = try fetchEmail(id: emailCacheId),
              let messageId = email.messageId,
              let accountId = email.accountId else {
            throw EmailBridgeError.syncFailed("E-Mail nicht gefunden")
        }

        let (server, _) = try await connectIMAP(accountId: accountId)
        defer { Task { @Sendable in try? await server.disconnect() } }

        let sourceFolder = email.folder ?? "INBOX"
        _ = try await server.selectMailbox(sourceFolder)
        let uids: MessageIdentifierSet<UID> = try await server.search(criteria: [.header("Message-ID", messageId)])
        if !uids.isEmpty {
            // Move to Trash if not already there, otherwise permanent delete
            if sourceFolder.lowercased() != "trash" {
                do {
                    try await server.moveToTrash(messages: uids)
                } catch {
                    // Fallback: flag as deleted
                    try await server.store(flags: [Flag.deleted], on: uids, operation: .add)
                    try await server.expunge()
                }
            } else {
                try await server.store(flags: [Flag.deleted], on: uids, operation: .add)
                try await server.expunge()
            }
        }

        // Record deletion so sync won't re-insert, then remove from local cache
        try await pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO emailDeletedIds (messageId, accountId)
                VALUES (?, ?)
                """, arguments: [messageId, accountId])
            _ = try EmailCache.deleteOne(db, key: emailCacheId)
        }
    }
}

extension Notification.Name {
    static let emailConfigured = Notification.Name("brainEmailConfigured")
}

enum EmailBridgeError: Error, LocalizedError {
    case notConfigured
    case syncFailed(String)
    case connectionTimeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "E-Mail nicht konfiguriert. Bitte IMAP-Einstellungen hinterlegen."
        case .syncFailed(let reason):
            return "E-Mail-Sync fehlgeschlagen: \(reason)"
        case .connectionTimeout:
            return "Verbindung zum E-Mail-Server abgelaufen (Timeout)."
        }
    }
}

// MARK: - Action Handlers

@MainActor final class EmailListHandler: ActionHandler {
    let type = "email.list"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let folder = properties["folder"]?.stringValue ?? "INBOX"
        let limit = properties["limit"]?.intValue ?? 50
        let emails = try bridge.listEmails(folder: folder, limit: limit)
        let results = emails.map { email -> ExpressionValue in
            .object([
                "id": .int(Int(email.id ?? 0)),
                "from": .string(email.fromAddr ?? ""),
                "subject": .string(email.subject ?? ""),
                "date": .string(email.date ?? ""),
                "isRead": .bool(email.isRead),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class EmailFetchHandler: ActionHandler {
    let type = "email.fetch"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.fetch: id fehlt")
        }
        guard let email = try bridge.fetchEmail(id: id) else {
            return .error("E-Mail \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(email.id ?? 0)),
            "from": .string(email.fromAddr ?? ""),
            "to": .string(email.toAddr ?? ""),
            "subject": .string(email.subject ?? ""),
            "body": .string(email.bodyPlain ?? ""),
            "date": .string(email.date ?? ""),
            "isRead": .bool(email.isRead),
        ]))
    }
}

@MainActor final class EmailSearchHandler: ActionHandler {
    let type = "email.search"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let query = properties["query"]?.stringValue else {
            return .error("email.search: query fehlt")
        }
        let limit = properties["limit"]?.intValue ?? 20
        let emails = try bridge.searchEmails(query: query, limit: limit)
        let results = emails.map { email -> ExpressionValue in
            .object([
                "id": .int(Int(email.id ?? 0)),
                "from": .string(email.fromAddr ?? ""),
                "subject": .string(email.subject ?? ""),
                "date": .string(email.date ?? ""),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class EmailMarkReadHandler: ActionHandler {
    let type = "email.markRead"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.markRead: id fehlt")
        }
        try bridge.markRead(id: id)
        if let email = try bridge.fetchEmail(id: id), let messageId = email.messageId {
            try await bridge.markReadOnServer(messageId: messageId, accountId: email.accountId)
        }
        return .success
    }
}

@MainActor final class EmailSendHandler: ActionHandler {
    let type = "email.send"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let to = properties["to"]?.stringValue,
              let subject = properties["subject"]?.stringValue else {
            return .error("email.send: to und subject erforderlich")
        }
        let body = properties["body"]?.stringValue ?? ""
        try await bridge.send(to: to, subject: subject, body: body)
        return .success
    }
}

@MainActor final class EmailSyncHandler: ActionHandler {
    let type = "email.sync"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 50
        let folder = properties["folder"]?.stringValue ?? "INBOX"
        let synced = try await bridge.sync(folder: folder, limit: limit)
        return .value(.object(["synced": .int(synced)]))
    }
}

@MainActor final class EmailConfigureHandler: ActionHandler {
    let type = "email.configure"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let imapHost = properties["imapHost"]?.stringValue,
              let username = properties["username"]?.stringValue,
              let password = properties["password"]?.stringValue else {
            return .error("email.configure: imapHost, username und password erforderlich")
        }
        let smtpHost = properties["smtpHost"]?.stringValue ?? imapHost.replacingOccurrences(of: "imap.", with: "smtp.")
        let imapPort = properties["imapPort"]?.intValue ?? 993
        let smtpPort = properties["smtpPort"]?.intValue ?? 587
        let address = properties["address"]?.stringValue

        try bridge.saveConfig(
            imapHost: imapHost, imapPort: imapPort,
            smtpHost: smtpHost, smtpPort: smtpPort,
            username: username, password: password,
            address: address
        )
        // Notify UI that email has been configured
        await MainActor.run {
            NotificationCenter.default.post(name: .emailConfigured, object: nil)
        }
        return .value(.object(["configured": .bool(true)]))
    }
}

// Move email to a different folder via IMAP.
@MainActor final class EmailMoveHandler: ActionHandler {
    let type = "email.move"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.move: id fehlt")
        }
        guard let folder = properties["folder"]?.stringValue else {
            return .error("email.move: folder fehlt")
        }
        try await bridge.moveMessage(emailCacheId: id, toFolder: folder)
        return .value(.object([
            "moved": .bool(true),
            "id": .int(Int(id)),
            "folder": .string(folder)
        ]))
    }
}

// Spam check: returns inbox emails with metadata for LLM analysis.
@MainActor final class EmailSpamCheckHandler: ActionHandler {
    let type = "email.spamCheck"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 20
        let emails = try bridge.listEmails(folder: "INBOX", limit: limit)
        let items = emails.map { email -> ExpressionValue in
            .object([
                "id": .int(Int(email.id ?? 0)),
                "from": .string(email.fromAddr ?? ""),
                "subject": .string(email.subject ?? ""),
                "preview": .string(String((email.bodyPlain ?? "").prefix(300))),
                "date": .string(email.date ?? ""),
                "isRead": .bool(email.isRead),
            ])
        }
        return .value(.object([
            "emails": .array(items),
            "count": .int(items.count),
            "instruction": .string("Analysiere jede E-Mail: Ist sie Spam, Phishing oder unerwuenscht? Begründe kurz. Schlage vor, verdächtige E-Mails in den Spam-Ordner zu verschieben (email_move tool mit folder='Junk').")
        ]))
    }
}

// Spam rescue: returns spam folder emails for LLM to check false positives.
@MainActor final class EmailRescueSpamHandler: ActionHandler {
    let type = "email.rescueSpam"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 20
        // Try to sync spam folder first
        _ = try? await bridge.sync(folder: "Junk", limit: limit)
        let emails = try bridge.listEmails(folder: "Junk", limit: limit)
        let items = emails.map { email -> ExpressionValue in
            .object([
                "id": .int(Int(email.id ?? 0)),
                "from": .string(email.fromAddr ?? ""),
                "subject": .string(email.subject ?? ""),
                "preview": .string(String((email.bodyPlain ?? "").prefix(300))),
                "date": .string(email.date ?? ""),
            ])
        }
        return .value(.object([
            "emails": .array(items),
            "count": .int(items.count),
            "instruction": .string("Analysiere jede E-Mail im Spam-Ordner: Ist sie wirklich Spam oder ein False Positive (fälschlich als Spam markiert)? Schlage vor, legitime E-Mails zurück in den Posteingang zu verschieben (email_move tool mit folder='INBOX').")
        ]))
    }
}

// MARK: - Additional Email Handlers (ARCHITECTURE.md primitives)

@MainActor final class EmailReadHandler: ActionHandler {
    let type = "email.read"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.read: id fehlt")
        }
        guard let email = try bridge.fetchEmail(id: id) else {
            return .error("E-Mail \(id) nicht gefunden")
        }
        try bridge.markRead(id: id)
        return .value(.object([
            "id": .int(Int(email.id ?? 0)),
            "from": .string(email.fromAddr ?? ""),
            "to": .string(email.toAddr ?? ""),
            "subject": .string(email.subject ?? ""),
            "body": .string(email.bodyPlain ?? email.bodyHtml ?? ""),
            "date": .string(email.date ?? ""),
            "isRead": .bool(true),
            "hasAttachments": .bool(email.hasAttachments),
            "folder": .string(email.folder ?? "INBOX"),
        ]))
    }
}

@MainActor final class EmailDeleteHandler: ActionHandler {
    let type = "email.delete"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.delete: id fehlt")
        }
        try await bridge.deleteMessage(emailCacheId: id)
        return .success
    }
}

@MainActor final class EmailReplyHandler: ActionHandler {
    let type = "email.reply"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }),
              let body = properties["body"]?.stringValue else {
            return .error("email.reply: id und body erforderlich")
        }
        guard let original = try bridge.fetchEmail(id: id) else {
            return .error("E-Mail \(id) nicht gefunden")
        }
        let to = original.fromAddr ?? ""
        let subject = "Re: \(original.subject ?? "")"
        let quotedBody = "\(body)\n\n---\nAm \(original.date ?? "") schrieb \(original.fromAddr ?? ""):\n\(original.bodyPlain ?? "")"
        try await bridge.send(to: to, subject: subject, body: quotedBody)
        return .value(.object([
            "to": .string(to),
            "subject": .string(subject),
            "status": .string("sent"),
        ]))
    }
}

@MainActor final class EmailForwardHandler: ActionHandler {
    let type = "email.forward"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }),
              let to = properties["to"]?.stringValue else {
            return .error("email.forward: id und to erforderlich")
        }
        guard let original = try bridge.fetchEmail(id: id) else {
            return .error("E-Mail \(id) nicht gefunden")
        }
        let subject = "Fwd: \(original.subject ?? "")"
        let body = "\(properties["body"]?.stringValue ?? "")\n\n---------- Weitergeleitete Nachricht ----------\nVon: \(original.fromAddr ?? "")\nDatum: \(original.date ?? "")\nBetreff: \(original.subject ?? "")\n\n\(original.bodyPlain ?? "")"
        try await bridge.send(to: to, subject: subject, body: body)
        return .value(.object([
            "to": .string(to),
            "subject": .string(subject),
            "status": .string("sent"),
        ]))
    }
}

@MainActor final class EmailFlagHandler: ActionHandler {
    let type = "email.flag"
    private let bridge: EmailBridge

    init(bridge: EmailBridge) { self.bridge = bridge }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("email.flag: id fehlt")
        }
        try await bridge.pool.write { db in
            if var cached = try EmailCache.fetchOne(db, key: id) {
                let currentFlags = cached.flags ?? ""
                if currentFlags.contains("flagged") {
                    cached.flags = currentFlags.replacingOccurrences(of: "flagged", with: "").trimmingCharacters(in: .whitespaces)
                } else {
                    cached.flags = currentFlags.isEmpty ? "flagged" : "\(currentFlags) flagged"
                }
                try cached.update(db)
            }
        }
        return .success
    }
}
