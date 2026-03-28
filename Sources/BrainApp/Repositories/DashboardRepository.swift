import Foundation
import BrainCore
import GRDB

// Dashboard data: counts, recent entries, tasks, greeting, unread mails.
struct DashboardRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    struct DashboardStats: Sendable {
        let entryCount: Int
        let openTaskCount: Int
        let skillCount: Int
        let tagCount: Int
        let linkCount: Int
        let recentEntries: [Entry]
        let openTasks: [Entry]
        let unreadMailCount: Int
        let todayEntryCount: Int
        let factCount: Int
    }

    func fetchStats() throws -> DashboardStats {
        try pool.read { db in
            let total = try Entry.filter(Column("deletedAt") == nil).fetchCount(db)
            let openTaskCount = try Entry
                .filter(Column("deletedAt") == nil)
                .filter(Column("type") == EntryType.task)
                .filter(Column("status") == EntryStatus.active)
                .fetchCount(db)
            let skills = try Skill.fetchCount(db)
            let tags = try Tag.fetchCount(db)
            let links = try Link.fetchCount(db)
            let recent = try Entry
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .limit(5)
                .fetchAll(db)

            // Open tasks (up to 10, ordered by priority desc, then creation date)
            let tasks = try Entry
                .filter(Column("deletedAt") == nil)
                .filter(Column("type") == EntryType.task)
                .filter(Column("status") == EntryStatus.active)
                .order(Column("priority").desc, Column("createdAt").desc)
                .limit(10)
                .fetchAll(db)

            // Unread mail count
            let unread = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM emailCache WHERE isRead = 0 AND folder = 'INBOX'") ?? 0

            // Entries created today
            let todayStr = Self.todayDateString()
            let todayCount = try Entry
                .filter(Column("deletedAt") == nil)
                .filter(Column("createdAt") >= todayStr)
                .fetchCount(db)

            // Knowledge facts count
            let facts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledgeFacts") ?? 0

            return DashboardStats(
                entryCount: total,
                openTaskCount: openTaskCount,
                skillCount: skills,
                tagCount: tags,
                linkCount: links,
                recentEntries: recent,
                openTasks: tasks,
                unreadMailCount: unread,
                todayEntryCount: todayCount,
                factCount: facts
            )
        }
    }

    static func greetingForTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func todayDateString() -> String {
        dayFormatter.string(from: Date())
    }
}
