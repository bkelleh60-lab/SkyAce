import Foundation

/// Static definitions for the four upgrade tracks and the current-level helpers.
/// Runtime upgrade levels are stored via ProgressManager.upgradeLevel(for:).
enum UpgradeKind: String, CaseIterable {
    case engine = "engine"
    case wings  = "wings"
    case fuel   = "fuel"
    case armor  = "armor"

    var displayName: String {
        switch self {
        case .engine: return "Engine Boost"
        case .wings:  return "Wing Tech"
        case .fuel:   return "Fuel Tank"
        case .armor:  return "Armor Plating"
        }
    }

    var shortName: String {
        switch self {
        case .engine: return "ENGINE"
        case .wings:  return "WINGS"
        case .fuel:   return "FUEL"
        case .armor:  return "ARMOR"
        }
    }

    var iconEmoji: String {
        switch self {
        case .engine: return "⚙️"
        case .wings:  return "🪽"
        case .fuel:   return "⛽"
        case .armor:  return "🛡"
        }
    }

    var description: String {
        switch self {
        case .engine: return "+15% top speed per level"
        case .wings:  return "+10% climb power per level"
        case .fuel:   return "Coming in Phase 2"
        case .armor:  return "Absorb crashes: 1 hit at L1, up to 5 hits at L5."
        }
    }

    var maxLevel: Int {
        switch self {
        case .engine: return 5
        case .wings:  return 5
        case .fuel:   return 3
        case .armor:  return 5
        }
    }

    var costs: [Int] {
        switch self {
        case .engine: return [200, 450, 800, 1300, 2000]
        case .wings:  return [250, 500, 900, 1500, 2400]
        case .fuel:   return [300, 600, 1000]
        case .armor:  return [350, 700, 1200, 1900, 2800]
        }
    }

    /// "Phase 2" — shown but not purchasable in v1.
    var isAvailable: Bool {
        return self != .fuel
    }
}

struct UpgradeState {
    let kind: UpgradeKind
    let currentLevel: Int

    var isMaxed: Bool { currentLevel >= kind.maxLevel }

    /// Cost of the next level, or nil if maxed out.
    var nextCost: Int? {
        guard currentLevel < kind.maxLevel else { return nil }
        return kind.costs[currentLevel]
    }

    static func current(_ kind: UpgradeKind) -> UpgradeState {
        return UpgradeState(kind: kind, currentLevel: ProgressManager.shared.upgradeLevel(for: kind.rawValue))
    }
}

// MARK: - Upgrade stat formulas
// Kept here so tests / preview UI can also read them.

enum UpgradeFormulas {
    static let baseHorizontalSpeed: CGFloat = 180.0
    static let baseClimbVelocity:   CGFloat = 320.0

    static func horizontalSpeed(engineLevel: Int) -> CGFloat {
        return baseHorizontalSpeed * (1.0 + 0.15 * CGFloat(engineLevel))
    }

    static func climbVelocity(wingLevel: Int) -> CGFloat {
        return baseClimbVelocity * (1.0 + 0.10 * CGFloat(wingLevel))
    }

    static func hitsAllowed(armorLevel: Int) -> Int {
        return max(0, min(armorLevel, UpgradeKind.armor.maxLevel))
    }
}
