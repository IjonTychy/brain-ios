import Foundation
import BrainCore
import EventKit
import GRDB
import os.log

// Facade over specialized repositories.
// Keeps backward compatibility — all callers use DataBridge methods.
// Repositories handle the actual operations (thread-safe, no @MainActor needed).
@MainActor @Observable
final class DataBridge {
    let db: DatabaseManager

    // AP 8.1: Specialized repositories
    let entries: EntryRepository
    let tags: TagRepository
    let links: LinkRepository
    let search: SearchRepository
    private let dashboard: DashboardRepository
    private let skillService: SkillService

    // Cached dashboard state
    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 5
    private(set) var entryCount: Int = 0
    private(set) var openTaskCount: Int = 0
    private(set) var skillCount: Int = 0
    private(set) var tagCount: Int = 0
    private(set) var linkCount: Int = 0
    private(set) var recentEntries: [Entry] = []
    private(set) var openTasks: [Entry] = []
    private(set) var unreadMailCount: Int = 0
    private(set) var todayEntryCount: Int = 0
    private(set) var factCount: Int = 0
    private(set) var isRefreshing: Bool = false

    // AP 8.2: Dependency injection with defaults
    init(db: DatabaseManager,
         entries: EntryRepository? = nil,
         tags: TagRepository? = nil,
         links: LinkRepository? = nil,
         search: SearchRepository? = nil) {
        self.db = db
        self.entries = entries ?? EntryRepository(pool: db.pool)
        self.tags = tags ?? TagRepository(pool: db.pool)
        self.links = links ?? LinkRepository(pool: db.pool)
        self.search = search ?? SearchRepository(pool: db.pool)
        self.dashboard = DashboardRepository(pool: db.pool)
        self.skillService = SkillService(pool: db.pool)
    }

    // MARK: - Dashboard

    func refreshDashboard() {
        guard Date().timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        defer { lastRefresh = Date() }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let stats = try dashboard.fetchStats()
            entryCount = stats.entryCount
            openTaskCount = stats.openTaskCount
            skillCount = stats.skillCount
            tagCount = stats.tagCount
            linkCount = stats.linkCount
            recentEntries = stats.recentEntries
            openTasks = stats.openTasks
            unreadMailCount = stats.unreadMailCount
            todayEntryCount = stats.todayEntryCount
            factCount = stats.factCount
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "DataBridge")
                .error("Dashboard refresh failed: \(error)")
        }
    }

    func dashboardVariables() -> [String: ExpressionValue] {
        refreshDashboard()
        let greeting = DashboardRepository.greetingForTimeOfDay()
        let entryValues = recentEntries.map { entry -> ExpressionValue in
            .object([
                "title": .string(entry.title ?? "Ohne Titel"),
                "type": .string(entry.type.rawValue),
                "status": .string(entry.status.rawValue),
            ])
        }
        let taskValues: [ExpressionValue] = openTasks.map { task in
            .object([
                "id": .string(String(task.id ?? 0)),
                "title": .string(task.title ?? "Ohne Titel"),
                "priority": .int(task.priority),
                "status": .string(task.status.rawValue),
            ])
        }

        let todayFormatted = Self.dashboardDateFormatter.string(from: Date())

        // Bug 6: Include today's calendar events
        let calBridge = EventKitBridge()
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let todayEvents = calBridge.listEvents(from: todayStart, to: todayEnd, limit: 10)
        let calendarValues: [ExpressionValue] = todayEvents.map { event in
            let timeStr: String
            if event.isAllDay {
                timeStr = "Ganztaegig"
            } else {
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm"
                timeStr = fmt.string(from: event.startDate) + " - " + fmt.string(from: event.endDate)
            }
            return .object([
                "title": .string(event.title),
                "time": .string(timeStr),
                "location": .string(event.location),
                "calendar": .string(event.calendarName),
            ])
        }

        // Upcoming birthdays from Contacts
        let contactsBridge = ContactsBridge()
        let bdayList = contactsBridge.upcomingBirthdays(withinDays: 14, limit: 5)
        var birthdayValues: [ExpressionValue] = []
        for bday in bdayList {
            let label: String
            if bday.daysUntil == 0 {
                label = "Heute"
            } else if bday.daysUntil == 1 {
                label = "Morgen"
            } else {
                label = "in \(bday.daysUntil) Tagen"
            }
            let obj: ExpressionValue = .object([
                "name": .string(bday.name),
                "daysUntil": .int(bday.daysUntil),
                "label": .string(label),
            ])
            birthdayValues.append(obj)
        }

        return [
            "greeting": .string(greeting),
            "today": .string(todayFormatted),
            "upcomingBirthdays": .array(birthdayValues),
            "stats": .object([
                "entries": .string(String(entryCount)),
                "openTasks": .string(String(openTaskCount)),
                "skills": .string(String(skillCount)),
                "tags": .string(String(tagCount)),
                "unreadMails": .string(String(unreadMailCount)),
                "todayEntries": .string(String(todayEntryCount)),
                "facts": .string(String(factCount)),
            ]),
            "recentEntries": .array(entryValues),
            "openTasks": .array(taskValues),
            "todayEvents": .array(calendarValues),
            "isLoading": .bool(isRefreshing),
        ]
    }

    func brainAdminVariables() -> [String: ExpressionValue] {
        refreshDashboard()
        let dbSize = db.approximateSize()
        let keychain = KeychainService()
        let anthropicConfigured = keychain.exists(key: KeychainKeys.anthropicAPIKey)
        let openAIConfigured = keychain.exists(key: KeychainKeys.openAIAPIKey)
        return [
            "stats": .object([
                "activeSkills": .string(String(skillCount)),
                "entries": .string(String(entryCount)),
                "tags": .string(String(tagCount)),
                "links": .string(String(linkCount)),
                "dbSize": .string(dbSize),
            ]),
            "anthropicConfigured": .bool(anthropicConfigured),
            "openAIConfigured": .bool(openAIConfigured),
        ]
    }

    // MARK: - Calendar (via EventKit bridge)

    // L18: Cached DateFormatters (static let — DateFormatter is Sendable in Swift 6.1+)
    private static let dashboardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "HH:mm"
        return f
    }()

    func calendarVariables() -> [String: ExpressionValue] {
        let bridge = EventKitBridge()
        let events = bridge.todayEvents().map { event -> ExpressionValue in
            .object([
                "title": .string(event.title),
                "time": .string(event.isAllDay ? "Ganztaegig" : Self.timeFormatter.string(from: event.startDate)),
                "location": .string(event.location),
                "calendar": .string(event.calendarName),
                "isAllDay": .bool(event.isAllDay),
            ])
        }
        return [
            "today": .string(Self.dateFormatter.string(from: Date())),
            "events": .array(events),
        ]
    }

    // MARK: - People (via Contacts bridge)

    nonisolated func peopleVariables(query: String = "") async -> [String: ExpressionValue] {
        let bridge = ContactsBridge()
        let contacts: [ExpressionValue]
        var denied = false

        // Check authorization status first
        let status = bridge.authorizationStatus()
        if status == .denied || status == .restricted {
            return ["contacts": .array([]), "permissionDenied": .bool(true)]
        }

        do {
            // Request access (shows dialog if .notDetermined)
            let granted = try await bridge.requestAccess()
            if !granted {
                denied = true
                contacts = []
            } else {
                // Run blocking enumerateContacts off main thread to avoid deadlock
                let q = query
                let results = try await Task.detached {
                    try q.isEmpty
                        ? bridge.listAll(limit: 200)
                        : bridge.search(query: q, limit: 200)
                }.value
                contacts = results.map(\.expressionValue)
            }
        } catch {
            denied = true
            contacts = []
        }
        return ["contacts": .array(contacts), "permissionDenied": .bool(denied)]
    }

    // MARK: - Facade: Entry operations (delegates to EntryRepository)

    nonisolated func createEntry(title: String, type: String = "thought", body: String? = nil) throws -> Entry {
        try entries.create(title: title, type: type, body: body)
    }

    nonisolated func searchEntries(query: String, limit: Int = 20) throws -> [Entry] {
        try search.search(query: query, limit: limit)
    }

    nonisolated func listEntries(limit: Int = 50) throws -> [Entry] {
        try entries.list(limit: limit)
    }

    @discardableResult
    nonisolated func updateEntry(id: Int64, title: String?, body: String?) throws -> Entry? {
        try entries.update(id: id, title: title, body: body)
    }

    nonisolated func deleteEntry(id: Int64) throws {
        try entries.delete(id: id)
    }

    @discardableResult
    nonisolated func markDone(id: Int64) throws -> Entry? {
        try entries.markDone(id: id)
    }

    @discardableResult
    nonisolated func archiveEntry(id: Int64) throws -> Entry? {
        try entries.archive(id: id)
    }

    @discardableResult
    nonisolated func restoreEntry(id: Int64) throws -> Entry? {
        try entries.restore(id: id)
    }

    nonisolated func fetchEntry(id: Int64) throws -> Entry? {
        try entries.fetch(id: id)
    }

    // MARK: - Facade: Link operations

    @discardableResult
    nonisolated func createLink(sourceId: Int64, targetId: Int64, relation: String = "related") throws -> Link {
        try links.create(sourceId: sourceId, targetId: targetId, relation: relation)
    }

    nonisolated func deleteLink(sourceId: Int64, targetId: Int64) throws {
        try links.delete(sourceId: sourceId, targetId: targetId)
    }

    nonisolated func linkedEntries(for entryId: Int64) throws -> [Entry] {
        try links.linkedEntries(for: entryId)
    }

    // MARK: - Facade: Tag operations

    nonisolated func addTag(entryId: Int64, tagName: String) throws {
        try tags.add(entryId: entryId, tagName: tagName)
    }

    nonisolated func removeTag(entryId: Int64, tagName: String) throws {
        try tags.remove(entryId: entryId, tagName: tagName)
    }

    nonisolated func listTags() throws -> [Tag] {
        try tags.list()
    }

    nonisolated func tagCounts() throws -> [(tag: Tag, count: Int)] {
        try tags.counts()
    }

    // MARK: - Facade: Search operations

    nonisolated func autocomplete(prefix: String, limit: Int = 10) throws -> [Entry] {
        try search.autocomplete(prefix: prefix, limit: limit)
    }

    // MARK: - Facade: Skill operations

    nonisolated func listSkills() throws -> [Skill] {
        try skillService.list()
    }

    @discardableResult
    nonisolated func installSkill(_ skill: Skill) throws -> Skill {
        try skillService.install(skill)
    }

    nonisolated func setSkillEnabled(id: String, enabled: Bool) throws {
        try skillService.setEnabled(id: id, enabled: enabled)
    }

    nonisolated func uninstallSkill(id: String) throws {
        try skillService.uninstall(id: id)
    }

    nonisolated func exportSkill(id: String) throws -> String {
        let lifecycle = SkillLifecycle(pool: db.pool)
        return try lifecycle.export(id: id)
    }

    nonisolated func importSkillFromMarkdown(_ markdown: String) throws -> Skill {
        let lifecycle = SkillLifecycle(pool: db.pool)
        let source = try lifecycle.preview(markdown: markdown)
        let installedSkill: Skill
        if source.screensJSON != nil || source.actionsJSON != nil {
            installedSkill = try lifecycle.installFromSource(source: source, createdBy: .import)
        } else {
            let definition = SkillDefinition(
                id: source.id,
                screens: [
                    "main": ScreenNode(
                        type: "stack",
                        properties: ["direction": .string("vertical"), "spacing": .double(12)],
                        children: [
                            ScreenNode(type: "text", properties: [
                                "value": .string(source.name),
                                "style": .string("title"),
                            ]),
                            ScreenNode(type: "text", properties: [
                                "value": .string(source.description ?? "Importierter Skill"),
                                "style": .string("body"),
                            ]),
                        ]
                    ),
                ]
            )
            installedSkill = try lifecycle.installFromDefinition(
                source: source, definition: definition, createdBy: .import
            )
        }
        try db.pool.write { db in
            var skill = installedSkill
            skill.sourceMarkdown = markdown
            try skill.update(db)
        }
        return installedSkill
    }

    // MARK: - Facade: Rules Engine

    nonisolated func evaluateRules(trigger: String, entryType: String? = nil) throws -> [RuleMatch] {
        let rulesEngine = RulesEngine(pool: db.pool)
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let timeOfDay = String(format: "%02d:%02d", hour, minute)
        return try rulesEngine.evaluate(context: RuleContext(trigger: trigger, entryType: entryType, timeOfDay: timeOfDay))
    }

    // MARK: - Facade: Proposals

    nonisolated func listProposals(status: ProposalStatus? = nil) throws -> [Proposal] {
        try db.pool.read { db in
            var request = Proposal.order(Column("createdAt").desc)
            if let status { request = request.filter(Column("status") == status) }
            return try request.fetchAll(db)
        }
    }

    nonisolated func applyProposal(id: Int64) throws -> Proposal? {
        try db.pool.write { db in
            guard var proposal = try Proposal.fetchOne(db, key: id) else { return nil }
            proposal.status = .applied
            proposal.appliedAt = ISO8601DateFormatter().string(from: Date())
            try proposal.update(db)
            return proposal
        }
    }

    nonisolated func rejectProposal(id: Int64) throws -> Proposal? {
        try db.pool.write { db in
            guard var proposal = try Proposal.fetchOne(db, key: id) else { return nil }
            proposal.status = .rejected
            try proposal.update(db)
            return proposal
        }
    }

    nonisolated func createProposal(title: String, description: String?, category: String, changeSpec: String?) throws -> Proposal {
        try db.pool.write { db in
            var proposal = Proposal(
                title: title,
                description: description,
                category: category,
                changeSpec: changeSpec,
                status: .pending
            )
            try proposal.insert(db)
            return proposal
        }
    }

    // MARK: - Facade: Rules CRUD

    nonisolated func listRules(category: String? = nil, enabled: Bool? = nil) throws -> [Rule] {
        try db.pool.read { db in
            var request = Rule.order(Column("priority").desc, Column("name").asc)
            if let category { request = request.filter(Column("category") == category) }
            if let enabled { request = request.filter(Column("enabled") == enabled) }
            return try request.fetchAll(db)
        }
    }

    nonisolated func fetchRule(id: Int64) throws -> Rule? {
        try db.pool.read { db in
            try Rule.fetchOne(db, key: id)
        }
    }

    nonisolated func createRule(category: String, name: String, condition: String?,
                                action: String, priority: Int = 0) throws -> Rule {
        try db.pool.write { db in
            var rule = Rule(
                category: category,
                name: name,
                condition: condition,
                action: action,
                priority: priority,
                enabled: true,
                modifiedBy: "user"
            )
            try rule.insert(db)
            return rule
        }
    }

    nonisolated func updateRule(_ rule: Rule) throws {
        try db.pool.write { db in
            var updated = rule
            updated.modifiedAt = ISO8601DateFormatter().string(from: Date())
            updated.modifiedBy = "user"
            try updated.update(db)
        }
    }

    nonisolated func deleteRule(id: Int64) throws {
        try db.pool.write { db in
            _ = try Rule.deleteOne(db, key: id)
        }
    }

    nonisolated func toggleRule(id: Int64) throws -> Rule? {
        try db.pool.write { db in
            guard var rule = try Rule.fetchOne(db, key: id) else { return nil }
            rule.enabled.toggle()
            rule.modifiedAt = ISO8601DateFormatter().string(from: Date())
            rule.modifiedBy = "user"
            try rule.update(db)
            return rule
        }
    }

    // MARK: - Facade: LLM Provider

    nonisolated func buildLLMProvider() async -> (any LLMProvider)? {
        let keychain = KeychainService()
        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-opus-4-6"

        if selectedModel == "on-device" {
            return OnDeviceProvider()
        }

        if selectedModel.hasPrefix("gemini") {
            let geminiKey = keychain.read(key: KeychainKeys.geminiAPIKey) ?? ""
            if !geminiKey.isEmpty {
                return GeminiProvider(apiKey: geminiKey, model: selectedModel)
            }
            if let token = try? await GoogleOAuthService().getValidToken() {
                return GeminiProvider(oauthToken: token, model: selectedModel)
            }
        }

        if selectedModel.hasPrefix("gpt-") || selectedModel.hasPrefix("o") {
            let openAIKey = keychain.read(key: KeychainKeys.openAIAPIKey) ?? ""
            if !openAIKey.isEmpty {
                return OpenAIProvider(apiKey: openAIKey, model: selectedModel)
            }
        }

        if selectedModel.hasPrefix("grok") {
            let xaiKey = keychain.read(key: KeychainKeys.xaiAPIKey) ?? ""
            if !xaiKey.isEmpty {
                return OpenAICompatibleProvider(
                    baseURL: "https://api.x.ai",
                    model: selectedModel,
                    apiKey: xaiKey,
                    providerName: "Grok"
                )
            }
        }

        if let endpoints = AvailableModels.loadCustomEndpoints() {
            for endpoint in endpoints where endpoint.model == selectedModel {
                return OpenAICompatibleProvider(
                    baseURL: endpoint.baseURL,
                    model: endpoint.model,
                    apiKey: endpoint.apiKey,
                    providerName: endpoint.name
                )
            }
        }

        let mode = UserDefaults.standard.string(forKey: "anthropicMode") ?? "api"
        switch mode {
        case "proxy":
            if let baseURL = keychain.read(key: KeychainKeys.anthropicProxyURL), !baseURL.isEmpty {
                let token = await BrainAPIAuthService.shared.getValidToken()
                let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                return AnthropicProvider(proxyURL: base + "/claude-proxy", model: selectedModel, bearerToken: token)
            }
        case "max":
            if let sessionKey = keychain.read(key: KeychainKeys.anthropicMaxSessionKey), !sessionKey.isEmpty {
                return AnthropicProvider(sessionKey: sessionKey, model: selectedModel)
            }
        default:
            break
        }

        let anthropicKey = keychain.read(key: KeychainKeys.anthropicAPIKey) ?? ""
        let provider = AnthropicProvider(apiKey: anthropicKey, model: selectedModel)
        return provider.isAvailable ? provider : nil
    }

    // MARK: - Facade: Knowledge

    nonisolated func saveKnowledgeFact(subject: String, predicate: String, object: String,
                                      confidence: Double = 1.0, sourceEntryId: Int64? = nil) throws -> KnowledgeFact {
        try db.pool.write { db in
            var fact = KnowledgeFact(
                subject: subject, predicate: predicate, object: object,
                confidence: confidence, sourceEntryId: sourceEntryId
            )
            try fact.insert(db)
            return fact
        }
    }
}

// MARK: - DataProviding conformance

extension DataBridge: DataProviding {
    nonisolated public var databasePool: DatabasePool { db.pool }
}
