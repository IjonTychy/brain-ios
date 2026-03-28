import HomeKit
import BrainCore

// Bridge between Action Primitives and HomeKit.
// Provides home.scene for activating scenes and home.device for controlling accessories.
@MainActor
final class HomeBridge: NSObject {

    private let manager = HMHomeManager()
    private var managerReady = false
    private var readyContinuation: CheckedContinuation<Void, Never>?

    // Wait for HomeKit manager to become ready.
    func waitForReady() async {
        if managerReady { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.readyContinuation = continuation
            manager.delegate = self
        }
    }

    // List all available scenes across all homes.
    func listScenes() async -> [HomeScene] {
        await waitForReady()
        var scenes: [HomeScene] = []
        for home in manager.homes {
            for actionSet in home.actionSets {
                scenes.append(HomeScene(
                    name: actionSet.name,
                    homeName: home.name,
                    uniqueIdentifier: actionSet.uniqueIdentifier.uuidString
                ))
            }
        }
        return scenes
    }

    // Execute a scene by name.
    func executeScene(named name: String) async throws -> Bool {
        await waitForReady()
        for home in manager.homes {
            for actionSet in home.actionSets where actionSet.name.lowercased() == name.lowercased() {
                try await home.executeActionSet(actionSet)
                return true
            }
        }
        return false
    }

    // List all accessories across all homes.
    func listAccessories() async -> [HomeAccessory] {
        await waitForReady()
        var accessories: [HomeAccessory] = []
        for home in manager.homes {
            for accessory in home.accessories {
                accessories.append(HomeAccessory(
                    name: accessory.name,
                    homeName: home.name,
                    room: accessory.room?.name ?? "Unbekannt",
                    uniqueIdentifier: accessory.uniqueIdentifier.uuidString,
                    isReachable: accessory.isReachable
                ))
            }
        }
        return accessories
    }
}

// MARK: - HMHomeManagerDelegate

extension HomeBridge: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            managerReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        }
    }
}

// MARK: - Models

struct HomeScene: Sendable {
    let name: String
    let homeName: String
    let uniqueIdentifier: String

    func toExpressionValue() -> ExpressionValue {
        .object([
            "name": .string(name),
            "home": .string(homeName),
            "id": .string(uniqueIdentifier),
        ])
    }
}

struct HomeAccessory: Sendable {
    let name: String
    let homeName: String
    let room: String
    let uniqueIdentifier: String
    let isReachable: Bool

    func toExpressionValue() -> ExpressionValue {
        .object([
            "name": .string(name),
            "home": .string(homeName),
            "room": .string(room),
            "id": .string(uniqueIdentifier),
            "reachable": .bool(isReachable),
        ])
    }
}

// MARK: - Action Handlers

@MainActor final class HomeSceneHandler: ActionHandler {
    let type = "home.scene"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let sceneName = properties["name"]?.stringValue else {
            return .error("home.scene: name fehlt")
        }
        let bridge = HomeBridge()
        let success = try await bridge.executeScene(named: sceneName)
        if success {
            return .value(.object([
                "scene": .string(sceneName),
                "status": .string("activated"),
            ]))
        }
        return .error("home.scene: Szene '\(sceneName)' nicht gefunden")
    }
}

@MainActor final class HomeDeviceHandler: ActionHandler {
    let type = "home.device"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let mode = properties["mode"]?.stringValue ?? "list"
        let bridge = HomeBridge()

        if mode == "list" {
            let accessories = await bridge.listAccessories()
            return .value(.object([
                "devices": .array(accessories.map { $0.toExpressionValue() }),
                "count": .int(accessories.count),
            ]))
        }

        // Device control requires more complex state management
        return .value(.object([
            "action": .string("home.device"),
            "status": .string("requires_ui"),
            "message": .string("Gerätesteuerung muss über die UI verwaltet werden"),
        ]))
    }
}
