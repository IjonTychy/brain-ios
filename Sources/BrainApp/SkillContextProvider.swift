import Foundation
import BrainCore
import GRDB

// Provides a unified set of template variables for ANY skill invocation,
// regardless of where the skill is opened (Dashboard, MoreTab, iPad Sidebar, SkillManager).
// Replaces the previous pattern where only the Dashboard got real data.
@MainActor
struct SkillContextProvider {
    let dataBridge: DataBridge

    /// Base variables every skill receives — time context + stats.
    func baseVariables() -> [String: ExpressionValue] {
        dataBridge.refreshDashboard()

        var vars: [String: ExpressionValue] = [:]

        // Time context
        vars["greeting"] = .string(DashboardRepository.greetingForTimeOfDay())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "EEEE, d. MMMM"
        vars["today"] = .string(formatter.string(from: Date()))
        vars["currentHour"] = .int(Calendar.current.component(.hour, from: Date()))

        // Stats (frequently referenced by skills)
        vars["stats"] = .object([
            "entries": .string(String(dataBridge.entryCount)),
            "todayEntries": .string(String(dataBridge.todayEntryCount)),
            "openTasks": .string(String(dataBridge.openTaskCount)),
            "unreadMails": .string(String(dataBridge.unreadMailCount)),
            "facts": .string(String(dataBridge.factCount)),
            "skills": .string(String(dataBridge.skillCount)),
            "tags": .string(String(dataBridge.tagCount)),
        ])

        return vars
    }

    /// Variables for a specific skill.
    /// Combines base variables + skill-specific data.
    func variables(for skill: Skill) -> [String: ExpressionValue] {
        var vars = baseVariables()

        // Dashboard gets extra data: recentEntries, openTasks, todayEvents
        if skill.id == "dashboard" {
            let dashVars = dataBridge.dashboardVariables()
            vars.merge(dashVars) { _, new in new }
        }

        // Skill-specific data queries (data block in SkillDefinition)
        if let definition = skill.toSkillDefinition(), definition.data != nil {
            let dataVars = SkillDataResolver(pool: dataBridge.db.pool)
                .resolve(definition)
            vars.merge(dataVars) { _, new in new }
        }

        return vars
    }

    /// Convenience: variables for a skill identified only by ID.
    func variables(forSkillId id: String) -> [String: ExpressionValue] {
        if id == "dashboard" {
            let placeholder = Skill(id: "dashboard", name: "Dashboard", screens: "{}", createdBy: .system)
            return variables(for: placeholder)
        }
        return baseVariables()
    }
}
