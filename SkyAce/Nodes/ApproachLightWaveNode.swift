import SpriteKit

/// Screen-anchored approach-light wave for Landing Practice (SKY-99).
///
/// A finite, ordered row of `lightCount` lights — each a cropped pole capped by
/// a colored glow orb — that cycle white → red → green in a left-to-right wave,
/// like sequenced ALSF approach lighting. Each glow runs the same color cycle
/// started after a per-index delay so the color travels across the row, with a
/// subtle alpha pulse layered on top for a genuine glow.
///
/// The node lays its lights out in its own coordinate space (origin = pole
/// base; x spans the scene width, inset from both edges). The scene positions
/// the whole node at the runway surface line and never scrolls it — like real
/// threshold lighting it marks a fixed point. Builds nothing (leaving the mode
/// on its bare gradient) if the pole or any glow asset is missing.
final class ApproachLightWaveNode: SKNode {

    // MARK: - Tunables

    /// Number of lights in the row (8–10 reads as a clear wave on every screen).
    static let lightCount = 9
    /// Seconds each color shows before transitioning to the next.
    static let colorDuration: TimeInterval = 0.4
    /// Delay between successive lights starting their cycle — the wave's "speed".
    static let waveDelta: TimeInterval = 0.12

    /// Rendered height of one pole (the cropped pole period).
    private static let poleHeight: CGFloat = 72
    /// Rendered diameter of the glow orb sitting at the top of each pole.
    private static let glowSize: CGFloat = 60
    /// Horizontal inset from each screen edge for the first/last light, so the
    /// row of `lightCount` lights spreads across the lower screen.
    private static let sideInset: CGFloat = 34
    /// One pole period cropped from the source strip (pixels 94–191 of the
    /// 500px image — one ~97px pole), normalized bottom-left.
    private static let poleCrop = CGRect(x: 94.0 / 500.0, y: 182.0 / 500.0,
                                         width: 97.0 / 500.0, height: 127.0 / 500.0)

    // MARK: - Init

    /// Builds the row spanning `sceneWidth`, anchored at the node origin (the
    /// pole base). Adds no children if the pole or any glow asset is missing.
    init(sceneWidth: CGFloat) {
        super.init()
        build(sceneWidth: sceneWidth)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func build(sceneWidth: CGFloat) {
        guard let poleTexture = SkySprites.texture(named: SkySprites.landingBgApproachLights)
                .map({ SKTexture(rect: Self.poleCrop, in: $0) }),
              // All three glow colors must be present — the wave can't read with
              // a missing color, so bail rather than show a partial cycle.
              let whiteGlow = SkySprites.texture(named: SkySprites.approachLightGlowWhite),
              let redGlow = SkySprites.texture(named: SkySprites.approachLightGlowRed),
              let greenGlow = SkySprites.texture(named: SkySprites.approachLightGlowGreen)
        else { return }
        let glowTextures = [whiteGlow, redGlow, greenGlow]

        let poleAspect = poleTexture.size().height > 0
            ? poleTexture.size().width / poleTexture.size().height
            : (97.0 / 127.0)
        let poleSize = CGSize(width: Self.poleHeight * poleAspect, height: Self.poleHeight)
        let glowSize = CGSize(width: Self.glowSize, height: Self.glowSize)

        // Even horizontal spread across the lower screen, inset from both edges.
        let firstX = Self.sideInset
        let lastX = sceneWidth - Self.sideInset
        let step = Self.lightCount > 1 ? (lastX - firstX) / CGFloat(Self.lightCount - 1) : 0

        for i in 0..<Self.lightCount {
            let light = SKNode()
            light.position = CGPoint(x: firstX + step * CGFloat(i), y: 0)
            addChild(light)

            // Pole anchored at its base so it stands up from the node origin.
            let pole = SKSpriteNode(texture: poleTexture, size: poleSize)
            pole.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            pole.zPosition = 0
            light.addChild(pole)

            // Glow orb at the top center of the pole, starting white.
            let glow = SKSpriteNode(texture: whiteGlow, size: glowSize)
            glow.position = CGPoint(x: 0, y: poleSize.height)
            glow.zPosition = 1
            // Normal alpha blend (not additive): the orbs sit over the bright
            // golden-hour sky, and additive blending washes the white and red
            // phases into the warm background — only green survived. The assets
            // are pre-baked blooms with their own alpha, so normal blending
            // renders true white/red/green and the orb covers the pole top.
            glow.blendMode = .alpha
            light.addChild(glow)

            runWave(on: glow, textures: glowTextures, index: i)
        }
    }

    /// Drives one glow orb's wave: the shared white→red→green color cycle,
    /// started after `index × waveDelta` so the color sweeps the row
    /// left-to-right, plus an alpha pulse (FinishLineNode aura idiom) so the
    /// light genuinely glows rather than swapping flat colors.
    private func runWave(on glow: SKSpriteNode, textures: [SKTexture], index: Int) {
        // setTexture(_:) keeps the node's size, so the orb never resizes as it
        // cycles. One step per color, each shown for `colorDuration` seconds.
        let cycle = SKAction.repeatForever(SKAction.sequence(
            textures.map { texture in
                SKAction.sequence([SKAction.setTexture(texture),
                                   SKAction.wait(forDuration: Self.colorDuration)])
            }
        ))
        let startDelay = SKAction.wait(forDuration: Double(index) * Self.waveDelta)
        glow.run(SKAction.sequence([startDelay, cycle]))

        // Independent alpha pulse, but with a higher floor than the finish-line
        // aura: these orbs are the primary colored light, and over the bright
        // golden-hour sky a deep dip washes the red and white phases out to
        // amber. A subtle 0.7↔1.0 pulse keeps all three colors vivid while
        // still glowing.
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])))
    }
}
