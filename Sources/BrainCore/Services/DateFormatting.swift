import Foundation

// Centralized date formatting utilities for brain-ios.
// Uses per-call factory pattern because ISO8601DateFormatter (NSFormatter subclass)
// is NOT thread-safe for concurrent calls — internal mutable state in Locale/Calendar.
public enum BrainDateFormatting {

    // Per-call factory — safe for concurrent access from any thread.
    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    // Current timestamp in ISO 8601 format.
    public static func iso8601Now() -> String {
        makeFormatter().string(from: Date())
    }

    // Format a date as ISO 8601 string.
    public static func iso8601String(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    // Parse an ISO 8601 string to Date.
    public static func date(from iso8601String: String) -> Date? {
        makeFormatter().date(from: iso8601String)
    }
}
