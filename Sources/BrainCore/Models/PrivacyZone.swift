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

public extension PrivacyLevel {
    // Skill-facing spelling as used in a step's `privacyLevel` property:
    // the raw value ("on_device_only") as well as camelCase ("onDeviceOnly")
    // and kebab-case, case-insensitive. nil for anything else.
    init?(skillValue: String) {
        let key = skillValue.lowercased().filter { !"_- ".contains($0) }
        switch key {
        case "unrestricted": self = .unrestricted
        case "ondeviceonly": self = .onDeviceOnly
        case "approvedcloudonly": self = .approvedCloudOnly
        default: return nil
        }
    }

    // Strictness order: onDeviceOnly > approvedCloudOnly > unrestricted.
    var strictness: Int {
        switch self {
        case .unrestricted: return 0
        case .approvedCloudOnly: return 1
        case .onDeviceOnly: return 2
        }
    }

    // The stricter of two levels.
    static func stricter(_ a: PrivacyLevel, _ b: PrivacyLevel) -> PrivacyLevel {
        a.strictness >= b.strictness ? a : b
    }
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
