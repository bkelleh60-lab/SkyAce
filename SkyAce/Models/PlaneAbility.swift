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

    enum Kind {
        case invincibilityBurst   // active
        case speedBoost           // active
        case glideControl         // passive
        case coinMagnet           // passive
    }

    let kind: Kind

    /// True for player-fired abilities (invincibility, speed boost); false for
    /// passives that apply automatically. Drives whether GameScene shows the
    /// HUD ability button.
    let isActive: Bool

    /// Short display name (Hangar ability line, e.g. "Overdrive").
    let displayName: String

    /// One-line description for the Hangar plane card.
    let blurb: String

    /// HUD/emoji glyph, reused in the ability button and the Hangar line. Kept
    /// as an emoji so no new art asset is required (matches the armor "🛡"
    /// badge convention).
    let iconEmoji: String

    // MARK: - Active tuning (ignored for passives)

    /// Seconds the burst / boost lasts.
    let duration: TimeInterval

    /// Uses per run. 0 means "unlimited, gated only by `cooldown`".
    let charges: Int

    /// Seconds between uses for cooldown-gated actives (speed boost).
    let cooldown: TimeInterval

    // MARK: - Passive tuning (no-op defaults for actives)

    /// glideControl: multiplier on the plane's climb impulse (>1 = crisper).
    let climbMultiplier: CGFloat

    /// glideControl: fraction of world gravity felt while descending
    /// (<1 = slower, more controlled fall).
    let descentGravityMultiplier: CGFloat

    /// speedBoost: world-scroll speed multiplier applied for `duration`.
    let speedBoostFactor: CGFloat

    /// coinMagnet: radius (points) within which coins are pulled toward the plane.
    let magnetRadius: CGFloat

    init(
        kind: Kind,
        isActive: Bool,
        displayName: String,
        blurb: String,
        iconEmoji: String,
        duration: TimeInterval = 0,
        charges: Int = 0,
        cooldown: TimeInterval = 0,
        climbMultiplier: CGFloat = 1.0,
        descentGravityMultiplier: CGFloat = 1.0,
        speedBoostFactor: CGFloat = 1.0,
        magnetRadius: CGFloat = 0
    ) {
        self.kind = kind
        self.isActive = isActive
        self.displayName = displayName
        self.blurb = blurb
        self.iconEmoji = iconEmoji
        self.duration = duration
        self.charges = charges
        self.cooldown = cooldown
        self.climbMultiplier = climbMultiplier
        self.descentGravityMultiplier = descentGravityMultiplier
        self.speedBoostFactor = speedBoostFactor
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

    /// Blue Sky Chaser — passive glide: crisper climb, softer descent for a
    /// higher control ceiling. Mild so it aids control without breaking pace.
    static let glideControl = PlaneAbility(
        kind: .glideControl,
        isActive: false,
        displayName: "Glide Control",
        blurb: "Crisper climb, gentler descent",
        iconEmoji: "🪶",
        climbMultiplier: 1.12,
        descentGravityMultiplier: 0.85
    )

    /// Shadow Dart — active overdrive: ~1.5s of ×1.5 world speed on a 5s
    /// cooldown. High risk/reward: more ground (and coins) but less reaction
    /// time. Self-limiting on obstacle levels.
    static let speedBoost = PlaneAbility(
        kind: .speedBoost,
        isActive: true,
        displayName: "Overdrive",
        blurb: "Speed burst on tap — short cooldown",
        iconEmoji: "⚡️",
        duration: 1.5,
        charges: 0,
        cooldown: 5.0,
        speedBoostFactor: 1.5
    )

    /// Night Hawk — passive coin magnet: pulls nearby coins in, trading the
    /// bomber's bulk for easier collection.
    static let coinMagnet = PlaneAbility(
        kind: .coinMagnet,
        isActive: false,
        displayName: "Coin Magnet",
        blurb: "Pulls in nearby coins",
        iconEmoji: "🧲",
        magnetRadius: 110
    )
}
