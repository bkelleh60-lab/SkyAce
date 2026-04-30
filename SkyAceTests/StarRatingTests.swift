import XCTest
@testable import SkyAce

/// Tests for the level star rating logic. The shipped game derives stars
/// from `hitsTaken` and a `completed` flag (see `StarRating` in
/// `Challenge.swift`), not from coin collection percentages — so these tests
/// exercise that contract rather than the hypothetical
/// `calculateStars(collected:total:timeRemaining:)` shape proposed in the
/// ticket. The intent (1/2/3 star thresholds + best-score persistence + edge
/// cases) is covered.
final class StarRatingTests: XCTestCase {

    // MARK: - Failure case

    func testZeroStarsWhenLevelNotCompleted() {
        XCTAssertEqual(StarRating.stars(forHitsTaken: 0, completed: false), 0)
        XCTAssertEqual(StarRating.stars(forHitsTaken: 5, completed: false), 0)
    }

    // MARK: - One star (≥2 hits, completed)

    func testOneStarForTwoHits() {
        XCTAssertEqual(StarRating.stars(forHitsTaken: 2, completed: true), 1)
    }

    func testOneStarForManyHits() {
        XCTAssertEqual(StarRating.stars(forHitsTaken: 99, completed: true), 1)
    }

    // MARK: - Two stars (exactly 1 hit, completed)

    func testTwoStarsForOneHit() {
        XCTAssertEqual(StarRating.stars(forHitsTaken: 1, completed: true), 2)
    }

    // MARK: - Three stars (zero hits, completed)

    func testThreeStarsForFlawlessRun() {
        XCTAssertEqual(StarRating.stars(forHitsTaken: 0, completed: true), 3)
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
