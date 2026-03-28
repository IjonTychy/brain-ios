import SwiftUI
import BrainCore
import ContactsUI

// Extracted from ContentView.swift so MoreTabView can reference it.
enum ContactSortOrder: String, CaseIterable {
    case name = "Name"
    case organization = "Organisation"

    var label: String { rawValue }
    var icon: String {
        switch self {
        case .name: return "person"
        case .organization: return "building.2"
        }
    }
}

struct PeopleTabView: View {
    @State private var contacts: [ContactInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var permissionDenied = false
    @State private var sortOrder: ContactSortOrder = .name
    @State private var isLoadingContacts = false  // Guard against concurrent loads

    private var filtered: [ContactInfo] {
        if searchText.isEmpty { return contacts }
        let q = searchText.lowercased()
        return contacts.filter {
            $0.fullName.lowercased().contains(q) ||
            $0.organization.lowercased().contains(q) ||
            $0.emails.contains(where: { $0.lowercased().contains(q) }) ||
            $0.phones.contains(where: { $0.contains(q) })
        }
    }

    // Group contacts by first letter of family name
    private var sortedContacts: [ContactInfo] {
        switch sortOrder {
        case .name:
            return filtered.sorted { ($0.familyName + $0.givenName).lowercased() < ($1.familyName + $1.givenName).lowercased() }
        case .organization:
            return filtered.sorted {
                if $0.organization == $1.organization {
                    return ($0.familyName + $0.givenName).lowercased() < ($1.familyName + $1.givenName).lowercased()
                }
                return $0.organization.lowercased() < $1.organization.lowercased()
            }
        }
    }

    private var sections: [(key: String, contacts: [ContactInfo])] {
        let source = sortedContacts
        switch sortOrder {
        case .name:
            let grouped = Dictionary(grouping: source) { $0.sectionKey }
            return grouped.sorted { $0.key < $1.key }.map { (key: $0.key, contacts: $0.value) }
        case .organization:
            let grouped = Dictionary(grouping: source) { c in
                c.organization.isEmpty ? "#" : String(c.organization.uppercased().prefix(1))
            }
            return grouped.sorted { $0.key < $1.key }.map { (key: $0.key, contacts: $0.value) }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(BrainTheme.Colors.brandPurple)
                    Text("Kontakte laden...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // end loading
            } else if permissionDenied {
                ContentUnavailableView {
                    Label("Kein Zugriff auf Kontakte", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Brain benötigt Zugriff auf deine Kontakte. Bitte erlaube den Zugriff in den Einstellungen.")
                } actions: {
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else if filtered.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if contacts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Keine Kontakte")
                        .font(.title3.weight(.semibold))
                    Text("Kontakte werden aus dem iOS-Adressbuch geladen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, BrainTheme.Spacing.xl)
            } else {
                contactListView
            }
        }
        .navigationTitle("Kontakte")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Sortierung", selection: $sortOrder) {
                    ForEach(ContactSortOrder.allCases, id: \.self) { order in
                        Label(order.label, systemImage: order.icon).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !contacts.isEmpty {
                        Text("\(contacts.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    BrainHelpButton(context: "Kontakte: Suchen, Sortieren, Filtern, Bearbeiten", screenName: "Kontakte")
                    BrainAvatarButton(context: .contacts)
                }
            }
        }
        .task { await loadContacts() }
        .refreshable { await loadContacts() }
    }

    private var contactListView: some View {
        List {
            ForEach(sections, id: \.key) { section in
                Section(section.key) {
                    ForEach(section.contacts, id: \.identifier) { contact in
                        NavigationLink {
                            ContactDetailView(contactId: contact.identifier)
                        } label: {
                            ContactRow(contact: contact)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Kontakte suchen...")
    }

    private func loadContacts() async {
        // Prevent concurrent calls from .task and .refreshable
        guard !isLoadingContacts else { return }
        isLoadingContacts = true
        defer { isLoadingContacts = false }

        let bridge = ContactsBridge()
        let status = bridge.authorizationStatus()

        if status == .denied || status == .restricted {
            permissionDenied = true
            isLoading = false
            return
        }

        do {
            let granted = try await bridge.requestAccess()
            if !granted {
                permissionDenied = true
                isLoading = false
                return
            }

            let loaded = try bridge.listAll(limit: 1000)
            contacts = loaded
        } catch {
            // Don't set permissionDenied for non-permission errors
            if (error as NSError).domain == CNErrorDomain {
                permissionDenied = true
            }
        }
        isLoading = false
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: ContactInfo

    private var avatarColor: Color {
        let colors: [Color] = [
            BrainTheme.Colors.brandPurple, BrainTheme.Colors.accentMint,
            BrainTheme.Colors.accentCoral, BrainTheme.Colors.accentSky, BrainTheme.Colors.accentAmber,
        ]
        return colors[abs(contact.fullName.hashValue) % colors.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(contact.initials)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(avatarColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName)
                    .font(.body)
                subtitleText
            }
            Spacer()
            if !contact.phones.isEmpty {
                Image(systemName: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if !contact.jobTitle.isEmpty && !contact.organization.isEmpty {
            Text("\(contact.jobTitle), \(contact.organization)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if !contact.organization.isEmpty {
            Text(contact.organization)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !contact.jobTitle.isEmpty {
            Text(contact.jobTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let email = contact.emails.first, !email.isEmpty {
            Text(email)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Contact Detail View

struct ContactDetailView: View {
    let contactId: String
    @State private var contact: ContactInfo?
    @State private var isLoading: Bool
    @State private var showContactEditor = false

    // Init with ID — loads contact from bridge
    init(contactId: String) {
        self.contactId = contactId
        self._contact = State(initialValue: nil)
        self._isLoading = State(initialValue: true)
    }

    // Init with pre-loaded ContactInfo (used from SearchView)
    init(contact: ContactInfo) {
        self.contactId = contact.identifier
        self._contact = State(initialValue: contact)
        self._isLoading = State(initialValue: false)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let contact {
                contactContent(contact)
            } else {
                ContentUnavailableView(
                    "Kontakt nicht gefunden",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
        }
        .navigationTitle(contact?.fullName ?? "Kontakt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if contact != nil {
                    Button {
                        showContactEditor = true
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                }
            }
        }
        .task { await loadContact() }
        .sheet(isPresented: $showContactEditor) {
            ContactEditorSheet(contactId: contactId) {
                Task { await loadContact() }
            }
        }
    }

    private func contactContent(_ c: ContactInfo) -> some View {
        List {
            // Header section with avatar and name
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrainTheme.Colors.brandPurple.opacity(0.2), BrainTheme.Colors.accentSky.opacity(0.15)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 88)
                        Text(c.initials)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(BrainTheme.Colors.brandPurple)
                    }
                    .shadow(color: BrainTheme.Colors.brandPurple.opacity(0.15), radius: 8, x: 0, y: 4)
                    Text(c.fullName)
                        .font(.title2.bold())
                    if !c.jobTitle.isEmpty || !c.organization.isEmpty {
                        let parts = [c.jobTitle, c.organization].filter { !$0.isEmpty }
                        Text(parts.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Quick action buttons
            if !c.phones.isEmpty || !c.emails.isEmpty {
                Section {
                    quickActions(c)
                }
            }

            // Phone numbers
            if !c.phones.isEmpty {
                Section("Telefon") {
                    ForEach(c.phones, id: \.self) { phone in
                        Button {
                            callPhone(phone)
                        } label: {
                            Label(phone, systemImage: "phone.fill")
                        }
                        .contextMenu {
                            Button("Kopieren", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = phone
                            }
                            Button("Nachricht senden", systemImage: "message.fill") {
                                sendSMS(phone)
                            }
                        }
                    }
                }
            }

            // Email addresses
            if !c.emails.isEmpty {
                Section("E-Mail") {
                    ForEach(c.emails, id: \.self) { email in
                        Button {
                            sendEmail(email)
                        } label: {
                            Label(email, systemImage: "envelope.fill")
                        }
                        .contextMenu {
                            Button("Kopieren", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = email
                            }
                        }
                    }
                }
            }

            // Addresses
            if !c.postalAddresses.isEmpty {
                Section("Adresse") {
                    ForEach(c.postalAddresses, id: \.self) { address in
                        Button {
                            openInMaps(address)
                        } label: {
                            Label(address, systemImage: "map.fill")
                        }
                        .contextMenu {
                            Button("Kopieren", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = address
                            }
                        }
                    }
                }
            }

            // Birthday
            if let bday = c.birthday, let month = bday.month, let day = bday.day {
                Section("Geburtstag") {
                    let yearText = bday.year.map { "\(day). \(monthName(month)) \($0)" }
                        ?? "\(day). \(monthName(month))"
                    Label(yearText, systemImage: "gift.fill")
                }
            }

            // Note
            if !c.note.isEmpty {
                Section("Notiz") {
                    Text(c.note)
                        .font(.body)
                }
            }
        }
    }

    private func quickActions(_ c: ContactInfo) -> some View {
        HStack(spacing: 16) {
            Spacer()
            if let phone = c.phones.first {
                actionButton(icon: "phone.fill", label: "Anrufen") {
                    callPhone(phone)
                }
            }
            if let phone = c.phones.first {
                actionButton(icon: "message.fill", label: "Nachricht") {
                    sendSMS(phone)
                }
            }
            if let email = c.emails.first {
                actionButton(icon: "envelope.fill", label: "E-Mail") {
                    sendEmail(email)
                }
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Actions

    private func callPhone(_ phone: String) {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func sendSMS(_ phone: String) {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "sms:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func sendEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }

    private func openInMaps(_ address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func monthName(_ month: Int) -> String {
        let names = ["", "Januar", "Februar", "Maerz", "April", "Mai", "Juni",
                     "Juli", "August", "September", "Oktober", "November", "Dezember"]
        return month >= 1 && month <= 12 ? names[month] : ""
    }

    private func loadContact() async {
        let bridge = ContactsBridge()
        // Ensure access is granted before reading
        _ = try? await bridge.requestAccess()
        do {
            contact = try bridge.read(identifier: contactId)
        } catch {
            contact = nil
        }
        isLoading = false
    }
}


// MARK: - Contact Editor (UIKit Wrapper)

struct ContactEditorSheet: UIViewControllerRepresentable {
    let contactId: String
    let onDismiss: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        guard let contact = try? store.unifiedContact(withIdentifier: contactId, keysToFetch: keys) else {
            return UINavigationController(rootViewController: UIViewController())
        }
        let vc = CNContactViewController(for: contact)
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDismiss: @MainActor () -> Void
        init(onDismiss: @escaping @MainActor () -> Void) { self.onDismiss = onDismiss }
        nonisolated func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            let callback = onDismiss
            Task { @MainActor in
                viewController.dismiss(animated: true)
                callback()
            }
        }
    }
}
