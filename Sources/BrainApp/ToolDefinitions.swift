import Foundation
import BrainCore

// Defines all Brain tools for the Anthropic Tool-Use API.
// Each tool maps to an ActionHandler and has a JSON Schema for parameters.
// Claude sees these tools and decides when to call them.

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    /// JSON Schema stored as a serialized JSON string (Sendable-safe).
    let inputSchemaJSON: String

    /// Convenience initializer that accepts a dictionary literal and serializes it.
    init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        if let data = try? JSONSerialization.data(withJSONObject: inputSchema, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            self.inputSchemaJSON = json
        } else {
            self.inputSchemaJSON = "{}"
        }
    }

    // Convert to Anthropic API JSON format.
    func toJSON() -> [String: Any] {
        let schema: Any = {
            if let data = inputSchemaJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return [String: Any]()
        }()
        return [
            "name": name,
            "description": description,
            "input_schema": schema
        ]
    }
}

// All tools that Brain exposes to the LLM via tool-use.
// We intentionally exclude UI-only actions (haptic, toast, navigate.to, set, clipboard.copy, open-url, share)
// and hardware-dependent actions (scan.text, nfc.read, speech.recognize, speech.transcribeFile, pencil.recognizeText)
// because those cannot be meaningfully triggered by the LLM in a chat context.
//
// Tool definitions are split into thematic extension files:
//   - ToolDefinitions+Entry.swift         (entryTools)
//   - ToolDefinitions+Communication.swift  (communicationTools)
//   - ToolDefinitions+System.swift         (systemTools)
//   - ToolDefinitions+AI.swift             (aiTools)
enum BrainTools {

    // The subset of tools the LLM should have access to in chat.
    static let all: [ToolDefinition] = entryTools + communicationTools + systemTools + aiTools

    // Maps tool names (underscored) to ActionHandler type strings (dotted).
    // e.g. "entry_create" -> "entry.create"
    static let toolNameToHandlerType: [String: String] = {
        var map: [String: String] = [:]
        // Entry
        map["entry_create"] = "entry.create"
        map["entry_search"] = "entry.search"
        map["entry_update"] = "entry.update"
        map["entry_delete"] = "entry.delete"
        map["entry_fetch"] = "entry.fetch"
        map["entry_list"] = "entry.list"
        map["entry_markDone"] = "entry.markDone"
        map["entry_archive"] = "entry.archive"
        map["entry_restore"] = "entry.restore"
        map["entry_crossref"] = "entry.crossref"
        // Tags
        map["tag_add"] = "tag.add"
        map["tag_remove"] = "tag.remove"
        map["tag_list"] = "tag.list"
        map["tag_counts"] = "tag.counts"
        // Links
        map["link_create"] = "link.create"
        map["link_delete"] = "link.delete"
        map["link_list"] = "link.list"
        // Search
        map["search_autocomplete"] = "search.autocomplete"
        // Knowledge
        map["knowledge_save"] = "knowledge.save"
        // Calendar
        map["calendar_list"] = "calendar.list"
        map["calendar_create"] = "calendar.create"
        map["calendar_delete"] = "calendar.delete"
        // Reminders
        map["reminder_set"] = "reminder.set"
        map["reminder_cancel"] = "reminder.cancel"
        map["reminder_list"] = "reminder.list"
        map["reminder_pendingCount"] = "reminder.pendingCount"
        // Contacts
        map["contact_search"] = "contact.search"
        map["contact_read"] = "contact.read"
        map["contact_create"] = "contact.create"
        map["contact_delete"] = "contact.delete"
        map["contact_merge"] = "contact.merge"
        map["contact_duplicates"] = "contact.duplicates"
        // Email
        map["email_list"] = "email.list"
        map["email_fetch"] = "email.fetch"
        map["email_search"] = "email.search"
        map["email_send"] = "email.send"
        map["email_sync"] = "email.sync"
        map["email_markRead"] = "email.markRead"
        map["email_move"] = "email.move"
        map["email_spamCheck"] = "email.spamCheck"
        map["email_rescueSpam"] = "email.rescueSpam"
        // email_configure removed (F-02) — credentials only via Settings UI
        // AI
        map["ai_summarize"] = "ai.summarize"
        map["ai_extractTasks"] = "ai.extractTasks"
        map["ai_briefing"] = "ai.briefing"
        map["ai_draftReply"] = "ai.draftReply"
        // Skills
        map["skill_create"] = "skill.create"
        map["skill_list"] = "skill.list"
        // Rules
        map["rules_evaluate"] = "rules.evaluate"
        map["improve_list"] = "improve.list"
        map["improve_apply"] = "improve.apply"
        // Location
        map["location_current"] = "location.current"
        // Semantic Search
        map["search_semantic"] = "search.semantic"
        map["entry_similar"] = "entry.similar"
        // Scanner + structured extraction
        map["scan_text"] = "scan.text"
        map["scan_extractContact"] = "scan.extractContact"
        map["scan_extractReceipt"] = "scan.extractReceipt"
        // File operations
        map["file_read"] = "file.read"
        map["file_write"] = "file.write"
        map["file_delete"] = "file.delete"
        // HTTP
        map["http_request"] = "http.request"
        // Storage
        map["storage_get"] = "storage.get"
        map["storage_set"] = "storage.set"
        // Email erweitert
        map["email_read"] = "email.read"
        map["email_delete"] = "email.delete"
        map["email_reply"] = "email.reply"
        map["email_forward"] = "email.forward"
        map["email_flag"] = "email.flag"
        // Entry erweitert
        map["entry_read"] = "entry.read"
        map["entry_toggle"] = "entry.toggle"
        // LLM
        map["llm_complete"] = "llm.complete"
        map["llm_classify"] = "llm.classify"
        map["llm_extract"] = "llm.extract"
        // Bluetooth
        map["bluetooth_scan"] = "bluetooth.scan"
        // HomeKit
        map["home_scene"] = "home.scene"
        map["home_device"] = "home.device"
        // Location geofence
        map["location_geofence"] = "location.geofence"
        // Calendar/Contact update
        map["calendar_update"] = "calendar.update"
        map["contact_update"] = "contact.update"
        // Camera
        map["camera_capture"] = "camera.capture"
        // Audio
        map["audio_record"] = "audio.record"
        map["audio_play"] = "audio.play"
        // Health
        map["health_read"] = "health.read"
        map["health_write"] = "health.write"
        // Conversation Memory
        map["memory_search_person"] = "memory.searchPerson"
        map["memory_search_topic"] = "memory.searchTopic"
        map["memory_facts"] = "memory.facts"
        map["user_profile"] = "user.profile"
        // On This Day
        map["onthisday_list"] = "onthisday.list"
        // Backup
        map["backup_export"] = "backup.export"
        // Proposal reject
        map["proposal_reject"] = "proposal.reject"
        // Image analysis
        map["image_detectText"] = "image.detectText"
        map["image_traceContours"] = "image.traceContours"
        map["svg_generate"] = "svg.generate"
        // Signal analysis
        map["signal_analyzeAudio"] = "signal.analyzeAudio"
        map["signal_analyzeBrightness"] = "signal.analyzeBrightness"
        // Morse code
        map["morse_decode"] = "morse.decode"
        map["morse_encode"] = "morse.encode"
        map["morse_decodeAudio"] = "morse.decodeAudio"
        map["morse_decodeVisual"] = "morse.decodeVisual"
        // Audio analysis (Phyphox-style)
        map["audio_amplitude"] = "audio.amplitude"
        map["audio_spectrum"] = "audio.spectrum"
        map["audio_pitch"] = "audio.pitch"
        map["audio_oscilloscope"] = "audio.oscilloscope"
        map["audio_tone"] = "audio.tone"
        map["audio_sonar"] = "audio.sonar"
        map["audio_frequencyTrack"] = "audio.frequencyTrack"
        // Sensor spectrum
        map["sensor_accSpectrum"] = "sensor.accSpectrum"
        map["sensor_gyroSpectrum"] = "sensor.gyroSpectrum"
        map["sensor_magSpectrum"] = "sensor.magSpectrum"
        // Camera analysis
        map["camera_color"] = "camera.color"
        map["camera_luminance"] = "camera.luminance"
        map["camera_depth"] = "camera.depth"
        // Stopwatch experiments
        map["stopwatch_acoustic"] = "stopwatch.acoustic"
        map["stopwatch_motion"] = "stopwatch.motion"
        map["stopwatch_optical"] = "stopwatch.optical"
        map["stopwatch_proximity"] = "stopwatch.proximity"
        return map
    }()

    // Convert tool input JSON (from Anthropic API) to PropertyValue dictionary (for ActionHandler).
    static func convertInput(_ input: [String: Any]) -> [String: PropertyValue] {
        var properties: [String: PropertyValue] = [:]
        for (key, value) in input {
            switch value {
            case let str as String:
                properties[key] = .string(str)
            case let num as Int:
                properties[key] = .int(num)
            case let num as Double:
                properties[key] = .double(num)
            case let bool as Bool:
                properties[key] = .bool(bool)
            default:
                properties[key] = .string(String(describing: value))
            }
        }
        return properties
    }

    // Convert ActionResult to a JSON-serializable string for tool_result.
    // Applies DataSanitizer truncation to prevent excessive context usage (F-08).
    static func resultToString(_ result: ActionResult) -> String {
        let raw: String
        switch result {
        case .success:
            raw = "{\"status\": \"success\"}"
        case .value(let val):
            raw = expressionValueToJSON(val)
        case .error(let msg):
            raw = "{\"error\": \"\(msg.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        }
        return DataSanitizer.sanitizeToolResult(raw)
    }

    // Human-readable description for destructive tool calls (shown in confirmation dialog).
    static func describeToolCall(_ name: String, input: [String: Any]) -> String {
        switch name {
        case "email_send":
            let to = input["to"] as? String ?? "?"
            let subject = input["subject"] as? String ?? "(kein Betreff)"
            return "E-Mail senden an \(to): \"\(subject)\""
        case "entry_delete":
            let id = input["id"] ?? "?"
            return "Entry #\(id) löschen"
        case "calendar_delete":
            let id = input["id"] ?? "?"
            return "Kalender-Event \(id) löschen"
        case "contact_create":
            let name = input["givenName"] as? String ?? "?"
            let family = input["familyName"] as? String ?? ""
            return "Neuen Kontakt anlegen: \(name) \(family)".trimmingCharacters(in: .whitespaces)
        case "reminder_set":
            let title = input["title"] as? String ?? "?"
            return "Erinnerung setzen: \"\(title)\""
        default:
            return "Aktion ausführen: \(name)"
        }
    }

    private static func expressionValueToJSON(_ val: ExpressionValue) -> String {
        let jsonObj = expressionValueToAny(val)
        if let data = try? JSONSerialization.data(withJSONObject: [jsonObj]),
           let str = String(data: data, encoding: .utf8) {
            // Strip the wrapping array brackets [...]
            let inner = str.dropFirst().dropLast()
            return String(inner)
        }
        return "null"
    }

    private static func expressionValueToAny(_ val: ExpressionValue) -> Any {
        switch val {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let arr): return arr.map { expressionValueToAny($0) }
        case .object(let dict): return dict.mapValues { expressionValueToAny($0) }
        case .null: return NSNull()
        }
    }
}
