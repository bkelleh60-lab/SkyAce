# Landing Practice — Horizontal Movement Investigation

**Status:** Investigation only (no code changes)
**Scope:** Determine how horizontal movement works across existing modes and whether
Landing Practice can reuse it.

## Summary

The plane **never has a world-space horizontal position** in any current mode. It is
pinned to a fixed X lane and the world is scrolled past it. There is **no shared
scrolling system** — each scene reimplements its own scroll loop. Landing Practice's
core fantasy (plane approaching a runway from the left) is the one thing the current
architecture does *not* do, so it needs new logic, but that logic is small and the
vertical control is fully reusable.

---

## 1. Free Flight (City & Mountain): what drives horizontal scrolling?

**Each scene does it independently — there is no shared scroll system.** They share a
*pattern*, but the code is duplicated.

- **City** (`SkyAce/Scenes/FreeFlightCityScene.swift`): scrolling happens in
  `update(_:)` (line 570) which calls a private
  `scrollLoop(_:speed:totalWidth:wrapMargin:delta:)` (line 637). It manually decrements
  each child's `position.x` by `speed * delta` and wraps it when it passes a left
  margin. Two parallax layers (`farBackground`, `nearForeground`) plus a separate
  landmark system.
- **Mountain** (`SkyAce/Scenes/FreeFlightMountainScene.swift`): its `update(_:)`
  (line 693) calls *different* helpers — `scrollTilingLayer(_:speed:delta:)` (line 745)
  and `scrollLayer(_:speed:delta:)` (line 733). Three mountain bands + cloud + pine line.
- **Landmarks** in both scenes scroll differently again — via `SKAction.moveBy` attached
  to each spawned node (City line 437, Mountain line 576), with `landmarkLayer.speed`
  used as a global multiplier for the ring boost.

Same conceptual approach (move children left, wrap/recycle, parallax by layer), but three
separate helper implementations and no shared base class. The only genuinely shared piece
is `SKGradientBackgroundNode.gradientTexture` (a texture helper, not movement).

## 2. Mission levels: same system or separate?

**Separate again — a third implementation**, and architecturally the most different of
the three.

- `SkyAce/Scenes/GameScene.swift` is the mission scene. It uses an **`SKCameraNode`**
  (`cameraRoot`, set up line 151) to keep the HUD fixed, which Free Flight does not.
- Its scroll is driven per-object: obstacles, coins, and the finish line each get an
  `SKAction.moveBy` whose duration is computed from
  `plane.horizontalSpeed * challenge.speedMultiplier` (e.g. `spawnObstaclePair` line 463,
  `spawnCoinPattern` line 583, `spawnFinishLine` line 551). The only `update()`-driven
  scroll is the two cloud parallax layers (lines 380–387).
- Mission *reads* `plane.horizontalSpeed` as a scalar to size scroll speeds, but the
  plane still doesn't move horizontally (see #3).

## 3. Does the plane have a horizontal velocity / world position?

**No. In every mode the plane is rendered at a fixed X and the world moves around it.**
This is the key finding.

- `PlaneNode` (`SkyAce/Nodes/PlaneNode.swift`) exposes `horizontalSpeed` (line 23), but
  it's **never applied to the plane's own position**. It's only used as a *speed scalar*
  for scrolling other objects (and for finish-line timing math). The plane's physics body
  only ever has a vertical velocity — `climb()` sets `velocity.dy` (line 155); gravity
  pulls `dy` down. `dx` is never touched.
- Each scene actively *pins* the plane to its lane every frame by lerping X back to a
  constant:
  - City: `plane.position.x += (size.width * 0.28 - plane.position.x) * 0.12` (line 583)
  - Mountain: same, `* 0.28` (line 704)
  - Mission: `plane.position.x += (size.width * 0.25 - plane.position.x) * 0.12`
    (line 377), with the comment *"Keep plane horizontally fixed — world moves past it."*
- The vertical control model lives entirely in `PlaneNode.climb()` / `update()` and is
  identical everywhere: hold = `climb()` each frame, release = gravity descends. That's
  exactly the hold-to-climb / release-to-descend fantasy, already built.

## 4. Simplest path for Landing Practice

The altitude mechanic is free — reuse `PlaneNode` + the per-frame
`if isTouching { plane.climb() }` / gravity loop verbatim. The new part is the
**horizontal approach to a fixed runway**, which is the inverse of the current setup:
instead of an endless world scrolling past a pinned plane, the *runway* should arrive and
the relative horizontal distance should *close to zero and stop*.

Two viable approaches, simplest first:

### Option A — Keep the plane pinned, scroll a finite runway in (recommended, lowest risk)

- Build a new `LandingPracticeScene` modeled on the Free Flight scenes (no camera needed,
  unlike Mission).
- Reuse the existing scroll-the-world-left pattern, but instead of infinite wrapping,
  scroll a **single finite ground/runway strip** in from the right that *decelerates and
  halts* when the runway marker reaches the plane's fixed X lane. The plane visually
  appears to "approach from the left" because the runway slides toward it — the same
  illusion every current mode already relies on.
- Touchdown detection = plane's Y descends into a target band while horizontally over the
  runway marker (and ideally while world speed has slowed). This is essentially the
  `FinishLineNode` cross pattern (`GameScene.handleFinishLineCross` line 560) repurposed
  as a landing zone, combined with a Y/vertical-speed check for a "good vs hard" landing.
- Reuses ~90% of existing code (PlaneNode control, scroll helpers, contact routing) and
  introduces only: a runway node, a deceleration curve on scroll speed, and a
  landing-quality check.

### Option B — Give the plane a real horizontal world velocity

- Add `dx` movement to the plane and a stationary runway, let the plane physically
  traverse toward it. This is "truer" to the fantasy but is genuinely *new* movement
  logic — nothing in the codebase moves the plane in X today, so it would diverge from the
  established architecture, and lose the easy reuse of the scroll-based scenes. The clamp
  lines that pin X (553/583/704/377) would have to be removed/replaced rather than reused.

### Recommendation

**Option A.** The existing architecture's central assumption — fixed-X plane, world
moves — actually *supports* the landing fantasy with a tweak (finite, decelerating scroll
+ a stop) rather than a rebuild. No existing scroll system is directly reusable as-is
(they're per-scene and infinite-wrapping), but the *pattern* and the *vertical control*
are, so the new scene would follow the Free Flight template rather than inventing new
horizontal-movement physics.

### Note for scoping

Because the three modes each hand-rolled scrolling, a Landing Practice scene will add a
*fourth* independent scroll implementation. If more modes are expected, this is a
reasonable moment to consider extracting a shared scroll/parallax helper — but that's a
refactor decision, not a requirement for shipping Landing Practice.

---

## Key file/function reference

| Concern | Location |
| --- | --- |
| City scroll loop | `SkyAce/Scenes/FreeFlightCityScene.swift` — `update(_:)` (570), `scrollLoop(...)` (637) |
| City plane X pin | `FreeFlightCityScene.swift:583` |
| Mountain scroll | `SkyAce/Scenes/FreeFlightMountainScene.swift` — `update(_:)` (693), `scrollTilingLayer(...)` (745), `scrollLayer(...)` (733) |
| Mountain plane X pin | `FreeFlightMountainScene.swift:704` |
| Mission scene + camera | `SkyAce/Scenes/GameScene.swift` — `setupCamera()` (151) |
| Mission per-object scroll | `GameScene.swift` — `spawnObstaclePair` (463), `spawnCoinPattern` (583), `spawnFinishLine` (551) |
| Mission plane X pin | `GameScene.swift:377` |
| Finish-line cross (landing-zone analog) | `GameScene.swift` — `handleFinishLineCross()` (560) |
| Vertical control model | `SkyAce/Nodes/PlaneNode.swift` — `horizontalSpeed` (23), `climb()` (155), `update()` (162) |
