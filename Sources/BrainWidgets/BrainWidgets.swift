import WidgetKit
import SwiftUI
import BrainCore
import GRDB

// Phase 21: Brain Widgets — Homescreen widgets for quick access.
// Uses App Group shared database for data.

@main
struct BrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureWidget()
        TasksWidget()
        BrainPulseWidget()
    }
}

// MARK: - Shared Database Access

enum WidgetDatabase {
    static func makeEntryService() -> EntryService? {
        guard let db = try? SharedContainer.makeDatabaseManager() else { return nil }
        return EntryService(pool: db.pool)
    }
}

// MARK: - 1. Quick Capture Widget (Small)

struct QuickCaptureWidget: Widget {
    let kind = "QuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            QuickCaptureWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Schnellerfassung")
        .description("Tippe um einen Gedanken festzuhalten.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickCaptureEntry: TimelineEntry {
    let date: Date
    let entryCount: Int
}

struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: .now, entryCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        let count = (try? WidgetDatabase.makeEntryService()?.count()) ?? 0
        completion(QuickCaptureEntry(date: .now, entryCount: count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        let count = (try? WidgetDatabase.makeEntryService()?.count()) ?? 0
        let entry = QuickCaptureEntry(date: .now, entryCount: count)
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900)))
        completion(timeline)
    }
}

struct QuickCaptureWidgetView: View {
    let entry: QuickCaptureEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundStyle(.blue)

            Text("Brain")
                .font(.headline)

            Text("\(entry.entryCount) Entries")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .widgetURL(URL(string: "brain://capture"))
    }
}

// MARK: - 2. Tasks Widget (Medium)

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Offene Aufgaben")
        .description("Zeigt deine offenen Brain-Aufgaben.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let totalOpen: Int
}

struct TaskItem: Identifiable {
    let id: Int64
    let title: String
    let priority: Int
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, tasks: [
            TaskItem(id: 1, title: "Beispiel-Aufgabe", priority: 0),
        ], totalOpen: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        let entry = fetchTasks()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let entry = fetchTasks()
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(600)))
        completion(timeline)
    }

    private func fetchTasks() -> TasksEntry {
        guard let service = WidgetDatabase.makeEntryService() else {
            return TasksEntry(date: .now, tasks: [], totalOpen: 0)
        }

        let openTasks = (try? service.list(type: .task, status: .active, limit: 8)) ?? []
        let totalOpen = (try? service.count(type: .task, status: .active)) ?? 0

        let items = openTasks.map { entry in
            TaskItem(id: entry.id ?? 0, title: entry.title ?? "Ohne Titel", priority: entry.priority)
        }

        return TasksEntry(date: .now, tasks: items, totalOpen: totalOpen)
    }
}

struct TasksWidgetView: View {
    let entry: TasksEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Aufgaben", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("\(entry.totalOpen) offen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.tasks.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Alles erledigt!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(entry.tasks) { task in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(task.title)
                            .font(.caption)
                            .lineLimit(1)
                            .privacySensitive() // F-19: Redact task titles on lock screen
                        Spacer()
                        if task.priority > 0 {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .widgetURL(URL(string: "brain://tasks"))
    }
}

// MARK: - 3. Brain Pulse Widget (Medium)

struct BrainPulseWidget: Widget {
    let kind = "BrainPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Brain Pulse")
        .description("Tages-Zusammenfassung auf einen Blick.")
        .supportedFamilies([.systemMedium])
    }
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let totalEntries: Int
    let openTasks: Int
    let todayEntries: Int
    let greeting: String
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now, totalEntries: 42, openTasks: 5, todayEntries: 3, greeting: "Guten Tag")
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(fetchPulse())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let entry = fetchPulse()
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800)))
        completion(timeline)
    }

    private func fetchPulse() -> PulseEntry {
        guard let db = try? SharedContainer.makeDatabaseManager() else {
            return PulseEntry(date: .now, totalEntries: 0, openTasks: 0, todayEntries: 0, greeting: greeting())
        }

        let service = EntryService(pool: db.pool)
        let total = (try? service.count()) ?? 0
        let open = (try? service.count(type: .task, status: .active)) ?? 0

        let todayCount: Int = (try? db.pool.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as cnt FROM entries
                WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now')
                """)
            return row?["cnt"] ?? 0
        }) ?? 0

        return PulseEntry(
            date: .now,
            totalEntries: total,
            openTasks: open,
            todayEntries: todayCount,
            greeting: greeting()
        )
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }
}

struct PulseWidgetView: View {
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.blue)
                Text(entry.greeting)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                StatBlock(icon: "doc.text", value: "\(entry.totalEntries)", label: "Entries")
                StatBlock(icon: "checkmark.circle", value: "\(entry.openTasks)", label: "Offen")
                StatBlock(icon: "plus.circle", value: "\(entry.todayEntries)", label: "Heute")
            }
        }
        .widgetURL(URL(string: "brain://dashboard"))
    }
}

struct StatBlock: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
