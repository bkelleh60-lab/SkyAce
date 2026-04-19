import SpriteKit

/// Decorative/bonus ring. Currently used only by the UnlockScene hero
/// animation (cosmetic). Kept contact-ready in case time-trial rings are
/// added in a future challenge type.
final class RingNode: SKNode {

    static let radius: CGFloat = 42

    init(tint: UIColor = SkyColors.tertiaryContainer) {
        super.init()
        build(tint: tint)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build(tint: UIColor) {
        let outer = SKShapeNode(circleOfRadius: RingNode.radius)
        outer.strokeColor = tint
        outer.lineWidth = 10
        outer.fillColor = .clear
        outer.glowWidth = 4
        outer.zPosition = 1
        addChild(outer)

        let inner = SKShapeNode(circleOfRadius: RingNode.radius - 10)
        inner.strokeColor = tint.withAlphaComponent(0.5)
        inner.lineWidth = 2
        inner.fillColor = .clear
        inner.zPosition = 2
        addChild(inner)

        // Contact-only — useful if the scene wants "pass-through" detection.
        let pb = SKPhysicsBody(circleOfRadius: RingNode.radius)
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.ring
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        physicsBody = pb
    }

    /// Cosmetic pulse — used while rings drift across the Unlock hero scene.
    func pulse() {
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.4),
            SKAction.scale(to: 1.0, duration: 0.4)
        ])
        run(SKAction.repeatForever(pulse))
    }
}
