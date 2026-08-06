import Foundation
import UIKit
import GameKit

/// Apple Game Center integration (SKY-68). Owns local-player authentication and
/// achievement reporting. Game Center is Apple-native — no third-party SDK, no
/// PII, no server infrastructure — so it is fully compliant with the App Store
/// Kids Category requirements this app ships under.
///
/// Achievement *rules* (which achievements a given game state earns, and the
/// progress percentage of the progressive ones) live in the pure
/// `AchievementRules` enum below so they can be unit-tested without GameKit.
/// This manager is the thin GameKit-facing layer: it derives the current
/// achievement state from the persistent managers, deduplicates reports, and
/// hands them to GameKit once the player is authenticated.
final class GameCenterManager {

    static let shared = GameCenterManager()

    /// Game Center achievement identifiers. These strings must exactly match
    /// the achievement identifiers registered in App Store Connect before the
    /// achievements will surface for players.
    enum Achievement: String, CaseIterable {
        case firstFlight   = "com.skyace.achievement.first_flight"
        case clearSkies    = "com.skyace.achievement.clear_skies"
        case stormChaser   = "com.skyace.achievement.storm_chaser"
        case acePilot      = "com.skyace.achievement.ace_pilot"
        case coinCollector = "com.skyace.achievement.coin_collector"
        case richBaron     = "com.skyace.achievement.rich_baron"
        case untouchable   = "com.skyace.achievement.untouchable"
        case speedRun      = "com.skyace.achievement.speed_run"
        case chainReaction = "com.skyace.achievement.chain_reaction"
        case freeSpirit    = "com.skyace.achievement.free_spirit"
        case upgraded      = "com.skyace.achievement.upgraded"
        case fullKit       = "com.skyace.achievement.full_kit"
    }

    /// True once the local player has authenticated with Game Center. Reporting
    /// is a no-op until this flips true; anything earned while unauthenticated
    /// is persisted locally and flushed the moment authentication succeeds.
    private(set) var isAuthenticated = false

    private let defaults = UserDefaults.standard

    private enum Key {
        /// One-time achievements the player has earned locally (raw identifier
        /// strings). Persisted so run-only achievements (Untouchable, Speed Run,
        /// Chain Reaction) — which can't be re-derived from stored state —
        /// survive to be flushed to Game Center after a later authentication.
        static let earned = "skyace.gamecenter.earnedAchievements"
        /// Highest percentage already reported to Game Center per achievement
        /// id. Lets progressive reports skip no-op resends and never regress.
        static let reportedPercent = "skyace.gamecenter.reportedPercent"
    }

    /// Presenter for the Game Center sign-in sheet, captured at authentication
    /// time. Weak — GameKit may invoke the handler long after launch, and we
    /// must not keep the root view controller alive.
    private weak var authPresenter: UIViewController?

    private init() {}

    // MARK: - Authentication

    /// Wires up `GKLocalPlayer.local.authenticateHandler`. Call once at launch.
    /// GameKit invokes the handler immediately if a session exists, or hands
    /// back a sign-in view controller to present. Presenting that sheet is
    /// standard Apple behavior and does not require a parental gate (SKY-68).
    func authenticate(presentingFrom presenter: UIViewController?) {
        authPresenter = presenter
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            guard let self = self else { return }
            if let viewController = viewController {
                // Not yet signed in — GameKit provides the sign-in UI. Present
                // it from the app's root; the player (or parent) can complete
                // or dismiss it. Dismissal simply leaves the game unauthenticated.
                self.authPresenter?.present(viewController, animated: true)
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            // Flush anything earned before authentication completed.
            if self.isAuthenticated { self.refreshProgress() }
        }
    }

    // MARK: - Public reporting entry points

    /// Reports achievements unlocked by winning a mission run. Call only on a
    /// win. Covers the run-specific achievements (Untouchable, Speed Run, Chain
    /// Reaction) using per-run data the persistent managers don't retain, then
    /// re-derives every progress-based achievement from the now-updated
    /// `ProgressManager` state. The caller must have already committed the run
    /// (star rating, coins) to `ProgressManager` before calling.
    func reportMissionWin(challenge: Challenge,
                          tookAnyHit: Bool,
                          coinsCollected: Int,
                          totalCoinsSpawned: Int,
                          timeRemaining: TimeInterval) {
        let runEarned = AchievementRules.runAchievements(
            challengeType: challenge.type,
            tookAnyHit: tookAnyHit,
            coinsCollected: coinsCollected,
            totalCoinsSpawned: totalCoinsSpawned,
            timeRemaining: timeRemaining
        )
        markEarned(runEarned)
        refreshProgress()
    }

    /// Re-derives and reports every achievement that can be computed from the
    /// current persistent state (level completion, star totals, lifetime coins,
    /// Free Flight sessions, upgrades) plus any locally-earned run achievements.
    /// Safe to call at any rest point — it deduplicates against what has already
    /// been reported. No-op below the GameKit layer until authenticated.
    func refreshProgress() {
        let pm = ProgressManager.shared
        let starsByLevel = Dictionary(
            uniqueKeysWithValues: ChallengeCatalog.all.map { ($0.id, pm.starsForLevel($0.id)) }
        )
        let upgradeLevels = Dictionary(
            uniqueKeysWithValues: UpgradeKind.allCases.map { ($0, pm.upgradeLevel(for: $0.rawValue)) }
        )

        // One-time achievements derivable from persistent state.
        let derived = AchievementRules.stateAchievements(
            completedLevelIDs: pm.completedLevelIDs,
            starsByLevel: starsByLevel,
            upgradeLevels: upgradeLevels
        )
        markEarned(derived)

        // Progressive achievements (id → percent complete).
        let progress = AchievementRules.progressiveAchievements(
            lifetimeCoinsEarned: pm.lifetimeCoinsEarned,
            freeFlightSessionsCompleted: pm.freeFlightSessionsCompleted
        )

        var toReport: [Achievement: Double] = [:]
        for achievement in earnedSet() { toReport[achievement] = 100 }
        for (achievement, percent) in progress {
            // A progressive achievement that has hit 100 is also an earned
            // one-timer; keep the max so it can't be walked back.
            toReport[achievement] = max(toReport[achievement] ?? 0, percent)
        }

        submit(toReport)
    }

    // MARK: - Local earned-state bookkeeping

    private func earnedSet() -> Set<Achievement> {
        let raw = defaults.array(forKey: Key.earned) as? [String] ?? []
        return Set(raw.compactMap(Achievement.init(rawValue:)))
    }

    private func markEarned(_ achievements: Set<Achievement>) {
        guard !achievements.isEmpty else { return }
        let updated = earnedSet().union(achievements)
        defaults.set(updated.map { $0.rawValue }, forKey: Key.earned)
    }

    // MARK: - GameKit submission

    /// Sends the given achievements to Game Center, skipping any whose target
    /// percentage has already been reported (so we never resend a completed
    /// one-timer or regress a progressive bar). No-op until authenticated —
    /// the earned state is already persisted, so a later `refreshProgress()`
    /// after sign-in will pick it up.
    private func submit(_ percentByAchievement: [Achievement: Double]) {
        guard isAuthenticated else { return }

        var reported = reportedPercentMap()
        var payload: [GKAchievement] = []
        for (achievement, percent) in percentByAchievement {
            let clamped = min(100, max(0, percent))
            if let last = reported[achievement.rawValue], last >= clamped { continue }
            let gk = GKAchievement(identifier: achievement.rawValue)
            gk.percentComplete = clamped
            gk.showsCompletionBanner = true
            payload.append(gk)
            reported[achievement.rawValue] = clamped
        }
        guard !payload.isEmpty else { return }

        GKAchievement.report(payload) { [weak self] error in
            guard let self = self, error == nil else { return }
            // Persist the reported watermarks only on success so a failed send
            // is retried on the next refresh rather than silently dropped.
            self.defaults.set(reported, forKey: Key.reportedPercent)
        }
    }

    private func reportedPercentMap() -> [String: Double] {
        defaults.dictionary(forKey: Key.reportedPercent) as? [String: Double] ?? [:]
    }

    #if DEBUG
    /// Test-only reset of the local reporting bookkeeping.
    func resetForTesting() {
        defaults.removeObject(forKey: Key.earned)
        defaults.removeObject(forKey: Key.reportedPercent)
        isAuthenticated = false
    }
    #endif
}

/// Pure achievement-derivation logic for SKY-68. Kept free of GameKit and of
/// singletons so the win-condition mapping can be unit-tested directly. Every
/// threshold lives here as a named constant; the ticket flags these for tuning
/// against playtest data before App Store Connect submission.
enum AchievementRules {

    // MARK: - Tunable thresholds

    /// Lifetime coins for Coin Collector.
    static let coinCollectorThreshold = 500
    /// Lifetime coins for Rich Baron.
    static let richBaronThreshold = 2_000
    /// Seconds still on the clock at completion for Speed Run.
    static let speedRunSecondsRemaining: TimeInterval = 30
    /// Completed Free Flight sessions for Free Spirit.
    static let freeSpiritSessionTarget = 10

    // MARK: - One-time achievements from persistent state

    /// One-time achievements derivable from stored progress: First Flight,
    /// Clear Skies, Storm Chaser, Ace Pilot, Upgraded, Full Kit.
    /// `starsByLevel` maps a level id to its best star rating (0–3);
    /// `upgradeLevels` maps each upgrade track to its current level.
    static func stateAchievements(
        completedLevelIDs: Set<Int>,
        starsByLevel: [Int: Int],
        upgradeLevels: [UpgradeKind: Int]
    ) -> Set<GameCenterManager.Achievement> {
        var earned: Set<GameCenterManager.Achievement> = []

        if !completedLevelIDs.isEmpty { earned.insert(.firstFlight) }

        func allThreeStars(_ ids: [Int]) -> Bool {
            !ids.isEmpty && ids.allSatisfy { (starsByLevel[$0] ?? 0) >= 3 }
        }
        let chapterOneIDs = ChallengeCatalog.all.filter { $0.chapter == .clearSkies }.map { $0.id }
        let chapterTwoIDs = ChallengeCatalog.all.filter { $0.chapter == .stormChaser }.map { $0.id }
        let allIDs = ChallengeCatalog.all.map { $0.id }
        if allThreeStars(chapterOneIDs) { earned.insert(.clearSkies) }
        if allThreeStars(chapterTwoIDs) { earned.insert(.stormChaser) }
        if allThreeStars(allIDs)        { earned.insert(.acePilot) }

        if upgradeLevels.values.contains(where: { $0 > 0 }) { earned.insert(.upgraded) }
        if UpgradeKind.allCases.contains(where: { (upgradeLevels[$0] ?? 0) >= $0.maxLevel }) {
            earned.insert(.fullKit)
        }

        return earned
    }

    // MARK: - Progressive achievements

    /// Progressive achievements as id → percent-complete (0–100): Coin
    /// Collector, Rich Baron, Free Spirit.
    static func progressiveAchievements(
        lifetimeCoinsEarned: Int,
        freeFlightSessionsCompleted: Int
    ) -> [GameCenterManager.Achievement: Double] {
        func percent(_ value: Int, _ target: Int) -> Double {
            guard target > 0 else { return 0 }
            return min(100, Double(value) / Double(target) * 100)
        }
        return [
            .coinCollector: percent(lifetimeCoinsEarned, coinCollectorThreshold),
            .richBaron:     percent(lifetimeCoinsEarned, richBaronThreshold),
            .freeSpirit:    percent(freeFlightSessionsCompleted, freeSpiritSessionTarget)
        ]
    }

    // MARK: - Run-specific achievements

    /// One-time achievements earned by the outcome of a single mission *win*:
    /// Untouchable, Speed Run, Chain Reaction. Call only for winning runs.
    ///
    /// Note on Speed Run: `timeRemaining` is time left against the level's
    /// expected duration. Because a time-trial is completed by surviving its
    /// full countdown, this threshold is expected to be tuned (and the trigger
    /// mechanic revisited) against playtest data before submission — the ticket
    /// explicitly defers threshold tuning.
    static func runAchievements(
        challengeType: ChallengeType,
        tookAnyHit: Bool,
        coinsCollected: Int,
        totalCoinsSpawned: Int,
        timeRemaining: TimeInterval
    ) -> Set<GameCenterManager.Achievement> {
        var earned: Set<GameCenterManager.Achievement> = []

        if !tookAnyHit { earned.insert(.untouchable) }

        if challengeType == .timeTrial, timeRemaining >= speedRunSecondsRemaining {
            earned.insert(.speedRun)
        }

        if challengeType == .coinChain, totalCoinsSpawned > 0, coinsCollected >= totalCoinsSpawned {
            earned.insert(.chainReaction)
        }

        return earned
    }
}
