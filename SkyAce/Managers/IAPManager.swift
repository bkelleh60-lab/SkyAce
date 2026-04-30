import Foundation
import StoreKit

/// StoreKit 2 wrapper for the single non-consumable full-unlock product.
///
/// Contract:
///   - Entitlement is verified against `Transaction.currentEntitlement(for:)`
///     on every launch. Never trust UserDefaults alone.
///   - ProgressManager.isFullUnlockCached is a synchronous-read cache only.
///   - A background transaction listener handles revokes and family-sharing
///     updates mid-session.
@MainActor
final class IAPManager: ObservableObject {

    static let shared = IAPManager()

    static let fullUnlockProductID = "com.skyace.fullunlock"

    /// Posted on the main actor whenever the verified entitlement transitions
    /// (`false → true` or `true → false`). UIKit-native subscription point for
    /// long-lived consumers that need to refresh mid-session.
    static let entitlementDidChange = Notification.Name("IAPEntitlementDidChange")

    @Published private(set) var product: Product?
    @Published private(set) var isFullyUnlocked: Bool = false
    @Published private(set) var isLoadingProduct: Bool = false
    @Published private(set) var lastError: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        // Seed from cache for the first frame; real value is set by verify().
        self.isFullyUnlocked = ProgressManager.shared.isFullUnlockCached
        self.transactionListener = makeTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    /// Call once at launch from AppDelegate.
    func bootstrap() async {
        await loadProduct()
        await verifyEntitlement()
    }

    /// Fetches the product from the App Store.
    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.fullUnlockProductID])
            self.product = products.first
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Authoritative check — StoreKit 2. Updates the cache on success.
    func verifyEntitlement() async {
        let unlocked = await currentlyOwnsFullUnlock()
        let didChange = unlocked != self.isFullyUnlocked
        self.isFullyUnlocked = unlocked
        ProgressManager.shared.isFullUnlockCached = unlocked
        if didChange {
            NotificationCenter.default.post(name: Self.entitlementDidChange, object: self)
        }
    }

    /// Runs the purchase flow for the full unlock. Caller is responsible for
    /// having presented the parental gate first.
    @discardableResult
    func purchase() async -> PurchaseResult {
        guard let product = product else {
            await loadProduct()
            guard let loaded = self.product else {
                return .failed("Product unavailable.")
            }
            return await performPurchase(loaded)
        }
        return await performPurchase(product)
    }

    /// User-initiated restore. Re-syncs with the App Store, then re-verifies.
    @discardableResult
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
        await verifyEntitlement()
        return isFullyUnlocked
    }

    /// Localized price string ("$2.99") — falls back to hard-coded default.
    var displayPrice: String {
        return product?.displayPrice ?? "$2.99"
    }

    /// Paywall accessor for UI / scene gating. Returns the verified StoreKit
    /// entitlement in Release builds. In Debug builds the
    /// `debugUnlockAllContent` flag (see DebugConfig.swift) can short-circuit
    /// this to `true` so QA can reach locked content. The StoreKit code path
    /// above is untouched — this only affects the synchronous read used by
    /// scenes to draw locked vs unlocked UI.
    var isContentUnlocked: Bool {
        #if DEBUG
        if debugUnlockAllContent { return true }
        #endif
        return isFullyUnlocked
    }

    // MARK: - Internals

    private func performPurchase(_ product: Product) async -> PurchaseResult {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await verifyEntitlement()
                    return .success
                case .unverified(_, let error):
                    return .failed("Could not verify purchase: \(error.localizedDescription)")
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    #if DEBUG
    /// Test-only hook. Sets the cached entitlement bit and posts the
    /// transition notification when the value actually changes — the same
    /// contract `verifyEntitlement()` uses in production. Lets unit tests
    /// observe `entitlementDidChange` without going through StoreKit.
    func setFullyUnlockedForTesting(_ value: Bool) {
        let didChange = value != self.isFullyUnlocked
        self.isFullyUnlocked = value
        if didChange {
            NotificationCenter.default.post(name: Self.entitlementDidChange, object: self)
        }
    }
    #endif

    private func currentlyOwnsFullUnlock() async -> Bool {
        guard let result = await Transaction.currentEntitlement(for: Self.fullUnlockProductID) else {
            return false
        }
        switch result {
        case .verified(let transaction):
            return transaction.revocationDate == nil
        case .unverified:
            return false
        }
    }

    private func makeTransactionListener() -> Task<Void, Never> {
        return Task.detached(priority: .background) {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await MainActor.run {
                        Task { await IAPManager.shared.verifyEntitlement() }
                    }
                }
            }
        }
    }
}

enum PurchaseResult {
    case success
    case cancelled
    case pending
    case failed(String)
}
