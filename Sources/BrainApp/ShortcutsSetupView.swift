import SwiftUI

// Guide for setting up Shortcuts automations for reliable background analysis.
// iOS Background App Refresh is unreliable — Shortcuts automations are the
// recommended workaround for periodic tasks.
struct ShortcutsSetupView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: BrainTheme.Spacing.md) {
                    Label("Warum Shortcuts?", systemImage: "info.circle")
                        .font(BrainTheme.Typography.headline)

                    Text("iOS begrenzt Hintergrund-Aktivitäten stark. Shortcuts-Automationen sind der zuverlässigste Weg, Brain regelmässig analysieren und synchronisieren zu lassen.")
                        .font(BrainTheme.Typography.callout)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                }
                .padding(.vertical, BrainTheme.Spacing.sm)
            }

            Section("Empfohlene Automationen") {
                automationRow(
                    icon: "brain.head.profile",
                    color: BrainTheme.Colors.brandPurple,
                    title: "Tägliche Analyse",
                    trigger: "Jeden Tag um 8:00",
                    action: "Brain Analyse ausführen",
                    description: "Erkennt Muster, analysiert neue Einträge, schlägt Skills vor."
                )

                automationRow(
                    icon: "envelope.arrow.triangle.branch",
                    color: BrainTheme.Colors.accentSky,
                    title: "Mail-Sync",
                    trigger: "Alle 30 Minuten",
                    action: "Brain Mail-Sync",
                    description: "Synchronisiert E-Mails im Hintergrund. Nur nötig wenn Mail konfiguriert ist."
                )

                automationRow(
                    icon: "bolt.fill",
                    color: BrainTheme.Colors.accentAmber,
                    title: "Tiefenanalyse",
                    trigger: "Beim Laden",
                    action: "Brain Tiefenanalyse",
                    description: "Ausführliche Analyse mit grossen Batches. Ideal wenn das Gerät lädt."
                )
            }

            Section("So geht's") {
                stepRow(number: 1, text: "Öffne die Shortcuts-App")
                stepRow(number: 2, text: "Tippe auf 'Automation' (unten)")
                stepRow(number: 3, text: "Tippe '+' → 'Persönliche Automation erstellen'")
                stepRow(number: 4, text: "Wähle den Auslöser (z.B. 'Tageszeit')")
                stepRow(number: 5, text: "Suche nach 'Brain' und wähle die gewünschte Aktion")
                stepRow(number: 6, text: "Deaktiviere 'Vor Ausführen fragen'")
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Shortcuts-App öffnen", systemImage: "arrow.up.forward.app")
                        .font(BrainTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrainTheme.Colors.brandPurple)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .navigationTitle("Shortcuts-Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func automationRow(icon: String, color: Color, title: String, trigger: String, action: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: BrainTheme.Spacing.sm) {
            HStack(spacing: BrainTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BrainTheme.Typography.headline)
                    Text(description)
                        .font(BrainTheme.Typography.caption)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                }
            }

            HStack(spacing: BrainTheme.Spacing.sm) {
                Label(trigger, systemImage: "clock")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrainTheme.Colors.brandPurple.opacity(0.12)))

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Label(action, systemImage: "app.badge.checkmark")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrainTheme.Colors.accentMint.opacity(0.15)))
            }
        }
        .padding(.vertical, BrainTheme.Spacing.xs)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: BrainTheme.Spacing.md) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(BrainTheme.Colors.brandPurple))

            Text(text)
                .font(BrainTheme.Typography.callout)
        }
    }
}
