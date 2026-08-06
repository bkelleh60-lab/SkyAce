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

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimaryContainer
        SkyHaptics.prepare()
        layoutScene()
    }

    // SKY-55 pattern: rebuild against the new dimensions on iPad rotation.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    private func layoutScene() {
        buildBackground()
        buildIntroText()
        buildTapHint()
    }

    // MARK: - Background

    private func buildBackground() {
        // Full-bleed intro illustration, aspect-filled so it covers the screen
        // without distortion. Falls back to the sky gradient if the asset is
        // somehow missing, so the scene is never blank.
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

    /// Size that covers `size` while preserving the texture's aspect ratio.
    private func aspectFillSize(for texture: SKTexture) -> CGSize {
        let tex = texture.size()
        guard tex.width > 0, tex.height > 0 else { return size }
        let scale = max(size.width / tex.width, size.height / tex.height)
        return CGSize(width: tex.width * scale, height: tex.height * scale)
    }

    // MARK: - Intro copy

    private func buildIntroText() {
        // The lower band of the artwork is pale, so the paragraph reads in dark
        // navy on a soft translucent panel — the game's card language — which
        // guarantees contrast for the Kids Category.
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        dismiss()
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        ProgressManager.shared.hasSeenGameIntro = true
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyNavigator.shared.showMenu()
    }
}
