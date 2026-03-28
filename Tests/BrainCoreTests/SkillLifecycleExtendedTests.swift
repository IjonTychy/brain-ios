import Testing
import Foundation
@testable import BrainCore

// Erweiterte Tests fuer SkillLifecycle und SkillCompiler
@Suite("Skill Lifecycle Erweitert")
struct SkillLifecycleExtendedTests {

    private func makeLifecycle() throws -> (SkillLifecycle, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (SkillLifecycle(pool: db.pool), db)
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

    // MARK: - Install und Fetch

    @Test("Install und fetch via Lifecycle")
    func installAndFetch() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())
        let fetched = try lc.fetch(id: "test-skill")
        #expect(fetched != nil)
        #expect(fetched?.name == "Test Skill")
    }

    @Test("Fetch gibt nil fuer unbekannte Skill-ID")
    func fetchUnknownId() throws {
        let (lc, _) = try makeLifecycle()
        let fetched = try lc.fetch(id: "nonexistent")
        #expect(fetched == nil)
    }

    // MARK: - List

    @Test("List gibt alle installierten Skills zurueck")
    func listAllSkills() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(id: "a", name: "Alpha"), definition: validDefinition(id: "a"))
        try lc.installFromDefinition(source: validSource(id: "b", name: "Beta"), definition: validDefinition(id: "b"))
        try lc.installFromDefinition(source: validSource(id: "c", name: "Gamma"), definition: validDefinition(id: "c"))
        let all = try lc.list()
        #expect(all.count == 3)
    }

    @Test("List mit enabledOnly filtert deaktivierte Skills")
    func listEnabledOnly() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(id: "on", name: "On"), definition: validDefinition(id: "on"))
        try lc.installFromDefinition(source: validSource(id: "off", name: "Off"), definition: validDefinition(id: "off"))
        try lc.disable(id: "off")
        let enabled = try lc.list(enabledOnly: true)
        #expect(enabled.count == 1)
        #expect(enabled.first?.id == "on")
    }

    @Test("Leere Liste bei keinen installierten Skills")
    func listEmpty() throws {
        let (lc, _) = try makeLifecycle()
        #expect(try lc.list().isEmpty)
    }

    // MARK: - Enable/Disable

    @Test("Neu installierter Skill ist standardmaessig aktiviert")
    func newSkillIsEnabledByDefault() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())
        #expect(try lc.fetch(id: "test-skill")?.enabled == true)
    }

    @Test("Disable setzt Skill auf inaktiv")
    func disableSkill() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())
        try lc.disable(id: "test-skill")
        #expect(try lc.fetch(id: "test-skill")?.enabled == false)
    }

    @Test("Enable reaktiviert deaktivierten Skill")
    func enableSkill() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())
        try lc.disable(id: "test-skill")
        try lc.enable(id: "test-skill")
        #expect(try lc.fetch(id: "test-skill")?.enabled == true)
    }

    @Test("Disable auf unbekannte ID ist kein Fehler")
    func disableUnknownId() throws {
        let (lc, _) = try makeLifecycle()
        try lc.disable(id: "nonexistent")
    }

    // MARK: - Uninstall

    @Test("Uninstall entfernt Skill dauerhaft")
    func uninstallSkill() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(), definition: validDefinition())
        try lc.uninstall(id: "test-skill")
        #expect(try lc.fetch(id: "test-skill") == nil)
    }

    @Test("List nach Uninstall zeigt weniger Skills")
    func listAfterUninstall() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(id: "a", name: "A"), definition: validDefinition(id: "a"))
        try lc.installFromDefinition(source: validSource(id: "b", name: "B"), definition: validDefinition(id: "b"))
        #expect(try lc.list().count == 2)
        try lc.uninstall(id: "a")
        #expect(try lc.list().count == 1)
        #expect(try lc.list().first?.id == "b")
    }

    @Test("Uninstall auf unbekannte ID ist kein Fehler")
    func uninstallUnknownId() throws {
        let (lc, _) = try makeLifecycle()
        try lc.uninstall(id: "ghost")
    }

    // MARK: - Count

    @Test("Count gibt korrekte Anzahl zurueck")
    func countSkills() throws {
        let (lc, _) = try makeLifecycle()
        #expect(try lc.count() == 0)
        try lc.installFromDefinition(source: validSource(id: "a", name: "A"), definition: validDefinition(id: "a"))
        #expect(try lc.count() == 1)
        try lc.installFromDefinition(source: validSource(id: "b", name: "B"), definition: validDefinition(id: "b"))
        #expect(try lc.count() == 2)
    }

    @Test("Count enabledOnly zaehlt nur aktive Skills")
    func countEnabledOnly() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(id: "a", name: "A"), definition: validDefinition(id: "a"))
        try lc.installFromDefinition(source: validSource(id: "b", name: "B"), definition: validDefinition(id: "b"))
        try lc.disable(id: "b")
        #expect(try lc.count() == 2)
        #expect(try lc.count(enabledOnly: true) == 1)
    }

    @Test("Count nach Uninstall sinkt")
    func countAfterUninstall() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: validSource(id: "a", name: "A"), definition: validDefinition(id: "a"))
        try lc.installFromDefinition(source: validSource(id: "b", name: "B"), definition: validDefinition(id: "b"))
        try lc.uninstall(id: "a")
        #expect(try lc.count() == 1)
    }

    // MARK: - Validation Errors bei unbekannten Primitives

    @Test("Installation mit unbekanntem Primitive schlaegt fehl")
    func validationFailsOnUnknownPrimitive() throws {
        let (lc, _) = try makeLifecycle()
        let badDef = SkillDefinition(
            id: "test-skill",
            screens: ["main": ScreenNode(type: "completely_unknown_widget")]
        )
        #expect(throws: SkillLifecycleError.self) {
            try lc.installFromDefinition(source: validSource(), definition: badDef)
        }
    }

    @Test("validationFailed-Fehler enthaelt Fehlermeldung")
    func validationErrorContainsMessage() throws {
        let (lc, _) = try makeLifecycle()
        let badDef = SkillDefinition(
            id: "test-skill",
            screens: [
                "s1": ScreenNode(type: "invalid_type_a"),
                "s2": ScreenNode(type: "invalid_type_b")
            ]
        )
        do {
            try lc.installFromDefinition(source: validSource(), definition: badDef)
            Issue.record("Erwartete SkillLifecycleError")
        } catch SkillLifecycleError.validationFailed(let errors) {
            #expect(!errors.isEmpty)
            #expect(errors.contains { $0.contains("Unknown primitive") })
        } catch {
            Issue.record("Unerwarteter Fehlertyp: \(error)")
        }
    }

    // MARK: - Mehrfach-Installation (upsert)

    @Test("Gleiche Skill-ID kann neu installiert werden")
    func reinstallUpdatesSkill() throws {
        let (lc, _) = try makeLifecycle()
        try lc.installFromDefinition(source: BrainSkillSource(id: "dup", name: "Version 1"), definition: validDefinition(id: "dup"))
        try lc.installFromDefinition(source: BrainSkillSource(id: "dup", name: "Version 2"), definition: validDefinition(id: "dup"))
        #expect(try lc.count() == 1)
        #expect(try lc.fetch(id: "dup")?.name == "Version 2")
    }
}

// MARK: - SkillCompiler Erweiterungen

@Suite("Skill Compiler Erweitert")
struct SkillCompilerExtendedTests {

    let compiler = SkillCompiler()

    // MARK: - Fehlerfaelle im Frontmatter

    @Test("Fehlende schliessende --- wirft unclosedFrontmatter")
    func unclosedFrontmatter() throws {
        let md = """
        ---
        id: test
        name: Test Skill
        """
        #expect(throws: SkillParserError.self) {
            try compiler.parseSource(md)
        }
    }

    @Test("Kein id wirft missingRequiredField mit field=id")
    func missingId() throws {
        let md = """
        ---
        name: Skill ohne ID
        ---
        Body
        """
        do {
            try compiler.parseSource(md)
            Issue.record("Erwartete SkillParserError.missingRequiredField")
        } catch SkillParserError.missingRequiredField(let field) {
            #expect(field == "id")
        } catch {
            Issue.record("Unerwarteter Fehler: \(error)")
        }
    }

    @Test("Kein name wirft missingRequiredField mit field=name")
    func missingName() throws {
        let md = """
        ---
        id: skill-without-name
        ---
        Body
        """
        do {
            try compiler.parseSource(md)
            Issue.record("Erwartete SkillParserError.missingRequiredField")
        } catch SkillParserError.missingRequiredField(let field) {
            #expect(field == "name")
        } catch {
            Issue.record("Unerwarteter Fehler: \(error)")
        }
    }

    @Test("Leerer Content wirft missingFrontmatter")
    func emptyContent() throws {
        #expect(throws: SkillParserError.self) {
            try compiler.parseSource("")
        }
    }

    @Test("Content ohne --- wirft missingFrontmatter")
    func contentWithoutDashes() throws {
        #expect(throws: SkillParserError.self) {
            try compiler.parseSource("id: test\nname: Test")
        }
    }

    // MARK: - Trigger-Parsing

    @Test("Einzelner Trigger wird korrekt geparsed")
    func singleTrigger() throws {
        let md = """
        ---
        id: trigger-test
        name: Trigger Test
        triggers:
          - type: siri
            phrase: Starte das
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.triggers.count == 1)
        #expect(source.triggers[0]["type"] == "siri")
        #expect(source.triggers[0]["phrase"] == "Starte das")
    }

    @Test("Mehrere Trigger werden alle geparsed")
    func multipleTriggers() throws {
        let md = """
        ---
        id: multi-trigger
        name: Multi Trigger
        triggers:
          - type: siri
            phrase: Siri starten
          - type: shortcut
            name: Shortcut Name
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.triggers.count == 2)
        #expect(source.triggers[0]["type"] == "siri")
        #expect(source.triggers[1]["type"] == "shortcut")
    }

    @Test("Kein triggers-Feld ergibt leere Liste")
    func noTriggersField() throws {
        let md = """
        ---
        id: no-triggers
        name: No Triggers
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.triggers.isEmpty)
    }

    // MARK: - Verschachtelte YAML-Sektionen

    @Test("Verschachtelte Sektionen werden uebersprungen, Top-Level-Keys bleiben")
    func nestedSectionsSkipped() throws {
        let md = """
        ---
        id: test-nested
        name: Nested Test
        triggers:
          - type: siri
            phrase: Teste mich
        version: 2.0
        ---
        Markdown body
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "test-nested")
        #expect(source.name == "Nested Test")
        #expect(source.version == "2.0")
    }

    // MARK: - Permissions

    @Test("Inline-Permissions werden korrekt geparsed")
    func inlinePermissions() throws {
        let md = """
        ---
        id: perm-test
        name: Perm Test
        permissions: [notifications, haptics, location]
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.permissions == ["notifications", "haptics", "location"])
    }

    @Test("Leere Permissions ergeben leere Liste")
    func emptyPermissions() throws {
        let md = """
        ---
        id: no-perms
        name: No Perms
        permissions: []
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.permissions.isEmpty)
    }

    // MARK: - Markdown Body

    @Test("Markdown Body wird korrekt extrahiert")
    func markdownBodyExtracted() throws {
        let md = """
        ---
        id: body-test
        name: Body Test
        ---

        # Mein Skill

        Beschreibung hier.
        """
        let source = try compiler.parseSource(md)
        #expect(source.markdownBody.contains("# Mein Skill"))
        #expect(source.markdownBody.contains("Beschreibung hier."))
    }

    @Test("Optionale Felder fallen auf Standardwerte zurueck")
    func optionalFieldDefaults() throws {
        let md = """
        ---
        id: minimal
        name: Minimal Skill
        ---
        """
        let source = try compiler.parseSource(md)
        #expect(source.version == "1.0")
        #expect(source.icon == nil)
        #expect(source.color == nil)
        #expect(source.description == nil)
        #expect(source.permissions.isEmpty)
        #expect(source.triggers.isEmpty)
    }

    @Test("Angefuehrte Werte werden korrekt entquotet")
    func quotedValuesUnquoted() throws {
        let md = """
        ---
        id: quoted-test
        name: "Quoted Skill Name"
        description: 'Single quoted desc'
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.name == "Quoted Skill Name")
        #expect(source.description == "Single quoted desc")
    }
}
