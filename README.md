# Sky Ace

A 2D side-scrolling arcade flying game for kids, built with SpriteKit + Swift 5.

## Requirements

- Xcode 15+
- iOS 16.0+ deployment target
- iPhone (portrait only)

## Build & Run

1. Open `SkyAce.xcodeproj` in Xcode.
2. Select an iPhone simulator (iOS 16+).
3. Press ▶ (Cmd+R).

## Project Structure

```
SkyAce/
├── AppDelegate.swift
├── GameViewController.swift
├── ParentalGateViewController.swift
├── Colors.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
├── Managers/          ProgressManager, AudioManager, IAPManager
├── Models/            Player, Upgrade, Challenge, GameState
├── Nodes/             PlaneNode, CoinNode, ObstacleNode, RingNode
├── Scenes/            Menu, Map, Game, Shop, Hangar, Results, Unlock, FreeFlight*
└── Resources/
    ├── Assets.xcassets
    └── Sounds/        placeholder audio files
```

## Before Shipping

The following assets must be added before App Store submission:

- **Fonts:** drop the following TTF files into `SkyAce/Resources/` and add them to the target:
  - `PlusJakartaSans-Bold.ttf`
  - `PlusJakartaSans-ExtraBold.ttf`
  - `PlusJakartaSans-ExtraBoldItalic.ttf`
  - `BeVietnamPro-Regular.ttf`
  - `BeVietnamPro-Medium.ttf`
- **Audio:** replace the 10 placeholder files in `SkyAce/Resources/Sounds/` with real audio.
- **App Icon:** add 1024×1024 icon to `Assets.xcassets/AppIcon.appiconset`.
- **IAP:** create the non-consumable product `com.skyace.fullunlock` at price tier $2.99 in App Store Connect.

## Compliance

- **Apple Kids category.** No ads, no analytics, no third-party SDKs, no tracking.
- **Parental gate:** arithmetic multiplication required before every IAP prompt.
- **PrivacyInfo.xcprivacy:** `NSPrivacyTracking = false`.
