import CoreGraphics
import Foundation

/// One asymmetric ability per plane (SKY-66). Plane choice becomes a gameplay
/// decision, not just a stats one: each plane carries either an *active*
/// ability the player fires from the HUD ability button, or a *passive*
/// modifier applied at scene init.
///
/// All tuning lives in `PlaneAbilityCatalog` so the values here are the single
/// dial for balancing abilities against the level gap/spawn curve. Fields that
/// don't apply to a given kind carry no-op defaults (multipliers 1.0, others 0)
/// so each catalog entry reads cleanly.
struct PlaneAbility {

    enum Kind: Equatable {
        case invincibilityBurst   // active
        case ghostMode            // active
        case quickClimb           // active
        case coinMagnet           // active
    }

    let kind: Kind

    /// True for player-fired abilities (invincibility, speed boost); false for
    /// passives that apply automatically. Drives whether GameScene shows the
    /// HUD ability button.
    let isActive: Bool

    /// Short display name (Hangar ability line, e.g. "Ghost Mode").
    let displayName: String

    /// One-line description for the Hangar plane card.
    let blurb: String

    /// HUD/emoji glyph, reused in the ability button and the Hangar line. Kept
    /// as an emoji so no new art asset is required (matches the armor "🛡"
    /// badge convention).
    let iconEmoji: String

    // MARK: - Active tuning (ignored for passives)

    /// Seconds the burst / effect lasts.
    let duration: TimeInterval

    /// Uses per run/level. 0 means "unlimited".
    let charges: Int

    /// quickClimb: multiplier on the plane's normal climb impulse for the
    /// burst (>1 = a stronger jump than a regular tap). No-op (1.0) for other
    /// kinds.
    let climbMultiplier: CGFloat

    /// coinMagnet: radius (points) within which coins are pulled toward the plane.
    let magnetRadius: CGFloat

    /// Creates a plane ability. Fields that don't apply to `kind` take the
    /// no-op defaults (multipliers 1.0, everything else 0) so each catalog
    /// entry only specifies the tuning that matters for its kind.
    init(
        kind: Kind,
        isActive: Bool,
        displayName: String,
        blurb: String,
        iconEmoji: String,
        duration: TimeInterval = 0,
        charges: Int = 0,
        climbMultiplier: CGFloat = 1.0,
        magnetRadius: CGFloat = 0
    ) {
        self.kind = kind
        self.isActive = isActive
        self.displayName = displayName
        self.blurb = blurb
        self.iconEmoji = iconEmoji
        self.duration = duration
        self.charges = charges
        self.climbMultiplier = climbMultiplier
        self.magnetRadius = magnetRadius
    }
}

/// Per-plane ability definitions. Referenced by `PlaneCatalog` entries in
/// `Player.swift`. Tuning notes live inline; see SKY-66 for the balance
/// rationale (short invincibility so early levels aren't trivialized).
enum PlaneAbilityCatalog {

    /// Red Baron (starter) — 0.4s invincibility burst, one charge per run.
    /// 0.4s clears a single obstacle but cannot carry a tight sequence, so it
    /// never trivializes Clear Skies levels. Boundary crashes stay lethal
    /// (handled scene-side).
    static let invincibilityBurst = PlaneAbility(
        kind: .invincibilityBurst,
        isActive: true,
        displayName: "Barrel Roll",
        blurb: "Brief shield — one save per run",
        iconEmoji: "✨",
        duration: 0.4,
        charges: 1
    )

    /// Blue Sky Chaser — active Quick Climb: a player-fired burst that jumps
    /// the plane upward at ~1.9× a normal tap's impulse. Two uses per level
    /// (charge-limited, no cooldown), reset each level. Firing is gated by the
    /// HUD ability button, never a normal screen tap.
    static let quickClimb = PlaneAbility(
        kind: .quickClimb,
        isActive: true,
        displayName: "Quick Climb",
        blurb: "Burst upward — 2 uses per level",
        iconEmoji: "⬆️",
        charges: 2,
        climbMultiplier: 1.9
    )

    /// Shadow Dart — active Ghost Mode (SKY-118): a player-fired survival
    /// ability. On activation the plane goes semi-transparent and phases
    /// through the next obstacle it would hit — collisions do no damage while
    /// ghosted. Ends the moment it passes one obstacle or after `duration`
    /// (3s), whichever comes first. One use per level, reset each level.
    /// Replaces the old Overdrive speed burst, which made obstacle levels
    /// harder rather than easier.
    static let ghostMode = PlaneAbility(
        kind: .ghostMode,
        isActive: true,
        displayName: "Ghost Mode",
        blurb: "Phase through one obstacle — 1 use per level",
        iconEmoji: "👻",
        duration: 3.0,
        charges: 1
    )

    /// Night Hawk — active Coin Magnet (SKY-119): a player-fired pulse that pulls
    /// nearby coins toward the plane for `duration`. Three uses per level
    /// (charge-limited, no cooldown), reset each level. Firing is gated by the
    /// HUD ability button; the pull radius/behavior are unchanged from the
    /// former passive implementation — only the trigger moved to the button.
    static let coinMagnet = PlaneAbility(
        kind: .coinMagnet,
        isActive: true,
        displayName: "Coin Magnet",
        blurb: "Pull in nearby coins — 3 uses per level",
        iconEmoji: "🧲",
        duration: 3,
        charges: 3,
        magnetRadius: 110
    )
}
