import SpriteKit

/// Paired cloud-pillar obstacles. One "pair" = a top pillar and a bottom
/// pillar separated by `gap`. Constructed by the scene; the scene moves
/// them leftward via an SKAction sequence.
///
/// Visual rendering is themed via `ObstacleTheme`. Hitbox geometry and
/// `gap` placement are identical across every theme — only the visual
/// changes per level.
final class ObstacleNode: SKNode {

    let gap: CGFloat
    let sceneHeight: CGFloat
    let gapCenterY: CGFloat  // Y coordinate of the middle of the gap.
    let theme: ObstacleTheme

    init(sceneSize: CGSize, gap: CGFloat, theme: ObstacleTheme) {
        self.gap = gap
        self.sceneHeight = sceneSize.height
        self.theme = theme

        // Random vertical placement that keeps both pillars on-screen.
        let margin: CGFloat = 80
        let minCenter = margin + gap / 2
        let maxCenter = sceneSize.height - margin - gap / 2
        self.gapCenterY = CGFloat.random(in: minCenter...maxCenter)

        super.init()
        buildPillars(sceneSize: sceneSize)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Routes obstacle rendering to the correct draw function for the
    /// current theme. Each theme function is responsible for adding the
    /// top and bottom pillars as child nodes with correct physics bodies.
    /// All four themes use sprite-based rendering (Stitch-generated PNG
    /// assets in `Assets.xcassets`). If a theme's asset is missing at
    /// runtime, the renderer falls back to `drawLegacyPillars` so the
    /// level remains playable during development.
    private func buildPillars(sceneSize: CGSize) {
        switch theme {
        case .hotAirBalloons:
            drawHotAirBalloons(sceneSize: sceneSize)
        case .harborPiers:
            drawHarborPiers(sceneSize: sceneSize)
        case .cityBuildings:
            drawCityBuildings(sceneSize: sceneSize)
        case .stormClouds:
            drawStormClouds(sceneSize: sceneSize)
        }
    }

    /// Original red+yellow striped pillar rendering. No theme case routes
    /// to this directly anymore — it survives as an internal fallback
    /// that the sprite-rendering helpers call when their Stitch assets
    /// are missing from the bundle, so the level remains playable in
    /// development even if an asset has not yet been imported.
    private func drawLegacyPillars(sceneSize: CGSize) {
        let pillarWidth: CGFloat = 60

        // Bottom pillar — from y=0 up to gapCenterY - gap/2.
        let bottomHeight = gapCenterY - gap / 2
        if bottomHeight > 0 {
            let bottom = makePillar(width: pillarWidth, height: bottomHeight, isTop: false)
            bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
            addChild(bottom)
        }

        // Top pillar — from gapCenterY + gap/2 up to sceneHeight.
        let topY0 = gapCenterY + gap / 2
        let topHeight = sceneSize.height - topY0
        if topHeight > 0 {
            let top = makePillar(width: pillarWidth, height: topHeight, isTop: true)
            top.position = CGPoint(x: 0, y: topY0 + topHeight / 2)
            addChild(top)
        }
    }

    // MARK: - Sprite-based theme renderers

    /// Hot Air Balloons theme. Stacks multiple balloon sprites vertically
    /// to fill the pillar height, choosing a randomized color variant for
    /// each balloon so a single pillar shows visual variety.
    private func drawHotAirBalloons(sceneSize: CGSize) {
        renderStackedSpriteTheme(
            sceneSize: sceneSize,
            textureNames: [
                "balloon_red",
                "balloon_blue",
                "balloon_yellow",
                "balloon_orange",
            ],
            spriteWidth: 56,
            spriteHeight: 84,
            spriteSpacing: 6
        )
    }

    /// Storm Clouds theme. Custom renderer (does not use
    /// `renderStackedSpriteTheme`) so we can stack plain cloud puffs with
    /// horizontal jitter for an organic column silhouette AND drop a single
    /// lightning bolt at the gap-facing edge of each pillar, oriented to
    /// point INTO the gap (down on top pillars, up on bottom pillars).
    private func drawStormClouds(sceneSize: CGSize) {
        guard let cloudTexture = Self.textureIfPresent("cloud_plain") else {
            drawLegacyPillars(sceneSize: sceneSize)
            return
        }

        let pillarWidth: CGFloat = 60
        let cloudSize = CGSize(width: 90, height: 65)
        let spacing: CGFloat = -25      // heavy overlap so adjacent clouds merge
        let xJitter: CGFloat = 10       // horizontal stagger so the column isn't a rigid line

        let bottomHeight = gapCenterY - gap / 2
        if bottomHeight > 0 {
            let bottom = makeStormCloudPillar(
                width: pillarWidth, height: bottomHeight, isTop: false,
                cloudTexture: cloudTexture, cloudSize: cloudSize,
                spacing: spacing, xJitter: xJitter
            )
            bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
            addChild(bottom)
        }

        let topY0 = gapCenterY + gap / 2
        let topHeight = sceneSize.height - topY0
        if topHeight > 0 {
            let top = makeStormCloudPillar(
                width: pillarWidth, height: topHeight, isTop: true,
                cloudTexture: cloudTexture, cloudSize: cloudSize,
                spacing: spacing, xJitter: xJitter
            )
            top.position = CGPoint(x: 0, y: topY0 + topHeight / 2)
            addChild(top)
        }
    }

    /// A small cartoon lightning bolt — yellow fill, orange outline, classic
    /// zigzag silhouette. Centered on the origin with the sharp point at the
    /// bottom (`y = -size.height / 2`) so the bolt visually "strikes down"
    /// in its default orientation. Flip vertically (`yScale = -1`) to make
    /// it point up.
    private func makeLightningBolt(size: CGSize) -> SKNode {
        let container = SKNode()

        let halfW = size.width / 2
        let halfH = size.height / 2

        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -halfW * 0.20, y:  halfH))               // top
        path.addLine(to: CGPoint(x:  halfW * 0.50, y:  halfH * 0.10))        // right shoulder
        path.addLine(to: CGPoint(x:  halfW * 0.10, y:  halfH * 0.10))        // inner indent
        path.addLine(to: CGPoint(x:  halfW * 0.30, y: -halfH))               // bottom point (strike)
        path.addLine(to: CGPoint(x: -halfW * 0.30, y: -halfH * 0.05))        // left shoulder
        path.addLine(to: CGPoint(x: -halfW * 0.05, y: -halfH * 0.05))        // inner indent
        path.closeSubpath()

        let bolt = SKShapeNode(path: path)
        bolt.fillColor = UIColor(red: 1.00, green: 0.92, blue: 0.30, alpha: 1.0)
        bolt.strokeColor = UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1.0)
        bolt.lineWidth = 1.2
        container.addChild(bolt)

        return container
    }

    /// Builds one storm cloud pillar: a column of overlapping cloud puffs
    /// with x-jitter, plus a single lightning bolt at the gap-facing edge
    /// oriented to point INTO the gap.
    ///
    /// For top pillars (hanging from the top of the screen), the gap-facing
    /// edge is the bottom of the pillar; the lightning bolt renders naturally
    /// (its sharp end points down).
    ///
    /// For bottom pillars (rising from the bottom of the screen), the
    /// gap-facing edge is the top of the pillar; the bolt is vertically
    /// flipped (`yScale = -1`) so its sharp end points up into the gap.
    private func makeStormCloudPillar(
        width: CGFloat, height: CGFloat, isTop: Bool,
        cloudTexture: SKTexture, cloudSize: CGSize,
        spacing: CGFloat, xJitter: CGFloat
    ) -> SKNode {
        let container = SKNode()

        // Stack cloud puffs along the pillar height with horizontal jitter.
        let unitHeight = cloudSize.height + spacing
        let count = max(1, Int((height + spacing) / unitHeight))
        let totalContent = CGFloat(count) * cloudSize.height
            + CGFloat(max(0, count - 1)) * spacing
        let firstYOffset = -height / 2
            + (height - totalContent) / 2
            + cloudSize.height / 2

        for i in 0..<count {
            let yOffset = firstYOffset + CGFloat(i) * unitHeight
            let xPos = CGFloat.random(in: -xJitter ... xJitter)
            let sprite = SKSpriteNode(texture: cloudTexture)
            sprite.size = cloudSize
            sprite.position = CGPoint(x: xPos, y: yOffset)
            container.addChild(sprite)
        }

        // Single lightning bolt at the gap-facing edge, pointing INTO the gap.
        let bolt = makeLightningBolt(size: CGSize(width: 18, height: 38))
        let boltXJitter = CGFloat.random(in: -10 ... 10)
        if isTop {
            // Top pillar: bolt at bottom edge, point down naturally.
            bolt.position = CGPoint(x: boltXJitter, y: -height / 2 + 22)
        } else {
            // Bottom pillar: bolt at top edge, flipped so the point goes up.
            bolt.yScale = -1
            bolt.position = CGPoint(x: boltXJitter, y: height / 2 - 22)
        }
        bolt.zPosition = 10
        container.addChild(bolt)

        // Standard 80% inset hitbox.
        container.physicsBody = makeStandardHitbox(width: width, height: height)

        #if DEBUG
        print(String(format: "[ObstacleNode] storm cloud pillar: %.0fx%.0f puffs=%d bolt=%@",
                     width, height, count, isTop ? "top→down" : "bot→up"))
        #endif

        return container
    }

    /// Harbor Piers theme. A single tall pier sprite scaled vertically to
    /// fill the pillar height. The cap end of the sprite is oriented to face
    /// the gap (top pillar = cap at bottom, bottom pillar = cap at top).
    ///
    /// Sprite PNGs are tight-cropped (no transparent padding), so
    /// `visualWidth` directly controls the rendered pier width. 70pt gives
    /// a small visual overhang past the 60pt hitbox so the pier reads as
    /// substantial without making the pier wildly wider than its collision
    /// area.
    private func drawHarborPiers(sceneSize: CGSize) {
        renderScaledSpriteTheme(
            sceneSize: sceneSize,
            textureNames: [
                "pier_stone",
                "pier_steel",
            ],
            visualWidth: 70
        )
    }

    /// City Buildings theme. A single tall building sprite scaled vertically
    /// to fill the pillar height. The top feature (antenna, cornice, billboard)
    /// is oriented to face the gap.
    ///
    /// Sprite PNGs are tight-cropped. `visualWidth` directly controls the
    /// rendered building width. 70pt gives a small visual overhang past the
    /// 60pt hitbox.
    private func drawCityBuildings(sceneSize: CGSize) {
        renderScaledSpriteTheme(
            sceneSize: sceneSize,
            textureNames: [
                "building_skyscraper",
                "building_residential",
                // "building_commercial" — dropped during SKY-62: source design had
                // a placeholder "Building Commercial" billboard text leaking
                // through and a wide aspect ratio that distorted when stretched
                // to fill a tall pillar. Imageset is removed from the bundle.
                // If we want a third building variant later, re-generate in
                // Stitch with a taller aspect ratio and no placeholder signage.
            ],
            visualWidth: 70
        )
    }

    // MARK: - Sprite rendering helpers

    /// Renders an obstacle pair using a vertical stack of fixed-size sprite
    /// units. One unit is one balloon, one cloud puff, etc. Multiple units
    /// are stacked along the pillar height. Each unit randomizes its texture
    /// from `textureNames`. If no texture in the list is present in the
    /// asset catalog, the entire pair falls back to `drawLegacyPillars` so
    /// the level remains playable while assets are missing.
    private func renderStackedSpriteTheme(
        sceneSize: CGSize,
        textureNames: [String],
        spriteWidth: CGFloat,
        spriteHeight: CGFloat,
        spriteSpacing: CGFloat
    ) {
        let availableTextures = textureNames.compactMap(Self.textureIfPresent)
        guard !availableTextures.isEmpty else {
            drawLegacyPillars(sceneSize: sceneSize)
            return
        }

        let pillarWidth: CGFloat = 60

        let bottomHeight = gapCenterY - gap / 2
        if bottomHeight > 0 {
            let bottom = makeStackedSpritePillar(
                width: pillarWidth, height: bottomHeight, isTop: false,
                textures: availableTextures,
                spriteSize: CGSize(width: spriteWidth, height: spriteHeight),
                spacing: spriteSpacing
            )
            bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
            addChild(bottom)
        }

        let topY0 = gapCenterY + gap / 2
        let topHeight = sceneSize.height - topY0
        if topHeight > 0 {
            let top = makeStackedSpritePillar(
                width: pillarWidth, height: topHeight, isTop: true,
                textures: availableTextures,
                spriteSize: CGSize(width: spriteWidth, height: spriteHeight),
                spacing: spriteSpacing
            )
            top.position = CGPoint(x: 0, y: topY0 + topHeight / 2)
            addChild(top)
        }
    }

    /// Renders an obstacle pair using a single tall sprite scaled to fit
    /// the pillar height. Used for piers and buildings where the obstacle
    /// is one continuous structure rather than a stack of units. The cap
    /// end of the sprite is oriented to face the gap.
    private func renderScaledSpriteTheme(
        sceneSize: CGSize,
        textureNames: [String],
        visualWidth: CGFloat
    ) {
        let availableTextures = textureNames.compactMap(Self.textureIfPresent)
        guard !availableTextures.isEmpty else {
            drawLegacyPillars(sceneSize: sceneSize)
            return
        }

        let pillarWidth: CGFloat = 60

        let bottomHeight = gapCenterY - gap / 2
        if bottomHeight > 0 {
            let texture = availableTextures.randomElement()!
            let bottom = makeScaledSpritePillar(
                width: pillarWidth, height: bottomHeight, isTop: false,
                texture: texture,
                visualWidth: visualWidth
            )
            bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
            addChild(bottom)
        }

        let topY0 = gapCenterY + gap / 2
        let topHeight = sceneSize.height - topY0
        if topHeight > 0 {
            let texture = availableTextures.randomElement()!
            let top = makeScaledSpritePillar(
                width: pillarWidth, height: topHeight, isTop: true,
                texture: texture,
                visualWidth: visualWidth
            )
            top.position = CGPoint(x: 0, y: topY0 + topHeight / 2)
            addChild(top)
        }
    }

    /// Builds one pillar as a vertical stack of sprite units. Number of
    /// units is computed from the pillar height so the stack roughly fills
    /// it. Each unit picks a random texture from `textures`. Hitbox is the
    /// standard 80% inset rectangle on the parent container.
    private func makeStackedSpritePillar(
        width: CGFloat, height: CGFloat, isTop: Bool,
        textures: [SKTexture],
        spriteSize: CGSize,
        spacing: CGFloat
    ) -> SKNode {
        let container = SKNode()

        let unitHeight = spriteSize.height + spacing
        let count = max(1, Int((height + spacing) / unitHeight))
        let totalContent = CGFloat(count) * spriteSize.height
            + CGFloat(max(0, count - 1)) * spacing
        let firstYOffset = -height / 2
            + (height - totalContent) / 2
            + spriteSize.height / 2

        for i in 0..<count {
            let yOffset = firstYOffset + CGFloat(i) * unitHeight
            let texture = textures[Int.random(in: 0..<textures.count)]
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = spriteSize
            sprite.position = CGPoint(x: 0, y: yOffset)
            container.addChild(sprite)
        }

        container.physicsBody = makeStandardHitbox(width: width, height: height)

        #if DEBUG
        print(String(format: "[ObstacleNode] stacked sprite pillar: %.0fx%.0f units=%d (%@)",
                     width, height, count, isTop ? "top" : "bot"))
        #endif

        return container
    }

    /// Builds one pillar as a single sprite scaled to fit the pillar
    /// dimensions. For top pillars, the sprite is vertically flipped so
    /// the cap/feature end faces the gap. Hitbox is the standard 80%
    /// inset rectangle on the parent container.
    private func makeScaledSpritePillar(
        width: CGFloat, height: CGFloat, isTop: Bool,
        texture: SKTexture,
        visualWidth: CGFloat
    ) -> SKNode {
        let container = SKNode()

        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: visualWidth, height: height)
        // Top pillar: flip vertically so the sprite's "top" (cap, antenna)
        // points down toward the gap rather than off-screen.
        if isTop {
            sprite.yScale = -1
        }
        container.addChild(sprite)

        container.physicsBody = makeStandardHitbox(width: width, height: height)

        #if DEBUG
        print(String(format: "[ObstacleNode] scaled sprite pillar: %.0fx%.0f (%@)",
                     visualWidth, height, isTop ? "top, flipped" : "bot"))
        #endif

        return container
    }

    /// Standard 80% inset rectangular physics body, identical to the
    /// hitbox the legacy pillar uses. All themed pillars share this so
    /// gameplay is theme-independent.
    private func makeStandardHitbox(width: CGFloat, height: CGFloat) -> SKPhysicsBody {
        let hitboxWidth  = max(20, width  * 0.8)
        let hitboxHeight = max(20, height * 0.8)
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: hitboxWidth, height: hitboxHeight))
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.obstacle
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        return pb
    }

    /// Returns an `SKTexture` for the named asset only if the asset
    /// exists in the bundle. Used to guard against missing Stitch assets
    /// during development — themes whose texture is missing fall back to
    /// the legacy renderer rather than rendering an invisible obstacle.
    private static func textureIfPresent(_ name: String) -> SKTexture? {
        guard UIImage(named: name) != nil else { return nil }
        return SKTexture(imageNamed: name)
    }

    // MARK: - Legacy

    private func makePillar(width: CGFloat, height: CGFloat, isTop: Bool) -> SKNode {
        let container = SKNode()

        // Hazard-striped barrier: bright red base with yellow diagonal warning
        // stripes. Visual language a kid recognizes instantly as "do not touch."
        // Top and bottom variants render identically so the rule is consistent.
        let cornerRadius: CGFloat = 10
        let rectSize = CGSize(width: width, height: height)

        let base = SKShapeNode(rectOf: rectSize, cornerRadius: cornerRadius)
        base.fillColor = UIColor(red: 0.93, green: 0.20, blue: 0.15, alpha: 1.0)
        base.strokeColor = UIColor(red: 0.55, green: 0.05, blue: 0.05, alpha: 1.0)
        base.lineWidth = 2
        base.zPosition = 0
        container.addChild(base)

        let stripes = makeDiagonalStripes(size: rectSize, cornerRadius: cornerRadius)
        stripes.zPosition = 1
        container.addChild(stripes)

        // Physics body inset ~20% from visible edges on both axes, so the plane
        // only registers a crash when clearly inside the barrier.
        let hitboxWidth  = max(20, width  * 0.8)
        let hitboxHeight = max(20, height * 0.8)
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: hitboxWidth, height: hitboxHeight))
        pb.isDynamic = false
        pb.categoryBitMask = PhysicsCategory.obstacle
        pb.contactTestBitMask = PhysicsCategory.plane
        pb.collisionBitMask = 0
        container.physicsBody = pb

        #if DEBUG
        print(String(format: "[ObstacleNode] pillar visual: %.0fx%.0f  hitbox: %.0fx%.0f (80%% inset, %@)",
                     width, height, hitboxWidth, hitboxHeight, isTop ? "top" : "bot"))
        #endif

        return container
    }

    /// Yellow diagonal warning stripes clipped to a rounded rectangle. Stripes
    /// are drawn as rotated bars that overrun the bounds, then cropped by the
    /// rounded-rect mask so they hug the same silhouette as the red base.
    private func makeDiagonalStripes(size: CGSize, cornerRadius: CGFloat) -> SKCropNode {
        let crop = SKCropNode()

        let mask = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask

        let yellow = UIColor(red: 1.0, green: 0.84, blue: 0.17, alpha: 1.0)
        let stripeSpacing: CGFloat = 22
        let stripeWidth:   CGFloat = 10
        let span = max(size.width, size.height) * 1.6
        let step = stripeSpacing + stripeWidth
        let count = Int((span * 2) / step) + 2

        for i in 0..<count {
            let x = -span + CGFloat(i) * step
            let path = CGMutablePath()
            path.move(to:    CGPoint(x: x,                  y: -span))
            path.addLine(to: CGPoint(x: x + stripeWidth,    y: -span))
            path.addLine(to: CGPoint(x: x + stripeWidth + span * 2, y: span))
            path.addLine(to: CGPoint(x: x + span * 2,       y: span))
            path.closeSubpath()

            let stripe = SKShapeNode(path: path)
            stripe.fillColor = yellow
            stripe.strokeColor = .clear
            crop.addChild(stripe)
        }

        return crop
    }
}
