import SpriteKit

/// SpriteKit physics category bitmask for all game nodes.
/// contactTestBitMask is used for detection; collisionBitMask is always 0
/// so SpriteKit never resolves physics contacts itself.
struct PhysicsCategory {
    static let plane:    UInt32 = 0b000001  // 1
    static let obstacle: UInt32 = 0b000010  // 2
    static let coin:     UInt32 = 0b000100  // 4
    static let ring:     UInt32 = 0b001000  // 8
    static let boundary: UInt32 = 0b010000  // 16
    static let finish:   UInt32 = 0b100000  // 32
}

/// Player-controlled plane.
///
/// Control model: touch-and-hold applies a burst of upward velocity each frame
/// via `climb()`. On release, world gravity (dy = -5.0) pulls it down.
/// Velocity is clamped so the plane never spirals out of control.
final class PlaneNode: SKNode {

    // Stats — set from ProgressManager upgrade levels on init.
    let horizontalSpeed: CGFloat
    let climbVelocity: CGFloat
    // SpriteKit uses positive-Y-up, so the "up" cap is positive and the
    // "down" cap is negative. Gravity.dy = -5 pulls velocity.dy toward -∞.
    let maxUpVelocity:   CGFloat =  500.0
    let maxDownVelocity: CGFloat = -400.0

    let plane: Plane

    private let body: SKNode

    /// Speed-trail emitter, lazily attached the first time
    /// `setBoostIntensity(_:)` is called with a non-zero value. Lives as a
    /// child of `body` so it inherits the visual scale, and uses the scene
    /// as `targetNode` so particles stay in world space and read as motion
    /// past the plane rather than sticking to it.
    private var boostTrail: SKEmitterNode?
    private static let boostTrailFullBirthRate: CGFloat = 240

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
        self.climbVelocity   = UpgradeFormulas.climbVelocity(wingLevel: wings)

        self.body = PlaneNode.makeBody(for: plane)
        super.init()

        body.setScale(visualScale)
        addChild(body)
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private static func makeBody(for plane: Plane) -> SKNode {
        // Prefer the bundled plane sprite; fall back to programmatic art while
        // final PNGs are still in production.
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
    func climb() {
        physicsBody?.velocity.dy = min(climbVelocity, maxUpVelocity)
        // Tilt nose up.
        let targetRotation: CGFloat = 0.25
        body.zRotation += (targetRotation - body.zRotation) * 0.25
    }

    /// Called every frame (by the scene) to clamp velocity and settle rotation.
    func update() {
        guard let pb = physicsBody else { return }
        var v = pb.velocity
        if v.dy > maxUpVelocity   { v.dy = maxUpVelocity }
        if v.dy < maxDownVelocity { v.dy = maxDownVelocity }
        pb.velocity = v

        // Tilt nose down while falling.
        if v.dy < 0 {
            let targetRotation: CGFloat = -0.3
            body.zRotation += (targetRotation - body.zRotation) * 0.08
        }
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
