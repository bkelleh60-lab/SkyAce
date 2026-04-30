import Foundation

/// Lightweight in-memory + UserDefaults currency tracker for the Free Flight
/// HUD. Coins and rings are two independent counters with no exchange rate
/// or relative weighting — each pickup increments its own total only.
final class CurrencyManager {

    static let shared = CurrencyManager()

    private enum Key {
        static let coinTotal = "skyace.currency.coinTotal"
        static let ringTotal = "skyace.currency.ringTotal"
    }

    /// Posted whenever `coinTotal` changes. `userInfo["total"]` carries the
    /// new Int total so HUDs can update without polling.
    static let coinTotalDidChange = Notification.Name("CurrencyManager.coinTotalDidChange")
    /// Posted whenever `ringTotal` changes. `userInfo["total"]` carries the
    /// new Int total.
    static let ringTotalDidChange = Notification.Name("CurrencyManager.ringTotalDidChange")

    private let defaults = UserDefaults.standard

    /// Indirection so unit tests can simulate free vs premium without
    /// reaching into StoreKit. Production reads the synchronous entitlement
    /// cache that IAPManager writes after StoreKit verification, honoring
    /// the `debugUnlockAllContent` bypass so QA builds behave like premium.
    var isContentUnlockedProvider: () -> Bool = CurrencyManager.defaultUnlockProvider

    private static let defaultUnlockProvider: () -> Bool = {
        #if DEBUG
        if debugUnlockAllContent { return true }
        #endif
        return ProgressManager.shared.isFullUnlockCached
    }

    private init() {}

    // MARK: - Read-only getters

    var coinTotal: Int { defaults.integer(forKey: Key.coinTotal) }
    var ringTotal: Int { defaults.integer(forKey: Key.ringTotal) }

    // MARK: - Mutations

    /// Maximum coins a free player can accumulate.
    static let freeCoinCap = 1_000

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        let new: Int
        if isContentUnlockedProvider() {
            new = coinTotal + amount
        } else {
            new = min(coinTotal + amount, CurrencyManager.freeCoinCap)
        }
        defaults.set(new, forKey: Key.coinTotal)
        NotificationCenter.default.post(
            name: CurrencyManager.coinTotalDidChange,
            object: self,
            userInfo: ["total": new]
        )
    }

    func addRings(_ amount: Int) {
        guard amount > 0 else { return }
        let new = ringTotal + amount
        defaults.set(new, forKey: Key.ringTotal)
        NotificationCenter.default.post(
            name: CurrencyManager.ringTotalDidChange,
            object: self,
            userInfo: ["total": new]
        )
    }

    /// Deducts coins for in-game purchases. Returns `false` and leaves the
    /// balance untouched if the player does not have enough. Posts
    /// `coinTotalDidChange` on success.
    @discardableResult
    func deductCoins(_ amount: Int) -> Bool {
        guard amount > 0 else { return false }
        let current = coinTotal
        guard current >= amount else { return false }
        let new = current - amount
        defaults.set(new, forKey: Key.coinTotal)
        NotificationCenter.default.post(
            name: CurrencyManager.coinTotalDidChange,
            object: self,
            userInfo: ["total": new]
        )
        return true
    }

    #if DEBUG
    /// Test-only helper. Wipes both totals from UserDefaults and restores the
    /// default unlock provider so each test starts from a known state.
    func resetForTesting() {
        defaults.removeObject(forKey: Key.coinTotal)
        defaults.removeObject(forKey: Key.ringTotal)
        isContentUnlockedProvider = CurrencyManager.defaultUnlockProvider
    }
    #endif
}
