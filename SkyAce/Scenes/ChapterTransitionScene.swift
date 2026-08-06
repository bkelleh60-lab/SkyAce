import SpriteKit

/// Full-screen chapter transition shown once between L5 completion and L6
/// (SKY-61, stretch goal). Full-bleed `chapter_transition` illustration with
/// the two chapter strings centered over a soft dark panel, and a
/// tap-anywhere-to-dismiss interaction.
///
/// Presentation is gated by `ProgressManager.hasSeenChapterTransition`
/// (see `ResultsScene`); this scene sets that flag on dismiss and then invokes
/// the `onDismiss` continuation to proceed to wherever the player was headed
/// (L6 or the map).
final class ChapterTransitionScene: SKScene {

    private let onDismiss: () -> Void
    private var isDismissing = false
    /// The player reaches this scene by tapping NEXT LEVEL / BACK TO MAP on the
    /// results screen; taps are ignored for a beat so a carried-over second tap
    /// can't dismiss this one-time screen before it's readable.
    private var acceptsTaps = false

    // MARK: - Init

    /// Creates the transition scene. `onDismiss` runs on tap to continue to the
    /// player's original destination (L6 or the map).
    init(size: CGSize, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    /// Builds the scene and arms the tap-accept timer once it attaches to a view.
    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
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

    /// Builds the background, the two chapter lines, and the tap hint.
    private func layoutScene() {
        buildBackground()
        buildText()
        buildTapHint()
    }

    // MARK: - Background

    /// Lays the full-bleed transition illustration, aspect-filled to cover the
    /// screen, falling back to a gradient if the asset is missing.
    private func buildBackground() {
        if let texture = SkySprites.texture(named: SkySprites.chapterTransition) {
            let bg = SKSpriteNode(texture: texture, size: aspectFillSize(for: texture))
            bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
            bg.zPosition = -100
            addChild(bg)
        } else {
            let gradient = SKGradientBackgroundNode(
                size: size, topColor: SkyColors.skPrimaryContainer, bottomColor: SkyColors.skOnSurface
            )
            gradient.zPosition = -100
            addChild(gradient)
        }
    }

    // MARK: - Text

    /// Stacks the two chapter lines centered on a soft dark panel. The artwork
    /// splits bright (upper-left) to stormy (lower-right), so the dark panel
    /// with white text keeps both lines legible across the whole composition.
    private func buildText() {
        let maxWidth = size.width * 0.78
        let centerY = size.height * 0.5

        let one = makeLabel(
            MissionContent.chapterTransition.chapterOneComplete,
            fontName: SkyFonts.bodyMediumName, fontSize: 17, maxWidth: maxWidth
        )
        let two = makeLabel(
            MissionContent.chapterTransition.chapterTwoIntro,
            fontName: SkyFonts.headlineName, fontSize: 21, maxWidth: maxWidth
        )

        let oneH = one.calculateAccumulatedFrame().height
        let twoH = two.calculateAccumulatedFrame().height
        let gap: CGFloat = 20
        let totalH = oneH + gap + twoH

        // Stack the two lines centered on centerY.
        one.position = CGPoint(x: size.width / 2, y: centerY + totalH / 2 - oneH / 2)
        two.position = CGPoint(x: size.width / 2, y: centerY - totalH / 2 + twoH / 2)

        let widest = max(one.calculateAccumulatedFrame().width, two.calculateAccumulatedFrame().width)
        let panelSize = CGSize(
            width: min(size.width - 32, widest + 56),
            height: totalH + 56
        )
        let panel = SKShapeNode(rectOf: panelSize, cornerRadius: 26)
        panel.fillColor = SkyColors.skOnSurface.withAlphaComponent(0.55)
        panel.strokeColor = .clear
        panel.position = CGPoint(x: size.width / 2, y: centerY)
        panel.zPosition = 5

        addChild(panel)
        addChild(one)
        addChild(two)
    }

    /// A centered, word-wrapping white label for one transition line.
    private func makeLabel(_ text: String, fontName: String, fontSize: CGFloat, maxWidth: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = fontName
        label.fontSize = fontSize
        label.fontColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxWidth
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 10
        return label
    }

    /// Adds the pulsing "tap to continue" affordance above the home indicator.
    private func buildTapHint() {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let hint = SKLabelNode(text: "TAP TO CONTINUE")
        hint.fontName = SkyFonts.headlineName
        hint.fontSize = 13
        hint.fontColor = .white
        hint.alpha = 0.9
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: size.width / 2, y: bottomInset + 44)
        hint.zPosition = 10
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.7),
            .fadeAlpha(to: 0.9, duration: 0.7)
        ])))
        addChild(hint)
    }

    // MARK: - Dismiss

    /// Any tap (after the initial lockout) dismisses the transition.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsTaps else { return }
        dismiss()
    }

    /// Records the one-time gate flag and runs the continuation. Runs at most once.
    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        ProgressManager.shared.hasSeenChapterTransition = true
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        onDismiss()
    }
}
