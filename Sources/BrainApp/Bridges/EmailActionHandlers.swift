import Foundation
import BrainCore
import GRDB
import SwiftMail

// Email action handlers (email.* primitives) backed by EmailBridge.
// Split out of EmailBridge.swift to keep compile units small.

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
