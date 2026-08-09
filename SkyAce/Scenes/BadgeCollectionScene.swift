import SpriteKit
import CoreImage

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

        let back = SKLabelNode(text: "‹")
        back.fontName = SkyFonts.headlineName
        back.fontSize = 30
        back.fontColor = SkyColors.skOnPrimary
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .center
        back.position = CGPoint(x: 24, y: barCenterY)
        back.zPosition = 200
        back.name = "badgesBack"
        addChild(back)

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
        let gridTopY = headerBottom - 20

        let badges = Badge.all
        for (index, badge) in badges.enumerated() {
            let col = index % 2
            let row = index / 2
            let x = sidePadding + cardWidth / 2 + CGFloat(col) * (cardWidth + columnGap)
            let y = gridTopY - cardHeight / 2 - CGFloat(row) * (cardHeight + rowGap)
            let card = makeBadgeCard(badge, width: cardWidth, height: cardHeight)
            card.position = CGPoint(x: x, y: y)
            contentNode.addChild(card)
        }

        // Total content span from the grid top to the bottom of the last row.
        let rowCount = (badges.count + 1) / 2
        contentHeight = CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * rowGap
    }

    private func makeBadgeCard(_ badge: Badge, width: CGFloat, height: CGFloat) -> SKNode {
        let card = SKNode()

        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 20)
        bg.fillColor = SkyColors.skSurfaceContainerLowest
        bg.strokeColor = .clear
        card.addChild(bg)

        let earned = badge.isEarned()
        let imageSize = CGSize(width: 100, height: 100)
        let imageNode: SKNode
        if let texture = SkySprites.texture(named: badge.assetName) {
            let display = earned ? texture : Self.desaturated(texture)
            let sprite = SKSpriteNode(texture: display, size: imageSize)
            sprite.alpha = earned ? 1.0 : 0.4
            imageNode = sprite
        } else {
            // Art missing — neutral placeholder so the card still communicates.
            let placeholder = SKShapeNode(circleOfRadius: 50)
            placeholder.fillColor = SkyColors.skSurfaceContainerHigh
            placeholder.strokeColor = .clear
            placeholder.alpha = earned ? 1.0 : 0.4
            imageNode = placeholder
        }
        imageNode.position = CGPoint(x: 0, y: height / 2 - 14 - 50)
        card.addChild(imageNode)

        let titleLabel = SKLabelNode(text: badge.title)
        titleLabel.fontName = SkyFonts.boldName
        titleLabel.fontSize = 15
        titleLabel.fontColor = SkyColors.skOnSurface
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: -30)
        card.addChild(titleLabel)

        let detailLabel = SKLabelNode(text: badge.detail)
        detailLabel.fontName = SkyFonts.bodyName
        detailLabel.fontSize = 13
        detailLabel.fontColor = SkyColors.skOnSurfaceVariant
        detailLabel.horizontalAlignmentMode = .center
        detailLabel.verticalAlignmentMode = .center
        detailLabel.numberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.preferredMaxLayoutWidth = width - 20
        detailLabel.position = CGPoint(x: 0, y: -64)
        card.addChild(detailLabel)

        return card
    }

    /// Returns a greyscale copy of `texture` for rendering unearned badges.
    /// Falls back to the original texture if the Core Image pipeline is
    /// unavailable so an unearned badge still shows (just not desaturated).
    private static func desaturated(_ texture: SKTexture) -> SKTexture {
        let sourceImage = CIImage(cgImage: texture.cgImage())
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return texture }
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        let context = CIContext(options: nil)
        guard let output = filter.outputImage,
              let cgResult = context.createCGImage(output, from: output.extent) else {
            return texture
        }
        return SKTexture(cgImage: cgResult)
    }

    // MARK: - Scroll clamping

    private func clampOffset(_ y: CGFloat) -> CGFloat {
        // Content is laid out from the top down, so it scrolls in the positive
        // direction. Overscroll room below matches the bottom safe area.
        let visibleHeight = size.height - topSafeInset - bottomSafeInset
        let overflow = contentHeight - visibleHeight + 120
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
