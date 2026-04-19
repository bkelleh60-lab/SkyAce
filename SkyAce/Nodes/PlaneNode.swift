import SpriteKit

/// SpriteKit physics category bitmask for all game nodes.
/// contactTestBitMask is used for detection; collisionBitMask is always 0
/// so SpriteKit never resolves physics contacts itself.
struct PhysicsCategory {
    static let plane:    UInt32 = 0b00001   // 1
    static let obstacle: UInt32 = 0b00010   // 2
    static let coin:     UInt32 = 0b00100   // 4
    static let ring:     UInt32 = 0b01000   // 8
    static let boundary: UInt32 = 0b10000   // 16
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

    // MARK: - Init

    init(planeID: String) {
        let plane = PlaneCatalog.plane(forID: planeID)
        self.plane = plane

        let engine = ProgressManager.shared.upgradeLevel(for: UpgradeKind.engine.rawValue)
        let wings  = ProgressManager.shared.upgradeLevel(for: UpgradeKind.wings.rawValue)
        self.horizontalSpeed = UpgradeFormulas.horizontalSpeed(engineLevel: engine)
        self.climbVelocity   = UpgradeFormulas.climbVelocity(wingLevel: wings)

        self.body = PlaneNode.makeBody(for: plane)
        super.init()

        addChild(body)
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private static func makeBody(for plane: Plane) -> SKNode {
        // Prefer the bundled plane sprite; fall back to programmatic art while
        // final PNGs are still in production.
        if let sprite = SkySprites.sprite(named: plane.spriteName, size: CGSize(width: 90, height: 45)) {
            sprite.zPosition = 10
            return sprite
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
        // Hitbox is intentionally smaller than the 90x45 visual sprite — gives
        // an arcade-style grace zone so a wingtip brushing a cloud pillar
        // doesn't crash. Collect radius for coins stays generous because
        // coin physics bodies are unchanged.
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 44, height: 18))
        pb.mass = 0.1
        pb.affectedByGravity = true
        pb.allowsRotation = false
        pb.linearDamping = 0.0
        pb.categoryBitMask = PhysicsCategory.plane
        pb.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.coin | PhysicsCategory.ring | PhysicsCategory.boundary
        pb.collisionBitMask = 0   // detection only — scene resolves effects
        self.physicsBody = pb
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
        // Sprite path: colorize the body sprite directly. (No-op on SKShapeNode.)
        body.run(flash)

        // Programmatic-fallback path: swap fill on each child SKShapeNode so the
        // colorize behaviour is visible even when the body is a shape container.
        body.enumerateChildNodes(withName: "*") { node, _ in
            if let shape = node as? SKShapeNode {
                let original = shape.fillColor
                shape.run(SKAction.sequence([
                    SKAction.run { shape.fillColor = UIColor.systemRed },
                    SKAction.wait(forDuration: 0.08),
                    SKAction.run { shape.fillColor = original }
                ]))
            }
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
