import SwiftUI
import BrainCore
import GRDB

// MARK: - Mail Config Form (for adding a new account)

struct MailConfigFormView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    var onAccountCreated: (() -> Void)?
    @State private var accountName = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var username = ""
    @State private var password = ""
    @State private var address = ""
    @State private var isSaving = false
    @State private var saveResult: String?
    @State private var saveSuccess = false
    @FocusState private var focusedField: MailField?

    private enum MailField {
        case name, imapHost, smtpHost, username, password, address
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("E-Mail einrichten")
                    .font(.title)
                    .fontWeight(.bold)

                Text("IMAP/SMTP für E-Mail-Integration konfigurieren.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Quick setup
                HStack(spacing: 8) {
                    Button("Gmail") { prefill(name: "Gmail", imap: "imap.gmail.com", smtp: "smtp.gmail.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Outlook") { prefill(name: "Outlook", imap: "outlook.office365.com", smtp: "smtp.office365.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("iCloud") { prefill(name: "iCloud", imap: "imap.mail.me.com", smtp: "smtp.mail.me.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                VStack(spacing: 10) {
                    TextField("Konto-Name (z.B. Gmail Privat)", text: $accountName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)

                    HStack(spacing: 8) {
                        TextField("IMAP-Server", text: $imapHost)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .imapHost)
                        TextField("Port", text: $imapPort)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    HStack(spacing: 8) {
                        TextField("SMTP-Server", text: $smtpHost)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .smtpHost)
                        TextField("Port", text: $smtpPort)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    TextField("Benutzername / E-Mail", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .username)

                    SecureField("Passwort", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)

                    TextField("Absender-Adresse (optional)", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .address)
                }
                .padding(.horizontal)

                if let result = saveResult {
                    HStack {
                        Image(systemName: saveSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(saveSuccess ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(saveSuccess ? .green : .red)
                    }
                }

                Button {
                    focusedField = nil
                    Task { await saveConfig() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text("Speichern & Testen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(imapHost.isEmpty || username.isEmpty || password.isEmpty || isSaving)
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {

        }
    }

    private func prefill(name: String, imap: String, smtp: String) {
        accountName = name
        imapHost = imap
        smtpHost = smtp
        imapPort = "993"
        smtpPort = "587"
    }

    private func saveConfig() async {
        isSaving = true
        saveResult = nil
        saveSuccess = false
        defer { isSaving = false }

        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let smtp = smtpHost.isEmpty ? imapHost.replacingOccurrences(of: "imap.", with: "smtp.") : smtpHost
        let addr = address.isEmpty ? username : address
        let name = accountName.isEmpty ? (addr.components(separatedBy: "@").last?.components(separatedBy: ".").first?.capitalized ?? "E-Mail") : accountName

        do {
            // Test IMAP connection BEFORE creating the account
            try await bridge.testIMAPConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                username: username,
                password: password
            )

            // Connection OK — now create the account
            let account = try bridge.createAccount(
                name: name,
                emailAddress: addr,
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                smtpHost: smtp,
                smtpPort: Int(smtpPort) ?? 587,
                username: username,
                password: password
            )

            // Sync emails in background
            Task {
                _ = try? await bridge.sync(limit: 10, accountId: account.id)
            }

            // Show success, then notify and switch to inbox after a short delay
            await MainActor.run {
                saveResult = "Verbindung erfolgreich! Konto wurde erstellt."
                saveSuccess = true
            }
            // Give user time to see the success message
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                NotificationCenter.default.post(name: .emailConfigured, object: nil)
                isConfigured = true
                onAccountCreated?()
            }
        } catch {
            // Auth failed — account was NOT created, form stays open
            saveResult = "Fehler: \(error.localizedDescription)"
            saveSuccess = false
        }
    }
}
