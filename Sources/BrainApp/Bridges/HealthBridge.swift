import HealthKit
import BrainCore

// Bridge between Action Primitives and HealthKit.
// Provides health.read for reading health data and health.write for saving samples.
@MainActor
final class HealthBridge {

    private let store = HKHealthStore()

    // Check if HealthKit is available on this device.
    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // Request authorization for specific health data types.
    func requestAuthorization(
        toRead: Set<HKSampleType>,
        toWrite: Set<HKSampleType> = []
    ) async throws {
        try await store.requestAuthorization(toShare: toWrite, read: toRead)
    }

    // Read the most recent samples of a given type.
    func readSamples(
        type: HKSampleType,
        limit: Int = 10,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async throws -> [HealthSample] {
        let predicate: NSPredicate?
        if let startDate, let endDate {
            predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )
        } else if let startDate {
            predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: Date(),
                options: .strictStartDate
            )
        } else {
            predicate = nil
        }

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: min(limit, 500),
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples ?? []).compactMap { HealthSample(from: $0) }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    // Read today's statistics for a cumulative quantity type (e.g. steps, calories).
    func readTodayStatistics(for quantityType: HKQuantityType, unit: HKUnit) async throws -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0.0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // Save a quantity sample (e.g., body weight, water intake).
    func saveSample(
        type: HKQuantityType,
        value: Double,
        unit: HKUnit,
        date: Date = Date()
    ) async throws {
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }
}

// MARK: - HealthSample

struct HealthSample: Sendable {
    // Create a fresh formatter per call to avoid Sendable issues with static let.
    private static func formatISO8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    let type: String
    let value: Double?
    let unit: String?
    let startDate: Date
    let endDate: Date
    let sourceName: String?

    init?(from sample: HKSample) {
        self.type = sample.sampleType.identifier
        self.startDate = sample.startDate
        self.endDate = sample.endDate
        self.sourceName = sample.sourceRevision.source.name

        if let quantitySample = sample as? HKQuantitySample {
            // Try common units — use local vars to satisfy definite initialization.
            let knownUnits: [(HKUnit, String)] = [
                (.count(), "count"),
                (.meter(), "m"),
                (.kilocalorie(), "kcal"),
                (.gram(), "g"),
                (.liter(), "L"),
                (.degreeCelsius(), "°C"),
                (.millimeterOfMercury(), "mmHg"),
                (.count().unitDivided(by: .minute()), "bpm"),
                (.second(), "s"),
            ]
            var matchedValue: Double?
            var matchedUnit: String?
            for (hkUnit, unitStr) in knownUnits {
                if quantitySample.quantity.is(compatibleWith: hkUnit) {
                    matchedValue = quantitySample.quantity.doubleValue(for: hkUnit)
                    matchedUnit = unitStr
                    break
                }
            }
            self.value = matchedValue
            self.unit = matchedUnit
        } else {
            self.value = nil
            self.unit = nil
        }
    }

    func toExpressionValue() -> ExpressionValue {
        var dict: [String: ExpressionValue] = [
            "type": .string(type),
            "startDate": .string(Self.formatISO8601(startDate)),
            "endDate": .string(Self.formatISO8601(endDate)),
        ]
        if let value { dict["value"] = .double(value) }
        if let unit { dict["unit"] = .string(unit) }
        if let sourceName { dict["source"] = .string(sourceName) }
        return .object(dict)
    }
}

// MARK: - Known Health Types

enum KnownHealthType {
    // Maps user-friendly type names to HKSampleType + unit.
    // All identifiers are well-known Apple constants, but we use guard-let
    // to avoid force-unwraps per project convention.
    static func resolve(_ name: String) -> (type: HKQuantityType, unit: HKUnit)? {
        let pair: (HKQuantityTypeIdentifier, HKUnit)?
        switch name.lowercased() {
        case "steps", "schritte":
            pair = (.stepCount, .count())
        case "heartrate", "herzfrequenz", "puls":
            pair = (.heartRate, .count().unitDivided(by: .minute()))
        case "calories", "kalorien", "activeenergy":
            pair = (.activeEnergyBurned, .kilocalorie())
        case "distance", "distanz", "strecke":
            pair = (.distanceWalkingRunning, .meter())
        case "weight", "gewicht":
            pair = (.bodyMass, .gramUnit(with: .kilo))
        case "height", "groesse":
            pair = (.height, .meterUnit(with: .centi))
        case "sleep", "schlaf":
            return nil // Sleep is a category type, not quantity
        case "water", "wasser", "trinken":
            pair = (.dietaryWater, .liter())
        case "bloodpressuresystolic", "blutdruck":
            pair = (.bloodPressureSystolic, .millimeterOfMercury())
        case "oxygen", "sauerstoff":
            pair = (.oxygenSaturation, .percent())
        case "temperature", "temperatur":
            pair = (.bodyTemperature, .degreeCelsius())
        default:
            return nil
        }
        guard let pair, let quantityType = HKQuantityType.quantityType(forIdentifier: pair.0) else {
            return nil
        }
        return (quantityType, pair.1)
    }
}

// MARK: - Action Handlers

final class HealthReadHandler: ActionHandler, Sendable {
    let type = "health.read"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { HealthBridge() }

        guard bridge.isAvailable else {
            return .error("health.read: HealthKit nicht verfügbar auf diesem Gerät")
        }

        guard let typeName = properties["type"]?.stringValue else {
            return .error("health.read: type fehlt (z.B. 'steps', 'heartrate', 'weight')")
        }

        guard let resolved = KnownHealthType.resolve(typeName) else {
            return .error("health.read: Unbekannter Typ '\(typeName)'. Unterstuetzte Typen: steps, heartrate, calories, distance, weight, water, oxygen, temperature")
        }

        // Request read authorization
        try await bridge.requestAuthorization(toRead: [resolved.type])

        // Check if "today" statistics requested
        let mode = properties["mode"]?.stringValue ?? "today"

        if mode == "today" {
            let value = try await bridge.readTodayStatistics(for: resolved.type, unit: resolved.unit)
            return .value(.object([
                "type": .string(typeName),
                "value": .double(value),
                "unit": .string(resolved.unit.unitString),
                "period": .string("today"),
            ]))
        }

        // Otherwise, read recent samples
        let limit = properties["limit"]?.intValue ?? 10
        let samples = try await bridge.readSamples(type: resolved.type, limit: limit)
        let items = samples.map { $0.toExpressionValue() }

        return .value(.object([
            "type": .string(typeName),
            "samples": .array(items),
            "count": .int(items.count),
        ]))
    }
}

final class HealthWriteHandler: ActionHandler, Sendable {
    let type = "health.write"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let bridge = await MainActor.run { HealthBridge() }

        guard bridge.isAvailable else {
            return .error("health.write: HealthKit nicht verfügbar auf diesem Gerät")
        }

        guard let typeName = properties["type"]?.stringValue else {
            return .error("health.write: type fehlt (z.B. 'weight', 'water')")
        }

        guard let value = properties["value"]?.doubleValue else {
            return .error("health.write: value fehlt")
        }

        guard let resolved = KnownHealthType.resolve(typeName) else {
            return .error("health.write: Unbekannter Typ '\(typeName)'")
        }

        // Request write authorization
        try await bridge.requestAuthorization(toRead: [], toWrite: [resolved.type])

        try await bridge.saveSample(type: resolved.type, value: value, unit: resolved.unit)
        return .value(.object([
            "status": .string("saved"),
            "type": .string(typeName),
            "value": .double(value),
            "unit": .string(resolved.unit.unitString),
        ]))
    }
}
