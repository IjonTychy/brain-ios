import SwiftUI
import BrainCore
import os.log
import BackgroundTasks

// Sendable wrapper for BGTask — BGTask is not Sendable (Apple legacy),
// but setTaskCompleted is documented as thread-safe. This wrapper allows
// safe capture in Task.detached closures without data race warnings.
// Uses OSAllocatedUnfairLock to guarantee setTaskCompleted is called at most once
// (both expiration handler and worker Task can race to complete).
private final class BGTaskHelper: Sendable {
    nonisolated(unsafe) private let task: BGTask
    private let completed = OSAllocatedUnfairLock(initialState: false)

    init(_ task: BGTask) { self.task = task }

    func complete(success: Bool) {
        let alreadyCompleted = completed.withLock { done -> Bool in
            if done { return true }
            done = true
            return false
        }
        guard !alreadyCompleted else { return }
        task.setTaskCompleted(success: success)
    }
}

@main
struct BrainApp: App {
    @State private var dataBridge: DataBridge
    @State private var storeKit = StoreKitManager()
    @State private var proactiveService: ProactiveService?
    @State private var periodicAnalysis: PeriodicAnalysisService?
    @State private var behaviorTracker: BehaviorTracker?
    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var dbError: String?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    private let authenticator = DeviceBiometricAuthenticator()

    // Background task identifiers
    static let analysisRefreshId = "com.example.brain-ios.analysis"
    static let deepAnalysisId = "com.example.brain-ios.deep-analysis"

    // Documents directory — always available on iOS, guard is defensive only.
    // nonisolated: needed for BGTask handlers which run outside MainActor.
    nonisolated private static var documentsDirectory: URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("No Documents directory available on this device")
        }
        return url
    }

    init() {
        let db: DatabaseManager
        var initDbError: String?
        do {
            db = try SharedContainer.makeDatabaseManager()
        } catch {
            // Fallback to temp DB so the app can still launch and show an error.
            // The user sees a persistent banner via dbError state.
            let logger = Logger(subsystem: "com.example.brain-ios", category: "App")
            logger.critical("Hauptdatenbank fehlgeschlagen, nutze temporaere DB: \(error)")
            initDbError = "Datenbank konnte nicht geöffnet werden: \(error.localizedDescription). Daten sind vorübergehend nicht verfügbar."
            do {
                db = try DatabaseManager.temporary()
            } catch {
                fatalError("Cannot create temporary database: \(error)")
            }
        }

        _dataBridge = State(initialValue: DataBridge(db: db))
        _dbError = State(initialValue: initDbError)

        // Register background tasks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.brain-ios.analysis",
                                         using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handleAnalysisRefresh(refreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.brain-ios.deep-analysis",
                                         using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            Self.handleDeepAnalysis(processingTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.brain-ios.mail-sync",
                                         using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handleMailSync(refreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environment(dataBridge)
                } else if faceIDEnabled && authenticator.canUseBiometrics && !isAuthenticated {
                    lockScreen
                } else {
                    ContentView()
                    .tint(BrainTheme.Colors.brandPurple)
                        .environment(dataBridge)
                        .environment(storeKit)
                        .id(LocalizationService.shared.revision)
                }
            }
            .overlay(alignment: .top) {
                if let dbError {
                    Text(dbError)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.9))
                        .accessibilityLabel("Datenbankfehler: \(dbError)")
                }
            }
            .task {
                if hasCompletedOnboarding {
                    await authenticateIfNeeded()
                }
                // Load StoreKit products and listen for transactions
                await storeKit.loadProducts()
                storeKit.startListening()

                // Load bundled skills (UI skills + language packs)
                let skillLifecycle = SkillLifecycle(pool: dataBridge.db.pool)
                SkillBundleLoader.loadBundledSkills(lifecycle: skillLifecycle)

                // Ensure bootstrap skills (with actions) are in the DB.
                // SkillBundleLoader loads from .brainskill.md (no actions JSON).
                // This ensures the Swift-defined definitions with full actions land in the DB.
                ensureBootstrapSkillsInDB(lifecycle: skillLifecycle)

                // Import bundled documents (ethics system etc.) on first launch
                BundledDocumentLoader.loadIfNeeded(pool: dataBridge.db.pool)

                // Load language skill — respects UserDefaults("brainLanguage") override
                LocalizationService.shared.loadLanguageSkill(from: dataBridge.db.pool)

                // Initialize proactive service and run analysis on launch
                // Initialize behavior tracker and periodic analysis
            if behaviorTracker == nil {
                behaviorTracker = BehaviorTracker(pool: dataBridge.db.pool)
            }
            if periodicAnalysis == nil {
                let tracker = behaviorTracker ?? BehaviorTracker(pool: dataBridge.db.pool)
                let analysis = PeriodicAnalysisService(pool: dataBridge.db.pool, behaviorTracker: tracker)
                periodicAnalysis = analysis
                analysis.start()
            }

            if proactiveService == nil {
                    let service = ProactiveService(pool: dataBridge.db.pool)
                    proactiveService = service
                    if service.shouldShowMorningBriefing {
                        service.generateMorningBriefing()
                    } else if service.shouldShowEveningRecap {
                        service.generateEveningRecap()
                    }
                    service.runPatternAnalysis()
                }

                // Background-embed entries that don't have embeddings yet
                let embeddingBridge = EmbeddingBridge(pool: dataBridge.db.pool)
                Task.detached(priority: .background) {
                    let logger = Logger(subsystem: "com.example.brain-ios", category: "Embedding")
                    do {
                        let count = try embeddingBridge.embedMissing(batchSize: 50)
                        if count > 0 {
                            logger.info("Embedded \(count) entries")
                        }
                    } catch {
                        logger.error("Embedding failed: \(error)")
                    }
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .background:
                    scheduleBackgroundTasks()
                case .active:
                    periodicAnalysis?.start()
                    // Reschedule-on-Launch: re-register the next 64 notifications from DB
                    Task {
                        let bridge = NotificationBridge()
                        await bridge.rescheduleFromDatabase(pool: dataBridge.db.pool)
                    }
                default:
                    break
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    // MARK: - Deep Link Handling (brain:// URL Schema)

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "brain" else { return }
        let host = url.host() ?? ""

        switch host {
        case "capture":
            // From QuickCapture widget
            break // Already on capture tab by default
        case "tasks", "search":
            NotificationCenter.default.post(name: .brainNavigateTab, object: nil, userInfo: ["tab": "search"])
        case "dashboard":
            NotificationCenter.default.post(name: .brainNavigateTab, object: nil, userInfo: ["tab": "dashboard"])
        case "import-skill":
            // brain://import-skill?url=https://example.com/skill.brainskill.md
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let skillURL = URL(string: urlParam) {
                Task {
                    await importSkillFromURL(skillURL)
                }
            }
        default:
            // Try as tab name
            if let _ = BrainTab(rawValue: host) {
                NotificationCenter.default.post(name: .brainNavigateTab, object: nil, userInfo: ["tab": host])
            }
        }
    }

    private func importSkillFromURL(_ url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else { return }
            let parser = BrainSkillParser()
            let source = try parser.parse(content)
            let lifecycle = SkillLifecycle(pool: dataBridge.db.pool)
            try lifecycle.installFromSource(source: source, createdBy: .user)
        } catch {
            // Import errors are logged but don't crash
            let logger = Logger(subsystem: "com.example.brain-ios", category: "DeepLink")
            logger.error("Skill import from URL failed: \(error)")
        }
    }

    // MARK: - Lock Screen

    @State private var lockScreenAppeared = false

    private var lockScreen: some View {
        ZStack {
            // Time-of-day gradient background
            BrainTheme.Gradients.timeOfDaySubtle()
                .ignoresSafeArea()

            VStack(spacing: BrainTheme.spacingXXL) {
                Spacer()

                // Brain icon with breathing animation
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(BrainTheme.Gradients.brand)
                    .symbolEffect(.pulse, isActive: !isAuthenticated)
                    .scaleEffect(lockScreenAppeared ? 1.0 : 0.8)
                    .opacity(lockScreenAppeared ? 1.0 : 0)

                VStack(spacing: BrainTheme.spacingSM) {
                    // Time-of-day greeting
                    Text(BrainTheme.seasonalGreeting() ?? BrainTheme.greeting())
                        .font(BrainTheme.Typography.subheadline)
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                        .opacity(lockScreenAppeared ? 1.0 : 0)

                    Text("I, Brain")
                        .font(BrainTheme.Typography.displayLarge)
                        .foregroundStyle(BrainTheme.Colors.textPrimary)
                        .opacity(lockScreenAppeared ? 1.0 : 0)
                }

                if let error = authError {
                    Text(error)
                        .font(BrainTheme.Typography.callout)
                        .foregroundStyle(BrainTheme.Colors.destructive)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Unlock button with glass card style
                Button(action: {
                    Task { await authenticateIfNeeded() }
                }) {
                    Label(
                        authenticator.biometricType == .faceID ? "Mit Face ID entsperren" : "Mit Touch ID entsperren",
                        systemImage: authenticator.biometricType == .faceID ? "faceid" : "touchid"
                    )
                    .font(BrainTheme.Typography.headline)
                    .foregroundStyle(BrainTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrainTheme.spacingMD)
                }
                .buttonStyle(.plain)
                .brainGlassCard(cornerRadius: BrainTheme.cornerRadiusLG)
                .padding(.horizontal, BrainTheme.spacingXXL)
                .opacity(lockScreenAppeared ? 1.0 : 0)

                Spacer()
                    .frame(height: 40)
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: isAuthenticated)
        .onAppear {
            withAnimation(BrainTheme.Animations.springGentle) {
                lockScreenAppeared = true
            }
        }
        .onDisappear {
            lockScreenAppeared = false
        }
    }


    // MARK: - Background Task Scheduling

    private func scheduleBackgroundTasks() {
        // Light refresh: runs every ~30 min, 30s execution time
        let refreshRequest = BGAppRefreshTaskRequest(identifier: "com.example.brain-ios.analysis")
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(refreshRequest)
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "BGTask").error("Failed to schedule refresh: \(error)")
        }

        // Deep analysis: runs ~1-2x/day, up to 10 min execution
        let processingRequest = BGProcessingTaskRequest(identifier: "com.example.brain-ios.deep-analysis")
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        processingRequest.requiresExternalPower = false
        processingRequest.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(processingRequest)
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "BGTask").error("Failed to schedule deep analysis: \(error)")
        }

        // Mail sync: runs every ~15 min, needs network
        let mailRequest = BGAppRefreshTaskRequest(identifier: "com.example.brain-ios.mail-sync")
        mailRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(mailRequest)
        } catch {
            Logger(subsystem: "com.example.brain-ios", category: "BGTask").error("Failed to schedule mail sync: \(error)")
        }
    }

    nonisolated private static func handleAnalysisRefresh(_ bgTask: BGAppRefreshTask) {
        // BGAppRefreshTask is not Sendable (Apple legacy) but setTaskCompleted is thread-safe.
        // We use a helper that captures the task once and manages completion internally.
        let helper = BGTaskHelper(bgTask)
        let analysisTask = Task.detached {
            do {
                let db = try SharedContainer.makeDatabaseManager()
                let tracker = BehaviorTracker(pool: db.pool)
                let service = await MainActor.run { PeriodicAnalysisService(pool: db.pool, behaviorTracker: tracker) }
                await service.runSingleCycle()
                helper.complete(success: true)
            } catch {
                helper.complete(success: false)
            }
        }
        bgTask.expirationHandler = {
            analysisTask.cancel()
            helper.complete(success: false)
        }
        // Schedule next refresh
        let request = BGAppRefreshTaskRequest(identifier: "com.example.brain-ios.analysis")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleDeepAnalysis(_ bgTask: BGProcessingTask) {
        let helper = BGTaskHelper(bgTask)
        let analysisTask = Task.detached {
            do {
                let db = try SharedContainer.makeDatabaseManager()
                let tracker = BehaviorTracker(pool: db.pool)
                let service = await MainActor.run { PeriodicAnalysisService(pool: db.pool, behaviorTracker: tracker) }
                await service.runDeepCycle(batchSize: 50)
                helper.complete(success: true)
            } catch {
                helper.complete(success: false)
            }
        }
        bgTask.expirationHandler = {
            analysisTask.cancel()
            helper.complete(success: false)
        }
        // Schedule next deep analysis
        let request = BGProcessingTaskRequest(identifier: "com.example.brain-ios.deep-analysis")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleMailSync(_ bgTask: BGAppRefreshTask) {
        let logger = Logger(subsystem: "com.example.brain-ios", category: "MailSync")
        let helper = BGTaskHelper(bgTask)
        let syncTask = Task.detached {
            do {
                let db = try SharedContainer.makeDatabaseManager()
                let bridge = EmailBridge(pool: db.pool)

                // Only sync if mail is configured
                let accounts = try bridge.listAccounts()
                guard !accounts.isEmpty else {
                    logger.info("No mail accounts configured, skipping background sync")
                    helper.complete(success: true)
                    return
                }

                var totalSynced = 0
                for account in accounts {
                    do {
                        let count = try await bridge.syncAllFolders(accountId: account.id, limit: 30)
                        totalSynced += count
                    } catch {
                        logger.error("Background sync failed for \(account.name): \(error)")
                    }
                }
                logger.info("Background mail sync done: \(totalSynced) new emails across \(accounts.count) accounts")
                helper.complete(success: true)
            } catch {
                logger.error("Background mail sync failed: \(error)")
                helper.complete(success: false)
            }
        }
        bgTask.expirationHandler = {
            syncTask.cancel()
            helper.complete(success: false)
        }
        // Schedule next mail sync (~15 min)
        let request = BGAppRefreshTaskRequest(identifier: "com.example.brain-ios.mail-sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func ensureBootstrapSkillsInDB(lifecycle: SkillLifecycle) {
        let bootstrapSkills: [(String, String, SkillDefinition)] = [
            ("dashboard", "Dashboard", BootstrapSkills.dashboard),
            ("mail-inbox", "Mail Inbox", BootstrapSkills.mailInbox),
            ("calendar", "Kalender", BootstrapSkills.calendar),
            ("mail-config", "Mail Konfiguration", BootstrapSkills.mailConfig),
            ("quick-capture", "Schnellerfassung", BootstrapSkills.quickCapture),
        ]

        for (id, name, definition) in bootstrapSkills {
            if let existing = try? lifecycle.fetch(id: id) {
                if existing.createdBy == .system {
                    // System version — safe to update with latest from code
                    let screensJSON = try? JSONEncoder().encode(definition.screens)
                    let actionsJSON = definition.actions.flatMap { try? JSONEncoder().encode($0) }
                    if let screensData = screensJSON,
                       let screensStr = String(data: screensData, encoding: .utf8) {
                        let actionsStr = actionsJSON.flatMap { String(data: $0, encoding: .utf8) }
                        try? lifecycle.updateDefinition(
                            id: id,
                            screens: screensStr,
                            actions: actionsStr,
                            version: definition.version
                        )
                    }
                }
                // User-modified (createdBy != .system) → do NOT overwrite
                continue
            }

            // Not yet in DB → install
            let source = BrainSkillSource(
                id: id,
                name: name,
                version: definition.version
            )
            do {
                _ = try lifecycle.installFromDefinition(
                    source: source,
                    definition: definition,
                    createdBy: .system
                )
            } catch {
                let logger = Logger(subsystem: "com.example.brain-ios", category: "Bootstrap")
                logger.error("Skill '\(id)' install failed: \(error)")
            }
        }
    }

    private func authenticateIfNeeded() async {
        guard faceIDEnabled, authenticator.canUseBiometrics else {
            isAuthenticated = true
            return
        }

        do {
            let success = try await authenticator.authenticate(reason: "Brain entsperren")
            isAuthenticated = success
            if !success {
                authError = "Authentifizierung fehlgeschlagen"
            }
        } catch {
            authError = "Fehler: \(error.localizedDescription)"
        }
    }
}
