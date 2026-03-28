import Speech
@preconcurrency import AVFoundation
import BrainCore

// Bridge between Action Primitives and iOS Speech framework.
// Provides speech.recognize for voice-to-text transcription.
// @unchecked Sendable: SFSpeechRecognizer is thread-safe, AVAudioEngine used serially.
final class SpeechBridge: @unchecked Sendable {

    // Request speech recognition permission.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // Check if speech recognition is available.
    var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))?.isAvailable == true
    }

    // Transcribe audio from a file URL.
    func transcribeFile(url: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechBridgeError.notAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // Start live microphone transcription. Returns the full transcription when stopped.
    // Runs on MainActor because AVAudioEngine and SFSpeechRecognizer are not Sendable.
    @MainActor
    func transcribeLive(duration: TimeInterval = 30) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechBridgeError.notAvailable
        }

        nonisolated(unsafe) let audioEngine = AVAudioEngine()
        nonisolated(unsafe) let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false

        nonisolated(unsafe) let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Use Timer on main run loop (already on MainActor)
        Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            request.endAudio()
        }

        let result: String = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }

        return result
    }
}

enum SpeechBridgeError: Error, LocalizedError {
    case notAvailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Spracherkennung nicht verfügbar"
        case .permissionDenied:
            return "Zugriff auf Spracherkennung nicht erlaubt"
        }
    }
}

// MARK: - Action Handlers

@MainActor final class SpeechRecognizeHandler: ActionHandler {
    let type = "speech.recognize"
    private let bridge = SpeechBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Request permission if needed
        if !bridge.isAvailable {
            let granted = await bridge.requestPermission()
            guard granted else {
                return .error("Spracherkennung nicht erlaubt")
            }
        }

        let duration = properties["duration"]?.doubleValue ?? 15.0
        let text = try await bridge.transcribeLive(duration: duration)
        return .value(.string(text))
    }
}

@MainActor final class SpeechTranscribeFileHandler: ActionHandler {
    let type = "speech.transcribeFile"
    private let bridge = SpeechBridge()

    /// Maximum allowed audio duration in seconds.
    private let maxDurationSeconds: Double = 120

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let urlString = properties["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return .error("speech.transcribeFile: url fehlt")
        }

        // F-40: Validate URL scheme is file:// within app sandbox.
        guard url.isFileURL else {
            return .error("speech.transcribeFile: Nur file:// URLs sind erlaubt")
        }

        let resolvedPath = url.standardizedFileURL.path
        guard let appSandbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent().path,
              resolvedPath.hasPrefix(appSandbox) else {
            return .error("speech.transcribeFile: Dateizugriff ausserhalb der App-Sandbox nicht erlaubt")
        }

        // F-40: Duration cap — reject audio files longer than 120 seconds.
        let asset = AVURLAsset(url: url)
        let durationSeconds = try await CMTimeGetSeconds(asset.load(.duration))
        if durationSeconds > maxDurationSeconds {
            return .error("speech.transcribeFile: Audiodatei zu lang (\(Int(durationSeconds))s) — maximal \(Int(maxDurationSeconds))s erlaubt")
        }

        let text = try await bridge.transcribeFile(url: url)
        return .value(.string(text))
    }
}
