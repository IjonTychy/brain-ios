import SwiftUI
import BrainCore
import GRDB

// Native mail tab: multi-account mailbox view with folder navigation,
// email list with detail view, compose/reply/forward support.
struct MailTabView: View {
    let dataBridge: DataBridge
    @State private var isConfigured: Bool
    @State private var showSettings = false
    @State private var accounts: [EmailAccount] = []

    init(dataBridge: DataBridge) {
        self.dataBridge = dataBridge
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        _isConfigured = State(initialValue: bridge.isConfigured)
    }

    var body: some View {
        Group {
            if isConfigured {
                MailMailboxesView(dataBridge: dataBridge, accounts: accounts, showSettings: $showSettings)
            } else {
                MailConfigFormView(dataBridge: dataBridge, isConfigured: $isConfigured)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailConfigured)) { _ in
            isConfigured = true
            loadAccounts()
        }
        .tint(BrainTheme.Colors.brandPurple)
        .task {
            let bridge = EmailBridge(pool: dataBridge.db.pool)
            try? bridge.migrateFromSingleAccountIfNeeded()
            loadAccounts()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                MailAccountsSettingsView(dataBridge: dataBridge, isConfigured: $isConfigured) {
                    loadAccounts()
                }
                .navigationTitle("E-Mail Konten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") { showSettings = false }
                    }
                }
            }
        }
    }

    private func loadAccounts() {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        accounts = (try? bridge.listAccounts()) ?? []
        isConfigured = !accounts.isEmpty
    }
}
