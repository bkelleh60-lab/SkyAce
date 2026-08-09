import SpriteKit
import UIKit
import CoreImage

/// Shared visual-effect helpers implementing the "Flat-Plus / Tactile Playground"
/// aesthetic from DESIGN.md:
///   • Linear gradients on hero CTAs (primary → primaryContainer).
///   • Ambient shadows under cards/buttons (onSurface @ 6%, 24–32px blur).
///   • Glassmorphism (backdrop blur + translucent tint) on floating overlays.
///
/// SpriteKit has no native gradient / shadow / backdrop-blur primitives, so each
/// effect is implemented by pre-rendering a UIGraphicsImageRenderer (or CI) pass
/// into an SKTexture that then backs an SKSpriteNode.
enum SkyUIEffects {

    // MARK: - Gradient rounded-rect texture

    /// Vertical linear-gradient rounded-rect texture. Use with SKSpriteNode to
    /// emulate CSS linear-gradient on SpriteKit shapes.
    /// Coordinates run top→bottom in screen space (UIKit), matching DESIGN.md
    /// which describes the "convex" button as lighter top, darker bottom.
    static func gradientTexture(size: CGSize,
                                cornerRadius: CGFloat,
                                top: UIColor,
                                bottom: UIColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }

    // MARK: - Ambient shadow

    /// Soft drop-shadow texture for use behind a card/button. The canvas is
    /// inset by `blur + |spread|` on every side so the shadow can bleed
    /// outside the shape. The returned sprite should be centered on the shape.
    /// Defaults follow DESIGN.md: onSurface @ 6%, 24px blur, -4px spread.
    static func shadowTexture(size: CGSize,
                              cornerRadius: CGFloat,
                              color: UIColor = SkyColors.ambientShadow,
                              blur: CGFloat = 24,
                              spread: CGFloat = -4) -> SKTexture {
        let padding = blur + max(0, -spread) + 4
        let canvas = CGSize(
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // spread > 0 grows the shadow shape beyond the source; < 0 shrinks it.
            let shapeSize = CGSize(
                width: size.width + spread * 2,
                height: size.height + spread * 2
            )
            let origin = CGPoint(
                x: (canvas.width - shapeSize.width) / 2,
                y: (canvas.height - shapeSize.height) / 2
            )
            let path = UIBezierPath(
                roundedRect: CGRect(origin: origin, size: shapeSize),
                cornerRadius: max(0, cornerRadius + spread)
            )
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: blur, color: color.cgColor)
            color.setFill()
            path.fill()
            cg.restoreGState()
        }
        return SKTexture(image: image)
    }

    /// Returns a pre-sized SKSpriteNode centered on .zero — drop behind the
    /// shape it's shadowing.
    static func shadowSprite(size: CGSize,
                             cornerRadius: CGFloat,
                             color: UIColor = SkyColors.ambientShadow,
                             blur: CGFloat = 24,
                             spread: CGFloat = -4) -> SKSpriteNode {
        let texture = shadowTexture(
            size: size,
            cornerRadius: cornerRadius,
            color: color,
            blur: blur,
            spread: spread
        )
        let padding = blur + max(0, -spread) + 4
        let spriteSize = CGSize(
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        return SKSpriteNode(texture: texture, size: spriteSize)
    }

    // MARK: - Glassmorphism backdrop

    /// Captures the current rendering of `scene` at `rect` (scene coordinates)
    /// and returns a Gaussian-blurred SKTexture suitable for a glass backdrop.
    /// Returns nil if the scene hasn't attached to a view yet.
    static func glassBackdrop(for scene: SKScene,
                              at rect: CGRect,
                              blurRadius: CGFloat = 20) -> SKTexture? {
        guard let view = scene.view,
              let sceneTexture = view.texture(from: scene, crop: rect) else {
            return nil
        }
        let cgImage = sceneTexture.cgImage()
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let blurred = ciImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)
        let context = CIContext()
        guard let outCG = context.createCGImage(blurred, from: extent) else {
            return nil
        }
        return SKTexture(cgImage: outCG)
    }

}

// MARK: - SkyGlassCard

/// Floating "glassmorphic" card per the DESIGN.md "Glass & Gradient Rule":
///   surfaceVariant @ 80% opacity + backdrop-blur 20px + ghost border @ 15%.
/// Captures a Gaussian-blurred snapshot of the scene content behind the card
/// rect and layers a translucent tinted pane on top, rounded to the requested
/// radius. Content added via `addChild(...)` renders above all glass layers.
final class SkyGlassCard: SKNode {

    let cardSize: CGSize
    let cardCornerRadius: CGFloat

    init(size: CGSize,
         cornerRadius: CGFloat = 28,
         tint: UIColor = SkyColors.surfaceContainerLowest,
         tintAlpha: CGFloat = 0.80) {
        self.cardSize = size
        self.cardCornerRadius = cornerRadius
        super.init()
        buildTint(tint: tint, alpha: tintAlpha)
        buildGhostBorder()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Captures the scene rendering behind this card's rect and installs it as
    /// a blurred backdrop layer. Call AFTER `self.position` has been set and
    /// BEFORE adding the card to the scene, so the capture doesn't include the
    /// card itself. `self.position` is assumed to be in scene coordinates (i.e.
    /// the intended parent sits at origin — true for the typical overlay pattern).
    func captureBackdrop(in scene: SKScene, blurRadius: CGFloat = 20) {
        let rect = CGRect(
            x: position.x - cardSize.width / 2,
            y: position.y - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
        guard let backdropTexture = SkyUIEffects.glassBackdrop(
            for: scene,
            at: rect,
            blurRadius: blurRadius
        ) else { return }

        let backdrop = SKSpriteNode(texture: backdropTexture, size: cardSize)

        // Clip the backdrop to the card's rounded shape.
        let maskShape = SKShapeNode(rectOf: cardSize, cornerRadius: cardCornerRadius)
        maskShape.fillColor = .white
        maskShape.strokeColor = .clear
        let cropNode = SKCropNode()
        cropNode.maskNode = maskShape
        cropNode.addChild(backdrop)
        cropNode.zPosition = -3
        addChild(cropNode)
    }

    private func buildTint(tint: UIColor, alpha: CGFloat) {
        let pane = SKShapeNode(rectOf: cardSize, cornerRadius: cardCornerRadius)
        pane.fillColor = tint.withAlphaComponent(alpha)
        pane.strokeColor = .clear
        pane.zPosition = -2
        addChild(pane)
    }

    private func buildGhostBorder() {
        let border = SKShapeNode(rectOf: cardSize, cornerRadius: cardCornerRadius)
        border.fillColor = .clear
        border.strokeColor = SkyColors.ghostBorder
        border.lineWidth = 1
        border.zPosition = -1
        addChild(border)
    }
}

// MARK: - SkySprites

/// Canonical filenames for every bundled PNG asset. These names match both
/// Asset Catalog imagesets (UI icons) and loose PNGs in Resources/Sprites/
/// (gameplay art). `SKTexture(imageNamed:)` resolves both transparently.
///
/// Game/UI code should call `SkySprites.texture(named:)` (NOT
/// `SKTexture(imageNamed:)` directly) so it can detect missing assets and
/// fall back to programmatic shapes while art is still in production.
enum SkySprites {
    // Plane sprites (Resources/Sprites/ for the original three; Asset Catalog
    // imagesets for the Stitch-designed Shadow Dart and Night Hawk).
    static let planeFighter     = "plane_fighter"
    static let planeJet         = "plane_jet"
    static let planeBiplane     = "plane_biplane"
    static let planeShadowDart  = "shadow_dart"
    static let planeNightHawk   = "night_hawk"

    // Gameplay sprites (Resources/Sprites/)
    static let coin             = "coin"
    static let ring             = "ring"
    static let cloudPillarTop   = "cloud_pillar_top"
    static let cloudPillarBot   = "cloud_pillar_bottom"

    // UI icons (Assets.xcassets/*.imageset). `*White` variants are used on
    // dark/saturated surfaces (sky gradient, primary buttons, colored tiles);
    // the unsuffixed versions are used on light surfaces.
    static let tabHangar         = "tab_hangar"
    static let tabHangarWhite    = "tab_hangar_white"
    static let tabShop           = "tab_shop"
    static let tabShopWhite      = "tab_shop_white"
    static let tabMap            = "tab_map"
    static let tabMapWhite       = "tab_map_white"
    static let iconSettings      = "icon_settings"
    static let iconSettingsWhite = "icon_settings_white"
    static let starFilled        = "star_filled"
    static let starFilledWhite   = "star_filled_white"
    static let starEmpty         = "star_empty"
    static let starEmptyWhite    = "star_empty_white"
    static let iconCoin          = "icon_coin"
    static let iconCoinWhite     = "icon_coin_white"
    static let iconLock          = "icon_lock"
    static let iconLockWhite     = "icon_lock_white"
    // New glyphs introduced with the redesigned Menu + persistent nav bar.
    static let iconPlay          = "icon_play"          // white triangle on PLAY CTA
    static let iconHome          = "icon_home"
    static let iconHomeWhite     = "icon_home_white"
    static let iconMissions      = "icon_missions"
    static let iconMissionsWhite = "icon_missions_white"
    static let iconWorldCity     = "icon_world_city"
    static let iconWorldMountain = "icon_world_mountain"
    static let pilotAvatar       = "pilot_avatar"

    // Mission intro / briefing art (SKY-61 / SKY-70). Full-screen backgrounds
    // and the two commander portraits are stretched to an explicit size at
    // every call site, so a single-scale imageset renders correctly on all
    // devices.
    static let introBackground        = "intro_bg"
    static let briefingCardClearSkies = "briefing_card_clearskies"
    static let briefingCardStormChaser = "briefing_card_stormchaser"
    static let pilotPortraitNeutral   = "pilot_portrait_neutral"
    static let pilotPortraitSerious   = "pilot_portrait_serious"
    // Results-screen portraits (SKY-122). Rio's reaction to the run outcome:
    // a thumbs-up on a win, a soft encouraging smile on a loss.
    static let pilotPortraitHappy       = "pilot_portrait_happy"
    static let pilotPortraitEncouraging = "pilot_portrait_encouraging"
    static let chapterTransition      = "chapter_transition"

    // Shop upgrade icons (Assets.xcassets/*.imageset).
    static let upgradeEngine     = "engine_boost"

    // Free Flight City landmarks (Resources/Sprites/).
    static let cityTowerBlue     = "city_tower_blue"
    static let cityHouseRed      = "city_house_red"
    static let cityClockTower    = "city_clock_tower"
    static let cityFlowerHouse   = "city_flower_house"
    static let citySkylineBG     = "city_skyline_bg"

    // Free Flight Mountain landmarks (Resources/Sprites/).
    static let mountainSnowDome    = "mountain_snow_dome"
    static let mountainPineGrove   = "mountain_pine_grove"
    static let mountainJaggedPeaks = "mountain_jagged_peaks"
    static let mountainSkyIsland   = "mountain_sky_island"

    // Landing Practice (SKY-83) sprites (Resources/Sprites/). The per-plane
    // gear-down variants are looked up by PlaneNode as "<planeID>_gear_down"
    // and intentionally have no constants here.
    static let runwayStrip          = "runway_strip"
    static let runwayThreshold      = "runway_threshold"
    static let landingZoneIndicator = "landing_zone_indicator"
    static let badgeSmoothLanding   = "badge_smooth_landing"
    static let dustCloud            = "dust_cloud"
    static let landingPracticeCard  = "free_flight_runway_challenge_card"

    // Landing Practice background environmental polish (SKY-93). Five Stitch
    // PNGs layered behind the runway to make the airfield read as a real
    // place at golden hour. Positioning, z-ordering, and scroll rates are all
    // handled in LandingPracticeScene.
    static let landingBgGround         = "landing_bg_ground"
    static let landingBgGrass          = "landing_bg_grass"
    static let landingBgCloudsA        = "landing_bg_clouds_a"
    static let landingBgCloudsB        = "landing_bg_clouds_b"
    static let landingBgSunGlow        = "landing_bg_sun_glow"
    static let landingBgHangars        = "landing_bg_hangars"
    static let landingBgApproachLights = "landing_bg_approach_lights"

    // Approach-light wave glow overlays (SKY-99). Three same-size additive
    // glow orbs — white, red, green — swapped on each light to drive the
    // left-to-right ALSF wave. Layered over the cropped pole from
    // `landingBgApproachLights`.
    static let approachLightGlowWhite  = "approach_light_glow_white"
    static let approachLightGlowRed    = "approach_light_glow_red"
    static let approachLightGlowGreen  = "approach_light_glow_green"

    // World selector card art (SKY-91). City and Mountain now use the same
    // baked Stitch card style as Landing Practice — background color, label,
    // illustration, and descriptor are all baked into a single sprite.
    static let cityCard             = "free_flight_city_card"
    static let mountainCard         = "free_flight_mountain_card"

    // Free Flight Mountain scenery (Resources/Sprites/). Three parallax
    // background strips, a pine tree foreground strip, and ambient props.
    static let mountainBgFar       = "mountain_bg_far"
    static let mountainBgMid       = "mountain_bg_mid"
    static let mountainBgNear      = "mountain_bg_near"
    static let mountainPineTrees   = "pine_trees"
    static let mountainSkiLodge    = "ski_lodge"
    static let mountainCableCar    = "cable_car"
    static let mountainHangGlider  = "hang_glider"
    static let mountainHotAirBalloon = "hot_air_balloon"

    /// Returns an SKTexture for `name` if the image exists in the asset catalog
    /// or in `Resources/Sprites/` (bundled as a folder reference), otherwise
    /// nil. Callers should fall back to programmatic art when nil is returned.
    ///
    /// `SKTexture(imageNamed:)` unhelpfully returns a non-nil "missing" texture
    /// when the image is absent, so we gate on explicit existence checks first.
    static func texture(named name: String) -> SKTexture? {
        // 1. Asset catalog (UI icons): UIImage(named:) checks the catalog and
        //    the top-level bundle.
        if UIImage(named: name) != nil {
            return SKTexture(imageNamed: name)
        }
        // 2. Sprites folder reference: UIImage(named:) does NOT search nested
        //    bundle subdirectories, so look there explicitly.
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Sprites"
        ), let image = UIImage(contentsOfFile: url.path) {
            return SKTexture(image: image)
        }
        return nil
    }

    /// Convenience: returns an SKSpriteNode for the named sprite sized to
    /// `size`, or nil if the image isn't bundled.
    static func sprite(named name: String, size: CGSize) -> SKSpriteNode? {
        guard let texture = texture(named: name) else { return nil }
        return SKSpriteNode(texture: texture, size: size)
    }

    /// Returns an SKSpriteNode at the requested size if the asset is bundled,
    /// otherwise an SKLabelNode rendering `fallbackEmoji`. Callers can drop the
    /// returned node at any position — both types draw centered on `.zero`.
    ///
    /// Use this anywhere the UI shows a small glyph (gear, star, lock) so the
    /// render upgrades automatically when the Stitch assets land.
    static func iconNode(named name: String,
                         fallbackEmoji: String,
                         size: CGFloat,
                         color: UIColor) -> SKNode {
        if let tex = texture(named: name) {
            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: size, height: size))
            return sprite
        }
        // NOTE: intentionally do NOT set fontName. Plus Jakarta Sans doesn't
        // include emoji glyphs, so forcing it onto an emoji-only label made
        // the glyph fall back to odd/partial rendering (⚙ appeared as a
        // yellow starburst instead of a gear). The default nil fontName lets
        // iOS composite emoji via Apple Color Emoji as expected.
        let label = SKLabelNode(text: fallbackEmoji)
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    /// Returns a circular-cropped portrait node at `diameter` points, or an
    /// emoji fallback label if the asset is missing. The source art is
    /// aspect-filled into a circle (center-cropped) so a full-bust portrait
    /// reads as a clean round avatar — the same floating-portrait treatment the
    /// mission briefing card uses, clipped to a circle for the results screens
    /// (SKY-122). Rendering through UIGraphicsImageRenderer bakes the circular
    /// clip at native screen scale, avoiding SKCropNode/SKShapeNode mask
    /// inconsistencies. The node draws centered on `.zero`.
    static func circularPortraitNode(named name: String,
                                     diameter: CGFloat,
                                     fallbackEmoji: String,
                                     fallbackColor: UIColor) -> SKNode {
        if let source = UIImage(named: name) {
            let side = CGSize(width: diameter, height: diameter)
            let renderer = UIGraphicsImageRenderer(size: side)
            let circular = renderer.image { _ in
                let bounds = CGRect(origin: .zero, size: side)
                UIBezierPath(ovalIn: bounds).addClip()
                // Aspect-fill: scale the source to cover the circle, centered.
                let src = source.size
                guard src.width > 0, src.height > 0 else { return }
                let scale = max(diameter / src.width, diameter / src.height)
                let drawSize = CGSize(width: src.width * scale, height: src.height * scale)
                let origin = CGPoint(x: (diameter - drawSize.width) / 2,
                                     y: (diameter - drawSize.height) / 2)
                source.draw(in: CGRect(origin: origin, size: drawSize))
            }
            return SKSpriteNode(texture: SKTexture(image: circular), size: side)
        }
        let label = SKLabelNode(text: fallbackEmoji)
        label.fontSize = diameter * 0.8
        label.fontColor = fallbackColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    /// Returns an SKSpriteNode rendered from an SF Symbol, tinted to `color`.
    /// Prefer this over emoji fallbacks when the glyph must be tinted precisely
    /// (e.g. nav-bar active/inactive states).
    static func sfSymbolNode(systemName: String, size: CGFloat, color: UIColor) -> SKSpriteNode {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let canvas = CGSize(width: size, height: size)
        // Rasterize the tinted symbol into an explicit RGBA bitmap. Handing a
        // `.withTintColor` template image straight to `SKTexture(image:)` drops
        // the tint and renders the glyph as flat black, so draw it ourselves.
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { _ in
            guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else { return }
            let tinted = symbol.withTintColor(color, renderingMode: .alwaysOriginal)
            let rect = CGRect(
                x: (canvas.width - symbol.size.width) / 2,
                y: (canvas.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            tinted.draw(in: rect)
        }
        return SKSpriteNode(texture: SKTexture(image: image), size: canvas)
    }
}

// MARK: - SKScene aspect-fill

extension SKScene {
    /// The size that fills `self.size` with `texture` while preserving the
    /// texture's aspect ratio (center-crop cover). Used by the full-screen
    /// narrative scenes so a fixed-aspect illustration covers the display
    /// without distortion.
    func aspectFillSize(for texture: SKTexture) -> CGSize {
        let tex = texture.size()
        guard tex.width > 0, tex.height > 0 else { return size }
        let scale = max(size.width / tex.width, size.height / tex.height)
        return CGSize(width: tex.width * scale, height: tex.height * scale)
    }
}

// MARK: - SkyHaptics

/// Haptic feedback helpers. Thin wrapper over `UIImpactFeedbackGenerator` and
/// `UINotificationFeedbackGenerator` with kid-friendly intensity choices and
/// pre-warming for low-latency firing. Call `SkyHaptics.prepare()` once on
/// scene `didMove(to:)` — each generator takes ~1.5 seconds to "warm up" after
/// a cold first call; preparing avoids a noticeable delay on first tap.
enum SkyHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// Pre-warm all haptic engines. Cheap — safe to call every scene load.
    static func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notification.prepare()
    }

    /// Subtle tap for button presses.
    static func uiTap()    { light.impactOccurred(intensity: 0.6) }

    /// Satisfying pop for coin / ring collection.
    static func collect()  { light.impactOccurred(intensity: 0.9) }

    /// Plane takes a hit — sharp, communicates danger.
    static func hit()      { heavy.impactOccurred() }

    /// Level completed. Success-pattern notification haptic.
    static func win()      { notification.notificationOccurred(.success) }

    /// Mission failed. Error-pattern notification haptic.
    static func fail()     { notification.notificationOccurred(.error) }
}
