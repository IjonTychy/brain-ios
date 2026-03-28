import Foundation
import UIKit
import BrainCore
import GRDB
import os.log

// MARK: - Navigate action

final class NavigateToHandler: ActionHandler, Sendable {
    let type = "navigate.to"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Navigation is primarily handled by SkillViewModel.handleBuiltinAction().
        // This handler exists so the dispatcher recognizes the type.
        return .success
    }
}

final class NavigateBackHandler: ActionHandler, Sendable {
    let type = "navigate.back"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("navigate.back"),
            "status": .string("requires_ui"),
        ]))
    }
}

final class NavigateTabHandler: ActionHandler, Sendable {
    let type = "navigate.tab"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let tab = properties["tab"]?.stringValue ?? ""
        // Post notification so ContentView can switch tabs
        await MainActor.run {
            NotificationCenter.default.post(
                name: .brainNavigateTab,
                object: nil,
                userInfo: ["tab": tab]
            )
        }
        return .success
    }
}

// Open an entry detail view by posting a notification with the entry ID.
final class EntryOpenHandler: ActionHandler, Sendable {
    let type = "entry.open"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let idValue = properties["id"]?.stringValue,
              let entryId = Int64(idValue) else {
            return ActionResult.error("entry.open: Keine gültige Entry-ID")
        }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .brainOpenEntry,
                object: nil,
                userInfo: ["entryId": entryId]
            )
        }
        return .success
    }
}

extension Notification.Name {
    static let brainNavigateTab = Notification.Name("brainNavigateTab")
    static let brainOpenEntry = Notification.Name("brainOpenEntry")
    static let brainSkillAction = Notification.Name("brainSkillAction")
    static let brainSkillsChanged = Notification.Name("brainSkillsChanged")
}

// MARK: - Haptic feedback

final class HapticHandler: ActionHandler, Sendable {
    let type = "haptic"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        #if canImport(UIKit)
        let style = properties["style"]?.stringValue ?? "medium"
        await MainActor.run {
            switch style {
            case "light":
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "selection":
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        #endif
        return .success
    }
}

// MARK: - Clipboard

final class ClipboardCopyHandler: ActionHandler, Sendable {
    let type = "clipboard.copy"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        #if canImport(UIKit)
        if let text = properties["text"]?.stringValue {
            await MainActor.run {
                UIPasteboard.general.string = text
            }
        }
        #endif
        return .success
    }
}

final class ClipboardPasteHandler: ActionHandler, Sendable {
    let type = "clipboard.paste"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        #if canImport(UIKit)
        let text = await MainActor.run { UIPasteboard.general.string }
        return .value(.string(text ?? ""))
        #else
        return .error("clipboard.paste: Nicht verfügbar auf dieser Plattform")
        #endif
    }
}

// MARK: - URL handling

final class OpenURLHandler: ActionHandler, Sendable {
    let type = "open-url"

    // Only allow safe URL schemes. Skills from external sources must not
    // be able to trigger tel:, sms:, facetime: or other privilege-escalating URLs.
    private static let allowedSchemes: Set<String> = ["https", "http", "mailto"]

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let urlString = properties["url"]?.stringValue,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme)
        else {
            return .error("URL nicht erlaubt oder ungültig")
        }

        #if canImport(UIKit)
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        #endif
        return .success
    }
}

// MARK: - Toast & Set

final class ToastHandler: ActionHandler, Sendable {
    let type = "toast"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Toast is a UI feedback action. On iOS, this would show a brief overlay.
        // For now, log the message. Full UI implementation requires SwiftUI overlay.
        let message = properties["message"]?.stringValue ?? ""
        Logger(subsystem: "com.example.brain-ios", category: "ActionHandlers")
            .debug("Toast: \(message)")
        return .success
    }
}

final class SetVariableHandler: ActionHandler, Sendable {
    let type = "set"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Variable setting is handled by the LogicInterpreter, not by action handlers.
        // This handler exists as a fallback if set is dispatched directly.
        return .success
    }
}

// MARK: - Share

final class ShareHandler: ActionHandler, Sendable {
    let type = "share"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        #if canImport(UIKit)
        let text = properties["text"]?.stringValue ?? ""
        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first,
                  let rootVC = window.rootViewController else { return }
            let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            // iPad requires popover presentation
            activityVC.popoverPresentationController?.sourceView = window
            rootVC.present(activityVC, animated: true)
        }
        #endif
        return .success
    }
}

// MARK: - UI dialog actions

final class AlertHandler: ActionHandler, Sendable {
    let type = "alert"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("alert"),
            "title": .string(properties["title"]?.stringValue ?? ""),
            "message": .string(properties["message"]?.stringValue ?? ""),
            "status": .string("requires_ui"),
        ]))
    }
}

final class ConfirmHandler: ActionHandler, Sendable {
    let type = "confirm"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("confirm"),
            "title": .string(properties["title"]?.stringValue ?? ""),
            "message": .string(properties["message"]?.stringValue ?? ""),
            "status": .string("requires_ui"),
        ]))
    }
}

// MARK: - Sheet actions

final class SheetOpenHandler: ActionHandler, Sendable {
    let type = "sheet.open"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("sheet.open"),
            "screen": .string(properties["screen"]?.stringValue ?? ""),
            "status": .string("requires_ui"),
        ]))
    }
}

final class SheetCloseHandler: ActionHandler, Sendable {
    let type = "sheet.close"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("sheet.close"),
            "status": .string("requires_ui"),
        ]))
    }
}

// MARK: - Spotlight handlers

@MainActor final class SpotlightIndexHandler: ActionHandler {
    let type = "spotlight.index"
    private let data: any DataProviding
    private let bridge = SpotlightBridge()

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["entryId"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("spotlight.index: entryId fehlt")
        }
        guard let entry = try data.fetchEntry(id: id) else {
            return .error("Entry \(id) nicht gefunden")
        }
        bridge.index(entry: entry)
        return .success
    }
}

final class SpotlightDeindexHandler: ActionHandler, Sendable {
    let type = "spotlight.deindex"
    private let bridge = SpotlightBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["entryId"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("spotlight.deindex: entryId fehlt")
        }
        bridge.deindex(entryId: id)
        return .success
    }
}

final class SpotlightRemoveHandler: ActionHandler, Sendable {
    let type = "spotlight.remove"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.intValue.flatMap({ Int64($0) }) else {
            return .error("spotlight.remove: id fehlt")
        }
        SpotlightBridge().deindex(entryId: id)
        return .success
    }
}
