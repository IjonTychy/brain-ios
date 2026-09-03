import SwiftUI
import BrainCore
import Contacts
import EventKit
import UserNotifications

// Full onboarding flow for first-time users.
// Pages: Welcome → Features → Privacy → Provider Selection → API Key → Mail Wizard → Permissions → First Entry
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(DataBridge.self) var dataBridge

    @State var currentPage = 0
    // Provider selection
    @State var selectedProvider: LLMProviderChoice = .anthropic
    @State var apiKey = ""
    @State var isValidatingKey = false
    @State var keyValidationResult: KeyValidationResult?
    // Proxy config
    @State var proxyURL = ""
    // Permissions
    @State var contactsGranted = false
    @State var calendarGranted = false
    @State var notificationsGranted = false
    @State var firstThought = ""
    @State var isSaving = false
    // Mail wizard state
    @State var mailWizardStep: MailWizardStep = .provider
    @State var mailProvider: MailProvider = .none
    @State var mailAddress = ""
    @State var mailPassword = ""
    @State var mailImapHost = ""
    @State var mailImapPort = "993"
    @State var mailSmtpHost = ""
    @State var mailSmtpPort = "587"
    @State var isSavingMail = false
    @State var mailSaveResult: KeyValidationResult?
    @State var showKennenlernSheet = false
    @FocusState var focusedField: OnboardingField?

    let keychain = KeychainService()

    enum OnboardingField {
        case apiKey, proxyURL
        case firstThought, mailAddress, mailPassword
        case mailImapHost, mailSmtpHost
    }

    let totalPages = 9

    // Explicit initializer: keeps the public entry point stable now that the
    // page state is internal (shared with the page extensions in other files).
    init(hasCompletedOnboarding: Binding<Bool>) {
        _hasCompletedOnboarding = hasCompletedOnboarding
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                    .background(BrainTheme.Gradients.purpleMist.ignoresSafeArea())
                featuresPage.tag(1)
                    .background(BrainTheme.Gradients.freshMint.ignoresSafeArea())
                privacyPage.tag(2)
                providerSelectionPage.tag(3)
                apiKeyPage.tag(4)
                mailWizardPage.tag(5)
                permissionsPage.tag(6)
                kennenlernPage.tag(7)
                firstEntryPage.tag(8)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(BrainTheme.Animations.springDefault, value: currentPage)

            // Page indicator at the very bottom, below all buttons
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? BrainTheme.Colors.brandPurple : Color(.systemGray4))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(BrainTheme.Animations.springSnappy, value: currentPage)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focusedField = nil }
        .onChange(of: currentPage) { _, _ in focusedField = nil }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrainHelpButton.onboarding
            }
        }
        .sheet(isPresented: $showKennenlernSheet) {
            NavigationStack {
                KennenlernDialogView()
                    .environment(dataBridge)
                    .navigationTitle("Kennenlernen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { showKennenlernSheet = false }
                        }
                    }
            }
        }
    }

    func nextButton(page: Int, title: String = "Weiter") -> some View {
        Button {
            focusedField = nil
            withAnimation { currentPage = page + 1 }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
    }

    func validationBanner(_ result: KeyValidationResult) -> some View {
        HStack {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isSuccess ? .green : .red)
            Text(result.message)
                .font(.caption)
                .foregroundStyle(result.isSuccess ? .green : .red)
        }
    }
}

// MARK: - Supporting types

struct KeyValidationResult {
    let isSuccess: Bool
    let message: String
}

enum LLMProviderChoice: String, CaseIterable {
    case anthropic
    case openAI
    case gemini
    case xAI
    case proxy
}
