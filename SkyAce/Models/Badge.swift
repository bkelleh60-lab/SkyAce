import Foundation

/// A collectible achievement badge shown on the badge collection screen
/// (SKY-124). Definitions are static and ordered for display; earned state is
/// read live from `ProgressManager` on every access so the collection screen
/// and the home-screen trophy indicator always reflect current progress —
/// no caching, per the ticket.
struct Badge {

    /// Bundled asset name for the full-colour badge art (asset catalog or
    /// `Resources/Sprites/`; both resolve through `SkySprites`).
    let assetName: String
    /// Display name shown beneath the badge art.
    let title: String
    /// One-line explanation of how the badge is earned.
    let detail: String
    /// Live earned check against persisted progress.
    let isEarned: () -> Bool

    /// The badges available at launch, in display order.
    static let all: [Badge] = [
        Badge(
            assetName: SkySprites.badgeCertifiedSkyAce,
            title: "Certified Sky Ace",
            detail: "Completed all 10 missions",
            isEarned: { ProgressManager.shared.hasEarnedCertifiedSkyAce }
        ),
        Badge(
            assetName: SkySprites.badgeSmoothLanding,
            title: "Pilot of the Year",
            detail: "Nailed a perfect landing",
            isEarned: { ProgressManager.shared.hasEarnedPerfectLanding }
        )
    ]

    /// How many badges the player has earned so far.
    static var earnedCount: Int {
        all.filter { $0.isEarned() }.count
    }

    /// True when the player has earned a badge they have not yet seen on the
    /// collection screen — drives the home-screen trophy dot.
    static var hasUnseenEarnedBadges: Bool {
        earnedCount > ProgressManager.shared.lastSeenBadgeCount
    }

    /// Records that the player has seen the current set of earned badges,
    /// clearing the home-screen trophy dot. Called when the collection screen
    /// appears.
    static func markAllSeen() {
        ProgressManager.shared.lastSeenBadgeCount = earnedCount
    }
}
