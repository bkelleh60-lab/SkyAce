import UIKit
import SpriteKit

// MARK: - Hex initializers

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension SKColor {
    static func hex(_ hex: UInt32, alpha: CGFloat = 1.0) -> SKColor {
        return SKColor(hex: hex, alpha: alpha)
    }
}

// MARK: - Sky Ace design system

enum SkyColors {
    // Core palette
    static let primary                 = UIColor(hex: 0x006289)
    static let primaryContainer        = UIColor(hex: 0x00BAFF)
    static let primaryFixed            = UIColor(hex: 0x00BAFF)
    static let onPrimary               = UIColor(hex: 0xE8F4FF)
    static let onPrimaryContainer      = UIColor(hex: 0x003248)

    // Surfaces — tonal shifts only, no borders
    static let surface                 = UIColor(hex: 0xF2F7FF)
    static let surfaceContainerLowest  = UIColor(hex: 0xFFFFFF)
    static let surfaceContainerLow     = UIColor(hex: 0xE8F2FF)
    static let surfaceContainer        = UIColor(hex: 0xD8EAFF)
    static let surfaceContainerHigh    = UIColor(hex: 0xCDE5FF)
    static let surfaceContainerHighest = UIColor(hex: 0xC2E0FF)

    // Text
    static let onSurface               = UIColor(hex: 0x08314D)
    static let onSurfaceVariant        = UIColor(hex: 0x3D5F7C)

    // Tertiary — gold, reserved for coins/rewards
    static let tertiaryContainer       = UIColor(hex: 0xFFD709)
    static let onTertiaryContainer     = UIColor(hex: 0x5B4B00)

    // Secondary — peach, used for Free Flight & alt actions
    static let secondaryContainer      = UIColor(hex: 0xFFC69A)
    static let onSecondaryContainer    = UIColor(hex: 0x6F3A00)

    // Outline variant — ghost borders only (accessibility), 15% alpha
    static let outlineVariant          = UIColor(hex: 0x8FB1D2)

    // Ambient shadow: onSurface @ 6%
    static var ambientShadow: UIColor {
        return onSurface.withAlphaComponent(0.06)
    }

    // Ghost border: outlineVariant @ 15%
    static var ghostBorder: UIColor {
        return outlineVariant.withAlphaComponent(0.15)
    }

    // MARK: SpriteKit conveniences
    static let skPrimary                 = SKColor(hex: 0x006289)
    static let skPrimaryContainer        = SKColor(hex: 0x00BAFF)
    static let skPrimaryFixed            = SKColor(hex: 0x00BAFF)
    static let skOnPrimary               = SKColor(hex: 0xE8F4FF)
    static let skOnPrimaryContainer      = SKColor(hex: 0x003248)
    static let skSurface                 = SKColor(hex: 0xF2F7FF)
    static let skSurfaceContainerLowest  = SKColor(hex: 0xFFFFFF)
    static let skSurfaceContainerLow     = SKColor(hex: 0xE8F2FF)
    static let skSurfaceContainer        = SKColor(hex: 0xD8EAFF)
    static let skSurfaceContainerHigh    = SKColor(hex: 0xCDE5FF)
    static let skSurfaceContainerHighest = SKColor(hex: 0xC2E0FF)
    static let skOnSurface               = SKColor(hex: 0x08314D)
    static let skOnSurfaceVariant        = SKColor(hex: 0x3D5F7C)
    static let skTertiaryContainer       = SKColor(hex: 0xFFD709)
    static let skOnTertiaryContainer     = SKColor(hex: 0x5B4B00)
    static let skSecondaryContainer      = SKColor(hex: 0xFFC69A)
    static let skOnSecondaryContainer    = SKColor(hex: 0x6F3A00)
    static let skOutlineVariant          = SKColor(hex: 0x8FB1D2)
}

// MARK: - Font helpers

enum SkyFonts {
    static func headline(_ size: CGFloat, italic: Bool = false) -> UIFont {
        let name = italic ? "PlusJakartaSans-ExtraBoldItalic" : "PlusJakartaSans-ExtraBold"
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }

    static func bold(_ size: CGFloat) -> UIFont {
        return UIFont(name: "PlusJakartaSans-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    static func body(_ size: CGFloat, medium: Bool = false) -> UIFont {
        let name = medium ? "BeVietnamPro-Medium" : "BeVietnamPro-Regular"
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: medium ? .medium : .regular)
    }

    // SpriteKit uses font names as strings on SKLabelNode
    static let headlineName        = "PlusJakartaSans-ExtraBold"
    static let headlineItalicName  = "PlusJakartaSans-ExtraBoldItalic"
    static let boldName            = "PlusJakartaSans-Bold"
    static let bodyName            = "BeVietnamPro-Regular"
    static let bodyMediumName      = "BeVietnamPro-Medium"
}
