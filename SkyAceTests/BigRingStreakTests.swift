import XCTest
@testable import SkyAce

/// Tests the SKY-63 big-ring streak scoring contract on `GameState`:
/// consecutive fly-throughs award an escalating coin bonus (base · streak), a
/// miss resets the streak, and the bonus is folded into both the collected and
/// spawned coin tallies so it never breaks the `coinsCollected <=
/// totalCoinsSpawned` invariant the star rating relies on.
final class BigRingStreakTests: XCTestCase {

    private let base = GameScene.bigRingBaseBonus  // 5

    private func makeState() -> GameState {
        // Any real challenge works — the streak logic is challenge-agnostic.
        GameState(challenge: ChallengeCatalog.all[0])
    }

    // MARK: - Escalating bonus

    func testFirstRingAwardsBaseBonus() {
        let state = makeState()
        XCTAssertEqual(state.collectBigRing(baseBonus: base), base)
        XCTAssertEqual(state.bigRingStreak, 1)
        XCTAssertEqual(state.bigRingsCollected, 1)
    }

    func testStreakEscalatesBaseTimesStreak() {
        let state = makeState()
        XCTAssertEqual(state.collectBigRing(baseBonus: base), base)       // 5
        XCTAssertEqual(state.collectBigRing(baseBonus: base), base * 2)   // 10
        XCTAssertEqual(state.collectBigRing(baseBonus: base), base * 3)   // 15
        XCTAssertEqual(state.bigRingStreak, 3)
        XCTAssertEqual(state.bigRingsCollected, 3)
    }

    // MARK: - Miss resets the streak

    func testMissResetsStreakButNotLifetimeCount() {
        let state = makeState()
        _ = state.collectBigRing(baseBonus: base)   // streak 1 → +5
        _ = state.collectBigRing(baseBonus: base)   // streak 2 → +10

        state.resetBigRingStreak()
        XCTAssertEqual(state.bigRingStreak, 0)

        // The next ring after a miss restarts at the base bonus…
        XCTAssertEqual(state.collectBigRing(baseBonus: base), base)
        XCTAssertEqual(state.bigRingStreak, 1)
        // …but the lifetime collected count keeps climbing across the miss.
        XCTAssertEqual(state.bigRingsCollected, 3)
    }

    // MARK: - Coin tally / star-ratio invariant

    func testBonusGrowsBothCollectedAndSpawnedEqually() {
        let state = makeState()
        let bonus = state.collectBigRing(baseBonus: base)
        XCTAssertEqual(state.coinsCollected, bonus)
        XCTAssertEqual(state.totalCoinsSpawned, bonus)
    }

    func testInvariantHoldsWithMixedRegularCoinsAndRings() {
        let state = makeState()
        // Some regular coins appear; only a few are collected.
        state.registerCoinSpawned(count: 20)
        state.collectCoin()
        state.collectCoin()

        // A streak of three rings on top.
        _ = state.collectBigRing(baseBonus: base)
        _ = state.collectBigRing(baseBonus: base)
        _ = state.collectBigRing(baseBonus: base)

        // Ring bonus total = 5 + 10 + 15 = 30, added to both tallies.
        XCTAssertEqual(state.coinsCollected, 2 + 30)
        XCTAssertEqual(state.totalCoinsSpawned, 20 + 30)
        XCTAssertLessThanOrEqual(
            state.coinsCollected, state.totalCoinsSpawned,
            "Ring bonuses must never push collected past spawned — the star ratio would exceed 100%."
        )
    }

    // MARK: - Defensive

    func testNonPositiveBaseBonusAwardsNothingButStillAdvancesStreak() {
        let state = makeState()
        XCTAssertEqual(state.collectBigRing(baseBonus: 0), 0)
        XCTAssertEqual(state.collectBigRing(baseBonus: -5), 0)
        XCTAssertEqual(state.bigRingStreak, 2)
        XCTAssertEqual(state.coinsCollected, 0)
        XCTAssertEqual(state.totalCoinsSpawned, 0)
    }
}
