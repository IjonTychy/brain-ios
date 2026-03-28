import SwiftUI
import BrainCore

// Wrapper that auto-compiles a skill's markdown into JSON screens via LLM
// when opened for the first time. Shows a progress indicator during compilation,
// then renders the skill normally once screens are available.
struct SkillAutoCompileView: View {
    let skill: Skill
    let dataBridge: DataBridge

    @State private var compiledDefinition: SkillDefinition?
    @State private var isCompiling = false
    @State private var errorMessage: String?
    @State private var thinkingPhrase = ThinkingPhrases.random()
    @State private var pendingJSON: String?
    @State private var safetyWarnings: [String] = []

    var body: some View {
        Group {
            if let definition = compiledDefinition {
                // Skill is compiled — render it
                SkillView(
                    definition: definition,
                    handlers: CoreActionHandlers.all(data: dataBridge)
                )
            } else if let json = pendingJSON, !safetyWarnings.isEmpty {
                // Safety review — user must confirm before installation
                VStack(spacing: BrainTheme.Spacing.lg) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(BrainTheme.Colors.warning)

                    Text("Sicherheitsprüfung")
                        .font(BrainTheme.Typography.headline)

                    Text("Dieser Skill enthält Aktionen die Daten verändern können:")
                        .font(BrainTheme.Typography.subheadline)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: BrainTheme.Spacing.sm) {
                        ForEach(safetyWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(BrainTheme.Colors.warning)
                        }
                    }
                    .brainCard()

                    HStack(spacing: BrainTheme.Spacing.lg) {
                        Button("Abbrechen") {
                            pendingJSON = nil
                            safetyWarnings = []
                            errorMessage = "Installation abgebrochen."
                        }
                        .buttonStyle(.bordered)

                        Button("Trotzdem installieren") {
                            Task { await installJSON(json) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrainTheme.Colors.warning)
                    }
                }
                .padding(BrainTheme.Spacing.xl)
            } else if isCompiling {
                // Compiling in progress
                VStack(spacing: BrainTheme.Spacing.xl) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .pulseEffect()

                    Text("Skill wird kompiliert...")
                        .font(BrainTheme.Typography.headline)

                    Text(thinkingPhrase)
                        .font(BrainTheme.Typography.caption)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                        .italic()

                    ProgressView()
                        .controlSize(.large)
                        .tint(BrainTheme.Colors.brandPurple)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                // Compilation failed
                ContentUnavailableView {
                    Label("Kompilierung fehlgeschlagen", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") {
                        Task { await compileSkill() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrainTheme.Colors.brandPurple)
                }
            } else {
                // No API key configured
                ContentUnavailableView {
                    Label("KI-Anbieter benötigt", systemImage: "key")
                } description: {
                    Text("Um diesen Skill zu kompilieren, muss ein KI-Anbieter in den Einstellungen konfiguriert sein.")
                }
            }
        }
        .navigationTitle(skill.name)
        .task {
            // Check if already compiled
            if let def = skill.toSkillDefinition() {
                compiledDefinition = def
                return
            }
            // Auto-compile if markdown is available and LLM is configured
            guard skill.sourceMarkdown != nil, !skill.sourceMarkdown!.isEmpty else {
                errorMessage = "Skill hat kein Quell-Markdown."
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
            guard hasProvider else { return }

            await compileSkill()
        }
    }

    private func compileSkill() async {
        guard let markdown = skill.sourceMarkdown else { return }
        isCompiling = true
        errorMessage = nil

        do {
            guard let provider = await dataBridge.buildLLMProvider() else {
                errorMessage = "Kein kompatibler LLM-Anbieter fuer das gewaehlte Modell konfiguriert."
                isCompiling = false
                return
            }
            let prompt = SkillCompilePrompt.build(markdown: markdown)
            let request = LLMRequest(
                messages: [LLMMessage(role: "user", content: prompt)],
                systemPrompt: SkillCompilePrompt.system,
                maxTokens: 4000
            )
            let response = try await provider.complete(request)
            let json = SkillCompilePrompt.extractJSON(from: response.content)

            guard !json.isEmpty else {
                errorMessage = "Kein gültiges JSON vom LLM erhalten."
                isCompiling = false
                return
            }

            // Safety check before installation
            let warnings = SkillSafetyAnalyzer.analyze(json: json, actions: nil)
            if warnings.isEmpty {
                // No dangerous actions — install directly
                await installJSON(json)
            } else {
                // Show safety review to user
                pendingJSON = json
                safetyWarnings = warnings
                isCompiling = false
            }
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
            isCompiling = false
        }
    }

    private func installJSON(_ json: String) async {
        guard let markdown = skill.sourceMarkdown else { return }
        isCompiling = true
        do {
            let lifecycle = SkillLifecycle(pool: dataBridge.db.pool)
            let source = try lifecycle.preview(markdown: markdown)
            try lifecycle.uninstall(id: source.id)
            let installed = try lifecycle.installFromSource(
                source: source,
                createdBy: skill.createdBy,
                screensJSON: json
            )
            compiledDefinition = installed.toSkillDefinition()
            pendingJSON = nil
            safetyWarnings = []
            if compiledDefinition == nil {
                errorMessage = "JSON wurde generiert, aber konnte nicht als Screen geladen werden."
            }
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isCompiling = false
    }
}
