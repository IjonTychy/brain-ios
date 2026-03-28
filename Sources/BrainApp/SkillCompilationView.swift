import SwiftUI
import BrainCore

// On-demand skill compilation: when a skill has sourceMarkdown but no screens,
// this view sends the markdown to the LLM to generate the UI definition.
// This is the "Ribosom" function of the architecture (DNA → mRNA → Protein).
// The compiled result is persisted to the DB — compilation happens only ONCE.
struct SkillCompilationView: View {
    let skill: Skill
    @Environment(DataBridge.self) private var dataBridge

    @State private var compiledDefinition: SkillDefinition?
    @State private var isCompiling = false
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var thinkingPhrase = ThinkingPhrases.random()
    @State private var phraseTimer: Timer?

    // Estimate compilation time based on markdown length
    private var estimatedSeconds: Int {
        let length = skill.sourceMarkdown?.count ?? 0
        if length < 500 { return 8 }
        if length < 1500 { return 15 }
        if length < 3000 { return 25 }
        return 40
    }

    private var estimateLabel: String {
        if estimatedSeconds <= 10 { return "Kleiner Skill — wenige Sekunden" }
        if estimatedSeconds <= 20 { return "Mittlerer Skill — ca. \(estimatedSeconds) Sekunden" }
        return "Umfangreicher Skill — ca. \(estimatedSeconds) Sekunden"
    }

    var body: some View {
        Group {
            if let definition = compiledDefinition {
                let vars = SkillContextProvider(dataBridge: dataBridge)
                    .variables(for: skill)
                SkillView(
                    definition: definition,
                    initialVariables: vars,
                    handlers: CoreActionHandlers.all(data: dataBridge)
                )
            } else if isCompiling {
                compilingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                compilingView
                    .task { await compileSkill() }
            }
        }
    }

    private var compilingView: some View {
        VStack(spacing: BrainTheme.Spacing.xl) {
            Spacer()

            // Brain icon that "fills with knowledge"
            ZStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(BrainTheme.Colors.textTertiary.opacity(0.3))

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(BrainTheme.Gradients.brand)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: 64 * progress)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
            }
            .frame(height: 80)

            VStack(spacing: BrainTheme.Spacing.sm) {
                Text("Brain kompiliert Skill")
                    .font(BrainTheme.Typography.headline)

                Text(skill.name)
                    .font(BrainTheme.Typography.subheadline)
                    .foregroundStyle(BrainTheme.Colors.brandPurple)
            }

            // Progress bar
            VStack(spacing: BrainTheme.Spacing.xs) {
                ProgressView(value: progress)
                    .tint(BrainTheme.Colors.brandPurple)
                    .frame(maxWidth: 200)

                Text(estimateLabel)
                    .font(BrainTheme.Typography.caption)
                    .foregroundStyle(BrainTheme.Colors.textTertiary)
            }

            // Thinking phrase (rotates)
            Text(thinkingPhrase)
                .font(BrainTheme.Typography.caption)
                .foregroundStyle(BrainTheme.Colors.textSecondary)
                .italic()
                .animation(.easeInOut, value: thinkingPhrase)

            Spacer()
        }
        .padding(BrainTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startProgressAnimation() }
        .onDisappear { phraseTimer?.invalidate() }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Kompilierung fehlgeschlagen", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen") {
                errorMessage = nil
                progress = 0
                Task { await compileSkill() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrainTheme.Colors.brandPurple)
        }
    }

    // MARK: - Animation

    private func startProgressAnimation() {
        // Animate progress bar to ~90% over estimated time
        let duration = Double(estimatedSeconds)
        withAnimation(.easeOut(duration: duration)) {
            progress = 0.9
        }

        // Rotate thinking phrases every 4 seconds
        phraseTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                thinkingPhrase = ThinkingPhrases.random()
            }
        }
    }

    // MARK: - Compilation

    private func compileSkill() async {
        guard let markdown = skill.sourceMarkdown, !markdown.isEmpty else {
            errorMessage = "Skill hat keinen Quelltext zum Kompilieren."
            return
        }

        // Check if any LLM provider is available (API keys, OAuth, proxy, or custom endpoints)
        let keychain = KeychainService()
        let hasProvider = keychain.exists(key: KeychainKeys.anthropicAPIKey)
            || keychain.exists(key: KeychainKeys.openAIAPIKey)
            || keychain.exists(key: KeychainKeys.geminiAPIKey)
            || keychain.exists(key: KeychainKeys.xaiAPIKey)
            || keychain.exists(key: KeychainKeys.anthropicProxyURL)
            || keychain.exists(key: GoogleOAuthKeys.accessToken)
            || (AvailableModels.loadCustomEndpoints()?.isEmpty == false)
        guard hasProvider else {
            errorMessage = "Konfiguriere einen API-Key in den Einstellungen, damit Brain Skills kompilieren kann."
            return
        }

        isCompiling = true
        defer { isCompiling = false }

        do {
            guard let provider = await dataBridge.buildLLMProvider() else {
                errorMessage = "Kein kompatibler LLM-Anbieter fuer das gewaehlte Modell konfiguriert."
                return
            }
            let prompt = SkillCompilePrompt.build(markdown: markdown)
            let request = LLMRequest(
                messages: [LLMMessage(role: "user", content: prompt)],
                systemPrompt: SkillCompilePrompt.system,
                maxTokens: 4096
            )

            let response = try await provider.complete(request)
            let jsonString = SkillCompilePrompt.extractJSON(from: response.content)

            guard !jsonString.isEmpty else {
                errorMessage = "Kein gültiges JSON vom LLM erhalten."
                return
            }

            // Parse the JSON to extract screens (and optionally actions)
            guard let jsonData = jsonString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                errorMessage = "LLM-Antwort enthielt kein gültiges JSON."
                return
            }

            // The JSON might be {"main": {...}} (just screens) or {"screens": {...}, "actions": {...}}
            let screensStr: String
            let actionsStr: String?

            if let screensObj = jsonObject["screens"] {
                // Format: {"screens": {...}, "actions": {...}}
                let screensData = try JSONSerialization.data(withJSONObject: screensObj)
                screensStr = String(data: screensData, encoding: .utf8) ?? "{}"
                if let actionsObj = jsonObject["actions"] {
                    let actionsData = try JSONSerialization.data(withJSONObject: actionsObj)
                    actionsStr = String(data: actionsData, encoding: .utf8)
                } else {
                    actionsStr = nil
                }
            } else if jsonObject["main"] != nil {
                // Format: {"main": {...}} — the whole JSON IS the screens dict
                screensStr = jsonString
                actionsStr = nil
            } else {
                errorMessage = "JSON hat weder 'screens' noch 'main' Key."
                return
            }

            // Persist to DB
            let lifecycle = SkillLifecycle(pool: dataBridge.db.pool)
            try lifecycle.updateDefinition(
                id: skill.id,
                screens: screensStr,
                actions: actionsStr
            )
            NotificationCenter.default.post(name: .brainSkillsChanged, object: nil)

            // Complete progress animation
            withAnimation(.easeIn(duration: 0.3)) {
                progress = 1.0
            }

            // Reload from DB
            if let updated = try lifecycle.fetch(id: skill.id),
               let definition = updated.toSkillDefinition() {
                compiledDefinition = definition
            } else {
                errorMessage = "Skill wurde kompiliert, konnte aber nicht geladen werden."
            }
        } catch {
            errorMessage = "Kompilierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
