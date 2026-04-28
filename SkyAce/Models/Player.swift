import Foundation
import UIKit

/// Static catalog of the three planes. Runtime ownership lives in ProgressManager.
struct Plane {
    let id: String
    let name: String
    let subtitle: String
    let cost: Int             // 0 for the starter plane
    let requiresFullUnlock: Bool
    let spriteName: String    // Resources/Sprites/*.png; nil-safe via SkySprites.texture
    let bodyColor: UIColor    // programmatic-fallback fill when sprite is absent
    let accentColor: UIColor  // programmatic-fallback accent
    // Set when the bundled PNG is authored nose-left; PlaneNode mirrors the
    // sprite so the plane reads as flying right in every scene.
    let assetFacesLeft: Bool
}

enum PlaneCatalog {
    static let blueSkyChaser = Plane(
        id: "blue_sky_chaser",
        name: "Blue Sky Chaser",
        subtitle: "Standard Jet Fighter",
        cost: 0,
        requiresFullUnlock: false,
        spriteName: SkySprites.planeJet,
        bodyColor: SkyColors.primaryContainer,
        accentColor: SkyColors.primary,
        assetFacesLeft: false
    )

    static let redBaron = Plane(
        id: "red_baron",
        name: "Red Baron MK-1",
        subtitle: "Standard Propeller Scout",
        cost: 500,
        requiresFullUnlock: false,
        spriteName: SkySprites.planeFighter,
        bodyColor: UIColor(hex: 0xE8424A),
        accentColor: UIColor(hex: 0xFFD709),
        assetFacesLeft: true
    )

    static let silverFalcon = Plane(
        id: "silver_falcon",
        name: "Silver Falcon",
        subtitle: "Advanced Stealth Jet",
        cost: 1200,
        requiresFullUnlock: true,
        spriteName: SkySprites.planeBiplane,
        bodyColor: UIColor(hex: 0xBFC8D1),
        accentColor: UIColor(hex: 0x3D5F7C),
        assetFacesLeft: false
    )

    static let all: [Plane] = [redBaron, blueSkyChaser, silverFalcon]

    static func plane(forID id: String) -> Plane {
        return all.first(where: { $0.id == id }) ?? redBaron
    }
}
