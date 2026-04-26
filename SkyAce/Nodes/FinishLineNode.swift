import SpriteKit

/// End-of-mission marker. Renders as a vertical checkered banner spanning the
/// full scene height, capped by a "FINISH" sign and a pair of fluttering
/// pennants. The scene moves it leftward at the same speed as obstacles; when
/// the plane's body overlaps the banner, the run is treated as complete.
///
/// Physics is contact-only (`PhysicsCategory.finish`) so the plane passes
/// through without any push-back — the scene resolves the win/lose outcome.
final class FinishLineNode: SKNode {

    static let bandWidth: CGFloat = 28

    init(sceneHeight: CGFloat) {
        super.init()
        build(sceneHeight: sceneHeight)
        configurePhysics(sceneHeight: sceneHeight)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build(sceneHeight: CGFloat) {
        // Soft glow behind the band — pulses to draw the eye as it scrolls in.
        let aura = SKShapeNode(
            rectOf: CGSize(width: FinishLineNode.bandWidth + 22, height: sceneHeight),
            cornerRadius: 10
        )
        aura.fillColor = SkyColors.skTertiaryContainer.withAlphaComponent(0.18)
        aura.strokeColor = SkyColors.skTertiaryContainer
        aura.lineWidth = 0
        aura.glowWidth = 14
        aura.alpha = 0.7
        aura.zPosition = 0
        aura.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.4, duration: 0.5),
            SKAction.fadeAlpha(to: 0.95, duration: 0.5)
        ])))
        addChild(aura)

        let band = makeCheckeredBand(width: FinishLineNode.bandWidth, height: sceneHeight)
        band.zPosition = 1
        addChild(band)

        let banner = makeBanner()
        banner.position = CGPoint(x: 0, y: sceneHeight / 2 - 60)
        banner.zPosition = 3
        addChild(banner)
        // Subtle bob so the banner feels like a real flag.
        banner.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: 0.06, duration: 0.6),
            SKAction.rotate(toAngle: -0.06, duration: 0.6)
        ])))

        let leftPennant = makePennant()
        leftPennant.position = CGPoint(x: -FinishLineNode.bandWidth / 2 - 4, y: sceneHeight / 2 - 8)
        leftPennant.zPosition = 2
        addChild(leftPennant)
        leftPennant.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 0.65, duration: 0.35),
            SKAction.scaleX(to: 1.0, duration: 0.35)
        ])))

        let rightPennant = makePennant()
        rightPennant.xScale = -1
        rightPennant.position = CGPoint(x: FinishLineNode.bandWidth / 2 + 4, y: sceneHeight / 2 - 8)
        rightPennant.zPosition = 2
        addChild(rightPennant)
        rightPennant.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: -0.65, duration: 0.35),
            SKAction.scaleX(to: -1.0, duration: 0.35)
        ])))
    }

    /// Two-column checkerboard, white & deep navy — universal "finish" cue.
    private func makeCheckeredBand(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()
        let rows = 14
        let rowHeight = height / CGFloat(rows)
        let cellWidth = width / 2

        for row in 0..<rows {
            for col in 0..<2 {
                let isDark = (row + col) % 2 == 0
                let cell = SKShapeNode(rectOf: CGSize(width: cellWidth, height: rowHeight))
                cell.fillColor = isDark ? SkyColors.skOnSurface : SkyColors.skSurfaceContainerLowest
                cell.strokeColor = .clear
                cell.position = CGPoint(
                    x: -cellWidth / 2 + CGFloat(col) * cellWidth,
                    y: -height / 2 + CGFloat(row) * rowHeight + rowHeight / 2
                )
                container.addChild(cell)
            }
        }
        return container
    }

    private func makeBanner() -> SKNode {
        let container = SKNode()
        let bannerSize = CGSize(width: 132, height: 38)

        let shadow = SKShapeNode(rectOf: bannerSize, cornerRadius: 12)
        shadow.fillColor = SkyColors.skOnSurface.withAlphaComponent(0.18)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -3)
        shadow.zPosition = -1
        container.addChild(shadow)

        let bg = SKShapeNode(rectOf: bannerSize, cornerRadius: 12)
        bg.fillColor = SkyColors.skPrimary
        bg.strokeColor = SkyColors.skSurfaceContainerLowest
        bg.lineWidth = 2
        bg.zPosition = 0
        container.addChild(bg)

        let label = SKLabelNode(text: "FINISH")
        label.fontName = SkyFonts.headlineItalicName
        label.fontSize = 19
        label.fontColor = SkyColors.skOnPrimary
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        container.addChild(label)

        return container
    }

    private func makePennant() -> SKNode {
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: 0,  y: 0))
        path.addLine(to: CGPoint(x: 22, y: -6))
        path.addLine(to: CGPoint(x: 0,  y: -14))
        path.closeSubpath()

        let triangle = SKShapeNode(path: path)
        triangle.fillColor = SkyColors.skTertiaryContainer
        triangle.strokeColor = .clear
        return triangle
    }

    private func configurePhysics(sceneHeight: CGFloat) {
        // Full-height contact band so the plane registers a cross at any altitude.
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: FinishLineNode.bandWidth, height: sceneHeight))
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.finish
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        physicsBody = pb
    }
}
