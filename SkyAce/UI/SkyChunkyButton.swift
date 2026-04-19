import SpriteKit
import UIKit

/// "Arcade" CTA button with a thick darker rim along the bottom that
/// disappears when pressed, giving a tactile physical-button feel per the
/// redesigned Menu spec. The body is a primary→primaryContainer gradient
/// (same "convex" language as SkyPillButton) sitting on a primary-dim rim;
/// tapping animates the body down to collapse the rim, plays a haptic, and
/// invokes the handler.
///
/// Composition:
///
///     ┌─────────────────┐   ← body (gradient pill)
///     │                 │
///     │   ▶  PLAY       │
///     │                 │
///     └─────────────────┘
///     ╚═════════════════╝   ← rim (darker primary-dim slab)
///
/// Use via `init(title:iconName:size:handler:)`; call `handleTap()` from the
/// parent scene's touch handler (same pattern as SkyPillButton).
final class SkyChunkyButton: SKNode {

    let buttonSize: CGSize
    private let rim: SKSpriteNode
    private let body: SKSpriteNode
    private let label: SKLabelNode
    private let iconSprite: SKNode?
    private let handler: () -> Void

    /// How far the body sits above the rim at rest. Collapses to 0 on press.
    private let rimLift: CGFloat = 8

    init(title: String,
         iconName: String? = nil,
         size: CGSize = CGSize(width: 280, height: 88),
         handler: @escaping () -> Void) {
        self.buttonSize = size
        self.handler = handler

        let radius = min(size.height / 2, 36)

        // Rim: same width as body, same height, primary-dim, sitting slightly
        // below the body so only a thin slab of it peeks out.
        let rimTexture = SkyUIEffects.gradientTexture(
            size: size,
            cornerRadius: radius,
            top: SkyColors.primary,
            bottom: UIColor(hex: 0x003F57)   // primary-dim (between primary and onPrimaryContainer)
        )
        self.rim = SKSpriteNode(texture: rimTexture, size: size)
        self.rim.position = CGPoint(x: 0, y: 0)

        // Body: primaryContainer→primary vertical gradient.
        let bodyTexture = SkyUIEffects.gradientTexture(
            size: size,
            cornerRadius: radius,
            top: SkyColors.primaryContainer,
            bottom: SkyColors.primary
        )
        self.body = SKSpriteNode(texture: bodyTexture, size: size)
        self.body.position = CGPoint(x: 0, y: rimLift)

        // Label
        self.label = SKLabelNode(text: title)
        self.label.fontName = SkyFonts.headlineItalicName
        self.label.fontSize = 30
        self.label.fontColor = SkyColors.onPrimary
        self.label.verticalAlignmentMode = .center
        self.label.horizontalAlignmentMode = .center

        // Optional icon (white filled glyph)
        if let iconName = iconName {
            self.iconSprite = SkySprites.iconNode(
                named: iconName,
                fallbackEmoji: "▶",
                size: 36,
                color: SkyColors.onPrimary
            )
        } else {
            self.iconSprite = nil
        }

        super.init()

        // Ambient shadow beneath the rim.
        let shadow = SkyUIEffects.shadowSprite(size: size, cornerRadius: radius, blur: 20, spread: -2)
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -10
        addChild(shadow)

        addChild(rim)
        addChild(body)

        // Layout label and optional icon horizontally inside the body.
        if let icon = iconSprite {
            icon.position = CGPoint(x: -60, y: 0)
            body.addChild(icon)
            label.position = CGPoint(x: 18, y: 0)
        } else {
            label.position = .zero
        }
        body.addChild(label)

        isUserInteractionEnabled = false
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func handleTap() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyHaptics.uiTap()

        // Press down: collapse rim; pop back up on release.
        let down = SKAction.moveTo(y: 0, duration: 0.06)
        let up   = SKAction.moveTo(y: rimLift, duration: 0.12)
        body.run(SKAction.sequence([down, up])) { [weak self] in
            self?.handler()
        }
    }
}
