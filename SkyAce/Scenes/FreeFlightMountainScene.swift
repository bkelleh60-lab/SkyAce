import SpriteKit

/// Paid-only sandbox. Blue-sky gradient with snow-capped peaks, eagles on
/// bezier paths, and light snowfall particles.
final class FreeFlightMountainScene: SKScene {

    private let worldNode = SKNode()
    private var plane: PlaneNode!
    private var isTouching = false
    private var lastUpdateTime: TimeInterval = 0

    private var farPeaks  = SKNode()
    private var mainPeaks = SKNode()
    private var treeLine  = SKNode()
    private var valley    = SKNode()
    private var cloudWisps = SKNode()

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
        physicsWorld.contactDelegate = nil

        addChild(worldNode)
        buildSkyGradient()
        buildFarPeaks()
        buildMainPeaks()
        buildTreeLine()
        buildValley()
        buildCloudWisps()
        buildEagles()
        buildSnow()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Layers

    private func buildSkyGradient() {
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: size,
            top: SkyColors.skPrimary,
            bottom: SkyColors.skPrimaryContainer
        )
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        worldNode.addChild(bg)

        let topFade = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.5), size: CGSize(width: size.width, height: 120))
        topFade.anchorPoint = .zero
        topFade.position = CGPoint(x: 0, y: size.height - 120)
        topFade.zPosition = -99
        worldNode.addChild(topFade)
    }

    private func buildFarPeaks() {
        farPeaks.zPosition = -80
        worldNode.addChild(farPeaks)
        for _ in 0..<8 {
            let tri = triangle(
                size: CGSize(width: CGFloat.random(in: 90...180), height: CGFloat.random(in: 90...140)),
                color: UIColor(hex: 0x3D5F7C).withAlphaComponent(0.35)
            )
            tri.position = CGPoint(x: CGFloat.random(in: 0...size.width * 2), y: 140)
            farPeaks.addChild(tri)
        }
    }

    private func buildMainPeaks() {
        mainPeaks.zPosition = -60
        worldNode.addChild(mainPeaks)
        for _ in 0..<5 {
            let peakSize = CGSize(width: CGFloat.random(in: 160...240), height: CGFloat.random(in: 180...260))
            let group = SKNode()
            let mountain = triangle(size: peakSize, color: UIColor(hex: 0x1F3A5A))
            mountain.position = .zero
            group.addChild(mountain)

            let snowHeight = peakSize.height * 0.28
            let snowTop = triangle(size: CGSize(width: peakSize.width * 0.45, height: snowHeight), color: .white)
            snowTop.position = CGPoint(x: 0, y: peakSize.height / 2 - snowHeight / 2)
            group.addChild(snowTop)

            group.position = CGPoint(x: CGFloat.random(in: 0...size.width * 2), y: 120 + peakSize.height / 2)
            mainPeaks.addChild(group)
        }
    }

    private func buildTreeLine() {
        treeLine.zPosition = -40
        worldNode.addChild(treeLine)
        for i in 0..<30 {
            let tree = triangle(
                size: CGSize(width: 24, height: 34),
                color: UIColor(hex: 0x0F4A28)
            )
            tree.position = CGPoint(x: CGFloat(i) * 80 + CGFloat.random(in: -10...10), y: 110)
            treeLine.addChild(tree)
        }
    }

    private func buildValley() {
        valley.zPosition = -30
        worldNode.addChild(valley)
        let strip = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: 80))
        strip.fillColor = UIColor(hex: 0x0A2E15)
        strip.strokeColor = .clear
        strip.position = CGPoint(x: size.width, y: 40)
        valley.addChild(strip)
    }

    private func buildCloudWisps() {
        cloudWisps.zPosition = -50
        worldNode.addChild(cloudWisps)
        for _ in 0..<3 {
            let wisp = SKShapeNode(ellipseOf: CGSize(width: 140, height: 24))
            wisp.fillColor = UIColor.white.withAlphaComponent(0.55)
            wisp.strokeColor = .clear
            wisp.position = CGPoint(x: CGFloat.random(in: 0...size.width * 2), y: CGFloat.random(in: size.height * 0.55...size.height * 0.85))
            cloudWisps.addChild(wisp)
        }
    }

    private func buildEagles() {
        for _ in 0..<3 {
            let eagle = SKLabelNode(text: "🦅")
            eagle.fontSize = 20
            eagle.position = CGPoint(x: -40, y: CGFloat.random(in: size.height * 0.5...size.height * 0.82))
            eagle.zPosition = -10
            addChild(eagle)
            let path = UIBezierPath()
            path.move(to: eagle.position)
            path.addQuadCurve(
                to: CGPoint(x: size.width + 40, y: eagle.position.y + CGFloat.random(in: -60...60)),
                controlPoint: CGPoint(x: size.width / 2, y: eagle.position.y + CGFloat.random(in: -80...80))
            )
            let follow = SKAction.follow(path.cgPath, asOffset: false, orientToPath: false, duration: 14)
            eagle.run(SKAction.repeatForever(SKAction.sequence([follow, SKAction.run {
                eagle.position = CGPoint(x: -40, y: CGFloat.random(in: self.size.height * 0.5...self.size.height * 0.82))
            }])))
        }
    }

    private func buildSnow() {
        let snow = SKEmitterNode()
        snow.particleTexture = SKTexture(image: snowflakeImage())
        snow.particleBirthRate = 5
        snow.particleLifetime = 10
        snow.particleSpeed = 30
        snow.particleSpeedRange = 10
        snow.emissionAngle = -.pi / 2
        snow.emissionAngleRange = 0.3
        snow.particleAlpha = 0.7
        snow.particleAlphaRange = 0.2
        snow.particleScale = 0.3
        snow.particleScaleRange = 0.2
        snow.particlePositionRange = CGVector(dx: size.width, dy: 0)
        snow.position = CGPoint(x: size.width / 2, y: size.height + 20)
        snow.zPosition = -5
        worldNode.addChild(snow)
    }

    private func snowflakeImage() -> UIImage {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }

    private func buildPlane() {
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID)
        plane.position = CGPoint(x: size.width * 0.28, y: size.height / 2)
        plane.zPosition = 10
        plane.physicsBody?.contactTestBitMask = 0
        plane.physicsBody?.categoryBitMask = 0
        worldNode.addChild(plane)
    }

    private func triangle(size: CGSize, color: UIColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width / 2, y: -size.height / 2))
        path.addLine(to: CGPoint(x: -size.width / 2, y: -size.height / 2))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = color
        shape.strokeColor = .clear
        return shape
    }

    // MARK: - Top bar

    private func buildTopBar() {
        let label = SKLabelNode(text: "MOUNTAIN RANGE")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: size.height - 40)
        label.zPosition = 200
        addChild(label)

        let exit = SkyPillButton(title: "EXIT", style: .surface, size: CGSize(width: 76, height: 32)) {
            SkyNavigator.shared.showMenu()
        }
        exit.position = CGPoint(x: 52, y: size.height - 40)
        exit.zPosition = 200
        addChild(exit)
    }

    // MARK: - Update / touch

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if isTouching { plane.climb() }
        plane.update()

        plane.position.y = min(size.height - 40, max(160, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        scrollLayer(farPeaks, speed: 20, delta: delta)
        scrollLayer(mainPeaks, speed: 55, delta: delta)
        scrollLayer(cloudWisps, speed: 30, delta: delta)
        scrollLayer(treeLine, speed: 120, delta: delta)
        scrollLayer(valley, speed: 190, delta: delta)
    }

    private func scrollLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -300 {
                node.position.x += size.width * 2 + 300
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
        }
        isTouching = true
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { isTouching = false }
}
