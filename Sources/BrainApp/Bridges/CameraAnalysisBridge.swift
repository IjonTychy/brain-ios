@preconcurrency import AVFoundation
import ARKit
import UIKit
import BrainCore

// Bridge for camera-based measurement — Phyphox-style experiments.
// Provides HSV color detection, luminance/brightness measurement,
// and LiDAR depth measurement.
// Use cases: Farbmessung, Leuchtdichte, Tiefensensor, optische Analyse.
@MainActor
final class CameraAnalysisBridge: NSObject {

    // MARK: - Color Analysis (HSV)

    // Capture a frame from the camera and analyze the center region's color.
    // Returns HSV (Hue, Saturation, Value) and RGB values.
    // Use cases: Farbmessung, Farbvergleich, Colorimeter, pH-Teststreifen ablesen.
    func analyzeColor(regionSize: CGFloat = 0.1) async throws -> ColorAnalysisResult {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraAnalysisError.cameraAccessDenied }
        } else if status != .authorized {
            throw CameraAnalysisError.cameraAccessDenied
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraAnalysisError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { throw CameraAnalysisError.cameraSetupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { throw CameraAnalysisError.cameraSetupFailed }
        session.addOutput(output)

        // Capture a single frame
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ColorAnalysisResult, Error>) in
            let delegate = ColorSampleDelegate(regionSize: regionSize, continuation: continuation)
            output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "camera.color"))
            session.startRunning()
            // delegate retains itself via the reference in the closure
            self._colorDelegate = delegate
        }

        session.stopRunning()
        self._colorDelegate = nil
        return result
    }

    private var _colorDelegate: ColorSampleDelegate?

    // MARK: - Luminance Measurement

    // Measure brightness/luminance over time from camera feed.
    // Returns time-series of brightness values (0.0 - 1.0).
    // Use cases: Leuchtdichte-Messung, Lichtsensor-Ersatz, optische Stoppuhr.
    func measureLuminance(duration: TimeInterval = 5.0, sampleRate: Double = 30.0) async throws -> [LuminanceSample] {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraAnalysisError.cameraAccessDenied }
        } else if status != .authorized {
            throw CameraAnalysisError.cameraAccessDenied
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraAnalysisError.noCameraAvailable
        }

        // Lock exposure for consistent measurements
        if device.isExposureModeSupported(.locked) {
            try device.lockForConfiguration()
            device.exposureMode = .locked
            device.unlockForConfiguration()
        }

        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.sessionPreset = .low
        guard session.canAddInput(input) else { throw CameraAnalysisError.cameraSetupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { throw CameraAnalysisError.cameraSetupFailed }
        session.addOutput(output)

        let cappedDuration = min(duration, 60.0)
        var samples: [LuminanceSample] = []
        let startTime = Date()

        let delegate = LuminanceSampleDelegate { brightness in
            let t = Date().timeIntervalSince(startTime)
            if t <= cappedDuration {
                samples.append(LuminanceSample(time: t, brightness: brightness))
            }
        }

        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "camera.luminance"))
        session.startRunning()

        try await Task.sleep(for: .seconds(cappedDuration))

        session.stopRunning()

        return samples
    }

    // MARK: - LiDAR Depth Measurement

    // Measure distance using LiDAR/ToF sensor (if available).
    // Returns depth in meters at the center point and a depth map summary.
    // Use cases: Entfernungsmessung, Raumvermessung, 3D-Scanning.
    func measureDepth() async throws -> DepthResult {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            throw CameraAnalysisError.lidarUnavailable
        }

        let arSession = ARSession()
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        arSession.run(config)

        // Wait for depth data
        var depthResult: DepthResult?
        for _ in 0..<30 { // Try for up to 3 seconds
            try await Task.sleep(for: .milliseconds(100))
            if let frame = arSession.currentFrame,
               let depthMap = frame.sceneDepth?.depthMap {

                let width = CVPixelBufferGetWidth(depthMap)
                let height = CVPixelBufferGetHeight(depthMap)

                CVPixelBufferLockBaseAddress(depthMap, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { continue }
                let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

                // Center point depth
                let centerIdx = (height / 2) * width + (width / 2)
                let centerDepth = Double(buffer[centerIdx])

                // Statistics
                let totalPixels = width * height
                var minDepth: Float = .infinity
                var maxDepth: Float = 0
                var sumDepth: Float = 0
                var validCount = 0

                for i in 0..<totalPixels {
                    let d = buffer[i]
                    if d > 0 && d < 100 { // Valid range
                        minDepth = min(minDepth, d)
                        maxDepth = max(maxDepth, d)
                        sumDepth += d
                        validCount += 1
                    }
                }

                let avgDepth = validCount > 0 ? Double(sumDepth / Float(validCount)) : 0

                depthResult = DepthResult(
                    centerDepth: round(centerDepth * 1000) / 1000,
                    minDepth: round(Double(minDepth) * 1000) / 1000,
                    maxDepth: round(Double(maxDepth) * 1000) / 1000,
                    avgDepth: round(avgDepth * 1000) / 1000,
                    width: width,
                    height: height,
                    unit: "m"
                )
                break
            }
        }

        arSession.pause()

        guard let result = depthResult else {
            throw CameraAnalysisError.depthDataUnavailable
        }
        return result
    }
}

// MARK: - Models

struct ColorAnalysisResult: Sendable {
    let hue: Double        // 0-360 degrees
    let saturation: Double // 0-1
    let value: Double      // 0-1 (brightness)
    let red: Double        // 0-255
    let green: Double      // 0-255
    let blue: Double       // 0-255
    let hexColor: String   // #RRGGBB
}

struct LuminanceSample: Sendable {
    let time: Double
    let brightness: Double // 0.0-1.0
}

struct DepthResult: Sendable {
    let centerDepth: Double
    let minDepth: Double
    let maxDepth: Double
    let avgDepth: Double
    let width: Int
    let height: Int
    let unit: String
}

// MARK: - Errors

enum CameraAnalysisError: Error, LocalizedError {
    case cameraAccessDenied
    case noCameraAvailable
    case cameraSetupFailed
    case lidarUnavailable
    case depthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied: return "Kamerazugriff nicht erlaubt"
        case .noCameraAvailable: return "Keine Kamera verfügbar"
        case .cameraSetupFailed: return "Kamera-Setup fehlgeschlagen"
        case .lidarUnavailable: return "LiDAR/Tiefensensor nicht verfügbar auf diesem Gerät"
        case .depthDataUnavailable: return "Keine Tiefendaten empfangen"
        }
    }
}

// MARK: - AVCaptureVideoDataOutput Delegates

private class ColorSampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let regionSize: CGFloat
    var continuation: CheckedContinuation<ColorAnalysisResult, Error>?
    private var captured = false

    init(regionSize: CGFloat, continuation: CheckedContinuation<ColorAnalysisResult, Error>) {
        self.regionSize = regionSize
        self.continuation = continuation
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !captured, let continuation else { return }
        captured = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            continuation.resume(throwing: CameraAnalysisError.cameraSetupFailed)
            self.continuation = nil
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            continuation.resume(throwing: CameraAnalysisError.cameraSetupFailed)
            self.continuation = nil
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Sample center region
        let regionW = Int(CGFloat(width) * regionSize)
        let regionH = Int(CGFloat(height) * regionSize)
        let startX = (width - regionW) / 2
        let startY = (height - regionH) / 2

        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0
        var pixelCount: Double = 0

        for y in startY..<(startY + regionH) {
            for x in startX..<(startX + regionW) {
                let offset = y * bytesPerRow + x * 4
                totalB += Double(buffer[offset])     // BGRA format
                totalG += Double(buffer[offset + 1])
                totalR += Double(buffer[offset + 2])
                pixelCount += 1
            }
        }

        guard pixelCount > 0 else {
            continuation.resume(throwing: CameraAnalysisError.cameraSetupFailed)
            self.continuation = nil
            return
        }

        let r = totalR / pixelCount
        let g = totalG / pixelCount
        let b = totalB / pixelCount

        // RGB → HSV
        let rn = r / 255.0, gn = g / 255.0, bn = b / 255.0
        let cmax = max(rn, gn, bn)
        let cmin = min(rn, gn, bn)
        let delta = cmax - cmin

        var hue: Double = 0
        if delta > 0 {
            if cmax == rn {
                hue = 60 * fmod((gn - bn) / delta, 6)
            } else if cmax == gn {
                hue = 60 * ((bn - rn) / delta + 2)
            } else {
                hue = 60 * ((rn - gn) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }

        let saturation = cmax > 0 ? delta / cmax : 0
        let value = cmax

        let hexColor = String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))

        let result = ColorAnalysisResult(
            hue: round(hue * 10) / 10,
            saturation: round(saturation * 1000) / 1000,
            value: round(value * 1000) / 1000,
            red: round(r),
            green: round(g),
            blue: round(b),
            hexColor: hexColor
        )

        continuation.resume(returning: result)
        self.continuation = nil
    }
}

private class LuminanceSampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let onSample: (Double) -> Void

    init(onSample: @escaping (Double) -> Void) {
        self.onSample = onSample
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

        // Sample every 4th pixel for performance
        var totalLuma: Double = 0
        var count: Double = 0

        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let offset = y * bytesPerRow + x * 4
                let b = Double(buffer[offset])
                let g = Double(buffer[offset + 1])
                let r = Double(buffer[offset + 2])
                // ITU-R BT.709 luma coefficients
                totalLuma += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }

        let brightness = count > 0 ? (totalLuma / count) / 255.0 : 0
        onSample(round(brightness * 10000) / 10000)
    }
}

// MARK: - Action Handlers

// Camera color analysis (HSV + RGB)
@MainActor
final class CameraColorHandler: ActionHandler {
    let type = "camera.color"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { CameraAnalysisBridge() }
        let regionSize = properties["regionSize"]?.doubleValue ?? 0.1
        let result = try await bridge.analyzeColor(regionSize: CGFloat(regionSize))

        return .value(.object([
            "hue": .double(result.hue),
            "saturation": .double(result.saturation),
            "value": .double(result.value),
            "red": .double(result.red),
            "green": .double(result.green),
            "blue": .double(result.blue),
            "hex": .string(result.hexColor),
        ]))
    }
}

// Camera luminance measurement over time
@MainActor
final class CameraLuminanceHandler: ActionHandler {
    let type = "camera.luminance"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { CameraAnalysisBridge() }
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 30.0
        let samples = try await bridge.measureLuminance(duration: duration, sampleRate: sampleRate)

        let values = samples.map(\.brightness)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 0

        return .value(.object([
            "sampleCount": .int(samples.count),
            "duration": .double(duration),
            "average": .double(round(avg * 10000) / 10000),
            "min": .double(round(minVal * 10000) / 10000),
            "max": .double(round(maxVal * 10000) / 10000),
            "samples": .array(samples.prefix(1000).map { s in
                .object([
                    "time": .double(s.time),
                    "brightness": .double(s.brightness),
                ])
            }),
        ]))
    }
}

// LiDAR depth measurement
@MainActor
final class CameraDepthHandler: ActionHandler {
    let type = "camera.depth"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { CameraAnalysisBridge() }
        let result = try await bridge.measureDepth()

        return .value(.object([
            "centerDepth": .double(result.centerDepth),
            "minDepth": .double(result.minDepth),
            "maxDepth": .double(result.maxDepth),
            "avgDepth": .double(result.avgDepth),
            "width": .int(result.width),
            "height": .int(result.height),
            "unit": .string(result.unit),
        ]))
    }
}
