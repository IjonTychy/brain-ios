import SwiftUI
import BrainCore

// Full email view with reply/forward/delete/move actions.
struct MailDetailView: View {
    let dataBridge: DataBridge
    let emailId: Int64
    @State private var email: EmailCache?
    @State private var isLoading = true
    @State private var showCompose = false
    @State private var composeMode: MailComposeView.Mode = .new(accountId: nil)
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade E-Mail...")
            } else if let email {
                emailContent(email)
            } else {
                ContentUnavailableView(
                    "E-Mail nicht gefunden",
                    systemImage: "envelope.badge.exclamationmark",
                    description: Text("Diese E-Mail konnte nicht geladen werden.")
                )
            }
        }
        .navigationTitle(email?.subject ?? "E-Mail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let email {
                    BrainAvatarButton(context: .forEmail(
                        subject: email.subject ?? "",
                        from: email.fromAddr ?? "",
                        body: email.bodyPlain ?? ""
                    ))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if email != nil {
                    Menu {
                        Button {
                            if let email {
                                composeMode = .reply(email: email)
                                showCompose = true
                            }
                        } label: {
                            Label("Antworten", systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            if let email {
                                composeMode = .forward(email: email)
                                showCompose = true
                            }
                        } label: {
                            Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
                        }
                        Button {
                            showMoveSheet = true
                        } label: {
                            Label("Verschieben", systemImage: "folder")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadEmail()
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                MailComposeView(dataBridge: dataBridge, mode: composeMode)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            NavigationStack {
                MailFolderPickerView(dataBridge: dataBridge, emailId: emailId) {
                    dismiss()
                }
            }
        }
        .confirmationDialog("E-Mail löschen?", isPresented: $showDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                Task { await deleteEmail() }
            }
        }
        .alert("Fehler", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func emailContent(_ email: EmailCache) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(email.subject ?? "Kein Betreff")
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(alignment: .top) {
                        // Sender avatar
                        let initials = emailInitials(email.fromAddr ?? "")
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Text(initials)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(email.fromAddr ?? "Unbekannt")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let to = email.toAddr, !to.isEmpty {
                                Text("An: \(to)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let dateStr = email.date {
                            Text(formatDate(dateStr))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.horizontal)

                // Body
                if let body = email.bodyPlain, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                } else {
                    Text("Kein Inhalt")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                if email.hasAttachments {
                    HStack {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Text("Anhänge vorhanden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Quick action buttons
                Divider()
                    .padding(.horizontal)
                HStack(spacing: 16) {
                    Button {
                        composeMode = .reply(email: email)
                        showCompose = true
                    } label: {
                        Label("Antworten", systemImage: "arrowshape.turn.up.left")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        composeMode = .forward(email: email)
                        showCompose = true
                    } label: {
                        Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Spacer(minLength: 60)
            }
        }
    }

    private func loadEmail() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        email = try? bridge.fetchEmail(id: emailId)
        isLoading = false

        // Mark as read
        if let email, !email.isRead {
            try? bridge.markRead(id: emailId)
            self.email?.isRead = true
            if let messageId = email.messageId {
                try? await bridge.markReadOnServer(messageId: messageId, accountId: email.accountId)
            }
        }
    }

    private func deleteEmail() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        do {
            try await bridge.deleteMessage(emailCacheId: emailId)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func emailInitials(_ address: String) -> String {
        let name = address.components(separatedBy: "@").first ?? address
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func formatDate(_ dateStr: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: dateStr) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_CH")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return dateStr
    }
}

// MARK: - Folder Picker for moving emails

struct MailFolderPickerView: View {
    let dataBridge: DataBridge
    let emailId: Int64
    let onMoved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isMoving = false
    @State private var moveError: String?
    @State private var extraFolders: [String] = []

    var body: some View {
        List {
            Section("Standard") {
                ForEach(MailMailboxesView.standardFolders, id: \.key) { folder in
                    Button {
                        Task { await moveToFolder(folder.key) }
                    } label: {
                        Label(folder.label, systemImage: folder.icon)
                    }
                    .disabled(isMoving)
                }
            }

            if !extraFolders.isEmpty {
                Section("Weitere Ordner") {
                    ForEach(extraFolders, id: \.self) { folderName in
                        Button {
                            Task { await moveToFolder(folderName) }
                        } label: {
                            Label(folderName, systemImage: "folder.fill")
                        }
                        .disabled(isMoving)
                    }
                }
            }
        }
        .navigationTitle("Verschieben nach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
        .overlay {
            if isMoving {
                ProgressView("Verschiebe...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Fehler", isPresented: .constant(moveError != nil)) {
            Button("OK") { moveError = nil }
        } message: {
            Text(moveError ?? "")
        }
        .task { await loadServerFolders() }
    }

    private func moveToFolder(_ folder: String) async {
        isMoving = true
        defer { isMoving = false }
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        do {
            try await bridge.moveMessage(emailCacheId: emailId, toFolder: folder)
            dismiss()
            onMoved()
        } catch {
            moveError = error.localizedDescription
        }
    }

    private func loadServerFolders() async {
        let bridge = EmailBridge(pool: dataBridge.db.pool)
        // Get accountId from the email being moved
        guard let email = try? bridge.fetchEmail(id: emailId),
              let accountId = email.accountId else { return }
        guard let folders = try? await bridge.listFolders(accountId: accountId) else { return }
        let standardKeys = Set(MailMailboxesView.standardFolders.map { $0.key.lowercased() })
        let extras = folders.map(\.0).filter { !standardKeys.contains($0.lowercased()) }.sorted()
        await MainActor.run { extraFolders = extras }
    }
}
