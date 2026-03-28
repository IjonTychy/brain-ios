import SwiftUI
import PhotosUI
import BrainCore
import GRDB

// User Profile and Brain Profile views.
// Users can describe themselves (preferences, family, ethics) and customize Brain's personality
// in free-form Markdown. The content is parsed into Knowledge Facts for the LLM context.

// MARK: - User Profile

struct UserProfileView: View {
    @AppStorage("userProfileMarkdown") private var profileMarkdown = ""
    @State private var isEditing = false
    @State private var editText = ""
    @State private var savedToast = false
    @Environment(DataBridge.self) private var dataBridge

    private let placeholder = """
    # Über mich

    ## Persönliches
    - Name:
    - Wohnort:
    - Sprachen:
    - Geburtstag:

    ## Familie
    - Partner/in:
    - Kinder:

    ## Beruf
    - Tätigkeit:
    - Arbeitgeber:
    - Fachgebiete:

    ## Interessen & Hobbys
    -

    ## Präferenzen
    - Kommunikationsstil:
    - Lieblings-Themen:
    - Abneigungen:

    ## Ethik & Werte
    - Wichtige Prinzipien:
    - Sensible Themen:

    ## Gesundheit (optional)
    - Allergien:
    - Besonderheiten:
    """

    var body: some View {
        List {
            if isEditing {
                Section {
                    TextEditor(text: $editText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 400)
                }
                Section {
                    Button("Speichern") {
                        profileMarkdown = editText
                        parseProfileToKnowledgeFacts(editText)
                        isEditing = false
                        savedToast = true
                    }
                    Button("Abbrechen", role: .cancel) {
                        isEditing = false
                    }
                }
            } else {
                if profileMarkdown.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 40))
                                .symbolEffect(.pulse, options: .speed(0.3))
                                .foregroundStyle(.blue)
                            Text("Dein Profil")
                                .font(.headline)
                            Text("Beschreibe Dich in Markdown — Brain lernt Dich so besser kennen. Diese Infos bleiben lokal auf Deinem Gerät.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }
                    Section {
                        Button("Profil erstellen") {
                            editText = placeholder
                            isEditing = true
                        }
                    }
                } else {
                    Section("Dein Profil") {
                        Text(profileMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Section {
                        Button("Bearbeiten") {
                            editText = profileMarkdown
                            isEditing = true
                        }
                    }
                }

                // Show extracted facts
                let facts = loadUserFacts()
                if !facts.isEmpty {
                    Section("Erkannte Fakten (\(facts.count))") {
                        ForEach(facts, id: \.id) { fact in
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.purple)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.predicate ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(fact.object ?? "")
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mein Profil")
        .overlay(alignment: .bottom) {
            if savedToast {
                Text("Profil gespeichert & Fakten extrahiert")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.move(edge: .bottom))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await MainActor.run { savedToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: savedToast)
    }

    private func loadUserFacts() -> [KnowledgeFact] {
        (try? dataBridge.db.pool.read { db in
            try KnowledgeFact
                .filter(Column("subject") == "User")
                .filter(Column("sourceType") == "user_profile")
                .order(Column("predicate").asc)
                .fetchAll(db)
        }) ?? []
    }

    private func parseProfileToKnowledgeFacts(_ markdown: String) {
        let pool = dataBridge.db.pool
        Task.detached {
            do {
                try pool.write { db in
                    // Clear old profile facts
                    try db.execute(sql: "DELETE FROM knowledgeFacts WHERE subject = 'User' AND sourceType = 'user_profile'")

                    // Parse markdown sections into facts
                    var currentSection = ""
                    for line in markdown.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("## ") {
                            currentSection = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("- ") {
                            let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                            if !content.isEmpty && content != "-" {
                                // Split "Key: Value" pattern
                                let predicate: String
                                let object: String
                                if let colonIdx = content.firstIndex(of: ":") {
                                    predicate = String(content[content.startIndex..<colonIdx])
                                        .trimmingCharacters(in: .whitespaces).lowercased()
                                    object = String(content[content.index(after: colonIdx)...])
                                        .trimmingCharacters(in: .whitespaces)
                                } else {
                                    predicate = currentSection.lowercased()
                                    object = content
                                }
                                guard !object.isEmpty else { continue }
                                try db.execute(sql: """
                                    INSERT INTO knowledgeFacts (subject, predicate, object, confidence, sourceType)
                                    VALUES ('User', ?, ?, 1.0, 'user_profile')
                                """, arguments: [predicate, object])
                            }
                        }
                    }
                }
            } catch {
                // Profile parsing should not crash
            }
        }
    }
}

// MARK: - Brain Profile

struct BrainProfileView: View {
    @AppStorage("brainProfileMarkdown") private var profileMarkdown = ""
    @AppStorage("aiPersonalityName") private var personalityName = "Brain"
    @AppStorage("aiPersonalityPreset") private var personalityPreset = "freundlich"
    @AppStorage("aiHumorLevel") private var humorLevel = 2.0
    @AppStorage("aiFormality") private var formality = "du"
    @State private var isEditing = false
    @State private var editText = ""
    @State private var savedToast = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var hasCustomAvatar = BrainAvatarStorage.hasCustomAvatar

    private let placeholder = """
    # Brain Persönlichkeit

    ## Grundcharakter
    - Stil: freundlich, hilfsbereit, aufmerksam
    - Humor: gelegentlich, nie auf Kosten anderer
    - Anrede: Du

    ## Kommunikation
    - Spricht Deutsch (Schweizer Kontext)
    - Antwortet präzise, nicht zu lang
    - Fragt nach wenn unklar

    ## Spezialgebiete
    - Persönliche Produktivität
    - Wissensmanagement
    - Tagesplanung

    ## Grenzen
    - Gibt zu wenn etwas nicht bekannt ist
    - Keine medizinischen/rechtlichen Diagnosen
    - Respektiert Privacy Zones

    ## Besondere Anweisungen
    -
    """

    var body: some View {
        List {
            // Avatar
            Section("Profilbild") {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        brainAvatarPreview
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text("Bild wählen")
                                    .font(.caption)
                            }
                            if hasCustomAvatar {
                                Button("Entfernen", role: .destructive) {
                                    BrainAvatarStorage.delete()
                                    hasCustomAvatar = false
                                }
                                .font(.caption)
                            }
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        BrainAvatarStorage.save(image)
                        hasCustomAvatar = true
                    }
                }
            }

            // Quick settings
            Section("Schnelleinstellungen") {
                TextField("Name", text: $personalityName)
                Picker("Stil", selection: $personalityPreset) {
                    Text("Freundlich").tag("freundlich")
                    Text("Sachlich").tag("sachlich")
                    Text("Witzig").tag("witzig")
                    Text("Empathisch").tag("empathisch")
                }
                Picker("Anrede", selection: $formality) {
                    Text("Du").tag("du")
                    Text("Sie").tag("sie")
                }
                HStack {
                    Text("Humor")
                    Slider(value: $humorLevel, in: 0...5, step: 1)
                    Text("\(Int(humorLevel))")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
            }

            // Extended profile (Markdown)
            if isEditing {
                Section("Erweiterte Persönlichkeit") {
                    TextEditor(text: $editText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                }
                Section {
                    Button("Speichern") {
                        profileMarkdown = editText
                        isEditing = false
                        savedToast = true
                    }
                    Button("Abbrechen", role: .cancel) { isEditing = false }
                }
            } else {
                Section("Erweiterte Persönlichkeit") {
                    if profileMarkdown.isEmpty {
                        VStack(spacing: 8) {
                            Text("Beschreibe Brains Persönlichkeit detailliert in Markdown.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Profil erstellen") {
                                editText = placeholder
                                isEditing = true
                            }
                        }
                    } else {
                        Text(profileMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Bearbeiten") {
                            editText = profileMarkdown
                            isEditing = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Brain Profil")
        .overlay(alignment: .bottom) {
            if savedToast {
                Text("Profil gespeichert")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.move(edge: .bottom))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await MainActor.run { savedToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: savedToast)
    }

    @ViewBuilder
    private var brainAvatarPreview: some View {
        if let data = try? Data(contentsOf: BrainAvatarStorage.avatarURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Kennenlern-Dialog

struct KennenlernDialogView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var chatService: ChatService?
    @State private var isStarted = false
    @State private var showSettings = false

    private let kennenlernPrompt = """
    Du führst jetzt ein Kennenlern-Interview mit dem User durch. Ziel: Lerne den User besser kennen.

    REGELN:
    1. Stelle EINE Frage auf einmal (nicht mehrere)
    2. Beginne mit leichten Fragen (Name, Wohnort, Beruf)
    3. Gehe dann zu persönlicheren Themen (Familie, Hobbys, Werte)
    4. Speichere JEDE Antwort als Knowledge Fact (nutze das knowledge_save Tool)
    5. Fasse am Ende zusammen was du gelernt hast
    6. Sei warmherzig und interessiert, nicht wie ein Formular
    7. Maximal 10 Fragen, dann beende das Interview

    Beginne mit einer freundlichen Begrüssung und der ersten Frage.
    """

    var body: some View {
        Group {
            if isStarted, let service = chatService {
                ChatView(chatService: service, showSettings: $showSettings)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Kennenlern-Dialog")
                        .font(.title2.bold())

                    Text("Brain stellt Dir Fragen um Dich besser kennenzulernen. Die Antworten werden als Wissen gespeichert und helfen Brain, Dir persönlichere Hilfe zu geben.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Du kannst dieses Interview jederzeit wiederholen — Brain aktualisiert dann sein Wissen.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Interview starten") {
                        startInterview()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
        }
        .navigationTitle("Kennenlernen")
    }

    private func startInterview() {
        let service = ChatService(pool: dataBridge.db.pool)
        service.setHandlers(CoreActionHandlers.all(data: dataBridge))
        chatService = service
        isStarted = true

        // Send the interview prompt as system-triggered message
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                service.pendingInput = kennenlernPrompt
            }
        }
    }
}
