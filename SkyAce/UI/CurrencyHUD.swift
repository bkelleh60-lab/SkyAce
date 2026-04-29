import SpriteKit

/// Top-right HUD showing the player's current coin and ring totals as two
/// pill-shaped badges. Each pill renders the asset icon on the left and the
/// running total on the right; the count pops on every increment.
///
/// Pills lay out side by side when horizontal space allows; if the available
/// width is too tight the ring pill drops below the coin pill so neither
/// runs into the screen edge or other top-bar UI.
final class CurrencyHUD: SKNode {

    private let coinPill: CurrencyPill
    private let ringPill: CurrencyPill
    private let maxLabel: SKLabelNode

    /// Vertical/horizontal gap between pills when stacked / side-by-side.
    private let pillGap: CGFloat = 8

    /// Total bounding size of the HUD with whichever layout (side-by-side
    /// or stacked) was last applied via `layout(maxWidth:)`. Used by scenes
    /// to position the HUD so its right edge sits a fixed margin in from
    /// the screen edge.
    private(set) var contentSize: CGSize = .zero

    override init() {
        coinPill = CurrencyPill(
            iconAssetName: SkySprites.coin,
            iconFallbackEmoji: "🪙",
            fillColor: SkyColors.tertiaryContainer,
            textColor: SkyColors.onTertiaryContainer,
            initialValue: CurrencyManager.shared.coinTotal
        )
        ringPill = CurrencyPill(
            iconAssetName: SkySprites.ring,
            iconFallbackEmoji: "💍",
            fillColor: SkyColors.skPrimaryContainer,
            textColor: SkyColors.skOnPrimary,
            initialValue: CurrencyManager.shared.ringTotal
        )
        maxLabel = SKLabelNode(text: "MAX")
        super.init()

        maxLabel.fontName = SkyFonts.headlineName
        maxLabel.fontSize = 9
        maxLabel.fontColor = SkyColors.onTertiaryContainer.withAlphaComponent(0.7)
        maxLabel.verticalAlignmentMode = .top
        maxLabel.horizontalAlignmentMode = .right
        maxLabel.zPosition = 3
        maxLabel.isHidden = true
        addChild(maxLabel)

        addChild(coinPill)
        addChild(ringPill)

        observeUpdates()
        refreshMaxIndicator(coinTotal: CurrencyManager.shared.coinTotal)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    /// Lay the two pills out so the bounding box never exceeds `maxWidth`.
    /// Falls back to a vertical stack when side-by-side won't fit. The HUD
    /// node's anchor (origin) is the *right* edge horizontally and the
    /// *vertical center*, which lets scenes position it via:
    ///
    ///     hud.position = CGPoint(x: rightEdge - margin, y: barCenterY)
    ///
    /// regardless of which layout was chosen.
    func layout(maxWidth: CGFloat) {
        let coinSize = coinPill.pillSize
        let ringSize = ringPill.pillSize
        let sideBySideWidth = coinSize.width + pillGap + ringSize.width

        if sideBySideWidth <= maxWidth {
            // Right-anchored side by side: ring on the right, coin to its left.
            ringPill.position = CGPoint(x: -ringSize.width / 2, y: 0)
            coinPill.position = CGPoint(
                x: -ringSize.width - pillGap - coinSize.width / 2,
                y: 0
            )
            contentSize = CGSize(
                width: sideBySideWidth,
                height: max(coinSize.height, ringSize.height)
            )
        } else {
            // Stacked: coin on top, ring below. Both right-aligned.
            let widest = max(coinSize.width, ringSize.width)
            let stackedHeight = coinSize.height + pillGap + ringSize.height
            coinPill.position = CGPoint(
                x: -coinSize.width / 2,
                y: (stackedHeight / 2) - (coinSize.height / 2)
            )
            ringPill.position = CGPoint(
                x: -ringSize.width / 2,
                y: -(stackedHeight / 2) + (ringSize.height / 2)
            )
            contentSize = CGSize(width: widest, height: stackedHeight)
        }

        // Anchor the MAX label to the bottom-right corner of the coin pill.
        maxLabel.position = CGPoint(
            x: coinPill.position.x + coinPill.pillSize.width / 2,
            y: coinPill.position.y - coinPill.pillSize.height / 2
        )
    }

    // MARK: - Notifications

    private func observeUpdates() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCoinUpdate(_:)),
            name: CurrencyManager.coinTotalDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRingUpdate(_:)),
            name: CurrencyManager.ringTotalDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEntitlementChange),
            name: IAPManager.entitlementDidChange,
            object: nil
        )
    }

    @objc private func handleCoinUpdate(_ note: Notification) {
        let total = (note.userInfo?["total"] as? Int) ?? CurrencyManager.shared.coinTotal
        coinPill.setValue(total, animated: true)
        refreshMaxIndicator(coinTotal: total)
    }

    @objc private func handleRingUpdate(_ note: Notification) {
        let total = (note.userInfo?["total"] as? Int) ?? CurrencyManager.shared.ringTotal
        ringPill.setValue(total, animated: true)
    }

    @objc private func handleEntitlementChange() {
        refreshMaxIndicator(coinTotal: CurrencyManager.shared.coinTotal)
    }

    private func refreshMaxIndicator(coinTotal: Int) {
        let atCap = coinTotal >= CurrencyManager.freeCoinCap && !IAPManager.shared.isContentUnlocked
        maxLabel.isHidden = !atCap
    }
}

// MARK: - Pill

/// Single rounded badge: icon on the left, count label on the right.
/// Internal layout uses fixed paddings so width grows naturally with longer
/// counts (e.g. 9999) while keeping vertical metrics stable.
private final class CurrencyPill: SKNode {

    private let iconSize: CGFloat = 18
    private let pillHeight: CGFloat = 32
    private let horizontalPadding: CGFloat = 10
    private let iconLabelSpacing: CGFloat = 6
    private let labelFontSize: CGFloat = 14

    private let fillColor: UIColor
    private let textColor: UIColor

    private var background: SKShapeNode!
    private let label: SKLabelNode

    private(set) var pillSize: CGSize = .zero

    init(iconAssetName: String,
         iconFallbackEmoji: String,
         fillColor: UIColor,
         textColor: UIColor,
         initialValue: Int) {
        self.fillColor = fillColor
        self.textColor = textColor

        self.label = SKLabelNode(text: "\(initialValue)")
        super.init()

        label.fontName = SkyFonts.headlineName
        label.fontSize = labelFontSize
        label.fontColor = textColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        label.zPosition = 2

        let icon = SkySprites.iconNode(
            named: iconAssetName,
            fallbackEmoji: iconFallbackEmoji,
            size: iconSize,
            color: textColor
        )
        icon.zPosition = 2

        // Compute width to fit current label, then build pill background.
        let labelWidth = label.frame.width
        let pillWidth = horizontalPadding + iconSize + iconLabelSpacing + labelWidth + horizontalPadding
        pillSize = CGSize(width: pillWidth, height: pillHeight)

        background = SKShapeNode(rectOf: pillSize, cornerRadius: pillHeight / 2)
        background.fillColor = fillColor
        background.strokeColor = .clear
        background.zPosition = 0
        addChild(background)

        // Icon centered vertically, sitting against the left interior padding.
        let iconX = -pillWidth / 2 + horizontalPadding + iconSize / 2
        icon.position = CGPoint(x: iconX, y: 0)
        addChild(icon)

        // Label starts immediately to the right of the icon.
        let labelX = iconX + iconSize / 2 + iconLabelSpacing
        label.position = CGPoint(x: labelX, y: 0)
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Update the count. When `animated` is true, the label briefly scales
    /// up and back to draw the eye to the increment.
    func setValue(_ value: Int, animated: Bool) {
        label.text = "\(value)"
        rebuildBackgroundIfNeeded()
        if animated {
            label.removeAllActions()
            label.run(SKAction.sequence([
                SKAction.scale(to: 1.35, duration: 0.10),
                SKAction.scale(to: 1.0, duration: 0.15)
            ]))
        }
    }

    /// Resize the background pill if a longer/shorter label changed the
    /// required width (e.g. crossing 9 → 10, 99 → 100, etc.).
    private func rebuildBackgroundIfNeeded() {
        let labelWidth = label.frame.width
        let pillWidth = horizontalPadding + iconSize + iconLabelSpacing + labelWidth + horizontalPadding
        guard abs(pillWidth - pillSize.width) > 0.5 else { return }
        pillSize = CGSize(width: pillWidth, height: pillHeight)
        background.removeFromParent()
        background = SKShapeNode(rectOf: pillSize, cornerRadius: pillHeight / 2)
        background.fillColor = fillColor
        background.strokeColor = .clear
        background.zPosition = 0
        addChild(background)
    }
}
