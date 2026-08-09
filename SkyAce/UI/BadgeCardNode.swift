import SpriteKit
import CoreImage

/// One badge card for the collection screen (SKY-124): a rounded surface card
/// holding the badge art (full colour when earned, desaturated at 40% opacity
/// when not), the badge name in bold, and its description in grey. Owns its own
/// visuals so `BadgeCollectionScene` only handles grid layout and spawning.
final class BadgeCardNode: SKNode {

    /// Shared Core Image context — construction is expensive, so it is reused
    /// across every desaturated badge rather than rebuilt per card.
    private static let ciContext = CIContext(options: nil)

    init(badge: Badge, size: CGSize) {
        super.init()
        build(badge: badge, size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build(badge: Badge, size: CGSize) {
        let bg = SKShapeNode(rectOf: size, cornerRadius: 20)
        bg.fillColor = SkyColors.skSurfaceContainerLowest
        bg.strokeColor = .clear
        addChild(bg)

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
        imageNode.position = CGPoint(x: 0, y: size.height / 2 - 14 - 50)
        addChild(imageNode)

        let titleLabel = SKLabelNode(text: badge.title)
        titleLabel.fontName = SkyFonts.boldName
        titleLabel.fontSize = 15
        titleLabel.fontColor = SkyColors.skOnSurface
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: -30)
        addChild(titleLabel)

        let detailLabel = SKLabelNode(text: badge.detail)
        detailLabel.fontName = SkyFonts.bodyName
        detailLabel.fontSize = 13
        detailLabel.fontColor = SkyColors.skOnSurfaceVariant
        detailLabel.horizontalAlignmentMode = .center
        detailLabel.verticalAlignmentMode = .center
        detailLabel.numberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.preferredMaxLayoutWidth = size.width - 20
        detailLabel.position = CGPoint(x: 0, y: -64)
        addChild(detailLabel)
    }

    /// Returns a greyscale copy of `texture` for rendering unearned badges.
    /// Falls back to the original texture if the Core Image pipeline is
    /// unavailable so an unearned badge still shows (just not desaturated).
    private static func desaturated(_ texture: SKTexture) -> SKTexture {
        let sourceImage = CIImage(cgImage: texture.cgImage())
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return texture }
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let cgResult = ciContext.createCGImage(output, from: output.extent) else {
            return texture
        }
        return SKTexture(cgImage: cgResult)
    }
}
