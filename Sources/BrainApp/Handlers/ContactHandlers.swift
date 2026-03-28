import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Contact actions
// ContactsBridge is @unchecked Sendable (CNContactStore is thread-safe).
// Handlers are NOT @MainActor — CNContactStore.enumerateContacts is blocking
// and must not run on MainActor to avoid deadlocks.

final class ContactLoadHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.load"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let granted = try await bridge.requestAccess()
        guard granted else {
            return .error("Zugriff auf Kontakte nicht erlaubt")
        }
        let query = properties["query"]?.stringValue ?? ""
        let limit = properties["limit"]?.intValue ?? 50
        let contacts = try query.isEmpty
            ? bridge.listAll(limit: limit)
            : bridge.search(query: query, limit: limit)
        return .value(.array(contacts.map(\.expressionValue)))
    }
}

final class ContactCreateHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.create"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let givenName = properties["givenName"]?.stringValue ?? ""
        let familyName = properties["familyName"]?.stringValue ?? ""
        let email = properties["email"]?.stringValue
        let phone = properties["phone"]?.stringValue

        let identifier = try bridge.create(givenName: givenName, familyName: familyName, email: email, phone: phone)
        return .value(.object([
            "id": .string(identifier),
            "givenName": .string(givenName),
            "familyName": .string(familyName),
        ]))
    }
}

final class ContactUpdateHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.update"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let identifier = properties["identifier"]?.stringValue else {
            return .error("contact.update: identifier fehlt")
        }
        let gn = properties["givenName"]?.stringValue
        let fn = properties["familyName"]?.stringValue
        let em = properties["email"]?.stringValue
        let ph = properties["phone"]?.stringValue
        let org = properties["organization"]?.stringValue
        let job = properties["jobTitle"]?.stringValue
        let addEm = properties["addEmail"]?.stringValue
        let addPh = properties["addPhone"]?.stringValue
        let note = properties["note"]?.stringValue
        let updated = try bridge.update(identifier: identifier, givenName: gn, familyName: fn,
                     organization: org, jobTitle: job,
                     email: em, phone: ph,
                     addEmail: addEm, addPhone: addPh, note: note)
        return .value(.object([
            "identifier": .string(updated.identifier),
            "name": .string(updated.fullName),
            "organization": .string(updated.organization),
            "status": .string("updated"),
        ]))
    }
}

// Delete a contact from iOS Contacts.
final class ContactDeleteHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.delete"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let identifier = properties["identifier"]?.stringValue else {
            return .error("contact.delete: identifier fehlt")
        }
        try bridge.delete(identifier: identifier)
        return .value(.object(["status": .string("deleted"), "identifier": .string(identifier)]))
    }
}

// Merge two contacts (keep target, absorb source).
final class ContactMergeHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.merge"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let sourceId = properties["sourceId"]?.stringValue,
              let targetId = properties["targetId"]?.stringValue else {
            return .error("contact.merge: sourceId und targetId benötigt")
        }
        let merged = try bridge.merge(sourceId: sourceId, targetId: targetId)
        return .value(.object([
            "identifier": .string(merged.identifier),
            "name": .string(merged.fullName),
            "emails": .int(merged.emails.count),
            "phones": .int(merged.phones.count),
            "status": .string("merged"),
        ]))
    }
}

// Find duplicate contacts for cleanup.
final class ContactDuplicatesHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.duplicates"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 20
        let dupes = try bridge.findDuplicates(limit: limit)
        let results: [ExpressionValue] = dupes.map { d in
            .object([
                "contact1Id": .string(d.contact1.identifier),
                "contact1Name": .string(d.contact1.fullName),
                "contact2Id": .string(d.contact2.identifier),
                "contact2Name": .string(d.contact2.fullName),
                "reason": .string(d.reason),
            ])
        }
        return .value(.object([
            "duplicates": .array(results),
            "count": .int(dupes.count),
        ]))
    }
}
