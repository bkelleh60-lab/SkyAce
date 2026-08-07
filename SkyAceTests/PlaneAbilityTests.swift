import XCTest
import SpriteKit
@testable import SkyAce

/// SKY-66 — asymmetric plane abilities. Covers the catalog wiring (each plane
/// carries its intended ability) and the parts of the behavior that don't need
/// a live scene: the passive glide climb multiplier, the passives gate, and the
/// invincibility flag.
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

    func testEachPlaneHasItsIntendedAbility() {
        XCTAssertEqual(PlaneCatalog.redBaron.ability.kind, .invincibilityBurst)
        XCTAssertEqual(PlaneCatalog.blueSkyChaser.ability.kind, .glideControl)
        XCTAssertEqual(PlaneCatalog.shadowDart.ability.kind, .speedBoost)
        XCTAssertEqual(PlaneCatalog.nightHawk.ability.kind, .coinMagnet)
    }

    func testActiveFlagMatchesKind() {
        XCTAssertTrue(PlaneCatalog.redBaron.ability.isActive)   // tap-fired
        XCTAssertTrue(PlaneCatalog.shadowDart.ability.isActive) // tap-fired
        XCTAssertFalse(PlaneCatalog.blueSkyChaser.ability.isActive) // passive
        XCTAssertFalse(PlaneCatalog.nightHawk.ability.isActive)     // passive
    }

    // MARK: - Balance constants (single dial for tuning)

    func testInvincibilityIsShortAndSingleCharge() {
        // Per the ticket balance note: ~0.4s clears one obstacle but can't
        // carry a tight sequence, and it's one use per run.
        let a = PlaneCatalog.redBaron.ability
        XCTAssertEqual(a.duration, 0.4, accuracy: 0.001)
        XCTAssertEqual(a.charges, 1)
    }

    func testSpeedBoostHasCooldownAndAboveOneFactor() {
        let a = PlaneCatalog.shadowDart.ability
        XCTAssertGreaterThan(a.speedBoostFactor, 1.0)
        XCTAssertGreaterThan(a.cooldown, 0)
        XCTAssertEqual(a.charges, 0) // cooldown-gated, not charge-limited
    }

    func testGlideSoftensDescentAndSharpensClimb() {
        let a = PlaneCatalog.blueSkyChaser.ability
        XCTAssertGreaterThan(a.climbMultiplier, 1.0)
        XCTAssertLessThan(a.descentGravityMultiplier, 1.0)
    }

    func testCoinMagnetHasPositiveRadius() {
        XCTAssertGreaterThan(PlaneCatalog.nightHawk.ability.magnetRadius, 0)
    }

    // MARK: - PlaneNode passive gate + glide climb

    func testPassivesDisabledByDefault() {
        let plane = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        XCTAssertFalse(plane.passivesEnabled,
                       "Passives must be off by default so Free Flight / Landing Practice are untouched.")
    }

    func testGlideClimbMultiplierAppliesOnlyWhenPassivesEnabled() {
        // A single tap from rest drives dy to the (multiplied) climb impulse.
        let base = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        base.physicsBody?.velocity = .zero
        base.climb()
        let baselineDy = base.physicsBody?.velocity.dy ?? 0

        let glide = PlaneNode(planeID: PlaneCatalog.blueSkyChaser.id)
        glide.passivesEnabled = true
        glide.physicsBody?.velocity = .zero
        glide.climb()
        let glideDy = glide.physicsBody?.velocity.dy ?? 0

        let expected = baselineDy * PlaneCatalog.blueSkyChaser.ability.climbMultiplier
        XCTAssertEqual(glideDy, expected, accuracy: 0.5,
                       "Glide passive should scale the climb impulse by climbMultiplier.")
        XCTAssertGreaterThan(glideDy, baselineDy)
    }

    func testNonGlidePlaneClimbUnaffectedByPassivesFlag() {
        // Red Baron's ability has a 1.0 climb multiplier, so enabling passives
        // must not change its climb.
        let off = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        off.physicsBody?.velocity = .zero
        off.climb()
        let dyOff = off.physicsBody?.velocity.dy ?? 0

        let on = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        on.passivesEnabled = true
        on.physicsBody?.velocity = .zero
        on.climb()
        let dyOn = on.physicsBody?.velocity.dy ?? 0

        XCTAssertEqual(dyOff, dyOn, accuracy: 0.001)
    }

    // MARK: - Invincibility flag

    func testActivateInvincibilitySetsFlag() {
        let plane = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        XCTAssertFalse(plane.isInvincible)
        plane.activateInvincibility(duration: 0.4)
        XCTAssertTrue(plane.isInvincible)
    }

    func testActivateInvincibilityIsIdempotentWhileActive() {
        // A second tap during an active burst must not re-arm or throw; the
        // scene also gates on charges, but the node is defensive on its own.
        let plane = PlaneNode(planeID: PlaneCatalog.redBaron.id)
        plane.activateInvincibility(duration: 0.4)
        plane.activateInvincibility(duration: 0.4)
        XCTAssertTrue(plane.isInvincible)
    }
}
