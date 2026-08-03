> Generated: 2026-08-02 | Token-lean format for LLM context

# sim/ — pure logic layer (all `class_name`, `extends RefCounted`)

No scene tree. Talks to the view by **signal** only (emitted by `GameState`).

## GameState — the owner (`sim/game_state.gd`)
Owns every module, runs the tick. `_init(rows, shafts, p_seed)`.
Signals: `passenger_spawned(p)`, `passenger_delivered(p, paid)`, `passenger_expired(p)`, `car_arrived(shaft_index, row)`.

| Member | Type |
|---|---|
| clock / building / spawner / economy / tenancy / upgrades / metrics / auto | SimClock / Building / TrafficSpawner / Economy / Tenancy / Upgrades / Metrics / AutoDispatch |

Key API: `buy(id)`, `relet(row)` (charges `relet_cost` BEFORE relet), `set_auto(shaft,on)`, `set_policy(shaft,preset)`, `is_preset_available(preset)`, `auto_licences()` (= `upgrades.level_of("auto")`), `dispatch(shaft,row)` (spring trip iff `is_spring_trip` && spring fitted), `tick(n)`.

* `buy()` grows **every** per-floor container to `building.row_count` via catch-up loop (historic desync bug — see spec §3.1).
* `_deliver()` credits satisfaction to `p.source_row` (the floor that generated the trip, not the endpoint): `tenancy.note_delivery(p.source_row)`.

## Building (`building.gd`)
`const MAX_ROWS=40`, `MAX_SHAFTS=8`. `var row_count`, `cars: Array[ElevatorCar]`, `waiting: Array` (Array[Passenger] per row).
API: `add_shaft()`, `add_row()`, `enqueue(p)`, `waiting_at(row)`, `total_waiting()`, `take_boardable(row, limit)` (FIFO).

## ElevatorCar (`elevator_car.gd`)
Fake lerp physics. Defaults: `capacity=4`, `rows_per_tick=0.04` (≈1.25s/floor; MUST match `Upgrades.SPEED_BASE`), `door_ticks=20`. `spring_multiplier` (1.0 = none).
States `IDLE/MOVING/DOORS`. `is_committed()` = launched (spring) trips cannot be redirected. `dispatch_to(row, express:=false)`, `launch_to(row)`, `step`, `answer_call()` (a parked car opens doors for a call at its own floor). Door phases via `door_opening_ticks()/door_closing_ticks()/door_elapsed_ticks()`.

## Passenger (`passenger.gd`)
Fields: `origin_row`, `destination_row`, `patience_ticks`, `fare`, `boarded`, **`source_row`** (floor whose tenant generated the trip; NOT derivable from endpoints), `_initial_patience`. `decay(n)`, `is_expired()` (exactly 0 is NOT expired), `patience_fraction()`, `waited_ticks()`, `direction()`.

## TrafficSpawner (`traffic_spawner.gd`)
Piecewise-constant curve bucketed by sim minute. `const REFERENCE_ROWS=6` (curve describes a 6-row building). `load_curve(path)`, `rate_at_minute(minute)`, `spawn_for_tick(minute, occupied)` — Bernoulli draw; `occupied` = `tenancy.occupied_rows()`. Deterministic from `seed_value()`.

## Tenancy (`tenancy.gd`)
Per-row tenants. Satisfaction scales *nothing monetary* (rent is dead) — a tenant's only value is generating traffic. `const MOVE_OUT_THRESHOLD=0.2`, `MOVE_OUT_TICKS=1200`, `RELET_COST=40.0`, `_DELIVERY_GAIN=0.02`, `_EXPIRY_LOSS=0.05`.
API: `rows()`, `add_row()`, `restore_row(row,sat,vacant,move_out_left)`, `note_delivery(row)`, `note_expiry(row)`, `accrue_for_tick()`, `satisfaction_at(row)`, `occupied_rows()`, `is_vacant(row)`, `is_moving_out(row)`, `move_out_ticks_left(row)`, `tenanted_count()`, `relet_cost(row)`, `relet(row)`.
**No-fail guarantee**: re-lease free when fewer than 2 rows tenanted (`MIN_ROWS_FOR_TRAFFIC=2`).
→ Spec A will add **kind** here (per-row) and a new `Fitout` for floor **class**.

## Economy (`economy.gd`)
`const COMBO_MAX=10.0`, `COMBO_STEP=0.02`, `STAIRS_PENALTY_FARES=1.0`. Fields: `cash`, `lifetime_earnings`, `combo`, `streak`, `riders_served`.
`credit_delivery(fare)`, `note_expiry(fare)` (required arg; stairs penalty = one fare, floored at 0 — no-fail), `accrue(amount)`, `can_afford`, `spend`. Combo hard-capped; breaks on expiry/stairs.

## AutoDispatch (`auto_dispatch.gd`)
Sweep policy. Only commands **IDLE** cars; never a moving or boarding car. Licences enforced in `GameState.set_auto` (mechanism here, gate there). `set_policy(shaft, preset, policy)`, `set_enabled`, `step(building)`, `enabled_count()`, `preset_of(shaft)`.

## DispatchPolicy (`dispatch_policy.gd`)
Orthogonal choices as constants: `Source` (EVERY_FLOOR/WAITING/RIDERS), `Order` (SWEEP/NEAREST), `WhenIdle` (STAY/LOBBY), `bypass_when_full`. Pure: caller passes floor arrays, gets a floor back. `const STAY_PUT=-1`, `LOBBY=0`. `PRESET_ORDER`= [MANUAL, EVERY_FLOOR, ANSWER_CALLS, ...]; `preset_requires(preset)`→hardware list; `preset_policy(preset)`. `candidates(from,row_count,waiting,riders)`, `choose(...)`.

## upgrades.gd
Defs are data (`data/upgrades.json`), effects are code. `const DOOR_TICKS_BASE=20`, `DOOR_TICKS_MIN=4`, `SPEED_BASE=0.04`, `CAPACITY_BASE=4`, `SPRING_BASE=4.0`. `load_defs`, `restore_levels` (no effects), `purchase(id,econ,building)`, `effect_value(id,level)`, `is_installed(id)` (hardware max_level 1), `is_zero_delta(id)`, `_sync_car`. `HARDWARE` = hall_buttons, car_buttons, load_sensor, lobby_parking, spring.

## Metrics (`metrics.gd`)
60 one-second rolling buckets (BUCKET_TICKS=20). `advance()` FIRST in tick, `record_delivery(waited_ticks)`, `record_expiry()`, `deliveries()`, `expiries()`, `average_wait_seconds()` (−1.0 sentinel when empty). Owns its own tick counter.

## SimClock (`sim_clock.gd`)
20Hz accumulator over 60Hz physics. `TICK_SECONDS=0.05`, `TICKS_PER_MINUTE=1200`, `MAX_TICKS_PER_FRAME=8` (overflow forfeited). `take_ticks(delta)`, `note_ticks(n)`, `sim_minute()` — day opens at `START_MINUTE=6` (morning rush), offset on the reading, not on ticks_executed.

## BoardCoords (`coords.gd`)
Single row↔y identity. Floors run bottom-up (may be negative → basement in Spec B). Fixed `row_height`, scrollable (`scroll_offset`, `set_viewport_height`, `scroll_by/scroll_to`, `_ground_offset`). **Edge-table** mapping (not division) so floor_to_y ⇄ y_to_floor round-trips exactly. All coordinates column-local; the frame offset lives in BuildingView.

## Gesture (`gesture.gd`)
Distinguishes TAP from PAN on a shaft column. `const DRAG_THRESHOLD=12.0`. Dispatch is a **tap** (press point resolves, never drift); panning is 2D. `press/move/release/take_pan_delta/selected_row/is_panning`.

## AutoDispatch / SaveCodec (`save_codec.gd`)
Turns a GameState into a versioned Dictionary and back. `const VERSION=1`. `encode(state)` / `decode(data)` (null when unusable — `_is_usable` checks version + required keys, never half-applies). Stores per-row satisfaction/vacancy/move-out. Pure data; file handling is in SaveStore.

## File handling — SaveStore (`game/save_store.gd`)
`PATH="user://save.json"`, atomic write via `.tmp`. All dynamic strings rendered via Label, never BBCode (shared github.io origin).
