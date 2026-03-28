import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import GRDB

// Who created or imported this skill.
public enum SkillCreator: String, Codable, Sendable, DatabaseValueConvertible {
    case user
    case system
    case brainAI = "brain-ai"
    case `import` = "import"
}

// A compiled, installed skill in the runtime engine.
// Skills are the "proteins" — JSON definitions that the engine renders
// into native SwiftUI views and executable workflows.
//
// The skill lifecycle:
//   .brainskill.md → LLM (compile) → Skill (JSON) → SQLite → Runtime Engine
//
// JSON columns (permissions, triggers, screens, actions) are stored as text.
// The Render Engine and Action Engine parse them at runtime.
public struct Skill: Codable, Sendable, Identifiable, Hashable {
    public static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public var id: String               // e.g. "pomodoro-timer"
    public var name: String
    public var description: String?
    public var version: String
    public var icon: String?            // SF Symbol name
    public var color: String?           // Hex color e.g. "#FF6347"
    public var capability: String?      // app, brain, hybrid — how the skill executes
    public var group: String?            // Skill group (Favoriten, Produktivitaet, etc.)
    public var permissions: String?     // JSON array: ["notifications", "haptics"]
    public var triggers: String?        // JSON array: [{type, phrase, ...}]
    public var screens: String          // JSON: full UI primitive tree
    public var actions: String?         // JSON: workflow definitions
    public var sourceMarkdown: String?  // Original .brainskill.md
    public var createdBy: SkillCreator
    public var enabled: Bool
    public var integrityHash: String?  // SHA-256 hash over skill JSON for tamper detection (F-43)
    public var installedAt: String?
    public var updatedAt: String?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        version: String = "1.0",
        icon: String? = nil,
        color: String? = nil,
        capability: String? = nil,
        group: String? = nil,
        permissions: String? = nil,
        triggers: String? = nil,
        screens: String = "{}",
        actions: String? = nil,
        sourceMarkdown: String? = nil,
        createdBy: SkillCreator = .user,
        enabled: Bool = true,
        integrityHash: String? = nil,
        installedAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.icon = icon
        self.color = color
        self.capability = capability
        self.group = group
        self.permissions = permissions
        self.triggers = triggers
        self.screens = screens
        self.actions = actions
        self.sourceMarkdown = sourceMarkdown
        self.createdBy = createdBy
        self.enabled = enabled
        self.integrityHash = integrityHash
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB conformances

extension Skill: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "skills" }

    // Skills use a text primary key (no auto-increment).
    // No didInsert needed.
}

// MARK: - Skill permissions enum (F-25)

/// Fixed set of allowed skill permissions. Unknown values are silently dropped (fail closed).
public enum SkillPermission: String, Codable, Sendable, CaseIterable {
    case notifications
    case haptics
    case location
    case contacts
    case calendar
    case email
    case camera
    case microphone
    case speech
    case nfc
    case entries
    case knowledgeFacts = "knowledge_facts"
    case shortcuts
}

// MARK: - Integrity hash (F-43)

extension Skill {

    /// Compute a SHA-256 hash over the skill's JSON-serialisable definition fields.
    /// The hash covers: id, name, version, screens, actions, permissions, triggers.
    public func computeIntegrityHash() -> String {
        // Build a deterministic canonical payload from the fields that define behaviour.
        var payload = ""
        payload += id
        payload += "|"
        payload += name
        payload += "|"
        payload += version
        payload += "|"
        payload += screens
        payload += "|"
        payload += (actions ?? "")
        payload += "|"
        payload += (permissions ?? "")
        payload += "|"
        payload += (triggers ?? "")

        let data = Data(payload.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns a copy of this skill with the integrityHash populated.
    public func withComputedHash() -> Skill {
        var copy = self
        copy.integrityHash = computeIntegrityHash()
        return copy
    }

    /// Verify that the stored integrity hash matches the current definition.
    /// Returns true if no hash is stored (backwards compatibility) or if it matches.
    public func verifyIntegrity() -> Bool {
        guard let stored = integrityHash else { return true }
        return stored == computeIntegrityHash()
    }
}

// MARK: - Conversion to SkillDefinition (for rendering)

extension Skill {

    /// Try to parse the screens JSON into a SkillDefinition that SkillView can render.
    /// Returns nil if screens is empty or unparseable.
    public func toSkillDefinition() -> SkillDefinition? {
        guard !screens.isEmpty, screens != "{}" else { return nil }
        guard let data = screens.data(using: .utf8),
              let screensDict = try? JSONDecoder().decode([String: ScreenNode].self, from: data)
        else { return nil }
        guard !screensDict.isEmpty else { return nil }

        // Parse actions JSON if present
        var actionsDict: [String: ActionDefinition]?
        if let actionsJSON = actions,
           let actionsData = actionsJSON.data(using: .utf8) {
            actionsDict = try? JSONDecoder().decode([String: ActionDefinition].self, from: actionsData)
        }

        return SkillDefinition(id: id, version: version, screens: screensDict, actions: actionsDict)
    }

    /// Whether this skill has renderable UI screens.
    public var hasScreens: Bool {
        !screens.isEmpty && screens != "{}"
    }
}

// MARK: - JSON helpers

extension Skill {

    // Decode the permissions JSON array into typed SkillPermission values.
    // Unknown permission strings are silently dropped (fail closed).
    public func decodedPermissions() -> [SkillPermission] {
        guard let json = permissions,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array.compactMap { SkillPermission(rawValue: $0) }
    }

    // Encode a Swift string array into the permissions JSON field.
    // Unknown permission strings are silently dropped before encoding.
    public static func encodePermissions(_ values: [String]) -> String? {
        let valid = values.compactMap { SkillPermission(rawValue: $0) }.map { $0.rawValue }
        guard let data = try? JSONEncoder().encode(valid) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Decode triggers into a generic array of dictionaries.
    public func decodedTriggers() -> [[String: String]] {
        guard let json = triggers,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return [] }
        return array
    }
}
