import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BrainCore

// MARK: - Source Viewer (Markdown "Virenschutz")

struct SkillSourceView: View {
    let skill: Skill

    var body: some View {
        ScrollView {
            Text(skill.sourceMarkdown ?? "Kein Quell-Markdown vorhanden.")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Skill-Quelle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - JSON Viewer (compiled screens)

struct SkillJSONView: View {
    let skill: Skill

    private var prettyJSON: String {
        guard let data = skill.screens.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return skill.screens }
        return str
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrainTheme.Spacing.md) {
                // Safety analysis
                let dangers = SkillSafetyAnalyzer.analyze(json: skill.screens, actions: skill.actions)
                if !dangers.isEmpty {
                    VStack(alignment: .leading, spacing: BrainTheme.Spacing.xs) {
                        Label("Sicherheitshinweise", systemImage: "exclamationmark.shield")
                            .font(.headline)
                            .foregroundStyle(BrainTheme.Colors.warning)
                        ForEach(dangers, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(BrainTheme.Colors.warning)
                        }
                    }
                    .brainCard()
                } else {
                    Label("Keine gefährlichen Aktionen erkannt", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(BrainTheme.Colors.success)
                        .padding(.horizontal)
                }

                Text(prettyJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .navigationTitle("Kompiliertes JSON")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safety Analyzer

enum SkillSafetyAnalyzer {
    // Actions that modify or delete data — flagged for user awareness.
    private static let dangerousActions: [String: String] = [
        "entry.delete": "Kann Einträge löschen",
        "file.delete": "Kann Dateien loeschen",
        "email.delete": "Kann E-Mails loeschen",
        "email.send": "Kann E-Mails senden",
        "contact.delete": "Kann Kontakte loeschen",
        "http.request": "Kann Netzwerk-Anfragen senden",
        "http.download": "Kann Dateien herunterladen",
        "calendar.delete": "Kann Kalender-Einträge löschen",
        "reminder.cancel": "Kann Erinnerungen loeschen",
    ]

    static func analyze(json: String, actions: String?) -> [String] {
        var warnings: [String] = []
        let combined = json + (actions ?? "")
        for (action, description) in dangerousActions {
            if combined.contains(action) {
                warnings.append(description)
            }
        }
        return warnings.sorted()
    }
}

// MARK: - Shareable File Wrapper

struct ShareableSkillFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
