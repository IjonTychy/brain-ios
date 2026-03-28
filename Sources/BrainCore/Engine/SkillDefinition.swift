import Foundation

// MARK: - Top-level skill definition

// The compiled JSON representation of a skill.
// This is the "protein" that the runtime engine executes.
// Generated from .brainskill.md by the LLM (Ribosom).
public struct SkillDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var version: String
    public var screens: [String: ScreenNode]
    public var actions: [String: ActionDefinition]?
    public var data: [String: DataQuery]?

    public init(
        id: String,
        version: String = "1.0",
        screens: [String: ScreenNode],
        actions: [String: ActionDefinition]? = nil,
        data: [String: DataQuery]? = nil
    ) {
        self.id = id
        self.version = version
        self.screens = screens
        self.actions = actions
        self.data = data
    }
}

// A declarative data query that a skill can define to automatically
// load data from the DB into template variables before rendering.
public struct DataQuery: Codable, Sendable, Equatable {
    public var source: String                     // "entries", "tags", "knowledgeFacts", "emailCache"
    public var filter: [String: PropertyValue]?   // e.g. {"type": "habit", "status": "active"}
    public var sort: String?                      // e.g. "createdAt DESC"
    public var limit: Int?                        // e.g. 20
    public var fields: [String]?                  // e.g. ["title", "status", "createdAt"]

    public init(
        source: String,
        filter: [String: PropertyValue]? = nil,
        sort: String? = nil,
        limit: Int? = nil,
        fields: [String]? = nil
    ) {
        self.source = source
        self.filter = filter
        self.sort = sort
        self.limit = limit
        self.fields = fields
    }
}

// MARK: - Screen nodes (UI tree)

// A node in the UI tree. Recursive structure matching the JSON format.
// Each node has a `type` that maps to a UI Primitive (e.g. "stack", "text", "button").
public struct ScreenNode: Codable, Sendable, Equatable {
    public var type: String                          // UI Primitive type
    public var properties: [String: PropertyValue]?  // Type-specific properties
    public var children: [ScreenNode]?               // Child nodes (for containers)
    public var onTap: String?                        // Action name to trigger on tap
    public var condition: String?                    // Expression: show/hide condition
    public var id: String?                           // Optional node identifier

    public init(
        type: String,
        properties: [String: PropertyValue]? = nil,
        children: [ScreenNode]? = nil,
        onTap: String? = nil,
        condition: String? = nil,
        id: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.children = children
        self.onTap = onTap
        self.condition = condition
        self.id = id
    }
}

// MARK: - Property values

// A property value that can be a literal or a template expression.
// Supports: string, number, boolean, array, object, or expression ({{...}}).
public enum PropertyValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([PropertyValue])
    case object([String: PropertyValue])

    // Check if the string value contains a template expression.
    public var isExpression: Bool {
        if case .string(let s) = self {
            return s.contains("{{") && s.contains("}}")
        }
        return false
    }

    // Extract the raw string value (for expressions or plain text).
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([PropertyValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: PropertyValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(
                PropertyValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode PropertyValue"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Validation Helpers

extension SkillDefinition {
    /// Collect all action names referenced in the screen tree (from onTap and button action properties).
    public func referencedActions() -> Set<String> {
        var actions: Set<String> = []
        for (_, screen) in screens {
            Self.collectActions(from: screen, into: &actions)
        }
        return actions
    }

    private static func collectActions(from node: ScreenNode, into actions: inout Set<String>) {
        if let onTap = node.onTap, !onTap.isEmpty {
            actions.insert(onTap)
        }
        if let actionProp = node.properties?["action"]?.stringValue, !actionProp.isEmpty {
            actions.insert(actionProp)
        }
        if let children = node.children {
            for child in children {
                collectActions(from: child, into: &actions)
            }
        }
    }
}

// MARK: - Actions

// A workflow definition composed of sequential steps.
public struct ActionDefinition: Codable, Sendable, Equatable {
    public var steps: [ActionStep]

    public init(steps: [ActionStep]) {
        self.steps = steps
    }
}

// A single step in an action workflow.
public struct ActionStep: Codable, Sendable, Equatable {
    public var type: String                          // Action Primitive type
    public var properties: [String: PropertyValue]?  // Parameters for the action

    public init(type: String, properties: [String: PropertyValue]? = nil) {
        self.type = type
        self.properties = properties
    }
}
