import SpriteKit

/// Free Flight City — "Skyline Tour" sandbox.
///
/// The plane drifts across a dawn-coloured city skyline while 4 distinctive
/// hero landmarks spawn one at a time in random order. Each landmark carries
/// its own coin chain or ring; collecting anything from a landmark fills
/// its stamp slot. All 4 stamps = +100 coin bonus + confetti celebration,
/// then the stamp card resets for another lap.
///
/// No fail state: the plane can't collide with buildings or boundaries —
/// only with coins and rings (which trigger collection, not damage).
final class FreeFlightCityScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Landmark catalog

    private enum Landmark: Int, CaseIterable {
        case blueTower, redHouse, clockTower, flowerHouse

        var spriteName: String {
            switch self {
            case .blueTower:   return SkySprites.cityTowerBlue
            case .redHouse:    return SkySprites.cityHouseRed
            case .clockTower:  return SkySprites.cityClockTower
            case .flowerHouse: return SkySprites.cityFlowerHouse
            }
        }
        var displaySize: CGSize {
            switch self {
            case .blueTower:   return CGSize(width: 180, height: 270)
            case .redHouse:    return CGSize(width: 160, height: 200)
            case .clockTower:  return CGSize(width: 180, height: 270)
            case .flowerHouse: return CGSize(width: 160, height: 200)
            }
        }
        var fallbackColor: UIColor {
            switch self {
            case .blueTower:   return SkyColors.primary
            case .redHouse:    return UIColor(hex: 0xE8424A)
            case .clockTower:  return UIColor(hex: 0xF3B100)
            case .flowerHouse: return UIColor(hex: 0x4CAF7D)
            }
        }
    }

    // MARK: - State

    private let worldNode = SKNode()
    private var plane: PlaneNode!
    private var isTouching = false
    private var lastUpdateTime: TimeInterval = 0

    // Parallax + decor
    private var distantSilhouettes = SKNode()
    private var groundStrip        = SKNode()
    private var birdLayer          = SKNode()
    private var landmarkLayer      = SKNode()

    // Landmark spawn state
    private var lastLandmarkSpawn: TimeInterval = 0
    private let landmarkSpawnInterval: TimeInterval = 10
    private let landmarkScrollSpeed: CGFloat = 110
    private var lastSpawnedLandmark: Landmark?

    // Stamps
    private var collectedStamps: Set<Landmark> = []
    private var stampCardHUD: StampCardHUD!

    // Safe area (populated in didMove)
    private var topSafeInset: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(hex: 0xFF9A6C)
        physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
        physicsWorld.contactDelegate = self
        topSafeInset = view.safeAreaInsets.top
        SkyHaptics.prepare()

        addChild(worldNode)
        buildSkyGradient()
        buildDistantSilhouettes()
        buildGroundStrip()
        buildBirds()
        buildLandmarkLayer()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Background layers

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
        for _ in 0..<12 {
            let h = CGFloat.random(in: 40...100)
            let w = CGFloat.random(in: 40...80)
            let rect = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 3)
            rect.fillColor = UIColor(hex: 0x6F3A00).withAlphaComponent(0.35)
            rect.strokeColor = .clear
            rect.position = CGPoint(
                x: CGFloat.random(in: 0...size.width * 1.5),
                y: 120 + h / 2
            )
            distantSilhouettes.addChild(rect)
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
    }

    private func buildBirds() {
        birdLayer.zPosition = -20
        worldNode.addChild(birdLayer)
        for _ in 0..<4 {
            let v = SKLabelNode(text: "v")
            v.fontSize = 14
            v.fontColor = SkyColors.onSurface.withAlphaComponent(0.3)
            v.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.5...size.height * 0.85)
            )
            birdLayer.addChild(v)
            let path = UIBezierPath()
            path.move(to: v.position)
            path.addQuadCurve(
                to: CGPoint(x: v.position.x - size.width - 60, y: v.position.y + CGFloat.random(in: -40...40)),
                controlPoint: CGPoint(x: v.position.x - size.width / 2, y: v.position.y + CGFloat.random(in: -60...60))
            )
            let follow = SKAction.follow(path.cgPath, asOffset: false, orientToPath: false, duration: 14)
            v.run(SKAction.repeatForever(SKAction.sequence([follow, SKAction.run { [weak self] in
                guard let self = self else { return }
                v.position = CGPoint(
                    x: self.size.width + 60,
                    y: CGFloat.random(in: self.size.height * 0.5...self.size.height * 0.85)
                )
            }])))
        }
    }

    private func buildLandmarkLayer() {
        landmarkLayer.zPosition = -40
        worldNode.addChild(landmarkLayer)
    }

    private func buildPlane() {
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID)
        plane.position = CGPoint(x: size.width * 0.28, y: size.height / 2)
        plane.zPosition = 10
        // Sandbox: physics body keeps coin/ring contact detection but
        // drops obstacle/boundary so nothing can crash the plane.
        plane.physicsBody?.categoryBitMask = PhysicsCategory.plane
        plane.physicsBody?.contactTestBitMask = PhysicsCategory.coin | PhysicsCategory.ring
        plane.physicsBody?.collisionBitMask = 0
        worldNode.addChild(plane)
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

        let label = SKLabelNode(text: "SKYLINE TOUR")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: barCenterY)
        label.zPosition = 200
        addChild(label)

        // Stamp card in the upper-right.
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
        node.position = CGPoint(x: size.width + 160, y: landmarkCenterY(for: chosen))
        landmarkLayer.addChild(node)

        let travel: CGFloat = size.width + 400
        let duration = TimeInterval(travel / landmarkScrollSpeed)
        node.run(SKAction.sequence([
            SKAction.moveBy(x: -travel, y: 0, duration: duration),
            SKAction.removeFromParent()
        ]))
    }

    private func landmarkCenterY(for landmark: Landmark) -> CGFloat {
        // Each Stitch landmark sprite has a painted drop-shadow occupying
        // roughly the bottom 18% of the PNG. Anchoring the PNG's bottom
        // edge to the ground strip makes the *visible* building float ~18%
        // above the ground. Shifting down by that padding lands the
        // subject's visual base firmly on the ground.
        let shadowPadding = landmark.displaySize.height * 0.18
        return 80 + landmark.displaySize.height / 2 - shadowPadding
    }

    private func buildLandmarkNode(_ landmark: Landmark) -> SKNode {
        let container = SKNode()
        container.name = "landmark-\(landmark.rawValue)"

        let size = landmark.displaySize
        if let sprite = SkySprites.sprite(named: landmark.spriteName, size: size) {
            sprite.zPosition = 0
            container.addChild(sprite)
        } else {
            let shape = SKShapeNode(rectOf: size, cornerRadius: 10)
            shape.fillColor = landmark.fallbackColor
            shape.strokeColor = .clear
            shape.zPosition = 0
            container.addChild(shape)
        }

        // Attach collectibles specific to each landmark. Each collectible
        // gets zPosition = 1 so it always renders in front of the landmark
        // sprite (zPosition = 0) — no more half-hidden coins.
        switch landmark {
        case .blueTower:
            // 5 coins in a gentle S-curve along the right side of the tower.
            let ys: [CGFloat] = [100, 50, 0, -50, -100]
            for (i, y) in ys.enumerated() {
                let xOffset: CGFloat = (i % 2 == 0) ? 80 : 60
                let coin = CoinNode()
                coin.position = CGPoint(x: xOffset, y: y)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .redHouse:
            // Single coin floating at the doorway.
            let coin = CoinNode()
            coin.position = CGPoint(x: 0, y: -70)
            coin.setScale(1.3)
            coin.zPosition = 1
            container.addChild(coin)

        case .clockTower:
            // Ring at the clock face + bonus coin inside it.
            let ring = RingNode()
            ring.position = CGPoint(x: 0, y: 60)
            ring.zPosition = 1
            container.addChild(ring)
            let coin = CoinNode()
            coin.position = CGPoint(x: 0, y: 60)
            coin.zPosition = 2   // sits in front of the ring
            container.addChild(coin)

        case .flowerHouse:
            // 4 coins floating above the roof garden.
            let positions: [(CGFloat, CGFloat)] = [(-50, 85), (-15, 100), (20, 95), (55, 80)]
            for (dx, dy) in positions {
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

        // Clamp plane vertically so it can't fly off-screen top/bottom.
        plane.position.y = min(size.height - 40, max(140, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        // Parallax drift for the back layers (landmarks move themselves via SKAction).
        scrollLayer(distantSilhouettes, speed: 25, delta: delta)
        scrollLayer(groundStrip, speed: 200, delta: delta)

        spawnLandmarkIfDue(currentTime: currentTime)
    }

    private func scrollLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -200 {
                node.position.x += size.width * 2 + 200
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

    /// Walk up `node`'s parent tree looking for a node named
    /// `"landmark-<rawValue>"` — that tells us which landmark the collectible
    /// belongs to so we can stamp it.
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
            title: "TOUR COMPLETE!",
            subtitle: "+100 BONUS COINS",
            at: center,
            in: self
        )

        // Reset card after the banner clears so the loop can run again.
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
