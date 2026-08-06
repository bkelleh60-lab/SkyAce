import SpriteKit

/// Slide-up mission briefing overlay shown after the player taps "Fly" and
/// before the gameplay scene loads (SKY-61). It dims the scene behind it and
/// slides a themed card up from the bottom carrying the commander portrait,
/// mission tagline, and story context, plus a primary START button that
/// dismisses the card and enters gameplay.
///
/// The card art variant and portrait expression follow the brief's chapter:
/// Clear Skies uses the bright card + neutral portrait, Storm Chaser uses the
/// stormy card + serious portrait.
///
/// This node is not itself interactive — the presenting scene (`MapScene`)
/// finds the START button by name and drives `handleTap()`, matching the
/// overlay-routing pattern already used for the menu's world select.
final class MissionBriefingCard: SKNode {

    private let brief: MissionBrief
    private let sceneSize: CGSize
    private let bottomInset: CGFloat
    private let onProceed: () -> Void

    private let scrim: SKSpriteNode
    private let cardGroup = SKNode()

    private var restY: CGFloat = 0
    private var offscreenY: CGFloat = 0
    private var isProceeding = false

    // MARK: - Init

    /// Creates the overlay for `brief`. `onProceed` runs after START slides the
    /// card away, to enter gameplay. `bottomInset` nudges the resting position
    /// clear of the home indicator.
    init(brief: MissionBrief,
         sceneSize: CGSize,
         bottomInset: CGFloat,
         onProceed: @escaping () -> Void) {
        self.brief = brief
        self.sceneSize = sceneSize
        self.bottomInset = bottomInset
        self.onProceed = onProceed
        self.scrim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.68), size: sceneSize)
        super.init()
        build()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    /// Assembles the scrim, themed card art, portrait, tagline, story, and the
    /// START button, positioned off-screen ready for `animateIn()`.
    private func build() {
        scrim.anchorPoint = .zero
        scrim.position = .zero
        scrim.zPosition = 0
        scrim.name = "briefScrim"
        addChild(scrim)

        // Themed card art. Clear Skies card center is light (dark text reads);
        // Storm Chaser center is dark (white text reads).
        let isClear = brief.chapter == .clearSkies
        let cardAsset = isClear ? SkySprites.briefingCardClearSkies : SkySprites.briefingCardStormChaser
        let textColor: UIColor = isClear ? SkyColors.onSurface : .white

        let cardWidth = min(sceneSize.width - 40, 360)
        // Moderately taller than the source art's 610×409 aspect so the portrait
        // and multi-line story fit comfortably in the clear center band. The
        // cloud frame is soft art, so the gentle vertical stretch reads fine.
        let cardHeight = (cardWidth * 0.85).rounded()

        let cardArt = cardBackground(asset: cardAsset, size: CGSize(width: cardWidth, height: cardHeight), isClear: isClear)
        cardArt.zPosition = 0
        cardGroup.addChild(cardArt)

        // Portrait, tagline, and story stacked and vertically centered inside
        // the card's clear zone.
        let portraitSide: CGFloat = 74
        let portrait = pilotPortrait(side: portraitSide, isClear: isClear)
        portrait.zPosition = 2

        let tagline = SKLabelNode(text: brief.tagline)
        tagline.fontName = SkyFonts.headlineName
        tagline.fontSize = 23
        tagline.fontColor = textColor
        tagline.numberOfLines = 2
        tagline.lineBreakMode = .byWordWrapping
        tagline.preferredMaxLayoutWidth = cardWidth * 0.82
        tagline.horizontalAlignmentMode = .center
        tagline.verticalAlignmentMode = .center
        tagline.zPosition = 2

        let story = SKLabelNode(text: brief.storyContext)
        story.fontName = SkyFonts.bodyMediumName
        story.fontSize = 14
        story.fontColor = textColor
        story.numberOfLines = 0
        story.lineBreakMode = .byWordWrapping
        story.preferredMaxLayoutWidth = cardWidth * 0.80
        story.horizontalAlignmentMode = .center
        story.verticalAlignmentMode = .center
        story.zPosition = 2

        let tagH = tagline.calculateAccumulatedFrame().height
        let storyH = story.calculateAccumulatedFrame().height
        let gap: CGFloat = 12
        let blockH = portraitSide + gap + tagH + gap + storyH

        // Lay out top→bottom, centering the block on the card art's center.
        var cursor = blockH / 2
        portrait.position = CGPoint(x: 0, y: cursor - portraitSide / 2)
        cursor -= (portraitSide + gap)
        tagline.position = CGPoint(x: 0, y: cursor - tagH / 2)
        cursor -= (tagH + gap)
        story.position = CGPoint(x: 0, y: cursor - storyH / 2)

        cardGroup.addChild(portrait)
        cardGroup.addChild(tagline)
        cardGroup.addChild(story)

        // START button sits below the card on the scrim. It is the only control:
        // it dismisses the briefing and enters gameplay.
        let buttonHeight: CGFloat = 52
        let button = SkyPillButton(
            title: "START",
            style: .primary,
            size: CGSize(width: cardWidth * 0.82, height: buttonHeight)
        ) { [weak self] in self?.proceed() }
        button.name = "briefStart"
        button.zPosition = 2
        let buttonY = -(cardHeight / 2) - 12 - buttonHeight / 2
        button.position = CGPoint(x: 0, y: buttonY)
        cardGroup.addChild(button)

        // Rest position. Centering the *whole* block on the screen center (the
        // original approach) let the START button hang into the lower third,
        // where it overlapped the active level's info card that shows dimmed
        // behind the scrim (SKY-112). Instead, pin the START button's baseline
        // into the lower-middle so it clears the tab bar and info card, and let
        // the card float above it. Clamp so a tall card on a shorter screen never
        // pushes off the top. Offscreen start sits fully below the bottom edge
        // for the slide-up.
        let bottomExtent = -buttonY + buttonHeight / 2  // origin → button bottom
        let topExtent = cardHeight / 2                  // origin → card top
        let buttonBottomTarget = max(sceneSize.height * 0.40, bottomInset + 160)
        let maxRestY = sceneSize.height - topExtent - 24 // keep card top on-screen
        restY = min(buttonBottomTarget + bottomExtent, maxRestY)
        offscreenY = -bottomExtent - 40
        cardGroup.position = CGPoint(x: sceneSize.width / 2, y: offscreenY)
        cardGroup.zPosition = 1
        addChild(cardGroup)
    }

    /// The themed card art stretched to `size`, or a solid rounded fallback
    /// panel if the asset is missing so the briefing is never blank.
    private func cardBackground(asset: String, size: CGSize, isClear: Bool) -> SKNode {
        if let texture = SkySprites.texture(named: asset) {
            return SKSpriteNode(texture: texture, size: size)
        }
        let panel = SKShapeNode(rectOf: size, cornerRadius: 24)
        panel.fillColor = isClear ? SkyColors.skPrimaryContainer : SkyColors.skOnSurface
        panel.strokeColor = .clear
        return panel
    }

    /// The commander portrait for this chapter, falling back to the neutral
    /// portrait, the pilot avatar, then an emoji so it always renders.
    private func pilotPortrait(side: CGFloat, isClear: Bool) -> SKNode {
        let preferred = isClear ? SkySprites.pilotPortraitNeutral : SkySprites.pilotPortraitSerious
        let name = SkySprites.texture(named: preferred) != nil ? preferred
            : (SkySprites.texture(named: SkySprites.pilotPortraitNeutral) != nil ? SkySprites.pilotPortraitNeutral
               : SkySprites.pilotAvatar)
        return SkySprites.iconNode(
            named: name,
            fallbackEmoji: "🧑‍✈️",
            size: side,
            color: SkyColors.onSurface
        )
    }

    // MARK: - Present / dismiss

    /// Fades the scrim in and slides the card up to rest.
    func animateIn() {
        scrim.alpha = 0
        scrim.run(.fadeIn(withDuration: 0.2))
        cardGroup.run(.moveTo(y: restY, duration: 0.32, timingMode: .easeOut))
    }

    /// Slide the card down, fade the scrim out, remove the overlay, then hand
    /// control back to the presenter. Runs at most once.
    private func proceed() {
        guard !isProceeding else { return }
        isProceeding = true
        scrim.run(.fadeOut(withDuration: 0.22))
        let slideDown = SKAction.moveTo(y: offscreenY, duration: 0.26, timingMode: .easeIn)
        cardGroup.run(slideDown) { [weak self] in
            self?.removeFromParent()
            self?.onProceed()
        }
    }
}

// MARK: - SKAction convenience

private extension SKAction {
    /// `moveTo(y:duration:)` with an explicit timing mode.
    static func moveTo(y: CGFloat, duration: TimeInterval, timingMode: SKActionTimingMode) -> SKAction {
        let action = SKAction.moveTo(y: y, duration: duration)
        action.timingMode = timingMode
        return action
    }
}
