# SKY-125 — Race Mode Networking Feasibility Spike

**Date:** 2026-09-14
**Revised:** 2026-09-14, second research pass on the Game Center question.
§B6 is rewritten and its conclusion reversed; §A7 gains item (d); the TL;DR and
§§6-7 are updated to match. The recommendation itself is unchanged.
**Scope:** Research and codebase review only. No production code, no UI, no
level design, no Game Center integration. Per the ticket, every question that
can only be settled by a proof-of-concept build is flagged as such.

---

## TL;DR

1. **Option A is feasible, but not the way the ticket frames it.**
   MultipeerConnectivity was **formally deprecated in Xcode 27**. Local
   peer-to-peer should be built on **Network framework** (`NWListener` /
   `NWBrowser` / `NWConnection` with `includePeerToPeer = true`), which Apple
   names as the migration target. Answer to "can it support a 60fps real-time
   arcade race": **yes**, with high confidence, because the sync problem here
   is far smaller than the ticket assumes (see §3).

2. **Option B is viable for this audience. An earlier version of this report
   said otherwise, and it was wrong.** Apple's GameKit documentation ties
   underage status to the removal of *communication* features (voice and
   personalized invitation text), not to a multiplayer ban, and Apple's Family
   Privacy Disclosure for Children explicitly describes children playing and
   interacting through Game Center. The widely-cited "under-13 block" reports
   both trace to Apple Arcade titles and third-party data collection, not to a
   platform restriction. See §B6 for the full correction. Multiplayer
   availability is a parent-controlled **Screen Time** setting, which makes
   Option B's real risk a product question (how many target households permit
   it) rather than a feasibility one.

3. **Recommendation: Option A, on Network framework, behind a parental gate,
   with the transport hidden behind a protocol** so Option B can be added later
   without a rewrite. Roughly 60 to 70% of the work (race scene, deterministic
   course, clock sync, opponent rendering, finish arbitration) is
   transport-agnostic and gets built either way.

4. **The single most important design decision:** each device simulates only
   its own plane, both devices generate the identical course from a shared
   seed, and the opponent plane is a **rendered ghost with no physics body**.
   That removes authority conflicts, collision reconciliation, and rollback
   entirely. Latency stops being a fairness problem and becomes a cosmetic one.

---

## 1. What the codebase actually looks like

Findings that drive every recommendation below.

### 1.1 The game is already a one-axis game

`GameScene.update(_:)` at `SkyAce/Scenes/GameScene.swift:605`:

```swift
// Keep plane horizontally fixed — world moves past it.
plane.position.x += (size.width * 0.25 - plane.position.x) * 0.12
```

The plane's x is pinned to 25% of screen width. The world scrolls past it.
The only player-controlled degree of freedom is **y**. Input is binary: a single
`isTouchingScreen` flag set in `touchesBegan` (`GameScene.swift:1579`) and
cleared on touch end, which drives `plane.climb()` once per frame.

This is the best possible starting point for a networked race. The complete
authoritative state of one player is a single float plus a bool.

### 1.2 There is zero Game Center scaffolding

A repo-wide search for `GameKit`, `GKMatch`, `GKLocalPlayer`, `GKAchievement`,
`MultipeerConnectivity`, `MCSession` and `GameCenter` across all `.swift`,
`.plist`, `.entitlements`, `.pbxproj` and `.md` files returns **no matches**.

SKY-68 (Game Center Achievements) reached "In Progress" twice and was
**Canceled** both times, most recently 2026-08-06. Its PR (#101) left nothing
behind. Option B starts from zero: capability, entitlements, App Store Connect
configuration, authentication, the lot.

Worth noting: SKY-68's description asserted that "`GKLocalPlayer`
authentication ... does not require a parental gate" and that Game Center is
"fully compliant with Kids Category requirements." Those claims were never
validated by App Review, because the ticket was cancelled before submission.
They should be treated as untested assumptions, not settled facts.

### 1.3 Course generation is non-deterministic today

Every spawn decision uses the system RNG. The ones that affect gameplay
geometry (as opposed to cosmetics):

| Location | What it randomises |
| -- | -- |
| `SkyAce/Nodes/ObstacleNode.swift:26` | `gapCenterY`, the gap position of every obstacle pair |
| `GameScene.swift:147`, `:747` | `nextBigRingObstacleTarget`, big-ring cadence |
| `GameScene.swift:823`, `:825` | coin-line centre Y |
| `GameScene.swift:886` | big-ring centre Y |
| `GameScene.swift:1102` | coin-pattern centre Y |

Cosmetic-only randomness that can stay unseeded: `GameScene.swift:252-267`
(parallax clouds), `GameScene.swift:1314-1315` (crash debris),
`ObstacleNode.swift:190`, `:199`, `:348` (visual jitter, texture pick).

For Race Mode both devices must produce byte-identical geometry. That means a
seeded PRNG (a small `SeededGenerator: RandomNumberGenerator`, ~20 lines)
threaded through the race spawner, and `ObstacleNode` needs its `gapCenterY`
made injectable rather than self-randomised. Both are small, contained changes.

### 1.4 Plane motion is not deterministic across devices, and that is fine

`PlaneNode` drives motion through `SKPhysicsBody` with scene gravity
(`PlaneNode.gravity = -5.0`, wired in `GameScene.didMove(to:)` at
`GameScene.swift:128`), and the sustained-hold ramp reads wall clock:

```swift
// PlaneNode.swift:248
let now = CACurrentMediaTime()
```

SpriteKit integrates physics at variable frame deltas and makes no
bit-reproducibility guarantee across devices. So **true lockstep is not
available** without rewriting plane motion onto a fixed-timestep integrator.

The recommended design (§3) does not need lockstep, so this never has to be
solved. It is called out because the obvious first instinct ("send inputs, both
sides simulate both planes") *does* need it, and would quietly desync.

### 1.5 `Challenge` cannot carry race levels

`SkyAce/Models/Challenge.swift` is welded to the mission progression:

- `ChallengeCatalog.all` is a static 10-entry array that `MapScene`,
  `ProgressManager` and `ChallengeCatalog.finalLevelID` all iterate. Adding
  race entries would leak into map layout, unlock logic and the "Certified Sky
  Ace" whole-game-completion badge from SKY-123.
- `Challenge` fields are all mission-grading concepts: `reward`,
  `levelDuration`, `obstacleGapMultipliers` indexed by `id - 1`.
- `GameState` (`SkyAce/Models/GameState.swift`) encodes star rating, coin
  ratios, armor and win-on-timer semantics. None of it applies to a race.

Race Mode needs its own model type (say `RaceCourse` in `Models/`) and its own
scene. Attempting to extend `Challenge` would be the wrong call and would put
the existing 10 levels at risk, which the ticket explicitly rules out.

### 1.6 Two planes at different heights: no obstacle in the way

Nothing blocks it. There is no plane-to-plane physics category
(`PhysicsCategory` in `PlaneNode.swift:8-16` has no such entry), and
`collisionBitMask = 0` everywhere (`PlaneNode.swift:223`) so SpriteKit never
resolves contacts itself. The boundary walls built in
`GameScene.buildBoundaries()` are `PhysicsCategory.boundary` and trigger
`handleBoundaryCrash()` on contact.

The opponent ghost should carry **no `physicsBody` at all**. It then cannot
trip boundaries, cannot collect the local player's coins, and cannot collide
with anything. Its position is set directly each frame from the network buffer.

---

## 2. Option A: local peer-to-peer

### A1. Which framework?

**Not MultipeerConnectivity.** An Apple DTS engineer states plainly in the
official migration thread:

> "Xcode 27, currently in beta, has formally deprecated Multipeer Connectivity."

Apple's stated reasons include, verbatim from that thread: "good latency but
poor throughput", "no flow control/back pressure support", "obsolete UI
components", relies on the deprecated `NSStream`, "always enables peer-to-peer
Wi-Fi (impacting network performance)", and "some gnarly bugs."

The migration target is **Network framework**, documented in technical note
**TN3213, "Moving from Multipeer Connectivity to Network framework."** Apple
also flags the specific misconception that matters here:

> "**IMPORTANT** Many folks use Multipeer Connectivity because they think it's
> the only way to use peer-to-peer Wi-Fi. That's not the case. Network
> framework has opt-in peer-to-peer Wi-Fi support."

So: `NWListener` advertising a Bonjour service on the host side, `NWBrowser`
discovering it on the joiner side, both with `NWParameters` where
`includePeerToPeer = true`, and an `NWConnection` carrying UDP datagrams for
state and TCP (or a reliable channel) for lobby handshake and results.

Was MultipeerConnectivity ever appropriate for a real-time arcade game? Apple's
own summary, "good latency but poor throughput", says it was usable for this
exact shape of workload (tiny frequent messages) and bad for the opposite (bulk
transfer). But the deprecation settles it regardless.

**Deployment target note:** the project is at `IPHONEOS_DEPLOYMENT_TARGET =
16.0`. Network framework peer-to-peer has been available since iOS 12, so
there is no floor problem.

### A2. Realistic latency

Honest answer: **I cannot measure this here, and neither can any amount of
further reading. This is POC item #1.**

What the published evidence supports:

- A 2025 arXiv study of cross-device interaction over Apple's native frameworks
  measured **mean one-way latency of 70.4 ms** across 1,000 sampled events
  between an iPhone and a MacBook Pro over standard Wi-Fi using
  MultipeerConnectivity. That is roughly **140 ms round trip**, and it is a
  worst-ish case: MPC's connection setup, a heterogeneous device pair, and an
  unspecified network.
- Two iPhones on the same modern Wi-Fi router, sending ~14-byte UDP datagrams
  over Network framework, should do considerably better. A 20 to 60 ms RTT is
  the reasonable expectation. But "should" is doing real work in that sentence.

**Is sub-100ms RTT achievable in practice?** Probably yes on a decent home
Wi-Fi network, and the design in §3 means it barely matters if we occasionally
miss. But do not commit to a number without measuring. A one-day POC (ping /
pong with a logged RTT histogram across a few real households) settles it.

### A3. What has to sync, and how much bandwidth

Minimum useful per-sample payload:

| Field | Type | Bytes |
| -- | -- | -- |
| message type | `UInt8` | 1 |
| race time (ms since green light) | `UInt32` | 4 |
| plane y | `Float32` | 4 |
| plane vertical velocity | `Float32` | 4 |
| flags (holding, crashed, finished) | `UInt8` | 1 |
| **total** | | **14** |

At a full 60 Hz that is 840 B/s of payload. With UDP + IPv6 headers (~48 bytes)
call it ~62 bytes on the wire per packet, so **~3.7 KB/s, about 30 kbit/s**,
each direction. On Wi-Fi that is nothing. **Bandwidth is not a constraint for
this game, at any send rate we would plausibly choose.**

Which means the send rate should be chosen for latency and jitter behaviour,
not for bandwidth. Recommendation in §3.

### A4. Connection flow, tap to green light

No server, no accounts, no prior setup:

1. Player taps Race Mode. **Parental gate appears first** (see A7).
2. Player picks Host or Join.
3. **Host:** `NWListener` starts advertising a Bonjour service (e.g.
   `_skyace-race._udp`) with a **non-identifying instance name** (see A7).
4. **Joiner:** `NWBrowser` lists nearby services. Player taps one.
5. `NWConnection` established. First use on each device triggers the **iOS
   Local Network permission prompt**.
6. Lobby handshake over the reliable channel: protocol version, chosen course
   id, **shared RNG seed** (host picks), each side's plane id and callsign.
   Abort with a friendly message on version mismatch.
7. Clock sync: 5 to 10 ping / pong exchanges, NTP-style offset estimate
   `offset = ((t1 - t0) + (t2 - t3)) / 2`, keep the sample with the lowest RTT.
8. Host picks a green-light instant ~2.5 s in the future in shared-clock terms
   and sends it. Both devices run a local 3-2-1 countdown to that instant.
9. Both devices start their own simulation at their local translation of that
   instant. Error should be well under one frame if the offset estimate is good.

Realistic time from tap to racing: a few seconds for discovery, plus a one-time
permission prompt on first ever use.

### A5. Sleep, disconnect, quit mid-race

`NWConnection`'s state handler surfaces `.failed` and `.cancelled`, and a
missing-heartbeat timer catches the silent cases (device sleeps, app
backgrounds, player walks out of Wi-Fi range).

Recommended behaviour, and it should be a deliberate product decision rather
than an error dialog: **the race continues locally as a solo run.** Fade the
opponent ghost out, show a soft "Your friend disconnected" banner, let the
player finish the course and see their time. For an 8-to-13-year-old sitting
next to a friend whose iPad went to sleep, an abrupt kick back to the menu is a
worse outcome than an unclaimed win. No reconnect logic in v1: a re-race is two
taps away.

Also needed: the app already handles backgrounding through the standard
lifecycle, but Race Mode should treat "we backgrounded" as "we forfeit,"
because SpriteKit pauses and the race clock would desync anyway.

### A6. Bluetooth?

Effectively **no**, and it should not be part of the plan.

MultipeerConnectivity historically advertised infrastructure Wi-Fi,
peer-to-peer Wi-Fi and Bluetooth as transports, but its Bluetooth peer-to-peer
path has been broken or unavailable since around iOS 11, with developer reports
that Wi-Fi must be enabled on both devices regardless. Network framework's
peer-to-peer support is Wi-Fi (AWDL) based, not Bluetooth.

Since MPC is deprecated anyway, treat this as settled: **Race Mode requires
Wi-Fi enabled on both devices.** They do not necessarily need to be on the same
network (peer-to-peer Wi-Fi handles that), but Wi-Fi must be on. Worth a line
in the UI copy.

### A7. Kids Category implications

Four real items, one of which is a genuine trap.

**(a) The Local Network prompt requires a parental gate.**
Apple's Kids Category announcement states that apps must "require a parental
gate in order to link out of the app, **request permissions**, or present
purchasing opportunities." The Local Network permission prompt is a permission
request. Therefore **the Race Mode entry point must sit behind the parental
gate**, the same gate the IAP flow will use (still unbuilt per CLAUDE.md).

Practically: `NSLocalNetworkUsageDescription` and `NSBonjourServices` go in
`Info.plist`, and the first `NWBrowser`/`NWListener` start must only ever be
reachable from the gate's success callback. This mirrors the rule CLAUDE.md
already states for StoreKit.

**(b) Do not broadcast the device name. This is the trap.**
Bonjour service instance names and `MCPeerID` display names conventionally
default to the device name, which on a kid's iPad is usually a real first name
("Ella's iPad"). Broadcasting that over the local network from a Kids Category
app is a personally identifiable information leak, and it is broadcast to every
device on the network, not just the peer.

Use a **randomly assigned callsign from a fixed preset list** ("Red Falcon",
"Sky Otter") as both the Bonjour instance name and the in-game label. Never a
user-typed name, which would also invoke the system keyboard and violate
CLAUDE.md's keyboard rule.

**(c) No chat, no free text, ever.**
Guideline 5.1.4 pulls in apps that "have the capability to share personal
information ... [including] the ability to chat." Race Mode must ship with zero
text entry and zero free-form communication. Preset emotes at most, and even
those are a v2 conversation.

**(d) Apple treats "nearby multiplayer" as its own parental-control axis.**
Added on the second research pass. Screen Time carries a distinct **"Allow
Nearby Multiplayer"** setting, which Apple describes as covering "players on the
same local network (for example, players connected to the same Wi-Fi network or
who are located within Bluetooth range)." That is exactly the Option A use case.

The setting is documented as a Game Center control, and there is no public
mechanism by which Screen Time could police arbitrary UDP or Bonjour traffic
from a non-GameKit app, so it almost certainly does **not** technically bind a
custom Network framework implementation. That is an inference, not a documented
guarantee, and it is listed in §7 as an open question.

The more useful takeaway is normative rather than technical: Apple has decided
that nearby multiplayer is something parents should be able to switch off. A
Kids Category app doing local peer-to-peer should behave consistently with that
expectation even where no API forces it. In practice the parental gate from (a)
already achieves the same outcome, since a parent who does not want it can
simply not pass the gate.

On the positive side: no PII is transmitted (14 bytes of y, velocity and
flags), nothing leaves the local network, no third party is involved, and no
new privacy-nutrition-label disclosures are triggered. Guideline 1.3's "may not
send personally identifiable information or device information to third
parties" is satisfied cleanly, **provided (b) is honoured.**

---

## 3. Shared design questions (both options)

These answers are transport-agnostic, which is precisely why this work should
be built first.

### S1. State sync approach

**Recommendation: hybrid, 20 to 30 Hz state samples plus immediate input
events, and do not attempt lockstep.**

Why not input-events-only: input events alone require both devices to simulate
both planes identically, which §1.4 shows is not available without rewriting
plane motion off `SKPhysicsBody`. Even then, a single dropped or late input
event desyncs the opponent's plane permanently with no correction path. Visual
smoothness would be excellent right up until it silently was not.

Why not every frame: bandwidth is free (§A3), so 60 Hz is affordable, but it
doubles packet processing for a visual improvement that the interpolation
buffer (S2) already delivers. 20 to 30 Hz is the sweet spot. Bump to 60 Hz only
if a POC shows the ghost reads as laggy, which it should not.

The input events (tap down, tap up) are sent immediately on change, in addition
to the periodic samples. They cost nothing, they arrive before the next
scheduled sample, and they let the receiving side start the opponent's climb a
frame or two earlier, which is what the eye actually notices.

All of this goes over an **unreliable / datagram** channel. Retransmitting a
position sample from 80 ms ago is worse than useless, since a newer one is
already in flight. The lobby handshake, the green-light instant and the finish
report go over a **reliable** channel.

### S2. Rendering the opponent

**Recommendation: interpolation buffer, rendering the opponent ~100 ms in the
past. Never render raw received positions.**

Keep the last few received samples. Render the ghost at `now - 100ms` by
interpolating between the two samples that bracket that time. When a sample is
late, extrapolate briefly using the last known vertical velocity (dead
reckoning), capped at ~150 ms before freezing the ghost.

This is unambiguously right for this game because **the opponent's exact
position is not gameplay-relevant.** There is no plane-to-plane collision. The
ghost is a visual pacing cue and nothing else. A 100 ms display lag on
something no one can collide with is invisible, and it buys complete immunity
to jitter. Raw position rendering would visibly stutter at any realistic
packet-loss rate.

For a single smooth axis driven by gravity plus impulses, linear interpolation
on position with velocity-based extrapolation is sufficient. No Hermite curves,
no rollback, no reconciliation.

### S3. Race start sync

Covered in A4 steps 7 and 8: NTP-style clock offset estimation, then a shared
future green-light instant, then both devices start locally. The 3-2-1
countdown is not just presentation, it is the buffer that absorbs handshake and
clock-sync variance.

One subtlety: **all race timestamps should be expressed as milliseconds since
green light**, not as wall-clock time. That way the clock offset is applied
exactly once, at start, and every subsequent comparison (positions, finish
times) is in a shared race-relative frame.

### S4. Finish line detection

**Local detection is sufficient and should be authoritative for that player's
own finish time.**

Each device detects its own finish through the existing contact path
(`PhysicsCategory.finish` → `handleFinishLineCross()` at
`GameScene.swift:1022`), records its race-relative finish time in ms, and sends
it over the **reliable** channel. Both devices then independently compare the
two numbers and reach the same verdict. Tie-break on the lexicographically
lower peer identifier, so both sides agree even in an exact tie.

This is fair because both devices fly the identical course from the shared seed
and both race clocks are anchored to the same green light. It needs no
confirmation round-trip, and the winner is displayed the moment the second
finish report lands.

The threat model here is a child cheating by patching the binary. For a local
co-play game between two kids in the same room, that is not worth a single line
of anti-cheat code.

Edge case worth handling: a player who crashes out never sends a finish time.
Send an explicit "did not finish" message so the opponent's device does not sit
waiting.

### S5. Level architecture

Race Mode needs a **new scene**. See §1.5. `Challenge` and `GameState` are
mission-grading types and extending them would put the existing 10 levels and
the SKY-123 completion badge at risk.

Proposed shape, consistent with the layout CLAUDE.md describes:

```
Models/RaceCourse.swift          // seed, length, obstacle density, theme
Models/RaceState.swift           // race-relative clock, own/opponent finish
Managers/RaceSessionManager.swift// transport-agnostic session + clock sync
Scenes/RaceScene.swift           // own plane simulated, opponent ghost rendered
UI/RaceHUD…                      // position pill, opponent gap indicator
```

with the transport itself behind a protocol:

```swift
protocol RaceTransport: AnyObject {
    func send(_ payload: Data, reliable: Bool)
    var delegate: RaceTransportDelegate? { get set }
}
```

`LocalNetworkTransport` implements it for Option A. A future
`GameCenterTransport` implements it for Option B with no change above it. This
protocol is the reason the hybrid path in §6 is cheap.

### S6. Codebase reuse

**Reusable as-is, no changes:** `ObstacleNode`, `CoinNode`, `RingNode`,
`BigRingNode`, `FinishLineNode`, `SkyColors` / `SkyFonts` / `SkySprites`,
`SkyUIEffects`, `AudioManager`, `CurrencyManager`, and the `UI/` primitives
(`SkyChunkyButton`, `CurrencyHUD`, and friends).

**`PlaneNode.swift` (654 lines): high reuse, one small addition.**
The local plane uses it unchanged. The opponent ghost needs a lightweight mode:
no `physicsBody`, position assigned externally, but keep the tilt logic in
`update(delta:)` and the visual body. Best done with an init parameter or a
`configureAsGhost()` method on the existing class, not a fork, so plane art and
ability visuals stay in one place. Ghosts should skip ability effects entirely
in v1.

**`GameScene.swift` (1660 lines): patterns reusable, class not.**
Directly liftable by copy-and-adapt: camera setup (`setupCamera()`), parallax
build (`buildParallaxBackground()`), boundary walls (`buildBoundaries()`),
spawn scheduling shape (`spawnTick(currentTime:)`), off-screen culling
(`cullOffscreenChildren()`), contact routing (`didBegin(_:)`), and the HUD
layout approach including the safe-area handling from SKY-98.

Not reusable: anything touching `GameState` (star rating, coin ratio, armor,
timer win condition) or `SkyNavigator.showResults(...)`, which takes a
mission-shaped argument list.

Rough split: **~40 to 50% of `GameScene`'s structure carries over** by
copy-adapt. Close to 0% carries over by subclassing, and attempting to subclass
would be a mistake given how much of the class is mission-grading logic.

**Needs a targeted change:** the seeded-RNG work from §1.3.

---

## 4. Option B: Game Center

### B1. What re-integration entails

Everything, from zero (§1.2). Enable the Game Center capability and
entitlements, configure the app in App Store Connect, authenticate via
`GKLocalPlayer.local.authenticateHandler` at launch, then build the
matchmaking and `GKMatch` data layer on top.

### B2. The GKMatch / GKMatchmaker flow

1. Authenticate `GKLocalPlayer` at launch. If the player is not signed in,
   GameKit presents Apple's sign-in UI.
2. Build a `GKMatchRequest` with `minPlayers = 2`, `maxPlayers = 2`.
3. Either present `GKMatchmakerViewController` (Apple's UI, includes the invite
   and nearby-players affordances) or drive `GKMatchmaker.shared()` directly
   with a custom UI.
4. On success a `GKMatch` arrives with a connected peer.
5. Exchange handshake, seed and green-light instant over `GKMatch.SendDataMode`
   `.reliable`, then stream position samples over `.unreliable`.
6. Race proceeds exactly as in §3. The whole of §3 is unchanged.

### B3. Expected latency

Worse than Option A, and more variable.

`GKMatch` forms a peer-to-peer connection where the network permits, and falls
back to **Apple relay servers** when NAT traversal fails. Relay adds a hop in
each direction. A developer report on Apple's forums measured **300 ms ping
through GameKit versus 120 ms through Unity's Relay under identical
conditions**, and noted reconnects taking **up to 15 seconds** when connections
dropped.

**Is sub-100ms achievable on LTE / 5G?** Sometimes, on a good 5G connection
with a direct peer-to-peer path. Not reliably, and not something to design
around. Plan for 100 to 300 ms RTT with occasional spikes.

The good news: the design in §3 tolerates this far better than a naive one
would, because the opponent is a non-colliding ghost. At 300 ms the ghost's
displayed position is meaningfully stale, which degrades the "neck and neck"
feeling, but it never produces an unfair result. The finish comparison is
race-relative and unaffected by transport latency.

### B4. Reliability layer

`GKMatch` provides both modes: `.reliable` (ordered, guaranteed) and
`.unreliable` (best-effort, may drop, may reorder). Same split as Option A: the
game does **not** need to build its own reliability layer.

It does need its own **sequence numbers on unreliable messages**, because
unreliable delivery may reorder, and applying a stale position sample after a
newer one would visibly jerk the ghost. That is four lines of code and is
needed in both options.

### B5. Friends versus random matchmaking

Both are available. `GKMatchmakerViewController` supports inviting specific
Game Center friends as well as auto-matching with strangers, and
`GKMatchmaker.shared()` supports programmatic invites.

**For this app, friends-only or invite-only is the only defensible choice.**
Random matchmaking pairs a 9-year-old with an unknown stranger. Even with zero
chat, that is a design decision that invites App Review scrutiny in the Kids
Category and is a hard conversation to have with parents.

Which sets up the real constraint on Option B's reach: the compelling version
("play with your cousin in another state") requires both children to have Game
Center accounts and to be Game Center friends, and requires both parents to
have left multiplayer enabled. That is a reach question, not a feasibility one.
See §B6.

### B6. Kids Category requirements

**Revised 2026-09-14 after a second research pass. The first version of this
section called the under-13 restriction a probable hard blocker. Apple's own
documentation does not support that, and the section below replaces it.**

#### What Apple actually documents

GameKit exposes three separate properties on `GKLocalPlayer`, and they are
commonly conflated. They are not the same thing:

| Property | Since | What it actually reflects |
| -- | -- | -- |
| `isUnderage` | iOS 4.1 | The Game Center account's underage status |
| `isMultiplayerGamingRestricted` | iOS 13.0 | The **Screen Time** multiplayer setting |
| `isPersonalizedCommunicationRestricted` | iOS 14.0 | The Screen Time communication setting |

Apple's documented consequence of being underage is narrow and specific. From
the `isPersonalizedCommunicationRestricted` reference:

> "If this property **or the underage property** is `true`, the local player
> can't include personalized messages on invitations or enable voice
> communication in multiplayer games."

And from Apple's "Authenticating a player" guide:

> "If the `isPersonalizedCommunicationRestricted` property is `true`, then the
> player isn't allowed to use voice or messaging features during a multiplayer
> game. ... **Note that if the player is underage, this property is always
> true.**"

The `isUnderage` reference itself says only that "Game Center disables some
features for the local player." **Nowhere in GameKit's documentation does Apple
state that underage status prevents a player from joining multiplayer matches.**
The documented effect of underage status is the removal of *communication*
features: voice chat and personalized invitation text.

Apple's own Family Privacy Disclosure for Children is more direct still. It
describes children as able to:

> "Play games and interact with other users using Game Center and the Apple
> Games app, and share information with others, including your child's Game
> Center nickname, avatar, and friends."

That is Apple's legal disclosure describing child-account Game Center
interaction as an expected, supported behaviour.

#### Where the "under-13 block" story came from

Both widely-cited community reports turn out to be narrower than they look, and
neither is evidence of a platform-level ban:

- **Wonderbox** (Apple Arcade). Parents reported multiplayer blocked for a
  10-year-old. The explanation in the thread is that *the developer* collected
  personal data during multiplayer and needed consent that cannot be given
  under 13. A later reply in the same thread reports the developer shipped an
  update that "solves our problem." That is a third-party data-collection
  problem, not a Game Center restriction.
- **Crossy Castle** (Apple Arcade). The developer's reply states "an age
  restriction for multiplayer mode is required in order to be compliant with
  **Apple Arcade's policies**." Apple Arcade carries its own additional policy
  layer. **Sky Ace is not an Apple Arcade title**, so that policy does not
  apply to it.

Reading both sources carefully, neither establishes that Game Center blocks
multiplayer for under-13 accounts generally.

#### The real constraint: a parental setting, and an API trap

Multiplayer availability is governed by **Screen Time**, which a parent
controls, not by account age. Apple's Screen Time settings expose:

- **Allow Multiplayer Games With:** everyone / only Game Center friends / no one
- **Allow Nearby Multiplayer** (see A7(d) below)
- Plus Adding Friends, Connect with Friends, Private Messaging, Avatar &
  Nickname Changes, Profile Privacy Changes

And here is the trap, stated plainly in Apple's own reference for
`isMultiplayerGamingRestricted`:

> "The `isMultiplayerGamingRestricted` property reflects whether there are
> *any* restrictions. For example, **when you configure the setting to friends
> only, this property returns `true`** for restricted."

So the boolean is `true` both when multiplayer is fully disallowed **and** when
it is set to friends-only, which is exactly the configuration a well-supervised
9-to-11-year-old is most likely to have, and exactly the mode §B5 recommends.

**If Sky Ace gated Race Mode on `isMultiplayerGamingRestricted == false`, it
would lock out precisely its intended users.** An Apple reply quoted in the
developer forums confirms the intended handling:

> "For those who are interested, the 'Multiplayer with Friends Only' option
> gets handled by Game Center. Apps only need check for whether Disallow All
> Multiplayer is turned on."

The catch is that the public API cannot distinguish those two states. The
practical implication: do not pre-gate the UI on this boolean. Let the player
attempt matchmaking and handle the failure gracefully, or treat `true` as
"friends-only may still work" rather than "multiplayer is off."

#### Revised verdict on Option B's compliance risk

**Option B is not disqualified for this audience.** The risk is materially
lower than the first pass concluded. Two points now work *in its favour*:

1. Apple force-disables voice and personalized messaging for underage players.
   Sky Ace wants no chat anyway, so the platform enforces the app's own safety
   requirement rather than fighting it.
2. Matchmaking restricted to Game Center friends is a parent-controlled setting
   Apple already ships, which is a stronger story to tell parents than anything
   the app could build itself.

Remaining Option B compliance items, unchanged:

- SKY-68 asserted `GKLocalPlayer` authentication needs no parental gate. Still
  untested by App Review. At least one shipping Kids-audience app (Fizz) puts
  Game Center access behind a parental gate, which suggests the conservative
  reading is the common one. Recommend gating it.
- Game Center surfaces the opponent's nickname and avatar to the player. Apple's
  privacy disclosure names this explicitly, so it is sanctioned, but it is still
  another child's chosen identifier rendered inside a Kids Category app. Option
  A avoids it entirely with preset callsigns.

#### What still needs verifying

The question is no longer "is Option B possible." It is **"what fraction of the
target audience has a Screen Time configuration that permits it."** That is a
product-risk question rather than a feasibility one, and it cannot be answered
from documentation at all. A real child-account test (POC item #4 in §7, about
half a day) would confirm the behaviour end to end and show what the failure
mode actually looks like when a parent has multiplayer set to "no one."

### B7. Does Option B need a server?

No custom server. `GKMatch` uses Apple's matchmaking infrastructure for
discovery and Apple's relay servers as a fallback transport, so it is
"serverless" from the developer's perspective but not truly peer-to-peer. No
backend to build, host, pay for or secure, which is a genuine advantage over
rolling a custom internet multiplayer stack.

---

## 5. Complexity comparison

Weekend-sized units, where one weekend is roughly two focused days. These are
engineering estimates only and exclude race level design and art, which the
ticket puts out of scope but which are real and probably add 1 to 2 weekends.

| Work item | Option A | Option B | Shared? |
| -- | --: | --: | :--: |
| Transport layer | 1.5 | 2.0 | no |
| Matchmaking / connection UI | 1.0 | 1.5 | no |
| Game Center capability, entitlements, ASC config, auth | 0 | 1.0 | no |
| Clock sync + countdown start | 0.5 | 0.5 | yes |
| Seeded deterministic course | 1.0 | 1.0 | yes |
| `RaceScene` + `RaceState` + ghost rendering with interpolation | 1.5 | 1.5 | yes |
| Finish arbitration + disconnect handling | 0.5 | 1.0 | mostly |
| Kids compliance work (gate, callsigns, plist) | 0.5 | 0.5+ | partly |
| Playtest, tune, edge cases | 1.5 | 2.0 | mostly |
| **Total** | **~8** | **~11** | **~60-70% shared** |

The first version of this report added an unbounded compliance risk to Option
B's column. §B6 retracts that. Option B's remaining downside is the ~3 extra
weekends and its dependence on household Game Center configuration, not a risk
of the work being invalidated outright.

---

## 6. Recommendation

**Build Option A, on Network framework, behind the parental gate, with the
transport behind a `RaceTransport` protocol.**

**The recommendation is unchanged after the B6 correction, but the reasoning
is weaker and more honest than in the first version.** Option B is no longer
disqualified. The case for A-first is now about latency, cost and use-case fit
rather than about B being unavailable.

Reasoning:

1. **It matches the actual use case.** The ticket's own note says the "sitting
   next to each other" scenario strongly favours Option A, and that is also the
   scenario where two 10-year-olds are most likely to play. Kids in the same
   room is the realistic Race Mode session.

2. **The latency picture favours A by a wide margin, and this is now the
   strongest argument.** Local Wi-Fi in the tens of milliseconds versus
   GameKit's reported 300 ms with 15-second reconnects is the difference
   between "we're neck and neck" and "the other plane keeps teleporting." For a
   racing game where the entire feel depends on seeing your opponent beside
   you, that gap is the product.

3. **Option A costs less and ships sooner.** ~8 weekends versus ~11, and none
   of Option A's work depends on App Store Connect configuration, Game Center
   accounts existing on both devices, or a parent having set a Screen Time
   value correctly.

4. **Option A works regardless of household configuration.** This is the
   inverse of the point the first version got wrong. Option B now has no
   *feasibility* blocker, but it does have a real *reach* question: it works
   only for children whose parents have enabled Game Center multiplayer, who
   have added each other as Game Center friends, and who both have accounts.
   Option A requires two kids, two devices, and Wi-Fi.

5. **The compliance surface is smaller and fully controllable.** Option A
   transmits 14 bytes of flight data on a local network with no account, no
   stranger, no third party and no identifier, once the callsign trap in A7(b)
   is handled. Option B involves Apple accounts for children and a visible
   opponent nickname and avatar. Both are workable; A is simply less to defend.

6. **Hybrid is cheap, and A-first is the right order.** ~60 to 70% of the work
   is transport-agnostic. Building A first delivers a shipped, playable mode
   and simultaneously builds most of what B would need. Adding B later costs
   roughly the transport plus matchmaking plus Game Center setup (~4.5
   weekends), not a rewrite.

**Where Option B now looks genuinely attractive, and this is a real change from
the first version:** Apple force-disables voice and personalized messaging for
underage players, and parents can restrict matchmaking to Game Center friends
only. That means Apple's own platform enforces the two safety properties Sky
Ace would otherwise have to build and defend itself. If remote play with a
distant friend is a strategic priority rather than a nice-to-have, **Option B
as a phase 2 is a reasonable and well-supported plan**, not the risky bet the
first version implied. The ghost-rendering design in §3 is what makes its
latency survivable, and that design gets built in phase 1 either way.

## 7. Unknowns requiring a proof-of-concept

Ordered by value per hour spent. Reordered after the second research pass:
item 1 is no longer a feasibility question, so it drops below the latency work.

| # | Question | How to answer | Effort |
| -- | -- | -- | -- |
| 1 | Actual RTT between two iPhones over Network framework peer-to-peer, in real homes | Stub app: ping/pong, log RTT histogram, test across 3 to 4 households including a congested one | ~1 day |
| 2 | Connection time and reliability of peer-to-peer Wi-Fi when the two devices are *not* on the same network | Same stub, Wi-Fi off the same SSID | included above |
| 3 | Does peer-to-peer Wi-Fi (AWDL) degrade the household Wi-Fi during a race? | Same stub, watch throughput on a third device | included above |
| 4 | What does Game Center multiplayer actually do end to end on a real under-13 child account, and what is the failure mode when a parent has it set to "no one"? | Family Sharing child account aged 11, minimal `GKMatchRequest`, try each Screen Time value. No longer decisive for Option B, but it sizes Option B's reach. | ~0.5 day |
| 5 | Does Screen Time's "Allow Nearby Multiplayer" affect a non-GameKit Bonjour / Network framework app? | Child account with the setting off, run the Option A stub. Inference says no; undocumented either way. | ~1 hour, on top of #4 |
| 6 | Does App Review accept a parental gate in front of the Local Network prompt as sufficient? | Pre-submission developer question to App Review, or first submission | days to weeks, external |
| 7 | Is `GKLocalPlayer` sign-in a "permission request" under Kids guidance? | Same channel as #6. Shipping precedent (Fizz) gates it, so gating is the safe default regardless. | as above |
| 8 | How much does SpriteKit physics actually drift between two devices over a 60 s race? | Instrumented build logging own-plane y per race-second on both devices, diffed | ~0.5 day, only needed if we ever want a lockstep guarantee |

Items 1 and 4 together are about a day and a half. Item 1 is now the one that
could still change the engineering plan; item 4 only changes how much Option B
is worth as a phase 2.

---

## Sources

- [Moving from Multipeer Connectivity to Network framework — Apple Developer Forums (DTS)](https://developer.apple.com/forums/thread/776069)
- [MCSessionSendDataMode.unreliable — Apple Developer Documentation](https://developer.apple.com/documentation/multipeerconnectivity/mcsessionsenddatamode/unreliable)
- [Multipeer Connectivity in Games — objc.io](https://www.objc.io/issues/18-games/multipeer-connectivity-for-games/)
- [Cross-Device Motion Interaction via Apple's Native System Frameworks (arXiv)](https://arxiv.org/pdf/2508.01110)
- [App Updates in the Kids Category — Apple Developer News](https://developer.apple.com/news/?id=091202019a)
- [App Review Guidelines 1.3 and 5.1.4 — Apple Developer](https://developer.apple.com/app-store/review/guidelines/)
- [Real-Time Matches — GameKit Programming Guide (archive)](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/GameKit_Guide/Matchmaking/Matchmaking.html)
- [GKMatch.SendDataMode.unreliable — Apple Developer Documentation](https://developer.apple.com/documentation/gamekit/gkmatch/senddatamode/unreliable)
- [Bad network latency when using GameKit — Apple Developer Forums](https://forums.developer.apple.com/forums/thread/744192)
- [Use parental controls to manage your child's iPhone or iPad — Apple Support](https://support.apple.com/en-us/105121)
- [GKLocalPlayer.isUnderage — Apple Developer Documentation](https://developer.apple.com/documentation/gamekit/gklocalplayer/isunderage)
- [GKLocalPlayer.isMultiplayerGamingRestricted — Apple Developer Documentation](https://developer.apple.com/documentation/gamekit/gklocalplayer/ismultiplayergamingrestricted)
- [GKLocalPlayer.isPersonalizedCommunicationRestricted — Apple Developer Documentation](https://developer.apple.com/documentation/gamekit/gklocalplayer/ispersonalizedcommunicationrestricted)
- [Authenticating a player — GameKit, Apple Developer Documentation](https://developer.apple.com/documentation/gamekit/authenticating-a-player)
- [Family Privacy Disclosure for Children — Apple Legal](https://www.apple.com/legal/privacy/en-ww/parent-disclosure/)
- [Change App Store, Media, Web & Games settings in Screen Time on Mac — Apple Support](https://support.apple.com/guide/mac-help/mchlbcf0dfe2/mac)
- [isMultiplayerGamingRestricted not covering all scenarios — Apple Developer Forums](https://developer.apple.com/forums/thread/748537)
- [My child's iPad will not allow her to play multiplayer games (Wonderbox) — Apple Support Communities](https://discussions.apple.com/thread/252625807)
- [Crossy Castle, Kids Account, Game Center — Apple Support Communities](https://discussions.apple.com/thread/251157295)
- [P2P Bluetooth not working in iOS 11 — Apple Developer Forums](https://developer.apple.com/forums/thread/88104)
- [Advances in Networking, Part 2 — WWDC19 Session 713](https://developer.apple.com/videos/play/wwdc2019/713/)
