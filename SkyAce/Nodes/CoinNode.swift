import SpriteKit

/// Collectible gold coin. Contact-only physics; movement is handled by
/// the scene moving an entire spawn wave.
final class CoinNode: SKNode {

    static let size: CGFloat = 26

    private let bodyShape: SKShapeNode

    override init() {
        self.bodyShape = SKShapeNode(circleOfRadius: CoinNode.size / 2)
        super.init()
        build()
        configurePhysics()
        animate()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build() {
        bodyShape.fillColor = SkyColors.tertiaryContainer
        bodyShape.strokeColor = .clear
        bodyShape.zPosition = 1
        addChild(bodyShape)

        // Inner ring — adds perceived depth without a border line.
        let inner = SKShapeNode(circleOfRadius: CoinNode.size / 2 - 5)
        inner.fillColor = SkyColors.onTertiaryContainer.withAlphaComponent(0.2)
        inner.strokeColor = .clear
        inner.zPosition = 2
        addChild(inner)

        let star = SKLabelNode(text: "★")
        star.fontColor = SkyColors.onTertiaryContainer
        star.fontName = SkyFonts.headlineName
        star.fontSize = 14
        star.verticalAlignmentMode = .center
        star.horizontalAlignmentMode = .center
        star.zPosition = 3
        addChild(star)
    }

    private func configurePhysics() {
        let pb = SKPhysicsBody(circleOfRadius: CoinNode.size / 2)
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.coin
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        physicsBody = pb
    }

    private func animate() {
        // Flip rotation + subtle bob.
        let flip = SKAction.sequence([
            SKAction.scaleX(to: 0.2, duration: 0.5),
            SKAction.scaleX(to: 1.0, duration: 0.5)
        ])
        bodyShape.run(SKAction.repeatForever(flip))

        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.6),
            SKAction.moveBy(x: 0, y: -4, duration: 0.6)
        ])
        run(SKAction.repeatForever(bob))
    }

    /// Called by scene when plane contacts the coin. Plays pop + removes.
    func collect() {
        physicsBody = nil
        let pop = SKAction.group([
            SKAction.scale(to: 1.8, duration: 0.2),
            SKAction.fadeOut(withDuration: 0.2)
        ])
        run(SKAction.sequence([pop, SKAction.removeFromParent()]))
    }
}
