import XCTest
@testable import SkyAce

/// Tests the post-SKY-37 star rating contract: stars are derived from the
/// percentage of available coins collected and whether time was still on the
/// clock at finish. Persistence (best-only) is also covered.
final class StarRatingTests: XCTestCase {

    // MARK: - Failure case

    func testZeroStarsWhenLevelNotCompleted() {
        XCTAssertEqual(
            StarRating.stars(completed: false, coinsCollected: 0, totalCoins: 10, timeRemaining: 10),
            0
        )
        XCTAssertEqual(
            StarRating.stars(completed: false, coinsCollected: 10, totalCoins: 10, timeRemaining: 10),
            0,
            "An incomplete run earns no stars even with a full coin sweep."
        )
    }

    // MARK: - One star (completed, low coin %)

    func testOneStarForCompletionWithNoCoins() {
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 0, totalCoins: 20, timeRemaining: 10),
            1
        )
    }

    func testOneStarJustBelowTwoStarThreshold() {
        // 49% — below the 50% two-star threshold.
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 49, totalCoins: 100, timeRemaining: 10),
            1
        )
    }

    func testOneStarWhenLevelHasNoCoins() {
        // Defensive: total=0 should not crash and should fall through to the
        // completion-only floor.
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 0, totalCoins: 0, timeRemaining: 5),
            1
        )
    }

    // MARK: - Two stars (≥50% coins)

    func testTwoStarsAtFiftyPercentCoins() {
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 10, totalCoins: 20, timeRemaining: 0),
            2
        )
    }

    func testTwoStarsAtSeventyNinePercentCoins() {
        // 79% — just below the 80% three-star threshold, even with time left.
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 79, totalCoins: 100, timeRemaining: 5),
            2
        )
    }

    func testTwoStarsWhenEightyPercentButNoTimeRemaining() {
        // ≥80% coins but timer expired — three stars require BOTH conditions.
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 80, totalCoins: 100, timeRemaining: 0),
            2
        )
    }

    // MARK: - Three stars (≥80% coins AND time remaining)

    func testThreeStarsAtEightyPercentCoinsWithTimeLeft() {
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 80, totalCoins: 100, timeRemaining: 1),
            3
        )
    }

    func testThreeStarsForFlawlessCoinSweep() {
        XCTAssertEqual(
            StarRating.stars(completed: true, coinsCollected: 20, totalCoins: 20, timeRemaining: 12),
            3
        )
    }

    // MARK: - Best-score persistence

    func testBestStarRatingNotOverwrittenByLowerScore() {
        let progress = ProgressManager.shared
        let testLevelID = 9_001 // outside the real catalog so we don't pollute play state
        let key = "skyace.starRatings"
        let defaults = UserDefaults.standard
        let originalRatings = defaults.dictionary(forKey: key)
        defer {
            if let original = originalRatings {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            // Also pull the test ID out of the completed-levels list.
            let completedKey = "skyace.completedLevels"
            if let arr = defaults.array(forKey: completedKey) as? [Int] {
                defaults.set(arr.filter { $0 != testLevelID }, forKey: completedKey)
            }
        }

        progress.markLevelCompleted(testLevelID, stars: 3)
        XCTAssertEqual(progress.starsForLevel(testLevelID), 3)

        progress.markLevelCompleted(testLevelID, stars: 1)
        XCTAssertEqual(progress.starsForLevel(testLevelID), 3,
                       "A lower star result must not overwrite a higher saved best.")
    }

    func testHigherStarRatingOverwritesLowerScore() {
        let progress = ProgressManager.shared
        let testLevelID = 9_002
        let key = "skyace.starRatings"
        let defaults = UserDefaults.standard
        let originalRatings = defaults.dictionary(forKey: key)
        defer {
            if let original = originalRatings {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            let completedKey = "skyace.completedLevels"
            if let arr = defaults.array(forKey: completedKey) as? [Int] {
                defaults.set(arr.filter { $0 != testLevelID }, forKey: completedKey)
            }
        }

        progress.markLevelCompleted(testLevelID, stars: 1)
        XCTAssertEqual(progress.starsForLevel(testLevelID), 1)

        progress.markLevelCompleted(testLevelID, stars: 3)
        XCTAssertEqual(progress.starsForLevel(testLevelID), 3)
    }
}
