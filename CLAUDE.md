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
- The root is `GameViewController` (UIKit). Game scenes are SpriteKit `SKScene`
  subclasses under `SkyAce/Scenes/` and are presented inside an `SKView` hosted
  by the root view controller.
- Reusable scene content lives in `SkyAce/Nodes/` (`SKNode`/`SKSpriteNode`
  subclasses such as `PlaneNode`, `RingNode`, `ObstacleNode`, `FinishLineNode`).
- Cross-cutting state lives in `SkyAce/Managers/` (`ProgressManager`,
  `IAPManager`, `AudioManager`, `DebugConfig`). Plain data types live in
  `SkyAce/Models/`.
- IAP logic is handled via StoreKit in `Managers/IAPManager.swift`. The purchase
  trigger point must always present `ParentalGateViewController` modally and
  only invoke StoreKit from its `onSuccess` callback.
- `ParentalGateViewController` owns all gate logic. Its operands (`numberA`,
  `numberB`) and `expectedAnswer` must remain `private` and must never be
  exposed via accessors, notifications, or `print`/`os_log` output.
- Progress and level unlock state is managed via `ProgressManager`.
- Free Flight availability is derived from unlock state — do not duplicate that logic.

---

## Code Style

- Follow standard Swift naming conventions (camelCase for variables/functions, PascalCase for types).
- UIKit views: build hierarchy programmatically with Auto Layout. Set
  `translatesAutoresizingMaskIntoConstraints = false` on every view you add
  (matching the pattern in `ParentalGateViewController`). Do not add Storyboards
  or XIBs.
- SpriteKit nodes: encapsulate visuals and per-node behavior inside the node
  subclass; keep scene files focused on layout, spawning, and physics-contact
  routing.
- No force unwraps (`!`) unless accompanied by an inline comment explaining why it is safe.
- Keep view controllers and scenes focused on presentation. Persistent or
  cross-scene logic belongs in `Managers/`; pure data shapes belong in `Models/`.
- Write one class/struct per file. File name must match the type name.

---

## Git Workflow

Follow this workflow for every piece of work:

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
