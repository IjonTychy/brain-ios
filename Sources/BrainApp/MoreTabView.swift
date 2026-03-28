import SwiftUI
import BrainCore

// Dedicated View struct for the "Mehr" tab.
// Extracted from ContentView to give SwiftUI a clear, named type
// (computed properties with complex view hierarchies caused crashes).
struct MoreTabView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var activeSkills: [Skill] = []
    @Binding var showSettings: Bool

    var body: some View {
        List {
            Section {
                moreMenuItem(title: L("tab.calendar"), icon: "calendar") {
                    CalendarTabView(dataBridge: dataBridge)
                }
                moreMenuItem(title: L("tab.files"), icon: "folder") {
                    FilesTabView(dataBridge: dataBridge)
                }
                moreMenuItem(title: L("tab.capture"), icon: "note.text") {
                    QuickCaptureView(dataBridge: dataBridge)
                }
                moreMenuItem(title: L("tab.contacts"), icon: "person.2") {
                    PeopleTabView()
                }
                moreMenuItem(title: L("tab.graph"), icon: "circle.hexagongrid") {
                    KnowledgeGraphView()
                }
                moreMenuItem(title: L("tab.skills"), icon: "puzzlepiece.extension") {
                    SkillManagerView()
                }
            }

            if !activeSkills.isEmpty {
                Section("Skills") {
                    ForEach(activeSkills, id: \.id) { skill in
                        NavigationLink {
                            skillDestination(skill)
                        } label: {
                            Label {
                                Text(skill.name)
                            } icon: {
                                Image(systemName: skill.icon ?? "puzzlepiece.extension")
                                    .foregroundStyle(skill.color.flatMap { Color(hex: $0) } ?? .blue)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label {
                        Text(L("settings.title")).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(BrainTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle(L("tab.more"))
        .tint(BrainTheme.Colors.brandPurple)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrainHelpButton(context: "Mehr-Tab: Kalender, Dateien, Kontakte, Skills", screenName: "Mehr")
            }
        }
        .task { loadActiveSkills() }
        .onReceive(NotificationCenter.default.publisher(for: .brainSkillsChanged)) { _ in
            loadActiveSkills()
        }
    }

    // Each menu item is a NavigationLink whose destination is created
    // lazily via @ViewBuilder closure — only evaluated when tapped.
    private func moreMenuItem<Destination: View>(
        title: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .navigationTitle(title)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    @ViewBuilder
    private func skillDestination(_ skill: Skill) -> some View {
        if let definition = skill.toSkillDefinition() {
            // Skill has compiled screens — render with full variable context
            let vars = SkillContextProvider(dataBridge: dataBridge)
                .variables(for: skill)
            SkillView(
                definition: definition,
                initialVariables: vars,
                handlers: CoreActionHandlers.all(data: dataBridge)
            )
            .navigationTitle(skill.name)
        } else if let md = skill.sourceMarkdown, !md.isEmpty {
            // Skill has markdown but no screens — auto-compile via LLM
            SkillCompilationView(skill: skill)
                .navigationTitle(skill.name)
        } else {
            ContentUnavailableView(
                "Skill hat keine UI",
                systemImage: "puzzlepiece.extension",
                description: Text("\(skill.name) hat keine darstellbaren Screens und kein Quell-Markdown.")
            )
        }
    }

    private func loadActiveSkills() {
        // Show ALL enabled skills (including those with sourceMarkdown for on-demand compilation)
        // Filter out language skills — they provide labels, not UI
        activeSkills = ((try? dataBridge.listSkills()) ?? [])
            .filter { $0.enabled && !$0.id.hasPrefix("brain-language-") }
    }
}
