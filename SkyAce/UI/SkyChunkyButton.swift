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
/// Use via `init(title:icon:size:style:…:handler:)`; call `handleTap()` from
/// the parent scene's touch handler (same pattern as SkyPillButton).
final class SkyChunkyButton: SKNode {

    /// Colour recipe for the body→rim gradient. Three steps: `bodyTop` (bright)
    /// fades to `mid` across the body, and `mid` fades to `rimBottom` across the
    /// darker rim slab below it — giving the tactile "convex pill on a dim
    /// slab" look. `.primary` reproduces the original blue PLAY treatment.
    struct Style {
        /// Bright tone at the top of the body's vertical gradient.
        let bodyTop: UIColor
        /// Shared mid tone: bottom of the body gradient and top of the rim.
        let mid: UIColor
        /// Darkest tone at the bottom of the rim slab.
        let rimBottom: UIColor
        /// Label and icon colour, chosen for legible contrast on the body.
        let label: UIColor

        /// Deep blue primary action (PLAY). White label reads on deep blue.
        static let primary = Style(
            bodyTop: SkyColors.primaryContainer,
            mid: SkyColors.primary,
            rimBottom: UIColor(hex: 0x003F57),   // primary-dim
            label: SkyColors.onPrimary
        )

        /// Warm orange/peach exploration action (FREE FLIGHT). Navy label —
        /// white is hard to read on the light peach face.
        static let secondary = Style(
            bodyTop: SkyColors.secondaryContainer,
            mid: SkyColors.secondaryContainerMid,
            rimBottom: SkyColors.secondaryContainerDim,
            label: SkyColors.onSurface
        )

        /// Gold economy action (UPGRADE). Navy label for the same reason.
        static let tertiary = Style(
            bodyTop: SkyColors.tertiaryContainer,
            mid: SkyColors.tertiaryContainerMid,
            rimBottom: SkyColors.tertiaryContainerDim,
            label: SkyColors.onSurface
        )
    }

    /// How the icon and label are arranged inside the body. PLAY uses
    /// `.horizontal` (icon left of label); the narrower two-column buttons use
    /// `.vertical` (icon stacked above label) so the text isn't clipped.
    enum ContentLayout {
        /// Icon to the left of the label (the wide PLAY button).
        case horizontal
        /// Icon stacked above the label (the narrow two-column buttons).
        case vertical
    }

    let buttonSize: CGSize
    private let rim: SKSpriteNode
    private let body: SKSpriteNode
    private let label: SKLabelNode
    private let iconSprite: SKNode?
    private let handler: () -> Void

    /// How far the body sits above the rim at rest. Collapses to 0 on press.
    private let rimLift: CGFloat = 8

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - icon: pre-built glyph node (sprite/label) drawn centered on `.zero`.
    ///     Pass `nil` for a text-only button.
    ///   - style: colour recipe (defaults to the blue `.primary` PLAY look).
    ///   - cornerRadius: pill radius; defaults to `min(height/2, 36)`.
    ///   - labelFontSize: title size; PLAY uses 30, the compact buttons 11.
    ///   - contentLayout: icon/label arrangement (see `ContentLayout`).
    init(title: String,
         icon: SKNode? = nil,
         size: CGSize = CGSize(width: 280, height: 88),
         style: Style = .primary,
         cornerRadius: CGFloat? = nil,
         labelFontSize: CGFloat = 30,
         contentLayout: ContentLayout = .horizontal,
         handler: @escaping () -> Void) {
        self.buttonSize = size
        self.handler = handler

        let radius = cornerRadius ?? min(size.height / 2, 36)

        // Rim: same width as body, same height, sitting slightly below the body
        // so only a thin slab of it peeks out. Steps mid → rimBottom.
        let rimTexture = SkyUIEffects.gradientTexture(
            size: size,
            cornerRadius: radius,
            top: style.mid,
            bottom: style.rimBottom
        )
        self.rim = SKSpriteNode(texture: rimTexture, size: size)
        self.rim.position = CGPoint(x: 0, y: 0)

        // Body: bodyTop → mid vertical gradient (the "convex" face).
        let bodyTexture = SkyUIEffects.gradientTexture(
            size: size,
            cornerRadius: radius,
            top: style.bodyTop,
            bottom: style.mid
        )
        self.body = SKSpriteNode(texture: bodyTexture, size: size)
        self.body.position = CGPoint(x: 0, y: rimLift)

        // Label
        self.label = SKLabelNode(text: title)
        self.label.fontName = SkyFonts.headlineItalicName
        self.label.fontSize = labelFontSize
        self.label.fontColor = style.label
        self.label.verticalAlignmentMode = .center
        self.label.horizontalAlignmentMode = .center

        self.iconSprite = icon

        super.init()

        // Ambient shadow beneath the rim.
        let shadow = SkyUIEffects.shadowSprite(size: size, cornerRadius: radius, blur: 20, spread: -2)
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -10
        addChild(shadow)

        addChild(rim)
        addChild(body)

        // Layout label and optional icon inside the body.
        if let icon = iconSprite {
            switch contentLayout {
            case .horizontal:
                icon.position = CGPoint(x: -60, y: 0)
                label.position = CGPoint(x: 18, y: 0)
            case .vertical:
                icon.position = CGPoint(x: 0, y: 13)
                label.position = CGPoint(x: 0, y: -19)
            }
            body.addChild(icon)
        } else {
            label.position = .zero
        }
        body.addChild(label)

        isUserInteractionEnabled = false
    }

    /// Convenience initialiser matching the original PLAY call site: builds the
    /// icon from an asset name (white glyph) using the default primary style.
    convenience init(title: String,
                     iconName: String?,
                     size: CGSize = CGSize(width: 280, height: 88),
                     handler: @escaping () -> Void) {
        let icon = iconName.map {
            SkySprites.iconNode(named: $0, fallbackEmoji: "▶", size: 36, color: SkyColors.onPrimary)
        }
        self.init(title: title, icon: icon, size: size, handler: handler)
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
