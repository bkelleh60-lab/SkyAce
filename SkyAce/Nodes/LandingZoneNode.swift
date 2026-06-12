import SpriteKit

/// Runway strip + touchdown target for Landing Practice (SKY-83, approach
/// redesign SKY-94).
///
/// The tarmac is a row of identical strip tiles inside `tileContainer`,
/// recycled left-to-right by `updateTiling(in:)` so the runway can keep
/// scrolling for as long as the free-approach phase lasts. The landing zone
/// (indicator + touchdown sensor) sits at the node's local origin and starts
/// concealed; when the player descends through the approach window the scene
/// re-anchors the origin with `realignOrigin(toX:)` — a counter-shifted jump
/// that leaves the tarmac visually untouched — and reveals the zone exactly
/// where the deceleration will halt it.
///
/// Physics follows the FinishLineNode pattern: detection only
/// (`PhysicsCategory.landingZone`), no push-back — the scene reads the
/// plane's vertical velocity in `didBegin(_:)` and resolves the landing
/// quality tier itself.
///
/// Local coordinate contract: the node's origin sits ON the runway surface
/// at the center of the touchdown zone. Scenes position the node so origin.x
/// is the plane's lane and origin.y is the ground line, and can settle a
/// landed plane directly against `position.y`.
final class LandingZoneNode: SKNode {

    /// Rendered tarmac height. Each tile's width follows from the strip
    /// art's aspect ratio so centerline dashes don't stretch.
    static let runwayHeight: CGFloat = 110

    /// Rendered size of the landing zone indicator box.
    static let zoneSize = CGSize(width: 84, height: 64)

    /// Touchdown sensor: zone-box width, extending this far up from the
    /// runway surface. Contact fires when the plane's hitbox bottom
    /// (center − 13.5) crosses the band top, i.e. at plane center
    /// ≈ surface + 26.5 — which is exactly where the gear-down sprites'
    /// wheels graze the tarmac at the 2x Free Flight visual scale (wheel
    /// bottoms sit 22–30pt below the node center across the four planes).
    /// Keeps the velocity read and feedback at the moment of *visual*
    /// touchdown.
    static let sensorHeight: CGFloat = 13

    /// Fraction of one strip tile that leads the node origin on the initial
    /// scroll-in, so tarmac is already on screen ahead of the zone point —
    /// short of halfway, like real touchdown markers near the approach
    /// threshold.
    private static let leadInFraction: CGFloat = 0.3

    /// Fraction of the strip's height (from its top edge) where the
    /// centerline dashes sit in the runway art — measured rows 114–123 of
    /// 240. The road is drawn in gentle perspective, so the *visual*
    /// touchdown line is the dash row, not the strip's top edge: a plane
    /// belongs in the road with its wheels on the dashes.
    private static let surfaceFraction: CGFloat = 0.494

    /// Rendered width of one runway strip tile.
    private(set) var stripWidth: CGFloat = 0

    /// How far below the node origin (the strip's top edge) the visual
    /// touchdown line sits. Scenes settle the plane's wheels here and the
    /// touchdown sensor rises from here.
    private(set) var surfaceDrop: CGFloat = 0

    private let tileContainer = SKNode()
    private var tiles: [SKSpriteNode] = []
    private let zoneAssembly = SKNode()

    init(sceneWidth: CGFloat) {
        super.init()
        buildStrip(sceneWidth: sceneWidth)
        buildZoneIndicator()
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildStrip(sceneWidth: CGFloat) {
        let height = LandingZoneNode.runwayHeight
        let texture = SkySprites.texture(named: SkySprites.runwayStrip)
        let tileSize: CGSize
        if let texture = texture {
            let aspect = texture.size().height > 0
                ? texture.size().width / texture.size().height
                : 5.6
            tileSize = CGSize(width: height * aspect, height: height)
        } else {
            // Asset missing — neutral tarmac blocks so the mode still plays.
            tileSize = CGSize(width: sceneWidth * 1.6, height: height)
        }
        stripWidth = tileSize.width
        surfaceDrop = height * LandingZoneNode.surfaceFraction

        tileContainer.zPosition = 0
        addChild(tileContainer)

        // Enough tiles to span the widest screen plus spares, so a tile that
        // exits left can always be recycled to the right end before a gap
        // would scroll into view.
        let tileCount = max(2, Int(ceil(sceneWidth / stripWidth)) + 2)
        for _ in 0..<tileCount {
            let tile: SKSpriteNode
            if let texture = texture {
                tile = SKSpriteNode(texture: texture, size: tileSize)
            } else {
                tile = SKSpriteNode(color: UIColor(hex: 0x55505E), size: tileSize)
            }
            tile.anchorPoint = CGPoint(x: 0, y: 1.0)
            tiles.append(tile)
            tileContainer.addChild(tile)
        }
        layoutTiles()
    }

    /// Initial layout: the leading tarmac edge sits `leadInFraction` of a
    /// tile left of the origin, the rest trailing contiguously to the right.
    private func layoutTiles() {
        for (index, tile) in tiles.enumerated() {
            tile.position = CGPoint(
                x: stripWidth * (CGFloat(index) - LandingZoneNode.leadInFraction),
                y: 0
            )
        }
    }

    private func buildZoneIndicator() {
        let zone: SKSpriteNode
        if let texture = SkySprites.texture(named: SkySprites.landingZoneIndicator) {
            zone = SKSpriteNode(texture: texture, size: LandingZoneNode.zoneSize)
        } else {
            zone = SKSpriteNode(color: UIColor(hex: 0xFFD709), size: LandingZoneNode.zoneSize)
        }
        // Hover above the runway strip pointing down at the touchdown
        // spot, with a gentle bob so it reads as "land here" on approach.
        // Anchored to the strip's top edge (not the touchdown line) so the
        // box never overlaps the road, including at the bottom of the bob.
        zone.position = CGPoint(x: 0, y: LandingZoneNode.zoneSize.height / 2 + 26)
        zone.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 8, duration: 0.7),
            SKAction.moveBy(x: 0, y: -8, duration: 0.7)
        ])))
        zoneAssembly.zPosition = 1
        zoneAssembly.alpha = 0   // concealed until the approach window opens (SKY-94)
        zoneAssembly.addChild(zone)
        addChild(zoneAssembly)
    }

    private func configurePhysics() {
        // Sensor band rising from the touchdown line over the zone. The
        // plane's descending hitbox enters it right where the indicator
        // points; contact-only so the plane never bounces off it.
        let size = CGSize(width: LandingZoneNode.zoneSize.width,
                          height: LandingZoneNode.sensorHeight)
        let pb = SKPhysicsBody(
            rectangleOf: size,
            center: CGPoint(x: 0, y: -surfaceDrop + size.height / 2)
        )
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.landingZone
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        physicsBody = pb
    }

    // MARK: - Approach scroll support (SKY-94)

    /// Node origin X that puts the tarmac's leading edge just past the right
    /// screen edge, ready to cruise in.
    func startOriginX(sceneWidth: CGFloat) -> CGFloat {
        sceneWidth + stripWidth * LandingZoneNode.leadInFraction + 20
    }

    /// Scene X of the tarmac's leading (leftmost) edge. At or below zero
    /// means the strip covers the screen from the left edge — tiling keeps
    /// the right side covered, so the runway is fully established.
    func leadingEdgeX(in scene: SKScene) -> CGFloat {
        tiles
            .map { tileContainer.convert($0.position, to: scene).x }
            .min() ?? .greatestFiniteMagnitude
    }

    /// Recycles any tile that has fully scrolled past the scene's left edge
    /// to the right end of the row, keeping the tarmac unbroken while the
    /// node scrolls left. Call once per frame during the approach.
    func updateTiling(in scene: SKScene) {
        guard var rightmostX = tiles.map({ $0.position.x }).max() else { return }
        for tile in tiles {
            let trailingEdgeX = tileContainer.convert(
                CGPoint(x: tile.position.x + stripWidth, y: 0), to: scene
            ).x
            if trailingEdgeX < 0 {
                rightmostX += stripWidth
                tile.position.x = rightmostX
            }
        }
    }

    /// Jumps the node origin — and with it the concealed zone indicator and
    /// touchdown sensor — to `x` (in the parent's coordinates) while
    /// counter-shifting the tile row so the tarmac doesn't move on screen.
    /// Lets the scene anchor the zone exactly where the deceleration will
    /// halt it, regardless of where the strip happens to be when the player
    /// commits to the landing.
    func realignOrigin(toX x: CGFloat) {
        let delta = x - position.x
        position.x = x
        tileContainer.position.x -= delta
    }

    /// Shows or hides the landing zone indicator. Hidden during the free
    /// approach phase; revealed when the approach window opens.
    func setZoneRevealed(_ revealed: Bool, fade: TimeInterval = 0) {
        zoneAssembly.removeAction(forKey: "zoneReveal")
        if fade <= 0 {
            zoneAssembly.alpha = revealed ? 1 : 0
        } else {
            zoneAssembly.run(
                SKAction.fadeAlpha(to: revealed ? 1 : 0, duration: fade),
                withKey: "zoneReveal"
            )
        }
    }

    /// Resets for a fresh approach: tiles back to the initial lead-in
    /// layout, counter-shift cleared, zone concealed. The scene repositions
    /// the node itself.
    func prepareForApproach() {
        tileContainer.position = .zero
        layoutTiles()
        setZoneRevealed(false)
    }
}
