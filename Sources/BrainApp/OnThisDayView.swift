import SwiftUI
import BrainCore
import GRDB

// Dedicated "An diesem Tag" view: shows entries created on the same calendar day
// in previous years, plus 1 week and 1 month ago. Groups by time distance.
struct OnThisDayView: View {
    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    @Environment(DataBridge.self) private var dataBridge
    @State private var entries: [Entry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Erinnerungen...")
                    .pulseEffect()
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Keine Erinnerungen",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("An diesem Tag gibt es noch keine früheren Einträge.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedEntries, id: \.label) { group in
                            Section {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    OnThisDayRow(entry: entry)
                                        .staggeredAppear(index: index)
                                }
                            } header: {
                                Label(group.label, systemImage: group.icon)
                                    .font(.headline)
                                    .foregroundStyle(group.color)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("An diesem Tag")
        .onAppear { loadEntries() }
        .refreshable { loadEntries() }
    }

    // MARK: - Grouping

    private var groupedEntries: [EntryGroup] {
        var weekAgo: [Entry] = []
        var monthAgo: [Entry] = []
        var yearGroups: [Int: [Entry]] = [:]

        let cal = Calendar.current
        let now = Date()

        for entry in entries {
            guard let dateStr = entry.createdAt,
                  let date = Self.dbDateFormatter.date(from: dateStr) else { continue }

            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0

            if days >= 5 && days <= 9 {
                weekAgo.append(entry)
            } else if days >= 28 && days <= 32 {
                monthAgo.append(entry)
            } else {
                let year = cal.component(.year, from: date)
                yearGroups[year, default: []].append(entry)
            }
        }

        var groups: [EntryGroup] = []

        if !weekAgo.isEmpty {
            groups.append(EntryGroup(
                label: "Vor einer Woche",
                icon: "7.circle",
                color: .blue,
                entries: weekAgo
            ))
        }
        if !monthAgo.isEmpty {
            groups.append(EntryGroup(
                label: "Vor einem Monat",
                icon: "30.circle",
                color: .cyan,
                entries: monthAgo
            ))
        }
        for year in yearGroups.keys.sorted(by: >) {
            let yearsAgo = cal.component(.year, from: now) - year
            groups.append(EntryGroup(
                label: yearsAgo == 1 ? "Vor einem Jahr (\(year))" : "Vor \(yearsAgo) Jahren (\(year))",
                icon: "calendar",
                color: .purple,
                entries: yearGroups[year, default: []]
            ))
        }

        return groups
    }

    // MARK: - Data loading

    private func loadEntries() {
        isLoading = true
        defer { isLoading = false }

        do {
            let pool = dataBridge.db.pool

            // Same calendar day in previous years
            let sameDay = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND strftime('%m-%d', createdAt) = strftime('%m-%d', 'now')
                    AND DATE(createdAt) != DATE('now')
                    ORDER BY createdAt DESC
                    LIMIT 50
                """)
            }

            // 1 week ago
            let weekAgo = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND DATE(createdAt) = DATE('now', '-7 days')
                    ORDER BY createdAt DESC
                    LIMIT 10
                """)
            }

            // 1 month ago
            let monthAgo = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND DATE(createdAt) = DATE('now', '-30 days')
                    ORDER BY createdAt DESC
                    LIMIT 10
                """)
            }

            // Deduplicate
            var seen = Set<Int64>()
            var all: [Entry] = []
            for entry in sameDay + weekAgo + monthAgo {
                if let id = entry.id, seen.insert(id).inserted {
                    all.append(entry)
                }
            }
            entries = all
        } catch {
            entries = []
        }
    }
}

// MARK: - Supporting types

private struct EntryGroup {
    let label: String
    let icon: String
    let color: Color
    let entries: [Entry]
}

private struct OnThisDayRow: View {
    let entry: Entry

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForType(entry.type))
                .font(.title3)
                .foregroundStyle(colorForType(entry.type))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? "Ohne Titel")
                    .font(.body)
                    .lineLimit(2)

                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let dateStr = entry.createdAt {
                    Text(formatDate(dateStr))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.type == .task {
                Image(systemName: entry.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.status == .done ? .green : .secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func iconForType(_ type: EntryType) -> String {
        type.icon
    }

    private func colorForType(_ type: EntryType) -> Color {
        type.color
    }

    private func formatDate(_ dateStr: String) -> String {
        guard let date = Self.dbDateFormatter.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_CH")
        fmt.dateFormat = "d. MMMM yyyy, HH:mm"
        return fmt.string(from: date)
    }
}
