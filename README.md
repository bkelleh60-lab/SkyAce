# Sky Ace

A 2D mission-based flying game for kids, built in Swift and SpriteKit for iPhone and iPad.

Sky Ace is an independent project, designed and developed at the kitchen table by a working dad and his nine-year-old son. The kid drew the planes, picked the colors, named the worlds, and tested every level until it felt right. The dad wrote the code.

## What it is

- **Listed in the Apple App Store Kids Category** (ages 9-11).
- **Press and hold to climb. Let go to dive.** That is the whole control scheme.
- **Ten mission levels** across three challenge types: obstacle courses, time trials with coin chains, and mixed coin-and-obstacle stages.
- **Two chapters with sequential level progression** — Clear Skies (Levels 1–5) and Storm Chaser (Levels 6–10). Each level must be completed before the next one unlocks.
- **1–3 star rating per mission** based on performance: coins collected and time remaining. Stars persist across sessions.
- **Two open-world Free Flight modes** with no fail state: City World ("Skyline Tour") and Mountain World ("Mountain Expedition"). Both have landmarks to circle and rings that grant a temporary speed boost.
- **A Hangar of unlockable planes**, each with distinct speed, armor, and handling stats.
- **A Shop with upgradeable systems** (Armor Plating, Engine Boost) using earned in-game currency.
- **One-time $2.99 in-app purchase** unlocks all 10 levels and Mountain World Free Flight. Levels 1 through 3 and City World Free Flight are free.

## Compliance and data posture

- **No advertisements** of any kind. No banners, interstitials, rewarded video, or offer walls.
- **No subscriptions and no consumable purchases.** A single non-consumable IAP, $2.99, one-time, restorable.
- **No third-party SDKs.** No analytics, no ad networks, no tracking, no social. The only frameworks linked are Apple's own (UIKit, SpriteKit, StoreKit, AVFoundation).
- **No data collection.** The app does not collect, store, or transmit any user or device data. There is no backend server. Game progress is saved locally in `UserDefaults` and is removed when the app is deleted.
- **No external links** without a parental gate.
- **`PrivacyInfo.xcprivacy`** declares `NSPrivacyTracking = false`.
- **Parental gate** is required before any in-app purchase or external link. Two-step arithmetic problem with randomized operands. No skip, no hint, no recovery shortcut.

## Tech stack

- Swift 5
- SpriteKit (game scenes and physics)
- UIKit (root view controller, parental gate)
- StoreKit (single non-consumable IAP)
- AVFoundation (game audio)
- iOS 16.0+ deployment target
- Universal: iPhone (portrait) and iPad (all orientations)

## Project layout

```
SkyAce/
├── AppDelegate.swift
├── GameViewController.swift
├── ParentalGateViewController.swift
├── Colors.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
├── Managers/          ProgressManager, AudioManager, IAPManager, DebugConfig
├── Models/            Player, Upgrade, Challenge, GameState
├── Nodes/             PlaneNode, CoinNode, ObstacleNode, RingNode, FinishLineNode
├── Scenes/            Menu, Map, Game, Shop, Hangar, Results,
│                      Unlock, FreeFlightCity, FreeFlightMountain
└── Resources/
    ├── Assets.xcassets
    ├── Sounds/
    └── PlusJakartaSans-*.ttf
```

The host app is UIKit + SpriteKit (no SwiftUI). Reusable scene content lives in `Nodes/` as `SKNode` / `SKSpriteNode` subclasses. Cross-cutting state lives in `Managers/`. Plain data shapes live in `Models/`. One class or struct per file; the file name matches the type name.

## Build and run

1. Open `SkyAce.xcodeproj` in Xcode 15 or newer.
2. Select an iPhone or iPad simulator running iOS 16 or newer.
3. Press Run (Cmd+R).

## App Store submission assets

App Store screenshots, App Preview videos, and the privacy and support pages live in `docs/`:

```
docs/
├── privacy.html
├── support.html
└── app-store-screenshots/
    ├── _compose.py            composition script for marketing frames
    ├── _contact_sheet.py      contact sheet builder for picking gameplay stills
    ├── iphone-6.7/final/      six 1284x2778 marketing screenshots
    ├── ipad-13/final/         six 2064x2752 marketing screenshots
    └── video/                 three App Preview videos (H.264, with silent AAC)
```

Raw simulator captures and source recordings are gitignored. Run the scripts to regenerate any final asset.

## License

This repository is published primarily so that App Store reviewers and curious developers can verify Sky Ace is original, independent work. The source is visible, but no permission is granted to copy, redistribute, or create derivative works. All rights reserved.
