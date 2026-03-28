import SwiftUI
import BrainCore

// Self-Modifier Proposal UI: lists pending/applied/rejected proposals
// with approve/reject swipe actions and detail view.
struct ProposalView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var proposals: [Proposal] = []
    @State private var filterStatus: ProposalStatus? = nil
    @State private var selectedProposal: Proposal?
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            // Status filter
            Picker("Status", selection: $filterStatus) {
                Text("Alle").tag(ProposalStatus?.none)
                Text("Offen").tag(ProposalStatus?.some(.pending))
                Text("Angewendet").tag(ProposalStatus?.some(.applied))
                Text("Abgelehnt").tag(ProposalStatus?.some(.rejected))
            }
            .pickerStyle(.segmented)
            .padding()

            if proposals.isEmpty {
                ContentUnavailableView(
                    "Keine Vorschläge",
                    systemImage: "lightbulb.slash",
                    description: Text("Brain hat noch keine Verbesserungsvorschläge erstellt.")
                )
            } else {
                List {
                    ForEach(proposals) { proposal in
                        ProposalRow(proposal: proposal)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedProposal = proposal }
                            .swipeActions(edge: .trailing) {
                                if proposal.status == .pending {
                                    Button {
                                        applyProposal(proposal)
                                    } label: {
                                        Label("Anwenden", systemImage: "checkmark.circle")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if proposal.status == .pending {
                                    Button {
                                        rejectProposal(proposal)
                                    } label: {
                                        Label("Ablehnen", systemImage: "xmark.circle")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Vorschläge")
        .refreshable { loadProposals() }
        .onAppear { loadProposals() }
        .onChange(of: filterStatus) { _, _ in loadProposals() }
        .sheet(item: $selectedProposal) { proposal in
            ProposalDetailView(proposal: proposal, dataBridge: dataBridge) {
                loadProposals()
            }
        }
        .brainToast($toast)
    }

    private func loadProposals() {
        proposals = (try? dataBridge.listProposals(status: filterStatus)) ?? []
    }

    private func applyProposal(_ proposal: Proposal) {
        guard let id = proposal.id else { return }

        // Skill suggestion proposals → send prompt to chat and navigate there
        if let spec = proposal.changeSpec, spec.contains("skill_suggestion") {
            if let prompt = extractSkillPrompt(from: spec) {
                // Mark as applied
                _ = try? dataBridge.applyProposal(id: id)
                // Navigate to chat with the prompt
                NotificationCenter.default.post(
                    name: .brainNavigateTab,
                    object: nil,
                    userInfo: ["tab": "chat", "message": prompt]
                )
                withAnimation { toast = "Skill wird generiert..." }
                loadProposals()
                return
            }
        }

        if let updated = try? dataBridge.applyProposal(id: id) {
            withAnimation { toast = "'\(updated.title)' angewendet" }
            loadProposals()
        }
    }

    private func extractSkillPrompt(from changeSpec: String) -> String? {
        guard let data = changeSpec.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prompt = json["suggestedSkillPrompt"] as? String else {
            return nil
        }
        return prompt
    }

    private func rejectProposal(_ proposal: Proposal) {
        guard let id = proposal.id else { return }
        if let _ = try? dataBridge.rejectProposal(id: id) {
            withAnimation { toast = "Vorschlag abgelehnt" }
            loadProposals()
        }
    }
}

// MARK: - Proposal Row

private struct ProposalRow: View {
    let proposal: Proposal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(categoryLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.12), in: Capsule())

                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let created = proposal.createdAt {
                        Text(created.prefix(10))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let desc = proposal.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch proposal.status {
        case .pending: return "circle"
        case .approved: return "checkmark.circle"
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch proposal.status {
        case .pending: return .orange
        case .approved: return .blue
        case .applied: return .green
        case .rejected: return .red
        }
    }

    private var statusLabel: String {
        switch proposal.status {
        case .pending: return "Offen"
        case .approved: return "Genehmigt"
        case .applied: return "Angewendet"
        case .rejected: return "Abgelehnt"
        }
    }

    private var categoryLabel: String {
        switch proposal.category {
        case "A": return "Konfig"
        case "B": return "Prompt"
        case "C": return "Regel"
        default: return proposal.category
        }
    }

    private var categoryColor: Color {
        switch proposal.category {
        case "A": return .blue
        case "B": return .purple
        case "C": return .orange
        default: return .gray
        }
    }
}

// MARK: - Proposal Detail View

struct ProposalDetailView: View {
    let proposal: Proposal
    let dataBridge: DataBridge
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Vorschlag") {
                    LabeledContent("Titel", value: proposal.title)
                    if let desc = proposal.description, !desc.isEmpty {
                        Text(desc)
                    }
                    LabeledContent("Kategorie", value: categoryLabel)
                    LabeledContent("Status", value: statusLabel)
                    if let created = proposal.createdAt {
                        LabeledContent("Erstellt", value: String(created.prefix(16)))
                    }
                    if let applied = proposal.appliedAt {
                        LabeledContent("Angewendet", value: String(applied.prefix(16)))
                    }
                }

                if let spec = proposal.changeSpec, !spec.isEmpty {
                    Section("Änderung (JSON)") {
                        Text(prettyJSON(spec))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if let rollback = proposal.rollbackData, !rollback.isEmpty {
                    Section("Rollback-Daten") {
                        Text(prettyJSON(rollback))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if proposal.status == .pending {
                    Section {
                        Button {
                            if let id = proposal.id {
                                // Skill suggestion → navigate to chat with prompt
                                if let spec = proposal.changeSpec, spec.contains("skill_suggestion"),
                                   let data = spec.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let prompt = json["suggestedSkillPrompt"] as? String {
                                    _ = try? dataBridge.applyProposal(id: id)
                                    NotificationCenter.default.post(
                                        name: .brainNavigateTab,
                                        object: nil,
                                        userInfo: ["tab": "chat", "message": prompt]
                                    )
                                } else {
                                    _ = try? dataBridge.applyProposal(id: id)
                                }
                                onDismiss()
                                dismiss()
                            }
                        } label: {
                            let isSkillSuggestion = proposal.changeSpec?.contains("skill_suggestion") ?? false
                            Label(
                                isSkillSuggestion ? "Skill generieren" : "Anwenden",
                                systemImage: isSkillSuggestion ? "wand.and.stars" : "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)
                        }

                        Button(role: .destructive) {
                            if let id = proposal.id {
                                _ = try? dataBridge.rejectProposal(id: id)
                                onDismiss()
                                dismiss()
                            }
                        } label: {
                            Label("Ablehnen", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
        }
    }

    private var categoryLabel: String {
        switch proposal.category {
        case "A": return "Konfiguration"
        case "B": return "Prompt-Anpassung"
        case "C": return "Regel-Änderung"
        default: return proposal.category
        }
    }

    private var statusLabel: String {
        switch proposal.status {
        case .pending: return "Offen"
        case .approved: return "Genehmigt"
        case .applied: return "Angewendet"
        case .rejected: return "Abgelehnt"
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return result
    }
}
