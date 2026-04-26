import Foundation

enum ChallengeType {
    case obstacleCourse
    case timeTrial
    case coinChain
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

    // Derived per-level difficulty knobs.

    /// Base gate width (gap between top/bottom obstacle pairs) before
    /// per-level scaling. Tune this single value to widen or tighten the
    /// whole progression at once.
    static let baseObstacleGap: CGFloat = 200.0

    /// Per-level gate-width multipliers applied to `baseObstacleGap`.
    /// Indexed by `id - 1` (level 1 → first entry). The curve eases the
    /// player in (L1 wide, gentle ramp through L3) and tightens steadily
    /// from L4 onward, ending at 75% for the L10 finale.
    static let obstacleGapMultipliers: [CGFloat] = [
        1.20, // L1
        1.10, // L2
        1.00, // L3
        0.95, // L4
        0.90, // L5
        0.87, // L6
        0.84, // L7
        0.81, // L8
        0.78, // L9
        0.75  // L10
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
    var coinChainTarget: Int { 15 }
    var coinChainTotal: Int { 20 }

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

    /// Free tier covers the first 3 levels.
    var requiresFullUnlock: Bool { return id > 3 }
}

enum ChallengeCatalog {

    // Static list — the order here is the order shown on the map.
    static let all: [Challenge] = [
        // Chapter 1 — Clear Skies
        Challenge(id: 1,  chapter: .clearSkies,  name: "First Flight",       type: .obstacleCourse, reward: 100, speedMultiplier: 1.0),
        Challenge(id: 2,  chapter: .clearSkies,  name: "Cloud Canyon",       type: .obstacleCourse, reward: 150, speedMultiplier: 1.1),
        Challenge(id: 3,  chapter: .clearSkies,  name: "Sunny Sprint",       type: .timeTrial,      reward: 120, speedMultiplier: 1.0),
        Challenge(id: 4,  chapter: .clearSkies,  name: "Coin Scatter",       type: .coinChain,      reward: 130, speedMultiplier: 1.1),
        Challenge(id: 5,  chapter: .clearSkies,  name: "Gusty Gorge",        type: .obstacleCourse, reward: 180, speedMultiplier: 1.2),

        // Chapter 2 — Storm Chaser
        Challenge(id: 6,  chapter: .stormChaser, name: "Lightning Dash",     type: .timeTrial,      reward: 200, speedMultiplier: 1.3),
        Challenge(id: 7,  chapter: .stormChaser, name: "Thunder Gap",        type: .obstacleCourse, reward: 220, speedMultiplier: 1.4),
        Challenge(id: 8,  chapter: .stormChaser, name: "The Coin Tornado",   type: .coinChain,      reward: 210, speedMultiplier: 1.3),
        Challenge(id: 9,  chapter: .stormChaser, name: "Hurricane Alley",    type: .obstacleCourse, reward: 250, speedMultiplier: 1.5),
        Challenge(id: 10, chapter: .stormChaser, name: "Sky Ace Challenge",  type: .obstacleCourse, reward: 300, speedMultiplier: 1.6)
    ]

    static func challenge(forID id: Int) -> Challenge? {
        return all.first(where: { $0.id == id })
    }
}

// Star rating thresholds: 3=0 hits, 2=1 hit, 1=2+ hits (completion).
enum StarRating {
    static func stars(forHitsTaken hits: Int, completed: Bool) -> Int {
        guard completed else { return 0 }
        switch hits {
        case 0:  return 3
        case 1:  return 2
        default: return 1
        }
    }
}
