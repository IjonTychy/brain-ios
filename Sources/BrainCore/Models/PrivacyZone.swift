import GRDB

// Privacy zone level that controls LLM routing for tagged entries.
// Entries with sensitive tags (e.g. "medizinisch") can be restricted
// to on-device processing only.
public enum PrivacyLevel: String, Codable, Sendable, CaseIterable {
    // No restriction — any LLM provider may be used.
    case unrestricted
    // Must use on-device LLM only. Data never leaves the device.
    case onDeviceOnly = "on_device_only"
    // May use cloud LLM, but only the user's preferred/approved provider.
    case approvedCloudOnly = "approved_cloud_only"
}

// Maps a tag to a privacy level. When an entry has a tag with a
// privacy zone, the LLM router enforces the restriction.
public struct PrivacyZone: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var tagId: Int64
    public var level: PrivacyLevel
    public var createdAt: String?

    public init(id: Int64? = nil, tagId: Int64, level: PrivacyLevel, createdAt: String? = nil) {
        self.id = id
        self.tagId = tagId
        self.level = level
        self.createdAt = createdAt
    }
}

extension PrivacyZone: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "privacyZones" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
