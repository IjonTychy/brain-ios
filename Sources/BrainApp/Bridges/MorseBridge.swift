import AVFoundation
import UIKit
import BrainCore

// Bridge for signal pattern analysis — audio amplitude and visual brightness.
// Provides generic pattern detection that can be used for:
// - Morse code decoding (acoustic + optical)
// - Rhythm detection, tempo analysis
// - Light pattern recognition (beacons, signals)
// - Heartbeat/pulse detection from video
// - Any on/off signal pattern analysis
@MainActor
final class SignalAnalysisBridge: NSObject {

    // MARK: - Audio Amplitude Analysis

    // Record audio and analyze amplitude pattern over time.
    // Returns an array of on/off intervals with their durations.
    // Use cases: Morse code, rhythm detection, clap patterns, noise monitoring.
    func analyzeAudioPattern(duration: TimeInterval = 10.0) async throws -> SignalPattern {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else {
            throw SignalAnalysisError.microphoneAccessDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        var amplitudes: [(time: Double, amplitude: Float)] = []
        let startTime = Date()
        let cappedDuration = min(duration, 60.0)
        let bufferSize: AVAudioFrameCount = 1024

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameCount))
            amplitudes.append((time: Date().timeIntervalSince(startTime), amplitude: rms))
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        return extractPattern(from: amplitudes.map { (time: $0.time, level: $0.amplitude) })
    }

    // MARK: - Visual Brightness Analysis

    // Capture video and analyze brightness changes over time.
    // Returns on/off intervals based on brightness threshold.
    // Use cases: Morse flashlight, LED blink patterns, beacon detection.
    func analyzeBrightnessPattern(duration: TimeInterval = 15.0) async throws -> SignalPattern {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw SignalAnalysisError.cameraAccessDenied }
        } else if status != .authorized {
            throw SignalAnalysisError.cameraAccessDenied
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw SignalAnalysisError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.sessionPreset = .low
        guard session.canAddInput(input) else { throw SignalAnalysisError.cameraSetupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else { throw SignalAnalysisError.cameraSetupFailed }
        session.addOutput(output)

        let collector = BrightnessCollector()
        let queue = DispatchQueue(label: "signal.brightness")
        output.setSampleBufferDelegate(collector, queue: queue)

        session.startRunning()
        try await Task.sleep(for: .seconds(min(duration, 60.0)))
        session.stopRunning()

        return extractPattern(from: collector.samples.map { (time: $0.time, level: $0.brightness) })
    }

    // MARK: - Pattern Extraction (shared)

    private func extractPattern(from samples: [(time: Double, level: Float)]) -> SignalPattern {
        guard !samples.isEmpty else {
            return SignalPattern(intervals: [], totalDuration: 0)
        }

        // Adaptive threshold: mean + 0.5 * stddev
        let mean = samples.map(\.level).reduce(0, +) / Float(samples.count)
        let variance = samples.map { ($0.level - mean) * ($0.level - mean) }.reduce(0, +) / Float(samples.count)
        let threshold = mean + sqrt(variance) * 0.5

        var intervals: [SignalInterval] = []
        var currentIsOn = samples.first.map { $0.level >= threshold } ?? false
        var intervalStart = samples.first?.time ?? 0

        for sample in samples.dropFirst() {
            let isOn = sample.level >= threshold
            if isOn != currentIsOn {
                let duration = sample.time - intervalStart
                if duration > 0.02 { // Debounce: ignore <20ms glitches
                    intervals.append(SignalInterval(isOn: currentIsOn, duration: duration))
                }
                currentIsOn = isOn
                intervalStart = sample.time
            }
        }

        if let last = samples.last {
            let duration = last.time - intervalStart
            if duration > 0.02 {
                intervals.append(SignalInterval(isOn: currentIsOn, duration: duration))
            }
        }

        return SignalPattern(
            intervals: intervals,
            totalDuration: samples.last?.time ?? 0
        )
    }
}

// MARK: - Morse Code Decoder (uses SignalPattern)

// Stateless Morse code translation — can be used independently of signal analysis.
enum MorseCodec: Sendable {

    static let morseToChar: [String: String] = {
        let table: [String: String] = [
            "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
            "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
            "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
            "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
            "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
            "Z": "--..",
            "0": "-----", "1": ".----", "2": "..---", "3": "...--",
            "4": "....-", "5": ".....", "6": "-....", "7": "--...",
            "8": "---..", "9": "----.",
            ".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--",
            "/": "-..-.", "(": "-.--.", ")": "-.--.-", "&": ".-...",
            ":": "---...", ";": "-.-.-.", "=": "-...-", "+": ".-.-.",
            "-": "-....-", "_": "..--.-", "@": ".--.-.",
        ]
        var reversed: [String: String] = [:]
        for (char, code) in table { reversed[code] = char }
        return reversed
    }()

    static let charToMorse: [String: String] = {
        morseToChar.reduce(into: [String: String]()) { $0[$1.value] = $1.key }
    }()

    // Decode a signal pattern into Morse code and text.
    static func decode(pattern: SignalPattern) -> MorseResult {
        let onIntervals = pattern.intervals.filter(\.isOn)
        guard !onIntervals.isEmpty else {
            return MorseResult(morseCode: "", decodedText: "", confidence: 0)
        }

        let sortedDurations = onIntervals.map(\.duration).sorted()
        let medianDuration = sortedDurations[sortedDurations.count / 2]
        let dotDashThreshold = medianDuration * 2.0

        var morseChars: [String] = []
        var currentChar = ""

        for interval in pattern.intervals {
            if interval.isOn {
                currentChar += interval.duration < dotDashThreshold ? "." : "-"
            } else {
                let charGap = medianDuration * 2.5
                let wordGap = medianDuration * 5.0

                if interval.duration >= wordGap {
                    if !currentChar.isEmpty { morseChars.append(currentChar); currentChar = "" }
                    morseChars.append(" ")
                } else if interval.duration >= charGap {
                    if !currentChar.isEmpty { morseChars.append(currentChar); currentChar = "" }
                }
            }
        }
        if !currentChar.isEmpty { morseChars.append(currentChar) }

        let morseString = morseChars.joined(separator: " ")
        var decoded = ""
        for code in morseChars {
            if code == " " { decoded += " " }
            else if let char = morseToChar[code] { decoded += char }
            else { decoded += "?" }
        }

        let total = morseChars.filter { $0 != " " }.count
        let known = morseChars.filter { $0 != " " && morseToChar[$0] != nil }.count
        let confidence = total > 0 ? Double(known) / Double(total) : 0

        return MorseResult(morseCode: morseString, decodedText: decoded.trimmingCharacters(in: .whitespaces), confidence: confidence)
    }

    // Decode Morse text string to plain text.
    static func decodeText(_ morseText: String) -> MorseResult {
        let words = morseText.components(separatedBy: "   ")
        var decoded = ""
        for (i, word) in words.enumerated() {
            if i > 0 { decoded += " " }
            for code in word.components(separatedBy: " ").filter({ !$0.isEmpty }) {
                decoded += morseToChar[code] ?? "?"
            }
        }
        return MorseResult(morseCode: morseText, decodedText: decoded, confidence: 1.0)
    }

    // Encode plain text to Morse code.
    static func encode(_ text: String) -> String {
        text.uppercased().map { char -> String in
            if char == " " { return "  " }
            return charToMorse[String(char)] ?? ""
        }.joined(separator: " ")
    }
}

// MARK: - Brightness Collector

private final class BrightnessCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private(set) var samples: [(time: Double, brightness: Float)] = []
    private let startTime = Date()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let cx = width / 2, cy = height / 2, sz = min(width, height) / 5

        var total: Float = 0
        var count = 0
        for y in (cy - sz / 2)..<(cy + sz / 2) {
            for x in (cx - sz / 2)..<(cx + sz / 2) {
                let off = y * bytesPerRow + x * 4
                let r = Float(buffer[off + 2]), g = Float(buffer[off + 1]), b = Float(buffer[off])
                total += (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
                count += 1
            }
        }

        samples.append((time: Date().timeIntervalSince(startTime), brightness: count > 0 ? total / Float(count) : 0))
    }
}

// MARK: - Models

struct SignalInterval: Codable, Sendable {
    let isOn: Bool
    let duration: Double
}

struct SignalPattern: Codable, Sendable {
    let intervals: [SignalInterval]
    let totalDuration: Double
}

struct MorseResult: Codable, Sendable {
    let morseCode: String
    let decodedText: String
    let confidence: Double
}

enum SignalAnalysisError: Error, LocalizedError {
    case microphoneAccessDenied
    case cameraAccessDenied
    case noCameraAvailable
    case cameraSetupFailed

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied: return "Mikrofonzugriff nicht erlaubt"
        case .cameraAccessDenied: return "Kamerazugriff nicht erlaubt"
        case .noCameraAvailable: return "Keine Kamera verfügbar"
        case .cameraSetupFailed: return "Kamera-Setup fehlgeschlagen"
        }
    }
}

// MARK: - Action Handlers (generic signal analysis + Morse-specific codec)

// Analyze audio amplitude pattern via microphone.
// Use cases: Morse decoding, rhythm detection, clap patterns, noise monitoring.
@MainActor
final class SignalAnalyzeAudioHandler: ActionHandler {
    let type = "signal.analyzeAudio"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 10.0

        let bridge = await MainActor.run { SignalAnalysisBridge() }
        let pattern = try await bridge.analyzeAudioPattern(duration: min(duration, 60.0))

        let intervalsJSON = pattern.intervals.map { interval -> ExpressionValue in
            .object([
                "isOn": .bool(interval.isOn),
                "duration": .double(interval.duration),
            ])
        }

        return .value(.object([
            "intervals": .array(intervalsJSON),
            "intervalCount": .int(pattern.intervals.count),
            "totalDuration": .double(pattern.totalDuration),
            "onCount": .int(pattern.intervals.filter(\.isOn).count),
        ]))
    }
}

// Analyze brightness changes via camera.
// Use cases: Morse flashlight, LED patterns, beacon detection, pulse from video.
@MainActor
final class SignalAnalyzeBrightnessHandler: ActionHandler {
    let type = "signal.analyzeBrightness"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 15.0

        let bridge = await MainActor.run { SignalAnalysisBridge() }
        let pattern = try await bridge.analyzeBrightnessPattern(duration: min(duration, 60.0))

        let intervalsJSON = pattern.intervals.map { interval -> ExpressionValue in
            .object([
                "isOn": .bool(interval.isOn),
                "duration": .double(interval.duration),
            ])
        }

        return .value(.object([
            "intervals": .array(intervalsJSON),
            "intervalCount": .int(pattern.intervals.count),
            "totalDuration": .double(pattern.totalDuration),
            "onCount": .int(pattern.intervals.filter(\.isOn).count),
        ]))
    }
}

// Decode Morse code from text input (dots and dashes).
final class MorseDecodeHandler: ActionHandler, Sendable {
    let type = "morse.decode"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let morseText = properties["morseCode"]?.stringValue else {
            return .actionError(code: "morse.missing_input", message: "morseCode fehlt")
        }
        let result = MorseCodec.decodeText(morseText)
        return .value(.object([
            "morseCode": .string(result.morseCode),
            "decodedText": .string(result.decodedText),
            "confidence": .double(result.confidence),
        ]))
    }
}

// Encode plain text to Morse code.
final class MorseEncodeHandler: ActionHandler, Sendable {
    let type = "morse.encode"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let text = properties["text"]?.stringValue else {
            return .actionError(code: "morse.missing_text", message: "text fehlt")
        }
        let morse = MorseCodec.encode(text)
        return .value(.object([
            "text": .string(text),
            "morseCode": .string(morse),
        ]))
    }
}

// Decode Morse from audio signal pattern (convenience: analyzeAudio + morseCodec).
@MainActor
final class MorseDecodeAudioHandler: ActionHandler {
    let type = "morse.decodeAudio"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 10.0

        let bridge = await MainActor.run { SignalAnalysisBridge() }
        let pattern = try await bridge.analyzeAudioPattern(duration: min(duration, 60.0))
        let result = MorseCodec.decode(pattern: pattern)

        return .value(.object([
            "morseCode": .string(result.morseCode),
            "decodedText": .string(result.decodedText),
            "confidence": .double(result.confidence),
        ]))
    }
}

// Decode Morse from visual signal pattern (convenience: analyzeBrightness + morseCodec).
@MainActor
final class MorseDecodeVisualHandler: ActionHandler {
    let type = "morse.decodeVisual"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 15.0

        let bridge = await MainActor.run { SignalAnalysisBridge() }
        let pattern = try await bridge.analyzeBrightnessPattern(duration: min(duration, 60.0))
        let result = MorseCodec.decode(pattern: pattern)

        return .value(.object([
            "morseCode": .string(result.morseCode),
            "decodedText": .string(result.decodedText),
            "confidence": .double(result.confidence),
        ]))
    }
}
