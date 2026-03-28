import Foundation
import GRDB
#if canImport(os)
import os.log
#endif

// CRUD and lifecycle operations for skills.
//
// TODO (Sprint 6.3 – F-44): Evaluate Apple App Attest for server-side skill
// distribution. App Attest (DeviceCheck framework) lets a backend verify that
// API requests originate from a genuine, unmodified app instance. This would
// protect the skill-install endpoint against replay and sideloading attacks.
// Evaluate: attestation key lifecycle, server-side verification cost, and
// graceful degradation for Simulator / TestFlight builds.
public struct SkillService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Install a new skill (insert or replace if same id exists).
    // Validates JSON fields before saving (F-24).
    @discardableResult
    public func install(_ skill: Skill) throws -> Skill {
        // Validate screens JSON (required field)
        try validateJSON(skill.screens, fieldName: "screens")

        // Validate actions JSON if present
        if let actions = skill.actions {
            try validateJSON(actions, fieldName: "actions")
        }

        // Validate triggers JSON if present
        if let triggers = skill.triggers {
            try validateJSON(triggers, fieldName: "triggers")
        }

        return try pool.write { db in
            var record = skill
            // Compute integrity hash over the skill definition (F-43)
            record.integrityHash = record.computeIntegrityHash()
            if record.installedAt == nil {
                record.installedAt = Self.iso8601Now()
            }
            if record.updatedAt == nil {
                record.updatedAt = Self.iso8601Now()
            }
            try record.save(db)
            return record
        }
    }

    /// Validate that a string is valid JSON.
    private func validateJSON(_ jsonString: String, fieldName: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw SkillInstallError.invalidJSON(field: fieldName, reason: "Not valid UTF-8")
        }
        guard JSONSerialization.isValidJSONObject(
            try JSONSerialization.jsonObject(with: data)
        ) else {
            throw SkillInstallError.invalidJSON(field: fieldName, reason: "Not a valid JSON object or array")
        }
    }

    // Fetch a skill by id. Verifies integrity hash if present (F-43).
    public func fetch(id: String) throws -> Skill? {
        let skill = try pool.read { db in
            try Skill.fetchOne(db, key: id)
        }
        if let skill, !skill.verifyIntegrity() {
            #if canImport(os)
            let logger = Logger(subsystem: "com.example.brain-ios", category: "SkillService")
            logger.warning("Skill integrity check failed for '\(id)' — possible tampering")
            #endif
            throw SkillInstallError.integrityCheckFailed(skillId: id)
        }
        return skill
    }

    // List all installed skills, optionally filtered by enabled state.
    public func list(enabledOnly: Bool = false) throws -> [Skill] {
        try pool.read { db in
            var request = Skill.order(Column("name"))
            if enabledOnly {
                request = request.filter(Column("enabled") == true)
            }
            return try request.fetchAll(db)
        }
    }

    // List skills created by a specific creator.
    public func list(createdBy: SkillCreator) throws -> [Skill] {
        try pool.read { db in
            try Skill
                .filter(Column("createdBy") == createdBy)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    // Enable or disable a skill.
    public func setEnabled(id: String, enabled: Bool) throws {
        try pool.write { db in
            if var skill = try Skill.fetchOne(db, key: id) {
                skill.enabled = enabled
                skill.updatedAt = Self.iso8601Now()
                try skill.update(db)
            }
        }
    }

    // Update a skill's JSON definition (screens, actions).
    public func updateDefinition(
        id: String,
        screens: String,
        actions: String?,
        version: String? = nil
    ) throws {
        try pool.write { db in
            if var skill = try Skill.fetchOne(db, key: id) {
                skill.screens = screens
                skill.actions = actions
                if let version { skill.version = version }
                skill.updatedAt = Self.iso8601Now()
                // Recompute integrity hash after definition change (F-43)
                skill.integrityHash = skill.computeIntegrityHash()
                try skill.update(db)
            }
        }
    }

    // Uninstall (delete) a skill permanently.
    public func uninstall(id: String) throws {
        try pool.write { db in
            _ = try Skill.deleteOne(db, key: id)
        }
    }

    // Count installed skills.
    public func count(enabledOnly: Bool = false) throws -> Int {
        try pool.read { db in
            var request = Skill.all()
            if enabledOnly {
                request = request.filter(Column("enabled") == true)
            }
            return try request.fetchCount(db)
        }
    }

    // MARK: - Helpers

    private static func iso8601Now() -> String {
        BrainDateFormatting.iso8601Now()
    }
}

// MARK: - Errors

public enum SkillInstallError: Error, Sendable {
    case invalidJSON(field: String, reason: String)
    case integrityCheckFailed(skillId: String)  // F-43: SHA-256 hash mismatch on load
}
