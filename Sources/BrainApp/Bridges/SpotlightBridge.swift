import CoreSpotlight
import BrainCore

// Bridge between entries and iOS Spotlight search.
// Indexes brain entries so they appear in system-wide search.
final class SpotlightBridge: Sendable {

    // Index an entry in Spotlight.
    func index(entry: Entry) {
        guard let id = entry.id else { return }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = entry.title
        if let body = entry.body {
            attributeSet.contentDescription = String(body.prefix(500))
        }
        attributeSet.contentCreationDate = DateFormatters.iso8601.date(from: entry.createdAt ?? "")

        let item = CSSearchableItem(
            uniqueIdentifier: "entry-\(id)",
            domainIdentifier: "com.example.brain-ios.entries",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item])
    }

    // Remove an entry from Spotlight.
    func deindex(entryId: Int64) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["entry-\(entryId)"])
    }

    // Remove all brain entries from Spotlight.
    func deindexAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["com.example.brain-ios.entries"])
    }

    // Batch index multiple entries.
    func indexBatch(entries: [Entry]) {
        let items = entries.compactMap { entry -> CSSearchableItem? in
            guard let id = entry.id else { return nil }

            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = entry.title
            if let body = entry.body {
                attributeSet.contentDescription = String(body.prefix(500))
            }

            return CSSearchableItem(
                uniqueIdentifier: "entry-\(id)",
                domainIdentifier: "com.example.brain-ios.entries",
                attributeSet: attributeSet
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items)
    }
}
