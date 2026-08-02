# Elevator Incremental — Design Spec

**Date:** 2026-08-01 (revised 2026-08-02, rounds 2 and 3 of multi-model review)
**Engine:** Godot 4.7 stable, GDScript
**Status:** Design approved. Implementation plan is the next artifact (§14).

## 1. Premise

You run a vertical building, dragging people up and down. You slowly buy your way
out of dragging, then demolish everything and start again bigger, until the
building leaves the atmosphere.

The game is an incremental with a tycoon economy and a visible simulation. Rent
is the soft currency, Blueprints are the prestige currency, and the thing being
optimised is passenger throughput.

## 2. Core loop

A cutaway building fills the screen: rows as floors, shafts as vertical channels,
elevator cars as boxes, passengers as sprites standing on rows with a destination
bubble and a draining patience meter.

1. Passengers spawn on rows with a destination.
2. The player drags on a shaft to send its car to a row.
3. Passengers delivered before their patience expires pay a fare and raise their
   row's tenant satisfaction. Passengers who expire take the stairs, pay nothing,
   and lower satisfaction.
4. Satisfaction scales tenant rent. Rent buys shafts, cars, speed, doors, staff,
   and eventually automation.
5. Automation takes over dispatch. The player keeps tuning it.
6. When growth stalls, the player demolishes: lifetime earnings convert to
   Blueprints, spent on a permanent tech tree, and the next era begins.

### 2.1 Input model

The touch target is always the **shaft column** — full board height, at least
44 pt wide — never the car. Cars are small and moving; columns are not. Verbs are
distinguished by **gesture**, never by tap cadence, so nothing depends on
double-tap timing (which also collides with mobile Safari's zoom heuristics).

The motivating geometry: at the §3 ceiling of 40 rows in a 1280-unit viewport a
row is exactly 32 units, and `canvas_items`+`expand` at a 720x1280 base scales by
min(393/720, 852/1280) = 0.546 on an iPhone 15 — so a row is roughly **17.5 pt**, and less once the HUD
takes its share. That is 2.5–3x under Apple's ~44 pt
floor, not marginally under it. Any design requiring a tap on a car, or verb
disambiguation by tap rate, degrades exactly when rows are thinnest — which is
when surge is supposed to matter most.

**Dispatch — press and drag on a column.**
Press anywhere on a shaft column. A floor-selector rail appears along that column
with detents at each row, and a magnified row label follows the thumb, offset
above it so the finger does not occlude the choice. Drag to a row; release to
dispatch.

**The mapping is absolute: detent *i* sits at row *i*'s screen position.** Any row
is one short drag away, and the cancel gesture stays unambiguous. A *relative*
mapping — finger displacement driving detent displacement — would make a lobby-to-
top dispatch require 39 x 32 = 1,248 units of travel on a 1,280-unit board, which
is physically unreachable, and every long dispatch would run into the board edge
and trigger cancel.

**Release-in-place is surge because the drag threshold was not crossed**, not
because of where the rail was anchored. That makes the threshold load-bearing:
it must be **strictly under 16 units** (half a row), or dispatching to the row your
thumb is already on — the most common intent, "there is a passenger *there*" —
becomes unreachable. §13 owns the exact value under that constraint.

The rail highlights the car's current row on appearance, so the player can see what
a no-op would be; that is presentation, not behaviour.

**The pointer is captured on drag-start.** Horizontal position is ignored until
release. A vertical thumb drag traces an arc that routinely exceeds ±22 pt — half
of a minimum-width column — so treating "left the column horizontally" as cancel
would make the primary verb self-cancel. Cancel is a deliberate gesture: drag past
the top or bottom of the board.

**Surge — tap a column.** A press and release without crossing the drag threshold
surges that shaft's car: a temporary speed boost on a cooldown.

**Event response — tap the event's own control.** An active event (§6) draws a
distinct oversized control on the affected column and suppresses surge there while
it is up, so there is never an ambiguous tap.

The gesture classifier is a state machine over a point stream (press → threshold →
detent quantisation → release), it is pure logic with no scene-tree dependency,
and it is unit-tested like `sim/` rather than left to manual play (§9).

## 3. Scale and the era ladder

### Board constants

Two UI constants bound the board, and both are design inputs rather than
incidental limits:

- **40 rows maximum.** The board never scrolls.
- **8 shafts maximum.** At a 720-unit base width, 44 pt is 44/0.546 = 80.6 units on
  an iPhone 15, so the screen fits 720/80.6 = 8.9 columns edge-to-edge and
  realistically **6–7**
  once a row-label gutter and margins exist. Because §2.1's touch guarantee is
  stated in pt, shaft count is capped by it. Shaft purchases therefore stop at the
  cap; capacity growth past that point comes from **cars per shaft** — itself
  capped, for the same node-budget reason (§8.5) — plus speed, capacity, and door
  time, which the express-shaft and zoning mechanics (§6, §5.4) support without
  needing more columns. A test asserts shaft purchases stop at the cap.

A row always means "one stop," but what a stop *is* inflates each era. This is how
the building reaches orbit while staying readable.

### Eras

Each era is entered by demolishing. Each has its own art, tenant set, and one new
rule. The unit inflates every era without exception.

| Era | A row represents | Board at 40 rows | Unit growth | New mechanic |
| --- | --- | --- | --- | --- |
| Walk-Up | 1 floor (~3.5 m) | ~140 m | — | Baseline: dispatch, deliver |
| Highrise | 4 floors (~14 m) | ~560 m | 4x | Express shafts, sky-lobby transfers |
| Megatower | 50 floors (~175 m) | ~7 km | 12.5x | Residents generate 24h internal traffic |
| Stratosphere | 1 km | 40 km | 5.7x | Pressure and wind: speed varies with altitude |
| Orbital Tether | 80 km | 3,200 km | 80x | Climbers haul cargo, not people; power budget |

Each era starts at 6 rows and expands as the player buys floors.

**Absolute height is not monotone across the ladder, and that is accepted.** An
earlier draft claimed era N+1 always begins shorter in metres than era N ended;
that is false for two of four transitions (Highrise→Megatower begins at 1,050 m
versus 560 m; Stratosphere→Orbital begins at 480,000 m versus 40,000 m) and is
*unachievable at any playable row count* for Orbital Tether — even a 1-row board is
80 km against the 40 km it would have to beat. What resets, and what carries the felt reset, is the **board** (6 of 40
rows), cash, and per-run upgrades — not absolute metres.

Growth factors are deliberately uneven, so Blueprint thresholds are tuned per era
(§13) rather than derived from them.

**Row semantics above Walk-Up.** From Highrise onward a passenger's origin and
destination are *rows*, not floors. Traffic internal to a row is abstracted into
that row's spawn rate and never touches an elevator. This keeps the sim's stop
model identical in every era.

## 4. Progression and prestige

**Demolishing** converts lifetime earnings into Blueprints via a sublinear formula
(square-root family, exact curve tuned during balancing) and resets the building,
cash, and per-run upgrades. Blueprints and the tech tree persist forever.

**The demolish action is gated on yielding at least 1 Blueprint,** and the
confirmation shows the projected yield before committing. Without the gate a new
player can wipe a run for nothing, which would be a self-inflicted fail state.

**Blueprint tech tree**, four branches:

- **Mechanical** — car speed, capacity, door time, acceleration, cars per shaft.
- **Human** — staff slots, satisfaction gain, passenger patience.
- **Automation** — dispatch policies, offline cap, offline rate.
- **Structure** — starting rows, starting shafts (to the §3 cap), era unlocks.

Era advancement is gated behind Structure nodes, so the player chooses when to
move on rather than being pushed.

## 5. Systems

### 5.1 Traffic

A spawner creates passengers according to a time-of-day curve, giving the game
rhythm: morning up-rush from the lobby, midday churn between middle rows, evening
down-rush.

**Curves are piecewise-constant on one-simulated-minute buckets**, stored in
`data/`, one set per era. The live spawner reads `curve[floor(sim_minute)]`. This
is what makes the catch-up model's integral and the live sim's integral the *same
finite sum* over any whole number of minutes (§9), rather than two different
quadrature rules over a continuous function.

Each passenger has an origin row, a destination row, a patience timer, and a fare.
Patience is displayed as a colour ramp from green to red.

### 5.2 Movement

Cars have position, speed, capacity, door dwell time, and a stop queue. Physics is
deliberately fake — position lerps toward the next stop with simple acceleration
shaping.

Door dwell dominates trip time in the early game, which makes "faster doors" a
strong and slightly surprising first purchase.

### 5.3 Tenancy

Each row holds a tenant with a rent rate and a satisfaction value tracking recent
wait times.

- Satisfaction scales rent continuously.
- Below a threshold, a move-out countdown starts and is displayed.
- Vacant rows earn nothing and can be re-leased.

**No fail state, guaranteed by one rule:** *re-leasing is free whenever the player
holds zero tenanted rows.* Any row, including the lobby, may vacate.

One rule, not two. An earlier draft also said the lobby could never vacate, which
made the free-re-lease guard ("holds no other tenanted row") unreachable — the two
rules cancelled, and §9's recovery test became unwritable because its setup was
forbidden. A single rule makes the terminal state *all rows vacant and cash zero*
recoverable by construction, and the test writable exactly as stated.

### 5.4 Dispatch

Manual at first. Automation is not a switch — it is a policy the player tunes:

1. **Nearest car** — assigns the closest idle car.
2. **Look-ahead** — considers cars already travelling toward the call.
3. **Zoning** — cars claim row ranges.
4. **Predictive** — pre-positions cars ahead of known rush-hour patterns.

Learning to schedule well by hand teaches the player what to buy later. Dispatch
dragging stops; dispatch decisions do not.

## 6. Additional mechanics

- **Smooth-operation combo** — a delivery streak with nobody expiring holds a
  rising income multiplier that decays on a bad delivery, **with a hard cap**
  (§13). Uncapped 1%-per-delivery compounding reaches infinity at ~71,270
  consecutive deliveries, which automation makes reachable.
- **Sky lobby / transfer rows** — passengers switch cars at a transfer row,
  turning one long trip into two short ones.
- **Express shafts** — assign a shaft to a row range.
- **Staff** — one operator per car: faster doors, +1 capacity, or cheerful
  (+satisfaction per delivery). No gacha.
- **Freight contracts** — a slow high-capacity car and timed cargo jobs.
- **Events** — stuck car, brownout, VIP inspection, cat in the shaft. Each draws
  its own oversized control on the affected column (§2.1).
- **Power budget** (Stratosphere onward) — climbing costs energy, descending
  regenerates it.
- **Contracts and achievements** — paying Blueprints, rewarding playing well
  rather than only playing long.

## 7. Lifecycle, idle, and offline

### 7.1 Three states, not two

The primary target is mobile Safari, where the dominant state is neither "open"
nor "closed" but **hidden**: the player locks the phone or switches apps and the
tab is backgrounded without unloading. `requestAnimationFrame` stops there, so a
two-state design would silently pay nothing for backgrounded time — making the
most natural way to leave the game its worst-rewarded path.

| State | Trigger | Behaviour |
| --- | --- | --- |
| Active | visible | Live sim at full rate |
| Hidden | `visibilitychange` → hidden | Save immediately, quiesce (§7.2), stop ticking |
| Resumed | `visibilitychange` → visible | Run catch-up, rehydrate, resume |
| Cold start | page load | Same catch-up path as Resumed |

**Godot does not surface `visibilitychange`, and the lifecycle module must obtain
it explicitly.** Verified against Godot 4.7 web platform source: the display layer
registers only `blur`/`focus` listeners and maps window blur to
`WINDOW_EVENT_FOCUS_OUT`; nothing registers `visibilitychange` or reads
`visibilityState`. An implementer building on Godot's focus notifications gets a
Hidden state that works on desktop tab-switch and **silently misses phone lock on
iOS**, which is the exact path this section exists for. `game/lifecycle` therefore
registers a `visibilitychange` listener via `JavaScriptBridge.get_interface`
plus `create_callback` under an `OS.has_feature("web")` guard, with
`NOTIFICATION_APPLICATION_FOCUS_OUT` as the desktop fallback.

**The hidden-save runs synchronously inside the JS callback, and forces the
filesystem sync from the JS side.** Two engine facts make this mandatory rather
than stylistic. Godot's web main loop is `emscripten_set_main_loop(..., -1, ...)`
— pure `requestAnimationFrame`, with no timer fallback — and §7.1's own premise is
that rAF stops when hidden, so a flag "consumed at the top of the next
`_physics_process`" is consumed *at resume*, and a tab evicted while hidden dies
having never saved. Worse, `FileAccess.close()` only sets `idb_needs_sync`; the
actual `godot_js_os_fs_sync()` call happens in `OS_Web::main_loop_iterate()` — the
same stopped loop — so even a synchronous write is not durable without forcing the
sync explicitly from the glue.

Serialisation *reads* sim state and does not mutate it, so running it inline is
compatible with the rule below. **Only sim-state mutation — the §7.2
reconciliation — defers**, via a flag consumed at the top of the next
`_physics_process`. Nothing mutates sim state inside a JS callback.

Without this, every hidden-kill silently reverts up to 30 seconds of play
including purchases, and the sim-clock anchor *masks* it economically by
re-crediting the time — so the symptom is an untraceable "my upgrade vanished" on
the most common way to leave the game.

**There is no reliable quit event on the primary target.** A tab killed from the
app switcher fires neither `NOTIFICATION_WM_CLOSE_REQUEST` nor a dependable
`beforeunload`. Saving hangs off `visibilitychange`/focus-out plus a **30-second
timer**; save-on-quit is a desktop nicety, not a guarantee.

### 7.2 The catch-up model

**The catch-up window is anchored on the sim clock, never on the save timestamp.**

`sim_wall_time` is **a wall-clock instant in Unix-epoch seconds: the moment up to
which time has been economically credited.** It is persisted, and it advances in
exactly two places — forward by `0.05` per executed tick, and by the atomic commit
below. It is *not* a duration accumulator; an accumulator would start near zero
while `now` is ~1.7e9, so `now - sim_wall_time` would clamp to the full cap on
every cold start and force-quit-relaunch would be free money.

```
elapsed = clampf(now - sim_wall_time, 0.0, offline_cap)
```

**Clock domains.** `sim_wall_time` lives in the epoch domain. At session start the
pair `(unix_now, ticks_msec_now)` is captured; in-session `now` is derived as
`unix_at_start + (ticks_msec() - ticks_at_start)/1000`, so the monotonic clock
supplies only the *delta* and DST/NTP/manual changes cannot move an in-session
window. Cold start reads `Time.get_unix_time_from_system()` directly. A single
persisted field cannot be the subtrahend for two different epochs, which is why
the delta is reconciled into the epoch domain rather than the field being stored
in tick-space.

**Catch-up commits the watermark atomically:** applying a window sets
`sim_wall_time = now - residual` in the *same* step that credits it. Credit and
commit are one transaction, so no coalesced save can snapshot credited cash
against a stale watermark. Without this the anchor reintroduces the exact defect
it was adopted to close: catch-up executes no ticks, so under a
ticks-only rule the watermark never moves and the next boundary re-credits the
same window.

**Time beyond the cap is forfeited,** which the commit rule delivers for free:
because the watermark jumps to `now - residual` rather than to
`old + credited`, an eight-hour cap after a three-day absence credits eight hours
and discards the remaining sixty-four. Under the alternative — advancing only by
the credited amount — twenty hours would stay on the books after a capped
twenty-four-hour absence, and five one-second background cycles would harvest all
of it in about five seconds. **On a window truncated by the clamp the residual is
zeroed rather than carried**, or the discarded excess leaks back in through the
residual field.

The governing invariant, which §9.2 tests directly: over any sequence of
hide/resume cycles, total credited sim-seconds is at most real elapsed seconds,
and at most `cycles x offline_cap`.

`saved_at` is a diagnostic field, not an economic input. This single choice closes
four separate defects an earlier draft had: catch-up had no committed watermark
(so re-saving after catch-up with an old `saved_at` awarded the same hour twice);
an in-session stall had no `saved_at` at all, so §8.3's "surrender to catch-up" had
no interface; and on a platform where hidden is throttled rather than stopped
(desktop Chrome runs hidden tabs at ~1 Hz), ticks executed while hidden were
credited *and* the full hidden window was credited again — a repeatable ~25%
over-credit. Anchoring on executed sim time makes every second credited exactly
once by construction.

**In-session stalls never route through catch-up.** The per-frame accumulator is
clamped; beyond the clamp, sim time simply lags wall-clock and deliveries land
late. Routing a jank window through the earnings-bearing model would double-pay:
the analytic model credits expected fares for passengers who are still in the
discrete sim and get delivered again when ticking resumes, so income would scale
with jank and inducing stalls would be an exploit. Only the Hidden→Resumed and
cold-start boundaries use §7.2.

**Progress integrates the curve at one step per simulated minute.** Four hours is
240 steps rather than 288,000 ticks — a 1200x reduction, cheap enough to run at
load, while tracking the piecewise-constant curve of §5.1 exactly.

This replaced a draft that sampled the rate at save time and multiplied. That was
wrong in a way the traffic curve guarantees: the error ratio `r(t₀) / mean(r)` is
unbounded, so with a peak merely 2x the daily mean, saving at the rush peak and
returning four hours later paid eight hours of mean earnings — a trivial exploit
(quit at 8:55 am daily), invisible to the player.

**Steps are phase-aligned to curve buckets.** The integrator advances to the next
bucket boundary as a partial step, then whole buckets, then banks the tail as the
residual. Fixed 60-second strides from an arbitrary phase would straddle every
boundary and read only the starting bucket, misattributing `phase x (curve_end -
curve_start)` per window — up to ~4e-3 relative on a 240-minute window, which is
six orders of magnitude past §9.1's bound and would make Test A pass only if
authored at a bucket boundary, i.e. only by avoiding the case that breaks it.

**The minute index is integer arithmetic** — `ticks_executed / 1200`, never a
float accumulator. After 1200 additions of 0.05 the accumulated value differs
from 60.0 by ~1e-13, and 60.0 is exactly the bucket comparison point, so one tick
lands in the wrong bucket and costs ~8e-5 at a 10% inter-bucket step.

**`catchup_residual_seconds` is bounded to `[0, 60)` and rejected outside it,** and
the step loop is independently bounded by `(offline_cap + 60) / 60`. It is
persisted, therefore devtools-editable, shared-origin-writable, and importable —
and `offline_cap` clamps `elapsed` but not the residual, so an unvalidated
`1e18` buys ~1.7e16 coarse steps and hangs the game at load, before any UI exists
to escape it. A hostile far-*future* `sim_wall_time` is the mirror case: it makes
`now - sim_wall_time` permanently negative so catch-up never pays again. Both are
in the §9.2 hostile-input matrix.

**The sub-minute remainder is carried, never dropped or rounded up.**
`catchup_residual_seconds` persists in the save (the offline analogue of the live
fractional-tick accumulator). On resume, `total = residual + elapsed`, run
`floor(total / 60)` steps, store `total mod 60` back. Both alternatives are
broken: truncating means a player who checks another app for 45 seconds earns
nothing, forever; rounding up means press-home-and-reopen is free money, a new
exploit structurally identical to the one this model was rewritten to kill.
Carrying the residual makes 120 background cycles of 29 seconds equal one
58-minute absence, which is §9's test.

**Discrete state is reconciled as a property of catch-up, not of the Hidden
transition.** Whenever catch-up runs with `elapsed` above a threshold on the
patience scale (minutes), **every** passenger — waiting *and* in-car — is cleared
and folded into the window's statistics, and cars are parked at their current
interpolated position. Below the threshold, discrete state resumes intact and the
gap rides as sim-time lag, which the anchor credits at the next boundary.

Anchoring this to elapsed time rather than to the hide event matters three ways.
It cannot run at hide-time at all (no main-loop iteration executes while hidden,
per §7.1), and it must not run inside the JS callback under the no-inline-mutation
rule. It would miss every path that never passes through Hidden — a 30-second timer
save during active play, followed by a tab crash or an OOM reload, leaves a save
full of seconds-scale patience timers that cold-start loads into an hours-older
world. And clearing on *every* hide would punish a three-second app-switch by
wiping the board and voiding in-flight fares.

Clearing in-car passengers matters as much as waiting ones: they are roughly a
fifth of the population, they carry the same draining patience, §8.3's order
expires them with no exemption for riders, and §6's combo decays on a *single* bad
delivery — so one surviving in-car expiry defeats the whole reconciliation.

Because reconciliation keys on elapsed rather than on the transition, the Hidden
and cold-start paths are identical by construction, which is what §9.2's path-
equivalence test asserts.

**Other rules:**

- Offline rate is never the instantaneous rate at save time.
- **Offline pays `offline_efficiency x ceiling`, where `offline_efficiency`
  starts well below 1 and is raised by the Automation branch toward a stated
  maximum that is still below 1.** The analytic model computes a *throughput
  ceiling* — by definition at least what any real dispatcher achieves — so paying
  100% of it would make idling weakly better than playing for every player whose
  dispatch is below optimal, which is every player on the Nearest-car tier and
  anyone simply playing badly. An earlier draft deleted the efficiency fraction to
  keep §9's fidelity test clean; that removed the only term that can hold the
  no-exploit property, so it is restored deliberately. Automation upgrades then
  read as "my building runs better without me," which is the fantasy anyway.
- For Hidden→Resumed the process never died, so `Time.get_ticks_msec()` is
  monotonic and available and is used; `Time.get_unix_time_from_system()` is
  reserved for cold start. This removes DST/NTP and in-session clock manipulation
  entirely from the common path.
- The model evolves tenancy state, not just cash: satisfaction decay, move-out
  countdowns, capacity as a throughput ceiling.
- Catch-up runs strictly after §8.6 step 7 (construction), on validated values — `clampf(NAN, …)`
  propagates `NAN`, and a `NAN` reaching the earnings integrator poisons every
  downstream currency.

On return, a "while you were away" summary reports cash earned, riders served, and
tenants lost.

### 7.3 Storage durability on the primary target

**Safari deletes script-writable storage — IndexedDB explicitly included — after
seven days of Safari use without user interaction with the site.** `user://` on web
*is* IndexedDB, so drifting away for a week returns the player to a deleted
building. Seven days of *browser use*, not calendar days, and it cannot be caught
by the §10.1 device pass.

**Home-screen web apps are exempt** — Safari skips that origin in its data-removal
algorithm and they keep their own use counter.

**Adding to the home screen must be a guided migration, not a prompt.** A
standalone home-screen web app is "not part of Safari," and that same separation
means it gets its **own storage container** — so a player with a week-old building
who follows an unguarded install prompt opens an *empty building* while the Safari
save keeps aging toward deletion. The mitigation would cause the loss it exists to
prevent. Therefore: export the save (clipboard plus on-screen string) *before*
prompting to install, and on first standalone launch with no save found, offer
"played in Safari? paste your save" rather than silently starting fresh. Container
isolation is verified on device as part of §10.1.

**Other adopted mitigations:** enable the PWA export and manifest (with the icon
fields populated — they are currently empty); treat "no save found" as a normal,
tested startup path.

**`progressive_web_app/ensure_cross_origin_isolation_headers` stays `false`.** It
is the natural thing to flip during PWA setup, and turning it on makes the
generated service worker inject COOP/COEP — cross-origin-isolating a build that
deliberately does not need it and blocking non-CORS subresources for no benefit.

**The service worker makes version skew routine.** Installed players run the
previous build for at least one launch after each deploy, so an old client meeting
a newer-schema save (§8.6's refusal path) is an ordinary post-deploy event rather
than a rare rollback. §8.6 handles it without data loss; a version-skew launch
belongs in the test matrix.

**Save export/import envelope.** The import string is the first thing in the design
that accepts a document *another person* authored, so the envelope is pinned:

- Export is `Marshalls.utf8_to_base64(JSON.stringify(state))`; import is
  `base64_to_utf8()` then `JSON.parse_string()`. **`Marshalls.variant_to_base64`,
  `Marshalls.base64_to_variant`, `var_to_bytes` and `bytes_to_var` are forbidden on
  both sides** — named explicitly because a ban list is what gets grepped, and
  because the compact-looking export encoding is exactly what pulls an implementer
  toward the import call §8.6 bans.
- A hard byte cap enforced *before* base64-decode, and a decoded-size cap before
  parse. Over-length input is the real exhaustion risk. **Excess nesting depth is
  not** — verified on 4.7.stable, depths of 1,500 / 5,000 / 100,000 all return
  `null` cleanly from a parser depth guard rather than overflowing the stack, so
  step 2's null-rejection already covers it. Do not build a pre-parse depth scanner
  on the assumption of a crash. A cheap container-count pre-scan is still worth
  having, since a legitimate save for this schema has a small bounded count.
- A malformed base64 paste is safe: `base64_to_utf8` on non-base64 input returns an
  empty string with a logged error and does not crash, so it degrades into a step-2
  rejection.
- Import backs up the existing save, requires explicit confirmation (it is a total
  irreversible replacement), and is single-flight against the §8.6 save mutex.

**Shared-origin exposure.** The game shares `seanperkins.github.io` with every
other Pages site on the account, and IndexedDB is keyed by origin, not path. The
sharper exposure is code rather than data: a service worker served from the root of
the *user-page* repo claims scope `/` and could intercept and substitute this
game's `index.js` and `index.wasm`. Accepted for a single-player game with no PII
(§12); a custom domain is the fix if that changes. A `<meta http-equiv=
"Content-Security-Policy">` via `html/head_include` is worth adding as defence in
depth (`img-src 'self' data:; connect-src 'self'` neutralises the §8.4 beacon at
platform level), but it needs a wasm-compatible `script-src` and must be validated
on device.

## 8. Architecture

### 8.1 The one rule

**The simulation knows nothing about the scene tree.** All game logic lives in
plain `RefCounted` classes under `sim/` — no nodes, no `get_node`, no rendering.

This buys two things: the sim is unit-testable headlessly, and the view can be
rewritten per era without touching game rules. It does *not* buy "offline is the
same code run differently" — catch-up is a separate coarse-step integrator over the
same curve data, validated against the live sim per §9.

### 8.2 Layout

```
res://
  sim/     game_state, building, elevator, passenger, traffic_spawner,
           tenancy, dispatcher, economy (cash, fares, combo), prestige,
           catch_up, gesture (input classifier)
  data/    eras, upgrades, tenants, traffic curves
  game/    game_root (owns sim, pumps ticks), save_manager, save_codec
           (export/import), lifecycle (visibility/focus), util/number_format
  view/    building_view, shaft_column, elevator_car, passenger_sprite,
           floor_row, floor_selector
  ui/      hud, upgrade_panel, prestige_panel, event_toast, a2hs_prompt
  tests/   GUT specs against sim/ and game/save_codec
```

`gesture` and `catch_up` live under `sim/` deliberately: both are pure logic with
named boundary conditions and both are unit-tested.

### 8.3 Tick model

**Physics stays at Godot's default 60 Hz; `game_root` runs a fixed-step
accumulator advancing the sim in 0.05-second steps (20/s).** `project.godot` has no
`[physics]` section, so `_physics_process` fires 60x/s by default and one tick per
callback would run the sim at 3x speed with every rate constant mistuned.
Accumulating preserves render smoothness instead of dropping the whole game to
20 Hz.

The accumulator is clamped per frame. Beyond the clamp, **sim time lags wall-clock
and nothing is surrendered to the catch-up model** (§7.2). `sim_wall_time` is the
single authority for how much time has been economically credited.

**Intra-tick order is fixed and written down**, because determinism is meaningless
without it:

```
spawn → move/doors → deliver → expire → accrue rent → update combo
```

Deliver precedes expire, so a passenger reaching exactly 0.0 patience on the tick
its doors open is **delivered**, pays, and extends the combo. A passenger spawned
on tick T first decays on tick T+1. Both boundaries are pinned by test.

**Determinism is a hard requirement**, with a seeded RNG for spawns.

### 8.4 Communication

Sim to view: **signals only**. View to sim: **explicit commands**
(`sim.dispatch(shaft, row)`). One-directional data flow.

**BBCode labels take only author-written literal markup.** Any dynamic text —
tenant names, welcome-back summaries, event toasts, anything influenced by save
content — goes through a plain `Label`, or through `bbcode_enabled = false`, or is
escaped with `s.replace("[", "[lb]")` before concatenation. Godot exposes no
`escape_bbcode()` helper, and assigning `.text` parses markup exactly as
`append_text()` does, so `bbcode_enabled = false` is the only unconditional off
switch. `[img]` fires a network request; `[url=]` is inert only as long as nothing
passes a `meta_clicked` payload to `OS.shell_open()`.

### 8.5 Designed-around risks

**Node count.** Sprites come from a pool; each row renders at most 12 individuals
before collapsing into a crowd bar. Counting *nodes* rather than passengers, since
§2 gives each passenger a body, a destination bubble, and a patience meter:

| component | nodes |
| --- | --- |
| passengers (40 rows x 12 x 3) | 1,440 |
| crowd bars (40 x 2) | 80 |
| tenant widgets (40 x 3) | 120 |
| cars (8 shafts x 2 cars x 2) | 32 |
| **subtotal** | **~1,672** |

Add the 40 `floor_row` and 8 `shaft_column` containers, the HUD and panels, and
passengers rendered inside cars, and the real ceiling is ~1,850. That is thousands,
not hundreds — roughly 2.8x an earlier estimate that assumed one node per passenger, and past the threshold where Control-node layout cost on GL
Compatibility in mobile Safari stops being free. The per-row cap is therefore a
**tunable constant with a global node ceiling above it**, and ~1,850 nodes is
measured on the target iPhone before Milestone 3. The car term is bounded because
§3 caps both shafts and cars per shaft.

**Big numbers.** GDScript floats reach ~1e308, ample *provided nothing compounds
without a cap* — hence §6's combo cap and §13's per-era peak-magnitude estimates.
Once any currency is `INF`, every comparison and the prestige square root degrade
silently.

**Number formatting.** The suffix ladder needs 98 two-letter entries to cover the
float range, so it is generated, not hand-written. Magnitude selection happens
*after* rounding, or 999,950 formats as "1000.0K" instead of "1.0M". Never compare
currency with `==`.

### 8.6 Persistence

Versioned JSON in `user://`, written on a 30-second timer, on visibility-hidden,
and on focus-out.

**Load sequence.** ("Version checked before parse" was not implementable — a
version inside the document cannot be read before parsing it.)

1. Reject before reading if the input exceeds `SAVE_MAX_BYTES` (1 MiB is generous
   for this schema). Missing file is a normal path, not an error.
2. `JSON.parse_string`. A `null` return or non-Dictionary root is a rejection.
3. Read and check `version` before interpreting any other field. **Godot's JSON
   parser returns every number as `TYPE_FLOAT`** — verified on 4.7.stable,
   `JSON.parse_string('{"version": 1}')` yields a float, and `1` and `1.0` are
   indistinguishable after parse. The gate is therefore *`TYPE_FLOAT` and integral
   (`v == floor(v)`) and within `[migration_floor, current]`*. A `TYPE_INT` check
   would refuse every save the game itself wrote and latch `writes_disabled` on
   first launch — bricking persistence while §9.2's "non-integer version refuses"
   test still passed. A version above the newest known, below the migration floor,
   absent, or non-integral routes through refuse-and-backup.
4. **Structural and version-specific validation only**: types, collection sizes,
   nesting. Not current-schema semantics — validating string ids against today's
   `data/` before migration would reject a legitimate v1 save whose ids migration
   exists to rename.
5. Migrate through the version chain.
6. **Current-schema validation**: every field type-checked *before* value-checked,
   every id against the known set, every count in its era's legal range.
7. Construct from an **explicit key allowlist**. Never iterate a parsed dictionary
   into `Object.set()` — mass-assignment lets a save reach properties that were
   never part of the schema.

**Type-check before value-check, always.** `is_finite()` is a float operation, and
`JSON.parse_string` can deliver a `String`, `Array`, `Dictionary`, `bool`, or
`null` for any field. `is_finite(d["cash"])` on `{"cash": {}}` raises *during
validation* — which is before construction, so the refusal path never engages and
the backup is never written. The protection dies before it runs. `is_finite()` is
still the right check and must stay: JSON has no `Infinity` literal, but `1e400` is
syntactically valid JSON and Godot's parser yields `INF` for it.

**Reject, do not clamp, on the untrusted paths.** Silently clamping `shafts: 99999`
turns a hostile document into a legal accepted save. Clamping belongs inside a
migration step (and is logged there); an import, or any save whose version equals
current, is rejected on out-of-range.

**Bound every collection before iterating it.** `{"passengers": [5,000,000 …]}`
passes every value-level check and OOMs the wasm heap on the platform §10 already
calls memory-constrained. Traverse by explicit known-key descent so unexpected
depth is structurally unreachable.

**A refused load sets a single `writes_disabled` latch for the session.** *Every*
write path checks it — timer, visibility-hidden, focus-out, quit, manual save.
Scoping the disable to "autosave" would be defeated within seconds: the first thing
a player does when a blocking error appears is switch apps to look it up, firing
the immediate hidden-save. **The backup write happens before the latch is set and
is exempt from it**, or the backup the recovery path depends on is never written.

Only an explicit user action clears the latch, and the choices offered depend on
*why* the load was refused:

- **Version above the newest known** — the routine post-deploy service-worker skew
  case (§7.3). This is a perfectly good save that a reload will read, so the
  message is "the game has updated; reload to continue," ideally triggering the
  service-worker update. Discard is **not** offered here. Offering destruction as
  the only actionable button during an ordinary deploy would let a confused player
  delete a healthy building.
- **Genuinely unmigratable** — discard-and-start-fresh is offered.

**The blocking message offers the backup as an export string, not a filename.** On
web the backup lives in IndexedDB, so naming a path a player can neither browse nor
retrieve is not an affordance; the §7.3 codec already exists, so the recovery path
has something to consume. Import remains available while the latch is set, since it
*is* the recovery path, and a successful validated import clears the latch and any
pending dirty flag — otherwise a deferred coalesced snapshot would serialise
pre-import state over the save the player just recovered.

**Writes are atomic and coalescing.** Serialise to a temp file, flush, close,
validate, then replace. A save requested while one is in flight sets a dirty flag
and runs **one** coalesced snapshot afterwards — it is never dropped. Blocking it
would discard the most important save in the design: timer save starts, player buys
an upgrade, player backgrounds Safari, the hidden-save is discarded, and killing
the tab restores pre-purchase state.

**On web, `FileAccess.close()` does not mean durable** — `user://` is memory-backed
and synced to IndexedDB asynchronously. A write may not survive an immediate kill;
the timer plus save-on-hide is the mitigation.

**The save schema includes sim continuation state** — RNG state, tick counter,
fractional-tick accumulator, `catchup_residual_seconds`, and `sim_wall_time`.

**The save is untrusted input** — editable from Safari devtools, writable by any
other site on the shared origin, and (via import) authored by another person:

- **JSON only.** Never `str_to_var()` or `bytes_to_var(…, true)` — Godot's Variant
  parser can construct an `Object`, and an object with its `script` property set is
  arbitrary code execution.
- **Never `load()` or `ResourceLoader.load()` on a `user://` path**, or any path
  derived from save content. `.tres`/`.res` can embed GDScript.
- **Validate then construct**, per the sequence above.

### 8.7 Balance as data

Upgrade definitions, tenant types, traffic curves, and era configuration live in
`data/`, so tuning does not require code changes.

**Resources are `res://`-only and compile-time.** Anything read from `user://` or
the network is JSON through the §8.6 gate. **`data/` holds numeric coefficients
over a fixed set of code-defined curve shapes — never expression strings**, since
running stored formulas through `Expression` is an eval.

## 9. Testing strategy

- **Sim** (`sim/`) — heavily unit tested with GUT. Deterministic, headless.
- **Saves and the save codec** — round-trip, migration per version bump, and the
  hostile-input matrix below.
- **View and UI** — thin by construction; smoke tests and manual play.

Assertions use exact equality on integer counts and a relative epsilon on floats,
because float accumulation can differ in the last bits between the CI Linux build
and the wasm build in Safari.

### 9.1 The catch-up model is validated by two separate tests

An earlier draft asserted that coarse-stepped and lived windows agree to 1e-9. That
is unachievable and would have failed permanently at Milestone 6, after which the
tolerance would have been loosened until meaningless. Two independent reasons: the
two paths use step sizes 1200x apart, so they are different quadrature rules
(midpoint error for even a pure daily sinusoid is ~7.9e-7, and ~1.8e-3 for a
half-hour rush ramp); and the live sim is stochastic, with a realised-count spread
of `1/sqrt(N)` — still 3.2e-4 at ten million passengers. Live earnings also depend
on dispatch, capacity, and door dwell, while catch-up uses a throughput ceiling:
these are different quantities, so float-epsilon agreement is a category error.

**Test A — integrator exactness (1e-9 relative).** Because §5.1's curves are
piecewise-constant on one-minute buckets and the live spawner reads
`curve[floor(sim_minute)]`, the *integrated rate* over any whole number of minutes
is the same finite sum in both paths. Assert that at 1e-9, and assert
self-consistency across step sizes (1-minute versus 1-second steps of the same
integrator). This is a legitimate float bound and a real regression guard — on
expected spawn count and integrated rate, not on realised earnings.

**Test B — the no-exploit property.** Over a named matrix of dispatch policy tiers
and upgrade states, and for every `t₀` phase in the day cycle,
`catch-up / lived <= 1.0`. **Active play must never be worse than idling, for any
player state.** This is the property the round-1 exploit finding was really about,
and it is checkable because §7.2's `offline_efficiency` sits below the ceiling by
construction.

An earlier draft asked instead for ±5% agreement with "the mean of N seeded live
runs." That was unwritable: it named no dispatch policy or upgrade state for the
runs, and it compared a throughput *ceiling* against realised dispatch, so the
ratio was structurally above 1 and grew as the player's dispatch got worse.

### 9.2 Named tests

Before Milestone 1 ships:

1. Intra-tick ordering: exact-zero patience both directions; tick-T spawn decays
   on T+1.
2. Gesture classifier: drag threshold, release-in-place is surge, dispatch to the
   pressed row, rail anchored at the car's row, horizontal arc does not cancel,
   cancel past the board edge.
3. Number formatter: 0, under 1000, exactly 1000, the 999,950 boundary, the top of
   the suffix ladder, `INF`/`NAN`.
4. No-fail recovery: drive every tenant out at zero cash; assert recovery reachable.
5. Blueprint conversion at `E = 0` and at the first `BP = 1` threshold.
6. Combo rise, decay on a bad delivery, and the cap.
7. Tenant satisfaction exactly at the move-out threshold, both directions.
8. Dispatch policies: fixed-scenario tests asserting which car each policy assigns.

Before Milestone 6 ships:

9. Catch-up boundaries: `elapsed <= 0`, exactly at the cap, far beyond the cap.
    Then the conservation invariant across *successive* resumes: two resumes after
    a 24 h absence with a 4 h cap credit 4 h total, not 8 h — total credited
    sim-seconds never exceed real elapsed seconds.
10. Residual conservation: 120 resumes of 29 s equals one 58-minute absence.
11. Path equivalence: hidden-for-N-then-resumed equals cold-start-after-N, for N
    of 0, sub-minute, at the cap, and beyond.
12. Resume reconciliation: no mass-expiry event in the first live ticks after a
    multi-hour resume.
13. Refused-load: unknown future version, version below the migration floor,
    absent version, non-integer version — each refuses, latches `writes_disabled`
    across *every* write path, and writes a backup.
14. Hostile-input matrix: wrong type per schema field, `1e400`, negative counts,
    counts above the era's range, unknown string ids, oversized input,
    over-length import string, non-base64 import string, `NAN` or a far-future value
    in `sim_wall_time`, and `catchup_residual_seconds` outside `[0, 60)`.
15. Atomic write: inject a failure between temp-write and replace; assert the live
    save is byte-identical to before.
17. A freshly-written save loads — the positive case that would have caught a
    `TYPE_INT` version gate refusing every save the game wrote.
18. Shaft and cars-per-shaft purchases stop at the §3 caps.
16. "No save found" is a normal startup path.

## 10. Delivery

Web export is the primary target; desktop is incidental.

**Hosting.** Public GitHub repo, built by GitHub Actions on every push to `main`,
published to Pages at <https://seanperkins.github.io/elevator-game-godot/>.

**Threadless export, deliberately.** Pages cannot set custom HTTP headers and
Godot's threaded web export requires COOP/COEP, so `variant/thread_support=false`
selects the `web_nothreads_release` template.

**Orientation.** Portrait, 720x1280 base, `canvas_items` stretch with `expand`.

**Renderer.** GL Compatibility (WebGL 2). Forward+ on web depends on WebGPU and is
not a safe bet in mobile Safari.

**VRAM texture compression off.** Enabling it for mobile requires "Import ETC2
ASTC"; without it Godot 4.7 fails the export with a config error whose message body
is empty.

**Payload.** `index.wasm` is 39,509,339 bytes raw and 10,052,184 at `gzip -9`.
Pages fronts with Fastly at a default compression level, not `-9`, so the served
figure is ~10.11 MB and the full first-load transfer is **~10.2 MB**. Acceptable
over LTE, not merely wifi. The sharper iOS risk is mobile Safari's per-tab memory
ceiling during wasm compilation plus game heap (§10.1).

### 10.1 Milestone 0 — pipeline check (REOPENED)

**The probe does not test persistence.** `_test_persistence()` opens the save with
`FileAccess.WRITE` and overwrites it *before* reading it back, and is called from
`_ready()`. On Godot web, `user://` is memory-backed and synced to IndexedDB
asynchronously, so a same-session write-then-read is served from memory. The probe
reports `ok` in exactly the failure modes it exists to catch: private browsing,
storage denied, quota refusal, or the sync silently failing. The claim
"round-trips a save through `user://`" is not supported by that evidence.

**Fix, structurally rather than by convention.** `restored` is computed **exactly
once, in `_ready()`, before any write in that session, and is immutable
thereafter**. Split the function: the tap path writes only, never re-reads, never
touches `restored`. Respecifying `_ready()` alone is insufficient because
`_test_persistence()` is also called from `_on_tap()` — if the rewritten function
recomputes `restored`, the first tap reads after a same-session write, `restored`
flips to yes, and the false positive returns. "Confirm by reloading, not by
tapping" is operator discipline, not a property of the probe, and the milestone was
reopened precisely because a probe whose evidence looks fine in the failure case is
worthless.

**The probe's readout sets `bbcode_enabled = false`.** It currently uses a
`RichTextLabel` with bbcode on, §11 keeps the scene permanently, and §10.1 asks it
to display a value read from a file that any other site on the shared origin can
write — so a planted `[img]https://…[/img]` becomes an outbound beacon from a
shipped scene. The readout uses no markup. The restored value is rendered as an
integer the probe parsed and range-checked, never as the raw string.

**Exit criteria, all on the actual iPhone:**

- Boots, renders, holds frame rate.
- Touch registers, including a **full-height drag along a column that does not
  cancel** (validates §2.1's pointer-capture rule).
- `restored: yes` after a page reload.
- `restored: yes` after a Safari force-quit and relaunch.
- Background/foreground cycle logs a sane wall-clock delta — exercised via **phone
  lock**, not just app-switch, since that is the path `blur` may not cover.
- A2HS container check: create a save in Safari, install to home screen, and
  record whether the save appears (validates §7.3's migration requirement).
- Memory: no tab reload during wasm compilation.

Desktop Chrome verification stands as evidence for the *pipeline*, not the
platform.

### 10.2 CI hardening

Required before Milestone 1. Exact shell logic belongs in the implementation plan
(§14); these are the commitments.

- **A `test` job running GUT headless, which `build` depends on.** §9 calls the sim
  suite where correctness lives and nothing runs it. The highest-consequence bug
  class is a migration corrupting saves, and it currently ships behind three
  `test -f` checks.
- **Pin the toolchain.** The Godot binary and export templates download over HTTPS
  with no integrity check from a *mutable* release-asset URL (`GODOT_VERSION:
  "4.7"`), then are `sudo mv`'d to `/usr/local/bin` and executed with deploy
  privileges. Pin to the exact patch release, verify both by SHA-256, fail on
  mismatch. **Vendor GUT at a commit SHA**, not a tag — it is `EditorPlugin` code
  executing inside the job, which is the whole reason to care, so it gets the same
  standard as everything else.
- **Pin *all* actions to commit SHAs, including `actions/*`.** Tag mutability is a
  property of git, not of the publisher; all four actions in the workflow are
  first-party, so a rule saying "third-party" would pin nothing.
- **Scope permissions per job**, with an explicit workflow-level floor of
  `contents: read`. Note that `actions/configure-pages` currently runs in `build`
  and reads the Pages configuration, so stripping `build` to `contents: read` alone
  breaks it — either grant `pages: read` or, cleaner, move `configure-pages` into
  `deploy` so `build` needs nothing more than `contents: read`.
- **Make the threadless guard a real gate.** The current step greps built JS for
  `SharedArrayBuffer` and prints "none (good: threadless)", but Godot's engine JS
  ships that feature-detection regardless of `thread_support` (9 occurrences in the
  current threadless build), so the branch is unreachable and the step has no
  `exit 1`. Assert the input: `grep -qx 'variant/thread_support=false'
  export_presets.cfg || exit 1` (verified to match — it is at column 0). Pair it
  with an output-side assertion once a threaded build confirms a discriminator, and
  scope the input check to the Web preset if a second preset is ever added.
- **Stop discarding import failures.** `godot --headless --import || true`
  converts every failure to success. Run `--import` **twice and require the second
  to exit 0** — the clean-checkout condition is first-run-only by definition, so
  the second run's status is a genuine signal that needs no documented exit code.
  This is an empirical claim and must be confirmed locally before it becomes a hard
  gate, or the first push turns CI red.
- **Gate `exclude_filter`, don't just set it.** `exclude_filter="tests/*,addons/
  gut/*"` without an assertion repeats the exact shape of the unreachable control
  it replaces — a typo'd glob silently ships the suite again. The `.pck` path table
  is greppable: assert `! grep -qa 'res://tests/' build/web/index.pck` and the same
  for `res://addons/gut/`.
- **`actions/checkout` sets `persist-credentials: false`.** The same threat model
  that pins GUT to a SHA — `EditorPlugin` code executing inside the job — says that
  code can read the `GITHUB_TOKEN` checkout otherwise leaves in `.git/config`.
- **Add `export_credentials.cfg` to `.gitignore`.** Godot writes keystore and
  notarisation secrets there; it is currently unignored, and a later signing preset
  would drop credentials into a public repo on `git add -A`.

## 11. Build order

Milestone 0's reopened criteria (§10.1) and CI hardening (§10.2) land before
Milestone 1.

1. **Vertical slice** — one shaft, one car, 6 rows, drag-dispatch, fares.
2. **Tycoon layer** — tenants, satisfaction, rent, move-outs, patience.
3. **Economy and upgrades** — shafts (to the cap), cars, speed, doors.
4. **Automation** — the dispatcher and its tunable policies.
5. **Prestige** — demolish, Blueprints, tech tree, era 2.
6. **Save and offline** — persistence, lifecycle, catch-up, welcome-back, A2HS
   migration, export/import.
7. **Content and feel** — remaining eras, events, staff, contracts, juice.

The probe scene is retained as a debug scene after Milestone 1 repoints
`run/main_scene`.

## 12. Decisions taken

- Tycoon economy over pure clicker or pure dispatch puzzle.
- Prestige resets the board (6 of 40 rows), not absolute height, which is not
  monotone across the ladder.
- Blueprints plus themed eras.
- Soft pressure: tenants leave, runs never fail — guaranteed by §5.3's single rule.
- Offline progress on, capped, curve-integrating, anchored on the sim clock.
- Drag-on-column as the primary verb, tap as surge; targets are columns, never
  cars; shaft count capped by the 44 pt guarantee.
- Determinism is hard, including written intra-tick ordering and continuation state
  in the save.
- Shared `github.io` origin accepted: single-player, no PII, game state only.
- **Clock manipulation accepted.** A player who moves the device clock forward
  harvests one `offline_cap` per cycle. Unfixable without a server, and self-harm
  in a single-player game.

## 13. Open items

Owned, not blocking:

- Blueprint conversion curve and per-era thresholds.
- Fare, rent, and upgrade cost curves.
- Patience durations per era and tenant tier.
- Traffic curve shapes per era (piecewise-constant, one-minute buckets).
- Surge magnitude and cooldown; drag threshold and detent feel.
- Combo hard cap, and expected peak magnitude per era so §8.5's float-headroom
  claim is checkable.
- **Orbital Tether's economic model.** Cargo climbers have no tenants, so tenancy,
  satisfaction, patience, the stairs fallback, **and §5.3's no-fail guarantee** —
  five systems — need era-5 substitutes. The no-fail rule is a tenancy rule and is
  vacuous where there are no tenants.

## 14. Deferred to the implementation plan

This document specifies design and constraints. The implementation plan is the next
artifact and owes what this one deliberately does not carry: file-by-file changes,
class APIs and method signatures, error-return contracts, the exact CI shell logic
for each §10.2 commitment, the save schema field list with per-field types and
ranges, and per-milestone task sequencing.
