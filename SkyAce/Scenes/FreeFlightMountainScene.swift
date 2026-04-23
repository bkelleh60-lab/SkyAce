import SpriteKit

/// Free Flight Mountain — "Mountain Expedition" sandbox.
///
/// Paid-only. Cold blue-sky range with drifting snowfall and 4 distinctive
/// hero landmarks that spawn one at a time in random order (snow dome,
/// pine grove, jagged peaks + gold nuggets, floating sky island + waterfall).
/// Collecting from each landmark fills a stamp slot; all 4 stamps triggers
/// a +100 coin bonus with confetti. No fail state — boundaries and
/// background scenery can't crash the plane.
final class FreeFlightMountainScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Landmark catalog

    private enum Landmark: Int, CaseIterable {
        case snowDome, pineGrove, jaggedPeaks, skyIsland

        var spriteName: String {
            switch self {
            case .snowDome:    return SkySprites.mountainSnowDome
            case .pineGrove:   return SkySprites.mountainPineGrove
            case .jaggedPeaks: return SkySprites.mountainJaggedPeaks
            case .skyIsland:   return SkySprites.mountainSkyIsland
            }
        }
        var displaySize: CGSize {
            switch self {
            case .snowDome:    return CGSize(width: 180, height: 180)
            case .pineGrove:   return CGSize(width: 200, height: 180)
            case .jaggedPeaks: return CGSize(width: 200, height: 180)
            case .skyIsland:   return CGSize(width: 200, height: 260)
            }
        }
        var fallbackColor: UIColor {
            switch self {
            case .snowDome:    return SkyColors.primaryContainer
            case .pineGrove:   return UIColor(hex: 0x0F4A28)
            case .jaggedPeaks: return UIColor(hex: 0x1F3A5A)
            case .skyIsland:   return UIColor(hex: 0xF5D76A)
            }
        }
        /// Y of the sprite's CENTER in the scene. Ground-anchored for the
        /// mountains (compensating for ~18% painted-shadow padding so the
        /// visible base actually sits on the valley floor), sky-anchored
        /// for the floating island.
        func centerY(for sceneSize: CGSize) -> CGFloat {
            switch self {
            case .snowDome, .pineGrove, .jaggedPeaks:
                let shadowPadding = displaySize.height * 0.18
                return 80 + displaySize.height / 2 - shadowPadding
            case .skyIsland:
                return sceneSize.height * 0.58
            }
        }
    }

    // MARK: - State

    private let worldNode = SKNode()
    private var plane: PlaneNode!
    private var isTouching = false
    private var lastUpdateTime: TimeInterval = 0

    private var farPeaks       = SKNode()
    private var cloudWisps     = SKNode()
    private var valley         = SKNode()
    private var landmarkLayer  = SKNode()

    private var lastLandmarkSpawn: TimeInterval = 0
    private let landmarkSpawnInterval: TimeInterval = 12
    private let landmarkScrollSpeed: CGFloat = 100
    private var lastSpawnedLandmark: Landmark?

    private var collectedStamps: Set<Landmark> = []
    private var stampCardHUD: StampCardHUD!

    private var topSafeInset: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
        physicsWorld.contactDelegate = self
        topSafeInset = view.safeAreaInsets.top
        SkyHaptics.prepare()

        addChild(worldNode)
        buildSkyGradient()
        buildFarPeaks()
        buildCloudWisps()
        buildValley()
        buildLandmarkLayer()
        buildEagles()
        buildSnow()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Background layers

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

        let topFade = SKSpriteNode(
            color: UIColor.white.withAlphaComponent(0.5),
            size: CGSize(width: size.width, height: 120)
        )
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

    private func buildCloudWisps() {
        cloudWisps.zPosition = -50
        worldNode.addChild(cloudWisps)
        for _ in 0..<3 {
            let wisp = SKShapeNode(ellipseOf: CGSize(width: 140, height: 24))
            wisp.fillColor = UIColor.white.withAlphaComponent(0.55)
            wisp.strokeColor = .clear
            wisp.position = CGPoint(
                x: CGFloat.random(in: 0...size.width * 2),
                y: CGFloat.random(in: size.height * 0.55...size.height * 0.85)
            )
            cloudWisps.addChild(wisp)
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

    private func buildLandmarkLayer() {
        landmarkLayer.zPosition = -40
        worldNode.addChild(landmarkLayer)
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
            eagle.run(SKAction.repeatForever(SKAction.sequence([follow, SKAction.run { [weak self] in
                guard let self = self else { return }
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
        // Sandbox: keep coin/ring contact but drop obstacle/boundary so
        // nothing in the scene can crash the plane.
        plane.physicsBody?.categoryBitMask = PhysicsCategory.plane
        plane.physicsBody?.contactTestBitMask = PhysicsCategory.coin | PhysicsCategory.ring
        plane.physicsBody?.collisionBitMask = 0
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
        let barCenterY = size.height - topSafeInset - 20

        let exit = SkyPillButton(
            title: "EXIT",
            style: .surface,
            size: CGSize(width: 76, height: 32)
        ) { SkyNavigator.shared.showMenu() }
        exit.position = CGPoint(x: 52, y: barCenterY)
        exit.zPosition = 200
        addChild(exit)

        let label = SKLabelNode(text: "MOUNTAIN EXPEDITION")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: barCenterY)
        label.zPosition = 200
        addChild(label)

        stampCardHUD = StampCardHUD(slotCount: Landmark.allCases.count)
        stampCardHUD.position = CGPoint(
            x: size.width - stampCardHUD.cardSize.width / 2 - 12,
            y: barCenterY
        )
        stampCardHUD.zPosition = 200
        addChild(stampCardHUD)
    }

    // MARK: - Landmark spawn

    private func spawnLandmarkIfDue(currentTime: TimeInterval) {
        guard currentTime - lastLandmarkSpawn >= landmarkSpawnInterval else { return }
        lastLandmarkSpawn = currentTime

        var candidates = Landmark.allCases
        if let last = lastSpawnedLandmark, candidates.count > 1 {
            candidates.removeAll { $0 == last }
        }
        guard let chosen = candidates.randomElement() else { return }
        lastSpawnedLandmark = chosen

        let node = buildLandmarkNode(chosen)
        node.position = CGPoint(x: size.width + 180, y: chosen.centerY(for: size))
        landmarkLayer.addChild(node)

        let travel: CGFloat = size.width + 440
        let duration = TimeInterval(travel / landmarkScrollSpeed)
        node.run(SKAction.sequence([
            SKAction.moveBy(x: -travel, y: 0, duration: duration),
            SKAction.removeFromParent()
        ]))
    }

    private func buildLandmarkNode(_ landmark: Landmark) -> SKNode {
        let container = SKNode()
        container.name = "landmark-\(landmark.rawValue)"

        let spriteSize = landmark.displaySize
        if let sprite = SkySprites.sprite(named: landmark.spriteName, size: spriteSize) {
            sprite.zPosition = 0
            container.addChild(sprite)
        } else {
            let shape = SKShapeNode(rectOf: spriteSize, cornerRadius: 10)
            shape.fillColor = landmark.fallbackColor
            shape.strokeColor = .clear
            shape.zPosition = 0
            container.addChild(shape)
        }

        // Collectibles sit at zPosition = 1 so they always render in front
        // of the landmark sprite (zPosition = 0).
        switch landmark {
        case .snowDome:
            // 4 coins in an arc curving over the snowy dome.
            let arc: [(CGFloat, CGFloat)] = [(-70, 50), (-25, 90), (25, 90), (70, 50)]
            for (dx, dy) in arc {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .pineGrove:
            // 3 coins hidden between the treetops.
            let spots: [(CGFloat, CGFloat)] = [(-55, 50), (0, 70), (55, 50)]
            for (dx, dy) in spots {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .jaggedPeaks:
            // Treasure run — 3 oversized gold coins at the base of the peaks.
            let nuggets: [(CGFloat, CGFloat)] = [(-50, -50), (0, -60), (50, -50)]
            for (dx, dy) in nuggets {
                let coin = CoinNode()
                coin.setScale(1.4)
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .skyIsland:
            // Ring in the waterfall's path, plus 2 coins floating above the
            // grass top.
            let ring = RingNode()
            ring.position = CGPoint(x: 0, y: -100)
            ring.zPosition = 1
            container.addChild(ring)

            let topCoins: [(CGFloat, CGFloat)] = [(-40, 90), (40, 90)]
            for (dx, dy) in topCoins {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }
        }

        return container
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if isTouching { plane.climb() }
        plane.update()

        plane.position.y = min(size.height - 40, max(160, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        scrollLayer(farPeaks, speed: 20, delta: delta)
        scrollLayer(cloudWisps, speed: 30, delta: delta)
        scrollLayer(valley, speed: 190, delta: delta)

        spawnLandmarkIfDue(currentTime: currentTime)
    }

    private func scrollLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -300 {
                node.position.x += size.width * 2 + 300
            }
        }
    }

    // MARK: - Contact (coin / ring collection)

    func didBegin(_ contact: SKPhysicsContact) {
        let (planeBody, otherBody): (SKPhysicsBody, SKPhysicsBody) = {
            if contact.bodyA.categoryBitMask == PhysicsCategory.plane { return (contact.bodyA, contact.bodyB) }
            return (contact.bodyB, contact.bodyA)
        }()
        guard planeBody.categoryBitMask == PhysicsCategory.plane else { return }

        switch otherBody.categoryBitMask {
        case PhysicsCategory.coin:
            if let coin = otherBody.node as? CoinNode {
                coin.collect()
                ProgressManager.shared.addCoins(1)
                coin.run(AudioManager.shared.sfxAction(SkySFX.coinCollect))
                SkyHaptics.collect()
                stampCollectedAncestor(of: coin)
            }
        case PhysicsCategory.ring:
            if let ring = otherBody.node as? RingNode {
                ring.physicsBody = nil
                ring.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 1.4, duration: 0.25),
                        SKAction.fadeOut(withDuration: 0.25)
                    ]),
                    SKAction.removeFromParent()
                ]))
                ProgressManager.shared.addCoins(5)
                ring.run(AudioManager.shared.sfxAction(SkySFX.ringPass))
                SkyHaptics.collect()
                stampCollectedAncestor(of: ring)
            }
        default:
            break
        }
    }

    private func stampCollectedAncestor(of node: SKNode) {
        var n: SKNode? = node
        while let current = n {
            if let name = current.name, name.hasPrefix("landmark-"),
               let raw = Int(name.replacingOccurrences(of: "landmark-", with: "")),
               let landmark = Landmark(rawValue: raw) {
                recordStamp(for: landmark)
                return
            }
            n = current.parent
        }
    }

    private func recordStamp(for landmark: Landmark) {
        guard !collectedStamps.contains(landmark) else { return }
        collectedStamps.insert(landmark)
        stampCardHUD.stamp(index: landmark.rawValue)

        if collectedStamps.count == Landmark.allCases.count {
            triggerTourComplete()
        }
    }

    private func triggerTourComplete() {
        ProgressManager.shared.addCoins(100)
        SkyHaptics.win()

        let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
        LandmarkCelebration.emitConfetti(at: center, in: self)
        LandmarkCelebration.showBanner(
            title: "EXPEDITION COMPLETE!",
            subtitle: "+100 BONUS COINS",
            at: center,
            in: self
        )

        run(SKAction.sequence([
            SKAction.wait(forDuration: 2.4),
            SKAction.run { [weak self] in
                self?.collectedStamps.removeAll()
                self?.stampCardHUD.reset()
            }
        ]))
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
