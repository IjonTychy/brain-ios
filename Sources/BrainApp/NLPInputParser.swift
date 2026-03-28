import Foundation
import BrainCore

// Phase 22/23: Natural Language Input Parser.
// Parses free-form German text like "Treffen mit Sarah morgen 15 Uhr"
// into structured entry data (type, title, date, priority, people).
// Works fully offline — no LLM needed.

struct ParsedInput: Sendable {
    var type: EntryType
    var title: String
    var date: Date?
    var time: String?   // "HH:mm" format
    var priority: Int
    var people: [String]
    var tags: [String]

    // Human-readable summary of what was parsed.
    var parseSummary: String {
        var parts: [String] = []
        parts.append("Typ: \(typeLabel)")
        if let date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_CH")
            f.dateStyle = .medium
            parts.append("Datum: \(f.string(from: date))")
        }
        if let time { parts.append("Zeit: \(time)") }
        if priority > 0 { parts.append("Priorität: \(priority == 2 ? "Hoch" : "Mittel")") }
        if !people.isEmpty { parts.append("Personen: \(people.joined(separator: ", "))") }
        if !tags.isEmpty { parts.append("Tags: \(tags.joined(separator: ", "))") }
        return parts.joined(separator: " | ")
    }

    private var typeLabel: String {
        type.label
    }
}

enum NLPInputParser {

    // Parse natural language text into a structured entry.
    static func parse(_ text: String) -> ParsedInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let type = EntryType(rawValue: OnDeviceProvider.classifyEntryType(text: trimmed)) ?? .thought
        let date = OnDeviceProvider.extractDate(from: trimmed)
        let time = extractTime(from: trimmed)
        let priority = OnDeviceProvider.extractPriority(from: trimmed)
        let people = OnDeviceProvider.extractPersonNames(from: trimmed)
        let tags = extractHashtags(from: trimmed)

        // Clean the title: remove date/time/tag noise
        var title = trimmed
        title = removeHashtags(from: title)
        title = cleanupTitle(title)

        return ParsedInput(
            type: type,
            title: title,
            date: date,
            time: time,
            priority: priority,
            people: people,
            tags: tags
        )
    }

    // MARK: - Time extraction

    // Extract time from patterns like "um 15:30", "15 Uhr", "um 9"
    private static func extractTime(from text: String) -> String? {
        let lowered = text.lowercased()

        // Pattern: "um HH:MM"
        if let range = lowered.range(of: #"um (\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let match = String(lowered[range])
            let digits = match.replacingOccurrences(of: "um ", with: "")
            return digits
        }

        // Pattern: "um HH Uhr"
        if let range = lowered.range(of: #"um (\d{1,2}) uhr"#, options: .regularExpression) {
            let match = String(lowered[range])
            let hour = match.replacingOccurrences(of: "um ", with: "")
                .replacingOccurrences(of: " uhr", with: "")
            if let h = Int(hour), h >= 0 && h <= 23 {
                return String(format: "%02d:00", h)
            }
        }

        // Pattern: "HH:MM Uhr"
        if let range = lowered.range(of: #"(\d{1,2}):(\d{2}) uhr"#, options: .regularExpression) {
            let match = String(lowered[range]).replacingOccurrences(of: " uhr", with: "")
            return match
        }

        return nil
    }

    // MARK: - Hashtag extraction

    // Extract #tags from text
    private static func extractHashtags(from text: String) -> [String] {
        let pattern = #"#(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match -> String? in
            guard let tagRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[tagRange])
        }
    }

    private static func removeHashtags(from text: String) -> String {
        text.replacingOccurrences(of: #"#\w+"#, with: "", options: .regularExpression)
    }

    // MARK: - Title cleanup

    private static func cleanupTitle(_ text: String) -> String {
        var result = text
        // Remove common noise words that got parsed into structured data
        let noisePatterns = [
            #"um \d{1,2}:\d{2}"#,
            #"um \d{1,2} [Uu]hr"#,
            #"\d{1,2}:\d{2} [Uu]hr"#,
        ]
        for pattern in noisePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Collapse whitespace
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
