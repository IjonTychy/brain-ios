import SwiftUI
import BrainCore

// MARK: - Quick Capture View

struct QuickCaptureView: View {
    let dataBridge: DataBridge
    @State private var captureText = ""
    @State private var entryType = "thought"
    @State private var savedToast: String?
    @State private var recentEntries: [Entry] = []
    @State private var parsedInput: ParsedInput?
    @FocusState private var isTextFocused: Bool

    private let entryTypes = ["thought", "task", "note", "event"]
    private let typeLabels = ["thought": "Gedanke", "task": "Aufgabe", "note": "Notiz", "event": "Termin"]

    var body: some View {
        VStack(spacing: 16) {
            // Type picker
            Picker("Typ", selection: $entryType) {
                ForEach(entryTypes, id: \.self) { type in
                    Text(typeLabels[type] ?? type).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Input with NLP preview
            TextField("Was beschäftigt dich?", text: $captureText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .focused($isTextFocused)
                .accessibilityIdentifier("capture.textField")
                .accessibilityLabel("Schnell-Eingabe")
                .onChange(of: captureText) { _, newValue in
                    if newValue.count >= 3 {
                        let parsed = NLPInputParser.parse(newValue)
                        parsedInput = parsed
                        // Auto-select type based on NLP
                        entryType = parsed.type.rawValue
                    } else {
                        parsedInput = nil
                    }
                }

            // NLP Parse Preview
            if let parsed = parsedInput, !captureText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(BrainTheme.Colors.brandPurple)
                        .font(.caption2)
                    Text(parsed.parseSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

            // Save button
            Button {
                saveEntry()
            } label: {
                Label("Speichern", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Toast
            // Toast is handled by .brainToast modifier

            Divider()

            // Recent entries with swipe (including delete)
            if !recentEntries.isEmpty {
                List {
                    Section("Letzte Einträge") {
                        ForEach(recentEntries) { entry in
                            SearchResultRow(entry: entry)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if let id = entry.id {
                                            try? dataBridge.deleteEntry(id: id)
                                            loadRecent()
                                        }
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                    if entry.type == .task && entry.status == .active {
                                        Button {
                                            if let id = entry.id {
                                                _ = try? dataBridge.markDone(id: id)
                                                loadRecent()
                                            }
                                        } label: {
                                            Label("Erledigt", systemImage: "checkmark")
                                        }
                                        .tint(.green)
                                    }
                                    Button {
                                        if let id = entry.id {
                                            _ = try? dataBridge.archiveEntry(id: id)
                                            loadRecent()
                                        }
                                    } label: {
                                        Label("Archiv", systemImage: "archivebox")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            Spacer()
        }
        .padding(.top)
        .onAppear { loadRecent() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrainHelpButton(context: "Quick Capture: Gedanken, Aufgaben, Notizen schnell erfassen", screenName: "Quick Capture")
            }
        }
        .brainToast($savedToast)
        .animation(.easeInOut(duration: 0.2), value: parsedInput != nil)
    }

    private func saveEntry() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            let parsed = NLPInputParser.parse(text)
            let entry = try dataBridge.createEntry(title: parsed.title, type: entryType)

            // Auto-tag with extracted tags
            if let entryId = entry.id {
                for tag in parsed.tags {
                    try? dataBridge.addTag(entryId: entryId, tagName: tag)
                }
            }

            // Auto-create calendar event if date+time were detected and type is event/task
            if let date = parsed.date, (entryType == "event" || parsed.time != nil) {
                Task {
                    await createCalendarEvent(title: parsed.title, date: date, time: parsed.time)
                }
            }

            captureText = ""
            parsedInput = nil
            let typeName = typeLabels[entryType] ?? "Entry"
            var toastMsg = "\(typeName) gespeichert!"
            if parsed.date != nil && parsed.time != nil {
                toastMsg += " Termin erstellt."
            }
            savedToast = toastMsg
            loadRecent()

            // Auto-dismiss toast
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { savedToast = nil }
            }
        } catch {
            savedToast = "Fehler: \(error.localizedDescription)"
        }
    }

    private func loadRecent() {
        recentEntries = (try? dataBridge.listEntries(limit: 10)) ?? []
    }

    // Auto-create calendar event when NLP detects date+time
    private func createCalendarEvent(title: String, date: Date, time: String?) async {
        let bridge = EventKitBridge()
        guard (try? await bridge.requestCalendarAccess()) == true else { return }

        var eventDate = date
        if let time, let colonIdx = time.firstIndex(of: ":") {
            let hour = Int(time[time.startIndex..<colonIdx]) ?? 0
            let minute = Int(time[time.index(after: colonIdx)...]) ?? 0
            eventDate = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        let endDate = eventDate.addingTimeInterval(3600) // 1 hour default duration
        _ = try? bridge.createEvent(title: title, startDate: eventDate, endDate: endDate)
    }
}

// Native contacts view with alphabet sections, detail navigation, and actions.
// PeopleTabView, ContactRow, ContactDetailView moved to PeopleTabView.swift

// MARK: - Color hex init (shared across views)


// MARK: - LazyView

// Defers creation of the wrapped view until it actually appears.
// Used in NavigationLink destinations to prevent eager evaluation
// of heavy views (DB queries, framework init) when the List renders.
