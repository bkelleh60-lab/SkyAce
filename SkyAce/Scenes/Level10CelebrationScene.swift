import SpriteKit

/// Full-screen celebration shown once, the first time Level 10 is completed,
/// before the standard `ResultsScene` (SKY-123). This is the game's biggest
/// payoff: the player earns the "Certified Sky Ace" badge, which is
/// permanently recorded via `ProgressManager.hasEarnedCertifiedSkyAce` for the
/// badge collection screen (SKY-124) to read.
///
/// Presentation flow: L10 gameplay ends → this scene → standard results screen.
/// The gate lives in `GameScene.routeToResults()` (a win on
/// `ChallengeCatalog.finalLevelID`); levels 1–9 route straight to `ResultsScene`.
///
/// Modeled on `ChapterTransitionScene`: full-bleed background, a brief tap
/// lockout so a carried-over tap can't skip it, and `didChangeSize` rebuild for
/// iPad rotation. It additionally auto-advances after `autoAdvanceDelay` so it
/// never blocks the player if untouched.
final class Level10CelebrationScene: SKScene {

    private let onDismiss: () -> Void
    private var isDismissing = false
    /// The player reaches this scene at the instant L10 gameplay ends; taps are
    /// ignored for a beat so a carried-over tap can't dismiss it before the
    /// badge reveal is readable.
    private var acceptsTaps = false

    /// Auto-advance to the results screen after this long if the player never
    /// taps (AC: "auto-advance after 4 seconds").
    private let autoAdvanceDelay: TimeInterval = 4.0
    private static let autoAdvanceKey = "level10AutoAdvance"

    // MARK: - Init

    /// Creates the celebration scene. `onDismiss` runs on tap (or auto-advance)
    /// to proceed to the standard L10 results screen.
    init(size: CGSize, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    /// Persists the earned badge, builds the scene, and runs the reveal.
    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skOnSurface
        SkyHaptics.prepare()

        // Persist the badge the moment the screen is shown, so it survives even
        // if the player force-quits before tapping through to the results.
        ProgressManager.shared.hasEarnedCertifiedSkyAce = true

        layoutScene()
    }

    /// Rebuilds the layout against the new dimensions on iPad rotation
    /// (SKY-55 pattern). The badge is already persisted, so replaying the reveal
    /// animation on resize loses no state.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        acceptsTaps = false
        layoutScene()
    }

    /// Builds the background and every reveal element, then kicks off the
    /// staged entrance and the tap-accept / auto-advance timers.
    private func layoutScene() {
        buildBackground()
        buildConfetti()
        let title = buildTitle()
        let glow = buildBadgeGlow()
        let badge = buildBadge()
        let portrait = buildPortrait()
        let message = buildMessage()
        let tapHint = buildTapHint()

        runReveal(title: title, glow: glow, badge: badge,
                  portrait: portrait, message: message, tapHint: tapHint)

        // Arm taps after a beat, and auto-advance after the full delay.
        run(.sequence([.wait(forDuration: 0.6),
                       .run { [weak self] in self?.acceptsTaps = true }]))
        run(.sequence([.wait(forDuration: autoAdvanceDelay),
                       .run { [weak self] in self?.advance() }]),
            withKey: Self.autoAdvanceKey)
    }

    // MARK: - Layout anchors

    /// Badge target side. Capped at 160pt (AC) but scaled down on very short
    /// screens (original 320×568 SE) so the badge, portrait, and message keep
    /// clear vertical gaps.
    private var badgeSide: CGFloat { min(160, size.height * 0.23) }

    private var titleCenterY: CGFloat { size.height * 0.80 }
    private var badgeCenterY: CGFloat { size.height * 0.55 }
    private var portraitCenterY: CGFloat { size.height * 0.33 }
    private var messageCenterY: CGFloat { size.height * 0.17 }

    // MARK: - Background

    /// Full-screen deep navy (#08314D) — dramatic and distinct from the standard
    /// results screen's sky blue, so this reads as the earned, bigger moment.
    private func buildBackground() {
        let bg = SKSpriteNode(color: SkyColors.skOnSurface, size: size)
        bg.anchorPoint = .zero
        bg.position = .zero
        bg.zPosition = -100
        addChild(bg)
    }

    // MARK: - Confetti

    /// Two full-width emitters — gold (#FFD709) and sky blue (#00BAFF) — raining
    /// from just above the top edge. Deliberately higher birth rate than the
    /// standard results confetti (SKY-122 uses 40) so this reads as the bigger
    /// celebration.
    private func buildConfetti() {
        for color in [SkyColors.skTertiaryContainer, SkyColors.skPrimaryContainer] {
            let emitter = SKEmitterNode()
            emitter.particleTexture = SKTexture(image: Self.confettiImage)
            emitter.particleBirthRate = 75
            emitter.numParticlesToEmit = 0
            emitter.particleLifetime = 3.5
            emitter.particleLifetimeRange = 1.5
            emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
            emitter.particleSpeed = 150
            emitter.particleSpeedRange = 70
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = .pi / 5
            emitter.yAcceleration = -45
            emitter.particleAlpha = 0.95
            emitter.particleAlphaRange = 0.1
            emitter.particleAlphaSpeed = -0.2
            emitter.particleScale = 0.55
            emitter.particleScaleRange = 0.35
            emitter.particleRotationSpeed = 4.5
            emitter.particleColorBlendFactor = 1.0
            emitter.particleColorSequence = nil
            emitter.particleColor = color
            emitter.position = CGPoint(x: size.width / 2, y: size.height + 20)
            emitter.zPosition = 90
            addChild(emitter)
        }
    }

    /// A small white filled dot used as the confetti particle sprite; tinted per
    /// emitter via `particleColor`.
    private static let confettiImage: UIImage = {
        let side = CGSize(width: 10, height: 10)
        return UIGraphicsImageRenderer(size: side).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: side))
        }
    }()

    // MARK: - Reveal elements (built hidden; animated in by runReveal)

    /// "CERTIFIED SKY ACE" in large bold gold, upper third. Starts hidden.
    private func buildTitle() -> SKLabelNode {
        let title = SKLabelNode(text: "CERTIFIED SKY ACE")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = min(34, size.width * 0.085)
        title.fontColor = SkyColors.skTertiaryContainer
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: titleCenterY)
        title.zPosition = 20
        title.alpha = 0
        title.setScale(0.6)
        addChild(title)
        return title
    }

    /// Soft golden glow that fades in behind the badge on landing.
    private func buildBadgeGlow() -> SKShapeNode {
        let glow = SKShapeNode(circleOfRadius: badgeSide * 0.62)
        glow.fillColor = SkyColors.skTertiaryContainer.withAlphaComponent(0.35)
        glow.strokeColor = SkyColors.skTertiaryContainer
        glow.lineWidth = 2
        glow.glowWidth = 26
        glow.blendMode = .add
        glow.position = CGPoint(x: size.width / 2, y: badgeCenterY)
        glow.zPosition = 8
        glow.alpha = 0
        addChild(glow)
        return glow
    }

    /// The gold medallion badge at ~160pt. Starts scaled to zero; `runReveal`
    /// pops it in with an overshoot bounce. Falls back to a trophy emoji if the
    /// asset is somehow missing.
    private func buildBadge() -> SKNode {
        let badge = SkySprites.iconNode(
            named: SkySprites.badgeCertifiedSkyAce,
            fallbackEmoji: "🏅",
            size: badgeSide,
            color: SkyColors.skTertiaryContainer
        )
        badge.position = CGPoint(x: size.width / 2, y: badgeCenterY)
        badge.zPosition = 10
        badge.setScale(0)
        addChild(badge)
        return badge
    }

    /// Rio's excited portrait, 80pt circular crop, below the badge. Starts
    /// hidden; fades in after the badge lands.
    private func buildPortrait() -> SKNode {
        let portrait = SkySprites.circularPortraitNode(
            named: SkySprites.pilotPortraitExcited,
            diameter: 80,
            fallbackEmoji: "🧑‍✈️",
            fallbackColor: SkyColors.skOnPrimary
        )
        portrait.position = CGPoint(x: size.width / 2, y: portraitCenterY)
        portrait.zPosition = 10
        portrait.alpha = 0
        addChild(portrait)
        return portrait
    }

    /// Rio's message, white bold, centered and word-wrapped to ~80% width.
    /// Starts hidden; fades in after the portrait.
    private func buildMessage() -> SKLabelNode {
        let message = SKLabelNode(text: "I don't hand these out to just anyone. You flew every level I threw at you and you didn't quit. That's what this badge means.")
        message.fontName = SkyFonts.boldName
        message.fontSize = 16
        message.fontColor = .white
        message.numberOfLines = 0
        message.lineBreakMode = .byWordWrapping
        message.preferredMaxLayoutWidth = size.width * 0.80
        message.horizontalAlignmentMode = .center
        message.verticalAlignmentMode = .center
        message.position = CGPoint(x: size.width / 2, y: messageCenterY)
        message.zPosition = 20
        message.alpha = 0
        addChild(message)
        return message
    }

    /// Small grey "TAP TO CONTINUE" affordance above the home indicator. Starts
    /// hidden; fades in last, then pulses.
    private func buildTapHint() -> SKLabelNode {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let hint = SKLabelNode(text: "TAP TO CONTINUE")
        hint.fontName = SkyFonts.headlineName
        hint.fontSize = 12
        hint.fontColor = SkyColors.skOutlineVariant
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: size.width / 2, y: bottomInset + 38)
        hint.zPosition = 20
        hint.alpha = 0
        addChild(hint)
        return hint
    }

    // MARK: - Reveal animation

    /// Stages the entrance so it reads top-to-bottom: confetti (already firing)
    /// → gold title → badge pop/bounce with a glow + sparkle on landing → Rio's
    /// portrait → her message → the tap hint.
    private func runReveal(title: SKLabelNode, glow: SKShapeNode, badge: SKNode,
                           portrait: SKNode, message: SKLabelNode, tapHint: SKLabelNode) {
        // Title fades + scales in with the badge.
        title.run(.sequence([
            .wait(forDuration: 0.1),
            .group([.fadeIn(withDuration: 0.3), .scale(to: 1.0, duration: 0.3)])
        ]))

        // Badge pop/bounce: overshoot, settle back, tiny second bounce.
        badge.run(.sequence([
            .wait(forDuration: 0.25),
            .group([
                .fadeIn(withDuration: 0.15),
                .sequence([
                    .scale(to: 1.18, duration: 0.28),
                    .scale(to: 0.92, duration: 0.10),
                    .scale(to: 1.03, duration: 0.08),
                    .scale(to: 1.0, duration: 0.06)
                ])
            ]),
            // Landing: glow in + sparkle burst + celebratory haptic/SFX.
            .run { [weak self] in
                self?.landBadge(glow: glow, at: badge.position)
            }
        ]))

        // Portrait fades in after the badge settles.
        portrait.run(.sequence([.wait(forDuration: 0.9), .fadeIn(withDuration: 0.3)]))

        // Message fades in after the portrait.
        message.run(.sequence([.wait(forDuration: 1.3), .fadeAlpha(to: 1.0, duration: 0.4)]))

        // Tap hint fades in last, then pulses to invite the tap.
        tapHint.run(.sequence([
            .wait(forDuration: 1.7),
            .fadeAlpha(to: 0.9, duration: 0.3),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.4, duration: 0.7),
                .fadeAlpha(to: 0.9, duration: 0.7)
            ]))
        ]))
    }

    /// Fires when the badge finishes its bounce: fades the golden glow in with a
    /// gentle pulse, sprays a short gold sparkle burst, and plays the win
    /// haptic + SFX.
    private func landBadge(glow: SKShapeNode, at point: CGPoint) {
        glow.run(.sequence([
            .fadeAlpha(to: 0.85, duration: 0.2),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.5, duration: 0.9),
                .fadeAlpha(to: 0.85, duration: 0.9)
            ]))
        ]))

        let sparkle = SKEmitterNode()
        sparkle.particleTexture = SKTexture(image: Self.confettiImage)
        sparkle.numParticlesToEmit = 28
        sparkle.particleBirthRate = 600
        sparkle.particleLifetime = 0.7
        sparkle.particleLifetimeRange = 0.3
        sparkle.emissionAngle = 0
        sparkle.emissionAngleRange = .pi * 2
        sparkle.particleSpeed = 130
        sparkle.particleSpeedRange = 60
        sparkle.particleAlpha = 1.0
        sparkle.particleAlphaSpeed = -1.3
        sparkle.particleScale = 0.35
        sparkle.particleScaleRange = 0.2
        sparkle.particleScaleSpeed = -0.3
        sparkle.particleColorBlendFactor = 1.0
        sparkle.particleColor = SkyColors.skTertiaryContainer
        sparkle.particleBlendMode = .add
        sparkle.position = point
        sparkle.zPosition = 9
        sparkle.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
        addChild(sparkle)

        SkyHaptics.win()
        run(AudioManager.shared.sfxAction(SkySFX.win))
    }

    // MARK: - Dismiss

    /// Any tap (after the initial lockout) advances immediately to the results
    /// screen.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsTaps else { return }
        advance()
    }

    /// Proceeds to the standard results screen. Runs at most once, whether
    /// triggered by tap or the auto-advance timer.
    private func advance() {
        guard !isDismissing else { return }
        isDismissing = true
        removeAction(forKey: Self.autoAdvanceKey)
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        onDismiss()
    }
}
