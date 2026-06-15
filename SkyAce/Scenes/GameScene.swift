import SpriteKit

/// The main gameplay scene. Runs one `Challenge` to completion.
///
/// World layout:
///   - zPosition -100..-50 — parallax backgrounds (sky, distant/foreground clouds).
///   - zPosition    0..10  — gameplay nodes (plane, coins, obstacles).
///   - The HUD lives on `cameraNode` (zPosition 100+) so it doesn't scroll.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Inputs
    private let challenge: Challenge
    private let state: GameState

    // MARK: - World nodes
    private let worldNode   = SKNode()          // gameplay layer
    private let hudNode     = SKNode()          // camera-attached HUD
    private let cameraRoot  = SKCameraNode()

    // Parallax layers
    private var bgGradient: SKSpriteNode!
    private var distantCloudLayer  = SKNode()
    private var nearCloudLayer     = SKNode()

    // Off-screen physics walls so the plane can't fly past the top/bottom of
    // the scene. Tracked so iPad rotation (SKY-55) can reposition them onto
    // the new screen edges without leaving stale colliders behind.
    private var topBoundary: SKNode?
    private var bottomBoundary: SKNode?

    // Gameplay
    private var plane: PlaneNode!

    // Spawn control
    private var lastObstacleSpawn: TimeInterval = 0
    private var lastCoinSpawn: TimeInterval = 0
    private var lastPatternSpawn: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var obstaclePatternIndex = 0
    /// The gap center Y of the most recently spawned obstacle pair. Coin
    /// lines in `obstacleCourse` mode align to this so collecting them
    /// doesn't force the plane into a pillar.
    private var lastObstacleGapY: CGFloat?

    // Finish line — scheduled once per run; tracked so we can stop spawning
    // hazards/coins on its approach and route the cross through didBegin.
    private var finishLineNode: FinishLineNode?
    private var finishLineSpawnTime: TimeInterval = .infinity

    // Input
    private var isTouchingScreen = false

    // HUD
    private var coinLabel: CoinAmountNode!
    private var coinPillBG: SKShapeNode!
    private var missionTitleLabel: SKLabelNode!
    private var progressBarFill: SKShapeNode!
    private var progressBarBG:   SKShapeNode!
    private var progressLabel:   SKLabelNode!
    private var pauseButton:     SKNode!
    private var armorBadge: SKLabelNode?

    /// Top safe-area inset (Dynamic Island / notch) pushed in by
    /// `GameViewController` once layout settles; keeps the centered pause
    /// button clear of the island. See `pauseButtonY()`.
    private var topSafeInset: CGFloat = 0

    // Pause overlay state
    private var pauseOverlay: SKNode?

    // End-of-run flag so we can ignore contacts after a result.
    private var runHasFinished = false

    /// SKY-75: seconds of `timeRemaining` at which the time-trial timer
    /// warning loop kicks in. 10s leaves a clear "last seconds" band on the
    /// 45s timeTrialDuration without feeling premature.
    private static let timerWarningThreshold: TimeInterval = 10
    /// Latched once the timer-warning loop has been started for this run so
    /// it isn't restarted every frame.
    private var timerWarningActive = false

    // MARK: - Init

    init(size: CGSize, challenge: Challenge) {
        self.challenge = challenge
        self.state = GameState(challenge: challenge)
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimaryContainer
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        physicsWorld.contactDelegate = self
        SkyHaptics.prepare()

        addChild(worldNode)
        setupCamera()
        buildParallaxBackground()
        buildBoundaries()
        buildPlane()
        buildHUD()
        buildStartHint()
        scheduleFinishLine()

        // SKY-75: engine ambience runs alongside the gameplay music. Played
        // from the AudioManager engine slot so it coexists with the music
        // track instead of replacing it.
        AudioManager.shared.playEngineLoop(
            SkyEngineLoop.filename(forPlaneID: ProgressManager.shared.selectedPlaneID)
        )
    }

    // Stop the engine loop on any scene exit (results, map, restart). The
    // dedicated engine player would otherwise keep looping under the next
    // scene's music until the player's next gameplay run replaced it.
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        AudioManager.shared.stopEngineLoop()
        AudioManager.shared.stopLoopingSFX()
    }

    // SKY-55: iPad rotation. Unlike menu scenes we can't rebuild from scratch
    // — the player's mid-flight state (coins collected, timer, armor, plane
    // position relative to the next obstacle) lives in `state` and on the
    // plane node. Relayout in place: re-anchor the camera, resize the
    // background gradient, reposition the boundary colliders onto the new
    // edges, rebuild the camera-attached HUD against the new corners, and
    // clamp the plane back to its target horizontal lane. In-flight obstacles
    // and coins keep their existing scroll actions and slide off naturally.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, worldNode.parent != nil else { return }

        cameraRoot.position = CGPoint(x: size.width / 2, y: size.height / 2)

        if let bg = bgGradient {
            bg.texture = SKGradientBackgroundNode.gradientTexture(
                size: size,
                top: SkyColors.skPrimary,
                bottom: SkyColors.skPrimaryContainer
            )
            bg.size = size
        }

        buildBoundaries()

        // The "Tap & hold to fly" hint is positioned at launch-time width and
        // self-removes after ~3s; drop it here so it doesn't linger off-center.
        children.filter { $0.name == "startHint" }.forEach { $0.removeFromParent() }

        // Rebuild HUD: every coin pill / mission card / pause button position
        // is keyed off scene size. The HUD lives inside cameraRoot so the
        // worldNode-attached gameplay state isn't touched.
        hudNode.removeAllChildren()
        armorBadge = nil
        buildHUD()

        // Pause overlay's dim sprite is sized to the old scene; rebuild it.
        if pauseOverlay != nil {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
            showPauseOverlay()
        }

        // The plane drifts back to its target lane on its own (see update()),
        // but we also clamp Y immediately so it can't end up outside the new
        // top/bottom boundaries.
        if plane != nil {
            plane.position.x = size.width * 0.25
            plane.position.y = max(40, min(size.height - 40, plane.position.y))
        }
    }

    // MARK: - Setup

    private func setupCamera() {
        cameraRoot.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraRoot)
        camera = cameraRoot

        cameraRoot.addChild(hudNode)
    }

    private func buildParallaxBackground() {
        let texture = SKGradientBackgroundNode.gradientTexture(
            size: size,
            top: SkyColors.skPrimary,
            bottom: SkyColors.skPrimaryContainer
        )
        bgGradient = SKSpriteNode(texture: texture, size: size)
        bgGradient.anchorPoint = .zero
        bgGradient.position = .zero
        bgGradient.zPosition = -100
        worldNode.addChild(bgGradient)

        distantCloudLayer.zPosition = -80
        worldNode.addChild(distantCloudLayer)
        nearCloudLayer.zPosition = -40
        worldNode.addChild(nearCloudLayer)

        for _ in 0..<8 {
            let cloud = MenuCloud()
            cloud.setScale(CGFloat.random(in: 0.6...0.9))
            cloud.alpha = 0.7
            cloud.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.5...size.height * 0.95)
            )
            distantCloudLayer.addChild(cloud)
        }

        for _ in 0..<5 {
            let cloud = MenuCloud()
            cloud.setScale(CGFloat.random(in: 0.9...1.2))
            cloud.alpha = 0.85
            cloud.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.2...size.height * 0.5)
            )
            nearCloudLayer.addChild(cloud)
        }
    }

    /// Invisible top/bottom walls so the plane can't fly off-screen. Replaces
    /// any existing walls so iPad rotation (SKY-55) can reposition them onto
    /// the new screen edges.
    private func buildBoundaries() {
        topBoundary?.removeFromParent()
        bottomBoundary?.removeFromParent()

        let top = SKNode()
        top.position = CGPoint(x: size.width / 2, y: size.height + 10)
        let topBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 20))
        topBody.isDynamic = false
        topBody.categoryBitMask = PhysicsCategory.boundary
        topBody.contactTestBitMask = PhysicsCategory.plane
        topBody.collisionBitMask = 0
        top.physicsBody = topBody
        worldNode.addChild(top)
        topBoundary = top

        let bottom = SKNode()
        bottom.position = CGPoint(x: size.width / 2, y: -10)
        let bottomBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 20))
        bottomBody.isDynamic = false
        bottomBody.categoryBitMask = PhysicsCategory.boundary
        bottomBody.contactTestBitMask = PhysicsCategory.plane
        bottomBody.collisionBitMask = 0
        bottom.physicsBody = bottomBody
        worldNode.addChild(bottom)
        bottomBoundary = bottom
    }

    private func buildPlane() {
        // Mission mode uses a 1.4x visual scale — lands the plane's rendered
        // height at ~26% of the easiest obstacle gap (240pt at L1). At the
        // narrowest late-game gap (112pt at L10) the visual fills ~56% of
        // the gap, but the unchanged 54x27 hitbox stays at ~24% of it so
        // collisions remain fair.
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 1.4)
        plane.position = CGPoint(x: size.width * 0.25, y: size.height / 2)
        plane.zPosition = 10
        worldNode.addChild(plane)
    }

    // MARK: - HUD

    private func buildHUD() {
        // Coin pill (top-left)
        let coinPillSize = CGSize(width: 110, height: 34)
        let pill = SKShapeNode(rectOf: coinPillSize, cornerRadius: 17)
        pill.fillColor = SkyColors.skTertiaryContainer
        pill.strokeColor = .clear
        pill.position = CGPoint(x: -size.width / 2 + coinPillSize.width / 2 + 14, y: size.height / 2 - 34)
        pill.zPosition = 100
        hudNode.addChild(pill)
        coinPillBG = pill

        coinLabel = CoinAmountNode(
            amount: "0",
            fontName: SkyFonts.headlineName,
            fontSize: 15,
            color: SkyColors.skOnTertiaryContainer
        )
        coinLabel.position = pill.position
        coinLabel.zPosition = 101
        hudNode.addChild(coinLabel)

        // Armor badge — only shown if the player has armor.
        if state.hitsAllowed > 0 {
            let armor = SKLabelNode(text: "🛡 \(state.hitsRemaining)")
            armor.fontName = SkyFonts.headlineName
            armor.fontSize = 14
            armor.fontColor = SkyColors.skOnPrimary
            armor.verticalAlignmentMode = .center
            armor.horizontalAlignmentMode = .center
            armor.position = CGPoint(x: pill.position.x + 90, y: pill.position.y)
            armor.zPosition = 101
            hudNode.addChild(armor)
            armorBadge = armor
        }

        // Mission info + progress bar (top-right)
        let missionCardSize = CGSize(width: 160, height: 54)
        let missionCard = SKShapeNode(rectOf: missionCardSize, cornerRadius: 18)
        missionCard.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.92)
        missionCard.strokeColor = .clear
        missionCard.position = CGPoint(x: size.width / 2 - missionCardSize.width / 2 - 14, y: size.height / 2 - 44)
        missionCard.zPosition = 100
        hudNode.addChild(missionCard)

        missionTitleLabel = SKLabelNode(text: challenge.name.uppercased())
        missionTitleLabel.fontName = SkyFonts.headlineName
        missionTitleLabel.fontSize = 11
        missionTitleLabel.fontColor = SkyColors.skOnSurface
        missionTitleLabel.horizontalAlignmentMode = .center
        missionTitleLabel.verticalAlignmentMode = .center
        missionTitleLabel.position = CGPoint(x: missionCard.position.x, y: missionCard.position.y + 12)
        missionTitleLabel.zPosition = 101
        hudNode.addChild(missionTitleLabel)

        let barBG = SKShapeNode(rectOf: CGSize(width: 130, height: 8), cornerRadius: 4)
        barBG.fillColor = SkyColors.skSurfaceContainer
        barBG.strokeColor = .clear
        barBG.position = CGPoint(x: missionCard.position.x, y: missionCard.position.y - 4)
        barBG.zPosition = 101
        hudNode.addChild(barBG)
        progressBarBG = barBG

        let fill = SKShapeNode(rectOf: CGSize(width: 2, height: 8), cornerRadius: 4)
        fill.fillColor = SkyColors.skPrimary
        fill.strokeColor = .clear
        fill.position = CGPoint(x: barBG.position.x - 65, y: barBG.position.y)
        fill.zPosition = 102
        hudNode.addChild(fill)
        progressBarFill = fill

        progressLabel = SKLabelNode(text: state.progressLabel)
        progressLabel.fontName = SkyFonts.bodyMediumName
        progressLabel.fontSize = 11
        progressLabel.fontColor = SkyColors.skOnSurfaceVariant
        progressLabel.horizontalAlignmentMode = .center
        progressLabel.verticalAlignmentMode = .center
        progressLabel.position = CGPoint(x: missionCard.position.x, y: missionCard.position.y - 18)
        progressLabel.zPosition = 101
        hudNode.addChild(progressLabel)

        // Pause button (top center). It sits below the top safe-area inset so
        // it clears the Dynamic Island / notch on iPhone; on iPad (no island)
        // the inset is small and it stays near the top edge.
        let pauseCenter = CGPoint(x: 0, y: pauseButtonY())
        let pauseBG = SKShapeNode(rectOf: CGSize(width: 46, height: 34), cornerRadius: 17)
        pauseBG.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.92)
        pauseBG.strokeColor = .clear
        pauseBG.position = pauseCenter
        pauseBG.zPosition = 100
        pauseBG.name = "pauseButton"
        hudNode.addChild(pauseBG)

        let pauseLabel = SKLabelNode(text: "II")
        pauseLabel.fontName = SkyFonts.headlineName
        pauseLabel.fontSize = 14
        pauseLabel.fontColor = SkyColors.skOnSurface
        pauseLabel.verticalAlignmentMode = .center
        pauseLabel.horizontalAlignmentMode = .center
        pauseLabel.position = pauseCenter
        pauseLabel.zPosition = 101
        pauseLabel.name = "pauseButton"
        hudNode.addChild(pauseLabel)
        self.pauseButton = pauseBG
    }

    /// Vertical center for the pause button, dropped below the top safe-area
    /// inset so the Dynamic Island / notch never covers it. The inset comes
    /// from the live view, or from the value `GameViewController` pushes once
    /// layout settles (whichever is larger), since `safeAreaInsets` can still
    /// be zero on the first HUD build.
    private func pauseButtonY() -> CGFloat {
        let safeTop = max(topSafeInset, view?.safeAreaInsets.top ?? 0)
        return size.height / 2 - safeTop - 17 - 8
    }

    /// Called by `GameViewController.viewSafeAreaInsetsDidChange` so the pause
    /// button settles below the Dynamic Island even when the first HUD build
    /// happened before the safe-area insets were known.
    func applyTopSafeInset(_ inset: CGFloat) {
        guard inset != topSafeInset else { return }
        topSafeInset = inset
        let y = pauseButtonY()
        hudNode.children
            .filter { $0.name == "pauseButton" }
            .forEach { $0.position.y = y }
    }

    private func buildStartHint() {
        let hint = SKLabelNode(text: "Tap & hold to fly")
        hint.fontName = SkyFonts.headlineName
        hint.fontSize = 18
        hint.fontColor = SkyColors.skOnPrimary
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.35)
        hint.zPosition = 50
        hint.name = "startHint"
        addChild(hint)
        hint.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.4),
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval
        if lastUpdateTime == 0 { delta = 0 } else { delta = currentTime - lastUpdateTime }
        lastUpdateTime = currentTime

        guard !runHasFinished, !state.isPaused else { return }

        state.advanceTime(delta)

        if isTouchingScreen {
            plane.climb()
        }
        plane.update()

        // Keep plane horizontally fixed — world moves past it.
        plane.position.x += (size.width * 0.25 - plane.position.x) * 0.12

        // Parallax drift.
        distantCloudLayer.children.forEach { cloud in
            cloud.position.x -= 0.3 * CGFloat(plane.horizontalSpeed * challenge.speedMultiplier) * CGFloat(delta) * 0.4
            if cloud.position.x < -80 { cloud.position.x = size.width + 40 }
        }
        nearCloudLayer.children.forEach { cloud in
            cloud.position.x -= CGFloat(plane.horizontalSpeed * challenge.speedMultiplier) * CGFloat(delta) * 0.7
            if cloud.position.x < -80 { cloud.position.x = size.width + 40 }
        }

        // Spawn logic per challenge type.
        spawnTick(currentTime: currentTime)

        // Finish-line scheduler. Fires once per run, when the precomputed
        // approach moment arrives.
        if finishLineNode == nil && state.elapsedTime >= finishLineSpawnTime {
            spawnFinishLine()
        }

        // Cull off-screen gameplay nodes.
        cullOffscreenChildren()

        // SKY-75: start the timer-warning loop the first time a timeTrial
        // run drops into the warning band. Stop it the moment the run ends
        // is handled in the win/fail sequences so the cue doesn't bleed
        // into the results scene.
        updateTimerWarning()

        // End conditions.
        if state.isGameOver { finishRun() }
        else { updateHUD() }
    }

    /// Starts the timer-warning loop the first frame a time-trial run drops
    /// into the warning band. Idempotent thereafter — the loop is stopped
    /// from the win/fail sequences and on scene exit.
    private func updateTimerWarning() {
        guard challenge.type == .timeTrial, !timerWarningActive else { return }
        if state.timeRemaining <= GameScene.timerWarningThreshold && state.timeRemaining > 0 {
            timerWarningActive = true
            AudioManager.shared.playLoopingSFX(SkySFX.timerWarning, fileExtension: "caf", volume: 0.55)
        }
    }

    // MARK: - Spawning

    /// Multiplier on `Challenge.spawnInterval` for coin-line cadence in
    /// `obstacleCourse` levels. Lowered from 1.5 (post-SKY-60) to 1.15 — a
    /// ~30% density bump so a player who routes around a near-pillar coin
    /// still leaves the run feeling rewarded (SKY-84).
    static let obstacleCourseCoinIntervalMultiplier: Double = 1.15

    /// Seconds between coin-pattern spawns in `timeTrial` levels. Lowered
    /// from 0.8s (post-SKY-60) to 0.62s — a ~28% density bump matching the
    /// obstacleCourse adjustment above (SKY-84).
    static let timeTrialCoinInterval: TimeInterval = 0.62

    /// Seconds between coin-pattern spawns in `coinChain` levels (Coin
    /// Scatter, Coin Tornado). Unchanged at 1.4s — these levels are already
    /// dense by design and were tuned separately per SKY-84 guidance.
    static let coinChainPatternInterval: TimeInterval = 1.4

    private func spawnTick(currentTime: TimeInterval) {
        // Stop populating the run once the finish gate is on its way — gives
        // the player a clean approach without a hazard right at the line.
        guard finishLineNode == nil else { return }

        switch challenge.type {
        case .obstacleCourse:
            if currentTime - lastObstacleSpawn >= challenge.spawnInterval {
                spawnObstaclePair()
                lastObstacleSpawn = currentTime
            }
            // Coin clusters in the gap, paced to the obstacle cadence.
            if currentTime - lastCoinSpawn >= challenge.spawnInterval * GameScene.obstacleCourseCoinIntervalMultiplier {
                spawnCoinLine()
                lastCoinSpawn = currentTime
            }

        case .timeTrial:
            // Dense coin spawns, no pillars.
            if currentTime - lastCoinSpawn >= GameScene.timeTrialCoinInterval {
                let pattern = nextCoinPattern()
                spawnCoinPattern(pattern)
                lastCoinSpawn = currentTime
            }

        case .coinChain:
            // Coin patterns frequent, obstacles occasional. Obstacle spawns
            // first so the just-placed pillars are visible to the coin
            // pattern's clearance check (SKY-60).
            if currentTime - lastObstacleSpawn >= challenge.spawnInterval * 1.8 {
                spawnObstaclePair()
                lastObstacleSpawn = currentTime
            }
            if currentTime - lastPatternSpawn >= GameScene.coinChainPatternInterval {
                let pattern = nextCoinPattern()
                spawnCoinPattern(pattern)
                lastPatternSpawn = currentTime
            }
        }
    }

    private func spawnObstaclePair() {
        let obstacle = ObstacleNode(sceneSize: size, gap: challenge.obstacleGap, theme: challenge.theme)
        obstacle.position = CGPoint(x: size.width + 80, y: 0)
        obstacle.zPosition = 1
        worldNode.addChild(obstacle)
        lastObstacleGapY = obstacle.gapCenterY

        // SKY-60: a coin spawned earlier may have scrolled into this new
        // obstacle's X column with a Y outside the new gap — at high levels
        // (short spawnInterval) the cycles can put the next obstacle right
        // on top of the previous coin line. Cull any embedded coin so we
        // never present an uncollectible collectible.
        removeCoinsEmbeddedIn(obstacle)

        let speed = plane.horizontalSpeed * challenge.speedMultiplier
        let distance = size.width + 200
        let duration = TimeInterval(distance / speed)
        obstacle.run(SKAction.sequence([
            SKAction.moveBy(x: -distance, y: 0, duration: duration),
            SKAction.removeFromParent()
        ]))
    }

    /// Minimum clearance, in points, between a coin's center and the nearest
    /// obstacle pillar edge. Sized so the plane (54pt-wide hitbox) plus the
    /// coin's 13pt radius plus a small margin all fit between the coin and
    /// the pillar — a player flying straight at a coin should never have to
    /// clip the pillar to collect it. Used by every coin spawn-time and
    /// post-spawn clearance check (SKY-84, supersedes the 20pt buffer from
    /// SKY-60).
    static let coinClearanceBuffer: CGFloat = 55

    /// Removes any `CoinNode` whose current world position falls inside the
    /// pillar (non-gap) area of `obstacle`, with the same buffer the coin
    /// spawn-time clearance check uses. Counterpart to `isInsideObstacle`
    /// that runs from the obstacle side (SKY-60).
    private func removeCoinsEmbeddedIn(_ obstacle: ObstacleNode, buffer: CGFloat = GameScene.coinClearanceBuffer) {
        for case let coin as CoinNode in worldNode.children
            where isInsidePillar(coin.position, of: obstacle, buffer: buffer) {
            coin.removeFromParent()
        }
    }

    private func spawnCoinLine() {
        // Align coin-chain Y to the last pillar's gap when available so
        // collecting coins doesn't steer the plane into a pillar. Start the
        // chain clearly past the pillar's X column (pillar is 60 wide at
        // width+80, so its right edge sits around width+110).
        let gapWander: CGFloat = 24
        let centerY: CGFloat
        if let gap = lastObstacleGapY {
            centerY = gap + CGFloat.random(in: -gapWander...gapWander)
        } else {
            centerY = CGFloat.random(in: size.height * 0.25...size.height * 0.75)
        }
        let startX = size.width + 160  // was +40 — placed coins inside the pillar column

        let speed = plane.horizontalSpeed * challenge.speedMultiplier
        let distance = size.width + 320
        let duration = TimeInterval(distance / speed)

        for i in 0..<4 {
            let position = CGPoint(x: startX + CGFloat(i) * 40, y: centerY)
            // Defense in depth (SKY-60): the gap-aligned Y plus wander can
            // still graze a pillar edge on tight L10 gates. Skip any coin
            // that would land embedded in a wall rather than spawning an
            // uncollectible collectible.
            if isInsideObstacle(position) { continue }
            let coin = CoinNode()
            coin.position = position
            coin.zPosition = 2
            worldNode.addChild(coin)
            state.registerCoinSpawned()
            coin.run(SKAction.sequence([
                SKAction.moveBy(x: -distance, y: 0, duration: duration),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Finish line

    /// Distance offscreen-right where the gate first appears, before scrolling
    /// into view. Acts as the "lead distance" the player effectively gets
    /// while the gate is still off-screen.
    private static let finishLineSpawnOffset: CGFloat = 80

    /// Computes when in the run the finish line should spawn so its center
    /// reaches the plane at exactly `challenge.levelDuration`. Lead distance
    /// scales with the plane's effective horizontal speed: at base speed
    /// (180pt/s) the gate is visible for ~1.6s before the cross; at the
    /// fastest level (×1.6 → ~288pt/s) it's still ~1.0s — enough warning to
    /// hold altitude through a full-height gate.
    private func scheduleFinishLine() {
        let speed = plane.horizontalSpeed * challenge.speedMultiplier
        guard speed > 0 else { return }
        let spawnX = size.width + GameScene.finishLineSpawnOffset
        let crossTravel = spawnX - size.width * 0.25
        let crossTime = TimeInterval(crossTravel / speed)
        finishLineSpawnTime = max(0, challenge.levelDuration - crossTime)
    }

    private func spawnFinishLine() {
        let finish = FinishLineNode(sceneHeight: size.height)
        finish.position = CGPoint(x: size.width + GameScene.finishLineSpawnOffset, y: size.height / 2)
        finish.zPosition = 4
        worldNode.addChild(finish)
        finishLineNode = finish

        // Slide all the way off the left edge then remove. Same speed as
        // obstacles/coins so the world reads as a continuous course.
        let speed = plane.horizontalSpeed * challenge.speedMultiplier
        let totalDistance = size.width + GameScene.finishLineSpawnOffset + 160
        let duration = TimeInterval(totalDistance / max(speed, 1))
        finish.run(SKAction.sequence([
            SKAction.moveBy(x: -totalDistance, y: 0, duration: duration),
            SKAction.removeFromParent()
        ]))
    }

    private func handleFinishLineCross() {
        guard !runHasFinished, !state.isGameOver else { return }

        // Crossing the finish line is the win condition for every non-timed
        // mission type. Coins are scoring only — they affect star rating
        // and currency, never completion.
        finishLineNode?.run(AudioManager.shared.sfxAction(SkySFX.ringPass))
        state.finish(won: true)
        finishRun()
    }

    // MARK: - Coin patterns (time trial + coin chain)

    private enum CoinPattern { case line, arcUp, arcDown, zigzag }

    private func nextCoinPattern() -> CoinPattern {
        let patterns: [CoinPattern] = [.line, .arcUp, .arcDown, .zigzag]
        let pattern = patterns[obstaclePatternIndex % patterns.count]
        obstaclePatternIndex += 1
        return pattern
    }

    private func spawnCoinPattern(_ pattern: CoinPattern) {
        let speed = plane.horizontalSpeed * challenge.speedMultiplier
        let distance = size.width + 260
        let duration = TimeInterval(distance / speed)
        let startX = size.width + 40
        let offsets = patternOffsets(pattern)

        // Pick a centerY that keeps every coin in the pattern clear of any
        // active obstacle pillar (SKY-60). The default random Y has no
        // obstacle awareness, and in `.coinChain` mode an obstacle pair
        // can spawn on the same tick at width+80 — in the middle of the
        // pattern's X span. Try several candidates before falling back to
        // per-coin culling so a tight pattern doesn't disappear entirely.
        let centerY = pickPatternCenterY(startX: startX, offsets: offsets)

        for offset in offsets {
            let position = CGPoint(x: startX + offset.x, y: centerY + offset.y)
            if isInsideObstacle(position) { continue }
            let coin = CoinNode()
            coin.position = position
            coin.zPosition = 2
            worldNode.addChild(coin)
            state.registerCoinSpawned()
            coin.run(SKAction.sequence([
                SKAction.moveBy(x: -distance, y: 0, duration: duration),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func patternOffsets(_ pattern: CoinPattern) -> [CGPoint] {
        switch pattern {
        case .line:
            return (0..<5).map { CGPoint(x: CGFloat($0) * 40, y: 0) }
        case .arcUp:
            return (0..<5).map { i in
                let t = CGFloat(i) / 4.0
                return CGPoint(x: CGFloat(i) * 42, y: sin(t * .pi) * 60)
            }
        case .arcDown:
            return (0..<5).map { i in
                let t = CGFloat(i) / 4.0
                return CGPoint(x: CGFloat(i) * 42, y: -sin(t * .pi) * 60)
            }
        case .zigzag:
            return (0..<6).map { i in
                CGPoint(x: CGFloat(i) * 36, y: (i % 2 == 0) ? -40 : 40)
            }
        }
    }

    /// Samples a few random Y values within the pattern's normal vertical
    /// band and returns the first one for which every coin in the pattern
    /// lands in clear space. Falls back to the last sampled Y so the spawn
    /// loop's per-coin clearance check can drop only the embedded coins.
    private func pickPatternCenterY(startX: CGFloat, offsets: [CGPoint]) -> CGFloat {
        var lastCandidate: CGFloat = size.height / 2
        for _ in 0..<6 {
            let candidate = CGFloat.random(in: size.height * 0.3...size.height * 0.7)
            lastCandidate = candidate
            let allClear = offsets.allSatisfy { offset in
                !isInsideObstacle(CGPoint(x: startX + offset.x, y: candidate + offset.y))
            }
            if allClear { return candidate }
        }
        return lastCandidate
    }

    /// Returns true if `worldPosition` sits inside (or within `buffer`pt of)
    /// the pillar area of any active `ObstacleNode` in the world. The gap
    /// between top/bottom pillars counts as clear space. Used by coin
    /// spawners so a coin never appears embedded inside a wall the player
    /// can't reach without crashing (SKY-60).
    private func isInsideObstacle(_ worldPosition: CGPoint, buffer: CGFloat = GameScene.coinClearanceBuffer) -> Bool {
        for case let obstacle as ObstacleNode in worldNode.children {
            if isInsidePillar(worldPosition, of: obstacle, buffer: buffer) { return true }
        }
        return false
    }

    /// True when `position` falls inside (or within `buffer`pt of) a pillar
    /// of `obstacle` — i.e. outside the navigable gap. Pillar width is fixed
    /// at 60pt in `ObstacleNode`, so we use 30pt as the half-width here.
    private func isInsidePillar(_ position: CGPoint, of obstacle: ObstacleNode, buffer: CGFloat) -> Bool {
        let pillarHalfWidth: CGFloat = 30
        let dx = position.x - obstacle.position.x
        guard abs(dx) <= pillarHalfWidth + buffer else { return false }
        let dy = position.y - obstacle.gapCenterY
        return abs(dy) > obstacle.gap / 2 - buffer
    }

    private func cullOffscreenChildren() {
        worldNode.children.forEach { node in
            if node is ObstacleNode || node is CoinNode {
                if node.position.x < -120 {
                    node.removeFromParent()
                }
            }
        }
    }

    // MARK: - HUD updates

    private func updateHUD() {
        coinLabel.setAmount("\(state.coinsCollected)")

        let totalWidth: CGFloat = 130
        let fraction = state.progress
        let width = max(2, totalWidth * fraction)
        progressBarFill.xScale = width / 2   // original shape was width 2
        // Keep the fill anchored to the left edge of the bar.
        let leftEdge = progressBarBG.position.x - totalWidth / 2
        progressBarFill.position.x = leftEdge + width / 2

        progressLabel.text = state.progressLabel
        armorBadge?.text = "🛡 \(state.hitsRemaining)"
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        guard !runHasFinished else { return }
        let (planeBody, otherBody): (SKPhysicsBody, SKPhysicsBody) = {
            if contact.bodyA.categoryBitMask == PhysicsCategory.plane { return (contact.bodyA, contact.bodyB) }
            return (contact.bodyB, contact.bodyA)
        }()
        guard planeBody.categoryBitMask == PhysicsCategory.plane else { return }

        switch otherBody.categoryBitMask {
        case PhysicsCategory.coin:
            if let coin = otherBody.node as? CoinNode {
                coin.collect()
                state.collectCoin()
                ProgressManager.shared.addCoins(1)
                coin.run(AudioManager.shared.sfxAction(SkySFX.coinCollect))
                SkyHaptics.collect()
                flashCoinPill()
            }
        case PhysicsCategory.obstacle:
            handleHit(node: otherBody.node)
        case PhysicsCategory.boundary:
            handleBoundaryCrash()
        case PhysicsCategory.finish:
            handleFinishLineCross()
        default:
            break
        }
    }

    private func handleHit(node: SKNode?) {
        plane.playHitFlash()
        plane.run(AudioManager.shared.sfxAction(SkySFX.hit))
        SkyHaptics.hit()
        let dead = state.registerHit()
        if dead {
            triggerFailSequence()
        } else {
            // Armor absorbed it — tiny knock-back + brief invuln would be nice,
            // but spec keeps this simple.
            cameraRoot.run(SKAction.sequence([
                SKAction.moveBy(x: 6, y: -4, duration: 0.05),
                SKAction.moveBy(x: -6, y: 4, duration: 0.08)
            ]))
        }
    }

    // Boundary contacts represent flying off the top or falling out of the
    // sky — armor never saves you from that, so this skips registerHit and
    // ends the run directly (SKY-72).
    private func handleBoundaryCrash() {
        plane.playHitFlash()
        plane.run(AudioManager.shared.sfxAction(SkySFX.hit))
        SkyHaptics.hit()
        state.finish(won: false)
        triggerFailSequence()
    }

    private func flashCoinPill() {
        coinPillBG.run(SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.08),
            SKAction.scale(to: 1.0, duration: 0.12)
        ]))
    }

    // MARK: - End-of-run

    private func triggerFailSequence() {
        guard !runHasFinished else { return }
        runHasFinished = true
        SkyHaptics.fail()

        // SKY-75: cut the engine and timer-warning loop the moment the run
        // ends so the fail SFX + plane-crash sequence reads cleanly.
        AudioManager.shared.fadeOutEngineLoop()
        AudioManager.shared.stopLoopingSFX()

        // Red vignette flash.
        let vignette = SKSpriteNode(color: UIColor.systemRed.withAlphaComponent(0.0), size: size)
        vignette.anchorPoint = .zero
        vignette.zPosition = 500
        hudNode.addChild(vignette)
        vignette.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        vignette.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.15),
            SKAction.fadeAlpha(to: 0.0, duration: 0.35)
        ]))

        run(AudioManager.shared.sfxAction(SkySFX.fail))
        plane.playCrash { [weak self] in
            guard let self = self else { return }
            self.routeToResults()
        }
    }

    private func finishRun() {
        guard !runHasFinished else { return }
        runHasFinished = true

        if state.didWin {
            triggerWinSequence()
        } else {
            triggerFailSequence()
        }
    }

    private func triggerWinSequence() {
        SkyHaptics.win()

        // SKY-75: cut the engine and timer-warning loop before the win
        // fanfare so the celebratory SFX isn't competing with ambience.
        AudioManager.shared.fadeOutEngineLoop()
        AudioManager.shared.stopLoopingSFX()

        // Coin burst.
        for _ in 0..<16 {
            let coin = CoinNode()
            coin.position = plane.position
            coin.zPosition = 20
            worldNode.addChild(coin)
            let dx = CGFloat.random(in: -180...180)
            let dy = CGFloat.random(in: 100...260)
            coin.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.5),
                    SKAction.fadeOut(withDuration: 0.5)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // White flash.
        let flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        flash.alpha = 0
        flash.zPosition = 600
        hudNode.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.8, duration: 0.12),
            SKAction.fadeAlpha(to: 0.0, duration: 0.25)
        ]))
        run(AudioManager.shared.sfxAction(SkySFX.win))

        let wait = SKAction.wait(forDuration: 0.6)
        run(wait) { [weak self] in self?.routeToResults() }
    }

    private func routeToResults() {
        SkyNavigator.shared.showResults(
            challenge: challenge,
            coinsCollected: state.coinsCollected,
            coinsAvailable: state.totalCoinsSpawned,
            timeRemaining: state.levelTimeRemaining,
            didWin: state.didWin
        )
    }

    // MARK: - Touch / pause

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // HUD pause button (HUD is in camera coords).
        let hudLocation = touch.location(in: hudNode)
        if let tapped = nodes(at: location).first(where: { $0.name == "pauseButton" }) ?? hudNode.nodes(at: hudLocation).first(where: { $0.name == "pauseButton" }) {
            _ = tapped
            togglePause()
            return
        }

        // Pause overlay buttons
        if let overlay = pauseOverlay {
            let p = touch.location(in: overlay)
            for node in overlay.nodes(at: p) {
                if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                    button.handleTap()
                    return
                }
                if node.name == "pauseQuit" {
                    AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                    SkyNavigator.shared.showMap()
                    return
                }
            }
            return
        }

        isTouchingScreen = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchingScreen = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchingScreen = false
    }

    // MARK: - Pause

    private func togglePause() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        if state.isPaused { resumeGame() } else { pauseGame() }
    }

    private func pauseGame() {
        state.setPaused(true)
        // Suspend the physics simulation itself. `worldNode.isPaused` only
        // freezes SKActions in that subtree — the scene's physicsWorld keeps
        // integrating gravity/momentum, so without this the plane keeps
        // falling and crashes while "paused". Setting speed to 0 halts
        // simulation while preserving each body's velocity, so the plane
        // holds its exact position and resumes with no velocity spike.
        physicsWorld.speed = 0
        worldNode.isPaused = true
        showPauseOverlay()
    }

    private func resumeGame() {
        state.setPaused(false)
        physicsWorld.speed = 1
        worldNode.isPaused = false
        pauseOverlay?.removeFromParent()
        pauseOverlay = nil
        lastUpdateTime = 0
    }

    private func showPauseOverlay() {
        let overlay = SKNode()
        overlay.zPosition = 1000
        overlay.position = .zero

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.55), size: size)
        dim.anchorPoint = .zero
        dim.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        overlay.addChild(dim)

        let title = SKLabelNode(text: "PAUSED")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 44
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: 0, y: 60)
        overlay.addChild(title)

        let resume = SkyPillButton(title: "RESUME", style: .primary, size: CGSize(width: 220, height: 52)) { [weak self] in
            self?.resumeGame()
        }
        resume.position = CGPoint(x: 0, y: -10)
        overlay.addChild(resume)

        let restart = SkyPillButton(title: "RESTART", style: .surface, size: CGSize(width: 220, height: 52)) { [weak self] in
            guard let self = self else { return }
            SkyNavigator.shared.showGame(challenge: self.challenge)
        }
        restart.position = CGPoint(x: 0, y: -72)
        overlay.addChild(restart)

        let quit = SKLabelNode(text: "QUIT TO MAP")
        quit.fontName = SkyFonts.bodyMediumName
        quit.fontSize = 13
        quit.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
        quit.position = CGPoint(x: 0, y: -130)
        quit.name = "pauseQuit"
        overlay.addChild(quit)

        cameraRoot.addChild(overlay)
        pauseOverlay = overlay
    }
}
