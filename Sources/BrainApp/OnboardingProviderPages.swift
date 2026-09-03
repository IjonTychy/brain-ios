import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// MARK: - OnboardingView: LLM provider selection and API key / proxy setup
// Split out of OnboardingView.swift to keep compile units small.

extension OnboardingView {
    // MARK: - Page 4: Provider Selection

    var providerSelectionPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("KI-Anbieter wählen")
                .font(.title)
                .fontWeight(.bold)

            Text("Brain unterstützt mehrere KI-Anbieter. Du brauchst einen eigenen API-Key.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                providerOption(
                    provider: .anthropic,
                    icon: "provider-anthropic",
                    name: "Anthropic (Claude)",
                    description: "Empfohlen — bestes Modell für Brain",
                    color: .orange,
                    useAssetImage: true
                )
                providerOption(
                    provider: .openAI,
                    icon: "provider-openai",
                    name: "OpenAI (GPT)",
                    description: "GPT-4o und GPT-4o Mini",
                    color: .green,
                    useAssetImage: true
                )
                providerOption(
                    provider: .gemini,
                    icon: "provider-google",
                    name: "Google (Gemini)",
                    description: "Gemini 2.5 Pro und Flash",
                    color: .blue,
                    useAssetImage: true
                )
                providerOption(
                    provider: .xAI,
                    icon: "provider-xai",
                    name: "xAI (Grok)",
                    description: "Grok 4 und Grok 4.1 Fast",
                    color: .purple,
                    useAssetImage: true
                )
                providerOption(
                    provider: .proxy,
                    icon: "server.rack",
                    name: "Eigener Proxy",
                    description: "Selbst-gehostetes LLM (OpenAI-kompatibel)",
                    color: .gray
                )
            }
            .padding(.horizontal)

            Spacer()

            Button {
                focusedField = nil
                withAnimation { currentPage = 4 }
            } label: {
                Text("Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Button("Ohne KI starten") {
                focusedField = nil
                currentPage = 5  // skip to mail
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
        .padding()
    }

    func providerOption(provider: LLMProviderChoice, icon: String, name: String, description: String, color: Color, useAssetImage: Bool = false) -> some View {
        Button {
            withAnimation {
                selectedProvider = provider
                apiKey = ""
                keyValidationResult = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(.primary)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if selectedProvider == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedProvider == provider ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedProvider == provider ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 5: API Key Entry

    var apiKeyPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text(apiKeyTitle)
                    .font(.title)
                    .fontWeight(.bold)

                Text(apiKeySubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if selectedProvider == .proxy {
                    proxyConfigView
                } else {
                    apiKeyInputView
                }

                Spacer(minLength: 20)

                Button("Überspringen") {
                    focusedField = nil
                    currentPage = 5  // skip to mail
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

                if keyValidationResult?.isSuccess == true {
                    nextButton(page: 4)
                }
            }
            .padding()
        }
    }

    var apiKeyTitle: String {
        switch selectedProvider {
        case .anthropic: return "Claude API-Key"
        case .openAI: return "OpenAI API-Key"
        case .gemini: return "Gemini API-Key"
        case .xAI: return "xAI API-Key"
        case .proxy: return "Proxy-Server"
        }
    }

    var apiKeySubtitle: String {
        switch selectedProvider {
        case .anthropic: return "Erstelle einen API-Key auf console.anthropic.com"
        case .openAI: return "Erstelle einen API-Key auf platform.openai.com"
        case .gemini: return "Erstelle einen API-Key in Google AI Studio"
        case .xAI: return "Erstelle einen API-Key auf console.x.ai"
        case .proxy: return "Gib die URL deines OpenAI-kompatiblen Proxy-Servers ein"
        }
    }

    var apiKeyPlaceholder: String {
        switch selectedProvider {
        case .anthropic: return "sk-ant-..."
        case .openAI: return "sk-..."
        case .gemini: return "API-Key..."
        case .xAI: return "xai-..."
        case .proxy: return ""
        }
    }

    var apiKeyInputView: some View {
        VStack(spacing: 12) {
            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .apiKey)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }

            if let result = keyValidationResult {
                validationBanner(result)
            }

            Button {
                focusedField = nil
                Task { await validateAndSaveKey() }
            } label: {
                HStack {
                    if isValidatingKey { ProgressView().tint(.white) }
                    Text("Testen & Speichern")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty || isValidatingKey)
        }
        .padding(.horizontal)
    }

    var proxyConfigView: some View {
        VStack(spacing: 12) {
            TextField("https://mein-server.de", text: $proxyURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($focusedField, equals: .proxyURL)

            Text("OpenAI-kompatibler Endpoint, selbst gehostet (z.B. LiteLLM, vLLM, Ollama)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let result = keyValidationResult {
                validationBanner(result)
            }

            Button {
                focusedField = nil
                Task { await validateAndSaveProxy() }
            } label: {
                HStack {
                    if isValidatingKey { ProgressView().tint(.white) }
                    Text("Verbindung testen")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(proxyURL.isEmpty || isValidatingKey)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    func validateAndSaveKey() async {
        focusedField = nil
        isValidatingKey = true
        keyValidationResult = nil
        defer { isValidatingKey = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            keyValidationResult = KeyValidationResult(isSuccess: false, message: "Bitte einen API-Key eingeben.")
            return
        }

        // Build provider for selected type
        let keychainKey: String
        let testProvider: any LLMProvider

        switch selectedProvider {
        case .anthropic:
            guard APIKeyValidator.validate(trimmedKey, provider: .anthropic) else {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: APIKeyValidator.errorMessage(for: .anthropic))
                return
            }
            keychainKey = KeychainKeys.anthropicAPIKey
            testProvider = AnthropicProvider(apiKey: trimmedKey)
        case .openAI:
            if trimmedKey.count < 8 {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "API-Key zu kurz. Bitte vollstaendigen Key eingeben.")
                return
            }
            keychainKey = KeychainKeys.openAIAPIKey
            testProvider = OpenAIProvider(apiKey: trimmedKey)
        case .gemini:
            if trimmedKey.count < 8 {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "API-Key zu kurz. Bitte vollstaendigen Key eingeben.")
                return
            }
            keychainKey = KeychainKeys.geminiAPIKey
            testProvider = GeminiProvider(apiKey: trimmedKey)
        case .xAI:
            if trimmedKey.count < 8 {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "API-Key zu kurz. Bitte vollstaendigen Key eingeben.")
                return
            }
            keychainKey = KeychainKeys.xaiAPIKey
            testProvider = OpenAICompatibleProvider(baseURL: "https://api.x.ai/v1", model: "grok-3-fast", apiKey: trimmedKey, providerName: "xAI")
        case .proxy:
            return  // proxy is handled separately
        }

        let testRequest = LLMRequest(
            messages: [LLMMessage(role: "user", content: "Sag 'OK'.")],
            maxTokens: 10
        )

        do {
            let response = try await testProvider.complete(testRequest)
            if !response.content.isEmpty {
                try keychain.save(key: keychainKey, value: trimmedKey)
                apiKey = trimmedKey
                keyValidationResult = KeyValidationResult(isSuccess: true, message: "API-Key gültig und gespeichert!")
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { currentPage = 5 }
            } else {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "Leere Antwort — Key prüfen")
            }
        } catch let error as LLMProviderError {
            switch error {
            case .apiError(let statusCode, let body):
                if statusCode == 401 {
                    keyValidationResult = KeyValidationResult(isSuccess: false, message: "API-Key ungültig (401 Unauthorized)")
                } else if statusCode == 403 {
                    keyValidationResult = KeyValidationResult(isSuccess: false, message: "Zugriff verweigert (403) — Key-Berechtigungen prüfen")
                } else {
                    let shortBody = String(body.prefix(100))
                    keyValidationResult = KeyValidationResult(isSuccess: false, message: "API-Fehler \(statusCode): \(shortBody)")
                }
            default:
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "Fehler: \(error.localizedDescription)")
            }
        } catch {
            keyValidationResult = KeyValidationResult(isSuccess: false, message: "Verbindungsfehler: \(error.localizedDescription)")
        }
    }

    func validateAndSaveProxy() async {
        focusedField = nil
        isValidatingKey = true
        keyValidationResult = nil
        defer { isValidatingKey = false }

        let trimmedURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            keyValidationResult = KeyValidationResult(isSuccess: false, message: "Bitte eine Proxy-URL eingeben.")
            return
        }

        do {
            try keychain.save(key: KeychainKeys.anthropicProxyURL, value: trimmedURL)

            // Test with a simple request
            let base = trimmedURL.hasSuffix("/") ? String(trimmedURL.dropLast()) : trimmedURL
            let provider = AnthropicProvider(proxyURL: base)
            let testRequest = LLMRequest(
                messages: [LLMMessage(role: "user", content: "Sag 'OK'.")],
                maxTokens: 10
            )
            let response = try await provider.complete(testRequest)
            if !response.content.isEmpty {
                keyValidationResult = KeyValidationResult(isSuccess: true, message: "Proxy verbunden!")
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { currentPage = 5 }
            } else {
                keyValidationResult = KeyValidationResult(isSuccess: false, message: "Leere Antwort vom Proxy")
            }
        } catch {
            keyValidationResult = KeyValidationResult(isSuccess: false, message: "Proxy-Fehler: \(error.localizedDescription)")
        }
    }
}
