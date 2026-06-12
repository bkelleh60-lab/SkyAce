import SpriteKit

/// Runway strip + touchdown target for Landing Practice (SKY-83).
///
/// Owns both visuals as children — the finite tarmac strip and the landing
/// zone indicator hovering above the touchdown point — and a single
/// contact-only sensor sized to the touchdown window. The whole node scrolls
/// in from the right as one unit and halts with the touchdown point aligned
/// to the plane's fixed X lane.
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

    /// Rendered tarmac height. The strip art's width follows from its
    /// aspect ratio so centerline dashes don't stretch.
    static let runwayHeight: CGFloat = 110

    /// Rendered size of the landing zone indicator box.
    static let zoneSize = CGSize(width: 84, height: 64)

    /// Touchdown sensor: zone-box width, extending this far up from the
    /// runway surface. Contact fires when the plane's hitbox bottom
    /// (center − 13.5) crosses the band top, i.e. at plane center
    /// ≈ surface + 26.5 — which is exactly where the gear-down sprites'
    /// wheels graze the tarmac at the 2x Free Flight visual scale (wheel
    /// bottoms sit 22–30pt below center across the four planes). Keeps the
    /// velocity read and feedback at the moment of *visual* touchdown.
    static let sensorHeight: CGFloat = 13

    /// Fraction of the strip's width (from its left end) where the
    /// touchdown zone sits — short of halfway, like real touchdown
    /// markers near the approach threshold.
    private static let touchdownFraction: CGFloat = 0.3

    /// Fraction of the strip's height (from its top edge) where the
    /// centerline dashes sit in the runway art — measured rows 114–123 of
    /// 240. The road is drawn in gentle perspective, so the *visual*
    /// touchdown line is the dash row, not the strip's top edge: a plane
    /// belongs in the road with its wheels on the dashes.
    private static let surfaceFraction: CGFloat = 0.494

    /// Total rendered width of the runway strip.
    private(set) var stripWidth: CGFloat = 0

    /// How far below the node origin (the strip's top edge) the visual
    /// touchdown line sits. Scenes settle the plane's wheels here and the
    /// touchdown sensor rises from here.
    private(set) var surfaceDrop: CGFloat = 0

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
        let strip: SKSpriteNode
        if let texture = SkySprites.texture(named: SkySprites.runwayStrip) {
            let aspect = texture.size().height > 0
                ? texture.size().width / texture.size().height
                : 5.6
            strip = SKSpriteNode(
                texture: texture,
                size: CGSize(width: height * aspect, height: height)
            )
        } else {
            // Asset missing — neutral tarmac block so the mode still plays.
            strip = SKSpriteNode(
                color: UIColor(hex: 0x55505E),
                size: CGSize(width: sceneWidth * 1.6, height: height)
            )
        }
        stripWidth = strip.size.width
        surfaceDrop = strip.size.height * LandingZoneNode.surfaceFraction

        // Origin sits at the strip's top edge over the touchdown point,
        // with `touchdownFraction` of the strip extending left of the
        // origin and the rest trailing off to the right. The visual
        // touchdown line (centerline dashes) sits `surfaceDrop` below.
        strip.anchorPoint = CGPoint(x: LandingZoneNode.touchdownFraction, y: 1.0)
        strip.position = .zero
        strip.zPosition = 0
        addChild(strip)
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
        zone.zPosition = 1
        zone.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 8, duration: 0.7),
            SKAction.moveBy(x: 0, y: -8, duration: 0.7)
        ])))
        addChild(zone)
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
}
