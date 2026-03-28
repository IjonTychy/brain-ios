@preconcurrency import AVFoundation
import BrainCore

// Bridge between Action Primitives and AVFoundation audio.
// Provides audio.record for recording and audio.play for playback.
@MainActor
final class AudioBridge: NSObject {

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playerContinuation: CheckedContinuation<Void, Never>?

    // Request microphone permission.
    nonisolated func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // Record audio to a temporary file. Returns the file URL.
    func record(duration: TimeInterval = 60, quality: AudioQuality = .medium) async throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brain-recording-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: quality.avQuality.rawValue,
        ]

        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        self.recorder = audioRecorder
        audioRecorder.record(forDuration: duration)

        // Wait for the recording to finish, supporting early cancellation
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch is CancellationError {
            // Task was cancelled — stop recording early
        }

        audioRecorder.stop()
        self.recorder = nil

        try session.setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    // Stop an in-progress recording early.
    func stopRecording() -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        return url
    }

    // Play audio from a file URL. Returns when playback completes.
    func play(url: URL) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        self.player = audioPlayer
        audioPlayer.delegate = self

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.playerContinuation = continuation
            audioPlayer.play()
        }

        self.player = nil
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Stop playback.
    func stopPlayback() {
        player?.stop()
        playerContinuation?.resume()
        playerContinuation = nil
        player = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioBridge: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playerContinuation?.resume()
            playerContinuation = nil
        }
    }
}

// MARK: - Audio Quality

enum AudioQuality: String, Sendable {
    case low, medium, high

    var sampleRate: Double {
        switch self {
        case .low: return 16000
        case .medium: return 22050
        case .high: return 44100
        }
    }

    var avQuality: AVAudioQuality {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

// MARK: - Action Handlers

final class AudioRecordHandler: ActionHandler, Sendable {
    let type = "audio.record"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { AudioBridge() }

        let hasPermission = await bridge.requestMicrophoneAccess()
        guard hasPermission else {
            return .error("audio.record: Mikrofonzugriff nicht erlaubt")
        }

        let duration = properties["duration"]?.doubleValue ?? 30.0
        // Cap at 5 minutes to prevent accidental long recordings
        let cappedDuration = min(duration, 300.0)

        let qualityStr = properties["quality"]?.stringValue ?? "medium"
        let quality = AudioQuality(rawValue: qualityStr) ?? .medium

        let url = try await bridge.record(duration: cappedDuration, quality: quality)
        return .value(.object([
            "url": .string(url.absoluteString),
            "duration": .double(cappedDuration),
            "format": .string("m4a"),
        ]))
    }
}

final class AudioPlayHandler: ActionHandler, Sendable {
    let type = "audio.play"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let urlString = properties["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return .error("audio.play: url fehlt")
        }

        // Only allow file:// URLs within app sandbox
        guard url.isFileURL else {
            return .error("audio.play: Nur lokale Dateien (file://) sind erlaubt")
        }

        let bridge = await MainActor.run { AudioBridge() }
        try await bridge.play(url: url)
        return .success
    }
}
