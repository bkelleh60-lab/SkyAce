import SpriteKit

/// Free Flight Mountain — "Mountain Expedition" sandbox.
///
/// Paid-only. Cold blue-sky range with drifting snowfall and 4 distinctive
/// hero landmarks that spawn one at a time in random order (snow dome,
/// pine grove, jagged peaks + gold nuggets, floating sky island + waterfall).
/// Each landmark carries a coin chain or ring for the player to collect.
/// No fail state — boundaries and background scenery can't crash the plane.
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

    private var bgFar          = SKNode()
    private var bgMid          = SKNode()
    private var bgNear         = SKNode()
    private var cloudWisps     = SKNode()
    private var pineLine       = SKNode()
    private var skyProps       = SKNode()
    private var landmarkLayer  = SKNode()

    private var lastLandmarkSpawn: TimeInterval = 0
    private let landmarkSpawnInterval: TimeInterval = 12
    private let landmarkScrollSpeed: CGFloat = 100
    private var lastSpawnedLandmark: Landmark?

    private var topSafeInset: CGFloat = 0

    // Flyable Y band — mirrors the clamp applied to the plane each frame in
    // update(). Collectibles must sit inside this band (with a buffer above
    // the floor) so the plane can actually fly to and through them. SKY-54:
    // before this was extracted, jaggedPeaks coins lived at offsets of -50/-60
    // (abs y ~80) — below the visible mountain peaks and far below the lower
    // plane clamp, so they were uncollectible in a paid scene.
    private let planeMinY: CGFloat = 160
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Smallest absolute Y a coin or ring is allowed to sit at. 30pt above
    /// `planeMinY` keeps the plane's hitbox top clear of the collectible's
    /// bottom edge, so the plane has to actively climb to collect rather
    /// than scraping the floor. Mirrors FreeFlightCityScene.
    private var collectibleMinY: CGFloat { planeMinY + 30 }

    // Currency HUD (top-right).
    private var currencyHUD: CurrencyHUD!

    // Ring speed boost. See FreeFlightCityScene for design notes — this
    // mirrors the same multiplier-on-scroll-speed approach.
    private let boostPeakMultiplier: CGFloat = 1.75
    private let boostHoldDuration: TimeInterval = 2.5
    private let boostTaperDuration: TimeInterval = 0.5
    private var boostActiveUntil: TimeInterval = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        physicsWorld.contactDelegate = self
        SkyHaptics.prepare()
        layoutScene()

        // SKY-75: engine ambience.
        AudioManager.shared.playEngineLoop(
            SkyEngineLoop.filename(forPlaneID: ProgressManager.shared.selectedPlaneID)
        )
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        AudioManager.shared.stopEngineLoop()
        // SKY-68: leaving the scene ends one Free Flight session. Record it and
        // report progress toward "Free Spirit" (and any coins earned this
        // session toward the coin achievements).
        ProgressManager.shared.incrementFreeFlightSessions()
        GameCenterManager.shared.refreshProgress()
    }

    // SKY-55: see FreeFlightCityScene.didChangeSize — same rationale (no win/
    // lose state, currency totals already in CurrencyManager). Tear down every
    // parallax container, drop landmarks/cable car/eagles, rebuild against the
    // new dimensions.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, worldNode.parent != nil else { return }
        worldNode.removeAllChildren()
        worldNode.removeAllActions()
        worldNode.removeFromParent()
        bgFar = SKNode()
        bgMid = SKNode()
        bgNear = SKNode()
        cloudWisps = SKNode()
        pineLine = SKNode()
        skyProps = SKNode()
        landmarkLayer = SKNode()
        lastLandmarkSpawn = 0
        lastSpawnedLandmark = nil
        boostActiveUntil = 0
        lastUpdateTime = 0
        plane = nil
        currencyHUD = nil
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    private func layoutScene() {
        topSafeInset = view?.safeAreaInsets.top ?? 0
        addChild(worldNode)
        buildSkyGradient()
        buildMountainBackground()
        buildCloudWisps()
        buildSkyProps()
        buildPineLine()
        buildLandmarkLayer()
        buildCableCar()
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

    /// Three tiling parallax mountain layers. Each layer scrolls at a fixed
    /// fraction of the world speed (far slowest, near fastest) so the range
    /// reads with depth as the plane flies forward.
    private func buildMountainBackground() {
        bgFar.zPosition  = -95
        bgMid.zPosition  = -90
        bgNear.zPosition = -85
        worldNode.addChild(bgFar)
        worldNode.addChild(bgMid)
        worldNode.addChild(bgNear)

        // Layer geometry: far layer sits highest on screen and is faintest,
        // near layer sits lowest and is full opacity. Heights tuned so each
        // band's painted peaks rise above the band below it.
        buildTilingLayer(
            into: bgFar,
            spriteName: SkySprites.mountainBgFar,
            tileHeight: 220,
            centerY: size.height * 0.215,
            alpha: 0.65
        )
        buildTilingLayer(
            into: bgMid,
            spriteName: SkySprites.mountainBgMid,
            tileHeight: 200,
            centerY: size.height * 0.172,
            alpha: 0.85
        )
        buildTilingLayer(
            into: bgNear,
            spriteName: SkySprites.mountainBgNear,
            tileHeight: 180,
            centerY: size.height * 0.140,
            alpha: 1.0
        )
    }

    /// Tiles `spriteName` horizontally across `layer`, sized to `tileHeight`
    /// preserving the asset's aspect ratio. Stores the per-tile width in
    /// `layer.userData` so `scrollTilingLayer` can recycle off-screen tiles.
    /// Falls back to a simple colored strip if the texture is missing.
    private func buildTilingLayer(into layer: SKNode,
                                  spriteName: String,
                                  tileHeight: CGFloat,
                                  centerY: CGFloat,
                                  alpha: CGFloat) {
        let texture = SkySprites.texture(named: spriteName)
        let aspect: CGFloat = {
            if let tex = texture {
                let s = tex.size()
                return s.height > 0 ? s.width / s.height : 1.75
            }
            return 1.75
        }()
        let tileWidth = tileHeight * aspect
        // Cover full screen plus a safety buffer of one extra tile so the
        // recycled tile is already in place when the leftmost tile cycles.
        let copies = max(2, Int(ceil(size.width / tileWidth)) + 1)

        for i in 0..<copies {
            let node: SKSpriteNode
            if let tex = texture {
                node = SKSpriteNode(texture: tex, size: CGSize(width: tileWidth, height: tileHeight))
            } else {
                node = SKSpriteNode(
                    color: UIColor(hex: 0x3D5F7C).withAlphaComponent(0.35),
                    size: CGSize(width: tileWidth, height: tileHeight)
                )
            }
            node.alpha = alpha
            node.position = CGPoint(
                x: tileWidth * (CGFloat(i) + 0.5),
                y: centerY
            )
            layer.addChild(node)
        }

        let userData = layer.userData ?? NSMutableDictionary()
        userData["tileWidth"] = tileWidth
        layer.userData = userData
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

    /// Foreground pine forest that scrolls at world speed. A ski lodge sits
    /// among the trees on every other tile so the landmark recurs roughly
    /// once every ~screen-and-a-half of travel — recurring scenery, not a
    /// hero landmark, with no collision or collectibles.
    private func buildPineLine() {
        pineLine.zPosition = -45
        worldNode.addChild(pineLine)

        let tileHeight: CGFloat = 110
        let centerY: CGFloat = 55  // base of pine strip flush with bottom (0)
        buildTilingLayer(
            into: pineLine,
            spriteName: SkySprites.mountainPineTrees,
            tileHeight: tileHeight,
            centerY: centerY,
            alpha: 1.0
        )

        // Ski lodge: child of one pine tile so it scrolls and recycles
        // alongside the trees. Anchored a little above the pine baseline so
        // it appears nestled in the grove rather than floating.
        guard let tileWidth = pineLine.userData?["tileWidth"] as? CGFloat,
              let lodgeTex = SkySprites.texture(named: SkySprites.mountainSkiLodge),
              pineLine.children.count >= 2 else { return }

        let lodgeHeight: CGFloat = 90
        let lodgeAspect = lodgeTex.size().height > 0
            ? lodgeTex.size().width / lodgeTex.size().height
            : 1.0
        let lodgeWidth = lodgeHeight * lodgeAspect
        let lodge = SKSpriteNode(
            texture: lodgeTex,
            size: CGSize(width: lodgeWidth, height: lodgeHeight)
        )
        // Offset within the host tile (tile is anchored at center, so
        // child x is relative to tile center). Place lodge ~25% in from
        // the tile's left edge so it doesn't clip when the tile cycles.
        lodge.position = CGPoint(x: -tileWidth * 0.25, y: tileHeight * 0.4)
        lodge.zPosition = 1
        pineLine.children[1].addChild(lodge)
    }

    private func buildLandmarkLayer() {
        landmarkLayer.zPosition = -40
        worldNode.addChild(landmarkLayer)
    }

    /// Cable car suspended on a thin cable line, traversing the upper sky in
    /// a slow left-right loop. Screen-anchored — does not parallax-scroll
    /// with the world. The cable line is a 1pt SKShapeNode, the one
    /// programmatic-art exception explicitly granted by the SKY-23 ticket
    /// (a structural element, not a visual asset).
    private func buildCableCar() {
        guard let texture = SkySprites.texture(named: SkySprites.mountainCableCar) else { return }

        let cableY = size.height * 0.65
        let leftAnchor = CGPoint(x: -10, y: cableY + 20)
        let rightAnchor = CGPoint(x: size.width + 10, y: cableY - 20)

        let path = CGMutablePath()
        path.move(to: leftAnchor)
        path.addLine(to: rightAnchor)
        let cable = SKShapeNode(path: path)
        cable.strokeColor = UIColor(white: 0.15, alpha: 0.55)
        cable.lineWidth = 1
        cable.zPosition = -25
        addChild(cable)

        let gondolaHeight: CGFloat = 56
        let aspect = texture.size().height > 0
            ? texture.size().width / texture.size().height
            : 1.0
        let gondolaWidth = gondolaHeight * aspect
        let gondola = SKSpriteNode(
            texture: texture,
            size: CGSize(width: gondolaWidth, height: gondolaHeight)
        )
        gondola.zPosition = -24

        // Animate gondola along the cable line. The line slopes slightly
        // downward (right anchor lower than left), so we lerp y in sync.
        // Hang the gondola ~6pt below the cable so the sprite reads as
        // suspended rather than skewered by the cable.
        let dropBelowCable: CGFloat = -6
        let startX: CGFloat = leftAnchor.x + 30
        let endX: CGFloat = rightAnchor.x - 30

        func yOnCable(at x: CGFloat) -> CGFloat {
            let t = (x - leftAnchor.x) / (rightAnchor.x - leftAnchor.x)
            return leftAnchor.y + (rightAnchor.y - leftAnchor.y) * t + dropBelowCable
        }

        gondola.position = CGPoint(x: startX, y: yOnCable(at: startX))
        addChild(gondola)

        let traverseDuration: TimeInterval = 30
        let goRight = SKAction.customAction(withDuration: traverseDuration) { node, elapsed in
            let t = CGFloat(elapsed / CGFloat(traverseDuration))
            let x = startX + (endX - startX) * t
            node.position = CGPoint(x: x, y: yOnCable(at: x))
        }
        let flipForReturn = SKAction.scaleX(to: -1, duration: 0)
        let flipForward   = SKAction.scaleX(to: 1, duration: 0)
        let goLeft = SKAction.customAction(withDuration: traverseDuration) { node, elapsed in
            let t = CGFloat(elapsed / CGFloat(traverseDuration))
            let x = endX + (startX - endX) * t
            node.position = CGPoint(x: x, y: yOnCable(at: x))
        }
        gondola.run(SKAction.repeatForever(SKAction.sequence([
            goRight, flipForReturn, goLeft, flipForward
        ])))
    }

    /// Ambient mid-sky props: a hang glider and a hot air balloon drift
    /// across the scene at varying heights, recurring on staggered timers
    /// so the sky never feels empty. Independent of world scroll — they
    /// have their own slow horizontal animations.
    private func buildSkyProps() {
        skyProps.zPosition = -55
        addChild(skyProps)

        scheduleSkyProp(
            spriteName: SkySprites.mountainHangGlider,
            propHeight: 44,
            yRange: size.height * 0.55 ... size.height * 0.78,
            duration: 22,
            firstDelay: 3
        )
        scheduleSkyProp(
            spriteName: SkySprites.mountainHotAirBalloon,
            propHeight: 70,
            yRange: size.height * 0.45 ... size.height * 0.72,
            duration: 30,
            firstDelay: 12,
            bobs: true
        )
    }

    private func scheduleSkyProp(spriteName: String,
                                 propHeight: CGFloat,
                                 yRange: ClosedRange<CGFloat>,
                                 duration: TimeInterval,
                                 firstDelay: TimeInterval,
                                 bobs: Bool = false) {
        guard let texture = SkySprites.texture(named: spriteName) else { return }
        let aspect = texture.size().height > 0
            ? texture.size().width / texture.size().height
            : 1.0
        let propWidth = propHeight * aspect

        let cycle = SKAction.run { [weak self] in
            guard let self = self else { return }
            let prop = SKSpriteNode(
                texture: texture,
                size: CGSize(width: propWidth, height: propHeight)
            )
            let startY = CGFloat.random(in: yRange)
            prop.position = CGPoint(x: -propWidth, y: startY)
            self.skyProps.addChild(prop)

            let drift = SKAction.moveBy(
                x: self.size.width + propWidth * 2,
                y: CGFloat.random(in: -30...30),
                duration: duration
            )
            if bobs {
                let bob = SKAction.repeatForever(SKAction.sequence([
                    SKAction.moveBy(x: 0, y: 8, duration: 1.4),
                    SKAction.moveBy(x: 0, y: -8, duration: 1.4)
                ]))
                prop.run(bob)
            }
            prop.run(SKAction.sequence([drift, SKAction.removeFromParent()]))
        }
        let gap = SKAction.wait(forDuration: duration * 0.9, withRange: 4)
        skyProps.run(SKAction.sequence([
            SKAction.wait(forDuration: firstDelay),
            SKAction.repeatForever(SKAction.sequence([cycle, gap]))
        ]))
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
        // Free-flight baseline: 2x visual scale so the plane reads prominent
        // against the far peaks and valley floor. Hitbox stays at the
        // PlaneNode defaults — scale affects only the rendered sprite.
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 2.0)
        plane.position = CGPoint(x: size.width * 0.28, y: size.height / 2)
        plane.zPosition = 10
        // Sandbox: keep coin/ring contact but drop obstacle/boundary so
        // nothing in the scene can crash the plane.
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

        let label = SKLabelNode(text: "MOUNTAIN EXPEDITION")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: barCenterY)
        label.zPosition = 200
        addChild(label)

        // Currency HUD in the upper-right. The title label here is wider
        // ("MOUNTAIN EXPEDITION"), so we reserve a bit more left-side space
        // before the HUD's available width starts.
        currencyHUD = CurrencyHUD()
        let rightMargin: CGFloat = 12
        let availableWidth = max(120, size.width - 240 - rightMargin)
        currencyHUD.layout(maxWidth: availableWidth)
        currencyHUD.position = CGPoint(x: size.width - rightMargin, y: barCenterY)
        currencyHUD.zPosition = 200
        addChild(currencyHUD)
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
        //
        // Y offsets are landmark-relative; they're chosen so each
        // collectible's *absolute* Y (= landmark.centerY + offset.y) lands
        // inside the plane's flyable band — i.e. >= collectibleMinY (190).
        // Validated by assertCollectiblesInFlyableBand below, so any future
        // tweak that drops a collectible back into the unreachable floor
        // zone trips in DEBUG builds.
        let landmarkCenter = landmark.centerY(for: size)
        switch landmark {
        case .snowDome:
            // 4 coins in an arc curving over the snowy dome. Side offsets
            // bumped from 50→60 so abs y clears the 190 floor (was 187.6,
            // 2.4pt below the plane's lower clamp).
            let arc: [(CGFloat, CGFloat)] = [(-70, 60), (-25, 100), (25, 100), (70, 60)]
            for (dx, dy) in arc {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .pineGrove:
            // 3 coins hidden between the treetops. Side offsets bumped
            // 50→60 to clear the flyable floor (same fix as snowDome).
            let spots: [(CGFloat, CGFloat)] = [(-55, 60), (0, 80), (55, 60)]
            for (dx, dy) in spots {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .jaggedPeaks:
            // Treasure run — 3 oversized gold coins arching just above the
            // peak tips. Original SKY-54 placement had these "at the base of
            // the peaks" with offsets of -50/-60 → abs y ~80, well below the
            // plane's lower clamp (160) and visually buried inside the
            // mountain sprite. Repositioned above the peak tips (landmark
            // top ~ centerY + 90 = 227) so the player flies up and over
            // the mountains to grab them.
            let nuggets: [(CGFloat, CGFloat)] = [(-50, 75), (0, 95), (50, 75)]
            for (dx, dy) in nuggets {
                let coin = CoinNode()
                coin.setScale(1.4)
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .skyIsland:
            // Ring in the waterfall's path, plus 2 coins floating above the
            // grass top. skyIsland is sky-anchored (centerY = sceneHeight *
            // 0.58) so even the -100 ring offset lands well above the
            // flyable floor.
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

        assertCollectiblesInFlyableBand(container, landmarkCenterY: landmarkCenter)
        return container
    }

    /// DEBUG-only sanity check: every coin/ring inside `container` must sit
    /// at an absolute Y >= `collectibleMinY`. Catches future regressions
    /// where someone tweaks an offset and accidentally drops a collectible
    /// back into the unreachable floor zone (the SKY-54 bug).
    private func assertCollectiblesInFlyableBand(_ container: SKNode,
                                                 landmarkCenterY: CGFloat) {
        #if DEBUG
        for child in container.children {
            guard child is CoinNode || child is RingNode else { continue }
            let absY = landmarkCenterY + child.position.y
            assert(
                absY >= collectibleMinY,
                "Collectible at offset y=\(child.position.y) → abs y=\(absY) " +
                "is below collectibleMinY=\(collectibleMinY). The plane " +
                "can't reach it — raise the offset."
            )
        }
        #endif
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if isTouching { plane.climb() }
        plane.update()

        // Top margin bumped to 50pt to keep the 2x-scaled sprite (half-height
        // ~45pt) fully on-screen at the upper extreme. Lower clamp (planeMinY)
        // also gates collectible placement — see collectibleMinY.
        plane.position.y = min(planeMaxY, max(planeMinY, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        let boost = currentBoostMultiplier(at: currentTime)
        landmarkLayer.speed = boost
        plane.setBoostIntensity((boost - 1) / (boostPeakMultiplier - 1))

        // Parallax scroll: world speed = 100. Far/mid/near layers scroll at
        // 20%/50%/80% of that for depth, pine line at 190% (foreground).
        scrollTilingLayer(bgFar,  speed: 20  * boost, delta: delta)
        scrollTilingLayer(bgMid,  speed: 50  * boost, delta: delta)
        scrollTilingLayer(bgNear, speed: 80  * boost, delta: delta)
        scrollLayer(cloudWisps, speed: 30 * boost, delta: delta)
        scrollTilingLayer(pineLine, speed: 190 * boost, delta: delta)

        spawnLandmarkIfDue(currentTime: currentTime)
    }

    private func currentBoostMultiplier(at currentTime: TimeInterval) -> CGFloat {
        let timeLeft = boostActiveUntil - currentTime
        guard timeLeft > 0 else { return 1.0 }
        if timeLeft >= boostTaperDuration { return boostPeakMultiplier }
        let t = CGFloat(timeLeft / boostTaperDuration)
        return 1.0 + (boostPeakMultiplier - 1.0) * t
    }

    private func triggerSpeedBoost() {
        boostActiveUntil = lastUpdateTime + boostHoldDuration + boostTaperDuration
    }

    private func scrollLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -300 {
                node.position.x += size.width * 2 + 300
            }
        }
    }

    /// Scroll helper for layers built by `buildTilingLayer`. Recycles a tile
    /// by adding the layer's total tiled width once it slips past the left
    /// edge, so seams stay invisible.
    private func scrollTilingLayer(_ layer: SKNode, speed: CGFloat, delta: TimeInterval) {
        guard let tileWidth = layer.userData?["tileWidth"] as? CGFloat,
              !layer.children.isEmpty else { return }
        let totalWidth = tileWidth * CGFloat(layer.children.count)
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -tileWidth / 2 {
                node.position.x += totalWidth
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
                // SKY-67: persistent balance credits at FreeFlight.coinCreditRate
                // via ProgressManager (residual carries across scene swaps).
                // CurrencyManager HUD still ticks 1:1 with what the player saw.
                ProgressManager.shared.creditFreeFlightPickup(faceValue: 1)
                CurrencyManager.shared.addCoins(1)
                coin.run(AudioManager.shared.sfxAction(SkySFX.coinCollect))
                SkyHaptics.collect()
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
                ProgressManager.shared.creditFreeFlightPickup(faceValue: 5)
                CurrencyManager.shared.addRings(1)
                ring.run(AudioManager.shared.sfxAction(SkySFX.ringPass))
                SkyHaptics.collect()
                triggerSpeedBoost()
            }
        default:
            break
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
