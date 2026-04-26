import Foundation
import CoreGraphics

/// Per-run state owned by GameScene. Separated out so scenes / overlays can
/// mutate it without scene internals bleeding everywhere.
final class GameState {

    let challenge: Challenge
    private(set) var coinsCollected: Int = 0
    private(set) var hitsTaken: Int = 0
    private(set) var timeRemaining: TimeInterval
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var isGameOver: Bool = false
    private(set) var didWin: Bool = false
    private(set) var isPaused: Bool = false

    // Armor state (derived from purchased armor level at scene init).
    let hitsAllowed: Int
    var hitsRemaining: Int

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
        checkCoinChainWin()
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

    private func checkCoinChainWin() {
        if challenge.type == .coinChain, coinsCollected >= challenge.coinChainTarget {
            finish(won: true)
        }
    }

    /// Fraction [0,1] for UI progress bars. Meaning depends on challenge type.
    var progress: CGFloat {
        switch challenge.type {
        case .timeTrial:
            let total = challenge.timeTrialDuration
            return total > 0 ? CGFloat(1.0 - (timeRemaining / total)) : 0
        case .coinChain:
            let target = CGFloat(challenge.coinChainTarget)
            return target > 0 ? min(1.0, CGFloat(coinsCollected) / target) : 0
        case .obstacleCourse:
            // Each obstacle course is a fixed elapsed-time run (~30s).
            let target: TimeInterval = 30.0
            return CGFloat(min(1.0, elapsedTime / target))
        }
    }

    var progressLabel: String {
        switch challenge.type {
        case .timeTrial:
            return "\(Int(ceil(timeRemaining)))s"
        case .coinChain:
            return "\(coinsCollected)/\(challenge.coinChainTarget)"
        case .obstacleCourse:
            return "\(coinsCollected) coins"
        }
    }

    var starsEarned: Int {
        return StarRating.stars(forHitsTaken: hitsTaken, completed: didWin)
    }
}
