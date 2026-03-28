import SwiftUI
import BrainCore

struct BrainHelpButton: View {
    let context: String
    let screenName: String
    @State private var showHelp = false

    var body: some View {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .foregroundStyle(BrainTheme.Colors.brandPurple)
        }
        .sheet(isPresented: $showHelp) {
            BrainHelpChat(context: context, screenName: screenName)
        }
    }

    // Convenience presets for common screens
    static var settings: some View {
        BrainHelpButton(
            context: "Einstellungen: LLM-Provider, Sicherheit, Datenschutz, Task-Routing",
            screenName: "Einstellungen"
        )
    }

    static var onboarding: some View {
        BrainHelpButton(
            context: "Onboarding: API-Keys, Mail-Konto, Berechtigungen einrichten",
            screenName: "Onboarding"
        )
    }

    static var chat: some View {
        BrainHelpButton(
            context: "Chat mit Brain: Modellauswahl, Spracheingabe, Tool-Aufrufe",
            screenName: "Chat"
        )
    }
}

private struct BrainHelpChat: View {
    let context: String
    let screenName: String
    @State private var messages: [(role: String, text: String)] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: BrainTheme.Spacing.md) {
                            helpBubble(
                                text: "Hallo! Du bist gerade bei \"\(screenName)\". Wie kann ich dir helfen?",
                                isAssistant: true
                            )
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                                helpBubble(text: msg.text, isAssistant: msg.role == "assistant")
                                    .id(index)
                            }
                            if isLoading {
                                HStack(spacing: 6) {
                                    ForEach(0..<3, id: \.self) { i in
                                        Circle()
                                            .fill(BrainTheme.Colors.brandPurple.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                            .offset(y: isLoading ? -4 : 4)
                                            .animation(
                                                .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                                                value: isLoading
                                            )
                                    }
                                }
                                .padding(.leading, BrainTheme.Spacing.lg)
                            }
                        }
                        .padding(BrainTheme.Spacing.lg)
                    }
                    .onChange(of: messages.count) {
                        withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                    }
                }
                Divider()
                HStack(spacing: BrainTheme.Spacing.sm) {
                    TextField("Frage stellen...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendMessage() }
                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? Color.gray : BrainTheme.Colors.brandPurple)
                    }
                    .disabled(inputText.isEmpty || isLoading)
                }
                .padding(BrainTheme.Spacing.md)
                .background(.bar)
            }
            .navigationTitle("Brain Hilfe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func helpBubble(text: String, isAssistant: Bool) -> some View {
        HStack {
            if !isAssistant { Spacer(minLength: 40) }
            Text(text)
                .font(.subheadline)
                .padding(BrainTheme.Spacing.md)
                .background(
                    isAssistant
                        ? AnyShapeStyle(.regularMaterial)
                        : AnyShapeStyle(BrainTheme.Colors.brandPurple.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: BrainTheme.Radius.md)
                )
                .foregroundStyle(.primary)
            if isAssistant { Spacer(minLength: 40) }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append((role: "user", text: text))
        isLoading = true
        Task {
            let helpText = contextualHelp(for: screenName, question: text)
            try? await Task.sleep(for: .milliseconds(600))
            messages.append((role: "assistant", text: helpText))
            isLoading = false
        }
    }

    private func contextualHelp(for screen: String, question: String) -> String {
        // Use comprehensive help content from BrainHelpContent
        return BrainHelpContent.helpText(for: screen)
    }
}
