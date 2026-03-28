import SwiftUI
import UniformTypeIdentifiers
import BrainCore

// Phase 21: Share Extension — Save content from any app into Brain.
// Accepts: Text, URLs, Images (as text description).
// Uses App Group shared database for persistence.

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Host the SwiftUI share view
        let shareView = ShareExtensionView(
            onSave: { [weak self] title, type, body in
                self?.saveEntry(title: title, type: type, body: body)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)

        // Extract shared content
        extractSharedContent()
    }

    private func extractSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Plain text
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        if let text = data as? String {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .sharedContentReceived,
                                    object: nil,
                                    userInfo: ["text": text, "type": "text"]
                                )
                            }
                        }
                    }
                }

                // URL
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        if let url = data as? URL {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .sharedContentReceived,
                                    object: nil,
                                    userInfo: ["text": url.absoluteString, "type": "url"]
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func saveEntry(title: String, type: String, body: String?) {
        do {
            let db = try SharedContainer.makeDatabaseManager()
            let entryService = EntryService(pool: db.pool)
            let entryType = EntryType(rawValue: type) ?? .thought
            let _ = try entryService.create(
                Entry(type: entryType, title: title, body: body, source: .shareSheet)
            )
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    let onSave: (String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var entryType = "thought"
    @State private var sharedText = ""

    private let types = ["thought", "task", "note"]
    private let typeLabels = ["thought": "Gedanke", "task": "Aufgabe", "note": "Notiz"]

    var body: some View {
        NavigationStack {
            Form {
                Section("In Brain speichern") {
                    Picker("Typ", selection: $entryType) {
                        ForEach(types, id: \.self) { type in
                            Text(typeLabels[type] ?? type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Titel", text: $title)

                    if !sharedText.isEmpty {
                        Text(sharedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }

                    TextField("Notizen (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Brain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let entryTitle = title.isEmpty ? sharedText : title
                        let entryBody = title.isEmpty ? nil : (notes.isEmpty ? sharedText : notes)
                        onSave(entryTitle, entryType, entryBody)
                    }
                    .disabled(title.isEmpty && sharedText.isEmpty)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharedContentReceived)) { notification in
                if let text = notification.userInfo?["text"] as? String {
                    sharedText = text
                    if title.isEmpty {
                        // Auto-fill title from first line or truncate
                        let firstLine = text.components(separatedBy: .newlines).first ?? text
                        title = String(firstLine.prefix(100))
                    }
                }
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let sharedContentReceived = Notification.Name("sharedContentReceived")
}
