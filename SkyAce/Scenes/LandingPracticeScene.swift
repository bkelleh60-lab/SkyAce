import SpriteKit

/// Free Flight — Landing Practice (SKY-83).
///
/// A pure-sandbox third Free Flight mode: the plane holds its fixed X lane
/// while a finite runway strip scrolls in from the right, decelerates, and
/// halts with the touchdown zone under the plane. The player manages descent
/// rate (hold to climb, release to land) and contacts the zone at one of
/// three quality tiers read from vertical velocity. No fail state — every
/// outcome auto-resets into a fresh approach.
///
/// Architecture is Option A from docs/landing-practice-movement-investigation.md:
/// modeled on FreeFlightCityScene (fixed-X plane, world moves, no camera),
/// with the FinishLineNode contact pattern repurposed as LandingZoneNode.
final class LandingPracticeScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Tunable landing constants (Connor's playtest dials)
    //
    // Velocity tiers are calibrated against logged touchdown velocities
    // under the post-SKY-78 momentum physics (gravity -5 ⇒ ~750 pt/s²
    // descent, tap onset floors dy at +320, maxDownVelocity -400, with
    // contact reads up to ~12 pt/s past the clamp). The ticket's
    // pre-SKY-78 values (-80 / -180) are unreachable under this model.
    // Three regimes actually occur at the sensor:
    //   ~ -285  gentle glide-in from the low-approach band → Smooth
    //   -320…-400  tap-flare near the deck (a tap always rebounds the
    //              plane ~68pt up, so it returns at ≥ ~320) → Rough
    //   ≤ -400  drop from altitude, no/late flare (terminal) → Crash

    /// Touchdown dy at or above this reads as a Smooth Landing.
    static let smoothLandingMaxDescent: CGFloat = -300
    /// Touchdown dy at or above this (and below smooth) is a Rough Landing;
    /// anything faster is a Crash Landing.
    static let roughLandingMaxDescent: CGFloat = -395

    /// Constant runway scroll-in speed during the cruise phase (pt/s).
    static let approachScrollSpeed: CGFloat = 200
    /// Distance over which the runway decelerates to its halt point. The
    /// ease-out curve's initial slope matches `approachScrollSpeed` when
    /// decelDistance / decelDuration == approachScrollSpeed / 2.
    static let decelDistance: CGFloat = 200
    static let decelDuration: TimeInterval = 2.0

    static let smoothResetDelay: TimeInterval = 2.5
    static let roughResetDelay: TimeInterval = 2.5
    static let crashResetDelay: TimeInterval = 1.5

    // MARK: - Layout constants

    /// Screen Y of the runway surface (tarmac top edge).
    private var groundY: CGFloat { 150 }
    /// Plane lane — same fraction as the Free Flight scenes.
    private var laneX: CGFloat { size.width * 0.28 }
    private var planeStartY: CGFloat { size.height * 0.55 }
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Floor while the runway is still moving: the low-approach band. It
    /// keeps the plane's hitbox clear of the touchdown sensor so contact
    /// can only begin after the runway halts, and it defines the smooth
    /// landing: a plane riding this band glides ~53pt onto the zone when
    /// the floor drops at halt (≈ -285 pt/s — the gentlest touchdown the
    /// physics can produce). Descending to and holding this band is the
    /// controlled approach the smooth tier rewards.
    private var approachFloorY: CGFloat { groundY + 80 }
    /// Floor once the runway has halted — deep enough to enter the sensor.
    private var landingFloorY: CGFloat { groundY + 16 }
    /// Where the plane settles so its wheels sit on the tarmac: gear-down
    /// wheel bottoms sit 22–30pt below the node center at the 2x visual
    /// scale, so center at +26 grazes the surface for all four planes.
    private var landedPlaneY: CGFloat { groundY + 26 }

    // MARK: - State

    private enum Phase { case approach, halted, landed, resetting }

    private var phase: Phase = .approach
    private let worldNode = SKNode()
    private let feedbackLayer = SKNode()
    private var plane: PlaneNode!
    private var runway: LandingZoneNode!
    private var isTouching = false

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
        phase = .approach
        isTouching = false
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

    /// Origin X that puts the entire strip past the right screen edge. The
    /// node origin sits 30% in from the strip's left end.
    private var offscreenRunwayX: CGFloat {
        size.width + runway.stripWidth * 0.3 + 20
    }

    /// Scrolls the runway in: cruise at constant speed, hand off to an
    /// ease-out deceleration (gear deploys at the handoff — the ticket's
    /// "deceleration trigger point"), halt with the touchdown zone on the
    /// plane's lane.
    private func beginApproach() {
        phase = .approach

        let decelStartX = laneX + Self.decelDistance
        let cruiseDistance = runway.position.x - decelStartX
        let cruise = SKAction.moveTo(
            x: decelStartX,
            duration: TimeInterval(max(0, cruiseDistance) / Self.approachScrollSpeed)
        )
        let deployGear = SKAction.run { [weak self] in
            // Red Baron MK-1 has fixed gear baked into its base art — the
            // deploy trigger must not fire anything for it: no sprite swap
            // and no gear SFX, ever (SKY-83 playtest bug 1).
            guard ProgressManager.shared.selectedPlaneID != "red_baron" else { return }
            self?.plane.setLandingGear(deployed: true)
        }
        let decel = SKAction.moveTo(x: laneX, duration: Self.decelDuration)
        decel.timingMode = .easeOut
        let halt = SKAction.run { [weak self] in
            self?.phase = .halted
        }
        runway.run(SKAction.sequence([cruise, deployGear, decel, halt]))
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

        let prompt = SKLabelNode(text: "Hold to climb. Release to land.")
        prompt.fontName = SkyFonts.headlineName
        prompt.fontSize = 20
        prompt.fontColor = SkyColors.skOnPrimary
        prompt.verticalAlignmentMode = .center
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        prompt.zPosition = 150
        prompt.alpha = 0
        addChild(prompt)
        prompt.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        guard let plane = plane else { return }

        let controlsLive = phase == .approach || phase == .halted
        if isTouching && controlsLive { plane.climb() }
        plane.update()

        guard controlsLive else { return }

        let floor = phase == .approach ? approachFloorY : landingFloorY
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
        // The approach floor keeps the plane clear of the sensor until the
        // runway halts, so a contact can only begin once a landing is
        // actually in progress — but guard anyway against double-fires.
        guard phase == .halted else { return }
        let descentRate = plane.physicsBody?.velocity.dy ?? 0
        phase = .landed
        isTouching = false

        // Freeze the plane and settle it onto the tarmac.
        plane.physicsBody?.velocity = .zero
        plane.physicsBody?.affectedByGravity = false
        plane.levelOut()
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
        SkyHaptics.win()
        showCelebrationBadge()
        scheduleReset(after: Self.smoothResetDelay)
    }

    private func handleRoughLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingRough, fileExtension: "caf"))
        SkyHaptics.hit()

        // Visual bounce off the tarmac, then a brief shake. No fanfare —
        // the missing celebration is the feedback.
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
        burstDustCloud(at: CGPoint(x: laneX, y: groundY + 12))
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

        // The fresh approach starts from the runway's own chain so its
        // moveTo can never overlap a roll-out still in flight.
        let rollOut = SKAction.moveTo(x: offscreenRunwayX, duration: 0.7)
        rollOut.timingMode = .easeIn
        runway.run(SKAction.sequence([
            rollOut,
            SKAction.run { [weak self] in self?.beginApproach() }
        ]))

        plane.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.plane.position = CGPoint(x: self.laneX, y: self.planeStartY)
                self.plane.setLandingGear(deployed: false)
                self.plane.levelOut(duration: 0)
                self.plane.physicsBody?.velocity = .zero
                self.plane.physicsBody?.affectedByGravity = true
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
        isTouching = true
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
}
