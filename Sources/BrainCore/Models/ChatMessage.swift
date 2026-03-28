import Foundation
import GRDB

// Closed set of allowed message roles (F-18).
// Prevents stored prompt injection via arbitrary role strings like "system".
public enum ChatRole: String, Codable, Sendable, DatabaseValueConvertible {
    case user
    case assistant
}

// A single message in the chat history between user and assistant.
public struct ChatMessage: Codable, Sendable, Identifiable {
    // Local UUID ensures stable ForEach identity even before DB insertion (id is nil).
    // Without this, multiple nil-id messages collide and SwiftUI shows duplicates.
    public let localId: UUID
    public var id: Int64?
    public var role: ChatRole
    public var content: String
    public var toolCalls: String?  // JSON
    public var sources: String?    // JSON
    public var channel: String
    public var model: String?      // LLM model that generated this response
    public var createdAt: String?

    public init(
        id: Int64? = nil,
        role: ChatRole,
        content: String,
        toolCalls: String? = nil,
        sources: String? = nil,
        channel: String = "app",
        model: String? = nil,
        createdAt: String? = nil
    ) {
        self.localId = UUID()
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.sources = sources
        self.channel = channel
        self.model = model
        self.createdAt = createdAt
    }
}

extension ChatMessage {
    // CodingKeys exclude localId from Codable (not a DB column)
    private enum CodingKeys: String, CodingKey {
        case id, role, content, toolCalls, sources, channel, model, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.localId = UUID()
        self.id = try c.decodeIfPresent(Int64.self, forKey: .id)
        self.role = try c.decode(ChatRole.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.toolCalls = try c.decodeIfPresent(String.self, forKey: .toolCalls)
        self.sources = try c.decodeIfPresent(String.self, forKey: .sources)
        self.channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "app"
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

extension ChatMessage: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "chatHistory" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
