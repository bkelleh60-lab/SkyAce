import SpriteKit
import UIKit

/// Pilot-avatar / title / coin-pill / sound-toggle / trophy header used on the
/// home screen (and any other scene that wants the same treatment). Mirrors the
/// `SkyTabBar` pattern: the node is anchored to a fixed scene-coordinate
/// position and exposes `setTopInset(_:)` so the host view controller can
/// patch the layout once the real safe-area insets arrive.
///
/// Anchor convention: position the node at `(size.width / 2, size.height)`
/// — i.e. the top-center of the scene. The surface fill extends DOWN from
/// the origin so it covers both the safe-area inset (filling behind the
/// Dynamic Island / notch) and the `contentHeight` strip below it. All
/// content (avatar, title, coin pill, sound toggle, trophy) sits at the center of
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
    /// Trophy glyph that opens the badge collection screen (SKY-124). Replaces
    /// the former sun/settings glyph at the top-right.
    private let trophy: SKSpriteNode
    /// Sound on/off toggle glyph, relocated next to the trophy so the mute
    /// control the sun icon used to provide is preserved (SKY-124). Its symbol
    /// reflects the current audio state.
    private let soundToggle: SKSpriteNode
    /// Transparent 44x44 hit targets carrying the routing names, so the small
    /// glyphs meet the 44pt minimum tap size in this kids' app.
    private let trophyHit: SKSpriteNode
    private let soundHit: SKSpriteNode
    /// Small gold "new badge" indicator drawn on the trophy while the player
    /// has earned a badge they haven't seen on the collection screen yet.
    private let badgeDot: SKShapeNode

    /// SF Symbol name for the current audio state — the slashed speaker once
    /// everything is muted, otherwise the standard speaker.
    private static var soundSymbolName: String {
        let isSoundOn = AudioManager.shared.musicEnabled || AudioManager.shared.sfxEnabled
        return isSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    /// Builds the header content — avatar, title, coin pill, trophy (with its
    /// unseen-badge dot), and sound toggle — for a bar of the given `width`,
    /// laid out below `topInset`.
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

        trophy = SkySprites.sfSymbolNode(
            systemName: "trophy.fill",
            size: 28,
            color: SkyColors.onSurface
        )
        trophyHit = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 44))
        trophyHit.name = "badgesButton"

        soundToggle = SkySprites.sfSymbolNode(
            systemName: SkyMenuTopBar.soundSymbolName,
            size: 26,
            color: SkyColors.onSurface
        )
        soundHit = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 44))
        soundHit.name = "soundToggle"

        // Notification-style dot (~8pt) in the app's coin/reward gold (#FFD709),
        // ringed in the surface colour so it reads against the trophy glyph.
        badgeDot = SKShapeNode(circleOfRadius: 4)
        badgeDot.fillColor = SkyColors.skTertiaryContainer
        badgeDot.strokeColor = SkyColors.skSurface
        badgeDot.lineWidth = 1.5
        badgeDot.isHidden = !Badge.hasUnseenEarnedBadges

        super.init()

        surface.zPosition = 0
        avatarRing.zPosition = 1
        avatar.zPosition = 2
        title.zPosition = 1
        coinPill.zPosition = 1
        trophyHit.zPosition = 1
        soundHit.zPosition = 1
        // Glyphs are visuals inside their hit targets; the dot rides above the
        // trophy glyph.
        trophy.zPosition = 0
        soundToggle.zPosition = 0
        badgeDot.zPosition = 2
        trophyHit.addChild(trophy)
        trophyHit.addChild(badgeDot)
        soundHit.addChild(soundToggle)

        addChild(surface)
        addChild(avatarRing)
        addChild(avatar)
        addChild(title)
        addChild(coinPill)
        addChild(trophyHit)
        addChild(soundHit)

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
    /// work can shift edge-anchored content (avatar, trophy) inboard of the
    /// Dynamic Island sensor housing without further wiring changes.
    func setHorizontalInsets(left: CGFloat, right: CGFloat) {
        leftInset = left
        rightInset = right
    }

    /// Positions the surface fill and all content for the current width and
    /// top inset. Re-run whenever the inset changes.
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

        // Trophy anchored at the far right (the old sun icon's slot); the sound
        // toggle sits just inboard of it. 48pt spacing keeps the two 44pt hit
        // frames from overlapping. Both clear the coin pill on the left.
        trophyHit.position = CGPoint(x: barWidth / 2 - 30, y: contentY)
        soundHit.position = CGPoint(x: barWidth / 2 - 30 - 48, y: contentY)

        // Glyphs are centered in their hit targets; nudge the dot to the trophy
        // glyph's upper-right corner.
        trophy.position = .zero
        soundToggle.position = .zero
        badgeDot.position = CGPoint(x: 11, y: 10)
    }

    /// Re-renders the sound glyph to match the current audio state. Called by
    /// the menu after it toggles sound so the icon flips between the speaker
    /// and slashed-speaker symbols.
    func refreshSoundToggle() {
        let glyph = SkySprites.sfSymbolNode(
            systemName: SkyMenuTopBar.soundSymbolName,
            size: 26,
            color: SkyColors.onSurface
        )
        soundToggle.texture = glyph.texture
    }
}
