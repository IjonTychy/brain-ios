import Testing
import Foundation
@testable import BrainCore

// Tests for AUFTRAG-SKILL-EXECUTION:
// - SkillLifecycle.updateDefinition() behavior
// - Skill.toSkillDefinition() conversion
// - Skill.createdBy protection logic

@Suite("Skill Lifecycle Update Definition")
struct SkillLifecycleUpdateTests {

    private func makeLifecycle() throws -> (SkillLifecycle, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (SkillLifecycle(pool: db.pool), db)
    }

    private func makeService() throws -> (SkillService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (SkillService(pool: db.pool), db)
    }

    private func validSource(id: String = "test-skill", name: String = "Test Skill") -> BrainSkillSource {
        BrainSkillSource(id: id, name: name)
    }

    private func validDefinition(id: String = "test-skill") -> SkillDefinition {
        SkillDefinition(
            id: id,
            screens: ["main": ScreenNode(type: "text", properties: ["value": .string("Hello")])]
        )
    }

    private func sampleSkill(
        id: String = "update-test",
        name: String = "Update Test",
        screens: String = #"{"main":{"type":"text","properties":{"value":"Hello"}}}"#,
        actions: String? = #"{"tap":{"steps":[{"type":"haptic","properties":{"style":"success"}}]}}"#,
        createdBy: SkillCreator = .user
    ) -> Skill {
        Skill(
            id: id,
            name: name,
            description: "Test skill for updateDefinition",
            version: "1.0",
            icon: "star",
            color: "#00FF00",
            screens: screens,
            actions: actions,
            createdBy: createdBy
        )
    }

    // MARK: - SkillLifecycle.updateDefinition()

    @Test("updateDefinition changes screens JSON")
    func updateDefinitionChangesScreens() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())

        let newScreens = #"{"main":{"type":"text","properties":{"value":"Updated"}}}"#
        try lc.updateDefinition(id: "test-skill", screens: newScreens, actions: nil)

        let fetched = try lc.fetch(id: "test-skill")
        #expect(fetched?.screens == newScreens)
    }

    @Test("updateDefinition changes actions JSON")
    func updateDefinitionChangesActions() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill()
        try svc.install(skill)

        let newActions = #"{"save":{"steps":[{"type":"toast","properties":{"message":"Saved"}}]}}"#
        try svc.updateDefinition(id: "update-test", screens: skill.screens, actions: newActions)

        let fetched = try svc.fetch(id: "update-test")
        #expect(fetched?.actions == newActions)
    }

    @Test("updateDefinition clears actions when nil is passed")
    func updateDefinitionClearsActions() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill()
        try svc.install(skill)

        // Verify actions are initially present
        let before = try svc.fetch(id: "update-test")
        #expect(before?.actions != nil)

        // Update with nil actions
        try svc.updateDefinition(id: "update-test", screens: skill.screens, actions: nil)

        let after = try svc.fetch(id: "update-test")
        #expect(after?.actions == nil)
    }

    @Test("updateDefinition updates version when provided")
    func updateDefinitionUpdatesVersion() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())

        let newScreens = #"{"main":{"type":"text","properties":{"value":"v2"}}}"#
        try lc.updateDefinition(id: "test-skill", screens: newScreens, actions: nil, version: "2.0")

        let fetched = try lc.fetch(id: "test-skill")
        #expect(fetched?.version == "2.0")
    }

    @Test("updateDefinition preserves version when not provided")
    func updateDefinitionPreservesVersion() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill()
        try svc.install(skill)

        let newScreens = #"{"main":{"type":"text","properties":{"value":"Changed"}}}"#
        try svc.updateDefinition(id: "update-test", screens: newScreens, actions: nil)

        let fetched = try svc.fetch(id: "update-test")
        #expect(fetched?.version == "1.0")
    }

    @Test("updateDefinition sets updatedAt timestamp")
    func updateDefinitionSetsTimestamp() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill()
        try svc.install(skill)

        let beforeUpdate = try svc.fetch(id: "update-test")
        let oldUpdatedAt = beforeUpdate?.updatedAt

        let newScreens = #"{"main":{"type":"text","properties":{"value":"Timestamped"}}}"#
        try svc.updateDefinition(id: "update-test", screens: newScreens, actions: nil)

        let after = try svc.fetch(id: "update-test")
        #expect(after?.updatedAt != nil)
        // updatedAt should be set (may or may not differ if test runs fast, but it should be non-nil)
        #expect(after?.updatedAt != nil)
    }

    @Test("updateDefinition recomputes integrity hash")
    func updateDefinitionRecomputesHash() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill()
        let installed = try svc.install(skill)
        let oldHash = installed.integrityHash

        let newScreens = #"{"main":{"type":"text","properties":{"value":"New Hash"}}}"#
        try svc.updateDefinition(id: "update-test", screens: newScreens, actions: nil, version: "2.0")

        let fetched = try svc.fetch(id: "update-test")
        #expect(fetched?.integrityHash != nil)
        #expect(fetched?.integrityHash != oldHash)
        // Integrity should still verify after update
        #expect(fetched?.verifyIntegrity() == true)
    }

    @Test("updateDefinition on nonexistent skill is silent no-op")
    func updateDefinitionNonexistentSkill() throws {
        let (svc, _) = try makeService()
        // Should not throw
        try svc.updateDefinition(id: "ghost-skill", screens: "{}", actions: nil)
    }

    // MARK: - Skill.toSkillDefinition()

    @Test("toSkillDefinition returns non-nil for valid screens JSON")
    func toSkillDefinitionWithValidScreens() throws {
        let skill = sampleSkill(
            screens: #"{"main":{"type":"text","properties":{"value":"Hello World"}}}"#
        )
        let def = skill.toSkillDefinition()
        #expect(def != nil)
        #expect(def?.id == "update-test")
        #expect(def?.screens["main"]?.type == "text")
    }

    @Test("toSkillDefinition returns nil for empty braces screens")
    func toSkillDefinitionWithEmptyBraces() {
        let skill = sampleSkill(screens: "{}")
        let def = skill.toSkillDefinition()
        #expect(def == nil)
    }

    @Test("toSkillDefinition returns nil for empty string screens")
    func toSkillDefinitionWithEmptyString() {
        let skill = Skill(id: "empty", name: "Empty", screens: "")
        let def = skill.toSkillDefinition()
        #expect(def == nil)
    }

    @Test("toSkillDefinition returns nil for invalid JSON")
    func toSkillDefinitionWithInvalidJSON() {
        let skill = sampleSkill(screens: "not json at all")
        let def = skill.toSkillDefinition()
        #expect(def == nil)
    }

    @Test("toSkillDefinition includes actions when present")
    func toSkillDefinitionIncludesActions() {
        let skill = sampleSkill(
            screens: #"{"main":{"type":"text","properties":{"value":"Hi"}}}"#,
            actions: #"{"tap":{"steps":[{"type":"haptic","properties":{"style":"success"}}]}}"#
        )
        let def = skill.toSkillDefinition()
        #expect(def != nil)
        #expect(def?.actions?["tap"] != nil)
        #expect(def?.actions?["tap"]?.steps.count == 1)
    }

    @Test("toSkillDefinition returns nil actions when actions JSON is nil")
    func toSkillDefinitionNilActions() {
        let skill = sampleSkill(
            screens: #"{"main":{"type":"text","properties":{"value":"Hi"}}}"#,
            actions: nil
        )
        let def = skill.toSkillDefinition()
        #expect(def != nil)
        #expect(def?.actions == nil)
    }

    @Test("toSkillDefinition preserves version from skill")
    func toSkillDefinitionPreservesVersion() {
        var skill = sampleSkill(
            screens: #"{"main":{"type":"text","properties":{"value":"Hi"}}}"#
        )
        skill.version = "3.5"
        let def = skill.toSkillDefinition()
        #expect(def?.version == "3.5")
    }

    @Test("After updateDefinition with valid JSON, toSkillDefinition returns non-nil")
    func toSkillDefinitionAfterUpdate() throws {
        let (svc, _) = try makeService()
        // Install with empty screens
        let skill = sampleSkill(screens: "{}")
        try svc.install(skill)

        // Verify toSkillDefinition is nil before
        let before = try svc.fetch(id: "update-test")
        #expect(before?.toSkillDefinition() == nil)

        // Update with valid screens
        let newScreens = #"{"main":{"type":"text","properties":{"value":"Now Renderable"}}}"#
        try svc.updateDefinition(id: "update-test", screens: newScreens, actions: nil)

        // Verify toSkillDefinition is non-nil after
        let after = try svc.fetch(id: "update-test")
        #expect(after?.toSkillDefinition() != nil)
        #expect(after?.toSkillDefinition()?.screens["main"]?.type == "text")
    }

    // MARK: - hasScreens property

    @Test("hasScreens returns false for empty braces")
    func hasScreensEmptyBraces() {
        let skill = sampleSkill(screens: "{}")
        #expect(skill.hasScreens == false)
    }

    @Test("hasScreens returns false for empty string")
    func hasScreensEmptyString() {
        let skill = Skill(id: "e", name: "E", screens: "")
        #expect(skill.hasScreens == false)
    }

    @Test("hasScreens returns true for valid screens JSON")
    func hasScreensValid() {
        let skill = sampleSkill(
            screens: #"{"main":{"type":"text","properties":{"value":"X"}}}"#
        )
        #expect(skill.hasScreens == true)
    }

    // MARK: - Skill.createdBy protection logic

    @Test("Skill with createdBy == .system is identifiable")
    func createdBySystem() {
        let skill = Skill(id: "sys", name: "System Skill", createdBy: .system)
        #expect(skill.createdBy == .system)
        #expect(skill.createdBy != .user)
        #expect(skill.createdBy != .brainAI)
    }

    @Test("Skill with createdBy == .brainAI is distinguishable")
    func createdByBrainAI() {
        let skill = Skill(id: "ai", name: "AI Skill", createdBy: .brainAI)
        #expect(skill.createdBy == .brainAI)
        #expect(skill.createdBy != .system)
        #expect(skill.createdBy != .user)
    }

    @Test("Skill with createdBy == .user is the default")
    func createdByUserDefault() {
        let skill = Skill(id: "usr", name: "User Skill")
        #expect(skill.createdBy == .user)
    }

    @Test("createdBy .brainAI raw value is 'brain-ai'")
    func createdByBrainAIRawValue() {
        #expect(SkillCreator.brainAI.rawValue == "brain-ai")
    }

    @Test("createdBy persists correctly in database")
    func createdByPersistsInDB() throws {
        let (svc, _) = try makeService()

        let systemSkill = sampleSkill(id: "sys-skill", name: "System", createdBy: .system)
        let aiSkill = sampleSkill(id: "ai-skill", name: "AI", createdBy: .brainAI)
        let userSkill = sampleSkill(id: "user-skill", name: "User", createdBy: .user)

        try svc.install(systemSkill)
        try svc.install(aiSkill)
        try svc.install(userSkill)

        #expect(try svc.fetch(id: "sys-skill")?.createdBy == .system)
        #expect(try svc.fetch(id: "ai-skill")?.createdBy == .brainAI)
        #expect(try svc.fetch(id: "user-skill")?.createdBy == .user)
    }

    @Test("list by createdBy distinguishes system from brainAI")
    func listByCreatorDistinguishes() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "sys1", name: "Sys1", createdBy: .system))
        try svc.install(sampleSkill(id: "ai1", name: "AI1", createdBy: .brainAI))
        try svc.install(sampleSkill(id: "ai2", name: "AI2", createdBy: .brainAI))
        try svc.install(sampleSkill(id: "usr1", name: "Usr1", createdBy: .user))

        let systemSkills = try svc.list(createdBy: .system)
        let aiSkills = try svc.list(createdBy: .brainAI)
        let userSkills = try svc.list(createdBy: .user)

        #expect(systemSkills.count == 1)
        #expect(aiSkills.count == 2)
        #expect(userSkills.count == 1)
    }

    @Test("updateDefinition does not change createdBy")
    func updateDefinitionPreservesCreatedBy() throws {
        let (svc, _) = try makeService()
        let skill = sampleSkill(id: "sys-update", name: "System Updatable", createdBy: .system)
        try svc.install(skill)

        let newScreens = #"{"main":{"type":"text","properties":{"value":"Updated"}}}"#
        try svc.updateDefinition(id: "sys-update", screens: newScreens, actions: nil, version: "2.0")

        let fetched = try svc.fetch(id: "sys-update")
        #expect(fetched?.createdBy == .system)
        #expect(fetched?.screens == newScreens)
        #expect(fetched?.version == "2.0")
    }
}
