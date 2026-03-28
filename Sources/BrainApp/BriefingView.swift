import SwiftUI
import BrainCore

// Brain Pulse: Morning Briefing and Evening Recap views.
// Shown automatically on app launch or accessible from Dashboard.

struct BriefingView: View {
    let briefing: BrainBriefing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrainTheme.spacingXL) {
                // Header with time-of-day greeting
                VStack(alignment: .leading, spacing: BrainTheme.spacingXS) {
                    if let seasonal = BrainTheme.seasonalGreeting() {
                        Text(seasonal)
                            .font(BrainTheme.Typography.caption)
                            .foregroundStyle(BrainTheme.Colors.brandAmber)
                    }
                    Text(briefing.greeting)
                        .font(BrainTheme.Typography.displayLarge)
                        .foregroundStyle(BrainTheme.Colors.textPrimary)
                    Text(briefing.date)
                        .font(BrainTheme.Typography.subheadline)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                }
                .padding(.bottom, BrainTheme.spacingSM)

                // Stats bar with animated numbers and glass cards
                HStack(spacing: BrainTheme.spacingMD) {
                    StatPill(icon: "doc.text", value: "\(briefing.totalEntries)", label: "Entries")
                    StatPill(icon: "checkmark.circle", value: "\(briefing.openTasks.count)", label: "Offen")
                    if briefing.unreadEmails > 0 {
                        StatPill(icon: "envelope.badge", value: "\(briefing.unreadEmails)", label: "E-Mails")
                    }
                    if briefing.yesterdayCount > 0 {
                        StatPill(icon: "arrow.left.circle", value: "\(briefing.yesterdayCount)", label: "Gestern")
                    }
                }

                // Overdue tasks (warning)
                if !briefing.overdueTasks.isEmpty {
                    SectionCard(title: "Überfällig", icon: "exclamationmark.triangle.fill", color: .orange) {
                        ForEach(briefing.overdueTasks) { task in
                            HStack {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(task.title)
                                    .font(BrainTheme.Typography.callout)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                }

                // Open tasks
                if !briefing.openTasks.isEmpty {
                    SectionCard(title: "Offene Aufgaben", icon: "checklist", color: .blue) {
                        ForEach(briefing.openTasks.prefix(5)) { task in
                            HStack {
                                Image(systemName: "circle")
                                    .foregroundStyle(BrainTheme.Colors.textTertiary)
                                    .font(.caption)
                                Text(task.title)
                                    .font(BrainTheme.Typography.callout)
                                    .lineLimit(1)
                            }
                        }
                        if briefing.openTasks.count > 5 {
                            Text("+ \(briefing.openTasks.count - 5) weitere")
                                .font(BrainTheme.Typography.caption)
                                .foregroundStyle(BrainTheme.Colors.textTertiary)
                        }
                    }
                    
                }

                // Insights from Pattern Engine
                if !briefing.insights.isEmpty {
                    SectionCard(title: "Erkenntnisse", icon: "lightbulb.fill", color: .yellow) {
                        ForEach(briefing.insights) { insight in
                            HStack(alignment: .top) {
                                Image(systemName: iconForPatternType(insight.type))
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                VStack(alignment: .leading) {
                                    Text(insight.message)
                                        .font(BrainTheme.Typography.callout)
                                }
                            }
                        }
                    }
                    
                }

                // On This Day
                if !briefing.onThisDay.isEmpty {
                    SectionCard(title: "An diesem Tag", icon: "clock.arrow.circlepath", color: .purple) {
                        ForEach(briefing.onThisDay) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.title)
                                        .font(BrainTheme.Typography.callout)
                                        .lineLimit(1)
                                    if let subtitle = entry.subtitle {
                                        Text(subtitle)
                                            .font(BrainTheme.Typography.caption)
                                            .foregroundStyle(BrainTheme.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    
                }
            }
            .padding()
        }
        .background(BrainTheme.Gradients.timeOfDaySubtle().ignoresSafeArea())
    }

    private func iconForPatternType(_ type: String) -> String {
        switch type {
        case "streak": return "flame.fill"
        case "anomaly": return "chart.line.downtrend.xyaxis"
        case "neglect": return "person.crop.circle.badge.exclamationmark"
        case "frequency": return "repeat"
        case "correlation": return "link"
        default: return "lightbulb"
        }
    }
}

// Evening Recap View
struct RecapView: View {
    let recap: BrainRecap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrainTheme.spacingXL) {
                VStack(alignment: .leading, spacing: BrainTheme.spacingXS) {
                    Text("Tagesrückblick")
                        .font(BrainTheme.Typography.displayLarge)
                        .foregroundStyle(BrainTheme.Colors.textPrimary)
                    Text(recap.date)
                        .font(BrainTheme.Typography.subheadline)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                }

                HStack(spacing: BrainTheme.spacingMD) {
                    StatPill(icon: "plus.circle", value: "\(recap.entriesCreated)", label: "Erstellt")
                    StatPill(icon: "checkmark.circle.fill", value: "\(recap.tasksCompleted)", label: "Erledigt")
                    StatPill(icon: "circle", value: "\(recap.tasksStillOpen)", label: "Offen")
                }

                if !recap.items.isEmpty {
                    SectionCard(title: "Heute erstellt", icon: "list.bullet", color: BrainTheme.Colors.brandBlue) {
                        ForEach(recap.items.prefix(10)) { item in
                            HStack {
                                Image(systemName: iconForEntryType(item.type))
                                    .foregroundStyle(BrainTheme.Colors.textSecondary)
                                    .font(.caption)
                                Text(item.title)
                                    .font(BrainTheme.Typography.callout)
                                    .lineLimit(1)
                                Spacer()
                                if item.status == "done" {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(BrainTheme.Colors.success)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                }
            }
            .padding()
        }
        .background(BrainTheme.Gradients.timeOfDaySubtle().ignoresSafeArea())
    }

    private func iconForEntryType(_ type: String) -> String {
        EntryType(rawValue: type)?.icon ?? "doc.text"
    }
}

// MARK: - Reusable Components

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: BrainTheme.spacingXS) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BrainTheme.Colors.brandBlue)
                .symbolEffect(.pulse, options: .speed(0.5))
            Text(value)
                .font(BrainTheme.Typography.statSmall)
                .contentTransition(.numericText())
            Text(label)
                .font(BrainTheme.Typography.captionSmall)
                .foregroundStyle(BrainTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrainTheme.spacingMD)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.cornerRadiusMD))
        .shadow(color: BrainTheme.Shadows.subtle, radius: 2, x: 0, y: 1)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrainTheme.spacingMD) {
            Label(title, systemImage: icon)
                .font(BrainTheme.Typography.headline)
                .foregroundStyle(color)

            content()
        }
        .padding(BrainTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.cornerRadiusLG))
        .shadow(color: BrainTheme.Shadows.subtle, radius: 4, x: 0, y: 2)
        .overlay(alignment: .leading) {
            // Colored accent bar on the left edge
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, BrainTheme.spacingSM)
        }
    }
}
