# SKY-93 — Landing Practice Environmental Polish: Procedural vs. Stitch Investigation

**Date:** 2026-06-12
**Scope:** Investigation only — no code changes. Determines which of the six
planned environmental elements for `LandingPracticeScene` should be built
procedurally with existing SpriteKit patterns and which should be commissioned
as Stitch PNGs.

---

## Elements under consideration

1. Green grass ground strip surrounding the runway on both sides
2. Warm sunset clouds (golden/peach, matching the golden-hour palette)
3. Sun glow or sun disc low on the horizon, right side
4. Approach lighting — a row of small glowing lights leading to the runway threshold
5. Distant hangar/building silhouettes on the horizon, right side
6. Control tower or windsock silhouette, right side, low detail

---

## Findings from existing scenes

### 1. City scene grass strip — programmatic SKShapeNode

Built in `buildNearForeground()` at `SkyAce/Scenes/FreeFlightCityScene.swift:274`.
The grass itself is at lines 284–299: 12 `SKShapeNode` rect segments per copy
(two copies for the scroll wrap), 14pt tall, fill color `0x4FA64F`, no stroke,
forming a continuous ribbon at the bottom of the screen. No PNG involved.
The warm-tone foreground buildings just above it (lines 306–335) are also
programmatic `SKShapeNode` rounded rects drawn from a 4-color palette.

### 2. Mountain scene clouds — programmatic SKShapeNode ellipses

Built in `buildCloudWisps()` at `SkyAce/Scenes/FreeFlightMountainScene.swift:271-284`:
three `SKShapeNode(ellipseOf: CGSize(width: 140, height: 24))` with white fill
at 0.55 alpha, randomly positioned in the upper sky band and scrolled at 30pt/s.

The only PNG clouds in the project are gameplay *obstacles*, not decor:
`cloud_plain` in `SkyAce/Nodes/ObstacleNode.swift:113` and the
`cloud_pillar_top` / `cloud_pillar_bottom` sprites used by `GameScene`.

### 3. Existing sun / glow effects — no sun disc exists anywhere

There is no sun, sun glow, radial-gradient texture, or sun PNG in the codebase.
The closest existing patterns:

- **The golden-hour sky is already in the target scene** — `goldenHourTexture`
  at `SkyAce/Scenes/LandingPracticeScene.swift:154-177` renders an amber →
  pale-yellow linear gradient via `UIGraphicsImageRenderer`. The comment at
  line 150 notes the gradient holds constant below the horizon "so the glow
  sits right where the runway meets the sky."
- **`SKShapeNode.glowWidth` halo pattern** — `SkyAce/Nodes/RingNode.swift:31`
  (`glowWidth = 4`) and the pulsing aura in
  `SkyAce/Nodes/FinishLineNode.swift:23-31` (`glowWidth = 14`). This is the
  project's established way to make something glow.
- **`SKEmitterNode` effects** — snow (`FreeFlightMountainScene.swift:489`),
  dust cloud (`LandingPracticeScene.swift:443`), boost trail
  (`PlaneNode.swift:387`).

---

## Recommendations

| Element | Recommendation | Basis |
|---|---|---|
| Grass ground strip | **Procedural** | Direct precedent: City grass is `SKShapeNode` rects (`FreeFlightCityScene.swift:284`). Copy the pattern; warm the green toward the golden-hour palette. |
| Sunset clouds | **Procedural** | Direct precedent: Mountain wisps are `SKShapeNode` ellipses. Same code with peach/gold fills (e.g. white → `0xF5D7A8` at ~0.5 alpha) gets a consistent look in minutes. |
| Sun glow / disc | **Procedural** | No asset exists; the scene already renders its own gradient textures, and `glowWidth` circles (RingNode/FinishLineNode pattern) or a small radial-gradient `UIGraphicsImageRenderer` texture both fit existing idioms. A painted PNG sun would be hard to blend seamlessly into the programmatic gradient sky. |
| Approach lighting | **Procedural** | Functional, repeating geometry that must be positioned relative to `LandingZoneNode`'s halt point — a row of small `SKShapeNode` circles with `glowWidth` is exactly the FinishLineNode aura pattern. Closest analog to the "structural element" exception the cable car's cable received in SKY-23. |
| Hangar/building silhouettes | **Stitch PNG** | All painted horizon scenery in this project is Stitch art: `city_skyline_bg`, the three `mountain_bg_*` strips. The City scene's programmatic buildings are deliberately crude near-foreground filler; a horizon silhouette is exactly what the painted strips do. |
| Control tower / windsock | **Stitch PNG** | Matches the landmark/prop pattern (`ski_lodge`, `cable_car`, city landmarks) — a distinctive visual subject, squarely inside the CLAUDE.md Stitch mandate. |

**Caveat:** under the project's Stitch rule, even the four "procedural" items
are technically visual assets, so the safe path is a quick Stitch lookup for
all six before coding, with the procedural ones proceeding as placeholders
only on explicit approval. The grass, clouds, and glow have direct
programmatic precedents in shipped scenes.

---

## Stitch asset specs

Both assets should be loose 1x PNGs in `SkyAce/Resources/Sprites/` (folder
reference), snake_case filenames, with constants added to the `SkySprites`
enum (`SkyAce/UI/SkyUIEffects.swift:222`) and loaded via
`SkySprites.texture(named:)` with a programmatic fallback — every scene
follows this pattern.

### Hangar/building silhouette strip

- **Suggested filename:** `landing_hangar_silhouettes.png`
- **Dimensions:** 661 × 377, transparent background — matching the
  `mountain_bg_far/mid/near` strips, the established horizon-layer format.
- **Tiling:** not required. The Landing Practice background is static (only
  the runway moves), so the strip is placed once on the right horizon.
- **Palette:** warm dusk silhouette tones, designed to sit against the
  `0xF5E6C0` horizon band of the golden-hour gradient.

### Control tower or windsock

- **Suggested filename:** `landing_control_tower.png`
- **Dimensions:** 512 × 512, transparent background — matching all eight
  landmark sprites.
- **Shadow convention:** landmark PNGs carry a painted drop-shadow in roughly
  the bottom 18% of the canvas, which scenes compensate for when
  ground-anchoring (`FreeFlightCityScene.swift:453-462`). Either keep that
  convention or request no shadow and skip the offset.

### Scale reference

Existing scenes render the 512×512 landmarks at 160–200pt display sizes and
the 661×377 strips at 110–220pt tall, so the same source resolutions are
comfortably sufficient here.

### Existing sprite dimensions (reference)

| Asset | Pixels | Role |
|---|---|---|
| `city_skyline_bg.png` | 512 × 293 | far horizon strip (City) |
| `mountain_bg_far/mid/near.png` | 661 × 377 | parallax horizon strips (Mountain) |
| `pine_trees.png` | 661 × 377 | foreground strip (Mountain) |
| `city_*` landmarks | 512 × 512 | hero landmarks (City) |
| `mountain_*` landmarks | 512 × 512 | hero landmarks (Mountain) |
| `ski_lodge.png`, `cable_car.png`, `hang_glider.png`, `hot_air_balloon.png` | 500 × 500 | ambient props (Mountain) |
| `runway_strip.png` | 1344 × 240 | runway (Landing Practice) |
| `landing_zone_indicator.png` | 750 × 580 | touchdown indicator (Landing Practice) |
