import Foundation
import StoreKit

public enum SubscriptionTier: String, Sendable {
    case free
    case pro
}

@MainActor
@Observable
public final class SubscriptionManager {
    public static let shared = SubscriptionManager()

    // Product IDs
    public static let monthlyProductID = "com.willhammond.tether.pro.monthly"
    public static let yearlyProductID = "com.willhammond.tether.pro.yearly"

    // Free tier limits
    public static let freeHistoryDays = 30
    public static let freeMaxFriends = 3

    // Trial
    public static let trialDurationDays = 14
    private let trialStartKey = "com.willhammond.tether.trialStartDate"

    public private(set) var tier: SubscriptionTier = .free
    public private(set) var products: [Product] = []
    public private(set) var purchasedProductIDs: Set<String> = []
    public private(set) var isLoading = false

    public var isPro: Bool { tier == .pro }
    public var isTrialActive: Bool {
        guard let start = trialStartDate else { return false }
        let elapsed = Date().timeIntervalSince(start)
        return elapsed < TimeInterval(Self.trialDurationDays * 86400)
    }

    public var trialDaysRemaining: Int {
        guard let start = trialStartDate else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = Self.trialDurationDays - Int(elapsed / 86400)
        return max(0, remaining)
    }

    private var trialStartDate: Date? {
        get { UserDefaults.standard.object(forKey: trialStartKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: trialStartKey) }
    }

    private var updateListenerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    public func start() async {
        // Start trial on first launch if not started
        if trialStartDate == nil {
            trialStartDate = Date()
        }

        // Listen for transaction updates
        updateListenerTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.handleVerified(transaction)
                    await transaction.finish()
                }
            }
        }

        await loadProducts()
        await updateEntitlements()
    }

    public func stop() {
        updateListenerTask?.cancel()
        updateListenerTask = nil
    }

    // MARK: - Products

    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [
                Self.monthlyProductID,
                Self.yearlyProductID,
            ])
        } catch {
            TetherLogger.general.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    public func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await handleVerified(transaction)
                await transaction.finish()
                return true
            }
            return false
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    public func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await updateEntitlements()
    }

    // MARK: - Entitlements

    private func updateEntitlements() async {
        var purchasedIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    purchasedIDs.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchasedIDs
        tier = purchasedIDs.isEmpty ? (isTrialActive ? .pro : .free) : .pro
    }

    private func handleVerified(_ transaction: Transaction) async {
        purchasedProductIDs.insert(transaction.productID)
        tier = .pro

        // Sync with backend
        do {
            try await APIClient.shared.requestVoid(
                .subscriptionVerify,
                method: "POST",
                body: [
                    "original_transaction_id": String(transaction.originalID),
                    "product_id": transaction.productID,
                ]
            )
        } catch {
            TetherLogger.general.error("Failed to sync subscription: \(error.localizedDescription)")
        }

        AnalyticsService.shared.track(.subscriptionStarted, parameters: [
            "productId": transaction.productID,
        ])
    }

    // MARK: - Free Tier Enforcement

    public func canAccessFullHistory() -> Bool {
        isPro || isTrialActive
    }

    public func canAddMoreFriends(currentCount: Int) -> Bool {
        isPro || isTrialActive || currentCount < Self.freeMaxFriends
    }

    public func isBlockingFullyAvailable() -> Bool {
        isPro || isTrialActive
    }

    // MARK: - Product Helpers

    public var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    public var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductID }
    }
}
