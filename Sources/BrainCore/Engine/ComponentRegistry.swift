import Foundation

// Categories of UI primitives in the component catalog.
public enum PrimitiveCategory: String, Codable, Sendable, CaseIterable {
    case layout
    case content
    case input
    case interaction
    case data
    case feedback
    case container
    case system
    case special
}

// Metadata about a registered UI primitive.
// The actual rendering is handled by the SwiftUI layer (BrainUI).
// This registry tracks what primitives are available and their capabilities.
public struct PrimitiveInfo: Sendable {
    public let type: String                   // e.g. "stack", "text", "button"
    public let category: PrimitiveCategory
    public let supportsChildren: Bool         // Can contain child nodes?
    public let requiredProperties: [String]   // Properties that must be set
    public let optionalProperties: [String]   // Properties that can be set

    public init(
        type: String,
        category: PrimitiveCategory,
        supportsChildren: Bool = false,
        requiredProperties: [String] = [],
        optionalProperties: [String] = []
    ) {
        self.type = type
        self.category = category
        self.supportsChildren = supportsChildren
        self.requiredProperties = requiredProperties
        self.optionalProperties = optionalProperties
    }
}

// Registry of all available UI primitives.
// Skills can only use primitives that are registered here (security catalog pattern).
// The renderer looks up primitives by type string to find the SwiftUI builder.
public final class ComponentRegistry: Sendable {

    private let primitives: [String: PrimitiveInfo]

    public init(primitives: [PrimitiveInfo] = ComponentRegistry.defaultPrimitives) {
        var dict: [String: PrimitiveInfo] = [:]
        for p in primitives {
            dict[p.type] = p
        }
        self.primitives = dict
    }

    // Look up a primitive by type name.
    public func lookup(_ type: String) -> PrimitiveInfo? {
        primitives[type]
    }

    // Check if a type is registered.
    public func isRegistered(_ type: String) -> Bool {
        primitives[type] != nil
    }

    // All registered type names.
    public var registeredTypes: [String] {
        Array(primitives.keys).sorted()
    }

    // All primitives in a category.
    public func primitives(in category: PrimitiveCategory) -> [PrimitiveInfo] {
        primitives.values.filter { $0.category == category }.sorted { $0.type < $1.type }
    }

    // Validate a screen node tree against the registry.
    // Returns a list of validation errors (empty = valid).
    public func validate(_ node: ScreenNode) -> [String] {
        var errors: [String] = []
        validateNode(node, errors: &errors)
        return errors
    }

    private func validateNode(_ node: ScreenNode, errors: inout [String]) {
        guard let info = primitives[node.type] else {
            errors.append("Unknown primitive type: '\(node.type)'")
            return
        }

        // Check required properties
        for req in info.requiredProperties {
            if node.properties?[req] == nil {
                errors.append("'\(node.type)' requires property '\(req)'")
            }
        }

        // URL scheme validation for web-view and open-url (F-14)
        if node.type == "web-view" || node.type == "open-url" {
            if let urlString = node.properties?["url"]?.stringValue {
                if !isAllowedURLScheme(urlString) {
                    errors.append("'\(node.type)' requires an https URL, got: '\(urlString)'")
                }
            }
        }

        // Check children
        if let children = node.children {
            if !info.supportsChildren {
                errors.append("'\(node.type)' does not support children, but has \(children.count)")
            }
            for child in children {
                validateNode(child, errors: &errors)
            }
        }
    }

    // MARK: - URL validation

    /// Only HTTPS URLs are allowed for web-view and open-url components.
    private func isAllowedURLScheme(_ urlString: String) -> Bool {
        let lowered = urlString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: lowered), let scheme = url.scheme else {
            // If it's an expression template, allow it (runtime will validate)
            return urlString.contains("{{")
        }
        return scheme == "https"
    }

    // MARK: - Default primitives catalog

    // All 92 UI primitives across 9 categories.
    public static let defaultPrimitives: [PrimitiveInfo] = [
        // Layout (15)
        PrimitiveInfo(type: "stack", category: .layout, supportsChildren: true, optionalProperties: ["direction", "spacing", "alignment"]),
        PrimitiveInfo(type: "scroll", category: .layout, supportsChildren: true, optionalProperties: ["direction"]),
        PrimitiveInfo(type: "list", category: .layout, supportsChildren: true, optionalProperties: ["data", "as", "itemTemplate"]),
        PrimitiveInfo(type: "grid", category: .layout, supportsChildren: true, optionalProperties: ["columns", "spacing"]),
        PrimitiveInfo(type: "tab-view", category: .layout, supportsChildren: true),
        PrimitiveInfo(type: "split-view", category: .layout, supportsChildren: true),
        PrimitiveInfo(type: "sheet", category: .layout, supportsChildren: true, optionalProperties: ["detents"]),
        PrimitiveInfo(type: "conditional", category: .layout, supportsChildren: true, requiredProperties: ["condition"]),
        PrimitiveInfo(type: "repeater", category: .layout, supportsChildren: true, requiredProperties: ["data", "as"]),
        PrimitiveInfo(type: "spacer", category: .layout),
        PrimitiveInfo(type: "lazy-vstack", category: .layout, supportsChildren: true, optionalProperties: ["spacing"]),
        PrimitiveInfo(type: "lazy-hstack", category: .layout, supportsChildren: true, optionalProperties: ["spacing"]),
        PrimitiveInfo(type: "section", category: .layout, supportsChildren: true, optionalProperties: ["header", "footer"]),
        PrimitiveInfo(type: "disclosure-group", category: .layout, supportsChildren: true, optionalProperties: ["title"]),
        PrimitiveInfo(type: "view-that-fits", category: .layout, supportsChildren: true),

        // Content (12)
        PrimitiveInfo(type: "text", category: .content, requiredProperties: ["value"], optionalProperties: ["style", "color", "alignment"]),
        PrimitiveInfo(type: "image", category: .content, requiredProperties: ["source"], optionalProperties: ["width", "height", "contentMode", "alt"]),
        PrimitiveInfo(type: "icon", category: .content, requiredProperties: ["name"], optionalProperties: ["size", "color"]),
        PrimitiveInfo(type: "avatar", category: .content, optionalProperties: ["source", "initials", "size"]),
        PrimitiveInfo(type: "badge", category: .content, requiredProperties: ["value"], optionalProperties: ["color", "text"]),
        PrimitiveInfo(type: "divider", category: .content),
        PrimitiveInfo(type: "markdown", category: .content, requiredProperties: ["value"]),
        PrimitiveInfo(type: "label", category: .content, optionalProperties: ["title", "icon"]),
        PrimitiveInfo(type: "async-image", category: .content, requiredProperties: ["url"], optionalProperties: ["width", "height", "alt"]),
        PrimitiveInfo(type: "date-text", category: .content, optionalProperties: ["date", "style"]),
        PrimitiveInfo(type: "redacted", category: .content, supportsChildren: true),
        PrimitiveInfo(type: "color-swatch", category: .content, optionalProperties: ["color", "size"]),

        // Input (13)
        PrimitiveInfo(type: "text-field", category: .input, optionalProperties: ["placeholder", "value", "onChange"]),
        PrimitiveInfo(type: "text-editor", category: .input, optionalProperties: ["value", "onChange"]),
        PrimitiveInfo(type: "toggle", category: .input, optionalProperties: ["value", "label", "onChange"]),
        PrimitiveInfo(type: "picker", category: .input, requiredProperties: ["options"], optionalProperties: ["value", "label", "style", "onChange"]),
        PrimitiveInfo(type: "slider", category: .input, optionalProperties: ["value", "min", "max", "step", "label", "onChange"]),
        PrimitiveInfo(type: "stepper", category: .input, optionalProperties: ["value", "min", "max", "label", "onChange"]),
        PrimitiveInfo(type: "date-picker", category: .input, optionalProperties: ["value", "label", "mode", "onChange"]),
        PrimitiveInfo(type: "color-picker", category: .input, optionalProperties: ["value", "label", "onChange"]),
        PrimitiveInfo(type: "search-field", category: .input, optionalProperties: ["value", "placeholder", "onChange"]),
        PrimitiveInfo(type: "secure-field", category: .input, optionalProperties: ["value", "placeholder", "onChange"]),
        PrimitiveInfo(type: "photo-picker", category: .input, optionalProperties: ["onSelect"]),
        PrimitiveInfo(type: "paste-button", category: .input, optionalProperties: ["value", "label", "action"]),
        PrimitiveInfo(type: "multi-picker", category: .input, requiredProperties: ["options"], optionalProperties: ["selection", "label"]),

        // Interaction (11)
        PrimitiveInfo(type: "button", category: .interaction, supportsChildren: true, optionalProperties: ["title", "style", "action"]),
        PrimitiveInfo(type: "link", category: .interaction, optionalProperties: ["destination", "title"]),
        PrimitiveInfo(type: "menu", category: .interaction, supportsChildren: true, requiredProperties: ["title"]),
        PrimitiveInfo(type: "swipe-actions", category: .interaction, supportsChildren: true),
        PrimitiveInfo(type: "pull-to-refresh", category: .interaction, supportsChildren: true, requiredProperties: ["action"]),
        PrimitiveInfo(type: "long-press", category: .interaction, supportsChildren: true, optionalProperties: ["action"]),
        PrimitiveInfo(type: "navigation-link", category: .interaction, supportsChildren: true, optionalProperties: ["title", "destination"]),
        PrimitiveInfo(type: "context-menu", category: .interaction, supportsChildren: true),
        PrimitiveInfo(type: "share-link", category: .interaction, optionalProperties: ["text", "title", "url"]),
        PrimitiveInfo(type: "confirmation-dialog", category: .interaction, supportsChildren: true, optionalProperties: ["title"]),
        PrimitiveInfo(type: "double-tap", category: .interaction, supportsChildren: true, optionalProperties: ["action"]),

        // Data (15)
        PrimitiveInfo(type: "chart", category: .data, requiredProperties: ["chartType", "data"], optionalProperties: ["title"]),
        PrimitiveInfo(type: "map", category: .data, optionalProperties: ["latitude", "longitude", "span", "height"]),
        PrimitiveInfo(type: "calendar-grid", category: .data, optionalProperties: ["mode", "data"]),
        PrimitiveInfo(type: "progress", category: .data, requiredProperties: ["value"], optionalProperties: ["total", "style"]),
        PrimitiveInfo(type: "gauge", category: .data, requiredProperties: ["value"], optionalProperties: ["min", "max", "label"]),
        PrimitiveInfo(type: "stat-card", category: .data, requiredProperties: ["title", "value"], optionalProperties: ["suffix", "trend"]),
        PrimitiveInfo(type: "timer-display", category: .data, optionalProperties: ["duration", "mode"]),
        PrimitiveInfo(type: "graph", category: .data, optionalProperties: ["nodes", "edges"]),
        PrimitiveInfo(type: "line-chart", category: .data, requiredProperties: ["data"], optionalProperties: ["title"]),
        PrimitiveInfo(type: "bar-chart", category: .data, requiredProperties: ["data"], optionalProperties: ["title"]),
        PrimitiveInfo(type: "pie-chart", category: .data, requiredProperties: ["data"], optionalProperties: ["title"]),
        PrimitiveInfo(type: "sparkline", category: .data, requiredProperties: ["data"]),
        PrimitiveInfo(type: "countdown", category: .data, optionalProperties: ["target"]),
        PrimitiveInfo(type: "metric", category: .data, optionalProperties: ["value", "label", "unit"]),
        PrimitiveInfo(type: "heat-map", category: .data, requiredProperties: ["data"], optionalProperties: ["columns"]),

        // Feedback (6)
        PrimitiveInfo(type: "alert", category: .feedback, supportsChildren: true, optionalProperties: ["title", "message"]),
        PrimitiveInfo(type: "toast", category: .feedback, optionalProperties: ["message", "type"]),
        PrimitiveInfo(type: "banner", category: .feedback, optionalProperties: ["message", "type"]),
        PrimitiveInfo(type: "loading", category: .feedback, optionalProperties: ["label"]),
        PrimitiveInfo(type: "skeleton", category: .feedback, supportsChildren: true),
        PrimitiveInfo(type: "haptic", category: .feedback, optionalProperties: ["style"]),

        // Container (5)
        PrimitiveInfo(type: "card", category: .container, supportsChildren: true),
        PrimitiveInfo(type: "grouped-list", category: .container, supportsChildren: true),
        PrimitiveInfo(type: "toolbar", category: .container, supportsChildren: true),
        PrimitiveInfo(type: "overlay", category: .container, supportsChildren: true),
        PrimitiveInfo(type: "full-screen-cover", category: .container, supportsChildren: true, optionalProperties: ["isPresented"]),

        // System (6)
        PrimitiveInfo(type: "open-url", category: .system, optionalProperties: ["url", "title"]),
        PrimitiveInfo(type: "copy-button", category: .system, optionalProperties: ["text", "label"]),
        PrimitiveInfo(type: "qr-code", category: .system, requiredProperties: ["data"], optionalProperties: ["size"]),
        PrimitiveInfo(type: "video-player", category: .system, optionalProperties: ["url", "height"]),
        PrimitiveInfo(type: "live-activity", category: .system, optionalProperties: ["title"]),
        PrimitiveInfo(type: "widget-preview", category: .system, optionalProperties: ["title"]),

        // Special (7)
        PrimitiveInfo(type: "rich-editor", category: .special, optionalProperties: ["value", "onChange"]),
        PrimitiveInfo(type: "canvas", category: .special),
        PrimitiveInfo(type: "camera", category: .special, optionalProperties: ["onCapture"]),
        PrimitiveInfo(type: "scanner", category: .special, optionalProperties: ["onScan"]),
        PrimitiveInfo(type: "audio-player", category: .special, optionalProperties: ["source", "title"]),
        PrimitiveInfo(type: "web-view", category: .special, requiredProperties: ["url"], optionalProperties: ["height"]),
        PrimitiveInfo(type: "empty-state", category: .special, optionalProperties: ["icon", "title", "message", "action"]),
    ]
}
