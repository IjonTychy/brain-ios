import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers
import BrainCore

// Root view: adaptive navigation for iPhone (TabView) and iPad (NavigationSplitView).
struct ContentView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var navState = NavigationState()
    @State private var chatService: ChatService?
    @State private var proactiveService: ProactiveService?
    @State private var showSettings = false
    @State private var showMarkdownImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showBriefing = false
    @State private var searchQuery = ""
    @State private var savedToast: String?
    @State private var activeSkills: [Skill] = []
    @State private var brainFact: String?
    @State private var showBrainFact = false
    @State private var openEntryId: Int64?

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onAppear {
            if chatService == nil {
                chatService = ChatService(pool: dataBridge.db.pool)
            }
            if proactiveService == nil {
                let service = ProactiveService(pool: dataBridge.db.pool)
                proactiveService = service
                // Self-Modifier: evaluate rules on app_open
                service.evaluateRules(trigger: "app_open")

                // Auto-show briefing if it's morning and we have one
                if service.shouldShowMorningBriefing {
                    service.generateMorningBriefing()
                    // Only show the sheet if briefing data was actually generated
                    if service.morningBriefing != nil {
                        showBriefing = true
                    }
                }
            }
            // Handle pending Siri question from AskBrainIntent
            // F-20: Read from App Group shared container (written by AskBrainIntent).
            let sharedDefaults = UserDefaults(suiteName: SharedContainer.appGroupID)
            if let siriQuestion = sharedDefaults?.string(forKey: "pendingSiriQuestion"),
               !siriQuestion.isEmpty {
                sharedDefaults?.removeObject(forKey: "pendingSiriQuestion")
                navState.selectedTab = .chat
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        chatService?.pendingInput = siriQuestion
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brainSkillAction)) { notification in
            if let action = notification.userInfo?["action"] as? String,
               let skill = notification.userInfo?["skill"] as? String {
                let vars = notification.userInfo?["variables"] as? [String: String] ?? [:]
                let contextStr = vars.isEmpty ? "" : " Kontext: " + vars.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                let prompt = "Der User hat im Skill \(skill) die Aktion \(action) ausgelöst.\(contextStr) Bitte führe die Aktion aus."
                chatService?.send(prompt)
                navState.selectedTab = .chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brainNavigateTab)) { notification in
            if let tabName = notification.userInfo?["tab"] as? String,
               let tab = BrainTab(rawValue: tabName) {
                navState.selectedTab = tab
                // If a message is included (e.g. from skill proposal), send it to chat
                if tab == .chat, let message = notification.userInfo?["message"] as? String {
                    let service = chatService ?? ChatService(pool: dataBridge.db.pool)
                    chatService = service
                    // Small delay to let the chat view appear
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        service.send(message)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brainOpenEntry)) { notification in
            if let entryId = notification.userInfo?["entryId"] as? Int64 {
                openEntryId = entryId
            }
        }
        .sheet(item: Binding(
            get: { openEntryId.map { EntryIdWrapper(id: $0) } },
            set: { openEntryId = $0?.id }
        )) { wrapper in
            NavigationStack {
                if let entry = try? dataBridge.fetchEntry(id: wrapper.id) {
                    EntryDetailView(entry: entry, dataBridge: dataBridge)
                } else {
                    ContentUnavailableView(
                        "Eintrag nicht gefunden",
                        systemImage: "doc.questionmark"
                    )
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let _ = try? await newItem.loadTransferable(type: Data.self) {
                    let _ = try? dataBridge.createEntry(title: "Foto-Analyse", type: "note", body: "Foto importiert. Bitte im Chat analysieren lassen.")
                    savedToast = "Foto als Entry gespeichert"
                }
            }
        }
        .fileImporter(
            isPresented: $showMarkdownImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        let filename = url.deletingPathExtension().lastPathComponent
                        let _ = try? dataBridge.createEntry(
                            title: filename,
                            type: "note",
                            body: text
                        )
                    }
                }
                savedToast = "\(urls.count) Datei(en) importiert"
            case .failure(let error):
                savedToast = "Import-Fehler: \(error.localizedDescription)"
            }
        }
        .safeAreaInset(edge: .top) {
            OfflineBanner()
                .padding(.top, 2)
        }
        .alert("Wusstest du?", isPresented: $showBrainFact) {
            Button("Cool!") { }
        } message: {
            Text(brainFact ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(dataBridge)
        }
        .sheet(isPresented: $showBriefing) {
            NavigationStack {
                if let briefing = proactiveService?.morningBriefing {
                    BriefingView(briefing: briefing)
                        .navigationTitle("Brain Pulse")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fertig") { showBriefing = false }
                            }
                        }
                } else if let recap = proactiveService?.eveningRecap {
                    RecapView(recap: recap)
                        .navigationTitle("Tagesrückblick")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fertig") { showBriefing = false }
                            }
                        }
                } else {
                    // Dismiss immediately if no data available
                    Color.clear.onAppear { showBriefing = false }
                }
            }
        }
    }

    // MARK: - iPhone: TabView (5 tabs like iPhone)

    private var iPhoneLayout: some View {
        TabView(selection: $navState.selectedTab) {
            NavigationStack {
                tabContent(for: .dashboard)
                    .navigationTitle(L(BrainTab.dashboard.localizationKey))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 12) {
                                BrainHelpButton(context: "Dashboard mit Heute-Übersicht, Kalender, Dokumenten", screenName: "Dashboard")
                                BrainAvatarButton(context: .dashboard)
                            }
                        }
                    }
            }
            .tabItem { Label(L(BrainTab.dashboard.localizationKey), systemImage: BrainTab.dashboard.icon) }
            .tag(BrainTab.dashboard)

            NavigationStack {
                tabContent(for: .search)
                    .navigationTitle(L(BrainTab.search.localizationKey))
            }
            .tabItem { Label(L(BrainTab.search.localizationKey), systemImage: BrainTab.search.icon) }
            .tag(BrainTab.search)

            NavigationStack {
                tabContent(for: .chat)
                    .navigationTitle(L(BrainTab.chat.localizationKey))
            }
            .tabItem { Label(L(BrainTab.chat.localizationKey), systemImage: BrainTab.chat.icon) }
            .tag(BrainTab.chat)

            NavigationStack {
                tabContent(for: .mail)
                    .navigationTitle(L(BrainTab.mail.localizationKey))
            }
            .tabItem { Label(L(BrainTab.mail.localizationKey), systemImage: BrainTab.mail.icon) }
            .tag(BrainTab.mail)

            NavigationStack {
                MoreTabView(showSettings: $showSettings)
            }
            .tabItem { Label(L(BrainTab.more.localizationKey), systemImage: BrainTab.more.icon) }
            .tag(BrainTab.more)
        }
        .tint(BrainTheme.Colors.brandPurple)
    }

    // Active skills in iPad sidebar — uses Button to set selectedSkill.
    @ViewBuilder
    private var iPadSkillsSection: some View {
        if !activeSkills.isEmpty {
            Section("Skills") {
                ForEach(activeSkills, id: \.id) { skill in
                    Button { selectedSkill = skill } label: {
                        skillLabel(for: skill)
                    }
                    .listRowBackground(selectedSkill?.id == skill.id ? Color.accentColor.opacity(0.15) : nil)
                }
            }
        }
    }

    private func skillLabel(for skill: Skill) -> some View {
        Label {
            Text(skill.name)
        } icon: {
            Image(systemName: skill.icon ?? "puzzlepiece.extension")
                .foregroundStyle(skill.color.flatMap { Color(hex: $0) } ?? .blue)
        }
    }

    private func skillView(for skill: Skill) -> some View {
        Group {
            if let definition = skill.toSkillDefinition() {
                let vars = SkillContextProvider(dataBridge: dataBridge)
                    .variables(for: skill)
                SkillView(
                    definition: definition,
                    initialVariables: vars,
                    handlers: actionHandlers
                )
            } else if let md = skill.sourceMarkdown, !md.isEmpty {
                SkillCompilationView(skill: skill)
            } else {
                ContentUnavailableView(
                    "Skill hat keine UI",
                    systemImage: "puzzlepiece.extension",
                    description: Text("\(skill.name) hat keine darstellbaren Screens.")
                )
            }
        }
    }

    // MARK: - iPad: NavigationSplitView (full sidebar)

    @State private var selectedSkill: Skill?

    private var iPadLayout: some View {
        NavigationSplitView {
            iPadSidebar
        } detail: {
            NavigationStack {
                if let skill = selectedSkill {
                    skillView(for: skill)
                        .navigationTitle(skill.name)
                } else {
                    tabContent(for: navState.selectedTab)
                        .navigationTitle(L(navState.selectedTab.localizationKey))
                }
            }
        }
    }

    private var iPadSidebar: some View {
        List {
            Section("Haupt") {
                ForEach([BrainTab.dashboard, .search, .chat, .mail], id: \.self) { tab in
                    Button { selectedSkill = nil; navState.selectedTab = tab } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .listRowBackground(navState.selectedTab == tab && selectedSkill == nil ? Color.accentColor.opacity(0.15) : nil)
                }
            }
            Section("Module") {
                ForEach(BrainTab.moreTabs, id: \.self) { tab in
                    Button { selectedSkill = nil; navState.selectedTab = tab } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .listRowBackground(navState.selectedTab == tab && selectedSkill == nil ? Color.accentColor.opacity(0.15) : nil)
                }
            }
            iPadSkillsSection
        }
        .navigationTitle("Brain")
        .task { loadActiveSkills() }
        .onReceive(NotificationCenter.default.publisher(for: .brainSkillsChanged)) { _ in
            loadActiveSkills()
        }
        .alert("Wusstest du?", isPresented: $showBrainFact) {
            Button("Cool!") { }
        } message: {
            Text(brainFact ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { showSettings = true } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                Button {
                    brainFact = BrainFacts.random()
                    showBrainFact = true
                } label: {
                    Label("Brain Fact", systemImage: "brain")
                }
            }
        }
    }

    @MainActor private var actionHandlers: [any ActionHandler] {
        CoreActionHandlers.all(data: dataBridge)
    }

    // Returns AnyView to prevent deeply nested opaque type chains that cause
    // compiler stack overflow during SIL lowering (ReplaceOpaqueTypesWithUnderlyingTypes).
    private func tabContent(for tab: BrainTab) -> AnyView {
        switch tab {
        case .dashboard:
            // Load dashboard from DB (may have been improved by Brain or user).
            // Fall back to code-defined BootstrapSkills.dashboard if no DB entry.
            let definition: SkillDefinition
            let lifecycle = SkillLifecycle(pool: dataBridge.db.pool)
            if let dbSkill = try? lifecycle.fetch(id: "dashboard"),
               let dbDef = dbSkill.toSkillDefinition() {
                definition = dbDef
            } else {
                definition = BootstrapSkills.dashboard
            }
            let vars = SkillContextProvider(dataBridge: dataBridge)
                .variables(forSkillId: "dashboard")
            return AnyView(SkillView(
                definition: definition,
                initialVariables: vars,
                handlers: actionHandlers
            ))
        case .search: return AnyView(SearchView(dataBridge: dataBridge))
        case .mail: return AnyView(MailTabView(dataBridge: dataBridge))
        case .calendar: return AnyView(CalendarTabView(dataBridge: dataBridge))
        case .files: return AnyView(FilesTabView(dataBridge: dataBridge))
        case .canvas: return AnyView(quickCaptureView)
        case .people: return AnyView(PeopleTabView())
        case .knowledgeGraph: return AnyView(KnowledgeGraphView())
        case .brainAdmin: return AnyView(SkillManagerView())
        case .chat: return AnyView(chatView)
        case .more: return AnyView(EmptyView()) // handled directly in iPhoneLayout
        }
    }

    // MARK: - Chat View (native, not skill-based)

    private var chatView: some View {
        ChatView(chatService: {
            let service = chatService ?? ChatService(pool: dataBridge.db.pool)
            service.setHandlers(actionHandlers)
            return service
        }(), showSettings: $showSettings)
    }

    // MARK: - Quick Capture (native, with DB write)

    private var quickCaptureView: some View {
        QuickCaptureView(dataBridge: dataBridge)
    }

    private func loadActiveSkills() {
        activeSkills = ((try? dataBridge.listSkills()) ?? [])
            .filter { $0.enabled && ($0.hasScreens || ($0.sourceMarkdown.map { !$0.isEmpty } ?? false)) }
    }

    // Load a skill definition from DB (user-modified or Brain-updated version).
    // Returns nil if not found — caller falls back to hardcoded BootstrapSkills.
    private func loadSkillDefinition(id: String) -> SkillDefinition? {
        guard let skills = try? dataBridge.listSkills(),
              let skill = skills.first(where: { $0.id == id && $0.enabled }),
              let definition = skill.toSkillDefinition() else {
            return nil
        }
        return definition
    }
}

// Used in NavigationLink destinations to prevent eager evaluation
// of heavy views (DB queries, framework init) when the List renders.
private struct LazyView<Content: View>: View {
    let build: () -> Content
    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }
    var body: some View {
        build()
    }
}

// Wrapper for sheet(item:) binding — Identifiable over an entry ID.
private struct EntryIdWrapper: Identifiable {
    let id: Int64
}
