@preconcurrency import CoreBluetooth
import BrainCore

// Bridge between Action Primitives and CoreBluetooth.
// Provides bluetooth.scan for discovering BLE devices and bluetooth.connect for connections.
// @preconcurrency import because CBCentralManager/CBPeripheral are not Sendable yet.
@MainActor
final class BluetoothBridge: NSObject {

    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var scanContinuation: CheckedContinuation<[BLEDevice], Never>?

    // Check if Bluetooth is available and powered on.
    var isAvailable: Bool {
        CBCentralManager.authorization == .allowedAlways
    }

    // Scan for nearby BLE devices for a given duration.
    func scan(duration: TimeInterval = 5.0) async -> [BLEDevice] {
        await withCheckedContinuation { continuation in
            self.scanContinuation = continuation
            self.discoveredPeripherals = []

            let manager = CBCentralManager(delegate: self, queue: .main)
            self.centralManager = manager

            // Stop scan after duration
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                manager.stopScan()
                let devices = self.discoveredPeripherals.map { BLEDevice(from: $0) }
                self.scanContinuation?.resume(returning: devices)
                self.scanContinuation = nil
                self.centralManager = nil
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothBridge: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false,
                ])
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }
}

// MARK: - BLEDevice

struct BLEDevice: Sendable {
    let identifier: String
    let name: String?
    let rssi: Int

    init(from peripheral: CBPeripheral, rssi: Int = 0) {
        self.identifier = peripheral.identifier.uuidString
        self.name = peripheral.name
        self.rssi = rssi
    }

    func toExpressionValue() -> ExpressionValue {
        .object([
            "identifier": .string(identifier),
            "name": .string(name ?? "Unbekannt"),
            "rssi": .int(rssi),
        ])
    }
}

// MARK: - Action Handlers

final class BluetoothScanHandler: ActionHandler, Sendable {
    let type = "bluetooth.scan"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { BluetoothBridge() }
        let available = await MainActor.run { bridge.isAvailable }
        guard available else {
            return .error("bluetooth.scan: Bluetooth nicht verfügbar oder Berechtigung fehlt")
        }
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let devices = await bridge.scan(duration: min(duration, 30.0))
        return .value(.object([
            "devices": .array(devices.map { $0.toExpressionValue() }),
            "count": .int(devices.count),
        ]))
    }
}

final class BluetoothConnectHandler: ActionHandler, Sendable {
    let type = "bluetooth.connect"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard properties["identifier"]?.stringValue != nil else {
            return .error("bluetooth.connect: identifier fehlt")
        }
        // BLE connection requires ongoing state management — return instructions for UI layer
        return .value(.object([
            "action": .string("bluetooth.connect"),
            "status": .string("requires_ui"),
            "message": .string("BLE-Verbindung muss über die UI verwaltet werden"),
        ]))
    }
}
