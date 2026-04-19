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

        // Prefer bundled cloud sprites for the correct gap-facing flat edge.
        // The asset is stretched to the pillar's full dimensions; a future
        // pass can implement 9-slice scaling via SKSpriteNode.centerRect if
        // artwork demands it.
        let spriteName = isTop ? SkySprites.cloudPillarTop : SkySprites.cloudPillarBot
        if let sprite = SkySprites.sprite(
            named: spriteName,
            size: CGSize(width: width, height: height)
        ) {
            sprite.zPosition = 0
            container.addChild(sprite)
        } else {
            // Fallback: stacked overlapping cloud circles.
            let base = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: width / 2)
            base.fillColor = SkyColors.surfaceContainerHighest
            base.strokeColor = .clear
            base.zPosition = 0
            container.addChild(base)

            let puffCount = max(3, Int(height / 40))
            for i in 0..<puffCount {
                let puff = SKShapeNode(circleOfRadius: width / 2 + 4)
                puff.fillColor = SkyColors.surfaceContainerHigh
                puff.strokeColor = .clear
                let t = (CGFloat(i) / CGFloat(max(1, puffCount - 1))) - 0.5
                puff.position = CGPoint(x: 0, y: t * height * 0.9)
                puff.zPosition = -1
                container.addChild(puff)
            }
        }

        // Collision-accurate physics body matching the pillar rect.
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.obstacle
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        container.physicsBody = pb

        return container
    }
}
