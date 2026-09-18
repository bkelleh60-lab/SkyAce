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
- **Completely free.** All 10 levels, City and Mountain Free Flight, Landing Practice, hangar planes, and upgrades. No ads. No in-app purchases. No subscriptions.

## Compliance and data posture

- **No advertisements** of any kind. No banners, interstitials, rewarded video, or offer walls.
- **No in-app purchases of any kind.** No unlock fee, no subscriptions, no consumables.
- **No third-party SDKs.** No analytics, no ad networks, no tracking, no social. The only frameworks linked are Apple's own (UIKit, SpriteKit, AVFoundation).
- **No data collection.** The app does not collect, store, or transmit any user or device data. There is no backend server. Game progress is saved locally in `UserDefaults` and is removed when the app is deleted.
- **No external links** without a parental gate.
- **`PrivacyInfo.xcprivacy`** declares `NSPrivacyTracking = false`.
- **Parental gate** is required before any external link out of the app. Two-step arithmetic problem with randomized operands. No skip, no hint, no recovery shortcut.

## Tech stack

- Swift 5
- SpriteKit (game scenes and physics)
- UIKit (root view controller, parental gate)
- AVFoundation (game audio)
- iOS 16.0+ deployment target
- Universal: iPhone (portrait) and iPad (all orientations)

## Project layout

```
SkyAce/
├── AppDelegate.swift
├── GameViewController.swift
├── Colors.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
├── Managers/          ProgressManager, AudioManager, CurrencyManager
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

App Store screenshots and the privacy and support pages live in `docs/`:

```
docs/
├── privacy.html
├── support.html
└── app-store-screenshots/
    ├── CAPTURE.md             slot-by-slot capture and recapture guide
    ├── _compose.py            composition script for marketing frames
    ├── iphone-6.7/final/      five 1284x2778 marketing screenshots
    └── ipad-13/final/         five 2064x2752 marketing screenshots
```

Raw simulator captures are gitignored. Run `_compose.py` to regenerate any final asset. See `docs/app-store-screenshots/CAPTURE.md` for the slot sequence, captions, and per-slot capture state.

## License

This repository is published primarily so that App Store reviewers and curious developers can verify Sky Ace is original, independent work. The source is visible, but no permission is granted to copy, redistribute, or create derivative works. All rights reserved.
