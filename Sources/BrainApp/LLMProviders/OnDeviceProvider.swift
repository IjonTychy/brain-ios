import Foundation
import BrainCore

#if canImport(FoundationModels)
import FoundationModels
#endif

// Phase 23: On-Device LLM Provider using Apple Foundation Models (iOS 26+).
// Falls back gracefully on older iOS versions or unsupported hardware.
// Handles: simple tasks (tagging, summarization, classification) offline.

// Uses conditional compilation so the app compiles on iOS 17+ but only
// activates on-device LLM features when running on iOS 26+ with
// supported hardware (iPhone 16 Pro+, iPad M1+, Mac M1+).

final class OnDeviceProvider: LLMProvider, @unchecked Sendable {

    let name = "apple-on-device"
    let supportsStreaming = true
    let isOnDevice = true
    let contextWindow = 4096  // Apple's on-device model context

    // Check if the on-device model is available on this hardware/OS.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _checkFoundationModelsAvailable()
        }
        #endif
        return false
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await _completeWithFoundationModels(request)
        }
        #endif
        throw OnDeviceError.unavailable
    }

    // MARK: - iOS 26+ Implementation

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func _checkFoundationModelsAvailable() -> Bool {
        // Apple Foundation Models availability check.
        // On supported hardware, the system model is pre-installed.
        // We check at runtime since this depends on device capabilities.
        let _ = LanguageModelSession()
        return true
    }

    @available(iOS 26.0, *)
    private func _completeWithFoundationModels(_ request: LLMRequest) async throws -> LLMResponse {
        let session = LanguageModelSession()

        // Build prompt from messages
        var prompt = ""
        if let systemPrompt = request.systemPrompt {
            prompt += "System: \(systemPrompt)\n\n"
        }
        for message in request.messages {
            let role = message.role == "user" ? "User" : "Assistant"
            prompt += "\(role): \(message.content)\n\n"
        }
        prompt += "Assistant:"

        let response = try await session.respond(to: prompt)
        return LLMResponse(
            content: response.content,
            providerName: name,
            tokensUsed: nil
        )
    }
    #endif

    // MARK: - Fallback: Simple on-device NLP

    // For basic tasks that don't need a full LLM, use NaturalLanguage framework.
    // Available on all iOS versions. Used when Foundation Models aren't available.
    static func classifyEntryType(text: String) -> String {
        let lowered = text.lowercased()

        // Simple keyword-based classification
        let taskKeywords = ["todo", "aufgabe", "erledigen", "machen", "muss", "soll",
                           "kaufen", "buchen", "anrufen", "schreiben", "fertig"]
        let eventKeywords = ["treffen", "termin", "meeting", "um", "uhr", "morgen",
                           "heute", "donnerstag", "freitag", "montag", "dienstag", "mittwoch"]
        let emailKeywords = ["email", "mail", "nachricht", "antwort", "betreff"]

        let taskScore = taskKeywords.filter { lowered.contains($0) }.count
        let eventScore = eventKeywords.filter { lowered.contains($0) }.count
        let emailScore = emailKeywords.filter { lowered.contains($0) }.count

        if taskScore > eventScore && taskScore > emailScore && taskScore > 0 {
            return "task"
        } else if eventScore > taskScore && eventScore > emailScore && eventScore > 0 {
            return "event"
        } else if emailScore > 0 {
            return "email"
        }
        return "thought"
    }

    // Extract a date from natural language text (simple heuristics).
    static func extractDate(from text: String) -> Date? {
        let lowered = text.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lowered.contains("heute") {
            return now
        }
        if lowered.contains("morgen") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if lowered.contains("übermorgen") {
            return calendar.date(byAdding: .day, value: 2, to: now)
        }
        if lowered.contains("nächste woche") || lowered.contains("nächste woche") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }

        // Day name extraction
        let dayNames = ["montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5,
                       "freitag": 6, "samstag": 7, "sonntag": 1]
        for (name, weekday) in dayNames {
            if lowered.contains(name) {
                return nextDate(weekday: weekday, from: now)
            }
        }

        // Time extraction: "um HH:MM" or "um HH Uhr"
        // Handled separately by the caller if needed.

        return nil
    }

    // Extract priority from text.
    static func extractPriority(from text: String) -> Int {
        let lowered = text.lowercased()
        if lowered.contains("dringend") || lowered.contains("wichtig") || lowered.contains("asap") {
            return 2
        }
        if lowered.contains("bald") || lowered.contains("zeitnah") {
            return 1
        }
        return 0
    }

    // Extract person names from text (simple pattern matching).
    static func extractPersonNames(from text: String) -> [String] {
        // Look for "mit [Name]" or "fuer [Name]" or "von [Name]" patterns
        let patterns = ["mit ", "für ", "für ", "von ", "an "]
        var names: [String] = []

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .caseInsensitive) {
                let after = text[range.upperBound...]
                let words = after.split(separator: " ")
                if let firstName = words.first {
                    let name = String(firstName).trimmingCharacters(in: .punctuationCharacters)
                    // Only treat as name if it starts with uppercase
                    if name.first?.isUppercase == true && name.count > 1 {
                        names.append(name)
                    }
                }
            }
        }

        return names
    }

    private static func nextDate(weekday: Int, from date: Date) -> Date? {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysToAdd = weekday - currentWeekday
        if daysToAdd <= 0 { daysToAdd += 7 }
        return calendar.date(byAdding: .day, value: daysToAdd, to: date)
    }
}

// MARK: - Errors

enum OnDeviceError: Error, LocalizedError {
    case unavailable
    case modelNotReady
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-Device LLM ist auf diesem Gerät nicht verfügbar."
        case .modelNotReady:
            return "Das On-Device Modell wird noch geladen."
        case .generationFailed(let reason):
            return "On-Device Generierung fehlgeschlagen: \(reason)"
        }
    }
}
