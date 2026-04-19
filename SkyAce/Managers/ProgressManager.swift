import Foundation

/// Persisted player progress. UserDefaults-backed. IAP entitlement is
/// cached here for fast synchronous reads, but the source of truth is
/// `IAPManager.verifyEntitlement()` (StoreKit 2 transaction check).
final class ProgressManager {

    static let shared = ProgressManager()

    // MARK: - Keys
    private enum Key {
        static let coins               = "skyace.coins"
        static let completedLevels     = "skyace.completedLevels"
        static let starRatings         = "skyace.starRatings"
        static let ownedPlanes         = "skyace.ownedPlanes"
        static let selectedPlane       = "skyace.selectedPlane"
        static let upgradeLevels       = "skyace.upgradeLevels"
        static let fullUnlockCached    = "skyace.fullUnlockCached"
        static let musicEnabled        = "skyace.musicEnabled"
        static let sfxEnabled          = "skyace.sfxEnabled"
    }

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.coins:            0,
            Key.completedLevels:  [Int](),
            Key.starRatings:      [String: Int](),
            Key.ownedPlanes:      ["blue_sky_chaser"],
            Key.selectedPlane:    "blue_sky_chaser",
            Key.upgradeLevels:    [String: Int](),
            Key.fullUnlockCached: false,
            Key.musicEnabled:     true,
            Key.sfxEnabled:       true
        ])
    }

    // MARK: - Coins

    var coins: Int {
        get { defaults.integer(forKey: Key.coins) }
        set { defaults.set(max(0, newValue), forKey: Key.coins) }
    }

    func addCoins(_ amount: Int) {
        coins = coins + amount
    }

    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard coins >= amount else { return false }
        coins = coins - amount
        return true
    }

    // MARK: - Levels

    var completedLevelIDs: Set<Int> {
        let arr = defaults.array(forKey: Key.completedLevels) as? [Int] ?? []
        return Set(arr)
    }

    func isLevelCompleted(_ id: Int) -> Bool {
        return completedLevelIDs.contains(id)
    }

    func markLevelCompleted(_ id: Int, stars: Int) {
        var set = completedLevelIDs
        set.insert(id)
        defaults.set(Array(set), forKey: Key.completedLevels)

        // Keep the best star rating.
        let existing = starsForLevel(id)
        if stars > existing {
            var ratings = defaults.dictionary(forKey: Key.starRatings) as? [String: Int] ?? [:]
            ratings[String(id)] = stars
            defaults.set(ratings, forKey: Key.starRatings)
        }
    }

    func starsForLevel(_ id: Int) -> Int {
        let ratings = defaults.dictionary(forKey: Key.starRatings) as? [String: Int] ?? [:]
        return ratings[String(id)] ?? 0
    }

    /// A level is progression-unlocked if it is level 1 OR the previous level
    /// was completed. Paywall is enforced separately.
    func isLevelProgressionUnlocked(_ id: Int) -> Bool {
        if id <= 1 { return true }
        return isLevelCompleted(id - 1)
    }

    // MARK: - Planes

    var ownedPlaneIDs: Set<String> {
        let arr = defaults.array(forKey: Key.ownedPlanes) as? [String] ?? []
        return Set(arr)
    }

    func ownsPlane(_ id: String) -> Bool {
        return ownedPlaneIDs.contains(id)
    }

    func purchasePlane(_ id: String) {
        var set = ownedPlaneIDs
        set.insert(id)
        defaults.set(Array(set), forKey: Key.ownedPlanes)
    }

    var selectedPlaneID: String {
        get { defaults.string(forKey: Key.selectedPlane) ?? "blue_sky_chaser" }
        set { defaults.set(newValue, forKey: Key.selectedPlane) }
    }

    // MARK: - Upgrades

    func upgradeLevel(for id: String) -> Int {
        let dict = defaults.dictionary(forKey: Key.upgradeLevels) as? [String: Int] ?? [:]
        return dict[id] ?? 0
    }

    func setUpgradeLevel(_ level: Int, for id: String) {
        var dict = defaults.dictionary(forKey: Key.upgradeLevels) as? [String: Int] ?? [:]
        dict[id] = level
        defaults.set(dict, forKey: Key.upgradeLevels)
    }

    // MARK: - Full Unlock cache
    // Written by IAPManager after StoreKit entitlement verification.
    // Read by scenes for synchronous gating decisions.

    var isFullUnlockCached: Bool {
        get { defaults.bool(forKey: Key.fullUnlockCached) }
        set { defaults.set(newValue, forKey: Key.fullUnlockCached) }
    }

    // MARK: - Audio toggles

    var musicEnabled: Bool {
        get { defaults.bool(forKey: Key.musicEnabled) }
        set { defaults.set(newValue, forKey: Key.musicEnabled) }
    }

    var sfxEnabled: Bool {
        get { defaults.bool(forKey: Key.sfxEnabled) }
        set { defaults.set(newValue, forKey: Key.sfxEnabled) }
    }

    // MARK: - Reset (debug only)
    #if DEBUG
    func resetAllProgress() {
        [Key.coins, Key.completedLevels, Key.starRatings, Key.ownedPlanes,
         Key.selectedPlane, Key.upgradeLevels, Key.fullUnlockCached].forEach {
            defaults.removeObject(forKey: $0)
        }
        registerDefaults()
    }
    #endif
}
