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
    private static let trialStartKey = "brainTrialStartDate"

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

    var trialStartDate: Date? {
        UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date
    }

    func startTrialIfNeeded() {
        if UserDefaults.standard.object(forKey: Self.trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.trialStartKey)
            logger.info("Trial started")
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
