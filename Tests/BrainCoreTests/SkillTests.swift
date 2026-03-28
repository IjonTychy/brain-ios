import Testing
import GRDB
@testable import BrainCore

@Suite("Skill CRUD & Lifecycle")
struct SkillTests {

    private func makeService() throws -> (SkillService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (SkillService(pool: db.pool), db)
    }

    private func sampleSkill(
        id: String = "pomodoro-timer",
        name: String = "Pomodoro Timer",
        screens: String = #"{"main":{"type":"stack","children":[]}}"#
    ) -> Skill {
        Skill(
            id: id,
            name: name,
            description: "Focus timer with 25/5 cycles",
            version: "1.0",
            icon: "timer",
            color: "#FF6347",
            permissions: #"["notifications","haptics"]"#,
            triggers: #"[{"type":"siri","phrase":"Starte Pomodoro"}]"#,
            screens: screens,
            actions: #"{"toggle":{"steps":[]}}"#,
            sourceMarkdown: "# Pomodoro Timer\n\nA simple focus timer.",
            createdBy: .user
        )
    }

    @Test("Install and fetch skill")
    func installAndFetch() throws {
        let (svc, _) = try makeService()

        let skill = sampleSkill()
        let installed = try svc.install(skill)
        #expect(installed.id == "pomodoro-timer")
        #expect(installed.name == "Pomodoro Timer")

        let fetched = try svc.fetch(id: "pomodoro-timer")
        #expect(fetched != nil)
        #expect(fetched?.name == "Pomodoro Timer")
        #expect(fetched?.icon == "timer")
        #expect(fetched?.color == "#FF6347")
        #expect(fetched?.createdBy == .user)
    }

    @Test("Skill uses text primary key (not auto-increment)")
    func textPrimaryKey() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "my-skill", name: "My Skill"))
        let fetched = try svc.fetch(id: "my-skill")
        #expect(fetched?.id == "my-skill")
    }

    @Test("List skills")
    func list() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "skill-a", name: "Alpha"))
        try svc.install(sampleSkill(id: "skill-b", name: "Beta"))
        try svc.install(sampleSkill(id: "skill-c", name: "Charlie"))

        let all = try svc.list()
        #expect(all.count == 3)
        // Ordered by name
        #expect(all[0].name == "Alpha")
        #expect(all[1].name == "Beta")
        #expect(all[2].name == "Charlie")
    }

    @Test("List enabled-only skills")
    func listEnabledOnly() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "skill-on", name: "Enabled"))
        var disabled = sampleSkill(id: "skill-off", name: "Disabled")
        disabled.enabled = false
        try svc.install(disabled)

        let enabledOnly = try svc.list(enabledOnly: true)
        #expect(enabledOnly.count == 1)
        #expect(enabledOnly.first?.id == "skill-on")
    }

    @Test("List skills by creator")
    func listByCreator() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "user-skill", name: "User Skill"))
        var aiSkill = sampleSkill(id: "ai-skill", name: "AI Skill")
        aiSkill.createdBy = .brainAI
        try svc.install(aiSkill)

        let userSkills = try svc.list(createdBy: .user)
        #expect(userSkills.count == 1)
        #expect(userSkills.first?.id == "user-skill")

        let aiSkills = try svc.list(createdBy: .brainAI)
        #expect(aiSkills.count == 1)
        #expect(aiSkills.first?.id == "ai-skill")
    }

    @Test("Enable and disable skill")
    func setEnabled() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill())
        try svc.setEnabled(id: "pomodoro-timer", enabled: false)

        let fetched = try svc.fetch(id: "pomodoro-timer")
        #expect(fetched?.enabled == false)

        try svc.setEnabled(id: "pomodoro-timer", enabled: true)
        let refetched = try svc.fetch(id: "pomodoro-timer")
        #expect(refetched?.enabled == true)
    }

    @Test("Update skill definition")
    func updateDefinition() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill())
        let newScreens = #"{"main":{"type":"text","value":"Updated"}}"#
        try svc.updateDefinition(
            id: "pomodoro-timer",
            screens: newScreens,
            actions: nil,
            version: "2.0"
        )

        let fetched = try svc.fetch(id: "pomodoro-timer")
        #expect(fetched?.screens == newScreens)
        #expect(fetched?.version == "2.0")
        #expect(fetched?.actions == nil)
        #expect(fetched?.updatedAt != nil)
    }

    @Test("Uninstall skill")
    func uninstall() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill())
        try svc.uninstall(id: "pomodoro-timer")

        let fetched = try svc.fetch(id: "pomodoro-timer")
        #expect(fetched == nil)
    }

    @Test("Count skills")
    func count() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "a", name: "A"))
        try svc.install(sampleSkill(id: "b", name: "B"))
        var disabled = sampleSkill(id: "c", name: "C")
        disabled.enabled = false
        try svc.install(disabled)

        #expect(try svc.count() == 3)
        #expect(try svc.count(enabledOnly: true) == 2)
    }

    @Test("Install replaces existing skill with same id")
    func installReplaces() throws {
        let (svc, _) = try makeService()

        try svc.install(sampleSkill(id: "dup", name: "Version 1"))
        try svc.install(sampleSkill(id: "dup", name: "Version 2"))

        let all = try svc.list()
        #expect(all.count == 1)
        #expect(all.first?.name == "Version 2")
    }

    @Test("Decode permissions JSON helper")
    func decodePermissions() throws {
        let skill = sampleSkill()
        let perms = skill.decodedPermissions()
        #expect(perms == [SkillPermission.notifications, SkillPermission.haptics])
    }

    @Test("Decode triggers JSON helper")
    func decodeTriggers() throws {
        let skill = sampleSkill()
        let triggers = skill.decodedTriggers()
        #expect(triggers.count == 1)
        #expect(triggers.first?["type"] == "siri")
        #expect(triggers.first?["phrase"] == "Starte Pomodoro")
    }

    @Test("Skill table exists in schema")
    func tableExists() throws {
        let db = try DatabaseManager.temporary()
        try db.pool.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name='skills'
                """)
            #expect(tables.count == 1)
        }
    }
}
