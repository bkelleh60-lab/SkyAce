import Foundation

/// Lightweight in-memory + UserDefaults currency tracker for the Free Flight
/// HUD. Coins and rings are two independent counters with no exchange rate
/// or relative weighting — each pickup increments its own total only.
final class CurrencyManager {

    static let shared = CurrencyManager()

    private enum Key {
        static let coinTotal = "skyace.currency.coinTotal"
        static let ringTotal = "skyace.currency.ringTotal"
        /// Coins earned from Landing Practice on `landingPracticeLastEarnDate`
        /// (SKY-95). Key string is fixed by the ticket spec.
        static let landingPracticeCoinsToday = "skyace.landingPracticeCoinsToday"
        /// Local calendar day (`yyyy-MM-dd`) the `landingPracticeCoinsToday`
        /// counter belongs to (SKY-95). Key string is fixed by the ticket spec.
        static let landingPracticeLastEarnDate = "skyace.landingPracticeLastEarnDate"
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

    // MARK: - Landing Practice daily reward (SKY-95)

    /// Coins granted per smooth landing in Landing Practice.
    static let landingPracticeSmoothLandingReward = 50
    /// Maximum coins earnable from Landing Practice in a single calendar day.
    static let landingPracticeDailyCoinCap = 500

    /// Coins already earned from Landing Practice today, or 0 if the stored
    /// earn date isn't today (a new day, or none recorded yet). Reading this
    /// also defines the "reset at midnight local time" behavior: the counter is
    /// scoped to the local calendar day string, so the first earn after
    /// midnight sees a non-matching date and starts fresh.
    var landingPracticeCoinsEarnedToday: Int {
        guard defaults.string(forKey: Key.landingPracticeLastEarnDate)
                == Self.localDateString(for: Date()) else { return 0 }
        return defaults.integer(forKey: Key.landingPracticeCoinsToday)
    }

    /// Grants the smooth-landing reward unless today's Landing Practice cap is
    /// already reached, crediting it to the player's spendable coin balance.
    /// Returns the amount granted (0 when the cap blocks it, so callers can
    /// suppress the reward indicator). Rough and crash landings never call this.
    ///
    /// The reward lands in `ProgressManager.coins` — the persistent, spendable
    /// balance the home top bar, Hangar, and Shop read from and spend against —
    /// so a smooth landing actually enriches the player. (It deliberately does
    /// *not* credit this manager's HUD-only `coinTotal`: no player-facing
    /// balance screen reads that store, so crediting it left the reward pill
    /// animating while the real balance never moved — SKY-106.)
    @discardableResult
    func grantLandingPracticeSmoothLandingReward() -> Int {
        let reward = Self.landingPracticeSmoothLandingReward
        let earnedToday = landingPracticeCoinsEarnedToday
        // All-or-nothing per landing: only grant if the full reward fits under
        // the cap. The cap (500) is an exact multiple of the reward (50), so
        // this never leaves an unreachable remainder.
        guard earnedToday + reward <= Self.landingPracticeDailyCoinCap else { return 0 }

        defaults.set(earnedToday + reward, forKey: Key.landingPracticeCoinsToday)
        defaults.set(Self.localDateString(for: Date()), forKey: Key.landingPracticeLastEarnDate)
        ProgressManager.shared.addCoins(reward)
        return reward
    }

    /// Local-calendar date as an ISO `yyyy-MM-dd` string. Uses the current time
    /// zone so the daily cap resets at local midnight, and a fixed POSIX
    /// locale/Gregorian calendar so the format is stable regardless of device
    /// locale settings.
    private static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    #if DEBUG
    /// Test-only helper. Wipes both totals plus the Landing Practice daily
    /// bookkeeping from UserDefaults so each test starts from a known state.
    func resetForTesting() {
        defaults.removeObject(forKey: Key.coinTotal)
        defaults.removeObject(forKey: Key.ringTotal)
        defaults.removeObject(forKey: Key.landingPracticeCoinsToday)
        defaults.removeObject(forKey: Key.landingPracticeLastEarnDate)
    }
    #endif
}
