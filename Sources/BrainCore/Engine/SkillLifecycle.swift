import Foundation
import GRDB

// Manages the complete skill lifecycle: parse → compile → validate → install → enable/disable → update → uninstall.
// Orchestrates SkillCompiler, ComponentRegistry, and SkillService.
public struct SkillLifecycle: Sendable {

    private let compiler: SkillCompiler
    private let service: SkillService
    private let registry: ComponentRegistry

    public init(
        pool: DatabasePool,
        registry: ComponentRegistry = ComponentRegistry()
    ) {
        self.compiler = SkillCompiler(registry: registry)
        self.service = SkillService(pool: pool)
        self.registry = registry
    }

    // MARK: - Import from .brainskill.md

    // Parse and validate a .brainskill.md source without installing.
    // Returns the parsed source for preview.
    public func preview(markdown: String) throws -> BrainSkillSource {
        try compiler.parseSource(markdown)
    }

    // MARK: - Install from source (without compiled definition)

    // Install a skill from its parsed source (.brainskill.md).
    // The skill is stored with an empty screens placeholder — the definition
    // will be compiled when the skill is first executed (by LLM or deterministic parser).
    @discardableResult
    public func installFromSource(
        source: BrainSkillSource,
        createdBy: SkillCreator = .user,
        screensJSON: String? = nil,
        actionsJSON: String? = nil
    ) throws -> Skill {
        // Encode triggers as JSON
        let triggersJSON: String?
        if !source.triggers.isEmpty,
           let data = try? JSONEncoder().encode(source.triggers) {
            triggersJSON = String(data: data, encoding: .utf8)
        } else {
            triggersJSON = nil
        }

        // Use LLM-generated screens JSON if provided, otherwise empty placeholder.
        let screens = screensJSON ?? "{}"

        let skill = Skill(
            id: source.id,
            name: source.name,
            description: source.description,
            version: source.version,
            icon: source.icon,
            color: source.color,
            capability: source.capability?.rawValue,
            permissions: Skill.encodePermissions(source.permissions),
            triggers: triggersJSON,
            screens: screens,
            actions: actionsJSON,
            sourceMarkdown: source.markdownBody,
            createdBy: createdBy,
            enabled: source.enabled ?? true
        )
        return try service.install(skill)
    }

    // MARK: - Install from JSON definition

    // Install a pre-compiled skill definition (e.g. from a Bootstrap Skill).
    @discardableResult
    public func installFromDefinition(
        source: BrainSkillSource,
        definition: SkillDefinition,
        createdBy: SkillCreator = .user
    ) throws -> Skill {
        // Validate against registry
        let errors = compiler.validate(definition)
        guard errors.isEmpty else {
            throw SkillLifecycleError.validationFailed(errors)
        }

        // Build and install
        var skill = try compiler.buildSkillRecord(
            source: source,
            definition: definition,
            createdBy: createdBy
        )
        // Preserve the original markdown
        skill.sourceMarkdown = nil // Will be set by caller if from .brainskill.md
        return try service.install(skill)
    }

    // MARK: - Lifecycle operations (delegate to SkillService)

    // Fetch an installed skill.
    public func fetch(id: String) throws -> Skill? {
        try service.fetch(id: id)
    }

    // List installed skills.
    public func list(enabledOnly: Bool = false) throws -> [Skill] {
        try service.list(enabledOnly: enabledOnly)
    }

    // Enable a skill.
    public func enable(id: String) throws {
        try service.setEnabled(id: id, enabled: true)
    }

    // Disable a skill.
    public func disable(id: String) throws {
        try service.setEnabled(id: id, enabled: false)
    }

    // Uninstall a skill permanently.
    public func uninstall(id: String) throws {
        try service.uninstall(id: id)
    }

    // Count installed skills.
    public func count(enabledOnly: Bool = false) throws -> Int {
        try service.count(enabledOnly: enabledOnly)
    }

    // Update a skill's JSON definition (screens, actions, version).
    // Delegates to SkillService.updateDefinition which recomputes the integrity hash.
    public func updateDefinition(
        id: String,
        screens: String,
        actions: String?,
        version: String? = nil
    ) throws {
        try service.updateDefinition(id: id, screens: screens, actions: actions, version: version)
    }

    // MARK: - Export to .brainskill.md

    // Export a skill to .brainskill.md format for sharing.
    // Reconstructs the YAML frontmatter from the Skill record.
    // If the original sourceMarkdown is available, returns that instead.
    public func export(id: String) throws -> String {
        guard let skill = try service.fetch(id: id) else {
            throw SkillLifecycleError.skillNotFound(id)
        }
        return exportSkill(skill)
    }

    // Export a Skill record to .brainskill.md format.
    public func exportSkill(_ skill: Skill) -> String {
        // Prefer the original markdown if stored
        if let source = skill.sourceMarkdown, !source.isEmpty {
            return source
        }

        // Reconstruct from metadata
        var lines: [String] = ["---"]
        lines.append("id: \(skill.id)")
        lines.append("name: \(skill.name)")
        if let desc = skill.description { lines.append("description: \(desc)") }
        lines.append("version: \(skill.version)")
        if let icon = skill.icon { lines.append("icon: \(icon)") }
        if let color = skill.color { lines.append("color: \(color)") }

        let perms = skill.decodedPermissions()
        if !perms.isEmpty {
            let permList = perms.map(\.rawValue).joined(separator: ", ")
            lines.append("permissions: [\(permList)]")
        }

        if let triggersJSON = skill.triggers,
           let data = triggersJSON.data(using: .utf8),
           let triggers = try? JSONDecoder().decode([[String: String]].self, from: data),
           !triggers.isEmpty {
            lines.append("triggers:")
            for trigger in triggers {
                let sorted = trigger.sorted { $0.key < $1.key }
                if let first = sorted.first {
                    lines.append("  - \(first.key): \(first.value)")
                    for kv in sorted.dropFirst() {
                        lines.append("    \(kv.key): \(kv.value)")
                    }
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append("# \(skill.name)")
        if let desc = skill.description {
            lines.append("")
            lines.append(desc)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

public enum SkillLifecycleError: Error, Sendable {
    case validationFailed([String])
    case compilationFailed(String)
    case skillNotFound(String)
}
