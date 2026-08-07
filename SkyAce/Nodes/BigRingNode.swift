import SpriteKit

/// Oversized gold "big ring" collectible (SKY-63). Flying through one awards a
/// streak-scaling coin bonus; the scene owns the streak counter, scoring, and
/// spawn cadence, while this node owns its visuals, pass-through physics, and
/// the fly-through burst.
///
/// Reuses the bundled gold, glowing `ring` sprite — the ticket's requested
/// visual treatment — scaled up well past a coin so it reads as a distinct,
/// high-value target rather than "another coin". Per SKY-63's Out of Scope,
/// the ring does not move or rotate; the only animation is a subtle attract
/// pulse for visibility.
final class BigRingNode: SKNode {

    /// Ring radius in points. The 130pt diameter dwarfs a coin (26pt) so the
    /// ring is an easy, deliberate target. Tunable.
    static let radius: CGFloat = 65

    /// Set once the plane flies through. Guards the collect animation against a
    /// double contact and lets the scene tell a collected ring from one that
    /// scrolled off uncollected (a streak-breaking miss).
    private(set) var wasCollected = false

    /// The gold ring art — faded/scaled on collect while the burst sparkles
    /// (siblings under this node) keep their own opacity.
    private let ringVisual: SKNode

    override init() {
        let diameter = BigRingNode.radius * 2
        if let sprite = SkySprites.sprite(
            named: SkySprites.ring,
            size: CGSize(width: diameter, height: diameter)
        ) {
            ringVisual = sprite
        } else {
            ringVisual = BigRingNode.makeProgrammaticRing()
        }
        super.init()
        ringVisual.zPosition = 1
        addChild(ringVisual)
        configurePhysics()
        animate()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Fallback gold ring for when the bundled `ring` sprite is unavailable.
    /// The shipping visual is the designed `ring.png` asset (see `init`); this
    /// stroked-circle stand-in — mirroring `RingNode`'s fallback — only renders
    /// if that asset fails to load. No ring design exists in the "Sky Ace Plane
    /// Assets" Stitch project (checked SKY-63), so it is marked as a placeholder.
    private static func makeProgrammaticRing() -> SKNode {
        let container = SKNode()

        // PLACEHOLDER: Stitch design required before App Store submission
        let outer = SKShapeNode(circleOfRadius: BigRingNode.radius)
        outer.strokeColor = SkyColors.tertiaryContainer
        outer.lineWidth = 14
        outer.fillColor = .clear
        outer.glowWidth = 6
        container.addChild(outer)

        let inner = SKShapeNode(circleOfRadius: BigRingNode.radius - 14)
        inner.strokeColor = SkyColors.tertiaryContainer.withAlphaComponent(0.5)
        inner.lineWidth = 3
        inner.fillColor = .clear
        container.addChild(inner)

        return container
    }

    private func configurePhysics() {
        // Reuses the `ring` category: mission runs spawn no other ring node, so
        // a `.ring` contact in GameScene is always a big ring, and the plane
        // already contact-tests `.ring` (see PlaneNode). Collision mask 0 keeps
        // it pass-through. The body is a touch smaller than the art so a fly-
        // through has to actually enter the hole rather than clip the rim.
        let pb = SKPhysicsBody(circleOfRadius: BigRingNode.radius * 0.72)
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.ring
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        physicsBody = pb
    }

    /// Gentle attract pulse (scale only — moving/rotating rings are out of
    /// scope for SKY-63).
    private func animate() {
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.6),
            SKAction.scale(to: 1.0, duration: 0.6)
        ])
        ringVisual.run(SKAction.repeatForever(pulse))
    }

    /// Plays the fly-through burst and removes the node. Scoring, sound, and
    /// streak bookkeeping stay in the scene. Idempotent — a second contact is a
    /// no-op.
    func collect() {
        guard !wasCollected else { return }
        wasCollected = true
        physicsBody = nil
        ringVisual.removeAllActions()

        emitSparkleBurst()

        // Fade/scale the ring art only — the sparkle siblings keep their own
        // alpha so the burst stays visible while the ring dissolves.
        let pop = SKAction.group([
            SKAction.scale(to: 1.6, duration: 0.3),
            SKAction.fadeOut(withDuration: 0.3)
        ])
        pop.timingMode = .easeOut
        ringVisual.run(pop)

        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.45),
            SKAction.removeFromParent()
        ]))
    }

    /// A brief gold sparkle burst — small dots flung radially outward that fade
    /// as they travel. Built from SKActions to match the effect style already
    /// used for the win coin burst rather than bundling an emitter/particle
    /// asset.
    private func emitSparkleBurst() {
        let count = 10
        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * .pi * 2
            // PLACEHOLDER: Stitch design required before App Store submission
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...5))
            spark.fillColor = SkyColors.tertiaryContainer
            spark.strokeColor = .clear
            spark.zPosition = 2
            addChild(spark)

            let dist = CGFloat.random(in: 40...90)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4),
                    SKAction.scale(to: 0.2, duration: 0.4)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }
}
