import SwiftUI
import BrainCore

// Dedicated settings view for all LLM providers.
// Accessible from Settings as "KI-Anbieter" NavigationLink.
// Each provider gets its own section with equal weight.
struct LLMProviderSettingsView: View {
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var anthropicStatus: KeyStatus = .unknown
    @State private var openAIStatus: KeyStatus = .unknown
    @State private var geminiStatus: KeyStatus = .unknown
    @State private var isTestingAnthropic = false
    @State private var isTestingOpenAI = false
    @State private var isGoogleOAuthLoggedIn = false
    @State private var isGoogleOAuthLoggingIn = false
    @State private var googleClientId = ""
    @State private var xaiKey = ""
    @State private var xaiStatus: KeyStatus = .unknown
    @State private var customName = ""
    @State private var customURL = ""
    @State private var customModel = ""
    @State private var customKey = ""
    @State private var customEndpoints: [AvailableModels.CustomEndpoint] = []
    @State private var validationError: String?
    @State private var anthropicError: String?
    @State private var openAIError: String?
    @State private var geminiError: String?
    @State private var googleOAuthError: String?
    @State private var isRefreshingModels = false
    @State private var modelGroups: [(provider: String, models: [AvailableModels.Model])] = []

    @AppStorage("selectedModel") private var selectedModel = "claude-opus-4-6"

    private let keychain = KeychainService()
    private let googleOAuth = GoogleOAuthService()

    var body: some View {
        List {
            modelPickerSection
            anthropicSection
            openAISection
            geminiSection
            xaiSection
            customEndpointSection
            onDeviceSection
        }
        .navigationTitle("KI-Anbieter")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrainHelpButton(context: "KI-Anbieter: API-Keys, Modelle, Preise", screenName: "KI-Anbieter")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
        .onAppear {
            loadStatus()
            modelGroups = AvailableModels.availableGrouped()
        }
        .task {
            isRefreshingModels = true
            await AvailableModels.refreshFromAPIs()
            modelGroups = AvailableModels.availableGrouped()
            isRefreshingModels = false
        }
    }

    // MARK: - Model Picker

    private var modelPickerSection: some View {
        Section {
            Picker("Standard-Modell", selection: $selectedModel) {
                ForEach(modelGroups, id: \.provider) { group in
                    Section(group.provider) {
                        ForEach(group.models) { model in
                            HStack {
                                Text(model.label)
                                Spacer()
                                Text(model.cost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(model.id)
                        }
                    }
                }
            }
            .pickerStyle(.navigationLink)

            Button {
                Task {
                    isRefreshingModels = true
                    await AvailableModels.forceRefresh()
                    modelGroups = AvailableModels.availableGrouped()
                    isRefreshingModels = false
                }
            } label: {
                HStack {
                    Label("Modelle aktualisieren", systemImage: "arrow.clockwise")
                    Spacer()
                    if isRefreshingModels {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isRefreshingModels)
        } header: {
            Text("Standard-Modell")
        } footer: {
            Text("Modelle werden von den Provider-APIs abgerufen. Im Chat jederzeit wechselbar.")
        }
    }

    // MARK: - Anthropic (Claude)

    private var anthropicSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("sk-ant-...", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                statusBadge(anthropicStatus)
                if let error = anthropicError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if !anthropicKey.isEmpty {
                    Button {
                        Task { await testAndSaveAnthropic() }
                    } label: {
                        HStack {
                            if isTestingAnthropic { ProgressView().controlSize(.small) }
                            Text("Testen & Speichern")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTestingAnthropic)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label { Text("Anthropic (Claude)") } icon: { Image("provider-anthropic").resizable().frame(width: 20, height: 20) }
        } footer: {
            Text("Modelle: Opus ($5/$25 pro 1M Token), Sonnet ($3/$15), Haiku ($1/$5)")
        }
    }

    // MARK: - OpenAI (GPT)

    private var openAISection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("sk-...", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                statusBadge(openAIStatus)
                if !openAIKey.isEmpty {
                    Button { saveOpenAIKey() } label: {
                        Text("Speichern").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label { Text("OpenAI (GPT)") } icon: { Image("provider-openai").resizable().frame(width: 20, height: 20) }
        } footer: {
            Text("Modelle: GPT-4o, GPT-4o Mini")
        }
    }

    // MARK: - Google (Gemini)

    private var geminiSection: some View {
        Section {
            // OAuth Login
            VStack(alignment: .leading, spacing: 8) {
                if isGoogleOAuthLoggedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Mit Google angemeldet")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Abmelden", role: .destructive) {
                            googleOAuth.logout()
                            isGoogleOAuthLoggedIn = false
                        }
                        .font(.caption)
                    }
                } else {
                    Button {
                        Task { await performGoogleOAuthLogin() }
                    } label: {
                        HStack {
                            if isGoogleOAuthLoggingIn {
                                ProgressView().controlSize(.small)
                            }
                            Text("Mit Google anmelden")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isGoogleOAuthLoggingIn)

                if let error = googleOAuthError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                }
            }
            .padding(.vertical, 4)

            // API Key alternative
            VStack(alignment: .leading, spacing: 8) {
                Text("Oder: API-Key").font(.caption).foregroundStyle(.secondary)
                SecureField("AIza...", text: $geminiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                statusBadge(geminiStatus)
                if !geminiKey.isEmpty {
                    Button { saveGeminiKey() } label: {
                        Text("Speichern").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label { Text("Google (Gemini)") } icon: { Image("provider-google").resizable().frame(width: 20, height: 20) }
        } footer: {
            Text("Modelle: Gemini 3.1 Pro ($2/$12), Flash ($0.50/$3), Flash-Lite ($0.25/$1.50). Login oder API-Key.")
        }
    }

    // MARK: - On-Device

    // MARK: - xAI (Grok)

    private var xaiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("xai-...", text: $xaiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                statusBadge(xaiStatus)
                if !xaiKey.isEmpty {
                    Button { saveXAIKey() } label: {
                        Text("Speichern").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label { Text("xAI (Grok)") } icon: { Image("provider-xai").resizable().frame(width: 20, height: 20) }
        } footer: {
            Text("Modelle: Grok 4, Grok 4.1 Fast. OpenAI-kompatible API.")
        }
    }

    private func saveXAIKey() {
        let trimmed = xaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else {
            xaiStatus = .invalid
            return
        }
        try? keychain.save(key: KeychainKeys.xaiAPIKey, value: trimmed)
        xaiStatus = .configured
        xaiKey = ""
    }

    // MARK: - Custom OpenAI-compatible Endpoints

    private var customEndpointSection: some View {
        Section {
            // Existing endpoints
            ForEach(customEndpoints, id: \.name) { endpoint in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(endpoint.name).font(.headline)
                        Text("\(endpoint.baseURL) — \(endpoint.model)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        AvailableModels.removeCustomEndpoint(name: endpoint.name)
                        customEndpoints = AvailableModels.loadCustomEndpoints() ?? []
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            // Add new endpoint
            DisclosureGroup("Neuen Endpoint hinzufuegen") {
                TextField("Name (z.B. Ollama)", text: $customName)
                    .textFieldStyle(.roundedBorder)
                TextField("URL (z.B. http://192.168.1.100:11434)", text: $customURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Modell-ID (z.B. llama3.2)", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                SecureField("API-Key (optional)", text: $customKey)
                    .textFieldStyle(.roundedBorder)

                if !customName.isEmpty && !customURL.isEmpty && !customModel.isEmpty {
                    Button {
                        let endpoint = AvailableModels.CustomEndpoint(
                            name: customName, baseURL: customURL,
                            model: customModel, apiKey: customKey.isEmpty ? nil : customKey
                        )
                        AvailableModels.addCustomEndpoint(endpoint)
                        customEndpoints = AvailableModels.loadCustomEndpoints() ?? []
                        customName = ""; customURL = ""; customModel = ""; customKey = ""
                    } label: {
                        Text("Hinzufügen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Label("Eigene Endpoints", systemImage: "server.rack")
        } footer: {
            Text("OpenAI-kompatible Server: Ollama, Mistral, Deepseek, LiteLLM, vLLM, etc.")
        }
    }

    // MARK: - On-Device

    private var onDeviceSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Immer verfügbar")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Auf dem Gerät (Offline)", systemImage: "iphone")
        } footer: {
            Text("Apple Foundation Models. Kostenlos, privat, keine API-Keys noetig.")
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: KeyStatus) -> some View {
        switch status {
        case .configured:
            Label("Konfiguriert", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .invalid:
            Label("Ungültig", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
        case .unknown:
            Label("Nicht konfiguriert", systemImage: "circle.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func loadStatus() {
        if keychain.exists(key: KeychainKeys.anthropicAPIKey) { anthropicStatus = .configured }
        if keychain.exists(key: KeychainKeys.openAIAPIKey) { openAIStatus = .configured }
        if keychain.exists(key: KeychainKeys.geminiAPIKey) { geminiStatus = .configured }
        if keychain.exists(key: KeychainKeys.xaiAPIKey) { xaiStatus = .configured }
        isGoogleOAuthLoggedIn = googleOAuth.isAuthenticated
        customEndpoints = AvailableModels.loadCustomEndpoints() ?? []
    }

    private func testAndSaveAnthropic() async {
        isTestingAnthropic = true
        anthropicError = nil
        defer { isTestingAnthropic = false }

        guard APIKeyValidator.validate(anthropicKey, provider: .anthropic) else {
            anthropicError = APIKeyValidator.errorMessage(for: .anthropic)
            anthropicStatus = .invalid
            return
        }

        let provider = AnthropicProvider(apiKey: anthropicKey)
        do {
            let request = LLMRequest(messages: [LLMMessage(role: "user", content: "Hallo")])
            _ = try await provider.complete(request)
            try keychain.saveWithBiometry(key: KeychainKeys.anthropicAPIKey, value: anthropicKey)
            anthropicStatus = .configured
            anthropicKey = ""
        } catch {
            anthropicError = error.localizedDescription
            anthropicStatus = .invalid
        }
    }

    private func saveOpenAIKey() {
        guard APIKeyValidator.validate(openAIKey, provider: .openAI) else {
            openAIError = APIKeyValidator.errorMessage(for: .openAI)
            openAIStatus = .invalid
            return
        }
        do {
            try keychain.saveWithBiometry(key: KeychainKeys.openAIAPIKey, value: openAIKey)
        } catch {
            try? keychain.save(key: KeychainKeys.openAIAPIKey, value: openAIKey)
        }
        openAIStatus = .configured
        openAIKey = ""
    }

    private func saveGeminiKey() {
        guard APIKeyValidator.validate(geminiKey, provider: .gemini) else {
            geminiError = APIKeyValidator.errorMessage(for: .gemini)
            geminiStatus = .invalid
            return
        }
        do {
            try keychain.save(key: KeychainKeys.geminiAPIKey, value: geminiKey)
        } catch {
            try? keychain.save(key: KeychainKeys.geminiAPIKey, value: geminiKey)
        }
        geminiStatus = .configured
        geminiKey = ""
    }

    private func performGoogleOAuthLogin() async {
        isGoogleOAuthLoggingIn = true
        defer { isGoogleOAuthLoggingIn = false }
        do {
            _ = try await googleOAuth.startOAuthFlow()
            isGoogleOAuthLoggedIn = true
        } catch {
            googleOAuthError = error.localizedDescription
        }
    }
}
