import XCTest
@testable import SkyAce

final class CurrencyManagerTests: XCTestCase {

    private let manager = CurrencyManager.shared

    override func setUp() {
        super.setUp()
        manager.resetForTesting()
        // Default to "free user" for each test. Tests that need premium
        // override the provider explicitly.
        manager.isContentUnlockedProvider = { false }
    }

    override func tearDown() {
        manager.resetForTesting()
        super.tearDown()
    }

    // MARK: - Coin cap (free user)

    func testAddCoins_freeUser_respectsCap() {
        manager.addCoins(1100)
        XCTAssertEqual(manager.coinTotal, CurrencyManager.freeCoinCap)
    }

    func testAddCoins_freeUser_doesNotExceedCapIncrementally() {
        manager.addCoins(600)
        manager.addCoins(600)
        XCTAssertEqual(manager.coinTotal, CurrencyManager.freeCoinCap)
    }

    // MARK: - No cap (premium user)

    func testAddCoins_premiumUser_noCap() {
        manager.isContentUnlockedProvider = { true }
        manager.addCoins(1500)
        XCTAssertEqual(manager.coinTotal, 1500)
    }

    // MARK: - Rings have no cap

    func testAddRings_noCapForAnyUser() {
        manager.addRings(2000)
        XCTAssertEqual(manager.ringTotal, 2000)
    }

    // MARK: - Premium-unlock transition

    func testCoinsCarryOverOnPremiumUnlock() {
        manager.addCoins(800)
        XCTAssertEqual(manager.coinTotal, 800)

        manager.isContentUnlockedProvider = { true }
        XCTAssertEqual(manager.coinTotal, 800,
                       "Existing coins must not reset when the player upgrades.")
    }

    func testCoinCapLiftsAfterPremiumUnlock() {
        manager.addCoins(1000)
        XCTAssertEqual(manager.coinTotal, CurrencyManager.freeCoinCap)

        manager.isContentUnlockedProvider = { true }
        manager.addCoins(200)
        XCTAssertEqual(manager.coinTotal, 1200)
    }

    // MARK: - Persistence

    func testCurrencyPersistsAcrossReinit() {
        // Premium so we can write 300 coins without bumping the cap.
        manager.isContentUnlockedProvider = { true }
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
        manager.isContentUnlockedProvider = { true }
        manager.addCoins(600)

        let didDeduct = manager.deductCoins(600)
        XCTAssertTrue(didDeduct)
        XCTAssertEqual(manager.coinTotal, 0)
    }

    func testDeductCoins_doesNotGoBelowZero() {
        manager.isContentUnlockedProvider = { true }
        manager.addCoins(100)

        let didDeduct = manager.deductCoins(600)
        XCTAssertFalse(didDeduct, "Deduct should be rejected when funds are insufficient.")
        XCTAssertEqual(manager.coinTotal, 100, "Balance must not change on a rejected deduct.")
    }

    // MARK: - Notifications

    func testAddCoinsPostsNotification() {
        manager.isContentUnlockedProvider = { true }
        let exp = expectation(forNotification: CurrencyManager.coinTotalDidChange, object: manager) { note in
            return (note.userInfo?["total"] as? Int) == 250
        }
        manager.addCoins(250)
        wait(for: [exp], timeout: 1.0)
    }
}
