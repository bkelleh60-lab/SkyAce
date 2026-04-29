import SpriteKit

/// Post-run scene. Win/fail-aware: stars + confetti + coin count-up on a win,
/// "MISSION FAILED" copy + try-again on a fail.
final class ResultsScene: SKScene {

    private let challenge: Challenge
    private let coinsCollected: Int
    private let hitsTaken: Int
    private let didWin: Bool

    // MARK: - Init
    init(size: CGSize, challenge: Challenge, coinsCollected: Int, hitsTaken: Int, didWin: Bool) {
        self.challenge = challenge
        self.coinsCollected = coinsCollected
        self.hitsTaken = hitsTaken
        self.didWin = didWin
        super.init(size: size)

        // Commit run results to progress/coins on the way in.
        if didWin {
            let stars = StarRating.stars(forHitsTaken: hitsTaken, completed: true)
            ProgressManager.shared.markLevelCompleted(challenge.id, stars: stars)
            ProgressManager.shared.addCoins(challenge.reward)
        }
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = didWin ? SkyColors.skPrimary : SkyColors.skOnSurface
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

    private func buildWin() {
        buildConfetti()

        let title = SKLabelNode(text: "LEVEL COMPLETE!")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 34
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.78)
        addChild(title)

        let subtitle = SKLabelNode(text: challenge.name)
        subtitle.fontName = SkyFonts.bodyMediumName
        subtitle.fontSize = 14
        subtitle.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.8)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.78 - 32)
        addChild(subtitle)

        // Stars with staggered spring pop-in.
        let stars = StarRating.stars(forHitsTaken: hitsTaken, completed: true)
        // Results scene sits on the primary sky-blue gradient — use white variants.
        for i in 0..<3 {
            let filled = i < stars
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
            star.position = CGPoint(x: size.width / 2 - 80 + CGFloat(i) * 80, y: size.height * 0.58)
            star.setScale(0.0)
            addChild(star)

            let delay = SKAction.wait(forDuration: 0.3 + Double(i) * 0.3)
            let up = SKAction.scale(to: 1.3, duration: 0.15)
            let down = SKAction.scale(to: 1.0, duration: 0.1)
            star.run(SKAction.sequence([delay, up, down]))
        }

        // Coin reward pill (gold) with count-up.
        let pillSize = CGSize(width: 200, height: 48)
        let pill = SKShapeNode(rectOf: pillSize, cornerRadius: 24)
        pill.fillColor = SkyColors.skTertiaryContainer
        pill.strokeColor = .clear
        pill.position = CGPoint(x: size.width / 2, y: size.height * 0.44)
        addChild(pill)

        let coinLabel = SKLabelNode()
        coinLabel.verticalAlignmentMode = .center
        coinLabel.horizontalAlignmentMode = .center
        coinLabel.position = pill.position
        coinLabel.attributedText = SkyUIEffects.coinAmountAttributed(
            prefix: "+ ",
            text: "0",
            fontName: SkyFonts.headlineName,
            fontSize: 20,
            color: SkyColors.skOnTertiaryContainer
        )
        addChild(coinLabel)

        animateCoinCountUp(label: coinLabel, target: challenge.reward)

        // Buttons
        let next = SkyPillButton(title: "NEXT LEVEL", style: .primary, size: CGSize(width: 240, height: 52)) { [weak self] in
            guard let self = self else { return }
            let nextID = self.challenge.id + 1
            if let nextChallenge = ChallengeCatalog.challenge(forID: nextID),
               !nextChallenge.requiresFullUnlock || IAPManager.shared.isContentUnlocked {
                SkyNavigator.shared.showGame(challenge: nextChallenge)
            } else if nextID <= ChallengeCatalog.all.count {
                SkyNavigator.shared.showUnlock()
            } else {
                SkyNavigator.shared.showMap()
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

    private func animateCoinCountUp(label: SKLabelNode, target: Int) {
        let steps = 30
        let stepDuration = 0.030
        var actions: [SKAction] = []
        for i in 0...steps {
            let value = Int(round(Double(target) * Double(i) / Double(steps)))
            actions.append(SKAction.run {
                label.attributedText = SkyUIEffects.coinAmountAttributed(
                    prefix: "+ ",
                    text: "\(value)",
                    fontName: SkyFonts.headlineName,
                    fontSize: 20,
                    color: SkyColors.skOnTertiaryContainer
                )
            })
            actions.append(SKAction.wait(forDuration: stepDuration))
        }
        label.run(SKAction.sequence(actions))
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
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        addChild(title)

        let subtitle = SKLabelNode(text: challenge.name)
        subtitle.fontName = SkyFonts.bodyMediumName
        subtitle.fontSize = 14
        subtitle.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.8)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.72 - 32)
        addChild(subtitle)

        let coinLine = SKLabelNode()
        coinLine.position = CGPoint(x: size.width / 2, y: size.height * 0.56)
        coinLine.attributedText = SkyUIEffects.coinAmountAttributed(
            prefix: "Coins collected: ",
            text: "\(coinsCollected)",
            fontName: SkyFonts.bodyName,
            fontSize: 14,
            color: SkyColors.skOnPrimary.withAlphaComponent(0.85),
            iconAsset: SkySprites.iconCoinWhite
        )
        addChild(coinLine)

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

    // MARK: - Touch

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
                SkyNavigator.shared.showMap()
                return
            }
        }
    }
}
