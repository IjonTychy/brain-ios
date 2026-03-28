import Testing
import Foundation
@testable import BrainCore

@Suite("Navigation Model")
struct NavigationTests {

    @Test("BrainTab has 11 cases (10 modules + more)")
    func tabCount() {
        #expect(BrainTab.allCases.count == 11)
        #expect(BrainTab.mainTabs.count == 5)
        #expect(BrainTab.moreTabs.count == 6)
    }

    @Test("Each tab has a title and icon")
    func tabMetadata() {
        for tab in BrainTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }

    @Test("NavigationState defaults")
    func defaults() {
        let state = NavigationState()
        #expect(state.selectedTab == .dashboard)
        #expect(state.selectedEntryId == nil)
        #expect(state.badges.isEmpty)
        #expect(state.totalBadgeCount == 0)
    }

    @Test("Badge operations")
    func badges() {
        var state = NavigationState()

        state.setBadge(5, for: .mail)
        state.setBadge(3, for: .chat)

        #expect(state.badge(for: .mail) == 5)
        #expect(state.badge(for: .chat) == 3)
        #expect(state.badge(for: .calendar) == 0)
        #expect(state.totalBadgeCount == 8)

        // Clear badge
        state.setBadge(0, for: .mail)
        #expect(state.badge(for: .mail) == 0)
        #expect(state.totalBadgeCount == 3)
    }

    @Test("NavigationState is Codable round-trip")
    func codableRoundTrip() throws {
        var state = NavigationState(selectedTab: .mail, selectedEntryId: 42)
        state.setBadge(7, for: .mail)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NavigationState.self, from: data)

        #expect(decoded.selectedTab == .mail)
        #expect(decoded.selectedEntryId == 42)
        #expect(decoded.badge(for: .mail) == 7)
    }

    @Test("BrainTab is Codable round-trip")
    func tabCodable() throws {
        let tab = BrainTab.brainAdmin
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(BrainTab.self, from: data)
        #expect(decoded == .brainAdmin)
    }
}
