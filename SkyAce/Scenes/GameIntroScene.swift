import SpriteKit

/// One-time game intro shown on first launch, before the menu / level select
/// (SKY-61, restyled in SKY-113). Full-screen `intro_bg` illustration with the
/// game intro paragraph laid directly over the calm lower band — Rio's portrait
/// above the copy and a primary "LET'S FLY" button below — and a
/// button-to-continue interaction.
///
/// Presentation is gated by `ProgressManager.hasSeenGameIntro`
/// (see `GameViewController`); this scene also sets that flag on dismiss so it
/// can never repeat, then routes to the menu.
final class GameIntroScene: SKScene {

    private var isDismissing = false
    /// Taps are ignored until the scene has been on screen briefly, so an
    /// over-eager first tap can't skip the intro before it has rendered.
    private var acceptsTaps = false

    /// Layout constants shared across the lower stack.
    private enum Layout {
        static let portraitSide: CGFloat = 80
        static let portraitGap: CGFloat = 8
        static let nameToTextGap: CGFloat = 14
        static let buttonHeight: CGFloat = 67 // +20% over the original 56pt
        static let buttonBottomPadding: CGFloat = 24
        static let buttonToTextGap: CGFloat = 40
    }

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

    /// Builds the background, then the lower stack (portrait, copy, button) from
    /// the bottom up so it stays anchored above the home indicator on every
    /// screen size.
    private func layoutScene() {
        buildBackground()
        buildLowerStack()
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

    // MARK: - Lower stack

    /// Lays Rio's portrait, her name label, the intro copy, and the primary
    /// button as one stack anchored from the bottom edge up. No card behind the
    /// text — the copy floats over the sky gradient with a soft drop shadow for
    /// legibility (SKY-113).
    private func buildLowerStack() {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let centerX = size.width / 2

        // Button pinned to the bottom, full-width with side padding.
        let buttonWidth = min(size.width - 48, 420)
        let buttonY = bottomInset + Layout.buttonBottomPadding + Layout.buttonHeight / 2
        buildStartButton(width: buttonWidth, centerY: buttonY)

        // Intro copy sits above the button. White bold text with a soft dark
        // drop shadow so it reads cleanly over the lower sky artwork.
        let copy = shadowed { self.introLabel(maxWidth: self.size.width * 0.85) }
        let textHeight = copy.calculateAccumulatedFrame().height
        let buttonTop = buttonY + Layout.buttonHeight / 2
        let textCenterY = buttonTop + Layout.buttonToTextGap + textHeight / 2
        copy.position = CGPoint(x: centerX, y: textCenterY)
        copy.zPosition = 10
        addChild(copy)
        let textTop = textCenterY + textHeight / 2

        // "Captain Rio" name label directly under the portrait, above the copy.
        let nameLabel = shadowed { self.rioNameLabel() }
        let nameHeight = nameLabel.calculateAccumulatedFrame().height
        let nameCenterY = textTop + Layout.nameToTextGap + nameHeight / 2
        nameLabel.position = CGPoint(x: centerX, y: nameCenterY)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        let nameTop = nameCenterY + nameHeight / 2

        // Rio's portrait above the name label.
        let portrait = buildPortrait(side: Layout.portraitSide)
        portrait.position = CGPoint(
            x: centerX,
            y: nameTop + Layout.portraitGap + Layout.portraitSide / 2
        )
        portrait.zPosition = 10
        addChild(portrait)
    }

    /// Rio's portrait, circular-cropped with a soft ambient shadow and a thin
    /// white ring to lift it off the sky. Falls back through the neutral
    /// portrait / pilot avatar / emoji chain so it always renders.
    private func buildPortrait(side: CGFloat) -> SKNode {
        let container = SKNode()
        let radius = side / 2

        // Soft shadow behind the disc.
        let shadow = SkyUIEffects.shadowSprite(size: CGSize(width: side, height: side), cornerRadius: radius)
        shadow.zPosition = -1
        container.addChild(shadow)

        if let texture = SkySprites.texture(named: SkySprites.pilotPortraitNeutral)
            ?? SkySprites.texture(named: SkySprites.pilotAvatar) {
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
            let mask = SKShapeNode(circleOfRadius: radius)
            mask.fillColor = .white
            mask.strokeColor = .clear
            let crop = SKCropNode()
            crop.maskNode = mask
            crop.addChild(sprite)
            crop.zPosition = 0
            container.addChild(crop)

            let ring = SKShapeNode(circleOfRadius: radius)
            ring.fillColor = .clear
            ring.strokeColor = UIColor.white.withAlphaComponent(0.9)
            ring.lineWidth = 2
            ring.zPosition = 1
            container.addChild(ring)
        } else {
            // Asset missing — emoji fallback so the intro is never blank.
            let label = SKLabelNode(text: "🧑‍✈️")
            label.fontSize = side
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            container.addChild(label)
        }
        return container
    }

    /// Wraps a white label in a soft drop shadow (black @ 50%, 1pt below),
    /// approximated by an offset dark duplicate since `SKLabelNode` has no
    /// native shadow. `build` is called twice — once for the shadow, once for
    /// the visible white copy — so both stay identical. Returns a container
    /// centered on `.zero`.
    private func shadowed(_ build: () -> SKLabelNode) -> SKNode {
        let container = SKNode()

        let shadow = build()
        shadow.fontColor = UIColor.black.withAlphaComponent(0.5)
        shadow.position = CGPoint(x: 0, y: -1)
        shadow.zPosition = 0
        container.addChild(shadow)

        let label = build()
        label.fontColor = .white
        label.position = .zero
        label.zPosition = 1
        container.addChild(label)

        return container
    }

    /// A configured intro paragraph label (bold, centered, wrapped). Color is
    /// applied by `shadowed(_:)`.
    private func introLabel(maxWidth: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: MissionContent.gameIntro.body)
        label.fontName = SkyFonts.boldName
        label.fontSize = 22
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxWidth
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    /// The small "Captain Rio" name label shown under the portrait. Color is
    /// applied by `shadowed(_:)`.
    private func rioNameLabel() -> SKLabelNode {
        let label = SKLabelNode(text: "Captain Rio")
        label.fontName = SkyFonts.boldName
        label.fontSize = 13
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    /// The primary "LET'S FLY" button, matching the START button on the mission
    /// briefing card (same `SkyPillButton` primary style). Taps are routed to it
    /// from `touchesBegan`, mirroring the briefing-card overlay pattern.
    private func buildStartButton(width: CGFloat, centerY: CGFloat) {
        let button = SkyPillButton(
            title: "LET'S FLY",
            style: .primary,
            size: CGSize(width: width, height: Layout.buttonHeight)
        ) { [weak self] in self?.dismiss(playSFX: false) }
        button.name = "introStart"
        button.position = CGPoint(x: size.width / 2, y: centerY)
        button.zPosition = 10
        addChild(button)
    }

    // MARK: - Dismiss

    /// Routes the tap to the START button (its `handleTap` plays SFX + haptic +
    /// press animation, then dismisses). A tap anywhere else on the screen is a
    /// forgiving fallback that also continues.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsTaps, let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            var current: SKNode? = node
            while let n = current {
                if let button = n as? SkyPillButton, button.name == "introStart" {
                    button.handleTap()
                    return
                }
                current = n.parent
            }
        }
        dismiss()
    }

    /// Records the one-time gate flag and routes to the menu. Runs at most once.
    /// `playSFX` is false when the tap already went through `SkyPillButton`,
    /// which plays the tap sound itself.
    private func dismiss(playSFX: Bool = true) {
        guard !isDismissing else { return }
        isDismissing = true
        ProgressManager.shared.hasSeenGameIntro = true
        if playSFX {
            AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        }
        SkyNavigator.shared.showMenu()
    }
}
