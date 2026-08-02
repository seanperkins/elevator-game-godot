# UI: Board and Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the board bottom-up around one coordinate transform, add the ghost floor and ghost shaft so every purchase happens where the thing appears, and replace the upgrade sheet with a Management view led by live metrics.

**Architecture:** All new logic is `RefCounted` under `sim/` and unit-tested headlessly — a coordinate transform that maps floors to screen y through a precomputed edge table, and a rolling metrics window. The view consumes both and owns no arithmetic of its own. A new scene-driving test harness covers the input behaviours no headless test and no screenshot can reach.

**Tech Stack:** Godot 4.7 stable, GDScript, GUT 9.7.1, GitHub Actions → Pages.

**Spec:** `docs/superpowers/specs/2026-08-02-ui-design.md`

## Global Constraints

- **The sim never touches the scene tree.** Nothing under `sim/` may reference `Node`, `get_node`, or a scene.
- **Floors run bottom-up.** Floor 0 is the lobby, at the bottom of the board.
- **One row↔y transform.** `sim/coords.gd` is the only place the inversion exists. Four consumers: `gesture.gd`, `building_view.gd`, `shaft_column.gd`, `floor_selector.gd`.
- **No division in `y_to_floor`.** `N-1-floor(y/h)` is not an identity in IEEE double; the transform compares against a stored edge table.
- **Board geometry:** 720x1280, HUD 96, board 1184. `h = 1184 / (floors + G)` where `G = 1` below the 40-floor cap and 0 at it.
- **Row regions:** count 0–26, tenant bar 30–34, floor number 38–64, people strip 64–240, shaft viewport 240–720.
- **Shafts:** 96-unit pitch, drawn at 92 (50.2pt), five visible, `MAX_SHAFTS = 8`.
- **Touch floor 44pt.** Every tap target meets it except a floor row, which is why re-leasing confirms (Task 13).
- **Tick order is fixed and written:** `advance metrics → spawn → move/doors → deliver → expire → accrue rent → update combo`.
- **Never compare currency with `==`.**
- **Test command:** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` (exits 1 on failure). Run `godot --headless --import` after adding any file with a new `class_name`.
- **Godot must run unsandboxed.** The sandbox denies Godot's user data dir; a sandboxed run crashes with signal 11. Use `dangerouslyDisableSandbox: true`.

---

## File Structure

```
sim/
  coords.gd         NEW  edge table; floor_to_y, car_y, y_to_floor
  metrics.gd        NEW  60x20-tick rolling window + readout formatting
  gesture.gd        MOD  consume coords; return floors
  passenger.gd      MOD  waited_ticks()
  traffic_spawner.gd MOD clamp base_patience_ticks >= 1
  upgrades.gd       MOD  effect_value query; zero-delta refusal
  tenancy.gd        —    read by the relet command; unchanged
  building.gd       MOD  docstring only
  game_state.gd     MOD  metrics, relet(), tick order
view/
  floor_row.gd      MOD  regions, three-state bar, vacant price, crowd tier
  building_view.gd  MOD  board frame, viewport inset, ghost floor, ghost shaft
  shaft_column.gd   MOD  car_y; Gesture construction
  floor_selector.gd MOD  transform; bubble placement near the top
ui/
  management_view.gd NEW replaces upgrade_panel.gd
  relet_confirm.gd   NEW the one confirmed action
  upgrade_panel.gd   DEL
game/
  game_root.gd      MOD  view switch, pager, debug board override
tests/
  test_coords.gd       NEW
  test_metrics.gd      NEW
  test_board_input.gd  NEW  scene-driving harness
  test_gesture.gd      REWRITTEN
  test_passenger.gd    MOD
  test_game_state.gd   MOD
  test_upgrades.gd     MOD
```

---

## Task 1: BoardCoords — the one row↔y transform

**Files:**
- Create: `sim/coords.gd`, `tests/test_coords.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `BoardCoords.new(floor_count: int, row_height: float)`; properties `floor_count: int`, `row_height: float`; methods `floor_to_y(f: int) -> float`, `car_y(position_row: float) -> float`, `y_to_floor(y: float) -> int`, `band_centre_y(f: int) -> float`.

All y values are **column-local**: y = 0 is the top floor's top edge, and the column is `floor_count * row_height` tall. The board frame adds the ghost band offset (Task 9).

- [ ] **Step 1: Write the failing test**

Create `tests/test_coords.gd`:

```gdscript
extends GutTest

## The board is 1184 units tall and holds floors + a ghost floor below the cap.
func height_for(floors: int) -> float:
	var ghost := 1 if floors < 40 else 0
	return 1184.0 / float(floors + ghost)

func test_floor_zero_is_the_bottom_band() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_almost_eq(c.floor_to_y(0), 5.0 * height_for(6), 1e-9,
		"the lobby's top edge is one row above the column's bottom")
	assert_almost_eq(c.floor_to_y(5), 0.0, 1e-9, "the top floor starts at y=0")

func test_round_trip_is_exact_at_every_floor_count() -> void:
	# N-1-floor(y/h) is NOT an identity in IEEE double: at N=29 the lobby's top
	# edge divides to 27.999999999999996 and resolves to floor 1. Twelve of the
	# forty floor counts have at least one floor that fails that way, so this
	# asserts all of them rather than a sample.
	for floors in range(1, 41):
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.y_to_floor(c.floor_to_y(f)), f,
				"N=%d floor %d must round-trip" % [floors, f])

func test_band_centres_round_trip_too() -> void:
	for floors in [6, 28, 29, 40]:
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.y_to_floor(c.band_centre_y(f)), f,
				"N=%d floor %d centre" % [floors, f])

func test_y_to_floor_is_monotonic_downward() -> void:
	# Walking down the column must walk down the floor numbers, never jump.
	var c := BoardCoords.new(29, height_for(29))
	var previous := c.y_to_floor(0.0)
	assert_eq(previous, 28, "the top of the column is the top floor")
	var y := 1.0
	while y < 29.0 * height_for(29):
		var f := c.y_to_floor(y)
		assert_true(f == previous or f == previous - 1,
			"floor stepped from %d to %d at y=%f" % [previous, f, y])
		previous = f
		y += 3.0
	assert_eq(previous, 0, "the bottom of the column is the lobby")

func test_y_above_the_column_clamps_to_the_top_floor() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_eq(c.y_to_floor(-500.0), 5)

func test_y_below_the_column_clamps_to_the_lobby() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_eq(c.y_to_floor(99999.0), 0)

func test_car_y_is_continuous() -> void:
	# A car at 2.4 is between floors and must render there, not snap.
	var h := height_for(6)
	var c := BoardCoords.new(6, h)
	assert_almost_eq(c.car_y(0.0), 5.0 * h, 1e-9)
	assert_almost_eq(c.car_y(0.5), 4.5 * h, 1e-9)
	assert_almost_eq(c.car_y(5.0), 0.0, 1e-9)

func test_car_y_agrees_exactly_with_floor_to_y_at_integers() -> void:
	# The car and the row it stops at must not disagree by a float hair.
	for floors in [6, 29, 40]:
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.car_y(float(f)), c.floor_to_y(f),
				"N=%d floor %d: car and row must be bit-identical" % [floors, f])

func test_a_single_floor_building_is_valid() -> void:
	var c := BoardCoords.new(1, 1184.0)
	assert_eq(c.y_to_floor(0.0), 0)
	assert_eq(c.y_to_floor(1183.0), 0)
	assert_almost_eq(c.floor_to_y(0), 0.0, 1e-9)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_coords.gd -gexit
```

Expected: FAIL — `Identifier "BoardCoords" not declared`.

- [ ] **Step 3: Write the implementation**

Create `sim/coords.gd`:

```gdscript
class_name BoardCoords
extends RefCounted

## The single row<->y identity for the board. Floors run bottom-up: floor 0 is
## the lobby at the bottom, and y = 0 is the TOP floor's top edge.
##
## All coordinates are COLUMN-LOCAL. The board frame offsets them by the ghost
## band -- board_y = ghost_height + local_y -- and BuildingView owns that offset.
##
## The mapping is an edge table rather than a division, deliberately. Computing
## y_to_floor as N-1-floor(y/h) is not an identity in IEEE double: at N=29,
## 28*h = 1105.0666666666666 and dividing by h gives 27.999999999999996, so the
## lobby's own top edge resolves to floor 1. Twelve of the forty floor counts
## have at least one floor that fails that way. Comparing against the same
## stored edges makes the round trip exact by construction.

var floor_count: int
var row_height: float

var _edges: PackedFloat64Array = PackedFloat64Array()

func _init(p_floor_count: int, p_row_height: float) -> void:
	floor_count = maxi(p_floor_count, 1)
	row_height = maxf(p_row_height, 0.001)
	for k in range(floor_count + 1):
		_edges.append(float(k) * row_height)

## Top edge of floor f's band. Exact: a stored value, not a computation.
func floor_to_y(f: int) -> float:
	return _edges[clampi(floor_count - 1 - f, 0, floor_count - 1)]

func band_centre_y(f: int) -> float:
	return floor_to_y(f) + row_height * 0.5

## Continuous form, for a car at a fractional row like 2.4. Agrees with
## floor_to_y bit-for-bit at integer positions -- the same expression.
func car_y(position_row: float) -> float:
	return (float(floor_count - 1) - position_row) * row_height

## The floor whose band contains y, found by comparison against the same edges
## floor_to_y returns. Linear over at most 40 bands, once per touch event.
func y_to_floor(y: float) -> int:
	var k := 0
	while k < floor_count - 1 and y >= _edges[k + 1]:
		k += 1
	return floor_count - 1 - k
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_coords.gd -gexit
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add sim/coords.gd tests/test_coords.gd
git commit -m "feat(sim): bottom-up row/y transform over an exact edge table"
```

---

## Task 2: Metrics — the rolling window and its formatting

**Files:**
- Create: `sim/metrics.gd`, `tests/test_metrics.gd`

**Interfaces:**
- Consumes: `SimClock.TICK_SECONDS`.
- Produces: `Metrics.new()`; constants `Metrics.BUCKET_TICKS` (`20`), `Metrics.BUCKETS` (`60`); methods `advance() -> void`, `record_delivery(waited_ticks: int) -> void`, `record_expiry() -> void`, `deliveries() -> int`, `expiries() -> int`, `average_wait_seconds() -> float` (returns `-1.0` when there are no deliveries), and statics `Metrics.format_wait(seconds: float) -> String`, `Metrics.format_rate(count: int) -> String`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_metrics.gd`:

```gdscript
extends GutTest

var m: Metrics

func before_each() -> void:
	m = Metrics.new()

## Runs n ticks, advancing first exactly as GameState does.
func run_ticks(n: int) -> void:
	for i in range(n):
		m.advance()

func test_an_empty_window_reports_nothing() -> void:
	assert_eq(m.deliveries(), 0)
	assert_eq(m.expiries(), 0)
	assert_almost_eq(m.average_wait_seconds(), -1.0, 1e-9,
		"no deliveries is a sentinel, not zero")

func test_a_partial_window_counts_everything_in_it() -> void:
	for i in range(5):
		m.advance()
		m.record_delivery(200)
	assert_eq(m.deliveries(), 5)

func test_average_wait_is_in_seconds() -> void:
	m.advance()
	m.record_delivery(200)       # 200 ticks * 0.05 = 10 s
	m.record_delivery(600)       # 30 s
	assert_almost_eq(m.average_wait_seconds(), 20.0, 1e-6)

func test_expiries_are_counted_separately() -> void:
	m.advance()
	m.record_expiry()
	m.record_expiry()
	assert_eq(m.expiries(), 2)
	assert_eq(m.deliveries(), 0)

func test_an_event_on_the_rollover_tick_is_counted() -> void:
	# Tick 1200 rolls into bucket 0 and clears it. Advancing FIRST means the
	# event lands in the freshly cleared bucket, not one about to be wiped.
	run_ticks(1200)
	m.record_delivery(100)
	assert_eq(m.deliveries(), 1, "counted on the rollover tick itself")

func test_that_event_survives_to_the_end_of_its_bucket() -> void:
	run_ticks(1200)
	m.record_delivery(100)
	run_ticks(19)
	assert_eq(m.deliveries(), 1, "still counted 19 ticks later")

func test_events_leave_the_window_after_a_full_wrap() -> void:
	m.advance()
	m.record_delivery(100)
	run_ticks(1200)              # a full wrap back onto that bucket
	assert_eq(m.deliveries(), 0, "the bucket was cleared on the way past")

func test_a_window_wrapped_more_than_once_holds_only_recent_events() -> void:
	for i in range(3000):
		m.advance()
		if i % 100 == 0:
			m.record_delivery(100)
	# 3000 ticks in, only the last ~1200 ticks of events remain: i = 1900,
	# 2000 ... 2900 is at most 12 of them.
	assert_between(m.deliveries(), 1, 12,
		"a wrapped window must not accumulate forever")

func test_negative_wait_is_floored_at_zero() -> void:
	m.advance()
	m.record_delivery(-5)
	assert_almost_eq(m.average_wait_seconds(), 0.0, 1e-9)

func test_format_wait_renders_a_dash_when_there_is_no_data() -> void:
	# The first thing a new player sees. Never "0", never "nan".
	assert_eq(Metrics.format_wait(-1.0), "—")

func test_format_wait_renders_whole_seconds() -> void:
	assert_eq(Metrics.format_wait(12.4), "12s")
	assert_eq(Metrics.format_wait(0.0), "0s")

func test_format_rate_renders_a_plain_count() -> void:
	assert_eq(Metrics.format_rate(0), "0")
	assert_eq(Metrics.format_rate(18), "18")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_metrics.gd -gexit
```

Expected: FAIL — `Identifier "Metrics" not declared`.

- [ ] **Step 3: Write the implementation**

Create `sim/metrics.gd`:

```gdscript
class_name Metrics
extends RefCounted

## A rolling window of recent service quality, in 60 one-second buckets.
##
## The window is SECOND-ALIGNED, not exactly 60 seconds: it holds 1200 ticks
## only at the instant before a rollover and 1181 just after, so a rate reads up
## to 1.58% low, oscillating once a second. Per-tick buckets would buy exactness
## nobody can perceive at 60x the storage.
##
## Metrics owns its own tick counter and never reads SimClock: note_ticks() runs
## LAST in GameState._tick_once, so ticks_executed lags this advance for the
## whole body of a tick, and deriving the bucket from it would file every event
## one bucket behind.

const BUCKET_TICKS := 20        # one simulated second at 0.05 s per tick
const BUCKETS := 60             # ~60 s of history

var _delivered: PackedInt32Array = PackedInt32Array()
var _wait_ticks: PackedInt64Array = PackedInt64Array()
var _expired: PackedInt32Array = PackedInt32Array()

var _tick: int = 0
var _index: int = 0

func _init() -> void:
	_delivered.resize(BUCKETS)
	_wait_ticks.resize(BUCKETS)
	_expired.resize(BUCKETS)

## FIRST in the tick order. Rolls into the next bucket and clears it before
## anything in this tick writes to it.
func advance() -> void:
	var next := (_tick / BUCKET_TICKS) % BUCKETS
	if next != _index:
		_index = next
		_delivered[_index] = 0
		_wait_ticks[_index] = 0
		_expired[_index] = 0
	_tick += 1

func record_delivery(waited_ticks: int) -> void:
	_delivered[_index] += 1
	_wait_ticks[_index] += maxi(waited_ticks, 0)

func record_expiry() -> void:
	_expired[_index] += 1

func deliveries() -> int:
	var n := 0
	for v in _delivered:
		n += v
	return n

func expiries() -> int:
	var n := 0
	for v in _expired:
		n += v
	return n

## Mean seconds a delivered passenger spent waiting. Returns -1.0 -- a sentinel,
## not a value -- when the window holds no deliveries, so the caller renders the
## no-data case instead of dividing by zero into NaN.
func average_wait_seconds() -> float:
	var d := deliveries()
	if d <= 0:
		return -1.0
	var total := 0
	for v in _wait_ticks:
		total += v
	return (float(total) / float(d)) * SimClock.TICK_SECONDS

## Pure formatting, kept in sim/ so the no-data rule is testable headlessly.
static func format_wait(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	return "%ds" % int(seconds)

static func format_rate(count: int) -> String:
	return str(count)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_metrics.gd -gexit
```

Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add sim/metrics.gd tests/test_metrics.gd
git commit -m "feat(sim): second-aligned rolling metrics window with a no-data sentinel"
```

---

## Task 3: Passenger.waited_ticks and the spawner's patience floor

**Files:**
- Modify: `sim/passenger.gd`, `sim/traffic_spawner.gd`
- Test: `tests/test_passenger.gd`, `tests/test_traffic_spawner.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Passenger.waited_ticks() -> int`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_passenger.gd`:

```gdscript
func test_waited_ticks_counts_time_spent_waiting() -> void:
	var p := make_p(0, 5, 900)
	p.decay(120)
	assert_eq(p.waited_ticks(), 120)

func test_waited_ticks_is_zero_for_a_fresh_passenger() -> void:
	assert_eq(make_p(0, 5, 900).waited_ticks(), 0)

func test_waited_ticks_at_the_zero_patience_boundary() -> void:
	# The passenger delivered on the tick it reaches 0 waited its whole patience.
	var p := make_p(0, 5, 900)
	p.decay(900)
	assert_eq(p.patience_ticks, 0)
	assert_eq(p.waited_ticks(), 900)

func test_waited_ticks_is_clamped_at_zero_for_nonpositive_patience() -> void:
	# _initial_patience is maxi(patience, 1), so a zero-patience passenger would
	# otherwise read one tick high. The contract is: meaningful for patience >= 1,
	# never negative, and pinned here rather than left to discovery.
	var p := make_p(0, 5, 0)
	assert_eq(p.waited_ticks(), 0, "not -1, and not 1")
	p.decay(3)
	assert_eq(p.waited_ticks(), 4, "documented: one high below the floor")
```

Append to `tests/test_traffic_spawner.gd`:

```gdscript
func test_patience_is_floored_at_one_tick() -> void:
	# waited_ticks()'s contract needs initial patience >= 1, and the curve file
	# is data. A zero in data must not silently break the metric.
	var f := FileAccess.open("user://zero_patience.json", FileAccess.WRITE)
	f.store_string('{"buckets":[5.0],"base_patience_ticks":0,"base_fare":4.0}')
	f.close()
	var s := TrafficSpawner.new(7)
	assert_true(s.load_curve("user://zero_patience.json"))
	assert_eq(s.base_patience_ticks, 1, "clamped, not zero")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_passenger.gd -gexit
```

Expected: FAIL — `Invalid call. Nonexistent function 'waited_ticks'`.

- [ ] **Step 3: Write the implementation**

In `sim/passenger.gd`, add after `patience_fraction()`:

```gdscript
## Ticks this passenger spent waiting on its floor. No new field is needed:
## patience decays only while waiting (GameState._expire) and is frozen once
## aboard, so at delivery this is exactly the wait.
##
## Meaningful for an initial patience of at least 1. Below that _initial_patience
## is clamped to 1 and this reads one tick high; the spawner floors the data so
## no production passenger can be in that state.
func waited_ticks() -> int:
	return maxi(_initial_patience - patience_ticks, 0)
```

In `sim/traffic_spawner.gd`, in `load_curve`, change:

```gdscript
	base_patience_ticks = int(parsed.get("base_patience_ticks", 900))
```

to:

```gdscript
	base_patience_ticks = maxi(int(parsed.get("base_patience_ticks", 900)), 1)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: PASS, all files.

- [ ] **Step 5: Commit**

```bash
git add sim/passenger.gd sim/traffic_spawner.gd tests/test_passenger.gd tests/test_traffic_spawner.gd
git commit -m "feat(sim): waited_ticks with a stated contract and a data-side patience floor"
```

---

## Task 4: Upgrades — one effect definition, and zero-delta refusal

**Files:**
- Modify: `sim/upgrades.gd`
- Test: `tests/test_upgrades.gd`

**Interfaces:**
- Consumes: `ElevatorCar`.
- Produces: `Upgrades.has_effect(id: String) -> bool`, `Upgrades.effect_value(id: String, level: int) -> float`, `Upgrades.is_zero_delta(id: String) -> bool`. `purchase()` now returns false for a zero-delta level.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_upgrades.gd`:

```gdscript
func test_effect_value_matches_what_the_car_gets() -> void:
	econ.accrue(1e9)
	up.purchase("doors", econ, b)
	assert_almost_eq(up.effect_value("doors", up.level_of("doors")),
		float(b.cars[0].door_ticks), 1e-9,
		"the query and the car must read one definition")

func test_effect_value_honours_the_door_floor() -> void:
	# The clamp is why the view may not duplicate the formula: without it the
	# annotation would read "doors 4 -> 2 ticks", a fabricated number.
	assert_almost_eq(up.effect_value("doors", 8), 4.0, 1e-9)
	assert_almost_eq(up.effect_value("doors", 12), 4.0, 1e-9)

func test_zero_delta_is_detected_at_the_door_floor() -> void:
	econ.accrue(1e12)
	for i in range(7):
		assert_true(up.purchase("doors", econ, b), "level %d" % i)
	assert_eq(up.level_of("doors"), 7)
	assert_false(up.is_zero_delta("doors"), "7 -> 8 still changes the value")
	assert_true(up.purchase("doors", econ, b))
	assert_eq(up.level_of("doors"), 8)
	assert_true(up.is_zero_delta("doors"), "8 -> 9 changes nothing")

func test_a_zero_delta_purchase_is_refused_by_the_sim() -> void:
	# Enforcing this only in the view is not enough: two taps queued during a
	# stalled frame would buy level 8 and then charge $832 for level 9.
	econ.accrue(1e12)
	for i in range(8):
		up.purchase("doors", econ, b)
	var cash_before := econ.cash
	assert_false(up.purchase("doors", econ, b), "refused")
	assert_almost_eq(econ.cash, cash_before, 1e-6, "and not charged")
	assert_eq(up.level_of("doors"), 8, "and not levelled")

func test_speed_and_capacity_never_saturate() -> void:
	assert_false(up.is_zero_delta("speed"))
	assert_false(up.is_zero_delta("capacity"))

func test_structural_upgrades_have_no_effect_value() -> void:
	assert_false(up.has_effect("shaft"))
	assert_false(up.has_effect("row"))
	assert_false(up.is_zero_delta("shaft"), "never blocks a structural purchase")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrades.gd -gexit
```

Expected: FAIL — `Nonexistent function 'effect_value'`.

- [ ] **Step 3: Write the implementation**

In `sim/upgrades.gd`, add these methods and rewrite `_sync_car` so there is one definition:

```gdscript
## The value each code-defined effect takes at a given level. THE definition --
## _sync_car reads it, and so does the view's annotation, so an annotation can
## never fabricate a number by duplicating the formula and dropping a clamp.
func effect_value(id: String, level: int) -> float:
	match id:
		"doors":
			return float(maxi(DOOR_TICKS_BASE - level * 2, DOOR_TICKS_MIN))
		"speed":
			return SPEED_BASE * (1.0 + 0.25 * float(level))
		"capacity":
			return float(CAPACITY_BASE + level)
		_:
			return 0.0

func has_effect(id: String) -> bool:
	return id == "doors" or id == "speed" or id == "capacity"

## True when the next level would change nothing. doors reaches DOOR_TICKS_MIN
## at level 8 while max_level is 12, so levels 8-11 would charge $7,226 for no
## effect. max_level stays 12 -- lowering DOOR_TICKS_MIN later should not force
## a re-tune of the cost curve -- so the refusal lives here.
func is_zero_delta(id: String) -> bool:
	if not has_effect(id):
		return false
	var lvl := level_of(id)
	return is_equal_approx(effect_value(id, lvl), effect_value(id, lvl + 1))

func _sync_car(car: ElevatorCar) -> void:
	car.door_ticks = int(effect_value("doors", level_of("doors")))
	car.rows_per_tick = effect_value("speed", level_of("speed"))
	car.capacity = int(effect_value("capacity", level_of("capacity")))
```

In `purchase()`, add the refusal immediately after the maxed check:

```gdscript
func purchase(id: String, econ: Economy, building: Building) -> bool:
	if not _defs.has(id) or is_maxed(id):
		return false
	if is_zero_delta(id):
		return false            # a level that changes nothing is not for sale
	var cost := cost_of(id)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrades.gd -gexit
```

Expected: PASS, 22 tests. `test_door_ticks_never_reach_zero` still passes — it buys 50 times and the refusal stops it at 8, which is still greater than zero.

- [ ] **Step 5: Commit**

```bash
git add sim/upgrades.gd tests/test_upgrades.gd
git commit -m "feat(sim): single effect definition and sim-side refusal of no-op levels"
```

---

## Task 5: GameState.relet — the first code path that charges for a lease

**Files:**
- Modify: `sim/game_state.gd`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: `Tenancy`, `Economy`.
- Produces: `GameState.relet(row: int) -> bool`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_game_state.gd`:

```gdscript
## Drives row 0 out of its lease and returns once it is vacant.
func vacate(state: GameState, row: int) -> void:
	while state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		state.tenancy.accrue_for_tick()

func test_relet_charges_the_cost() -> void:
	vacate(gs, 0)
	gs.economy.accrue(1000.0)
	var before := gs.economy.cash
	assert_true(gs.relet(0))
	assert_false(gs.tenancy.is_vacant(0))
	assert_almost_eq(gs.economy.cash, before - Tenancy.RELET_COST, 1e-6,
		"re-leasing has never actually charged before this")

func test_relet_is_free_when_nothing_is_tenanted() -> void:
	for row in range(gs.building.row_count):
		vacate(gs, row)
	assert_eq(gs.tenancy.tenanted_count(), 0)
	var before := gs.economy.cash
	assert_true(gs.relet(0), "the no-fail guarantee")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_relet_is_refused_when_unaffordable_and_charges_nothing() -> void:
	vacate(gs, 0)
	assert_lt(gs.economy.cash, Tenancy.RELET_COST)
	var before := gs.economy.cash
	assert_false(gs.relet(0))
	assert_true(gs.tenancy.is_vacant(0), "still vacant")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_relet_is_refused_on_a_tenanted_row() -> void:
	gs.economy.accrue(1000.0)
	var before := gs.economy.cash
	assert_false(gs.relet(2))
	assert_almost_eq(gs.economy.cash, before, 1e-6, "must not charge")

func test_relet_is_refused_outside_the_building() -> void:
	gs.economy.accrue(1000.0)
	assert_false(gs.relet(-1))
	assert_false(gs.relet(99))

func test_relet_reads_the_cost_before_reletting() -> void:
	# relet_cost is derived from tenanted_count, and relet() flips it. Reletting
	# first would turn the free last-row case into a $40 charge.
	var solo := GameState.new(1, 1, 5)
	vacate(solo, 0)
	var before := solo.economy.cash
	assert_true(solo.relet(0))
	assert_almost_eq(solo.economy.cash, before, 1e-6, "free, not $40")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit
```

Expected: FAIL — `Nonexistent function 'relet'`.

- [ ] **Step 3: Write the implementation**

In `sim/game_state.gd`, add after `buy()`:

```gdscript
## Re-lease a vacant floor. Until now nothing in the game charged for this:
## Tenancy.relet() restores a tenant without touching Economy and
## Tenancy.relet_cost() had no caller outside tests, so wiring the view straight
## to tenancy would have made re-leasing free forever -- hollowing out §5.3's
## guarantee, which is that re-leasing is free CONDITIONALLY.
##
## The cost is read BEFORE the relet: relet_cost derives from tenanted_count,
## and relet() increments it, so the order decides whether the last row costs
## nothing or forty dollars.
func relet(row: int) -> bool:
	if row < 0 or row >= building.row_count:
		return false
	if not tenancy.is_vacant(row):
		return false
	var cost := tenancy.relet_cost(row)
	if not economy.spend(cost):
		return false
	tenancy.relet(row)
	return true
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/game_state.gd tests/test_game_state.gd
git commit -m "feat(sim): relet command that actually charges the lease"
```

---

## Task 6: Wire Metrics into the tick order

**Files:**
- Modify: `sim/game_state.gd`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: `Metrics`, `Passenger.waited_ticks`.
- Produces: `GameState.metrics: Metrics`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_game_state.gd`:

```gdscript
func test_deliveries_reach_the_metrics_window() -> void:
	var car: ElevatorCar = gs.building.cars[0]
	car.rows_per_tick = 1.0
	car.door_ticks = 2
	gs.building.enqueue(Passenger.new(0, 2, 100000, 10.0))
	gs.dispatch(0, 0)
	gs.tick(1)
	gs.dispatch(0, 2)
	gs.tick(5)
	assert_eq(gs.metrics.deliveries(), 1)
	assert_gte(gs.metrics.average_wait_seconds(), 0.0, "a real wait was recorded")

func test_expiries_reach_the_metrics_window() -> void:
	gs.building.enqueue(Passenger.new(0, 1, 0, 10.0))
	gs.tick(2)
	assert_eq(gs.metrics.expiries(), 1)

func test_the_metrics_window_advances_with_the_sim() -> void:
	gs.building.enqueue(Passenger.new(0, 1, 0, 10.0))
	gs.tick(2)
	assert_eq(gs.metrics.expiries(), 1)
	gs.tick(SimClock.TICKS_PER_MINUTE + BUCKET_SLACK)
	assert_eq(gs.metrics.expiries(), 0, "it left the window")

const BUCKET_SLACK := 40   # one bucket either side of the boundary

func test_a_spawned_passenger_first_decays_on_the_next_tick() -> void:
	# Spec §8.3: "A passenger spawned on tick T first decays on tick T+1."
	# No test has ever pinned this, and the code decays on tick T because
	# _tick_once spawns and then expires within the same call.
	var p := Passenger.new(0, 1, 100, 1.0)
	gs.building.enqueue(p)
	gs.tick(1)
	assert_eq(p.patience_ticks, 99,
		"one tick of decay for one tick of waiting")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit
```

Expected: FAIL — `Invalid access to property 'metrics'`.

Note: `test_a_spawned_passenger_first_decays_on_the_next_tick` pins the *current* behaviour (decay on the enqueue tick is indistinguishable here because the passenger was enqueued before `tick()` was called). It exists so the boundary stops being unpinned; §9 of the spec records that the spec text and the code disagree about the spawn-tick case, which is a separate decision.

- [ ] **Step 3: Write the implementation**

In `sim/game_state.gd`:

```gdscript
var metrics: Metrics
```

In `_init`, after `upgrades.load_defs(...)`:

```gdscript
	metrics = Metrics.new()
```

Update the class docstring's order line and `_tick_once`:

```gdscript
##   advance metrics -> spawn -> move/doors -> deliver -> expire
##     -> accrue rent -> update combo
```

```gdscript
func _tick_once() -> void:
	metrics.advance()      # first: clears the bucket this tick will write into
	_spawn()
	_move_and_doors()
	_deliver()
	_expire()
	economy.accrue(tenancy.accrue_for_tick())
	clock.note_ticks(1)
```

In `_deliver`, record the delivery:

```gdscript
		for p in car.take_arrivals():
			var paid := economy.credit_delivery(p.fare)
			tenancy.note_delivery(p.destination_row)
			metrics.record_delivery(p.waited_ticks())
			passenger_delivered.emit(p, paid)
```

In `_expire`, record the expiry:

```gdscript
			if p.is_expired():
				economy.note_expiry()
				tenancy.note_expiry(p.origin_row)
				metrics.record_expiry()
				passenger_expired.emit(p)
```

- [ ] **Step 4: Run the full suite**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/game_state.gd tests/test_game_state.gd
git commit -m "feat(sim): metrics advance first in the written tick order"
```

---

## Task 7: Gesture speaks floors

**Files:**
- Modify: `sim/gesture.gd`
- Test: `tests/test_gesture.gd` (rewritten)

**Interfaces:**
- Consumes: `BoardCoords`.
- Produces: `Gesture.new(coords: BoardCoords)`; unchanged `press(y, car_floor)`, `move(y)`, `release()`, `selected_row()`, `is_dragging()`, `Gesture.DRAG_THRESHOLD`, `Gesture.Result`.

`selected_row()` now returns a **floor**, bottom-up.

- [ ] **Step 1: Rewrite the test**

Replace `tests/test_gesture.gd` entirely:

```gdscript
extends GutTest

## 40 floors in the 1184-unit board = 29.6 units per floor. Not 32: the board
## is 1184, not the full 1280, because the HUD takes 96.
const H := 29.6
const FLOORS := 40

var g: Gesture

func before_each() -> void:
	g = Gesture.new(BoardCoords.new(FLOORS, H))

## Column-local y of the centre of floor f's band, bottom-up.
func centre_of(f: int) -> float:
	return float(FLOORS - 1 - f) * H + H * 0.5

func test_threshold_is_under_half_a_row() -> void:
	# Half a row is 14.8 at the real board height, not the 16 the design spec
	# still says. Under it, or dispatching to the floor your thumb is on is
	# unreachable.
	assert_lt(Gesture.DRAG_THRESHOLD, H * 0.5)

func test_press_and_release_in_place_is_surge() -> void:
	g.press(centre_of(10), 10)
	assert_eq(g.release(), Gesture.Result.SURGE)

func test_tiny_wobble_is_still_surge() -> void:
	g.press(centre_of(10), 10)
	g.move(centre_of(10) + Gesture.DRAG_THRESHOLD - 0.1)
	assert_eq(g.release(), Gesture.Result.SURGE)

func test_crossing_the_threshold_becomes_a_drag() -> void:
	g.press(centre_of(10), 10)
	g.move(centre_of(10) + Gesture.DRAG_THRESHOLD + 0.1)
	assert_true(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.DISPATCH)

func test_the_board_is_bottom_up() -> void:
	# The top of the column is the TOP floor; the bottom is the lobby.
	g.press(centre_of(20), 20)
	g.move(0.0)
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), FLOORS - 1, "y=0 is the top floor")

	g.press(centre_of(20), 20)
	g.move(float(FLOORS) * H - 1.0)
	g.release()
	assert_eq(g.selected_row(), 0, "the bottom of the column is the lobby")

func test_mapping_is_absolute_not_relative() -> void:
	# Any floor is one short drag away. A relative mapping would need 39 rows of
	# travel to reach the top.
	g.press(centre_of(0), 0)
	g.move(centre_of(20))
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), 20)

func test_dispatch_to_the_floor_under_the_thumb_is_reachable() -> void:
	# From the band centre a minimal nudge in EITHER direction stays on the
	# floor, which is what the sub-half-row threshold buys.
	for direction in [1.0, -1.0]:
		g.press(centre_of(12), 12)
		g.move(centre_of(12) + direction * (Gesture.DRAG_THRESHOLD + 0.1))
		assert_eq(g.release(), Gesture.Result.DISPATCH)
		assert_eq(g.selected_row(), 12,
			"nudged %s" % ("down" if direction > 0.0 else "up"))

func test_selection_snaps_to_the_band_under_the_thumb() -> void:
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 1 - 7) * H + 1.0)        # just inside floor 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 7) * H - 1.0)            # last unit of floor 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 7) * H + 1.0)            # over into floor 6
	g.release()
	assert_eq(g.selected_row(), 6)

func test_horizontal_movement_is_ignored() -> void:
	# The pointer is captured on drag-start; only y is read.
	g.press(centre_of(0), 0)
	g.move(centre_of(10))
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), 10)

func test_dragging_past_the_top_cancels() -> void:
	g.press(centre_of(20), 20)
	g.move(-H)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_dragging_past_the_bottom_cancels() -> void:
	g.press(centre_of(20), 20)
	g.move(float(FLOORS) * H + H)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_the_lobbys_whole_band_dispatches_and_never_cancels() -> void:
	# The trap the viewport inset exists to avoid: with the ghost floor in the
	# column, the cancel edge fell inside the lobby's band -- the highest-traffic
	# target in the game -- and half of it silently cancelled.
	for floors in [6, 28, 29, 39, 40]:
		var h := 1184.0 / float(floors + (1 if floors < 40 else 0))
		var gg := Gesture.new(BoardCoords.new(floors, h))
		var top := float(floors - 1) * h
		for frac in [0.01, 0.25, 0.5, 0.75, 0.99]:
			gg.press(h * 0.5, floors - 1)
			gg.move(top + h * frac)
			assert_eq(gg.release(), Gesture.Result.DISPATCH,
				"N=%d, %.0f%% into the lobby's band" % [floors, frac * 100.0])
			assert_eq(gg.selected_row(), 0)

func test_returning_from_beyond_the_edge_still_dispatches() -> void:
	g.press(centre_of(20), 20)
	g.move(-H)
	g.move(centre_of(3))
	assert_eq(g.release(), Gesture.Result.DISPATCH, "cancel is judged at release")
	assert_eq(g.selected_row(), 3)

func test_release_without_press_is_none() -> void:
	assert_eq(g.release(), Gesture.Result.NONE)

func test_rail_starts_at_the_cars_floor() -> void:
	g.press(centre_of(4), 12)
	assert_eq(g.selected_row(), 12, "before any movement, the car's floor")

func test_a_second_press_resets_state() -> void:
	g.press(centre_of(0), 0)
	g.move(centre_of(10))
	g.release()
	g.press(centre_of(0), 3)
	assert_false(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.SURGE)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_gesture.gd -gexit
```

Expected: FAIL — `Gesture.new()` takes two arguments, and the bottom-up expectations do not hold.

- [ ] **Step 3: Write the implementation**

Replace the state and the two coordinate methods in `sim/gesture.gd`:

```gdscript
class_name Gesture
extends RefCounted

## Classifies a point stream on a shaft column into one verb.
##
## Verbs separate by GESTURE, never by tap cadence -- nothing here depends on
## double-tap timing, which also collides with mobile Safari's zoom heuristics.
##
## The mapping is ABSOLUTE: a detent is a floor's band on screen, so any floor
## is one short drag away. A relative mapping would make a lobby-to-top dispatch
## need 39 rows of travel on a board 40 rows tall.
##
## Screen y is converted to a FLOOR by BoardCoords -- the one definition of the
## bottom-up inversion. This class holds no coordinate arithmetic beyond the
## cancel edges.

enum Result { NONE, SURGE, DISPATCH, CANCELLED }

const DRAG_THRESHOLD := 12.0     # < 14.8, half a row at the 40-floor ceiling

var _coords: BoardCoords
var _active := false
var _dragging := false
var _press_y := 0.0
var _current_y := 0.0
var _selected_row := 0

func _init(coords: BoardCoords) -> void:
	_coords = coords

func press(y: float, car_floor: int) -> void:
	_active = true
	_dragging = false
	_press_y = y
	_current_y = y
	_selected_row = clampi(car_floor, 0, _coords.floor_count - 1)

func move(y: float) -> void:
	if not _active:
		return
	_current_y = y
	if absf(y - _press_y) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging and not _is_beyond_edge(y):
		_selected_row = _coords.y_to_floor(y)

func release() -> int:
	if not _active:
		return Result.NONE
	var out := Result.SURGE
	if _dragging:
		out = Result.CANCELLED if _is_beyond_edge(_current_y) else Result.DISPATCH
	_active = false
	_dragging = false
	return out

func selected_row() -> int:
	return _selected_row

func is_dragging() -> bool:
	return _dragging

## Cancel is a deliberate gesture: past the top or bottom of the column, with
## half a row of slop. The column spans exactly the floors -- the ghost band is
## outside it -- so this edge never falls inside the lobby's band.
##
## In practice only the top edge is reachable: the board's bottom is the bottom
## of the screen. The rule stays symmetric because asymmetry would be a special
## case with no benefit.
func _is_beyond_edge(y: float) -> bool:
	var h := _coords.row_height
	return y < -h * 0.5 or y > h * (float(_coords.floor_count) + 0.5)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_gesture.gd -gexit
```

Expected: PASS, 17 tests. Other suites will fail to parse until Task 10 updates `ShaftColumn`; that is expected and fixed there.

- [ ] **Step 5: Commit**

```bash
git add sim/gesture.gd tests/test_gesture.gd
git commit -m "feat(sim): gesture returns floors via BoardCoords, bottom-up"
```

---

## Task 8: FloorRow — regions, the three-state bar, and the crowd tier

**Files:**
- Modify: `view/floor_row.gd`

**Interfaces:**
- Consumes: `Passenger`, `PassengerSprite`.
- Produces: `FloorRow.GUTTER_WIDTH` (`64.0`), `FloorRow.STRIP_WIDTH` (`176.0`), `FloorRow.SPRITE_PITCH` (`14.0`), `FloorRow.MAX_INDIVIDUALS` (`12`), `FloorRow.VACANT_MAX_INDIVIDUALS` (`10`), `FloorRow.CROWD_BAR_BELOW` (`40.0`); methods `set_row(index: int)`, `set_waiting(passengers: Array)`, `set_tenant(satisfaction: float, vacant: bool, moving_out: bool, ticks_left: int, relet_price: String)`.

There is no tenant status *text*: the bar carries all three states. A vacant floor shows its re-lease price instead.

- [ ] **Step 1: Replace the file**

Replace `view/floor_row.gd` entirely:

```gdscript
class_name FloorRow
extends Control

## One floor of the board, in four fixed regions:
##
##   [count] [tenant bar] [floor no.] | people strip | (shafts, drawn above)
##
## The waiting count is leftmost and never moves. It is the number a dispatch
## decision is made on, so it cannot shift with the shaft count, and it cannot
## sit unlabelled beside the floor number where the two read as one value.
##
## There is no tenant status TEXT. The 4-unit bar carries all three states --
## satisfaction, a draining move-out countdown, and vacancy. Text in the gutter
## overlapped the floor number at the capped 29.6-unit row; text in the strip
## overlapped the sprites, and vacant floors still spawn passengers, so the two
## co-occur. In the dense tier it would sit on the crowd bar, whose LENGTH is
## the encoding.

const MAX_INDIVIDUALS := 12
const VACANT_MAX_INDIVIDUALS := 10      # leaves room for the re-lease price
const SPRITE_PITCH := 14.0
const CROWD_BAR_BELOW := 40.0           # row height at or under which sprites collapse

const GUTTER_WIDTH := 64.0
const STRIP_WIDTH := 176.0
const COUNT_WIDTH := 26.0
const BAR_X := 30.0
const BAR_W := 4.0
const LABEL_X := 38.0
const SPRITE_X := GUTTER_WIDTH + 4.0

const GREEN := Color("4ade80")
const RED := Color("ef4444")
const GREY := Color("3f3f46")

var row_index: int = 0

var _label: Label
var _count: Label
var _price: Label
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _crowd: ColorRect
var _sprites: Array[PassengerSprite] = []

func _ready() -> void:
	var rule := ColorRect.new()
	rule.color = Color("232c38")
	rule.size = Vector2(size.x, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.position = Vector2(0, 2)
	_count.size = Vector2(COUNT_WIDTH, 18)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)

	_bar_track = ColorRect.new()
	_bar_track.color = Color("1b2430")
	_bar_track.position = Vector2(BAR_X, 1)
	_bar_track.size = Vector2(BAR_W, size.y - 1)
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_track)

	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(BAR_X, 1)
	_bar_fill.size = Vector2(BAR_W, size.y - 1)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_fill)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("7c8899"))
	_label.position = Vector2(LABEL_X, 3)
	add_child(_label)

	_crowd = ColorRect.new()
	_crowd.visible = false
	_crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crowd)

	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 11)
	_price.add_theme_color_override("font_color", GREEN)
	_price.size = Vector2(40, 16)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_price.position = Vector2(GUTTER_WIDTH + STRIP_WIDTH - 40.0, (size.y - 16.0) * 0.5)
	_price.visible = false
	add_child(_price)

func set_row(index: int) -> void:
	row_index = index
	_label.text = str(index)

## Individual sprites while the row is tall enough to tell them apart; below
## CROWD_BAR_BELOW they collapse into one bar whose length is the crowd and
## whose colour is the WORST patience on the floor. The count is never affected
## and is always exact.
func set_waiting(passengers: Array) -> void:
	var total: int = passengers.size()
	_count.text = "" if total <= 0 else str(total)

	var cap: int = VACANT_MAX_INDIVIDUALS if _price.visible else MAX_INDIVIDUALS
	if size.y <= CROWD_BAR_BELOW:
		_hide_sprites()
		_draw_crowd_bar(total, cap)
		return

	_crowd.visible = false
	var shown: int = mini(total, cap)
	while _sprites.size() < shown:
		var s := PassengerSprite.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(
				SPRITE_X + float(i) * SPRITE_PITCH,
				(size.y - _sprites[i].size.y) * 0.5)
			_sprites[i].show_for(p.patience_fraction())
		else:
			_sprites[i].recycle()

func _hide_sprites() -> void:
	for s in _sprites:
		s.recycle()

func _draw_crowd_bar(total: int, cap: int) -> void:
	if total <= 0:
		_crowd.visible = false
		return
	var worst := 1.0
	_crowd.visible = true
	_crowd.color = RED.lerp(GREEN, clampf(worst, 0.0, 1.0))
	var span := float(cap) * SPRITE_PITCH
	var fraction := clampf(float(total) / float(cap), 0.0, 1.0)
	_crowd.position = Vector2(SPRITE_X, (size.y - 9.0) * 0.5)
	_crowd.size = Vector2(maxf(span * fraction, 3.0), 9.0)

## Called with the worst remaining patience on the floor so the crowd bar can
## colour itself; separate from set_waiting so the caller does the min once.
func set_crowd_colour(worst_fraction: float) -> void:
	_crowd.color = RED.lerp(GREEN, clampf(worst_fraction, 0.0, 1.0))

## Three states in one 4-unit bar.
##   tenanted   -- filled proportional to satisfaction, red->green
##   moving out -- red, the fill DRAINING over the countdown, so the bar is the
##                 countdown rather than labelling one
##   vacant     -- solid grey, and the re-lease price shows in the strip
func set_tenant(satisfaction: float, vacant: bool, moving_out: bool,
		ticks_left: int, relet_price: String) -> void:
	var full := size.y - 1.0
	if vacant:
		_bar_fill.color = GREY
		_bar_fill.position = Vector2(BAR_X, 1)
		_bar_fill.size = Vector2(BAR_W, full)
		_price.text = relet_price
		_price.visible = true
		return

	_price.visible = false
	var fraction := clampf(satisfaction, 0.0, 1.0)
	if moving_out:
		_bar_fill.color = RED
		fraction = clampf(float(ticks_left) / float(Tenancy.MOVE_OUT_TICKS), 0.0, 1.0)
	else:
		_bar_fill.color = RED.lerp(GREEN, fraction)
	var height := maxf(full * fraction, 1.0)
	_bar_fill.size = Vector2(BAR_W, height)
	_bar_fill.position = Vector2(BAR_X, 1.0 + (full - height))
```

- [ ] **Step 2: Import and check it parses**

```bash
godot --headless --import 2>&1 | grep -i "error" | head
```

Expected: no output. (Runtime verification comes in Task 11.)

- [ ] **Step 3: Commit**

```bash
git add view/floor_row.gd
git commit -m "feat(view): four fixed row regions and a three-state tenant bar"
```

---

## Task 9: BuildingView — bottom-up, inset, ghost floor and ghost shaft

**Files:**
- Modify: `view/building_view.gd`

**Interfaces:**
- Consumes: `BoardCoords`, `FloorRow`, `ShaftColumn`, `GameState`.
- Produces: `BuildingView.bind(state)`, `rebuild()`, `refresh()`, `visible_shafts() -> int`, `max_scroll() -> int`, `first_visible_shaft() -> int`, `scroll_by(n)`, `scroll_to_end()`, `coords() -> BoardCoords`; signals `floor_purchase_requested()`, `shaft_purchase_requested()`, `relet_requested(floor: int)`.

- [ ] **Step 1: Replace the file**

Replace `view/building_view.gd` entirely:

```gdscript
class_name BuildingView
extends Control

## Renders the sim and routes input back as explicit commands. Owns no
## coordinate arithmetic: every floor<->y conversion goes through BoardCoords.
##
## Frames: BoardCoords is COLUMN-LOCAL (y=0 is the top floor). This view works
## in the BOARD frame, which is offset downward by the ghost band --
## board_y = ghost_height + local_y. A naive use of the local transform here
## draws the top floor inside the ghost band and leaves the bottom band empty.

signal floor_purchase_requested()
signal shaft_purchase_requested()
signal relet_requested(floor_index: int)

const SHAFT_AREA_X := FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH   # 240
const SHAFT_WIDTH := 96.0        # pitch; columns draw at 92 = 50.2pt
const RELET_SPAN := SHAFT_AREA_X # the vacant-floor tap reaches the whole gutter+strip

var _state: GameState
var _coords: BoardCoords
var _ghost_height: float = 0.0
var _scroll_index: int = 0

var _shaft_viewport: Control
var _ghost_row: Control
var _columns: Array[ShaftColumn] = []
var _slots: Array[Control] = []
var _rows: Array[FloorRow] = []

func coords() -> BoardCoords:
	return _coords

func bind(state: GameState) -> void:
	_state = state
	_shaft_viewport = Control.new()
	_shaft_viewport.clip_contents = true
	add_child(_shaft_viewport)
	_build_all()

func rebuild() -> void:
	for c in _shaft_viewport.get_children():
		c.queue_free()
	for r in _rows:
		r.queue_free()
	if _ghost_row != null:
		_ghost_row.queue_free()
		_ghost_row = null
	_columns.clear()
	_slots.clear()
	_rows.clear()
	_build_all()
	move_child(_shaft_viewport, get_child_count() - 1)

func _build_all() -> void:
	var floors := _state.building.row_count
	var ghost := 1 if floors < Building.MAX_ROWS else 0
	var h := size.y / float(floors + ghost)
	_ghost_height = h * float(ghost)
	_coords = BoardCoords.new(floors, h)

	_build_rows()
	if ghost == 1:
		_build_ghost_floor()

	# The viewport spans the FLOORS only. That frees the ghost band for its own
	# tap and keeps Gesture's cancel edge off the lobby's band.
	_shaft_viewport.position = Vector2(SHAFT_AREA_X, _ghost_height)
	_shaft_viewport.size = Vector2(size.x - SHAFT_AREA_X, size.y - _ghost_height)
	_build_slots()
	_build_columns()

func _build_rows() -> void:
	for i in range(_state.building.row_count):
		var row := FloorRow.new()
		row.position = Vector2(0, _ghost_height + _coords.floor_to_y(i))
		row.size = Vector2(size.x, _coords.row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.set_row(i)
		_rows.append(row)

## A full-height empty row above the top floor. A row, not a button, so the next
## floor is always visibly there; at the cap the term simply leaves the divisor.
func _build_ghost_floor() -> void:
	_ghost_row = Control.new()
	_ghost_row.position = Vector2.ZERO
	_ghost_row.size = Vector2(size.x, _ghost_height)
	add_child(_ghost_row)

	var bg := ColorRect.new()
	bg.color = Color("141a21")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_row.add_child(bg)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.position = Vector2(FloorRow.LABEL_X, (_ghost_height - 20.0) * 0.5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_row.add_child(label)
	_ghost_label = label

	_ghost_row.gui_input.connect(_on_ghost_input)

var _ghost_label: Label

func _on_ghost_input(event: InputEvent) -> void:
	if _is_tap(event):
		floor_purchase_requested.emit()

## All five visible positions draw a placeholder so the early board reads as
## room to grow. Only the TRAILING one -- index `owned` -- is priced and takes
## the tap; the rest are inert and visually flatter.
func _build_slots() -> void:
	var owned := _state.building.cars.size()
	for i in range(visible_shafts()):
		var slot := Control.new()
		slot.size = Vector2(SHAFT_WIDTH - 4.0, _shaft_viewport.size.y)
		_shaft_viewport.add_child(slot)

		var bg := ColorRect.new()
		bg.color = Color("151b23")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.position = Vector2(6, 8)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)

		slot.set_meta("label", label)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slots.append(slot)
	_position_slots(owned)

func _position_slots(owned: int) -> void:
	var buyable := owned if owned < Building.MAX_SHAFTS else -1
	for i in range(_slots.size()):
		var index := _scroll_index + i
		var slot := _slots[i]
		slot.position = Vector2(float(i) * SHAFT_WIDTH, 0)
		var label: Label = slot.get_meta("label")
		if index == buyable:
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			label.text = "+ SHAFT\n$%s" % NumberFormat.compact(
				_state.upgrades.cost_of("shaft"))
			label.add_theme_color_override("font_color",
				Color("4ade80") if _state.economy.can_afford(
					_state.upgrades.cost_of("shaft")) else Color("4a5563"))
			if not slot.gui_input.is_connected(_on_slot_input):
				slot.gui_input.connect(_on_slot_input)
		else:
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = ""
			if slot.gui_input.is_connected(_on_slot_input):
				slot.gui_input.disconnect(_on_slot_input)

func _on_slot_input(event: InputEvent) -> void:
	if _is_tap(event):
		shaft_purchase_requested.emit()

func _build_columns() -> void:
	for i in range(_state.building.cars.size()):
		var col := ShaftColumn.new()
		col.size = Vector2(SHAFT_WIDTH - 4.0, _shaft_viewport.size.y)
		_shaft_viewport.add_child(col)
		var index := i
		col.setup(index, _coords,
			func() -> int: return _state.building.cars[index].current_row())
		col.dispatch_requested.connect(_on_dispatch)
		col.surge_requested.connect(_on_surge)
		_columns.append(col)
	_scroll_index = clampi(_scroll_index, 0, max_scroll())
	_position_columns()

## Paged-out columns are HIDDEN, not merely clipped. Godot's documentation says
## a clipped child receives no input either, but that was never verified on 4.7
## and hiding costs nothing.
func _position_columns() -> void:
	var last := _scroll_index + visible_shafts()
	for i in range(_columns.size()):
		_columns[i].position = Vector2(float(i - _scroll_index) * SHAFT_WIDTH, 0)
		_columns[i].visible = i >= _scroll_index and i < last
	_position_slots(_state.building.cars.size())

func visible_shafts() -> int:
	return maxi(int((size.x - SHAFT_AREA_X) / SHAFT_WIDTH), 1)

## Counts the trailing ghost slot, so the eighth shaft is reachable. Without it,
## five owned shafts fill all five visible positions and shafts 6-8 are dead.
func slot_count() -> int:
	return mini(_state.building.cars.size() + 1, Building.MAX_SHAFTS)

func max_scroll() -> int:
	return maxi(slot_count() - visible_shafts(), 0)

func first_visible_shaft() -> int:
	return _scroll_index

func scroll_by(delta: int) -> void:
	_scroll_index = clampi(_scroll_index + delta, 0, max_scroll())
	_position_columns()

func scroll_to_end() -> void:
	_scroll_index = max_scroll()
	_position_columns()

func _on_dispatch(shaft_index: int, floor_index: int) -> void:
	_state.dispatch(shaft_index, floor_index)

func _on_surge(_shaft_index: int) -> void:
	# Surge is Milestone 3+; the verb is wired so the input model is complete.
	pass

## A vacant floor's whole gutter-plus-strip span is the re-lease target. The
## 26-unit gutter alone is ~16pt tall at the cap, far under the touch floor, and
## the confirm (ui/relet_confirm.gd) exists for the same reason.
func _gui_input(event: InputEvent) -> void:
	if not _is_tap(event):
		return
	var local: Vector2 = event.position
	if local.x >= RELET_SPAN or local.y < _ghost_height:
		return
	var floor_index := _coords.y_to_floor(local.y - _ghost_height)
	if _state.tenancy.is_vacant(floor_index):
		relet_requested.emit(floor_index)

func _is_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not event.pressed
	if event is InputEventMouseButton:
		return not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false

func refresh() -> void:
	if _state == null:
		return
	for i in range(_columns.size()):
		_columns[i].set_car_position(_state.building.cars[i].position_row)
	for i in range(_rows.size()):
		var waiting := _state.building.waiting_at(i)
		var vacant := _state.tenancy.is_vacant(i)
		var price := "FREE" if _state.tenancy.relet_cost(i) <= 0.0 \
			else "$" + NumberFormat.compact(_state.tenancy.relet_cost(i))
		_rows[i].set_tenant(
			_state.tenancy.satisfaction_at(i), vacant,
			_state.tenancy.is_moving_out(i),
			_state.tenancy.move_out_ticks_left(i), price)
		_rows[i].set_waiting(waiting)
		_rows[i].set_crowd_colour(_worst_patience(waiting))
	if _ghost_label != null:
		var cost := _state.upgrades.cost_of("row")
		_ghost_label.text = "+ BUILD FLOOR  $%s" % NumberFormat.compact(cost)
		_ghost_label.add_theme_color_override("font_color",
			Color("4ade80") if _state.economy.can_afford(cost) else Color("4a5563"))
	_position_slots(_state.building.cars.size())

func _worst_patience(waiting: Array) -> float:
	var worst := 1.0
	for p in waiting:
		worst = minf(worst, p.patience_fraction())
	return worst
```

- [ ] **Step 2: Import and check it parses**

```bash
godot --headless --import 2>&1 | grep -i "error" | head
```

Expected: errors about `ShaftColumn.setup()` taking different arguments — fixed in Task 10.

- [ ] **Step 3: Commit**

```bash
git add view/building_view.gd
git commit -m "feat(view): bottom-up board, inset viewport, ghost floor and ghost shaft"
```

---

## Task 10: ShaftColumn and FloorSelector through the transform

**Files:**
- Modify: `view/shaft_column.gd`, `view/floor_selector.gd`

**Interfaces:**
- Consumes: `BoardCoords`, `Gesture`.
- Produces: `ShaftColumn.setup(index: int, coords: BoardCoords, car_floor_provider: Callable)`, `ShaftColumn.set_car_position(position_row: float)`; `FloorSelector.configure(coords: BoardCoords)`, `FloorSelector.show_at(floor_index: int)`, `FloorSelector.hide_rail()`.

- [ ] **Step 1: Replace `view/shaft_column.gd`**

```gdscript
class_name ShaftColumn
extends Control

## The touch target -- full column height, never the car. Verbs separate by
## gesture: drag = dispatch, tap = surge.
##
## The column spans the FLOORS only; the ghost band is above it and belongs to
## the floor-purchase target. That inset is what keeps Gesture's cancel edge
## from falling inside the lobby's dispatch band.

signal dispatch_requested(shaft_index: int, floor_index: int)
signal surge_requested(shaft_index: int)

var shaft_index: int = 0

var _gesture: Gesture
var _coords: BoardCoords
var _selector: FloorSelector
var _car_rect: ColorRect
var _car_floor_provider: Callable

func setup(index: int, coords: BoardCoords, car_floor_provider: Callable) -> void:
	shaft_index = index
	_coords = coords
	_car_floor_provider = car_floor_provider
	_gesture = Gesture.new(coords)

	var shaft_bg := ColorRect.new()
	shaft_bg.color = Color("1b2430")
	shaft_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	shaft_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shaft_bg)

	_car_rect = ColorRect.new()
	_car_rect.color = Color("4cc2ff")
	_car_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_car_rect)

	_selector = FloorSelector.new()
	_selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_selector)
	_selector.configure(coords)

## position_row is FRACTIONAL -- a car mid-trip sits at 2.4 -- so this uses the
## continuous car_y rather than the integer floor mapping. Coercing to an int
## would make a moving car jump between floors instead of gliding.
func set_car_position(position_row: float) -> void:
	_car_rect.position = Vector2(3, _coords.car_y(position_row) + 2.0)
	_car_rect.size = Vector2(size.x - 6.0, _coords.row_height - 4.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var local_y: float = event.position.y
		if pressed:
			_gesture.press(local_y, _car_floor_provider.call())
			_selector.show_at(_gesture.selected_row())
		else:
			var result := _gesture.release()
			_selector.hide_rail()
			match result:
				Gesture.Result.DISPATCH:
					dispatch_requested.emit(shaft_index, _gesture.selected_row())
				Gesture.Result.SURGE:
					surge_requested.emit(shaft_index)
				_:
					pass
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		_gesture.move(event.position.y)
		if _gesture.is_dragging():
			_selector.show_at(_gesture.selected_row())
```

- [ ] **Step 2: Replace `view/floor_selector.gd`**

```gdscript
class_name FloorSelector
extends Control

## The drag rail. The marker covers the selected floor's whole band -- exactly
## the band the classifier selects -- so the highlight can never disagree with
## what releasing dispatches.
##
## The bubble normally sits ABOVE the thumb so the finger does not occlude the
## choice. For the top two bands there is no room above: the viewport is inset
## to the floors and clips, so the bubble flips below the marker instead.

const BUBBLE_OFFSET := 46.0

var _coords: BoardCoords
var _bubble: Label
var _marker: ColorRect

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_marker = ColorRect.new()
	_marker.color = Color("4cc2ff", 0.35)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)

	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 34)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)

func configure(coords: BoardCoords) -> void:
	_coords = coords

func show_at(floor_index: int) -> void:
	visible = true
	var y := _coords.floor_to_y(floor_index)
	_marker.position = Vector2(0, y)
	_marker.size = Vector2(size.x, _coords.row_height)
	_bubble.text = str(floor_index)
	var above := y - BUBBLE_OFFSET
	_bubble.position = Vector2(4, above if above >= 0.0 \
		else y + _coords.row_height + 2.0)

func hide_rail() -> void:
	visible = false
```

- [ ] **Step 3: Import and verify the project parses cleanly**

```bash
godot --headless --import 2>&1 | grep -i "error" | head
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: no parse errors; the headless suite passes.

- [ ] **Step 4: Commit**

```bash
git add view/shaft_column.gd view/floor_selector.gd
git commit -m "feat(view): car and rail through the transform; continuous car_y"
```

---

## Task 11: The scene-driving input harness

**Files:**
- Create: `tests/test_board_input.gd`

**Interfaces:**
- Consumes: the whole board.
- Produces: nothing other tasks consume.

This harness does not exist today. `tests/` holds only headless unit tests of `sim/` classes; the "paging regression" cited in earlier drafts was a throwaway probe that survives as a sentence in a commit message. These behaviours cannot be reached any other way — a screenshot cannot catch a mirrored board, because the mirror is self-consistent.

- [ ] **Step 1: Write the harness and its tests**

Create `tests/test_board_input.gd`:

```gdscript
extends GutTest

## Drives the real scene with synthetic input. GUT provides a scene tree, so the
## board can be instantiated, sized, and touched exactly as a thumb would.

const ROOT := preload("res://game/game_root.tscn")

var root: Control
var view: BuildingView

func before_each() -> void:
	root = ROOT.instantiate()
	root.size = Vector2(720, 1280)
	add_child_autofree(root)
	await wait_frames(2)
	view = root._view

func after_each() -> void:
	root = null
	view = null

## Board-frame y of the centre of a floor's band.
func floor_centre_y(f: int) -> float:
	return root.HUD_HEIGHT + view._ghost_height + view.coords().band_centre_y(f)

func column_x(slot: int) -> float:
	return BuildingView.SHAFT_AREA_X + float(slot) * BuildingView.SHAFT_WIDTH + 40.0

func press_at(x: float, y: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(x, y)
	e.global_position = e.position
	Input.parse_input_event(e)

func release_at(x: float, y: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = Vector2(x, y)
	e.global_position = e.position
	Input.parse_input_event(e)

func drag_to(x: float, y: float) -> void:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(x, y)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)

func do_drag(x: float, from_y: float, to_y: float) -> void:
	press_at(x, from_y)
	await wait_frames(2)
	drag_to(x, to_y)
	await wait_frames(2)
	release_at(x, to_y)
	await wait_frames(2)

func do_tap(x: float, y: float) -> void:
	press_at(x, y)
	await wait_frames(2)
	release_at(x, y)
	await wait_frames(2)

# --- the mirrored-board check ---------------------------------------------

func test_a_drag_onto_a_floors_band_dispatches_to_that_floor() -> void:
	# THE check. A mirrored board is self-consistent across gesture, rail and
	# car, so it passes casual play and every screenshot; only this catches it.
	for target in [0, 2, 5]:
		await do_drag(column_x(0), floor_centre_y(1), floor_centre_y(target))
		assert_eq(root.state.building.cars[0].target_row, target,
			"drag onto floor %d's band" % target)

func test_the_car_renders_at_the_floor_it_is_on() -> void:
	# The car and the label must agree; they are the two surfaces that mirror
	# together.
	root.state.building.cars[0].position_row = 0.0
	view.refresh()
	var car_y: float = view._columns[0]._car_rect.position.y
	var lobby_y: float = view.coords().floor_to_y(0)
	assert_almost_eq(car_y, lobby_y + 2.0, 0.01,
		"the car at floor 0 draws in the lobby's band")

func test_the_rail_marker_agrees_with_the_selected_floor() -> void:
	press_at(column_x(0), floor_centre_y(1))
	await wait_frames(2)
	drag_to(column_x(0), floor_centre_y(4))
	await wait_frames(2)
	var marker_y: float = view._columns[0]._selector._marker.position.y
	assert_almost_eq(marker_y, view.coords().floor_to_y(4), 0.01)
	release_at(column_x(0), floor_centre_y(4))
	await wait_frames(2)

# --- purchases -------------------------------------------------------------

func test_a_tap_in_the_ghost_band_buys_a_floor() -> void:
	root.state.economy.accrue(1e6)
	var before := root.state.building.row_count
	await do_tap(400.0, root.HUD_HEIGHT + view._ghost_height * 0.5)
	assert_eq(root.state.building.row_count, before + 1,
		"the ghost band is tappable at x=400, where the columns used to be")

func test_a_tap_in_the_ghost_band_does_not_surge() -> void:
	root.state.economy.accrue(1e6)
	var before := root.state.building.cars[0].target_row
	await do_tap(400.0, root.HUD_HEIGHT + view._ghost_height * 0.5)
	assert_eq(root.state.building.cars[0].target_row, before,
		"a floor purchase is not a dispatch")

func test_every_shaft_up_to_the_cap_is_reachable() -> void:
	# With five visible slots and no ghost slot, five owned shafts fill every
	# position and shafts 6-8 are unbuyable forever.
	root.state.economy.accrue(1e12)
	for owned in range(1, Building.MAX_SHAFTS):
		var slot_index := owned - view.first_visible_shaft()
		if slot_index >= view.visible_shafts():
			view.scroll_to_end()
			await wait_frames(2)
			slot_index = owned - view.first_visible_shaft()
		assert_between(slot_index, 0, view.visible_shafts() - 1,
			"a buyable slot must be on screen at owned=%d" % owned)
		await do_tap(column_x(slot_index), floor_centre_y(1))
		await wait_frames(2)
		assert_eq(root.state.building.cars.size(), owned + 1,
			"bought shaft %d" % (owned + 1))
	assert_eq(root.state.building.cars.size(), Building.MAX_SHAFTS)

func test_a_tap_on_a_non_trailing_placeholder_does_nothing() -> void:
	root.state.economy.accrue(1e12)
	var before := root.state.building.cars.size()
	await do_tap(column_x(view.visible_shafts() - 1), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before,
		"only the trailing slot is buyable")

# --- paging ----------------------------------------------------------------

func test_a_paged_out_column_cannot_be_touched_through_the_people_strip() -> void:
	root.state.economy.accrue(1e12)
	for i in range(6):
		root.state.buy("shaft")
	view.rebuild()
	view.scroll_to_end()
	await wait_frames(2)
	var targets := []
	for c in root.state.building.cars:
		targets.append(c.target_row)
	await do_drag(120.0, floor_centre_y(4), floor_centre_y(1))
	for i in range(root.state.building.cars.size()):
		assert_eq(root.state.building.cars[i].target_row, targets[i],
			"shaft %d must not move" % i)

func test_the_leftmost_visible_column_commands_its_own_shaft() -> void:
	root.state.economy.accrue(1e12)
	for i in range(6):
		root.state.buy("shaft")
	view.rebuild()
	view.scroll_to_end()
	await wait_frames(2)
	var first := view.first_visible_shaft()
	assert_gt(first, 0, "the strip must actually be paged for this to mean anything")
	await do_drag(column_x(0), floor_centre_y(4), floor_centre_y(2))
	assert_eq(root.state.building.cars[first].target_row, 2)
	assert_ne(root.state.building.cars[0].target_row, 2,
		"shaft 0 is off screen and must not have moved")

# --- re-lease --------------------------------------------------------------

func vacate(row: int) -> void:
	while root.state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		root.state.tenancy.accrue_for_tick()
	view.refresh()

func test_a_tap_on_a_vacant_floors_gutter_opens_the_confirm() -> void:
	vacate(2)
	await do_tap(100.0, floor_centre_y(2))
	assert_true(root._relet_confirm.visible, "the confirm is shown")
	assert_eq(root._relet_confirm.floor_index, 2)

func test_a_tap_past_the_strip_reaches_the_column_not_the_confirm() -> void:
	vacate(2)
	await do_tap(300.0, floor_centre_y(2))
	assert_false(root._relet_confirm.visible,
		"x=300 is the shaft viewport, not the re-lease span")

func test_a_tap_on_a_tenanted_floor_does_nothing() -> void:
	await do_tap(100.0, floor_centre_y(3))
	assert_false(root._relet_confirm.visible)
```

- [ ] **Step 2: Run it**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_input.gd -gexit
```

Expected: **five** tests fail, not three. The three re-lease tests fail because
`_relet_confirm` does not exist until Task 13, and the two purchase tests
(`..._buys_a_floor`, `..._up_to_the_cap_is_reachable`) fail because the old
`game_root.gd` never connects `floor_purchase_requested` or
`shaft_purchase_requested` — Task 14 does. The ghost row and the trailing slot
*do* receive their events here; nothing is listening yet.

Every other test must PASS. If a dispatch test fails, the board is mirrored and
Task 9 or 10 is wrong; fix it before continuing.

**Two environment facts this harness had to be built around**, both of which
make the naive version pass vacuously — a synthetic tap that misses and a tap
on nothing are indistinguishable from the sim's side:

- `game_root.tscn` anchors full-rect, so it resizes to GUT's parent (2000x2560)
  *before* `_ready` lays the board out. Pin `PRESET_TOP_LEFT` and set the size
  explicitly, or the board under test is 18 shafts wide with 352-unit rows.
- The headless window is 0x0, which makes the root viewport's final transform a
  **0.05 scale**. `Input.parse_input_event` and `push_input(event)` both apply
  its inverse, multiplying every coordinate by twenty. Inject with
  `push_input(event, true)` — viewport-local — which skips the transform.

- [ ] **Step 3: Commit**

```bash
git add tests/test_board_input.gd
git commit -m "test: scene-driving harness for the input behaviours screenshots cannot catch"
```

---

## Task 12: ManagementView replaces the upgrade sheet

**Files:**
- Create: `ui/management_view.gd`
- Delete: `ui/upgrade_panel.gd`

**Interfaces:**
- Consumes: `GameState`, `Metrics`, `NumberFormat`.
- Produces: `ManagementView.bind(state: GameState)`, `ManagementView.refresh()`.

- [ ] **Step 1: Write the view**

Create `ui/management_view.gd`:

```gdscript
class_name ManagementView
extends Control

## One scrolling surface: a live readout, then a list under headings. No tabs --
## a second navigation layer inside a view you already navigated to, solving a
## length problem this list does not have yet.
##
## Every dynamic string goes through Label, never RichTextLabel with bbcode:
## upgrade levels come from a user:// save at Milestone 6, on a github.io origin
## shared with every other Pages site on the account (see main.gd).

const BUTTON_HEIGHT := 88.0       # 48pt at the 0.546 iPhone scale
const MARGIN := 12.0

var _state: GameState
var _rows: Dictionary = {}        # id -> {button, effect_label}
var _riders: Label
var _wait: Label
var _gaveup: Label

func bind(state: GameState) -> void:
	_state = state

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_build_readout())
	box.add_child(_heading("SPEND"))
	for id in _state.upgrades.ids():
		if id == "shaft" or id == "row":
			continue          # bought on the board, where they appear
		box.add_child(_build_upgrade_row(id))
	refresh()

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("5b6675"))
	l.custom_minimum_size = Vector2(0, 28)
	return l

func _build_readout() -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	_riders = _stat(row, "riders / min")
	_wait = _stat(row, "avg wait")
	_gaveup = _stat(row, "gave up")
	return panel

func _stat(parent: Control, caption: String) -> Label:
	var col := VBoxContainer.new()
	parent.add_child(col)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 22)
	col.add_child(value)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color("5b6675"))
	col.add_child(cap)
	return value

func _build_upgrade_row(id: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	var captured := id
	b.pressed.connect(func() -> void: _state.buy(captured))
	_rows[id] = b
	return b

## Annotations state MECHANICAL effects read from Upgrades -- never a predicted
## metric, and never a formula copied into the view. Duplicating
## maxi(20 - 2*level, 4) and dropping the clamp would render "doors 4 -> 2".
func refresh() -> void:
	if _state == null:
		return
	var m := _state.metrics
	_riders.text = Metrics.format_rate(m.deliveries())
	_wait.text = Metrics.format_wait(m.average_wait_seconds())
	_gaveup.text = Metrics.format_rate(m.expiries())

	for id in _rows.keys():
		var b: Button = _rows[id]
		var name := _state.upgrades.name_of(id)
		var lvl := _state.upgrades.level_of(id)
		if _state.upgrades.is_maxed(id):
			b.text = "%s  MAX (Lv%d)" % [name, lvl]
			b.disabled = true
			continue
		if _state.upgrades.is_zero_delta(id):
			b.text = "%s  Lv%d\n%s (max effect)" % [name, lvl, _effect_text(id, lvl, lvl)]
			b.disabled = true
			continue
		var cost := _state.upgrades.cost_of(id)
		b.text = "%s  Lv%d      $%s\n%s" % [
			name, lvl, NumberFormat.compact(cost), _effect_text(id, lvl, lvl + 1)]
		b.disabled = not _state.economy.can_afford(cost)

func _effect_text(id: String, from_level: int, to_level: int) -> String:
	var a := _state.upgrades.effect_value(id, from_level)
	var b := _state.upgrades.effect_value(id, to_level)
	match id:
		"doors":
			return "doors %d → %d ticks" % [int(a), int(b)]
		"speed":
			return "speed %.2f → %.2f rows/tick" % [a, b]
		"capacity":
			return "capacity %d → %d" % [int(a), int(b)]
		_:
			return ""
```

- [ ] **Step 2: Delete the old panel**

```bash
git rm ui/upgrade_panel.gd ui/upgrade_panel.gd.uid
```

- [ ] **Step 3: Import and check it parses**

```bash
godot --headless --import 2>&1 | grep -i "error" | head
```

Expected: errors from `game/game_root.gd` still referencing `UpgradePanel` — fixed in Task 14.

- [ ] **Step 4: Commit**

```bash
git add ui/management_view.gd
git commit -m "feat(ui): management view led by live metrics, annotations from one definition"
```

---

## Task 13: The re-lease confirm

**Files:**
- Create: `ui/relet_confirm.gd`

**Interfaces:**
- Consumes: `GameState`, `NumberFormat`.
- Produces: `ReletConfirm.bind(state: GameState)`, `ReletConfirm.open_for(floor_index: int)`, `ReletConfirm.close()`, property `floor_index: int`; signal `confirmed(floor_index: int)`.

- [ ] **Step 1: Write it**

Create `ui/relet_confirm.gd`:

```gdscript
class_name ReletConfirm
extends Control

## The single confirmed action in the game.
##
## Every other purchase is a bare tap, because its target meets the 44pt floor
## and the price is on the target. A floor row cannot: at the 40-floor cap it is
## 29.6 units -- 16.16pt -- so a vertical miss onto an adjacent ALSO-VACANT floor
## would spend $40 on the wrong one. Naming the floor in the prompt is what makes
## that mistake recoverable.

signal confirmed(floor_index: int)

const BUTTON_HEIGHT := 88.0

var floor_index: int = -1

var _state: GameState
var _title: Label
var _confirm: Button

func bind(state: GameState) -> void:
	_state = state
	visible = false

	var bg := ColorRect.new()
	bg.color = Color("161c24")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = -16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_confirm = Button.new()
	_confirm.text = "RE-LEASE"
	_confirm.add_theme_font_size_override("font_size", 20)
	_confirm.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_confirm.pressed.connect(_on_confirm)
	box.add_child(_confirm)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	cancel.pressed.connect(close)
	box.add_child(cancel)

func open_for(p_floor_index: int) -> void:
	floor_index = p_floor_index
	var cost := _state.tenancy.relet_cost(floor_index)
	var price := "free" if cost <= 0.0 else "$" + NumberFormat.compact(cost)
	_title.text = "Re-lease floor %d — %s" % [floor_index, price]
	_confirm.disabled = not _state.economy.can_afford(cost)
	visible = true

func close() -> void:
	visible = false
	floor_index = -1

func _on_confirm() -> void:
	var target := floor_index
	close()
	if _state.relet(target):
		confirmed.emit(target)
```

- [ ] **Step 2: Import and check it parses**

```bash
godot --headless --import 2>&1 | grep -i "error" | head
```

Expected: only the `game_root.gd` errors from Task 12.

- [ ] **Step 3: Commit**

```bash
git add ui/relet_confirm.gd
git commit -m "feat(ui): re-lease confirm, the one target that cannot meet 44pt"
```

---

## Task 14: game_root — two views, the pager, and a debug board

**Files:**
- Modify: `game/game_root.gd`

**Interfaces:**
- Consumes: everything above.
- Produces: `game_root.state`, `game_root.HUD_HEIGHT`, `game_root._view`, `game_root._relet_confirm` (read by the harness).

- [ ] **Step 1: Replace the file**

Replace `game/game_root.gd` entirely:

```gdscript
extends Control

## Owns the sim and pumps it. Physics stays at Godot's default 60 Hz and the
## clock accumulates to 20 Hz -- one tick per callback would run the sim 3x fast.
##
## Two views, one button. It reads MANAGE on the board and BOARD in management;
## never CLOSE, because a view is not a sheet. The sim runs in both.

const START_ROWS := 6
const START_SHAFTS := 1
const START_SEED := 20260802

const HUD_HEIGHT := 96.0
const TOUCH_MIN := 88.0

var state: GameState
var _view: BuildingView
var _management: ManagementView
var _relet_confirm: ReletConfirm
var _cash_label: Label
var _rate_label: Label
var _view_button: Button
var _prev_shaft: Button
var _next_shaft: Button
var _pager_label: Label
var _last_shape := Vector2i.ZERO

func _ready() -> void:
	var rows := START_ROWS
	var shafts := START_SHAFTS
	var override := _debug_board_override()
	if override != Vector2i.ZERO:
		rows = override.x
		shafts = override.y
	state = GameState.new(rows, shafts, START_SEED)
	if shafts > 1:
		# GameState builds one car per requested shaft; keep upgrades in step so
		# the pager and the ghost slot see the same count.
		pass

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 28)
	_cash_label.position = Vector2(16, 10)
	add_child(_cash_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.position = Vector2(16, 48)
	add_child(_rate_label)

	_view = BuildingView.new()
	_view.position = Vector2(0, HUD_HEIGHT)
	_view.size = Vector2(size.x, size.y - HUD_HEIGHT)
	add_child(_view)
	_view.bind(state)
	_view.floor_purchase_requested.connect(func() -> void: state.buy("row"))
	_view.shaft_purchase_requested.connect(_on_buy_shaft)
	_view.relet_requested.connect(_on_relet_requested)

	_management = ManagementView.new()
	_management.position = Vector2(0, HUD_HEIGHT)
	_management.size = Vector2(size.x, size.y - HUD_HEIGHT)
	_management.visible = false
	add_child(_management)
	_management.bind(state)

	_relet_confirm = ReletConfirm.new()
	_relet_confirm.size = Vector2(size.x - 80.0, 260.0)
	_relet_confirm.position = Vector2(40.0, size.y * 0.5 - 130.0)
	add_child(_relet_confirm)
	_relet_confirm.bind(state)

	_prev_shaft = _pager_button("<", 236.0, func() -> void: _view.scroll_by(-1))
	_next_shaft = _pager_button(">", 420.0, func() -> void: _view.scroll_by(1))

	_pager_label = Label.new()
	_pager_label.add_theme_font_size_override("font_size", 14)
	_pager_label.add_theme_color_override("font_color", Color("7c8899"))
	_pager_label.position = Vector2(328, 38)
	_pager_label.size = Vector2(88, 20)
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pager_label)

	_view_button = Button.new()
	_view_button.text = "MANAGE"
	_view_button.add_theme_font_size_override("font_size", 20)
	_view_button.size = Vector2(200, TOUCH_MIN)
	_view_button.position = Vector2(size.x - 208, 4)
	_view_button.pressed.connect(_on_toggle_view)
	add_child(_view_button)

	_last_shape = Vector2i(state.building.row_count, state.building.cars.size())
	_refresh_pager()

## Screenshot and device testing need boards that cost 1.36e8 to reach by play.
## This is a command-line override, NOT an edit to START_ROWS: an unreverted
## edit would ship every new player a forty-floor building.
##   godot -- --board=40x8
func _debug_board_override() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--board="):
			continue
		var spec := arg.substr("--board=".length()).split("x")
		if spec.size() != 2:
			continue
		return Vector2i(
			clampi(int(spec[0]), 1, Building.MAX_ROWS),
			clampi(int(spec[1]), 1, Building.MAX_SHAFTS))
	return Vector2i.ZERO

func _pager_button(label: String, x: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 24)
	b.size = Vector2(TOUCH_MIN, TOUCH_MIN)
	b.position = Vector2(x, 4)
	b.pressed.connect(on_press)
	b.pressed.connect(_refresh_pager)
	add_child(b)
	return b

func _on_buy_shaft() -> void:
	if state.buy("shaft"):
		_view.scroll_to_end()

func _on_relet_requested(floor_index: int) -> void:
	_relet_confirm.open_for(floor_index)

func _on_toggle_view() -> void:
	var showing_board := _management.visible
	_management.visible = not showing_board
	_view.visible = showing_board
	_view_button.text = "BOARD" if _management.visible else "MANAGE"
	var pageable := not _management.visible and _view.max_scroll() > 0
	_prev_shaft.visible = pageable
	_next_shaft.visible = pageable
	_pager_label.visible = pageable

## Hidden entirely while every slot -- including the trailing ghost -- fits.
## The label counts shafts, not slots, so the ghost is excluded from its totals.
func _refresh_pager() -> void:
	if _management.visible:
		return
	var total := state.building.cars.size()
	var pageable := _view.max_scroll() > 0
	_prev_shaft.visible = pageable
	_next_shaft.visible = pageable
	_pager_label.visible = pageable
	if not pageable:
		return
	var first := _view.first_visible_shaft()
	var last := mini(first + _view.visible_shafts(), total)
	_prev_shaft.disabled = first <= 0
	_next_shaft.disabled = first >= _view.max_scroll()
	_pager_label.text = "shafts %d-%d of %d" % [first + 1, maxi(last, first + 1), total]

func _physics_process(delta: float) -> void:
	var ticks := state.clock.take_ticks(delta)
	if ticks > 0:
		state.tick(ticks)

	var shape := Vector2i(state.building.row_count, state.building.cars.size())
	if shape != _last_shape:
		_view.rebuild()
		if shape.y > _last_shape.y:
			_view.scroll_to_end()
		_last_shape = shape
		_refresh_pager()

	if _management.visible:
		_management.refresh()
	else:
		_view.refresh()

	_cash_label.text = "$" + NumberFormat.compact(state.economy.cash)
	var rent := 0.0
	for row in range(state.building.row_count):
		rent += state.tenancy.rent_at(row)
	_rate_label.text = "%s/min   combo %.2fx" % [
		NumberFormat.compact(rent), state.economy.combo]
```

- [ ] **Step 2: Run the full suite**

```bash
godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: PASS, every file including `test_board_input.gd`.

- [ ] **Step 3: Verify the board at all four corners of the matrix**

```bash
for spec in 6x1 6x8 40x1 40x8; do
  godot --headless --quit-after 120 -- --board=$spec 2>&1 | grep -viE "^\[|DONE|Godot Engine" | head -3
  echo "--- $spec clean ---"
done
```

Expected: no script errors for any of the four.

Then capture screenshots at 6, 28, 29 and 40 floors (28 and 29 are the two sides of the density tier and must be compared as a pair), and at 1 and 8 shafts, using the same `--board=` override with a windowed run.

- [ ] **Step 4: Commit**

```bash
git add game/game_root.gd
git commit -m "feat(game): two views, ghost-slot-aware pager, --board debug override"
```

---

## Task 15: Reconcile the design spec

**Files:**
- Modify: `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md`, `sim/building.gd`

The UI spec's §9 lists edits the older design spec needs. Making them keeps the two documents from disagreeing about board geometry.

- [ ] **Step 1: Fix the row-height arithmetic in §2.1**

The spec says a row at the 40-floor ceiling is "exactly 32 units… roughly 17.5 pt" and the drag threshold must be "strictly under 16 units". The board is 1184, not 1280, so replace with: a capped row is **29.6 units / 16.16 pt**, and the threshold bound is **strictly under 14.8 units**. `DRAG_THRESHOLD = 12.0` still satisfies it with 2.8 units of margin.

- [ ] **Step 2: Fix the same bound in §13**

"drag threshold (strictly under 16 units, §2.1)" → "strictly under 14.8 units, §2.1".

- [ ] **Step 3: Retire the 8.9-columns derivation in §3 and in code**

§3 derives the 8-shaft cap from "720/80.6 = 8.9 columns fit edge-to-edge". The strip pages now, so the cap is a design choice rather than a consequence. Say so, and make the same edit to the docstring at the top of `sim/building.gd`.

- [ ] **Step 4: Update §8.2's file list**

`ui/` names `upgrade_panel`; replace with `management_view, relet_confirm`. `sim/` has no `metrics` or `coords`; add both.

- [ ] **Step 5: Correct §8.3's false claim**

"A passenger spawned on tick T first decays on tick T+1. Both boundaries are pinned by test." No test pinned either boundary before this plan. Task 6 adds one; update the sentence to name what is actually pinned, and record that `_tick_once` spawns and expires within the same call.

- [ ] **Step 6: Re-baseline §8.5's node budget**

The crowd bar's trigger is now row height, not crowd size, so sprites and bars are mutually exclusive and the sprite tier caps at 28 floors. The passenger term falls from `40x12x3 = 1,440` to `28x12x3 = 1,008`, and the peak subtotal is **~1,124 at 28 floors** against the stated 1,672 — a ~33% drop. Update the table and the "measured on the target iPhone" note.

- [ ] **Step 7: Run the suite and commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add docs/superpowers/specs/2026-08-01-elevator-incremental-design.md sim/building.gd
git commit -m "docs: reconcile the design spec with the 1184-unit board"
```

---

## Self-Review

**Spec coverage:**

| UI spec section | Task |
| --- | --- |
| §2 two views, MANAGE/BOARD, sheet removed | 14 |
| §3.1 geometry, bottom-up, viewport inset | 1, 9 |
| §3.2 one transform, four consumers, two frames, edge table | 1, 7, 9, 10 |
| §3.3 four regions, three-state bar, vacant price, 92/50.2pt | 8 |
| §3.4 ghost floor, ghost shaft, inert placeholders | 9, 11 |
| §3.5 density tiers, crowd bar replaces §8.5's trigger | 8, 15 |
| §3.6 paging, hidden not clipped, label counts shafts | 9, 14 |
| §4.1 verb table | 9, 10, 11, 14 |
| §4.2 cancel edges, ghost band | 7 |
| §4.3 re-lease confirm | 13, 11 |
| §5 Management, Label-only, one surface | 12 |
| §5.1 readout, `—` at zero, second-aligned window | 2, 12 |
| §5.2 annotations from the query, zero-delta refusal | 4, 12 |
| §6 coords, metrics, waited_ticks, relet, effect query | 1–6 |
| §7 code impact | all |
| §8 verification, 1–16 | 1–6, 11, 14 |
| §9 spec deltas and edits | 15 |

Every §8 verification item maps to a test: 1→Task 2; 2→Task 2 (`format_wait`); 3→Task 3; 4→Task 1; 5→Task 7 (`test_the_lobbys_whole_band_dispatches_and_never_cancels`); 6→Task 5; 7→Task 1 arithmetic plus Task 8's `CROWD_BAR_BELOW`; 8→Task 4; 9→Task 6; 10, 11→Task 11; 12→Task 11; 13→Task 7 (unit-level, since the harness cannot press outside a control); 14→Task 11; 15→Task 11; 16→Task 11.

**Placeholder scan:** no TBD/TODO. Every code step contains runnable GDScript; every test step contains real assertions with expected values. The one prose-only task is 15, which edits prose.

**Type consistency:** `BoardCoords` is constructed as `(floor_count, row_height)` in Tasks 1, 7, 9 and 11. `Gesture.new(coords)` is one argument in Tasks 7 and 10. `ShaftColumn.setup(index, coords, provider)` matches between Tasks 9 and 10. `FloorSelector.configure(coords)` matches Tasks 10. `FloorRow.set_tenant(satisfaction, vacant, moving_out, ticks_left, relet_price)` is five arguments in Tasks 8 and 9. `Metrics.format_wait/format_rate` are statics used in Tasks 2 and 12. `Upgrades.effect_value(id, level)` matches Tasks 4 and 12. `GameState.relet(row) -> bool` matches Tasks 5, 13. `BuildingView.coords()` is used by Task 11.

**Known rough edge:** Task 14's `_debug_board_override` starts `GameState` with N shafts, but `Upgrades.level_of("shaft")` stays 0, so the ghost slot prices the *first* shaft upgrade rather than the next one. Harmless for screenshots — which is all the override is for — and Task 11's reachability test starts from the shipped one-shaft board, so it is unaffected.
