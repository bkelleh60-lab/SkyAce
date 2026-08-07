import Foundation
import CoreGraphics

/// Per-run state owned by GameScene. Separated out so scenes / overlays can
/// mutate it without scene internals bleeding everywhere.
final class GameState {

    let challenge: Challenge
    private(set) var coinsCollected: Int = 0
    /// Total coins that spawned during this run. Used as the denominator
    /// for the star-rating coin percentage at finish. Spawning is dynamic
    /// (no fixed level total), so the scene increments this as it places
    /// coin nodes — coins that flew past uncollected still count as
    /// "available," which is the desired semantics.
    private(set) var totalCoinsSpawned: Int = 0
    private(set) var hitsTaken: Int = 0
    private(set) var timeRemaining: TimeInterval
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var isGameOver: Bool = false
    private(set) var didWin: Bool = false
    private(set) var isPaused: Bool = false

    // Armor state (derived from purchased armor level at scene init).
    let hitsAllowed: Int
    var hitsRemaining: Int

    // MARK: - Big-ring streak (SKY-63)

    /// Consecutive big rings flown through without a miss. Drives the escalating
    /// bonus and the on-screen streak indicator; reset when a ring scrolls off
    /// uncollected.
    private(set) var bigRingStreak = 0
    /// Total big rings collected this run (stat / potential results use).
    private(set) var bigRingsCollected = 0

    init(challenge: Challenge) {
        self.challenge = challenge
        self.timeRemaining = challenge.timeTrialDuration
        let armor = ProgressManager.shared.upgradeLevel(for: UpgradeKind.armor.rawValue)
        self.hitsAllowed = UpgradeFormulas.hitsAllowed(armorLevel: armor)
        self.hitsRemaining = self.hitsAllowed
    }

    // MARK: - Mutations

    func collectCoin() {
        coinsCollected += 1
    }

    func registerCoinSpawned(count: Int = 1) {
        totalCoinsSpawned += count
    }

    /// Registers a big-ring fly-through: advances the streak and returns the
    /// coin bonus (`baseBonus * newStreak` — Ring 1 = base, Ring 2 = 2·base, …).
    /// The bonus is folded into both the collected and spawned coin tallies, so
    /// it enriches the run's visible coin count without skewing the collection
    /// ratio the star rating grades — the bonus is fully "collected" of what it
    /// adds, keeping the invariant `coinsCollected <= totalCoinsSpawned`.
    @discardableResult
    func collectBigRing(baseBonus: Int) -> Int {
        bigRingStreak += 1
        bigRingsCollected += 1
        let bonus = max(0, baseBonus) * bigRingStreak
        coinsCollected += bonus
        totalCoinsSpawned += bonus
        return bonus
    }

    /// Resets the streak after a missed ring (one that scrolled off screen
    /// uncollected).
    func resetBigRingStreak() {
        bigRingStreak = 0
    }

    /// Returns true if the plane is dead (run should end).
    func registerHit() -> Bool {
        if hitsRemaining > 0 {
            hitsRemaining -= 1
            return false
        }
        hitsTaken += 1
        finish(won: false)
        return true
    }

    func advanceTime(_ delta: TimeInterval) {
        guard !isGameOver, !isPaused else { return }
        elapsedTime += delta

        if challenge.type == .timeTrial {
            timeRemaining = max(0, timeRemaining - delta)
            if timeRemaining <= 0 {
                finish(won: true)
            }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func finish(won: Bool) {
        guard !isGameOver else { return }
        isGameOver = true
        didWin = won
    }

    // MARK: - Derived

    /// Fraction [0,1] for UI progress bars. Meaning depends on challenge type.
    var progress: CGFloat {
        switch challenge.type {
        case .timeTrial:
            let total = challenge.timeTrialDuration
            return total > 0 ? CGFloat(1.0 - (timeRemaining / total)) : 0
        case .obstacleCourse, .coinChain:
            let target = challenge.levelDuration
            return target > 0 ? CGFloat(min(1.0, elapsedTime / target)) : 0
        }
    }

    var progressLabel: String {
        switch challenge.type {
        case .timeTrial:
            return "\(Int(ceil(timeRemaining)))s"
        case .obstacleCourse, .coinChain:
            return "\(coinsCollected) coins"
        }
    }

    /// Time still on the clock relative to the level's expected duration.
    /// Drives the 3★ "time remaining" bonus for every mission type.
    var levelTimeRemaining: TimeInterval {
        return max(0, challenge.levelDuration - elapsedTime)
    }

    var starsEarned: Int {
        return StarRating.stars(
            completed: didWin,
            coinsCollected: coinsCollected,
            totalCoins: totalCoinsSpawned,
            timeRemaining: levelTimeRemaining
        )
    }
}
