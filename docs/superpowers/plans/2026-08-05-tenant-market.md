# Tenant Market Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tenants arrive by market draw instead of player choice: vacant tower floors auto-fill after 30 s with a class-weighted random kind, and upgrading an occupied floor prices its tenant out.

**Architecture:** New `sim/market.gd` (RefCounted, own seeded rng) owns per-floor fill countdowns and the weighted draw; `Tenancy` gains an uncancellable "priced out" move-out; `GameState` pumps the market right after tenancy's vacate step and restricts `lease()` to the basement. The FloorPanel picker survives only for basement floors (parking).

**Tech Stack:** Godot 4.7 GDScript, GUT 9.7.1. Spec: `docs/superpowers/specs/2026-08-05-tenant-market-design.md`.

## Global Constraints

- Sim layer: `extends RefCounted`, **no Nodes, no FileAccess, no scene tree**.
- The tick order is fixed and written: `metrics.advance → spawn → move/doors → deliver → auto-dispatch → expire → tenancy → market → note_ticks` (this plan inserts `market`).
- Market rng must NOT be the spawner's rng — one extra draw shifts the whole traffic sequence.
- Save stays **v4**; new per-floor fields are optional with defaults; save-derived values **clamp, never refuse**.
- Run tests: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/<file>.gd -gexit` (single file; `-gdir` takes a directory only — `-gdir=<file>` exits 0 with "Nothing was run", a false green).
- Full suite before finishing: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.

---

### Task 1: Market module

**Files:**
- Create: `sim/market.gd`
- Test: `tests/test_market.gd`

**Interfaces:**
- Consumes: `Tenancy.is_vacant/lease`, `Fitout.tier_at`, `TenantCatalog.available_for_class(tier, TenantKind.Where.TOWER)`, `TenantKind.requires_class/entrance/id`.
- Produces: `Market.new(p_seed: int)`, `Market.FILL_TICKS := 600`, `step(tenancy, fitout, catalog, floor_count) -> void`, `draw_kind(tier: int, catalog: TenantCatalog) -> String`, `fill_ticks_left(floor_index: int) -> int`, `restore_floor(floor_index: int, ticks: int) -> void`. Tasks 3–5 rely on these exact names.

**Semantics (pinned by the tests below):**
- `step()` scans tower floors `0..floor_count-1` each tick. A vacant floor with no countdown gets one at `FILL_TICKS` (no decrement that tick); on later ticks it decrements; at 0 the market draws a kind and calls `tenancy.lease(floor, id)` (which sets satisfaction 1.0 and clears the clock). So a floor fills **exactly `FILL_TICKS` ticks after first sighting**. A floor that is no longer vacant has any stale countdown erased — the scan self-heals, which is also what makes a save missing the field harmless.
- Draw pool: `available_for_class(tier, TOWER)` minus entrance kinds. Weight `= 3.0 ^ (requires_class - 1)`. Empty pool → return `""`; `step()` then resets the countdown instead of drawing every tick.
- rng: own `RandomNumberGenerator`, `seed = p_seed + SEED_OFFSET` (`SEED_OFFSET := 7919`).

- [ ] **Step 1: Write the failing tests** — `tests/test_market.gd`:

```gdscript
extends GutTest

const SEED := 12345

var tenancy: Tenancy
var fitout: Fitout
var catalog: TenantCatalog
var market: Market

func before_each() -> void:
	var index := FloorIndex.new(0, 6)
	tenancy = Tenancy.new(index, 6)
	fitout = Fitout.new(index)
	catalog = TenantCatalog.new()
	assert_true(catalog.load_from("res://data/tenants.json"))
	market = Market.new(SEED)

func _vacate(floor_index: int) -> void:
	tenancy.restore_floor(floor_index, 1.0, true, 0)

func _step() -> void:
	market.step(tenancy, fitout, catalog, 6)

func test_a_vacant_floor_fills_exactly_fill_ticks_after_first_sighting() -> void:
	_vacate(3)
	_step()
	assert_eq(market.fill_ticks_left(3), Market.FILL_TICKS, "sighting tick arms the clock")
	for i in range(Market.FILL_TICKS - 1):
		_step()
	assert_true(tenancy.is_vacant(3), "one tick early is still vacant")
	_step()
	assert_false(tenancy.is_vacant(3))
	assert_ne(tenancy.kind_at(3), "")
	assert_eq(market.fill_ticks_left(3), 0)

func test_a_filled_floor_arrives_content() -> void:
	_vacate(3)
	_step()
	for i in range(Market.FILL_TICKS):
		_step()
	assert_almost_eq(tenancy.satisfaction_at(3), 1.0, 1e-9)
	assert_false(tenancy.is_moving_out(3))

func test_a_tenanted_floor_never_gets_a_countdown() -> void:
	_step()
	for f in range(6):
		assert_eq(market.fill_ticks_left(f), 0)

func test_a_floor_tenanted_by_other_means_drops_its_countdown() -> void:
	_vacate(3)
	_step()
	tenancy.lease(3, "shops")
	_step()
	assert_eq(market.fill_ticks_left(3), 0, "the scan self-heals")

func test_the_draw_respects_the_floors_class() -> void:
	for i in range(200):
		var k := catalog.kind(market.draw_kind(1, catalog))
		assert_eq(k.requires_class, 1)

func test_the_draw_leans_toward_the_top_tier() -> void:
	var top := 0
	for i in range(300):
		if catalog.kind(market.draw_kind(3, catalog)).requires_class == 3:
			top += 1
	# weights 9/9/3/3/1/1 -> expected ~69%. Seeded, so the count is run-stable.
	assert_between(top, 150, 260)

func test_basement_kinds_never_appear_in_a_tower_draw() -> void:
	for i in range(200):
		assert_ne(market.draw_kind(3, catalog), "parking")

func test_same_seed_same_sequence() -> void:
	var a := Market.new(SEED)
	var b := Market.new(SEED)
	for i in range(20):
		assert_eq(a.draw_kind(3, catalog), b.draw_kind(3, catalog))

func test_the_tier_is_read_at_fill_time_not_vacancy_time() -> void:
	var above_one := 0
	for trial in range(20):
		var index := FloorIndex.new(0, 6)
		tenancy = Tenancy.new(index, 6)
		fitout = Fitout.new(index)
		market = Market.new(SEED + trial)
		_vacate(3)
		_step()                       # countdown armed while the floor is class 1
		fitout.set_tier(3, 3)         # upgraded mid-countdown
		for i in range(Market.FILL_TICKS):
			_step()
		if catalog.kind(tenancy.kind_at(3)).requires_class > 1:
			above_one += 1
	assert_gt(above_one, 0, "a mid-countdown upgrade improves the pending draw")

func test_restore_floor_resumes_a_partial_countdown() -> void:
	_vacate(3)
	market.restore_floor(3, 5)
	for i in range(4):
		_step()
	assert_true(tenancy.is_vacant(3))
	_step()
	assert_false(tenancy.is_vacant(3))
```

- [ ] **Step 2: Run to verify failure** — `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_market.gd -gexit`. Expected: parse/failure on `Market` not found.

- [ ] **Step 3: Implement `sim/market.gd`:**

```gdscript
class_name Market
extends RefCounted

## Who moves in is the MARKET's decision, not the player's. The player's
## levers are encourage (class upgrades weight the draw) and unlock (buying
## floors); the lease picker is gone. See the 2026-08-05 tenant-market spec.
##
## Owns per-floor fill countdowns and the weighted draw, nothing else:
## Tenancy keeps who-is-where, satisfaction and move-outs, and the market
## writes arrivals through tenancy.lease(). No cash changes hands at move-in
## -- refilling for free is what replaced the old free-below-two-tenants
## no-fail guarantee, and it is the stronger one.

## Half of Tenancy.MOVE_OUT_TICKS: 30 s of vacancy before someone moves in.
const FILL_TICKS := 600
## Added to the run seed. The market must NOT share the spawner's rng: the
## spawner draws once per tick and one extra draw would shift the whole
## traffic sequence.
const SEED_OFFSET := 7919
## weight = base ^ (requires_class - 1): a class 3 floor draws ~69% tier 3
## against the shipped catalog. The lever for how often an upgrade "wastes".
const TIER_WEIGHT_BASE := 3.0

var _rng := RandomNumberGenerator.new()
## floor_index -> ticks until move-in. Keyed by FLOOR, not slot: digging
## shifts slots but never renumbers floors, so this survives a dig untouched.
var _fill_left: Dictionary = {}

func _init(p_seed: int) -> void:
	_rng.seed = p_seed + SEED_OFFSET

## Scans TOWER floors only -- the basement (parking) stays a deliberate
## purchase. A vacant floor's first sighting arms the clock at FILL_TICKS and
## does not decrement it, so a fill lands exactly FILL_TICKS ticks later. A
## floor found occupied drops any stale countdown: the scan self-heals, which
## is also why a save missing the countdown field merely restarts the clock.
func step(tenancy: Tenancy, fitout: Fitout, catalog: TenantCatalog,
		floor_count: int) -> void:
	for floor_index in range(floor_count):
		if not tenancy.is_vacant(floor_index):
			_fill_left.erase(floor_index)
			continue
		if not _fill_left.has(floor_index):
			_fill_left[floor_index] = FILL_TICKS
			continue
		_fill_left[floor_index] -= 1
		if _fill_left[floor_index] <= 0:
			var id := draw_kind(fitout.tier_at(floor_index), catalog)
			if id.is_empty():
				_fill_left[floor_index] = FILL_TICKS
				continue
			tenancy.lease(floor_index, id)
			_fill_left.erase(floor_index)

## The tier is the caller's CURRENT tier -- read at fill time, so upgrading a
## vacant floor mid-countdown improves the pending draw.
func draw_kind(tier: int, catalog: TenantCatalog) -> String:
	var pool: Array[TenantKind] = []
	for k in catalog.available_for_class(tier, TenantKind.Where.TOWER):
		if not k.entrance:
			pool.append(k)
	var total := 0.0
	for k in pool:
		total += pow(TIER_WEIGHT_BASE, k.requires_class - 1)
	if total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for k in pool:
		roll -= pow(TIER_WEIGHT_BASE, k.requires_class - 1)
		if roll <= 0.0:
			return k.id
	return pool[pool.size() - 1].id

func fill_ticks_left(floor_index: int) -> int:
	return _fill_left.get(floor_index, 0)

## Resumes a saved countdown. Zero or negative means "no countdown", matching
## the encode side; step() re-arms a vacant floor on its next sighting anyway.
func restore_floor(floor_index: int, ticks: int) -> void:
	if ticks > 0:
		_fill_left[floor_index] = clampi(ticks, 1, FILL_TICKS)
```

- [ ] **Step 4: Run to verify pass** — same command. Expected: all test_market tests PASS.
- [ ] **Step 5: Commit** — `git add sim/market.gd sim/market.gd.uid tests/test_market.gd tests/test_market.gd.uid && git commit -m "Draw tenants from a market instead of a menu"`. (The `.uid` files appear after the editor/headless import; if absent, commit without them and fold them into the next commit.)

---

### Task 2: Priced-out move-outs in Tenancy

**Files:**
- Modify: `sim/tenancy.gd`
- Test: `tests/test_tenancy.gd`

**Interfaces:**
- Produces: `Tenancy.begin_move_out(floor_index: int) -> void`, `Tenancy.is_priced_out(floor_index: int) -> bool`, and `restore_floor(floor_index, satisfaction, vacant, move_out_left, kind := "", priced_out := false)`. Tasks 3–4 rely on these.

**Why a flag:** `note_delivery` cancels a move-out the moment satisfaction sits above the threshold — and a priced-out tenant's satisfaction is high, so without a flag the first delivery would cancel the eviction.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_tenancy.gd`:

```gdscript
func test_pricing_out_starts_the_move_out_clock() -> void:
	t.begin_move_out(0)
	assert_true(t.is_moving_out(0))
	assert_eq(t.move_out_ticks_left(0), Tenancy.MOVE_OUT_TICKS)

func test_a_priced_out_move_out_cannot_be_cancelled_by_good_service() -> void:
	t.begin_move_out(0)
	for i in range(100):
		t.note_delivery(0)
	assert_true(t.is_moving_out(0), "good service does not lower the rent")
	for i in range(Tenancy.MOVE_OUT_TICKS):
		t.accrue_for_tick()
	assert_true(t.is_vacant(0))

func test_pricing_out_a_floor_already_moving_out_keeps_its_clock() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(100):
		t.accrue_for_tick()
	var left := t.move_out_ticks_left(0)
	t.begin_move_out(0)
	assert_eq(t.move_out_ticks_left(0), left, "no clock reset")
	assert_true(t.is_priced_out(0), "but the eviction is now uncancellable")

func test_pricing_out_a_vacant_floor_does_nothing() -> void:
	t.restore_floor(0, 1.0, true, 0)
	t.begin_move_out(0)
	assert_false(t.is_moving_out(0))
	assert_false(t.is_priced_out(0))

func test_vacating_clears_the_priced_out_flag_and_a_new_tenant_starts_clean() -> void:
	t.begin_move_out(0)
	for i in range(Tenancy.MOVE_OUT_TICKS):
		t.accrue_for_tick()
	assert_false(t.is_priced_out(0))
	t.lease(0, "shops")
	assert_false(t.is_priced_out(0))

func test_restore_floor_round_trips_the_priced_out_flag() -> void:
	t.restore_floor(0, 1.0, false, 600, "shops", true)
	assert_true(t.is_priced_out(0))
	for i in range(50):
		t.note_delivery(0)
	assert_true(t.is_moving_out(0), "a reloaded eviction stays uncancellable")
	t.restore_floor(1, 1.0, true, 0, "", true)
	assert_false(t.is_priced_out(1), "a vacant floor cannot be priced out")
```

- [ ] **Step 2: Run to verify failure** — `-gtest=res://tests/test_tenancy.gd`. Expected: FAIL on missing `begin_move_out`.
- [ ] **Step 3: Implement in `sim/tenancy.gd`:**
  - Field: `var _priced_out: Array[bool] = []`. Append `false` in `_append_floor()`; `insert(0, false)` in `dig()`.
  - `restore_floor` gains trailing param `priced_out := false`; body adds `_priced_out[_index.slot(floor_index)] = priced_out and not vacant`.
  - `note_delivery`: the clock-cancel line becomes conditional:
    ```gdscript
    if _satisfaction[_index.slot(floor_index)] > MOVE_OUT_THRESHOLD \
    		and not _priced_out[_index.slot(floor_index)]:
    	_move_out_left[_index.slot(floor_index)] = 0
    ```
  - `accrue_for_tick`: inside the vacate branch, add `_priced_out[slot] = false`.
  - `lease()`: add `_priced_out[_index.slot(floor_index)] = false`.
  - New funcs:
    ```gdscript
    ## Renovation evicts: the upgraded floor's new class outranks the sitting
    ## tenant by construction, so their move-out starts regardless of
    ## satisfaction and note_delivery cannot cancel it -- good service does
    ## not lower the rent. A floor already moving out keeps its clock (and
    ## becomes uncancellable).
    func begin_move_out(floor_index: int) -> void:
    	if not _valid(floor_index) or _vacant[_index.slot(floor_index)]:
    		return
    	var slot := _index.slot(floor_index)
    	_priced_out[slot] = true
    	if _move_out_left[slot] <= 0:
    		_move_out_left[slot] = MOVE_OUT_TICKS

    func is_priced_out(floor_index: int) -> bool:
    	return _valid(floor_index) and _priced_out[_index.slot(floor_index)]
    ```
- [ ] **Step 4: Run to verify pass** — `-gtest=res://tests/test_tenancy.gd`. Expected: PASS, including all pre-existing tests.
- [ ] **Step 5: Commit** — `git commit -m "Let a renovation price the sitting tenant out"` (add `sim/tenancy.gd tests/test_tenancy.gd`).

---

### Task 3: GameState integration — market in the tick, eviction on upgrade, lease restricted to the basement

**Files:**
- Modify: `sim/game_state.gd` (fields ~line 24-33, `_init` ~line 130, `lease`/`lease_cost` lines 226-255, `upgrade_class` line 276, `_tick_once` line 370)
- Modify: `sim/tenancy.gd` (delete `MIN_FLOORS_FOR_TRAFFIC`, rewrite the class docstring's no-fail paragraph)
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: `Market` (Task 1), `Tenancy.begin_move_out` (Task 2).
- Produces: `GameState.market: Market` (public field, read by the codec in Task 4 and the panel in Task 5).

**Spec deviation, deliberate:** the spec says `MIN_FLOORS_FOR_TRAFFIC` "still gates traffic", but grep shows its only consumer was `lease_cost`'s free-tenant rule — nothing else reads it. It dies with that rule instead of surviving as a dead constant.

- [ ] **Step 1: Update the broken tests and write the new ones** in `tests/test_game_state.gd`:
  - **Delete** `test_only_the_cheapest_eligible_kind_is_free_below_two_tenants`, `test_leasing_is_free_when_nothing_is_tenanted`, `test_lease_reads_the_cost_before_mutating_tenancy`, and the "full $60 while traffic earns" test around line 274 — all pin the dead free-lease rule.
  - **Rewrite** `test_leasing_charges_the_kinds_price_and_sets_the_kind` and the class-gate test at ~251 (both lease tower floors, now refused) as:
    ```gdscript
    func test_a_tower_floor_cannot_be_leased_by_hand() -> void:
    	gs.economy.accrue(1000.0)
    	gs.tenancy.restore_floor(3, 1.0, true, 0)
    	assert_false(gs.lease(3, "apartments"), "tower floors are the market's")
    	assert_true(gs.tenancy.is_vacant(3))
    ```
  - **Fix setup-only uses of `lease()`** (~lines 243, 383, and any others the run reveals): replace `gs.lease(3, "law_firm")` with `gs.tenancy.lease(3, "law_firm")` plus `gs.fitout.set_tier(3, 3)` where the test needs the class — the fare-multiplier tests only need the tenant installed, not the purchase path.
  - **Check `_silence` interactions:** any test that silences floors and then ticks ≥ `Market.FILL_TICKS` will have its silence undone by the market. Grep `_silence` usages; if one ticks that long, re-silence inside its loop or shorten the run. (Expected: none tick 600+, verify.)
  - **Add:**
    ```gdscript
    func test_the_market_fills_a_vacated_floor_for_free() -> void:
    	gs.tenancy.restore_floor(3, 1.0, true, 0)
    	var cash := gs.economy.cash
    	gs.tick(Market.FILL_TICKS + 2)
    	assert_false(gs.tenancy.is_vacant(3), "the no-fail guarantee, structural now")
    	assert_gte(gs.economy.cash, cash, "move-in charges nothing (fares may add)")

    func test_upgrading_an_occupied_floor_prices_the_tenant_out() -> void:
    	gs.economy.accrue(10000.0)
    	assert_true(gs.upgrade_class(3))
    	assert_true(gs.tenancy.is_moving_out(3), "renovation evicts")
    	assert_true(gs.tenancy.is_priced_out(3))

    func test_upgrading_a_vacant_floor_evicts_nobody() -> void:
    	gs.economy.accrue(10000.0)
    	gs.tenancy.restore_floor(3, 1.0, true, 0)
    	assert_true(gs.upgrade_class(3))
    	assert_false(gs.tenancy.is_moving_out(3))
    	assert_true(gs.tenancy.is_vacant(3))

    func test_same_seed_draws_the_same_tenant() -> void:
    	var a := GameState.new(6, 1, 999)
    	var b := GameState.new(6, 1, 999)
    	for s in [a, b]:
    		s.tenancy.restore_floor(3, 1.0, true, 0)
    		s.tick(Market.FILL_TICKS + 2)
    	assert_ne(a.tenancy.kind_at(3), "")
    	assert_eq(a.tenancy.kind_at(3), b.tenancy.kind_at(3))

    func test_market_draws_do_not_touch_the_spawner_rng() -> void:
    	var before: int = gs.spawner.rng.state
    	for i in range(50):
    		gs.market.draw_kind(3, gs.catalog)
    	assert_eq(gs.spawner.rng.state, before, "one shared draw shifts all traffic")
    ```
    (If GUT lacks `assert_gte`, use `assert_true(gs.economy.cash >= cash)`.)
- [ ] **Step 2: Run to verify failure** — `-gtest=res://tests/test_game_state.gd`. Expected: FAIL on `gs.market` / `Market.FILL_TICKS`.
- [ ] **Step 3: Implement in `sim/game_state.gd`:**
  - Field after `var auto: AutoDispatch`: `var market: Market`.
  - In `_init`, after `fitout = Fitout.new(building.index)`: `market = Market.new(p_seed)`.
  - `_tick_once`, after the `accrue_for_tick` loop:
    ```gdscript
    # The market moves in AFTER move-outs vacate, so a floor emptied this
    # tick starts its fill countdown this tick. Tower floors only -- the
    # basement stays a deliberate purchase.
    market.step(tenancy, fitout, catalog, building.floor_count)
    ```
    Update the class docstring's tick-order line to `... -> expire -> advance tenancy -> market -> update combo`.
  - `lease()`: add as the first guard, and trim the docstring's cost-order paragraph (the cost no longer depends on tenancy):
    ```gdscript
    # Tower floors are the market's; only the basement leases by hand.
    if floor_index >= 0:
    	return false
    ```
  - `lease_cost()` collapses (the free-below-two-tenants rule dies with the picker; the market IS the no-fail guarantee now):
    ```gdscript
    func lease_cost(_floor_index: int, kind_id: String) -> float:
    	var k := catalog.kind(kind_id)
    	return INF if k == null else k.lease_cost
    ```
  - `upgrade_class()`: after `fitout.set_tier(floor_index, next)`, add `tenancy.begin_move_out(floor_index)` (no-ops on vacant floors) and extend the docstring: the purchase is not inert on a tenanted floor for a second reason now — it evicts.
  - In `sim/tenancy.gd`: delete `MIN_FLOORS_FOR_TRAFFIC` and its comment block; rewrite the class docstring's "NO FAIL STATE" paragraph to: the guarantee is structural — the market refills vacant tower floors for free, so there is always traffic coming back.
- [ ] **Step 4: Run to verify pass** — `-gtest=res://tests/test_game_state.gd`, then `-gtest=res://tests/test_tenancy.gd` (docstring/constant removal must not break it). Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Pump the market each tick and make renovation evict"`.

---

### Task 4: Persistence — fill countdown and priced-out flag in save v4

**Files:**
- Modify: `sim/save_codec.gd` (encode floors block ~line 261-274, decode floors loop ~line 433-458)
- Test: `tests/test_save_codec.gd`

**Interfaces:**
- Consumes: `state.market.fill_ticks_left/restore_floor`, `state.tenancy.is_priced_out`, `restore_floor(..., kind, priced_out)`.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_save_codec.gd` (match the file's existing helper style for building a state and round-tripping; the assertions are what matters):

```gdscript
func test_a_partial_fill_countdown_round_trips() -> void:
	var s := GameState.new(6, 1, 999)
	s.tenancy.restore_floor(3, 1.0, true, 0)
	s.tick(10)   # arms the countdown and burns a few ticks
	var left := s.market.fill_ticks_left(3)
	assert_between(left, 1, Market.FILL_TICKS)
	var back := SaveCodec.decode(SaveCodec.encode(s))
	assert_eq(back.market.fill_ticks_left(3), left)

func test_a_priced_out_eviction_round_trips() -> void:
	var s := GameState.new(6, 1, 999)
	s.economy.accrue(10000.0)
	assert_true(s.upgrade_class(3))
	var back := SaveCodec.decode(SaveCodec.encode(s))
	assert_true(back.tenancy.is_priced_out(3))
	for i in range(50):
		back.tenancy.note_delivery(3)
	assert_true(back.tenancy.is_moving_out(3), "reload must not soften the eviction")

func test_a_save_without_the_market_fields_decodes_and_refills() -> void:
	var s := GameState.new(6, 1, 999)
	s.tenancy.restore_floor(3, 1.0, true, 0)
	var data := SaveCodec.encode(s)
	for r in data["floors"]:
		r.erase("fill_left")
		r.erase("priced_out")
	var back := SaveCodec.decode(data)
	assert_not_null(back, "an old v4 save still decodes")
	assert_false(back.tenancy.is_priced_out(3))
	back.tick(Market.FILL_TICKS + 2)
	assert_false(back.tenancy.is_vacant(3), "the countdown restarts, harmlessly")

func test_malformed_market_fields_clamp_rather_than_refuse() -> void:
	var s := GameState.new(6, 1, 999)
	s.tenancy.restore_floor(3, 1.0, true, 0)
	var data := SaveCodec.encode(s)
	data["floors"][3]["fill_left"] = "x"
	data["floors"][3]["priced_out"] = "x"
	data["floors"][2]["fill_left"] = 999999
	var back := SaveCodec.decode(data)
	assert_not_null(back)
	assert_eq(back.market.fill_ticks_left(3), 0)
	assert_false(back.tenancy.is_priced_out(3))
```

  (Adjust `SaveCodec.decode(...)` calls to the file's actual one-arg/While-catalog-path call style found in neighbouring tests.)
- [ ] **Step 2: Run to verify failure** — `-gtest=res://tests/test_save_codec.gd`.
- [ ] **Step 3: Implement in `sim/save_codec.gd`:**
  - Encode, inside the per-floor dict (after `"kind"`):
    ```gdscript
    "fill_left": state.market.fill_ticks_left(floor_index),
    "priced_out": state.tenancy.is_priced_out(floor_index),
    ```
  - Decode, in the floors loop: read the flag with the same TYPE_BOOL caution as `vacant` (a bare `bool()` on a String is an engine error):
    ```gdscript
    var raw_priced: Variant = r.get("priced_out", false)
    var priced: bool = typeof(raw_priced) == TYPE_BOOL and raw_priced
    ```
    Pass it through `restore_floor` (kind stays restored separately by `set_kind`, as today):
    ```gdscript
    state.tenancy.restore_floor(floor_index,
    	_bounded(r.get("satisfaction", 1.0), 0.0, 1.0, 1.0), vacant,
    	_bounded_int(r.get("move_out_left", 0), 0, Tenancy.MOVE_OUT_TICKS, 0),
    	"", priced)
    ```
    And after `set_kind`:
    ```gdscript
    state.market.restore_floor(floor_index,
    	_bounded_int(r.get("fill_left", 0), 0, Market.FILL_TICKS, 0))
    ```
  - `VERSION` stays 4. No preflight additions — both fields are optional-with-default, and save-derived violations clamp.
- [ ] **Step 4: Run to verify pass** — `-gtest=res://tests/test_save_codec.gd`. Expected: PASS including all pre-existing v1–v4 tests.
- [ ] **Step 5: Commit** — `git commit -m "Persist the fill countdown and the eviction flag in save v4"`.

---

### Task 5: UI — the picker becomes basement-only, tower vacancies show the countdown

**Files:**
- Modify: `ui/floor_panel.gd` (bind ~line 91-99, `show_floor` ~line 103-132, `_rebuild_picker` line 141)
- Test: `tests/test_board_input.gd` (floor-panel section, lines 414-437)

**Interfaces:**
- Consumes: `GameState.market.fill_ticks_left`, `Market.FILL_TICKS`, `SimClock.TICK_SECONDS`.
- `picker_visible()` and `is_locked()` keep their signatures — the input tests read them.

- [ ] **Step 1: Update the tests** in `tests/test_board_input.gd`:
  - `test_the_lease_picker_appears_when_the_floor_is_vacant` becomes its inversion (keep whatever vacate helper it already uses):
    ```gdscript
    func test_a_vacant_tower_floor_shows_no_picker_the_market_fills_it() -> void:
    	# ...existing vacate of floor 3...
    	root.panel.show_floor(root.state, 3)
    	assert_false(root.panel.picker_visible(), "you don't choose who moves in either")
    ```
  - The tenanted-floor test (line 416) and `is_locked` test (line 435) stand unchanged.
  - The basement lease-button test from the "Unlock the lease buttons on a basement floor" commit must keep passing untouched — it is the regression guard for the parking path. Find it (grep `parking` in tests/) before editing.
- [ ] **Step 2: Run to verify failure** — `-gtest=res://tests/test_board_input.gd`. Expected: the rewritten test FAILs (picker still appears).
- [ ] **Step 3: Implement in `ui/floor_panel.gd`:**
  - New field `var _fill_label: Label`; in `bind()`, create it between `_upgrade` and `_picker`:
    ```gdscript
    _fill_label = Label.new()
    _fill_label.add_theme_font_size_override("font_size", 20)
    _box.add_child(_fill_label)
    ```
  - In `show_floor()`, replace `_rebuild_picker(vacant)` with:
    ```gdscript
    # Tower vacancies are the market's: no picker, just the arrival clock.
    # The basement keeps the picker -- parking is a purchase, not a tenant.
    var market_floor := vacant and _floor >= 0
    _fill_label.visible = market_floor
    if market_floor:
    	var left := _state.market.fill_ticks_left(_floor)
    	if left <= 0:
    		left = Market.FILL_TICKS   # vacated this tick; the scan arms it next tick
    	_fill_label.text = "NEW TENANT IN %ds" % int(ceil(float(left) * SimClock.TICK_SECONDS))
    _rebuild_picker(vacant and _floor < 0)
    ```
    (Like the LEAVING label, the text is refreshed per `show_floor`, not per frame — same precedent.)
  - Update the class docstring: the picker is basement-only; who moves in is the market's call.
- [ ] **Step 4: Run to verify pass** — `-gtest=res://tests/test_board_input.gd`. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Show the market's arrival clock where the picker was"`.

---

### Task 6: Full suite, docs, codemaps

- [ ] **Step 1: Full suite** — `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. Expected: all green. Fix any straggler (likely candidates: smoke test ticking past FILL_TICKS, drag-scroll/gesture tests that lease tower floors in setup — switch those to `tenancy.lease()` direct).
- [ ] **Step 2: Update `CLAUDE.md`** — append one Status paragraph:
    ```
    **The tenant market (2026-08-05).** Players no longer pick tenants: a vacant
    tower floor refills itself 30 s later with a class-weighted market draw
    (`sim/market.gd`, own rng — never the spawner's), and upgrading an occupied
    floor prices its tenant out through an uncancellable move-out. `lease()` is
    basement-only (parking). The old free-below-two-tenants rule is gone; the
    market refilling for free IS the no-fail guarantee now.
    ```
- [ ] **Step 3: Regenerate codemaps** — run `/cc-codemaps:update-codemaps` so `codemaps/sim.md` picks up Market and the Tenancy/GameState API changes.
- [ ] **Step 4: Commit** — `git commit -m "Note the tenant market in the project docs"`.
