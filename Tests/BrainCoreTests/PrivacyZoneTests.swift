import Testing
import Foundation
import GRDB
@testable import BrainCore

@Suite("Privacy Zones")
struct PrivacyZoneTests {

    private func makeServices() throws -> (PrivacyZoneService, TagService, EntryService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (
            PrivacyZoneService(pool: db.pool),
            TagService(pool: db.pool),
            EntryService(pool: db.pool),
            db
        )
    }

    // MARK: - PrivacyZoneService CRUD

    @Test("Set and retrieve privacy zone for tag")
    func setAndRetrieve() throws {
        let (pzs, ts, _, _) = try makeServices()
        let tag = try ts.create(Tag(name: "medizinisch"))

        let zone = try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)
        #expect(zone.level == .onDeviceOnly)
        #expect(zone.tagId == tag.id!)

        let fetched = try pzs.zone(forTagId: tag.id!)
        #expect(fetched?.level == .onDeviceOnly)
    }

    @Test("Upsert updates existing zone")
    func upsertUpdates() throws {
        let (pzs, ts, _, _) = try makeServices()
        let tag = try ts.create(Tag(name: "finanzen"))

        try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)
        try pzs.setLevel(.approvedCloudOnly, forTagId: tag.id!)

        let zone = try pzs.zone(forTagId: tag.id!)
        #expect(zone?.level == .approvedCloudOnly)
    }

    @Test("Remove zone resets to no zone")
    func removeZone() throws {
        let (pzs, ts, _, _) = try makeServices()
        let tag = try ts.create(Tag(name: "geheim"))

        try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)
        try pzs.removeZone(forTagId: tag.id!)

        let zone = try pzs.zone(forTagId: tag.id!)
        #expect(zone == nil)
    }

    @Test("List all zones with tag names")
    func listAll() throws {
        let (pzs, ts, _, _) = try makeServices()
        let tag1 = try ts.create(Tag(name: "gesundheit"))
        let tag2 = try ts.create(Tag(name: "finanzen"))

        try pzs.setLevel(.onDeviceOnly, forTagId: tag1.id!)
        try pzs.setLevel(.approvedCloudOnly, forTagId: tag2.id!)

        let all = try pzs.listAll()
        #expect(all.count == 2)
        #expect(all[0].tagName == "finanzen") // alphabetical
        #expect(all[1].tagName == "gesundheit")
    }

    // MARK: - Strictest Level

    @Test("Strictest level for entry with one restricted tag")
    func strictestLevelSingleTag() throws {
        let (pzs, ts, es, _) = try makeServices()

        let tag = try ts.create(Tag(name: "medizinisch"))
        try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)

        var entry = Entry(type: .note, title: "Arztbesuch")
        entry = try es.create(entry)
        try ts.attach(tagId: tag.id!, to: entry.id!)

        let level = try pzs.strictestLevel(forEntryId: entry.id!)
        #expect(level == .onDeviceOnly)
    }

    @Test("Strictest level picks most restrictive")
    func strictestLevelMultipleTags() throws {
        let (pzs, ts, es, _) = try makeServices()

        let tagMed = try ts.create(Tag(name: "medizinisch"))
        let tagBiz = try ts.create(Tag(name: "geschaeft"))
        try pzs.setLevel(.onDeviceOnly, forTagId: tagMed.id!)
        try pzs.setLevel(.approvedCloudOnly, forTagId: tagBiz.id!)

        var entry = Entry(type: .note, title: "Krankenversicherung geschaeftlich")
        entry = try es.create(entry)
        try ts.attach(tagId: tagMed.id!, to: entry.id!)
        try ts.attach(tagId: tagBiz.id!, to: entry.id!)

        let level = try pzs.strictestLevel(forEntryId: entry.id!)
        #expect(level == .onDeviceOnly) // onDeviceOnly > approvedCloudOnly
    }

    @Test("Unrestricted for entry with no restricted tags")
    func unrestrictedDefault() throws {
        let (pzs, ts, es, _) = try makeServices()

        let tag = try ts.create(Tag(name: "hobby"))
        var entry = Entry(type: .thought, title: "Modellbau")
        entry = try es.create(entry)
        try ts.attach(tagId: tag.id!, to: entry.id!)

        let level = try pzs.strictestLevel(forEntryId: entry.id!)
        #expect(level == .unrestricted)
    }

    @Test("Strictest level by tag names")
    func strictestLevelByTagNames() throws {
        let (pzs, ts, _, _) = try makeServices()

        let tag = try ts.create(Tag(name: "medizinisch"))
        try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)

        let level = try pzs.strictestLevel(forTagNames: ["medizinisch", "hobby"])
        #expect(level == .onDeviceOnly)
    }

    @Test("Empty tag names returns unrestricted")
    func emptyTagNames() throws {
        let (pzs, _, _, _) = try makeServices()
        let level = try pzs.strictestLevel(forTagNames: [])
        #expect(level == .unrestricted)
    }

    // MARK: - LLMRouter Privacy Zone Integration

    private let cloudProvider = PrivacyMockProvider(
        name: "Claude",
        isAvailable: true,
        supportsStreaming: true,
        isOnDevice: false,
        contextWindow: 200_000
    )

    private let onDeviceProvider = PrivacyMockProvider(
        name: "Llama-3B",
        isAvailable: true,
        supportsStreaming: true,
        isOnDevice: true,
        contextWindow: 4_096
    )

    @Test("onDeviceOnly forces on-device routing")
    func onDeviceOnlyRouting() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medical note")],
            privacyLevel: .onDeviceOnly
        )
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    @Test("onDeviceOnly returns nil when no on-device provider")
    func onDeviceOnlyNoProvider() {
        let router = LLMRouter(
            providers: [cloudProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medical")],
            privacyLevel: .onDeviceOnly
        )
        let provider = router.route(request)
        #expect(provider == nil)
    }

    @Test("approvedCloudOnly routes to cloud")
    func approvedCloudOnlyRouting() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "business data")],
            privacyLevel: .approvedCloudOnly
        )
        let provider = router.route(request)
        #expect(provider?.name == "Claude")
    }

    @Test("approvedCloudOnly falls back to on-device if no cloud")
    func approvedCloudOnlyFallback() {
        let router = LLMRouter(
            providers: [onDeviceProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "business")],
            privacyLevel: .approvedCloudOnly
        )
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    @Test("unrestricted uses normal routing (cloud for medium)")
    func unrestrictedNormalRouting() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "hello")],
            privacyLevel: .unrestricted
        )
        let provider = router.route(request)
        #expect(provider?.name == "Claude")
    }

    @Test("Privacy zone takes precedence over complexity")
    func privacyOverridesComplexity() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceProvider],
            isConnected: { true }
        )

        // High complexity normally routes to cloud, but onDeviceOnly overrides
        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "complex medical analysis")],
            complexity: .high,
            privacyLevel: .onDeviceOnly
        )
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    // MARK: - PrivacyLevel Model

    @Test("PrivacyLevel raw values")
    func privacyLevelRawValues() {
        #expect(PrivacyLevel.unrestricted.rawValue == "unrestricted")
        #expect(PrivacyLevel.onDeviceOnly.rawValue == "on_device_only")
        #expect(PrivacyLevel.approvedCloudOnly.rawValue == "approved_cloud_only")
    }

    @Test("PrivacyLevel round-trip encoding")
    func privacyLevelCodable() throws {
        let original = PrivacyLevel.onDeviceOnly
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PrivacyLevel.self, from: data)
        #expect(decoded == original)
    }

    @Test("Cascade delete removes privacy zone when tag is deleted")
    func cascadeDeleteTag() throws {
        let (pzs, ts, _, _) = try makeServices()
        let tag = try ts.create(Tag(name: "temp"))
        try pzs.setLevel(.onDeviceOnly, forTagId: tag.id!)

        try ts.delete(id: tag.id!)

        let zone = try pzs.zone(forTagId: tag.id!)
        #expect(zone == nil)
    }
}

// Re-use the PrivacyMockProvider from LLMRouterTests (same structure).
private struct PrivacyMockProvider: LLMProvider, Sendable {
    var name: String
    var isAvailable: Bool
    var supportsStreaming: Bool
    var isOnDevice: Bool
    var contextWindow: Int

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "mock", providerName: name)
    }
}
