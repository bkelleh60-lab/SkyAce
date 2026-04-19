import SpriteKit
import UIKit

/// Shared UI building blocks for Free Flight "landmark tour" scenes.
///
/// The two Free Flight scenes (City + Mountain) present a sandbox where the
/// player drifts across a scrolling landscape dotted with 4 distinctive
/// landmarks. Visiting and collecting from each landmark fills one slot on
/// a 4-slot stamp card; completing all 4 triggers a coin bonus + a
/// confetti/banner celebration and then resets for another lap.
///
/// This file provides the pieces that both scenes share:
///   • `StampCardHUD` — the 4-slot indicator displayed in the top-right
///   • `LandmarkCelebration` — confetti + banner used on tour completion

// MARK: - Stamp card HUD

/// Four-slot (by default) horizontal stamp card. Slots start grey and
/// animate to gold on `stamp(index:)`. `reset()` returns all slots to grey.
final class StampCardHUD: SKNode {
    private let slotCount: Int
    private var slots: [SKShapeNode] = []

    init(slotCount: Int = 4) {
        self.slotCount = slotCount
        super.init()
        build()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Total width occupied by the card (bounding rect). Useful for
    /// positioning the node inside a top bar.
    var cardSize: CGSize {
        let slotRadius: CGFloat = 10
        let spacing: CGFloat = 8
        let totalWidth = CGFloat(slotCount) * (slotRadius * 2) + CGFloat(slotCount - 1) * spacing
        return CGSize(width: totalWidth + 24, height: 36)
    }

    private func build() {
        let slotRadius: CGFloat = 10
        let spacing: CGFloat = 8
        let size = cardSize

        // Background pill.
        let card = SKShapeNode(
            rectOf: size,
            cornerRadius: size.height / 2
        )
        card.fillColor = SkyColors.surfaceContainerLowest.withAlphaComponent(0.9)
        card.strokeColor = .clear
        card.zPosition = 0
        addChild(card)

        // Evenly-spaced circular slots centered across the card.
        let stride = slotRadius * 2 + spacing
        let totalSpan = CGFloat(slotCount - 1) * stride
        let startX = -totalSpan / 2
        for i in 0..<slotCount {
            let slot = SKShapeNode(circleOfRadius: slotRadius)
            slot.fillColor = SkyColors.outlineVariant.withAlphaComponent(0.35)
            slot.strokeColor = .clear
            slot.position = CGPoint(x: startX + CGFloat(i) * stride, y: 0)
            slot.zPosition = 1
            addChild(slot)
            slots.append(slot)
        }
    }

    func stamp(index: Int) {
        guard slots.indices.contains(index) else { return }
        let slot = slots[index]
        slot.fillColor = SkyColors.tertiaryContainer
        slot.run(SKAction.sequence([
            SKAction.scale(to: 1.4, duration: 0.10),
            SKAction.scale(to: 1.0, duration: 0.15)
        ]))
    }

    func reset() {
        for slot in slots {
            slot.fillColor = SkyColors.outlineVariant.withAlphaComponent(0.35)
        }
    }
}

// MARK: - Tour-complete celebration

enum LandmarkCelebration {

    /// Emit a short confetti burst from `center`. Self-cleans after ~1.4s.
    static func emitConfetti(at center: CGPoint, in parent: SKNode, pieces: Int = 40) {
        let colors: [UIColor] = [
            SkyColors.primaryContainer,
            SkyColors.tertiaryContainer,
            SkyColors.secondaryContainer,
            .systemPink,
            .systemGreen,
            .systemPurple
        ]
        for _ in 0..<pieces {
            let piece = SKShapeNode(rectOf: CGSize(width: 6, height: 10), cornerRadius: 2)
            piece.fillColor = colors.randomElement()!
            piece.strokeColor = .clear
            piece.position = center
            piece.zPosition = 500
            parent.addChild(piece)
            let dx = CGFloat.random(in: -200...200)
            let dy = CGFloat.random(in: 100...260)
            let rot = CGFloat.random(in: -.pi * 2 ... .pi * 2)
            piece.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 1.4),
                    SKAction.rotate(byAngle: rot, duration: 1.4),
                    SKAction.fadeOut(withDuration: 1.4)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    /// Show an oversized animated "TOUR COMPLETE!" banner + subtitle,
    /// auto-removing after ~2 seconds.
    static func showBanner(
        title: String,
        subtitle: String,
        at center: CGPoint,
        in parent: SKNode,
        subtitleColor: UIColor = SkyColors.onPrimary
    ) {
        let titleLabel = SKLabelNode(text: title)
        titleLabel.fontName = SkyFonts.headlineItalicName
        titleLabel.fontSize = 44
        titleLabel.fontColor = SkyColors.tertiaryContainer
        titleLabel.position = center
        titleLabel.setScale(0.1)
        titleLabel.alpha = 0
        titleLabel.zPosition = 600
        parent.addChild(titleLabel)

        // Drop shadow behind the title (as a child so it animates together).
        let shadow = SKLabelNode(text: title)
        shadow.fontName = SkyFonts.headlineItalicName
        shadow.fontSize = 44
        shadow.fontColor = SkyColors.onPrimaryContainer.withAlphaComponent(0.5)
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        titleLabel.addChild(shadow)

        let subtitleLabel = SKLabelNode(text: subtitle)
        subtitleLabel.fontName = SkyFonts.headlineName
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = subtitleColor
        subtitleLabel.position = CGPoint(x: center.x, y: center.y - 42)
        subtitleLabel.setScale(0.1)
        subtitleLabel.alpha = 0
        subtitleLabel.zPosition = 600
        parent.addChild(subtitleLabel)

        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: 0.20),
            SKAction.scale(to: 1.0, duration: 0.30)
        ])
        let hold = SKAction.wait(forDuration: 1.6)
        let disappear = SKAction.group([
            SKAction.fadeOut(withDuration: 0.40),
            SKAction.scale(to: 0.8, duration: 0.40)
        ])
        let cleanup = SKAction.removeFromParent()
        let seq = SKAction.sequence([appear, hold, disappear, cleanup])
        titleLabel.run(seq)
        subtitleLabel.run(seq)
    }
}
