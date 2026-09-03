import SwiftUI
import BrainCore
import GRDB

// MARK: - Mail Accounts Settings View (manage all accounts)

struct MailAccountsSettingsView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    let onChanged: () -> Void
    @State private var accounts: [EmailAccount] = []
    @State private var showAddAccount = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                ForEach(accounts) { account in
                    NavigationLink {
                        MailSettingsView(
                            dataBridge: dataBridge,
                            isConfigured: $isConfigured,
                            accountId: account.id,
                            onChanged: {
                                loadAccounts()
                                onChanged()
                            }
                        )
                        .navigationTitle(account.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(account.name)
                                .fontWeight(.medium)
                            Text(account.emailAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    accounts.move(fromOffsets: source, toOffset: destination)
                    saveSortOrder()
                }
            } footer: {
                if accounts.count > 1 {
                    Text("Zum Sortieren gedrückt halten und ziehen.")
                }
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
            }
        }
        .environment(\.editMode, $editMode)
        .task {
            loadAccounts()
        }
        .toolbar {
            if accounts.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddAccount) {
            NavigationStack {
                MailConfigFormView(
                    dataBridge: dataBridge,
                    isConfigured: $isConfigured,
                    onAccountCreated: {
                        loadAccounts()
                        onChanged()
                        showAddAccount = false
                    }
                )
                .navigationTitle("Konto hinzufügen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showAddAccount = false }
                    }
                }
            }
        }
    }

    private func loadAccounts() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        accounts = (try? bridge.listAccounts()) ?? []
    }

    private func saveSortOrder() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let orderedIds = accounts.map(\.id)
        try? bridge.updateSortOrders(orderedIds)
        onChanged()
    }
}

// MARK: - Mail Settings View (edit single account)

struct MailSettingsView: View {
    let dataBridge: DataBridge
    @Binding var isConfigured: Bool
    let accountId: String?
    var onChanged: (() -> Void)?
    @State private var accountName = ""
    @State private var imapHost = ""
    @State private var imapPort = ""
    @State private var smtpHost = ""
    @State private var smtpPort = ""
    @State private var username = ""
    @State private var password = ""
    @State private var address = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusSuccess = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Konto") {
                TextField("Konto-Name", text: $accountName)
            }

            Section("Eingehend (IMAP)") {
                TextField("IMAP-Server", text: $imapHost)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Port", text: $imapPort)
                    .keyboardType(.numberPad)
            }

            Section("Ausgehend (SMTP)") {
                TextField("SMTP-Server", text: $smtpHost)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Port", text: $smtpPort)
                    .keyboardType(.numberPad)
            }

            Section("Anmeldedaten") {
                TextField("Benutzername / E-Mail", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Passwort", text: $password)
                TextField("Absender-Adresse", text: $address)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section("Schnelleinrichtung") {
                HStack(spacing: 8) {
                    Button("Gmail") { prefill(imap: "imap.gmail.com", smtp: "smtp.gmail.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Outlook") { prefill(imap: "outlook.office365.com", smtp: "smtp.office365.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("iCloud") { prefill(imap: "imap.mail.me.com", smtp: "smtp.mail.me.com") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            if let msg = statusMessage {
                Section {
                    HStack {
                        Image(systemName: statusSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(statusSuccess ? .green : .red)
                        Text(msg)
                            .font(.callout)
                    }
                }
            }

            Section {
                Button {
                    Task { await testAndSave() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Testen & Speichern")
                        Spacer()
                    }
                }
                .disabled(imapHost.isEmpty || username.isEmpty || password.isEmpty || isTesting)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("E-Mail-Konto entfernen", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("E-Mail-Konto wirklich entfernen?", isPresented: $showDeleteConfirmation) {
            Button("Entfernen", role: .destructive) {
                if let accountId {
                    let bridge = EmailBridge(pool: dataBridge.db.pool)
                    try? bridge.deleteAccount(id: accountId)
                    let remaining = (try? bridge.listAccounts()) ?? []
                    isConfigured = !remaining.isEmpty
                    onChanged?()
                }
            }
        }
        .onAppear {
            loadExistingConfig()
        }
    }

    private func prefill(imap: String, smtp: String) {
        imapHost = imap
        smtpHost = smtp
        imapPort = "993"
        smtpPort = "587"
    }

    private func loadExistingConfig() {
        guard let accountId else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        guard let (account, _) = try? bridge.loadAccountConfig(id: accountId) else { return }
        accountName = account.name
        imapHost = account.imapHost
        imapPort = "\(account.imapPort)"
        smtpHost = account.smtpHost
        smtpPort = "\(account.smtpPort)"
        username = account.username
        address = account.emailAddress
        // Don't load password for security
    }

    private func testAndSave() async {
        isTesting = true
        statusMessage = nil
        statusSuccess = false
        defer { isTesting = false }

        guard let accountId else { return }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        let smtp = smtpHost.isEmpty ? imapHost.replacingOccurrences(of: "imap.", with: "smtp.") : smtpHost
        let addr = address.isEmpty ? username : address
        let effectivePassword: String
        if password.isEmpty {
            // Use existing password from keychain
            guard let existing = try? bridge.loadAccountConfig(id: accountId).password else {
                statusMessage = "Fehler: Kein Passwort gespeichert."
                statusSuccess = false
                return
            }
            effectivePassword = existing
        } else {
            effectivePassword = password
        }

        do {
            // Test connection first
            try await bridge.testIMAPConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                username: username,
                password: effectivePassword
            )

            // Connection OK — save changes
            var account = EmailAccount(
                id: accountId,
                name: accountName.isEmpty ? "E-Mail" : accountName,
                emailAddress: addr,
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                smtpHost: smtp,
                smtpPort: Int(smtpPort) ?? 587,
                username: username
            )
            if let existing = try? bridge.loadAccountConfig(id: accountId).account {
                account.sortOrder = existing.sortOrder
            }

            try bridge.updateAccount(account, password: password.isEmpty ? nil : password)
            statusMessage = "Verbindung OK! Einstellungen gespeichert."
            statusSuccess = true
            isConfigured = true
            // Show success for 2 seconds before notifying parent
            try? await Task.sleep(for: .seconds(2))
            onChanged?()
        } catch {
            statusMessage = "Fehler: \(error.localizedDescription)"
            statusSuccess = false
        }
    }
}
