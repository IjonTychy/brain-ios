import Testing
import Foundation
@testable import BrainCore

@Suite("Skill Compiler & Lifecycle")
struct SkillCompilerTests {

    let compiler = SkillCompiler()

    // MARK: - BrainSkill parser

    @Test("Parse minimal .brainskill.md")
    func parseMinimal() throws {
        let md = """
        ---
        id: test-skill
        name: Test Skill
        ---

        # Test Skill

        A simple test.
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "test-skill")
        #expect(source.name == "Test Skill")
        #expect(source.version == "1.0")
        #expect(source.markdownBody.contains("# Test Skill"))
    }

    @Test("Parse full .brainskill.md with all fields")
    func parseFull() throws {
        let md = """
        ---
        id: pomodoro-timer
        name: Pomodoro Timer
        description: Focus timer with 25/5 cycles
        version: 2.0
        icon: timer
        color: "#FF6347"
        permissions: [notifications, haptics]
        triggers:
          - type: siri
            phrase: Starte Pomodoro
          - type: shortcut
            name: Focus starten
        ---

        # Pomodoro Timer

        A focus timer.
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "pomodoro-timer")
        #expect(source.name == "Pomodoro Timer")
        #expect(source.description == "Focus timer with 25/5 cycles")
        #expect(source.version == "2.0")
        #expect(source.icon == "timer")
        #expect(source.color == "#FF6347")
        #expect(source.permissions == ["notifications", "haptics"])
        #expect(source.triggers.count == 2)
        #expect(source.triggers[0]["type"] == "siri")
        #expect(source.triggers[0]["phrase"] == "Starte Pomodoro")
    }

    @Test("Missing frontmatter throws error")
    func missingFrontmatter() throws {
        let md = "# No frontmatter here"
        #expect(throws: SkillParserError.self) {
            try compiler.parseSource(md)
        }
    }

    @Test("Missing required id throws error")
    func missingId() throws {
        let md = """
        ---
        name: No ID Skill
        ---
        Body
        """
        #expect(throws: SkillParserError.self) {
            try compiler.parseSource(md)
        }
    }

    // MARK: - Validation

    @Test("Validate valid definition")
    func validateValid() {
        let def = SkillDefinition(
            id: "test",
            screens: [
                "main": ScreenNode(
                    type: "stack",
                    children: [
                        ScreenNode(type: "text", properties: ["value": .string("Hello")])
                    ]
                )
            ]
        )
        let errors = compiler.validate(def)
        #expect(errors.isEmpty)
    }

    @Test("Validate catches unknown primitive")
    func validateUnknown() {
        let def = SkillDefinition(
            id: "test",
            screens: ["main": ScreenNode(type: "nonexistent")]
        )
        let errors = compiler.validate(def)
        #expect(!errors.isEmpty)
        #expect(errors[0].contains("Unknown primitive"))
    }

    // MARK: - Build skill record

    @Test("Build skill record from source and definition")
    func buildRecord() throws {
        let source = BrainSkillSource(
            id: "test",
            name: "Test",
            description: "A test skill",
            version: "1.0",
            icon: "star",
            permissions: ["haptics"]
        )
        let definition = SkillDefinition(
            id: "test",
            screens: ["main": ScreenNode(type: "text", properties: ["value": .string("Hi")])]
        )

        let skill = try compiler.buildSkillRecord(source: source, definition: definition)
        #expect(skill.id == "test")
        #expect(skill.name == "Test")
        #expect(skill.icon == "star")
        #expect(skill.decodedPermissions() == [SkillPermission.haptics])
        #expect(skill.screens.contains("text"))
    }

    // MARK: - Lifecycle

    @Test("Install and fetch via lifecycle")
    func lifecycle() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let source = BrainSkillSource(id: "lc-test", name: "LC Test")
        let definition = SkillDefinition(
            id: "lc-test",
            screens: ["main": ScreenNode(type: "text", properties: ["value": .string("Hello")])]
        )

        try lifecycle.installFromDefinition(source: source, definition: definition)

        let fetched = try lifecycle.fetch(id: "lc-test")
        #expect(fetched != nil)
        #expect(fetched?.name == "LC Test")
        #expect(fetched?.enabled == true)
    }

    @Test("Lifecycle rejects invalid skill")
    func lifecycleRejectsInvalid() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let source = BrainSkillSource(id: "bad", name: "Bad Skill")
        let definition = SkillDefinition(
            id: "bad",
            screens: ["main": ScreenNode(type: "totally_unknown_type")]
        )

        #expect(throws: SkillLifecycleError.self) {
            try lifecycle.installFromDefinition(source: source, definition: definition)
        }
    }

    @Test("Enable and disable via lifecycle")
    func enableDisable() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let source = BrainSkillSource(id: "toggle", name: "Toggle")
        let definition = SkillDefinition(
            id: "toggle",
            screens: ["main": ScreenNode(type: "text", properties: ["value": .string("X")])]
        )
        try lifecycle.installFromDefinition(source: source, definition: definition)

        try lifecycle.disable(id: "toggle")
        #expect(try lifecycle.fetch(id: "toggle")?.enabled == false)

        try lifecycle.enable(id: "toggle")
        #expect(try lifecycle.fetch(id: "toggle")?.enabled == true)
    }

    // MARK: - B1: New parser fields

    @Test("Parse capability field")
    func parseCapability() throws {
        let md = """
        ---
        id: cap-test
        name: Cap Test
        capability: hybrid
        created_by: system
        enabled: true
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.capability == .hybrid)
        #expect(source.createdBy == "system")
        #expect(source.enabled == true)
    }

    @Test("Parse nested llm block")
    func parseLLMBlock() throws {
        let md = """
        ---
        id: llm-test
        name: LLM Test
        capability: brain
        llm:
          required: true
          fallback: on-device
          complexity: medium
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.capability == .brain)
        #expect(source.llmRequired == true)
        #expect(source.llmFallback == "on-device")
        #expect(source.llmComplexity == "medium")
    }

    @Test("Parse skill without new fields has nil defaults")
    func parseWithoutNewFields() throws {
        let md = """
        ---
        id: old-skill
        name: Old Skill
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.capability == nil)
        #expect(source.llmRequired == nil)
        #expect(source.llmFallback == nil)
        #expect(source.llmComplexity == nil)
        #expect(source.createdBy == nil)
        #expect(source.enabled == nil)
    }

    @Test("Parse nested permissions list")
    func parseNestedPermissions() throws {
        let md = """
        ---
        id: perm-test
        name: Perm Test
        permissions:
          - notifications
          - haptics
          - entries
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.permissions.contains("notifications"))
        #expect(source.permissions.contains("haptics"))
        #expect(source.permissions.contains("entries"))
        #expect(source.permissions.count == 3)
    }

    @Test("Install from source without definition")
    func installFromSource() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let source = BrainSkillSource(
            id: "src-test",
            name: "Source Test",
            description: "A test",
            version: "1.0",
            icon: "star",
            capability: .app,
            createdBy: "system"
        )
        let skill = try lifecycle.installFromSource(source: source, createdBy: .system)
        #expect(skill.id == "src-test")
        #expect(skill.capability == "app")
        #expect(skill.createdBy == .system)

        let fetched = try lifecycle.fetch(id: "src-test")
        #expect(fetched != nil)
        #expect(fetched?.capability == "app")
    }

    @Test("Install from source skips duplicate version")
    func installFromSourceVersionCheck() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let source = BrainSkillSource(
            id: "ver-test",
            name: "Version Test",
            version: "1.0",
            capability: .brain
        )
        try lifecycle.installFromSource(source: source, createdBy: .system)

        // Install same version again — should upsert without error
        try lifecycle.installFromSource(source: source, createdBy: .system)

        let count = try lifecycle.count()
        #expect(count == 1)
    }

    @Test("Parse real bundled skill file format")
    func parseRealSkillFormat() throws {
        let md = """
        ---
        id: brain-translate
        name: Schnell-Uebersetzer
        description: Texte sofort uebersetzen
        version: "1.0"
        capability: brain
        created_by: system
        enabled: true
        permissions:
          - entries
        llm:
          required: true
          fallback: on-device
          complexity: low
        triggers:
          - type: user_action
            action: translate
          - type: shortcut
            phrase: Uebersetze
        ---

        # Schnell-Uebersetzer

        Uebersetzen via Brain.
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "brain-translate")
        #expect(source.capability == .brain)
        #expect(source.llmRequired == true)
        #expect(source.llmFallback == "on-device")
        #expect(source.llmComplexity == "low")
        #expect(source.permissions == ["entries"])
        #expect(source.triggers.count == 2)
        #expect(source.createdBy == "system")
        #expect(source.enabled == true)
    }

    @Test("Preview without installing")
    func preview() throws {
        let db = try DatabaseManager.temporary()
        let lifecycle = SkillLifecycle(pool: db.pool)

        let md = """
        ---
        id: preview-test
        name: Preview Test
        ---
        Body
        """
        let source = try lifecycle.preview(markdown: md)
        #expect(source.id == "preview-test")

        // Should NOT be installed
        let fetched = try lifecycle.fetch(id: "preview-test")
        #expect(fetched == nil)
    }
}
