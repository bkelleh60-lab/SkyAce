import SpriteKit

/// Post-run scene. Win/fail-aware: stars + confetti + coin count-up on a win,
/// "MISSION FAILED" copy + try-again on a fail.
final class ResultsScene: SKScene {

    private let challenge: Challenge
    private let coinsCollected: Int
    private let coinsAvailable: Int
    private let timeRemaining: TimeInterval
    private let didWin: Bool
    private let starsEarned: Int

    // MARK: - Init
    init(size: CGSize, challenge: Challenge, coinsCollected: Int, coinsAvailable: Int, timeRemaining: TimeInterval, didWin: Bool) {
        self.challenge = challenge
        self.coinsCollected = coinsCollected
        self.coinsAvailable = coinsAvailable
        self.timeRemaining = timeRemaining
        self.didWin = didWin
        self.starsEarned = StarRating.stars(
            completed: didWin,
            coinsCollected: coinsCollected,
            totalCoins: coinsAvailable,
            timeRemaining: timeRemaining
        )
        super.init(size: size)

        // Commit run results to progress/coins on the way in.
        if didWin {
            ProgressManager.shared.markLevelCompleted(challenge.id, stars: starsEarned)
            ProgressManager.shared.addCoins(challenge.reward)
        }
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = didWin ? SkyColors.skPrimary : SkyColors.skOnSurface
        layoutScene()
    }

    // SKY-55: see MenuScene.didChangeSize. Re-runs the win/fail layout against
    // the new dimensions; the coin count-up animation restarts but the run
    // results are already committed to ProgressManager in init() so no state is
    // lost.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    private func layoutScene() {
        buildBackground()
        if didWin { buildWin() } else { buildFail() }
    }

    // MARK: - Background

    private func buildBackground() {
        let top: SKColor    = didWin ? SkyColors.skPrimary           : SkyColors.skOnSurface
        let bottom: SKColor = didWin ? SkyColors.skPrimaryContainer  : SkyColors.skOnSurface.withAlphaComponent(0.85)
        let tex = SKGradientBackgroundNode.gradientTexture(size: size, top: top, bottom: bottom)
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        addChild(bg)
    }

    // MARK: - Win UI

    /// Lays out the win screen — confetti, stars, Rio's congratulations, coin
    /// count-up, and the NEXT LEVEL / UPGRADE SHOP / BACK TO MAP actions (the
    /// first and last route through the chapter transition after an L5 win).
    ///
    /// The stars, Rio portrait, and her message share a vertically-centered
    /// stack (SKY-122) so the added content holds its spacing on both a short
    /// iPhone SE and a tall 15 Pro. Level 10 uses this same standard screen —
    /// its dedicated celebration is a follow-up ticket.
    private func buildWin() {
        buildConfetti()

        let title = SKLabelNode(text: "LEVEL COMPLETE!")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 34
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.82)
        addChild(title)

        let subtitle = SKLabelNode(text: challenge.name)
        subtitle.fontName = SkyFonts.bodyMediumName
        subtitle.fontSize = 14
        subtitle.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.8)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.82 - 30)
        addChild(subtitle)

        // Stars with staggered spring pop-in, grouped in a row container so the
        // whole trio can be positioned as one item in the centered stack.
        // Results scene sits on the primary sky-blue gradient — use white variants.
        let starsRow = SKNode()
        for i in 0..<3 {
            let filled = i < starsEarned
            let spriteName = filled ? SkySprites.starFilledWhite : SkySprites.starEmptyWhite
            let fallbackColor = filled
                ? SkyColors.tertiaryContainer
                : SkyColors.onPrimary.withAlphaComponent(0.2)
            let star = SkySprites.iconNode(
                named: spriteName,
                fallbackEmoji: "★",
                size: 56,
                color: fallbackColor
            )
            star.position = CGPoint(x: -80 + CGFloat(i) * 80, y: 0)
            star.setScale(0.0)
            starsRow.addChild(star)

            let delay = SKAction.wait(forDuration: 0.3 + Double(i) * 0.3)
            let up = SKAction.scale(to: 1.3, duration: 0.15)
            let down = SKAction.scale(to: 1.0, duration: 0.1)
            star.run(SKAction.sequence([delay, up, down]))
        }
        addChild(starsRow)

        // Rio's happy portrait + congratulations, between the stars and the
        // coin pill. Circular crop matching the mission briefing card treatment.
        let portrait = SkySprites.circularPortraitNode(
            named: SkySprites.pilotPortraitHappy,
            diameter: 80,
            fallbackEmoji: "🧑‍✈️",
            fallbackColor: SkyColors.skOnPrimary
        )
        addChild(portrait)

        let message = rioMessageLabel(text: "Clean run. I knew you had it in you.")
        addChild(message)

        // Center the stars → portrait → message block in the band between the
        // subtitle and the coin pill.
        layoutStack(
            [(starsRow, 56), (portrait, 80), (message, message.calculateAccumulatedFrame().height)],
            x: size.width / 2,
            bandTop: size.height * 0.82 - 30 - 24,
            bandBottom: size.height * 0.40 + 30
        )

        // Coin reward pill (gold) with count-up — shared CoinRewardPill so
        // mission end and Landing Practice render the identical treatment.
        let pill = CoinRewardPill(amount: 0)
        pill.position = CGPoint(x: size.width / 2, y: size.height * 0.40)
        addChild(pill)
        pill.animateCountUp(to: challenge.reward)

        // Buttons
        let next = SkyPillButton(title: "NEXT LEVEL", style: .primary, size: CGSize(width: 240, height: 52)) { [weak self] in
            guard let self = self else { return }
            self.advanceAfterResults {
                let nextID = self.challenge.id + 1
                if let nextChallenge = ChallengeCatalog.challenge(forID: nextID) {
                    SkyNavigator.shared.showGame(challenge: nextChallenge)
                } else {
                    SkyNavigator.shared.showMap()
                }
            }
        }
        next.position = CGPoint(x: size.width / 2, y: size.height * 0.26)
        addChild(next)

        let shop = SkyPillButton(title: "UPGRADE SHOP", style: .surface, size: CGSize(width: 240, height: 52)) {
            SkyNavigator.shared.showShop()
        }
        shop.position = CGPoint(x: size.width / 2, y: size.height * 0.26 - 64)
        addChild(shop)

        let mapLink = SKLabelNode(text: "BACK TO MAP")
        mapLink.fontName = SkyFonts.headlineName
        mapLink.fontSize = 12
        mapLink.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.9)
        mapLink.position = CGPoint(x: size.width / 2, y: size.height * 0.10)
        mapLink.name = "resultsBackToMap"
        addChild(mapLink)

        run(AudioManager.shared.sfxAction(SkySFX.win))
    }

    private func buildConfetti() {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: confettiImage())
        emitter.particleBirthRate = 40
        emitter.numParticlesToEmit = 0
        emitter.particleLifetime = 3.0
        emitter.particleLifetimeRange = 1.5
        emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
        emitter.particleSpeed = 120
        emitter.particleSpeedRange = 60
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 6
        emitter.yAcceleration = -40
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.1
        emitter.particleAlphaSpeed = -0.2
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.3
        emitter.particleRotationSpeed = 4
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = nil
        emitter.particleColor = SkyColors.skTertiaryContainer
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 20)
        emitter.zPosition = 90
        addChild(emitter)
    }

    private func confettiImage() -> UIImage {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Fail UI

    private func buildFail() {
        let title = SKLabelNode(text: "MISSION FAILED")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 32
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.80)
        addChild(title)

        let subtitle = SKLabelNode(text: challenge.name)
        subtitle.fontName = SkyFonts.bodyMediumName
        subtitle.fontSize = 14
        subtitle.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.8)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.80 - 30)
        addChild(subtitle)

        // Rio's encouraging portrait + message, between the level name and the
        // coins-collected line. Same circular crop and size as the win screen.
        let portrait = SkySprites.circularPortraitNode(
            named: SkySprites.pilotPortraitEncouraging,
            diameter: 80,
            fallbackEmoji: "🧑‍✈️",
            fallbackColor: SkyColors.skOnPrimary
        )
        addChild(portrait)

        let message = rioMessageLabel(text: "Shake it off. Every ace has bad runs. Try again.")
        addChild(message)

        let coinLine = CoinAmountNode(
            prefix: "Coins collected: ",
            amount: "\(coinsCollected)",
            fontName: SkyFonts.bodyName,
            fontSize: 14,
            color: SkyColors.skOnPrimary.withAlphaComponent(0.85),
            iconAsset: SkySprites.iconCoinWhite
        )
        addChild(coinLine)

        // Center the portrait → message → coins block in the band between the
        // level name and the TRY AGAIN button.
        layoutStack(
            [(portrait, 80),
             (message, message.calculateAccumulatedFrame().height),
             (coinLine, coinLine.calculateAccumulatedFrame().height)],
            x: size.width / 2,
            bandTop: size.height * 0.80 - 30 - 24,
            bandBottom: size.height * 0.38 + 34
        )

        let retry = SkyPillButton(title: "TRY AGAIN", style: .primary, size: CGSize(width: 240, height: 52)) { [weak self] in
            guard let self = self else { return }
            SkyNavigator.shared.showGame(challenge: self.challenge)
        }
        retry.position = CGPoint(x: size.width / 2, y: size.height * 0.38)
        addChild(retry)

        let mapLink = SKLabelNode(text: "BACK TO MAP")
        mapLink.fontName = SkyFonts.headlineName
        mapLink.fontSize = 12
        mapLink.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.9)
        mapLink.position = CGPoint(x: size.width / 2, y: size.height * 0.22)
        mapLink.name = "resultsBackToMap"
        addChild(mapLink)
    }

    // MARK: - Rio message (SKY-122)

    /// A centered, word-wrapping label carrying one of Rio's short reaction
    /// lines. Uses the same font family and on-primary color as the rest of the
    /// screen's body text so it reads as part of the existing screen.
    private func rioMessageLabel(text: String) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = SkyFonts.bodyMediumName
        label.fontSize = 17
        label.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.9)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = min(size.width - 64, 320)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    // MARK: - Layout

    /// Positions `items` (top→bottom) as a vertically-centered stack in the band
    /// between `bandBottom` and `bandTop` at horizontal position `x`. Each entry
    /// is a node and its measured height; nodes are placed by their center with
    /// equal gaps.
    ///
    /// On the tallest and mid-size screens (iPhone 15 Pro down through the
    /// current iPhone SE at 375×667) the content fits with room to spare and is
    /// laid out untouched. On the very shortest supported screen — the original
    /// 320×568 SE — the stars + portrait + a wrapped message can exceed the band
    /// between the header and the fixed coin pill/button below it. Rather than
    /// let the message overlap the pill, the whole stack is uniformly scaled down
    /// to fit the band, so Rio's portrait and message stay clear of the pill on
    /// every device.
    private func layoutStack(_ items: [(node: SKNode, height: CGFloat)],
                             x: CGFloat, bandTop: CGFloat, bandBottom: CGFloat) {
        let bandHeight = bandTop - bandBottom
        let totalContent = items.reduce(0) { $0 + $1.height }

        // Shrink-to-fit only when the content genuinely overflows the band; the
        // common case leaves `fit == 1` and the layout unchanged.
        let fit = (totalContent > bandHeight && totalContent > 0)
            ? bandHeight / totalContent
            : 1.0
        let scaledHeights = items.map { $0.height * fit }
        let scaledTotal = scaledHeights.reduce(0, +)
        let slack = max(0, bandHeight - scaledTotal)
        let gap = items.count > 1 ? slack / CGFloat(items.count + 1) : slack / 2

        var cursor = bandTop - gap
        for (i, item) in items.enumerated() {
            if fit < 1.0 { item.node.setScale(fit) }
            item.node.position = CGPoint(x: x, y: cursor - scaledHeights[i] / 2)
            cursor -= (scaledHeights[i] + gap)
        }
    }

    // MARK: - Touch

    /// Routes taps to the pill buttons and the BACK TO MAP link.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
            if node.name == "resultsBackToMap" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                advanceAfterResults { SkyNavigator.shared.showMap() }
                return
            }
        }
    }

    // MARK: - Chapter transition (SKY-61)

    /// Inserts the one-time Clear Skies → Storm Chaser chapter transition
    /// between an L5 win and the player's next destination. In every other case
    /// it runs `continuation` directly. The transition scene sets its own
    /// `hasSeenChapterTransition` gate on dismiss, so it appears exactly once.
    private func advanceAfterResults(_ continuation: @escaping () -> Void) {
        if didWin,
           challenge.id == 5,
           !ProgressManager.shared.hasSeenChapterTransition {
            SkyNavigator.shared.showChapterTransition(then: continuation)
        } else {
            continuation()
        }
    }
}
