import Speech
@preconcurrency import AVFoundation

// Manages live voice-to-text for chat input fields.
// Streams partial transcription results so the user sees text appear in real-time.
// Used by ChatView's microphone button.
@MainActor
@Observable
final class VoiceInputManager {
    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onPartialResult: ((String) -> Void)?
    var isListening = false
    var permissionDenied = false

    // Start listening with a callback for each partial transcription update.
    func startListening(onPartial: @escaping (String) -> Void) {
        onPartialResult = onPartial

        Task {
            // Request permissions
            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard speechStatus == .authorized else {
                permissionDenied = true
                isListening = false
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                isListening = false
                return
            }

            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE")),
                  recognizer.isAvailable else {
                // Fallback to system locale
                guard let fallback = SFSpeechRecognizer(), fallback.isAvailable else {
                    isListening = false
                    return
                }
                startRecognition(with: fallback)
                return
            }
            startRecognition(with: recognizer)
        }
    }

    private func startRecognition(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isListening = true
        } catch {
            isListening = false
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.onPartialResult?(result.bestTranscription.formattedString)
                }
                if error != nil || (result?.isFinal == true) {
                    self.cleanupAudio()
                }
            }
        }

        // Auto-stop after 60 seconds to save battery
        Task {
            try? await Task.sleep(for: .seconds(60))
            if isListening {
                stopListening()
            }
        }
    }

    // Stop listening and finalize transcription.
    func stopListening() {
        recognitionTask?.finish()
        cleanupAudio()
        isListening = false
    }

    private func cleanupAudio() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
