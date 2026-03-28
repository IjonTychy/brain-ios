import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Skill handlers

@MainActor final class SkillListHandler: ActionHandler {
    let type = "skill.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let skills = try data.listSkills()
        let results = skills.map { skill -> ExpressionValue in
            .object([
                "id": .string(skill.id),
                "name": .string(skill.name),
                "version": .string(skill.version),
                "enabled": .bool(skill.enabled),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class SkillCreateHandler: ActionHandler {
    let type = "skill.create"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let markdown = properties["markdown"]?.stringValue else {
            return .error("skill.create: markdown erforderlich")
        }

        // Enforce screens_json as required — without it the skill has no UI
        guard let screensJSON = properties["screens_json"]?.stringValue, !screensJSON.isEmpty else {
            return .error("skill.create: screens_json ist PFLICHT. Ohne screens_json hat der Skill keine UI. Bitte erstelle einen JSON-String mit mindestens einem 'main' Screen: {\"main\":{\"type\":\"stack\",\"properties\":{\"direction\":\"vertical\",\"spacing\":16},\"children\":[...]}}")
        }

        // Pre-validate screens_json BEFORE installation
        guard let screensData = screensJSON.data(using: .utf8),
              let screensDict = try? JSONDecoder().decode([String: ScreenNode].self, from: screensData),
              !screensDict.isEmpty else {
            return .error("skill.create: screens_json ist kein gueltiges ScreenNode-JSON. Erwartetes Format: {\"main\":{\"type\":\"stack\",\"properties\":{\"direction\":\"vertical\"},\"children\":[{\"type\":\"text\",\"properties\":{\"value\":\"Titel\",\"style\":\"largeTitle\"}}]}}")
        }
        guard screensDict["main"] != nil else {
            return .error("skill.create: screens_json muss einen 'main' Screen enthalten. Der Key 'main' fehlt im JSON.")
        }

        // Validate actions_json if provided
        let actionsJSON = properties["actions_json"]?.stringValue
        if let actionsStr = actionsJSON, !actionsStr.isEmpty {
            guard let actionsData = actionsStr.data(using: .utf8),
                  let _ = try? JSONDecoder().decode([String: ActionDefinition].self, from: actionsData) else {
                return .error("skill.create: actions_json ist kein gueltiges JSON. Erwartetes Format: {\"actionName\":{\"steps\":[{\"type\":\"entry.create\",\"properties\":{\"title\":\"...\",\"type\":\"thought\"}}]}}")
            }
        }

        // Parse and validate the LLM-generated .brainskill.md
        let lifecycle = SkillLifecycle(pool: data.databasePool)
        let source: BrainSkillSource
        do {
            source = try lifecycle.preview(markdown: markdown)
        } catch {
            return .error("Skill-Markdown ungueltig: \(error)")
        }

        // If skill with this ID already exists, uninstall it first (allows updates)
        if (try lifecycle.fetch(id: source.id)) != nil {
            try lifecycle.uninstall(id: source.id)
        }

        // Install with pre-validated screens + actions JSON
        let skill = try lifecycle.installFromSource(source: source, createdBy: .brainAI, screensJSON: screensJSON, actionsJSON: actionsJSON)
        NotificationCenter.default.post(name: .brainSkillsChanged, object: nil)

        // Advisory: warn if buttons reference many undefined actions
        if let definition = skill.toSkillDefinition(),
           let actions = definition.actions {
            let missing = definition.referencedActions().subtracting(Set(actions.keys))
            if missing.count > 3 {
                return .value(.object([
                    "id": .string(skill.id),
                    "name": .string(skill.name),
                    "status": .string("installiert_mit_warnungen"),
                    "warning": .string("Fehlende Actions: \(missing.sorted().joined(separator: ", "))"),
                ]))
            }
        }

        return .value(.object([
            "id": .string(skill.id),
            "name": .string(skill.name),
            "description": .string(skill.description ?? ""),
            "version": .string(skill.version),
            "capability": .string(skill.capability ?? "hybrid"),
            "status": .string("installiert"),
        ]))
    }

}

@MainActor final class SkillInstallHandler: ActionHandler {
    let type = "skill.install"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.stringValue,
              let name = properties["name"]?.stringValue else {
            return .error("skill.install: id und name erforderlich")
        }
        let version = properties["version"]?.stringValue ?? "1.0"
        let description = properties["description"]?.stringValue

        let screens = properties["screens"]?.stringValue ?? "{}"
        let skill = Skill(
            id: id, name: name, description: description,
            version: version, screens: screens, createdBy: .user
        )
        _ = try data.installSkill(skill)
        return .value(.object([
            "id": .string(id),
            "name": .string(name),
        ]))
    }
}

// MARK: - Self-Modifier handlers

@MainActor final class RulesEvaluateHandler: ActionHandler {
    let type = "rules.evaluate"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let trigger = properties["trigger"]?.stringValue ?? "manual"
        let entryType = properties["entryType"]?.stringValue

        let matches = try data.evaluateRules(trigger: trigger, entryType: entryType)
        let results = matches.map { match -> ExpressionValue in
            .object([
                "ruleId": .int(Int(match.rule.id ?? 0)),
                "ruleName": .string(match.rule.name),
                "action": .string(match.actionJSON),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class ProposalListHandler: ActionHandler {
    let type = "improve.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let statusFilter = properties["status"]?.stringValue.flatMap { ProposalStatus(rawValue: $0) }
        let proposals = try data.listProposals(status: statusFilter)
        let results = proposals.map { p -> ExpressionValue in
            .object([
                "id": .int(Int(p.id ?? 0)),
                "title": .string(p.title),
                "category": .string(p.category),
                "status": .string(p.status.rawValue),
                "description": .string(p.description ?? ""),
            ])
        }
        return .value(.array(results))
    }
}

@MainActor final class ProposalApplyHandler: ActionHandler {
    let type = "improve.apply"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("improve.apply: id fehlt")
        }
        guard let proposal = try data.applyProposal(id: id) else {
            return .error("Proposal \(id) nicht gefunden")
        }

        if let spec = proposal.changeSpec,
           spec.contains("skill_suggestion"),
           let specData = spec.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: specData) as? [String: Any],
           let prompt = json["suggestedSkillPrompt"] as? String,
           !prompt.isEmpty {
            NotificationCenter.default.post(
                name: .brainNavigateTab,
                object: nil,
                userInfo: ["tab": "chat", "message": prompt]
            )
            return .value(.object([
                "id": .int(Int(proposal.id ?? 0)),
                "title": .string(proposal.title),
                "status": .string(proposal.status.rawValue),
                "action": .string("chat_generation_started"),
                "prompt": .string(prompt),
            ]))
        }

        return .value(.object([
            "id": .int(Int(proposal.id ?? 0)),
            "title": .string(proposal.title),
            "status": .string(proposal.status.rawValue),
        ]))
    }
}

@MainActor final class ProposalRejectHandler: ActionHandler {
    let type = "proposal.reject"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue else {
            return .actionError(code: "proposal.missing_id", message: "Proposal-ID fehlt")
        }
        _ = try data.rejectProposal(id: Int64(id))
        return .value(.object([
            "status": .string("rejected"),
            "id": .int(id),
        ]))
    }
}
