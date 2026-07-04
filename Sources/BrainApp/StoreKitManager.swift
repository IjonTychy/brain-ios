import StoreKit
import os.log

// StoreKit 2 manager for brain-ios: 30-day trial + CHF 49.- one-time purchase.
// Product ID must match App Store Connect configuration.
@MainActor @Observable
final class StoreKitManager {

    static let productId = "com.example.brain-ios.lifetime"

    // Purchase state
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .loading
    private(set) var errorMessage: String?

    enum PurchaseState: Equatable {
        case loading
        case trial(daysRemaining: Int)
        case trialExpired
        case purchased
        case notPurchased
    }

    // Trial config
    static let trialDurationDays = 30
    private static let trialStartKey = "brainTrialStartDate"          // legacy UserDefaults key
    private static let trialStartKeychainKey = "brain-trial-start"    // survives reinstalls

    private let keychain = KeychainService()
    private let logger = Logger(subsystem: "com.example.brain-ios", category: "StoreKit")

    func startListening() {
        Task { await listenForTransactions() }
    }

    // MARK: - Public API

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productId])
            product = products.first
            await updatePurchaseState()
        } catch {
            logger.error("Failed to load products: \(error)")
            errorMessage = "Produkte konnten nicht geladen werden"
            purchaseState = .notPurchased
        }
    }

    func purchase() async {
        guard let product else {
            errorMessage = "Produkt nicht verfügbar"
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchaseState = .purchased
                logger.info("Purchase successful")
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Kauf wird verarbeitet..."
            @unknown default:
                break
            }
        } catch {
            logger.error("Purchase failed: \(error)")
            errorMessage = "Kauf fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchaseState()
    }

    var isFullAccess: Bool {
        switch purchaseState {
        case .purchased, .trial:
            return true
        case .loading, .trialExpired, .notPurchased:
            return false
        }
    }

    // MARK: - Trial Management

    // The trial start lives in the Keychain (thisDeviceOnly, no biometry) so a
    // simple app reinstall does not reset the 30-day window. Existing installs
    // with a UserDefaults-based start date are migrated on first read.
    var trialStartDate: Date? {
        if let stored = keychain.read(key: Self.trialStartKeychainKey),
           let interval = TimeInterval(stored) {
            return Date(timeIntervalSince1970: interval)
        }
        if let legacy = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date {
            try? keychain.save(key: Self.trialStartKeychainKey,
                               value: String(legacy.timeIntervalSince1970))
            return legacy
        }
        return nil
    }

    func startTrialIfNeeded() {
        guard trialStartDate == nil else { return }
        let now = Date()
        do {
            try keychain.save(key: Self.trialStartKeychainKey,
                              value: String(now.timeIntervalSince1970))
            logger.info("Trial started")
        } catch {
            // Keychain unavailable — degrade to UserDefaults instead of blocking the app
            UserDefaults.standard.set(now, forKey: Self.trialStartKey)
            logger.error("Trial start could not be stored in Keychain: \(error)")
        }
    }

    var trialDaysRemaining: Int {
        guard let start = trialStartDate else { return Self.trialDurationDays }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialDurationDays - elapsed)
    }

    var isTrialActive: Bool {
        trialDaysRemaining > 0
    }

    // MARK: - Internal

    private func updatePurchaseState() async {
        // Check for existing purchase
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productId {
                purchaseState = .purchased
                return
            }
        }

        // No purchase — check trial
        startTrialIfNeeded()
        let remaining = trialDaysRemaining
        if remaining > 0 {
            purchaseState = .trial(daysRemaining: remaining)
        } else {
            purchaseState = .trialExpired
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await updatePurchaseState()
            }
        }
    }

    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }
}
