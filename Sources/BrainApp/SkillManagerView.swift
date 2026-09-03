import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BrainCore

// Skill management view: list, enable/disable, share, import, delete installed skills.
// Replaces the static Brain Admin skill with a native SwiftUI interface.
struct SkillManagerView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var selectedGroup: String = "Alle"
    @State private var editingSkill: Skill?
    @State private var editSource: String = ""
    @State private var skills: [Skill] = []
    @State private var showImporter = false
    @State private var shareItem: ShareableSkillFile?
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var skillToDelete: Skill?
    @State private var pendingImportMarkdown: String?
    @State private var showConfetti = false
    @State private var showSkillCreator = false

    // Body extracted into sections to reduce opaque type nesting depth.
    var body: some View {
        List {
            skillsListSection
            selfModifierSection
            featuresSection
            Section("System") { systemStatsView }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    BrainHelpButton(context: "Skills: Installieren, Verwalten, Teilen, Löschen", screenName: "Skills")
                    BrainAvatarButton(context: .skills)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showSkillCreator = true } label: {
                        Label("Skill erstellen", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("skills.createButton")
                    Button { showImporter = true } label: {
                        Label("Importieren", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("skills.importButton")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(isPresented: $showSkillCreator) {
            NavigationStack {
                BrainAssistantSheet(context: .skillCreator)
            }
        }
        .refreshable { loadSkills() }
        .confirmationDialog(
            "Skill löschen?",
            isPresented: Binding(get: { skillToDelete != nil }, set: { if !$0 { skillToDelete = nil } }),
            presenting: skillToDelete
        ) { skill in
            Button("Löschen", role: .destructive) { deleteSkill(skill) }
        } message: { skill in
            Text("\"\(skill.name)\" wird unwiderruflich entfernt.")
        }
        .onAppear { loadSkills() }
        .onReceive(NotificationCenter.default.publisher(for: .brainSkillsChanged)) { _ in
            loadSkills()
        }
        .sheet(isPresented: Binding(get: { pendingImportMarkdown != nil }, set: { if !$0 { pendingImportMarkdown = nil } })) {
            if let markdown = pendingImportMarkdown {
                SkillImportPreview(markdown: markdown) { confirmImport() } onCancel: { pendingImportMarkdown = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toast { toastBanner(msg, color: .green) }
            if let err = errorMessage { toastBanner(err, color: .red) }
        }
        .animation(.easeInOut, value: toast)
        .animation(.easeInOut, value: errorMessage)
        .confettiOverlay(isActive: showConfetti)
        .onChange(of: showConfetti) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showConfetti = false }
            }
        }
    }

    // MARK: - Extracted List Sections

    private var skillsListSection: some View {
        Section {
            if skills.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundStyle(BrainTheme.Gradients.brand)
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Keine Skills installiert")
                        .font(.title3.weight(.semibold))
                    Text("Importiere .brainskill.md Dateien oder lasse Brain neue Skills erstellen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(BrainTheme.Spacing.xl)
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                    NavigationLink {
                        SkillDetailSettingsView(
                            skill: skill,
                            onToggle: { toggleSkill(id: skill.id, enabled: $0) },
                            onShare: { shareSkill(skill) },
                            onDelete: { skillToDelete = skill }
                        )
                    } label: {
                        skillRowLabel(skill)
                    }
                }
            }
        } header: {
            HStack {
                Text("Skills")
                Spacer()
                Text("\(skills.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func skillRowLabel(_ skill: Skill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: skill.icon ?? "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill((skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue).opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder((skill.color.flatMap { Color(hex: $0) } ?? BrainTheme.Colors.brandBlue).opacity(0.2), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name).font(.body)
                if let desc = skill.description {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if skill.enabled == false {
                Text("Aus").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var selfModifierSection: some View {
        Section("Self-Modifier") {
            NavigationLink { RulesView() } label: { Label("Regeln", systemImage: "gearshape.2") }
            NavigationLink { ProposalView() } label: { Label("Verbesserungsvorschläge", systemImage: "lightbulb") }
        }
    }

    private var featuresSection: some View {
        Section("Features") {
            NavigationLink { UserProfileView() } label: { Label("Mein Profil", systemImage: "person.text.rectangle") }
            NavigationLink { BrainProfileView() } label: { Label("Brain Profil", systemImage: "brain.head.profile") }
            NavigationLink { KennenlernDialogView() } label: { Label("Kennenlernen", systemImage: "person.2.wave.2") }
            NavigationLink { OnThisDayView() } label: { Label("An diesem Tag", systemImage: "clock.arrow.circlepath") }
            NavigationLink { BackupView() } label: { Label("Datensicherung", systemImage: "externaldrive") }
        }
    }

    // MARK: - System Stats

    private var systemStatsView: some View {
        Group {
            HStack {
                Label("Einträge", systemImage: "doc.text")
                Spacer()
                Text("\(dataBridge.entryCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Tags", systemImage: "tag")
                Spacer()
                Text("\(dataBridge.tagCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Verknüpfungen", systemImage: "link")
                Spacer()
                Text("\(dataBridge.linkCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("DB Grösse", systemImage: "internaldrive")
                Spacer()
                Text(dataBridge.db.approximateSize())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toast

    private func toastBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.gradient)
            .clipShape(Capsule())
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { toast = nil; errorMessage = nil }
    }

    // MARK: - Actions

    private func loadSkills() {
        dataBridge.refreshDashboard()
        skills = (try? dataBridge.listSkills()) ?? []
    }

    private func toggleSkill(id: String, enabled: Bool) {
        do {
            // Language skills: use exclusive toggle (only one active at a time)
            if id.hasPrefix("brain-language-") {
                let locale = String(id.dropFirst("brain-language-".count))
                LocalizationService.shared.setLanguage(enabled ? locale : "de", pool: dataBridge.db.pool)
                loadSkills()
                return
            }
            try dataBridge.setSkillEnabled(id: id, enabled: enabled)
            loadSkills()
        } catch {
            showError("Fehler: \(error.localizedDescription)")
        }
    }

    private func shareSkill(_ skill: Skill) {
        do {
            let markdown = try dataBridge.exportSkill(id: skill.id)
            let fileName = "\(skill.id).brainskill.md"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            shareItem = ShareableSkillFile(url: tempURL)
        } catch {
            showError("Export fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func confirmDeleteSkills(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        skillToDelete = skills[index]
    }

    private func deleteSkill(_ skill: Skill) {
        do {
            try dataBridge.uninstallSkill(id: skill.id)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            loadSkills()
            showToast("\"\(skill.name)\" gelöscht")
        } catch {
            showError("Löschen fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                showError("Kein Zugriff auf die Datei")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                pendingImportMarkdown = markdown
            } catch {
                showError("Datei konnte nicht gelesen werden: \(error.localizedDescription)")
            }
        case .failure(let error):
            showError("Datei-Auswahl fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func confirmImport() {
        guard let markdown = pendingImportMarkdown else { return }
        do {
            let skill = try dataBridge.importSkillFromMarkdown(markdown)
            loadSkills()
            showToast("\"\(skill.name)\" importiert")
            showConfetti = true
        } catch {
            showError("Import fehlgeschlagen: \(error.localizedDescription)")
        }
        pendingImportMarkdown = nil
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { toast = nil }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { errorMessage = nil }
        }
    }
}
