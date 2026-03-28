// Pure data model for navigation state.
// Can be persisted (Codable) to restore last-viewed tab on app relaunch.
// The @Observable ViewModel wrapping this will live in BrainUI (SwiftUI layer).
public struct NavigationState: Codable, Sendable, Equatable {

    // Currently selected tab.
    public var selectedTab: BrainTab

    // Currently selected entry ID (for detail views).
    public var selectedEntryId: Int64?

    // Badge counts per tab (e.g. unread mail count).
    public var badges: [BrainTab: Int]

    public init(
        selectedTab: BrainTab = .dashboard,
        selectedEntryId: Int64? = nil,
        badges: [BrainTab: Int] = [:]
    ) {
        self.selectedTab = selectedTab
        self.selectedEntryId = selectedEntryId
        self.badges = badges
    }

    // Get badge count for a tab (0 if none).
    public func badge(for tab: BrainTab) -> Int {
        badges[tab] ?? 0
    }

    // Set badge count for a tab.
    public mutating func setBadge(_ count: Int, for tab: BrainTab) {
        if count > 0 {
            badges[tab] = count
        } else {
            badges.removeValue(forKey: tab)
        }
    }

    // Total badge count across all tabs.
    public var totalBadgeCount: Int {
        badges.values.reduce(0, +)
    }
}
