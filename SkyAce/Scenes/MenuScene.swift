import SpriteKit

/// Landing screen: sky gradient, drifting clouds, animated plane,
/// "SKY ACE" logo, PLAY / FREE FLIGHT / UPGRADE SHOP buttons, and the
/// coin-balance pill + settings gear in the corners.
final class MenuScene: SKScene {

    private var worldSelectOverlay: SKNode?

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        buildGradient()
        buildClouds()
        buildFlyingPlane()
        buildLogo()
        buildButtons()
        buildTopBar()
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

    private func buildFlyingPlane() {
        let plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID)
        plane.zPosition = -30
        plane.setScale(0.9)
        plane.physicsBody = nil
        addChild(plane)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: -80, y: size.height * 0.25))
        path.addCurve(
            to: CGPoint(x: size.width + 80, y: size.height * 0.35),
            controlPoint1: CGPoint(x: size.width * 0.33, y: size.height * 0.15),
            controlPoint2: CGPoint(x: size.width * 0.66, y: size.height * 0.5)
        )

        let follow = SKAction.follow(path.cgPath, asOffset: false, orientToPath: true, duration: 8)
        let reset = SKAction.run { plane.position = CGPoint(x: -80, y: self.size.height * 0.25) }
        plane.run(SKAction.repeatForever(SKAction.sequence([follow, reset])))
    }

    // MARK: - Logo

    private func buildLogo() {
        let logo = SKLabelNode(text: "SKY ACE")
        logo.fontName = SkyFonts.headlineItalicName
        logo.fontSize = 52
        logo.fontColor = SkyColors.skOnPrimary
        logo.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        logo.zPosition = 10

        // Drop shadow.
        let shadow = SKLabelNode(text: "SKY ACE")
        shadow.fontName = SkyFonts.headlineItalicName
        shadow.fontSize = 52
        shadow.fontColor = SkyColors.skOnPrimaryContainer.withAlphaComponent(0.4)
        shadow.position = CGPoint(x: 2, y: -3)
        shadow.zPosition = -1
        logo.addChild(shadow)

        addChild(logo)

        let subtitle = SKLabelNode(text: "Pilot your plane through the skies.")
        subtitle.fontName = SkyFonts.bodyName
        subtitle.fontSize = 14
        subtitle.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.72 - 36)
        subtitle.zPosition = 10
        addChild(subtitle)
    }

    // MARK: - Buttons

    private func buildButtons() {
        let centerX = size.width / 2
        let baseY = size.height * 0.42

        let play = SkyPillButton(
            title: "PLAY",
            style: .primary,
            size: CGSize(width: 240, height: 56)
        ) { [weak self] in self?.tapPlay() }
        play.position = CGPoint(x: centerX, y: baseY)
        play.zPosition = 10
        addChild(play)

        let freeFlight = SkyPillButton(
            title: "FREE FLIGHT",
            style: .secondary,
            size: CGSize(width: 240, height: 56)
        ) { [weak self] in self?.tapFreeFlight() }
        freeFlight.position = CGPoint(x: centerX, y: baseY - 70)
        freeFlight.zPosition = 10
        addChild(freeFlight)

        let shop = SkyPillButton(
            title: "UPGRADE SHOP",
            style: .surface,
            size: CGSize(width: 240, height: 56)
        ) { [weak self] in self?.tapShop() }
        shop.position = CGPoint(x: centerX, y: baseY - 140)
        shop.zPosition = 10
        addChild(shop)
    }

    // MARK: - Top bar

    private func buildTopBar() {
        let coinPill = SkyCoinPill(coins: ProgressManager.shared.coins)
        coinPill.position = CGPoint(x: size.width - 66, y: size.height - 44)
        coinPill.zPosition = 20
        coinPill.name = "coinPill"
        addChild(coinPill)

        let gear = SKLabelNode(text: "⚙")
        gear.fontSize = 28
        gear.fontColor = SkyColors.skOnPrimary
        gear.verticalAlignmentMode = .center
        gear.position = CGPoint(x: 28, y: size.height - 44)
        gear.zPosition = 20
        gear.name = "settingsGear"
        addChild(gear)
    }

    // MARK: - Actions

    private func tapPlay() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyNavigator.shared.showMap()
    }

    private func tapShop() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyNavigator.shared.showShop()
    }

    private func tapFreeFlight() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        showWorldSelect()
    }

    // MARK: - World select overlay

    private func showWorldSelect() {
        guard worldSelectOverlay == nil else { return }

        let overlay = SKNode()
        overlay.zPosition = 100

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.35), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        dim.name = "worldSelectDim"
        overlay.addChild(dim)

        let cardSize = CGSize(width: min(size.width - 40, 340), height: 360)
        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 28)
        card.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.94)
        card.strokeColor = .clear
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
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

        // City tile — free.
        let city = worldTile(
            title: "CITY",
            subtitle: "Dawn skyline.",
            locked: false,
            tileColor: UIColor(hex: 0xFF9A6C)
        )
        city.position = CGPoint(x: -cardSize.width / 4 - 4, y: -20)
        city.name = "worldSelectCity"
        card.addChild(city)

        // Mountain tile — requires full unlock.
        let unlocked = IAPManager.shared.isFullyUnlocked
        let mountain = worldTile(
            title: "MOUNTAIN",
            subtitle: unlocked ? "Alpine peaks." : "Locked",
            locked: !unlocked,
            tileColor: SkyColors.primary
        )
        mountain.position = CGPoint(x: cardSize.width / 4 + 4, y: -20)
        mountain.name = "worldSelectMountain"
        card.addChild(mountain)

        addChild(overlay)
        worldSelectOverlay = overlay

        overlay.alpha = 0
        overlay.run(SKAction.fadeIn(withDuration: 0.2))
    }

    private func worldTile(title: String, subtitle: String, locked: Bool, tileColor: UIColor) -> SKNode {
        let container = SKNode()
        let size = CGSize(width: 120, height: 180)

        let bg = SKShapeNode(rectOf: size, cornerRadius: 20)
        bg.fillColor = tileColor
        bg.strokeColor = .clear
        container.addChild(bg)

        if locked {
            let overlay = SKShapeNode(rectOf: size, cornerRadius: 20)
            overlay.fillColor = UIColor.black.withAlphaComponent(0.5)
            overlay.strokeColor = .clear
            container.addChild(overlay)

            let lock = SKLabelNode(text: "🔒")
            lock.fontSize = 34
            lock.verticalAlignmentMode = .center
            lock.position = CGPoint(x: 0, y: 16)
            container.addChild(lock)

            let unlockBadge = SKShapeNode(rectOf: CGSize(width: 90, height: 26), cornerRadius: 13)
            unlockBadge.fillColor = SkyColors.tertiaryContainer
            unlockBadge.strokeColor = .clear
            unlockBadge.position = CGPoint(x: 0, y: -30)
            container.addChild(unlockBadge)

            let unlockLabel = SKLabelNode(text: "UNLOCK")
            unlockLabel.fontName = SkyFonts.headlineName
            unlockLabel.fontSize = 12
            unlockLabel.fontColor = SkyColors.skOnTertiaryContainer
            unlockLabel.verticalAlignmentMode = .center
            unlockLabel.position = CGPoint(x: 0, y: -30)
            container.addChild(unlockLabel)
        }

        let titleLabel = SKLabelNode(text: title)
        titleLabel.fontName = SkyFonts.headlineName
        titleLabel.fontSize = 16
        titleLabel.fontColor = SkyColors.skOnPrimary
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: size.height / 2 - 22)
        container.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(text: subtitle)
        subtitleLabel.fontName = SkyFonts.bodyName
        subtitleLabel.fontSize = 11
        subtitleLabel.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position = CGPoint(x: 0, y: -size.height / 2 + 20)
        container.addChild(subtitleLabel)

        return container
    }

    private func dismissWorldSelect() {
        guard let overlay = worldSelectOverlay else { return }
        worldSelectOverlay = nil
        overlay.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.15), SKAction.removeFromParent()]))
    }

    // MARK: - Touches

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
                        if IAPManager.shared.isFullyUnlocked {
                            SkyNavigator.shared.showFreeFlightMountain()
                        } else {
                            SkyNavigator.shared.showUnlock()
                        }
                        return
                    }
                    n = current.parent
                }
            }
            return
        }

        // Normal screen taps: dispatched by SkyPillButton directly.
        for node in tapped {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
            if node.name == "settingsGear" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                toggleMusic()
                return
            }
        }
    }

    private func toggleMusic() {
        AudioManager.shared.musicEnabled.toggle()
        if AudioManager.shared.musicEnabled {
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
final class SkyCoinPill: SKNode {
    private let label: SKLabelNode

    init(coins: Int) {
        self.label = SKLabelNode(text: "★ \(coins)")
        super.init()

        let size = CGSize(width: 120, height: 36)
        let bg = SKShapeNode(rectOf: size, cornerRadius: 18)
        bg.fillColor = SkyColors.skTertiaryContainer
        bg.strokeColor = .clear
        addChild(bg)

        label.fontName = SkyFonts.headlineName
        label.fontSize = 15
        label.fontColor = SkyColors.skOnTertiaryContainer
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        addChild(label)
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func setCoins(_ coins: Int) { label.text = "★ \(coins)" }
}

/// The primary pill-shaped action button used across all menu scenes.
final class SkyPillButton: SKNode {
    enum Style { case primary, secondary, surface, tertiary, disabled }

    let buttonSize: CGSize
    private let shape: SKShapeNode
    private let label: SKLabelNode
    private let handler: () -> Void
    var style: Style

    init(title: String, style: Style, size: CGSize, handler: @escaping () -> Void) {
        self.buttonSize = size
        self.style = style
        self.handler = handler
        self.shape = SKShapeNode(rectOf: size, cornerRadius: size.height / 2)
        self.label = SKLabelNode(text: title)
        super.init()
        addChild(shape)
        addChild(label)
        applyStyle()
        configureLabel()
        isUserInteractionEnabled = false
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func setTitle(_ title: String) { label.text = title }

    func setStyle(_ newStyle: Style) {
        self.style = newStyle
        applyStyle()
        configureLabel()
    }

    func handleTap() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        run(SKAction.sequence([
            SKAction.scale(to: 0.96, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.08)
        ]))
        handler()
    }

    private func applyStyle() {
        shape.strokeColor = .clear
        switch style {
        case .primary:
            shape.fillColor = SkyColors.skPrimary
        case .secondary:
            shape.fillColor = SkyColors.skSecondaryContainer
        case .surface:
            shape.fillColor = SkyColors.skSurfaceContainerLowest
        case .tertiary:
            shape.fillColor = SkyColors.skTertiaryContainer
        case .disabled:
            shape.fillColor = SkyColors.skSurfaceContainer
        }
    }

    private func configureLabel() {
        label.fontName = SkyFonts.headlineName
        label.fontSize = 16
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = .zero
        switch style {
        case .primary:   label.fontColor = SkyColors.skOnPrimary
        case .secondary: label.fontColor = SkyColors.skOnSecondaryContainer
        case .surface:   label.fontColor = SkyColors.skOnSurface
        case .tertiary:  label.fontColor = SkyColors.skOnTertiaryContainer
        case .disabled:  label.fontColor = SkyColors.skOnSurfaceVariant
        }
    }
}
