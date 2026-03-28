import SwiftUI
import BrainCore

// MARK: - Chat View

struct ChatView: View {
    @Bindable var chatService: ChatService
    @Binding var showSettings: Bool
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    // Voice input
    @State private var isRecording = false
    @State private var voiceInputManager = VoiceInputManager()

    // Model selection in chat
    @AppStorage("selectedModel") private var globalModel = "claude-opus-4-6"
    @State private var chatModel: String = ""

    // Confirmation dialog for destructive tool calls
    @State private var showToolConfirmation = false
    @State private var pendingToolDescription = ""
    @State private var pendingToolContinuation: CheckedContinuation<Bool, Never>?

    private var currentModelLabel: String {
        AvailableModels.shortLabel(for: chatModel)
    }

    var body: some View {
        chatScrollContent
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    BrainHelpButton.chat
                    chatModelMenu
                }
            }

        }
        .onAppear {
            let autoRoute = UserDefaults.standard.bool(forKey: "autoRouteModels")
            if chatModel.isEmpty { chatModel = autoRoute ? "auto" : globalModel }
            if autoRoute { chatModel = "auto" }
            chatService.chatModelOverride = (chatModel == "auto") ? nil : chatModel
            chatService.confirmationHandler = { [self] toolName, description in
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        pendingToolDescription = description
                        pendingToolContinuation = continuation
                        showToolConfirmation = true
                    }
                }
            }
        }
        .onChange(of: chatModel) { _, newModel in
            let autoRoute = UserDefaults.standard.bool(forKey: "autoRouteModels")
            if newModel == "auto" || autoRoute {
                chatService.chatModelOverride = nil
            } else {
                chatService.chatModelOverride = newModel
            }
        }
        .onChange(of: chatService.pendingInput) {
            handlePendingInput()
        }
        .alert("Aktion bestätigen", isPresented: $showToolConfirmation) {
            Button("Ausführen", role: .destructive) {
                pendingToolContinuation?.resume(returning: true)
                pendingToolContinuation = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingToolContinuation?.resume(returning: false)
                pendingToolContinuation = nil
            }
        } message: {
            Text(pendingToolDescription)
        }
    }

    // Extracted to help the compiler type-check the ChatView body
    private var chatScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    OfflineBanner()
                    chatEmptyState
                    chatMessageList
                    chatToolCallsView
                    chatStreamingView
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { chatInputBar }
            .onAppear {
                if let last = chatService.messages.last {
                    proxy.scrollTo(last.localId, anchor: .bottom)
                }
            }
            .onChange(of: chatService.messages.count) {
                if let last = chatService.messages.last {
                    withAnimation { proxy.scrollTo(last.localId, anchor: .bottom) }
                }
            }
            .onChange(of: chatService.streamingContent) {
                if chatService.isStreaming {
                    withAnimation {
                        proxy.scrollTo(chatService.streamingContent.isEmpty ? "thinking-indicator" : "streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.isStreaming) {
                if chatService.isStreaming {
                    withAnimation { proxy.scrollTo("thinking-indicator", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Chat body sub-views (extracted to reduce opaque type nesting depth)

    @ViewBuilder
    private var chatEmptyState: some View {
        if chatService.messages.isEmpty {
            let keychain = KeychainService()
            let hasKey = keychain.exists(key: KeychainKeys.anthropicAPIKey)
                || keychain.exists(key: KeychainKeys.openAIAPIKey)
                || keychain.exists(key: KeychainKeys.geminiAPIKey)
                || keychain.exists(key: KeychainKeys.brainAPIRefreshToken)
            if hasKey {
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 56))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Noch keine Nachrichten")
                        .font(.title3.weight(.semibold))
                    Text("Schreibe Brain eine Nachricht.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        suggestionChip("Was steht heute an?")
                        suggestionChip("Fasse zusammen...")
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal, BrainTheme.Spacing.xl)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Kein API-Key konfiguriert")
                        .font(.headline)
                    Text("Richte einen API-Key ein, um mit Brain zu chatten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showSettings = true
                    } label: {
                        Label("Einstellungen öffnen", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.top, 60)
                .padding(.horizontal, 32)
            }
        }
    }

    private var chatMessageList: some View {
        ForEach(chatService.messages, id: \.localId) { message in
            chatBubble(message)
                .id(message.localId)
        }
    }

    @ViewBuilder
    private var chatToolCallsView: some View {
        if chatService.isStreaming && !chatService.activeToolCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(chatService.activeToolCalls) { tool in
                    HStack(spacing: 8) {
                        if tool.isRunning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        }
                        Text(toolDisplayName(tool.name))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let result = tool.result, !tool.isRunning {
                            Text(String(result.prefix(60)))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.Radius.md))
            .padding(.horizontal)
            .id("tools")
        }
    }

    @ViewBuilder
    private var chatStreamingView: some View {
        if chatService.isStreaming {
            if !chatService.streamingContent.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let attributed = try? AttributedString(markdown: chatService.streamingContent) {
                            Text(attributed)
                        } else {
                            Text(chatService.streamingContent)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BrainTheme.Colors.glassBorder, lineWidth: 0.5))
                    Spacer(minLength: 48)
                }
                .id("streaming")
            }

            HStack(spacing: 12) {
                ProgressView().controlSize(.regular).tint(BrainTheme.Colors.brandPurple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chatService.streamingContent.isEmpty ? L("chat.thinking") : "Brain streamt...")
                        .font(.subheadline).fontWeight(.medium)
                    if !chatService.activeToolCalls.isEmpty {
                        Text("\(chatService.activeToolCalls.count) Tool(s) aktiv")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    chatService.cancelStream()
                } label: {
                    Text("Abbrechen").font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial).clipShape(Capsule())
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: BrainTheme.Radius.lg).strokeBorder(BrainTheme.Colors.glassBorder, lineWidth: 0.5))
            .padding(.horizontal)
            .id("thinking-indicator")

            if chatService.elapsedSeconds > 0 {
                HStack(spacing: 16) {
                    Label("\(chatService.elapsedSeconds)s", systemImage: "clock")
                    if chatService.liveOutputTokens > 0 {
                        Label("~\(chatService.liveOutputTokens) Tokens", systemImage: "number")
                    }
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
        }
    }

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            if let error = chatService.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).lineLimit(2)
                    Spacer()
                    Button {
                        chatService.error = nil
                        chatService.retryLastMessage()
                    } label: {
                        Label("Nochmal", systemImage: "arrow.clockwise")
                    }
                    Button { chatService.error = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .font(.caption).foregroundStyle(.white).padding(10).background(Color.red)
            }
            Divider()
            HStack(spacing: 8) {
                TextField(L("chat.placeholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...5)
                    .focused($isInputFocused).onSubmit { sendMessage() }

                // Microphone button: tap to start, tap again to stop and send
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(isRecording ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: isRecording)
                }
                .disabled(chatService.isStreaming)

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.bounce, value: inputText.isEmpty)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isStreaming)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }

    private var chatModelMenu: some View {
        Menu {
            // Auto-routing option
            Button {
                chatModel = "auto"
                chatService.chatModelOverride = nil
                UserDefaults.standard.set(true, forKey: "autoRouteModels")
            } label: {
                HStack {
                    Text("Auto (empfohlen)")
                    Spacer()
                    Text("smart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if chatModel == "auto" { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(AvailableModels.available()) { model in
                Button {
                    chatModel = model.id
                    chatService.chatModelOverride = model.id
                    UserDefaults.standard.set(false, forKey: "autoRouteModels")
                } label: {
                    HStack {
                        Text(model.label)
                        Spacer()
                        Text(model.cost)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if chatModel == model.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(chatModel == "auto" ? "Auto" : currentModelLabel)
                    .font(.subheadline).fontWeight(.medium)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(.systemGray5)).clipShape(Capsule())
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    // Render assistant messages as markdown
                    if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .textSelection(.enabled)
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(message.content)
                }

                // Model badge + Timestamp
                HStack(spacing: 6) {
                    if !isUser, let model = message.model {
                        Text(Self.shortModelName(model))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(isUser ? Color.white.opacity(0.7) : Color(uiColor: .secondaryLabel))
                    }
                    if let ts = message.createdAt, let date = Self.chatDateFormatter.date(from: ts) {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(isUser ? Color.white.opacity(0.7) : Color(uiColor: .tertiaryLabel))
                    }
                }
            }
            .padding(12)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: 18).fill(BrainTheme.Gradients.brand)
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BrainTheme.Colors.glassBorder, lineWidth: 0.5))
                }
            }
            .foregroundStyle(isUser ? .white : .primary)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private static func shortModelName(_ model: String) -> String {
        let map: [String: String] = [
            "claude-opus-4-6": "Opus",
            "claude-sonnet-4-6": "Sonnet",
            "claude-haiku-4-5-20251001": "Haiku",
            "gemini-2.5-pro": "Gemini Pro",
            "gemini-2.0-flash": "Gemini Flash",
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
        ]
        return map[model] ?? model
    }

    private static let chatDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chatService.send(text)
    }

    private func startRecording() {
        isRecording = true
        voiceInputManager.startListening { partialText in
            inputText = partialText
        }
    }

    private func stopRecording() {
        isRecording = false
        voiceInputManager.stopListening()
        // If we got text, auto-send it
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            sendMessage()
        }
    }

    // Pick up a pending Siri question if one exists.
    private func handlePendingInput() {
        if let pending = chatService.pendingInput {
            chatService.pendingInput = nil
            inputText = pending
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run { sendMessage() }
            }
        }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(BrainTheme.Colors.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // Human-readable tool names for the UI.
    private func toolDisplayName(_ name: String) -> String {
        let map: [String: String] = [
            "entry_create": "Erstelle Entry...",
            "entry_search": "Durchsuche Entries...",
            "entry_update": "Aktualisiere Entry...",
            "entry_delete": "Loesche Entry...",
            "entry_fetch": "Lade Entry...",
            "entry_list": "Liste Entries...",
            "entry_markDone": "Markiere als erledigt...",
            "entry_archive": "Archiviere...",
            "entry_restore": "Stelle wieder her...",
            "entry_crossref": "Suche Verwandte...",
            "tag_add": "Fuege Tag hinzu...",
            "tag_remove": "Entferne Tag...",
            "tag_list": "Liste Tags...",
            "tag_counts": "Zaehle Tags...",
            "link_create": "Verknüpfe Entries...",
            "link_delete": "Entferne Verknüpfung...",
            "link_list": "Liste Verknüpfungen...",
            "search_autocomplete": "Autocomplete...",
            "knowledge_save": "Speichere Wissen...",
            "calendar_list": "Lade Kalender...",
            "calendar_create": "Erstelle Termin...",
            "calendar_delete": "Loesche Termin...",
            "reminder_set": "Setze Erinnerung...",
            "reminder_cancel": "Storniere Erinnerung...",
            "reminder_list": "Liste Erinnerungen...",
            "reminder_pendingCount": "Zaehle Erinnerungen...",
            "contact_search": "Suche Kontakte...",
            "contact_read": "Lese Kontakt...",
            "contact_create": "Erstelle Kontakt...",
            "email_list": "Liste E-Mails...",
            "email_fetch": "Lade E-Mail...",
            "email_search": "Suche E-Mails...",
            "email_send": "Sende E-Mail...",
            "ai_summarize": "Fasse zusammen...",
            "ai_extractTasks": "Extrahiere Tasks...",
            "ai_briefing": "Erstelle Briefing...",
            "skill_list": "Liste Skills...",
            "rules_evaluate": "Prüfe Regeln...",
            "improve_list": "Liste Vorschläge...",
            "location_current": "Bestimme Standort...",
        ]
        return map[name] ?? name
    }
}

