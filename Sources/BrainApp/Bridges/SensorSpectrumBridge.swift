import CoreMotion
import Accelerate
import BrainCore

// Bridge for frequency-domain analysis of sensor data.
// Applies FFT to accelerometer, gyroscope, or magnetometer time-series
// to reveal periodic patterns (vibrations, oscillations, rotations).
// Use cases: Beschleunigungs-Spektrum, Magnetfeld-Spektrum, Vibration analysis,
// resonance detection, structural health monitoring.
@MainActor
final class SensorSpectrumBridge {

    private let sensorBridge = SensorBridge()

    // MARK: - Accelerometer Spectrum

    // Compute frequency spectrum of accelerometer data.
    // Reveals periodic motions like vibrations, oscillations, walking cadence.
    nonisolated func accelerometerSpectrum(duration: TimeInterval = 5.0, sampleRate: Double = 100.0, axis: String = "magnitude") async throws -> SpectrumResult {
        let samples = try await sensorBridge.readAccelerometer(duration: duration, sampleRate: sampleRate)
        let values = extractAxis(from: samples, axis: axis)
        return computeSpectrum(values: values, sampleRate: sampleRate, sensorName: "Accelerometer")
    }

    // MARK: - Gyroscope Spectrum

    // Compute frequency spectrum of gyroscope data.
    // Reveals rotational oscillations, wobble frequencies.
    nonisolated func gyroscopeSpectrum(duration: TimeInterval = 5.0, sampleRate: Double = 100.0, axis: String = "magnitude") async throws -> SpectrumResult {
        let samples = try await sensorBridge.readGyroscope(duration: duration, sampleRate: sampleRate)
        let values = extractAxis(from: samples, axis: axis)
        return computeSpectrum(values: values, sampleRate: sampleRate, sensorName: "Gyroscope")
    }

    // MARK: - Magnetometer Spectrum

    // Compute frequency spectrum of magnetometer data.
    // Reveals oscillating magnetic fields, AC interference (50/60 Hz).
    nonisolated func magnetometerSpectrum(duration: TimeInterval = 5.0, sampleRate: Double = 100.0, axis: String = "magnitude") async throws -> SpectrumResult {
        let samples = try await sensorBridge.readMagnetometer(duration: duration, sampleRate: sampleRate)
        let values = extractAxis(from: samples, axis: axis)
        return computeSpectrum(values: values, sampleRate: sampleRate, sensorName: "Magnetometer")
    }

    // MARK: - DSP

    private nonisolated func extractAxis(from samples: [SensorSample3D], axis: String) -> [Float] {
        switch axis.lowercased() {
        case "x": return samples.map { Float($0.x) }
        case "y": return samples.map { Float($0.y) }
        case "z": return samples.map { Float($0.z) }
        default:
            // Magnitude: sqrt(x² + y² + z²)
            return samples.map { sample -> Float in
                let mag = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)
                return Float(mag)
            }
        }
    }

    private nonisolated func computeSpectrum(values: [Float], sampleRate: Double, sensorName: String) -> SpectrumResult {
        // Pad to next power of two
        let n = nextPowerOfTwo(values.count)
        guard n >= 64 else {
            return SpectrumResult(sensor: sensorName, bins: [], dominantFrequency: 0, dominantMagnitude: 0, sampleCount: values.count, frequencyResolution: 0)
        }

        var padded = values
        if padded.count < n {
            padded.append(contentsOf: [Float](repeating: 0, count: n - padded.count))
        }

        let log2n = vDSP_Length(log2(Float(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return SpectrumResult(sensor: sensorName, bins: [], dominantFrequency: 0, dominantMagnitude: 0, sampleCount: values.count, frequencyResolution: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(padded, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // Split complex format
        let halfN = n / 2
        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                guard let realAddr = realBuf.baseAddress, let imagAddr = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: realAddr, imagp: imagAddr)

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
        var scale = Float(2.0 / Float(n))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Square root for amplitude (not power)
        var sqrtMagnitudes = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvsqrtf(&sqrtMagnitudes, magnitudes, &count)

        // Build bins (skip DC)
        let freqResolution = sampleRate / Double(n)
        var bins: [SpectrumBin] = []
        bins.reserveCapacity(halfN)

        var dominantFreq: Double = 0
        var dominantMag: Float = 0

        for i in 1..<halfN {
            let freq = Double(i) * freqResolution
            let mag = sqrtMagnitudes[i]
            bins.append(SpectrumBin(frequency: round(freq * 100) / 100, magnitude: Double(mag)))

            if mag > dominantMag {
                dominantMag = mag
                dominantFreq = freq
            }
        }

        return SpectrumResult(
            sensor: sensorName,
            bins: bins,
            dominantFrequency: round(dominantFreq * 100) / 100,
            dominantMagnitude: Double(dominantMag),
            sampleCount: values.count,
            frequencyResolution: round(freqResolution * 1000) / 1000
        )
    }

    private nonisolated func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var v = n - 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        return v + 1
    }
}

// MARK: - Models

struct SpectrumBin: Sendable {
    let frequency: Double // Hz
    let magnitude: Double
}

struct SpectrumResult: Sendable {
    let sensor: String
    let bins: [SpectrumBin]
    let dominantFrequency: Double
    let dominantMagnitude: Double
    let sampleCount: Int
    let frequencyResolution: Double
}

// MARK: - Action Handlers

// Accelerometer frequency spectrum (vibration analysis)
@MainActor
final class SensorAccSpectrumHandler: ActionHandler {
    let type = "sensor.accSpectrum"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { SensorSpectrumBridge() }
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 100.0
        let axis = properties["axis"]?.stringValue ?? "magnitude"

        let result = try await bridge.accelerometerSpectrum(duration: duration, sampleRate: sampleRate, axis: axis)
        return spectrumToResult(result)
    }
}

// Gyroscope frequency spectrum
@MainActor
final class SensorGyroSpectrumHandler: ActionHandler {
    let type = "sensor.gyroSpectrum"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { SensorSpectrumBridge() }
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 100.0
        let axis = properties["axis"]?.stringValue ?? "magnitude"

        let result = try await bridge.gyroscopeSpectrum(duration: duration, sampleRate: sampleRate, axis: axis)
        return spectrumToResult(result)
    }
}

// Magnetometer frequency spectrum (AC field detection)
@MainActor
final class SensorMagSpectrumHandler: ActionHandler {
    let type = "sensor.magSpectrum"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { SensorSpectrumBridge() }
        let duration = properties["duration"]?.doubleValue ?? 5.0
        let sampleRate = properties["sampleRate"]?.doubleValue ?? 100.0
        let axis = properties["axis"]?.stringValue ?? "magnitude"

        let result = try await bridge.magnetometerSpectrum(duration: duration, sampleRate: sampleRate, axis: axis)
        return spectrumToResult(result)
    }
}

// Shared helper to convert SpectrumResult → ActionResult
private func spectrumToResult(_ result: SpectrumResult) -> ActionResult {
    .value(.object([
        "sensor": .string(result.sensor),
        "sampleCount": .int(result.sampleCount),
        "frequencyResolution": .double(result.frequencyResolution),
        "dominantFrequency": .double(result.dominantFrequency),
        "dominantMagnitude": .double(result.dominantMagnitude),
        "bins": .array(result.bins.prefix(500).map { bin in
            .object([
                "frequency": .double(bin.frequency),
                "magnitude": .double(bin.magnitude),
            ])
        }),
    ]))
}
