@preconcurrency import AVFoundation
import Accelerate
import BrainCore

// Bridge for advanced audio analysis — Phyphox-style experiments.
// Provides FFT spectrum, pitch detection (autocorrelation), oscilloscope waveform,
// and tone generation. Uses Accelerate framework for DSP performance.
@MainActor
final class AudioAnalysisBridge: NSObject {

    // MARK: - Audio Amplitude (continuous RMS over time)

    // Measure audio amplitude (RMS) over time. Returns time-series of amplitude values.
    // Use cases: Applausmeter, noise monitoring, volume envelope.
    func measureAmplitude(duration: TimeInterval = 5.0, sampleRate: Double = 50.0) async throws -> [[String: Any]] {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw AudioAnalysisError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let cappedDuration = min(duration, 60.0)
        var samples: [(time: Double, rms: Float, peak: Float, db: Float)] = []
        let startTime = Date()
        let bufferSize: AVAudioFrameCount = UInt32(format.sampleRate / sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            // RMS
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))

            // Peak
            var peak: Float = 0
            vDSP_maxmgv(channelData, 1, &peak, vDSP_Length(count))

            // dB (reference: 1.0 = 0 dBFS)
            let db = rms > 0 ? 20.0 * log10(rms) : -160.0

            let t = Date().timeIntervalSince(startTime)
            samples.append((time: t, rms: rms, peak: peak, db: db))
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        return samples.map { sample in
            [
                "time": sample.time,
                "rms": Double(sample.rms),
                "peak": Double(sample.peak),
                "db": Double(sample.db),
            ] as [String: Any]
        }
    }

    // MARK: - FFT Spectrum

    // Compute frequency spectrum using FFT. Returns frequency bins with magnitudes.
    // Use cases: Audio spectrum analyzer, frequency identification, harmonic analysis.
    func spectrum(duration: TimeInterval = 2.0, fftSize: Int = 4096) async throws -> [[String: Any]] {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw AudioAnalysisError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let audioSampleRate = format.sampleRate

        // Collect raw samples
        let cappedDuration = min(duration, 30.0)
        let validFFTSize = nextPowerOfTwo(max(fftSize, 256))
        var rawSamples: [Float] = []
        rawSamples.reserveCapacity(Int(audioSampleRate * cappedDuration))

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(validFFTSize), format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            rawSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        guard rawSamples.count >= validFFTSize else {
            throw AudioAnalysisError.insufficientData
        }

        // Use the last fftSize samples for spectrum
        let startIdx = rawSamples.count - validFFTSize
        let window = Array(rawSamples[startIdx..<(startIdx + validFFTSize)])

        return computeFFT(samples: window, sampleRate: audioSampleRate)
    }

    // MARK: - Autocorrelation (Pitch Detection)

    // Detect the fundamental frequency (pitch) of an audio signal via autocorrelation.
    // Returns detected frequency in Hz and musical note name.
    // Use cases: Tuner, pitch detection, frequency measurement, Doppler effect.
    func detectPitch(duration: TimeInterval = 3.0) async throws -> [String: Any] {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw AudioAnalysisError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let audioSampleRate = format.sampleRate

        let cappedDuration = min(duration, 30.0)
        let fftSize = 4096
        var rawSamples: [Float] = []
        rawSamples.reserveCapacity(Int(audioSampleRate * cappedDuration))

        // Collect multiple pitch readings over time
        var pitchReadings: [(time: Double, frequency: Double)] = []
        let startTime = Date()

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
            rawSamples.append(contentsOf: samples)

            // Only compute pitch when we have enough samples
            if samples.count >= fftSize {
                let freq = self.autocorrelationPitch(samples: samples, sampleRate: audioSampleRate)
                if freq > 0 {
                    let t = Date().timeIntervalSince(startTime)
                    pitchReadings.append((time: t, frequency: freq))
                }
            }
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        // Average the detected pitches (ignore outliers)
        let avgFrequency: Double
        if pitchReadings.isEmpty {
            avgFrequency = 0
        } else {
            let sorted = pitchReadings.map(\.frequency).sorted()
            // Use median for robustness
            avgFrequency = sorted[sorted.count / 2]
        }

        let note = frequencyToNote(avgFrequency)

        return [
            "frequency": avgFrequency,
            "note": note.name,
            "octave": note.octave,
            "cents": note.cents,
            "readings": pitchReadings.map { ["time": $0.time, "frequency": $0.frequency] },
        ]
    }

    // MARK: - Oscilloscope (Waveform)

    // Capture raw waveform data for oscilloscope display.
    // Returns time-domain samples at the given sample rate.
    // Use cases: Waveform visualization, signal analysis, audio debugging.
    func oscilloscope(duration: TimeInterval = 0.1, sampleRate: Double = 44100) async throws -> [[String: Any]] {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw AudioAnalysisError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let audioSampleRate = format.sampleRate

        // Short capture (max 2 seconds for oscilloscope)
        let cappedDuration = min(duration, 2.0)
        var rawSamples: [Float] = []

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            rawSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        // Downsample if requested rate is lower than native
        let step = max(1, Int(audioSampleRate / sampleRate))
        let maxSamples = min(rawSamples.count, 10000) // Cap to prevent huge responses

        var result: [[String: Any]] = []
        result.reserveCapacity(maxSamples / step)

        for i in stride(from: 0, to: maxSamples, by: step) {
            let time = Double(i) / audioSampleRate
            result.append([
                "time": time,
                "amplitude": Double(rawSamples[i]),
            ])
        }

        return result
    }

    // MARK: - Tone Generator

    // Generate a sine wave tone at a given frequency for a given duration.
    // Use cases: Frequency generator, hearing test, acoustic experiments, sonar.
    func generateTone(frequency: Double = 440.0, duration: TimeInterval = 1.0, volume: Float = 0.5) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        let audioSampleRate: Double = 44100
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: audioSampleRate, channels: 1) else {
            throw AudioAnalysisError.toneGenerationFailed
        }

        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        let cappedDuration = min(duration, 30.0)
        let cappedFrequency = min(max(frequency, 20.0), 20000.0) // Audible range
        let cappedVolume = min(max(volume, 0.0), 1.0)

        let frameCount = AVAudioFrameCount(audioSampleRate * cappedDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            throw AudioAnalysisError.toneGenerationFailed
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioAnalysisError.toneGenerationFailed
        }
        let data = channelData
        let twoPiF = Float(2.0 * Double.pi * cappedFrequency)
        let sr = Float(audioSampleRate)

        for i in 0..<Int(frameCount) {
            data[i] = cappedVolume * sin(twoPiF * Float(i) / sr)
        }

        try engine.start()
        playerNode.play()
        await playerNode.scheduleBuffer(buffer)

        try await Task.sleep(for: .seconds(cappedDuration + 0.1))
        playerNode.stop()
        engine.stop()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Sonar (Echo Distance Measurement)

    // Emit a short chirp tone and measure the time until echo is detected.
    // Returns estimated distance based on speed of sound (~343 m/s at 20°C).
    // Use cases: Distance measurement, room size estimation.
    func sonar(frequency: Double = 5000.0, maxDistance: Double = 10.0) async throws -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        let audioSampleRate: Double = 44100
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: audioSampleRate, channels: 1) else {
            throw AudioAnalysisError.toneGenerationFailed
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Generate a short chirp (10ms)
        let chirpDuration: Double = 0.01
        let chirpFrames = AVAudioFrameCount(audioSampleRate * chirpDuration)
        guard let chirpBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chirpFrames) else {
            throw AudioAnalysisError.toneGenerationFailed
        }
        chirpBuffer.frameLength = chirpFrames

        guard let chirpChannelData = chirpBuffer.floatChannelData?[0] else {
            throw AudioAnalysisError.toneGenerationFailed
        }
        let chirpData = chirpChannelData
        let twoPiF = Float(2.0 * Double.pi * frequency)
        for i in 0..<Int(chirpFrames) {
            // Envelope: fade in/out to avoid click
            let envelope = sin(Float.pi * Float(i) / Float(chirpFrames))
            chirpData[i] = 0.8 * envelope * sin(twoPiF * Float(i) / Float(audioSampleRate))
        }

        // Listen for echo
        let speedOfSound: Double = 343.0 // m/s at 20°C
        let maxListenTime = (2.0 * maxDistance / speedOfSound) + 0.05 // round-trip + margin
        var amplitudes: [(time: Double, amplitude: Float)] = []
        let startTime = Date()

        inputNode.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))
            amplitudes.append((time: Date().timeIntervalSince(startTime), amplitude: rms))
        }

        try engine.start()
        playerNode.play()
        await playerNode.scheduleBuffer(chirpBuffer)

        try await Task.sleep(for: .seconds(maxListenTime))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        // Find echo peak (skip the first few ms — that's our own chirp)
        let skipTime = chirpDuration + 0.005 // Skip chirp + settling
        let echoSamples = amplitudes.filter { $0.time > skipTime }

        guard !echoSamples.isEmpty else {
            return [
                "detected": false,
                "distance": 0.0,
                "echoTime": 0.0,
            ]
        }

        // Find the peak amplitude after the chirp
        let threshold = echoSamples.map(\.amplitude).sorted().last.map { $0 * 0.3 } ?? 0.01
        if let echoPeak = echoSamples.first(where: { $0.amplitude > threshold }) {
            let roundTripTime = echoPeak.time - chirpDuration / 2 // Compensate for chirp center
            let distance = (roundTripTime * speedOfSound) / 2.0 // One-way distance

            return [
                "detected": true,
                "distance": round(distance * 100) / 100, // cm precision
                "echoTime": roundTripTime,
                "unit": "m",
            ]
        }

        return [
            "detected": false,
            "distance": 0.0,
            "echoTime": 0.0,
        ]
    }

    // MARK: - Frequency Tracking (Doppler)

    // Track frequency changes over time. Useful for Doppler effect measurement.
    // Returns time-series of detected frequencies.
    func trackFrequency(duration: TimeInterval = 10.0, referenceFrequency: Double? = nil) async throws -> [[String: Any]] {
        let hasPermission = await AVAudioApplication.requestRecordPermission()
        guard hasPermission else { throw AudioAnalysisError.microphoneAccessDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let audioSampleRate = format.sampleRate

        let cappedDuration = min(duration, 60.0)
        let fftSize = 4096
        var readings: [(time: Double, frequency: Double, amplitude: Float)] = []
        let startTime = Date()

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count >= fftSize else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: min(count, fftSize)))

            // RMS for amplitude
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

            // Only detect pitch if signal is strong enough
            if rms > 0.01 {
                let freq = self.autocorrelationPitch(samples: samples, sampleRate: audioSampleRate)
                if freq > 0 {
                    let t = Date().timeIntervalSince(startTime)
                    readings.append((time: t, frequency: freq, amplitude: rms))
                }
            }
        }

        try engine.start()
        try await Task.sleep(for: .seconds(cappedDuration))
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try session.setActive(false)

        return readings.map { reading in
            var entry: [String: Any] = [
                "time": reading.time,
                "frequency": reading.frequency,
                "amplitude": Double(reading.amplitude),
            ]
            if let ref = referenceFrequency {
                let shift = reading.frequency - ref
                let shiftPercent = (shift / ref) * 100
                entry["shift"] = shift
                entry["shiftPercent"] = shiftPercent
            }
            return entry
        }
    }

    // MARK: - DSP Helpers

    private func computeFFT(samples: [Float], sampleRate: Double) -> [[String: Any]] {
        let n = samples.count
        let log2n = vDSP_Length(log2(Float(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // Split complex
        let halfN = n / 2
        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                guard let realAddr = realBuf.baseAddress, let imagAddr = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: realAddr, imagp: imagAddr)

                // Pack into split complex
                windowed.withUnsafeBufferPointer { ptr in
                    guard let baseAddr = ptr.baseAddress else { return }
                    baseAddr.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                // FFT
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Magnitudes
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Normalize
        var scale = Float(1.0 / Float(n))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Convert to dB
        var dbMagnitudes = [Float](repeating: 0, count: halfN)
        var one: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &one, &dbMagnitudes, 1, vDSP_Length(halfN), 0)

        // Build result (skip DC component)
        let freqResolution = sampleRate / Double(n)
        var result: [[String: Any]] = []
        result.reserveCapacity(halfN)

        for i in 1..<halfN {
            let freq = Double(i) * freqResolution
            if freq > 20000 { break } // Only audible range
            result.append([
                "frequency": round(freq * 10) / 10,
                "magnitude": Double(magnitudes[i]),
                "db": Double(dbMagnitudes[i]),
            ])
        }

        return result
    }

    private func autocorrelationPitch(samples: [Float], sampleRate: Double) -> Double {
        let n = samples.count
        guard n >= 256 else { return 0 }

        // Autocorrelation via Accelerate
        let minLag = Int(sampleRate / 5000) // Max 5 kHz
        let maxLag = min(Int(sampleRate / 50), n / 2) // Min 50 Hz
        guard maxLag > minLag else { return 0 }

        var bestLag = 0
        var bestCorr: Float = 0

        for lag in minLag..<maxLag {
            var correlation: Float = 0
            vDSP_dotpr(samples, 1,
                       Array(samples[lag..<n]), 1,
                       &correlation,
                       vDSP_Length(n - lag))

            // Normalize
            correlation /= Float(n - lag)

            if correlation > bestCorr {
                bestCorr = correlation
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return 0 }
        return sampleRate / Double(bestLag)
    }

    private func nextPowerOfTwo(_ n: Int) -> Int {
        var v = n - 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        return v + 1
    }

    private func frequencyToNote(_ frequency: Double) -> (name: String, octave: Int, cents: Double) {
        guard frequency > 0 else { return ("—", 0, 0) }

        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let a4 = 440.0
        let semitonesFromA4 = 12.0 * log2(frequency / a4)
        let roundedSemitones = Int(round(semitonesFromA4))
        let cents = (semitonesFromA4 - Double(roundedSemitones)) * 100.0

        // A4 = MIDI note 69
        let midiNote = 69 + roundedSemitones
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1

        return (noteNames[noteIndex], octave, round(cents * 10) / 10)
    }
}

// MARK: - Errors

enum AudioAnalysisError: Error, LocalizedError {
    case microphoneAccessDenied
    case insufficientData
    case toneGenerationFailed

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied: return "Mikrofonzugriff nicht erlaubt"
        case .insufficientData: return "Nicht genuegend Audiodaten aufgenommen"
        case .toneGenerationFailed: return "Tongenerierung fehlgeschlagen"
        }
    }
}

// MARK: - Action Handlers

// Audio amplitude measurement (continuous RMS, peak, dB)
@MainActor
final class AudioAmplitudeHandler: ActionHandler {
    let type = "audio.amplitude"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 50.0
        let bridge = AudioAnalysisBridge()
        let samples = try await bridge.measureAmplitude(duration: duration, sampleRate: sampleRate)

        let rmsValues = samples.compactMap { $0["rms"] as? Double }
        let avgRms = rmsValues.isEmpty ? 0 : rmsValues.reduce(0, +) / Double(rmsValues.count)
        let maxRms = rmsValues.max() ?? 0
        let dbValues = samples.compactMap { $0["db"] as? Double }
        let avgDb = dbValues.isEmpty ? -160 : dbValues.reduce(0, +) / Double(dbValues.count)

        let sampleArray: [ExpressionValue] = samples.map { sample in
            let t = sample["time"] as? Double ?? 0
            let r = sample["rms"] as? Double ?? 0
            let p = sample["peak"] as? Double ?? 0
            let d = sample["db"] as? Double ?? 0
            return .object(["time": .double(t), "rms": .double(r), "peak": .double(p), "db": .double(d)])
        }

        var dict: [String: ExpressionValue] = [:]
        dict["sampleCount"] = .int(samples.count)
        dict["duration"] = .double(duration)
        dict["averageRms"] = .double(round(avgRms * 10000) / 10000)
        dict["maxRms"] = .double(round(maxRms * 10000) / 10000)
        dict["averageDb"] = .double(round(avgDb * 10) / 10)
        dict["samples"] = .array(sampleArray)
        return .value(.object(dict))
    }
}

// FFT spectrum analysis
@MainActor
final class AudioSpectrumHandler: ActionHandler {
    let type = "audio.spectrum"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 2.0
        let fftSize = properties["fftSize"]?.intValue ?? 4096
        let bridge = AudioAnalysisBridge()
        let bins = try await bridge.spectrum(duration: duration, fftSize: fftSize)

        var dominantFreq: Double = 0
        var dominantMag: Double = -999
        for bin in bins {
            if let mag = bin["db"] as? Double, let freq = bin["frequency"] as? Double, mag > dominantMag {
                dominantMag = mag
                dominantFreq = freq
            }
        }

        let binArray: [ExpressionValue] = bins.prefix(500).map { bin in
            let f = bin["frequency"] as? Double ?? 0
            let m = bin["magnitude"] as? Double ?? 0
            let d = bin["db"] as? Double ?? 0
            return .object(["frequency": .double(f), "magnitude": .double(m), "db": .double(d)])
        }

        var dict: [String: ExpressionValue] = [:]
        dict["binCount"] = .int(bins.count)
        dict["dominantFrequency"] = .double(dominantFreq)
        dict["dominantMagnitudeDb"] = .double(round(dominantMag * 10) / 10)
        dict["bins"] = .array(binArray)
        return .value(.object(dict))
    }
}

// Pitch detection via autocorrelation
@MainActor
final class AudioPitchHandler: ActionHandler {
    let type = "audio.pitch"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 3.0
        let bridge = AudioAnalysisBridge()
        let result = try await bridge.detectPitch(duration: duration)

        let readings = (result["readings"] as? [[String: Double]]) ?? []
        let readingArray: [ExpressionValue] = readings.map { r in
            let t = r["time"] ?? 0
            let f = r["frequency"] ?? 0
            return .object(["time": .double(t), "frequency": .double(f)])
        }

        var dict: [String: ExpressionValue] = [:]
        dict["frequency"] = .double(result["frequency"] as? Double ?? 0)
        dict["note"] = .string(result["note"] as? String ?? "—")
        dict["octave"] = .int(result["octave"] as? Int ?? 0)
        dict["cents"] = .double(result["cents"] as? Double ?? 0)
        dict["readings"] = .array(readingArray)
        return .value(.object(dict))
    }
}

// Oscilloscope waveform capture
@MainActor
final class AudioOscilloscopeHandler: ActionHandler {
    let type = "audio.oscilloscope"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 0.1
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 44100
        let bridge = AudioAnalysisBridge()
        let waveform = try await bridge.oscilloscope(duration: duration, sampleRate: sampleRate)

        let waveArray: [ExpressionValue] = waveform.map { sample in
            let t = sample["time"] as? Double ?? 0
            let a = sample["amplitude"] as? Double ?? 0
            return .object(["time": .double(t), "amplitude": .double(a)])
        }

        var dict: [String: ExpressionValue] = [:]
        dict["sampleCount"] = .int(waveform.count)
        dict["duration"] = .double(duration)
        dict["sampleRate"] = .double(sampleRate)
        dict["waveform"] = .array(waveArray)
        return .value(.object(dict))
    }
}

// Tone generator (sine wave)
@MainActor
final class AudioToneHandler: ActionHandler {
    let type = "audio.tone"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let frequency = properties["frequency"]?.doubleValue ?? 440.0
        let duration = properties["duration"]?.doubleValue ?? 1.0
        let volume = Float(properties["volume"]?.doubleValue ?? 0.5)
        let bridge = AudioAnalysisBridge()
        try await bridge.generateTone(frequency: frequency, duration: duration, volume: volume)

        var dict: [String: ExpressionValue] = [:]
        dict["frequency"] = .double(frequency)
        dict["duration"] = .double(duration)
        dict["volume"] = .double(Double(volume))
        return .value(.object(dict))
    }
}

// Sonar (echo-based distance measurement)
@MainActor
final class AudioSonarHandler: ActionHandler {
    let type = "audio.sonar"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let frequency = properties["frequency"]?.doubleValue ?? 5000.0
        let maxDistance = properties["maxDistance"]?.doubleValue ?? 10.0
        let bridge = AudioAnalysisBridge()
        let result = try await bridge.sonar(frequency: frequency, maxDistance: maxDistance)

        var dict: [String: ExpressionValue] = [:]
        dict["detected"] = .bool(result["detected"] as? Bool ?? false)
        dict["distance"] = .double(result["distance"] as? Double ?? 0)
        dict["echoTime"] = .double(result["echoTime"] as? Double ?? 0)
        dict["unit"] = .string("m")
        return .value(.object(dict))
    }
}

// Frequency tracking (Doppler effect)
@MainActor
final class AudioFrequencyTrackHandler: ActionHandler {
    let type = "audio.frequencyTrack"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let duration = properties["duration"]?.doubleValue ?? 10.0
        let referenceFrequency = properties["referenceFrequency"]?.doubleValue
        let bridge = AudioAnalysisBridge()
        let readings = try await bridge.trackFrequency(duration: duration, referenceFrequency: referenceFrequency)

        let readingArray: [ExpressionValue] = readings.map { r in
            var entry: [String: ExpressionValue] = [:]
            entry["time"] = .double(r["time"] as? Double ?? 0)
            entry["frequency"] = .double(r["frequency"] as? Double ?? 0)
            entry["amplitude"] = .double(r["amplitude"] as? Double ?? 0)
            if let shift = r["shift"] as? Double {
                entry["shift"] = .double(shift)
            }
            if let shiftPercent = r["shiftPercent"] as? Double {
                entry["shiftPercent"] = .double(shiftPercent)
            }
            return .object(entry)
        }

        var dict: [String: ExpressionValue] = [:]
        dict["readingCount"] = .int(readings.count)
        dict["duration"] = .double(duration)
        if let refFreq = referenceFrequency {
            dict["referenceFrequency"] = .double(refFreq)
        } else {
            dict["referenceFrequency"] = .null
        }
        dict["readings"] = .array(readingArray)
        return .value(.object(dict))
    }
}
