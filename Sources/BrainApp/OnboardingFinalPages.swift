import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// MARK: - OnboardingView: Permissions, get-to-know and first entry pages
// Split out of OnboardingView.swift to keep compile units small.

extension OnboardingView {
    // MARK: - Page 7: Permissions

    var permissionsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Berechtigungen")
                .font(.title)
                .fontWeight(.bold)

            Text("Brain funktioniert auch ohne — aber mit Zugriff kann es mehr.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                permissionButton(
                    icon: "person.crop.circle",
                    title: "Kontakte",
                    description: "Personen in Brain verknüpfen",
                    granted: contactsGranted
                ) {
                    await requestContacts()
                }

                permissionButton(
                    icon: "calendar",
                    title: "Kalender",
                    description: "Termine und Erinnerungen anzeigen",
                    granted: calendarGranted
                ) {
                    await requestCalendar()
                }

                permissionButton(
                    icon: "bell.fill",
                    title: "Benachrichtigungen",
                    description: "Erinnerungen und Briefings erhalten",
                    granted: notificationsGranted
                ) {
                    await requestNotifications()
                }
            }
            .padding(.horizontal)

            Spacer()

            nextButton(page: 6, title: "Weiter")
        }
        .padding()
    }

    // MARK: - Page 8: Kennenlernen

    var kennenlernPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.wave.2")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            VStack(spacing: 12) {
                Text("Brain kennenlernen")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Brain kann Dich in einem kurzen Interview besser kennenlernen. So gibt es Dir persönlichere und hilfreichere Antworten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 12) {
                kennenlernFeature(icon: "brain.head.profile", text: "Brain fragt nach Name, Beruf, Hobbys und mehr")
                kennenlernFeature(icon: "lock.shield", text: "Antworten bleiben lokal auf deinem Gerät")
                kennenlernFeature(icon: "arrow.clockwise", text: "Jederzeit wiederholbar und aktualisierbar")
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showKennenlernSheet = true
                } label: {
                    Text("Interview starten")
                        .font(BrainTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrainTheme.Colors.brandPurple)
                .padding(.horizontal)

                Button {
                    focusedField = nil
                    withAnimation { currentPage = 8 }
                } label: {
                    Text("Überspringen")
                }
                .foregroundStyle(.secondary)

                Text("Du findest das Interview jederzeit unter\nMehr → Kennenlernen oder frag Brain im Chat:\n«Lerne mich kennen»")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    func kennenlernFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.purple)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Page 9: First Entry

    var firstEntryPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Dein erster Gedanke")
                .font(.title)
                .fontWeight(.bold)

            Text("Schreib einfach drauflos. Brain merkt sich alles.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Was beschäftigt dich gerade?", text: $firstThought, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .padding(.horizontal)
                .focused($focusedField, equals: .firstThought)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    focusedField = nil
                    Task { await saveAndFinish() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(firstThought.isEmpty ? "Los geht's!" : "Speichern & Los geht's!")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    @ViewBuilder
    func permissionButton(
        icon: String, title: String, description: String,
        granted: Bool, action: @escaping () async -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Erlauben") {
                    Task { await action() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func requestContacts() async {
        let store = CNContactStore()
        do {
            contactsGranted = try await store.requestAccess(for: .contacts)
        } catch {
            contactsGranted = false
        }
    }

    func requestCalendar() async {
        let store = EKEventStore()
        do {
            calendarGranted = try await store.requestFullAccessToEvents()
        } catch {
            calendarGranted = false
        }
    }

    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            notificationsGranted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            notificationsGranted = false
        }
    }

    func saveAndFinish() async {
        focusedField = nil
        isSaving = true
        defer { isSaving = false }

        if !firstThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try? dataBridge.createEntry(title: firstThought)
        }

        hasCompletedOnboarding = true
    }
}
