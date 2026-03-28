@preconcurrency import Contacts
import BrainCore

// Bridge between Action Primitives and iOS Contacts framework.
// Provides contact.search, contact.read, contact.create, contact.update.
// NOT @MainActor: CNContactStore.enumerateContacts is synchronous and blocking.
// Running it on MainActor can cause deadlocks. CNContactStore is thread-safe.
// @unchecked Sendable: CNContactStore is documented as thread-safe.
final class ContactsBridge: @unchecked Sendable {
    private let store = CNContactStore()

    // Request access to contacts. Returns true if granted.
    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    // Check current authorization status without prompting.
    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // Search contacts by name.
    // Standard keys shared by search and listAll.
    nonisolated(unsafe) private static let standardKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
    ]

    // Search contacts by name.
    func search(query: String, limit: Int = 20) throws -> [ContactInfo] {
        let keysToFetch = Self.standardKeys

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = CNContact.predicateForContacts(matchingName: query)

        var results: [ContactInfo] = []
        try store.enumerateContacts(with: request) { contact, stop in
            results.append(ContactInfo(from: contact))
            if results.count >= limit {
                stop.pointee = true
            }
        }
        return results
    }

    // Read a single contact by identifier (fetches all available keys).
    // NOTE: CNContactNoteKey omitted — requires com.apple.developer.contacts.notes
    // entitlement (Apple-restricted). Without it, unifiedContacts() throws.
    func read(identifier: String) throws -> ContactInfo? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]

        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]), keysToFetch: keysToFetch)
        return contacts.first.map { ContactInfo(from: $0) }
    }

    // List all contacts (for import/sync purposes).
    // List all contacts (for import/sync purposes).
    func listAll(limit: Int = 500) throws -> [ContactInfo] {
        let keysToFetch = Self.standardKeys

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .familyName

        var results: [ContactInfo] = []
        try store.enumerateContacts(with: request) { contact, stop in
            results.append(ContactInfo(from: contact))
            if results.count >= limit {
                stop.pointee = true
            }
        }
        return results
    }

    // Create a new contact.
    func create(givenName: String, familyName: String, email: String? = nil, phone: String? = nil) throws -> String {
        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName

        if let email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        if let phone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        try store.execute(saveRequest)
        return contact.identifier
    }

    // Update an existing contact's properties.
    // All changes are written directly to iOS Contacts (CNContactStore) —
    // they appear immediately in the native Contacts app. No separate sync needed.
    func update(identifier: String, givenName: String? = nil, familyName: String? = nil,
                organization: String? = nil, jobTitle: String? = nil,
                email: String? = nil, phone: String? = nil,
                addEmail: String? = nil, addPhone: String? = nil,
                note: String? = nil) throws -> ContactInfo {
        // CNContactNoteKey requires com.apple.developer.contacts.notes entitlement
        // (Apple-restricted). Using standardKeys avoids the crash.
        let keysToFetch: [CNKeyDescriptor] = Self.standardKeys
        guard let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch).mutableCopy() as? CNMutableContact else {
            throw ContactBridgeError.notFound
        }
        if let givenName { existing.givenName = givenName }
        if let familyName { existing.familyName = familyName }
        if let organization { existing.organizationName = organization }
        if let jobTitle { existing.jobTitle = jobTitle }
        // CNContactNoteKey requires com.apple.developer.contacts.notes entitlement.
        // Silently ignore note updates to prevent crash.
        // if let note { existing.note = note }

        // Replace all emails (set mode)
        if let email {
            existing.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        // Add email (append mode)
        if let addEmail {
            let newEntry = CNLabeledValue(label: CNLabelOther, value: addEmail as NSString)
            existing.emailAddresses = existing.emailAddresses + [newEntry]
        }
        // Replace all phones (set mode)
        if let phone {
            existing.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        // Add phone (append mode)
        if let addPhone {
            let newEntry = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: addPhone))
            existing.phoneNumbers = existing.phoneNumbers + [newEntry]
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(existing)
        try store.execute(saveRequest)
        return ContactInfo(from: existing)
    }

    // Delete a contact from iOS Contacts.
    func delete(identifier: String) throws {
        let keysToFetch: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor]
        guard let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch).mutableCopy() as? CNMutableContact else {
            throw ContactBridgeError.notFound
        }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(contact)
        try store.execute(saveRequest)
    }

    // Merge two contacts: keep target, move data from source, delete source.
    func merge(sourceId: String, targetId: String) throws -> ContactInfo {
        // CNContactNoteKey requires com.apple.developer.contacts.notes entitlement.
        let allKeys: [CNKeyDescriptor] = Self.standardKeys
        guard let source = try store.unifiedContact(withIdentifier: sourceId, keysToFetch: allKeys).mutableCopy() as? CNMutableContact else {
            throw ContactBridgeError.notFound
        }
        guard let target = try store.unifiedContact(withIdentifier: targetId, keysToFetch: allKeys).mutableCopy() as? CNMutableContact else {
            throw ContactBridgeError.notFound
        }

        // Merge emails (add source's that target doesn't have)
        let existingEmails = Set(target.emailAddresses.map { $0.value as String })
        for emailEntry in source.emailAddresses {
            if !existingEmails.contains(emailEntry.value as String) {
                target.emailAddresses = target.emailAddresses + [emailEntry]
            }
        }

        // Merge phones
        let existingPhones = Set(target.phoneNumbers.map { $0.value.stringValue })
        for phoneEntry in source.phoneNumbers {
            if !existingPhones.contains(phoneEntry.value.stringValue) {
                target.phoneNumbers = target.phoneNumbers + [phoneEntry]
            }
        }

        // Merge organization (if target empty)
        if target.organizationName.isEmpty && !source.organizationName.isEmpty {
            target.organizationName = source.organizationName
        }
        if target.jobTitle.isEmpty && !source.jobTitle.isEmpty {
            target.jobTitle = source.jobTitle
        }

        // Merge note (append)
        if !source.note.isEmpty {
            target.note = target.note.isEmpty ? source.note : "\(target.note)\n\(source.note)"
        }

        // Merge addresses
        let existingAddrs = Set(target.postalAddresses.map { ($0.value as CNPostalAddress).street })
        for addr in source.postalAddresses {
            if !existingAddrs.contains((addr.value as CNPostalAddress).street) {
                target.postalAddresses = target.postalAddresses + [addr]
            }
        }

        // Save target, delete source
        let saveRequest = CNSaveRequest()
        saveRequest.update(target)
        saveRequest.delete(source)
        try store.execute(saveRequest)
        return ContactInfo(from: target)
    }

    // Find potential duplicate contacts (same name or similar).
    func findDuplicates(limit: Int = 50) throws -> [(contact1: ContactInfo, contact2: ContactInfo, reason: String)] {
        let all = try listAll(limit: 2000)
        var duplicates: [(contact1: ContactInfo, contact2: ContactInfo, reason: String)] = []

        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let a = all[i]
                let b = all[j]

                // Exact name match
                if !a.fullName.isEmpty && a.fullName.lowercased() == b.fullName.lowercased() {
                    duplicates.append((a, b, "Gleicher Name"))
                    if duplicates.count >= limit { return duplicates }
                    continue
                }

                // Same email
                let sharedEmails = Set(a.emails.map { $0.lowercased() }).intersection(Set(b.emails.map { $0.lowercased() }))
                if !sharedEmails.isEmpty {
                    duplicates.append((a, b, "Gleiche E-Mail: \(sharedEmails.first ?? "")"))
                    if duplicates.count >= limit { return duplicates }
                    continue
                }

                // Same phone
                let aPhones = Set(a.phones.map { $0.filter(\.isNumber) })
                let bPhones = Set(b.phones.map { $0.filter(\.isNumber) })
                let sharedPhones = aPhones.intersection(bPhones)
                if !sharedPhones.isEmpty {
                    duplicates.append((a, b, "Gleiche Telefonnummer"))
                    if duplicates.count >= limit { return duplicates }
                }
            }
        }
        return duplicates
    }
}

enum ContactBridgeError: Error, LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return "Kontakt nicht gefunden"
        }
    }
}

// Lightweight contact representation for the skill engine.
struct ContactInfo: Sendable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let givenName: String
    let familyName: String
    let fullName: String
    let initials: String
    let emails: [String]
    let phones: [String]
    let organization: String
    let jobTitle: String
    let postalAddresses: [String]
    let birthday: DateComponents?
    let note: String
    let hasImage: Bool

    // Section key for alphabet grouping (first letter of family name, or "#")
    var sectionKey: String {
        let key = familyName.isEmpty ? givenName : familyName
        guard let first = key.uppercased().first, first.isLetter else { return "#" }
        return String(first)
    }

    init(from contact: CNContact) {
        self.identifier = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        // Use CNContactFormatter for locale-correct name order
        self.fullName = CNContactFormatter.string(from: contact, style: .fullName)
            ?? "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let g = contact.givenName.prefix(1)
        let f = contact.familyName.prefix(1)
        self.initials = g.isEmpty && f.isEmpty ? "?" : "\(g)\(f)"
        self.emails = contact.emailAddresses.map { $0.value as String }
        self.phones = contact.phoneNumbers.map { $0.value.stringValue }
        self.organization = contact.organizationName
        self.jobTitle = contact.isKeyAvailable(CNContactJobTitleKey) ? contact.jobTitle : ""
        self.birthday = contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil
        self.note = ""
        self.hasImage = contact.isKeyAvailable(CNContactImageDataAvailableKey) ? contact.imageDataAvailable : false
        if contact.isKeyAvailable(CNContactPostalAddressesKey) {
            self.postalAddresses = contact.postalAddresses.map { labeled in
                let addr = labeled.value
                return [addr.street, addr.postalCode, addr.city, addr.country]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
        } else {
            self.postalAddresses = []
        }
    }

    // Convert to ExpressionValue for use in skills.
    var expressionValue: ExpressionValue {
        .object([
            "id": .string(identifier),
            "name": .string(fullName),
            "givenName": .string(givenName),
            "familyName": .string(familyName),
            "initials": .string(initials),
            "email": .string(emails.first ?? ""),
            "phone": .string(phones.first ?? ""),
            "organization": .string(organization),
            "address": .string(postalAddresses.first ?? ""),
        ])
    }
}

// MARK: - ContactsBridge Birthday Extension

extension ContactsBridge {
    // Upcoming birthdays within the next N days.
    func upcomingBirthdays(withinDays days: Int = 14, limit: Int = 10) -> [(name: String, date: DateComponents, daysUntil: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var results: [(name: String, date: DateComponents, daysUntil: Int)] = []

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .familyName

        try? store.enumerateContacts(with: request) { contact, _ in
            guard let bday = contact.birthday, let bdayMonth = bday.month, let bdayDay = bday.day else { return }
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            var nextBday = DateComponents(month: bdayMonth, day: bdayDay)
            nextBday.year = cal.component(.year, from: today)
            guard var nextDate = cal.date(from: nextBday) else { return }
            if nextDate < today {
                nextBday.year = cal.component(.year, from: today) + 1
                guard let d = cal.date(from: nextBday) else { return }
                nextDate = d
            }
            let diff = cal.dateComponents([.day], from: today, to: nextDate).day ?? 999
            if diff <= days {
                results.append((name: name, date: bday, daysUntil: diff))
            }
        }

        return results.sorted { $0.daysUntil < $1.daysUntil }.prefix(limit).map { $0 }
    }
}

// MARK: - Action Handlers
// Not @MainActor — CNContactStore is thread-safe, blocking calls must not run on MainActor.

final class ContactSearchHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.search"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let query = properties["query"]?.stringValue ?? ""
        let limit = properties["limit"]?.intValue ?? 20
        let contacts = try bridge.search(query: query, limit: limit)
        return .value(.array(contacts.map(\.expressionValue)))
    }
}

final class ContactReadHandler: ActionHandler, @unchecked Sendable {
    let type = "contact.read"
    private let bridge = ContactsBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.stringValue else {
            return .error("contact.read requires 'id' property")
        }
        let result = try bridge.read(identifier: id)
        guard let contact = result else {
            return .error("Contact not found: \(id)")
        }
        return .value(contact.expressionValue)
    }
}
