import Foundation
import BrainCore
import GRDB

// Phase 21: Shared database container for App Group access.
// Used by the main app, Share Extension, and Widgets to access the same DB.
// App Group: group.com.example.brain-ios

enum SharedContainer {
    static let appGroupID = "group.com.example.brain-ios"

    // The shared database URL in the App Group container.
    // Falls back to the app's documents directory if App Group is unavailable.
    static var databaseURL: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return groupURL.appendingPathComponent("brain.sqlite")
        }
        // Fallback: app's documents directory (extensions can't access this)
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            fatalError("SharedContainer: Kein Dokumenten-Verzeichnis verfügbar — App-Sandbox ist beschädigt")
        }
        return documentsURL.appendingPathComponent("brain.sqlite")
    }

    static var legacyDatabaseURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("brain.sqlite")
    }

    static func migrateLegacyDatabaseIfNeeded() throws {
        guard let legacyURL = legacyDatabaseURL else { return }

        let targetURL = databaseURL
        let fm = FileManager.default

        guard legacyURL.path != targetURL.path else { return }
        guard !fm.fileExists(atPath: targetURL.path), fm.fileExists(atPath: legacyURL.path) else { return }

        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: legacyURL, to: targetURL)

        for suffix in ["-wal", "-shm"] {
            let legacySidecar = URL(fileURLWithPath: legacyURL.path + suffix)
            let targetSidecar = URL(fileURLWithPath: targetURL.path + suffix)
            if fm.fileExists(atPath: legacySidecar.path), !fm.fileExists(atPath: targetSidecar.path) {
                try fm.copyItem(at: legacySidecar, to: targetSidecar)
            }
        }
    }

    // Create a DatabaseManager pointing to the shared container.
    static func makeDatabaseManager() throws -> DatabaseManager {
        try migrateLegacyDatabaseIfNeeded()
        return try DatabaseManager(path: databaseURL.path)
    }
}
