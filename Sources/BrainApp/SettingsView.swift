import SwiftUI
import BrainCore

// API-Key management and app settings.
// Accessible from Brain Admin tab toolbar.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataBridge.self) private var dataBridge: DataBridge?
    @Environment(StoreKitManager.self) private var storeKit: StoreKitManager?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("faceIDEnabled") private var faceIDEnabled = true
    @AppStorage("aiPersonalityPreset") private var personalityPreset = "freundlich"
    @AppStorage("aiPersonalityName") private var personalityName = "Brain"
    @AppStorage("aiHumorLevel") private var humorLevel = 2.0
    @AppStorage("aiFormality") private var formality = "du"

    // Proxy state (used by proxy section in advanced)
    @State private var proxyURL = ""
    @State private var proxyUsername = ""
    @State private var proxyPassword = ""
    @State private var proxy2FACode = ""
    @State private var proxy2FATempToken = ""
    @State private var proxyStatus: KeyStatus = .unknown
    @State private var isLoggingInProxy = false
    @State private var isTestingProxy = false
    @State private var validationError: String?
    @State private var proxyLoggedIn = false
    @State private var showResetConfirmation = false
    @State private var proxyDisplayName: String?
    @State private var show2FAField = false
    @AppStorage("anthropicMode") private var anthropicMode = "api"
    @AppStorage("selectedModel") private var selectedModel = "claude-opus-4-6"
    @AppStorage(PinnedURLSession.tofuEnabledKey) private var tofuEnabled = false
    @AppStorage("autoRouteModels") private var autoRouteModels = false
    @AppStorage("showAdvancedSettings") private var showAdvanced = false
    @AppStorage("model.low") private var modelLow = "claude-haiku-4-5-20251001"
    @AppStorage("model.medium") private var modelMedium = "claude-sonnet-4-6"
    @AppStorage("model.high") private var modelHigh = "claude-opus-4-6"
    @AppStorage("model.private") private var modelPrivate = "on-device"
    @State private var monthCost: Double = 0
    @State private var customSystemPrompt: String = ""
    @State private var showSystemPromptEditor = false
    @State private var showResetPromptConfirm = false

    private let keychain = KeychainService()

    // Body split into extracted section methods to reduce opaque type nesting depth.
    // Deep nesting causes compiler stack overflow in ReplaceOpaqueTypesWithUnderlyingTypes.
    var body: some View {
        NavigationStack {
            List {
                // LLM Provider settings (dedicated sub-view)
                Section {
                    NavigationLink {
                        LLMProviderSettingsView()
                    } label: {
                        HStack {
                            Label("KI-Anbieter", systemImage: "cpu")
                            Spacer()
                            Text(AvailableModels.shortLabel(for: selectedModel))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Normal settings
                securitySection
                // LLM Billing
                Section {
                    NavigationLink {
                        LLMBillingView()
                    } label: {
                        HStack {
                            Label("Abrechnung", systemImage: "chart.bar")
                            Spacer()
                            if monthCost > 0 {
                                Text(String(format: "$%.2f", monthCost))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                shortcutsSetupSection
                purchaseSection
                infoSection

                proxySection
                taskRoutingSection
                privacyZonesSection
                systemPromptSection
                developmentSection
            }
            .navigationTitle(L("settings.title"))
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .tint(BrainTheme.Colors.brandPurple)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrainHelpButton.settings
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }

            }
            .onAppear {
                loadCurrentState()
            }
        }
    }

    // MARK: - Sections

    private var taskRoutingSection: some View {
        Section("Aufgaben-Routing") {
            Toggle("Automatisch routen", isOn: $autoRouteModels)
            if autoRouteModels {
                let models = AvailableModels.available()
                Picker("Einfach (Tags, Klassifizierung)", selection: $modelLow) {
                    ForEach(models) { m in Text(m.label).tag(m.id) }
                }
                Picker("Standard (Chat, Fragen)", selection: $modelMedium) {
                    ForEach(models) { m in Text(m.label).tag(m.id) }
                }
                Picker("Komplex (Analyse, Skills)", selection: $modelHigh) {
                    ForEach(models) { m in Text(m.label).tag(m.id) }
                }
                Picker("Privat (Privacy Zones)", selection: $modelPrivate) {
                    ForEach(models) { m in Text(m.label).tag(m.id) }
                }
            }
            Text("Brain wählt basierend auf Aufgabe das passende Modell. Spart Kosten bei einfachen Anfragen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @State private var maxSessionKeyInput = ""
    @State private var maxSessionKeySaved = false

    private var proxySection: some View {
        Section("Claude Max / Proxy") {
            // Max mode: Session Key from browser
            VStack(alignment: .leading, spacing: 8) {
                Label("Claude Max (Session-Key)", systemImage: "key.fill")
                Text("Session-Key aus dem Browser extrahieren (claude.ai → Cookie \"sessionKey\"). Gültig ~30 Tage.")
                    .font(.caption2).foregroundStyle(.secondary)
                SecureField("sk-ant-sid...", text: $maxSessionKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !maxSessionKeyInput.isEmpty {
                    Button("Session-Key speichern") {
                        let ks = KeychainService()
                        try? ks.save(key: KeychainKeys.anthropicMaxSessionKey, value: maxSessionKeyInput)
                        maxSessionKeyInput = ""
                        maxSessionKeySaved = true
                        anthropicMode = "max"
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrainTheme.Colors.brandPurple)
                }
                if maxSessionKeySaved || anthropicMode == "max" {
                    Label("Max-Modus aktiv", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Proxy mode
            VStack(alignment: .leading, spacing: 8) {
                Label("Proxy-URL", systemImage: "server.rack")
                Text("OpenAI-kompatibler Proxy mit JWT-Authentifizierung")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("https://mein-server:8082", text: $proxyURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("settings.proxyURL")
            }
            .padding(.vertical, 4)

            if proxyLoggedIn {
                proxyLoggedInView
            } else {
                proxyLoginForm
            }
        }
    }

    @ViewBuilder
    private var proxyLoggedInView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("Angemeldet").font(.subheadline).fontWeight(.medium)
                if let name = proxyDisplayName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusBadge(proxyStatus)
        }
        Button {
            Task { await testProxyConnection() }
        } label: {
            HStack {
                if isTestingProxy { ProgressView().tint(.white) }
                Text("Verbindung testen")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isTestingProxy)
        Button("Abmelden", role: .destructive) {
            BrainAPIAuthService.shared.logout()
            proxyLoggedIn = false
            proxyDisplayName = nil
            proxyStatus = .unknown
            anthropicMode = "api"
        }
    }

    @ViewBuilder
    private var proxyLoginForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Anmeldung", systemImage: "person.badge.key")
            TextField("Benutzername", text: $proxyUsername)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
            SecureField("Passwort", text: $proxyPassword)
                .textFieldStyle(.roundedBorder).textContentType(.none).autocorrectionDisabled().textInputAutocapitalization(.never)
            if show2FAField {
                HStack {
                    TextField("2FA-Code", text: $proxy2FACode)
                        .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                    Button {
                        Task { await submit2FA() }
                    } label: {
                        HStack {
                            if isLoggingInProxy { ProgressView().tint(.white) }
                            Text("Bestätigen")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(proxy2FACode.isEmpty || isLoggingInProxy)
                }
            }
        }
        .padding(.vertical, 4)
        if let validationError, anthropicMode == "proxy" {
            Text(validationError).font(.caption2).foregroundStyle(.red)
        }
        if !show2FAField {
            Button {
                Task { await loginToProxy() }
            } label: {
                HStack {
                    if isLoggingInProxy { ProgressView().tint(.white) }
                    Text("Anmelden")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(proxyURL.isEmpty || proxyUsername.isEmpty || proxyPassword.isEmpty || isLoggingInProxy)
        }
    }

    private var securitySection: some View {
        Section("Sicherheit") {
            Toggle("Face ID / Touch ID", isOn: $faceIDEnabled)
                .accessibilityIdentifier("settings.faceID")
            // TOFU always visible
                Toggle("Zertifikat-Fallback (TOFU)", isOn: $tofuEnabled)
                    .accessibilityIdentifier("settings.tofu")
                if tofuEnabled {
                    Text("Bei Zertifikatsrotation wird das neue Zertifikat akzeptiert, wenn die TLS-Validierung OK ist. Deaktivieren für strengeres Pinning.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
        }
    }

    private var privacyZonesSection: some View {
        Section("Privacy Zones") {
            NavigationLink {
                PrivacyZoneSettingsView()
            } label: {
                Label("Datenschutz-Zonen konfigurieren", systemImage: "lock.shield")
            }
            Text("Tags sind Schlagwörter die du Einträgen zuweisen kannst (z.B. #gesundheit, #finanzen, #privat). Privacy Zones bestimmen, welche Tags nur lokal auf dem Gerät verarbeitet werden und nie an Cloud-LLMs gesendet werden.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        Section("System-Prompt") {
            VStack(alignment: .leading, spacing: 8) {
                let hasCustom = !customSystemPrompt.isEmpty
                HStack {
                    Label(
                        hasCustom ? "Benutzerdefiniert" : "Standard",
                        systemImage: hasCustom ? "pencil.circle.fill" : "checkmark.circle"
                    )
                    .foregroundStyle(hasCustom ? .orange : .green)
                    Spacer()
                }

                Text("Der System-Prompt definiert Brains Persönlichkeit, Wissen und Verhalten. Änderungen wirken sich auf alle zukünftigen Chat-Nachrichten aus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showSystemPromptEditor = true
                } label: {
                    Text("System-Prompt bearbeiten")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if hasCustom {
                    Button {
                        showResetPromptConfirm = true
                    } label: {
                        Text("Auf Standard zurücksetzen")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            customSystemPrompt = UserDefaults.standard.string(forKey: "customSystemPromptOverride") ?? ""
        }
        .sheet(isPresented: $showSystemPromptEditor) {
            SystemPromptEditorView(
                customPrompt: $customSystemPrompt,
                pool: dataBridge!.db.pool
            )
        }
        .confirmationDialog("System-Prompt zurücksetzen?", isPresented: $showResetPromptConfirm) {
            Button("Zurücksetzen", role: .destructive) {
                customSystemPrompt = ""
                UserDefaults.standard.removeObject(forKey: "customSystemPromptOverride")
            }
        } message: {
            Text("Der System-Prompt wird auf den Standard zurückgesetzt. Deine Anpassungen gehen verloren.")
        }
    }

    private var developmentSection: some View {
        Section("Entwicklung") {
            Button("Onboarding zurücksetzen") {
                showResetConfirmation = true
            }
            .foregroundStyle(.red)
            .confirmationDialog("App komplett zurücksetzen?", isPresented: $showResetConfirmation) {
                Button("Zurücksetzen", role: .destructive) {
                    // Clear all API keys from Keychain
                    let ks = KeychainService()
                    ks.delete(key: KeychainKeys.anthropicAPIKey)
                    ks.delete(key: KeychainKeys.openAIAPIKey)
                    ks.delete(key: KeychainKeys.geminiAPIKey)
                    ks.delete(key: KeychainKeys.xaiAPIKey)
                    ks.delete(key: KeychainKeys.anthropicProxyURL)
                    ks.delete(key: GoogleOAuthKeys.clientId)
                    ks.delete(key: GoogleOAuthKeys.accessToken)
                    ks.delete(key: GoogleOAuthKeys.refreshToken)
                    // Clear relevant UserDefaults
                    UserDefaults.standard.removeObject(forKey: "selectedModel")
                    UserDefaults.standard.removeObject(forKey: "anthropicMode")
                    UserDefaults.standard.removeObject(forKey: "autoRouteModels")
                    hasCompletedOnboarding = false
                    dismiss()
                }
            } message: {
                Text("Alle API-Keys und Einstellungen werden geloescht. Das Onboarding wird erneut angezeigt.")
            }
        }
    }

    @State private var showPaywall = false

    private var purchaseSection: some View {
        Section("Lizenz") {
            if let store = storeKit {
                switch store.purchaseState {
                case .purchased:
                    HStack {
                        Label("Freigeschaltet", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(BrainTheme.Colors.success)
                        Spacer()
                        Text("Lifetime")
                            .foregroundStyle(.secondary)
                    }
                case .trial(let days):
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("Testphase", systemImage: "clock")
                            Spacer()
                            Text("Noch \(days) Tage")
                                .foregroundStyle(days <= 7 ? BrainTheme.Colors.warning : .secondary)
                        }
                    }
                case .trialExpired:
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("Testphase abgelaufen", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(BrainTheme.Colors.error)
                            Spacer()
                            Text("Jetzt kaufen")
                                .foregroundStyle(BrainTheme.Colors.brandPurple)
                        }
                    }
                case .loading, .notPurchased:
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Brain freischalten", systemImage: "cart")
                    }
                }
            } else {
                Text("Laden...")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            if let store = storeKit {
                PaywallView(store: store)
            }
        }
    }

    private var shortcutsSetupSection: some View {
        Section {
            NavigationLink {
                ShortcutsSetupView()
            } label: {
                Label("Shortcuts-Automationen", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            }
        } header: {
            Text("Hintergrund-Analyse")
        } footer: {
            Text("Für zuverlässige Hintergrund-Analyse empfehlen wir Shortcuts-Automationen einzurichten.")
        }
    }

    private var infoSection: some View {
        Section("Info") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func statusBadge(_ status: KeyStatus) -> some View {
        switch status {
        case .configured:
            Label("Konfiguriert", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .invalid:
            Label("Ungültig", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .unknown:
            Label("Nicht konfiguriert", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func loadCurrentState() {
        if let savedProxy = keychain.read(key: KeychainKeys.anthropicProxyURL), !savedProxy.isEmpty {
            proxyURL = savedProxy
        }
        let auth = BrainAPIAuthService.shared
        proxyLoggedIn = auth.isLoggedIn
        proxyDisplayName = auth.displayName
        if proxyLoggedIn {
            proxyStatus = .configured
        }
        // Load month cost for billing badge
        if let db = dataBridge?.db {
            let tracker = CostTracker(pool: db.pool)
            monthCost = (try? tracker.currentMonthCostEuros()) ?? 0
        }
    }

    // Login to proxy via JWT auth
    private func loginToProxy() async {
        isLoggingInProxy = true
        validationError = nil
        defer { isLoggingInProxy = false }

        let trimmed = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://") else {
            validationError = "Proxy-URL muss mit https:// beginnen (HTTP nicht erlaubt)."
            return
        }

        // Save proxy URL
        try? keychain.save(key: KeychainKeys.anthropicProxyURL, value: trimmed)

        do {
            let result = try await BrainAPIAuthService.shared.login(
                baseURL: trimmed,
                username: proxyUsername,
                password: proxyPassword
            )
            // Login succeeded
            proxyLoggedIn = true
            proxyDisplayName = result.displayName.isEmpty ? proxyUsername : result.displayName
            proxyStatus = .configured
            anthropicMode = "proxy"
            proxyUsername = ""
            proxyPassword = ""
        } catch AuthError.requires2FA(let tempToken) {
            // Show 2FA input
            proxy2FATempToken = tempToken
            show2FAField = true
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func submit2FA() async {
        isLoggingInProxy = true
        validationError = nil
        defer { isLoggingInProxy = false }

        let trimmed = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await BrainAPIAuthService.shared.login2FA(
                baseURL: trimmed,
                tempToken: proxy2FATempToken,
                code: proxy2FACode
            )
            proxyLoggedIn = true
            proxyDisplayName = result.displayName.isEmpty ? proxyUsername : result.displayName
            proxyStatus = .configured
            anthropicMode = "proxy"
            proxyUsername = ""
            proxyPassword = ""
            proxy2FACode = ""
            proxy2FATempToken = ""
            show2FAField = false
        } catch {
            validationError = error.localizedDescription
        }
    }

    // Test proxy connection with current JWT
    private func testProxyConnection() async {
        isTestingProxy = true
        validationError = nil
        defer { isTestingProxy = false }

        guard let token = await BrainAPIAuthService.shared.getValidToken() else {
            proxyStatus = .invalid
            proxyLoggedIn = false
            validationError = "Session abgelaufen. Bitte erneut anmelden."
            return
        }

        let base = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeProxyURL = (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/claude-proxy"
        let provider = AnthropicProvider(proxyURL: claudeProxyURL, bearerToken: token)
        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "Sag 'OK'.")],
            maxTokens: 10
        )

        do {
            let response = try await provider.complete(request)
            if !response.content.isEmpty {
                proxyStatus = .configured
            } else {
                proxyStatus = .invalid
            }
        } catch {
            proxyStatus = .invalid
            validationError = "Proxy-Test: \(error.localizedDescription)"
        }
    }

    private func formatExpiry(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_CH")
        fmt.dateFormat = "d. MMM yyyy, HH:mm"
        return fmt.string(from: date)
    }
}

enum KeyStatus {
    case unknown, configured, invalid
}
