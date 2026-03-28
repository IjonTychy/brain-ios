import SwiftUI
import BrainCore

// Compose view for new emails, replies, and forwards.
struct MailComposeView: View {
    let dataBridge: DataBridge
    let mode: Mode
    @State private var toAddress = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var sendSuccess = false
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case new(accountId: String?)
        case reply(email: EmailCache)
        case forward(email: EmailCache)

        var accountId: String? {
            switch self {
            case .new(let accountId): return accountId
            case .reply(let email): return email.accountId
            case .forward(let email): return email.accountId
            }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("An", text: $toAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Betreff", text: $subject)
            }

            Section {
                TextEditor(text: $messageBody)
                    .frame(minHeight: 200)
            }

            if let error = sendError {
                Section {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await sendEmail() }
                } label: {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(toAddress.isEmpty || subject.isEmpty || isSending)
            }

        }
        .onAppear {
            prefillFromMode()
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .new: return "Neue E-Mail"
        case .reply: return "Antworten"
        case .forward: return "Weiterleiten"
        }
    }

    private func prefillFromMode() {
        switch mode {
        case .new:
            break
        case .reply(let email):
            toAddress = email.fromAddr ?? ""
            let originalSubject = email.subject ?? ""
            subject = originalSubject.hasPrefix("Re: ") ? originalSubject : "Re: \(originalSubject)"
            let quotedBody = (email.bodyPlain ?? "")
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            let from = email.fromAddr ?? "Unbekannt"
            let date = email.date ?? ""
            messageBody = "\n\n---\nAm \(date) schrieb \(from):\n\(quotedBody)"
        case .forward(let email):
            let originalSubject = email.subject ?? ""
            subject = originalSubject.hasPrefix("Fwd: ") ? originalSubject : "Fwd: \(originalSubject)"
            let from = email.fromAddr ?? "Unbekannt"
            let to = email.toAddr ?? ""
            let date = email.date ?? ""
            messageBody = "\n\n---\nWeitergeleitete Nachricht:\nVon: \(from)\nAn: \(to)\nDatum: \(date)\nBetreff: \(originalSubject)\n\n\(email.bodyPlain ?? "")"
        }
    }

    private func sendEmail() async {
        isSending = true
        sendError = nil
        defer { isSending = false }

        let bridge = EmailBridge(pool: dataBridge.db.pool)
        do {
            try await bridge.send(
                to: toAddress,
                subject: subject,
                body: messageBody,
                accountId: mode.accountId
            )
            sendSuccess = true
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }
}
