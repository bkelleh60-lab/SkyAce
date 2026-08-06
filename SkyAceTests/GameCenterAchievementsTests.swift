import XCTest
@testable import SkyAce

/// Unit tests for the pure achievement-derivation rules (SKY-68). GameKit and
/// authentication aren't exercised here — only the win-condition → achievement
/// mapping, which is where the game logic lives.
final class GameCenterAchievementsTests: XCTestCase {

    private typealias A = GameCenterManager.Achievement

    // Helpers -----------------------------------------------------------------

    /// Star map awarding `stars` to every level id in `range`.
    private func stars(_ stars: Int, forLevels range: ClosedRange<Int>) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: range.map { ($0, stars) })
    }

    private var allLevelIDs: [Int] { ChallengeCatalog.all.map { $0.id } }
    private var chapterOneIDs: [Int] { ChallengeCatalog.all.filter { $0.chapter == .clearSkies }.map { $0.id } }
    private var chapterTwoIDs: [Int] { ChallengeCatalog.all.filter { $0.chapter == .stormChaser }.map { $0.id } }

    // MARK: - First Flight

    func testFirstFlight_notEarnedWithNoCompletions() {
        let earned = AchievementRules.stateAchievements(
            completedLevelIDs: [], starsByLevel: [:], upgradeLevels: [:]
        )
        XCTAssertFalse(earned.contains(.firstFlight))
    }

    func testFirstFlight_earnedAfterAnyCompletion() {
        let earned = AchievementRules.stateAchievements(
            completedLevelIDs: [1], starsByLevel: [:], upgradeLevels: [:]
        )
        XCTAssertTrue(earned.contains(.firstFlight))
    }

    // MARK: - Chapter three-star achievements

    func testClearSkies_requiresAllChapterOneThreeStarred() {
        // Two stars on chapter one → not earned.
        var earned = AchievementRules.stateAchievements(
            completedLevelIDs: Set(allLevelIDs),
            starsByLevel: stars(2, forLevels: 1...5),
            upgradeLevels: [:]
        )
        XCTAssertFalse(earned.contains(.clearSkies))

        // Three stars on every chapter-one level → earned.
        earned = AchievementRules.stateAchievements(
            completedLevelIDs: Set(allLevelIDs),
            starsByLevel: Dictionary(uniqueKeysWithValues: chapterOneIDs.map { ($0, 3) }),
            upgradeLevels: [:]
        )
        XCTAssertTrue(earned.contains(.clearSkies))
        XCTAssertFalse(earned.contains(.stormChaser), "Chapter two untouched")
        XCTAssertFalse(earned.contains(.acePilot))
    }

    func testStormChaser_requiresAllChapterTwoThreeStarred() {
        let earned = AchievementRules.stateAchievements(
            completedLevelIDs: Set(allLevelIDs),
            starsByLevel: Dictionary(uniqueKeysWithValues: chapterTwoIDs.map { ($0, 3) }),
            upgradeLevels: [:]
        )
        XCTAssertTrue(earned.contains(.stormChaser))
        XCTAssertFalse(earned.contains(.clearSkies))
    }

    func testAcePilot_requiresAllTenThreeStarred() {
        // One level short → not earned.
        var starMap = stars(3, forLevels: 1...10)
        starMap[10] = 2
        var earned = AchievementRules.stateAchievements(
            completedLevelIDs: Set(allLevelIDs), starsByLevel: starMap, upgradeLevels: [:]
        )
        XCTAssertFalse(earned.contains(.acePilot))

        // All ten three-starred → Ace Pilot plus both chapter achievements.
        earned = AchievementRules.stateAchievements(
            completedLevelIDs: Set(allLevelIDs),
            starsByLevel: stars(3, forLevels: 1...10),
            upgradeLevels: [:]
        )
        XCTAssertTrue(earned.contains(.acePilot))
        XCTAssertTrue(earned.contains(.clearSkies))
        XCTAssertTrue(earned.contains(.stormChaser))
    }

    // MARK: - Upgrade achievements

    func testUpgraded_earnedAfterFirstPurchase() {
        let none = AchievementRules.stateAchievements(
            completedLevelIDs: [], starsByLevel: [:],
            upgradeLevels: [.engine: 0, .wings: 0, .armor: 0]
        )
        XCTAssertFalse(none.contains(.upgraded))

        let some = AchievementRules.stateAchievements(
            completedLevelIDs: [], starsByLevel: [:],
            upgradeLevels: [.engine: 1, .wings: 0, .armor: 0]
        )
        XCTAssertTrue(some.contains(.upgraded))
        XCTAssertFalse(some.contains(.fullKit))
    }

    func testFullKit_earnedWhenAnyTrackMaxed() {
        let maxedEngine = AchievementRules.stateAchievements(
            completedLevelIDs: [], starsByLevel: [:],
            upgradeLevels: [.engine: UpgradeKind.engine.maxLevel, .wings: 2, .armor: 1]
        )
        XCTAssertTrue(maxedEngine.contains(.fullKit))
        XCTAssertTrue(maxedEngine.contains(.upgraded))
    }

    func testFullKit_notEarnedBelowMax() {
        let earned = AchievementRules.stateAchievements(
            completedLevelIDs: [], starsByLevel: [:],
            upgradeLevels: [.engine: UpgradeKind.engine.maxLevel - 1, .wings: 4, .armor: 4]
        )
        XCTAssertFalse(earned.contains(.fullKit))
    }

    // MARK: - Progressive achievements

    func testCoinAchievements_scaleWithLifetimeCoins() {
        let progress = AchievementRules.progressiveAchievements(
            lifetimeCoinsEarned: 250, freeFlightSessionsCompleted: 0
        )
        // 250 / 500 = 50% of Coin Collector; 250 / 2000 = 12.5% of Rich Baron.
        XCTAssertEqual(progress[.coinCollector] ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(progress[.richBaron] ?? -1, 12.5, accuracy: 0.001)
    }

    func testCoinAchievements_clampAt100() {
        let progress = AchievementRules.progressiveAchievements(
            lifetimeCoinsEarned: 10_000, freeFlightSessionsCompleted: 0
        )
        XCTAssertEqual(progress[.coinCollector] ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(progress[.richBaron] ?? -1, 100, accuracy: 0.001)
    }

    func testFreeSpirit_scalesWithSessions() {
        let half = AchievementRules.progressiveAchievements(
            lifetimeCoinsEarned: 0, freeFlightSessionsCompleted: 5
        )
        XCTAssertEqual(half[.freeSpirit] ?? -1, 50, accuracy: 0.001)

        let full = AchievementRules.progressiveAchievements(
            lifetimeCoinsEarned: 0, freeFlightSessionsCompleted: 10
        )
        XCTAssertEqual(full[.freeSpirit] ?? -1, 100, accuracy: 0.001)
    }

    // MARK: - Run achievements

    func testUntouchable_earnedOnlyOnCleanRun() {
        let clean = AchievementRules.runAchievements(
            challengeType: .obstacleCourse, tookAnyHit: false,
            coinsCollected: 0, totalCoinsSpawned: 10, timeRemaining: 0
        )
        XCTAssertTrue(clean.contains(.untouchable))

        let hit = AchievementRules.runAchievements(
            challengeType: .obstacleCourse, tookAnyHit: true,
            coinsCollected: 0, totalCoinsSpawned: 10, timeRemaining: 0
        )
        XCTAssertFalse(hit.contains(.untouchable))
    }

    func testChainReaction_requiresFullCoinCollectionOnCoinChain() {
        let full = AchievementRules.runAchievements(
            challengeType: .coinChain, tookAnyHit: true,
            coinsCollected: 12, totalCoinsSpawned: 12, timeRemaining: 0
        )
        XCTAssertTrue(full.contains(.chainReaction))

        let partial = AchievementRules.runAchievements(
            challengeType: .coinChain, tookAnyHit: true,
            coinsCollected: 11, totalCoinsSpawned: 12, timeRemaining: 0
        )
        XCTAssertFalse(partial.contains(.chainReaction))

        // 100% collection but not a coinChain level → not earned.
        let wrongType = AchievementRules.runAchievements(
            challengeType: .obstacleCourse, tookAnyHit: true,
            coinsCollected: 12, totalCoinsSpawned: 12, timeRemaining: 0
        )
        XCTAssertFalse(wrongType.contains(.chainReaction))
    }

    func testChainReaction_notEarnedWhenNoCoinsSpawned() {
        // A run with zero coins must not trivially satisfy 100% collection.
        let earned = AchievementRules.runAchievements(
            challengeType: .coinChain, tookAnyHit: false,
            coinsCollected: 0, totalCoinsSpawned: 0, timeRemaining: 0
        )
        XCTAssertFalse(earned.contains(.chainReaction))
    }

    func testSpeedRun_requiresTimeTrialAboveThreshold() {
        let fast = AchievementRules.runAchievements(
            challengeType: .timeTrial, tookAnyHit: true,
            coinsCollected: 0, totalCoinsSpawned: 0,
            timeRemaining: AchievementRules.speedRunSecondsRemaining
        )
        XCTAssertTrue(fast.contains(.speedRun))

        let slow = AchievementRules.runAchievements(
            challengeType: .timeTrial, tookAnyHit: true,
            coinsCollected: 0, totalCoinsSpawned: 0,
            timeRemaining: AchievementRules.speedRunSecondsRemaining - 0.1
        )
        XCTAssertFalse(slow.contains(.speedRun))

        // Same time margin but not a time-trial → not earned.
        let wrongType = AchievementRules.runAchievements(
            challengeType: .obstacleCourse, tookAnyHit: true,
            coinsCollected: 0, totalCoinsSpawned: 0,
            timeRemaining: AchievementRules.speedRunSecondsRemaining + 5
        )
        XCTAssertFalse(wrongType.contains(.speedRun))
    }

    // MARK: - Identifier hygiene

    func testAchievementIdentifiersAreUniqueAndNamespaced() {
        let ids = A.allCases.map { $0.rawValue }
        XCTAssertEqual(Set(ids).count, ids.count, "Achievement identifiers must be unique")
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("com.skyace.achievement.") })
    }
}
