import Foundation
import GRDB

// Central database access point. Manages the GRDB connection pool
// and runs migrations on first access.
public final class DatabaseManager: Sendable {

    // The underlying GRDB database pool.
    public let pool: DatabasePool

    // The filesystem path of the database.
    public let path: String?

    // Initialise with an on-disk database at the given path.
    // Runs all pending migrations automatically.
    public init(path: String) throws {
        self.path = path
        pool = try DatabasePool(path: path)
        try Self.migrate(pool)
    }

    // Initialise with a temporary database (useful for testing).
    // Creates a uniquely-named file in the system temp directory.
    public static func temporary() throws -> DatabaseManager {
        let dir = NSTemporaryDirectory()
        let path = dir + "/brain-test-\(UUID().uuidString).sqlite"
        let pool = try DatabasePool(path: path)
        try migrate(pool)
        return DatabaseManager(pool: pool, path: path)
    }

    // Approximate database file size as human-readable string.
    public func approximateSize() -> String {
        guard let path else { return "unbekannt" }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let bytes = attrs[.size] as? Int64 ?? 0
            if bytes < 1024 {
                return "\(bytes) B"
            } else if bytes < 1024 * 1024 {
                return "\(bytes / 1024) KB"
            } else {
                let mb = Double(bytes) / (1024.0 * 1024.0)
                return String(format: "%.1f MB", mb)
            }
        } catch {
            return "unbekannt"
        }
    }

    // MARK: - Private

    // Private initialiser that skips migrations.
    private init(pool: DatabasePool, path: String? = nil) {
        self.pool = pool
        self.path = path
    }

    private static func migrate(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(pool)
    }
}
