> Generated: 2026-08-03 | Token-lean format for LLM context

# sim/ — pure logic layer (all `class_name`, `extends RefCounted`)

No scene tree. Talks to the view by **signal** only (emitted by `GameState`).

## GameState — the owner (`game_state.gd`)
`_init(floors, shafts, p_seed, catalog_path, p_meta: Meta = null, blueprints_path)`.
`BASE_FLOORS=6`, `BASE_SHAFTS=1`, `BASE_SEED=20260802` (game_root's START_* are refs to these).
Signals: `passenger_spawned(p)`,
`passenger_delivered(p, paid)`, `passenger_expired(p)`, `car_arrived(shaft_index, floor_index)`.

Owns: `clock, building, spawner, economy, tenancy, fitout, catalog, upgrades, metrics, auto, meta`.
Keeps `catalog_path()` / `blueprints_path()` so a demolish rebuilds against the
same catalogs (otherwise overrides are silently defeated).

API: `buy(id)`, `lease(floor_index, kind_id)`, `lease_cost(floor_index, kind_id)`,
`available_kinds(floor_index)`, `class_upgrade_cost(floor_index)`, `upgrade_class(floor_index)`,
`set_policy(shaft, preset)`, `is_preset_available(preset)`, `auto_licences()` (= `upgrades.level_of("auto")`),
`dispatch(shaft, floor_index)`, `tick(n)`, `is_valid()`, `invalid_what()`, `invalid_path()`.

* **`_valid` defaults to FALSE**, set true as the LAST statement of `_init`. A
  GDScript constructor that errors returns a HALF-BUILT object and the caller
  resumes, so a default of `true` reports a state with a null clock as valid.
* `_init` **never resizes the building** — the saved size is the authority. The
  Meta's starting size is applied by the callers that BEGIN a run
  (`Prestige.demolish`, `game_root`'s cold boot).
* Cap budgets measure against **`BASE_FLOORS`**, not the current size:
  `set_max_level("floor", meta.height_cap() - BASE_FLOORS)`. Against the current
  size it is a level budget measured against a floor count, correct only at
  level 0, and a reload caps the player below what they paid for.
* A malformed blueprint catalog is **fatal** — no skip-the-tree fallback.

* `buy()` grows **every** per-floor container via `_grow_per_floor_containers()` — one loop, not two (historic desync bug).
* `_deliver()` credits satisfaction to `p.source_floor` — the floor that GENERATED the trip, not the endpoint.
* `_sources()` caches `Array[TrafficSource]`, rebuilt when `tenancy.revision() + fitout.revision()` changes.

## Meta (`meta.gd`) — the persistent half
Blueprints, tech-tree levels, and the derivations a run STARTS from. Knows
nothing about GameState; GameState reads it, never the reverse.
`BASE_HEIGHT_CAP=10`, `HEIGHT_PER_LEVEL=5`, `MAX_HEIGHT_CAP=20` (**not**
`Building.MAX_FLOORS`), `MAX_BLUEPRINTS=1_000_000_000` (**== `Prestige.MAX_YIELD`**,
pinned), `MAX_RUNS=1_000_000`, `BASE_STARTING_SHAFTS=1`, `MAX_NODES=64`,
`MAX_BASE=1_000_000`, `MAX_NODE_LEVEL=64`.
`NODE_TO_UPGRADE = {motor: speed, gearing: doors, cabin: capacity}` — node id →
upgrade id, in THAT direction. Structure nodes map to nothing.

`load_defs(path)`, `is_usable()`, `ids()`, `name_of/note_of/branch_of`,
`level_of`, `is_maxed`, `cost_of` (= `base * (level+1)`),
`is_zero_delta(id, up)`, `can_buy(id, up)`, `buy(id, up)`,
`to_dict()` / `restore(data)`, `height_cap()`, `starting_shafts()`,
`starting_level(upgrade_id)`.

* `is_usable()` is a **stored flag**, never `not _defs.is_empty()`: every
  malformed rule is a mid-loop failure, and a partial load reporting usable
  makes `restore`'s iterate-`ids()` rule silently drop the tree.
* `load_defs` **never touches `_spent`** (unlike `Upgrades.load_defs`, which
  zeroes `_levels`) and builds into a local, publishing only on success.
* `is_zero_delta` evaluates at the **Meta's** level, not the run's — delegating
  would refuse `gearing` at L0 whenever the run's doors sat at the plateau.
* `restore` returns false ONLY when defs are unloaded. A malformed block is an
  EMPTY Meta, not a refusal: refusing deletes a building.
* `to_dict`/`restore` deep-copy at both ends; the demolish clone depends on it.

## Prestige (`prestige.gd`) — static only, the one place a run can END
`MAX_YIELD=1_000_000_000`, `DEMOLITION_FLOOR=900.0`, `EARNINGS_PER_BLUEPRINT=100.0`.
`yield_for(earnings)`, `can_demolish(state)`, `demolish(state) -> GameState|null`.

`blueprints(E) = floor(sqrt(max(0, E - 900) / 100))`, so n BP need `900 + 100n²`
and the n-th costs `$100(2n-1)`. The offset breaks the scale invariance of a bare
square root, whose rate-optimal exit is nine minutes at six floors.

* **`maxf` argument order is load-bearing**: `maxf(E - FLOOR, 0.0)` absorbs NAN
  to 0; reversed it returns NAN and `minf(NAN, MAX)` yields MAX_YIELD.
* Clamp in FLOAT space before `int()` — out-of-range float→int is
  platform-defined and the ship target is a different toolchain.
* `demolish` order: **clone Meta → credit the CLONE → build → validate → return**.
  GameState holds the Meta by reference, so crediting the live one leaves the old
  run holding Blueprints it never earned when the caller's save fails, and the
  autosave makes that durable beside a still-demolish-eligible building.
* `E` is **per-run**; `lifetime_earnings` resets because a fresh GameState is
  constructed. Making it cumulative mints without limit.
* New seed = `BASE_SEED + runs_completed` read AFTER the increment.

## Building (`building.gd`)
`MAX_FLOORS=40`, `MAX_SHAFTS=8`. `floor_count`, `cars: Array[ElevatorCar]`, `waiting` (Array[Passenger] per floor).
`add_shaft()`, `add_floor()`, `enqueue(p)`, `waiting_at(f)`, `total_waiting()`, `take_boardable(f, limit)` (FIFO), `remove_waiting_from_source(f)`.

## ElevatorCar (`elevator_car.gd`)
Fake lerp physics. `capacity=4`, `floors_per_tick=0.04` (MUST equal `Upgrades.SPEED_BASE`), `door_ticks=20`, `spring_multiplier=1.0`.
States `IDLE/MOVING/DOORS`. `dispatch_to(f, express)`, `launch_to(f)`, `step(n)`, `answer_call()` (a parked car opens doors for a call at its OWN floor — boarding, not routing), `is_committed()`, `current_floor()`, door phases via `door_opening_ticks()/door_closing_ticks()/door_elapsed_ticks()`.

## Passenger (`passenger.gd`)
`origin_floor`, `destination_floor`, `patience_ticks`, `fare`, `boarded`, **`source_floor`** (the tenant floor that generated the trip; NOT derivable from endpoints), `_initial_patience`.
`decay(n)`, `is_expired()` (exactly 0 is NOT expired), `patience_fraction()`, `waited_ticks()`, `direction()`.

## TrafficSpawner (`traffic_spawner.gd`)
`spawn_from_sources(minute, sources: Array[TrafficSource], lobby_tenanted) -> Array[Passenger]`.
**One Bernoulli trial per tick against the SUMMED rate**, then a weighted pick of which source produced it — not one trial per floor, so the seed sequence does not depend on building height. Threshold is `total / SimClock.TICKS_PER_SIM_MINUTE`.
`load_curve(path)` reads **only** `base_patience_ticks` (900); per-floor rate and fare come from the catalog. `rng` is a duck-typed member (a subclass would trip NATIVE_METHOD_OVERRIDE). `seed_value()`.
`_destination_for()` returns -1 meaning "inbound, swap the endpoints"; collapses to interfloor when the lobby is not a usable endpoint (incl. a tenant ON floor 0).

## TenantCatalog / TenantKind / TrafficSource
* **TenantCatalog** (`tenant_catalog.gd`) — loads `data/tenants.json`. `kind(id)`, `all_kinds()`, `available_for_class(tier)`, `cheapest_for_class(tier)`, `class_cost(tier)`, `fare_multiplier(tier)`, `max_tier()`, `largest_bucket()` (saturation guard: `MAX_FLOORS x this` must stay under `TICKS_PER_SIM_MINUTE`).
* **TenantKind** (`tenant_kind.gd`) — `BUCKETS=24`. `id, display_name, requires_class, lease_cost, base_fare, rate[24], inbound[24], outbound[24]`. `rate_at/inbound_at/outbound_at/interfloor_at(minute)`, all `posmod(minute, 24)`.
* **TrafficSource** (`traffic_source.gd`) — one tenanted floor as the spawner sees it: `floor_index, kind, fare_multiplier`. Knows nothing of Tenancy or Fitout.

## Tenancy (`tenancy.gd`)
Per-floor tenants. `MOVE_OUT_THRESHOLD=0.2`, `MOVE_OUT_TICKS=1200`, `_DELIVERY_GAIN=0.02`, `_EXPIRY_LOSS=0.05`, `MIN_FLOORS_FOR_TRAFFIC=2`.
`floors()`, `add_floor()`, `revision()`, `restore_floor(...)`, `kind_at(f)`, `set_kind(f, id)`, `lease(f, kind_id)`, `note_delivery(f)`, `note_expiry(f)`, `accrue_for_tick()` → floors that vacated, `satisfaction_at(f)`, `occupied_floors()`, `is_vacant(f)`, `is_moving_out(f)`, `move_out_ticks_left(f)`, `tenanted_count()`.
**No-fail guarantee**: leasing is free while fewer than `MIN_FLOORS_FOR_TRAFFIC` floors are tenanted.

## Fitout (`fitout.gd`)
Per-floor **class** (tier), separate from Tenancy so a class purchase is not a tenancy event. `BASE_TIER=1`. `floors()`, `add_floor()`, `tier_at(f)`, `set_tier(f, tier)`, `revision()`.

## Economy (`economy.gd`)
`COMBO_MAX=10.0`, `COMBO_STEP=0.02`, `STAIRS_PENALTY_FARES=1.0`. `cash, lifetime_earnings, combo, streak, riders_served`.
`credit_delivery(fare)`, `note_expiry(fare)` (**required arg** — the default was the bug), `accrue`, `can_afford`, `spend`. Cash floors at 0 (no debt).

## AutoDispatch (`auto_dispatch.gd`)
Only ever commands an **IDLE** car; a manual dispatch always wins. Licences enforced in `GameState`, mechanism here.
`set_policy(shaft, preset, policy)`, `step(building)`, `enabled_count()`, `preset_of(shaft)`, `is_enabled(shaft)`.

## DispatchPolicy (`dispatch_policy.gd`)
Three orthogonal choices: `Source {EVERY_FLOOR=1, HALL_CALLS=2, CAR_CALLS=4}` (a bitmask), `Order {SWEEP, NEAREST}`, `WhenIdle {STAY, RETURN_TO_LOBBY}`, plus `bypass_when_full` (load weighing).
`STAY_PUT=-1`, `LOBBY=0`. `PRESET_ORDER` = MANUAL, EVERY_FLOOR, ANSWER_CALLS, NEAREST_CALL, CALLS_THEN_LOBBY.
`preset_requires(preset)` → hardware ids (**EVERY_FLOOR requires none** — that is why it stops everywhere), `preset_policy(preset)`, `candidates(...)`, `choose(...)`.

## Upgrades (`upgrades.gd`)
Defs are data, effects are code. `DOOR_TICKS_BASE=20`, `DOOR_TICKS_MIN=4`, `SPEED_BASE=0.04`, `CAPACITY_BASE=4`, `SPRING_BASE=4.0`.
`load_defs` (now also stores `note`, which `note_of` had always indexed),
`restore_levels` (applies NO effects — the saved car values are the authority),
`purchase(id, econ, building)`, `effect_value(id, level)`, `is_installed(id)`,
`is_maxed(id)`, `is_zero_delta(id)`, `has_effect(id)`,
**`set_max_level(id, level)`** (per-run ceiling; clamps to [0,∞); only
`is_maxed` reads max_level — `cost_of` does not) and
**`grant_level(id, level, building)`** (levels a run BEGINS with; clamps to
[0, max_level], syncs every car, **never calls `_apply`** — mirroring
`purchase()` would call `add_floor()` N times and grow a decoded building past
its own saved floors array; also consumes the price ladder).
`HARDWARE` = hall_buttons, car_buttons, load_sensor, lobby_parking, spring, **call_direction**.

## Metrics (`metrics.gd`)
`BUCKET_TICKS=20`, `BUCKETS=60` (~60 s of history, independent of `TICKS_PER_*`). `advance()` runs FIRST in the tick. `record_delivery(waited)`, `record_expiry()`, `deliveries()`, `expiries()`, `average_wait_seconds()` (−1.0 sentinel when empty).

## SimClock (`sim_clock.gd`)
`TICK_SECONDS=0.05`, `TICKS_PER_REAL_MINUTE=1200`, **`TICKS_PER_SIM_MINUTE=600`** (one traffic bucket = 30 real s), `MAX_TICKS_PER_FRAME=8` (overflow forfeited, never queued), `START_MINUTE=6`.
`take_ticks(delta)`, `note_ticks(n)`, `sim_minute()` = `START_MINUTE + ticks_executed / TICKS_PER_SIM_MINUTE`.
The two constants must move together: the bucket length and the spawner's denominator are the same unit, and changing one alone nets zero.

## BoardCoords (`coords.gd`)
Single floor↔y identity, bottom-up (may go negative → basement in Spec B). **Edge-table** mapping, not division, so `floor_to_y ⇄ y_to_floor` round-trips exactly. `fixed(bottom, top, height)`, `scroll_offset`, `set_viewport_height`, `scroll_by/scroll_to`.

## Gesture (`gesture.gd`)
TAP vs PAN on a shaft column. `DRAG_THRESHOLD=12.0`. Dispatch is a tap (the press point resolves, never drift). `press/move/release/take_pan_delta/selected_floor/is_panning`.

## SaveCodec (`save_codec.gd`)
`VERSION=4`, `SUPPORTED_VERSIONS=[1,2,3,4]`.
`encode(state)` / `decode(p_data, catalog_path, blueprints_path)` → null when
unusable (never half-applied) — the two trailing params are default-valued so
existing one-arg call sites still compile.
Bounds: `MAX_MONEY=1e15`, `MAX_CAPACITY=CAPACITY_BASE+8`,
`MAX_SPEED=SPEED_BASE*(1+0.25*12)`, `MIN_SPEED=0.0001`.

**v4 adds a `meta` block** (`{blueprints, runs, spent}`) — it rides in the same
file as the run because a demolish must persist both in ONE write.

Decode order: `_preflight → _migrate_to_v3 → _migrate_to_v4 → _is_usable →
build the Meta → GameState.new → levels → cars → floors → policies`.
* `_preflight` is TYPE-only and runs FIRST, because migration itself throws:
  `_migrate_to_v3` casts `version` and assigns `levels` to a typed Dictionary
  before any check exists. `meta` is deliberately NOT preflighted.
* `_legacy_meta(floor_count, path)` — **version ≤ 3 only**, grants
  `clampi(ceili((floor_count-10)/5.0), 0, 2)` height levels, charges nothing.
* `_empty_meta(path)` — version == 4, meta absent OR malformed. Grants nothing.
  Two names for two behaviours, deliberately: one word for both is how an erased
  v4 save ends up handed the whole cap ladder.
* `salvage_meta(p_data, path)` — reads the **UNMIGRATED** dict via `data.get`
  only, never calls `_legacy_meta`. A refused RUN must not take the tree down.
* Every save-derived conversion is type-guarded **in decode**, not in a `void`
  callee (`restore_levels` aborting mid-loop returns a non-null HALF-restored
  state). Violations **clamp**, they do not refuse — a declared override of the
  base design, because refusing deletes a building.
**v3 migrates on read**: `_migrate_to_v3` renames `row_count→floor_count`, `rows→floors`, car `position_row/target_row/rows_per_tick`, and `levels.row→levels.floor`. It deliberately does NOT rewrite `version`, because the v1/v2 tenancy branches still need to know which they are reading.
Guards are `version >= 2`, not `== 2` — pinning the literal is how they silently stopped covering current saves when VERSION moved.
