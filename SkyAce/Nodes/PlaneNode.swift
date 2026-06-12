import SpriteKit

/// SpriteKit physics category bitmask for all game nodes.
/// contactTestBitMask is used for detection; collisionBitMask is always 0
/// so SpriteKit never resolves physics contacts itself.
struct PhysicsCategory {
    static let plane:       UInt32 = 0b0000001  // 1
    static let obstacle:    UInt32 = 0b0000010  // 2
    static let coin:        UInt32 = 0b0000100  // 4
    static let ring:        UInt32 = 0b0001000  // 8
    static let boundary:    UInt32 = 0b0010000  // 16
    static let finish:      UInt32 = 0b0100000  // 32
    static let landingZone: UInt32 = 0b1000000  // 64 — SKY-83 touchdown sensor
}

/// Player-controlled plane.
///
/// Control model — momentum-based (SKY-78):
///  * Tap onset: `climbImpulse` is added to the current vertical velocity,
///    capped at `maxClimbVelocity`. Rapid tapping therefore stacks toward
///    the cap (momentum), whereas the legacy hard-reset feel is preserved
///    for single taps from rest because 0 + climbImpulse ≈ legacy peak.
///  * Sustained hold: an additional per-frame upward acceleration is applied
///    that ramps from 0 to `holdImpulseScale * climbImpulse` over
///    `holdImpulseDuration` seconds. Holding therefore gives a stronger,
///    committed climb than a tap.
///  * Descent: gravity (`PlaneNode.gravity`, wired into each scene's
///    `physicsWorld.gravity`) pulls the plane down. Vertical velocity is
///    clamped to `[maxDownVelocity, maxClimbVelocity]` so it never runs away.
final class PlaneNode: SKNode {

    // MARK: - Tunable physics constants
    //
    // The five tunables called out in SKY-78. Treat as playtest dials —
    // `climbImpulse` here is the *base* value before per-plane upgrade
    // scaling; the upgrade-scaled instance value lives on `self.climbImpulse`
    // and is derived in `init` via `UpgradeFormulas.climbVelocity(wingLevel:)`.

    /// Hard ceiling on upward velocity (pt/s). Additive tap impulses and the
    /// hold-impulse contribution both clamp against this.
    static let maxClimbVelocity: CGFloat = 500.0

    /// Multiplier applied to `climbImpulse` to produce the per-second hold
    /// acceleration at full ramp. Final per-second contribution while held
    /// at full ramp = `climbImpulse * holdImpulseScale` pt/s.
    static let holdImpulseScale: CGFloat = 1.5

    /// Seconds of continuous hold required for the hold-impulse to reach
    /// `holdImpulseScale`. Linear ramp from 0 to 1 over this window.
    static let holdImpulseDuration: TimeInterval = 0.2

    /// Downward acceleration applied via the scene's physics world gravity.
    /// Each scene sets `physicsWorld.gravity.dy = PlaneNode.gravity` so this
    /// is the single source of truth for descent feel.
    static let gravity: CGFloat = -5.0

    /// Floor on downward velocity (pt/s). Not part of the SKY-78 five but
    /// kept so a long fall doesn't blow past collision sweeps.
    static let maxDownVelocity: CGFloat = -400.0

    // MARK: - Per-plane stats (set from ProgressManager upgrades on init)

    let horizontalSpeed: CGFloat
    /// Upgrade-scaled additive impulse applied to vertical velocity on each
    /// tap onset. Base value comes from `UpgradeFormulas.baseClimbVelocity`.
    let climbImpulse: CGFloat

    let plane: Plane

    private let body: SKNode

    /// The textured sprite inside `body`, when the bundled plane art is in
    /// use (nil for the programmatic fallback body). Held so the landing
    /// gear swap (SKY-83) can change its texture in place.
    private weak var bodySprite: SKSpriteNode?

    /// Speed-trail emitter, lazily attached the first time
    /// `setBoostIntensity(_:)` is called with a non-zero value. Lives as a
    /// child of `body` so it inherits the visual scale, and uses the scene
    /// as `targetNode` so particles stay in world space and read as motion
    /// past the plane rather than sticking to it.
    private var boostTrail: SKEmitterNode?
    private static let boostTrailFullBirthRate: CGFloat = 240

    /// Wall-clock time the current hold began (set on tap onset, nilled when
    /// the touch is released). Nil ⇒ not currently holding.
    private var holdStartTime: TimeInterval?

    /// Set to true inside `climb()`, read+cleared by `update()`. Lets
    /// `update()` detect a touch release (no climb this frame) and reset
    /// the hold state.
    private var climbActiveThisFrame = false

    // MARK: - Init

    /// - Parameter visualScale: multiplies the rendered sprite size only.
    ///   Applied to the internal `body` child so the physics body on `self`
    ///   keeps its original local-space dimensions — collisions do not scale.
    init(planeID: String, visualScale: CGFloat = 1.0) {
        let plane = PlaneCatalog.plane(forID: planeID)
        self.plane = plane

        let engine = ProgressManager.shared.upgradeLevel(for: UpgradeKind.engine.rawValue)
        let wings  = ProgressManager.shared.upgradeLevel(for: UpgradeKind.wings.rawValue)
        self.horizontalSpeed = UpgradeFormulas.horizontalSpeed(engineLevel: engine)
        self.climbImpulse    = UpgradeFormulas.climbVelocity(wingLevel: wings)

        self.body = PlaneNode.makeBody(for: plane)
        super.init()

        body.setScale(visualScale)
        addChild(body)
        bodySprite = body.children.compactMap { $0 as? SKSpriteNode }.first
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private static func makeBody(for plane: Plane) -> SKNode {
        // Prefer the bundled plane sprite; fall back to a generic propeller
        // body if the named asset isn't present. Shadow Dart and Night Hawk
        // are Stitch-designed PNGs in the asset catalog; the others live
        // under Resources/Sprites/.
        if let sprite = SkySprites.sprite(named: plane.spriteName, size: CGSize(width: 90, height: 45)) {
            // Wrap so the boost-trail emitter (added later as a child of `body`
            // at x=-48) stays behind the plane even when the inner sprite is
            // mirrored for an asset that's authored nose-left.
            let container = SKNode()
            container.zPosition = 10
            if plane.assetFacesLeft {
                sprite.xScale = -1
            }
            container.addChild(sprite)
            return container
        }
        return makeProgrammaticBody(for: plane)
    }

    private static func makeProgrammaticBody(for plane: Plane) -> SKNode {
        let container = SKNode()
        container.zPosition = 10

        let hull = SKShapeNode(ellipseOf: CGSize(width: 64, height: 22))
        hull.fillColor = plane.bodyColor
        hull.strokeColor = .clear
        hull.zPosition = 0
        container.addChild(hull)

        let wing = SKShapeNode(rectOf: CGSize(width: 40, height: 10), cornerRadius: 4)
        wing.fillColor = plane.accentColor
        wing.strokeColor = .clear
        wing.position = CGPoint(x: -4, y: -4)
        wing.zPosition = 1
        container.addChild(wing)

        let tail = SKShapeNode(rectOf: CGSize(width: 10, height: 18), cornerRadius: 2)
        tail.fillColor = plane.accentColor
        tail.strokeColor = .clear
        tail.position = CGPoint(x: -26, y: 8)
        tail.zPosition = 1
        container.addChild(tail)

        let canopy = SKShapeNode(ellipseOf: CGSize(width: 22, height: 10))
        canopy.fillColor = SkyColors.surfaceContainerHighest
        canopy.strokeColor = .clear
        canopy.position = CGPoint(x: 4, y: 6)
        canopy.zPosition = 2
        container.addChild(canopy)

        let prop = SKShapeNode(rectOf: CGSize(width: 4, height: 28), cornerRadius: 2)
        prop.fillColor = SkyColors.onSurface.withAlphaComponent(0.7)
        prop.strokeColor = .clear
        prop.position = CGPoint(x: 30, y: 0)
        prop.zPosition = 3
        prop.name = "propeller"
        prop.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 0.08)))
        container.addChild(prop)

        return container
    }

    private func configurePhysics() {
        // Fuselage-only hitbox, ~60% of the 90x45 visual sprite. Excludes
        // wingtips and the nose so near-misses read as near-misses and only
        // clear body-on-obstacle contact registers as a crash.
        let hitboxSize = CGSize(width: 54, height: 27)
        let pb = SKPhysicsBody(rectangleOf: hitboxSize)
        pb.mass = 0.1
        pb.affectedByGravity = true
        pb.allowsRotation = false
        pb.linearDamping = 0.0
        pb.categoryBitMask = PhysicsCategory.plane
        pb.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.coin | PhysicsCategory.ring | PhysicsCategory.boundary | PhysicsCategory.finish
        pb.collisionBitMask = 0   // detection only — scene resolves effects
        self.physicsBody = pb

        #if DEBUG
        print("[PlaneNode] physics body size: \(hitboxSize.width) x \(hitboxSize.height) (60% of 90x45 sprite)")
        #endif
    }

    // MARK: - Control

    /// Apply a climb impulse. Called every frame while touch is held.
    ///
    /// First call of a hold = "tap onset": adds `climbImpulse` to dy,
    /// but never lets the post-tap velocity drop below `climbImpulse`. So a
    /// tap from rest matches the legacy hard-reset feel (dy → climbImpulse),
    /// a tap mid-descent reverses direction (dy → climbImpulse), and a tap
    /// while already ascending stacks momentum toward `maxClimbVelocity`.
    ///
    /// Subsequent calls = "sustained hold": drive dy up to a ramping target
    /// that goes from `climbImpulse` at hold-start to
    /// `climbImpulse * holdImpulseScale` after `holdImpulseDuration`. The
    /// hold keeps the plane climbing even against gravity — same dominance
    /// as the legacy per-frame velocity reset, but stronger than a tap.
    func climb() {
        guard let pb = physicsBody else { return }
        let now = CACurrentMediaTime()

        if holdStartTime == nil {
            // Tap onset — additive impulse with a floor of `climbImpulse` so
            // a tap always lifts the plane, and a ceiling of `maxClimbVelocity`.
            holdStartTime = now
            let boosted = max(pb.velocity.dy + climbImpulse, climbImpulse)
            pb.velocity.dy = min(boosted, PlaneNode.maxClimbVelocity)
        } else if let start = holdStartTime {
            // Sustained hold — drive dy toward a ramping hold target.
            let heldFor = now - start
            let ramp = CGFloat(min(heldFor / PlaneNode.holdImpulseDuration, 1.0))
            let holdTarget = climbImpulse * (1 + (PlaneNode.holdImpulseScale - 1) * ramp)
            let clamped = min(holdTarget, PlaneNode.maxClimbVelocity)
            if pb.velocity.dy < clamped {
                pb.velocity.dy = clamped
            }
        }

        climbActiveThisFrame = true

        // Tilt nose up.
        let targetRotation: CGFloat = 0.25
        body.zRotation += (targetRotation - body.zRotation) * 0.25
    }

    /// Called every frame (by the scene) to clamp velocity and settle rotation.
    func update() {
        guard let pb = physicsBody else { return }

        // Detect touch release: climb() wasn't called this frame, so reset
        // the hold state so the next tap fires a fresh onset impulse.
        if !climbActiveThisFrame {
            holdStartTime = nil
        }
        climbActiveThisFrame = false

        var v = pb.velocity
        if v.dy > PlaneNode.maxClimbVelocity { v.dy = PlaneNode.maxClimbVelocity }
        if v.dy < PlaneNode.maxDownVelocity  { v.dy = PlaneNode.maxDownVelocity }
        pb.velocity = v

        // Tilt nose down while falling.
        if v.dy < 0 {
            let targetRotation: CGFloat = -0.3
            body.zRotation += (targetRotation - body.zRotation) * 0.08
        }
    }

    // MARK: - Landing gear (SKY-83)

    /// True while the gear-down sprite variant is showing.
    private(set) var isGearDeployed = false

    /// Gear-up texture and display size, captured on deploy so retract can
    /// restore them exactly.
    private var gearUpTexture: SKTexture?
    private var gearUpSize: CGSize = .zero

    /// Swaps the body sprite between the gear-up art and the bundled
    /// "<planeID>_gear_down" variant. Used by Landing Practice: deploy at
    /// the runway deceleration trigger, retract on approach reset.
    ///
    /// The gear-down exports are registered against the gear-up art by
    /// scripts/process_sky83_assets.py: equal canvas width, fuselage
    /// top-aligned, any extra canvas height is gear hanging below. Display
    /// therefore keeps the gear-up width, scales height by the relative
    /// texture aspect, and shifts the sprite down by half the extra height
    /// so the fuselage doesn't move or resize on swap.
    ///
    /// Planes without a gear-down asset no-op and keep their existing
    /// sprite throughout (Red Baron's gear is fixed in its base art).
    func setLandingGear(deployed: Bool) {
        guard deployed != isGearDeployed, let sprite = bodySprite else { return }

        if deployed {
            guard let gearTexture = SkySprites.texture(named: plane.id + "_gear_down"),
                  let upTexture = sprite.texture else { return }
            let up = upTexture.size()
            let down = gearTexture.size()
            guard up.width > 0, up.height > 0, down.width > 0 else { return }

            gearUpTexture = upTexture
            gearUpSize = sprite.size

            let heightFactor = (down.height / down.width) / (up.height / up.width)
            let newHeight = gearUpSize.height * heightFactor
            sprite.texture = gearTexture
            sprite.size = CGSize(width: gearUpSize.width, height: newHeight)
            sprite.position.y = -(newHeight - gearUpSize.height) / 2
            isGearDeployed = true
        } else {
            if let upTexture = gearUpTexture {
                sprite.texture = upTexture
                sprite.size = gearUpSize
                sprite.position.y = 0
            }
            isGearDeployed = false
        }
    }

    /// Smoothly levels the body's nose tilt — used when the plane settles
    /// onto the runway after a Landing Practice touchdown.
    func levelOut(duration: TimeInterval = 0.2) {
        body.run(SKAction.rotate(toAngle: 0, duration: duration, shortestUnitArc: true))
    }

    // MARK: - Effects

    /// Plays hit feedback but does not change physics — scene owns run state.
    func playHitFlash() {
        let flash = SKAction.sequence([
            SKAction.colorize(with: UIColor.systemRed, colorBlendFactor: 0.6, duration: 0.06),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.2)
        ])

        // Body is always a container now: sprite path wraps an SKSpriteNode,
        // programmatic path holds SKShapeNodes. Colorize the sprite child(ren)
        // directly, and swap fillColor on shape children since SKAction.colorize
        // is a no-op on SKShapeNode.
        body.enumerateChildNodes(withName: "*") { node, _ in
            if let sprite = node as? SKSpriteNode {
                sprite.run(flash)
            } else if let shape = node as? SKShapeNode {
                let original = shape.fillColor
                shape.run(SKAction.sequence([
                    SKAction.run { shape.fillColor = UIColor.systemRed },
                    SKAction.wait(forDuration: 0.08),
                    SKAction.run { shape.fillColor = original }
                ]))
            }
        }
    }

    /// Drives the speed-trail emitter behind the plane. `intensity` is a
    /// 0...1 scalar — 0 hides the trail, 1 emits at full rate. Smooth
    /// taper is the caller's responsibility (pass 0.6, 0.3, 0.0... over
    /// time to fade out). The emitter is created lazily on first non-zero
    /// call so non-Free-Flight scenes never pay for it.
    func setBoostIntensity(_ intensity: CGFloat) {
        let clamped = max(0, min(1, intensity))
        if boostTrail == nil {
            guard clamped > 0 else { return }
            boostTrail = makeBoostTrail()
            body.addChild(boostTrail!)
        }
        guard let trail = boostTrail else { return }
        if trail.targetNode == nil { trail.targetNode = scene }
        trail.particleBirthRate = PlaneNode.boostTrailFullBirthRate * clamped
    }

    private func makeBoostTrail() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: PlaneNode.boostTrailParticleImage())
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 0.45
        emitter.particleLifetimeRange = 0.15
        // Body-local: fire from just behind the tail (body sprite is 90 wide,
        // centred, so the tail sits at x = -45).
        emitter.position = CGPoint(x: -48, y: 0)
        emitter.particlePositionRange = CGVector(dx: 4, dy: 14)
        emitter.emissionAngle = .pi
        emitter.emissionAngleRange = 0.25
        emitter.particleSpeed = 220
        emitter.particleSpeedRange = 60
        emitter.particleAlpha = 0.85
        emitter.particleAlphaRange = 0.15
        emitter.particleAlphaSpeed = -1.6
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.4
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = nil
        emitter.particleColor = UIColor(hex: 0x9FE4FF)
        emitter.zPosition = -1
        return emitter
    }

    private static func boostTrailParticleImage() -> UIImage {
        let size = CGSize(width: 12, height: 6)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Crash spin + fade for fail state.
    func playCrash(completion: @escaping () -> Void) {
        physicsBody = nil
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.6)
        let fall = SKAction.moveBy(x: 0, y: -320, duration: 0.6)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        run(SKAction.group([spin, fall, fade])) {
            completion()
        }
    }
}
