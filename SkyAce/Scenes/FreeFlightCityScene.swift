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

    // Stamps
    private var collectedStamps: Set<Landmark> = []
    private var stampCardHUD: StampCardHUD!

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
        physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
        physicsWorld.contactDelegate = self
        topSafeInset = view.safeAreaInsets.top
        SkyHaptics.prepare()

        addChild(worldNode)
        buildSkyFill()
        buildSkyTopBlend()
        buildFarCityBackground()
        buildNearForeground()
        buildBirds()
        buildLandmarkLayer()
        buildPlane()
        buildTopBar()
    }

    // MARK: - Background layers

    private func buildSkyFill() {
        // Full-screen sky gradient anchored behind the painted city layer.
        // The top colour matches the top pixel of the cityscape PNG so the
        // seam between painted sky and gradient sky is imperceptible.
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: size,
            top: UIColor(hex: 0xE8F2FF),
            bottom: UIColor(hex: 0xCDE5FF)
        )
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -110
        worldNode.addChild(bg)
    }

    /// Soft blend along the top edge of the scene. The SKView's UIKit
    /// background is `SkyColors.surface` (0xF2F7FF) — a touch lighter than
    /// the sky gradient's top colour (0xE8F2FF) — so any sliver of the
    /// view that ends up visible above the scene reads as a hard step.
    /// A short vertical gradient overlay fades the sky up to the surface
    /// colour so the join is imperceptible regardless of device chrome.
    private func buildSkyTopBlend() {
        // ~12% of scene height, clamped so the band stays a soft seam rather
        // than visibly compressing the sky on small or very tall devices.
        let blendHeight = min(max(size.height * 0.12, 80), 160)
        let blendSize = CGSize(width: size.width, height: blendHeight)
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: blendSize,
            top: SkyColors.skSurface,
            bottom: UIColor(hex: 0xE8F2FF)
        )
        let blend = SKSpriteNode(texture: tex, size: blendSize)
        blend.anchorPoint = CGPoint(x: 0, y: 1)
        blend.position = CGPoint(x: 0, y: size.height)
        blend.zPosition = -109
        worldNode.addChild(blend)
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
        // edge to the grass strip (y = 14) makes the *visible* building
        // float ~18% above the grass. Shifting down by that padding lands
        // the subject's visual base firmly on the grass.
        let groundBaseline: CGFloat = 14
        let shadowPadding = landmark.displaySize.height * 0.18
        return groundBaseline + landmark.displaySize.height / 2 - shadowPadding
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
                triggerSpeedBoost()
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
