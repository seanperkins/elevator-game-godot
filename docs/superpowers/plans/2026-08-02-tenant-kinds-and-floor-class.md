# Tenant Kinds and Floor Class — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a floor something you choose a tenant for and invest in, so traffic shape comes from the tenant mix rather than one building-wide curve.

**Architecture:** A `TenantCatalog` loads kinds from `data/tenants.json`. `Tenancy` gains a kind per row; a new `Fitout` owns a class per row. `GameState` assembles an `Array[TrafficSource]` cache and rebuilds it when either container's revision moves. The spawner takes that array instead of a floor list. A new `HallColumn` turns a tap on the left of the board into a `FloorPanel` for that floor.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.7.1, JSON data files under `data/`.

**Spec:** `docs/superpowers/specs/2026-08-02-tenant-kinds-and-floor-class-design.md` (committed `06858a6`). Section references below (§n) point into it.

## Global Constraints

- **Test command:** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- **Every `godot` invocation needs `dangerouslyDisableSandbox: true`.** The sandbox blocks Godot's user data dir and the process dies with signal 11 otherwise.
- **After adding any file with a new `class_name`, run `godot --headless --import` once** before the tests will see it.
- **Baseline:** 380 tests passing at `06858a6` on branch `tenant-kinds-and-floor-class`.
- **The sim never touches the scene tree.** `Fitout`, `TenantCatalog`, `TenantKind`, `TrafficSource` all `extends RefCounted`.
- **Purchases are refused by the sim, not merely greyed in the view** (§12).
- **`lease()` reads cost before mutating tenancy** — cost derives from `tenanted_count()`, which leasing increments (§12).
- **44pt touch targets** (88 board units at `ROW_HEIGHT`). The one documented exception retires with `ReletConfirm`.
- **The fixed tick order in `GameState`'s docstring does not change.** No task adds a phase.
- **Commit after every task.** Run the full suite before each commit.

---

### Task 1: The stairs penalty is dead — wire it and remove its escape hatch

**Files:**
- Modify: `sim/economy.gd:39`
- Modify: `sim/game_state.gd:216`
- Modify: `tests/test_economy.gd:40`, `:44`, `:47`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Economy.note_expiry(fare: float) -> void` — required argument, no default.

`Economy.note_expiry` takes a fare and deducts one fare's worth. The only production caller passes nothing, so every real expiry deducts `0.0 × 1.0 = 0`. Three unit tests cover the penalty and all pass, because they call `Economy` directly (§2).

- [ ] **Step 1: Write the failing test**

In `tests/test_game_state.gd`:

```gdscript
func test_a_real_expiry_deducts_the_stairs_penalty() -> void:
	# Seeded first: a fresh GameState holds $0 and economy.gd:42 caps the
	# penalty at available cash, so "assert cash fell" would leave $0 -> $0
	# and fail against the fixed code exactly as it fails against the broken
	# code. The seeding is what makes this test able to distinguish them.
	gs.economy.accrue(100.0)
	var before := gs.economy.cash
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0))
	gs.tick(2)
	assert_almost_eq(gs.economy.cash, before - 10.0, 1e-9,
		"one expiry costs exactly min(fare, cash)")
```

- [ ] **Step 2: Run it and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit -gunit_test_name=test_a_real_expiry_deducts_the_stairs_penalty`
Expected: FAIL — cash is unchanged at 100.0, because the call site passes no fare.

- [ ] **Step 3: Pass the fare and drop the default**

`sim/game_state.gd:216`:

```gdscript
				economy.note_expiry(p.fare)
```

`sim/economy.gd:39` — the default *is* the bug's mechanism, so removing it turns this class of regression into a parse error rather than a coverage gap:

```gdscript
func note_expiry(fare: float) -> void:
```

- [ ] **Step 4: Fix the two bare callers the parse error finds**

Both are in `tests/test_economy.gd`. `:40` inside `test_expiry_resets_the_combo_and_the_streak`, and `:47` inside `test_expiry_does_not_take_cash_away` — rename the second, because beside `test_taking_the_stairs_costs_money` (`:82`) its old name now reads as a contradiction:

```gdscript
func test_expiry_resets_the_combo_and_the_streak() -> void:
	econ.credit_delivery(10.0)
	econ.credit_delivery(10.0)
	assert_gt(econ.streak, 0)
	econ.note_expiry(0.0)
	assert_almost_eq(econ.combo, 1.0, 1e-9, "one bad delivery kills it")
	assert_eq(econ.streak, 0)

func test_a_zero_fare_expiry_takes_no_cash() -> void:
	econ.credit_delivery(10.0)
	var before := econ.cash
	econ.note_expiry(0.0)
	assert_almost_eq(econ.cash, before, 1e-9)
```

- [ ] **Step 5: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: 381 passing.

- [ ] **Step 6: Commit**

```bash
git add sim/economy.gd sim/game_state.gd tests/test_economy.gd tests/test_game_state.gd
git commit -m "Wire the stairs penalty and drop its default argument

Economy.note_expiry took an optional fare and the only production caller
passed nothing, so every real expiry deducted zero. Three unit tests covered
the penalty and passed, because they called Economy directly -- nothing
tested the seam.

The default is the bug's mechanism: a caller that forgets compiles and
silently deducts nothing. Required makes that a parse error.

The new test seeds cash first. A fresh GameState holds \$0 and the penalty is
capped at available cash, so an unseeded test reads \$0 -> \$0 and cannot
tell the fixed code from the broken code."
```

---

### Task 2: `Passenger.source_row`, required

**Files:**
- Modify: `sim/passenger.gd:12-17`
- Modify: `sim/traffic_spawner.gd:84`
- Modify: 41 call sites across `tests/` (`test_game_state` 18, `test_building` 8, `test_board_input` 6, `test_elevator_car` 6, `test_auto_dispatch` 2, `test_passenger` 1)

**Interfaces:**
- Consumes: nothing.
- Produces: `Passenger._init(origin: int, destination: int, patience: int, p_fare: float, p_source_row: int)`; field `source_row: int`.

The floor that *generated* a trip stops being derivable from its endpoints once the lobby becomes an endpoint (§5.1). Two rules need it — the fare (§5 step 6) and satisfaction (§5.1) — so the passenger carries it.

**No default.** Defaulting to `0` makes every passenger built by anything that forgets attribute its satisfaction to floor 0, silently rebuilding the exact failure §5.1 calls fatal. Defaulting to `origin_row` changes delivery attribution, which is a different bug. This is Task 1's argument applied to the field this spec introduces (§5.2).

- [ ] **Step 1: Write the failing test**

In `tests/test_passenger.gd`:

```gdscript
func test_a_passenger_remembers_which_floor_generated_it() -> void:
	# An inbound trip starts at the lobby but belongs to floor 5.
	var p := Passenger.new(0, 5, 900, 4.0, 5)
	assert_eq(p.origin_row, 0)
	assert_eq(p.source_row, 5, "the generating floor, not the endpoint")
```

- [ ] **Step 2: Run it and watch it fail**

Expected: parse error — `Passenger._init` takes 4 arguments.

- [ ] **Step 3: Add the field**

`sim/passenger.gd`:

```gdscript
## The floor whose tenant generated this trip. NOT derivable from the
## endpoints: an inbound trip runs lobby -> F, so its origin is the lobby
## while the traffic belongs to F. Both the fare (kind.base_fare x the
## floor's class multiplier) and satisfaction credit follow this, not the
## endpoints -- see spec §5.1.
var source_row: int

func _init(origin: int, destination: int, patience: int, p_fare: float,
		p_source_row: int) -> void:
	origin_row = origin
	destination_row = destination
	patience_ticks = patience
	_initial_patience = maxi(patience, 1)
	fare = p_fare
	source_row = p_source_row
```

- [ ] **Step 4: Fix every call site the parse errors find**

`sim/traffic_spawner.gd:84` — under the current uniform-pairs model the origin *is* the generating floor, so this is faithful until Task 10 replaces it:

```gdscript
	out.append(Passenger.new(occupied[origin_index], occupied[destination_index],
		base_patience_ticks, base_fare, occupied[origin_index]))
```

`tests/test_passenger.gd:4` is a factory, so that whole file is one edit:

```gdscript
func _p(origin: int, dest: int, patience: int, fare: float, source := -1) -> Passenger:
	return Passenger.new(origin, dest, patience, fare,
		source if source >= 0 else origin)
```

For the remaining 40 test sites, pass the origin as the source — every existing test predates directional traffic, so origin is the honest generating floor for all of them. Work through the parse errors until the suite loads.

- [ ] **Step 5: Run the full suite**

Expected: 382 passing.

- [ ] **Step 6: Commit**

```bash
git add sim/passenger.gd sim/traffic_spawner.gd tests/
git commit -m "Passenger carries the floor that generated it, with no default

Once the lobby is an endpoint, the generating floor stops being derivable
from origin or destination -- an inbound trip runs lobby -> F but belongs to
F. Fare and satisfaction both follow it.

Required, not defaulted, for the same reason note_expiry's default had to
go: defaulting to 0 would attribute every forgotten passenger's satisfaction
to floor 0, which is precisely the failure the rule exists to prevent."
```

---

### Task 3: Satisfaction follows the generating floor

**Files:**
- Modify: `sim/game_state.gd:200`, `:217`
- Modify: `tests/test_game_state.gd:124-128`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: `Passenger.source_row` (Task 2).
- Produces: no new API — a behaviour change in `_deliver` and `_expire`.

Satisfaction is attributed by *endpoint* today, which is correct only because every trip has two tenanted endpoints. §5 makes the lobby an endpoint of most trips, and under endpoint attribution a floor in its outbound peak is **monotonically non-increasing**: perfect service holds it flat, and any imperfection is unrecoverable because the credit went to floor 0 (§5.1).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_delivery_credits_the_generating_floor_not_the_destination() -> void:
	# An outbound trip: floor 4's tenant sent somebody to the lobby.
	# The credit belongs to 4, which generated it, not to 0, which received it.
	for i in range(30):
		gs.tenancy.note_expiry(4)
	var before := gs.tenancy.satisfaction_at(4)
	var lobby_before := gs.tenancy.satisfaction_at(0)
	var p := Passenger.new(4, 0, 900, 4.0, 4)
	gs.building.cars[0].dispatch_to(4)
	gs.building.enqueue(p)
	gs.tick(SimClock.TICKS_PER_MINUTE)
	assert_gt(gs.tenancy.satisfaction_at(4), before, "the generator is credited")
	assert_almost_eq(gs.tenancy.satisfaction_at(0), lobby_before, 1e-9,
		"the lobby received the trip but did not generate it")

func test_expiry_blames_the_generating_floor_not_the_origin() -> void:
	# An inbound trip: floor 3's visitor gave up in the lobby.
	# The blame belongs to 3, not to the lobby they were standing in.
	var before := gs.tenancy.satisfaction_at(3)
	var lobby_before := gs.tenancy.satisfaction_at(0)
	gs.building.enqueue(Passenger.new(0, 3, 0, 10.0, 3))
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(3), before, "the generator is blamed")
	assert_almost_eq(gs.tenancy.satisfaction_at(0), lobby_before, 1e-9,
		"the lobby held the queue but did not generate it")
```

- [ ] **Step 2: Run them and watch them fail**

Expected: both FAIL — credit lands on row 0 and blame lands on row 0.

- [ ] **Step 3: Change both attribution sites**

`sim/game_state.gd:200`:

```gdscript
				# The floor that GENERATED the trip, not the endpoint. Under
				# directional traffic most trips have the lobby at one end, so
				# endpoint attribution would credit floor 0 for everyone else's
				# service and leave an outbound-peak floor unable to recover.
				tenancy.note_delivery(p.source_row)
```

`sim/game_state.gd:217`:

```gdscript
					tenancy.note_expiry(p.source_row)
```

- [ ] **Step 4: Rewrite the test whose name encodes the old rule**

`tests/test_game_state.gd:124` — its passenger must set `source_row` explicitly or the assertion means nothing:

```gdscript
func test_expiry_lowers_the_generating_rows_satisfaction() -> void:
	var before := gs.tenancy.satisfaction_at(3)
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(3), before)
```

- [ ] **Step 5: Run the full suite**

Expected: 384 passing.

- [ ] **Step 6: Commit**

```bash
git add sim/game_state.gd tests/test_game_state.gd
git commit -m "Credit and blame satisfaction to the generating floor

Endpoint attribution is correct only while every trip has two tenanted
endpoints, which is true today and stops being true when the lobby becomes
an endpoint of most trips.

Under endpoint attribution a floor in its outbound peak can only lose:
every expiry blames it and every success credits floor 0, so perfect service
holds satisfaction flat and any imperfection is unrecoverable. Floor 0
meanwhile absorbs credit and blame from the whole building.

Both directions now follow p.source_row -- the same floor that sets the fare."
```

---

### Task 4: `TenantKind`, `TenantCatalog`, and the data file

**Files:**
- Create: `sim/tenant_kind.gd`
- Create: `sim/tenant_catalog.gd`
- Rewrite: `data/tenants.json`
- Test: `tests/test_tenant_catalog.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `TenantKind` fields: `id: String`, `display_name: String`, `requires_class: int`, `lease_cost: float`, `base_fare: float`, `rate: PackedFloat32Array`, `inbound: PackedFloat32Array`, `outbound: PackedFloat32Array`
  - `TenantKind.rate_at(minute: int) -> float`, `.inbound_at(minute: int) -> float`, `.outbound_at(minute: int) -> float`
  - `TenantCatalog.load_from(path: String) -> bool`
  - `TenantCatalog.kind(id: String) -> TenantKind` (null when unknown)
  - `TenantCatalog.available_for_class(tier: int) -> Array[TenantKind]`
  - `TenantCatalog.cheapest_for_class(tier: int) -> TenantKind`
  - `TenantCatalog.class_cost(tier: int) -> float`, `.fare_multiplier(tier: int) -> float`, `.max_tier() -> int`
  - `TenantCatalog.largest_bucket() -> float`

`data/tenants.json` already exists and is dead — it describes `rent_per_minute` for a deli, a dentist and accountants, an income source removed when rent was, and no `.gd` file references it (§4). This task repurposes it.

**The numbers are pinned by §5.6, not free.** `Σ` of the shipped curve's 24 buckets is **47.4**, and the starting building is 1 Shops + 5 Apartments, so `5·Σ(Apartments) + Σ(Shops) = 47.4`. The arrays below satisfy it exactly: `Σ(Apartments) = 7.7`, `Σ(Shops) = 8.9`, `5(7.7) + 8.9 = 47.4`. `Apartments[8] = 0.9` is the anchor §5.6 states, and `Offices[8] = 3.0` sits inside its stated 2–4× band.

- [ ] **Step 1: Write the failing test**

`tests/test_tenant_catalog.gd`:

```gdscript
extends GutTest

var cat: TenantCatalog

func before_each() -> void:
	cat = TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"), "the shipped file loads")

func test_a_class_gates_which_kinds_may_lease() -> void:
	var t1 := cat.available_for_class(1)
	var ids := PackedStringArray()
	for k in t1:
		ids.append(k.id)
	assert_eq(ids.size(), 2, "class 1 offers exactly the tier-1 kinds")
	assert_true(ids.has("apartments") and ids.has("shops"))
	assert_eq(cat.available_for_class(3).size(), 6, "class 3 offers everything")

func test_the_starting_roster_totals_the_shipped_curve() -> void:
	# spec §5.6: the opening's daily VOLUME is pinned even though its shape
	# deliberately changes. 1 Shops + 5 Apartments must total what
	# data/traffic_walkup.json totalled: 47.4 trips per simulated day.
	var apartments := 0.0
	var shops := 0.0
	for h in range(24):
		apartments += cat.kind("apartments").rate_at(h)
		shops += cat.kind("shops").rate_at(h)
	assert_almost_eq(5.0 * apartments + shops, 47.4, 1e-4)

func test_offices_are_inbound_at_eight_and_apartments_outbound_at_seven() -> void:
	# The mirror is the whole point of the feature, so it is asserted
	# directly rather than inferred from a total. Each kind is pinned at the
	# hour ITS OWN curve peaks -- apartments are on a falling shoulder by 8.
	var office := cat.kind("office")
	assert_gt(office.inbound_at(8), office.outbound_at(8) * 3.0)
	var apt := cat.kind("apartments")
	assert_gt(apt.outbound_at(7), apt.inbound_at(7) * 3.0)

func test_the_total_rate_cannot_saturate_the_bernoulli_trial() -> void:
	# spec §5.6: the spawner clips silently at p = 1 and emits at most one
	# passenger per tick. MAX_ROWS x the largest single bucket is the
	# worst case, exhaustive by construction -- "every kind combination" is
	# 6^40 and is not a writable test.
	assert_lt(float(Building.MAX_ROWS) * cat.largest_bucket(),
		float(SimClock.TICKS_PER_MINUTE))
```

- [ ] **Step 2: Run it and watch it fail**

Expected: parse error — `TenantCatalog` does not exist.

- [ ] **Step 3: Write `sim/tenant_kind.gd`**

```gdscript
class_name TenantKind
extends RefCounted

## One leasable tenant type. `rate` is trips per simulated minute generated by
## ONE FLOOR of this kind, one bucket per simulated hour -- the same shape and
## bucketing as the old building-wide curve, so the piecewise-constant property
## the catch-up integrator would rely on is preserved.
##
## `inbound` is the share of that minute's trips running lobby -> here and
## `outbound` the share running here -> lobby; the remainder is interfloor.
## A kind therefore states where its people GO, not only how many there are,
## which is what makes up-peak and down-peak a consequence of who leased
## rather than a mechanic bolted on.

const BUCKETS := 24

var id: String
var display_name: String
var requires_class: int
var lease_cost: float
var base_fare: float
var rate: PackedFloat32Array
var inbound: PackedFloat32Array
var outbound: PackedFloat32Array

func rate_at(minute: int) -> float:
	return rate[posmod(minute, BUCKETS)]

func inbound_at(minute: int) -> float:
	return inbound[posmod(minute, BUCKETS)]

func outbound_at(minute: int) -> float:
	return outbound[posmod(minute, BUCKETS)]

func interfloor_at(minute: int) -> float:
	return maxf(1.0 - inbound_at(minute) - outbound_at(minute), 0.0)
```

- [ ] **Step 4: Write `sim/tenant_catalog.gd`**

```gdscript
class_name TenantCatalog
extends RefCounted

## The leasing domain: which kinds exist, and what a floor class costs and is
## worth. Both live in one file so a kind's `requires_class` is checked against
## the same ladder it is tuned against.
##
## A malformed file is refused WHOLE. This data controls probabilities and
## money, so shape checks are not enough -- see _validate.

var _kinds: Array[TenantKind] = []
var _by_id: Dictionary = {}
var _class_cost: Dictionary = {}          # tier -> float
var _class_multiplier: Dictionary = {}    # tier -> float
var _max_tier: int = 0

func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return _parse(parsed as Dictionary)

func _parse(data: Dictionary) -> bool:
	_kinds = []
	_by_id = {}
	_class_cost = {}
	_class_multiplier = {}
	_max_tier = 0

	var classes: Variant = data.get("classes")
	if typeof(classes) != TYPE_ARRAY or (classes as Array).is_empty():
		return false
	var expected_tier := 1
	for entry in (classes as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var e: Dictionary = entry
		if int(e.get("tier", -1)) != expected_tier:
			return false                      # tiers contiguous from 1
		var cost := float(e.get("cost", -1.0))
		var mult := float(e.get("fare_multiplier", 0.0))
		# A negative cost is free money, not a discount: can_afford(-400) is
		# cash >= -400 (true) and spend then runs cash -= -400.
		if not is_finite(cost) or cost < 0.0:
			return false
		if not is_finite(mult) or mult <= 0.0:
			return false
		_class_cost[expected_tier] = cost
		_class_multiplier[expected_tier] = mult
		_max_tier = expected_tier
		expected_tier += 1

	var kinds: Variant = data.get("kinds")
	if typeof(kinds) != TYPE_ARRAY or (kinds as Array).is_empty():
		return false
	for entry in (kinds as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var k := _parse_kind(entry as Dictionary)
		if k == null:
			return false
		if _by_id.has(k.id):
			return false                      # ids unique
		_by_id[k.id] = k
		_kinds.append(k)

	# Without a tier-1 kind the no-fail guarantee ("the cheapest eligible kind
	# is free") selects from an empty set and silently has no implementation.
	for k in _kinds:
		if k.requires_class == 1:
			return true
	return false

func _parse_kind(e: Dictionary) -> TenantKind:
	var k := TenantKind.new()
	k.id = str(e.get("id", ""))
	if k.id.is_empty():
		return null
	k.display_name = str(e.get("name", k.id))
	k.requires_class = int(e.get("requires_class", 0))
	if not _class_cost.has(k.requires_class):
		return null                           # requires a tier the ladder defines
	k.lease_cost = float(e.get("lease_cost", -1.0))
	k.base_fare = float(e.get("base_fare", 0.0))
	if not is_finite(k.lease_cost) or k.lease_cost < 0.0:
		return null
	if not is_finite(k.base_fare) or k.base_fare <= 0.0:
		return null
	k.rate = _floats(e.get("rate"))
	k.inbound = _floats(e.get("inbound"))
	k.outbound = _floats(e.get("outbound"))
	if k.rate.is_empty() or k.inbound.is_empty() or k.outbound.is_empty():
		return null
	for h in range(TenantKind.BUCKETS):
		# A negative interfloor remainder feeds a weighted pick, which is the
		# one malformed case that fails silently rather than crashing.
		if k.inbound[h] + k.outbound[h] > 1.0:
			return null
	return k

func _floats(v: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != TenantKind.BUCKETS:
		return out
	for x in (v as Array):
		if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
			return PackedFloat32Array()
		var f := float(x)
		if not is_finite(f) or f < 0.0:
			return PackedFloat32Array()
		out.append(f)
	return out

func kind(id: String) -> TenantKind:
	return _by_id.get(id, null)

func all_kinds() -> Array[TenantKind]:
	return _kinds

## Every kind at or below `tier`, in file order.
func available_for_class(tier: int) -> Array[TenantKind]:
	var out: Array[TenantKind] = []
	for k in _kinds:
		if k.requires_class <= tier:
			out.append(k)
	return out

## Lowest lease_cost among eligible kinds; ties break by FIRST APPEARANCE in
## the file, so the free recovery tenant (§9) and the save-restore fallback
## (§10) are deterministic rather than dependent on JSON ordering.
func cheapest_for_class(tier: int) -> TenantKind:
	var best: TenantKind = null
	for k in available_for_class(tier):
		if best == null or k.lease_cost < best.lease_cost:
			best = k
	return best

func class_cost(tier: int) -> float:
	return float(_class_cost.get(tier, INF))

func fare_multiplier(tier: int) -> float:
	return float(_class_multiplier.get(tier, 1.0))

func max_tier() -> int:
	return _max_tier

## The largest single rate bucket across every kind. MAX_ROWS x this is the
## worst-case summed rate, which must stay under TICKS_PER_MINUTE or the
## Bernoulli trial clips silently at p = 1.
func largest_bucket() -> float:
	var top := 0.0
	for k in _kinds:
		for h in range(TenantKind.BUCKETS):
			top = maxf(top, k.rate[h])
	return top
```

- [ ] **Step 5: Rewrite `data/tenants.json`**

```json
{
  "comment": "Traffic is per FLOOR of this kind, per simulated minute, one bucket per simulated hour. inbound = share running lobby->here, outbound = share running here->lobby, remainder is interfloor. The starting building (1 shops + 5 apartments) must total 47.4 trips/day -- see spec 5.6.",
  "classes": [
    { "tier": 1, "cost": 0,    "fare_multiplier": 1.00 },
    { "tier": 2, "cost": 400,  "fare_multiplier": 1.35 },
    { "tier": 3, "cost": 2500, "fare_multiplier": 1.80 }
  ],
  "kinds": [
    {
      "id": "apartments", "name": "Apartments",
      "requires_class": 1, "lease_cost": 60.0, "base_fare": 3.0,
      "rate": [0.1,0.1,0.1,0.1,0.1,0.1, 0.5,1.2,0.9,0.2, 0.2,0.2,0.3,0.2,
               0.2,0.2,0.2,0.5,1.1,0.5, 0.3,0.2,0.1,0.1],
      "inbound": [0.3,0.3,0.3,0.3,0.3,0.3, 0.1,0.05,0.05,0.1, 0.2,0.2,0.3,0.3,
                  0.3,0.35,0.5,0.7,0.8,0.75, 0.7,0.6,0.5,0.4],
      "outbound": [0.3,0.3,0.3,0.3,0.3,0.3, 0.75,0.85,0.8,0.6, 0.4,0.35,0.3,0.3,
                   0.3,0.3,0.25,0.15,0.1,0.1, 0.1,0.15,0.2,0.25]
    },
    {
      "id": "shops", "name": "Shops",
      "requires_class": 1, "lease_cost": 60.0, "base_fare": 3.5,
      "rate": [0.0,0.0,0.0,0.0,0.0,0.0, 0.0,0.1,0.3,0.6, 0.8,1.0,1.2,1.1,
               0.9,0.8,0.7,0.6,0.4,0.3, 0.1,0.0,0.0,0.0],
      "inbound": [0.25,0.25,0.25,0.25,0.25,0.25, 0.25,0.25,0.25,0.25,
                  0.25,0.25,0.25,0.25, 0.25,0.25,0.25,0.25,0.25,0.25,
                  0.25,0.25,0.25,0.25],
      "outbound": [0.25,0.25,0.25,0.25,0.25,0.25, 0.25,0.25,0.25,0.25,
                   0.25,0.25,0.25,0.25, 0.25,0.25,0.25,0.25,0.25,0.25,
                   0.25,0.25,0.25,0.25]
    },
    {
      "id": "office", "name": "Offices",
      "requires_class": 2, "lease_cost": 140.0, "base_fare": 4.0,
      "rate": [0.05,0.05,0.05,0.05,0.05,0.05, 0.3,1.5,3.0,1.2, 0.5,0.5,1.0,0.9,
               0.5,0.5,0.8,2.6,1.2,0.4, 0.2,0.1,0.05,0.05],
      "inbound": [0.2,0.2,0.2,0.2,0.2,0.2, 0.7,0.85,0.9,0.75, 0.5,0.4,0.4,0.55,
                  0.4,0.35,0.25,0.1,0.05,0.05, 0.1,0.15,0.2,0.2],
      "outbound": [0.3,0.3,0.3,0.3,0.3,0.3, 0.1,0.05,0.05,0.1, 0.25,0.35,0.4,0.3,
                   0.35,0.4,0.55,0.85,0.9,0.85, 0.7,0.6,0.5,0.4]
    },
    {
      "id": "gym", "name": "Gym",
      "requires_class": 2, "lease_cost": 120.0, "base_fare": 3.8,
      "rate": [0.05,0.05,0.05,0.05,0.1,0.4, 1.1,1.3,0.7,0.4, 0.4,0.5,0.7,0.5,
               0.4,0.4,0.6,1.0,1.4,1.2, 0.8,0.4,0.2,0.1],
      "inbound": [0.45,0.45,0.45,0.45,0.45,0.45, 0.45,0.45,0.45,0.45,
                  0.45,0.45,0.45,0.45, 0.45,0.45,0.45,0.45,0.45,0.45,
                  0.45,0.45,0.45,0.45],
      "outbound": [0.45,0.45,0.45,0.45,0.45,0.45, 0.45,0.45,0.45,0.45,
                   0.45,0.45,0.45,0.45, 0.45,0.45,0.45,0.45,0.45,0.45,
                   0.45,0.45,0.45,0.45]
    },
    {
      "id": "law_firm", "name": "Law Firm",
      "requires_class": 3, "lease_cost": 380.0, "base_fare": 9.0,
      "rate": [0.05,0.05,0.05,0.05,0.05,0.05, 0.2,0.5,0.7,0.7, 0.7,0.7,0.7,0.7,
               0.7,0.7,0.7,0.6,0.4,0.2, 0.1,0.05,0.05,0.05],
      "inbound": [0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4,
                  0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4],
      "outbound": [0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4,
                   0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4]
    },
    {
      "id": "clinic", "name": "Clinic",
      "requires_class": 3, "lease_cost": 340.0, "base_fare": 8.0,
      "rate": [0.05,0.05,0.05,0.05,0.05,0.05, 0.4,1.0,1.6,1.5, 1.3,1.0,0.6,0.8,
               0.9,0.8,0.6,0.4,0.2,0.1, 0.05,0.05,0.05,0.05],
      "inbound": [0.5,0.5,0.5,0.5,0.5,0.5, 0.5,0.5,0.5,0.5, 0.5,0.5,0.5,0.5,
                  0.5,0.5,0.5,0.5,0.5,0.5, 0.5,0.5,0.5,0.5],
      "outbound": [0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4,
                   0.4,0.4,0.4,0.4,0.4,0.4, 0.4,0.4,0.4,0.4]
    }
  ]
}
```

- [ ] **Step 6: Import and run**

Run: `godot --headless --import` then the full suite.
Expected: 389 passing (5 new).

- [ ] **Step 7: Add the refusal tests**

```gdscript
func _catalog_from(data: Dictionary) -> TenantCatalog:
	var c := TenantCatalog.new()
	var path := "user://test_tenants_%d.json" % randi()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var ok := c.load_from(path)
	DirAccess.remove_absolute(path)
	return c if ok else null

func _valid_kind(overrides: Dictionary) -> Dictionary:
	var k := {
		"id": "k1", "name": "K1", "requires_class": 1,
		"lease_cost": 10.0, "base_fare": 1.0,
		"rate": [], "inbound": [], "outbound": [],
	}
	for h in range(24):
		(k["rate"] as Array).append(0.1)
		(k["inbound"] as Array).append(0.3)
		(k["outbound"] as Array).append(0.3)
	for key in overrides:
		k[key] = overrides[key]
	return k

const _CLASSES := [
	{ "tier": 1, "cost": 0, "fare_multiplier": 1.0 },
]

func test_a_negative_class_cost_is_refused() -> void:
	# The one malformed case that CREDITS the player instead of crashing:
	# can_afford(-400) is true and spend runs cash -= -400.
	assert_null(_catalog_from({
		"classes": [{ "tier": 1, "cost": -400, "fare_multiplier": 1.0 }],
		"kinds": [_valid_kind({})],
	}))

func test_an_impossible_direction_mix_is_refused() -> void:
	# inbound + outbound > 1 makes the interfloor remainder negative, which
	# feeds a weighted pick -- silent, unlike every other malformed case.
	var bad := []
	for h in range(24):
		bad.append(0.8)
	assert_null(_catalog_from({
		"classes": _CLASSES,
		"kinds": [_valid_kind({ "inbound": bad, "outbound": bad })],
	}))

func test_a_catalog_with_no_tier_one_kind_is_refused() -> void:
	# Otherwise the no-fail guarantee selects from an empty set.
	assert_null(_catalog_from({
		"classes": [
			{ "tier": 1, "cost": 0, "fare_multiplier": 1.0 },
			{ "tier": 2, "cost": 400, "fare_multiplier": 1.35 },
		],
		"kinds": [_valid_kind({ "requires_class": 2 })],
	}))

func test_a_short_bucket_array_is_refused() -> void:
	assert_null(_catalog_from({
		"classes": _CLASSES,
		"kinds": [_valid_kind({ "rate": [0.1, 0.1, 0.1] })],
	}))
```

- [ ] **Step 8: Run the full suite and commit**

Expected: 393 passing.

```bash
git add sim/tenant_kind.gd sim/tenant_catalog.gd data/tenants.json tests/test_tenant_catalog.gd
git commit -m "Add the tenant catalog, repurposing a dead data file

data/tenants.json described rent_per_minute for a deli, a dentist and
accountants -- an income source removed when rent was, referenced by no .gd
file. It now describes the leasing domain.

A kind states where its people GO, not only how many: per-hour inbound and
outbound shares with interfloor as the remainder. Up-peak and down-peak then
arrive as a consequence of who leased rather than as a mechanic.

The curve numbers are pinned, not chosen: 5 x sum(apartments) + sum(shops)
= 47.4, the daily total of the curve being replaced, so the opening's volume
is unchanged while its shape deliberately is not.

Validation covers the cases that fail SILENTLY -- a negative class cost
credits the player, and a direction mix over 1.0 feeds a negative share into
a weighted pick. Neither would crash."
```

---

### Task 5: `Fitout` — a class per floor

**Files:**
- Create: `sim/fitout.gd`
- Test: `tests/test_fitout.gd`

**Interfaces:**
- Consumes: `TenantCatalog` (Task 4).
- Produces: `Fitout.new(row_count: int)`; `rows() -> int`; `add_row() -> void`; `tier_at(row: int) -> int`; `set_tier(row: int, tier: int) -> void`; `revision() -> int`.

Class is built into the floor and survives a tenant change; kind and satisfaction leave with the tenant. That split is the spec's headline rule, and giving it two owners is what makes it structural rather than remembered (§3).

- [ ] **Step 1: Write the failing test**

`tests/test_fitout.gd`:

```gdscript
extends GutTest

var f: Fitout

func before_each() -> void:
	f = Fitout.new(6)

func test_every_floor_starts_at_tier_one() -> void:
	for row in range(6):
		assert_eq(f.tier_at(row), 1)

func test_a_new_row_starts_at_tier_one() -> void:
	f.add_row()
	assert_eq(f.rows(), 7)
	assert_eq(f.tier_at(6), 1)

func test_setting_a_tier_moves_the_revision() -> void:
	var before := f.revision()
	f.set_tier(2, 3)
	assert_eq(f.tier_at(2), 3)
	assert_ne(f.revision(), before, "a class purchase must invalidate the cache")

func test_an_out_of_range_row_reads_tier_one_and_writes_nothing() -> void:
	assert_eq(f.tier_at(99), 1)
	var before := f.revision()
	f.set_tier(99, 3)
	assert_eq(f.revision(), before)
```

- [ ] **Step 2: Run it and watch it fail**

Expected: parse error — `Fitout` does not exist.

- [ ] **Step 3: Write `sim/fitout.gd`**

```gdscript
class_name Fitout
extends RefCounted

## What is built INTO a floor, as opposed to what a tenant brings with them.
## Today that is one thing -- the floor's class -- and later it is where
## amenities land without touching the tenancy loop.
##
## The split is the spec's headline rule made structural: things built into the
## floor persist, things built for the tenant leave with them. That is what
## makes replacing a tenant a real cost rather than a free re-roll.
##
## Indexes its dense array DIRECTLY, exactly as Tenancy does. A shared index
## object was considered and rejected: in a building whose bottom floor is
## always 0 the mapping is the identity, so it earns nothing, and it converts a
## container-size desync from a loud out-of-range access into a silent
## valid-but-wrong index that an "the containers agree" test would pass through.

const BASE_TIER := 1

var _tier: PackedInt32Array = PackedInt32Array()
var _revision: int = 0

func _init(row_count: int) -> void:
	for i in range(maxi(row_count, 0)):
		_tier.append(BASE_TIER)

func rows() -> int:
	return _tier.size()

func add_row() -> void:
	_tier.append(BASE_TIER)
	_revision += 1

func tier_at(row: int) -> int:
	return _tier[row] if _valid(row) else BASE_TIER

## Moves the revision, because a cached TrafficSource carries this floor's fare
## multiplier. Without that a class upgrade on a TENANTED floor would leave the
## stale multiplier cached until the next tenancy event -- which on a
## well-served floor may be never, making the purchase inert.
func set_tier(row: int, tier: int) -> void:
	if not _valid(row):
		return
	_tier[row] = tier
	_revision += 1

func revision() -> int:
	return _revision

func _valid(row: int) -> bool:
	return row >= 0 and row < _tier.size()
```

- [ ] **Step 4: Import, run, commit**

Run: `godot --headless --import`, then the full suite. Expected: 397 passing.

```bash
git add sim/fitout.gd tests/test_fitout.gd
git commit -m "Add Fitout: the class built into a floor

Three facts with three lifetimes -- class persists, kind and satisfaction
leave with the tenant. Two owners rather than one is what makes that
structural instead of remembered.

Indexes its array directly rather than through a shared mapping object. In a
building whose bottom floor is always 0 that mapping is the identity, and a
shared count turns a container desync from a loud out-of-range access into a
silent wrong index that the agreement test would pass through.

set_tier moves a revision because a cached traffic source carries the fare
multiplier."
```

---

### Task 6: `Tenancy` — revision counter and vacated-row reporting

**Files:**
- Modify: `sim/tenancy.gd` — `accrue_for_tick`, `relet`, `restore_row`, docstrings at `:77-78`
- Test: `tests/test_tenancy.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Tenancy.revision() -> int`; `Tenancy.accrue_for_tick() -> PackedInt32Array` (rows that vacated on this tick).

`GameState` caches an `Array[TrafficSource]` and must know when it goes stale. A counter answers *that* something changed; §5.4 also needs *which floor* vacated, and a counter is floor-anonymous by construction (§5.3).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_accrue_reports_which_rows_vacated() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	var vacated := PackedInt32Array()
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		var out := t.accrue_for_tick()
		if not out.is_empty():
			vacated = out
	assert_eq(vacated.size(), 1, "exactly one row vacated")
	assert_eq(vacated[0], 0, "and the caller is told which")

func test_a_vacancy_moves_the_revision() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	var before := t.revision()
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_ne(t.revision(), before)

func test_restoring_a_row_moves_the_revision() -> void:
	# The path every returning player's session starts with: decode mutates
	# tenancy from outside, and a cache built at construction would otherwise
	# never learn about it.
	var before := t.revision()
	t.restore_row(2, 0.5, true, 0)
	assert_ne(t.revision(), before)
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `accrue_for_tick` returns nothing and `revision` does not exist.

- [ ] **Step 3: Implement**

In `sim/tenancy.gd`, add the counter and change the two mutators:

```gdscript
var _revision: int = 0

func revision() -> int:
	return _revision
```

Replace `accrue_for_tick` (and its docstring at `:77-78`, which says "Returns nothing"):

```gdscript
## Advances move-out countdowns and RETURNS the rows that vacated on this tick.
##
## The docstring this replaces said "returns nothing", meaning tenants are not
## an income source -- a rejection of rent, not of all return values. The row
## identity is needed because a vacating floor's waiting passengers have to be
## removed by source, and a revision counter is floor-anonymous by
## construction: it reports that something changed, not which floor.
func accrue_for_tick() -> PackedInt32Array:
	var vacated := PackedInt32Array()
	for row in range(_satisfaction.size()):
		if _vacant[row]:
			continue
		if _move_out_left[row] > 0:
			_move_out_left[row] -= 1
			if _move_out_left[row] <= 0:
				_vacant[row] = true
				_revision += 1
				vacated.append(row)
	return vacated
```

Add `_revision += 1` to `restore_row` (after the writes) and to `relet`.

- [ ] **Step 4: Run the full suite**

Expected: 400 passing. `sim/game_state.gd:170` discards the new return value, which GDScript permits, so no call site breaks.

- [ ] **Step 5: Commit**

```bash
git add sim/tenancy.gd tests/test_tenancy.gd
git commit -m "Tenancy reports vacated rows and carries a revision

A cached traffic-source list goes stale on four paths, and the one that does
not pass through GameState is a move-out: it happens inside accrue_for_tick,
which returned void by documented design, so GameState learned nothing.

The counter answers 'has anything changed'. It cannot answer 'which floor
vacated', which the waiting-passenger sweep needs, so accrue_for_tick now
returns the rows.

restore_row moves the revision too -- that is the path every returning
player's session starts with, and a cache built at construction would
otherwise never learn the save's vacancies."
```

---

### Task 7: `Tenancy` — a kind per row, a roster prefix, and vacant purchases

**Files:**
- Modify: `sim/tenancy.gd` — `_init`, `add_row`, `relet`, `restore_row`, docstrings at `:15-19`, `:116-118`
- Modify: `tests/test_tenancy.gd:120-122`
- Test: `tests/test_tenancy.gd`

**Interfaces:**
- Consumes: Task 6's revision.
- Produces: `Tenancy.new(row_count: int, tenanted_prefix: int)`; `kind_at(row: int) -> String` (`""` when none); `set_kind(row: int, kind_id: String) -> void`; `add_row()` now appends a **vacant** row.

`_append_row()` appends `_vacant = false`, so a purchased floor arrives *tenanted* — and with no kind it cannot spawn, price a fare, or draw a sparkline (§4.4). The vacancy is applied by **row index**, not by entry point: `_init` loops the same helper with nothing distinguishing row 6 from row 0, so vacating only in `add_row()` would leave `GameState.new(40, …)` with 40 tenanted kindless rows (§4.3).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_only_the_roster_prefix_starts_tenanted() -> void:
	var tall := Tenancy.new(10, 6)
	for row in range(6):
		assert_false(tall.is_vacant(row), "row %d is in the roster" % row)
	for row in range(6, 10):
		assert_true(tall.is_vacant(row), "row %d is past the roster" % row)
		assert_eq(tall.kind_at(row), "", "and carries no kind")

func test_a_purchased_row_arrives_vacant() -> void:
	t.add_row()
	assert_eq(t.rows(), 7)
	assert_true(t.is_vacant(6), "you choose who moves in")
	assert_eq(t.kind_at(6), "")

func test_a_kind_is_remembered_and_cleared_on_vacancy() -> void:
	t.set_kind(2, "office")
	assert_eq(t.kind_at(2), "office")
	while t.satisfaction_at(2) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(2)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_true(t.is_vacant(2))
	assert_eq(t.kind_at(2), "", "kind leaves with the tenant")
```

- [ ] **Step 2: Run and watch it fail**

Expected: parse error — `Tenancy.new` takes one argument.

- [ ] **Step 3: Implement**

```gdscript
var _kind: PackedStringArray = PackedStringArray()

## `tenanted_prefix` is how many LEADING rows start with a tenant. Everything
## past it arrives vacant with no kind, so a constructed floor and a purchased
## one agree.
##
## The divergence is by row INDEX, not by entry point. _append_row is shared
## with add_row, and flipping the append itself would make every floor of a new
## building vacant; vacating only in add_row would leave a tall constructed
## building fully tenanted and kindless. So both callers vacate, by index.
func _init(row_count: int, tenanted_prefix: int) -> void:
	for i in range(row_count):
		_append_row()
		if i >= tenanted_prefix:
			_vacant[i] = true

func add_row() -> void:
	_append_row()
	_vacant[_vacant.size() - 1] = true
	_revision += 1
```

Extend `_append_row` with `_kind.append("")`, have `relet`/`restore_row` accept and write a kind, and clear the kind wherever a row becomes vacant (`accrue_for_tick`'s vacancy branch):

```gdscript
func kind_at(row: int) -> String:
	return _kind[row] if _valid(row) else ""

func set_kind(row: int, kind_id: String) -> void:
	if not _valid(row):
		return
	_kind[row] = kind_id
	_revision += 1
```

- [ ] **Step 4: Invert the two tests §4.4 names**

`tests/test_tenancy.gd:120-122` and the `Tenancy.new(6)` calls throughout the file become `Tenancy.new(6, 6)`:

```gdscript
func test_add_row_extends_tenancy_with_a_vacant_row() -> void:
	t.add_row()
	assert_eq(t.rows(), 7)
	assert_true(t.is_vacant(6), "a purchased floor is leased, not granted")
```

- [ ] **Step 5: Run the full suite**

Expected: `tests/test_game_state.gd:134` now fails — that is Task 9's, and this task's `GameState` call site still passes one argument. Fix the constructor call in `sim/game_state.gd:39` to `Tenancy.new(rows, rows)` as a temporary faithful value (Task 9 replaces it with the roster length), so the suite stays green.

Expected: 403 passing.

- [ ] **Step 6: Commit**

```bash
git add sim/tenancy.gd sim/game_state.gd tests/test_tenancy.gd
git commit -m "Tenancy carries a kind, and rows past the roster arrive vacant

A purchased floor arrived tenanted, because add_row delegates to the same
helper the constructor uses. With no kind that floor cannot spawn, price a
fare, or draw a sparkline -- a state reachable in the first minutes of play
through the game's main progression verb.

The rule is by row index, not by entry point: _append_row is shared, so
flipping it would empty a new building, and vacating only in add_row would
leave a tall constructed building fully tenanted and kindless.

Kind clears when the tenant leaves, which is the half of the persistence rule
that makes replacing a tenant cost something."
```

---

### Task 8: `TrafficSource` and the source-driven spawn path

**Files:**
- Create: `sim/traffic_source.gd`
- Modify: `sim/traffic_spawner.gd` — add `spawn_from_sources`, add the RNG seam
- Test: `tests/test_traffic_spawner.gd`

**Interfaces:**
- Consumes: `TenantKind` (Task 4).
- Produces:
  - `TrafficSource.new(floor: int, kind: TenantKind, fare_multiplier: float)`; fields `floor_row`, `kind`, `fare_multiplier`; `rate_at(minute) -> float`
  - `TrafficSpawner.spawn_from_sources(minute: int, sources: Array[TrafficSource], lobby_tenanted: bool) -> Array[Passenger]`
  - `TrafficSpawner.rng` — a duck-typed member the tests swap

Added **alongside** the existing `spawn_for_tick` so this task lands green; Task 10 cuts over and deletes the old path.

- [ ] **Step 1: Write the failing test**

```gdscript
class CountingRng:
	var draws: int = 0
	var _next: float
	func _init(next_value: float) -> void:
		_next = next_value
	func randf() -> float:
		draws += 1
		return _next
	func randi_range(a: int, b: int) -> int:
		draws += 1
		return a

func _sources(n: int, kind: TenantKind) -> Array[TrafficSource]:
	var out: Array[TrafficSource] = []
	for i in range(n):
		out.append(TrafficSource.new(i, kind, 1.0))
	return out

func test_the_draw_count_is_independent_of_source_count() -> void:
	# Pin the BRANCH first: a 40-source building has a larger total and so a
	# larger p, which means a different branch and a different draw count for
	# reasons that have nothing to do with the property being tested. An RNG
	# returning 0.0 makes both take the spawning path (the guard is
	# `if randf() >= per_tick: return`), and only then is a count comparison
	# meaningful.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var kind := cat.kind("apartments")

	var small := TrafficSpawner.new(1)
	small.rng = CountingRng.new(0.0)
	small.spawn_from_sources(8, _sources(6, kind), true)

	var large := TrafficSpawner.new(1)
	large.rng = CountingRng.new(0.0)
	large.spawn_from_sources(8, _sources(40, kind), true)

	assert_eq(large.rng.draws, small.rng.draws,
		"the weighted pick costs a constant number of draws, not one per source")

func test_a_tenanted_lobby_generates_only_interfloor_trips() -> void:
	# The shipped starting building puts Shops on floor 0, so this is the
	# default code path from the first frame -- an inbound trip for floor 0
	# would be lobby -> lobby.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(99)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(3, cat.kind("apartments"), 1.0),
	]
	for tick in range(20000):
		for p in s.spawn_from_sources(9, sources, true):
			if p.source_row == 0:
				assert_ne(p.origin_row, p.destination_row, "a trip must go somewhere")

func test_the_fare_comes_from_the_kind_and_the_floors_class() -> void:
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(7)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(2, cat.kind("office"), 1.8),
		TrafficSource.new(5, cat.kind("office"), 1.8),
	]
	var seen := false
	for tick in range(20000):
		for p in s.spawn_from_sources(8, sources, true):
			assert_almost_eq(p.fare, 4.0 * 1.8, 1e-5)
			seen = true
	assert_true(seen, "the fixture must actually spawn something")
```

- [ ] **Step 2: Run and watch it fail**

Expected: parse error — `TrafficSource` does not exist.

- [ ] **Step 3: Write `sim/traffic_source.gd`**

```gdscript
class_name TrafficSource
extends RefCounted

## One tenanted floor, as the spawner sees it: what it generates and what its
## trips are worth. Exists so the spawner never learns about Tenancy or Fitout
## -- it is handed a plain array and knows nothing about where it came from.

var floor_row: int
var kind: TenantKind
var fare_multiplier: float

func _init(p_floor: int, p_kind: TenantKind, p_multiplier: float) -> void:
	floor_row = p_floor
	kind = p_kind
	fare_multiplier = p_multiplier

func rate_at(minute: int) -> float:
	return kind.rate_at(minute)
```

- [ ] **Step 4: Add the seam and the new method to `sim/traffic_spawner.gd`**

```gdscript
## A duck-typed member rather than a RandomNumberGenerator subclass: declaring
## randf() on a subclass of a native class trips NATIVE_METHOD_OVERRIDE, and
## the draw-count test needs to swap in a counter.
var rng = RandomNumberGenerator.new()

const LOBBY := 0

## One Bernoulli trial per tick against the SUMMED rate, then a weighted pick
## of which source produced it. The alternative -- a trial per occupied floor
## -- would be forty draws a tick at the cap and would make the seed sequence
## depend on building height.
##
## `lobby_tenanted` decides whether the lobby is a usable endpoint. When floor 0
## is vacant it is neither an origin nor a destination, so every kind's inbound
## and outbound weights collapse into interfloor -- the same collapse applied to
## a tenant ON floor 0, whose lobby trips would otherwise be lobby -> lobby.
func spawn_from_sources(minute: int, sources: Array[TrafficSource],
		lobby_tenanted: bool) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if sources.size() < 2:
		return out
	var total := 0.0
	for s in sources:
		total += s.rate_at(minute)
	if total <= 0.0:
		return out
	if rng.randf() >= total / float(SimClock.TICKS_PER_MINUTE):
		return out

	var pick := rng.randf() * total
	var chosen: TrafficSource = sources[sources.size() - 1]
	var running := 0.0
	for s in sources:
		running += s.rate_at(minute)
		if pick < running:
			chosen = s
			break

	var origin := chosen.floor_row
	var destination := _destination_for(chosen, sources, minute, lobby_tenanted)
	if destination == chosen.floor_row:
		return out
	if destination == -1:
		origin = LOBBY
		destination = chosen.floor_row

	out.append(Passenger.new(origin, destination, base_patience_ticks,
		chosen.kind.base_fare * chosen.fare_multiplier, chosen.floor_row))
	return out

## Returns the destination floor, or -1 to mean "this is an inbound trip, so
## swap the endpoints". Collapses to interfloor whenever the lobby is not a
## usable endpoint for this source.
func _destination_for(chosen: TrafficSource, sources: Array[TrafficSource],
		minute: int, lobby_tenanted: bool) -> int:
	var lobby_usable := lobby_tenanted and chosen.floor_row != LOBBY
	var roll := rng.randf()
	if lobby_usable:
		if roll < chosen.kind.inbound_at(minute):
			return -1
		if roll < chosen.kind.inbound_at(minute) + chosen.kind.outbound_at(minute):
			return LOBBY
	var others: Array[TrafficSource] = []
	for s in sources:
		if s.floor_row != chosen.floor_row:
			others.append(s)
	if others.is_empty():
		return chosen.floor_row          # caller drops it
	return others[rng.randi_range(0, others.size() - 1)].floor_row
```

- [ ] **Step 5: Import, run the full suite, commit**

Expected: 407 passing.

```bash
git add sim/traffic_source.gd sim/traffic_spawner.gd tests/test_traffic_spawner.gd
git commit -m "Add the source-driven spawn path alongside the old one

One Bernoulli trial per tick against the summed rate, then a weighted pick of
which floor produced it -- so the RNG cost stays independent of building
height rather than becoming forty draws a tick at the cap.

The lobby is only an endpoint when it can be one. A vacant floor 0 is neither
an origin nor a destination, and a tenant ON floor 0 would otherwise generate
lobby-to-lobby trips, so both cases collapse the directional weights into
interfloor.

The RNG is a duck-typed member, not a RandomNumberGenerator subclass:
declaring randf() on a subclass of a native class trips
NATIVE_METHOD_OVERRIDE, and the draw-count test needs to swap a counter in.

Added beside spawn_for_tick rather than replacing it, so this lands green."
```

---

### Task 9: `GameState` — catalog, roster, and one growth loop

**Files:**
- Modify: `sim/game_state.gd:33-56`
- Modify: `tests/test_game_state.gd:130-134`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: `TenantCatalog` (4), `Fitout` (5), `Tenancy(row_count, tenanted_prefix)` (7).
- Produces: `GameState.DEFAULT_ROSTER: Array[String]`; `GameState.new(rows, shafts, seed, catalog_path := "res://data/tenants.json")`; `is_valid() -> bool`; `catalog: TenantCatalog`; `fitout: Fitout`; `_grow_per_floor_containers() -> void`.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_tall_new_building_tenants_only_the_roster() -> void:
	# The state every --board= session and every pre-restore decode starts
	# from. Neither the buy("row") test nor the save round-trips cover it:
	# both pass whether or not _init applies the roster limit.
	var tall := GameState.new(12, 1, 4242)
	for row in range(6):
		assert_false(tall.tenancy.is_vacant(row))
		assert_ne(tall.tenancy.kind_at(row), "")
	for row in range(6, 12):
		assert_true(tall.tenancy.is_vacant(row), "row %d" % row)
		assert_eq(tall.tenancy.kind_at(row), "")
		assert_eq(tall.fitout.tier_at(row), 1)

func test_the_starting_roster_is_shops_over_apartments() -> void:
	assert_eq(gs.tenancy.kind_at(0), "shops")
	for row in range(1, 6):
		assert_eq(gs.tenancy.kind_at(row), "apartments")

func test_buying_a_row_grows_every_per_floor_container() -> void:
	gs.economy.accrue(1e9)
	assert_true(gs.buy("row"))
	assert_eq(gs.building.row_count, 7)
	assert_eq(gs.tenancy.rows(), 7)
	assert_eq(gs.fitout.rows(), 7, "one loop grows every container")
	assert_true(gs.tenancy.is_vacant(6), "a purchased floor is leased, not granted")
	assert_eq(gs.tenancy.kind_at(6), "")
	assert_eq(gs.fitout.tier_at(6), 1)

func test_a_malformed_catalog_makes_the_state_invalid() -> void:
	var bad := GameState.new(6, 1, 1, "res://data/does_not_exist.json")
	assert_false(bad.is_valid())
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `DEFAULT_ROSTER`, `fitout`, `catalog` and `is_valid` do not exist.

- [ ] **Step 3: Implement**

```gdscript
## The starting assignment: six kind ids, one per row from the lobby up. NOT
## the catalog's length -- adding a seventh KIND must not tenant a seventh ROW.
## Both the tenanted-row count and those rows' kinds derive from this one list,
## so they cannot drift.
const DEFAULT_ROSTER: Array[String] = ["shops", "apartments", "apartments",
	"apartments", "apartments", "apartments"]

var catalog: TenantCatalog
var fitout: Fitout

var _valid: bool = true

func _init(rows: int, shafts: int, p_seed: int,
		catalog_path := "res://data/tenants.json") -> void:
	clock = SimClock.new()
	building = Building.new(rows, shafts)
	spawner = TrafficSpawner.new(p_seed)
	spawner.load_curve("res://data/traffic_walkup.json")
	economy = Economy.new()

	# Before Tenancy, which needs the roster length. Nothing constructed above
	# needs the catalog, so this slots in with no cycle.
	catalog = TenantCatalog.new()
	if not catalog.load_from(catalog_path):
		_valid = false
		push_error("tenant catalog is malformed or missing: %s" % catalog_path)

	var prefix := mini(building.row_count, DEFAULT_ROSTER.size())
	tenancy = Tenancy.new(building.row_count, prefix)
	fitout = Fitout.new(building.row_count)
	for row in range(prefix):
		tenancy.set_kind(row, DEFAULT_ROSTER[row])

	upgrades = Upgrades.new()
	upgrades.load_defs("res://data/upgrades.json")
	metrics = Metrics.new()
	auto = AutoDispatch.new()

## RefCounted cannot fail in _init, so construction records the failure and the
## boot path checks it. SaveCodec.decode returns null rather than handing back a
## poisoned state.
func is_valid() -> bool:
	return _valid
```

Replace the inline tenancy catch-up in `buy()`:

```gdscript
	var ok := upgrades.purchase(id, economy, building)
	if ok:
		_grow_per_floor_containers()
		_resync_policies()
	return ok

## ONE loop for every per-floor container. Two identical loops is how a
## container gets forgotten; the historic desync this replaces is pinned by
## test_buying_a_row_grows_every_per_floor_container, and Spec B adds a third
## container to this function rather than a third loop beside it.
func _grow_per_floor_containers() -> void:
	while tenancy.rows() < building.row_count:
		tenancy.add_row()
	while fitout.rows() < building.row_count:
		fitout.add_row()
```

- [ ] **Step 4: Update the inverted test**

`tests/test_game_state.gd:130-134` is replaced by `test_buying_a_row_grows_every_per_floor_container` from Step 1 — delete the old one.

- [ ] **Step 5: Run the full suite and commit**

Expected: 410 passing.

```bash
git add sim/game_state.gd tests/test_game_state.gd
git commit -m "GameState loads the catalog, applies the roster, grows containers once

DEFAULT_ROSTER is the starting ASSIGNMENT, not the catalog. Both the count of
tenanted rows and those rows' kinds read the same array, so adding a seventh
kind cannot tenant a seventh row.

Rows past the roster arrive vacant with no kind, which is the state every
--board= session and every pre-restore decode starts from -- and which
neither the buy test nor the save round-trips would have caught.

One _grow_per_floor_containers replaces the inline tenancy loop. Two
identical loops is how a container gets forgotten, and Spec B adds a third."
```

---

### Task 10: The source cache, and the cutover

**Files:**
- Modify: `sim/game_state.gd` — `_spawn`, cache, revision baseline
- Modify: `sim/traffic_spawner.gd` — delete `spawn_for_tick`, `curve`, `rate_at_minute`, `base_fare`, `REFERENCE_ROWS`, and the `:62-64` / `:69-75` docstrings
- Modify: `data/traffic_walkup.json` — drop `base_fare`
- Rewrite: `tests/test_traffic_spawner.gd` (all 14 `spawn_for_tick` sites plus the four `rate_at_minute`/`curve` functions)
- Modify: `tests/test_game_state.gd:216`, `:235-254`, `:261`; `tests/test_auto_dispatch.gd:13`, `:136`

**Interfaces:**
- Consumes: `TrafficSource` (8), `Fitout`/`Tenancy` revisions (5, 6), catalog (9).
- Produces: `GameState._sources() -> Array[TrafficSource]` (cached).

**This is the largest task in the plan** — the spawner's signature changes and the test suite is its biggest consumer (§11.1). Three symbols die, not one.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_the_source_cache_rebuilds_when_a_floor_vacates() -> void:
	while gs.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(3)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(3))
	for s in gs._sources():
		assert_ne(s.floor_row, 3, "a vacated floor stops generating traffic")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `_sources` does not exist.

- [ ] **Step 3: Add the cache**

```gdscript
var _source_cache: Array[TrafficSource] = []
var _source_revision: int = -1

## Rebuilt when EITHER container's revision moves. Compared with != rather than
## >: both counters only increment today, so > would be correct -- but it stops
## working silently the moment any future path swaps a container into a live
## GameState and resets one to zero.
func _sources() -> Array[TrafficSource]:
	var revision := tenancy.revision() + fitout.revision()
	if revision != _source_revision:
		_source_cache = []
		for row in range(building.row_count):
			if tenancy.is_vacant(row):
				continue
			var k := catalog.kind(tenancy.kind_at(row))
			if k == null:
				continue
			_source_cache.append(TrafficSource.new(row, k,
				catalog.fare_multiplier(fitout.tier_at(row))))
		_source_revision = revision
	return _source_cache

func _spawn() -> void:
	for p in spawner.spawn_from_sources(clock.sim_minute(), _sources(),
			not tenancy.is_vacant(0)):
		building.enqueue(p)
		passenger_spawned.emit(p)
```

- [ ] **Step 4: Delete the old spawner API**

From `sim/traffic_spawner.gd`, remove `spawn_for_tick`, `rate_at_minute`, `curve`, `base_fare`, `REFERENCE_ROWS`, and the docstrings at `:62-64` and `:69-75`. `load_curve` survives, reading only `base_patience_ticks` — patience stays building-wide (§14) and the curve file remains the calibration reference.

Remove the `"base_fare"` key from `data/traffic_walkup.json`.

- [ ] **Step 5: Rewrite the spawner tests**

All 14 `spawn_for_tick` sites (lines 33, 34, 45, 46, 57, 64, 70, 77, 82, 109, 120, 137, 138, 151) stop compiling, as do the four functions using `rate_at_minute`/`curve` (`:10`, `:13`, `:17`, `:21`). Three properties are carried across **deliberately**, not ported:

```gdscript
func test_a_trip_must_go_somewhere() -> void:
	# Was :71. The only guard against a degenerate lobby-to-lobby trip, which
	# is exactly what the floor-0 collapse rule exists to prevent.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(31)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(4, cat.kind("apartments"), 1.0),
	]
	for tick in range(20000):
		for p in s.spawn_from_sources(12, sources, true):
			assert_ne(p.origin_row, p.destination_row)

func test_rush_hour_generates_more_than_the_overnight_trough() -> void:
	# Was :22, which used the deleted rate_at_minute. The property is worth
	# keeping; the symbol is not.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_gt(apt.rate_at(7), apt.rate_at(2))

func test_the_curve_wraps_around_the_day() -> void:
	# Was :19, which compared rate_at_minute(8) with ITSELF and could not
	# fail. Its NAME claimed piecewise-constancy within a bucket, but under
	# one-bucket-per-hour with an integer minute index there are no minutes
	# "inside" a bucket to be constant across -- the property has no referent,
	# which is presumably how it decayed into a tautology unnoticed.
	#
	# What is actually worth pinning at that boundary is the wrap, so this
	# carries :19 across as the check it can meaningfully make.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_almost_eq(apt.rate_at(8), apt.rate_at(8 + 24), 1e-9,
		"the same hour a day later is the same bucket")
	assert_almost_eq(apt.rate_at(0), apt.rate_at(-24), 1e-9,
		"and posmod handles a negative index")
```

`:84`'s `p.fare == spawner.base_fare` dies with `base_fare`; its replacement is Task 8's `test_the_fare_comes_from_the_kind_and_the_floors_class`. `:142-153`'s `REFERENCE_ROWS == 6` is replaced by Task 4's calibration test.

- [ ] **Step 6: Fix the silencing idiom's four sites**

`spawner.curve = PackedFloat32Array()` no longer exists. Replace with a state that has no sources — `tests/test_game_state.gd:216`, `:261` (`quiet_state`, behind six parked-car tests at `:267, 280, 289, 300, 311, 321`), and `tests/test_auto_dispatch.gd:13`, `:136`:

```gdscript
func _silence(state: GameState) -> void:
	# One tenanted floor cannot generate a trip, so nothing spawns. Replaces
	# `spawner.curve = PackedFloat32Array()`, which set a field that is gone.
	for row in range(1, state.building.row_count):
		state.tenancy.restore_row(row, 1.0, true, 0)
```

- [ ] **Step 7: Re-derive the two opening-traffic tests**

`tests/test_game_state.gd:235-250` asserts >4 spawns in the opening three minutes, calibrated to a curve shape §5.6 deliberately changes; `:252-254` calls the deleted `rate_at_minute`. Re-derive from the roster: at `START_MINUTE = 6` the starting building's summed rate is `shops.rate_at(6) + 5 × apartments.rate_at(6)` = `0.0 + 5 × 0.5` = **2.5** trips/min, so three minutes expect ~7.5 spawns.

```gdscript
func test_the_opening_minutes_carry_real_traffic() -> void:
	var spawned := 0
	gs.passenger_spawned.connect(func(_p): spawned += 1)
	gs.tick(SimClock.TICKS_PER_MINUTE * 3)
	# 1 shops + 5 apartments at hour 6 = 0.0 + 5(0.5) = 2.5 trips/min,
	# so ~7.5 over three minutes. Four is a comfortable floor for a
	# Bernoulli draw at this rate.
	assert_gt(spawned, 4, "the opening is a rush, not a trickle")
```

- [ ] **Step 8: Run the full suite and commit**

Expected: green. Report the count.

```bash
git add sim/ data/traffic_walkup.json tests/
git commit -m "Cut over to source-driven spawning and delete the old API

Three symbols die together -- spawn_for_tick, rate_at_minute and curve --
and the test suite is the spawner's largest consumer: fourteen call sites in
test_traffic_spawner.gd plus four more functions that used only the other
two symbols.

Three properties are carried across deliberately rather than ported: the
guard that a trip must go somewhere, rush > overnight, and bucket
flatness -- the last one FIXED, since it compared a value with itself and
could not fail.

REFERENCE_ROWS scaling is deleted rather than kept: a per-floor rate summed
over occupied floors IS that scaling, and keeping both would give a
forty-floor tower 40/6x the traffic it already generates.

The cache compares tenancy.revision() + fitout.revision() with != rather
than >, so it does not depend on the monotonicity argument holding forever."
```

---

### Task 11: `lease()` replaces `relet()`

**Files:**
- Modify: `sim/tenancy.gd:27`, `:116-129` — `RELET_COST`, `relet_cost`, `relet`
- Modify: `sim/game_state.gd:58-76`
- Modify: `view/building_view.gd:313`
- Rewrite: `tests/test_tenancy.gd:68,80,91,99,108`; `tests/test_game_state.gd:147-190`

**Interfaces:**
- Consumes: catalog (4), fitout (5), tenancy kinds (7).
- Produces: `GameState.lease_cost(row: int, kind_id: String) -> float`; `GameState.lease(row: int, kind_id: String) -> bool`; `GameState.available_kinds(row: int) -> Array[TenantKind]`.

The flat `RELET_COST := 40.0` becomes a per-kind `lease_cost`, and `relet_cost(_row)` **deliberately ignores its row** — which a per-kind price cannot (§8.2).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_leasing_charges_the_kinds_price_and_sets_the_kind() -> void:
	gs.economy.accrue(1000.0)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	var before := gs.economy.cash
	assert_true(gs.lease(3, "apartments"))
	assert_false(gs.tenancy.is_vacant(3))
	assert_eq(gs.tenancy.kind_at(3), "apartments")
	assert_almost_eq(gs.economy.cash, before - 60.0, 1e-6)

func test_a_kind_above_the_floors_class_is_refused() -> void:
	gs.economy.accrue(1e6)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	assert_false(gs.lease(3, "law_firm"), "class 1 cannot take a tier-3 tenant")
	assert_true(gs.tenancy.is_vacant(3))

func test_only_the_cheapest_eligible_kind_is_free_below_two_tenants() -> void:
	# The guarantee must be exact -- a $0 player can always recover -- without
	# rewarding collapse. An already-upgraded floor would otherwise hand out a
	# free premium tenant.
	for row in range(1, 6):
		gs.tenancy.restore_row(row, 1.0, true, 0)
	gs.fitout.set_tier(3, 3)
	gs.economy.cash = 0.0
	assert_false(gs.lease(3, "law_firm"), "the expensive one is not free")
	assert_true(gs.lease(3, "apartments"), "the cheapest eligible one is")

func test_lease_reads_the_cost_before_mutating_tenancy() -> void:
	# Cost derives from tenanted_count(), which leasing increments, so the
	# order decides whether the last row costs nothing or full price.
	for row in range(1, 6):
		gs.tenancy.restore_row(row, 1.0, true, 0)
	gs.economy.cash = 0.0
	var before := gs.economy.cash
	assert_true(gs.lease(3, "apartments"))
	assert_almost_eq(gs.economy.cash, before, 1e-6, "free, not $60")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `lease` does not exist.

- [ ] **Step 3: Implement**

In `sim/tenancy.gd`, delete `RELET_COST`, `relet_cost` and `relet`; rewrite the `MIN_ROWS_FOR_TRAFFIC` docstring at `:116-118` and the class docstring at `:15-19`, both of which state the old arithmetic rationale:

```gdscript
## Free while the player cannot earn. Under directional traffic a lone tenant
## COULD generate lobby trips, so this is now a deliberate policy guard rather
## than arithmetic -- but the guarantee it protects is unchanged: there must
## always be something a $0 player can take.
const MIN_ROWS_FOR_TRAFFIC := 2

func lease(row: int, kind_id: String) -> void:
	if not _valid(row):
		return
	_vacant[row] = false
	_satisfaction[row] = 1.0
	_move_out_left[row] = 0
	_kind[row] = kind_id
	_revision += 1
```

In `sim/game_state.gd`, replace the `relet` docstring (`:58-66`) and function:

```gdscript
## Lease a vacant floor to a chosen kind.
##
## The cost is read BEFORE tenancy is mutated: it derives from tenanted_count(),
## which leasing increments, so the order decides whether the last row costs
## nothing or full price.
##
## Refused here rather than merely greyed in the view, because a disabled
## button is bypassed by two taps queued during a stalled frame.
func lease(row: int, kind_id: String) -> bool:
	if row < 0 or row >= building.row_count:
		return false
	if not tenancy.is_vacant(row):
		return false
	var k := catalog.kind(kind_id)
	if k == null or k.requires_class > fitout.tier_at(row):
		return false
	var cost := lease_cost(row, kind_id)
	if not economy.spend(cost):
		return false
	tenancy.lease(row, kind_id)
	return true

## Below two tenants the CHEAPEST ELIGIBLE kind is free. Making every kind free
## would hand a floor already upgraded to class 3 a free Law Firm, which is a
## strategy rather than a safety net.
func lease_cost(row: int, kind_id: String) -> float:
	var k := catalog.kind(kind_id)
	if k == null:
		return INF
	if tenancy.tenanted_count() >= Tenancy.MIN_ROWS_FOR_TRAFFIC:
		return k.lease_cost
	var cheapest := catalog.cheapest_for_class(fitout.tier_at(row))
	return 0.0 if cheapest != null and cheapest.id == kind_id else k.lease_cost

func available_kinds(row: int) -> Array[TenantKind]:
	return catalog.available_for_class(fitout.tier_at(row))
```

- [ ] **Step 4: Rewrite the six `GameState` relet tests and five `Tenancy` ones**

`tests/test_game_state.gd:147-190` — each of `_charges_the_cost`, `_is_free_when_nothing_is_tenanted`, `_is_refused_when_unaffordable_and_charges_nothing`, `_is_refused_on_a_tenanted_row`, `_is_refused_outside_the_building`, `_reads_the_cost_before_reletting` gets a `lease` equivalent. The last is Step 1's `test_lease_reads_the_cost_before_mutating_tenancy`.

`tests/test_tenancy.gd:68,80,91,99,108` — five functions pinning relet pricing and restore; rewrite against `lease(row, kind_id)`.

- [ ] **Step 5: Fix `view/building_view.gd:313`**

`_state.tenancy.relet_cost(i)` is gone. Task 17 removes the price from the strip entirely; for now pass an empty string so the view compiles.

- [ ] **Step 6: Run the full suite and commit**

```bash
git add sim/ view/building_view.gd tests/
git commit -m "lease(row, kind) replaces relet(row)

A flat RELET_COST becomes a per-kind lease_cost, and relet_cost deliberately
ignored its row argument -- which a per-kind price cannot.

Below two tenants only the CHEAPEST ELIGIBLE kind is free. Making all of them
free would hand a floor already upgraded to class 3 a free Law Firm: the
class gate constrains a class-1 floor and does nothing for an upgraded one,
so the recovery rule was rewarding collapse rather than protecting against it.

The charge-before-mutate order survives: cost derives from tenanted_count,
which leasing increments."
```

---

### Task 12: `upgrade_class()` and the test that discriminates

**Files:**
- Modify: `sim/game_state.gd`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: catalog (4), fitout (5), source cache (10).
- Produces: `GameState.class_upgrade_cost(row: int) -> float`; `GameState.upgrade_class(row: int) -> bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_upgrading_a_tenanted_floor_changes_its_fare_on_the_next_spawn() -> void:
	# THE discriminating test. A class purchase mutates Fitout, not Tenancy,
	# so a Tenancy-scoped revision would leave the stale x1.00 cached until
	# the next tenancy event -- which on a well-served floor may be never.
	# The "new tenant is charged x1.80" test cannot catch that: a lease moves
	# the revision and rebuilds the cache, so it passes either way.
	gs.economy.accrue(1e6)
	var before := 0.0
	for s in gs._sources():
		if s.floor_row == 3:
			before = s.fare_multiplier
	assert_almost_eq(before, 1.0, 1e-9)
	assert_true(gs.upgrade_class(3))
	var after := 0.0
	for s in gs._sources():
		if s.floor_row == 3:
			after = s.fare_multiplier
	assert_almost_eq(after, 1.35, 1e-9,
		"the upgrade pays immediately, with no intervening tenancy event")

func test_a_class_upgrade_is_refused_when_unaffordable_or_maxed() -> void:
	gs.economy.cash = 10.0
	assert_false(gs.upgrade_class(3), "cannot afford $400")
	assert_eq(gs.fitout.tier_at(3), 1)
	gs.economy.accrue(1e6)
	assert_true(gs.upgrade_class(3))
	assert_true(gs.upgrade_class(3))
	assert_eq(gs.fitout.tier_at(3), 3)
	assert_false(gs.upgrade_class(3), "tier 3 is the top of the ladder")

func test_class_survives_a_tenant_change_and_kind_does_not() -> void:
	# The headline invariant: things built into the floor persist, things
	# built for the tenant leave with them.
	gs.economy.accrue(1e6)
	assert_true(gs.upgrade_class(3))
	assert_true(gs.upgrade_class(3))
	while gs.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(3)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(3))
	assert_eq(gs.tenancy.kind_at(3), "", "kind leaves with the tenant")
	assert_eq(gs.fitout.tier_at(3), 3, "class is built into the floor")

func test_a_new_tenant_on_a_class_three_floor_is_charged_the_multiplier() -> void:
	gs.economy.accrue(1e6)
	gs.upgrade_class(3)
	gs.upgrade_class(3)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	assert_true(gs.lease(3, "law_firm"))
	for s in gs._sources():
		if s.floor_row == 3:
			assert_almost_eq(s.kind.base_fare * s.fare_multiplier, 9.0 * 1.8, 1e-5)
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `upgrade_class` does not exist.

- [ ] **Step 3: Implement**

```gdscript
## The fare multiplier is why this is not inert on a tenanted floor. Class
## gates leasing and leasing only happens on vacancy, so a purchase with no
## live effect would pay nothing until the tenant left -- a button you
## rationally never press except in a crisis.
func class_upgrade_cost(row: int) -> float:
	var next := fitout.tier_at(row) + 1
	if next > catalog.max_tier():
		return INF
	return catalog.class_cost(next)

func upgrade_class(row: int) -> bool:
	if row < 0 or row >= building.row_count:
		return false
	var next := fitout.tier_at(row) + 1
	if next > catalog.max_tier():
		return false
	var cost := class_upgrade_cost(row)
	if not economy.spend(cost):
		return false
	fitout.set_tier(row, next)
	return true
```

- [ ] **Step 4: Run the full suite and commit**

```bash
git add sim/game_state.gd tests/test_game_state.gd
git commit -m "Add upgrade_class, and the test that can actually catch it failing

A class purchase mutates Fitout, not Tenancy. A revision scoped to Tenancy
alone would never move for one, leaving the stale x1.00 multiplier in the
cached traffic source until the next tenancy event -- which on a well-served
floor may be never. That is exactly the inert button the fare multiplier
exists to prevent.

The obvious test does not catch it: 'a new tenant on a class-3 floor is
charged x1.80' needs a lease, and a lease moves the revision and rebuilds the
cache, so it passes whether or not Fitout invalidates anything. The test that
discriminates upgrades an ALREADY TENANTED floor and asserts the fare changes
with no intervening tenancy event."
```

---

### Task 13: A move-out removes its waiting passengers, by source

**Files:**
- Modify: `sim/game_state.gd:_tick_once`
- Modify: `sim/building.gd` — add `remove_waiting_from_source`
- Test: `tests/test_game_state.gd`, `tests/test_building.gd`

**Interfaces:**
- Consumes: `accrue_for_tick`'s vacated rows (6), `Passenger.source_row` (2).
- Produces: `Building.remove_waiting_from_source(source_row: int) -> int` (count removed).

Queues are indexed by **`origin_row`** (`sim/building.gd:44`). An inbound trip `LOBBY → F` waits in `waiting[0]` with `source_row = F`, so clearing `waiting[F]` removes none of them — and clearing `waiting[0]` when floor 0 vacates would delete every *other* floor's inbound visitors (§5.4).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_move_out_removes_that_floors_waiting_passengers_from_every_queue() -> void:
	# The inbound case is the one that matters: those passengers stand in the
	# LOBBY queue, so a rule phrased over "that floor's queue" misses them
	# entirely -- and for inbound-heavy kinds that is most of the floor's
	# traffic.
	var mine := Passenger.new(0, 4, 900, 4.0, 4)     # inbound, belongs to 4
	var theirs := Passenger.new(0, 2, 900, 4.0, 2)   # inbound, belongs to 2
	var also_mine := Passenger.new(4, 0, 900, 4.0, 4)  # outbound, belongs to 4
	gs.building.enqueue(mine)
	gs.building.enqueue(theirs)
	gs.building.enqueue(also_mine)
	var cash_before := gs.economy.cash

	while gs.tenancy.satisfaction_at(4) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(4)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(4))

	var left: Array[Passenger] = []
	for row in range(gs.building.row_count):
		for p in gs.building.waiting_at(row):
			left.append(p)
	for p in left:
		assert_ne(p.source_row, 4, "no passenger from the vacated floor remains")
	var survivors := 0
	for p in left:
		if p.source_row == 2:
			survivors += 1
	assert_eq(survivors, 1, "another floor's lobby queue is untouched")
	assert_gte(gs.economy.cash, cash_before,
		"removal is not an expiry -- the failure was already charged")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — passengers with `source_row == 4` remain.

- [ ] **Step 3: Implement**

`sim/building.gd`:

```gdscript
## Removes every waiting passenger generated by `source_row`, from EVERY queue.
##
## Source-scoped, not queue-scoped: queues are indexed by origin, so an inbound
## trip belonging to floor F waits at the lobby. Clearing waiting[F] would miss
## all of them, and clearing waiting[0] when the lobby vacates would delete
## every other floor's visitors.
func remove_waiting_from_source(source_row: int) -> int:
	var removed := 0
	for row in range(waiting.size()):
		var survivors: Array[Passenger] = []
		for p in waiting[row]:
			if p.source_row == source_row:
				removed += 1
			else:
				survivors.append(p)
		waiting[row] = survivors
	return removed
```

`sim/game_state.gd:_tick_once`, replacing the bare `tenancy.accrue_for_tick()`:

```gdscript
		# The tenant left, so their visitors stop arriving. NOT charged as
		# expiries: the expiries that caused the move-out were already charged,
		# and charging again would double-penalise one failure.
		for row in tenancy.accrue_for_tick():
			building.remove_waiting_from_source(row)
```

- [ ] **Step 4: Run the full suite and commit**

```bash
git add sim/building.gd sim/game_state.gd tests/
git commit -m "A move-out removes its waiting passengers by source, not by queue

Waiting queues are indexed by origin_row, so an inbound trip belonging to
floor F stands in the LOBBY queue. Clearing waiting[F] removes none of them,
and for inbound-heavy kinds that is most of the floor's traffic -- so the
unbounded credit leak this exists to close would have survived intact.

The mirror is worse: any row including the lobby may vacate, and waiting[0]
holds every other floor's visitors, so a queue-scoped rule would silently
delete traffic belonging to the whole building.

Removed passengers are not charged as expiries. What remains is genuinely
bounded: passengers already aboard a car, capped by total car capacity."
```

---

### Task 14: `SaveCodec` v2

**Files:**
- Modify: `sim/save_codec.gd` — `VERSION`, `encode`, `decode`, `_is_usable`, docstring `:17-19`
- Test: `tests/test_save_codec.gd`

**Interfaces:**
- Consumes: catalog (4), fitout (5), tenancy kinds (7).
- Produces: `SaveCodec.VERSION = 2`; rows carry `kind` (String or `null`) and `class` (int).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_vacant_row_round_trips_as_a_null_kind() -> void:
	# The state a newly purchased floor is in, so this is the common case.
	var gs := GameState.new(6, 1, 7)
	gs.economy.accrue(1e9)
	gs.buy("row")
	var back := SaveCodec.decode(SaveCodec.encode(gs))
	assert_not_null(back)
	assert_true(back.tenancy.is_vacant(6))
	assert_eq(back.tenancy.kind_at(6), "")

func test_v2_round_trips_kind_and_class() -> void:
	var gs := GameState.new(6, 1, 7)
	gs.economy.accrue(1e6)
	gs.upgrade_class(2)
	var back := SaveCodec.decode(SaveCodec.encode(gs))
	assert_eq(back.fitout.tier_at(2), 2)
	assert_eq(back.tenancy.kind_at(0), "shops")

func test_a_v1_save_migrates() -> void:
	var data := _v1_save()
	var back := SaveCodec.decode(data)
	assert_not_null(back)
	assert_eq(back.fitout.tier_at(0), 1)
	assert_eq(back.tenancy.kind_at(0), "apartments")

func test_a_vacant_v1_row_migrates_with_no_kind() -> void:
	var data := _v1_save()
	(data["rows"] as Array)[2]["vacant"] = true
	var back := SaveCodec.decode(data)
	assert_true(back.tenancy.is_vacant(2))
	assert_eq(back.tenancy.kind_at(2), "", "a vacant floor has no tenant")

func test_a_kind_the_restored_class_cannot_lease_falls_back() -> void:
	# Independent validation lets this through: a known id skips the
	# unknown-id fallback and the class clamp never looks at the kind.
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array)[3]["kind"] = "law_firm"
	(data["rows"] as Array)[3]["class"] = 1
	var back := SaveCodec.decode(data)
	assert_eq(back.tenancy.kind_at(3), "apartments",
		"falls back to the cheapest eligible kind")

func test_a_short_v2_rows_array_is_refused() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array).resize(3)
	assert_null(SaveCodec.decode(data))

func test_an_out_of_range_class_bounds_to_the_top_tier() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array)[1]["class"] = 99
	var back := SaveCodec.decode(data)
	assert_eq(back.fitout.tier_at(1), 3, "bounded, not prevented")
```

Add a `_v1_save()` helper returning a `version: 1` dictionary with `rows` entries carrying only `satisfaction`, `vacant`, `move_out_left`.

- [ ] **Step 2: Run and watch it fail**

- [ ] **Step 3: Implement**

```gdscript
const VERSION := 2
const SUPPORTED_VERSIONS := [1, 2]
```

In `encode`, per row:

```gdscript
		rows.append({
			"satisfaction": state.tenancy.satisfaction_at(row),
			"vacant": state.tenancy.is_vacant(row),
			"move_out_left": state.tenancy.move_out_ticks_left(row),
			# null, not absent: v2 requires the field present, and a vacant or
			# newly purchased floor genuinely has no kind. Without an explicit
			# encoding "a missing kind is malformed" and "vacant floors have no
			# kind" contradict each other.
			"kind": null if state.tenancy.kind_at(row).is_empty() \
				else state.tenancy.kind_at(row),
			"class": state.fitout.tier_at(row),
		})
```

In `decode`, after constructing the state:

```gdscript
	var version := int(data["version"])
	var saved_rows: Array = data.get("rows", [])
	# v1 may fall through -- §4.3 defines what rows past the roster get.
	# v2 may not: a short array silently keeps a constructor default that
	# contradicts the save, and past the roster that default is VACANCY, i.e.
	# the silent loss of a floor the player leased.
	if version == 2 and saved_rows.size() < state.building.row_count:
		return null

	for row in range(mini(saved_rows.size(), state.building.row_count)):
		var r: Dictionary = saved_rows[row]
		if version == 2 and not (r.has("kind") and r.has("class")):
			return null
		var vacant := bool(r.get("vacant", false))
		state.tenancy.restore_row(row, float(r.get("satisfaction", 1.0)),
			vacant, int(r.get("move_out_left", 0)))
		state.fitout.set_tier(row, clampi(int(r.get("class", 1)), 1,
			state.catalog.max_tier()))
		state.tenancy.set_kind(row, _restore_kind(state, row, version, r, vacant))
	return state

## A vacant row has no kind. A v1 row infers `apartments`; a v2 row carries an
## explicit id or null. Either way the result is cross-checked against the
## restored class, because independent validation lets {class: 1, kind:
## "law_firm"} through -- a known id skips the unknown-id fallback and the
## class clamp never looks at the kind.
static func _restore_kind(state: GameState, row: int, version: int,
		r: Dictionary, vacant: bool) -> String:
	if vacant:
		return ""
	var id := ""
	if version == 1:
		id = "apartments"
	else:
		var raw: Variant = r["kind"]
		id = "" if raw == null else str(raw)
	if id.is_empty():
		return ""
	var k := state.catalog.kind(id)
	var tier := state.fitout.tier_at(row)
	if k == null or k.requires_class > tier:
		var fallback := state.catalog.cheapest_for_class(tier)
		return "" if fallback == null else fallback.id
	return id
```

Update `_is_usable` to accept `SUPPORTED_VERSIONS`, and rewrite the docstring at `:17-19` to say which branch applies to which version rather than stating refusal absolutely.

- [ ] **Step 4: Run the full suite and commit**

```bash
git add sim/save_codec.gd tests/test_save_codec.gd
git commit -m "SaveCodec v2: kind and class per row, with a null encoding

'No kind' needs an explicit representation. v2 requires the field present, so
without one 'a missing kind is malformed' and 'vacant floors have no kind'
contradict each other, and a save containing a newly bought floor is either
rejected or restored with a tenant it never had.

Restoration is cross-checked rather than validated field by field:
{class: 1, kind: law_firm} passes both independent checks -- a known id skips
the unknown-id fallback and the class clamp never looks at the kind.

A short v2 rows array is refused. Past the roster the constructor default is
vacancy, so falling through would silently drop a floor the player leased."
```

---

### Task 15: `HallColumn`

**Files:**
- Create: `view/hall_column.gd`
- Modify: `view/building_view.gd` — insert the column, ghost drag forwarding, `rebuild()` ordering
- Test: `tests/test_board_input.gd`

**Interfaces:**
- Consumes: `Gesture`, `PointerEvents`, `BoardCoords`.
- Produces: `HallColumn` with `signal floor_selected(floor_index: int)` and `signal pan_requested(delta: Vector2)`; `setup(coords: BoardCoords)`.

`HallColumn` **introduces** left-region panning — `BuildingView._gui_input` reads releases only and rows are `MOUSE_FILTER_IGNORE`, so dragging on the left does nothing today (§7).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_tap_on_the_hall_selects_the_floor_it_looks_like_after_scrolling() -> void:
	var root := _board(20, 3)
	root.view.pan_board_by(Vector2(0, 300))
	var target := 12
	var y := root.view.coords.band_centre_y(target)
	_tap(root.view.hall_column, Vector2(100, y))
	assert_eq(root.last_selected_floor, target,
		"a board wrong by a scroll offset is self-consistent and catastrophic")

func test_a_drag_on_the_hall_pans_and_does_not_select() -> void:
	var root := _board(20, 3)
	root.last_selected_floor = -1
	var before := root.view.coords.scroll_offset
	_drag(root.view.hall_column, Vector2(100, 400), Vector2(100, 250))
	assert_eq(root.last_selected_floor, -1, "a pan is not a selection")
	assert_ne(root.view.coords.scroll_offset, before)

func test_a_tap_on_the_ghost_band_buys_a_floor_and_opens_no_panel() -> void:
	# y_to_floor CLAMPS above the roof, so a hall column that won this
	# contest would open the top floor's panel instead of buying a floor --
	# exactly when the roof is scrolled into view.
	var root := _board(8, 2)
	root.last_selected_floor = -1
	var rows_before := root.state.building.row_count
	root.state.economy.accrue(1e9)
	_tap_ghost(root.view)
	assert_eq(root.state.building.row_count, rows_before + 1)
	assert_eq(root.last_selected_floor, -1)

func test_the_ghost_still_wins_after_a_rebuild() -> void:
	# rebuild() moves the shaft viewport last, so "the ghost is the last
	# child" holds only on the first build.
	var root := _board(8, 2)
	root.state.economy.accrue(1e9)
	root.view.rebuild()
	root.last_selected_floor = -1
	var rows_before := root.state.building.row_count
	_tap_ghost(root.view)
	assert_eq(root.state.building.row_count, rows_before + 1)
	assert_eq(root.last_selected_floor, -1)

func test_a_tap_at_exactly_the_shaft_boundary_reaches_the_shaft() -> void:
	# Rewritten from test_a_tap_past_the_strip_reaches_the_column_not_the_confirm.
	var root := _board(8, 2)
	_tap(root.view, Vector2(BuildingView.SHAFT_AREA_X, 400))
	assert_eq(root.last_selected_floor, -1, "x = 240 belongs to the shaft")
```

- [ ] **Step 2: Run and watch it fail**

- [ ] **Step 3: Write `view/hall_column.gd`**

```gdscript
class_name HallColumn
extends Control

## The hall region's touch target: TAP opens that floor's panel, DRAG pans the
## board. One input path rather than _gui_input on every FloorRow, so a drag
## crossing a row boundary cannot become ambiguous.
##
## What it takes over from is NOT FloorRow -- FloorRow itself is
## MOUSE_FILTER_IGNORE. It is BuildingView._gui_input, the relet tap path.
##
## It INTRODUCES left-region panning rather than preserving it: today
## BuildingView._gui_input reads releases only, so dragging on the left does
## nothing at all.
##
## Spans the full board height so its local y IS board y and a touch goes
## straight to y_to_floor with no offset arithmetic -- the property that kept
## ShaftColumn correct once the board began to scroll.

signal floor_selected(floor_index: int)
signal pan_requested(delta: Vector2)

var _gesture: Gesture
var _coords: BoardCoords

func setup(coords: BoardCoords) -> void:
	_coords = coords
	_gesture = Gesture.new(coords)

func _gui_input(event: InputEvent) -> void:
	if PointerEvents.is_press(event):
		_gesture.press(event.position, 0)
	elif PointerEvents.is_release(event):
		if _gesture.release() == Gesture.Result.TAP:
			# Belt and braces against the roof clamp: y_to_floor returns
			# top_floor for any y above the building, so a tap in the sky
			# would otherwise select the top floor rather than doing nothing.
			if event.position.y >= _coords.floor_to_y(_coords.top_floor):
				floor_selected.emit(_gesture.selected_row())
	elif PointerEvents.is_drag(event):
		_gesture.move(event.position)
		if _gesture.is_panning():
			var delta := _gesture.take_pan_delta()
			if delta != Vector2.ZERO:
				pan_requested.emit(delta)
```

- [ ] **Step 4: Wire it into `BuildingView`**

Add the column at `x ∈ [0, FloorRow.STRIP_RIGHT)`, spanning the full board height, **inserted before the ghost row** so the ghost keeps its band. Re-establish that ordering inside `rebuild()`, which moves `_shaft_viewport` last (`:76`). Give the ghost row drag forwarding to `pan_requested`, as `ShaftColumn` has.

- [ ] **Step 5: Import, run the suite, commit**

```bash
git add view/hall_column.gd view/building_view.gd tests/test_board_input.gd
git commit -m "Add HallColumn: tap the hall to open a floor, drag to pan

One input path for the whole hall region rather than _gui_input per row, so
a drag crossing a row boundary cannot become ambiguous. Its local y is board
y, so a touch goes straight to y_to_floor with no offset arithmetic.

It takes over from BuildingView._gui_input, not from FloorRow -- FloorRow is
already MOUSE_FILTER_IGNORE -- and it INTRODUCES left-region panning rather
than preserving it, since the existing handler reads releases only.

The ghost band keeps its tap. y_to_floor clamps above the roof, so a hall
column that won that contest would open the top floor's panel instead of
buying a floor, precisely when the roof is scrolled into view. The ordering
is re-established on rebuild(), which moves the shaft viewport last."
```

---

### Task 16: `DaySparkline`

**Files:**
- Create: `view/day_sparkline.gd`
- Test: `tests/test_day_sparkline.gd`

**Interfaces:**
- Consumes: `TenantKind` (4).
- Produces: `DaySparkline.show_kind(kind: TenantKind)`; `bar_heights() -> PackedFloat32Array`; `segment_shares(bucket: int) -> Vector3` (inbound, outbound, interfloor).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_it_draws_one_bar_per_simulated_hour() -> void:
	var s := DaySparkline.new()
	s.size = Vector2(240, 48)
	s.show_kind(_apartments())
	assert_eq(s.bar_heights().size(), 24)

func test_bar_height_is_proportional_to_rate() -> void:
	var s := DaySparkline.new()
	s.size = Vector2(240, 48)
	var k := _apartments()
	s.show_kind(k)
	var h := s.bar_heights()
	# hour 7 is the out-peak (1.2) and hour 2 the overnight trough (0.1)
	assert_almost_eq(h[7] / h[2], k.rate_at(7) / k.rate_at(2), 1e-3)

func test_the_segments_match_the_mix() -> void:
	var s := DaySparkline.new()
	s.size = Vector2(240, 48)
	var k := _apartments()
	s.show_kind(k)
	var seg := s.segment_shares(7)
	assert_almost_eq(seg.x, k.inbound_at(7), 1e-5)
	assert_almost_eq(seg.y, k.outbound_at(7), 1e-5)
	assert_almost_eq(seg.x + seg.y + seg.z, 1.0, 1e-5)
```

- [ ] **Step 2: Run and watch it fail**

- [ ] **Step 3: Implement `view/day_sparkline.gd`**

A `Control` with `_draw()`: 24 bars, height proportional to `rate_at(h)` normalised to the kind's own maximum, each split vertically into up to three coloured segments by that hour's mix. `bar_heights()` and `segment_shares()` are the testable seams; `_draw()` reads them.

- [ ] **Step 4: Import, run, commit**

```bash
git add view/day_sparkline.gd tests/test_day_sparkline.gd
git commit -m "Add DaySparkline: a kind's day as 24 bars split by direction

Volume and direction at once, which is what makes two kinds at the same tier
comparable -- the choice between them is a shape decision, and a number
cannot show a shape."
```

---

### Task 17: `FloorPanel`, and retiring `ReletConfirm`

**Files:**
- Create: `ui/floor_panel.gd`
- Delete: `ui/relet_confirm.gd`
- Modify: `game/game_root.gd:29`, `:80`, `:90-94`, `:159-160`
- Modify: `view/building_view.gd:19`, `:29`, `:280-291`, `:313-319`
- Modify: `view/floor_row.gd:28,33,42,91-102,118-120,142-146,148,154`
- Modify: `tests/test_board_input.gd:272,278,286`

**Interfaces:**
- Consumes: `GameState.available_kinds`, `.lease_cost`, `.lease`, `.class_upgrade_cost`, `.upgrade_class`; `DaySparkline` (16); `HallColumn.floor_selected` (15).
- Produces: `FloorPanel.show_floor(state: GameState, row: int)`; `signal lease_requested(row, kind_id)`; `signal upgrade_requested(row)`.

**The price leaves the strip**, so `VACANT_MAX_INDIVIDUALS := 9` and `VACANT_STRIP_RIGHT` are deleted and a vacant row draws the full `MAX_INDIVIDUALS := 12` (§8.1).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_the_lease_picker_is_hidden_while_the_floor_is_tenanted() -> void:
	var root := _board(8, 2)
	root.panel.show_floor(root.state, 3)
	assert_false(root.panel.picker_visible(), "you choose who moves in, not out")

func test_the_lease_picker_appears_when_the_floor_is_vacant() -> void:
	var root := _board(8, 2)
	root.state.tenancy.restore_row(3, 1.0, true, 0)
	root.panel.show_floor(root.state, 3)
	assert_true(root.panel.picker_visible())

func test_a_floor_counting_down_to_move_out_still_counts_as_tenanted() -> void:
	var root := _board(8, 2)
	while root.state.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(3)
	assert_true(root.state.tenancy.is_moving_out(3))
	root.panel.show_floor(root.state, 3)
	assert_false(root.panel.picker_visible(),
		"the move-out clock keeps its teeth")

func test_kinds_above_the_floors_class_are_shown_locked() -> void:
	var root := _board(8, 2)
	root.state.tenancy.restore_row(3, 1.0, true, 0)
	root.panel.show_floor(root.state, 3)
	assert_true(root.panel.is_locked("law_firm"), "with the class it needs")
	assert_false(root.panel.is_locked("apartments"))
```

- [ ] **Step 2: Run and watch it fail**

- [ ] **Step 3: Write `ui/floor_panel.gd`**

A bottom sheet inset by `SafeArea`, 44pt targets: header (floor, class, tenant, satisfaction bar) → `DaySparkline` of the sitting tenant → UPGRADE CLASS with price and what it unlocks → the lease picker, **only when vacant**.

- [ ] **Step 4: Delete `ReletConfirm` across all thirteen surfaces**

Work the §8.1 table. `tests/test_board_input.gd:272`, `:278`, `:286` are three whole test functions, not four dangling assertions; `:278` is the x-boundary pin and was **rewritten** in Task 15, not deleted — delete the other two.

- [ ] **Step 5: Import, run, commit**

```bash
git add ui/ view/ game/game_root.gd tests/
git commit -m "Add FloorPanel and retire ReletConfirm across thirteen surfaces

The panel is the whole feature's surface: what this floor is, what its day
looks like, what upgrading costs, and -- only when vacant -- who will take it.

The lease picker is hidden while a tenant sits there, including while a
move-out countdown runs. You choose who moves in, not who moves out, so
tenant churn stays driven by satisfaction and the move-out clock keeps its
teeth.

ReletConfirm was the one documented 44pt exception, and it existed only
because a 16pt row could not be a touch target. Rows are a fixed 88 units
now. The price leaves the strip with it, so VACANT_MAX_INDIVIDUALS and the
sprite-cap arithmetic that existed to make room for it go too."
```

---

### Task 18: Boot wiring and the invalid-catalog screen

**Files:**
- Modify: `game/game_root.gd` — `_ready` (`:50`, `:54`), panel wiring, `HallColumn` connection

**Interfaces:**
- Consumes: `GameState.is_valid()` (9), `FloorPanel` (17), `HallColumn` (15).
- Produces: the shipped wiring.

`_ready()` constructs unconditionally at `:50` and `:54` with no alternative branch, so "the boot path refuses to start" needs a defined behaviour: **a static error screen naming the file** (§4.1). A malformed shipped `tenants.json` is a build error a player can hit, and a blank board with a console message they cannot see is indistinguishable from a hang.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_an_invalid_state_shows_an_error_screen_and_does_not_start_the_sim() -> void:
	var root := GameRoot.new()
	root.catalog_path_override = "res://data/does_not_exist.json"
	add_child_autofree(root)
	assert_true(root.error_screen_visible())
	assert_false(root.sim_running())
```

- [ ] **Step 2: Run and watch it fail**

- [ ] **Step 3: Implement**

Branch `_ready()` on `state.is_valid()`; on failure show a `Label` naming the path and skip `set_process`. On success, connect `HallColumn.floor_selected` → `FloorPanel.show_floor`, and the panel's `lease_requested` / `upgrade_requested` → `GameState.lease` / `.upgrade_class`.

- [ ] **Step 4: Run the full suite, play it, commit**

Run the suite, then launch the game and check: tap a floor's left side, upgrade a class, watch a tenant move out and re-lease it.

```bash
git add game/game_root.gd tests/
git commit -m "Wire the hall panel and define what a bad catalog looks like

_ready constructed unconditionally with no failure branch, so 'the boot path
refuses to start' was an intention rather than a behaviour. A malformed
shipped tenants.json is a build error a player can reach, and a blank board
with a console message they cannot see is indistinguishable from a hang."
```

---

## Self-Review

**Spec coverage.** §2→T1, §3→T5/T9, §3.1→T9, §4→T4, §4.1→T4/T9/T18, §4.2→T4, §4.3→T7/T9, §4.4→T7/T9, §5→T8/T10, §5.1→T3, §5.2→T2, §5.3→T6/T10/T12, §5.4→T13, §5.5→T8/T10/T11, §5.6→T4/T10, §6→T12, §7→T15, §8→T16/T17, §8.1→T17, §8.2→T11, §9→T11, §10→T14, §11.1→T10, §11.2→spread, §12→global constraints, §13→no work (documented), §14→no work.

**Placeholders.** None: every code step carries real GDScript, and the curve data is authored to §5.6's equation rather than deferred.

**Type consistency.** `source_row` (T2) is the same name in T3, T8, T13. `revision()` returns `int` on both `Tenancy` (T6) and `Fitout` (T5), summed in T10. `accrue_for_tick()` returns `PackedInt32Array` in T6 and is consumed as such in T13. `lease(row, kind_id)` has the same signature in `Tenancy` (T11) and `GameState` (T11). `TenantCatalog.cheapest_for_class` is used by T11 and T14. `kind_at` returns `""` for "no kind" everywhere, and `null` is the *save* encoding only (T14).

**One gap I could not close:** Task 10 is the largest and cannot be split further — the spawner signature, the cache, and the test-suite sweep have to land together or the suite is red between tasks. Expect it to take roughly as long as tasks 1–9 combined.

---

Plan complete and saved to `docs/superpowers/plans/2026-08-02-tenant-kinds-and-floor-class.md`.
