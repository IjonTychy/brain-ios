import SwiftUI
import EventKit
import BrainCore

// Native calendar tab: week/day view with EventKit integration.
// Replaces the simple BootstrapSkills.calendar SkillView.
struct CalendarTabView: View {
    let dataBridge: DataBridge
    @State private var selectedDate = Date()
    @State private var events: [EventInfo] = []
    @State private var accessState: EventKitBridge.CalendarAccessState = .notDetermined
    @State private var showCreateEvent = false
    @State private var viewMode: CalendarViewMode = .week

    @State private var bridge = EventKitBridge()

    enum CalendarViewMode: String, CaseIterable {
        case day = "Tag"
        case week = "Woche"
        case month = "Monat"
    }

    var body: some View {
        VStack(spacing: 0) {
            if accessState == .denied {
                ContentUnavailableView(
                    "Kein Kalender-Zugriff",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Bitte erlaube den Kalender-Zugriff in den Einstellungen.")
                )
            } else {
                // View mode picker
                Picker("Ansicht", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .sensoryFeedback(.selection, trigger: viewMode)

                // Date navigation
                dateNavigationBar

                // Calendar strip (week view)
                if viewMode == .week || viewMode == .day {
                    weekStrip
                }

                // Events list
                eventsList
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrainHelpButton(context: "Kalender: Termine, Wochen/Monatsansicht, Erstellen", screenName: "Kalender")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        selectedDate = Date()
                        loadEvents()
                    } label: {
                        Text("Heute")
                            .font(.subheadline)
                    }
                    Button {
                        showCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            accessState = bridge.calendarAccessState()
            if accessState == .notDetermined {
                _ = try? await bridge.requestCalendarAccess()
                accessState = bridge.calendarAccessState()
            }
            loadEvents()
        }
        .onChange(of: selectedDate) { _, _ in
            loadEvents()
        }
        .onChange(of: viewMode) { _, _ in
            loadEvents()
        }
        .sheet(isPresented: $showCreateEvent) {
            NavigationStack {
                CreateEventView(bridge: bridge) {
                    loadEvents()
                }
            }
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationBar: some View {
        HStack {
            Button {
                withAnimation(BrainTheme.Animations.springSnappy) { navigateBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(BrainTheme.Colors.brandPurple)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                    .contentTransition(.numericText())
                if viewMode != .day {
                    Text(yearText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation(BrainTheme.Animations.springSnappy) { navigateForward() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(BrainTheme.Colors.brandPurple)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var headerTitle: String {
        switch viewMode {
        case .day:
            return Self.dayHeaderFormatter.string(from: selectedDate)
        case .week:
            let weekStart = calendar.startOfWeek(for: selectedDate)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let startMonth = Self.shortMonthFormatter.string(from: weekStart)
            let endMonth = Self.shortMonthFormatter.string(from: weekEnd)
            if startMonth == endMonth {
                return startMonth
            }
            return "\(startMonth) – \(endMonth)"
        case .month:
            return Self.monthYearFormatter.string(from: selectedDate)
        }
    }

    private var yearText: String {
        Self.yearFormatter.string(from: selectedDate)
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        let weekStart = calendar.startOfWeek(for: selectedDate)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(day)

                    Button {
                        selectedDate = day
                    } label: {
                        VStack(spacing: 4) {
                            Text(Self.weekdayFormatter.string(from: day))
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white : .secondary)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.callout)
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundStyle(isSelected ? .white : (isToday ? BrainTheme.Colors.brandBlue : .primary))
                            HStack(spacing: 2) {
                                let dayColors = uniqueCalendarColors(for: day)
                                if dayColors.isEmpty {
                                    Circle().fill(Color.clear).frame(width: 5, height: 5)
                                } else {
                                    ForEach(dayColors.prefix(3), id: \.self) { hex in
                                        let dotColor: Color = isSelected ? .white : (Color(hex: hex) ?? .blue)
                                        Circle()
                                            .fill(dotColor)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                            }
                        }
                        .frame(width: 44, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? AnyShapeStyle(BrainTheme.Gradients.brand) : AnyShapeStyle(Color.clear))
                                .shadow(color: isSelected ? BrainTheme.Colors.brandPurple.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                        )
                        .animation(BrainTheme.Animations.springSnappy, value: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Month Grid

    // MARK: - Events List

    private var eventsList: some View {
        Group {
            if viewMode == .month {
                monthEventsList
            } else {
                dayEventsList
            }
        }
    }

    private var dayEventsList: some View {
        let dayEvents = eventsForDate(selectedDate)
        return List {
            if dayEvents.isEmpty {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(BrainTheme.Gradients.brand)
                            .symbolEffect(.pulse, options: .speed(0.5))
                        Text("Keine Termine")
                            .font(.title3.weight(.semibold))
                        Text(Self.dayHeaderFormatter.string(from: selectedDate) + " ist frei.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section(Self.dayHeaderFormatter.string(from: selectedDate)) {
                    ForEach(dayEvents, id: \.identifier) { event in
                        EventRowView(event: event)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var monthEventsList: some View {
        let daysInMonth = daysWithEventsInMonth()
        return List {
            if daysInMonth.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Keine Termine",
                        systemImage: "calendar",
                        description: Text("Keine Termine in diesem Monat.")
                    )
                }
            } else {
                ForEach(daysInMonth, id: \.date) { dayGroup in
                    Section(Self.sectionHeaderFormatter.string(from: dayGroup.date)) {
                        ForEach(dayGroup.events, id: \.identifier) { event in
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Data

    private var calendar: Calendar { Calendar.current }

    private func loadEvents() {
        let range = dateRange()
        Task { @MainActor in
            let loaded = bridge.listEvents(from: range.start, to: range.end, limit: 200)
            events = loaded
        }
    }

    private func dateRange() -> (start: Date, end: Date) {
        switch viewMode {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        case .week:
            let weekStart = calendar.startOfWeek(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            return (weekStart, end)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: selectedDate)
            let monthStart = calendar.date(from: comps) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return (monthStart, end)
        }
    }

    private func eventsForDate(_ date: Date) -> [EventInfo] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func dayHasEvents(_ date: Date) -> Bool {
        events.contains { calendar.isDate($0.startDate, inSameDayAs: date) }
    }

    private func uniqueCalendarColors(for date: Date) -> [String] {
        let dayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
        var seen = Set<String>()
        return dayEvents.compactMap { event in
            let hex = event.calendarColorHex
            guard !seen.contains(hex) else { return nil }
            seen.insert(hex)
            return hex
        }
    }

    private struct DayGroup {
        let date: Date
        let events: [EventInfo]
    }

    private func daysWithEventsInMonth() -> [DayGroup] {
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return grouped.keys.sorted().map { date in
            DayGroup(date: date, events: grouped[date]?.sorted { $0.startDate < $1.startDate } ?? [])
        }
    }

    private func navigateBack() {
        switch viewMode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    private func navigateForward() {
        switch viewMode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Formatters

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "MMMM"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "EE"
        return f
    }()

    private static let sectionHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()
}

// MARK: - Event Row

private struct EventRowView: View {
    let event: EventInfo

    /// Parse calendar color from EventKit hex string
    private var calendarColor: Color {
        Color(hex: event.calendarColorHex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color bar (uses actual iOS calendar color)
            RoundedRectangle(cornerRadius: 2)
                .fill(calendarColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if event.isAllDay {
                        Text("Ganztaegig")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Self.timeFormatter.string(from: event.startDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("–")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(Self.timeFormatter.string(from: event.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "location")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(event.calendarName)
                .font(.caption2)
                .foregroundStyle(calendarColor)
        }
        .padding(.vertical, 4)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Create Event View

struct CreateEventView: View {
    let bridge: EventKitBridge
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var isAllDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Termin") {
                TextField("Titel", text: $title)
                Toggle("Ganztaegig", isOn: $isAllDay)
                DatePicker("Beginn", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ende", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
            }

            Section("Details") {
                TextField("Ort", text: $location)
                TextField("Notizen", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Neuer Termin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") {
                    createEvent()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        }
    }

    private func createEvent() {
        do {
            _ = try bridge.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes.isEmpty ? nil : notes,
                location: location.isEmpty ? nil : location
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// Color(hex:) extension defined in ContentView.swift
