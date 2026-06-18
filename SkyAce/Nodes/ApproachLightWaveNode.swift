import SpriteKit

/// Approach-light wave for Landing Practice (SKY-99).
///
/// An infinite, recycling row of glowing orbs that scroll in with the rest of
/// the airfield (grass, runway) and cycle white → red → green in a wave that
/// runs along them toward the threshold, like sequenced ALSF approach lighting.
///
/// The orbs scroll at the runway's on-screen rate (driven by the scene calling
/// `scroll(by:)` each frame) and recycle off the left edge to the right so the
/// row never runs out — the same trick the grass strip uses. Because a
/// recycling row has no stable per-orb identity, the colour wave is driven by
/// each orb's **world position** plus time (`updateWave(time:)`), not a fixed
/// index: the recycle jump is a whole number of wave periods, so colours stay
/// continuous across it. A subtle alpha pulse layered on top keeps the orbs
/// genuinely glowing. Builds nothing if any glow asset is missing.
final class ApproachLightWaveNode: SKNode {

    // MARK: - Tunables

    /// Seconds each colour shows before transitioning to the next; the full
    /// white→red→green cycle therefore takes `colorDuration × 3`.
    static let colorDuration: TimeInterval = 0.4
    /// Distance between adjacent orbs (points) — wider than the orb so the
    /// lights read as a row of distinct points rather than a merged strip.
    private static let spacing: CGFloat = 64
    /// Rendered diameter of each glow orb.
    private static let glowSize: CGFloat = 52
    /// Orb-centre height above the row base (the node origin sits at the runway
    /// surface line; the orbs hover just above the grass — no poles, SKY-99).
    private static let glowCenterHeight: CGFloat = 52
    /// Orbs per full colour cycle in world space — adjacent orbs are offset by
    /// `1 / lightsPerCycle` of a cycle, giving the travelling-wave gradient.
    private static let lightsPerCycle = 10
    /// How far past a screen edge an orb travels before it recycles.
    private static let recycleMargin: CGFloat = 80

    // MARK: - State

    private var glowTextures: [SKTexture] = []
    private var orbs: [SKSpriteNode] = []
    /// World-space X of each orb (screen X = worldX − cameraX). Conserved as the
    /// orb scrolls; bumped by a whole `trainWidth` (an integer number of wave
    /// periods) on recycle so the colour wave stays continuous.
    private var worldX: [CGFloat] = []
    /// Accumulated leftward scroll — increases as the world slides left.
    private var cameraX: CGFloat = 0
    /// Total width of the orb train; also the recycle jump distance.
    private var trainWidth: CGFloat = 0
    private var sceneWidth: CGFloat = 0

    /// Spatial period (world points) of one full white→red→green cycle.
    private var spatialPeriod: CGFloat { Self.spacing * CGFloat(Self.lightsPerCycle) }
    /// Seconds for the wave to advance one full cycle along the row.
    private var cycleDuration: TimeInterval { Self.colorDuration * 3 }

    // MARK: - Init

    /// Builds a row wide enough to cover `sceneWidth` plus a full recycling
    /// train. Adds no orbs if any glow asset is missing.
    init(sceneWidth: CGFloat) {
        super.init()
        build(sceneWidth: sceneWidth)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func build(sceneWidth: CGFloat) {
        guard let white = SkySprites.texture(named: SkySprites.approachLightGlowWhite),
              let red = SkySprites.texture(named: SkySprites.approachLightGlowRed),
              let green = SkySprites.texture(named: SkySprites.approachLightGlowGreen)
        else { return }
        glowTextures = [white, red, green]
        self.sceneWidth = sceneWidth

        // Train length: enough to cover the screen plus both recycle margins,
        // rounded up to a whole number of wave cycles so the recycle jump
        // (`trainWidth`) is an integer number of spatial periods — that keeps
        // the colour wave continuous when an orb wraps around.
        let needed = (sceneWidth + 2 * Self.recycleMargin) / Self.spacing
        let cycles = max(2, Int((needed / CGFloat(Self.lightsPerCycle)).rounded(.up)))
        let count = cycles * Self.lightsPerCycle
        trainWidth = CGFloat(count) * Self.spacing

        let glow = CGSize(width: Self.glowSize, height: Self.glowSize)
        for i in 0..<count {
            let x = CGFloat(i) * Self.spacing
            let orb = SKSpriteNode(texture: white, size: glow)
            orb.position = CGPoint(x: x, y: Self.glowCenterHeight)
            orb.zPosition = 1
            // Normal alpha blend (not additive): over the bright golden-hour sky
            // additive washes the white and red phases into the warm background.
            // The assets carry their own alpha, so normal blending renders true
            // white/red/green.
            orb.blendMode = .alpha
            addChild(orb)
            orbs.append(orb)
            worldX.append(x)

            // Subtle independent alpha pulse so each orb genuinely glows.
            orb.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.7, duration: 0.5),
                .fadeAlpha(to: 1.0, duration: 0.5)
            ])))
        }
    }

    // MARK: - Per-frame driving (called by the scene)

    /// Scrolls the row by `dx` (negative = left, with the runway) and recycles
    /// any orb that has travelled a full margin past either screen edge, jumping
    /// it a whole `trainWidth` to the far side so the row stays unbroken.
    func scroll(by dx: CGFloat) {
        guard !orbs.isEmpty, dx != 0 else { return }
        cameraX -= dx
        for i in orbs.indices {
            var sx = worldX[i] - cameraX
            if dx < 0 {
                while sx < -Self.recycleMargin { worldX[i] += trainWidth; sx = worldX[i] - cameraX }
            } else {
                while sx > sceneWidth + Self.recycleMargin { worldX[i] -= trainWidth; sx = worldX[i] - cameraX }
            }
            orbs[i].position.x = sx
        }
    }

    /// Advances the colour wave for the given scene time. Each orb's colour is a
    /// function of its world position and `time`, so the wave runs smoothly
    /// along the row (toward the threshold) and animates even while the scroll
    /// is paused. Only swaps a texture when the colour actually changes.
    func updateWave(time: TimeInterval) {
        guard !orbs.isEmpty else { return }
        let period = spatialPeriod
        let phaseOverTime = time / cycleDuration
        for i in orbs.indices {
            let phase = Double(worldX[i] / period) - phaseOverTime
            let frac = phase - floor(phase)            // [0, 1)
            let index = min(2, Int(frac * 3))          // white | red | green
            let texture = glowTextures[index]
            if orbs[i].texture !== texture { orbs[i].texture = texture }
        }
    }
}
