// Top-level navigation tabs for brain-ios.
// iPhone: 5 tabs (Home, Search, Chat, Mail, More).
// iPad: Full sidebar with all sections.
public enum BrainTab: String, CaseIterable, Codable, Sendable {
    case dashboard
    case search
    case chat
    case mail
    case calendar
    case files
    case canvas
    case people
    case knowledgeGraph
    case brainAdmin
    case more

    // Localization key for the tab title (resolved via LocalizationService in BrainApp).
    public var localizationKey: String {
        switch self {
        case .dashboard: "tab.home"
        case .search: "tab.search"
        case .mail: "tab.mail"
        case .calendar: "tab.calendar"
        case .files: "tab.files"
        case .canvas: "tab.capture"
        case .people: "tab.contacts"
        case .knowledgeGraph: "tab.graph"
        case .brainAdmin: "tab.skills"
        case .chat: "tab.chat"
        case .more: "tab.more"
        }
    }

    // Display name shown in the tab bar / sidebar (German fallback).
    // In BrainApp, use L(tab.localizationKey) for localized titles.
    public var title: String {
        switch self {
        case .dashboard: "Home"
        case .search: "Suche"
        case .mail: "Posteingang"
        case .calendar: "Kalender"
        case .files: "Dateien"
        case .canvas: "Erfassen"
        case .people: "Kontakte"
        case .knowledgeGraph: "Wissensnetz"
        case .brainAdmin: "Skills"
        case .chat: "Chat"
        case .more: "Mehr"
        }
    }

    // SF Symbol name for the tab icon.
    public var icon: String {
        switch self {
        case .dashboard: "house"
        case .search: "magnifyingglass"
        case .mail: "envelope"
        case .calendar: "calendar"
        case .files: "folder"
        case .canvas: "note.text"
        case .people: "person.2"
        case .knowledgeGraph: "circle.hexagongrid"
        case .brainAdmin: "puzzlepiece.extension"
        case .chat: "bubble.left.and.bubble.right"
        case .more: "ellipsis.circle"
        }
    }

    // The 5 tabs shown in the iPhone tab bar.
    public static let mainTabs: [BrainTab] = [.dashboard, .search, .chat, .mail, .more]

    // Items shown in the "More" tab as NavigationLinks.
    public static let moreTabs: [BrainTab] = [.calendar, .files, .canvas, .people, .knowledgeGraph, .brainAdmin]
}
