import XCTest
@testable import SkyAce

/// Verifies the SKY-61 centralized narrative content model: every level has a
/// brief, chapters line up with the level catalog, and the intro / transition
/// copy is present. Guards against a copy edit accidentally dropping or
/// misfiling a brief.
final class MissionContentTests: XCTestCase {

    // MARK: - Mission briefs

    func testTenBriefsInLevelOrder() {
        XCTAssertEqual(MissionContent.all.count, 10)
        XCTAssertEqual(MissionContent.all.map { $0.level }, Array(1...10))
    }

    func testChaptersSplitAtLevelFive() {
        for brief in MissionContent.all {
            let expected: Chapter = brief.level <= 5 ? .clearSkies : .stormChaser
            XCTAssertEqual(brief.chapter, expected,
                           "Level \(brief.level) is in the wrong chapter.")
        }
    }

    func testBriefChaptersMatchTheLevelCatalog() {
        // The briefing card picks its art/portrait from the brief's chapter, so
        // it must agree with the catalog the map is built from.
        for brief in MissionContent.all {
            let challenge = ChallengeCatalog.challenge(forID: brief.level)
            XCTAssertNotNil(challenge, "No catalog challenge for level \(brief.level).")
            XCTAssertEqual(brief.chapter, challenge?.chapter,
                           "Brief chapter disagrees with catalog for level \(brief.level).")
        }
    }

    func testLookupByLevel() {
        XCTAssertEqual(MissionContent.brief(forLevel: 1)?.tagline, "First Wings Up")
        XCTAssertEqual(MissionContent.brief(forLevel: 10)?.tagline, "Prove You're an Ace")
        XCTAssertNil(MissionContent.brief(forLevel: 0))
        XCTAssertNil(MissionContent.brief(forLevel: 11))
    }

    func testEveryBriefHasNonEmptyCopy() {
        for brief in MissionContent.all {
            XCTAssertFalse(brief.tagline.trimmingCharacters(in: .whitespaces).isEmpty,
                           "Empty tagline at level \(brief.level).")
            XCTAssertFalse(brief.storyContext.trimmingCharacters(in: .whitespaces).isEmpty,
                           "Empty story context at level \(brief.level).")
        }
    }

    // MARK: - Game intro + chapter transition

    func testGameIntroCopyPresent() {
        XCTAssertFalse(MissionContent.gameIntro.body.trimmingCharacters(in: .whitespaces).isEmpty)
        // The intro welcomes the player to the academy and names their instructor.
        XCTAssertTrue(MissionContent.gameIntro.body.contains("Skyview Flight Academy"))
        XCTAssertTrue(MissionContent.gameIntro.body.contains("Captain Rio"))
    }

    func testChapterTransitionCopyPresent() {
        XCTAssertFalse(MissionContent.chapterTransition.chapterOneComplete
            .trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertFalse(MissionContent.chapterTransition.chapterTwoIntro
            .trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
