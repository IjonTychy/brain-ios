import Testing
import Foundation
@testable import BrainCore

@Suite("Skill Definition JSON")
struct SkillDefinitionTests {

    @Test("Parse minimal skill JSON")
    func parseMinimal() throws {
        let json = """
        {
            "id": "hello",
            "version": "1.0",
            "screens": {
                "main": {
                    "type": "text",
                    "properties": {
                        "value": "Hello World",
                        "style": "largeTitle"
                    }
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        #expect(skill.id == "hello")
        #expect(skill.screens["main"]?.type == "text")
        #expect(skill.screens["main"]?.properties?["value"]?.stringValue == "Hello World")
    }

    @Test("Parse nested screen tree")
    func parseNested() throws {
        let json = """
        {
            "id": "nested",
            "version": "1.0",
            "screens": {
                "main": {
                    "type": "stack",
                    "properties": {"direction": "vertical"},
                    "children": [
                        {"type": "text", "properties": {"value": "Title", "style": "headline"}},
                        {"type": "text", "properties": {"value": "Body"}}
                    ]
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        let main = skill.screens["main"]!
        #expect(main.type == "stack")
        #expect(main.children?.count == 2)
        #expect(main.children?[0].type == "text")
        #expect(main.children?[0].properties?["style"]?.stringValue == "headline")
    }

    @Test("Parse actions with steps")
    func parseActions() throws {
        let json = """
        {
            "id": "actions-test",
            "version": "1.0",
            "screens": {"main": {"type": "text", "properties": {"value": "Hi"}}},
            "actions": {
                "save": {
                    "steps": [
                        {"type": "entry.create", "properties": {"title": "{{input.value}}"}},
                        {"type": "haptic", "properties": {"style": "success"}},
                        {"type": "toast", "properties": {"message": "Gespeichert!"}}
                    ]
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        let save = skill.actions?["save"]
        #expect(save?.steps.count == 3)
        #expect(save?.steps[0].type == "entry.create")
        #expect(save?.steps[1].type == "haptic")
    }

    @Test("PropertyValue handles all types")
    func propertyValueTypes() throws {
        let json = """
        {
            "id": "types",
            "version": "1.0",
            "screens": {
                "main": {
                    "type": "test",
                    "properties": {
                        "text": "hello",
                        "number": 42,
                        "decimal": 3.14,
                        "flag": true,
                        "items": ["a", "b", "c"]
                    }
                }
            }
        }
        """
        let skill = try JSONDecoder().decode(SkillDefinition.self, from: json.data(using: .utf8)!)
        let props = skill.screens["main"]!.properties!

        #expect(props["text"]?.stringValue == "hello")
        #expect(props["number"]?.intValue == 42)
        #expect(props["decimal"]?.doubleValue == 3.14)
        #expect(props["flag"]?.boolValue == true)
        if case .array(let arr) = props["items"] {
            #expect(arr.count == 3)
        } else {
            Issue.record("Expected array")
        }
    }

    @Test("Expression detection in property values")
    func expressionDetection() {
        let expr = PropertyValue.string("{{user.name}}")
        #expect(expr.isExpression == true)

        let plain = PropertyValue.string("Hello World")
        #expect(plain.isExpression == false)

        let num = PropertyValue.int(42)
        #expect(num.isExpression == false)
    }

    @Test("Codable round-trip preserves structure")
    func codableRoundTrip() throws {
        let original = SkillDefinition(
            id: "round-trip",
            screens: [
                "main": ScreenNode(
                    type: "stack",
                    properties: ["direction": .string("vertical")],
                    children: [
                        ScreenNode(type: "text", properties: ["value": .string("Hello")])
                    ]
                )
            ],
            actions: [
                "tap": ActionDefinition(steps: [
                    ActionStep(type: "haptic", properties: ["style": .string("success")])
                ])
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkillDefinition.self, from: data)
        #expect(decoded == original)
    }
}
