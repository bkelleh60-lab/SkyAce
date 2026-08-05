import XCTest
@testable import SkyAce

final class CurrencyManagerTests: XCTestCase {

    private let manager = CurrencyManager.shared

    override func setUp() {
        super.setUp()
        manager.resetForTesting()
        // The Landing Practice reward credits the player's spendable balance
        // (ProgressManager.coins), so clear that too for a known starting point.
        ProgressManager.shared.resetAllProgress()
    }

    override func tearDown() {
        manager.resetForTesting()
        ProgressManager.shared.resetAllProgress()
        super.tearDown()
    }

    // MARK: - Coins (no cap — Sky Ace is fully free)

    func testAddCoins_accumulatesWithoutCap() {
        manager.addCoins(1500)
        XCTAssertEqual(manager.coinTotal, 1500)
    }

    func testAddCoins_accumulatesIncrementally() {
        manager.addCoins(600)
        manager.addCoins(600)
        XCTAssertEqual(manager.coinTotal, 1200)
    }

    // MARK: - Rings

    func testAddRings_accumulates() {
        manager.addRings(2000)
        XCTAssertEqual(manager.ringTotal, 2000)
    }

    // MARK: - Persistence

    func testCurrencyPersistsAcrossReinit() {
        manager.addCoins(300)
        manager.addRings(50)

        // CurrencyManager is a singleton backed by UserDefaults, so a fresh
        // read of `.shared` is the closest analog to a process restart.
        // Re-reading the singleton must report the same totals.
        XCTAssertEqual(CurrencyManager.shared.coinTotal, 300)
        XCTAssertEqual(CurrencyManager.shared.ringTotal, 50)
    }

    // MARK: - Deduction

    func testDeductCoins_reducesBalance() {
        manager.addCoins(600)

        let didDeduct = manager.deductCoins(600)
        XCTAssertTrue(didDeduct)
        XCTAssertEqual(manager.coinTotal, 0)
    }

    func testDeductCoins_doesNotGoBelowZero() {
        manager.addCoins(100)

        let didDeduct = manager.deductCoins(600)
        XCTAssertFalse(didDeduct, "Deduct should be rejected when funds are insufficient.")
        XCTAssertEqual(manager.coinTotal, 100, "Balance must not change on a rejected deduct.")
    }

    // MARK: - Landing Practice daily reward (SKY-95)

    func testLandingPracticeReward_grantsFiftyCoins() {
        let granted = manager.grantLandingPracticeSmoothLandingReward()
        XCTAssertEqual(granted, 50)
        XCTAssertEqual(ProgressManager.shared.coins, 50,
                       "Reward must land in the player's spendable balance.")
        XCTAssertEqual(manager.landingPracticeCoinsEarnedToday, 50)
    }

    // SKY-106 regression: the reward must credit the spendable balance
    // (ProgressManager.coins) that the home bar / Hangar / Shop read, NOT the
    // HUD-only CurrencyManager.coinTotal. Crediting the latter left the reward
    // pill animating while the player's balance never moved.
    func testLandingPracticeReward_creditsSpendableBalanceNotHudCounter() {
        manager.grantLandingPracticeSmoothLandingReward()
        XCTAssertEqual(ProgressManager.shared.coins, 50,
                       "Reward must reach the spendable player balance.")
        XCTAssertEqual(manager.coinTotal, 0,
                       "Reward must not be diverted into the HUD-only coin counter.")
    }

    func testLandingPracticeReward_accumulatesAcrossLandings() {
        manager.grantLandingPracticeSmoothLandingReward()
        manager.grantLandingPracticeSmoothLandingReward()
        manager.grantLandingPracticeSmoothLandingReward()
        XCTAssertEqual(manager.landingPracticeCoinsEarnedToday, 150)
        XCTAssertEqual(ProgressManager.shared.coins, 150)
    }

    func testLandingPracticeReward_enforcesDailyCap() {
        // 10 smooth landings = 500 coins = the daily cap.
        for _ in 0..<10 {
            XCTAssertEqual(manager.grantLandingPracticeSmoothLandingReward(), 50)
        }
        XCTAssertEqual(manager.landingPracticeCoinsEarnedToday,
                       CurrencyManager.landingPracticeDailyCoinCap)

        // The 11th smooth landing grants nothing and adds no coins.
        XCTAssertEqual(manager.grantLandingPracticeSmoothLandingReward(), 0,
                       "No reward once the daily cap is reached.")
        XCTAssertEqual(ProgressManager.shared.coins, 500,
                       "Coin balance must not move once capped.")
    }

    func testLandingPracticeReward_resetsOnNewDay() {
        // Simulate yesterday's session having hit the cap by writing the stored
        // keys directly with a stale date.
        let defaults = UserDefaults.standard
        defaults.set(500, forKey: "skyace.landingPracticeCoinsToday")
        defaults.set("2000-01-01", forKey: "skyace.landingPracticeLastEarnDate")

        // A stale date reads as zero earned today, so a fresh grant succeeds and
        // restarts the counter at the reward amount.
        XCTAssertEqual(manager.landingPracticeCoinsEarnedToday, 0,
                       "A non-today stored date must read as zero earned today.")
        XCTAssertEqual(manager.grantLandingPracticeSmoothLandingReward(), 50)
        XCTAssertEqual(manager.landingPracticeCoinsEarnedToday, 50)
    }

    // MARK: - Notifications

    func testAddCoinsPostsNotification() {
        let exp = expectation(forNotification: CurrencyManager.coinTotalDidChange, object: manager) { note in
            return (note.userInfo?["total"] as? Int) == 250
        }
        manager.addCoins(250)
        wait(for: [exp], timeout: 1.0)
    }
}
