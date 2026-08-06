import SpriteKit

/// One-time game intro shown on first launch, before the menu / level select
/// (SKY-61). Full-screen `intro_bg` illustration with the game intro paragraph
/// laid over the calm lower band, and a tap-anywhere-to-dismiss interaction.
///
/// Presentation is gated by `ProgressManager.hasSeenGameIntro`
/// (see `GameViewController`); this scene also sets that flag on dismiss so it
/// can never repeat, then routes to the menu.
final class GameIntroScene: SKScene {

    private var isDismissing = false
    /// Taps are ignored until the scene has been on screen briefly, so an
    /// over-eager first tap can't skip the intro before it has rendered.
    private var acceptsTaps = false

    // MARK: - Lifecycle

    /// Builds the scene and arms the tap-accept timer once it attaches to a view.
    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimaryContainer
        SkyHaptics.prepare()
        layoutScene()
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.acceptsTaps = true }]))
    }

    /// Rebuilds the layout against the new dimensions on iPad rotation
    /// (SKY-55 pattern).
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    /// Builds the background, intro paragraph, and tap hint in one pass.
    private func layoutScene() {
        buildBackground()
        buildIntroText()
        buildTapHint()
    }

    // MARK: - Background

    /// Lays the full-bleed intro illustration, aspect-filled to cover the
    /// screen, falling back to the sky gradient if the asset is missing.
    private func buildBackground() {
        if let texture = SkySprites.texture(named: SkySprites.introBackground) {
            let bg = SKSpriteNode(texture: texture, size: aspectFillSize(for: texture))
            bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
            bg.zPosition = -100
            addChild(bg)
        } else {
            let gradient = SKGradientBackgroundNode(
                size: size, topColor: SkyColors.skPrimaryContainer, bottomColor: SkyColors.skSurface
            )
            gradient.zPosition = -100
            addChild(gradient)
        }
    }

    // MARK: - Intro copy

    /// Lays the intro paragraph in the lower band. The artwork there is pale, so
    /// the text is dark navy on a soft translucent panel (the game's card
    /// language) to guarantee contrast for the Kids Category.
    private func buildIntroText() {
        let maxWidth = size.width * 0.8
        let centerY = size.height * 0.27

        let label = SKLabelNode(text: MissionContent.gameIntro.body)
        label.fontName = SkyFonts.bodyMediumName
        label.fontSize = 18
        label.fontColor = SkyColors.skOnSurface
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxWidth
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: centerY)
        label.zPosition = 10

        let textFrame = label.calculateAccumulatedFrame()
        let panelSize = CGSize(
            width: min(size.width - 28, textFrame.width + 56),
            height: textFrame.height + 48
        )
        let panel = SKShapeNode(rectOf: panelSize, cornerRadius: 24)
        panel.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.62)
        panel.strokeColor = .clear
        panel.position = CGPoint(x: size.width / 2, y: centerY)
        panel.zPosition = 5

        addChild(panel)
        addChild(label)
    }

    /// Adds the pulsing "tap to continue" affordance above the home indicator.
    private func buildTapHint() {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let hint = SKLabelNode(text: "TAP TO CONTINUE")
        hint.fontName = SkyFonts.headlineName
        hint.fontSize = 13
        hint.fontColor = SkyColors.skOnSurfaceVariant
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: size.width / 2, y: bottomInset + 44)
        hint.zPosition = 10
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.7),
            .fadeAlpha(to: 1.0, duration: 0.7)
        ])))
        addChild(hint)
    }

    // MARK: - Dismiss

    /// Any tap (after the initial lockout) dismisses the intro.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsTaps else { return }
        dismiss()
    }

    /// Records the one-time gate flag and routes to the menu. Runs at most once.
    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        ProgressManager.shared.hasSeenGameIntro = true
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyNavigator.shared.showMenu()
    }
}
