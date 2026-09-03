import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// MARK: - OnboardingView: Mail wizard page (provider, credentials, server, done)
// Split out of OnboardingView.swift to keep compile units small.

extension OnboardingView {
    // MARK: - Page 6: Mail Wizard

    var mailWizardPage: some View {
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
    var mailProviderStep: some View {
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
    var mailCredentialsStep: some View {
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
    var mailServerStep: some View {
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
    var mailDoneStep: some View {
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

    func applyMailPreset(_ provider: MailProvider) {
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

    func saveMailConfig() async {
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
}

enum MailProvider: String, CaseIterable {
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

enum MailWizardStep: Int, CaseIterable {
    case provider = 0
    case credentials = 1
    case serverConfig = 2
    case done = 3
}
