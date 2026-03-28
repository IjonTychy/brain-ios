import Testing
import Foundation
@testable import BrainCore

@Suite("Component Registry")
struct ComponentRegistryTests {

    let registry = ComponentRegistry()

    @Test("Default registry has 90 primitives")
    func defaultCount() {
        // 15 Layout + 12 Content + 13 Input + 11 Interaction + 15 Data
        // + 6 Feedback + 5 Container + 6 System + 7 Special = 90
        #expect(registry.registeredTypes.count == 90)
    }

    @Test("All categories have primitives")
    func allCategories() {
        for category in PrimitiveCategory.allCases {
            let prims = registry.primitives(in: category)
            #expect(!prims.isEmpty, "Category \(category) should have primitives")
        }
    }

    @Test("Lookup known primitive")
    func lookupKnown() {
        let text = registry.lookup("text")
        #expect(text != nil)
        #expect(text?.category == .content)
        #expect(text?.requiredProperties.contains("value") == true)
    }

    @Test("Lookup unknown returns nil")
    func lookupUnknown() {
        #expect(registry.lookup("nonexistent") == nil)
        #expect(registry.isRegistered("nonexistent") == false)
    }

    @Test("Container primitives support children")
    func containersSupportsChildren() {
        let stack = registry.lookup("stack")
        #expect(stack?.supportsChildren == true)

        let list = registry.lookup("list")
        #expect(list?.supportsChildren == true)

        // text should not support children
        let text = registry.lookup("text")
        #expect(text?.supportsChildren == false)
    }

    @Test("Validate valid screen node")
    func validateValid() {
        let node = ScreenNode(
            type: "stack",
            properties: ["direction": .string("vertical")],
            children: [
                ScreenNode(type: "text", properties: ["value": .string("Hello")])
            ]
        )
        let errors = registry.validate(node)
        #expect(errors.isEmpty)
    }

    @Test("Validate catches unknown type")
    func validateUnknownType() {
        let node = ScreenNode(type: "nonexistent")
        let errors = registry.validate(node)
        #expect(errors.count == 1)
        #expect(errors[0].contains("Unknown primitive"))
    }

    @Test("Validate catches missing required property")
    func validateMissingRequired() {
        let node = ScreenNode(type: "text")  // missing "value"
        let errors = registry.validate(node)
        #expect(errors.count == 1)
        #expect(errors[0].contains("requires property 'value'"))
    }

    @Test("Validate catches children on non-container")
    func validateChildrenOnNonContainer() {
        let node = ScreenNode(
            type: "text",
            properties: ["value": .string("Hi")],
            children: [ScreenNode(type: "text", properties: ["value": .string("Child")])]
        )
        let errors = registry.validate(node)
        #expect(errors.count == 1)
        #expect(errors[0].contains("does not support children"))
    }

    @Test("Validate recurses into children")
    func validateRecursive() {
        let node = ScreenNode(
            type: "stack",
            children: [
                ScreenNode(type: "unknown_type")
            ]
        )
        let errors = registry.validate(node)
        #expect(errors.contains { $0.contains("Unknown primitive") })
    }

    @Test("ThemeConfig defaults")
    func themeDefaults() {
        let theme = ThemeConfig()
        #expect(theme.colorScheme == .system)
        #expect(theme.primaryColor == "#007AFF")
        #expect(theme.fontSize == .medium)
        #expect(theme.cornerRadius == 12.0)
    }

    @Test("ThemeConfig is Codable")
    func themeCodable() throws {
        let original = ThemeConfig(primaryColor: "#FF0000", fontSize: .large)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThemeConfig.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - New category tests

    @Test("Feedback category has 6 primitives")
    func feedbackCategory() {
        let prims = registry.primitives(in: .feedback)
        #expect(prims.count == 6)
        let types = prims.map(\.type)
        #expect(types.contains("alert"))
        #expect(types.contains("toast"))
        #expect(types.contains("banner"))
        #expect(types.contains("loading"))
        #expect(types.contains("skeleton"))
        #expect(types.contains("haptic"))
    }

    @Test("Container category has 5 primitives")
    func containerCategory() {
        let prims = registry.primitives(in: .container)
        #expect(prims.count == 5)
        let types = prims.map(\.type)
        #expect(types.contains("card"))
        #expect(types.contains("grouped-list"))
        #expect(types.contains("toolbar"))
        #expect(types.contains("overlay"))
        #expect(types.contains("full-screen-cover"))
    }

    @Test("System category has 6 primitives")
    func systemCategory() {
        let prims = registry.primitives(in: .system)
        #expect(prims.count == 6)
        let types = prims.map(\.type)
        #expect(types.contains("open-url"))
        #expect(types.contains("copy-button"))
        #expect(types.contains("qr-code"))
        #expect(types.contains("video-player"))
        #expect(types.contains("live-activity"))
        #expect(types.contains("widget-preview"))
    }

    @Test("Layout category has 15 primitives")
    func layoutCategory() {
        let prims = registry.primitives(in: .layout)
        #expect(prims.count == 15)
        #expect(prims.map(\.type).contains("lazy-vstack"))
        #expect(prims.map(\.type).contains("section"))
        #expect(prims.map(\.type).contains("disclosure-group"))
    }

    @Test("Content category has 12 primitives")
    func contentCategory() {
        let prims = registry.primitives(in: .content)
        #expect(prims.count == 12)
        #expect(prims.map(\.type).contains("label"))
        #expect(prims.map(\.type).contains("async-image"))
        #expect(prims.map(\.type).contains("color-swatch"))
    }

    @Test("Input category has 13 primitives")
    func inputCategory() {
        let prims = registry.primitives(in: .input)
        #expect(prims.count == 13)
        #expect(prims.map(\.type).contains("multi-picker"))
        #expect(prims.map(\.type).contains("photo-picker"))
        #expect(prims.map(\.type).contains("paste-button"))
    }

    @Test("Interaction category has 11 primitives")
    func interactionCategory() {
        let prims = registry.primitives(in: .interaction)
        #expect(prims.count == 11)
        #expect(prims.map(\.type).contains("navigation-link"))
        #expect(prims.map(\.type).contains("context-menu"))
        #expect(prims.map(\.type).contains("share-link"))
    }

    @Test("Data category has 15 primitives")
    func dataCategory() {
        let prims = registry.primitives(in: .data)
        #expect(prims.count == 15)
        #expect(prims.map(\.type).contains("line-chart"))
        #expect(prims.map(\.type).contains("bar-chart"))
        #expect(prims.map(\.type).contains("pie-chart"))
        #expect(prims.map(\.type).contains("sparkline"))
        #expect(prims.map(\.type).contains("metric"))
        #expect(prims.map(\.type).contains("heat-map"))
    }

    @Test("Special category has 7 primitives")
    func specialCategory() {
        let prims = registry.primitives(in: .special)
        #expect(prims.count == 7)
    }

    // MARK: - Validation tests for new primitives

    @Test("Validate chart with data")
    func validateChart() {
        let node = ScreenNode(
            type: "line-chart",
            properties: ["data": .array([.int(1), .int(2), .int(3)])]
        )
        let errors = registry.validate(node)
        #expect(errors.isEmpty)
    }

    @Test("Validate qr-code requires data")
    func validateQRCode() {
        let node = ScreenNode(type: "qr-code")
        let errors = registry.validate(node)
        #expect(errors.count == 1)
        #expect(errors[0].contains("requires property 'data'"))
    }

    @Test("Validate card supports children")
    func validateCard() {
        let node = ScreenNode(
            type: "card",
            children: [
                ScreenNode(type: "text", properties: ["value": .string("Inhalt")])
            ]
        )
        let errors = registry.validate(node)
        #expect(errors.isEmpty)
    }

    @Test("Validate skeleton supports children")
    func validateSkeleton() {
        let node = ScreenNode(
            type: "skeleton",
            children: [
                ScreenNode(type: "text", properties: ["value": .string("Loading...")])
            ]
        )
        let errors = registry.validate(node)
        #expect(errors.isEmpty)
    }

    @Test("Validate multi-picker requires options")
    func validateMultiPicker() {
        let node = ScreenNode(type: "multi-picker")
        let errors = registry.validate(node)
        #expect(errors.count == 1)
        #expect(errors[0].contains("requires property 'options'"))
    }

    @Test("Validate async-image requires url")
    func validateAsyncImage() {
        let withUrl = ScreenNode(type: "async-image", properties: ["url": .string("https://example.com/img.png")])
        #expect(registry.validate(withUrl).isEmpty)

        let withoutUrl = ScreenNode(type: "async-image")
        #expect(registry.validate(withoutUrl).count == 1)
    }

    @Test("All container category primitives support children")
    func allContainersSupportChildren() {
        for prim in registry.primitives(in: .container) {
            #expect(prim.supportsChildren, "\(prim.type) should support children")
        }
    }

    @Test("No duplicate primitive types")
    func noDuplicates() {
        let types = registry.registeredTypes
        let uniqueTypes = Set(types)
        #expect(types.count == uniqueTypes.count, "Found duplicate primitive types")
    }
}
