import Foundation

// Color scheme preference.
public enum ColorSchemePreference: String, Codable, Sendable {
    case light
    case dark
    case system
}

// Theme configuration for the skill renderer.
// Stored per-user, applied globally. Skills can override individual values.
public struct ThemeConfig: Codable, Sendable, Equatable {
    public var colorScheme: ColorSchemePreference
    public var primaryColor: String       // Hex e.g. "#007AFF"
    public var secondaryColor: String     // Hex e.g. "#5856D6"
    public var backgroundColor: String    // Hex for main background
    public var surfaceColor: String       // Hex for cards/elevated surfaces
    public var textColor: String          // Hex for primary text
    public var textSecondaryColor: String // Hex for secondary/muted text
    public var fontSize: FontSizeScale
    public var cornerRadius: Double       // Default corner radius for cards

    public init(
        colorScheme: ColorSchemePreference = .system,
        primaryColor: String = "#007AFF",
        secondaryColor: String = "#5856D6",
        backgroundColor: String = "#FFFFFF",
        surfaceColor: String = "#F2F2F7",
        textColor: String = "#000000",
        textSecondaryColor: String = "#8E8E93",
        fontSize: FontSizeScale = .medium,
        cornerRadius: Double = 12.0
    ) {
        self.colorScheme = colorScheme
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.surfaceColor = surfaceColor
        self.textColor = textColor
        self.textSecondaryColor = textSecondaryColor
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
    }
}

// Font size scaling preference (accessibility).
public enum FontSizeScale: String, Codable, Sendable, CaseIterable {
    case small
    case medium
    case large
    case extraLarge
}
