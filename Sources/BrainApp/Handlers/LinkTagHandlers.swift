import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Link actions

@MainActor final class LinkCreateHandler: ActionHandler {
    let type = "link.create"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let sourceId = properties["sourceId"]?.intValue.flatMap({ Int64($0) }),
              let targetId = properties["targetId"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("link.create: sourceId und targetId erforderlich")
        }
        let relation = properties["relation"]?.stringValue ?? "related"
        let link = try data.createLink(sourceId: sourceId, targetId: targetId, relation: relation)
        return .value(.object([
            "id": .int(Int(link.id ?? 0)),
            "sourceId": .int(Int(link.sourceId)),
            "targetId": .int(Int(link.targetId)),
        ]))
    }
}

@MainActor final class LinkDeleteHandler: ActionHandler {
    let type = "link.delete"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let sourceId = properties["sourceId"]?.intValue.flatMap({ Int64($0) }),
              let targetId = properties["targetId"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("link.delete: sourceId und targetId erforderlich")
        }
        try data.deleteLink(sourceId: sourceId, targetId: targetId)
        return .success
    }
}

@MainActor final class LinkedEntriesHandler: ActionHandler {
    let type = "link.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("link.list: entryId fehlt")
        }
        let entries = try data.linkedEntries(for: entryId)
        let results = entries.map { entry -> ExpressionValue in
            .object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
                "type": .string(entry.type.rawValue),
            ])
        }
        return .value(.array(results))
    }
}

// MARK: - Tag actions

@MainActor final class TagAddHandler: ActionHandler {
    let type = "tag.add"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }),
              let tagName = properties["tag"]?.stringValue else {
            return .error("tag.add: entryId und tag erforderlich")
        }
        try data.addTag(entryId: entryId, tagName: tagName)
        return .success
    }
}

@MainActor final class TagRemoveHandler: ActionHandler {
    let type = "tag.remove"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }),
              let tagName = properties["tag"]?.stringValue else {
            return .error("tag.remove: entryId und tag erforderlich")
        }
        try data.removeTag(entryId: entryId, tagName: tagName)
        return .success
    }
}

@MainActor final class TagListHandler: ActionHandler {
    let type = "tag.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let tags = try data.listTags()
        let results = tags.map { tag -> ExpressionValue in
            .object([
                "id": .int(Int(tag.id ?? 0)),
                "name": .string(tag.name),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class TagCountsHandler: ActionHandler {
    let type = "tag.counts"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let counts = try data.tagCounts()
        let results = counts.map { item -> ExpressionValue in
            .object([
                "id": .int(Int(item.tag.id ?? 0)),
                "name": .string(item.tag.name),
                "count": .int(item.count),
            ])
        }
        return .value(.array(results))
    }
}

// MARK: - Search autocomplete

@MainActor final class SearchAutocompleteHandler: ActionHandler {
    let type = "search.autocomplete"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let prefix = properties["prefix"]?.stringValue else {
            return .error("search.autocomplete: prefix fehlt")
        }
        let limit = properties["limit"]?.intValue ?? 10
        let entries = try data.autocomplete(prefix: prefix, limit: limit)
        let results = entries.map { entry -> ExpressionValue in
            .object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
            ])
        }
        return .value(.array(results))
    }
}

// MARK: - Knowledge actions

@MainActor final class KnowledgeSaveHandler: ActionHandler {
    let type = "knowledge.save"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let subject = properties["subject"]?.stringValue,
              let predicate = properties["predicate"]?.stringValue,
              let object = properties["object"]?.stringValue else {
            return .error("knowledge.save: subject, predicate, object erforderlich")
        }
        let confidence = properties["confidence"]?.doubleValue ?? 1.0
        let sourceEntryId = properties["sourceEntryId"]?.intValue.flatMap({ Int64($0) })

        let fact = try data.saveKnowledgeFact(
            subject: subject, predicate: predicate, object: object,
            confidence: confidence, sourceEntryId: sourceEntryId
        )
        return .value(.object([
            "id": .int(Int(fact.id ?? 0)),
            "subject": .string(subject),
        ]))
    }
}
