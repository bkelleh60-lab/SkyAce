import SpriteKit

/// Collectible gold coin. Contact-only physics; movement is handled by
/// the scene moving an entire spawn wave.
final class CoinNode: SKNode {

    static let size: CGFloat = 26

    /// True once this coin has been captured by the coin-magnet passive
    /// (SKY-66, Night Hawk). The scene selects nearby coins; the switch to
    /// homing and the per-frame pull live here (see `beginMagnetHoming()` /
    /// `home(toward:)`).
    private(set) var isMagnetized = false

    /// Flippable element — either the sprite (when bundled) or the
    /// programmatic gold circle. Kept as a property so the flip animation
    /// can scale it on the X axis.
    private let flippable: SKNode

    override init() {
        if let sprite = SkySprites.sprite(
            named: SkySprites.coin,
            size: CGSize(width: CoinNode.size, height: CoinNode.size)
        ) {
            self.flippable = sprite
        } else {
            self.flippable = CoinNode.makeProgrammaticBody()
        }
        super.init()
        addChild(flippable)
        configurePhysics()
        animate()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private static func makeProgrammaticBody() -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(circleOfRadius: CoinNode.size / 2)
        body.fillColor = SkyColors.tertiaryContainer
        body.strokeColor = .clear
        body.zPosition = 1
        container.addChild(body)

        // Inner ring — adds perceived depth without a border line.
        let inner = SKShapeNode(circleOfRadius: CoinNode.size / 2 - 5)
        inner.fillColor = SkyColors.onTertiaryContainer.withAlphaComponent(0.2)
        inner.strokeColor = .clear
        inner.zPosition = 2
        container.addChild(inner)

        let star = SKLabelNode(text: "★")
        star.fontColor = SkyColors.onTertiaryContainer
        star.fontName = SkyFonts.headlineName
        star.fontSize = 14
        star.verticalAlignmentMode = .center
        star.horizontalAlignmentMode = .center
        star.zPosition = 3
        container.addChild(star)

        return container
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
        flippable.run(SKAction.repeatForever(flip))

        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.6),
            SKAction.moveBy(x: 0, y: -4, duration: 0.6)
        ])
        run(SKAction.repeatForever(bob))
    }

    // MARK: - Coin magnet (SKY-66)

    /// Switches this coin from scrolling to plane-homing. Drops the scroll +
    /// bob actions so `home(toward:)` can drive position each frame without the
    /// scroll `moveBy` clobbering it. Idempotent — a second call is a no-op.
    func beginMagnetHoming() {
        guard !isMagnetized else { return }
        isMagnetized = true
        removeAllActions()  // scroll + bob live on self; the flip lives on the child
    }

    /// Eases this coin toward `point` (the plane). Called each frame once
    /// magnetized; collection still fires via the normal coin contact.
    func home(toward point: CGPoint, fraction: CGFloat = 0.25) {
        position.x += (point.x - position.x) * fraction
        position.y += (point.y - position.y) * fraction
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
