import SpriteKit

/// HUD ability button + charge/cooldown indicator for a plane's active ability
/// (SKY-66). Deliberately reuses the existing functional-HUD language — an
/// emoji glyph inside a rounded pill, matching the coin pill and armor badge —
/// so no new art asset is required.
///
/// The scene owns the ability timing and drives visual state via `setState(_:)`.
/// Touch routing finds this node by the `"abilityButton"` name (mirroring the
/// pause button) and calls `handleTap()`, which fires `onTap` only when `.ready`
/// so a spent/cooling ability can't be triggered.
final class AbilityButtonNode: SKNode {

    enum State {
        case ready      // armed — tap to fire
        case active     // ability currently running
        case cooldown   // recharging, not yet tappable
        case spent      // one-shot ability used up for this run
    }

    private static let diameter: CGFloat = 58

    private let ring: SKShapeNode
    private let glyph: SKLabelNode
    private let onTap: () -> Void

    private(set) var state: State = .ready

    init(emoji: String, onTap: @escaping () -> Void) {
        self.onTap = onTap

        let d = AbilityButtonNode.diameter
        ring = SKShapeNode(circleOfRadius: d / 2)
        ring.lineWidth = 3
        glyph = SKLabelNode(text: emoji)

        super.init()

        name = "abilityButton"

        ring.name = "abilityButton"
        ring.zPosition = 0
        addChild(ring)

        glyph.fontName = SkyFonts.headlineName
        glyph.fontSize = 26
        glyph.verticalAlignmentMode = .center
        glyph.horizontalAlignmentMode = .center
        glyph.name = "abilityButton"
        glyph.zPosition = 1
        addChild(glyph)

        applyStateStyle()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - State

    func setState(_ newState: State) {
        guard newState != state else { return }
        state = newState
        applyStateStyle()

        // A short pop when the ability becomes usable again draws the eye back.
        if newState == .ready {
            run(SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.12)
            ]))
        }
    }

    private func applyStateStyle() {
        switch state {
        case .ready:
            ring.fillColor = SkyColors.skPrimaryContainer
            ring.strokeColor = SkyColors.skPrimary
            glyph.alpha = 1.0
            alpha = 1.0
            startReadyPulse()
        case .active:
            ring.fillColor = SkyColors.skTertiaryContainer
            ring.strokeColor = SkyColors.skOnTertiaryContainer
            glyph.alpha = 1.0
            alpha = 1.0
            stopReadyPulse()
        case .cooldown:
            ring.fillColor = SkyColors.skSurfaceContainer
            ring.strokeColor = SkyColors.skOutlineVariant
            glyph.alpha = 0.5
            alpha = 0.85
            stopReadyPulse()
        case .spent:
            ring.fillColor = SkyColors.skSurfaceContainer
            ring.strokeColor = SkyColors.skOutlineVariant
            glyph.alpha = 0.35
            alpha = 0.6
            stopReadyPulse()
        }
    }

    private static let pulseKey = "abilityReadyPulse"

    private func startReadyPulse() {
        guard action(forKey: AbilityButtonNode.pulseKey) == nil else { return }
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.6),
            SKAction.scale(to: 1.0, duration: 0.6)
        ])
        run(SKAction.repeatForever(pulse), withKey: AbilityButtonNode.pulseKey)
    }

    private func stopReadyPulse() {
        removeAction(forKey: AbilityButtonNode.pulseKey)
        setScale(1.0)
    }

    // MARK: - Input

    /// Fires the ability only when armed. No-op while active, cooling, or spent.
    func handleTap() {
        guard state == .ready else { return }
        onTap()
    }
}
