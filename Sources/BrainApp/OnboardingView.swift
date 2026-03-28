import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// Full onboarding flow for first-time users.
// Pages: Welcome → Features → Privacy → Provider Selection → API Key → Mail Wizard → Permissions → First Entry
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(DataBridge.self) private var dataBridge

    @State private var currentPage = 0
    // Provider selection
    @State private var selectedProvider: LLMProviderChoice = .anthropic
    @State private var apiKey = ""
    @State private var isValidatingKey = false
    @State private var keyValidationResult: KeyValidationResult?
    // Proxy config
    @State private var proxyURL = ""
    @State private var proxyUsername = ""
    @State private var proxyPassword = ""
    @State private var isLoggingInProxy = false
    // Permissions
    @State private var contactsGranted = false
    @State private var calendarGranted = false
    @State private var notificationsGranted = false
    @State private var firstThought = ""
    @State private var isSaving = false
    // Mail wizard state
    @State private var mailWizardStep: MailWizardStep = .provider
    @State private var mailProvider: MailProvider = .none
    @State private var mailAddress = ""
    @State private var mailPassword = ""
    @State private var mailImapHost = ""
    @State private var mailImapPort = "993"
    @State private var mailSmtpHost = ""
    @State private var mailSmtpPort = "587"
    @State private var isSavingMail = false
    @State private var mailSaveResult: KeyValidationResult?
    @State private var showKennenlernSheet = false
    @FocusState private var focusedField: OnboardingField?

    private let keychain = KeychainService()

    private enum OnboardingField {
        case apiKey, proxyURL, proxyUser, proxyPass
        case firstThought, mailAddress, mailPassword
        case mailImapHost, mailSmtpHost
    }

    private let totalPages = 9

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                    .background(BrainTheme.Gradients.purpleMist.ignoresSafeArea())
                featuresPage.tag(1)
                    .background(BrainTheme.Gradients.freshMint.ignoresSafeArea())
                privacyPage.tag(2)
                providerSelectionPage.tag(3)
                apiKeyPage.tag(4)
                mailWizardPage.tag(5)
                permissionsPage.tag(6)
                kennenlernPage.tag(7)
                firstEntryPage.tag(8)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(BrainTheme.Animations.springDefault, value: currentPage)

            // Page indicator at the very bottom, below all buttons
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? BrainTheme.Colors.brandPurple : Color(.systemGray4))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(BrainTheme.Animations.springSnappy, value: currentPage)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focusedField = nil }
        .onChange(of: currentPage) { _, _ in focusedField = nil }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrainHelpButton.onboarding
            }
        }
        .sheet(isPresented: $showKennenlernSheet) {
            NavigationStack {
                KennenlernDialogView()
                    .environment(dataBridge)
                    .navigationTitle("Kennenlernen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { showKennenlernSheet = false }
                        }
                    }
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(BrainTheme.Gradients.brand)
                .symbolEffect(.pulse)

            // Language selection
            Picker("Sprache", selection: Binding(
                get: { LocalizationService.shared.activeLocale },
                set: { newLang in
                    LocalizationService.shared.setLanguage(newLang, pool: dataBridge.db.pool)
                }
            )) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
                Text("Fran\u{00E7}ais").tag("fr")
                Text("Italiano").tag("it")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Text("Willkommen bei Brain")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Dein pers\u{00F6}nliches Gehirn auf dem iPhone.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            nextButton(page: 0)
        }
        .padding()
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Was Brain kann")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 20) {
                featureRow(icon: "brain", title: "Denkt mit", description: "KI-gestützte Analyse deiner Gedanken und Notizen")
                featureRow(icon: "magnifyingglass", title: "Findet alles", description: "Volltextsuche über alle Einträge und E-Mails")
                featureRow(icon: "lock.shield", title: "Deine Daten", description: "Alles bleibt auf deinem Gerät — kein Cloud-Zwang")
                featureRow(icon: "gearshape.2", title: "Lernt dazu", description: "Brain baut eigene Skills und verbessert sich selbst")
            }
            .padding(.horizontal)

            Spacer()

            nextButton(page: 1)
        }
        .padding()
    }

    // MARK: - Page 3: Privacy

    private var privacyPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("Datenschutz")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    privacyRow(icon: "iphone", text: "Alle Daten bleiben lokal auf deinem Gerät")
                    privacyRow(icon: "key.fill", text: "API-Keys werden im iOS Keychain gespeichert")
                    privacyRow(icon: "network.slash", text: "Offline-Nutzung ohne Einschränkungen")
                    privacyRow(icon: "arrow.up.right.circle", text: "Nur wenn du fragst, geht etwas an die KI-API")
                }
                .padding(.horizontal)
            }

            Spacer()

            nextButton(page: 2)
        }
        .padding()
    }

    // MARK: - Page 4: Provider Selection

    private var providerSelectionPage: some View {
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

    private func providerOption(provider: LLMProviderChoice, icon: String, name: String, description: String, color: Color, useAssetImage: Bool = false) -> some View {
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

    private var apiKeyPage: some View {
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

    private var apiKeyTitle: String {
        switch selectedProvider {
        case .anthropic: return "Claude API-Key"
        case .openAI: return "OpenAI API-Key"
        case .gemini: return "Gemini API-Key"
        case .xAI: return "xAI API-Key"
        case .proxy: return "Proxy-Server"
        }
    }

    private var apiKeySubtitle: String {
        switch selectedProvider {
        case .anthropic: return "Erstelle einen API-Key auf console.anthropic.com"
        case .openAI: return "Erstelle einen API-Key auf platform.openai.com"
        case .gemini: return "Erstelle einen API-Key in Google AI Studio"
        case .xAI: return "Erstelle einen API-Key auf console.x.ai"
        case .proxy: return "Gib die URL deines OpenAI-kompatiblen Proxy-Servers ein"
        }
    }

    private var apiKeyPlaceholder: String {
        switch selectedProvider {
        case .anthropic: return "sk-ant-..."
        case .openAI: return "sk-..."
        case .gemini: return "API-Key..."
        case .xAI: return "xai-..."
        case .proxy: return ""
        }
    }

    private var apiKeyInputView: some View {
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

    private var proxyConfigView: some View {
        VStack(spacing: 12) {
            TextField("https://mein-server.de", text: $proxyURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($focusedField, equals: .proxyURL)

            Text("Optionale Anmeldedaten (JWT-Auth)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Benutzername", text: $proxyUsername)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .proxyUser)

            SecureField("Passwort", text: $proxyPassword)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .proxyPass)

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

    // MARK: - Page 6: Mail Wizard

    private var mailWizardPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("E-Mail einrichten")
                .font(.title)
                .fontWeight(.bold)

            // Wizard progress
            HStack(spacing: 4) {
                ForEach(MailWizardStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step.rawValue <= mailWizardStep.rawValue ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
            }

            Group {
                switch mailWizardStep {
                case .provider: mailProviderStep
                case .credentials: mailCredentialsStep
                case .serverConfig: mailServerStep
                case .done: mailDoneStep
                }
            }
            .animation(.easeInOut, value: mailWizardStep)

            Spacer()

            if mailWizardStep != .done {
                Button("Überspringen") {
                    focusedField = nil
                    currentPage = 6  // skip to permissions
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            }
        }
        .padding()
    }

    // Step 1: Choose mail provider
    private var mailProviderStep: some View {
        VStack(spacing: 12) {
            Text("Welchen E-Mail-Anbieter nutzt du?")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(MailProvider.allCases.filter { $0 != .none }, id: \.self) { provider in
                Button {
                    withAnimation {
                        mailProvider = provider
                        applyMailPreset(provider)
                        mailWizardStep = .credentials
                    }
                } label: {
                    HStack {
                        Image(systemName: provider.icon)
                            .font(.title3)
                            .foregroundStyle(provider.color)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName).font(.headline).foregroundStyle(.primary)
                            Text(provider.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // Step 2: Email + Password
    private var mailCredentialsStep: some View {
        VStack(spacing: 16) {
            if mailProvider != .custom {
                HStack {
                    Image(systemName: mailProvider.icon)
                        .foregroundStyle(mailProvider.color)
                    Text(mailProvider.displayName)
                        .font(.headline)
                }
            }

            Text(mailProvider == .gmail
                ? "Verwende ein App-Passwort (nicht dein Google-Passwort)."
                : "Gib deine Zugangsdaten ein.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("E-Mail-Adresse", text: $mailAddress)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .focused($focusedField, equals: .mailAddress)

            SecureField(mailProvider == .gmail ? "App-Passwort" : "Passwort", text: $mailPassword)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .mailPassword)

            if let result = mailSaveResult {
                validationBanner(result)
            }

            HStack(spacing: 12) {
                Button("Zurück") {
                    focusedField = nil
                    withAnimation { mailWizardStep = .provider }
                }
                .buttonStyle(.bordered)

                Button {
                    focusedField = nil
                    if mailProvider == .custom {
                        withAnimation { mailWizardStep = .serverConfig }
                    } else {
                        Task { await saveMailConfig() }
                    }
                } label: {
                    HStack {
                        if isSavingMail { ProgressView().tint(.white) }
                        Text(mailProvider == .custom ? "Weiter" : "Verbinden")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mailAddress.isEmpty || mailPassword.isEmpty || isSavingMail)
            }
        }
        .padding(.horizontal)
    }

    // Step 3: Manual server config (only for custom)
    private var mailServerStep: some View {
        VStack(spacing: 12) {
            Text("IMAP/SMTP-Server")
                .font(.headline)

            Group {
                HStack(spacing: 8) {
                    TextField("IMAP-Server", text: $mailImapHost)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .mailImapHost)
                    TextField("Port", text: $mailImapPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 65)
                }

                HStack(spacing: 8) {
                    TextField("SMTP-Server", text: $mailSmtpHost)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .mailSmtpHost)
                    TextField("Port", text: $mailSmtpPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 65)
                }
            }

            if let result = mailSaveResult {
                validationBanner(result)
            }

            HStack(spacing: 12) {
                Button("Zurück") {
                    focusedField = nil
                    withAnimation { mailWizardStep = .credentials }
                }
                .buttonStyle(.bordered)

                Button {
                    focusedField = nil
                    Task { await saveMailConfig() }
                } label: {
                    HStack {
                        if isSavingMail { ProgressView().tint(.white) }
                        Text("Verbinden")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mailImapHost.isEmpty || isSavingMail)
            }
        }
        .padding(.horizontal)
    }

    // Step 4: Success
    private var mailDoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("E-Mail eingerichtet!")
                .font(.headline)

            Text("\(mailAddress)")
                .font(.callout)
                .foregroundStyle(.secondary)

            nextButton(page: 5)
        }
    }

    // MARK: - Page 7: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Berechtigungen")
                .font(.title)
                .fontWeight(.bold)

            Text("Brain funktioniert auch ohne — aber mit Zugriff kann es mehr.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                permissionButton(
                    icon: "person.crop.circle",
                    title: "Kontakte",
                    description: "Personen in Brain verknüpfen",
                    granted: contactsGranted
                ) {
                    await requestContacts()
                }

                permissionButton(
                    icon: "calendar",
                    title: "Kalender",
                    description: "Termine und Erinnerungen anzeigen",
                    granted: calendarGranted
                ) {
                    await requestCalendar()
                }

                permissionButton(
                    icon: "bell.fill",
                    title: "Benachrichtigungen",
                    description: "Erinnerungen und Briefings erhalten",
                    granted: notificationsGranted
                ) {
                    await requestNotifications()
                }
            }
            .padding(.horizontal)

            Spacer()

            nextButton(page: 6, title: "Weiter")
        }
        .padding()
    }

    // MARK: - Page 8: Kennenlernen

    private var kennenlernPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.wave.2")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            VStack(spacing: 12) {
                Text("Brain kennenlernen")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Brain kann Dich in einem kurzen Interview besser kennenlernen. So gibt es Dir persönlichere und hilfreichere Antworten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 12) {
                kennenlernFeature(icon: "brain.head.profile", text: "Brain fragt nach Name, Beruf, Hobbys und mehr")
                kennenlernFeature(icon: "lock.shield", text: "Antworten bleiben lokal auf deinem Gerät")
                kennenlernFeature(icon: "arrow.clockwise", text: "Jederzeit wiederholbar und aktualisierbar")
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showKennenlernSheet = true
                } label: {
                    Text("Interview starten")
                        .font(BrainTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrainTheme.Colors.brandPurple)
                .padding(.horizontal)

                Button {
                    focusedField = nil
                    withAnimation { currentPage = 8 }
                } label: {
                    Text("Überspringen")
                }
                .foregroundStyle(.secondary)

                Text("Du findest das Interview jederzeit unter\nMehr → Kennenlernen oder frag Brain im Chat:\n«Lerne mich kennen»")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    private func kennenlernFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.purple)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Page 9: First Entry

    private var firstEntryPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Dein erster Gedanke")
                .font(.title)
                .fontWeight(.bold)

            Text("Schreib einfach drauflos. Brain merkt sich alles.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Was beschäftigt dich gerade?", text: $firstThought, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .padding(.horizontal)
                .focused($focusedField, equals: .firstThought)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    focusedField = nil
                    Task { await saveAndFinish() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(firstThought.isEmpty ? "Los geht's!" : "Speichern & Los geht's!")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Components

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text).font(.callout)
        }
    }

    @ViewBuilder
    private func permissionButton(
        icon: String, title: String, description: String,
        granted: Bool, action: @escaping () async -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Erlauben") {
                    Task { await action() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func nextButton(page: Int, title: String = "Weiter") -> some View {
        Button {
            focusedField = nil
            withAnimation { currentPage = page + 1 }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
    }

    private func validationBanner(_ result: KeyValidationResult) -> some View {
        HStack {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isSuccess ? .green : .red)
            Text(result.message)
                .font(.caption)
                .foregroundStyle(result.isSuccess ? .green : .red)
        }
    }

    // MARK: - Actions

    private func validateAndSaveKey() async {
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

    private func validateAndSaveProxy() async {
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

            // If credentials provided, try proxy auth
            if !proxyUsername.isEmpty && !proxyPassword.isEmpty {
                let auth = BrainAPIAuthService.shared
                _ = try await auth.login(baseURL: trimmedURL, username: proxyUsername, password: proxyPassword)
            }

            // Test with a simple request
            let provider = AnthropicProvider(proxyURL: trimmedURL)
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

    private func requestContacts() async {
        let store = CNContactStore()
        do {
            contactsGranted = try await store.requestAccess(for: .contacts)
        } catch {
            contactsGranted = false
        }
    }

    private func requestCalendar() async {
        let store = EKEventStore()
        do {
            calendarGranted = try await store.requestFullAccessToEvents()
        } catch {
            calendarGranted = false
        }
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            notificationsGranted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            notificationsGranted = false
        }
    }

    private func applyMailPreset(_ provider: MailProvider) {
        switch provider {
        case .gmail:
            mailImapHost = "imap.gmail.com"
            mailSmtpHost = "smtp.gmail.com"
        case .outlook:
            mailImapHost = "outlook.office365.com"
            mailSmtpHost = "smtp.office365.com"
        case .icloud:
            mailImapHost = "imap.mail.me.com"
            mailSmtpHost = "smtp.mail.me.com"
        case .custom:
            mailImapHost = ""
            mailSmtpHost = ""
        case .none:
            break
        }
        mailImapPort = "993"
        mailSmtpPort = "587"
    }

    private func saveMailConfig() async {
        focusedField = nil
        isSavingMail = true
        mailSaveResult = nil
        defer { isSavingMail = false }

        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let smtp = mailSmtpHost.isEmpty ? mailImapHost.replacingOccurrences(of: "imap.", with: "smtp.") : mailSmtpHost
        let username = mailAddress

        do {
            try bridge.saveConfig(
                imapHost: mailImapHost,
                imapPort: Int(mailImapPort) ?? 993,
                smtpHost: smtp,
                smtpPort: Int(mailSmtpPort) ?? 587,
                username: username,
                password: mailPassword,
                address: mailAddress
            )
            mailSaveResult = KeyValidationResult(isSuccess: true, message: "E-Mail konfiguriert!")
            withAnimation { mailWizardStep = .done }
        } catch {
            mailSaveResult = KeyValidationResult(isSuccess: false, message: "Fehler: \(error.localizedDescription)")
        }
    }

    private func saveAndFinish() async {
        focusedField = nil
        isSaving = true
        defer { isSaving = false }

        if !firstThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try? dataBridge.createEntry(title: firstThought)
        }

        hasCompletedOnboarding = true
    }
}

// MARK: - Supporting types

private struct KeyValidationResult {
    let isSuccess: Bool
    let message: String
}

enum LLMProviderChoice: String, CaseIterable {
    case anthropic
    case openAI
    case gemini
    case xAI
    case proxy
}

private enum MailProvider: String, CaseIterable {
    case none
    case gmail
    case outlook
    case icloud
    case custom

    var displayName: String {
        switch self {
        case .none: return ""
        case .gmail: return "Gmail"
        case .outlook: return "Outlook / Microsoft 365"
        case .icloud: return "iCloud Mail"
        case .custom: return "Anderer Anbieter"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return ""
        case .gmail: return "Benötigt ein App-Passwort"
        case .outlook: return "Outlook, Hotmail, Live.com"
        case .icloud: return "me.com, icloud.com"
        case .custom: return "Eigenen IMAP/SMTP-Server eingeben"
        }
    }

    var icon: String {
        switch self {
        case .none: return "envelope"
        case .gmail: return "envelope.fill"
        case .outlook: return "envelope.badge.fill"
        case .icloud: return "icloud"
        case .custom: return "server.rack"
        }
    }

    var color: Color {
        switch self {
        case .none: return .gray
        case .gmail: return .red
        case .outlook: return .blue
        case .icloud: return .cyan
        case .custom: return .gray
        }
    }
}

private enum MailWizardStep: Int, CaseIterable {
    case provider = 0
    case credentials = 1
    case serverConfig = 2
    case done = 3
}
