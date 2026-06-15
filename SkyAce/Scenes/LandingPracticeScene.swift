import SpriteKit

/// Free Flight — Landing Practice (SKY-83, approach redesign SKY-94).
///
/// A pure-sandbox third Free Flight mode with a two-phase approach:
///
/// * **Free approach** — the runway cruises in from the right and keeps
///   scrolling (tiles recycle) while the player flies hold-to-climb /
///   release-to-descend, choosing when to start the landing.
/// * **Final approach** — descending through the approach window
///   (`approachAltitudeThresholdFraction`) commits the landing: the runway
///   decelerates, the landing zone is revealed where the deceleration will
///   halt it (the plane's X lane), and controls invert to tap-to-correct
///   ("keep the nose up") for fine descent-rate management to touchdown.
///
/// Touchdown reads vertical velocity into one of three quality tiers. No
/// fail state — every outcome auto-resets into a fresh approach.
///
/// Architecture is Option A from docs/landing-practice-movement-investigation.md:
/// modeled on FreeFlightCityScene (fixed-X plane, world moves, no camera),
/// with the FinishLineNode contact pattern repurposed as LandingZoneNode.
final class LandingPracticeScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Tunable approach constants (SKY-94, Connor's playtest dials)

    /// Constant runway scroll speed during the free approach phase (pt/s).
    static let approachScrollSpeed: CGFloat = 200

    /// The approach window: descending below this fraction of scene height
    /// commits the landing — the runway decelerates, the landing zone
    /// appears, and controls switch to tap-to-correct.
    static let approachAltitudeThresholdFraction: CGFloat = 0.35

    /// Upward correction added to the plane's dy per tap on final approach
    /// (pt/s). Deliberately a fraction of the Phase-1 climb impulse (base
    /// 320): against the gentle committed-descent gravity (~300 pt/s²,
    /// `committedDescentGravity`) a steady ~2 taps/s roughly cancels gravity
    /// for a slow, gentle descent (Smooth), while sparser taps drift toward
    /// Rough and doing nothing toward Crash. One tap ≈ a 140 pt/s save.
    static let finalApproachTapImpulse: CGFloat = 140

    /// How quickly the runway sheds speed once the approach window opens
    /// (pt/s²). Stopping distance (v²/2a ≈ 80pt) and duration (v/a ≈ 0.8s)
    /// both derive from this and `approachScrollSpeed`. Kept short enough
    /// that the zone finishes aligning at the lane before the continuously
    /// descending plane can reach the touchdown sensor — even the slowest
    /// case, the smallest phone's ~1.2s no-tap fall, outlasts it — so the
    /// plane always touches down on an aligned zone.
    static let runwayDecelerationRate: CGFloat = 250

    /// Pause between the threshold crossing and the landing zone fade-in
    /// (0.0–0.5s) — a beat of "the runway is slowing… there's the zone".
    static let landingZoneRevealDelay: TimeInterval = 0.15

    /// Gentle gravity (SpriteKit accel units; ×150 ⇒ pt/s²) applied to the
    /// plane for the committed final descent — swapped in at the threshold
    /// crossing and restored to `PlaneNode.gravity` on the next approach.
    /// Far softer than flight gravity (-5.0) so tap-to-correct has real
    /// authority and the player gets a full second-plus to feather the
    /// touchdown rather than the old build's half-second plummet.
    static let committedDescentGravity: CGFloat = -2.0

    /// Floor on descent speed during the committed final approach (pt/s),
    /// tighter than the flight body's -400. Device-independent: however far
    /// the plane still has to fall, an untouched descent tops out here, so a
    /// tall iPad screen can't amplify the fall into a distance-driven slam.
    /// Sits just inside the Crash band so doing nothing still risks a Crash
    /// while any reasonable tapping escapes it.
    static let committedTerminalVelocity: CGFloat = -370

    // MARK: - Tunable landing constants (Connor's playtest dials)
    //
    // Velocity tiers are calibrated against the SKY-94 *continuous* committed
    // descent (no park-and-drop): the instant the player commits at the
    // approach window, gravity softens to `committedDescentGravity` and the
    // plane sinks under live tap-to-correct all the way to the sensor
    // (contact at center ≈ surface + 26.5). Tap authority
    // (`finalApproachTapImpulse`) plus the gentle gravity make the touchdown
    // rate the player's to manage the whole way down:
    //   no taps → drifts to the committed terminal (≈ -370 on a long fall) → Crash
    //   a tap here and there → ~ -200…-330 → Rough
    //   a steady ~2 tap/s feather holds dy shallow → Smooth
    // Because gravity is gentle and the descent is continuous from the commit
    // altitude, the input matters from the instant the "Tap to correct!" cue
    // appears. The old build's 2s parked dead-zone — taps doing nothing, then
    // a sudden half-second plummet as the runway halted — is gone.

    /// Touchdown dy at or above this reads as a Smooth Landing.
    static let smoothLandingMaxDescent: CGFloat = -180
    /// Touchdown dy at or above this (and below smooth) is a Rough Landing;
    /// anything faster is a Crash Landing.
    static let roughLandingMaxDescent: CGFloat = -340

    /// Seconds each landing result is held on screen before the approach
    /// auto-resets, per tier.
    static let smoothResetDelay: TimeInterval = 2.5
    static let roughResetDelay: TimeInterval = 2.5
    static let crashResetDelay: TimeInterval = 1.5

    // MARK: - Derived approach geometry

    /// Altitude (points) below which the final approach activates.
    private var approachAltitudeThreshold: CGFloat {
        size.height * Self.approachAltitudeThresholdFraction
    }
    /// Ground the runway covers while decelerating: v² / 2a.
    private var decelStoppingDistance: CGFloat {
        Self.approachScrollSpeed * Self.approachScrollSpeed
            / (2 * Self.runwayDecelerationRate)
    }
    /// Time the deceleration takes: v / a.
    private var decelDuration: TimeInterval {
        TimeInterval(Self.approachScrollSpeed / Self.runwayDecelerationRate)
    }

    // MARK: - Layout constants

    /// Screen Y of the runway strip's top edge (LandingZoneNode origin).
    private var groundY: CGFloat { 150 }
    /// Screen Y of the visual touchdown line — the road's centerline
    /// dashes, `surfaceDrop` below the strip top. All landing geometry
    /// keys off this so the plane sits *in* the road with its wheels on
    /// the dashes, matching the art's gentle perspective.
    private var touchdownSurfaceY: CGFloat { groundY - (runway?.surfaceDrop ?? 0) }
    /// Plane lane — same fraction as the Free Flight scenes.
    private var laneX: CGFloat { size.width * 0.28 }
    /// Plane spawn altitude at the start of each approach.
    private var planeStartY: CGFloat { size.height * 0.55 }
    /// Ceiling the plane is clamped below so it never leaves the top of screen.
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Floor during the free approach phase — set to the approach window
    /// itself so the plane commits from a consistent altitude. The descent
    /// distance (and thus the time the runway has to finish aligning) no
    /// longer depends on how early the player dived: they fly the band above
    /// this line and commit by descending onto it.
    private var approachFloorY: CGFloat { approachAltitudeThreshold }
    /// Backstop floor for the committed descent — just below the sensor so
    /// the plane is stopped by the touchdown contact (center ≈ surface +
    /// 26.5), not by this clamp. The descent rate is preserved for the tier
    /// read because the contact fires before this line is reached.
    private var landingFloorY: CGFloat { touchdownSurfaceY + 16 }
    /// Where the plane settles so its wheels sit on the touchdown line:
    /// gear-down wheel bottoms sit 22–30pt below the node center at the
    /// 2x visual scale, so center at +26 grazes the line for all four
    /// planes.
    private var landedPlaneY: CGFloat { touchdownSurfaceY + 26 }

    /// Continuous hold (seconds) during the committed descent that triggers a
    /// go-around instead of a correction tap. Comfortably longer than a
    /// feathering tap (~0.1s) so trimming the descent can't abort by accident,
    /// short enough that "hold to climb out" feels immediate.
    static let goAroundHoldDuration: TimeInterval = 0.3

    // MARK: - State

    /// The approach lifecycle: free approach → committed final approach →
    /// halted runway → landed → resetting back into a fresh approach.
    private enum Phase { case freeApproach, finalApproach, halted, landed, resetting }

    /// Current approach phase.
    private var phase: Phase = .freeApproach
    /// Container for everything that scrolls and shakes (the HUD sits outside it).
    private let worldNode = SKNode()
    /// Overlay above the world for landing badges and result text.
    private let feedbackLayer = SKNode()
    // Implicitly unwrapped: both are built in layoutScene() (didMove /
    // didChangeSize rebuild) before any touch or update path can run, and
    // update() additionally guards plane against the teardown window.
    private var plane: PlaneNode!
    private var runway: LandingZoneNode!
    /// True while a finger is down — drives climb in free approach and the
    /// hold detection on final approach.
    private var isTouching = false
    /// Wall-clock time the current committed-descent touch began, for
    /// distinguishing a correction tap from a held go-around. Nil unless a
    /// finger is down during `.finalApproach`/`.halted`.
    private var committedTouchStartTime: TimeInterval?
    /// True from a go-around trigger until the plane has climbed back up
    /// through the approach window. While set, the free-approach floor drops
    /// to a low ground line (so the abort climb isn't yanked upward) and the
    /// commit check is suppressed (so it doesn't immediately re-commit from
    /// below the window).
    private var isGoingAround = false
    /// Timestamp of the previous `update(_:)`, for manual delta-time integration.
    private var lastUpdateTime: TimeInterval = 0
    private weak var instructionPrompt: SKLabelNode?

    // MARK: - Lifecycle

    /// Sets gravity and the contact delegate, builds the scene, and starts the
    /// per-plane engine loop.
    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        physicsWorld.contactDelegate = self
        SkyHaptics.prepare()
        layoutScene()

        AudioManager.shared.playEngineLoop(
            SkyEngineLoop.filename(forPlaneID: ProgressManager.shared.selectedPlaneID)
        )
    }

    /// Stops the engine loop as the scene is torn down.
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        AudioManager.shared.stopEngineLoop()
    }

    // SKY-55: see FreeFlightCityScene.didChangeSize — sandbox mode with no
    // run state worth preserving, so tear down and rebuild for the new
    // dimensions. The current approach restarts; acceptable on a deliberate
    // device rotation.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, worldNode.parent != nil else { return }
        worldNode.removeAllChildren()
        worldNode.removeAllActions()
        worldNode.removeFromParent()
        feedbackLayer.removeAllChildren()
        feedbackLayer.removeFromParent()
        plane = nil
        runway = nil
        phase = .freeApproach
        isTouching = false
        isGoingAround = false
        committedTouchStartTime = nil
        lastUpdateTime = 0
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    /// Builds the sky, runway, plane, and HUD, then opens the first approach.
    private func layoutScene() {
        addChild(worldNode)
        buildSky()
        buildRunway()
        buildPlane()
        buildTopBar()
        feedbackLayer.zPosition = 150
        addChild(feedbackLayer)
        showInstructionPromptIfFirstLaunch()
        beginApproach()
    }

    // MARK: - Sky

    /// Adds the golden-hour gradient backdrop behind the world.
    private func buildSky() {
        let bg = SKSpriteNode(texture: Self.goldenHourTexture(size: size), size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        worldNode.addChild(bg)
    }

    /// Golden-hour gradient: deep amber at the top of the sky blending to a
    /// warm pale yellow at the horizon, held constant below the ground line
    /// so the glow sits right where the runway meets the sky. Rendered with
    /// explicit endpoints (start at (0,0) so gradient location 0 lands at
    /// the sprite top — see FreeFlightCityScene.skyGradientTexture for why
    /// the shared helper's labels can't be trusted here).
    private static func goldenHourTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(hex: 0xC97B2A).cgColor,
                UIColor(hex: 0xF5E6C0).cgColor,
                UIColor(hex: 0xF5E6C0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.8, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }

    // MARK: - Runway

    /// Creates the runway/landing-zone node off-screen right, ready to cruise in.
    private func buildRunway() {
        runway = LandingZoneNode(sceneWidth: size.width)
        runway.position = CGPoint(x: offscreenRunwayX, y: groundY)
        runway.zPosition = -10
        worldNode.addChild(runway)
    }

    /// Origin X that puts the tarmac's leading edge past the right screen
    /// edge, ready to cruise in.
    private var offscreenRunwayX: CGFloat {
        runway.startOriginX(sceneWidth: size.width)
    }

    /// Opens a fresh free approach: gravity on, hold-to-climb live, runway
    /// cruising in from the right at constant speed (driven from
    /// `update(_:)` so it can scroll indefinitely while tiles recycle). The
    /// approach stays open — no scripted halt — until the plane descends
    /// through the approach window.
    private func beginApproach() {
        phase = .freeApproach
        isGoingAround = false
        committedTouchStartTime = nil
        // Restore full flight gravity — the previous approach's committed
        // descent softened it to `committedDescentGravity`.
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        // Gravity stays off through the reset fade (update() doesn't clamp
        // position while resetting, so the plane would sink); it turns back
        // on only when the approach — and the position clamp — are live.
        plane.physicsBody?.velocity = .zero
        plane.physicsBody?.affectedByGravity = true
    }

    /// The commit moment (SKY-94): the plane has descended through the
    /// approach window, so the runway begins its deceleration, the landing
    /// zone is revealed where the deceleration will halt it, the gear
    /// deploys, and controls invert to tap-to-correct.
    private func beginFinalApproach() {
        phase = .finalApproach
        // A finger still held from Phase 1 must not keep climbing — final
        // approach input is discrete taps (or a held go-around) only.
        isTouching = false
        committedTouchStartTime = nil

        // Soften gravity for the committed descent so tap-to-correct has real
        // authority and the player has time to feather the touchdown. Restored
        // to full flight gravity by `beginApproach()` on the next pass.
        physicsWorld.gravity = CGVector(dx: 0, dy: Self.committedDescentGravity)

        // Red Baron MK-1 has fixed gear baked into its base art — the
        // deploy trigger must not fire anything for it: no sprite swap
        // and no gear SFX, ever (SKY-83 playtest bug 1).
        if ProgressManager.shared.selectedPlaneID != "red_baron" {
            plane.setLandingGear(deployed: true)
        }

        // Halt geometry: the runway sheds `approachScrollSpeed` at
        // `runwayDecelerationRate`, covering v²/2a more points. Re-anchor
        // the still-hidden zone exactly that far right of the lane (the
        // tarmac doesn't move — only the origin jumps) so the deceleration
        // ends with the zone on the plane's X lane.
        runway.realignOrigin(toX: laneX + decelStoppingDistance)

        // Ease-out over T = v/a: average speed v/2 means the curve's
        // initial slope matches the cruise speed, so the handoff from
        // constant scroll doesn't pop.
        let decel = SKAction.moveTo(x: laneX, duration: decelDuration)
        decel.timingMode = .easeOut
        runway.run(SKAction.sequence([
            decel,
            // Only advance to .halted if still in the committed descent. The
            // continuous descent can reach the runway a frame before the decel
            // finishes — that touchdown has already moved us to .landed (and a
            // held go-around to .freeApproach). This stale completion must not
            // clobber that phase: doing so left `.landed` reading as `.halted`,
            // which failed the reset guard and hung the scene (plane frozen
            // with gravity off, so restart taps climbed it to the top).
            SKAction.run { [weak self] in
                if self?.phase == .finalApproach { self?.phase = .halted }
            }
        ]))

        run(SKAction.sequence([
            SKAction.wait(forDuration: Self.landingZoneRevealDelay),
            SKAction.run { [weak self] in self?.runway.setZoneRevealed(true, fade: 0.3) }
        ]), withKey: "revealZone")

        showTapToCorrectCue()
    }

    // MARK: - Plane

    /// Spawns the player's plane at the lane start with the landing sensor as
    /// its only contact interest (nothing else collects or crashes here).
    private func buildPlane() {
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 2.0)
        plane.position = CGPoint(x: laneX, y: planeStartY)
        plane.zPosition = 10
        // Sandbox: only the touchdown sensor matters — nothing can crash
        // or collect in this mode.
        plane.physicsBody?.categoryBitMask = PhysicsCategory.plane
        plane.physicsBody?.contactTestBitMask = PhysicsCategory.landingZone
        plane.physicsBody?.collisionBitMask = 0
        worldNode.addChild(plane)
    }

    // MARK: - Top bar

    /// Lays out the EXIT button and mode title in the top safe-area bar.
    private func buildTopBar() {
        let topSafeInset = view?.safeAreaInsets.top ?? 0
        let barCenterY = size.height - topSafeInset - 20

        let exit = SkyPillButton(
            title: "EXIT",
            style: .surface,
            size: CGSize(width: 76, height: 32)
        ) { SkyNavigator.shared.showMenu() }
        exit.position = CGPoint(x: 52, y: barCenterY)
        exit.zPosition = 200
        addChild(exit)

        let label = SKLabelNode(text: "LANDING PRACTICE")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: barCenterY)
        label.zPosition = 200
        addChild(label)
    }

    // MARK: - First-time instruction prompt

    /// Shows the one-time "Hold to climb. Release to descend." prompt on the
    /// player's first-ever Landing Practice session.
    private func showInstructionPromptIfFirstLaunch() {
        guard !ProgressManager.shared.landingPracticeInstructionShown else { return }
        ProgressManager.shared.landingPracticeInstructionShown = true

        let prompt = SKLabelNode(text: "Hold to climb. Release to descend.")
        prompt.fontName = SkyFonts.headlineName
        prompt.fontSize = 20
        prompt.fontColor = .white
        prompt.verticalAlignmentMode = .center
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        prompt.zPosition = 150
        prompt.alpha = 0
        addChild(prompt)
        instructionPrompt = prompt
        prompt.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Final approach cue

    /// "Tap to correct!" — shown on every threshold crossing, not just the
    /// first launch: the control inversion needs re-anchoring each approach.
    private func showTapToCorrectCue() {
        presentApproachCue("Tap to correct!", hold: 1.6)
    }

    /// The single transient cue slot near the top of the play area. Showing a
    /// new cue evicts any cue (or first-launch instruction) already there so
    /// two never overlap — e.g. "Tap to correct!" still fading when a held
    /// go-around fires "Go around!".
    private weak var approachCue: SKLabelNode?
    /// Fades `text` into the cue slot, holds it for `hold` seconds, then fades out.
    private func presentApproachCue(_ text: String, hold: TimeInterval) {
        instructionPrompt?.removeAllActions()
        instructionPrompt?.removeFromParent()
        approachCue?.removeAllActions()
        approachCue?.removeFromParent()

        let cue = SKLabelNode(text: text)
        cue.fontName = SkyFonts.headlineName
        cue.fontSize = 20
        cue.fontColor = .white
        cue.verticalAlignmentMode = .center
        cue.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        cue.zPosition = 150
        cue.alpha = 0
        addChild(cue)
        approachCue = cue
        cue.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: hold),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Go-around

    /// Powers out of a committed landing: the player held instead of tapping,
    /// so climb away, stow the gear, hide the zone, and hand the runway back
    /// to the free-approach scroll for a fresh setup. The held finger keeps
    /// driving `plane.climb()` in `update()` (phase is back to `.freeApproach`)
    /// until released, so a hold reads as "power up and away".
    private func goAround() {
        isGoingAround = true
        phase = .freeApproach
        committedTouchStartTime = nil

        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        plane.physicsBody?.affectedByGravity = true
        plane.climb()

        // Stow the gear (Red Baron's is fixed in its base art — leave it).
        if ProgressManager.shared.selectedPlaneID != "red_baron" {
            plane.setLandingGear(deployed: false)
        }

        // Hand the tarmac back to the free-approach scroll: cancel the
        // deceleration (and its pending halt), drop the still-pending zone
        // reveal, and conceal the zone. update() resumes scrolling it left.
        runway.removeAllActions()
        removeAction(forKey: "revealZone")
        runway.setZoneRevealed(false, fade: 0.3)

        showGoAroundCue()
    }

    /// "Go around!" — brief confirmation that the abort took. Evicts the
    /// still-fading "Tap to correct!" cue so the two don't overlap.
    private func showGoAroundCue() {
        presentApproachCue("Go around!", hold: 1.2)
    }

    // MARK: - Update

    /// Per-frame driver: scrolls the runway, applies climb/tap input, detects
    /// the commit and go-around moments, clamps the committed descent, and holds
    /// the plane to its phase floor.
    override func update(_ currentTime: TimeInterval) {
        // The cruise scroll is integrated manually so it can run for an
        // unbounded free approach; clamp dt so a frame hitch can't
        // teleport the runway.
        let delta: TimeInterval = lastUpdateTime == 0
            ? 0
            : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime

        guard let plane = plane else { return }

        if phase == .freeApproach {
            runway.position.x -= Self.approachScrollSpeed * CGFloat(delta)
        }
        if phase == .freeApproach || phase == .finalApproach {
            runway.updateTiling(in: self)
        }

        if isTouching && phase == .freeApproach { plane.climb() }
        plane.update()

        let controlsLive = phase == .freeApproach || phase == .finalApproach || phase == .halted
        guard controlsLive else { return }

        // Go-around: a sustained hold during the committed descent (vs. a
        // brief correction tap) powers the plane out of the landing and
        // reopens a fresh approach.
        if phase == .finalApproach || phase == .halted,
           isTouching,
           let start = committedTouchStartTime,
           currentTime - start >= Self.goAroundHoldDuration {
            goAround()
        }

        // The commit moment: the plane sinks through the approach window
        // while the runway is established beneath it (leading edge past the
        // screen's left edge — descending any earlier just rides Phase 1's
        // floor until the tarmac arrives). Suppressed mid-go-around so the
        // abort climb doesn't instantly re-commit from below the window.
        if phase == .freeApproach, !isGoingAround,
           plane.position.y <= approachAltitudeThreshold,
           runway.leadingEdgeX(in: self) <= 0 {
            beginFinalApproach()
        }

        // Clamp the committed descent to a gentle, device-independent terminal
        // so an untouched fall tops out in (at worst) the Crash band near
        // `committedTerminalVelocity` rather than accelerating without bound
        // over a tall screen.
        if phase == .finalApproach || phase == .halted,
           let pb = plane.physicsBody,
           pb.velocity.dy < Self.committedTerminalVelocity {
            pb.velocity.dy = Self.committedTerminalVelocity
        }

        if phase == .freeApproach {
            // The window is the resting floor: a plane descending onto it
            // (dy ≤ 0) is held there until commit, giving a consistent commit
            // altitude. During a go-around the plane starts *below* the window
            // climbing out, so the floor drops to a low ground line and never
            // yanks the climb upward; once it clears the window the abort ends
            // and normal commit rules resume.
            let floor = isGoingAround ? (touchdownSurfaceY + 50) : approachFloorY
            if plane.position.y <= floor, let pb = plane.physicsBody, pb.velocity.dy <= 0 {
                plane.position.y = floor
                pb.velocity.dy = 0
            }
            if isGoingAround, plane.position.y >= approachAltitudeThreshold {
                isGoingAround = false
            }
        } else if plane.position.y <= landingFloorY {
            // Committed backstop — the touchdown contact normally stops the
            // plane above this line (preserving its descent rate for the tier
            // read); this only catches a contact that didn't fire.
            plane.position.y = landingFloorY
        }
        plane.position.y = min(planeMaxY, plane.position.y)
        plane.position.x += (laneX - plane.position.x) * 0.12
    }

    // MARK: - Touchdown

    /// Physics contact entry point — routes a plane↔landing-zone touch to the
    /// touchdown handler.
    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard categories == PhysicsCategory.plane | PhysicsCategory.landingZone else { return }
        handleLandingZoneContact()
    }

    /// Resolves a touchdown: freezes and settles the plane onto the tarmac, then
    /// dispatches to the smooth/rough/crash tier by its descent rate.
    private func handleLandingZoneContact() {
        // Accept the touchdown across the whole committed descent, not just at
        // full halt. The sensor rides with the runway, so a contact can only
        // physically begin once the zone has slid within a hitbox-width of the
        // lane — i.e. the runway is aligned (or all but). Guarding only on
        // `.halted` could drop a touchdown that lands a frame before the decel
        // action's completion handler flips the phase.
        guard phase == .finalApproach || phase == .halted else { return }
        let descentRate = plane.physicsBody?.velocity.dy ?? 0
        phase = .landed
        isTouching = false
        committedTouchStartTime = nil

        // Clear any feedback still on screen from a prior approach so this
        // tier's visuals can never overlap (e.g. a lingering smooth badge
        // showing behind fresh "Bumpy" text).
        feedbackLayer.removeAllActions()
        feedbackLayer.removeAllChildren()
        feedbackLayer.alpha = 1

        // Freeze the plane and settle it onto the tarmac. Attitude is
        // per-tier: clean landings flare nose-up; crashes keep the frozen
        // nose-down descent tilt under the dust cloud (reset re-levels).
        plane.physicsBody?.velocity = .zero
        plane.physicsBody?.affectedByGravity = false
        let settle = SKAction.move(
            to: CGPoint(x: laneX, y: landedPlaneY),
            duration: 0.15
        )
        settle.timingMode = .easeOut
        plane.run(settle)

        if descentRate >= Self.smoothLandingMaxDescent {
            handleSmoothLanding()
        } else if descentRate >= Self.roughLandingMaxDescent {
            handleRoughLanding()
        } else {
            handleCrashLanding()
        }
    }

    /// Smooth-tier feedback: touchdown chime, nose-up flare, win haptic, badge,
    /// and — unless today's daily cap is reached — the +50 coin reward (SKY-95).
    private func handleSmoothLanding() {
        run(SKAction.sequence([
            AudioManager.shared.sfxAction(SkySFX.landingTouchdown, fileExtension: "caf"),
            SKAction.wait(forDuration: 0.25),
            AudioManager.shared.sfxAction(SkySFX.landingSuccess, fileExtension: "caf")
        ]))
        plane.playTouchdownFlare()
        SkyHaptics.win()
        showCelebrationBadge()

        // SKY-95: grant 50 coins per smooth landing, capped at 500/day. The
        // daily-cap bookkeeping and coin grant live in CurrencyManager; it
        // returns 0 once the cap is reached, in which case no pill is shown and
        // the badge stands alone.
        let reward = CurrencyManager.shared.grantLandingPracticeSmoothLandingReward()
        if reward > 0 {
            showCoinRewardPill(amount: reward)
        }

        scheduleReset(after: Self.smoothResetDelay)
    }

    /// Pops the shared coin-reward pill in below the celebration badge, timed to
    /// land just after the badge's scale-in so the two read in sequence.
    private func showCoinRewardPill(amount: Int) {
        let pill = CoinRewardPill(amount: amount)
        pill.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        pill.zPosition = 1
        pill.alpha = 0
        feedbackLayer.addChild(pill)
        pill.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.45),
            SKAction.run { [weak pill] in pill?.animateIn() }
        ]))
    }

    /// Rough-tier feedback: impact sound, bounce, world shake, "Bumpy" text.
    private func handleRoughLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingRough, fileExtension: "caf"))
        SkyHaptics.hit()

        // Visual bounce off the tarmac, then a brief shake. No fanfare —
        // the missing celebration is the feedback.
        plane.playTouchdownFlare()
        plane.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 16, duration: 0.12),
            SKAction.moveBy(x: 0, y: -16, duration: 0.14)
        ]))
        shakeWorld(amplitude: 7)
        showFeedbackText("Bumpy Landing")
        scheduleReset(after: Self.roughResetDelay)
    }

    /// Crash-tier feedback: impact sound, hard shake, dust burst, retry text.
    private func handleCrashLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingCrash, fileExtension: "caf"))
        SkyHaptics.fail()
        shakeWorld(amplitude: 12)
        burstDustCloud(at: CGPoint(x: laneX, y: touchdownSurfaceY + 12))
        showFeedbackText("Crash — try again!")
        scheduleReset(after: Self.crashResetDelay)
    }

    // MARK: - Feedback visuals

    /// Pops the smooth-landing badge (or a gold fallback) into the feedback layer.
    private func showCelebrationBadge() {
        let width = min(size.width - 90, 300)
        let badgeSize: CGSize
        let badge: SKSpriteNode
        if let texture = SkySprites.texture(named: SkySprites.badgeSmoothLanding) {
            let aspect = texture.size().width > 0
                ? texture.size().height / texture.size().width
                : 0.9
            badgeSize = CGSize(width: width, height: width * aspect)
            badge = SKSpriteNode(texture: texture, size: badgeSize)
        } else {
            // Asset missing — keep the moment celebratory with a plain gold
            // burst so the tier still reads.
            badgeSize = CGSize(width: width, height: width * 0.6)
            badge = SKSpriteNode(color: UIColor(hex: 0xFFD709), size: badgeSize)
        }
        badge.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        badge.setScale(0.01)
        feedbackLayer.addChild(badge)

        let pop = SKAction.sequence([
            SKAction.scale(to: 1.08, duration: 0.28),
            SKAction.scale(to: 1.0, duration: 0.12)
        ])
        pop.timingMode = .easeOut
        badge.run(pop)
    }

    /// Fades a single line of result text into the feedback layer.
    private func showFeedbackText(
        _ text: String,
        color: UIColor = .white,
        y: CGFloat = 0.62
    ) {
        let label = SKLabelNode(text: text)
        label.fontName = SkyFonts.headlineName
        label.fontSize = 24
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * y)
        label.alpha = 0
        feedbackLayer.addChild(label)
        label.run(SKAction.fadeIn(withDuration: 0.2))
    }

    /// Decaying net-zero jolt on the world container — HUD stays put.
    private func shakeWorld(amplitude: CGFloat) {
        var actions: [SKAction] = []
        var a = amplitude
        for _ in 0..<3 {
            actions.append(SKAction.moveBy(x: a, y: -a * 0.6, duration: 0.04))
            actions.append(SKAction.moveBy(x: -2 * a, y: a * 1.2, duration: 0.05))
            actions.append(SKAction.moveBy(x: a, y: -a * 0.6, duration: 0.04))
            a *= 0.55
        }
        worldNode.run(SKAction.sequence(actions))
    }

    /// Emits a short-lived dust burst at the crash touchdown point.
    private func burstDustCloud(at point: CGPoint) {
        guard let texture = SkySprites.texture(named: SkySprites.dustCloud) else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.numParticlesToEmit = 12
        emitter.particleBirthRate = 60
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.3
        emitter.position = point
        emitter.particlePositionRange = CGVector(dx: 50, dy: 8)
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 0.9
        emitter.particleSpeed = 90
        emitter.particleSpeedRange = 50
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.1
        emitter.particleScale = 0.14
        emitter.particleScaleRange = 0.08
        emitter.particleScaleSpeed = 0.18
        emitter.yAcceleration = -60
        emitter.zPosition = 20
        worldNode.addChild(emitter)
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Reset

    /// Schedules `resetForNextApproach()` to run after `delay` seconds.
    private func scheduleReset(after delay: TimeInterval) {
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.resetForNextApproach() }
        ]))
    }

    /// Fades the plane out where it stands and back in at the start
    /// position while the runway scrolls back out, then begins a fresh
    /// approach. One action sequence — no teleporting in view.
    private func resetForNextApproach() {
        guard phase == .landed else { return }
        phase = .resetting

        feedbackLayer.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.run { [weak self] in
                self?.feedbackLayer.removeAllChildren()
                self?.feedbackLayer.alpha = 1
            }
        ]))

        // Scroll the tarmac fully off the right edge, then rebuild the
        // strip for the next pass. The fresh approach starts from the
        // runway's own chain so the cruise scroll can never overlap a
        // roll-out still in flight.
        let clearDistance = size.width - runway.leadingEdgeX(in: self) + 40
        let rollOut = SKAction.moveBy(x: clearDistance, y: 0, duration: 0.7)
        rollOut.timingMode = .easeIn
        runway.run(SKAction.sequence([
            rollOut,
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.runway.prepareForApproach()
                self.runway.position.x = self.offscreenRunwayX
                self.beginApproach()
            }
        ]))

        plane.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.plane.position = CGPoint(x: self.laneX, y: self.planeStartY)
                self.plane.setLandingGear(deployed: false)
                self.plane.levelOut(duration: 0)
                self.plane.physicsBody?.velocity = .zero
            },
            SKAction.fadeIn(withDuration: 0.25)
        ]))
    }

    // MARK: - Touch

    /// Routes touches: HUD buttons first, then phase-specific input — hold to
    /// climb in free approach, tap-to-correct / hold-to-go-around once committed.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
        }
        switch phase {
        case .freeApproach:
            isTouching = true
        case .finalApproach, .halted:
            // Phase 2: a brief tap trims the descent rate ("keep the nose
            // up"); a hold past `goAroundHoldDuration` triggers a go-around
            // (detected in update). Apply the correction immediately so a tap
            // stays responsive even when it turns out to be the start of a hold.
            isTouching = true
            committedTouchStartTime = CACurrentMediaTime()
            plane.applyCorrectionTap(impulse: Self.finalApproachTapImpulse)
        case .landed, .resetting:
            break
        }
    }
    /// Clears the touch/hold state when the finger lifts.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        committedTouchStartTime = nil
    }
    /// Clears the touch/hold state if the touch is cancelled.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        committedTouchStartTime = nil
    }
}
