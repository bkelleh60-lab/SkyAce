import SpriteKit

/// Sandbox mode — city skyline at dawn. No fail state, coins not persisted,
/// upgrades are read-only.
final class FreeFlightCityScene: SKScene {

    private let worldNode = SKNode()
    private var plane: PlaneNode!
    private var isTouching = false
    private var lastUpdateTime: TimeInterval = 0

    // Parallax layers
    private var distantSilhouettes = SKNode()
    private var midBuildings = SKNode()
    private var foreBuildings = SKNode()
    private var groundStrip = SKNode()
    private var birdLayer  = SKNode()

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(hex: 0xFF9A6C)
        physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
        physicsWorld.contactDelegate = nil

        addChild(worldNode)
        buildSkyGradient()
        buildDistantSilhouettes()
        buildMidBuildings()
        buildForeBuildings()
        buildGroundStrip()
        buildBirds()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Layers

    private func buildSkyGradient() {
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: size,
            top: UIColor(hex: 0xFF9A6C),
            bottom: UIColor(hex: 0xFFD4A3)
        )
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        worldNode.addChild(bg)
    }

    private func buildDistantSilhouettes() {
        distantSilhouettes.zPosition = -80
        worldNode.addChild(distantSilhouettes)
        for _ in 0..<10 {
            let h = CGFloat.random(in: 40...90)
            let w = CGFloat.random(in: 40...80)
            let rect = SKShapeNode(rectOf: CGSize(width: w, height: h))
            rect.fillColor = UIColor(hex: 0x6F3A00).withAlphaComponent(0.35)
            rect.strokeColor = .clear
            rect.position = CGPoint(x: CGFloat.random(in: 0...size.width * 1.5), y: 120 + h / 2)
            distantSilhouettes.addChild(rect)
        }
    }

    private func buildMidBuildings() {
        midBuildings.zPosition = -60
        worldNode.addChild(midBuildings)
        for _ in 0..<8 {
            let building = makeCityBuilding(
                size: CGSize(width: CGFloat.random(in: 60...100), height: CGFloat.random(in: 100...180)),
                flicker: true
            )
            building.position = CGPoint(x: CGFloat.random(in: 0...size.width * 2), y: 100)
            midBuildings.addChild(building)
        }
    }

    private func buildForeBuildings() {
        foreBuildings.zPosition = -40
        worldNode.addChild(foreBuildings)
        for _ in 0..<6 {
            let building = makeCityBuilding(
                size: CGSize(width: CGFloat.random(in: 80...140), height: CGFloat.random(in: 140...240)),
                flicker: false
            )
            building.position = CGPoint(x: CGFloat.random(in: 0...size.width * 2), y: 80)
            foreBuildings.addChild(building)
        }
    }

    private func buildGroundStrip() {
        groundStrip.zPosition = -30
        worldNode.addChild(groundStrip)
        let base = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: 80))
        base.fillColor = UIColor(hex: 0x5B2A00)
        base.strokeColor = .clear
        base.position = CGPoint(x: size.width, y: 40)
        groundStrip.addChild(base)

        for i in 0..<12 {
            let antenna = SKShapeNode(rectOf: CGSize(width: 2, height: 18), cornerRadius: 1)
            antenna.fillColor = SkyColors.onSurface.withAlphaComponent(0.6)
            antenna.strokeColor = .clear
            antenna.position = CGPoint(x: CGFloat(i) * 220 + 60, y: 90)
            groundStrip.addChild(antenna)
        }
    }

    private func buildBirds() {
        birdLayer.zPosition = -20
        worldNode.addChild(birdLayer)
        for _ in 0..<4 {
            let v = SKLabelNode(text: "v")
            v.fontName = SkyFonts.headlineName
            v.fontSize = 14
            v.fontColor = SkyColors.onSurface.withAlphaComponent(0.3)
            v.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: size.height * 0.5...size.height * 0.85))
            birdLayer.addChild(v)
            let path = UIBezierPath()
            path.move(to: v.position)
            path.addQuadCurve(
                to: CGPoint(x: v.position.x - size.width - 60, y: v.position.y + CGFloat.random(in: -40...40)),
                controlPoint: CGPoint(x: v.position.x - size.width / 2, y: v.position.y + CGFloat.random(in: -60...60))
            )
            let follow = SKAction.follow(path.cgPath, asOffset: false, orientToPath: false, duration: 14)
            v.run(SKAction.repeatForever(SKAction.sequence([follow, SKAction.run {
                v.position = CGPoint(x: self.size.width + 60, y: CGFloat.random(in: self.size.height * 0.5...self.size.height * 0.85))
            }])))
        }
    }

    private func buildPlane() {
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID)
        plane.position = CGPoint(x: size.width * 0.28, y: size.height / 2)
        plane.zPosition = 10
        // Contact-free sandbox.
        plane.physicsBody?.contactTestBitMask = 0
        plane.physicsBody?.categoryBitMask = 0
        worldNode.addChild(plane)
    }

    // MARK: - Building makers

    private func makeCityBuilding(size: CGSize, flicker: Bool) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: size, cornerRadius: 4)
        body.fillColor = UIColor(hex: 0x3D2300)
        body.strokeColor = .clear
        body.position = CGPoint(x: 0, y: size.height / 2)
        container.addChild(body)

        // Flickering windows — small yellow dots.
        let cols = Int(size.width / 14)
        let rows = Int(size.height / 18)
        for c in 0..<cols {
            for r in 0..<rows {
                guard Bool.random() else { continue }
                let window = SKShapeNode(rectOf: CGSize(width: 4, height: 6))
                window.fillColor = UIColor(hex: 0xFFD709)
                window.strokeColor = .clear
                let x = -size.width / 2 + 10 + CGFloat(c) * 14
                let y = 20 + CGFloat(r) * 18
                window.position = CGPoint(x: x, y: y)
                container.addChild(window)
                if flicker {
                    let flickerAction = SKAction.sequence([
                        SKAction.wait(forDuration: TimeInterval.random(in: 2...5)),
                        SKAction.fadeAlpha(to: 0.3, duration: 0.2),
                        SKAction.fadeAlpha(to: 1.0, duration: 0.2)
                    ])
                    window.run(SKAction.repeatForever(flickerAction))
                }
            }
        }
        return container
    }

    // MARK: - Top bar

    private func buildTopBar() {
        let label = SKLabelNode(text: "CITY SKYLINE")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 80, y: size.height - 40)
        label.zPosition = 200
        addChild(label)

        let exit = SkyPillButton(title: "EXIT", style: .surface, size: CGSize(width: 76, height: 32)) {
            SkyNavigator.shared.showMenu()
        }
        exit.position = CGPoint(x: 52, y: size.height - 40)
        exit.zPosition = 200
        addChild(exit)
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if isTouching { plane.climb() }
        plane.update()

        // Clamp plane vertically.
        plane.position.y = min(size.height - 40, max(140, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        // Parallax drift — each layer scrolls at a different speed.
        scrollLayer(distantSilhouettes, speed: 25, delta: delta)
        scrollLayer(midBuildings, speed: 70, delta: delta)
        scrollLayer(foreBuildings, speed: 140, delta: delta)
        scrollLayer(groundStrip, speed: 200, delta: delta)
    }

    private func scrollLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -200 {
                node.position.x += size.width * 2 + 200
            }
        }
    }

    // MARK: - Touch

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
