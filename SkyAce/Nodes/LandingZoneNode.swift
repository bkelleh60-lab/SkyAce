import SpriteKit

/// Runway strip + touchdown target for Landing Practice (SKY-83, approach
/// redesign SKY-94).
///
/// The tarmac is a row of identical strip tiles inside `tileContainer`,
/// recycled left-to-right by `updateTiling(in:)` so the runway can keep
/// scrolling for as long as the free-approach phase lasts. Each tile is one
/// centerline-dash period cropped from the flat-shaded middle of the strip
/// art (see `tileTextureRect`) — NOT the whole picture — so only the
/// lane-marker tarmac repeats and the painted runway-end threshold bars
/// never tile across the screen (SKY-94 playtest fix). The landing zone
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

    /// The repeating slice of the dashes-only `runway_strip.png` (563×122).
    /// Pixels x 158–256 span exactly one centerline-dash period (dashes recur
    /// every ~98px, dash ≈48px / gap ≈49px) over the tarmac content band (rows
    /// 0–116; the bottom 6px is transparent), so the tarmac brightness barely
    /// drifts across the seam. The runway-end threshold is a separate asset
    /// (`runway_threshold.png`), so the strip is pure repeating tarmac.
    /// Normalized, origin bottom-left (rows map to 1−row/height): the content
    /// band's lower edge (row 116) sits 6/122 from the bottom.
    private static let tileTextureRect = CGRect(
        x: 158.0 / 563.0, y: 6.0 / 122.0,
        width: 98.0 / 563.0, height: 116.0 / 122.0
    )

    /// Fraction of the cropped tile's height (from its top edge) where the
    /// centerline dashes sit in the runway art — dash row 56 within the 0–116
    /// content band ⇒ 56/116 ≈ 0.483. The road is drawn in gentle perspective,
    /// so the *visual* touchdown line is the dash row, not the strip's top
    /// edge: a plane belongs in the road with its wheels on the dashes.
    private static let surfaceFraction: CGFloat = 0.483

    /// Rendered width of one runway strip tile.
    private(set) var stripWidth: CGFloat = 0

    /// How far below the node origin (the strip's top edge) the visual
    /// touchdown line sits. Scenes settle the plane's wheels here and the
    /// touchdown sensor rises from here.
    private(set) var surfaceDrop: CGFloat = 0

    /// Painted content band of `runway_threshold.png` (299×251): the runway
    /// cross-section (borders + tarmac + "19" + bars) spans rows 3–245, so the
    /// piece aligns with the tarmac tiles when anchored top-edge at the strip
    /// top. Normalized, origin bottom-left (lower edge row 245 ⇒ 6/251).
    private static let thresholdContentRect = CGRect(
        x: 0, y: 6.0 / 251.0, width: 1.0, height: 242.0 / 251.0
    )

    /// Fraction of the threshold's width over which its left edge is feathered
    /// to transparent, so its (slightly darker) surface blends into the strip
    /// tarmac instead of meeting it with a hard seam. Kept inside the plain
    /// left margin — the "19" begins at x≈18/299 ≈ 0.06 — so the digits aren't
    /// touched.
    private static let thresholdLeftFeatherFrac: CGFloat = 0.055

    private let tileContainer = SKNode()
    private var tiles: [SKSpriteNode] = []
    private let zoneAssembly = SKNode()
    /// Runway-end threshold bars (SKY-93). Hidden during the approach; the
    /// scene reveals them at the taxi stopping point on a smooth/rough landing
    /// so the plane rolls out and halts just before the end of the runway.
    private var thresholdBars: SKSpriteNode?

    init(sceneWidth: CGFloat) {
        super.init()
        buildStrip(sceneWidth: sceneWidth)
        buildZoneIndicator()
        buildThresholdBars()
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildStrip(sceneWidth: CGFloat) {
        let height = LandingZoneNode.runwayHeight

        // Crop the full strip to the one-dash-period repeating slice. Only
        // this slice tiles, so the runway-end bars never repeat across screen.
        let tileTexture = SkySprites.texture(named: SkySprites.runwayStrip)
            .map { SKTexture(rect: LandingZoneNode.tileTextureRect, in: $0) }

        let tileSize: CGSize
        if let tileTexture = tileTexture {
            let px = tileTexture.size()
            let aspect = px.height > 0 ? px.width / px.height : (199.0 / 240.0)
            tileSize = CGSize(width: height * aspect, height: height)
        } else {
            // Asset missing — a modest neutral tarmac tile so the mode still
            // plays and still tiles/recycles like the real art.
            tileSize = CGSize(width: sceneWidth * 0.5, height: height)
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
            if let tileTexture = tileTexture {
                tile = SKSpriteNode(texture: tileTexture, size: tileSize)
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

    /// Builds the hidden runway-end threshold (SKY-93) from
    /// `runway_threshold.png` — the painted end piece (navy surface, the "19"
    /// designation, and the threshold bars). Cropped to its content band and
    /// rendered at the runway height, anchored top-edge at the strip top so it
    /// lines up with the tarmac tiles and reads as the runway's final segment.
    private func buildThresholdBars() {
        guard let texture = LandingZoneNode.featheredThresholdTexture() else { return }
        let px = texture.size()
        let aspect = px.height > 0 ? px.width / px.height : (299.0 / 242.0)
        let h = LandingZoneNode.runwayHeight
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: h * aspect, height: h))
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        sprite.position = .zero
        sprite.zPosition = 0.5   // above the tarmac tiles (0), below the chevron (1)
        sprite.alpha = 0
        addChild(sprite)
        thresholdBars = sprite
    }

    /// Loads `runway_threshold.png`, crops it to its content band, and feathers
    /// the left edge to transparent so the threshold's surface blends into the
    /// strip tarmac with no hard seam. Falls back to an unfeathered crop if the
    /// file can't be read for compositing.
    private static func featheredThresholdTexture() -> SKTexture? {
        guard let url = Bundle.main.url(
                forResource: SkySprites.runwayThreshold, withExtension: "png",
                subdirectory: "Sprites"),
              let image = UIImage(contentsOfFile: url.path),
              let cg = image.cgImage,
              let cropped = cg.cropping(to: CGRect(x: 0, y: 3, width: cg.width, height: cg.height - 9))
        else {
            return SkySprites.texture(named: SkySprites.runwayThreshold)
                .map { SKTexture(rect: thresholdContentRect, in: $0) }
        }
        let w = cropped.width, h = cropped.height
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let faded = renderer.image { ctx in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            // destinationOut: erase fully at the left edge, ramping to keep by
            // the feather end — a soft fade into the tarmac beneath.
            ctx.cgContext.setBlendMode(.destinationOut)
            let colors = [UIColor(white: 0, alpha: 1).cgColor,
                          UIColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors, locations: [0, 1]
            ) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: CGFloat(w) * thresholdLeftFeatherFrac, y: 0),
                options: []
            )
        }
        return SKTexture(image: faded)
    }

    /// Rolls the runway out to its end for a completed landing (SKY-93). The
    /// plane stays fixed in its lane; instead the whole strip scrolls left so
    /// the runway's end travels in from the right and halts with the threshold
    /// bars `gap` points right of `stopSceneX` (the lane). The bars are parked
    /// at the rightmost tile edge — the runway's actual end — and the tiles are
    /// NOT recycled during the roll (the scene is `.landed`, so `update` does
    /// not tile), so the tarmac runs out past the bars and they read as the
    /// terminus. `completion` fires when the roll stops. No-op (immediate
    /// completion) if the bars or scene are missing or the geometry degenerates.
    func rollOutToEnd(stopSceneX: CGFloat, gap: CGFloat, speed: CGFloat,
                      completion: @escaping () -> Void) {
        guard let bars = thresholdBars, let scene = scene, !tiles.isEmpty else {
            completion(); return
        }
        // Rightmost tarmac edge (the runway's end) in scene coordinates.
        let rightEdgeScene = tiles
            .map { tileContainer.convert(CGPoint(x: $0.position.x + stripWidth, y: 0), to: scene).x }
            .max() ?? position.x
        let barsW = bars.size.width
        // Park the bars at the very end of the tarmac (off-screen right) and
        // reveal them; they ride in as the strip scrolls.
        bars.removeAction(forKey: "barsReveal")
        bars.position.x = (rightEdgeScene - barsW / 2) - position.x
        bars.alpha = 1

        // Scroll left so the bars' left edge halts `gap` right of the lane.
        let distance = (rightEdgeScene - barsW) - (stopSceneX + gap)
        guard distance > 0 else { completion(); return }
        let duration = max(0.9, min(2.0, TimeInterval(distance / speed)))
        let roll = SKAction.moveBy(x: -distance, y: 0, duration: duration)
        roll.timingMode = .easeOut
        run(SKAction.sequence([roll, SKAction.run(completion)]), withKey: "rollOut")
    }

    /// Hides the threshold bars and cancels any roll (reset / next approach).
    func hideThresholdBars() {
        removeAction(forKey: "rollOut")
        thresholdBars?.removeAction(forKey: "barsReveal")
        thresholdBars?.alpha = 0
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
    /// layout, counter-shift cleared, zone and end bars concealed. The scene
    /// repositions the node itself.
    func prepareForApproach() {
        tileContainer.position = .zero
        layoutTiles()
        setZoneRevealed(false)
        hideThresholdBars()
    }
}
