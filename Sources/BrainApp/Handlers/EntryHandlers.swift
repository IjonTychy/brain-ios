import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Entry actions

@MainActor final class EntryCreateHandler: ActionHandler {
    let type = "entry.create"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let title = properties["title"]?.stringValue ?? "Ohne Titel"
        let entryType = properties["type"]?.stringValue ?? "thought"
        let body = properties["body"]?.stringValue

        let entry = try data.createEntry(title: title, type: entryType, body: body)
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "title": .string(entry.title ?? ""),
        ]))
    }
}

@MainActor final class EntrySearchHandler: ActionHandler {
    let type = "entry.search"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let query = properties["query"]?.stringValue ?? ""
        let limit = properties["limit"]?.intValue ?? 20

        let entries = try data.searchEntries(query: query, limit: limit)
        let results = entries.map { entry -> ExpressionValue in
            .object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
                "type": .string(entry.type.rawValue),
                "body": .string(entry.body ?? ""),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class EntryUpdateHandler: ActionHandler {
    let type = "entry.update"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .actionError(code: "entry.missing_id", message: "ID fehlt für entry.update")
        }
        let title = properties["title"]?.stringValue
        let body = properties["body"]?.stringValue

        do {
            guard let entry = try data.updateEntry(id: id, title: title, body: body) else {
                return .actionError(code: "entry.not_found", message: "Entry \(id) nicht gefunden")
            }
            return .value(.object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
            ]))
        } catch {
            return .actionError(code: "entry.update_failed", message: "Entry-Update fehlgeschlagen", details: error.localizedDescription)
        }
    }
}

@MainActor final class EntryDeleteHandler: ActionHandler {
    let type = "entry.delete"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .actionError(code: "entry.missing_id", message: "ID fehlt für entry.delete")
        }
        do {
            try data.deleteEntry(id: id)
            return .success
        } catch {
            return .actionError(code: "entry.delete_failed", message: "Entry-Loeschung fehlgeschlagen", details: error.localizedDescription)
        }
    }
}

@MainActor final class EntryMarkDoneHandler: ActionHandler {
    let type = "entry.markDone"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("entry.markDone: id fehlt")
        }
        guard let entry = try data.markDone(id: id) else {
            return .error("Entry \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "status": .string(entry.status.rawValue),
        ]))
    }
}

@MainActor final class EntryArchiveHandler: ActionHandler {
    let type = "entry.archive"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("entry.archive: id fehlt")
        }
        guard let entry = try data.archiveEntry(id: id) else {
            return .error("Entry \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "status": .string(entry.status.rawValue),
        ]))
    }
}

@MainActor final class EntryRestoreHandler: ActionHandler {
    let type = "entry.restore"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("entry.restore: id fehlt")
        }
        guard let entry = try data.restoreEntry(id: id) else {
            return .error("Entry \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "status": .string(entry.status.rawValue),
        ]))
    }
}

@MainActor final class EntryListHandler: ActionHandler {
    let type = "entry.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 50
        let entries = try data.listEntries(limit: limit)
        let results = entries.map { entry -> ExpressionValue in
            .object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
                "type": .string(entry.type.rawValue),
                "status": .string(entry.status.rawValue),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class EntryFetchHandler: ActionHandler {
    let type = "entry.fetch"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("entry.fetch: id fehlt")
        }
        guard let entry = try data.fetchEntry(id: id) else {
            return .error("Entry \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "title": .string(entry.title ?? ""),
            "type": .string(entry.type.rawValue),
            "body": .string(entry.body ?? ""),
            "status": .string(entry.status.rawValue),
        ]))
    }
}

@MainActor final class EntryReadHandler: ActionHandler {
    let type = "entry.read"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .actionError(code: "entry.missing_id", message: "ID fehlt für entry.read")
        }
        guard let entry = try data.fetchEntry(id: id) else {
            return .actionError(code: "entry.not_found", message: "Entry \(id) nicht gefunden")
        }
        return .value(.object([
            "id": .int(Int(entry.id ?? 0)),
            "type": .string(entry.type.rawValue),
            "title": .string(entry.title ?? ""),
            "body": .string(entry.body ?? ""),
            "status": .string(entry.status.rawValue),
            "priority": .int(entry.priority),
            "createdAt": .string(entry.createdAt ?? ""),
        ]))
    }
}

@MainActor final class EntryToggleHandler: ActionHandler {
    let type = "entry.toggle"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .actionError(code: "entry.missing_id", message: "ID fehlt für entry.toggle")
        }
        guard let entry = try data.fetchEntry(id: id) else {
            return .actionError(code: "entry.not_found", message: "Entry \(id) nicht gefunden")
        }
        // Toggle: done → active (restore), active → done (markDone)
        let toggled: Entry?
        if entry.status == .done {
            toggled = try data.restoreEntry(id: id)
        } else {
            toggled = try data.markDone(id: id)
        }
        return .value(.object([
            "id": .int(Int(id)),
            "status": .string(toggled?.status.rawValue ?? "active"),
        ]))
    }
}
