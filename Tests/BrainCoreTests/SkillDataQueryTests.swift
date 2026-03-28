import Testing
import Foundation
@testable import BrainCore

@Suite("DataQuery & AUFTRAG-SELBSTERWEITERUNG")
struct SkillDataQueryTests {

    // MARK: - DataQuery encoding/decoding

    @Test("DataQuery encodes and decodes correctly via JSON")
    func dataQueryRoundTrip() throws {
        let query = DataQuery(
            source: "entries",
            filter: ["type": .string("habit"), "status": .string("active")],
            sort: "createdAt DESC",
            limit: 20,
            fields: ["title", "status", "createdAt"]
        )

        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(DataQuery.self, from: data)
        #expect(decoded == query)
    }

    @Test("DataQuery with all fields set roundtrips correctly")
    func dataQueryAllFields() throws {
        let query = DataQuery(
            source: "knowledgeFacts",
            filter: ["category": .string("science"), "rating": .int(5)],
            sort: "updatedAt ASC",
            limit: 100,
            fields: ["id", "title", "body", "category", "rating"]
        )

        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(DataQuery.self, from: data)

        #expect(decoded.source == "knowledgeFacts")
        #expect(decoded.filter?["category"]?.stringValue == "science")
        #expect(decoded.filter?["rating"]?.intValue == 5)
        #expect(decoded.sort == "updatedAt ASC")
        #expect(decoded.limit == 100)
        #expect(decoded.fields == ["id", "title", "body", "category", "rating"])
    }

    @Test("DataQuery with minimal fields (source only) works")
    func dataQueryMinimal() throws {
        let query = DataQuery(source: "tags")

        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(DataQuery.self, from: data)

        #expect(decoded.source == "tags")
        #expect(decoded.filter == nil)
        #expect(decoded.sort == nil)
        #expect(decoded.limit == nil)
        #expect(decoded.fields == nil)
    }

    @Test("DataQuery decodes from JSON string")
    func dataQueryFromJSON() throws {
        let json = """
        {
            "source": "emailCache",
            "filter": {"unread": true},
            "sort": "receivedAt DESC",
            "limit": 50,
            "fields": ["subject", "sender"]
        }
        """
        let query = try JSONDecoder().decode(DataQuery.self, from: json.data(using: .utf8)!)

        #expect(query.source == "emailCache")
        #expect(query.filter?["unread"]?.boolValue == true)
        #expect(query.sort == "receivedAt DESC")
        #expect(query.limit == 50)
        #expect(query.fields?.count == 2)
    }

    // MARK: - SkillDefinition with data field

    @Test("SkillDefinition with data field encodes and decodes correctly")
    func skillDefinitionWithData() throws {
        let skill = SkillDefinition(
            id: "habit-tracker",
            screens: [
                "main": ScreenNode(type: "text", properties: ["value": .string("Habits")])
            ],
            data: [
                "habits": DataQuery(
                    source: "entries",
                    filter: ["type": .string("habit")],
                    sort: "createdAt DESC",
                    limit: 20
                )
            ]
        )

        let encoded = try JSONEncoder().encode(skill)
        let decoded = try JSONDecoder().decode(SkillDefinition.self, from: encoded)

        #expect(decoded == skill)
        #expect(decoded.data?["habits"]?.source == "entries")
        #expect(decoded.data?["habits"]?.limit == 20)
    }

    @Test("SkillDefinition without data field (nil) still works — backward compat")
    func skillDefinitionWithoutData() throws {
        let skill = SkillDefinition(
            id: "simple",
            screens: [
                "main": ScreenNode(type: "text", properties: ["value": .string("Hello")])
            ]
        )

        let encoded = try JSONEncoder().encode(skill)
        let decoded = try JSONDecoder().decode(SkillDefinition.self, from: encoded)

        #expect(decoded == skill)
        #expect(decoded.data == nil)
    }

    @Test("Existing JSON without data key still decodes (backward compat)")
    func backwardCompatNoDataKey() throws {
        let json = """
        {
            "id": "legacy-skill",
            "version": "1.0",
            "screens": {
                "main": {
                    "type": "text",
                    "properties": {"value": "Legacy"}
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        #expect(skill.id == "legacy-skill")
        #expect(skill.data == nil)
        #expect(skill.screens["main"]?.type == "text")
    }

    @Test("JSON with data key decodes into [String: DataQuery]")
    func jsonWithDataKey() throws {
        let json = """
        {
            "id": "data-skill",
            "version": "1.0",
            "screens": {
                "main": {"type": "text", "properties": {"value": "{{data.items}}"}}
            },
            "data": {
                "items": {
                    "source": "entries",
                    "filter": {"type": "todo"},
                    "sort": "createdAt DESC",
                    "limit": 10,
                    "fields": ["title", "status"]
                },
                "tags": {
                    "source": "tags"
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        #expect(skill.data?.count == 2)

        let items = try #require(skill.data?["items"])
        #expect(items.source == "entries")
        #expect(items.filter?["type"]?.stringValue == "todo")
        #expect(items.sort == "createdAt DESC")
        #expect(items.limit == 10)
        #expect(items.fields == ["title", "status"])

        let tags = try #require(skill.data?["tags"])
        #expect(tags.source == "tags")
        #expect(tags.filter == nil)
    }

    // MARK: - ScreenNode action collection

    @Test("ScreenNode with onTap property can be read")
    func screenNodeOnTap() throws {
        let json = """
        {
            "type": "button",
            "properties": {"label": "Save"},
            "onTap": "saveAction"
        }
        """
        let node = try JSONDecoder().decode(ScreenNode.self, from: json.data(using: .utf8)!)
        #expect(node.type == "button")
        #expect(node.onTap == "saveAction")
    }

    @Test("ScreenNode with action property in a button can be read")
    func screenNodeButtonAction() throws {
        let json = """
        {
            "type": "button",
            "properties": {"label": "Delete", "action": "deleteAction"},
            "onTap": "deleteAction"
        }
        """
        let node = try JSONDecoder().decode(ScreenNode.self, from: json.data(using: .utf8)!)
        #expect(node.properties?["action"]?.stringValue == "deleteAction")
        #expect(node.onTap == "deleteAction")
    }

    @Test("Nested ScreenNode children traversal works")
    func nestedChildrenTraversal() throws {
        let json = """
        {
            "type": "stack",
            "properties": {"direction": "vertical"},
            "children": [
                {
                    "type": "text",
                    "properties": {"value": "Title"}
                },
                {
                    "type": "stack",
                    "properties": {"direction": "horizontal"},
                    "children": [
                        {
                            "type": "button",
                            "properties": {"label": "Save"},
                            "onTap": "saveAction"
                        },
                        {
                            "type": "button",
                            "properties": {"label": "Cancel"},
                            "onTap": "cancelAction"
                        }
                    ]
                }
            ]
        }
        """
        let root = try JSONDecoder().decode(ScreenNode.self, from: json.data(using: .utf8)!)

        // Collect all onTap actions by traversing the tree
        let actions = collectOnTapActions(from: root)
        #expect(actions.count == 2)
        #expect(actions.contains("saveAction"))
        #expect(actions.contains("cancelAction"))
    }

    @Test("Deep nesting traversal finds all actions")
    func deepNestingTraversal() throws {
        let leaf = ScreenNode(type: "button", properties: ["label": .string("Deep")], onTap: "deepAction")
        let level2 = ScreenNode(type: "stack", children: [leaf])
        let level1 = ScreenNode(type: "stack", children: [
            ScreenNode(type: "button", onTap: "topAction"),
            level2
        ])
        let root = ScreenNode(type: "stack", children: [level1])

        let actions = collectOnTapActions(from: root)
        #expect(actions.count == 2)
        #expect(actions.contains("deepAction"))
        #expect(actions.contains("topAction"))
    }

    @Test("ScreenNode without onTap or children returns empty actions")
    func noActionsNode() {
        let node = ScreenNode(type: "text", properties: ["value": .string("Hello")])
        let actions = collectOnTapActions(from: node)
        #expect(actions.isEmpty)
    }

    // MARK: - Helper

    /// Recursively collects all onTap action names from a ScreenNode tree.
    private func collectOnTapActions(from node: ScreenNode) -> [String] {
        var actions: [String] = []
        if let tap = node.onTap {
            actions.append(tap)
        }
        if let children = node.children {
            for child in children {
                actions.append(contentsOf: collectOnTapActions(from: child))
            }
        }
        return actions
    }
}
