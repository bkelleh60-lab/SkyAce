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
    /// 320): against gravity (~750 pt/s²) a steady ~5 taps/s roughly cancels
    /// gravity for a slow, gentle descent (Smooth), while sparse taps let the
    /// plane build speed toward Rough/Crash. One tap ≈ a 140 pt/s save.
    static let finalApproachTapImpulse: CGFloat = 140

    /// How quickly the runway sheds speed once the approach window opens
    /// (pt/s²). Stopping distance (v²/2a) and duration (v/a) both derive
    /// from this and `approachScrollSpeed`.
    static let runwayDecelerationRate: CGFloat = 100

    /// Pause between the threshold crossing and the landing zone fade-in
    /// (0.0–0.5s) — a beat of "the runway is slowing… there's the zone".
    static let landingZoneRevealDelay: TimeInterval = 0.15

    /// Height above the touchdown surface at which the plane lines up while
    /// the runway decelerates, and from which it is released into the
    /// committed final descent the instant the runway halts. This drop
    /// distance (≈ height − 26.5pt sensor) is what the player taps to manage,
    /// so it must be tall enough that no taps reaches terminal (Crash) while
    /// steady taps stay gentle (Smooth) — that spread is the whole skill.
    /// Kept just under the smallest phone's 0.35-height window (~233pt) so
    /// crossing the threshold doesn't pop the plane upward onto the band.
    static let finalApproachHoverHeight: CGFloat = 130

    // MARK: - Tunable landing constants (Connor's playtest dials)
    //
    // Velocity tiers are calibrated against the SKY-94 committed final
    // descent. At the runway's halt the plane is released from the line-up
    // band (`finalApproachHoverHeight`, ~130pt up) and falls to the sensor
    // (contact at center ≈ surface + 26.5), a ~103pt drop under tap control.
    // Under gravity (~750 pt/s²), with each tap adding `finalApproachTapImpulse`:
    //   no taps → terminal (≈ -394, clamped toward -400) → Crash
    //   a tap or two during the drop → ~ -160…-330 → Rough
    //   a steady ~5 tap/s feather holds dy shallow all the way down → Smooth
    // The earlier build held the plane at surface+48 and dropped it only
    // ~21.5pt, so every touchdown read ≈ -180 (Rough) and neither Crash nor
    // Smooth was reachable — raising the band and lengthening the drop is
    // what restores the three-tier skill spread.

    /// Touchdown dy at or above this reads as a Smooth Landing.
    static let smoothLandingMaxDescent: CGFloat = -150
    /// Touchdown dy at or above this (and below smooth) is a Rough Landing;
    /// anything faster is a Crash Landing.
    static let roughLandingMaxDescent: CGFloat = -330

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
    private var planeStartY: CGFloat { size.height * 0.55 }
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Floor during the free approach phase — the low-approach band the
    /// plane rides if it descends before the runway is established and the
    /// approach window can open. Keeps the hitbox well clear of the
    /// touchdown sensor.
    private var approachFloorY: CGFloat { touchdownSurfaceY + 80 }
    /// Line-up band the plane holds while the runway decelerates: high
    /// enough above the sensor (center − 13.5 stays clear of the surface+13
    /// band) that contact can't fire until the runway halts, and tall enough
    /// that the post-halt release becomes a real, tappable final descent
    /// rather than a fixed ~20pt drop. Its height above the contact line is
    /// the committed drop the landing tiers are calibrated to.
    private var finalApproachFloorY: CGFloat {
        touchdownSurfaceY + Self.finalApproachHoverHeight
    }
    /// Floor once the runway has halted — deep enough to enter the sensor.
    private var landingFloorY: CGFloat { touchdownSurfaceY + 16 }
    /// Where the plane settles so its wheels sit on the touchdown line:
    /// gear-down wheel bottoms sit 22–30pt below the node center at the
    /// 2x visual scale, so center at +26 grazes the line for all four
    /// planes.
    private var landedPlaneY: CGFloat { touchdownSurfaceY + 26 }

    // MARK: - State

    private enum Phase { case freeApproach, finalApproach, halted, landed, resetting }

    private var phase: Phase = .freeApproach
    private let worldNode = SKNode()
    private let feedbackLayer = SKNode()
    // Implicitly unwrapped: both are built in layoutScene() (didMove /
    // didChangeSize rebuild) before any touch or update path can run, and
    // update() additionally guards plane against the teardown window.
    private var plane: PlaneNode!
    private var runway: LandingZoneNode!
    private var isTouching = false
    private var lastUpdateTime: TimeInterval = 0
    private weak var instructionPrompt: SKLabelNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        physicsWorld.contactDelegate = self
        SkyHaptics.prepare()
        layoutScene()

        AudioManager.shared.playEngineLoop(
            SkyEngineLoop.filename(forPlaneID: ProgressManager.shared.selectedPlaneID)
        )
    }

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
        lastUpdateTime = 0
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

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
        // approach input is discrete taps only.
        isTouching = false

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
            SKAction.run { [weak self] in self?.phase = .halted }
        ]))

        run(SKAction.sequence([
            SKAction.wait(forDuration: Self.landingZoneRevealDelay),
            SKAction.run { [weak self] in self?.runway.setZoneRevealed(true, fade: 0.3) }
        ]))

        showTapToCorrectCue()
    }

    // MARK: - Plane

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

    private func showInstructionPromptIfFirstLaunch() {
        guard !ProgressManager.shared.landingPracticeInstructionShown else { return }
        ProgressManager.shared.landingPracticeInstructionShown = true

        let prompt = SKLabelNode(text: "Hold to climb. Release to descend.")
        prompt.fontName = SkyFonts.headlineName
        prompt.fontSize = 20
        prompt.fontColor = SkyColors.skOnPrimary
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
    /// Same treatment as the first-launch instruction.
    private func showTapToCorrectCue() {
        // The cue shares the instruction's screen slot; clear the prompt if
        // the player committed inside its 3-second run.
        if let prompt = instructionPrompt {
            prompt.removeAllActions()
            prompt.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15),
                SKAction.removeFromParent()
            ]))
        }

        let cue = SKLabelNode(text: "Tap to correct!")
        cue.fontName = SkyFonts.headlineName
        cue.fontSize = 20
        cue.fontColor = SkyColors.skOnPrimary
        cue.verticalAlignmentMode = .center
        cue.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        cue.zPosition = 150
        cue.alpha = 0
        addChild(cue)
        cue.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Update

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

        // The commit moment: the plane sinks through the approach window
        // while the runway is established beneath it (leading edge past the
        // screen's left edge — descending any earlier just rides Phase 1's
        // floor until the tarmac arrives).
        if phase == .freeApproach,
           plane.position.y <= approachAltitudeThreshold,
           runway.leadingEdgeX(in: self) <= 0 {
            beginFinalApproach()
        }

        let floor: CGFloat
        switch phase {
        case .freeApproach:  floor = approachFloorY
        case .finalApproach: floor = finalApproachFloorY
        default:             floor = landingFloorY
        }
        if plane.position.y <= floor {
            plane.position.y = floor
            // Resting on the floor must also rest the body: without this,
            // gravity keeps integrating dy toward terminal while the clamp
            // holds the position, and the post-halt glide then starts at
            // full terminal speed — every landing read as a crash.
            if let pb = plane.physicsBody, pb.velocity.dy < 0 {
                pb.velocity.dy = 0
            }
        }
        plane.position.y = min(planeMaxY, plane.position.y)
        plane.position.x += (laneX - plane.position.x) * 0.12
    }

    // MARK: - Touchdown

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard categories == PhysicsCategory.plane | PhysicsCategory.landingZone else { return }
        handleLandingZoneContact()
    }

    private func handleLandingZoneContact() {
        // The approach floors keep the plane's hitbox clear of the sensor
        // until the runway halts, so a contact can only begin once a landing
        // is actually in progress — but guard anyway against double-fires.
        guard phase == .halted else { return }
        let descentRate = plane.physicsBody?.velocity.dy ?? 0
        phase = .landed
        isTouching = false

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

    private func handleSmoothLanding() {
        run(SKAction.sequence([
            AudioManager.shared.sfxAction(SkySFX.landingTouchdown, fileExtension: "caf"),
            SKAction.wait(forDuration: 0.25),
            AudioManager.shared.sfxAction(SkySFX.landingSuccess, fileExtension: "caf")
        ]))
        plane.playTouchdownFlare()
        SkyHaptics.win()
        showCelebrationBadge()
        scheduleReset(after: Self.smoothResetDelay)
    }

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
        showFeedbackText("Bumpy but you made it!")
        scheduleReset(after: Self.roughResetDelay)
    }

    private func handleCrashLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingCrash, fileExtension: "caf"))
        SkyHaptics.fail()
        shakeWorld(amplitude: 12)
        burstDustCloud(at: CGPoint(x: laneX, y: touchdownSurfaceY + 12))
        showFeedbackText("Try again!")
        scheduleReset(after: Self.crashResetDelay)
    }

    // MARK: - Feedback visuals

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

    private func showFeedbackText(_ text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = SkyFonts.headlineName
        label.fontSize = 24
        label.fontColor = SkyColors.skOnPrimary
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
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
            // Phase 2: discrete "keep the nose up" corrections — gravity
            // keeps pulling, each tap trims the descent rate.
            plane.applyCorrectionTap(impulse: Self.finalApproachTapImpulse)
        case .landed, .resetting:
            break
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
}
