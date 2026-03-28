// Sanitizes and truncates data before it enters the LLM context.
// Prevents excessive token usage and limits PII exposure. (F-08)

public enum DataSanitizer: Sendable {

    /// Maximum characters for a single tool result sent to the LLM.
    public static let maxToolResultLength = 4000

    /// Truncate text to a maximum length, appending a note if truncated.
    public static func truncate(_ text: String, max: Int = maxToolResultLength) -> String {
        guard text.count > max else { return text }
        let truncated = String(text.prefix(max))
        return truncated + "\n... [abgeschnitten, \(text.count) Zeichen total]"
    }

    /// Sanitize a tool result string for safe inclusion in LLM context.
    /// Truncates to maxToolResultLength.
    public static func sanitizeToolResult(_ result: String) -> String {
        sanitizeForLLM(result)
    }

    /// M2: Sanitize markdown for LLM context.
    /// Strips image references (tracking pixels) and raw URLs.
    public static func sanitizeForLLM(_ text: String, max: Int = maxToolResultLength) -> String {
        var sanitized = text
        // Strip image references (tracking pixels, remote images)
        sanitized = sanitized.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^\)]+\)"#,
            with: "[Bild: $1]",
            options: .regularExpression
        )
        // Strip raw URLs in angle brackets
        sanitized = sanitized.replacingOccurrences(
            of: #"<https?://[^>]+>"#,
            with: "[URL entfernt]",
            options: .regularExpression
        )
        return truncate(sanitized, max: max)
    }
}
