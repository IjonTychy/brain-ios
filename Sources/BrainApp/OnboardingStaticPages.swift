import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// MARK: - OnboardingView: Welcome, features and privacy pages
// Split out of OnboardingView.swift to keep compile units small.

extension OnboardingView {
    // MARK: - Page 1: Welcome

    var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(BrainTheme.Gradients.brand)
                .symbolEffect(.pulse)

            // Language selection
            Picker("Sprache", selection: Binding(
                get: { LocalizationService.shared.activeLocale },
                set: { newLang in
                    LocalizationService.shared.setLanguage(newLang, pool: dataBridge.db.pool)
                }
            )) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
                Text("Fran\u{00E7}ais").tag("fr")
                Text("Italiano").tag("it")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Text("Willkommen bei Brain")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Dein pers\u{00F6}nliches Gehirn auf dem iPhone.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            nextButton(page: 0)
        }
        .padding()
    }

    // MARK: - Page 2: Features

    var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Was Brain kann")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 20) {
                featureRow(icon: "brain", title: "Denkt mit", description: "KI-gestützte Analyse deiner Gedanken und Notizen")
                featureRow(icon: "magnifyingglass", title: "Findet alles", description: "Volltextsuche über alle Einträge und E-Mails")
                featureRow(icon: "lock.shield", title: "Deine Daten", description: "Alles bleibt auf deinem Gerät — kein Cloud-Zwang")
                featureRow(icon: "gearshape.2", title: "Lernt dazu", description: "Brain baut eigene Skills und verbessert sich selbst")
            }
            .padding(.horizontal)

            Spacer()

            nextButton(page: 1)
        }
        .padding()
    }

    // MARK: - Page 3: Privacy

    var privacyPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("Datenschutz")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    privacyRow(icon: "iphone", text: "Alle Daten bleiben lokal auf deinem Gerät")
                    privacyRow(icon: "key.fill", text: "API-Keys werden im iOS Keychain gespeichert")
                    privacyRow(icon: "network.slash", text: "Offline-Nutzung ohne Einschränkungen")
                    privacyRow(icon: "arrow.up.right.circle", text: "Nur wenn du fragst, geht etwas an die KI-API")
                }
                .padding(.horizontal)
            }

            Spacer()

            nextButton(page: 2)
        }
        .padding()
    }

    // MARK: - Components

    func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text).font(.callout)
        }
    }
}
