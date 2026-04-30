import SpriteKit
import UIKit

/// Persistent 4-tab bottom navigation bar:
///
///     [ Home ]  [ Hangar ]  [ Missions ]  [ Shop ]
///
/// All four tabs share the same baseline and visual treatment. The active
/// tab — set by each scene at construction — renders at full opacity in the
/// primary color; inactive tabs dim to 60–70% opacity with the on-surface-
/// variant color so the active state always reflects the current screen.
///
/// Position the bar with its **center at y = bottomInset + barHeight / 2**.
/// The icon/label content sits in the upper `barHeight` strip; when a
/// `bottomInset` is supplied the surface fill extends downward by that
/// amount so the bar reads as flush with the device's bottom edge while
/// the home indicator passes safely below the touch targets.
final class SkyTabBar: SKNode {
    enum Tab: Int { case home, hangar, missions, shop }

    private let barWidth: CGFloat
    private let bottomInset: CGFloat
    static let barHeight: CGFloat = 80

    let active: Tab

    init(active: Tab, width: CGFloat, bottomInset: CGFloat = 0) {
        self.active = active
        self.barWidth = width
        self.bottomInset = bottomInset
        super.init()
        buildBar()
        buildTabs()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Bar background (rounded top corners only)

    private func buildBar() {
        let bar = SKShapeNode(path: Self.topRoundedRectPath(
            size: CGSize(width: barWidth, height: Self.barHeight),
            topRadius: 40
        ))
        bar.fillColor = SkyColors.surfaceContainerLow
        bar.strokeColor = .clear
        bar.zPosition = 0
        addChild(bar)

        // Extend the surface fill below the bar through the home-indicator
        // safe-area region so the bar reads flush with the screen edge.
        if bottomInset > 0 {
            let fill = SKSpriteNode(
                color: SkyColors.surfaceContainerLow,
                size: CGSize(width: barWidth, height: bottomInset)
            )
            fill.position = CGPoint(x: 0, y: -Self.barHeight / 2 - bottomInset / 2)
            fill.zPosition = 0
            addChild(fill)
        }

        // Subtle ambient shadow above the bar (matches the mockup's
        // upward-casting shadow).
        let shadow = SkyUIEffects.shadowSprite(
            size: CGSize(width: barWidth, height: Self.barHeight),
            cornerRadius: 40,
            color: SkyColors.onSurface.withAlphaComponent(0.08),
            blur: 16,
            spread: -4
        )
        shadow.zPosition = -1
        addChild(shadow)
    }

    // MARK: - Tabs

    private func buildTabs() {
        // `justify-around` puts each tab at (0.125, 0.375, 0.625, 0.875) of the
        // bar width, measured from the bar's left edge. We translate into the
        // bar's centered coordinate space with an X offset of -barWidth/2.
        let slots: [(Tab, CGFloat)] = [
            (.home,     barWidth * 0.125),
            (.hangar,   barWidth * 0.375),
            (.missions, barWidth * 0.625),
            (.shop,     barWidth * 0.875)
        ]

        for (tab, xInBar) in slots {
            let x = xInBar - barWidth / 2
            let node = buildStandardTab(tab)
            node.position = CGPoint(x: x, y: 0)
            node.zPosition = 2
            node.name = "tab-\(tab.rawValue)"
            addChild(node)
        }
    }

    private func buildStandardTab(_ tab: Tab) -> SKNode {
        let isActive = (tab == active)
        let group = SKNode()

        let (spriteName, emoji, title): (String, String, String) = {
            switch tab {
            case .home:     return (SkySprites.iconHome,     "⌂",  "HOME")
            case .hangar:   return (SkySprites.tabHangar,    "✈",  "HANGAR")
            case .missions: return (SkySprites.iconMissions, "📋", "MISSIONS")
            case .shop:     return (SkySprites.tabShop,      "🛒", "SHOP")
            }
        }()
        let color: UIColor = isActive ? SkyColors.primary : SkyColors.onSurfaceVariant

        // Hangar gets a building SF Symbol so it is visually distinct from the
        // Free Flight airplane icon on the home screen.
        let icon: SKNode
        if tab == .hangar {
            icon = SkySprites.sfSymbolNode(systemName: "building.2.fill", size: 22, color: color)
        } else {
            icon = SkySprites.iconNode(named: spriteName, fallbackEmoji: emoji, size: 22, color: color)
        }
        icon.position = CGPoint(x: 0, y: 8)
        icon.alpha = isActive ? 1.0 : 0.6
        group.addChild(icon)

        let label = SKLabelNode(text: title)
        label.fontName = SkyFonts.headlineName
        label.fontSize = 9
        label.fontColor = color
        label.alpha = isActive ? 1.0 : 0.7
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -14)
        group.addChild(label)

        return group
    }

    // MARK: - Touch dispatch

    /// Called by the parent scene's touch handler with a point in the scene's
    /// coordinate space. Returns true if the tap was on a tab and was handled.
    @discardableResult
    func handleTap(sceneLocation: CGPoint) -> Bool {
        let local = convert(sceneLocation, from: parent ?? self)
        for node in nodes(at: local) {
            var n: SKNode? = node
            while let current = n {
                if let name = current.name, name.hasPrefix("tab-"),
                   let raw = Int(name.replacingOccurrences(of: "tab-", with: "")),
                   let tab = Tab(rawValue: raw) {
                    AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                    SkyHaptics.uiTap()
                    switch tab {
                    case .home:     SkyNavigator.shared.showMenu()
                    case .hangar:   SkyNavigator.shared.showHangar()
                    case .missions: SkyNavigator.shared.showMap()
                    case .shop:     SkyNavigator.shared.showShop()
                    }
                    return true
                }
                n = current.parent
            }
        }
        return false
    }

    // MARK: - Helpers

    /// CGPath for a rectangle with only the TOP two corners rounded — the
    /// bottom stays square so the bar sits flush against the screen edge.
    private static func topRoundedRectPath(size: CGSize, topRadius: CGFloat) -> CGPath {
        let r = min(topRadius, size.height, size.width / 2)
        let w = size.width
        let h = size.height
        let x = -w / 2
        let y = -h / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y + h - r))
        path.addArc(
            withCenter: CGPoint(x: x + w - r, y: y + h - r),
            radius: r,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: x + r, y: y + h))
        path.addArc(
            withCenter: CGPoint(x: x + r, y: y + h - r),
            radius: r,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.close()
        return path.cgPath
    }
}
