# App Store Screenshot Capture Guide

Reference for recapturing the App Store screenshot slots. Background rationale for the 5-slot baseline lives in [SKY-71](https://linear.app/skyace/issue/SKY-71/app-store-screenshots-resubmission-pass); the coin-chain slot was added in [SKY-74](https://linear.app/skyace/issue/SKY-74/add-coin-chain-screenshot-to-app-store-submission) to visually demonstrate the second mission type (Sunny Sprint / coin chain) and strengthen the 4.3(a) appeal.

The current sequence is 6 stills per device, no preview videos. Notes on what was deliberately skipped:
- Level-complete-3-star slot is still dropped (rhetorically nice, but not cited in Apple's 4.3(a) rejection; expensive to capture).
- Preview videos are skipped (optional in App Store Connect; the existing ones use pre-SKY-62 obstacle art, so a future ticket can re-record).

## Pre-capture checklist

- [ ] Post-[SKY-62](https://linear.app/skyace/issue/SKY-62) obstacle art is in the build (verify the gameplay scene does not show red-striped pillars).
- [ ] `DebugConfig.debugUnlockAllContent` is `false` in the build being captured.
- [ ] Test progression state set up so captures reflect a real mid-progression save: levels 1–2 completed with stars, coins on hand.
- [ ] Premium content unlocked via either StoreKit test purchase (preferred) or temporary debug flag (must be reverted before commit). Required for slot 5 shop capture.
- [ ] iPad layout confirmed stable (see [SKY-49](https://linear.app/skyace/issue/SKY-49)) before any iPad capture.
- [ ] Final targets: 1284 × 2778 iPhone (App Store Connect 6.5" slot) and 2064 × 2752 iPad. `_compose.py` will downscale from the simulator's native resolution.

## Slot sequence

The order matters — slot 1 must be the missions map, not the home screen. Slot 4 demonstrates the coin-chain mission type and must read as clearly distinct from the slot-2 obstacle course (open sky, no wall-based obstacles, timer + coin HUD visible).

| # | Filename            | Screen                                                                                  | Caption                                          |
| - | ------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------ |
| 1 | `01-missions.png`   | Missions map, mid-progression, mission card expanded, multiple locked levels visible    | Ten missions. Three stars each.                  |
| 2 | `02-gameplay.png`   | Active obstacle-course gameplay, post-SKY-62 obstacles, finish line in frame, timer + coin HUD | Every mission has a finish line.          |
| 3 | `03-hangar.png`     | Hangar with a plane centered and the bottom tab visible                                 | Pick your plane.                                 |
| 4 | `04-coinchain.png`  | Active coin-chain gameplay (Sunny Sprint), open sky, scattered coin patterns, timer in top right, no wall obstacles | Collect every coin. Beat the clock. |
| 5 | `05-freeflight.png` | Free Flight city scene, clock tower in lower third, plane in upper half                 | Open skies. No timer. No walls.                  |
| 6 | `06-shop.png`       | Shop with Engine Boost + Armor Plating rows visible, no paywall modal, Fuel Tank "Coming Soon" scrolled out of frame | Upgrade your plane. No ads. No tracking. |

## Per-slot capture notes

**Slot 1 — Missions map.** Tap a non-locked level so its mission card is expanded. Aim for at least 3 locked levels visible above the expanded card. Levels below the card should show their earned stars.

**Slot 2 — Obstacle-course gameplay.** Capture during an active run on a level where the finish line (checkered flag) is visible or clearly approaching. At least one obstacle and one coin should be on screen. Timer and coin count readable. Must use post-SKY-62 themed obstacle art.

**Slot 3 — Hangar.** Reuse the existing "Pick your plane" composition — a single centered plane with the bottom tab bar visible is acceptable for the pragmatic scope.

**Slot 4 — Coin-chain gameplay.** Capture during an active run on Sunny Sprint (or another coin-chain level). Frame must show an open sky with a scattered coin pattern, the plane somewhere mid-frame, the "SUNNY SPRINT" + timer HUD top-right, and the coin counter top-left. Do NOT include any wall-based obstacles — that's what makes this slot read as a different mission type from slot 2.

**Slot 5 — Free Flight.** City scene. Clock tower landmark in the lower third, plane in the upper half. "SKYLINE TOUR" HUD label visible if possible.

**Slot 6 — Shop.** Premium unlock required first — the paywall overlay in [ShopScene.swift](../../SkyAce/Scenes/ShopScene.swift) is non-dismissable until `IAPManager.shared.isContentUnlocked` is `true`. Either complete a StoreKit test purchase via the `SkyAce.storekit` config, or temporarily flip `debugUnlockAllContent` to `true` (and revert before commit). Once unlocked, scroll so Engine Boost and Armor Plating rows show with their upgrade levels and coin prices. Keep Fuel Tank "Coming Soon" out of frame if it can be scrolled away.

## Composing a slot

Raw simulator captures go in `iphone-6.7/raw/` and `ipad-13/raw/` (both gitignored). Then run `_compose.py` once per slot per device:

```sh
# From the repo root.
cd docs/app-store-screenshots

python3 _compose.py \
  iphone-6.7/raw/01-missions.png \
  "Ten missions. Three stars each." \
  iphone-6.7/final/01-missions.png \
  --device iphone

python3 _compose.py \
  ipad-13/raw/01-missions.png \
  "Ten missions. Three stars each." \
  ipad-13/final/01-missions.png \
  --device ipad
```

Repeat for each slot using the filenames and captions in the table above. Note that the raw filename in `raw/` does not have to match the final filename — `_compose.py` reads from any path you point it at. The current coin-chain raws are stored as `07-coinchain.png` even though the final lands at `04-coinchain.png`.

## Done check

Before declaring the screenshot pass complete:

- [ ] All 6 iPhone slots regenerated with the new sequence + captions.
- [ ] All 6 iPad slots regenerated with the new sequence + captions.
- [ ] No pre-SKY-62 obstacle art in any asset.
- [ ] Slot 1 is the missions map, not the home screen.
- [ ] Slot 4 (coin chain) contains no wall-based obstacles.
- [ ] Paywall modal does not appear in slot 6 shop.
- [ ] `debugUnlockAllContent` is `false` in committed code.
- [ ] All assets uploaded to App Store Connect.
