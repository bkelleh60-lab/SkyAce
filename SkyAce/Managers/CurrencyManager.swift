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

    private init() {}

    // MARK: - Read-only getters

    var coinTotal: Int { defaults.integer(forKey: Key.coinTotal) }
    var ringTotal: Int { defaults.integer(forKey: Key.ringTotal) }

    // MARK: - Mutations

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        let new = coinTotal + amount
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
}
