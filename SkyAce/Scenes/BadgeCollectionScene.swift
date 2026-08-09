import SpriteKit

/// Badge collection screen (SKY-124). Reached from the home-screen trophy.
/// Shows every earnable badge in a 2-column grid: earned badges render in full
/// colour, unearned badges render desaturated at 40% opacity with their name
/// and description still visible so the player always knows what to work
/// toward. Earned state is read live from `ProgressManager` on every visit —
/// no caching.
final class BadgeCollectionScene: SKScene {

    /// Scrolling container for the badge grid (the header and back button stay
    /// fixed). Only scrolls when the grid is taller than the screen; with the
    /// launch set of two badges it fits without scrolling.
    private let contentNode = SKNode()
    private var contentHeight: CGFloat = 0
    /// Scene-space Y of the top of the first grid row, captured in `buildGrid`
    /// so the scroll extent accounts for the real space above the grid rather
    /// than a fixed pad.
    private var gridTopY: CGFloat = 0
    private var scrollVelocity: CGFloat = 0
    private var lastPanY: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0

    private var topSafeInset: CGFloat = 0
    private var bottomSafeInset: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        SkyHaptics.prepare()
        // Opening the screen clears the home-screen trophy "new badge" dot.
        Badge.markAllSeen()
        layoutScene()
    }

    // SKY-55 pattern: rebuild on rotation (iPad) so the grid re-centers.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        contentNode.removeAllChildren()
        contentNode.removeFromParent()
        contentNode.position = .zero
        scrollVelocity = 0
        layoutScene()
    }

    private func layoutScene() {
        topSafeInset = view?.safeAreaInsets.top ?? 0
        bottomSafeInset = view?.safeAreaInsets.bottom ?? 0
        buildGradient()
        buildTopBar()
        buildGrid()
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

    // MARK: - Fixed chrome (back + header)

    private func buildTopBar() {
        let barCenterY = size.height - topSafeInset - 20

        // Transparent 44x44 hit target carries the routing name; the chevron
        // is just its visual, so the tap area meets the 44pt minimum.
        let backHit = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 44))
        backHit.position = CGPoint(x: 30, y: barCenterY)
        backHit.zPosition = 200
        backHit.name = "badgesBack"
        let back = SKLabelNode(text: "‹")
        back.fontName = SkyFonts.headlineName
        back.fontSize = 30
        back.fontColor = SkyColors.skOnPrimary
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .center
        back.position = .zero
        backHit.addChild(back)
        addChild(backHit)

        // Screen header in the game's title style.
        let header = SKLabelNode(text: "My Badges")
        header.fontName = SkyFonts.headlineName
        header.fontSize = 28
        header.fontColor = SkyColors.skOnPrimary
        header.verticalAlignmentMode = .center
        header.horizontalAlignmentMode = .center
        header.position = CGPoint(x: size.width / 2, y: barCenterY - 48)
        header.zPosition = 200
        addChild(header)

        // Empty state: no badges earned yet.
        if Badge.earnedCount == 0 {
            let hint = SKLabelNode(text: "Complete challenges to earn badges.")
            hint.fontName = SkyFonts.bodyName
            hint.fontSize = 14
            hint.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
            hint.verticalAlignmentMode = .center
            hint.horizontalAlignmentMode = .center
            hint.position = CGPoint(x: size.width / 2, y: barCenterY - 78)
            hint.zPosition = 200
            addChild(hint)
        }
    }

    // MARK: - Badge grid

    private func buildGrid() {
        contentNode.position = .zero
        contentNode.zPosition = 0
        addChild(contentNode)

        let sidePadding: CGFloat = 24
        let columnGap: CGFloat = 16
        let rowGap: CGFloat = 16
        let cardHeight: CGFloat = 196
        let cardWidth = (size.width - sidePadding * 2 - columnGap) / 2

        // Grid starts below the header (and the empty-state hint if shown).
        let barCenterY = size.height - topSafeInset - 20
        let headerBottom = Badge.earnedCount == 0 ? barCenterY - 96 : barCenterY - 72
        gridTopY = headerBottom - 20

        let badges = Badge.all
        for (index, badge) in badges.enumerated() {
            let col = index % 2
            let row = index / 2
            let x = sidePadding + cardWidth / 2 + CGFloat(col) * (cardWidth + columnGap)
            let y = gridTopY - cardHeight / 2 - CGFloat(row) * (cardHeight + rowGap)
            let card = BadgeCardNode(badge: badge, size: CGSize(width: cardWidth, height: cardHeight))
            card.position = CGPoint(x: x, y: y)
            contentNode.addChild(card)
        }

        // Total content span from the grid top to the bottom of the last row.
        let rowCount = (badges.count + 1) / 2
        contentHeight = CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * rowGap
    }

    // MARK: - Scroll clamping

    private func clampOffset(_ y: CGFloat) -> CGFloat {
        // Content is laid out downward from `gridTopY`. The grid can scroll up
        // until its last row clears the bottom safe area; derive that extent
        // from the real grid origin rather than a fixed pad.
        let gridBottom = gridTopY - contentHeight
        let bottomLimit = bottomSafeInset + 16
        let overflow = bottomLimit - gridBottom
        guard overflow > 0 else { return 0 }
        return min(overflow, max(0, y))
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
            if node.name == "badgesBack" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                SkyNavigator.shared.showMenu()
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
}
