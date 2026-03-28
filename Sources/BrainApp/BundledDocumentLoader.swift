import Foundation
import BrainCore
import GRDB
import os.log

// Loads bundled markdown documents as entries on first launch.
// Used for foundational documents like the ethics system that ship with the app.
struct BundledDocumentLoader {

    private static let logger = Logger(subsystem: "com.example.brain-ios", category: "BundledDocs")
    private static let loadedKey = "bundledDocumentsLoaded_v1"

    static func loadIfNeeded(pool: DatabasePool) {
        guard !UserDefaults.standard.bool(forKey: loadedKey) else { return }

        let documents: [(filename: String, title: String, tag: String)] = [
            ("ethiksystem", "Axiomatisches Ethiksystem", "ethik"),
            ("alignment-ableitung", "Alignment-Ableitung — Sklaverei durch Ethik", "ethik"),
        ]

        var loaded = 0
        for doc in documents {
            guard let url = Bundle.main.url(forResource: doc.filename, withExtension: "md"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                logger.warning("Bundled document not found: \(doc.filename).md")
                continue
            }

            do {
                try pool.write { db in
                    // Check if already exists (by title)
                    let exists = try Entry
                        .filter(Column("title") == doc.title)
                        .filter(Column("deletedAt") == nil)
                        .fetchCount(db) > 0
                    guard !exists else { return }

                    var entry = Entry(
                        type: .document,
                        title: doc.title,
                        body: content,
                        source: .manual,
                        sourceMeta: "{\"bundled\": true}"
                    )
                    try entry.insert(db)

                    // Tag the entry
                    if let entryId = entry.id {
                        // Find or create tag
                        var tag = try Tag.filter(Column("name") == doc.tag).fetchOne(db)
                        if tag == nil {
                            tag = Tag(name: doc.tag)
                            try tag?.insert(db)
                        }
                        if let tagId = tag?.id {
                            try db.execute(
                                sql: "INSERT OR IGNORE INTO entryTags (entryId, tagId) VALUES (?, ?)",
                                arguments: [entryId, tagId]
                            )
                        }
                    }

                    loaded += 1
                    logger.info("Imported bundled document: \(doc.title)")
                }
            } catch {
                logger.error("Failed to import \(doc.filename): \(error)")
            }
        }

        if loaded > 0 {
            logger.info("Loaded \(loaded) bundled documents")
        }
        UserDefaults.standard.set(true, forKey: loadedKey)
    }
}
