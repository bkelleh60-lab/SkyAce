import SpriteKit
import UIKit

/// Pilot-avatar / title / coin-pill / settings-gear header used on the home
/// screen (and any other scene that wants the same treatment). Mirrors the
/// `SkyTabBar` pattern: the node is anchored to a fixed scene-coordinate
/// position and exposes `setTopInset(_:)` so the host view controller can
/// patch the layout once the real safe-area insets arrive.
///
/// Anchor convention: position the node at `(size.width / 2, size.height)`
/// — i.e. the top-center of the scene. The surface fill extends DOWN from
/// the origin so it covers both the safe-area inset (filling behind the
/// Dynamic Island / notch) and the `contentHeight` strip below it. All
/// content (avatar, title, coin pill, gear) sits at the vertical center of
/// that lower strip, well clear of the inset.
final class SkyMenuTopBar: SKNode {

    static let contentHeight: CGFloat = 72

    private let barWidth: CGFloat
    private(set) var topInset: CGFloat
    private(set) var leftInset: CGFloat = 0
    private(set) var rightInset: CGFloat = 0

    private let surface: SKSpriteNode
    private let avatarRing: SKShapeNode
    private let avatar: SKNode
    private let title: SKLabelNode
    private let coinPill: SkyCoinPill
    private let gear: SKNode

    init(width: CGFloat, topInset: CGFloat = 0) {
        self.barWidth = width
        self.topInset = topInset

        // Surface fill — full-width rectangle that extends behind the
        // Dynamic Island. Built at zero size; `applyLayout` resizes it.
        self.surface = SKSpriteNode(color: SkyColors.surface, size: .zero)

        // Pilot avatar.
        let avatarSize: CGFloat = 52
        avatarRing = SKShapeNode(circleOfRadius: avatarSize / 2 + 3)
        avatarRing.fillColor = SkyColors.primaryContainer
        avatarRing.strokeColor = .clear

        if let sprite = SkySprites.sprite(
            named: SkySprites.pilotAvatar,
            size: CGSize(width: avatarSize, height: avatarSize)
        ) {
            let mask = SKShapeNode(circleOfRadius: avatarSize / 2)
            mask.fillColor = .white
            mask.strokeColor = .clear
            let crop = SKCropNode()
            crop.maskNode = mask
            crop.addChild(sprite)
            avatar = crop
        } else {
            let placeholder = SKShapeNode(circleOfRadius: avatarSize / 2)
            placeholder.fillColor = SkyColors.surfaceContainer
            placeholder.strokeColor = .clear
            let glyph = SKLabelNode(text: "👨‍✈️")
            glyph.fontSize = 30
            glyph.verticalAlignmentMode = .center
            glyph.horizontalAlignmentMode = .center
            placeholder.addChild(glyph)
            avatar = placeholder
        }

        title = SKLabelNode(text: "Sky Ace")
        title.fontName = SkyFonts.headlineName
        title.fontSize = 20
        title.fontColor = SkyColors.primaryContainer
        title.verticalAlignmentMode = .baseline
        title.horizontalAlignmentMode = .left

        coinPill = SkyCoinPill(coins: ProgressManager.shared.coins)
        coinPill.setScale(0.85)
        coinPill.name = "coinPill"

        gear = SkySprites.iconNode(
            named: SkySprites.iconSettings,
            fallbackEmoji: "⚙",
            size: 28,
            color: SkyColors.onSurface
        )
        gear.name = "settingsGear"

        super.init()

        surface.zPosition = 0
        avatarRing.zPosition = 1
        avatar.zPosition = 2
        title.zPosition = 1
        coinPill.zPosition = 1
        gear.zPosition = 1

        addChild(surface)
        addChild(avatarRing)
        addChild(avatar)
        addChild(title)
        addChild(coinPill)
        addChild(gear)

        applyLayout()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Update the safe-area inset after construction. Scenes receive
    /// `safeAreaInsets` of zero in `didMove(to:)` on the very first present,
    /// so the host view controller calls this once layout settles to extend
    /// the surface fill behind the Dynamic Island and reposition content
    /// below the inset.
    func setTopInset(_ inset: CGFloat) {
        guard inset != topInset else { return }
        topInset = inset
        applyLayout()
    }

    /// Plumbing for landscape support (SKY-049). Stored now so future layout
    /// work can shift edge-anchored content (avatar, gear) inboard of the
    /// Dynamic Island sensor housing without further wiring changes.
    func setHorizontalInsets(left: CGFloat, right: CGFloat) {
        leftInset = left
        rightInset = right
    }

    private func applyLayout() {
        let contentHeight = Self.contentHeight
        let totalHeight = topInset + contentHeight

        // Surface fill — extends from origin (top of screen) down through
        // both the inset and the content strip.
        surface.size = CGSize(width: barWidth, height: totalHeight)
        surface.position = CGPoint(x: 0, y: -totalHeight / 2)

        // Content y — center of the strip below the inset.
        let contentY = -topInset - contentHeight / 2

        let avatarSize: CGFloat = 52
        let avatarX: CGFloat = -barWidth / 2 + 44

        avatarRing.position = CGPoint(x: avatarX, y: contentY)
        avatar.position = CGPoint(x: avatarX, y: contentY)

        title.position = CGPoint(x: avatarX + avatarSize / 2 + 14, y: contentY + 4)

        coinPill.position = CGPoint(x: avatarX + avatarSize / 2 + 14 + 52, y: contentY - 16)

        gear.position = CGPoint(x: barWidth / 2 - 32, y: contentY)
    }
}
