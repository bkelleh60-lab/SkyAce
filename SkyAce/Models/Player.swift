import Foundation
import UIKit

/// Static catalog of the four planes. Runtime ownership lives in ProgressManager.
struct Plane {
    let id: String
    let name: String
    let subtitle: String
    let cost: Int             // 0 for the starter plane
    let spriteName: String    // Resources/Sprites/*.png; nil-safe via SkySprites.texture
    let bodyColor: UIColor    // programmatic-fallback fill when sprite is absent
    let accentColor: UIColor  // programmatic-fallback accent
    // Set when the bundled PNG is authored nose-left; PlaneNode mirrors the
    // sprite so the plane reads as flying right in every scene.
    let assetFacesLeft: Bool
    // Asymmetric ability (SKY-66) — one per plane, active or passive.
    let ability: PlaneAbility
}

enum PlaneCatalog {
    static let blueSkyChaser = Plane(
        id: "blue_sky_chaser",
        name: "Blue Sky Chaser",
        subtitle: "Standard Jet",
        cost: 600,
        spriteName: SkySprites.planeJet,
        bodyColor: SkyColors.primaryContainer,
        accentColor: SkyColors.primary,
        assetFacesLeft: false,
        ability: PlaneAbilityCatalog.quickClimb
    )

    static let redBaron = Plane(
        id: "red_baron",
        name: "Red Baron MK-1",
        subtitle: "Standard Propeller Scout",
        cost: 500,
        spriteName: SkySprites.planeFighter,
        bodyColor: UIColor(hex: 0xE8424A),
        accentColor: UIColor(hex: 0xFFD709),
        assetFacesLeft: true,
        ability: PlaneAbilityCatalog.invincibilityBurst
    )

    static let shadowDart = Plane(
        id: "shadow_dart",
        name: "Shadow Dart",
        subtitle: "Fast as Light",
        cost: 1200,
        spriteName: SkySprites.planeShadowDart,
        bodyColor: UIColor(hex: 0x08314D),
        accentColor: UIColor(hex: 0x00BAFF),
        assetFacesLeft: false,
        ability: PlaneAbilityCatalog.speedBoost
    )

    static let nightHawk = Plane(
        id: "night_hawk",
        name: "Night Hawk",
        subtitle: "Supreme Bomber",
        cost: 2000,
        spriteName: SkySprites.planeNightHawk,
        bodyColor: UIColor(hex: 0x08314D),
        accentColor: UIColor(hex: 0xFF8C00),
        assetFacesLeft: false,
        ability: PlaneAbilityCatalog.coinMagnet
    )

    static let all: [Plane] = [redBaron, blueSkyChaser, shadowDart, nightHawk]

    static func plane(forID id: String) -> Plane {
        return all.first(where: { $0.id == id }) ?? redBaron
    }
}
