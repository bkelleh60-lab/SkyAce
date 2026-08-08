import XCTest
import SpriteKit
@testable import SkyAce

/// SKY-66 / SKY-117 — asymmetric plane abilities. Covers the catalog wiring
/// (each plane carries its intended ability) and the parts of the behavior that
/// don't need a live scene: the Quick Climb burst impulse and the invincibility
/// flag.
final class PlaneAbilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ProgressManager.shared.resetAllProgress()
    }

    override func tearDown() {
        ProgressManager.shared.resetAllProgress()
        super.tearDown()
    }

    // MARK: - Catalog wiring (thematic mapping)

    /// Each plane maps to its intended ability kind (thematic wiring).
    func testEachPlaneHasItsIntendedAbility() {
        XCTAssertEqual(PlaneCatalog.redBaron.ability.kind, .invincibilityBurst)
        XCTAssertEqual(PlaneCatalog.blueSkyChaser.ability.kind, .quickClimb)
        XCTAssertEqual(PlaneCatalog.shadowDart.ability.kind, .speedBoost)
        XCTAssertEqual(PlaneCatalog.nightHawk.ability.kind, .coinMagnet)
    }

    /// `isActive` matches each ability kind: active kinds are HUD/tap-fired,
    /// the coin magnet is passive.
    func testActiveFlagMatchesKind() {
        XCTAssertTrue(PlaneCatalog.redBaron.ability.isActive)      // tap-fired
        XCTAssertTrue(PlaneCatalog.shadowDart.ability.isActive)    // tap-fired
        XCTAssertTrue(PlaneCatalog.blueSkyChaser.ability.isActive) // HUD-button-fired
        XCTAssertFalse(PlaneCatalog.nightHawk.ability.isActive)    // passive
    }

    // MARK: - Balance constants (single dial for tuning)

    /// Red Baron's invincibility burst is a short, single-charge save.
    func testInvincibilityIsShortAndSingleCharge() {
        // Per the ticket balance note: ~0.4s clears one obstacle but can't
        // carry a tight sequence, and it's one use per run.
        let a = PlaneCatalog.redBaron.ability
        XCTAssertEqual(a.duration, 0.4, accuracy: 0.001)
        XCTAssertEqual(a.charges, 1)
    }

    /// Shadow Dart's speed boost is cooldown-gated with an above-1 speed factor.
    func testSpeedBoostHasCooldownAndAboveOneFactor() {
        let a = PlaneCatalog.shadowDart.ability
        XCTAssertGreaterThan(a.speedBoostFactor, 1.0)
        XCTAssertGreaterThan(a.cooldown, 0)
        XCTAssertEqual(a.charges, 0) // cooldown-gated, not charge-limited
    }

    /// Quick Climb is active with two uses and a 1.8×–2× burst multiplier.
    func testQuickClimbIsActiveWithTwoUsesAndStrongMultiplier() {
        // Per SKY-117: two uses per level, and a burst multiplier in the
        // 1.8×–2× band so the jump reads as noticeably stronger than a tap.
        let a = PlaneCatalog.blueSkyChaser.ability
        XCTAssertTrue(a.isActive)
        XCTAssertEqual(a.charges, 2)
        XCTAssertGreaterThanOrEqual(a.climbMultiplier, 1.8)
        XCTAssertLessThanOrEqual(a.climbMultiplier, 2.0)
    }

    /// Night Hawk's coin magnet has a positive pull radius.
    func testCoinMagnetHasPositiveRadius() {
        XCTAssertGreaterThan(PlaneCatalog.nightHawk.ability.magnetRadius, 0)
    }

    // MARK: - Quick Climb burst (SKY-117)

    /// A Quick Climb burst from rest jumps higher than a normal tap and past
    /// the normal per-frame velocity cap.
    func testQuickClimbBurstIsStrongerThanANormalTap() {
        // A single tap from rest drives dy to the plane's climb impulse.
        let tap = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        tap.physicsBody?.velocity = .zero
        tap.climb()
        let tapDy = tap.physicsBody?.velocity.dy ?? 0

        // A Quick Climb burst from rest jumps well past that, exceeding even the
        // normal per-frame velocity cap (the raised burst ceiling permits it).
        let burst = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        burst.physicsBody?.velocity = .zero
        burst.quickClimb(multiplier: PlaneCatalog.blueSkyChaser.ability.climbMultiplier)
        let burstDy = burst.physicsBody?.velocity.dy ?? 0

        XCTAssertGreaterThan(burstDy, tapDy)
        XCTAssertGreaterThan(burstDy, PlaneNode.maxClimbVelocity)
    }

    /// An oversized multiplier is still clamped to the burst velocity ceiling.
    func testQuickClimbBurstRespectsTheBurstCeiling() {
        let plane = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        plane.physicsBody?.velocity = .zero
        plane.quickClimb(multiplier: 5.0) // absurd multiplier — must still clamp
        let dy = plane.physicsBody?.velocity.dy ?? 0
        XCTAssertLessThanOrEqual(dy, PlaneNode.maxBurstClimbVelocity)
    }

    /// A burst never lowers a climb that's already faster than the boosted value.
    func testQuickClimbDoesNotReduceAnAlreadyFasterClimb() {
        let plane = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        plane.physicsBody?.velocity = CGVector(dx: 0, dy: PlaneNode.maxBurstClimbVelocity)
        plane.quickClimb(multiplier: PlaneCatalog.blueSkyChaser.ability.climbMultiplier)
        let dy = plane.physicsBody?.velocity.dy ?? 0
        XCTAssertEqual(dy, PlaneNode.maxBurstClimbVelocity, accuracy: 0.001)
    }

    // MARK: - Invincibility flag

    /// Activating the invincibility burst sets the `isInvincible` flag.
    func testActivateInvincibilitySetsFlag() {
        let plane = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        XCTAssertFalse(plane.isInvincible)
        plane.activateInvincibility(duration: 0.4)
        XCTAssertTrue(plane.isInvincible)
    }

    /// Re-activating invincibility while it's already active is a safe no-op.
    func testActivateInvincibilityIsIdempotentWhileActive() {
        // A second tap during an active burst must not re-arm or throw; the
        // scene also gates on charges, but the node is defensive on its own.
        let plane = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        plane.activateInvincibility(duration: 0.4)
        plane.activateInvincibility(duration: 0.4)
        XCTAssertTrue(plane.isInvincible)
    }
}
