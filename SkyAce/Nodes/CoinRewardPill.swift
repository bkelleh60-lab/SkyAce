import SpriteKit

/// The gold coin-reward pill: a fully-rounded rectangle behind a centered
/// `CoinAmountNode` ("+ <amount>" with the bundled coin glyph).
///
/// Extracted from `ResultsScene.buildWin()` (SKY-95) so the mission-end reward
/// and the Landing Practice smooth-landing reward render the identical visual
/// treatment. Used two ways:
///
/// * Mission end — built at `0`, then `animateCountUp(to:)` rolls the number up
///   to the level reward.
/// * Landing Practice — built at the fixed `+50` reward, then `animateIn()`
///   pops it onto the feedback layer after the smooth-landing badge.
final class CoinRewardPill: SKNode {

    /// Default pill height, exposed so callers positioning content relative to
    /// the pill (e.g. the Runway Challenge celebration badge) stay in sync if
    /// the default size changes (SKY-124).
    static let defaultHeight: CGFloat = 48

    /// The rounded-rect gold background.
    private let pill: SKShapeNode
    /// The "+ <amount>" coin glyph + number drawn centered on the pill.
    private let coinLabel: CoinAmountNode

    /// Builds the pill at its resting scale showing `amount`.
    /// - Parameters:
    ///   - amount: the coin value rendered after the "+ " prefix.
    ///   - prefix: leading text before the coin glyph (default "+ ").
    ///   - pillSize: the rounded-rect background size (default matches the
    ///     mission-end pill).
    ///   - fontSize: amount/prefix point size (default matches mission end).
    init(amount: Int,
         prefix: String = "+ ",
         pillSize: CGSize = CGSize(width: 200, height: CoinRewardPill.defaultHeight),
         fontSize: CGFloat = 20) {
        pill = SKShapeNode(rectOf: pillSize, cornerRadius: pillSize.height / 2)
        pill.fillColor = SkyColors.skTertiaryContainer
        pill.strokeColor = .clear

        coinLabel = CoinAmountNode(
            prefix: prefix,
            amount: "\(amount)",
            fontName: SkyFonts.headlineName,
            fontSize: fontSize,
            color: SkyColors.skOnTertiaryContainer
        )

        super.init()
        addChild(pill)
        addChild(coinLabel)
    }

    /// Not supported — this node is only ever built in code.
    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Replaces the displayed amount (re-lays out the icon/number).
    func setAmount(_ amount: Int) {
        coinLabel.setAmount("\(amount)")
    }

    /// Rolls the amount from 0 up to `target` over a short sequence — the
    /// mission-end count-up. Runs on the coin label so the pill background
    /// stays put.
    func animateCountUp(to target: Int) {
        let steps = 30
        let stepDuration = 0.030
        var actions: [SKAction] = []
        for i in 0...steps {
            let value = Int(round(Double(target) * Double(i) / Double(steps)))
            actions.append(SKAction.run { [weak self] in self?.setAmount(value) })
            actions.append(SKAction.wait(forDuration: stepDuration))
        }
        coinLabel.run(SKAction.sequence(actions))
    }

    /// Pops the pill in from a slightly shrunken, transparent state — the
    /// Landing Practice reward entrance. Call after adding the pill at
    /// `alpha = 0`.
    func animateIn() {
        alpha = 0
        setScale(0.6)
        let scale = SKAction.scale(to: 1.0, duration: 0.25)
        scale.timingMode = .easeOut
        run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.2),
            scale
        ]))
    }
}
