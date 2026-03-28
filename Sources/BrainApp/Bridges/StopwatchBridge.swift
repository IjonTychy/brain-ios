@preconcurrency import AVFoundation
import CoreMotion
import Accelerate
import UIKit
import BrainCore

// Bridge for event-triggered stopwatch measurements — Phyphox-style.
// Measures time between two trigger events detected by sensors:
// - Acoustic: Time between two loud sounds (claps, snaps)
// - Motion: Time between two acceleration spikes (drops, collisions)
// - Optical: Time between two brightness changes (flashlight, LED)
// - Proximity: Time between two proximity events (hand wave)
// Use cases: Reaction time, speed of sound, pendulum period, falling time.
@MainActor
final class StopwatchBridge: NSObject {

    // MARK: - Acoustic Stopwatch

    // Measure time between two acoustic trigger events (loud sounds).
    // threshold: RMS amplitude threshold (0.0-1.0) to trigger (default 0.1)
    // maxWait: Maximum wait time in seconds before timeout.
    // Returns: time between first and second trigger, plus trigger amplitudes.
    func acousticStopwatch(threshold: Float = 0.1, maxWait: TimeInterval = 30.0) async throws -> StopwatchResult {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw StopwatchError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        var triggerTimes: [(time: Date, amplitude: Float)] = []
        let startTime = Date()
        let cappedMaxWait = min(maxWait, 120.0)
        // Debounce: ignore triggers within 50ms of each other
        let debounceInterval: TimeInterval = 0.05

        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            guard triggerTimes.count < 2 else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)

            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))

            if rms >= threshold {
                let now = Date()
                // Debounce check
                if let last = triggerTimes.last, now.timeIntervalSince(last.time) < debounceInterval {
                    return
                }
                triggerTimes.append((time: now, amplitude: rms))
            }
        }

        try engine.start()

        // Wait until 2 triggers or timeout
        while triggerTimes.count < 2 {
            if Date().timeIntervalSince(startTime) > cappedMaxWait {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        guard triggerTimes.count >= 2 else {
            return StopwatchResult(
                elapsed: 0,
                triggerCount: triggerTimes.count,
                trigger1Time: triggerTimes.first.map { $0.time.timeIntervalSince(startTime) },
                trigger2Time: nil,
                trigger1Value: triggerTimes.first.map { Double($0.amplitude) },
                trigger2Value: nil,
                timedOut: true,
                sensorType: "acoustic"
            )
        }

        let elapsed = triggerTimes[1].time.timeIntervalSince(triggerTimes[0].time)
        return StopwatchResult(
            elapsed: round(elapsed * 100000) / 100000, // 10µs precision
            triggerCount: 2,
            trigger1Time: triggerTimes[0].time.timeIntervalSince(startTime),
            trigger2Time: triggerTimes[1].time.timeIntervalSince(startTime),
            trigger1Value: Double(triggerTimes[0].amplitude),
            trigger2Value: Double(triggerTimes[1].amplitude),
            timedOut: false,
            sensorType: "acoustic"
        )
    }

    // MARK: - Motion Stopwatch

    // Measure time between two acceleration spikes.
    // threshold: Acceleration magnitude in G to trigger (default 1.5).
    // Use cases: Drop time, collision timing, reaction time with phone shake.
    func motionStopwatch(threshold: Double = 1.5, maxWait: TimeInterval = 30.0) async throws -> StopwatchResult {
        let manager = CMMotionManager()
        guard manager.isAccelerometerAvailable else {
            throw StopwatchError.sensorUnavailable("Accelerometer")
        }

        manager.accelerometerUpdateInterval = 1.0 / 100.0 // 100 Hz
        var triggerTimes: [(time: Date, magnitude: Double)] = []
        let startTime = Date()
        let cappedMaxWait = min(maxWait, 120.0)
        let debounceInterval: TimeInterval = 0.1

        manager.startAccelerometerUpdates(to: OperationQueue()) { data, _ in
            guard triggerTimes.count < 2, let data else { return }
            let a = data.acceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

            if magnitude >= threshold {
                let now = Date()
                if let last = triggerTimes.last, now.timeIntervalSince(last.time) < debounceInterval {
                    return
                }
                triggerTimes.append((time: now, magnitude: magnitude))
            }
        }

        while triggerTimes.count < 2 {
            if Date().timeIntervalSince(startTime) > cappedMaxWait { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        manager.stopAccelerometerUpdates()

        guard triggerTimes.count >= 2 else {
            return StopwatchResult(
                elapsed: 0,
                triggerCount: triggerTimes.count,
                trigger1Time: triggerTimes.first.map { $0.time.timeIntervalSince(startTime) },
                trigger2Time: nil,
                trigger1Value: triggerTimes.first?.magnitude,
                trigger2Value: nil,
                timedOut: true,
                sensorType: "motion"
            )
        }

        let elapsed = triggerTimes[1].time.timeIntervalSince(triggerTimes[0].time)
        return StopwatchResult(
            elapsed: round(elapsed * 100000) / 100000,
            triggerCount: 2,
            trigger1Time: triggerTimes[0].time.timeIntervalSince(startTime),
            trigger2Time: triggerTimes[1].time.timeIntervalSince(startTime),
            trigger1Value: triggerTimes[0].magnitude,
            trigger2Value: triggerTimes[1].magnitude,
            timedOut: false,
            sensorType: "motion"
        )
    }

    // MARK: - Optical Stopwatch (Brightness)

    // Measure time between two brightness changes via camera.
    // threshold: Minimum brightness change (0.0-1.0) to trigger (default 0.2).
    // Use cases: Light gate, flashlight timing, LED blink timing.
    func opticalStopwatch(threshold: Double = 0.2, maxWait: TimeInterval = 30.0) async throws -> StopwatchResult {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw StopwatchError.cameraAccessDenied }
        } else if status != .authorized {
            throw StopwatchError.cameraAccessDenied
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw StopwatchError.noCameraAvailable
        }

        // Lock exposure for consistent brightness readings
        if device.isExposureModeSupported(.locked) {
            try device.lockForConfiguration()
            device.exposureMode = .locked
            device.unlockForConfiguration()
        }

        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.sessionPreset = .low
        guard session.canAddInput(input) else { throw StopwatchError.cameraSetupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { throw StopwatchError.cameraSetupFailed }
        session.addOutput(output)

        var triggerTimes: [(time: Date, brightness: Double)] = []
        var lastBrightness: Double?
        let startTime = Date()
        let cappedMaxWait = min(maxWait, 120.0)
        let debounceInterval: TimeInterval = 0.1

        let delegate = BrightnessStopwatchDelegate { brightness in
            guard triggerTimes.count < 2 else { return }

            if let last = lastBrightness {
                let change = abs(brightness - last)
                if change >= threshold {
                    let now = Date()
                    if let lastTrigger = triggerTimes.last, now.timeIntervalSince(lastTrigger.time) < debounceInterval {
                        lastBrightness = brightness
                        return
                    }
                    triggerTimes.append((time: now, brightness: brightness))
                }
            }
            lastBrightness = brightness
        }

        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "stopwatch.optical"))
        session.startRunning()

        while triggerTimes.count < 2 {
            if Date().timeIntervalSince(startTime) > cappedMaxWait { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        session.stopRunning()

        guard triggerTimes.count >= 2 else {
            return StopwatchResult(
                elapsed: 0,
                triggerCount: triggerTimes.count,
                trigger1Time: triggerTimes.first.map { $0.time.timeIntervalSince(startTime) },
                trigger2Time: nil,
                trigger1Value: triggerTimes.first?.brightness,
                trigger2Value: nil,
                timedOut: true,
                sensorType: "optical"
            )
        }

        let elapsed = triggerTimes[1].time.timeIntervalSince(triggerTimes[0].time)
        return StopwatchResult(
            elapsed: round(elapsed * 100000) / 100000,
            triggerCount: 2,
            trigger1Time: triggerTimes[0].time.timeIntervalSince(startTime),
            trigger2Time: triggerTimes[1].time.timeIntervalSince(startTime),
            trigger1Value: triggerTimes[0].brightness,
            trigger2Value: triggerTimes[1].brightness,
            timedOut: false,
            sensorType: "optical"
        )
    }

    // MARK: - Proximity Stopwatch

    // Measure time between two proximity sensor changes.
    // Use cases: Hand-wave timing, object passing detection.
    func proximityStopwatch(maxWait: TimeInterval = 30.0) async throws -> StopwatchResult {
        UIDevice.current.isProximityMonitoringEnabled = true
        defer { UIDevice.current.isProximityMonitoringEnabled = false }

        var triggerTimes: [(time: Date, isNear: Bool)] = []
        let startTime = Date()
        let cappedMaxWait = min(maxWait, 120.0)
        var lastState = UIDevice.current.proximityState

        while triggerTimes.count < 2 {
            if Date().timeIntervalSince(startTime) > cappedMaxWait { break }

            let currentState = UIDevice.current.proximityState
            if currentState != lastState {
                triggerTimes.append((time: Date(), isNear: currentState))
                lastState = currentState
            }

            try await Task.sleep(for: .milliseconds(5))
        }

        guard triggerTimes.count >= 2 else {
            return StopwatchResult(
                elapsed: 0,
                triggerCount: triggerTimes.count,
                trigger1Time: triggerTimes.first.map { $0.time.timeIntervalSince(startTime) },
                trigger2Time: nil,
                trigger1Value: triggerTimes.first.map { $0.isNear ? 1.0 : 0.0 },
                trigger2Value: nil,
                timedOut: true,
                sensorType: "proximity"
            )
        }

        let elapsed = triggerTimes[1].time.timeIntervalSince(triggerTimes[0].time)
        return StopwatchResult(
            elapsed: round(elapsed * 100000) / 100000,
            triggerCount: 2,
            trigger1Time: triggerTimes[0].time.timeIntervalSince(startTime),
            trigger2Time: triggerTimes[1].time.timeIntervalSince(startTime),
            trigger1Value: triggerTimes[0].isNear ? 1.0 : 0.0,
            trigger2Value: triggerTimes[1].isNear ? 1.0 : 0.0,
            timedOut: false,
            sensorType: "proximity"
        )
    }
}

// MARK: - Models

struct StopwatchResult: Sendable {
    let elapsed: Double       // seconds between trigger 1 and 2
    let triggerCount: Int     // 0, 1, or 2
    let trigger1Time: Double? // seconds since start
    let trigger2Time: Double?
    let trigger1Value: Double? // sensor value at trigger
    let trigger2Value: Double?
    let timedOut: Bool
    let sensorType: String
}

// MARK: - Errors

enum StopwatchError: Error, LocalizedError {
    case microphoneAccessDenied
    case cameraAccessDenied
    case noCameraAvailable
    case cameraSetupFailed
    case sensorUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied: return "Mikrofonzugriff nicht erlaubt"
        case .cameraAccessDenied: return "Kamerazugriff nicht erlaubt"
        case .noCameraAvailable: return "Keine Kamera verfügbar"
        case .cameraSetupFailed: return "Kamera-Setup fehlgeschlagen"
        case .sensorUnavailable(let s): return "\(s) nicht verfügbar"
        }
    }
}

// MARK: - Brightness Delegate

private class BrightnessStopwatchDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let onBrightness: (Double) -> Void

    init(onBrightness: @escaping (Double) -> Void) {
        self.onBrightness = onBrightness
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var totalLuma: Double = 0
        var count: Double = 0

        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let offset = y * bytesPerRow + x * 4
                let b = Double(buffer[offset])
                let g = Double(buffer[offset + 1])
                let r = Double(buffer[offset + 2])
                totalLuma += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }

        let brightness = count > 0 ? (totalLuma / count) / 255.0 : 0
        onBrightness(brightness)
    }
}

// MARK: - Action Handlers

private func stopwatchToResult(_ result: StopwatchResult) -> ActionResult {
    var dict: [String: ExpressionValue] = [
        "elapsed": .double(result.elapsed),
        "triggerCount": .int(result.triggerCount),
        "timedOut": .bool(result.timedOut),
        "sensorType": .string(result.sensorType),
    ]
    if let t1 = result.trigger1Time { dict["trigger1Time"] = .double(t1) }
    if let t2 = result.trigger2Time { dict["trigger2Time"] = .double(t2) }
    if let v1 = result.trigger1Value { dict["trigger1Value"] = .double(v1) }
    if let v2 = result.trigger2Value { dict["trigger2Value"] = .double(v2) }
    return .value(.object(dict))
}

// Acoustic stopwatch (time between two sounds)
@MainActor
final class StopwatchAcousticHandler: ActionHandler {
    let type = "stopwatch.acoustic"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { StopwatchBridge() }
        let threshold = Float(properties["threshold"]?.doubleValue ?? 0.1)
        let maxWait = properties["maxWait"]?.doubleValue ?? 30.0
        let result = try await bridge.acousticStopwatch(threshold: threshold, maxWait: maxWait)
        return stopwatchToResult(result)
    }
}

// Motion stopwatch (time between two acceleration spikes)
@MainActor
final class StopwatchMotionHandler: ActionHandler {
    let type = "stopwatch.motion"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { StopwatchBridge() }
        let threshold = properties["threshold"]?.doubleValue ?? 1.5
        let maxWait = properties["maxWait"]?.doubleValue ?? 30.0
        let result = try await bridge.motionStopwatch(threshold: threshold, maxWait: maxWait)
        return stopwatchToResult(result)
    }
}

// Optical stopwatch (time between two brightness changes)
@MainActor
final class StopwatchOpticalHandler: ActionHandler {
    let type = "stopwatch.optical"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { StopwatchBridge() }
        let threshold = properties["threshold"]?.doubleValue ?? 0.2
        let maxWait = properties["maxWait"]?.doubleValue ?? 30.0
        let result = try await bridge.opticalStopwatch(threshold: threshold, maxWait: maxWait)
        return stopwatchToResult(result)
    }
}

// Proximity stopwatch (time between two proximity events)
@MainActor
final class StopwatchProximityHandler: ActionHandler {
    let type = "stopwatch.proximity"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { StopwatchBridge() }
        let maxWait = properties["maxWait"]?.doubleValue ?? 30.0
        let result = try await bridge.proximityStopwatch(maxWait: maxWait)
        return stopwatchToResult(result)
    }
}
