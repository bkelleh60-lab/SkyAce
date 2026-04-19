import SpriteKit

/// Vertical-scrolling level select. Nodes connected by a dashed curved
/// path, alternating left/right offsets, with four visual states:
///   - completed (gold filled + checkmark badge)
///   - active    (large primary + info card + FLY NOW button + pulse ring)
///   - progression-locked (grayscale + lock badge)
///   - paywall-locked     (grayscale + gold UNLOCK badge, taps → Unlock)
final class MapScene: SKScene {

    private let contentNode = SKNode()
    private var contentHeight: CGFloat = 0

    // Pan-scroll state
    private var lastPanY: CGFloat = 0
    private var scrollVelocity: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0

    // Derived
    private var activeLevelID: Int { findActiveLevelID() }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        buildBackground()
        addChild(contentNode)
        buildLevelList()
        buildTopBar()
        buildTabBar()
        // Scroll to the active level on entry.
        DispatchQueue.main.async { [weak self] in
            self?.scrollToActive()
        }
    }

    // MARK: - Background

    private func buildBackground() {
        let gradient = SKGradientBackgroundNode(
            size: size, topColor: SkyColors.skPrimary, bottomColor: SkyColors.skPrimaryContainer
        )
        gradient.zPosition = -100
        addChild(gradient)

        // Drifting cloud silhouettes.
        for _ in 0..<6 {
            let cloud = MenuCloud()
            cloud.alpha = 0.5
            cloud.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.1...size.height * 0.9)
            )
            cloud.zPosition = -50
            addChild(cloud)
            let speed = CGFloat.random(in: 10...25)
            let distance = size.width + 200
            let dur = TimeInterval(distance / speed)
            cloud.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: -distance, y: 0, duration: dur),
                SKAction.run { cloud.position = CGPoint(x: self.size.width + 80, y: CGFloat.random(in: self.size.height * 0.1...self.size.height * 0.9)) }
            ])))
        }
    }

    // MARK: - Level list

    private func buildLevelList() {
        let nodeSpacing: CGFloat = 150
        let topPadding: CGFloat = 120
        let bottomPadding: CGFloat = 120

        let centerX = size.width / 2

        // Path — dashed curve connecting each level node.
        let path = UIBezierPath()
        for (index, challenge) in ChallengeCatalog.all.enumerated() {
            let xOffset: CGFloat = (index % 2 == 0) ? -40 : 40
            let y = bottomPadding + CGFloat(index) * nodeSpacing
            let point = CGPoint(x: centerX + xOffset, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                let prevOffset: CGFloat = ((index - 1) % 2 == 0) ? -40 : 40
                let prevY = bottomPadding + CGFloat(index - 1) * nodeSpacing
                let prev = CGPoint(x: centerX + prevOffset, y: prevY)
                let control = CGPoint(x: (prev.x + point.x) / 2, y: (prev.y + point.y) / 2 + 30)
                path.addQuadCurve(to: point, controlPoint: control)
            }

            // Level node
            let state = levelState(for: challenge)
            let node = makeLevelNode(for: challenge, state: state, isActive: challenge.id == activeLevelID && state == .active)
            node.position = point
            node.zPosition = 10
            contentNode.addChild(node)
        }

        let dashedLine = SKShapeNode(path: path.cgPath)
        dashedLine.strokeColor = SkyColors.skPrimaryFixed
        dashedLine.lineWidth = 6
        dashedLine.lineCap = .round
        dashedLine.fillColor = .clear
        dashedLine.zPosition = 5

        // Dashed effect via CGPath.copy(dashingWithPhase:lengths:)
        let dashedPath = path.cgPath.copy(dashingWithPhase: 0, lengths: [12, 8])
        dashedLine.path = dashedPath
        contentNode.addChild(dashedLine)

        contentHeight = bottomPadding + CGFloat(ChallengeCatalog.all.count) * nodeSpacing + topPadding
    }

    enum LevelState { case completed, active, progressionLocked, paywallLocked }

    private func levelState(for challenge: Challenge) -> LevelState {
        let completed = ProgressManager.shared.isLevelCompleted(challenge.id)
        let progression = ProgressManager.shared.isLevelProgressionUnlocked(challenge.id)
        let paywallOK = !challenge.requiresFullUnlock || IAPManager.shared.isFullyUnlocked

        if completed { return .completed }
        if !paywallOK { return .paywallLocked }
        if !progression { return .progressionLocked }
        return .active
    }

    private func findActiveLevelID() -> Int {
        for challenge in ChallengeCatalog.all {
            if levelState(for: challenge) == .active { return challenge.id }
        }
        return 1
    }

    private func makeLevelNode(for challenge: Challenge, state: LevelState, isActive: Bool) -> SKNode {
        let container = SKNode()
        container.name = "level-\(challenge.id)"

        let circleRadius: CGFloat = (state == .active) ? 32 : (state == .completed ? 24 : 20)
        let circle = SKShapeNode(circleOfRadius: circleRadius)
        circle.strokeColor = .clear

        switch state {
        case .completed:
            circle.fillColor = SkyColors.skTertiaryContainer
            let star = SKLabelNode(text: "★")
            star.fontName = SkyFonts.headlineName
            star.fontSize = 20
            star.fontColor = SkyColors.skOnTertiaryContainer
            star.verticalAlignmentMode = .center
            star.horizontalAlignmentMode = .center
            container.addChild(star)

            let badge = SKShapeNode(rectOf: CGSize(width: 130, height: 26), cornerRadius: 13)
            badge.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.9)
            badge.strokeColor = .clear
            badge.position = CGPoint(x: 80, y: 0)
            container.addChild(badge)

            let label = SKLabelNode(text: "✓ COMPLETED")
            label.fontName = SkyFonts.headlineName
            label.fontSize = 11
            label.fontColor = SkyColors.skOnSurface
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 80, y: 0)
            container.addChild(label)

        case .active:
            circle.fillColor = SkyColors.skPrimary
            let idLabel = SKLabelNode(text: "\(challenge.id)")
            idLabel.fontName = SkyFonts.headlineItalicName
            idLabel.fontSize = 28
            idLabel.fontColor = SkyColors.skOnPrimary
            idLabel.verticalAlignmentMode = .center
            idLabel.horizontalAlignmentMode = .center
            container.addChild(idLabel)

            // Pulse ring
            let pulse = SKShapeNode(circleOfRadius: circleRadius + 6)
            pulse.strokeColor = SkyColors.skPrimaryFixed
            pulse.lineWidth = 3
            pulse.fillColor = .clear
            pulse.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.group([SKAction.scale(to: 1.25, duration: 1.0), SKAction.fadeAlpha(to: 0.0, duration: 1.0)]),
                SKAction.run { pulse.setScale(1.0); pulse.alpha = 1.0 }
            ])))
            container.addChild(pulse)

            if isActive { addActiveInfoCard(challenge: challenge, to: container) }

        case .progressionLocked:
            circle.fillColor = SkyColors.skSurfaceContainerHigh
            let lock = SKLabelNode(text: "🔒")
            lock.fontSize = 16
            lock.verticalAlignmentMode = .center
            lock.horizontalAlignmentMode = .center
            container.addChild(lock)

        case .paywallLocked:
            circle.fillColor = SkyColors.skSurfaceContainerHigh
            let lock = SKLabelNode(text: "🔒")
            lock.fontSize = 16
            lock.verticalAlignmentMode = .center
            lock.horizontalAlignmentMode = .center
            container.addChild(lock)

            let badge = SKShapeNode(rectOf: CGSize(width: 90, height: 26), cornerRadius: 13)
            badge.fillColor = SkyColors.skTertiaryContainer
            badge.strokeColor = .clear
            badge.position = CGPoint(x: 72, y: 0)
            container.addChild(badge)

            let unlock = SKLabelNode(text: "UNLOCK")
            unlock.fontName = SkyFonts.headlineName
            unlock.fontSize = 11
            unlock.fontColor = SkyColors.skOnTertiaryContainer
            unlock.verticalAlignmentMode = .center
            unlock.horizontalAlignmentMode = .center
            unlock.position = CGPoint(x: 72, y: 0)
            container.addChild(unlock)
        }

        container.insertChild(circle, at: 0)
        return container
    }

    private func addActiveInfoCard(challenge: Challenge, to parent: SKNode) {
        let cardSize = CGSize(width: 260, height: 130)
        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 24)
        card.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.96)
        card.strokeColor = .clear
        card.position = CGPoint(x: 0, y: -90)
        parent.addChild(card)

        let chapter = SKLabelNode(text: "LEVEL \(challenge.id) — \(challenge.chapter.title.uppercased())")
        chapter.fontName = SkyFonts.headlineName
        chapter.fontSize = 11
        chapter.fontColor = SkyColors.skOnSurfaceVariant
        chapter.verticalAlignmentMode = .center
        chapter.horizontalAlignmentMode = .center
        chapter.position = CGPoint(x: 0, y: 42)
        card.addChild(chapter)

        let name = SKLabelNode(text: challenge.name)
        name.fontName = SkyFonts.headlineName
        name.fontSize = 20
        name.fontColor = SkyColors.skOnSurface
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .center
        name.position = CGPoint(x: 0, y: 18)
        card.addChild(name)

        let reward = SKLabelNode(text: "REWARD: ★ \(challenge.reward)")
        reward.fontName = SkyFonts.bodyMediumName
        reward.fontSize = 12
        reward.fontColor = SkyColors.skOnTertiaryContainer
        reward.verticalAlignmentMode = .center
        reward.horizontalAlignmentMode = .center
        reward.position = CGPoint(x: 0, y: -4)
        card.addChild(reward)

        let fly = SkyPillButton(title: "FLY NOW", style: .primary, size: CGSize(width: 160, height: 38)) {
            SkyNavigator.shared.showGame(challenge: challenge)
        }
        fly.position = CGPoint(x: 0, y: -32)
        fly.name = "flyNow-\(challenge.id)"
        card.addChild(fly)
    }

    // MARK: - Top / tab bars

    private func buildTopBar() {
        let back = SKLabelNode(text: "‹")
        back.fontName = SkyFonts.headlineName
        back.fontSize = 30
        back.fontColor = SkyColors.skOnPrimary
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .center
        back.position = CGPoint(x: 24, y: size.height - 44)
        back.zPosition = 200
        back.name = "mapBack"
        addChild(back)

        let title = SKLabelNode(text: "SKY ACE")
        title.fontName = SkyFonts.headlineItalicName
        title.fontSize = 22
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: size.width / 2, y: size.height - 44)
        title.zPosition = 200
        title.verticalAlignmentMode = .center
        addChild(title)

        let pill = SkyCoinPill(coins: ProgressManager.shared.coins)
        pill.position = CGPoint(x: size.width - 66, y: size.height - 44)
        pill.zPosition = 200
        addChild(pill)
    }

    private func buildTabBar() {
        let bar = SkyTabBar(active: .missions)
        bar.position = CGPoint(x: size.width / 2, y: 44)
        bar.zPosition = 200
        addChild(bar)
    }

    // MARK: - Scroll

    private func scrollToActive() {
        let nodeSpacing: CGFloat = 150
        let bottomPadding: CGFloat = 120
        let activeIndex = max(0, activeLevelID - 1)
        let targetY = bottomPadding + CGFloat(activeIndex) * nodeSpacing
        let desiredOffset = -(targetY - size.height / 2)
        contentNode.position.y = clampOffset(desiredOffset)
    }

    private func clampOffset(_ y: CGFloat) -> CGFloat {
        // Keep at least top padding visible.
        let maxY: CGFloat = 0
        let minY: CGFloat = -(contentHeight - size.height)
        if minY > maxY { return 0 }
        return min(maxY, max(minY, y))
    }

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        guard abs(scrollVelocity) > 0.5 else { return }
        contentNode.position.y = clampOffset(contentNode.position.y + scrollVelocity * CGFloat(delta))
        scrollVelocity *= 0.92
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        lastPanY = touch.location(in: self).y
        scrollVelocity = 0

        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if node.name == "mapBack" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                SkyNavigator.shared.showMenu()
                return
            }
            if let bar = (node as? SkyTabBar) ?? (node.parent as? SkyTabBar) {
                bar.handleTap(at: touch.location(in: bar))
                return
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let dy = y - lastPanY
        lastPanY = y
        contentNode.position.y = clampOffset(contentNode.position.y + dy)
        scrollVelocity = dy * 60
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: contentNode)
        let tapped = contentNode.nodes(at: location)

        // If the gesture was essentially a tap (no scroll), route level / button.
        if abs(scrollVelocity) < 80 {
            for node in tapped {
                var n: SKNode? = node
                while let current = n {
                    if let name = current.name {
                        if name.hasPrefix("flyNow-") {
                            if let button = (current as? SkyPillButton) { button.handleTap(); return }
                        }
                        if name.hasPrefix("level-") {
                            let idString = name.replacingOccurrences(of: "level-", with: "")
                            if let id = Int(idString), let challenge = ChallengeCatalog.challenge(forID: id) {
                                routeLevelTap(challenge)
                                return
                            }
                        }
                    }
                    n = current.parent
                }
            }
        }
    }

    private func routeLevelTap(_ challenge: Challenge) {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        let state = levelState(for: challenge)
        switch state {
        case .active, .completed:
            SkyNavigator.shared.showGame(challenge: challenge)
        case .paywallLocked:
            SkyNavigator.shared.showUnlock()
        case .progressionLocked:
            // Shake ding — no navigation.
            break
        }
    }
}

// Convenience — SpriteKit lacks insertChild(at:).
private extension SKNode {
    func insertChild(_ node: SKNode, at index: Int) {
        addChild(node)
        let children = self.children
        if index < children.count {
            self.removeChildren(in: [node])
            self.insertChild(node: node, at: index)
        }
    }
    // SKNode does have a native insertChild(_:at:), but helper above avoids
    // a name conflict if upstream changes the API.
    private func insertChild(node: SKNode, at index: Int) {
        // No direct API — re-append as last child; Z-order is controlled
        // via zPosition, so the visual order is preserved regardless.
        self.addChild(node)
    }
}

/// Glassmorphic bottom tab bar shared by MapScene, ShopScene, HangarScene.
final class SkyTabBar: SKNode {
    enum Tab: Int { case hangar, shop, missions }

    let bar: SKShapeNode
    var active: Tab

    init(active: Tab) {
        self.active = active
        self.bar = SKShapeNode(rectOf: CGSize(width: 260, height: 56), cornerRadius: 28)
        super.init()
        bar.fillColor = SkyColors.skSurfaceContainerLowest.withAlphaComponent(0.92)
        bar.strokeColor = .clear
        addChild(bar)

        let items: [(Tab, String, String)] = [
            (.hangar, "✈", "HANGAR"),
            (.shop, "🛍", "SHOP"),
            (.missions, "📋", "MISSIONS")
        ]

        for (index, (tab, icon, title)) in items.enumerated() {
            let group = SKNode()
            group.position = CGPoint(x: -90 + CGFloat(index) * 90, y: 0)
            let iconLabel = SKLabelNode(text: icon)
            iconLabel.fontSize = 22
            iconLabel.verticalAlignmentMode = .center
            iconLabel.horizontalAlignmentMode = .center
            iconLabel.position = CGPoint(x: 0, y: 8)
            group.addChild(iconLabel)

            let titleLabel = SKLabelNode(text: title)
            titleLabel.fontName = SkyFonts.headlineName
            titleLabel.fontSize = 9
            titleLabel.fontColor = tab == active ? SkyColors.skPrimary : SkyColors.skOnSurfaceVariant
            titleLabel.verticalAlignmentMode = .center
            titleLabel.horizontalAlignmentMode = .center
            titleLabel.position = CGPoint(x: 0, y: -14)
            group.addChild(titleLabel)

            iconLabel.alpha = tab == active ? 1.0 : 0.55
            group.name = "tab-\(tab.rawValue)"
            addChild(group)
        }
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func handleTap(at p: CGPoint) {
        for node in nodes(at: p) {
            var n: SKNode? = node
            while let current = n {
                if let name = current.name, name.hasPrefix("tab-") {
                    let id = name.replacingOccurrences(of: "tab-", with: "")
                    if let raw = Int(id), let tab = Tab(rawValue: raw) {
                        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                        switch tab {
                        case .hangar:   SkyNavigator.shared.showHangar()
                        case .shop:     SkyNavigator.shared.showShop()
                        case .missions: SkyNavigator.shared.showMap()
                        }
                    }
                    return
                }
                n = current.parent
            }
        }
    }
}
