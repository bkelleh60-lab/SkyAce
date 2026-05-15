# Sky Ace — Level `obstacleGap` Audit

## Where the values live

There is no separate `ChallengeCatalog.swift` file. `ChallengeCatalog` is an `enum` defined alongside the `Challenge` struct in `SkyAce/Models/Challenge.swift` (starting at line 81).

## `obstacleGap` is computed, not stored per level

None of the 10 `Challenge(...)` initializers in `ChallengeCatalog.all` (`Challenge.swift:84-98`) pass an `obstacleGap` value — the struct has no stored property for it. Instead, it's derived inside the struct from a shared base value and a per-level multiplier:

```swift
// Challenge.swift:34
static let baseObstacleGap: CGFloat = 200.0

// Challenge.swift:40-51
static let obstacleGapMultipliers: [CGFloat] = [
    1.20, 1.10, 1.00, 0.95, 0.90, 0.87, 0.84, 0.81, 0.78, 0.75
]

// Challenge.swift:54-57
var obstacleGap: CGFloat {
    let idx = max(0, min(Challenge.obstacleGapMultipliers.count - 1, id - 1))
    return Challenge.baseObstacleGap * Challenge.obstacleGapMultipliers[idx]
}
```

So every level's `obstacleGap` is `200.0 × obstacleGapMultipliers[id - 1]`. None of the 10 levels override or explicitly set the value — all inherit from the shared formula.

## Per-level table

| ID | Chapter      | Name              | Type            | Multiplier | obstacleGap (pts) |
|---:|--------------|-------------------|-----------------|-----------:|------------------:|
| 1  | Clear Skies  | First Flight      | obstacleCourse  | 1.20       | 240.0             |
| 2  | Clear Skies  | Cloud Canyon      | obstacleCourse  | 1.10       | 220.0             |
| 3  | Clear Skies  | Sunny Sprint      | timeTrial       | 1.00       | 200.0             |
| 4  | Clear Skies  | Coin Scatter      | coinChain       | 0.95       | 190.0             |
| 5  | Clear Skies  | Gusty Gorge       | obstacleCourse  | 0.90       | 180.0             |
| 6  | Storm Chaser | Lightning Dash    | timeTrial       | 0.87       | 174.0             |
| 7  | Storm Chaser | Thunder Gap       | obstacleCourse  | 0.84       | 168.0             |
| 8  | Storm Chaser | The Coin Tornado  | coinChain       | 0.81       | 162.0             |
| 9  | Storm Chaser | Hurricane Alley   | obstacleCourse  | 0.78       | 156.0             |
| 10 | Storm Chaser | Sky Ace Challenge | obstacleCourse  | 0.75       | 150.0             |

## Notes

- `obstacleGap` is only gameplay-meaningful for `obstacleCourse` levels (1, 2, 5, 7, 9, 10). It is still computed for `timeTrial` (3, 6) and `coinChain` (4, 8) levels, but those mission types do not consume it when spawning.
- The curve is intentionally non-monotonic across L3 → L4 → L5 (1.00 → 0.95 → 0.90): L4 is a `coinChain` and L5 is the chapter-closing `obstacleCourse`, so the gap tightens steadily even though obstacles are not the focus of every level.
- To re-tune the whole progression, change `baseObstacleGap` (uniform scale) or edit individual entries in `obstacleGapMultipliers` (per-level scale). No call sites need to change.
