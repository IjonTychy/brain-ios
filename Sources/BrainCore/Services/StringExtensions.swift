// String extensions for safe SQL query construction.

extension String {
    /// Escape SQL LIKE wildcard characters (%, _, \) for safe use in LIKE patterns. (F-16)
    /// Use with GRDB's `.like(pattern, escape: "\\")`.
    public func escapedForLIKE() -> String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
