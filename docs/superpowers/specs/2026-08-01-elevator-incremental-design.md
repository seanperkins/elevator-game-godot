# Elevator Incremental — Design Spec

**Date:** 2026-08-01
**Engine:** Godot 4.7 stable, GDScript
**Status:** Approved design, pending implementation plan

## 1. Premise

You run a vertical building, clicking to move people up and down. You slowly buy
your way out of clicking, then demolish everything and start again bigger, until
the building leaves the atmosphere.

The game is an incremental with a tycoon economy and a visible simulation. Rent
is the soft currency, Blueprints are the prestige currency, and the thing being
optimised is passenger throughput.

## 2. Core loop

A cutaway building fills the screen: floors as rows, shafts as vertical channels,
elevator cars as boxes, passengers as sprites standing on floors with a
destination bubble and a draining patience meter.

1. Passengers spawn on floors with a destination.
2. The player clicks a car, then a floor, to dispatch it.
3. Passengers delivered before their patience expires pay a fare and raise their
   floor's tenant satisfaction. Passengers who expire take the stairs, pay
   nothing, and lower satisfaction.
4. Satisfaction scales tenant rent. Rent buys shafts, cars, speed, doors, staff,
   and eventually automation.
5. Automation takes over dispatch. The player keeps tuning it.
6. When growth stalls, the player demolishes: lifetime earnings convert to
   Blueprints, spent on a permanent tech tree, and the next era begins.

### Click verbs

Three verbs, none of which expire:

- **Dispatch** — click a car, then a floor. Primary verb until automation.
- **Surge** — rapid-click a moving car for a temporary speed boost, on a
  cooldown so it cannot be spammed. Relevant in every era.
- **Event response** — clickable interruptions (see §6).

## 3. Scale and the era ladder

### The 40-row board

The board shows approximately 40 rows and never scrolls. This is a UI constant,
not a height cap. A row always means "one stop," but what a stop *is* inflates
each era. This is how the building reaches orbit while staying readable.

### Eras

Each era is entered by demolishing. Each has its own art, tenant set, and one
new rule.

| Era | A row represents | New mechanic |
| --- | --- | --- |
| Walk-Up | one floor | Baseline: call, dispatch, deliver |
| Highrise | one floor | Express shafts, sky-lobby transfers |
| Megatower | a district (~50 floors) | Residents generate 24h internal traffic |
| Stratosphere | a kilometre | Pressure and wind: speed varies with altitude |
| Orbital Tether | ~80 km | Climbers haul cargo, not people; power budget |

Board height per era grows within the ~40-row ceiling — early Walk-Up starts at
6 rows and expands as the player buys floors.

## 4. Progression and prestige

**Demolishing** converts lifetime earnings into Blueprints via a sublinear
formula (square-root family, exact curve to be tuned during balancing) and
resets the building, cash, and per-run upgrades. Blueprints and the tech tree
persist forever.

**Blueprint tech tree**, four branches:

- **Mechanical** — car speed, capacity, door time, acceleration.
- **Human** — staff slots, satisfaction gain, passenger patience.
- **Automation** — dispatch policies, offline cap, offline rate.
- **Structure** — starting floors, starting shafts, era unlocks.

Era advancement is gated behind Structure nodes, so the player chooses when to
move on rather than being pushed.

## 5. Systems

Four systems, each independently understandable and testable.

### 5.1 Traffic

A spawner creates passengers according to a time-of-day curve, giving the game
rhythm: morning up-rush from the lobby, midday churn between middle floors,
evening down-rush. Curves are data, one set per era.

Each passenger has an origin floor, a destination floor, a patience timer, and a
fare. Patience is displayed as a colour ramp from green to red.

Rush hours make upgrades legible: a building that coped yesterday drowns today,
so the player buys a shaft.

### 5.2 Movement

Cars have position, speed, capacity, door dwell time, and a stop queue.

Physics is deliberately fake — position lerps toward the next stop with simple
acceleration shaping. The sim must run hundreds of passengers, not be accurate.

Door dwell dominates trip time in the early game, which makes "faster doors" a
strong and slightly surprising first purchase.

### 5.3 Tenancy

Each floor holds a tenant with a rent rate and a satisfaction value tracking
recent wait times.

- Satisfaction scales rent continuously.
- Below a threshold, a move-out countdown starts and is displayed, giving the
  player a chance to recover it.
- Vacant floors earn nothing and can be re-leased. Better tenants pay more and
  demand faster service.

**No fail state.** Bad play means slow progress, never a loss screen.

### 5.4 Dispatch

Manual at first. Automation is not a switch — it is a policy the player tunes.
The player buys the auto-dispatcher, then buys better rules for it:

1. **Nearest car** — naive, assigns the closest idle car.
2. **Look-ahead** — considers cars already travelling toward the call.
3. **Zoning** — cars claim floor ranges.
4. **Predictive** — pre-positions cars ahead of known rush-hour patterns.

This is the design's load-bearing idea: learning to schedule well by hand teaches
the player what to buy later. Dispatch clicking stops; dispatch decisions do not.

## 6. Additional mechanics

Roughly in unlock order.

- **Smooth-operation combo** — a streak of deliveries with nobody expiring holds
  a rising income multiplier that decays on a bad delivery. This is what makes
  active play pay more than idling, without punishing idling.
- **Sky lobby / transfer floors** — passengers ride to a transfer floor and
  switch cars, turning one long trip into two short ones and roughly doubling
  throughput.
- **Express shafts** — assign a shaft to a floor range. First genuine strategic
  choice.
- **Staff** — one operator per car with a trait: faster doors, +1 capacity, or
  cheerful (+satisfaction per delivery). No gacha, no randomised acquisition.
- **Freight contracts** — a slow high-capacity car and timed cargo jobs paying
  lump sums, competing with passengers for shaft time.
- **Events** — stuck car (rapid-click to free), power brownout (half speed until
  responded to), VIP inspection, cat in the shaft. Short, clickable, and they
  break up the rhythm.
- **Power budget** (Stratosphere onward) — climbing costs energy, descending
  regenerates it, making balanced up/down traffic worth engineering.
- **Contracts and achievements** — e.g. "serve 500 riders in one rush hour" —
  paying Blueprints, rewarding playing well rather than only playing long.

## 7. Idle and offline

The sim runs while the window is open. While closed, progress accrues at a
reduced automated rate, capped at a few hours, with the cap and rate improvable
through the Automation branch.

On return, a "while you were away" summary reports cash earned, riders served,
and any tenants lost.

Offline progress uses an **analytic model**, not replayed ticks (see §8.4).

## 8. Architecture

### 8.1 The one rule

**The simulation knows nothing about the scene tree.** All game logic lives in
plain `RefCounted` classes under `sim/` — no nodes, no `get_node`, no rendering.
The Godot layer owns a sim instance, pumps it with fixed ticks, and renders what
it finds inside.

This buys three things: the sim is unit-testable headlessly, offline progress is
the same code run differently, and the view can be rewritten per era without
touching game rules.

### 8.2 Layout

```
res://
  sim/     game_state, building, elevator, passenger,
           traffic_spawner, tenancy, dispatcher, economy
  data/    eras, upgrades, tenants, traffic curves
  game/    game_root (owns sim, pumps ticks), save_manager,
           offline_progress, number_format
  view/    building_view, elevator_car, passenger_sprite, floor_row
  ui/      hud, upgrade_panel, prestige_panel, event_toast
  tests/   GUT specs against sim/
```

### 8.3 Tick model

The sim advances in fixed ticks (20/s) driven from `_physics_process`, with a
seeded RNG for passenger spawns.

Determinism is a requirement, not a nicety: it lets a test assert "after 600
ticks with this config, throughput is N" and get the same answer every run,
which is the only sane way to balance an incremental.

### 8.4 Communication

Sim to view: **signals only** (`passenger_spawned`, `car_arrived`,
`tenant_departed`, …). The view subscribes and animates.

View to sim: **explicit commands** (`sim.dispatch(car, floor)`). The view never
mutates sim state directly. One-directional data flow.

### 8.5 Designed-around risks

**Sprite count.** Hundreds of passengers will not survive as individual nodes.
Sprites come from a pool; each floor renders at most ~12 individuals before
collapsing into a crowd bar with a count. This caps the worst case in every era.

**Offline catch-up.** Four hours at 20 ticks/sec is 288,000 ticks, far too slow
to replay. Offline progress instead computes throughput and rent rates at save
time and multiplies by elapsed time with an idle penalty — the same numbers the
live sim produces, arrived at in one step.

**Big numbers.** GDScript floats reach ~1e308, comfortably past a five-era game,
so no BigNumber library is needed. What is needed is a formatter (12.4K / 8.1M /
2.3aa) and the discipline never to compare currency with `==`.

### 8.6 Persistence

Versioned JSON in `user://`, written on a timer and on quit, with an explicit
migration step on load. Save version is checked before parse; unknown future
versions refuse to load rather than corrupting state.

### 8.7 Balance as data

Upgrade definitions, tenant types, traffic curves, and era configuration live in
`data/` as Godot Resources or JSON, so tuning does not require code changes.

## 9. Testing strategy

- **Sim** (`sim/`) — heavily unit tested with GUT. Deterministic, headless,
  no scene tree. This is where correctness lives.
- **Offline model** — tested against the live sim: running N ticks live and
  computing N ticks analytically must agree within a stated tolerance.
- **Saves** — round-trip tests, plus a migration test per version bump.
- **View and UI** — thin by construction; verified by smoke tests and manual
  play, not unit tests.

## 10. Delivery

Builds are reviewed on an iPhone, so the web export is the primary delivery
target and desktop is incidental.

**Hosting.** Public GitHub repo, built by GitHub Actions on every push to
`main`, published to GitHub Pages at
<https://seanperkins.github.io/elevator-game-godot/>.

**Threadless export, deliberately.** GitHub Pages cannot set custom HTTP
headers, and Godot's threaded web export requires COOP/COEP. The export
therefore sets `variant/thread_support=false`, which uses the
`web_nothreads_release` template and needs no special headers.

**Orientation.** Portrait, 720x1280 base viewport, `canvas_items` stretch with
`expand`. A tall building suits a phone held upright; desktop gets the same
board with more horizontal room for panels.

**Renderer.** GL Compatibility (WebGL 2). Forward+ on web depends on WebGPU and
is not a safe bet in mobile Safari.

**VRAM texture compression is off.** Enabling it for mobile requires "Import
ETC2 ASTC" in project settings; without it, Godot 4.7 fails the export with a
config error whose message body is empty. This is a 2D game with no compressed
textures, so there is nothing to gain by turning it on.

### Milestone 0 — pipeline check (complete)

Before any game code, a probe scene was deployed to verify the whole chain on a
real device: rendering, frame-loop animation, touch input, text layout, and
`user://` persistence (IndexedDB on web, the likeliest thing to break in
Safari).

Verified in Chrome against the live Pages URL: Godot 4.7 web build boots over
plain HTTP with no COOP/COEP headers, runs at 60 fps, registers taps, and
round-trips a save through `user://`.

**Outstanding:** confirmation on the user's actual iPhone. Desktop Chrome is
strong evidence, not proof, for mobile Safari.

**Known cost:** the wasm payload is ~39 MB uncompressed. Acceptable over wifi;
worth revisiting if it grows.

## 11. Build order

Each milestone is playable on its own.

1. **Vertical slice** — one shaft, one car, 6 floors, manual dispatch, fares.
   Ugly but playable.
2. **Tycoon layer** — tenants, satisfaction, rent, move-outs, patience meters.
3. **Economy and upgrades** — shafts, cars, speed, doors; data-driven upgrade
   definitions.
4. **Automation** — the dispatcher and its tunable policies.
5. **Prestige** — demolish, Blueprints, tech tree, era 2.
6. **Save and offline** — persistence and the welcome-back screen.
7. **Content and feel** — remaining eras, events, staff, contracts, juice.

## 12. Decisions taken

Recorded so they are not relitigated:

- Tycoon economy over pure clicker or pure dispatch puzzle.
- Prestige resets height rather than scrolling or zone-collapsing the view.
- Blueprints plus themed eras, rather than a tech tree alone or carried-over
  floors.
- Soft pressure: tenants leave, runs never fail.
- Offline progress on, capped, improvable.

## 13. Open items for balancing

Deferred to implementation, not blocking:

- Exact Blueprint conversion curve and per-era thresholds.
- Fare, rent, and upgrade cost curves.
- Patience durations per era and tenant tier.
- Traffic curve shapes per era.
- Surge boost magnitude and cooldown.
