import Foundation

enum ChallengeType {
    case obstacleCourse
    case timeTrial
    case coinChain
}

/// Per-level obstacle visual theme. Hitbox and gap mechanics are identical
/// across themes; only the rendering differs. Each theme corresponds to a
/// set of sprite assets in `Assets.xcassets` and a renderer in `ObstacleNode`.
enum ObstacleTheme {
    case hotAirBalloons
    case harborPiers
    case cityBuildings
    case stormClouds
}

enum Chapter: Int {
    case clearSkies = 1
    case stormChaser = 2

    var title: String {
        switch self {
        case .clearSkies:  return "Clear Skies"
        case .stormChaser: return "Storm Chaser"
        }
    }
}

struct Challenge {
    let id: Int
    let chapter: Chapter
    let name: String
    let type: ChallengeType
    let reward: Int
    let speedMultiplier: CGFloat
    let theme: ObstacleTheme

    // Derived per-level difficulty knobs.

    /// Base gate width (gap between top/bottom obstacle pairs) before
    /// per-level scaling. Tune this single value to widen or tighten the
    /// whole progression at once.
    static let baseObstacleGap: CGFloat = 200.0

    /// Per-level gate-width multipliers applied to `baseObstacleGap`.
    /// Indexed by `id - 1` (level 1 → first entry). The curve eases the
    /// player in through Clear Skies (L1–L4), sharpens at the chapter
    /// transition into Storm Chaser (L5 → L6 drops from 175pt to 160pt),
    /// and steepens through the Storm Chaser chapter ending at 56% (112pt)
    /// for the L10 finale.
    static let obstacleGapMultipliers: [CGFloat] = [
        1.20,  // L1  — 240pt
        1.10,  // L2  — 220pt
        1.00,  // L3  — 200pt
        0.95,  // L4  — 190pt
        0.875, // L5  — 175pt
        0.80,  // L6  — 160pt
        0.74,  // L7  — 148pt
        0.68,  // L8  — 136pt
        0.62,  // L9  — 124pt
        0.56   // L10 — 112pt
    ]

    /// Gap between top/bottom obstacle pairs, narrowing with level.
    var obstacleGap: CGFloat {
        let idx = max(0, min(Challenge.obstacleGapMultipliers.count - 1, id - 1))
        return Challenge.baseObstacleGap * Challenge.obstacleGapMultipliers[idx]
    }

    /// Seconds between obstacle spawns, floor 1.0s.
    var spawnInterval: TimeInterval {
        return max(1.0, 2.2 - 0.1 * Double(id - 1))
    }

    var timeTrialDuration: TimeInterval { 45.0 }

    /// Total time from level start until the finish line crosses the plane.
    /// Drives finish-line scheduling in GameScene; each mission type has a
    /// fixed-length course so the player always has a clear "end" to fly to.
    var levelDuration: TimeInterval {
        switch type {
        case .obstacleCourse: return 30.0
        case .timeTrial:      return timeTrialDuration
        case .coinChain:      return 35.0
        }
    }
}

enum ChallengeCatalog {

    // Static list — the order here is the order shown on the map.
    //
    // Each level is assigned an obstacle theme per the SKY-62 plan:
    //   Levels 1-3 (free tier) → Hot Air Balloons
    //   Levels 4-5             → Harbor Piers
    //   Levels 6-7             → City Buildings
    //   Levels 8-10            → Storm Clouds
    static let all: [Challenge] = [
        // Chapter 1 — Clear Skies
        Challenge(id: 1,  chapter: .clearSkies,  name: "First Flight",       type: .obstacleCourse, reward: 100, speedMultiplier: 1.0, theme: .hotAirBalloons),
        Challenge(id: 2,  chapter: .clearSkies,  name: "Cloud Canyon",       type: .obstacleCourse, reward: 150, speedMultiplier: 1.1, theme: .hotAirBalloons),
        Challenge(id: 3,  chapter: .clearSkies,  name: "Sunny Sprint",       type: .timeTrial,      reward: 120, speedMultiplier: 1.0, theme: .hotAirBalloons),
        Challenge(id: 4,  chapter: .clearSkies,  name: "Coin Scatter",       type: .coinChain,      reward: 130, speedMultiplier: 1.1, theme: .harborPiers),
        Challenge(id: 5,  chapter: .clearSkies,  name: "Gusty Gorge",        type: .obstacleCourse, reward: 180, speedMultiplier: 1.2, theme: .harborPiers),

        // Chapter 2 — Storm Chaser
        Challenge(id: 6,  chapter: .stormChaser, name: "Lightning Dash",     type: .timeTrial,      reward: 200, speedMultiplier: 1.3, theme: .cityBuildings),
        Challenge(id: 7,  chapter: .stormChaser, name: "Thunder Gap",        type: .obstacleCourse, reward: 220, speedMultiplier: 1.4, theme: .cityBuildings),
        Challenge(id: 8,  chapter: .stormChaser, name: "The Coin Tornado",   type: .coinChain,      reward: 210, speedMultiplier: 1.3, theme: .stormClouds),
        Challenge(id: 9,  chapter: .stormChaser, name: "Hurricane Alley",    type: .obstacleCourse, reward: 250, speedMultiplier: 1.5, theme: .stormClouds),
        Challenge(id: 10, chapter: .stormChaser, name: "Sky Ace Challenge",  type: .obstacleCourse, reward: 300, speedMultiplier: 1.6, theme: .stormClouds)
    ]

    static func challenge(forID id: Int) -> Challenge? {
        return all.first(where: { $0.id == id })
    }

    /// The id of the last level in the game (currently L10, "Sky Ace
    /// Challenge"). Clearing it is the whole-game completion moment that earns
    /// the Certified Sky Ace badge (SKY-123). Derived so it tracks the catalog.
    static var finalLevelID: Int { all.map(\.id).max() ?? 0 }
}

/// Star rating thresholds:
///   1★ — finished the level (time expired or finish line reached)
///   2★ — finished AND collected ≥50% of coins that appeared
///   3★ — finished AND collected ≥80% of coins AND time still on the clock
///
/// Thresholds are tunable here.
enum StarRating {
    static let twoStarCoinThreshold: Double = 0.5
    static let threeStarCoinThreshold: Double = 0.8

    static func stars(
        completed: Bool,
        coinsCollected: Int,
        totalCoins: Int,
        timeRemaining: TimeInterval
    ) -> Int {
        guard completed else { return 0 }
        let pct = totalCoins > 0 ? Double(coinsCollected) / Double(totalCoins) : 0
        if pct >= threeStarCoinThreshold && timeRemaining > 0 { return 3 }
        if pct >= twoStarCoinThreshold { return 2 }
        return 1
    }
}
