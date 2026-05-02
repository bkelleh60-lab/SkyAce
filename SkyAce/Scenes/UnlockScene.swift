import SpriteKit

/// Paywall scene. Sky gradient + animated plane-through-rings hero,
/// value bullets, gold UNLOCK button (parental gate → StoreKit purchase),
/// and a Restore Purchase link.
final class UnlockScene: SKScene {

    private var animatedPlane: PlaneNode?
    private var statusLabel: SKLabelNode?

    override func didMove(to view: SKView) {
        backgroundColor = SkyColors.skPrimary
        layoutScene()
    }

    // SKY-55: see MenuScene.didChangeSize. The animated plane and any in-flight
    // status text are dropped; rebuilding the paywall is acceptable since
    // purchase flows route through StoreKit, not scene state.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, !children.isEmpty else { return }
        animatedPlane = nil
        statusLabel = nil
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    private func layoutScene() {
        buildBackground()
        buildHeroAnimation()
        buildCopy()
        buildActions()
        buildDismiss()
    }

    // MARK: - Background

    private func buildBackground() {
        let tex = SKGradientBackgroundNode.gradientTexture(
            size: size, top: SkyColors.skPrimary, bottom: SkyColors.skPrimaryContainer
        )
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        addChild(bg)
    }

    // MARK: - Hero

    private func buildHeroAnimation() {
        let heroY = size.height * 0.72

        // Three rings laid out horizontally.
        let ringSpacing: CGFloat = 110
        for i in 0..<3 {
            let ring = RingNode()
            ring.position = CGPoint(x: size.width / 2 - ringSpacing + CGFloat(i) * ringSpacing, y: heroY)
            ring.zPosition = 5
            ring.pulse()
            addChild(ring)
        }

        let plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID)
        plane.physicsBody = nil
        plane.setScale(0.85)
        plane.zPosition = 10
        addChild(plane)
        animatedPlane = plane

        let path = UIBezierPath()
        path.move(to: CGPoint(x: -40, y: heroY - 10))
        path.addCurve(
            to: CGPoint(x: size.width + 40, y: heroY + 10),
            controlPoint1: CGPoint(x: size.width * 0.33, y: heroY - 50),
            controlPoint2: CGPoint(x: size.width * 0.66, y: heroY + 40)
        )

        let follow = SKAction.follow(path.cgPath, asOffset: false, orientToPath: false, duration: 3.5)
        let reset = SKAction.run { plane.position = CGPoint(x: -40, y: heroY - 10) }
        plane.run(SKAction.repeatForever(SKAction.sequence([follow, reset])))
    }

    // MARK: - Copy

    private func buildCopy() {
        let title = SKLabelNode(text: "Unlock Sky Ace")
        title.fontName = SkyFonts.headlineName
        title.fontSize = 36
        title.fontColor = SkyColors.skOnPrimary
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
        addChild(title)

        let bullets = [
            "All 10 levels",
            "Full upgrade shop",
            "No ads. No subscriptions. Ever."
        ]
        for (index, bullet) in bullets.enumerated() {
            let row = SKNode()

            let check = SKLabelNode(text: "✓")
            check.fontName = SkyFonts.headlineName
            check.fontSize = 20
            check.fontColor = SkyColors.skTertiaryContainer
            check.verticalAlignmentMode = .center
            check.horizontalAlignmentMode = .center
            check.position = CGPoint(x: -110, y: 0)
            row.addChild(check)

            let label = SKLabelNode(text: bullet)
            label.fontName = SkyFonts.bodyMediumName
            label.fontSize = 15
            label.fontColor = SkyColors.skOnPrimary
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: -94, y: 0)
            row.addChild(label)

            row.position = CGPoint(x: size.width / 2, y: size.height * 0.44 - CGFloat(index) * 28)
            addChild(row)
        }
    }

    // MARK: - Actions

    private func buildActions() {
        let unlock = SkyPillButton(
            title: "UNLOCK FOR \(IAPManager.shared.displayPrice)",
            style: .tertiary,
            size: CGSize(width: 260, height: 56)
        ) { [weak self] in
            self?.startPurchaseFlow()
        }
        unlock.position = CGPoint(x: size.width / 2, y: size.height * 0.27)
        unlock.zPosition = 10
        addChild(unlock)

        let restore = SKLabelNode(text: "Restore Purchase")
        restore.fontName = SkyFonts.bodyMediumName
        restore.fontSize = 14
        restore.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.9)
        restore.position = CGPoint(x: size.width / 2, y: size.height * 0.21)
        restore.name = "unlockRestore"
        addChild(restore)

        let status = SKLabelNode(text: " ")
        status.fontName = SkyFonts.bodyName
        status.fontSize = 12
        status.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.85)
        status.position = CGPoint(x: size.width / 2, y: size.height * 0.16)
        addChild(status)
        statusLabel = status

        // Parent-facing footer.
        let footerTop = SKLabelNode(text: "Free to try. One fair price to unlock everything.")
        footerTop.fontName = SkyFonts.bodyName
        footerTop.fontSize = 11
        footerTop.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.65)
        footerTop.position = CGPoint(x: size.width / 2, y: 78)
        addChild(footerTop)

        let footerBottom = SKLabelNode(text: "No ads. No subscriptions. No tricks.")
        footerBottom.fontName = SkyFonts.bodyName
        footerBottom.fontSize = 11
        footerBottom.fontColor = SkyColors.skOnPrimary.withAlphaComponent(0.65)
        footerBottom.position = CGPoint(x: size.width / 2, y: 60)
        addChild(footerBottom)
    }

    private func buildDismiss() {
        let x = SKLabelNode(text: "✕")
        x.fontName = SkyFonts.headlineName
        x.fontSize = 20
        x.fontColor = SkyColors.skOnPrimary
        x.position = CGPoint(x: size.width - 28, y: size.height - 44)
        x.zPosition = 100
        x.name = "unlockClose"
        addChild(x)
    }

    // MARK: - Purchase flow

    private func startPurchaseFlow() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        SkyNavigator.shared.presentParentalGate { [weak self] in
            self?.runPurchase()
        }
    }

    private func runPurchase() {
        statusLabel?.text = "Contacting App Store…"
        Task { @MainActor in
            let result = await IAPManager.shared.purchase()
            await MainActor.run { self.handle(result: result) }
        }
    }

    private func handle(result: PurchaseResult) {
        switch result {
        case .success:
            statusLabel?.text = "Unlocked! Enjoy."
            playUnlockAnimation()
        case .cancelled:
            statusLabel?.text = " "
        case .pending:
            statusLabel?.text = "Purchase pending — check back soon."
        case .failed(let message):
            statusLabel?.text = message
        }
    }

    private func playUnlockAnimation() {
        run(AudioManager.shared.sfxAction(SkySFX.win))
        let flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.alpha = 0
        flash.zPosition = 500
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.8, duration: 0.2),
            SKAction.fadeAlpha(to: 0.0, duration: 0.4)
        ]))
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.1),
            SKAction.run { SkyNavigator.shared.showMap() }
        ]))
    }

    private func runRestore() {
        AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
        statusLabel?.text = "Restoring…"
        Task { @MainActor in
            let ok = await IAPManager.shared.restore()
            await MainActor.run {
                statusLabel?.text = ok ? "Restored! Enjoy." : "Nothing to restore."
                if ok { playUnlockAnimation() }
            }
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
            if node.name == "unlockRestore" { runRestore(); return }
            if node.name == "unlockClose" {
                AudioManager.shared.playSFX(SkySFX.uiTap, on: self)
                SkyNavigator.shared.showMenu()
                return
            }
        }
    }
}
