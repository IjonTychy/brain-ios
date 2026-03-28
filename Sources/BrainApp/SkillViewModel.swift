import SwiftUI
import Observation
import BrainCore

// Observable state container for a running skill.
@MainActor @Observable
final class SkillViewModel {
    var context: ExpressionContext
    var currentScreen: String
    var definition: SkillDefinition
    var isLoading = false
    var errorMessage: String?

    private let interpreter: LogicInterpreter
    private let dispatcher: ActionDispatcher
    // Guard against concurrent action execution (race condition fix)
    private var actionTask: Task<Void, Never>?

    init(
        definition: SkillDefinition,
        initialScreen: String = "main",
        initialVariables: [String: ExpressionValue] = [:],
        additionalHandlers: [any ActionHandler] = []
    ) {
        self.definition = definition
        self.currentScreen = initialScreen
        self.context = ExpressionContext(variables: initialVariables)

        // Build dispatcher with all handlers at init (immutable after construction)
        let dispatcher = ActionDispatcher(handlers: additionalHandlers)
        self.dispatcher = dispatcher
        self.interpreter = LogicInterpreter(dispatcher: dispatcher)
    }

    var currentScreenNode: ScreenNode? {
        definition.screens[currentScreen]
    }

    // MARK: - Action handling

    func executeAction(_ actionName: String, actionContext: ExpressionContext? = nil) {
        let mergedContext = mergedContext(with: actionContext)

        guard let action = definition.actions?[actionName] else {
            handleBuiltinAction(actionName, context: mergedContext)
            return
        }

        // Cancel any in-flight action to prevent race conditions
        // from rapid successive taps
        actionTask?.cancel()

        actionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            isLoading = true
            errorMessage = nil

            do {
                let result = try await interpreter.execute(action: action, context: mergedContext)
                guard !Task.isCancelled else { return }
                self.context = mergedContext
                if case .error(let msg) = result {
                    errorMessage = msg
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Fehler: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    // MARK: - Variable management

    func setVariable(_ key: String, value: ExpressionValue) {
        context.variables[key] = value
    }

    func getVariable(_ key: String) -> ExpressionValue? {
        context.variables[key]
    }

    // MARK: - Navigation

    func navigateTo(screen: String) {
        guard definition.screens[screen] != nil else { return }
        currentScreen = screen
    }

    // MARK: - Built-in actions

    // Lookup table for tab navigation aliases.
    // Keys are exact action names, values are BrainTab rawValues.
    private static let tabAliases: [String: String] = [
        "goToMail": "mail", "goMail": "mail",
        "goToSearch": "search", "goSearch": "search",
        "goToChat": "chat", "goChat": "chat",
        "goToCalendar": "calendar", "goCalendar": "calendar",
        "goToFiles": "files", "goFiles": "files",
        "goToContacts": "people", "goContacts": "people",
        "goToSkills": "brainAdmin", "goSkills": "brainAdmin",
        "goToDashboard": "dashboard", "goDashboard": "dashboard",
        "goToKnowledgeGraph": "knowledgeGraph", "goKnowledgeGraph": "knowledgeGraph",
        "goToCanvas": "canvas", "goCanvas": "canvas",
    ]

    private func postTabNavigation(_ tabName: String) {
        NotificationCenter.default.post(
            name: .brainNavigateTab,
            object: nil,
            userInfo: ["tab": tabName]
        )
    }

    private func handleBuiltinAction(_ name: String, context: ExpressionContext) {
        // 1. Exact tab alias match (goToContacts, goMail, etc.)
        if let tab = Self.tabAliases[name] {
            postTabNavigation(tab)
        } else if name.hasPrefix("navigate:") {
            let screen = String(name.dropFirst("navigate:".count))
            navigateTo(screen: screen)
        } else if name.hasPrefix("navigate.tab:") {
            let tabName = String(name.dropFirst("navigate.tab:".count))
            postTabNavigation(tabName)
        } else if name.hasPrefix("goTo") {
            // Generic fallback for unknown goTo* actions — extract tab name
            let tabName = String(name.dropFirst(4)).lowercased()
            postTabNavigation(tabName)
        } else if name.hasPrefix("set:") {
            // set:variableName=value
            let parts = String(name.dropFirst(4)).split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                setVariable(String(parts[0]), value: .string(String(parts[1])))
            }
        } else if name.hasPrefix("toggle:") {
            let varName = String(name.dropFirst(7))
            let current = context.variables[varName]
            if case .bool(let b) = current {
                setVariable(varName, value: .bool(!b))
            } else {
                setVariable(varName, value: .bool(true))
            }
        } else if name.hasPrefix("open-url:") {
            let urlStr = String(name.dropFirst(9))
            if let url = URL(string: urlStr) {
                Task { @MainActor in UIApplication.shared.open(url) }
            }
        } else if name == "dismiss" || name == "close" || name == "back" {
            if let prev = definition.screens.keys.first {
                currentScreen = prev
            }
        } else if name == "refresh" || name == "reload" {
            Task { @MainActor in
                isLoading = true
                self.context = self.context // trigger re-render
                isLoading = false
            }
        } else if name == "openEntry" || name == "completeTask" || name == "quickCapture" {
            NotificationCenter.default.post(name: .brainSkillAction, object: nil, userInfo: [
                "action": name,
                "skill": definition.id,
                "variables": context.variables.mapValues { String(describing: $0) }
            ])
        } else if name.isEmpty {
            // Empty action name -- ignore silently
        } else if dispatcher.hasHandler(for: name) {
            // Action name directly matches a registered handler (e.g. "camera.capture").
            // Execute it as a single-step action without going through chat.
            let step = ActionStep(type: name)
            actionTask?.cancel()
            actionTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                isLoading = true
                do {
                    let result = try await dispatcher.execute(step: step, context: context)
                    guard !Task.isCancelled else { return }
                    if case .value(let val) = result {
                        self.context.variables["lastResult"] = val
                    } else if case .error(let msg) = result {
                        errorMessage = msg
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = "Fehler: \(error.localizedDescription)"
                }
                isLoading = false
            }
        } else {
            // Unknown action: route to Brain chat as an LLM request.
            // This makes all skill buttons functional — Brain interprets the intent.
            let skillName = definition.id
            let vars = context.variables.mapValues { "\($0)" }
            NotificationCenter.default.post(
                name: .brainSkillAction,
                object: nil,
                userInfo: [
                    "action": name,
                    "skill": skillName,
                    "variables": vars
                ]
            )
        }
    }

    private func mergedContext(with actionContext: ExpressionContext?) -> ExpressionContext {
        guard let actionContext else { return context }
        var merged = context
        for (key, value) in actionContext.variables {
            merged.variables[key] = value
        }
        return merged
    }
}
