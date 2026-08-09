# Sky Ace — Claude Code Instructions

## Project Overview

Sky Ace is a freemium iOS arcade flying game for kids ages 8–13, built with Swift and SpriteKit.
It is listed in the **Apple App Store Kids Category (ages 9–11)** and must remain compliant with all
Apple Kids Category guidelines at all times.

---

## Tech Stack

- **Language:** Swift
- **Framework:** SpriteKit
- **Platform:** iOS
- **Payments:** StoreKit (in-app purchases)
- **Version control:** Git / GitHub

---

## Monetization Model

- Free tier: Levels 1–3 and City world Free Flight
- Paid tier ($2.99 one-time IAP): All 10 levels and Mountain world Free Flight
- No ads. No subscriptions. No consumable purchases.
- All IAP must be gated behind the parental gate before StoreKit is invoked.

---

## App Store Compliance Rules

These are non-negotiable and must be respected in every change:

- All in-app purchases must be behind a parental gate before any StoreKit call is made.
- The parental gate may not be disabled, bypassed, or have any recovery/hint path.
- No links out of the app without a parental gate.
- No third-party analytics or advertising SDKs.
- Do not collect or transmit personally identifiable information.
- Do not invoke the system keyboard in any screen accessible to kids without a parental gate.

---

## Architecture Notes

- The host app is **UIKit + SpriteKit** — there is no SwiftUI in this project.
  Do not introduce SwiftUI for incidental work; if a feature genuinely needs it,
  raise it before starting.
- The root is `GameViewController` (UIKit, `SkyAce/GameViewController.swift`).
  Game scenes are SpriteKit `SKScene` subclasses under `SkyAce/Scenes/` and are
  presented inside an `SKView` hosted by the root view controller.
- Reusable content is split by role:
  - `SkyAce/Nodes/` — gameplay-world `SKNode`/`SKSpriteNode` subclasses that live
    inside a scene's world and participate in gameplay/physics (`PlaneNode`,
    `RingNode`, `BigRingNode`, `CoinNode`, `ObstacleNode`, `FinishLineNode`,
    `LandingZoneNode`, …).
  - `SkyAce/UI/` — reusable chrome/overlay nodes and shared UI primitives
    (`MissionBriefingCard`, `SkyChunkyButton`, `SkyTabBar`, `SkyMenuTopBar`,
    `CurrencyHUD`, `AbilityButtonNode`, and the `SkyUIEffects`/`SkySprites`
    helpers). Rule of thumb: if it's part of the flying world, it goes in
    `Nodes/`; if it's HUD, menu, or overlay chrome, it goes in `UI/`.
- Design tokens live in `SkyAce/Colors.swift` (`SkyColors`, `SkyFonts`) and
  `SkyAce/UI/SkyUIEffects.swift` (`SkySprites`, `SkyUIEffects`).
- Cross-cutting state lives in `SkyAce/Managers/`. The managers that exist today
  are `ProgressManager`, `CurrencyManager`, and `AudioManager`. Plain data types
  live in `SkyAce/Models/`.
- Progress and level unlock state is managed via `ProgressManager`.
- Free Flight availability is derived from unlock state — do not duplicate that logic.

### Monetization / parental gate (planned — not yet in the codebase)

The IAP and parental-gate infrastructure described in the compliance rules is
**not yet implemented** — there is currently no `IAPManager`,
`ParentalGateViewController`, or `import StoreKit` anywhere in the repo. Do not
assume these files exist. When this work is built, it MUST follow these rules:

- IAP logic MUST live in `Managers/IAPManager.swift` and use StoreKit. The
  purchase trigger point MUST present the parental gate modally and only invoke
  StoreKit from its success callback.
- The parental gate (planned `ParentalGateViewController`) owns all gate logic.
  Its operands (e.g. `numberA`, `numberB`) and expected answer MUST remain
  `private` and MUST never be exposed via accessors, notifications, or
  `print`/`os_log` output.

---

## Code Style

- Follow standard Swift naming conventions (camelCase for variables/functions, PascalCase for types).
- UIKit views: build hierarchy programmatically with Auto Layout. Set
  `translatesAutoresizingMaskIntoConstraints = false` on every view you add. Do
  not add Storyboards or XIBs.
- SpriteKit nodes: encapsulate visuals and per-node behavior inside the node
  subclass; keep scene files focused on layout, spawning, and physics-contact
  routing.
- Use the shared design tokens — `SkyColors` and `SkyFonts` (in
  `SkyAce/Colors.swift`) for colors and fonts, and `SkySprites` for asset
  lookups. Never hardcode raw color literals, font names, or asset-name strings
  in scenes or nodes.
- No force unwraps (`!`) unless accompanied by an inline comment explaining why it is safe.
- Keep view controllers and scenes focused on presentation. Persistent or
  cross-scene logic belongs in `Managers/`; pure data shapes belong in `Models/`.
- Write one class/struct per file. File name must match the type name.

---

## UX Assets and Stitch Design Tool

MANDATORY: Never create visual game assets, plane sprites, UI components, icons,
or artwork from scratch using code (SKShapeNode, SKSpriteNode programmatic drawing,
CALayer, Core Graphics, etc.) without first checking whether a Stitch design exists.

Before building any visual asset programmatically:
1. Query the Stitch MCP server first to check whether a design exists
   (list/inspect projects, screens, and design systems — read-only lookup).
   Filter by the active project and design system listed below.
2. If a matching design is found: surface what you found and confirm with
   Brian before using it. Do not assume a match without explicit confirmation.
3. If nothing is found: stop, report to Brian, and wait for him to either
   provide a Stitch URL / exported asset or explicitly confirm no design exists.
4. Only proceed with programmatic placeholder code if Brian explicitly confirms
   no Stitch design exists AND instructs you to create a placeholder.
5. All programmatic placeholders must be marked with:
   // PLACEHOLDER: Stitch design required before App Store submission

Do NOT use the Stitch MCP server to generate, create, or modify designs
without Brian's explicit instruction — lookup only.

The Stitch design tool is at: [stitch.google.com](http://stitch.google.com)
Active Sky Ace design project: "Sky Ace Plane Assets"
Active game design system: "Sky Challenge Flight" (High-Energy Tactile Playground)

This rule applies to: plane sprites, bird sprites, UI icons, button artwork,
HUD elements, scene backgrounds, and any other visual asset.
This rule does NOT apply to: layout constraints, text labels, progress bars,
or purely structural/functional UI with no visual design requirements.

---

## Building & Testing

- The project is a plain Xcode project (`SkyAce.xcodeproj`) with a shared
  `SkyAce` scheme. There is no Swift Package Manager manifest and no CocoaPods.
- Unit tests live in the `SkyAceTests` target (XCTest). Run them locally with:
  ```
  xcodebuild test -scheme SkyAce -destination 'platform=iOS Simulator,name=iPhone 15'
  ```
  (substitute any installed simulator for the destination).
- **CI runs on Xcode Cloud**, not GitHub Actions — there is no
  `.github/workflows/` directory. Pull requests are gated by the
  "SkyAce | Production Build | Build - iOS" check, driven from App Store Connect.
- When a change is not verifiable in this environment (e.g. no simulator
  available), say so explicitly rather than claiming it was tested.

---

## Git Workflow

> **Branch conventions.** Automated Claude Code sessions run on their own
> `claude/sky-<issue>-<id>` branches and open the PR as a **draft**
> automatically — when working in that context, use the branch you were assigned
> rather than creating a new `feature/*` branch. The `feature/sky-*` convention
> below is for **manual local work**. Either way: branch from the latest `main`,
> reference the `SKY-X` issue in commits, and open the PR against `main`.

Follow this workflow for manual local work:

1. **Before starting**, create a feature branch from `main`:
   ```
   git checkout main
   git pull
   git checkout -b feature/sky-[issue-number]-short-description
   ```
   Example: `feature/sky-5-parental-gate`

2. **Commit as you go** — do not batch everything into one commit at the end.
   Commit message format:
   ```
   [SKY-X] Brief description of what changed
   ```
   Example: `[SKY-5] Add ParentalGateViewModel with two-step math logic`

3. **When the work is complete and all acceptance criteria pass:**
   ```
   git push origin feature/sky-[issue-number]-short-description
   ```
   Then open a pull request against `main` with:
   - Title matching the Linear issue title
   - Description summarizing what was built
   - Acceptance criteria listed as checkboxes

4. **Never commit directly to `main`.**

5. **Do not open the PR until the acceptance criteria in the Linear ticket are fully met.**

---

## Linear

- Project board: Sky Ace team in Linear
- Issue identifier format: `SKY-X`
- Always reference the Linear issue number in branch names and commit messages.
- Acceptance criteria for each ticket live in the Linear issue description.
  Treat them as the definition of done.

---

## What to Do When Uncertain

- If a task touches IAP or parental gate logic, re-read the App Store Compliance Rules
  section above before writing any code.
- If you are unsure which file owns a behavior, search for it — do not duplicate logic
  in a new file.
- If a task would require changing the monetization model or unlock logic, stop and ask
  before proceeding.
