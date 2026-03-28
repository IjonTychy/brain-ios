import CoreMotion
import UIKit
import BrainCore

// Bridge for raw sensor data access — inspired by Phyphox.
// Provides generic access to all iPhone sensors as action primitives.
// Any skill can use these handlers to build measurement tools:
// - Accelerometer (Beschleunigung, Neigung, Vibrationsmessung)
// - Gyroscope (Drehrate, Rotationsmessung)
// - Magnetometer (Kompass, Metalldetector)
// - Barometer (Luftdruck, relative Höhenmessung)
// - Proximity (Näherungssensor)
// - Device Motion (fusionierte Daten: Attitude, Gravity, UserAcceleration)
@MainActor
final class SensorBridge {

    // MARK: - Accelerometer

    // Read accelerometer data for a specified duration.
    // Returns an array of timestamped (x, y, z) acceleration values in G.
    // Use cases: Vibration measurement, step counter, tilt detection, shake detection,
    // car acceleration, earthquake detection, spirit level.
    nonisolated func readAccelerometer(duration: TimeInterval = 5.0, sampleRate: Double = 50.0) async throws -> [SensorSample3D] {
        let manager = CMMotionManager()
        guard manager.isAccelerometerAvailable else {
            throw SensorError.sensorUnavailable("Accelerometer")
        }

        manager.accelerometerUpdateInterval = 1.0 / sampleRate
        var samples: [SensorSample3D] = []
        let startTime = Date()
        let cappedDuration = min(duration, 60.0)

        manager.startAccelerometerUpdates()

        while Date().timeIntervalSince(startTime) < cappedDuration {
            if let data = manager.accelerometerData {
                samples.append(SensorSample3D(
                    timestamp: Date().timeIntervalSince(startTime),
                    x: data.acceleration.x,
                    y: data.acceleration.y,
                    z: data.acceleration.z
                ))
            }
            try await Task.sleep(for: .milliseconds(Int(1000.0 / sampleRate)))
        }

        manager.stopAccelerometerUpdates()
        return samples
    }

    // MARK: - Gyroscope

    // Read gyroscope data (rotation rate in rad/s).
    // Use cases: Rotation measurement, angular velocity, pendulum experiments,
    // spin detection, gesture recognition.
    nonisolated func readGyroscope(duration: TimeInterval = 5.0, sampleRate: Double = 50.0) async throws -> [SensorSample3D] {
        let manager = CMMotionManager()
        guard manager.isGyroAvailable else {
            throw SensorError.sensorUnavailable("Gyroscope")
        }

        manager.gyroUpdateInterval = 1.0 / sampleRate
        var samples: [SensorSample3D] = []
        let startTime = Date()

        manager.startGyroUpdates()

        while Date().timeIntervalSince(startTime) < min(duration, 60.0) {
            if let data = manager.gyroData {
                samples.append(SensorSample3D(
                    timestamp: Date().timeIntervalSince(startTime),
                    x: data.rotationRate.x,
                    y: data.rotationRate.y,
                    z: data.rotationRate.z
                ))
            }
            try await Task.sleep(for: .milliseconds(Int(1000.0 / sampleRate)))
        }

        manager.stopGyroUpdates()
        return samples
    }

    // MARK: - Magnetometer

    // Read magnetometer data (magnetic field in microtesla).
    // Use cases: Compass, metal detector, electromagnetic field measurement,
    // magnet proximity, direction finding.
    nonisolated func readMagnetometer(duration: TimeInterval = 5.0, sampleRate: Double = 50.0) async throws -> [SensorSample3D] {
        let manager = CMMotionManager()
        guard manager.isMagnetometerAvailable else {
            throw SensorError.sensorUnavailable("Magnetometer")
        }

        manager.magnetometerUpdateInterval = 1.0 / sampleRate
        var samples: [SensorSample3D] = []
        let startTime = Date()

        manager.startMagnetometerUpdates()

        while Date().timeIntervalSince(startTime) < min(duration, 60.0) {
            if let data = manager.magnetometerData {
                samples.append(SensorSample3D(
                    timestamp: Date().timeIntervalSince(startTime),
                    x: data.magneticField.x,
                    y: data.magneticField.y,
                    z: data.magneticField.z
                ))
            }
            try await Task.sleep(for: .milliseconds(Int(1000.0 / sampleRate)))
        }

        manager.stopMagnetometerUpdates()
        return samples
    }

    // MARK: - Barometer (Altimeter)

    // Read barometric pressure data (in kPa) and relative altitude changes.
    // Use cases: Weather station, altitude tracking, floor detection,
    // atmospheric pressure logging.
    nonisolated func readBarometer(duration: TimeInterval = 5.0) async throws -> [BarometerSample] {
        let altimeter = CMAltimeter()
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            throw SensorError.sensorUnavailable("Barometer")
        }

        var samples: [BarometerSample] = []
        let startTime = Date()

        altimeter.startRelativeAltitudeUpdates(to: OperationQueue()) { data, _ in
            guard let data else { return }
            samples.append(BarometerSample(
                timestamp: Date().timeIntervalSince(startTime),
                pressure: data.pressure.doubleValue, // kPa
                relativeAltitude: data.relativeAltitude.doubleValue // meters
            ))
        }

        try await Task.sleep(for: .seconds(min(duration, 60.0)))
        altimeter.stopRelativeAltitudeUpdates()
        return samples
    }

    // MARK: - Device Motion (Fused Sensors)

    // Read fused device motion data (attitude, gravity, user acceleration, rotation rate).
    // This is the highest-quality motion data, combining accelerometer + gyroscope + magnetometer.
    // Use cases: Spirit level (Attitude), free-fall detection, precise rotation tracking,
    // augmented reality, gesture recognition.
    nonisolated func readDeviceMotion(duration: TimeInterval = 5.0, sampleRate: Double = 50.0) async throws -> [DeviceMotionSample] {
        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else {
            throw SensorError.sensorUnavailable("DeviceMotion")
        }

        manager.deviceMotionUpdateInterval = 1.0 / sampleRate
        var samples: [DeviceMotionSample] = []
        let startTime = Date()

        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)

        while Date().timeIntervalSince(startTime) < min(duration, 60.0) {
            if let motion = manager.deviceMotion {
                samples.append(DeviceMotionSample(
                    timestamp: Date().timeIntervalSince(startTime),
                    pitch: motion.attitude.pitch,    // Neigung vorne/hinten (rad)
                    roll: motion.attitude.roll,      // Neigung links/rechts (rad)
                    yaw: motion.attitude.yaw,        // Kompassrichtung (rad)
                    gravityX: motion.gravity.x,
                    gravityY: motion.gravity.y,
                    gravityZ: motion.gravity.z,
                    userAccelX: motion.userAcceleration.x,
                    userAccelY: motion.userAcceleration.y,
                    userAccelZ: motion.userAcceleration.z,
                    rotationRateX: motion.rotationRate.x,
                    rotationRateY: motion.rotationRate.y,
                    rotationRateZ: motion.rotationRate.z,
                    magneticFieldX: motion.magneticField.field.x,
                    magneticFieldY: motion.magneticField.field.y,
                    magneticFieldZ: motion.magneticField.field.z,
                    heading: motion.heading // -1 if unavailable
                ))
            }
            try await Task.sleep(for: .milliseconds(Int(1000.0 / sampleRate)))
        }

        manager.stopDeviceMotionUpdates()
        return samples
    }

    // MARK: - Proximity Sensor

    // Read proximity sensor state (near/far).
    // Use cases: Pocket detection, hand wave gesture, auto screen-off.
    nonisolated func readProximity() async -> Bool {
        return await MainActor.run {
            let device = UIDevice.current
            device.isProximityMonitoringEnabled = true
            let isNear = device.proximityState
            device.isProximityMonitoringEnabled = false
            return isNear
        }
    }

    // MARK: - Screen Brightness

    // Read current screen brightness (0.0 to 1.0).
    nonisolated func readScreenBrightness() async -> Double {
        return await MainActor.run {
            Double(UIScreen.main.brightness)
        }
    }

    // MARK: - Battery

    // Read battery state and level.
    nonisolated func readBattery() async -> BatterySample {
        return await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let level = device.batteryLevel
            let state = device.batteryState
            device.isBatteryMonitoringEnabled = false
            let stateString: String
            switch state {
            case .charging: stateString = "charging"
            case .full: stateString = "full"
            case .unplugged: stateString = "unplugged"
            default: stateString = "unknown"
            }
            return BatterySample(
                level: Double(level),
                isCharging: state == .charging || state == .full,
                state: stateString
            )
        }
    }
}

// MARK: - Models

struct SensorSample3D: Codable, Sendable {
    let timestamp: Double
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double { sqrt(x * x + y * y + z * z) }
}

struct BarometerSample: Codable, Sendable {
    let timestamp: Double
    let pressure: Double          // kPa
    let relativeAltitude: Double  // meters
}

struct DeviceMotionSample: Codable, Sendable {
    let timestamp: Double
    let pitch: Double             // rad, Neigung vorne/hinten
    let roll: Double              // rad, Neigung links/rechts
    let yaw: Double               // rad, Kompassrichtung
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let magneticFieldX: Double
    let magneticFieldY: Double
    let magneticFieldZ: Double
    let heading: Double           // degrees, -1 if unavailable
}

struct BatterySample: Codable, Sendable {
    let level: Double             // 0.0 to 1.0
    let isCharging: Bool
    let state: String             // charging, full, unplugged, unknown
}

enum SensorError: Error, LocalizedError {
    case sensorUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sensorUnavailable(let name): return "Sensor nicht verfügbar: \(name)"
        }
    }
}

// MARK: - Action Handlers

// Generic accelerometer reading.
// Use cases: Vibration meter, step counter, tilt sensor, earthquake, spirit level.
@MainActor
final class SensorAccelerometerHandler: ActionHandler {
    let type = "sensor.accelerometer"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 50.0

        let bridge = await MainActor.run { SensorBridge() }
        let samples = try await bridge.readAccelerometer(duration: min(duration, 60.0), sampleRate: min(sampleRate, 100.0))

        return sensorResult3D(samples: samples, unit: "G")
    }
}

// Generic gyroscope reading.
// Use cases: Rotation measurement, pendulum, spin detection.
@MainActor
final class SensorGyroscopeHandler: ActionHandler {
    let type = "sensor.gyroscope"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 50.0

        let bridge = await MainActor.run { SensorBridge() }
        let samples = try await bridge.readGyroscope(duration: min(duration, 60.0), sampleRate: min(sampleRate, 100.0))

        return sensorResult3D(samples: samples, unit: "rad/s")
    }
}

// Generic magnetometer reading.
// Use cases: Compass, metal detector, magnetic field measurement.
@MainActor
final class SensorMagnetometerHandler: ActionHandler {
    let type = "sensor.magnetometer"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 50.0

        let bridge = await MainActor.run { SensorBridge() }
        let samples = try await bridge.readMagnetometer(duration: min(duration, 60.0), sampleRate: min(sampleRate, 100.0))

        return sensorResult3D(samples: samples, unit: "µT")
    }
}

// Barometer / altimeter reading.
// Use cases: Weather station, altitude tracking, floor detection.
@MainActor
final class SensorBarometerHandler: ActionHandler {
    let type = "sensor.barometer"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0

        let bridge = await MainActor.run { SensorBridge() }
        let samples = try await bridge.readBarometer(duration: min(duration, 60.0))

        let samplesJSON = samples.map { s -> ExpressionValue in
            .object([
                "timestamp": .double(s.timestamp),
                "pressure": .double(s.pressure),
                "relativeAltitude": .double(s.relativeAltitude),
            ])
        }

        let avgPressure = samples.isEmpty ? 0 : samples.map(\.pressure).reduce(0, +) / Double(samples.count)
        let altChange = (samples.last?.relativeAltitude ?? 0) - (samples.first?.relativeAltitude ?? 0)

        return .value(.object([
            "samples": .array(samplesJSON),
            "sampleCount": .int(samples.count),
            "averagePressure": .double(avgPressure),
            "altitudeChange": .double(altChange),
            "unit": .string("kPa"),
        ]))
    }
}

// Device motion (fused: attitude + gravity + acceleration + rotation + magnetic).
// Use cases: Spirit level, free-fall detection, precise rotation, AR.
@MainActor
final class SensorDeviceMotionHandler: ActionHandler {
    let type = "sensor.deviceMotion"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 50.0

        let bridge = await MainActor.run { SensorBridge() }
        let samples = try await bridge.readDeviceMotion(duration: min(duration, 60.0), sampleRate: min(sampleRate, 100.0))

        // Return latest + stats
        guard let latest = samples.last else {
            return .actionError(code: "sensor.no_data", message: "Keine Motion-Daten")
        }

        return .value(.object([
            "sampleCount": .int(samples.count),
            "pitch": .double(latest.pitch * 180.0 / .pi),  // Convert to degrees
            "roll": .double(latest.roll * 180.0 / .pi),
            "yaw": .double(latest.yaw * 180.0 / .pi),
            "heading": .double(latest.heading),
            "gravity": .object([
                "x": .double(latest.gravityX),
                "y": .double(latest.gravityY),
                "z": .double(latest.gravityZ),
            ]),
            "userAcceleration": .object([
                "x": .double(latest.userAccelX),
                "y": .double(latest.userAccelY),
                "z": .double(latest.userAccelZ),
            ]),
            "magneticField": .object([
                "x": .double(latest.magneticFieldX),
                "y": .double(latest.magneticFieldY),
                "z": .double(latest.magneticFieldZ),
            ]),
        ]))
    }
}

// Proximity sensor reading.
@MainActor
final class SensorProximityHandler: ActionHandler {
    let type = "sensor.proximity"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { SensorBridge() }
        let isNear = await bridge.readProximity()
        return .value(.object([
            "isNear": .bool(isNear),
            "distance": .string(isNear ? "near" : "far"),
        ]))
    }
}

// Battery state reading.
@MainActor
final class SensorBatteryHandler: ActionHandler {
    let type = "sensor.battery"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { SensorBridge() }
        let battery = await bridge.readBattery()
        return .value(.object([
            "level": .double(battery.level),
            "percentage": .int(Int(battery.level * 100)),
            "isCharging": .bool(battery.isCharging),
            "state": .string(battery.state),
        ]))
    }
}

// MARK: - Shared helper

private func sensorResult3D(samples: [SensorSample3D], unit: String) -> ActionResult {
    guard !samples.isEmpty else {
        return .actionError(code: "sensor.no_data", message: "Keine Sensordaten")
    }

    let avgMag = samples.map(\.magnitude).reduce(0, +) / Double(samples.count)
    let maxMag = samples.map(\.magnitude).max() ?? 0
    let minMag = samples.map(\.magnitude).min() ?? 0
    guard let latest = samples.last else {
        return .actionError(code: "sensor.no_data", message: "Keine Sensordaten verfügbar")
    }

    return .value(.object([
        "sampleCount": .int(samples.count),
        "latest": .object([
            "x": .double(latest.x),
            "y": .double(latest.y),
            "z": .double(latest.z),
            "magnitude": .double(latest.magnitude),
        ]),
        "average": .double(avgMag),
        "max": .double(maxMag),
        "min": .double(minMag),
        "unit": .string(unit),
    ]))
}
