import SpriteKit

/// Home screen: sky gradient, drifting clouds, a pilot-avatar top bar with
/// the coin balance + sound toggle + badges trophy, the user's selected plane as a tilted
/// hero image, a chunky PLAY CTA, a 2-tile bento row (FREE FLIGHT /
/// UPGRADE), and the persistent bottom nav bar with Home as the active tab.
final class MenuScene: SKScene {

    private var worldSelectOverlay: SKNode?

    /// iOS safe-area insets, populated on didMove so top-bar content clears
    /// the Dynamic Island / notch and the nav bar clears the home indicator.
    private var topSafeInset: CGFloat = 0
    private var bottomSafeInset: CGFloat = 0

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        SkyHaptics.prepare()
        layoutScene()
    }

    // SKY-55: SpriteKit's `.resizeFill` updates `scene.size` on iPad rotation
    // but doesn't reposition or resize anything we built against the launch-time
    // size. Tear down and re-run the layout pipeline so every node lands in the
    // right spot for the new orientation. The first call (size == oldSize, or
    // pre-didMove zero) is a no-op.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        // Modal world-select overlay can't survive a rebuild — its blurred
        // backdrop snapshot is anchored to the old layout and the overlay is
        // anyway dismissable, so drop it before rebuilding.
        worldSelectOverlay?.removeFromParent()
        worldSelectOverlay = nil
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    private func layoutScene() {
        topSafeInset = view?.safeAreaInsets.top ?? 0
        bottomSafeInset = view?.safeAreaInsets.bottom ?? 0
        buildGradient()
        buildClouds()
        buildTopBar()
        buildHeroPlane()
        buildPlayCTA()
        buildBentoRow()
        buildNavBar()
    }

    // MARK: - Background

    private func buildGradient() {
        let gradient = SKGradientBackgroundNode(
            size: size,
            topColor: SkyColors.skPrimary,
            bottomColor: SkyColors.skPrimaryContainer
        )
        gradient.zPosition = -100
        addChild(gradient)
    }

    private func buildClouds() {
        for _ in 0..<8 {
            let cloud = MenuCloud()
            let y = CGFloat.random(in: size.height * 0.3...size.height * 0.9)
            cloud.position = CGPoint(x: CGFloat.random(in: -60...size.width + 60), y: y)
            cloud.zPosition = -50
            addChild(cloud)
            startCloudDrift(cloud)
        }
    }

    private func startCloudDrift(_ cloud: SKNode) {
        let speed = CGFloat.random(in: 15...40)
        let distance = size.width + 200
        let duration = TimeInterval(distance / speed)
        let moveLeft = SKAction.moveBy(x: -distance, y: 0, duration: duration)
        let reset = SKAction.run { [weak self] in
            guard let self = self else { return }
            cloud.position = CGPoint(x: self.size.width + 80, y: CGFloat.random(in: self.size.height * 0.3...self.size.height * 0.9))
        }
        cloud.run(SKAction.repeatForever(SKAction.sequence([moveLeft, reset])))
    }

    // MARK: - Top bar (pilot avatar + title + coin pill + gear)

    private func buildTopBar() {
        // SkyMenuTopBar anchors to the top edge of the screen and lays its
        // surface fill + content out internally relative to the current
        // top safe-area inset. The host view controller patches the inset
        // after the first layout pass — see `viewSafeAreaInsetsDidChange`.
        let bar = SkyMenuTopBar(width: size.width, topInset: topSafeInset)
        bar.position = CGPoint(x: size.width / 2, y: size.height)
        bar.zPosition = 30
        bar.name = "topBar"
        addChild(bar)
    }

    // MARK: - Hero plane (user's selected, tilted up 12°)

    private func buildHeroPlane() {
        let plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 2.8)
        plane.physicsBody = nil
        plane.zRotation = CGFloat.pi / 180 * 12
        plane.position = CGPoint(x: size.width / 2, y: size.height * 0.60)
        plane.zPosition = 10
        addChild(plane)
    }

    // MARK: - PLAY CTA (chunky arcade button)

    private func buildPlayCTA() {
        let cta = SkyChunkyButton(
            title: "PLAY",
            iconName: SkySprites.iconPlay,
            size: CGSize(width: min(size.width - 80, 300), height: 88)
        ) { [weak self] in self?.tapPlay() }
        cta.position = CGPoint(x: size.width / 2, y: size.height * 0.34)
        cta.zPosition = 20
        cta.name = "playCTA"
        addChild(cta)
    }

    // MARK: - Bento row (FREE FLIGHT + UPGRADE)

    /// FREE FLIGHT (peach) and UPGRADE (gold) share the PLAY button's chunky
    /// pill treatment via `SkyChunkyButton`, just smaller and in their own
    /// colour styles, so the three buttons read as one cohesive set (SKY-92).
    private func buildBentoRow() {
        let tileSize = CGSize(width: 138, height: 86)
        let rowY = size.height * 0.22
        let gap: CGFloat = 16
        let totalWidth = tileSize.width * 2 + gap

        // Navy plane glyph — matches the navy label for legible contrast on
        // the light peach face.
        let planeIcon = SkySprites.sfSymbolNode(
            systemName: "airplane", size: 28, color: SkyColors.onSurface
        )
        let freeFlight = SkyChunkyButton(
            title: "FREE FLIGHT",
            icon: planeIcon,
            size: tileSize,
            style: .secondary,
            cornerRadius: 28,
            labelFontSize: 11,
            contentLayout: .vertical
        ) { [weak self] in self?.tapFreeFlight() }
        freeFlight.position = CGPoint(
            x: size.width / 2 - totalWidth / 2 + tileSize.width / 2,
            y: rowY
        )
        freeFlight.zPosition = 15
        freeFlight.name = "bentoFreeFlight"
        addChild(freeFlight)

        // Navy shopping-bag glyph — the standard (navy) asset matches the navy
        // label for legible contrast on the gold face.
        let bagIcon = SkySprites.iconNode(
            named: SkySprites.tabShop, fallbackEmoji: "🛒", size: 28, color: SkyColors.onSurface
        )
        let upgrade = SkyChunkyButton(
            title: "UPGRADE",
            icon: bagIcon,
            size: tileSize,
            style: .tertiary,
            cornerRadius: 28,
            labelFontSize: 11,
            contentLayout: .vertical
        ) { [weak self] in self?.tapShop() }
        upgrade.position = CGPoint(
            x: size.width / 2 + totalWidth / 2 - tileSize.width / 2,
            y: rowY
        )
        upgrade.zPosition = 15
        upgrade.name = "bentoUpgrade"
        addChild(upgrade)
    }

    // MARK: - Bottom nav bar

    private func buildNavBar() {
        let bar = SkyTabBar(active: .home, width: size.width, bottomInset: bottomSafeInset)
        // Tap targets sit above the home indicator; the bar's surface fill
        // extends down behind it so the bar is flush with the screen edge.
        bar.position = CGPoint(x: size.width / 2, y: bottomSafeInset + SkyTabBar.barHeight / 2)
        bar.zPosition = 40
        bar.name = "navBar"
        addChild(bar)
    }

    // MARK: - Actions

    private func tapPlay() {
        // SkyChunkyButton.handleTap already plays SFX + haptic.
        SkyNavigator.shared.showMap()
    }

    /// Opens the shop. Invoked by the UPGRADE button's handler; the button's
    /// `handleTap` already plays the SFX + haptic, so this doesn't repeat them.
    private func tapShop() {
        SkyNavigator.shared.showShop()
    }

    /// Opens the world-select overlay. Invoked by the FREE FLIGHT button's
    /// handler, which already plays the SFX + haptic via `handleTap`.
    private func tapFreeFlight() {
        showWorldSelect()
    }

    // MARK: - World select overlay

    private func showWorldSelect() {
        guard worldSelectOverlay == nil else { return }

        let overlay = SKNode()
        overlay.zPosition = 100

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.25), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        dim.name = "worldSelectDim"
        overlay.addChild(dim)

        // Glassmorphic card: Gaussian-blurred snapshot of the sky+clouds behind,
        // tinted with surfaceContainerLowest @ 80%. Capture must happen BEFORE
        // the overlay is added so the card itself isn't included in the snapshot.
        let cardSize = CGSize(width: min(size.width - 40, 340), height: 360)
        let card = SkyGlassCard(
            size: cardSize,
            cornerRadius: 28,
            tint: SkyColors.surfaceContainerLowest,
            tintAlpha: 0.80
        )
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
        card.captureBackdrop(in: self, blurRadius: 20)
        overlay.addChild(card)

        let title = SKLabelNode(text: "Choose a World")
        title.fontName = SkyFonts.headlineName
        title.fontSize = 22
        title.fontColor = SkyColors.skOnSurface
        title.position = CGPoint(x: 0, y: cardSize.height / 2 - 40)
        card.addChild(title)

        let closeX = SKLabelNode(text: "✕")
        closeX.fontName = SkyFonts.headlineName
        closeX.fontSize = 22
        closeX.fontColor = SkyColors.skOnSurfaceVariant
        closeX.position = CGPoint(x: cardSize.width / 2 - 24, y: cardSize.height / 2 - 28)
        closeX.name = "worldSelectClose"
        card.addChild(closeX)

        // Three peer world tiles (SKY-83): City, Mountain, Landing Practice.
        let tileGap: CGFloat = 10
        let tileWidth = (cardSize.width - 24 - 2 * tileGap) / 3
        let tileSize = CGSize(width: tileWidth, height: 150)
        let slotX = tileWidth + tileGap

        // City tile — free (SKY-91 baked card art).
        let city = bakedWorldTile(
            cardAsset: SkySprites.cityCard,
            tileSize: tileSize,
            fallbackTitle: "CITY",
            fallbackSubtitle: "Dawn skyline.",
            fallbackIconAsset: SkySprites.iconWorldCity,
            fallbackEmoji: "🏙",
            fallbackColor: UIColor(hex: 0xFF9A6C)
        )
        city.position = CGPoint(x: -slotX, y: -20)
        city.name = "worldSelectCity"
        card.addChild(city)

        // Mountain tile — free for all players (SKY-91 baked card art).
        let mountain = bakedWorldTile(
            cardAsset: SkySprites.mountainCard,
            tileSize: tileSize,
            fallbackTitle: "MOUNTAIN",
            fallbackSubtitle: "Alpine peaks.",
            fallbackIconAsset: SkySprites.iconWorldMountain,
            fallbackEmoji: "🏔",
            fallbackColor: SkyColors.primary
        )
        mountain.position = CGPoint(x: 0, y: -20)
        mountain.name = "worldSelectMountain"
        card.addChild(mountain)

        // Landing Practice tile — free, no unlock (SKY-83 / SKY-91 baked card art).
        let landing = bakedWorldTile(
            cardAsset: SkySprites.landingPracticeCard,
            tileSize: tileSize,
            fallbackTitle: "RUNWAY CHALLENGE",
            fallbackSubtitle: "Clear for landing.",
            fallbackIconAsset: SkySprites.landingPracticeCard,
            fallbackEmoji: "🛬",
            fallbackColor: UIColor(hex: 0xF3B100)
        )
        landing.position = CGPoint(x: slotX, y: -20)
        landing.name = "worldSelectLanding"
        card.addChild(landing)

        addChild(overlay)
        worldSelectOverlay = overlay

        overlay.alpha = 0
        overlay.run(SKAction.fadeIn(withDuration: 0.2))
    }

    private func worldTile(title: String,
                           subtitle: String,
                           iconAsset: String,
                           iconFallback: String,
                           tileColor: UIColor,
                           tileSize: CGSize = CGSize(width: 120, height: 180)) -> SKNode {
        let container = SKNode()
        let size = tileSize
        // Type scales down with the tile so three-across still fits.
        let compact = size.width < 110

        let bg = SKShapeNode(rectOf: size, cornerRadius: 20)
        bg.fillColor = tileColor
        bg.strokeColor = .clear
        container.addChild(bg)

        // World icon centered between title and subtitle.
        let icon = SkySprites.iconNode(
            named: iconAsset,
            fallbackEmoji: iconFallback,
            size: (size.width * 0.53).rounded(),
            color: SkyColors.onPrimary
        )
        icon.position = CGPoint(x: 0, y: 6)
        container.addChild(icon)

        let titleLabel = SKLabelNode(text: title)
        titleLabel.fontName = SkyFonts.headlineName
        titleLabel.fontSize = compact ? 13 : 16
        titleLabel.fontColor = SkyColors.skOnPrimary
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: size.height / 2 - 22)
        container.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(text: subtitle)
        subtitleLabel.fontName = SkyFonts.bodyName
        subtitleLabel.fontSize = compact ? 10 : 11
        subtitleLabel.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position = CGPoint(x: 0, y: -size.height / 2 + 20)
        container.addChild(subtitleLabel)

        return container
    }

    /// Baked world card tile (SKY-91). City, Mountain, and Landing Practice all
    /// use Stitch card art that bakes in the background color, label,
    /// illustration, and descriptor, so each tile is a single sprite stretched
    /// to the shared slot size. If the art is missing, a programmatic peer tile
    /// is built from the fallback values so the mode stays reachable.
    private func bakedWorldTile(cardAsset: String,
                                tileSize: CGSize,
                                fallbackTitle: String,
                                fallbackSubtitle: String,
                                fallbackIconAsset: String,
                                fallbackEmoji: String,
                                fallbackColor: UIColor) -> SKNode {
        guard let texture = SkySprites.texture(named: cardAsset) else {
            return worldTile(
                title: fallbackTitle,
                subtitle: fallbackSubtitle,
                iconAsset: fallbackIconAsset,
                iconFallback: fallbackEmoji,
                tileColor: fallbackColor,
                tileSize: tileSize
            )
        }
        let container = SKNode()
        let sprite = SKSpriteNode(texture: texture, size: tileSize)
        container.addChild(sprite)
        return container
    }

    private func dismissWorldSelect() {
        guard let overlay = worldSelectOverlay else { return }
        worldSelectOverlay = nil
        overlay.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.15), SKAction.removeFromParent()]))
    }

    // MARK: - Touches

    /// Routes a tap to the world-select overlay (when shown), the chunky PLAY /
    /// FREE FLIGHT / UPGRADE buttons, the settings gear, or the nav bar — in
    /// that priority order, walking up the node tree so taps on a label or icon
    /// still resolve to their button.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let tapped = nodes(at: location)

        // Route overlay taps first.
        if worldSelectOverlay != nil {
            for node in tapped {
                var n: SKNode? = node
                while let current = n {
                    if current.name == "worldSelectClose" || current.name == "worldSelectDim" {
                        dismissWorldSelect()
                        return
                    }
                    if current.name == "worldSelectCity" {
                        dismissWorldSelect()
                        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                        SkyNavigator.shared.showFreeFlightCity()
                        return
                    }
                    if current.name == "worldSelectMountain" {
                        dismissWorldSelect()
                        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                        SkyNavigator.shared.showFreeFlightMountain()
                        return
                    }
                    if current.name == "worldSelectLanding" {
                        dismissWorldSelect()
                        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                        SkyNavigator.shared.showLandingPractice()
                        return
                    }
                    n = current.parent
                }
            }
            return
        }

        // Chunky PLAY button (walk up the tree — tap may hit label/icon).
        for node in tapped {
            var n: SKNode? = node
            while let current = n {
                if let cta = current as? SkyChunkyButton {
                    cta.handleTap()
                    return
                }
                n = current.parent
            }
        }

        // Named nodes: settings gear, nav tabs. (FREE FLIGHT / UPGRADE are now
        // SkyChunkyButtons, handled by the chunky-button walk-up loop above.)
        for node in tapped {
            var n: SKNode? = node
            while let current = n {
                switch current.name {
                case "soundToggle":
                    AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                    SkyHaptics.uiTap()
                    toggleSound()
                    return
                case "badgesButton":
                    AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                    SkyHaptics.uiTap()
                    SkyNavigator.shared.showBadges()
                    return
                default:
                    break
                }
                if let bar = current as? SkyTabBar {
                    bar.handleTap(sceneLocation: location)
                    return
                }
                n = current.parent
            }
        }
    }

    /// SKY-75: settings gear is a single Sound on/off switch — toggling it
    /// flips both the music and SFX flags together so a player who wants
    /// silence gets silence (music, engine ambience, and SFX all off) without
    /// having to mute the device.
    private func toggleSound() {
        // Read both flags — they're persisted independently and can land in
        // a mixed state (e.g. an older install that pre-dates the unified
        // toggle). Treat "sound on" as either flag enabled so the first tap
        // always behaves as a mute when anything is audible.
        let isSoundOn = AudioManager.shared.musicEnabled || AudioManager.shared.sfxEnabled
        let nextState = !isSoundOn
        AudioManager.shared.musicEnabled = nextState
        AudioManager.shared.sfxEnabled = nextState
        if nextState {
            AudioManager.shared.playMusic(SkyMusic.menu)
        }
    }
}

// MARK: - Shared SpriteKit UI components used by many scenes

/// Simple sky gradient background — a tall SKShapeNode with a gradient fill.
/// SpriteKit doesn't support gradients natively, so we compose from horizontal
/// strips of progressively interpolated colors.
final class SKGradientBackgroundNode: SKNode {

    init(size: CGSize, topColor: SKColor, bottomColor: SKColor) {
        super.init()
        build(size: size, top: topColor, bottom: bottomColor)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build(size: CGSize, top: SKColor, bottom: SKColor) {
        // Render a CG gradient into a texture for efficiency.
        let texture = Self.gradientTexture(size: size, top: top, bottom: bottom)
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.anchorPoint = .zero
        sprite.position = .zero
        addChild(sprite)
    }

    static func gradientTexture(size: CGSize, top: SKColor, bottom: SKColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
        return SKTexture(image: image)
    }
}

/// Soft drifting cloud shape used on menu/map backgrounds.
final class MenuCloud: SKNode {
    override init() {
        super.init()
        let baseScale = CGFloat.random(in: 0.7...1.3)
        let tint = SkyColors.skSurface.withAlphaComponent(CGFloat.random(in: 0.6...0.9))

        let positions: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 28), (-18, -4, 22), (18, -4, 22), (-34, 0, 16), (34, 0, 16)
        ]
        for (x, y, r) in positions {
            let puff = SKShapeNode(circleOfRadius: r)
            puff.fillColor = tint
            puff.strokeColor = .clear
            puff.position = CGPoint(x: x, y: y)
            addChild(puff)
        }
        setScale(baseScale)
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }
}

/// Coin balance pill — gold background with the current coin count.
/// Uses the bundled `icon_coin` glyph when available; falls back to 🪙.
final class SkyCoinPill: SKNode {
    private let label: SKLabelNode
    private let icon: SKNode

    init(coins: Int) {
        self.label = SKLabelNode(text: "\(coins)")
        self.icon = SkySprites.iconNode(
            named: SkySprites.iconCoin,
            fallbackEmoji: "🪙",
            size: 18,
            color: SkyColors.onTertiaryContainer
        )
        super.init()

        let pillSize = CGSize(width: 120, height: 36)
        let bg = SKShapeNode(rectOf: pillSize, cornerRadius: 18)
        bg.fillColor = SkyColors.skTertiaryContainer
        bg.strokeColor = .clear
        addChild(bg)

        icon.position = CGPoint(x: -32, y: 0)
        addChild(icon)

        label.fontName = SkyFonts.headlineName
        label.fontSize = 15
        label.fontColor = SkyColors.skOnTertiaryContainer
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 8, y: 0)
        addChild(label)
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func setCoins(_ coins: Int) { label.text = "\(coins)" }
}

/// The primary pill-shaped action button used across all menu scenes.
/// Per DESIGN.md:
///   • Primary CTA: vertical gradient primaryContainer → primary (convex feel).
///   • All styles: soft ambient shadow beneath (onSurface @ 6%, 24px blur).
///   • Full-pill roundedness (height/2).
final class SkyPillButton: SKNode {
    enum Style { case primary, secondary, surface, tertiary, disabled }

    let buttonSize: CGSize
    private let fill: SKSpriteNode
    private let shadow: SKSpriteNode
    private let label: SKLabelNode
    private var coinTitleNode: CoinAmountNode?
    private let handler: () -> Void
    var style: Style

    init(title: String, style: Style, size: CGSize, handler: @escaping () -> Void) {
        self.buttonSize = size
        self.style = style
        self.handler = handler
        let radius = size.height / 2
        self.fill = SKSpriteNode(color: .clear, size: size)
        self.shadow = SkyUIEffects.shadowSprite(size: size, cornerRadius: radius)
        self.label = SKLabelNode(text: title)
        super.init()
        shadow.zPosition = -1
        fill.zPosition = 0
        label.zPosition = 1
        addChild(shadow)
        addChild(fill)
        addChild(label)
        applyStyle()
        configureLabel()
        isUserInteractionEnabled = false
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func setTitle(_ title: String) {
        coinTitleNode?.removeFromParent()
        coinTitleNode = nil
        label.isHidden = false
        label.text = title
    }

    /// Set a title that contains an inline coin icon (e.g. "BUY [coin] 350").
    /// Hides the plain label and adds a `CoinAmountNode` child. The icon and
    /// text colors are derived from the current style.
    func setCoinAmountTitle(prefix: String? = nil, amount: String, fontSize: CGFloat = 16) {
        coinTitleNode?.removeFromParent()
        label.isHidden = true
        let node = CoinAmountNode(
            prefix: prefix,
            amount: amount,
            fontName: SkyFonts.headlineName,
            fontSize: fontSize,
            color: SkyPillButton.labelColor(for: style)
        )
        node.zPosition = 1
        node.position = .zero
        addChild(node)
        coinTitleNode = node
    }

    func setStyle(_ newStyle: Style) {
        self.style = newStyle
        applyStyle()
        configureLabel()
    }

    func handleTap() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyHaptics.uiTap()
        run(SKAction.sequence([
            SKAction.scale(to: 0.96, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.08)
        ]))
        handler()
    }

    private func applyStyle() {
        let radius = buttonSize.height / 2
        // Lighter colour on top, darker on bottom — "convex" feel per spec.
        let (top, bottom): (UIColor, UIColor)
        switch style {
        case .primary:
            top = SkyColors.primaryContainer
            bottom = SkyColors.primary
        case .secondary:
            top = SkyColors.secondaryContainer.lightened(by: 0.10)
            bottom = SkyColors.secondaryContainer
        case .surface:
            top = SkyColors.surfaceContainerLowest
            bottom = SkyColors.surfaceContainerLow
        case .tertiary:
            top = SkyColors.tertiaryContainer.lightened(by: 0.10)
            bottom = SkyColors.tertiaryContainer
        case .disabled:
            top = SkyColors.surfaceContainer
            bottom = SkyColors.surfaceContainer
        }
        fill.texture = SkyUIEffects.gradientTexture(
            size: buttonSize,
            cornerRadius: radius,
            top: top,
            bottom: bottom
        )
        fill.size = buttonSize
    }

    private func configureLabel() {
        label.fontName = SkyFonts.headlineName
        label.fontSize = 16
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = .zero
        label.fontColor = SkyPillButton.labelColor(for: style)
    }

    /// Foreground color the button uses for plain titles in the given style.
    /// Exposed so callers building attributed titles (e.g. with an inline coin
    /// icon) can match the same color the button would have used for text.
    static func labelColor(for style: Style) -> UIColor {
        switch style {
        case .primary:   return SkyColors.skOnPrimary
        case .secondary: return SkyColors.skOnSecondaryContainer
        case .surface:   return SkyColors.skOnSurface
        case .tertiary:  return SkyColors.skOnTertiaryContainer
        case .disabled:  return SkyColors.skOnSurfaceVariant
        }
    }
}

// MARK: - Coin amount node

/// Inline coin-price/reward composition: optional prefix text, then the
/// bundled coin glyph (or 🪙 fallback), then the amount text — all centered
/// horizontally around the node's origin and vertically centered with the
/// surrounding text baseline. Drop in anywhere a coin amount is shown so
/// every screen renders the same coin asset.
final class CoinAmountNode: SKNode {

    private let icon: SKNode
    private let amountLabel: SKLabelNode
    private var prefixLabel: SKLabelNode?
    private let iconSize: CGFloat
    private let spacing: CGFloat
    private let fontName: String
    private let fontSize: CGFloat

    init(prefix: String? = nil,
         amount: String,
         fontName: String,
         fontSize: CGFloat,
         color: UIColor,
         iconAsset: String = SkySprites.iconCoin,
         iconScale: CGFloat = 1.2,
         spacing: CGFloat = 4) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.iconSize = fontSize * iconScale
        self.spacing = spacing

        self.amountLabel = SKLabelNode(text: amount)
        self.icon = SkySprites.iconNode(
            named: iconAsset,
            fallbackEmoji: "🪙",
            size: iconSize,
            color: color
        )

        super.init()

        amountLabel.fontName = fontName
        amountLabel.fontSize = fontSize
        amountLabel.fontColor = color
        amountLabel.verticalAlignmentMode = .center
        amountLabel.horizontalAlignmentMode = .left

        if let prefix = prefix, !prefix.isEmpty {
            let p = SKLabelNode(text: prefix)
            p.fontName = fontName
            p.fontSize = fontSize
            p.fontColor = color
            p.verticalAlignmentMode = .center
            p.horizontalAlignmentMode = .left
            prefixLabel = p
            addChild(p)
        }
        addChild(icon)
        addChild(amountLabel)

        layoutContents()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Update the amount text (e.g. for the level-complete count-up animation
    /// or the in-game coin counter). Re-runs layout so the icon stays
    /// positioned to the left of the (possibly wider) number.
    func setAmount(_ amount: String) {
        amountLabel.text = amount
        layoutContents()
    }

    private func layoutContents() {
        let prefixWidth = prefixLabel?.frame.width ?? 0
        let amountWidth = amountLabel.frame.width
        let segmentCount = (prefixLabel != nil ? 1 : 0) + 2 // (prefix?) + icon + amount
        let totalWidth = prefixWidth + iconSize + amountWidth + spacing * CGFloat(segmentCount - 1)
        var x = -totalWidth / 2

        if let p = prefixLabel {
            p.position = CGPoint(x: x, y: 0)
            x += prefixWidth + spacing
        }

        // SKSprite icons anchor at center — position at icon's center x.
        icon.position = CGPoint(x: x + iconSize / 2, y: 0)
        x += iconSize + spacing

        amountLabel.position = CGPoint(x: x, y: 0)
    }
}

// MARK: - Color lightening helper (used for subtle gradient highlights)

private extension UIColor {
    func lightened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(
            red: min(1, r + amount),
            green: min(1, g + amount),
            blue: min(1, b + amount),
            alpha: a
        )
    }
}
