import SpriteKit

/// Free Flight — Landing Practice (SKY-83, approach redesign SKY-94).
///
/// A pure-sandbox third Free Flight mode with a two-phase approach:
///
/// * **Free approach** — the runway cruises in from the right and keeps
///   scrolling (tiles recycle) while the player flies hold-to-climb /
///   release-to-descend, choosing when to start the landing.
/// * **Final approach** — descending through the approach window
///   (`approachAltitudeThresholdFraction`) commits the landing: the runway
///   decelerates, the landing zone is revealed where the deceleration will
///   halt it (the plane's X lane), and controls invert to tap-to-correct
///   ("keep the nose up") for fine descent-rate management to touchdown.
///
/// Touchdown reads vertical velocity into one of three quality tiers. No
/// fail state — every outcome auto-resets into a fresh approach.
///
/// Architecture is Option A from docs/landing-practice-movement-investigation.md:
/// modeled on FreeFlightCityScene (fixed-X plane, world moves, no camera),
/// with the FinishLineNode contact pattern repurposed as LandingZoneNode.
final class LandingPracticeScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Tunable approach constants (SKY-94, Connor's playtest dials)

    /// Constant runway scroll speed during the free approach phase (pt/s).
    static let approachScrollSpeed: CGFloat = 200

    /// The approach window: descending below this fraction of scene height
    /// commits the landing — the runway decelerates, the landing zone
    /// appears, and controls switch to tap-to-correct.
    static let approachAltitudeThresholdFraction: CGFloat = 0.35

    /// Upward correction added to the plane's dy per tap on final approach
    /// (pt/s). Deliberately a fraction of the Phase-1 climb impulse (base
    /// 320): against the gentle committed-descent gravity (~300 pt/s²,
    /// `committedDescentGravity`) a steady ~2 taps/s roughly cancels gravity
    /// for a slow, gentle descent (Smooth), while sparser taps drift toward
    /// Rough and doing nothing toward Crash. One tap ≈ a 140 pt/s save.
    static let finalApproachTapImpulse: CGFloat = 140

    /// How quickly the runway sheds speed once the approach window opens
    /// (pt/s²). Stopping distance (v²/2a ≈ 80pt) and duration (v/a ≈ 0.8s)
    /// both derive from this and `approachScrollSpeed`. Kept short enough
    /// that the zone finishes aligning at the lane before the continuously
    /// descending plane can reach the touchdown sensor — even the slowest
    /// case, the smallest phone's ~1.2s no-tap fall, outlasts it — so the
    /// plane always touches down on an aligned zone.
    static let runwayDecelerationRate: CGFloat = 250

    /// Pause between the threshold crossing and the landing zone fade-in
    /// (0.0–0.5s) — a beat of "the runway is slowing… there's the zone".
    static let landingZoneRevealDelay: TimeInterval = 0.15

    /// Gentle gravity (SpriteKit accel units; ×150 ⇒ pt/s²) applied to the
    /// plane for the committed final descent — swapped in at the threshold
    /// crossing and restored to `PlaneNode.gravity` on the next approach.
    /// Far softer than flight gravity (-5.0) so tap-to-correct has real
    /// authority and the player gets a full second-plus to feather the
    /// touchdown rather than the old build's half-second plummet.
    static let committedDescentGravity: CGFloat = -2.0

    /// Floor on descent speed during the committed final approach (pt/s),
    /// tighter than the flight body's -400. Device-independent: however far
    /// the plane still has to fall, an untouched descent tops out here, so a
    /// tall iPad screen can't amplify the fall into a distance-driven slam.
    /// Sits just inside the Crash band so doing nothing still risks a Crash
    /// while any reasonable tapping escapes it.
    static let committedTerminalVelocity: CGFloat = -370

    // MARK: - Tunable landing constants (Connor's playtest dials)
    //
    // Velocity tiers are calibrated against the SKY-94 *continuous* committed
    // descent (no park-and-drop): the instant the player commits at the
    // approach window, gravity softens to `committedDescentGravity` and the
    // plane sinks under live tap-to-correct all the way to the sensor
    // (contact at center ≈ surface + 26.5). Tap authority
    // (`finalApproachTapImpulse`) plus the gentle gravity make the touchdown
    // rate the player's to manage the whole way down:
    //   no taps → drifts to the committed terminal (≈ -370 on a long fall) → Crash
    //   a tap here and there → ~ -200…-330 → Rough
    //   a steady ~2 tap/s feather holds dy shallow → Smooth
    // Because gravity is gentle and the descent is continuous from the commit
    // altitude, the input matters from the instant the "Tap to correct!" cue
    // appears. The old build's 2s parked dead-zone — taps doing nothing, then
    // a sudden half-second plummet as the runway halted — is gone.

    /// Touchdown dy at or above this reads as a Smooth Landing.
    static let smoothLandingMaxDescent: CGFloat = -180
    /// Touchdown dy at or above this (and below smooth) is a Rough Landing;
    /// anything faster is a Crash Landing.
    static let roughLandingMaxDescent: CGFloat = -340

    /// Seconds the crash result is held on screen before the approach
    /// auto-resets (crash stops in place; smooth/rough taxi out — see below).
    static let crashResetDelay: TimeInterval = 1.5

    /// Duration (each direction) of the SKY-100 fade-to-black reset: the screen
    /// fades to black over this, the scene resets silently while fully black,
    /// then fades back in over this on a fresh approach. Replaces the old
    /// visible scroll-rewind + plane fade so the player never watches the reset.
    static let landingResetFadeDuration: TimeInterval = 0.4

    // MARK: - Landing roll-out (SKY-93)
    //
    // On a smooth or rough landing the runway keeps scrolling (the plane stays
    // in its lane, taxiing forward) and the runway's end — marked by the
    // threshold bars — rides in from the right, decelerating so the plane halts
    // just short of the bars before the approach resets: a beat of "you made it
    // to the end" instead of stopping dead. A crash still stops in place.

    /// Taxi scroll speed (pt/s); the roll's duration is derived from this and
    /// the distance to the runway end so the feel is device-independent.
    static let landingRollOutSpeed: CGFloat = 170
    /// Beat held at the bars after stopping, before the approach resets.
    static let landingRollOutHold: TimeInterval = 0.9
    /// The plane halts this many points left of the threshold piece — "right
    /// before them".
    static let thresholdBarsStopGap: CGFloat = 50

    // MARK: - Derived approach geometry

    /// Altitude (points) below which the final approach activates.
    private var approachAltitudeThreshold: CGFloat {
        size.height * Self.approachAltitudeThresholdFraction
    }
    /// Ground the runway covers while decelerating: v² / 2a.
    private var decelStoppingDistance: CGFloat {
        Self.approachScrollSpeed * Self.approachScrollSpeed
            / (2 * Self.runwayDecelerationRate)
    }
    /// Time the deceleration takes: v / a.
    private var decelDuration: TimeInterval {
        TimeInterval(Self.approachScrollSpeed / Self.runwayDecelerationRate)
    }

    // MARK: - Layout constants

    /// Screen Y of the runway strip's top edge (LandingZoneNode origin).
    private var groundY: CGFloat { 150 }
    /// Screen Y of the visual touchdown line — the road's centerline
    /// dashes, `surfaceDrop` below the strip top. All landing geometry
    /// keys off this so the plane sits *in* the road with its wheels on
    /// the dashes, matching the art's gentle perspective.
    private var touchdownSurfaceY: CGFloat { groundY - (runway?.surfaceDrop ?? 0) }
    /// Plane lane — same fraction as the Free Flight scenes.
    private var laneX: CGFloat { size.width * 0.28 }
    /// Plane spawn altitude at the start of each approach.
    private var planeStartY: CGFloat { size.height * 0.55 }
    /// Ceiling the plane is clamped below so it never leaves the top of screen.
    private var planeMaxY: CGFloat { size.height - 50 }
    /// Floor during the free approach phase — set to the approach window
    /// itself so the plane commits from a consistent altitude. The descent
    /// distance (and thus the time the runway has to finish aligning) no
    /// longer depends on how early the player dived: they fly the band above
    /// this line and commit by descending onto it.
    private var approachFloorY: CGFloat { approachAltitudeThreshold }
    /// Backstop floor for the committed descent — just below the sensor so
    /// the plane is stopped by the touchdown contact (center ≈ surface +
    /// 26.5), not by this clamp. The descent rate is preserved for the tier
    /// read because the contact fires before this line is reached.
    private var landingFloorY: CGFloat { touchdownSurfaceY + 16 }
    /// Where the plane settles so its wheels sit on the touchdown line:
    /// gear-down wheel bottoms sit 22–30pt below the node center at the
    /// 2x visual scale, so center at +26 grazes the line for all four
    /// planes.
    private var landedPlaneY: CGFloat { touchdownSurfaceY + 26 }

    // MARK: - Background layer layout (SKY-93)

    /// Screen Y of the horizon line: where the distant hangars stand and where
    /// the ground plane's top is aligned, so the field reads as one continuous
    /// surface running from the hangars down past the runway.
    private var horizonY: CGFloat { groundY + 25 }
    /// Rendered height of one grass tile (aspect-preserved). Tuned so the
    /// blade tops poke just above the runway strip's top edge and the body
    /// falls behind the tarmac, grounding it.
    private static let grassHeight: CGFloat = 150
    /// Screen Y of each grass tile's vertical center.
    private var grassCenterY: CGFloat { groundY - 10 }
    /// Rendered height of one hangar tile (aspect-preserved). Small + distant.
    private static let hangarHeight: CGFloat = 130
    /// Screen Y of each hangar tile's vertical center — placed so the building
    /// bases (≈0.369 of the tile height below center) land on `horizonY`.
    private var hangarCenterY: CGFloat { horizonY + 48 }
    /// Source-image row (top-down fraction) where the ground asset's painted
    /// horizon sits; this row is aligned to `horizonY` on screen.
    private static let groundHorizonFrac: CGFloat = 0.36
    /// Below this image fraction the ground is fully opaque; above it the sky
    /// band is feathered to transparent so it melts into the gradient at the
    /// horizon (the asset itself is opaque, so the fade is applied in code).
    private static let groundFeatherEndFrac: CGFloat = 0.37
    /// z behind the hangars (so they stand on it) but in front of the sun glow
    /// (so the ground occludes the sun's lower half at the horizon), and in
    /// front of the sky gradient.
    private static let groundZ: CGFloat = -96
    /// Fraction of `approachScrollSpeed` the distant hangars creep at.
    private static let hangarParallaxFactor: CGFloat = 0.08
    /// Screen Y of the bottom (pole base) of the approach-light row — just
    /// above the grass layer, at the runway surface line. The wave node
    /// (`ApproachLightWaveNode`, SKY-99) is positioned here; everything else
    /// about the lights lives in that node.
    private var approachLightY: CGFloat { touchdownSurfaceY }
    /// Sun-glow rendered diameter and its screen-anchored center, sitting on
    /// the right horizon (the direction the runway cruises in from). Centered
    /// on `horizonY` so the ground occludes the lower half and the upper half
    /// glows into the sky like a low setting sun.
    private static let sunGlowDiameter: CGFloat = 320
    private var sunGlowCenter: CGPoint { CGPoint(x: size.width * 0.82, y: horizonY) }

    /// Continuous hold (seconds) during the committed descent that triggers a
    /// go-around instead of a correction tap. Comfortably longer than a
    /// feathering tap (~0.1s) so trimming the descent can't abort by accident,
    /// short enough that "hold to climb out" feels immediate.
    static let goAroundHoldDuration: TimeInterval = 0.3

    // MARK: - State

    /// The approach lifecycle: free approach → committed final approach →
    /// halted runway → landed → resetting back into a fresh approach.
    private enum Phase { case freeApproach, finalApproach, halted, landed, resetting }

    /// Current approach phase.
    private var phase: Phase = .freeApproach
    /// Container for everything that scrolls and shakes (the HUD sits outside it).
    private let worldNode = SKNode()
    /// SKY-93 background environmental layers (all children of `worldNode`,
    /// behind the runway). Clouds drift on their own actions; the grass and the
    /// approach lights track the tarmac's on-screen motion; the hangars creep
    /// left on a slow independent parallax.
    private let cloudLayer = SKNode()
    private let hangarLayer = SKNode()
    private let grassLayer = SKNode()
    /// Scrolling wave of approach lights (SKY-99) — a child of `worldNode` that
    /// scrolls with the grass and recycles. Held so `update(_:)` can drive its
    /// scroll and colour wave each frame; rebuilt with the scene.
    private var approachLights: ApproachLightWaveNode?
    /// Mirror-tiled ground plane (SKY-93). Unlike the other layers it scrolls
    /// by moving its own position (the tiles are a fixed mirrored strip wrapped
    /// by the pattern period), so the non-tileable painterly plate repeats with
    /// no visible seam.
    private let groundLayer = SKNode()
    /// True only during the smooth/rough taxi roll-out, so the foreground
    /// layers scroll with the runway then (the scene is `.landed`, which
    /// otherwise freezes them).
    private var isRollingOut = false
    /// Tarmac leading-edge X from the previous frame, used to scroll the grass
    /// and approach lights at exactly the runway's on-screen rate (so they
    /// track the tarmac through cruise, deceleration, and the commit-time
    /// origin realign alike). Sentinel = no live previous frame to diff against.
    private var lastLeadingEdgeX: CGFloat = .greatestFiniteMagnitude
    /// Overlay above the world for landing badges and result text.
    private let feedbackLayer = SKNode()
    /// Full-screen black overlay driving the SKY-100 fade-to-black reset. Added
    /// once per layout, above every other node (HUD included), alpha 0 at rest
    /// so it sits ready and invisible until a reset animates its alpha.
    private let resetFadeOverlay = SKSpriteNode()
    // Implicitly unwrapped: both are built in layoutScene() (didMove /
    // didChangeSize rebuild) before any touch or update path can run, and
    // update() additionally guards plane against the teardown window.
    private var plane: PlaneNode!
    private var runway: LandingZoneNode!
    /// True while a finger is down — drives climb in free approach and the
    /// hold detection on final approach.
    private var isTouching = false
    /// Wall-clock time the current committed-descent touch began, for
    /// distinguishing a correction tap from a held go-around. Nil unless a
    /// finger is down during `.finalApproach`/`.halted`.
    private var committedTouchStartTime: TimeInterval?
    /// True from a go-around trigger until the plane has climbed back up
    /// through the approach window. While set, the free-approach floor drops
    /// to a low ground line (so the abort climb isn't yanked upward) and the
    /// commit check is suppressed (so it doesn't immediately re-commit from
    /// below the window).
    private var isGoingAround = false
    /// Timestamp of the previous `update(_:)`, for manual delta-time integration.
    private var lastUpdateTime: TimeInterval = 0
    private weak var instructionPrompt: SKLabelNode?

    // MARK: - Lifecycle

    /// Sets gravity and the contact delegate, builds the scene, and starts the
    /// per-plane engine loop.
    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        physicsWorld.contactDelegate = self
        SkyHaptics.prepare()
        layoutScene()

        AudioManager.shared.playEngineLoop(
            SkyEngineLoop.filename(forPlaneID: ProgressManager.shared.selectedPlaneID)
        )
    }

    /// Stops the engine loop as the scene is torn down.
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        AudioManager.shared.stopEngineLoop()
    }

    // SKY-55: see FreeFlightCityScene.didChangeSize — sandbox mode with no
    // run state worth preserving, so tear down and rebuild for the new
    // dimensions. The current approach restarts; acceptable on a deliberate
    // device rotation.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != .zero, oldSize != size, worldNode.parent != nil else { return }
        worldNode.removeAllChildren()
        worldNode.removeAllActions()
        worldNode.removeFromParent()
        // The background layer nodes are reused properties, so wipe their
        // subtrees/userData (worldNode.removeAllChildren only detaches them)
        // before layoutScene re-populates them for the new size (SKY-93).
        for layer in [cloudLayer, hangarLayer, grassLayer, groundLayer] {
            layer.removeAllChildren()
            layer.removeAllActions()
            layer.userData = nil
            layer.position = .zero
            layer.removeFromParent()
        }
        lastLeadingEdgeX = .greatestFiniteMagnitude
        isRollingOut = false
        // The scrolling light node is a fresh instance each layout and is torn
        // down with worldNode above; drop the stale reference before rebuild.
        approachLights = nil
        feedbackLayer.removeAllChildren()
        feedbackLayer.removeFromParent()
        plane = nil
        runway = nil
        phase = .freeApproach
        isTouching = false
        isGoingAround = false
        committedTouchStartTime = nil
        lastUpdateTime = 0
        removeAllChildren()
        removeAllActions()
        layoutScene()
    }

    /// Builds the sky, runway, plane, and HUD, then opens the first approach.
    private func layoutScene() {
        addChild(worldNode)
        buildSky()
        // Runway before the background: the approach-light row is positioned at
        // `approachLightY`, which reads `runway.surfaceDrop`, so the runway must
        // exist first or the lights fall back to the nil-runway Y (SKY-99).
        buildRunway()
        buildBackgroundEnvironment()
        buildPlane()
        buildTopBar()
        feedbackLayer.zPosition = 150
        addChild(feedbackLayer)
        buildResetFadeOverlay()
        showInstructionPromptIfFirstLaunch()
        beginApproach()
    }

    /// Builds the persistent full-screen black overlay for the fade-to-black
    /// reset (SKY-100). Sized to the scene, anchored bottom-left to match the
    /// scene's origin, alpha 0 and above every other node so a reset can take
    /// the whole screen — play area and HUD alike — to black and back.
    private func buildResetFadeOverlay() {
        resetFadeOverlay.removeAllActions()
        resetFadeOverlay.color = .black
        resetFadeOverlay.size = size
        resetFadeOverlay.anchorPoint = .zero
        resetFadeOverlay.position = .zero
        resetFadeOverlay.alpha = 0
        resetFadeOverlay.zPosition = 1000
        addChild(resetFadeOverlay)
    }

    // MARK: - Sky

    /// Adds the golden-hour gradient backdrop behind the world.
    private func buildSky() {
        let bg = SKSpriteNode(texture: Self.goldenHourTexture(size: size), size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        worldNode.addChild(bg)
    }

    /// Golden-hour gradient: deep amber at the top of the sky blending to a
    /// warm pale yellow at the horizon, held constant below the ground line
    /// so the glow sits right where the runway meets the sky. Rendered with
    /// explicit endpoints (start at (0,0) so gradient location 0 lands at
    /// the sprite top — see FreeFlightCityScene.skyGradientTexture for why
    /// the shared helper's labels can't be trusted here).
    private static func goldenHourTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(hex: 0xC97B2A).cgColor,
                UIColor(hex: 0xF5E6C0).cgColor,
                UIColor(hex: 0xF5E6C0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.8, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }

    // MARK: - Background environment (SKY-93)

    /// Layers the Stitch background assets behind the runway: sun glow,
    /// drifting clouds, distant hangars, and grass strip all sit inside
    /// `worldNode` (so they share the landing shake with the sky) and behind
    /// the runway (z -10) so the tarmac reads as embedded in the ground. The
    /// approach-light wave is screen-anchored and added separately (SKY-99).
    /// Each falls back to nothing if its asset is missing — the mode still
    /// plays on the bare golden-hour gradient.
    private func buildBackgroundEnvironment() {
        buildGround()
        buildSunGlow()
        buildClouds()
        buildHangars()
        buildGrass()
        buildApproachLights()
    }

    /// Painterly ground plane filling from the horizon down to the bottom of
    /// the screen, so the runway sits in a real field instead of floating on
    /// the bare gradient. Scaled to cover the full width and the horizon-to-
    /// bottom band (aspect-preserved, overflow runs off-screen), with the
    /// asset's painted horizon row aligned to `horizonY`. Static — distant
    /// ground barely moves, so the scrolling grass/runway read as parallax on
    /// top of it. No-op if the asset is missing.
    private func buildGround() {
        guard let texture = featheredGroundTexture() else { return }
        let px = texture.size()
        guard px.width > 0, px.height > 0 else { return }

        // Cover the full width AND the horizon→bottom band; take the larger
        // scale so neither dimension leaves a gap (excess runs off-screen).
        let groundBand = horizonY                                  // horizon down to y=0
        let belowHorizonFrac = 1 - Self.groundHorizonFrac
        let scale = max(size.width / px.width,
                        groundBand / (belowHorizonFrac * px.height))
        let rendered = CGSize(width: px.width * scale, height: px.height * scale)
        // Horizon row sits (0.5 - frac) of the height above the tile center.
        let horizonOffset = (0.5 - Self.groundHorizonFrac) * rendered.height
        let centerY = horizonY - horizonOffset

        groundLayer.zPosition = Self.groundZ
        worldNode.addChild(groundLayer)

        // Mirror-tiled so the non-tileable plate repeats seamlessly: every
        // other tile is flipped, so each seam meets its own mirror image and is
        // pixel-continuous. The strip is wrapped by the 2-tile mirror period in
        // `scrollGround`, so an even tile count covering the screen across one
        // full period is enough.
        let tileW = rendered.width
        var count = max(4, Int(ceil(size.width / tileW)) + 3)
        if count % 2 != 0 { count += 1 }
        for i in 0..<count {
            let tile = SKSpriteNode(texture: texture, size: rendered)
            tile.xScale = (i % 2 == 0) ? 1 : -1
            tile.position = CGPoint(x: tileW * (CGFloat(i) + 0.5), y: centerY)
            groundLayer.addChild(tile)
        }
        let userData = groundLayer.userData ?? NSMutableDictionary()
        userData["period"] = tileW * 2
        groundLayer.userData = userData
    }

    /// Loads the ground asset and feathers its top edge to transparent across
    /// the sky band, so the opaque field below the horizon melts into the sky
    /// gradient instead of showing a hard line. Falls back to the raw texture
    /// (no feather) if the file can't be read as a UIImage for compositing.
    private func featheredGroundTexture() -> SKTexture? {
        guard let url = Bundle.main.url(
                forResource: SkySprites.landingBgGround, withExtension: "png",
                subdirectory: "Sprites"),
              let image = UIImage(contentsOfFile: url.path) else {
            return SkySprites.texture(named: SkySprites.landingBgGround)
        }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let faded = renderer.image { ctx in
            image.draw(at: .zero)
            // destinationOut: drawn alpha = how much to erase. Erase fully at
            // the very top (transparent sky band) ramping to keep at the
            // feather end, just below the painted horizon. Untouched below.
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
                end: CGPoint(x: 0, y: image.size.height * Self.groundFeatherEndFrac),
                options: []
            )
        }
        return SKTexture(image: faded)
    }

    /// Soft radial sun bloom sitting on the right horizon, behind the ground
    /// so its lower half is occluded and it reads as a low setting sun.
    private func buildSunGlow() {
        guard let texture = SkySprites.texture(named: SkySprites.landingBgSunGlow) else { return }
        let glow = SKSpriteNode(
            texture: texture,
            size: CGSize(width: Self.sunGlowDiameter, height: Self.sunGlowDiameter)
        )
        glow.position = sunGlowCenter
        // Behind the ground (groundZ -96) so the field occludes the sun's
        // lower half instead of the glow washing over it.
        glow.zPosition = -97
        // Normal alpha blend: the asset is already a soft amber radial with
        // transparent edges, so it melts into the gradient. (Additive blow it
        // out to white over the pale horizon.)
        glow.alpha = 0.85
        worldNode.addChild(glow)
    }

    /// Two warm sunset cloud variants drifting slowly left across the upper
    /// sky, each on its own loop so the pair never lines up repetitively.
    private func buildClouds() {
        cloudLayer.zPosition = -90
        worldNode.addChild(cloudLayer)

        // (assetName, height, centerY fraction, drift seconds across travel).
        let specs: [(String, CGFloat, CGFloat, TimeInterval)] = [
            (SkySprites.landingBgCloudsA, 150, 0.80, 46),
            (SkySprites.landingBgCloudsB, 175, 0.66, 58),
            (SkySprites.landingBgCloudsA, 110, 0.72, 70)
        ]
        for (index, spec) in specs.enumerated() {
            let (name, height, yFraction, period) = spec
            guard let texture = SkySprites.texture(named: name) else { continue }
            let aspect = texture.size().height > 0
                ? texture.size().width / texture.size().height
                : 1.5
            let width = height * aspect
            let cloud = SKSpriteNode(texture: texture, size: CGSize(width: width, height: height))
            cloud.alpha = 0.9
            cloud.zPosition = CGFloat(index)
            cloudLayer.addChild(cloud)
            startCloudDrift(cloud, width: width, y: size.height * yFraction, period: period,
                            phaseFraction: CGFloat(index) / CGFloat(specs.count))
        }
    }

    /// Runs `cloud` on an endless right-to-left drift: it enters off the right
    /// edge, crosses the screen, and wraps back. `phaseFraction` staggers the
    /// initial position so the clouds don't march in lockstep.
    private func startCloudDrift(_ cloud: SKSpriteNode, width: CGFloat, y: CGFloat,
                                 period: TimeInterval, phaseFraction: CGFloat) {
        let travel = size.width + width
        let startX = size.width + width / 2
        let endX = -width / 2
        let drift = SKAction.moveBy(x: -travel, y: 0, duration: period)
        let reset = SKAction.moveBy(x: travel, y: 0, duration: 0)
        cloud.position = CGPoint(x: startX - travel * phaseFraction, y: y)
        // Run the remainder of the first pass for the staggered start, then loop.
        let firstLeg = TimeInterval((cloud.position.x - endX) / travel) * period
        cloud.run(SKAction.sequence([
            SKAction.moveTo(x: endX, duration: firstLeg),
            reset,
            SKAction.repeatForever(SKAction.sequence([drift, reset]))
        ]))
    }

    /// Distant hangar silhouettes tiled along the horizon, creeping left on a
    /// very slow parallax (`hangarParallaxFactor` of the runway speed).
    private func buildHangars() {
        hangarLayer.zPosition = -85
        worldNode.addChild(hangarLayer)
        buildScrollingTiles(
            into: hangarLayer,
            textureName: SkySprites.landingBgHangars,
            tileHeight: Self.hangarHeight,
            centerY: hangarCenterY
        )
    }

    /// Full-width grass strip tiled beneath and around the runway so the
    /// tarmac sits in the ground rather than floating. Scrolls with the tarmac.
    private func buildGrass() {
        grassLayer.zPosition = -60
        worldNode.addChild(grassLayer)
        buildScrollingTiles(
            into: grassLayer,
            textureName: SkySprites.landingBgGrass,
            tileHeight: Self.grassHeight,
            centerY: grassCenterY
        )
    }

    /// Spawns the approach-light wave (SKY-99). All the visuals and the wave
    /// animation live in `ApproachLightWaveNode`; the scene positions it at the
    /// runway surface line inside `worldNode` (behind the runway, z -10, so the
    /// glows sit in the ground), then drives its scroll and colour wave from
    /// `update(_:)` so the lights move in with the grass and runway.
    private func buildApproachLights() {
        let lights = ApproachLightWaveNode(sceneWidth: size.width)
        lights.position = CGPoint(x: 0, y: approachLightY)
        lights.zPosition = -55
        worldNode.addChild(lights)
        approachLights = lights
    }

    // MARK: - Background tiling helpers

    /// Tiles `textureName` horizontally across `layer`, aspect-preserved to
    /// `tileHeight`, enough copies to cover the widest screen plus a spare.
    /// Stores the tile width in `layer.userData` so `scrollLayer` can recycle.
    /// No-op (leaving the gradient bare) if the asset is missing.
    private func buildScrollingTiles(into layer: SKNode, textureName: String,
                                     tileHeight: CGFloat, centerY: CGFloat) {
        guard let texture = SkySprites.texture(named: textureName) else { return }
        let s = texture.size()
        let aspect = s.height > 0 ? s.width / s.height : 1.75
        layoutTileRow(into: layer, texture: texture,
                      tileSize: CGSize(width: tileHeight * aspect, height: tileHeight),
                      centerY: centerY)
    }

    /// Lays a contiguous row of identical tiles spanning the screen (plus one
    /// spare for seamless recycling) and records the tile width on the layer.
    private func layoutTileRow(into layer: SKNode, texture: SKTexture,
                               tileSize: CGSize, centerY: CGFloat) {
        let count = max(2, Int(ceil(size.width / tileSize.width)) + 1)
        for i in 0..<count {
            let tile = SKSpriteNode(texture: texture, size: tileSize)
            tile.position = CGPoint(x: tileSize.width * (CGFloat(i) + 0.5), y: centerY)
            layer.addChild(tile)
        }
        let userData = layer.userData ?? NSMutableDictionary()
        userData["tileWidth"] = tileSize.width
        layer.userData = userData
    }

    /// Scrolls the mirror-tiled ground by moving the whole layer and wrapping
    /// its position by the mirror period, so it repeats seamlessly without
    /// per-tile recycling (which would break the flipped-tile alternation).
    private func scrollGround(by dx: CGFloat) {
        guard dx != 0,
              let period = groundLayer.userData?["period"] as? CGFloat, period > 0,
              !groundLayer.children.isEmpty else { return }
        groundLayer.position.x += dx
        while groundLayer.position.x <= -period { groundLayer.position.x += period }
        while groundLayer.position.x > 0 { groundLayer.position.x -= period }
    }

    /// Shifts a tiled layer by `dx` (negative = left) and recycles any tile
    /// that has fully left the screen edge to the far end, keeping the row
    /// unbroken in either scroll direction.
    private func scrollLayer(_ layer: SKNode, by dx: CGFloat) {
        guard dx != 0, let tileWidth = layer.userData?["tileWidth"] as? CGFloat,
              !layer.children.isEmpty else { return }
        for tile in layer.children { tile.position.x += dx }
        if dx < 0 {
            // Moving left: recycle tiles off the left edge to the right end.
            while let leftmost = layer.children.min(by: { $0.position.x < $1.position.x }),
                  leftmost.position.x + tileWidth / 2 < 0 {
                let rightmostX = layer.children.map { $0.position.x }.max() ?? 0
                leftmost.position.x = rightmostX + tileWidth
            }
        } else {
            // Moving right (roll-out): recycle tiles off the right edge to the left.
            while let rightmost = layer.children.max(by: { $0.position.x < $1.position.x }),
                  rightmost.position.x - tileWidth / 2 > size.width {
                let leftmostX = layer.children.map { $0.position.x }.min() ?? 0
                rightmost.position.x = leftmostX - tileWidth
            }
        }
    }

    // MARK: - Runway

    /// Creates the runway/landing-zone node off-screen right, ready to cruise in.
    private func buildRunway() {
        runway = LandingZoneNode(sceneWidth: size.width)
        runway.position = CGPoint(x: offscreenRunwayX, y: groundY)
        runway.zPosition = -10
        worldNode.addChild(runway)
    }

    /// Origin X that puts the tarmac's leading edge past the right screen
    /// edge, ready to cruise in.
    private var offscreenRunwayX: CGFloat {
        runway.startOriginX(sceneWidth: size.width)
    }

    /// Opens a fresh free approach: gravity on, hold-to-climb live, runway
    /// cruising in from the right at constant speed (driven from
    /// `update(_:)` so it can scroll indefinitely while tiles recycle). The
    /// approach stays open — no scripted halt — until the plane descends
    /// through the approach window.
    private func beginApproach() {
        phase = .freeApproach
        isGoingAround = false
        committedTouchStartTime = nil
        // Restore full flight gravity — the previous approach's committed
        // descent softened it to `committedDescentGravity`.
        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        // Gravity stays off through the reset fade (update() doesn't clamp
        // position while resetting, so the plane would sink); it turns back
        // on only when the approach — and the position clamp — are live.
        plane.physicsBody?.velocity = .zero
        plane.physicsBody?.affectedByGravity = true
    }

    /// The commit moment (SKY-94): the plane has descended through the
    /// approach window, so the runway begins its deceleration, the landing
    /// zone is revealed where the deceleration will halt it, the gear
    /// deploys, and controls invert to tap-to-correct.
    private func beginFinalApproach() {
        phase = .finalApproach
        // A finger still held from Phase 1 must not keep climbing — final
        // approach input is discrete taps (or a held go-around) only.
        isTouching = false
        committedTouchStartTime = nil

        // Soften gravity for the committed descent so tap-to-correct has real
        // authority and the player has time to feather the touchdown. Restored
        // to full flight gravity by `beginApproach()` on the next pass.
        physicsWorld.gravity = CGVector(dx: 0, dy: Self.committedDescentGravity)

        // Red Baron MK-1 has fixed gear baked into its base art — the
        // deploy trigger must not fire anything for it: no sprite swap
        // and no gear SFX, ever (SKY-83 playtest bug 1).
        if ProgressManager.shared.selectedPlaneID != "red_baron" {
            plane.setLandingGear(deployed: true)
        }

        // Halt geometry: the runway sheds `approachScrollSpeed` at
        // `runwayDecelerationRate`, covering v²/2a more points. Re-anchor
        // the still-hidden zone exactly that far right of the lane (the
        // tarmac doesn't move — only the origin jumps) so the deceleration
        // ends with the zone on the plane's X lane.
        runway.realignOrigin(toX: laneX + decelStoppingDistance)

        // Ease-out over T = v/a: average speed v/2 means the curve's
        // initial slope matches the cruise speed, so the handoff from
        // constant scroll doesn't pop.
        let decel = SKAction.moveTo(x: laneX, duration: decelDuration)
        decel.timingMode = .easeOut
        runway.run(SKAction.sequence([
            decel,
            // Only advance to .halted if still in the committed descent. The
            // continuous descent can reach the runway a frame before the decel
            // finishes — that touchdown has already moved us to .landed (and a
            // held go-around to .freeApproach). This stale completion must not
            // clobber that phase: doing so left `.landed` reading as `.halted`,
            // which failed the reset guard and hung the scene (plane frozen
            // with gravity off, so restart taps climbed it to the top).
            SKAction.run { [weak self] in
                if self?.phase == .finalApproach { self?.phase = .halted }
            }
        ]))

        run(SKAction.sequence([
            SKAction.wait(forDuration: Self.landingZoneRevealDelay),
            SKAction.run { [weak self] in self?.runway.setZoneRevealed(true, fade: 0.3) }
        ]), withKey: "revealZone")

        showTapToCorrectCue()
    }

    // MARK: - Plane

    /// Spawns the player's plane at the lane start with the landing sensor as
    /// its only contact interest (nothing else collects or crashes here).
    private func buildPlane() {
        plane = PlaneNode(planeID: ProgressManager.shared.selectedPlaneID, visualScale: 2.0)
        plane.position = CGPoint(x: laneX, y: planeStartY)
        plane.zPosition = 10
        // Sandbox: only the touchdown sensor matters — nothing can crash
        // or collect in this mode.
        plane.physicsBody?.categoryBitMask = PhysicsCategory.plane
        plane.physicsBody?.contactTestBitMask = PhysicsCategory.landingZone
        plane.physicsBody?.collisionBitMask = 0
        worldNode.addChild(plane)
    }

    // MARK: - Top bar

    /// Lays out the EXIT button and mode title in the top safe-area bar.
    private func buildTopBar() {
        let topSafeInset = view?.safeAreaInsets.top ?? 0
        let barCenterY = size.height - topSafeInset - 20

        let exit = SkyPillButton(
            title: "EXIT",
            style: .surface,
            size: CGSize(width: 76, height: 32)
        ) { SkyNavigator.shared.showMenu() }
        exit.position = CGPoint(x: 52, y: barCenterY)
        exit.zPosition = 200
        addChild(exit)

        let label = SKLabelNode(text: "RUNWAY CHALLENGE")
        label.fontName = SkyFonts.headlineName
        label.fontSize = 13
        label.fontColor = SkyColors.skOnPrimary
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 100, y: barCenterY)
        label.zPosition = 200
        addChild(label)
    }

    // MARK: - First-time instruction prompt

    /// Shows the one-time "Hold to climb. Release to descend." prompt on the
    /// player's first-ever Landing Practice session.
    private func showInstructionPromptIfFirstLaunch() {
        guard !ProgressManager.shared.landingPracticeInstructionShown else { return }
        ProgressManager.shared.landingPracticeInstructionShown = true

        let prompt = SKLabelNode(text: "Hold to climb. Release to descend.")
        prompt.fontName = SkyFonts.headlineName
        prompt.fontSize = 20
        prompt.fontColor = .white
        prompt.verticalAlignmentMode = .center
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        prompt.zPosition = 150
        prompt.alpha = 0
        addChild(prompt)
        instructionPrompt = prompt
        prompt.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Final approach cue

    /// "Tap to correct!" — shown on every threshold crossing, not just the
    /// first launch: the control inversion needs re-anchoring each approach.
    private func showTapToCorrectCue() {
        presentApproachCue("Tap to correct!", hold: 1.6)
    }

    /// The single transient cue slot near the top of the play area. Showing a
    /// new cue evicts any cue (or first-launch instruction) already there so
    /// two never overlap — e.g. "Tap to correct!" still fading when a held
    /// go-around fires "Go around!".
    private weak var approachCue: SKLabelNode?
    /// Fades `text` into the cue slot, holds it for `hold` seconds, then fades out.
    private func presentApproachCue(_ text: String, hold: TimeInterval) {
        instructionPrompt?.removeAllActions()
        instructionPrompt?.removeFromParent()
        approachCue?.removeAllActions()
        approachCue?.removeFromParent()

        let cue = SKLabelNode(text: text)
        cue.fontName = SkyFonts.headlineName
        cue.fontSize = 20
        cue.fontColor = .white
        cue.verticalAlignmentMode = .center
        cue.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        cue.zPosition = 150
        cue.alpha = 0
        addChild(cue)
        approachCue = cue
        cue.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: hold),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Go-around

    /// Powers out of a committed landing: the player held instead of tapping,
    /// so climb away, stow the gear, hide the zone, and hand the runway back
    /// to the free-approach scroll for a fresh setup. The held finger keeps
    /// driving `plane.climb()` in `update()` (phase is back to `.freeApproach`)
    /// until released, so a hold reads as "power up and away".
    private func goAround() {
        isGoingAround = true
        phase = .freeApproach
        committedTouchStartTime = nil

        physicsWorld.gravity = CGVector(dx: 0, dy: PlaneNode.gravity)
        plane.physicsBody?.affectedByGravity = true
        plane.climb()

        // Stow the gear (Red Baron's is fixed in its base art — leave it).
        if ProgressManager.shared.selectedPlaneID != "red_baron" {
            plane.setLandingGear(deployed: false)
        }

        // Hand the tarmac back to the free-approach scroll: cancel the
        // deceleration (and its pending halt), drop the still-pending zone
        // reveal, and conceal the zone. update() resumes scrolling it left.
        runway.removeAllActions()
        removeAction(forKey: "revealZone")
        runway.setZoneRevealed(false, fade: 0.3)

        showGoAroundCue()
    }

    /// "Go around!" — brief confirmation that the abort took. Evicts the
    /// still-fading "Tap to correct!" cue so the two don't overlap.
    private func showGoAroundCue() {
        presentApproachCue("Go around!", hold: 1.2)
    }

    // MARK: - Update

    /// Per-frame driver: scrolls the runway, applies climb/tap input, detects
    /// the commit and go-around moments, clamps the committed descent, and holds
    /// the plane to its phase floor.
    override func update(_ currentTime: TimeInterval) {
        // The cruise scroll is integrated manually so it can run for an
        // unbounded free approach; clamp dt so a frame hitch can't
        // teleport the runway.
        let delta: TimeInterval = lastUpdateTime == 0
            ? 0
            : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime

        guard let plane = plane else { return }

        if phase == .freeApproach {
            runway.position.x -= Self.approachScrollSpeed * CGFloat(delta)
        }
        if phase == .freeApproach || phase == .finalApproach {
            runway.updateTiling(in: self)
        }

        // SKY-93: scroll the grass, approach lights, and (slower) hangars at the
        // tarmac's real on-screen rate by diffing its leading edge frame to
        // frame. This tracks the runway through the cruise, the commit-time
        // origin realign (which leaves the edge put), and the deceleration
        // alike, with no per-layer speed bookkeeping. Clouds drift on their own
        // actions and are intentionally left out. Frozen outside the live scroll
        // phases so the reset roll-out can't drag the strips along.
        if phase == .freeApproach || phase == .finalApproach || phase == .halted || isRollingOut {
            let edge = runway.leadingEdgeX(in: self)
            if lastLeadingEdgeX != .greatestFiniteMagnitude {
                let dx = edge - lastLeadingEdgeX
                scrollLayer(grassLayer, by: dx)
                scrollLayer(hangarLayer, by: dx * Self.hangarParallaxFactor)
                scrollGround(by: dx)
                approachLights?.scroll(by: dx)
            }
            lastLeadingEdgeX = edge
        } else {
            lastLeadingEdgeX = .greatestFiniteMagnitude
        }

        // The colour wave runs on scene time so it keeps flowing toward the
        // threshold even while the scroll is paused (halted / between approaches).
        approachLights?.updateWave(time: currentTime)

        if isTouching && phase == .freeApproach { plane.climb() }
        plane.update()

        let controlsLive = phase == .freeApproach || phase == .finalApproach || phase == .halted
        guard controlsLive else { return }

        // Go-around: a sustained hold during the committed descent (vs. a
        // brief correction tap) powers the plane out of the landing and
        // reopens a fresh approach.
        if phase == .finalApproach || phase == .halted,
           isTouching,
           let start = committedTouchStartTime,
           currentTime - start >= Self.goAroundHoldDuration {
            goAround()
        }

        // The commit moment: the plane sinks through the approach window
        // while the runway is established beneath it (leading edge past the
        // screen's left edge — descending any earlier just rides Phase 1's
        // floor until the tarmac arrives). Suppressed mid-go-around so the
        // abort climb doesn't instantly re-commit from below the window.
        if phase == .freeApproach, !isGoingAround,
           plane.position.y <= approachAltitudeThreshold,
           runway.leadingEdgeX(in: self) <= 0 {
            beginFinalApproach()
        }

        // Clamp the committed descent to a gentle, device-independent terminal
        // so an untouched fall tops out in (at worst) the Crash band near
        // `committedTerminalVelocity` rather than accelerating without bound
        // over a tall screen.
        if phase == .finalApproach || phase == .halted,
           let pb = plane.physicsBody,
           pb.velocity.dy < Self.committedTerminalVelocity {
            pb.velocity.dy = Self.committedTerminalVelocity
        }

        if phase == .freeApproach {
            // The window is the resting floor: a plane descending onto it
            // (dy ≤ 0) is held there until commit, giving a consistent commit
            // altitude. During a go-around the plane starts *below* the window
            // climbing out, so the floor drops to a low ground line and never
            // yanks the climb upward; once it clears the window the abort ends
            // and normal commit rules resume.
            let floor = isGoingAround ? (touchdownSurfaceY + 50) : approachFloorY
            if plane.position.y <= floor, let pb = plane.physicsBody, pb.velocity.dy <= 0 {
                plane.position.y = floor
                pb.velocity.dy = 0
            }
            if isGoingAround, plane.position.y >= approachAltitudeThreshold {
                isGoingAround = false
            }
        } else if plane.position.y <= landingFloorY {
            // Committed backstop — the touchdown contact normally stops the
            // plane above this line (preserving its descent rate for the tier
            // read); this only catches a contact that didn't fire.
            plane.position.y = landingFloorY
        }
        plane.position.y = min(planeMaxY, plane.position.y)
        plane.position.x += (laneX - plane.position.x) * 0.12
    }

    // MARK: - Touchdown

    /// Physics contact entry point — routes a plane↔landing-zone touch to the
    /// touchdown handler.
    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard categories == PhysicsCategory.plane | PhysicsCategory.landingZone else { return }
        handleLandingZoneContact()
    }

    /// Resolves a touchdown: freezes and settles the plane onto the tarmac, then
    /// dispatches to the smooth/rough/crash tier by its descent rate.
    private func handleLandingZoneContact() {
        // Accept the touchdown across the whole committed descent, not just at
        // full halt. The sensor rides with the runway, so a contact can only
        // physically begin once the zone has slid within a hitbox-width of the
        // lane — i.e. the runway is aligned (or all but). Guarding only on
        // `.halted` could drop a touchdown that lands a frame before the decel
        // action's completion handler flips the phase.
        guard phase == .finalApproach || phase == .halted else { return }
        let descentRate = plane.physicsBody?.velocity.dy ?? 0
        phase = .landed
        isTouching = false
        committedTouchStartTime = nil

        // SKY-103: kill the approach cue ("Tap to correct!") instantly at
        // touchdown — don't let its fade-out run on behind the outcome feedback,
        // where it reads as a bug overlapping the celebration badge.
        approachCue?.removeAllActions()
        approachCue?.alpha = 0

        // Clear any feedback still on screen from a prior approach so this
        // tier's visuals can never overlap (e.g. a lingering smooth badge
        // showing behind fresh "Bumpy" text).
        feedbackLayer.removeAllActions()
        feedbackLayer.removeAllChildren()
        feedbackLayer.alpha = 1

        // Freeze the plane. Attitude is per-tier: clean landings flare
        // nose-up; crashes keep the frozen nose-down descent tilt under the
        // dust cloud (reset re-levels). Smooth/rough then taxi to the runway
        // end (beginLandingRollout owns their settle); a crash settles dead in
        // place here.
        plane.physicsBody?.velocity = .zero
        plane.physicsBody?.affectedByGravity = false

        if descentRate >= Self.smoothLandingMaxDescent {
            handleSmoothLanding()
        } else if descentRate >= Self.roughLandingMaxDescent {
            handleRoughLanding()
        } else {
            let settle = SKAction.move(
                to: CGPoint(x: laneX, y: landedPlaneY),
                duration: 0.15
            )
            settle.timingMode = .easeOut
            plane.run(settle)
            handleCrashLanding()
        }
    }

    /// Smooth/rough ending (SKY-93): the plane settles in its lane, then the
    /// runway keeps scrolling — the plane taxiing forward — and the runway's
    /// end rides in from the right, decelerating so the plane halts just short
    /// of the threshold bars before the approach resets. The touchdown chevron
    /// is dismissed (its job is done). Crash landings never call this.
    private func beginLandingRollout() {
        isRollingOut = true   // let the foreground layers scroll with the taxi
        runway.setZoneRevealed(false, fade: 0.3)

        // Plane stays in its lane; just settle the wheels onto the tarmac.
        let settle = SKAction.move(to: CGPoint(x: laneX, y: landedPlaneY), duration: 0.15)
        settle.timingMode = .easeOut
        plane.run(settle)

        // Scroll the runway so its end taxis in from the right and stops with
        // the bars just ahead of the plane, then hold and reset.
        runway.rollOutToEnd(stopSceneX: laneX, gap: Self.thresholdBarsStopGap,
                            speed: Self.landingRollOutSpeed) { [weak self] in
            guard let self = self else { return }
            self.run(SKAction.sequence([
                SKAction.wait(forDuration: Self.landingRollOutHold),
                SKAction.run { [weak self] in self?.resetForNextApproach() }
            ]))
        }
    }

    /// Smooth-tier feedback: touchdown chime, nose-up flare, win haptic, badge,
    /// and — unless today's daily cap is reached — the +50 coin reward (SKY-95).
    private func handleSmoothLanding() {
        run(SKAction.sequence([
            AudioManager.shared.sfxAction(SkySFX.landingTouchdown, fileExtension: "caf"),
            SKAction.wait(forDuration: 0.25),
            AudioManager.shared.sfxAction(SkySFX.landingSuccess, fileExtension: "caf")
        ]))
        plane.playTouchdownFlare()
        SkyHaptics.win()
        showCelebrationBadge()

        // SKY-95: grant 50 coins per smooth landing, capped at 500/day. The
        // daily-cap bookkeeping and coin grant live in CurrencyManager; it
        // returns 0 once the cap is reached, in which case no pill is shown and
        // the badge stands alone.
        let reward = CurrencyManager.shared.grantLandingPracticeSmoothLandingReward()
        if reward > 0 {
            showCoinRewardPill(amount: reward)
        }

        beginLandingRollout()
    }

    /// Pops the shared coin-reward pill in below the celebration badge, timed to
    /// land just after the badge's scale-in so the two read in sequence.
    private func showCoinRewardPill(amount: Int) {
        let pill = CoinRewardPill(amount: amount)
        pill.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        pill.zPosition = 1
        pill.alpha = 0
        feedbackLayer.addChild(pill)
        pill.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.45),
            SKAction.run { [weak pill] in pill?.animateIn() }
        ]))
    }

    /// Rough-tier feedback: impact sound, world shake, "Bumpy" text, then the
    /// taxi roll-out. No fanfare — the missing celebration is the feedback. The
    /// old in-place bounce is dropped: a position bounce would fight the taxi
    /// move, and the shake already sells the rough touchdown.
    private func handleRoughLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingRough, fileExtension: "caf"))
        SkyHaptics.hit()

        plane.playTouchdownFlare()
        shakeWorld(amplitude: 7)
        showFeedbackText("Bumpy Landing")
        beginLandingRollout()
    }

    /// Crash-tier feedback: impact sound, hard shake, dust burst, retry text.
    private func handleCrashLanding() {
        run(AudioManager.shared.sfxAction(SkySFX.landingCrash, fileExtension: "caf"))
        SkyHaptics.fail()
        shakeWorld(amplitude: 12)
        burstDustCloud(at: CGPoint(x: laneX, y: touchdownSurfaceY + 12))
        showFeedbackText("Crash — try again!")
        scheduleReset(after: Self.crashResetDelay)
    }

    // MARK: - Feedback visuals

    /// Pops the smooth-landing badge (or a gold fallback) into the feedback layer.
    private func showCelebrationBadge() {
        let width = min(size.width - 90, 300)
        let badgeSize: CGSize
        let badge: SKSpriteNode
        if let texture = SkySprites.texture(named: SkySprites.badgeSmoothLanding) {
            let aspect = texture.size().width > 0
                ? texture.size().height / texture.size().width
                : 0.9
            badgeSize = CGSize(width: width, height: width * aspect)
            badge = SKSpriteNode(texture: texture, size: badgeSize)
        } else {
            // Asset missing — keep the moment celebratory with a plain gold
            // burst so the tier still reads.
            badgeSize = CGSize(width: width, height: width * 0.6)
            badge = SKSpriteNode(color: UIColor(hex: 0xFFD709), size: badgeSize)
        }
        badge.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        badge.setScale(0.01)
        feedbackLayer.addChild(badge)

        let pop = SKAction.sequence([
            SKAction.scale(to: 1.08, duration: 0.28),
            SKAction.scale(to: 1.0, duration: 0.12)
        ])
        pop.timingMode = .easeOut
        badge.run(pop)
    }

    /// Fades a single line of result text into the feedback layer.
    private func showFeedbackText(
        _ text: String,
        color: UIColor = .white,
        y: CGFloat = 0.62
    ) {
        let label = SKLabelNode(text: text)
        label.fontName = SkyFonts.headlineName
        label.fontSize = 24
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * y)
        label.alpha = 0
        feedbackLayer.addChild(label)
        label.run(SKAction.fadeIn(withDuration: 0.2))
    }

    /// Decaying net-zero jolt on the world container — HUD stays put.
    private func shakeWorld(amplitude: CGFloat) {
        var actions: [SKAction] = []
        var a = amplitude
        for _ in 0..<3 {
            actions.append(SKAction.moveBy(x: a, y: -a * 0.6, duration: 0.04))
            actions.append(SKAction.moveBy(x: -2 * a, y: a * 1.2, duration: 0.05))
            actions.append(SKAction.moveBy(x: a, y: -a * 0.6, duration: 0.04))
            a *= 0.55
        }
        worldNode.run(SKAction.sequence(actions))
    }

    /// Emits a short-lived dust burst at the crash touchdown point.
    private func burstDustCloud(at point: CGPoint) {
        guard let texture = SkySprites.texture(named: SkySprites.dustCloud) else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.numParticlesToEmit = 12
        emitter.particleBirthRate = 60
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.3
        emitter.position = point
        emitter.particlePositionRange = CGVector(dx: 50, dy: 8)
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 0.9
        emitter.particleSpeed = 90
        emitter.particleSpeedRange = 50
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.1
        emitter.particleScale = 0.14
        emitter.particleScaleRange = 0.08
        emitter.particleScaleSpeed = 0.18
        emitter.yAcceleration = -60
        emitter.zPosition = 20
        worldNode.addChild(emitter)
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Reset

    /// Schedules `resetForNextApproach()` to run after `delay` seconds.
    private func scheduleReset(after delay: TimeInterval) {
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.resetForNextApproach() }
        ]))
    }

    /// Fade-to-black reset (SKY-100): the screen fades to black, every scene
    /// element snaps back to its approach-start state while fully black (nothing
    /// the player can see reposition or scroll), then the screen fades back in
    /// on a fresh approach already cruising in. Replaces the old visible
    /// scroll-rewind + plane fade.
    private func resetForNextApproach() {
        guard phase == .landed else { return }
        phase = .resetting
        isRollingOut = false   // foreground layers freeze through the black reset

        resetFadeOverlay.removeAllActions()
        resetFadeOverlay.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: Self.landingResetFadeDuration),
            SKAction.run { [weak self] in self?.performSilentReset() },
            SKAction.fadeOut(withDuration: Self.landingResetFadeDuration)
        ]))
    }

    /// The reset block run while the screen is fully black: snaps every element
    /// to its approach-start state with no animation, then opens a fresh
    /// approach so the runway is already cruising in as the screen fades back.
    /// The approach lights and drifting clouds keep running underneath the
    /// overlay throughout — nothing here stops them.
    private func performSilentReset() {
        // Clear any feedback (badge / result text / coin pill) instantly.
        feedbackLayer.removeAllChildren()
        feedbackLayer.alpha = 1

        // Plane back to the start altitude and lane: gear stowed, levelled,
        // velocity cleared.
        plane.position = CGPoint(x: laneX, y: planeStartY)
        plane.setLandingGear(deployed: false)
        plane.levelOut(duration: 0)
        plane.physicsBody?.velocity = .zero

        // Runway off-screen right, tiles/zone/end-bars reset to the lead-in.
        runway.prepareForApproach()
        runway.position.x = offscreenRunwayX
        // Drop the stale leading-edge so the foreground scroll diff restarts
        // cleanly from the repositioned runway (no first-frame jump).
        lastLeadingEdgeX = .greatestFiniteMagnitude

        beginApproach()
    }

    // MARK: - Touch

    /// Routes touches: HUD buttons first, then phase-specific input — hold to
    /// climb in free approach, tap-to-correct / hold-to-go-around once committed.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        for node in nodes(at: location) {
            if let button = (node as? SkyPillButton) ?? (node.parent as? SkyPillButton) {
                button.handleTap()
                return
            }
        }
        switch phase {
        case .freeApproach:
            isTouching = true
        case .finalApproach, .halted:
            // Phase 2: a brief tap trims the descent rate ("keep the nose
            // up"); a hold past `goAroundHoldDuration` triggers a go-around
            // (detected in update). Apply the correction immediately so a tap
            // stays responsive even when it turns out to be the start of a hold.
            isTouching = true
            committedTouchStartTime = CACurrentMediaTime()
            plane.applyCorrectionTap(impulse: Self.finalApproachTapImpulse)
        case .landed, .resetting:
            break
        }
    }
    /// Clears the touch/hold state when the finger lifts.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        committedTouchStartTime = nil
    }
    /// Clears the touch/hold state if the touch is cancelled.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        committedTouchStartTime = nil
    }
}
