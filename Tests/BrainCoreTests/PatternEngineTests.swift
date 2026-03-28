import Testing
import Foundation
import GRDB
@testable import BrainCore

@Suite("Pattern Engine")
struct PatternEngineTests {

    private func makeEngine() throws -> (PatternEngine, EntryService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (PatternEngine(pool: db.pool), EntryService(pool: db.pool), db)
    }

    @Test("Keine Muster bei leerer Datenbank")
    func emptyDatabase() throws {
        let (engine, _, _) = try makeEngine()
        #expect(try engine.analyze().isEmpty)
    }

    @Test("Kein Streak bei weniger als 3 Tagen")
    func streakBelowThreshold() throws {
        let (engine, svc, _) = try makeEngine()
        let today = DateFormatters.dateOnly.string(from: Date())
        let yesterday = DateFormatters.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        try svc.create(Entry(type: .task, title: "Task 1", status: .done,
            createdAt: today + "T10:00:00Z"))
        try svc.create(Entry(type: .task, title: "Task 2", status: .done,
            createdAt: yesterday + "T10:00:00Z"))
        #expect(try engine.analyze().filter { $0.type == .streak }.isEmpty)
    }

    @Test("Streak wird erkannt ab 3 aufeinanderfolgenden Tagen")
    func streakDetectedAt3Days() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<3 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            try svc.create(Entry(type: .task, title: "Task",
                status: .done, createdAt: dayStr + "T10:00:00Z"))
        }
        let streaks = try engine.analyze().filter { $0.type == .streak }
        #expect(!streaks.isEmpty)
        #expect(streaks.first?.description.contains("3") == true)
    }

    @Test("Streak-Confidence ist 1.0 bei 7 Tagen")
    func streakConfidenceMax() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            try svc.create(Entry(type: .task, title: "Task",
                status: .done, createdAt: dayStr + "T10:00:00Z"))
        }
        let streaks = try engine.analyze().filter { $0.type == .streak }
        #expect(!streaks.isEmpty)
        #expect(streaks.first!.confidence == 1.0)
    }

    @Test("Streak bricht bei fehlendem Tag ab")
    func streakBreaksOnGap() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        let todayStr = DateFormatters.dateOnly.string(from: today)
        let d2 = DateFormatters.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -2, to: today)!)
        let d3 = DateFormatters.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -3, to: today)!)
        try svc.create(Entry(type: .task, title: "T1", status: .done,
            createdAt: todayStr + "T10:00:00Z"))
        try svc.create(Entry(type: .task, title: "T2", status: .done,
            createdAt: d2 + "T10:00:00Z"))
        try svc.create(Entry(type: .task, title: "T3", status: .done,
            createdAt: d3 + "T10:00:00Z"))
        #expect(try engine.analyze().filter { $0.type == .streak }.isEmpty)
    }

    @Test("Streak zaehlt nur erledigte Tasks")
    func streakOnlyCountsDoneTasks() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<5 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            try svc.create(Entry(type: .thought, title: "Thought",
                createdAt: dayStr + "T10:00:00Z"))
        }
        #expect(try engine.analyze().filter { $0.type == .streak }.isEmpty)
    }

    @Test("Streak ignoriert soft-geloeschte Entries")
    func streakIgnoresDeleted() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<5 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            let entry = try svc.create(Entry(type: .task, title: "Task",
                status: .done, createdAt: dayStr + "T10:00:00Z"))
            try svc.delete(id: entry.id!)
        }
        #expect(try engine.analyze().filter { $0.type == .streak }.isEmpty)
    }

    @Test("Keine Anomalie bei zu wenig historischen Daten")
    func noAnomalyWithInsufficientBaseline() throws {
        let (engine, svc, _) = try makeEngine()
        let today = DateFormatters.dateOnly.string(from: Date())
        try svc.create(Entry(type: .thought, title: "Single",
            createdAt: today + "T10:00:00Z"))
        #expect(try engine.analyze().filter { $0.type == .anomaly }.isEmpty)
    }

    @Test("Anomalie bei unterdurchschnittlicher Aktivitaet")
    func anomalyDetectedWhenActivityLow() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for dayOffset in 1...7 {
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            for i in 0..<10 {
                let minute = String(format: "%02d", i)
                try svc.create(Entry(type: .thought, title: "E",
                    createdAt: dayStr + "T10:" + minute + ":00Z"))
            }
        }
        let todayStr = DateFormatters.dateOnly.string(from: today)
        try svc.create(Entry(type: .thought, title: "Only one",
            createdAt: todayStr + "T09:00:00Z"))
        let anomalies = try engine.analyze().filter { $0.type == .anomaly }
        #expect(!anomalies.isEmpty)
        #expect(anomalies.first?.description.contains("wenig") == true)
    }

    @Test("Keine Anomalie bei normaler Aktivitaet")
    func noAnomalyAtNormalActivity() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for dayOffset in 0...7 {
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            for i in 0..<5 {
                let minute = String(format: "%02d", i)
                try svc.create(Entry(type: .thought, title: "E",
                    createdAt: dayStr + "T10:" + minute + ":00Z"))
            }
        }
        #expect(try engine.analyze().filter { $0.type == .anomaly }.isEmpty)
    }

    @Test("Muster werden nach Confidence absteigend sortiert")
    func patternsSortedByConfidence() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            try svc.create(Entry(type: .task, title: "T",
                status: .done, createdAt: dayStr + "T10:00:00Z"))
        }
        let patterns = try engine.analyze()
        for i in 0..<(patterns.count - 1) {
            #expect(patterns[i].confidence >= patterns[i + 1].confidence)
        }
    }

    @Test("DateFormatters.dateOnly formatiert korrekt")
    func dateOnlyFormatter() {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 18
        c.hour = 14; c.minute = 30
        c.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: c)!
        #expect(DateFormatters.dateOnly.string(from: date) == "2026-03-18")
    }

    @Test("DateFormatters.dateOnly Round-Trip")
    func dateOnlyRoundTrip() {
        let original = "2026-01-15"
        let parsed = DateFormatters.dateOnly.date(from: original)
        #expect(parsed != nil)
        #expect(DateFormatters.dateOnly.string(from: parsed!) == original)
    }

    @Test("DateFormatters.iso8601 enthaelt T-Trennzeichen")
    func iso8601ContainsTSeparator() {
        #expect(DateFormatters.iso8601.string(
            from: Date(timeIntervalSince1970: 1000000)).contains("T"))
    }

    @Test("DetectedPattern haelt alle Felder korrekt")
    func detectedPatternFields() {
        let p = DetectedPattern(type: .streak, description: "5 Tage",
            confidence: 0.8, relatedEntryIds: [1, 2])
        #expect(p.type == .streak)
        #expect(p.description == "5 Tage")
        #expect(p.confidence == 0.8)
        #expect(p.relatedEntryIds == [1, 2])
    }

    @Test("PatternType rawValues sind korrekt")
    func patternTypeRawValues() {
        #expect(PatternType.frequency.rawValue == "frequency")
        #expect(PatternType.neglect.rawValue == "neglect")
        #expect(PatternType.correlation.rawValue == "correlation")
        #expect(PatternType.streak.rawValue == "streak")
        #expect(PatternType.anomaly.rawValue == "anomaly")
    }

    @Test("Streak relatedEntryIds ist leer")
    func streakRelatedIdsEmpty() throws {
        let (engine, svc, _) = try makeEngine()
        let today = Date()
        for offset in 0..<3 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let dayStr = DateFormatters.dateOnly.string(from: day)
            try svc.create(Entry(type: .task, title: "T",
                status: .done, createdAt: dayStr + "T10:00:00Z"))
        }
        let streaks = try engine.analyze().filter { $0.type == .streak }
        #expect(streaks.first?.relatedEntryIds.isEmpty == true)
    }
}
