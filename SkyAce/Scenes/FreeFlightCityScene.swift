import SpriteKit

/// Free Flight City — "Skyline Tour" sandbox.
///
/// The plane drifts across a dawn-coloured city skyline while 4 distinctive
/// hero landmarks spawn one at a time in random order. Each landmark carries
/// its own coin chain or ring for the player to collect.
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
    private var farBackground = SKNode()   // Stitch cityscape PNG, slow scroll
    private var nearForeground = SKNode()  // close warm-tone buildings, fast scroll
    private var birdLayer      = SKNode()
    private var landmarkLayer  = SKNode()

    // Tile geometry for the mirror-pair scrolling loop.
    private var farTileWidth: CGFloat = 0
    private var nearTileWidth: CGFloat = 0

    // Landmark spawn state
    private var lastLandmarkSpawn: TimeInterval = 0
    private let landmarkSpawnInterval: TimeInterval = 10
    private let landmarkScrollSpeed: CGFloat = 110
    private var lastSpawnedLandmark: Landmark?

    // Currency HUD (top-right).
    private var currencyHUD: CurrencyHUD!

    // Ring speed boost.
    //
    // Free-flight forward motion is the world scrolling past a near-stationary
    // plane, so the boost is implemented as a multiplier on every horizontal
    // scroll speed (parallax layers + landmark SKAction time via
    // `landmarkLayer.speed`). On ring collection we extend `boostActiveUntil`
    // — collecting a second ring while boosted resets the timer instead of
    // stacking peaks. The taper window at the end of the boost smoothly
    // interpolates the multiplier back to 1.0 (and fades the trail with it).
    private let boostPeakMultiplier: CGFloat = 1.75
    private let boostHoldDuration: TimeInterval = 2.5
    private let boostTaperDuration: TimeInterval = 0.5
    private var boostActiveUntil: TimeInterval = 0

    // Safe area (populated in didMove)
    private var topSafeInset: CGFloat = 0

    // Flyable Y band — mirrors the clamp applied to the plane each frame in
    // update(). Collectibles must sit inside this band (with a buffer above
    // the floor) so the plane can actually fly to and through them. Without
    // the buffer, coins/rings end up below the plane's lower clamp and
    // either auto-collect on entry or stay forever out of reach.
    private let planeMinY: CGFloat = 140
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Smallest absolute Y a coin or ring is allowed to sit at. 30pt above
    /// `planeMinY` keeps the plane's hitbox top (~planeMinY + 13.5) clear of
    /// the collectible's bottom edge, so the plane has to actively climb to
    /// collect rather than scraping the floor.
    private var collectibleMinY: CGFloat { planeMinY + 30 }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(hex: 0xCDE5FF)
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

    // SKY-55: see MenuScene.didChangeSize. Free Flight is an endless sandbox
    // with no win/lose state — coin/ring totals live in CurrencyManager and
    // survive the rebuild. Plane resets to the starting Y, parallax phases and
    // landmark spawn timing reset; acceptable on a deliberate device rotation.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, worldNode.parent != nil else { return }
        worldNode.removeAllChildren()
        worldNode.removeAllActions()
        worldNode.removeFromParent()
        farBackground = SKNode()
        nearForeground = SKNode()
        birdLayer = SKNode()
        landmarkLayer = SKNode()
        farTileWidth = 0
        nearTileWidth = 0
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
        buildSkyFill()
        buildFarCityBackground()
        buildNearForeground()
        buildBirds()
        buildLandmarkLayer()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Background layers

    private func buildSkyFill() {
        // Single seamless sky gradient covering the entire scene.
        //
        // The previous attempt at SKY-12 (commit a77300a) added a small
        // skSurface→0xE8F2FF overlay along the top edge to mask the
        // SKView/scene boundary, but the actual visible "hard line" was
        // never at that boundary — it was further down, where the pale
        // gradient sky meets the **cityscape PNG's** painted sky. The
        // PNG's top row is 0x3A86CA (a saturated mid-blue), while the
        // old gradient at that y was ~0xDBECFF (almost white): a 130-unit
        // step in the red channel that the eye reads as a sharp line.
        //
        // Fix: drive the gradient from skSurface at the very top (matches
        // the SKView's UIKit background, removing any chance of a seam
        // there) down to 0x3A86CA at the y where the cityscape PNG's
        // top edge sits (≈45% from the top of the scene, since the PNG
        // is rendered at 0.55 × scene height anchored at the bottom).
        // From that point downward the gradient is hidden by the PNG,
        // so the colour is held constant and the painted sky takes over.
        let tex = Self.skyGradientTexture(size: size)
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -110
        worldNode.addChild(bg)
    }

    /// Sky gradient: skSurface (0xF2F7FF) at the sprite top, fading
    /// linearly to 0x3A86CA at 45% down (where the cityscape PNG's top
    /// edge sits), then held constant for the lower 55% (which the PNG
    /// occludes). The 45% stop is the exact colour of the PNG's top row,
    /// sampled directly from the asset, so the gradient/PNG join is
    /// continuous.
    ///
    /// `start` is set to (0, 0) and `end` to (0, size.height) so that
    /// — once the rendered image flows through the UIImage→SKTexture
    /// pipeline and back into scene coordinates — location 0 lands at
    /// the SPRITE TOP. The shared `SKGradientBackgroundNode.gradientTexture`
    /// helper uses the opposite endpoints, which is why its `top:`/`bottom:`
    /// labels are visually inverted relative to the displayed sprite.
    private static func skyGradientTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                SkyColors.skSurface.cgColor,
                UIColor(hex: 0x3A86CA).cgColor,
                UIColor(hex: 0x3A86CA).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.45, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }

    /// Slow-scrolling far layer: the Stitch-generated cityscape PNG, tiled
    /// horizontally using a mirror-pair pattern so every tile seam is pixel
    /// identical (no visible break during scroll).
    private func buildFarCityBackground() {
        farBackground.zPosition = -100
        worldNode.addChild(farBackground)

        guard let tex = SkySprites.texture(named: SkySprites.citySkylineBG) else {
            // Asset missing — fall back to a neutral mid-sky strip so the
            // scene still renders without the bright peach placeholder.
            let strip = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: 120))
            strip.fillColor = UIColor(hex: 0x9FCEF5)
            strip.strokeColor = .clear
            strip.position = CGPoint(x: size.width * 2, y: 60)
            farBackground.addChild(strip)
            farTileWidth = size.width
            return
        }

        let texSize = tex.size()
        let targetHeight = size.height * 0.55
        let targetWidth = targetHeight * (texSize.width / texSize.height)
        farTileWidth = targetWidth

        // 4 tiles (even count) so the mirror parity survives wrap-around.
        // Pattern: [A][mirror(A)][A][mirror(A)]. Seams match because:
        //   - A's right edge pixel == mirror(A)'s left edge pixel (both are
        //     the rightmost pixel of the source image).
        //   - mirror(A)'s right edge pixel == A's left edge pixel.
        let tileCount = 4
        for i in 0..<tileCount {
            let tile = SKSpriteNode(
                texture: tex,
                size: CGSize(width: targetWidth, height: targetHeight)
            )
            tile.anchorPoint = CGPoint(x: 0.5, y: 0)
            tile.position = CGPoint(
                x: CGFloat(i) * targetWidth + targetWidth / 2,
                y: 0
            )
            if i % 2 == 1 { tile.xScale = -1 }
            farBackground.addChild(tile)
        }
    }

    /// Fast-scrolling near layer: a continuous grass strip plus warm-tone
    /// foreground buildings. The content is laid out deterministically across
    /// `[0, 2 * spread)` as two identical copies so every child can share a
    /// single wrap distance of `2 * spread` without visual jumps.
    private func buildNearForeground() {
        nearForeground.zPosition = -50
        worldNode.addChild(nearForeground)

        let spread = size.width * 2
        nearTileWidth = spread

        // Grass strip: 12 short segments per copy form a seamless ribbon.
        // Individual segments keep every child a comparable size so they
        // share the wrap threshold used by the buildings.
        let segmentsPerCopy = 12
        let segmentWidth = spread / CGFloat(segmentsPerCopy)
        for copy in 0..<2 {
            let baseX = CGFloat(copy) * spread
            for s in 0..<segmentsPerCopy {
                let seg = SKShapeNode(
                    rectOf: CGSize(width: segmentWidth + 1, height: 14)
                )
                seg.fillColor = UIColor(hex: 0x4FA64F)
                seg.strokeColor = .clear
                seg.position = CGPoint(
                    x: baseX + CGFloat(s) * segmentWidth + segmentWidth / 2,
                    y: 7
                )
                nearForeground.addChild(seg)
            }
        }

        // Warm-tone close-up buildings. Heights are capped at 64 so tops stay
        // below the plane clamp (min y = 140). Fractions are deterministic
        // across copies so a building's post-wrap neighbour looks identical
        // to its pre-wrap neighbour.
        let palette: [UIColor] = [
            UIColor(hex: 0xC48660),
            UIColor(hex: 0xA8704A),
            UIColor(hex: 0xE0A97A),
            UIColor(hex: 0x8C5A3A)
        ]
        struct Slot { let f: CGFloat; let w: CGFloat; let h: CGFloat; let c: Int }
        let slots: [Slot] = [
            Slot(f: 0.075, w: 60, h: 46, c: 0),
            Slot(f: 0.225, w: 78, h: 58, c: 1),
            Slot(f: 0.375, w: 54, h: 40, c: 2),
            Slot(f: 0.525, w: 70, h: 52, c: 3),
            Slot(f: 0.675, w: 56, h: 44, c: 0),
            Slot(f: 0.875, w: 82, h: 62, c: 1)
        ]
        for copy in 0..<2 {
            let baseX = CGFloat(copy) * spread
            for slot in slots {
                let rect = SKShapeNode(
                    rectOf: CGSize(width: slot.w, height: slot.h),
                    cornerRadius: 4
                )
                rect.fillColor = palette[slot.c]
                rect.strokeColor = .clear
                rect.position = CGPoint(
                    x: baseX + slot.f * spread,
                    y: 14 + slot.h / 2
                )
                nearForeground.addChild(rect)
            }
        }
    }

    private func buildBirds() {
        birdLayer.zPosition = -20
        worldNode.addChild(birdLayer)
        for _ in 0..<4 {
            let birdSize = CGSize(width: 24, height: 12)
            let v: SKSpriteNode
            if let tex = SkySprites.texture(named: "bird") {
                v = SKSpriteNode(texture: tex, size: birdSize)
            } else {
                v = SKSpriteNode(color: .white, size: birdSize)
            }
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
        // Free-flight baseline: 2x visual scale so the plane reads big against
        // the distant skyline silhouettes (40-100pt tall) and the 80pt ground
        // strip. Hitbox is unchanged — scaling applies to the sprite only.
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 2.0)
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

        // Currency HUD in the upper-right. Available width is whatever sits
        // between the title label's right edge (with breathing room) and a
        // 12pt margin from the screen edge.
        currencyHUD = CurrencyHUD()
        let rightMargin: CGFloat = 12
        let availableWidth = max(120, size.width - 220 - rightMargin)
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
        // edge to the grass strip (y = 14) makes the *visible* building
        // float ~18% above the grass. Shifting down by that padding lands
        // the subject's visual base firmly on the grass.
        let groundBaseline: CGFloat = 14
        let shadowPadding = landmark.displaySize.height * 0.18
        return groundBaseline + landmark.displaySize.height / 2 - shadowPadding
    }

    private func buildLandmarkNode(_ landmark: Landmark) -> SKNode {
        let container = SKNode()

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
        // sprite (zPosition = 0).
        //
        // Y offsets are landmark-relative; they're chosen so each
        // collectible's *absolute* Y (= landmarkCenterY + offset.y) lands
        // inside the plane's flyable band — i.e. >= collectibleMinY (170).
        // The hand-picked numbers below are validated by the
        // `assertCollectiblesInFlyableBand` debug check at the bottom of
        // this method, so any future tweak that drops one back below the
        // floor will trip in DEBUG builds.
        let landmarkCenter = landmarkCenterY(for: landmark)
        switch landmark {
        case .blueTower:
            // 5 coins climbing the tower's right side in a gentle S-curve.
            // Tower spans absolute y ≈ -34..235 (landmarkCenter ≈ 100, h=270).
            // Offsets keep every coin between the lower flyable boundary
            // (abs y = 170) and just above the rooftop (abs y ≈ 310).
            let placements: [(x: CGFloat, y: CGFloat)] = [
                (80,  70),   // abs y ≈ 170 — bottom of the climb
                (60, 105),
                (80, 140),
                (60, 175),
                (80, 210)    // abs y ≈ 310 — floats just above the roof
            ]
            for (dx, dy) in placements {
                let coin = CoinNode()
                coin.position = CGPoint(x: dx, y: dy)
                coin.zPosition = 1
                container.addChild(coin)
            }

        case .redHouse:
            // Single coin floating above the chimney. The original "doorway"
            // placement (offset y = -70 → abs y = 8) sat on the grass,
            // entirely below the plane's lower clamp.
            let coin = CoinNode()
            coin.position = CGPoint(x: 0, y: 130)   // abs y ≈ 208
            coin.setScale(1.3)
            coin.zPosition = 1
            container.addChild(coin)

        case .clockTower:
            // Ring centred near the top of the tower with a bonus coin
            // nested in it. Lifted from offset 60 (abs y ≈ 160 — ring
            // bottom at 118, well below the plane floor) to offset 110 so
            // the ring's bottom edge (abs y ≈ 168) sits clear of the
            // plane's hitbox-top at floor (~153.5). The plane has to
            // actively climb to fly through the centre at abs y ≈ 210
            // rather than auto-collect from the floor.
            let ring = RingNode()
            ring.position = CGPoint(x: 0, y: 110)
            ring.zPosition = 1
            container.addChild(ring)
            let coin = CoinNode()
            coin.position = CGPoint(x: 0, y: 110)
            coin.zPosition = 2   // sits in front of the ring
            container.addChild(coin)

        case .flowerHouse:
            // 4 coins floating above the roof garden. Original offsets
            // (80–100) put them at abs y 158–178, low enough that the
            // plane could collect them while parked at the floor. Bumped
            // ~25pt to clear the lower flyable boundary (abs y ≥ 183).
            let positions: [(CGFloat, CGFloat)] = [
                (-50, 110), (-15, 125), (20, 120), (55, 105)
            ]
            for (dx, dy) in positions {
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
    /// back into the unreachable floor zone.
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

        // Clamp plane vertically so it can't fly off-screen top/bottom.
        // Top margin keeps the 2x-scaled sprite (half-height ~45pt) fully
        // on-screen at the upper extreme; bottom margin keeps the plane
        // above the foreground buildings (tops cap at y≈78) with room to
        // spare — collectible placement keys off this same band.
        plane.position.y = min(planeMaxY, max(planeMinY, plane.position.y))
        plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12

        // Boost multiplier scales every horizontal scroll source so the world
        // accelerates uniformly. landmarkLayer.speed propagates to running
        // SKActions on its descendants (per SKNode docs), so already-spawned
        // landmarks accelerate along with newly emitted ones.
        let boost = currentBoostMultiplier(at: currentTime)
        landmarkLayer.speed = boost
        plane.setBoostIntensity((boost - 1) / (boostPeakMultiplier - 1))

        // Parallax drift (landmarks move themselves via SKAction).
        // Far layer scrolls slowly for depth; near layer scrolls fast so the
        // foreground blurs past the plane.
        scrollLoop(
            farBackground,
            speed: 30 * boost,
            totalWidth: farTileWidth * 4,
            wrapMargin: farTileWidth / 2,
            delta: delta
        )
        scrollLoop(
            nearForeground,
            speed: 180 * boost,
            totalWidth: nearTileWidth * 2,
            wrapMargin: 120,
            delta: delta
        )

        spawnLandmarkIfDue(currentTime: currentTime)
    }

    /// Returns the current speed multiplier — 1.0 when no boost is active,
    /// `boostPeakMultiplier` during the hold window, then linearly tapering
    /// back to 1.0 over `boostTaperDuration`.
    private func currentBoostMultiplier(at currentTime: TimeInterval) -> CGFloat {
        let timeLeft = boostActiveUntil - currentTime
        guard timeLeft > 0 else { return 1.0 }
        if timeLeft >= boostTaperDuration { return boostPeakMultiplier }
        let t = CGFloat(timeLeft / boostTaperDuration)
        return 1.0 + (boostPeakMultiplier - 1.0) * t
    }

    /// Triggers (or refreshes) the speed boost. A second ring during an
    /// active boost extends the deadline rather than stacking, so peak
    /// speed is bounded.
    private func triggerSpeedBoost() {
        boostActiveUntil = lastUpdateTime + boostHoldDuration + boostTaperDuration
    }

    /// Scrolls every child left by `speed * delta`. When a child drops past
    /// `-wrapMargin`, it jumps `totalWidth` to the right. Using the same
    /// `totalWidth` for every child preserves relative spacing across wraps,
    /// which keeps the far layer's mirror-tile seam pattern pixel-perfect and
    /// keeps the near layer's pseudo-random building spacing stable.
    private func scrollLoop(_ layer: SKNode,
                            speed: CGFloat,
                            totalWidth: CGFloat,
                            wrapMargin: CGFloat,
                            delta: TimeInterval) {
        guard totalWidth > 0 else { return }
        layer.children.forEach { node in
            node.position.x -= speed * CGFloat(delta)
            if node.position.x < -wrapMargin {
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
