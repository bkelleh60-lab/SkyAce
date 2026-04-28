import SpriteKit

/// Plane carousel. Dark showcase card, ‹ dots ›, swipe support, and a
/// FLY!/BUY button at the bottom depending on ownership.
final class HangarScene: SKScene {

    private var currentIndex: Int = 0
    private var showcase: SKNode!
    private var nameLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var flyButton: SkyPillButton!
    private var dotsContainer: SKNode!
    private var previewPlane: PlaneNode?

    // Swipe
    private var swipeStartX: CGFloat = 0
    private var swipeActive: Bool = false

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skSurface

        // Determine starting index from the selected plane.
        currentIndex = PlaneCatalog.all.firstIndex(where: { $0.id == ProgressManager.shared.selectedPlaneID }) ?? 0

        buildBackground()
        buildShowcase()
        buildNavArrows()
        buildDots()
        buildInfo()
        buildActionButton()
        buildTopBar()
        buildTabBar()
        refresh()
    }

    // MARK: - Background

    private func buildBackground() {
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: size, top: SkyColors.skSurfaceContainer, bottom: SkyColors.skSurface
        )
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        addChild(bg)
    }

    // MARK: - Showcase card

    private func buildShowcase() {
        let container = SKNode()
        container.zPosition = 5
        container.position = CGPoint(x: size.width / 2, y: size.height * 0.6)

        let cardSize = CGSize(width: size.width - 60, height: 280)
        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 36)
        card.fillColor = SkyColors.skOnSurface.withAlphaComponent(0.9)
        card.strokeColor = .clear
        container.addChild(card)

        let wrench = SKLabelNode(text: "🔧")
        wrench.fontSize = 20
        wrench.verticalAlignmentMode = .center
        wrench.horizontalAlignmentMode = .center
        wrench.position = CGPoint(x: cardSize.width / 2 - 30, y: cardSize.height / 2 - 30)
        container.addChild(wrench)

        addChild(container)
        showcase = container
    }

    // MARK: - Nav arrows

    private func buildNavArrows() {
        let left = SKLabelNode(text: "‹")
        left.fontName = SkyFonts.headlineName
        left.fontSize = 44
        left.fontColor = SkyColors.skOnSurface
        left.verticalAlignmentMode = .center
        left.horizontalAlignmentMode = .center
        left.position = CGPoint(x: 32, y: size.height * 0.6)
        left.zPosition = 10
        left.name = "hangarLeft"
        addChild(left)

        let right = SKLabelNode(text: "›")
        right.fontName = SkyFonts.headlineName
        right.fontSize = 44
        right.fontColor = SkyColors.skOnSurface
        right.verticalAlignmentMode = .center
        right.horizontalAlignmentMode = .center
        right.position = CGPoint(x: size.width - 32, y: size.height * 0.6)
        right.zPosition = 10
        right.name = "hangarRight"
        addChild(right)
    }

    // MARK: - Dots

    private func buildDots() {
        dotsContainer = SKNode()
        dotsContainer.position = CGPoint(x: size.width / 2, y: size.height * 0.6 - 180)
        dotsContainer.zPosition = 10
        addChild(dotsContainer)
    }

    private func refreshDots() {
        dotsContainer.removeAllChildren()
        let count = PlaneCatalog.all.count
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(count - 1) * spacing
        for i in 0..<count {
            let isActive = i == currentIndex
            let size: CGSize = isActive ? CGSize(width: 18, height: 6) : CGSize(width: 6, height: 6)
            let dot = SKShapeNode(rectOf: size, cornerRadius: 3)
            dot.fillColor = isActive ? SkyColors.skPrimary : SkyColors.skOnSurfaceVariant.withAlphaComponent(0.35)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: -totalWidth / 2 + CGFloat(i) * spacing, y: 0)
            dotsContainer.addChild(dot)
        }
    }

    // MARK: - Info labels

    private func buildInfo() {
        nameLabel = SKLabelNode(text: "")
        nameLabel.fontName = SkyFonts.headlineName
        nameLabel.fontSize = 32
        nameLabel.fontColor = SkyColors.skOnSurface
        nameLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.6 - 230)
        nameLabel.zPosition = 10
        addChild(nameLabel)

        subtitleLabel = SKLabelNode(text: "")
        subtitleLabel.fontName = SkyFonts.bodyName
        subtitleLabel.fontSize = 13
        subtitleLabel.fontColor = SkyColors.skOnSurfaceVariant
        subtitleLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.6 - 256)
        subtitleLabel.zPosition = 10
        addChild(subtitleLabel)
    }

    // MARK: - Action button

    private func buildActionButton() {
        flyButton = SkyPillButton(title: "FLY!", style: .primary, size: CGSize(width: 260, height: 56)) { [weak self] in
            self?.handlePrimaryAction()
        }
        flyButton.position = CGPoint(x: size.width / 2, y: 130)
        flyButton.zPosition = 20
        addChild(flyButton)
    }

    // MARK: - Top / tab bars

    private func buildTopBar() {
        let back = SKLabelNode(text: "‹")
        back.fontName = SkyFonts.headlineName
        back.fontSize = 30
        back.fontColor = SkyColors.skOnSurface
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .center
        back.position = CGPoint(x: 24, y: size.height - 44)
        back.zPosition = 200
        back.name = "hangarBack"
        addChild(back)

        let title = SKLabelNode(text: "HANGAR")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 20
        title.fontColor = SkyColors.skOnSurface
        title.position = CGPoint(x: size.width / 2, y: size.height - 44)
        title.zPosition = 200
        addChild(title)

        let pill = SkyCoinPill(coins: ProgressManager.shared.coins)
        pill.position = CGPoint(x: size.width - 66, y: size.height - 44)
        pill.zPosition = 200
        addChild(pill)
    }

    private func buildTabBar() {
        let bar = SkyTabBar(active: .hangar, width: size.width)
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        bar.position = CGPoint(x: size.width / 2, y: bottomInset + SkyTabBar.barHeight / 2)
        bar.zPosition = 200
        addChild(bar)
    }

    // MARK: - State refresh

    private func refresh() {
        let plane = PlaneCatalog.all[currentIndex]
        nameLabel.text = plane.name
        subtitleLabel.text = plane.subtitle
        refreshDots()
        refreshShowcaseSprite(for: plane)

        let owned = ProgressManager.shared.ownsPlane(plane.id)
        let selected = ProgressManager.shared.selectedPlaneID == plane.id

        if owned {
            flyButton.setTitle(selected ? "FLY!" : "SELECT")
            flyButton.setStyle(.primary)
        } else if plane.requiresFullUnlock && !IAPManager.shared.isContentUnlocked {
            flyButton.setTitle("UNLOCK GAME")
            flyButton.setStyle(.tertiary)
        } else if ProgressManager.shared.coins >= plane.cost {
            flyButton.setTitle("★ \(plane.cost) COINS")
            flyButton.setStyle(.tertiary)
        } else {
            flyButton.setTitle("NOT ENOUGH COINS")
            flyButton.setStyle(.disabled)
        }
    }

    private func refreshShowcaseSprite(for plane: Plane) {
        previewPlane?.removeFromParent()
        let preview = PlaneNode(planeID: plane.id)
        preview.physicsBody = nil
        preview.setScale(2.1)
        preview.position = .zero
        showcase.addChild(preview)
        previewPlane = preview
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        let plane = PlaneCatalog.all[currentIndex]
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)

        if ProgressManager.shared.ownsPlane(plane.id) {
            // Select + fly if the selected plane matches, otherwise just select.
            if ProgressManager.shared.selectedPlaneID != plane.id {
                ProgressManager.shared.selectedPlaneID = plane.id
                refresh()
                return
            }
            SkyNavigator.shared.showMap()
            return
        }

        if plane.requiresFullUnlock && !IAPManager.shared.isContentUnlocked {
            SkyNavigator.shared.showUnlock()
            return
        }

        #if DEBUG
        if debugUnlockAllContent {
            ProgressManager.shared.purchasePlane(plane.id)
            ProgressManager.shared.selectedPlaneID = plane.id
            refresh()
            return
        }
        #endif

        if ProgressManager.shared.spendCoins(plane.cost) {
            ProgressManager.shared.purchasePlane(plane.id)
            ProgressManager.shared.selectedPlaneID = plane.id
            refresh()
        }
    }

    private func paginate(delta: Int) {
        let count = PlaneCatalog.all.count
        currentIndex = (currentIndex + delta + count) % count
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        refresh()
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        swipeStartX = touch.location(in: self).x
        swipeActive = true

        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if node.name == "hangarBack" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                SkyNavigator.shared.showMenu()
                return
            }
            if node.name == "hangarLeft"  { paginate(delta: -1); swipeActive = false; return }
            if node.name == "hangarRight" { paginate(delta: +1); swipeActive = false; return }
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                swipeActive = false
                return
            }
            if let bar = (node as? SkyTabBar) ?? (node.parent as? SkyTabBar) {
                bar.handleTap(sceneLocation: touch.location(in: self))
                swipeActive = false
                return
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard swipeActive, let touch = touches.first else { return }
        let dx = touch.location(in: self).x - swipeStartX
        if dx > 50 { paginate(delta: -1) }
        else if dx < -50 { paginate(delta: +1) }
        swipeActive = false
    }
}
