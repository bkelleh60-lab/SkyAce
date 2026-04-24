import SpriteKit

/// Paired cloud-pillar obstacles. One "pair" = a top pillar and a bottom
/// pillar separated by `gap`. Constructed by the scene; the scene moves
/// them leftward via an SKAction sequence.
final class ObstacleNode: SKNode {

    let gap: CGFloat
    let sceneHeight: CGFloat
    let gapCenterY: CGFloat  // Y coordinate of the middle of the gap.

    init(sceneSize: CGSize, gap: CGFloat) {
        self.gap = gap
        self.sceneHeight = sceneSize.height

        // Random vertical placement that keeps both pillars on-screen.
        let margin: CGFloat = 80
        let minCenter = margin + gap / 2
        let maxCenter = sceneSize.height - margin - gap / 2
        self.gapCenterY = CGFloat.random(in: minCenter...maxCenter)

        super.init()
        buildPillars(sceneSize: sceneSize)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func buildPillars(sceneSize: CGSize) {
        let pillarWidth: CGFloat = 60

        // Bottom pillar — from y=0 up to gapCenterY - gap/2.
        let bottomHeight = gapCenterY - gap / 2
        if bottomHeight > 0 {
            let bottom = makePillar(width: pillarWidth, height: bottomHeight, isTop: false)
            bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
            addChild(bottom)
        }

        // Top pillar — from gapCenterY + gap/2 up to sceneHeight.
        let topY0 = gapCenterY + gap / 2
        let topHeight = sceneSize.height - topY0
        if topHeight > 0 {
            let top = makePillar(width: pillarWidth, height: topHeight, isTop: true)
            top.position = CGPoint(x: 0, y: topY0 + topHeight / 2)
            addChild(top)
        }
    }

    private func makePillar(width: CGFloat, height: CGFloat, isTop: Bool) -> SKNode {
        let container = SKNode()

        // Hazard-striped barrier: bright red base with yellow diagonal warning
        // stripes. Visual language a kid recognizes instantly as "do not touch."
        // Top and bottom variants render identically so the rule is consistent.
        let cornerRadius: CGFloat = 10
        let rectSize = CGSize(width: width, height: height)

        let base = SKShapeNode(rectOf: rectSize, cornerRadius: cornerRadius)
        base.fillColor = UIColor(red: 0.93, green: 0.20, blue: 0.15, alpha: 1.0)
        base.strokeColor = UIColor(red: 0.55, green: 0.05, blue: 0.05, alpha: 1.0)
        base.lineWidth = 2
        base.zPosition = 0
        container.addChild(base)

        let stripes = makeDiagonalStripes(size: rectSize, cornerRadius: cornerRadius)
        stripes.zPosition = 1
        container.addChild(stripes)

        // Physics body inset ~20% from visible edges on both axes, so the plane
        // only registers a crash when clearly inside the barrier.
        let hitboxWidth  = max(20, width  * 0.8)
        let hitboxHeight = max(20, height * 0.8)
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: hitboxWidth, height: hitboxHeight))
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.obstacle
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        container.physicsBody = pb

        #if DEBUG
        print(String(format: "[ObstacleNode] pillar visual: %.0fx%.0f  hitbox: %.0fx%.0f (80%% inset, %@)",
                     width, height, hitboxWidth, hitboxHeight, isTop ? "top" : "bot"))
        #endif

        return container
    }

    /// Yellow diagonal warning stripes clipped to a rounded rectangle. Stripes
    /// are drawn as rotated bars that overrun the bounds, then cropped by the
    /// rounded-rect mask so they hug the same silhouette as the red base.
    private func makeDiagonalStripes(size: CGSize, cornerRadius: CGFloat) -> SKCropNode {
        let crop = SKCropNode()

        let mask = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask

        let yellow = UIColor(red: 1.0, green: 0.84, blue: 0.17, alpha: 1.0)
        let stripeSpacing: CGFloat = 22
        let stripeWidth:   CGFloat = 10
        let span = max(size.width, size.height) * 1.6
        let step = stripeSpacing + stripeWidth
        let count = Int((span * 2) / step) + 2

        for i in 0..<count {
            let x = -span + CGFloat(i) * step
            let path = CGMutablePath()
            path.move(to:    CGPoint(x: x,                  y: -span))
            path.addLine(to: CGPoint(x: x + stripeWidth,    y: -span))
            path.addLine(to: CGPoint(x: x + stripeWidth + span * 2, y: span))
            path.addLine(to: CGPoint(x: x + span * 2,       y: span))
            path.closeSubpath()

            let stripe = SKShapeNode(path: path)
            stripe.fillColor = yellow
            stripe.strokeColor = .clear
            crop.addChild(stripe)
        }

        return crop
    }
}
