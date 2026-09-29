# Crazy Train — Item Roadmap

Design of the purchase-item expansion: what each item does, how it hooks
into the engine, and which missions it powers. Update this file as items
ship or rules change.

Status legend: 🟢 shipped · 🟡 in progress · ⚪ planned

## Design rules

- **Motion items become path facts.** Anything that changes how a train
  moves should be observable on the traced path (a cell set, a `PathStep`
  flag, or a per-game counter) — that's what makes missions about it
  nearly free, following the tunnel-mission pattern.
- **Preview never lies.** Every item validates placement with the same
  function that drives its hover tint.
- **No budget missions.** Goals reward doing things, never *not spending*.
- **No music.** New audio is diegetic only.

## The headliners

### Speed pad — $150 · 🟢
A booster strip placed on straight track (tap to place, tap to remove,
half refund on bulldoze). Crossing one gives the train a **2-second
burst of double speed** (game-time; pausing doesn't tick it).
- *Engine:* `Set<Cell> speedPads`; per-train transient `boost` seconds,
  set on cell entry, consumed in `_advance`. Not saved (transient).
- *Feeds:* the loop-de-loop's speed requirement; lap-time missions.

### Lap timer — 🟢 (system, not an item)
Per-train clock in **sim-seconds** (`dt × speed`, so 2× playback doesn't
cheat the mission — it measures track quality, not patience). On lap
completion, `bestLapTime` records the minimum; persisted.
- *Missions:* "Complete a lap in under N seconds."

### Loop-de-loop — $450 · 🟢
A vertical 360° hoop on a **flat straight** track cell. Trains need
momentum: entering **without an active speed boost stalls the train**
short of the loop (status chip explains; a speed pad run-up fixes it).
Riding through lifts the train around the circle.
- *Engine:* `Set<Cell> loops`; stall = hold like a signal; counter
  `loopsRidden` increments per engine pass-through (persisted).
- *Missions:* "Ride a loop-de-loop" · "Loop N times" · pairs with pads.

### Jump ramp — $250 · 🟢
A one-ended launcher: place the ramp on an empty cell, pick its firing
direction; a train entering the ramp flies **3 cells** in that direction
and must land on track aligned to catch it (validated at placement and
at trace time). Jumps clear water, chasms, and other lines — no partner
pad needed.
- *Engine:* `Map<Cell, Dir> ramps`; traceLoop emits a flight step from
  ramp to landing track; counter `jumpsMade` (persisted).
- *Missions:* "Jump the gorge" · "Land N jumps in one lap."

### Turntable — $500 · 🟢
A rotating platform placed at a line's end: the train rolls on, spins,
and heads back out the way it came. Legalizes **out-and-back lines** —
the first alternative to closed loops.
- *Engine:* `Set<Cell> turntables`; traceLoop reverses through the cell
  (entry == exit edge, in-and-out parametrization); path check =
  turntable cell on route.
- *Missions:* "Run an out-and-back line" · "Serve a dead-end depot."

## The supporting cast

### Dynamite — $100 per blast · 🟢
One tap craters a 2×2 area to below the water line (respecting vertex
locks under structures). The fun version of the lower-land tool.
- *Engine:* consumable tool; reuses terraform cascade with a preset
  target; counter `blastsFired` (persisted).
- *Missions:* "Blast a lake and bridge it."

### Cow catcher — $200 fleet upgrade · 🟢
Fleet upgrade (one purchase covers every train): cows on the line are
shoved aside without stopping, each paying a **$5 moo toll**. Converts
the hazard into a trickle economy.
- *Engine:* world-scoped flag (persisted); `_advance` cow check
  relocates instead of blocking; counter `cowsPlowed` (persisted).
- *Missions:* "Plow through 10 cows."

### Grand Terminal — $1,000 upgrade · 🟢
Upgrades the home station once per world: the lap-formula payout is
**doubled**. The late-game money sink.
- *Engine:* `bool grandTerminal` (persisted); payout formula ×2; station
  renders grander.
- *Missions:* keeps earnings targets ("$1,500 in one lap") viable late.

## Mission mapping — shipped

| Level (stop) | Stars |
|---|---|
| Switchback Pass (●●●) · 🟢 | Run a line off a turntable · lap under 16s on 45+ track (lastLapSteps/lastLapTime) · 10 crash-free dual-train laps (dualLaps, reset on crash) |
| Terraformer's Folly (●●●) · 🟢 | 4 dynamite blasts · ride a loop-de-loop 5× · land 15 ramp jumps |
| Possible 7th stop — "Thrill Line" · ⚪ | Pure showcase: chain loops, multi-jump lap, best-lap leaderboard vs. your own record (route map would need a 7th station) |

Existing levels stay untouched; all items are available in the sandbox
and every scenario once shipped.

## Explicitly rejected

- Budget/spending-cap missions (feel bad; punish experimentation).
- Recreating copyrighted music for any item or screen.
