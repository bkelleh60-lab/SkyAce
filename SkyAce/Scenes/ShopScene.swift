import SpriteKit

/// Scrollable upgrade shop. Featured card for the first unlockable upgrade,
/// smaller cards for the rest, a "current plane" stat card, and a paywall
/// overlay for free users.
final class ShopScene: SKScene {

    private let contentNode = SKNode()
    private var contentHeight: CGFloat = 0

    private var lastPanY: CGFloat = 0
    private var scrollVelocity: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0

    private var paywallOverlay: SKNode?

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skSurface
        buildBackground()
        addChild(contentNode)
        buildContent()
        buildTopBar()
        buildTabBar()

        if !IAPManager.shared.isContentUnlocked {
            presentPaywallOverlay()
        }
    }

    // MARK: - Background

    private func buildBackground() {
        let bg = SKSpriteNode(color: SkyColors.skSurface, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        addChild(bg)
    }

    // MARK: - Content

    private struct BuiltCard {
        let node: SKNode
        let height: CGFloat
    }

    /// Constant edge-to-edge spacing between adjacent cards so the rhythm holds
    /// when individual card heights grow to fit wrapped descriptions.
    private let cardSpacing: CGFloat = 20

    private func buildContent() {
        var previousHeight: CGFloat = 0
        var cursorY: CGFloat = 0

        func place(_ built: BuiltCard) {
            if previousHeight == 0 {
                cursorY = 20 + built.height / 2
            } else {
                cursorY += previousHeight / 2 + cardSpacing + built.height / 2
            }
            built.node.position = CGPoint(x: size.width / 2, y: cursorY)
            contentNode.addChild(built.node)
            previousHeight = built.height
        }

        // Current plane card first.
        place(buildCurrentPlaneCard())

        // Featured (first unlockable) upgrade card.
        let featured = firstFeatured()
        if let featured = featured {
            place(buildFeaturedCard(for: featured))
        }

        // Small upgrade cards for the remaining tracks (including fuel).
        let smallKinds = UpgradeKind.allCases.filter { $0 != featured?.kind }
        for kind in smallKinds {
            place(buildSmallUpgradeCard(kind: kind))
        }

        contentHeight = cursorY + previousHeight / 2 + 80
    }

    private func firstFeatured() -> UpgradeState? {
        for kind in [UpgradeKind.engine, .wings, .armor] where kind.isAvailable {
            let state = UpgradeState.current(kind)
            if !state.isMaxed { return state }
        }
        return nil
    }

    // MARK: - Featured card

    private func buildFeaturedCard(for upgrade: UpgradeState) -> BuiltCard {
        let node = SKNode()
        node.name = "featured-\(upgrade.kind.rawValue)"

        let cardWidth = size.width - 40
        let textLeft = -cardWidth / 2 + 100
        let textRight = cardWidth / 2 - 16
        let detailMaxWidth = max(80, textRight - textLeft)

        // Build the wrapped description first so we can size the card around it.
        let detail = SKLabelNode(text: upgrade.kind.description)
        detail.fontName = SkyFonts.bodyName
        detail.fontSize = 12
        detail.fontColor = SkyColors.skOnSurfaceVariant
        detail.horizontalAlignmentMode = .left
        detail.verticalAlignmentMode = .top
        detail.numberOfLines = 0
        detail.lineBreakMode = .byWordWrapping
        detail.preferredMaxLayoutWidth = detailMaxWidth
        let detailHeight = max(14, detail.frame.height)

        // Min height 180 preserves the original visual rhythm for a 1-line
        // description; longer descriptions push the card taller in 14pt steps.
        let cardHeight = max(180, 166 + detailHeight)
        let cardSize = CGSize(width: cardWidth, height: cardHeight)

        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 28)
        card.fillColor = SkyColors.skSurfaceContainerLowest
        card.strokeColor = .clear
        node.addChild(card)

        let iconBG = SKShapeNode(circleOfRadius: 56)
        iconBG.fillColor = SkyColors.skPrimaryContainer
        iconBG.strokeColor = .clear
        iconBG.position = CGPoint(x: -cardWidth / 2 + 30, y: cardHeight / 2 - 60)
        node.addChild(iconBG)

        let icon = SKLabelNode(text: upgrade.kind.iconEmoji)
        icon.fontSize = 58
        icon.verticalAlignmentMode = .center
        icon.horizontalAlignmentMode = .center
        icon.position = iconBG.position
        node.addChild(icon)

        let badge = SKShapeNode(rectOf: CGSize(width: 88, height: 22), cornerRadius: 11)
        badge.fillColor = SkyColors.skTertiaryContainer
        badge.strokeColor = .clear
        badge.position = CGPoint(x: cardWidth / 2 - 60, y: cardHeight / 2 - 22)
        node.addChild(badge)

        let badgeLabel = SKLabelNode(text: "FEATURED")
        badgeLabel.fontName = SkyFonts.headlineName
        badgeLabel.fontSize = 10
        badgeLabel.fontColor = SkyColors.skOnTertiaryContainer
        badgeLabel.verticalAlignmentMode = .center
        badgeLabel.horizontalAlignmentMode = .center
        badgeLabel.position = badge.position
        node.addChild(badgeLabel)

        // Top-anchored: title sits a fixed offset from the top of the card.
        let title = SKLabelNode(text: upgrade.kind.displayName.uppercased())
        title.fontName = SkyFonts.headlineName
        title.fontSize = 20
        title.fontColor = SkyColors.skOnSurface
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: textLeft, y: cardHeight / 2 - 54)
        node.addChild(title)

        detail.position = CGPoint(x: textLeft, y: cardHeight / 2 - 76)
        node.addChild(detail)

        // Bottom-anchored: bar / level / buy keep fixed offsets from the
        // bottom edge so the card grows in the middle when detail wraps.
        let barY = -cardHeight / 2 + 78
        let levelY = -cardHeight / 2 + 58
        let buyY = -cardHeight / 2 + 32

        let barBG = SKShapeNode(rectOf: CGSize(width: 200, height: 8), cornerRadius: 4)
        barBG.fillColor = SkyColors.skSurfaceContainerHigh
        barBG.strokeColor = .clear
        barBG.position = CGPoint(x: -cardWidth / 2 + 200, y: barY)
        node.addChild(barBG)

        let fraction = CGFloat(upgrade.currentLevel) / CGFloat(upgrade.kind.maxLevel)
        let fillWidth = max(2, 200 * fraction)
        let fill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: 8), cornerRadius: 4)
        fill.fillColor = SkyColors.skPrimary
        fill.strokeColor = .clear
        fill.position = CGPoint(x: barBG.position.x - 100 + fillWidth / 2, y: barY)
        node.addChild(fill)

        let levelLabel = SKLabelNode(text: "LEVEL \(upgrade.currentLevel) / \(upgrade.kind.maxLevel)")
        levelLabel.fontName = SkyFonts.headlineName
        levelLabel.fontSize = 10
        levelLabel.fontColor = SkyColors.skOnSurfaceVariant
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: textLeft, y: levelY)
        node.addChild(levelLabel)

        if let cost = upgrade.nextCost {
            let buy = SkyPillButton(title: "BUY  ★ \(cost)", style: affordStyle(cost), size: CGSize(width: 160, height: 40)) { [weak self] in
                self?.attemptBuy(upgrade: upgrade)
            }
            buy.position = CGPoint(x: cardWidth / 2 - 100, y: buyY)
            buy.name = "featuredBuy"
            node.addChild(buy)
        } else {
            let maxed = SKLabelNode(text: "MAX LEVEL")
            maxed.fontName = SkyFonts.headlineName
            maxed.fontSize = 12
            maxed.fontColor = SkyColors.skOnSurfaceVariant
            maxed.verticalAlignmentMode = .center
            maxed.horizontalAlignmentMode = .right
            maxed.position = CGPoint(x: cardWidth / 2 - 32, y: buyY)
            node.addChild(maxed)
        }

        return BuiltCard(node: node, height: cardHeight)
    }

    // MARK: - Small upgrade card

    private func buildSmallUpgradeCard(kind: UpgradeKind) -> BuiltCard {
        let state = UpgradeState.current(kind)
        let node = SKNode()
        node.name = "smallCard-\(kind.rawValue)"

        let cardWidth = size.width - 40
        let textLeft = -cardWidth / 2 + 110

        // The right-side content reserves a different width depending on what
        // is shown (locked vs purchasable vs maxed). Compute the leftmost edge
        // of that content so the description never collides with the button.
        let buttonReservedWidth: CGFloat
        let buttonCenterX: CGFloat
        if !kind.isAvailable {
            buttonReservedWidth = 150
            buttonCenterX = cardWidth / 2 - 92
        } else if state.isMaxed {
            buttonReservedWidth = 60
            buttonCenterX = cardWidth / 2 - 40
        } else {
            buttonReservedWidth = 110
            buttonCenterX = cardWidth / 2 - 80
        }
        let buttonLeftEdge = buttonCenterX - buttonReservedWidth / 2
        let hintMaxWidth = max(60, buttonLeftEdge - textLeft - 12)

        // Wrap the description before sizing the card so we know how tall to
        // make it. The original layout assumed a single line of fontSize 10.
        let hint = SKLabelNode(text: kind.description)
        hint.fontName = SkyFonts.bodyName
        hint.fontSize = 10
        hint.fontColor = SkyColors.skOnSurfaceVariant
        hint.horizontalAlignmentMode = .left
        hint.verticalAlignmentMode = .top
        hint.numberOfLines = 0
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = hintMaxWidth
        let hintHeight = max(10, hint.frame.height)

        // Min height 110 preserves the original look for short descriptions;
        // longer descriptions (e.g. armor) push the card taller so wrapped
        // lines have space to render without clipping or overlap.
        let cardHeight = max(110, 74 + hintHeight)
        let cardSize = CGSize(width: cardWidth, height: cardHeight)

        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 24)
        card.fillColor = SkyColors.skSurfaceContainerLowest
        card.strokeColor = .clear
        node.addChild(card)

        let icon = SKLabelNode(text: kind.iconEmoji)
        icon.fontSize = 40
        icon.verticalAlignmentMode = .center
        icon.horizontalAlignmentMode = .center
        icon.position = CGPoint(x: -cardWidth / 2 + 56, y: 0)
        node.addChild(icon)

        // Top-anchored: title and level row sit a fixed distance from the top.
        let title = SKLabelNode(text: kind.displayName)
        title.fontName = SkyFonts.headlineName
        title.fontSize = 16
        title.fontColor = SkyColors.skOnSurface
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: textLeft, y: cardHeight / 2 - 35)
        node.addChild(title)

        let level = SKLabelNode(text: "LEVEL \(state.currentLevel) / \(kind.maxLevel)")
        level.fontName = SkyFonts.bodyMediumName
        level.fontSize = 11
        level.fontColor = SkyColors.skOnSurfaceVariant
        level.horizontalAlignmentMode = .left
        level.verticalAlignmentMode = .center
        level.position = CGPoint(x: textLeft, y: cardHeight / 2 - 55)
        node.addChild(level)

        // Wrapped hint hangs from a fixed distance below the level row.
        hint.position = CGPoint(x: textLeft, y: cardHeight / 2 - 66)
        node.addChild(hint)

        // Button vertically centered on the card.
        if !kind.isAvailable {
            let soon = SkyPillButton(title: "🔒 COMING SOON", style: .disabled, size: CGSize(width: 150, height: 36)) { }
            soon.position = CGPoint(x: buttonCenterX, y: 0)
            node.addChild(soon)
        } else if state.isMaxed {
            let maxed = SKLabelNode(text: "MAX")
            maxed.fontName = SkyFonts.headlineName
            maxed.fontSize = 12
            maxed.fontColor = SkyColors.skOnSurfaceVariant
            maxed.verticalAlignmentMode = .center
            maxed.horizontalAlignmentMode = .center
            maxed.position = CGPoint(x: buttonCenterX, y: 0)
            node.addChild(maxed)
        } else if let cost = state.nextCost {
            let button = SkyPillButton(title: "★ \(cost)", style: affordStyle(cost), size: CGSize(width: 110, height: 36)) { [weak self] in
                self?.attemptBuy(upgrade: state)
            }
            button.position = CGPoint(x: buttonCenterX, y: 0)
            button.name = "smallBuy-\(kind.rawValue)"
            node.addChild(button)
        }

        return BuiltCard(node: node, height: cardHeight)
    }

    private func affordStyle(_ cost: Int) -> SkyPillButton.Style {
        return ProgressManager.shared.coins >= cost ? .tertiary : .disabled
    }

    // MARK: - Current plane card

    private func buildCurrentPlaneCard() -> BuiltCard {
        let plane = PlaneCatalog.plane(forID: ProgressManager.shared.selectedPlaneID)
        let node = SKNode()

        let cardSize = CGSize(width: size.width - 40, height: 170)
        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 28)
        card.fillColor = SkyColors.skSurfaceContainerLow
        card.strokeColor = .clear
        node.addChild(card)

        let title = SKLabelNode(text: "CURRENT PLANE")
        title.fontName = SkyFonts.headlineName
        title.fontSize = 11
        title.fontColor = SkyColors.skOnSurfaceVariant
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: -cardSize.width / 2 + 20, y: cardSize.height / 2 - 22)
        node.addChild(title)

        let preview = PlaneNode(planeID: plane.id)
        preview.physicsBody = nil
        preview.setScale(0.9)
        preview.position = CGPoint(x: -cardSize.width / 2 + 70, y: 0)
        node.addChild(preview)

        let name = SKLabelNode(text: plane.name)
        name.fontName = SkyFonts.headlineName
        name.fontSize = 18
        name.fontColor = SkyColors.skOnSurface
        name.horizontalAlignmentMode = .left
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: -cardSize.width / 2 + 130, y: 22)
        node.addChild(name)

        // 3 stat bars.
        let stats: [(String, Int)] = [
            ("SPEED",    UpgradeState.current(.engine).currentLevel + 2),
            ("ARMOR",    UpgradeState.current(.armor).currentLevel + 1),
            ("HANDLING", UpgradeState.current(.wings).currentLevel + 2)
        ]
        for (index, (label, filled)) in stats.enumerated() {
            let row = statBar(label: label, filled: filled)
            row.position = CGPoint(x: -cardSize.width / 2 + 130, y: 0 - CGFloat(index) * 18)
            node.addChild(row)
        }

        return BuiltCard(node: node, height: cardSize.height)
    }

    private func statBar(label: String, filled: Int) -> SKNode {
        let container = SKNode()
        let labelNode = SKLabelNode(text: label)
        labelNode.fontName = SkyFonts.headlineName
        labelNode.fontSize = 9
        labelNode.fontColor = SkyColors.skOnSurfaceVariant
        labelNode.horizontalAlignmentMode = .left
        labelNode.verticalAlignmentMode = .center
        labelNode.position = CGPoint(x: 0, y: 0)
        container.addChild(labelNode)

        let baseX: CGFloat = 60
        for i in 0..<5 {
            let segment = SKShapeNode(rectOf: CGSize(width: 18, height: 6), cornerRadius: 3)
            segment.fillColor = (i < filled) ? SkyColors.skPrimary : SkyColors.skSurfaceContainerHigh
            segment.strokeColor = .clear
            segment.position = CGPoint(x: baseX + CGFloat(i) * 22, y: 0)
            container.addChild(segment)
        }
        return container
    }

    // MARK: - Top/tab bars

    private func buildTopBar() {
        let back = SKLabelNode(text: "‹")
        back.fontName = SkyFonts.headlineName
        back.fontSize = 30
        back.fontColor = SkyColors.skOnSurface
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .center
        back.position = CGPoint(x: 24, y: size.height - 44)
        back.zPosition = 200
        back.name = "shopBack"
        addChild(back)

        let title = SKLabelNode(text: "SHOP")
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
        let bar = SkyTabBar(active: .shop, width: size.width)
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        bar.position = CGPoint(x: size.width / 2, y: bottomInset + SkyTabBar.barHeight / 2)
        bar.zPosition = 200
        addChild(bar)
    }

    // MARK: - Paywall overlay

    private func presentPaywallOverlay() {
        let overlay = SKNode()
        overlay.zPosition = 300

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.25), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        overlay.addChild(dim)

        let card = SKShapeNode(rectOf: CGSize(width: size.width - 60, height: 260), cornerRadius: 28)
        card.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.98)
        card.strokeColor = .clear
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(card)

        let title = SKLabelNode(text: "Unlock The Shop")
        title.fontName = SkyFonts.headlineName
        title.fontSize = 22
        title.fontColor = SkyColors.skOnSurface
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        overlay.addChild(title)

        let body = SKLabelNode(text: "Get the upgrade shop, all 10 levels,")
        body.fontName = SkyFonts.bodyName
        body.fontSize = 13
        body.fontColor = SkyColors.skOnSurfaceVariant
        body.position = CGPoint(x: size.width / 2, y: size.height / 2 + 36)
        overlay.addChild(body)

        let body2 = SKLabelNode(text: "and every plane — one fair price.")
        body2.fontName = SkyFonts.bodyName
        body2.fontSize = 13
        body2.fontColor = SkyColors.skOnSurfaceVariant
        body2.position = CGPoint(x: size.width / 2, y: size.height / 2 + 18)
        overlay.addChild(body2)

        let unlock = SkyPillButton(
            title: "UNLOCK  \(IAPManager.shared.displayPrice)",
            style: .tertiary,
            size: CGSize(width: 240, height: 54)
        ) { [weak self] in
            self?.handleUnlockTap()
        }
        unlock.position = CGPoint(x: size.width / 2, y: size.height / 2 - 24)
        unlock.name = "paywallUnlock"
        overlay.addChild(unlock)

        let back = SKLabelNode(text: "Back to menu")
        back.fontName = SkyFonts.bodyMediumName
        back.fontSize = 13
        back.fontColor = SkyColors.skOnSurfaceVariant
        back.position = CGPoint(x: size.width / 2, y: size.height / 2 - 76)
        back.name = "paywallBack"
        overlay.addChild(back)

        addChild(overlay)
        paywallOverlay = overlay
    }

    private func handleUnlockTap() {
        SkyNavigator.shared.showUnlock()
    }

    // MARK: - Scroll

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        guard abs(scrollVelocity) > 0.5 else { return }
        contentNode.position.y = clampOffset(contentNode.position.y + scrollVelocity * CGFloat(delta))
        scrollVelocity *= 0.92
    }

    private func clampOffset(_ y: CGFloat) -> CGFloat {
        let maxY: CGFloat = 0
        let minY: CGFloat = -(contentHeight - size.height + 80)
        if minY > maxY { return 0 }
        return min(maxY, max(minY, y))
    }

    // MARK: - Buying

    private func attemptBuy(upgrade: UpgradeState) {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        guard upgrade.kind.isAvailable else { return }
        if !IAPManager.shared.isContentUnlocked {
            SkyNavigator.shared.showUnlock()
            return
        }
        guard let cost = upgrade.nextCost else { return }
        guard ProgressManager.shared.spendCoins(cost) else {
            // Not enough — shake toolbar, spec doesn't require a specific UI.
            return
        }
        ProgressManager.shared.setUpgradeLevel(upgrade.currentLevel + 1, for: upgrade.kind.rawValue)
        AudioManager.shared.playSFX(SkySFX.win, on: self)
        // Refresh by re-presenting the scene — simpler than partial rebuilds.
        SkyNavigator.shared.showShop()
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        lastPanY = touch.location(in: self).y
        scrollVelocity = 0

        // Overlay taps take priority.
        if let overlay = paywallOverlay {
            for node in overlay.nodes(at: touch.location(in: overlay)) {
                if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                    button.handleTap()
                    return
                }
                if node.name == "paywallBack" {
                    AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                    SkyNavigator.shared.showMenu()
                    return
                }
            }
            return
        }

        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if node.name == "shopBack" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                SkyNavigator.shared.showMenu()
                return
            }
            if let bar = (node as? SkyTabBar) ?? (node.parent as? SkyTabBar) {
                bar.handleTap(sceneLocation: touch.location(in: self))
                return
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard paywallOverlay == nil, let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let dy = y - lastPanY
        lastPanY = y
        contentNode.position.y = clampOffset(contentNode.position.y + dy)
        scrollVelocity = dy * 60
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard paywallOverlay == nil, let touch = touches.first else { return }
        guard abs(scrollVelocity) < 80 else { return }
        // Shop cards have button children — route taps to pill buttons.
        let p = touch.location(in: contentNode)
        for node in contentNode.nodes(at: p) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
        }
    }
}
