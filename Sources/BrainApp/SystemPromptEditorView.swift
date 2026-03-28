import SwiftUI
import BrainCore
import GRDB

// Full-screen editor for the system prompt.
// Shows the default prompt as starting point, allows editing, and saves to UserDefaults.
struct SystemPromptEditorView: View {
    @Binding var customPrompt: String
    let pool: DatabasePool
    @Environment(\.dismiss) private var dismiss
    @State private var editText = ""
    @State private var isLoading = true
    @State private var defaultPrompt = ""
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Info banner
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Änderungen wirken sich auf alle zukünftigen Chat-Nachrichten aus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))

                if isLoading {
                    Spacer()
                    ProgressView("Lade System-Prompt...")
                    Spacer()
                } else {
                    TextEditor(text: $editText)
                        .font(.system(.caption, design: .monospaced))
                        .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("System-Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        savePrompt()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button {
                            showResetConfirm = true
                        } label: {
                            Label("Standard laden", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        Spacer()
                        Text("\(editText.count) Zeichen")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

            }
            .confirmationDialog("Standard-Prompt laden?", isPresented: $showResetConfirm) {
                Button("Standard laden") {
                    editText = defaultPrompt
                }
            } message: {
                Text("Der aktuelle Text wird durch den Standard-System-Prompt ersetzt. Du kannst ihn danach weiter bearbeiten.")
            }
            .task {
                // Build the default prompt for reference
                let builder = SystemPromptBuilder(pool: pool)
                defaultPrompt = builder.build()

                // Start with custom if set, otherwise default
                if customPrompt.isEmpty {
                    editText = defaultPrompt
                } else {
                    editText = customPrompt
                }
                isLoading = false
            }
        }
    }

    private func savePrompt() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultPrompt || trimmed.isEmpty {
            // Same as default or empty → remove override
            customPrompt = ""
            UserDefaults.standard.removeObject(forKey: "customSystemPromptOverride")
        } else {
            customPrompt = trimmed
            UserDefaults.standard.set(trimmed, forKey: "customSystemPromptOverride")
        }
    }
}
