# Building Downward (Parking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Floors below the lobby, leasable as parking, which act as a second entrance and raise the building's inbound traffic.

**Architecture:** Floors become signed (`-depth .. floor_count-1`) while every per-floor array stays dense and zero-based. A single shared `FloorIndex` owns the floor→slot mapping so `Building`, `Tenancy` and `Fitout` cannot disagree about it. Parking is an ordinary tenant kind carrying a new `entrance` flag, which routes it into the spawner's entrance set instead of its source list.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.7.1.

**Spec:** `docs/superpowers/specs/2026-08-04-building-downward-parking-design.md`

## Global Constraints

- **Sim never touches the scene tree.** Everything in `sim/` is `RefCounted`, no Nodes, no `FileAccess` outside the documented loaders.
- **`floor_count` keeps meaning "tower floors"** — the count at index 0 and above. It never becomes the total. `total_floors()` is the total.
- **Nothing may be named `parking` in code** except the tenant kind id in `data/tenants.json`. `lobby_parking` already exists and means cars returning to the lobby when idle. Identifiers here are `depth`, `dig`, `depth_cap`, `PARK_BONUS`, `entrance`.
- **One Bernoulli trial per tick** in `TrafficSpawner`, at every depth. The draw count must not depend on building size — the seed sequence depends on it.
- **`SaveCodec.VERSION` stays 4.** No migration. New keys are read with `data.get(key, default)`.
- **Income is credited to `Passenger.source_floor`**, the floor that generated the trip, never the endpoint.
- **`PARK_BONUS = 0.15` is a guess.** Task 10 measures it. Do not present it as derived.
- Run the whole suite with `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. A single file is `-gtest=res://tests/test_x.gd`. **`-gdir=<file>` prints "Nothing was run" and exits 0** — a false green.
- **Check the test COUNT after every run.** A script with a parse error is silently dropped and the suite still prints "All tests passed". The count is the only signal.

---

## File Structure

**New:**
- `sim/floor_index.gd` — the one floor→slot mapping, shared by reference.
- `tests/test_floor_index.gd`
- `art/floors/parking.png` — garage scenery, 384×240.

**Modified:**
- `sim/building.gd` — `depth`, `dig()`, signed accessors, `waiting` spanning.
- `sim/tenancy.gd` / `sim/fitout.gd` — take the shared index; `dig()` grows them.
- `sim/traffic_spawner.gd` — entrance set, rate scaling, the `-1` sentinel fix.
- `sim/building_day.gd` — mirrors the spawner's entrance handling.
- `sim/tenant_kind.gd` / `sim/tenant_catalog.gd` — `where`, `entrance`, branching validation.
- `sim/meta.gd` — `depth_cap()`.
- `sim/game_state.gd` — `dig` budget, source list, `_expire` range.
- `sim/save_codec.gd` — `depth`, `floors` spanning the basement.
- `sim/coords.gd` — `footroom`.
- `view/building_view.gd` — dig band, signed `BoardCoords`.
- `view/floor_row.gd` — `P1` labels.
- `data/upgrades.json`, `data/blueprints.json`, `data/tenants.json`.

---

## Task 1: FloorIndex — the one mapping

**Files:**
- Create: `sim/floor_index.gd`
- Test: `tests/test_floor_index.gd`

**Interfaces:**
- Produces: `FloorIndex.new(bottom: int, above: int)`, `slot(f) -> int`, `holds(f) -> bool`, `size() -> int`, `dig() -> void`, `grow_up() -> void`, and the fields `bottom`, `above`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_floor_index.gd
extends GutTest

## The floor -> array slot mapping, and the ONLY copy of it. Building, Tenancy
## and Fitout share one instance, so "the three agree" is not a property to test
## -- it is unrepresentable. What IS worth testing is the mapping itself and its
## refusal at the edges, because every per-floor array in the sim is behind it.

func test_a_ground_only_building_is_the_identity() -> void:
	# The case that made a shared index earn nothing before basements existed --
	# it must still be free.
	var ix := FloorIndex.new(0, 10)
	for f in range(0, 10):
		assert_eq(ix.slot(f), f, "floor %d" % f)
	assert_eq(ix.size(), 10)

func test_the_basement_occupies_the_front_of_the_array() -> void:
	var ix := FloorIndex.new(-2, 10)
	assert_eq(ix.slot(-2), 0, "the deepest floor is slot 0")
	assert_eq(ix.slot(-1), 1)
	assert_eq(ix.slot(0), 2, "the lobby is no longer slot 0")
	assert_eq(ix.slot(9), 11)
	assert_eq(ix.size(), 12)

func test_it_refuses_floors_outside_the_building() -> void:
	# The hazard Fitout's old docstring named: an offset turns an out-of-range
	# access into an in-range WRONG one. holds() is what stops that.
	var ix := FloorIndex.new(-2, 10)
	assert_false(ix.holds(-3), "below the basement")
	assert_false(ix.holds(10), "above the roof")
	assert_true(ix.holds(-2))
	assert_true(ix.holds(9))

func test_digging_moves_the_bottom_and_growing_moves_the_top() -> void:
	var ix := FloorIndex.new(0, 1)
	ix.dig()
	assert_eq(ix.bottom, -1)
	assert_eq(ix.slot(-1), 0, "the new floor takes slot 0")
	assert_eq(ix.slot(0), 1, "and everything above shifts up one")
	ix.grow_up()
	assert_eq(ix.above, 2)
	assert_eq(ix.size(), 3)

func test_digging_twice_does_not_move_what_was_already_there() -> void:
	# The front-insertion bug that is invisible until you dig a SECOND time.
	var ix := FloorIndex.new(0, 3)
	ix.dig()
	var first := ix.slot(-1)
	ix.dig()
	assert_eq(ix.slot(-2), 0, "the newest floor is at the front")
	assert_eq(ix.slot(-1), first + 1, "and the older one moved up exactly one")
```

- [ ] **Step 2: Run it and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_floor_index.gd -gexit`
Expected: FAIL — `Identifier "FloorIndex" not declared`.

- [ ] **Step 3: Write `sim/floor_index.gd`**

```gdscript
class_name FloorIndex
extends RefCounted

## Which array slot a FLOOR occupies. There is exactly one of these per building:
## Building, Tenancy and Fitout share the same instance by reference, so a
## desync between them is not a bug to test for -- it is unrepresentable.
##
## Fitout's docstring rejected a shared index object, and was right to while the
## bottom floor was always 0: the mapping was the identity and earned nothing.
## Digging deletes that precondition. What the rejection got right, and what this
## class is shaped by, is that a COPIED offset turns a container desync from a
## loud out-of-range access into a silent valid-but-wrong index -- floor -1
## reading floor -2's slot, in range, wrong answer, and an "the arrays are the
## same length" test passing straight through it. One instance, not three.

## The lowest floor in the building: -depth.
var bottom: int = 0
## One past the top: floor_count.
var above: int = 1

func _init(p_bottom: int = 0, p_above: int = 1) -> void:
	bottom = p_bottom
	above = maxi(p_above, p_bottom + 1)

## The array slot for a floor. Callers MUST have checked holds() first; this
## does not bounds-check, because a caller that skips the check should fail
## loudly on the array access rather than quietly here.
func slot(f: int) -> int:
	return f - bottom

func holds(f: int) -> bool:
	return f >= bottom and f < above

func size() -> int:
	return above - bottom

## A new floor at the BOTTOM. Every existing floor's slot shifts up by one,
## which is why callers insert at the front rather than appending.
func dig() -> void:
	bottom -= 1

func grow_up() -> void:
	above += 1
```

- [ ] **Step 4: Run it and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_floor_index.gd -gexit`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
godot --headless --import
git add sim/floor_index.gd sim/floor_index.gd.uid tests/test_floor_index.gd tests/test_floor_index.gd.uid
git commit -m "Give the building one definition of floor-to-slot

Fitout's docstring rejected a shared index object and was right to: with
the bottom floor always 0 the mapping was the identity and earned
nothing. Digging deletes that precondition.

What the rejection got right is the reason this is SHARED and not copied
into three owners. An offset duplicated across Building, Tenancy and
Fitout turns a desync from a loud out-of-range access into a silent
in-range wrong one -- floor -1 reading floor -2's slot -- which an
\"arrays are the same length\" test passes straight through. One instance
makes that unrepresentable rather than tested for."
```

---

## Task 2: The `-1` inbound sentinel collides with a real floor

Do this **before** any basement exists, so it is a pure refactor with no behaviour change and a clean bisect point.

**Files:**
- Modify: `sim/traffic_spawner.gd:76-92`
- Test: `tests/test_traffic_spawner.gd`

**Interfaces:**
- Produces: `TrafficSpawner._destination_for(...) -> Vector2i` where `.x` is the destination floor and `.y` is `1` for an inbound trip, `0` otherwise.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_traffic_spawner.gd
func test_an_inbound_trip_is_flagged_not_encoded_as_floor_minus_one() -> void:
	# _destination_for returned -1 to mean "inbound, swap the endpoints". That
	# was safe only while floors started at 0. The FIRST floor dug is -1, so the
	# sentinel becomes a real destination and inbound traffic silently starts
	# delivering people to the basement. The flag is separate now.
	var sp := TrafficSpawner.new(1)
	assert_true(sp.load_curve("res://data/patience.json"), "curve loads")
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"), "catalog loads")
	var k := cat.kind("office")
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(4, k, 1.0),
	]
	# Sweep the day so both inbound and outbound arise.
	var saw_inbound := false
	for minute in range(0, 48):
		var d := sp._destination_for(sources[1], sources, minute, true)
		assert_between(d.y, 0, 1, "the flag is a flag")
		if d.y == 1:
			saw_inbound = true
			assert_ne(d.x, -1, "an inbound trip must not encode itself as floor -1")
	assert_true(saw_inbound, "the office takes inbound trips at some hour")
```

- [ ] **Step 2: Run it and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_traffic_spawner.gd -gexit`
Expected: FAIL — `Invalid access to property or key 'y' on a base object of type 'int'`.

- [ ] **Step 3: Change the return type**

In `sim/traffic_spawner.gd`, replace the docstring and signature of `_destination_for`:

```gdscript
## The destination floor in `.x`, and `.y == 1` when this is an INBOUND trip, so
## the caller swaps the endpoints.
##
## The flag used to be `-1` in the return value itself. That was safe only while
## the lowest floor was 0; the first floor dug IS -1, and a sentinel that is also
## a legal answer delivers inbound passengers into the basement with no error
## anywhere. Collapses to interfloor whenever the lobby is not a usable endpoint.
func _destination_for(chosen: TrafficSource, sources: Array[TrafficSource],
		minute: int, lobby_tenanted: bool) -> Vector2i:
```

Every `return -1` inside becomes `return Vector2i(chosen.floor_index, 1)`, and every `return <floor>` becomes `return Vector2i(<floor>, 0)`.

In `spawn_from_sources`, replace:

```gdscript
	var origin := chosen.floor_index
	var destination := _destination_for(chosen, sources, minute, lobby_tenanted)
	if destination == chosen.floor_index:
		return out
	if destination == -1:
		origin = LOBBY
		destination = chosen.floor_index
```

with:

```gdscript
	var origin := chosen.floor_index
	var answer := _destination_for(chosen, sources, minute, lobby_tenanted)
	var destination := answer.x
	if answer.y == 1:
		origin = LOBBY
		destination = chosen.floor_index
	elif destination == chosen.floor_index:
		return out
```

Note the reordering: the self-trip refusal must not run on an inbound answer, whose `.x` legitimately equals `chosen.floor_index`.

- [ ] **Step 4: Run the whole suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS, and **the count must be exactly one higher than before this task**. Traffic is seeded, so any behaviour change here shows as unrelated failures in `test_traffic_spawner` or `test_game_state`.

- [ ] **Step 5: Commit**

```bash
git add sim/traffic_spawner.gd tests/test_traffic_spawner.gd
git commit -m "Stop encoding 'inbound' as floor -1

_destination_for returned -1 to mean 'this is inbound, swap the
endpoints'. That is safe exactly while the lowest floor is 0, and the
first floor dug is -1 -- so the sentinel becomes a legal destination and
inbound passengers start being delivered into the basement with nothing
raising anywhere.

It returns Vector2i now: destination in x, an inbound flag in y. Pure
refactor, no behaviour change at depth 0, landed before basements exist
so a bisect can tell the two apart.

The self-trip refusal moved BELOW the inbound branch. An inbound answer's
.x legitimately equals the chosen floor, so checking it first would have
dropped every inbound trip."
```

---

## Task 3: Building gains depth

**Files:**
- Modify: `sim/building.gd`
- Test: `tests/test_building.gd`

**Interfaces:**
- Consumes: `FloorIndex` from Task 1.
- Produces: `Building.depth: int`, `Building.index: FloorIndex`, `bottom_floor() -> int`, `total_floors() -> int`, `has_floor(f) -> bool`, `dig() -> bool`. `waiting` is indexed via `index.slot(f)`.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_building.gd
func test_a_new_building_has_no_basement() -> void:
	var b := Building.new(4, 1)
	assert_eq(b.depth, 0)
	assert_eq(b.bottom_floor(), 0)
	assert_eq(b.total_floors(), 4)
	assert_true(b.has_floor(0))
	assert_false(b.has_floor(-1))

func test_digging_adds_a_floor_below_the_lobby() -> void:
	var b := Building.new(4, 1)
	assert_true(b.dig())
	assert_eq(b.depth, 1)
	assert_eq(b.bottom_floor(), -1)
	assert_eq(b.total_floors(), 5, "the tower did not shrink")
	assert_eq(b.floor_count, 4, "floor_count still means TOWER floors")
	assert_true(b.has_floor(-1))
	assert_false(b.has_floor(-2))

func test_people_waiting_in_the_basement_stay_where_they_were_put() -> void:
	# The front-insertion bug: invisible until you dig a SECOND time, because
	# with one basement floor the shift is a no-op for everyone above it.
	var b := Building.new(4, 1)
	b.dig()
	b.enqueue(Passenger.new(-1, 3, 100, 1.0, 3))
	assert_eq(b.waiting_at(-1).size(), 1, "queued in the basement")
	b.dig()
	assert_eq(b.waiting_at(-1).size(), 1, "still there after digging deeper")
	assert_eq(b.waiting_at(-2).size(), 0, "and the new floor is empty")

func test_a_passenger_below_the_basement_is_refused() -> void:
	var b := Building.new(4, 1)
	b.dig()
	b.enqueue(Passenger.new(-2, 3, 100, 1.0, 3))
	assert_eq(b.waiting_at(-2).size(), 0, "there is no floor -2 to wait on")

func test_digging_stops_at_the_hard_cap() -> void:
	var b := Building.new(4, 1)
	for i in range(Meta.MAX_DEPTH_CAP):
		assert_true(b.dig(), "dig %d" % i)
	assert_false(b.dig(), "the engine cap refuses beyond MAX_DEPTH_CAP")
	assert_eq(b.depth, Meta.MAX_DEPTH_CAP)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_building.gd -gexit`
Expected: FAIL — `Invalid access to property or key 'depth'`.

- [ ] **Step 3: Implement**

In `sim/building.gd`, replace the constructor and add the accessors:

```gdscript
const MAX_FLOORS := 40
const MAX_SHAFTS := 8

## TOWER floors: the count at index 0 and above. NOT the total -- see
## total_floors(). Nine loops in the sim say range(floor_count), and every one
## of them is about the tower.
var floor_count: int
## Floors dug below the lobby. The building runs -depth .. floor_count - 1.
var depth: int = 0
## The one floor -> slot mapping, shared BY REFERENCE with Tenancy and Fitout.
var index: FloorIndex
var cars: Array[ElevatorCar] = []
## One queue per floor, dense from the BOTTOM floor. Index it through `index`.
var waiting: Array = []

func _init(p_floor_count: int, shaft_count: int) -> void:
	floor_count = clampi(p_floor_count, 1, MAX_FLOORS)
	index = FloorIndex.new(0, floor_count)
	for i in range(floor_count):
		waiting.append([] as Array[Passenger])
	for i in range(clampi(shaft_count, 0, MAX_SHAFTS)):
		cars.append(ElevatorCar.new(0))

func bottom_floor() -> int:
	return -depth

func total_floors() -> int:
	return floor_count + depth

func has_floor(f: int) -> bool:
	return index.holds(f)

## A new floor BELOW the lobby. Front insertion, because the basement occupies
## the front of every per-floor array and the new floor is the deepest.
##
## Bounded by Meta.MAX_DEPTH_CAP rather than by MAX_FLOORS: depth and height are
## independent budgets, and a tampered save must land on this release's ladder
## top rather than on the engine's floor limit.
func dig() -> bool:
	if depth >= Meta.MAX_DEPTH_CAP:
		return false
	depth += 1
	index.dig()
	waiting.insert(0, [] as Array[Passenger])
	return true
```

Then update `add_floor`, `enqueue` and `waiting_at`:

```gdscript
func add_floor() -> bool:
	if floor_count >= MAX_FLOORS:
		return false
	floor_count += 1
	index.grow_up()
	waiting.append([] as Array[Passenger])
	return true

func enqueue(p: Passenger) -> void:
	if not has_floor(p.origin_floor):
		return
	waiting[index.slot(p.origin_floor)].append(p)
```

Audit every other `waiting[...]` access in the file and route it through `index.slot()`, and every `0 <= f < floor_count` bound through `has_floor()`.

- [ ] **Step 4: Run the whole suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS. `sim/building.gd:23` (the constructor loop) is audit site 1 of 9 and is now correct by construction.

- [ ] **Step 5: Commit**

```bash
git add sim/building.gd tests/test_building.gd
git commit -m "Let the building have a basement

floor_count deliberately keeps meaning TOWER floors rather than becoming
the total. Nine loops in the sim say range(floor_count) and every one is
about the tower; redefining it would have walked all nine into a basement
silently.

waiting is dense from the BOTTOM floor, so digging inserts at the front.
The test that matters digs TWICE -- with one basement floor the shift is
a no-op for everyone above it, so a front-insertion bug is invisible
until the second dig."
```

---

## Task 4: Tenancy and Fitout span the basement

**Files:**
- Modify: `sim/tenancy.gd`, `sim/fitout.gd` (including the docstring at `fitout.gd:12-16`)
- Test: `tests/test_tenancy.gd`, `tests/test_fitout.gd`

**Interfaces:**
- Consumes: `FloorIndex` (Task 1), `Building.index` (Task 3).
- Produces: `Tenancy.new(index: FloorIndex, tenanted_prefix: int)`, `Fitout.new(index: FloorIndex)`, both with a `dig()` that inserts at the front.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_tenancy.gd
func test_a_dug_floor_is_vacant_and_addressable_by_its_negative_index() -> void:
	var ix := FloorIndex.new(0, 3)
	var t := Tenancy.new(ix, 1)
	ix.dig()
	t.dig()
	assert_true(t.is_vacant(-1), "digging excavates, it does not lease")
	assert_eq(t.kind_at(-1), "", "and it has no tenant kind")

func test_leasing_the_basement_does_not_disturb_the_tower() -> void:
	# The silent-wrong-index failure this whole design is shaped against: an
	# off-by-one in the mapping writes the LOBBY's tenancy when asked for -1,
	# which is in range and therefore raises nothing.
	var ix := FloorIndex.new(0, 3)
	var t := Tenancy.new(ix, 3)
	var lobby_kind := t.kind_at(0)
	ix.dig()
	t.dig()
	t.lease(-1, "parking")
	assert_eq(t.kind_at(-1), "parking")
	assert_eq(t.kind_at(0), lobby_kind, "the lobby is untouched")
	assert_false(t.is_vacant(0))

func test_digging_twice_keeps_the_first_basement_where_it_was() -> void:
	var ix := FloorIndex.new(0, 2)
	var t := Tenancy.new(ix, 2)
	ix.dig(); t.dig()
	t.lease(-1, "parking")
	ix.dig(); t.dig()
	assert_eq(t.kind_at(-1), "parking", "the leased floor did not move")
	assert_true(t.is_vacant(-2), "the new one is the empty one")
```

```gdscript
# append to tests/test_fitout.gd
func test_a_dug_floor_starts_at_the_base_tier() -> void:
	var ix := FloorIndex.new(0, 3)
	var f := Fitout.new(ix)
	ix.dig()
	f.dig()
	assert_eq(f.tier_at(-1), Fitout.BASE_TIER)
	assert_eq(f.floors(), 4, "three tower floors and one basement")

func test_upgrading_the_basement_does_not_upgrade_the_lobby() -> void:
	var ix := FloorIndex.new(0, 3)
	var f := Fitout.new(ix)
	ix.dig()
	f.dig()
	f.set_tier(-1, 3)
	assert_eq(f.tier_at(-1), 3)
	assert_eq(f.tier_at(0), Fitout.BASE_TIER, "the lobby is untouched")
```

- [ ] **Step 2: Run and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tenancy.gd -gexit`
Expected: FAIL — `Invalid call. Nonexistent function 'dig'`.

- [ ] **Step 3: Implement**

`sim/tenancy.gd` — take the index, route every accessor through it:

```gdscript
var _index: FloorIndex

func _init(index: FloorIndex, tenanted_prefix: int) -> void:
	_index = index
	for i in range(index.size()):
		_append_floor()
		if i >= tenanted_prefix:
			_vacant[i] = true

## A floor dug below the lobby: excavated, therefore VACANT. It goes to the
## FRONT of every array, because the basement is dense from the bottom.
func dig() -> void:
	_satisfaction.insert(0, 1.0)
	_vacant.insert(0, true)
	_move_out_left.insert(0, 0)
	_kind.insert(0, "")
	_revision += 1

func _valid(floor_index: int) -> bool:
	return _index.holds(floor_index)
```

Every `_satisfaction[floor_index]`, `_vacant[floor_index]`, `_move_out_left[floor_index]` and `_kind[floor_index]` becomes `[_index.slot(floor_index)]`. `accrue_for_tick`'s loop becomes `for f in range(_index.bottom, _index.above)` and its returned `vacated` array carries **floors**, not slots — check its consumer in `game_state.gd`.

`sim/fitout.gd` — same shape, and **replace the docstring at lines 12-16**:

```gdscript
## Indexes its dense array through the building's shared FloorIndex.
##
## A shared index object was once considered and rejected here, correctly: while
## the bottom floor was always 0 the mapping was the identity and earned nothing.
## Digging deleted that precondition. What the old comment got right, and what
## FloorIndex is shaped by, is that a COPIED offset turns a container desync from
## a loud out-of-range access into a silent in-range wrong one. Sharing one
## instance makes the desync unrepresentable rather than something to test for.
```

- [ ] **Step 4: Run the whole suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS. `GameState` must now pass `building.index` to both constructors. Audit sites 2 (`tenancy.gd:46`) and the `Fitout` constructor are closed.

- [ ] **Step 5: Commit**

```bash
git add sim/tenancy.gd sim/fitout.gd tests/test_tenancy.gd tests/test_fitout.gd sim/game_state.gd
git commit -m "Let tenancy and fitout reach below the lobby

Both take the building's shared FloorIndex rather than a floor count, so
there is one mapping and not three copies of an offset.

Fitout's docstring argued against exactly this and has been rewritten
rather than left contradicting the file. It was right while the bottom
floor was always 0 -- the mapping was the identity. What it got right and
still applies is that a COPIED offset makes a desync silent, which is why
the instance is shared.

The test that would catch the failure mode leases the basement and then
asserts the LOBBY is untouched: an off-by-one writes floor 0 when asked
for floor -1, which is in range and raises nothing."
```

---

## Task 5: Tenant kinds know where they belong and whether they generate trips

**Files:**
- Modify: `sim/tenant_kind.gd`, `sim/tenant_catalog.gd`, `data/tenants.json`
- Test: `tests/test_tenant_catalog.gd`

**Interfaces:**
- Produces: `TenantKind.Where` enum (`TOWER`, `BASEMENT`), `TenantKind.where`, `TenantKind.entrance: bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_tenant_catalog.gd
func test_existing_kinds_default_to_the_tower_and_generate_trips() -> void:
	# The six shipped kinds carry neither field, so the defaults are what keeps
	# this change additive.
	var c := TenantCatalog.new()
	assert_true(c.load_from("res://data/tenants.json"))
	for id in ["apartments", "shops", "office", "gym", "law_firm", "clinic"]:
		var k := c.kind(id)
		assert_eq(k.where, TenantKind.Where.TOWER, "%s is a tower kind" % id)
		assert_false(k.entrance, "%s generates its own trips" % id)

func test_parking_is_a_basement_entrance_that_generates_nothing() -> void:
	var c := TenantCatalog.new()
	assert_true(c.load_from("res://data/tenants.json"))
	var k := c.kind("parking")
	assert_not_null(k, "parking is in the catalog")
	assert_eq(k.where, TenantKind.Where.BASEMENT)
	assert_true(k.entrance)
	assert_eq(k.base_fare, 0.0, "a garage earns nothing directly")
	for minute in range(0, 48):
		assert_eq(k.rate_at(minute), 0.0, "an entrance spawns no trips at %d" % minute)
		assert_eq(k.inbound_at(minute), 0.0)
		assert_eq(k.outbound_at(minute), 0.0)

func test_an_entrance_carrying_curves_is_fatal() -> void:
	# tenants.json is fatal-if-malformed, and the two shapes must not blur: an
	# entrance with a rate array would spawn trips TO a car park.
	var path := "user://bad_entrance.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"classes": [{"tier": 1, "cost": 0.0, "fare_multiplier": 1.0}],
		"kinds": [{"id": "x", "name": "X", "entrance": true, "where": "basement",
			"requires_class": 0, "lease_cost": 1.0, "base_fare": 0.0,
			"rate": [1.0], "inbound": [1.0], "outbound": [1.0]}]}))
	f.close()
	var c := TenantCatalog.new()
	assert_false(c.load_from(path), "an entrance with curves must be refused")

func test_a_source_with_empty_curves_is_fatal() -> void:
	# The other direction, because a one-way check passes vacuously against the
	# file that ships.
	var path := "user://bad_source.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"classes": [{"tier": 1, "cost": 0.0, "fare_multiplier": 1.0}],
		"kinds": [{"id": "x", "name": "X", "requires_class": 0,
			"lease_cost": 1.0, "base_fare": 1.0,
			"rate": [], "inbound": [], "outbound": []}]}))
	f.close()
	var c := TenantCatalog.new()
	assert_false(c.load_from(path), "a source with no curves must be refused")
```

- [ ] **Step 2: Run and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tenant_catalog.gd -gexit`
Expected: FAIL — `Cannot find member "Where" in base "TenantKind"`.

- [ ] **Step 3: Implement**

`sim/tenant_kind.gd`:

```gdscript
## Which half of the building this kind may be leased in. Without it the picker
## offers every kind everywhere and the first thing a player does is put a car
## park on the roof.
enum Where { TOWER, BASEMENT }
var where: Where = Where.TOWER

## An ENTRANCE kind does not generate trips; it RECEIVES arrivals that other
## floors generate. A visitor comes IN through a garage, they are not going to
## it, and a garage with an `inbound` weight would mean "trips from the lobby to
## the car park" -- which the spawner would happily produce.
##
## Not inferred from `where`: the mine, when it arrives, is a BASEMENT kind that
## genuinely is a source.
var entrance: bool = false
```

and make the three accessors safe on empty curves:

```gdscript
func rate_at(minute: int) -> float:
	return 0.0 if rate.is_empty() else rate[minute % rate.size()]
```

(same shape for `inbound_at` and `outbound_at`).

`sim/tenant_catalog.gd`, in the per-kind parse beside `requires_class`:

```gdscript
	k.where = TenantKind.Where.BASEMENT \
		if str(e.get("where", "tower")) == "basement" else TenantKind.Where.TOWER
	k.entrance = bool(e.get("entrance", false))
	# The two shapes must not blur. An entrance with curves spawns trips to a car
	# park; a source without them is a floor that silently never spawns anything.
	# This file is fatal-if-malformed, so both are load failures.
	var has_curves := not (k.rate.is_empty() and k.inbound.is_empty() \
		and k.outbound.is_empty())
	if k.entrance == has_curves:
		return false
```

`data/tenants.json` gains:

```json
{ "id": "parking", "name": "Parking", "where": "basement", "entrance": true,
  "requires_class": 0, "lease_cost": 300.0, "base_fare": 0.0,
  "rate": [], "inbound": [], "outbound": [] }
```

- [ ] **Step 4: Run the whole suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS. If `test_floor_scenery`'s "every shipped kind has art" fails, that is correct — Task 9 draws `parking.png`. Mark it pending with a comment naming Task 9 rather than deleting it.

- [ ] **Step 5: Commit**

```bash
git add sim/tenant_kind.gd sim/tenant_catalog.gd data/tenants.json tests/test_tenant_catalog.gd
git commit -m "Give a tenant kind a half of the building and a traffic role

`where` keeps a car park off the roof. `entrance` is the piece that
'parking is leasable like anything else' hides: a normal kind GENERATES
trips, and a garage generates none -- it receives arrivals other floors
generate. A garage with an inbound weight means 'trips from the lobby to
the car park', which the spawner would produce without complaint.

It is a flag rather than an inference from `where`, because the mine will
be a basement kind that genuinely is a source.

The catalog's validation branches on it, both directions. A one-way check
passes vacuously against the file that ships."
```

---

## Task 6: The spawner grows a second entrance

**Files:**
- Modify: `sim/traffic_spawner.gd`, `sim/building_day.gd`, `sim/game_state.gd:369`
- Test: `tests/test_traffic_spawner.gd`, `tests/test_building_day.gd`

**Interfaces:**
- Consumes: `TenantKind.entrance` (Task 5), `Vector2i` return (Task 2).
- Produces: `TrafficSpawner.PARK_BONUS`, `spawn_from_sources(minute, sources, lobby_tenanted, entrances: PackedInt32Array)`.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_traffic_spawner.gd
func _office_sources(cat: TenantCatalog) -> Array[TrafficSource]:
	return [TrafficSource.new(0, cat.kind("shops"), 1.0),
			TrafficSource.new(4, cat.kind("office"), 1.0)] as Array[TrafficSource]

func test_with_no_entrances_the_spawner_is_unchanged() -> void:
	# THE test that says this feature is additive. Same seed, same sequence.
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"))
	var a := TrafficSpawner.new(99); a.load_curve("res://data/patience.json")
	var b := TrafficSpawner.new(99); b.load_curve("res://data/patience.json")
	for minute in range(0, 200):
		var x := a.spawn_from_sources(minute, _office_sources(cat), true,
			PackedInt32Array())
		var y := b.spawn_from_sources(minute, _office_sources(cat), true,
			PackedInt32Array([]))
		assert_eq(x.size(), y.size(), "minute %d" % minute)

func test_the_draw_count_does_not_depend_on_depth() -> void:
	# The seed-sequence property. A trial per entrance would make the sequence
	# depend on how deep the building is, exactly as a trial per floor would make
	# it depend on how tall.
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"))
	var counter := DrawCounter.new()
	var sp := TrafficSpawner.new(7); sp.load_curve("res://data/patience.json")
	sp.rng = counter
	for minute in range(0, 100):
		sp.spawn_from_sources(minute, _office_sources(cat), true,
			PackedInt32Array())
	var shallow := counter.draws
	counter.draws = 0
	for minute in range(0, 100):
		sp.spawn_from_sources(minute, _office_sources(cat), true,
			PackedInt32Array([-1, -2, -3]))
	assert_lte(counter.draws, shallow + 100,
		"at most one extra draw per tick, for the entrance choice")

func test_arrivals_appear_at_the_entrances_and_nowhere_else() -> void:
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"))
	var sp := TrafficSpawner.new(3); sp.load_curve("res://data/patience.json")
	var seen := {}
	for minute in range(0, 4000):
		for p in sp.spawn_from_sources(minute % 48, _office_sources(cat), true,
				PackedInt32Array([-1, -2])):
			seen[p.origin_floor] = true
	assert_true(seen.has(-1) and seen.has(-2), "both garages take arrivals")
	assert_false(seen.has(-3), "never below the bottom floor")

func test_an_arrival_is_credited_to_the_floor_that_generated_it() -> void:
	# The project invariant: income follows source_floor, not the endpoint.
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"))
	var sp := TrafficSpawner.new(11); sp.load_curve("res://data/patience.json")
	for minute in range(0, 2000):
		for p in sp.spawn_from_sources(minute % 48, _office_sources(cat), true,
				PackedInt32Array([-1])):
			if p.origin_floor == -1:
				assert_ne(p.source_floor, -1,
					"the garage did not generate this trip, the tenant did")

func test_a_vacant_lobby_collapses_lobby_arrivals_but_not_parking_ones() -> void:
	# The exception. A driver parking at -1 and riding to an office never needs a
	# lobby tenant, so parking keeps a building earning with floor 0 unleased.
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"))
	var sources: Array[TrafficSource] = [
		TrafficSource.new(4, cat.kind("office"), 1.0),
		TrafficSource.new(6, cat.kind("gym"), 1.0)]
	var sp := TrafficSpawner.new(5); sp.load_curve("res://data/patience.json")
	var from_park := 0
	var from_lobby := 0
	for minute in range(0, 4000):
		for p in sp.spawn_from_sources(minute % 48, sources, false,
				PackedInt32Array([-1])):
			if p.origin_floor == -1: from_park += 1
			elif p.origin_floor == 0: from_lobby += 1
	assert_gt(from_park, 0, "parking arrivals survive a vacant lobby")
	assert_eq(from_lobby, 0, "lobby arrivals do not")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `Too many arguments for "spawn_from_sources()"`.

- [ ] **Step 3: Implement**

In `sim/traffic_spawner.gd`:

```gdscript
## Extra inbound arrivals per LEASED entrance floor, as a fraction of the
## building's base rate.
##
## THIS NUMBER IS A GUESS. It has not been measured on the real sim and must be
## before it ships -- see the spec's §9. Run 1 caps at two shafts and may dig 2
## with no tree spend, so a wrong value here is not "digging is weak", it is
## "digging is a trap a new player takes and then drowns in".
const PARK_BONUS := 0.15
```

`spawn_from_sources` gains a fourth parameter and scales the total:

```gdscript
func spawn_from_sources(minute: int, sources: Array[TrafficSource],
		lobby_tenanted: bool, entrances: PackedInt32Array) -> Array[Passenger]:
	...
	var total := 0.0
	for s in sources:
		total += s.rate_at(minute)
	# ONE trial, against a scaled total. A trial per entrance would make the seed
	# sequence depend on depth, the same way a trial per floor would make it
	# depend on height.
	var park := PARK_BONUS * float(entrances.size())
	total *= 1.0 + park
```

The weighted source pick then runs against the **unscaled** total (`total / (1.0 + park)`), so which floor generates the trip is unaffected by depth. On an inbound answer, choose the entrance:

```gdscript
	if answer.y == 1:
		origin = _entrance_for(entrances, park)
		destination = chosen.floor_index
```

```gdscript
## Which door this arrival came through. The lobby with probability
## 1/(1+park), otherwise a garage, uniformly.
##
## Uniform is deliberate and is the whole diminishing return: the fourth garage
## adds the same arrivals as the first, but they are further from where they are
## going, so depth costs more car time per trip it buys.
func _entrance_for(entrances: PackedInt32Array, park: float) -> int:
	if entrances.is_empty():
		return LOBBY
	if rng.randf() >= park / (1.0 + park):
		return LOBBY
	return entrances[mini(int(rng.randf() * float(entrances.size())),
		entrances.size() - 1)]
```

`_destination_for`'s collapse must **not** apply to parking arrivals. The lobby-tenanted check governs whether the LOBBY is a usable endpoint; pass `lobby_tenanted or not entrances.is_empty()` into it, with this comment:

```gdscript
	# A leased garage is a usable entrance even when floor 0 is not. The collapse
	# exists because an untenanted LOBBY cannot be an endpoint, and a garage is a
	# different endpoint that is not untenanted. Consequence, stated because it
	# looks like a loophole and is not: parking keeps a building earning with no
	# leased lobby, which is a second way out of the no-fail-state hole.
```

`sim/game_state.gd:369` (`_sources`) is audit site 3: it becomes
`for floor_index in range(building.bottom_floor(), building.floor_count)`, and an
`entrance` kind is appended to a new `_entrance_cache: PackedInt32Array` instead
of to `_source_cache`.

`sim/building_day.gd` must reproduce the same split — it derives the day chart
from the same sources, and would otherwise draw a curve the sim does not spawn.

- [ ] **Step 4: Run the whole suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS, count up by 5.

- [ ] **Step 5: Commit**

```bash
git add sim/traffic_spawner.gd sim/building_day.gd sim/game_state.gd tests/test_traffic_spawner.gd tests/test_building_day.gd
git commit -m "Give the building a second front door

A leased garage does not generate trips -- it changes where other floors'
inbound trips start. The summed rate scales by 1 + PARK_BONUS * n and the
entrance is drawn on inbound, so ONE Bernoulli trial per tick survives:
a trial per entrance would make the seed sequence depend on depth exactly
as a trial per floor would make it depend on height.

The source pick runs against the UNSCALED total, so which tenant
generates a trip is unaffected by how deep you have dug. Only where the
visitor comes in changes.

Uniform entrance choice is the diminishing return, for free: the fourth
garage adds the same arrivals as the first, further from where they are
going.

The lobby-collapse rule gets an exception. It exists because an
untenanted LOBBY cannot be an endpoint; a leased garage is a different
endpoint that is not untenanted. So parking keeps a building earning with
floor 0 unleased -- a second way out of the no-fail-state hole rather
than a loophole in it.

PARK_BONUS is labelled a guess in the source, not presented as derived."
```

---

## Task 7: Digging is a purchase under a tree ceiling

**Files:**
- Modify: `sim/meta.gd`, `sim/game_state.gd`, `sim/upgrades.gd`, `data/upgrades.json`, `data/blueprints.json`
- Test: `tests/test_meta.gd`, `tests/test_upgrades.gd`

**Interfaces:**
- Produces: `Meta.depth_cap() -> int`, `Meta.BASE_DEPTH_CAP`, `Meta.DEPTH_PER_LEVEL`, `Meta.MAX_DEPTH_CAP`, the `dig` upgrade id.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_meta.gd
func test_the_depth_ceiling_walks_two_to_eight() -> void:
	var m := loaded()
	m.blueprints = 1000
	var u := upgrades()
	assert_eq(m.depth_cap(), Meta.BASE_DEPTH_CAP, "run one digs two")
	for i in range(3):
		assert_true(m.buy("depth", u), "depth level %d" % i)
		assert_eq(m.depth_cap(),
			Meta.BASE_DEPTH_CAP + Meta.DEPTH_PER_LEVEL * (i + 1), "level %d" % (i + 1))
	assert_eq(m.depth_cap(), Meta.MAX_DEPTH_CAP,
		"a maxed node lands exactly on the ladder top")

func test_the_depth_clamp_is_not_vacuous() -> void:
	var m := Meta.new()
	assert_true(m.load_defs(write_defs([ok_node({"id": "depth", "max_level": 64})])))
	assert_true(m.restore({"spent": {"depth": 64}}))
	assert_eq(m.level_of("depth"), 64, "the level is real")
	assert_eq(m.depth_cap(), Meta.MAX_DEPTH_CAP, "bounded by this release's ladder")

func test_a_run_may_dig_to_the_ceiling_and_no_further() -> void:
	var m := loaded()
	m.blueprints = 1000
	var u := upgrades()
	assert_true(m.buy("depth", u), "one level")
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1,
		"res://data/tenants.json", m)
	s.economy.cash = 1_000_000.0
	while not s.upgrades.is_maxed("dig"):
		assert_true(s.buy("dig"), "dig %d" % s.building.depth)
	assert_eq(s.building.depth, m.depth_cap(), "dug to the ceiling")
	assert_false(s.buy("dig"), "the sim refuses, not merely the view")

func test_digging_yields_a_vacant_floor_not_a_leased_one() -> void:
	var m := loaded()
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1,
		"res://data/tenants.json", m)
	s.economy.cash = 1_000_000.0
	assert_true(s.buy("dig"))
	assert_true(s.tenancy.is_vacant(-1), "excavation is not a lease")

func test_a_run_deeper_than_the_tree_pays_for_keeps_its_basement() -> void:
	# The live-save case, as for shafts. grant_level clamps the COUNTER to the
	# new budget, which looks like it should fill the hole back in. It does not.
	var m := loaded()
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1,
		"res://data/tenants.json", m)
	s.economy.cash = 1_000_000.0
	for i in range(Meta.BASE_DEPTH_CAP):
		assert_true(s.buy("dig"))
	assert_eq(s.building.depth, Meta.BASE_DEPTH_CAP)
	assert_true(s.upgrades.is_maxed("dig"), "and no more are for sale")
	assert_false(s.buy("dig"))
	assert_eq(s.building.depth, Meta.BASE_DEPTH_CAP, "nothing was filled in")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `Invalid call. Nonexistent function 'depth_cap'`.

- [ ] **Step 3: Implement**

`sim/meta.gd`:

```gdscript
## The depth ceiling a first run plays under, and what each level of `depth`
## adds: 2 -> 4 -> 6 -> 8, landing exactly on MAX_DEPTH_CAP.
const BASE_DEPTH_CAP := 2
const DEPTH_PER_LEVEL := 2
## This release's ladder top. NOT Building.MAX_FLOORS -- depth and height are
## independent budgets, and a tampered save must land here.
const MAX_DEPTH_CAP := 8

func depth_cap() -> int:
	return mini(BASE_DEPTH_CAP + DEPTH_PER_LEVEL * level_of("depth"), MAX_DEPTH_CAP)
```

`data/blueprints.json` gains:

```json
{ "id": "depth", "name": "Deep Excavation", "branch": "structure",
  "base": 9, "max_level": 3, "note": "+2 floors you may dig" }
```

`data/upgrades.json` gains:

```json
{ "id": "dig", "name": "Dig Down", "base": 400.0, "growth": 1.35, "max_level": 8 }
```

`sim/upgrades.gd`'s `_apply` gains:

```gdscript
		"dig":
			return building.dig()
```

`sim/game_state.gd`, beside the floor and shaft budgets:

```gdscript
	# No base subtraction, unlike floor and shaft: a building starts at depth 0,
	# so every level of `dig` is a purchase.
	upgrades.set_max_level("dig", meta.depth_cap())
	upgrades.grant_level("dig", building.depth, building)
```

`GameState.buy("dig")` must also grow `tenancy` and `fitout` — digging excavates a floor, and all three containers move together or the shared `FloorIndex` reports a size no array has.

- [ ] **Step 4: Run the whole suite**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/meta.gd sim/upgrades.gd sim/game_state.gd data/upgrades.json data/blueprints.json tests/test_meta.gd tests/test_upgrades.gd
git commit -m "Sell digging by the floor under a ceiling bought by demolishing

The third structure node, and the same shape floors and shafts already
follow: a per-run cash price under a permanent meta ceiling. 2/4/6/8,
landing exactly on MAX_DEPTH_CAP, clamped to this release's ladder rather
than to Building.MAX_FLOORS -- depth and height are independent budgets.

The budget takes no base subtraction, unlike floor and shaft: a building
starts at depth 0, so every level of dig is a purchase.

Digging EXCAVATES. It yields a vacant floor that then goes through the
ordinary lease flow, which is why tenancy and fitout grow on dig and not
on lease."
```

---

## Task 8: The board reaches the basement

**Files:**
- Modify: `sim/coords.gd`, `view/building_view.gd`, `view/floor_row.gd`
- Test: `tests/test_coords_scroll.gd`, `tests/test_board_input.gd`

**Interfaces:**
- Consumes: `Building.bottom_floor()`, `Building.depth`.
- Produces: `BoardCoords.footroom`.

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_coords_scroll.gd
func test_footroom_lets_the_dig_band_be_reached() -> void:
	# The mirror of headroom. The dig band is one floor BELOW the bottom floor,
	# so the upper clamp has to reach past the building the way the lower one
	# reaches past the roof.
	var c := BoardCoords.fixed(-2, 9, 120.0)
	c.set_viewport_height(600.0)
	c.footroom = 120.0
	c.scroll_to(1e9)
	var band_top := c.floor_to_y(c.bottom_floor) + 120.0
	assert_lte(band_top + 120.0, 600.0 + 0.01, "the whole band is inside the window")

func test_no_footroom_means_no_scrolling_past_the_bottom_floor() -> void:
	var c := BoardCoords.fixed(-2, 9, 120.0)
	c.set_viewport_height(600.0)
	c.footroom = 0.0
	c.scroll_to(1e9)
	assert_almost_eq(c.floor_to_y(c.bottom_floor) + 120.0, 600.0, 0.01,
		"the bottom floor sits on the bottom edge and no further")
```

```gdscript
# append to tests/test_board_input.gd
func test_a_basement_floor_is_labelled_P1_and_is_still_floor_minus_one() -> void:
	root.state.economy.accrue(1e9)
	assert_true(root.state.buy("dig"))
	await wait_physics_frames(3)
	var row: FloorRow = view._floors[0]
	assert_eq(row.floor_index, -1, "the index is signed")
	assert_eq(row._label.text, "P1", "the label is not")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `Invalid access to property or key 'footroom'`.

- [ ] **Step 3: Implement**

`sim/coords.gd`:

```gdscript
## Content BELOW the bottom floor that scrolling must be able to reach: the dig
## band. The exact mirror of `headroom`, and it widens the UPPER clamp for the
## same reason -- the band is a control, and a control you cannot scroll to is
## not a control.
var footroom: float = 0.0
```

and in `scroll_to`:

```gdscript
	var travel := maxf(content_height() + footroom - _viewport_height, 0.0)
```

`view/building_view.gd`: build `BoardCoords.fixed(_state.building.bottom_floor(), _state.building.floor_count - 1, FLOOR_HEIGHT)`; set `footroom` to `FLOOR_HEIGHT` while the run may still dig and `0.0` at the ceiling; build rows over `range(bottom_floor(), floor_count)` (audit site 9); add the dig band as the mirror of `_build_ghost_floor`, wired to a new `dig_requested` signal.

`view/floor_row.gd`:

```gdscript
func set_floor(index: int) -> void:
	floor_index = index
	# Basements read as P1, P2 counting DOWN. The index stays signed everywhere;
	# only the label differs. "-1" is the same width but reads as a subtraction.
	_label.text = str(index) if index >= 0 else "P%d" % -index
```

- [ ] **Step 4: Run the whole suite**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/coords.gd view/building_view.gd view/floor_row.gd tests/test_coords_scroll.gd tests/test_board_input.gd
git commit -m "Let the board scroll into the basement

footroom is headroom's mirror and exists for the same reason: the dig
band is a control, and a control the scroll range cannot reach is not a
control. Headroom shipped this morning for the ghost band above the roof;
this is the same fix pointing down.

Basement floors label as P1, P2 counting down. The index stays signed
everywhere including BoardCoords -- only the label differs. '-1' is the
same width in the 25-unit gutter but reads as a subtraction."
```

---

## Task 9: A garage to look at

**Files:**
- Create: `art/floors/parking.png` (384×240), `brand/art/floors/parking.png` (1280 wide)
- Modify: `brand/floor-art-prompts.md`
- Test: `tests/test_floor_scenery.gd`

- [ ] **Step 1: Un-pend the completeness test**

`test_every_shipped_tenant_kind_has_art` already reads `data/tenants.json` and requires every kind to resolve, so adding `parking` in Task 5 made it fail. Remove the pending marker; it is now the test for this task.

- [ ] **Step 2: Generate**

Append the subject to `brand/floor-art-prompts.md` under "The seven subjects", renaming that heading to "The subjects":

```
**8. Parking** (`parking`)
```
Subject: an underground car park. Two parking bays marked out on the floor with
flat painted lines, a low concrete beam across the upper wall, a square support
column on the left, and the bottom of a ramp entering from the right. Exposed
concrete in flat pale tan, teal bay markings, one rust-coloured sign panel with
no text on it.
```
```

Then run, from a directory containing `style.txt`:

```sh
export GEMINI_API_KEY="$(security find-generic-password -s nanobanana -w)"
python3 ~/.claude/plugins/cache/mobility-labs/ml/0.2.0/skills/nanobanana/generate.py \
  --prompt "$(cat style.txt)

Subject: an underground car park. Two parking bays marked out on the floor with flat painted lines, a low concrete beam across the upper wall, a square support column on the left, and the bottom of a ramp entering from the right. Exposed concrete in flat pale tan, teal bay markings, one rust-coloured sign panel with no text on it." \
  --output raw/parking.png --model pro --aspect-ratio 16:9 --resolution 2K
```

- [ ] **Step 3: Crop and install**

Left-aligned crop to 8:5, then `LANCZOS` to 384×240 into `art/floors/`, and a 1280-wide 64-colour copy into `brand/art/floors/`. **Check it against the scale table before accepting** — measure the object's height, not its top edge, since these rooms have a floor band along the bottom.

- [ ] **Step 4: Import and run**

```sh
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: PASS, including `test_every_image_matches_the_region_it_covers`.

- [ ] **Step 5: Commit**

```bash
git add art/floors/parking.png art/floors/parking.png.import brand/art/floors/parking.png brand/art/floors/parking.png.import brand/floor-art-prompts.md tests/test_floor_scenery.gd
git commit -m "Draw the garage

Eighth floor image, generated against the same style block and scale
table as the other seven. The completeness test drove this: it reads
data/tenants.json and requires every kind named there to resolve, so
adding `parking` in the catalog is what made it fail."
```

---

## Task 10: Save the depth, and measure the number

**Files:**
- Modify: `sim/save_codec.gd`
- Test: `tests/test_save_codec.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# append to tests/test_save_codec.gd
func test_depth_survives_a_round_trip() -> void:
	var s := _played_state()
	s.economy.cash = 1e9
	assert_true(s.buy("dig"))
	s.tenancy.lease(-1, "parking")
	var after := SaveCodec.decode(SaveCodec.encode(s), "res://data/tenants.json")
	assert_not_null(after)
	assert_eq(after.building.depth, 1)
	assert_eq(after.tenancy.kind_at(-1), "parking", "the basement's lease too")

func test_a_save_without_the_key_decodes_to_no_basement() -> void:
	# Every save written before this feature. It is not depth 0 by luck -- it was
	# written by a build that could not dig.
	var s := _played_state()
	var d: Dictionary = SaveCodec.encode(s)
	d.erase("depth")
	var after := SaveCodec.decode(d, "res://data/tenants.json")
	assert_not_null(after, "an older save still loads")
	assert_eq(after.building.depth, 0)

func test_an_absurd_depth_is_bounded_to_the_ladder() -> void:
	var s := _played_state()
	var d: Dictionary = SaveCodec.encode(s)
	d["depth"] = 99
	var after := SaveCodec.decode(d, "res://data/tenants.json")
	assert_not_null(after)
	assert_lte(after.building.depth, Meta.MAX_DEPTH_CAP)

func test_a_floors_array_that_disagrees_with_the_depth_is_refused() -> void:
	# floor_count and the floors array length used to be the same number. They
	# are not any more, so their agreement is a new thing to check.
	var s := _played_state()
	s.economy.cash = 1e9
	assert_true(s.buy("dig"))
	var d: Dictionary = SaveCodec.encode(s)
	var floors: Array = d["floors"]
	floors.remove_at(0)
	d["floors"] = floors
	assert_null(SaveCodec.decode(d, "res://data/tenants.json"),
		"length must equal floor_count + depth")
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `after.building.depth` is 0 where 1 was expected.

- [ ] **Step 3: Implement**

Encode `"depth": state.building.depth`, and write `floors` over
`range(state.building.bottom_floor(), state.building.floor_count)` (audit site 5).

Decode `depth` **before** the building is constructed:

```gdscript
	# Bounded against the LADDER top, not MAX_FLOORS: a hand-written save must
	# not mint a 40-deep basement. Read with .get because a save written before
	# digging existed has no such key -- the same additive argument that let
	# Meta.dev_unlocked into v4 without a version bump.
	var depth: int = _bounded_int(data.get("depth", 0), 0, Meta.MAX_DEPTH_CAP, 0)
```

then refuse when `saved_floors.size() != floors + depth`, then dig the building
`depth` times before restoring tenancy. Audit site 6 (`save_codec.gd:410`) reads
entry `i` as floor `i + building.bottom_floor()`.

- [ ] **Step 4: Run the whole suite**

Expected: PASS. Confirm `SaveCodec.VERSION` is still `4`.

- [ ] **Step 5: Measure PARK_BONUS and record the result**

This is a required step, not a follow-up. Using the dev board override
(`godot -- --board=10x2`), run to a steady state at depth 0 and at depth 2 with
both garages leased, and record in the spec's §9:

1. Expiry rate at each depth. If depth 2 more than doubles expiries, lower
   `PARK_BONUS` or set `BASE_DEPTH_CAP` to 1.
2. Net `lifetime_earnings` at each. Digging must be positive at run 1's
   two-shaft budget or nobody digs twice.
3. Whether the garage's own satisfaction ever falls enough to move out. If it
   cannot, §4's feedback loop is decorative and the entrance share should scale
   with satisfaction directly.

Replace the "THIS NUMBER IS A GUESS" comment with the measured finding, whatever
it is. Leaving it as a guess after this task is a plan failure.

- [ ] **Step 6: Commit**

```bash
git add sim/save_codec.gd tests/test_save_codec.gd docs/superpowers/specs/2026-08-04-building-downward-parking-design.md
git commit -m "Persist the basement inside save v4

No version bump and no migration: the decoder already reads optional keys
as data.get(key, default), which is the same argument that let
Meta.dev_unlocked into v4.

The floors array grows DOWNWARD -- written from bottom_floor to
floor_count, entry i is floor i + bottom_floor -- and depth is decoded
first so the mapping is unambiguous. A save whose length disagrees with
floor_count + depth is refused, which is a genuinely new check: those two
numbers used to be the same one.

An absurd depth is bounded against Meta.MAX_DEPTH_CAP and not
MAX_FLOORS, so a hand-written save cannot mint a 40-deep basement."
```

---

## Self-review

**Spec coverage.** §1 informs the plan's framing. §2 → Tasks 1, 3, 4 (and the nine audit sites are named against Tasks 3, 4, 6, 8, 10). §3 → Tasks 4, 5. §4 → Tasks 5, 6. §5 needs no code — it is the reason Task 6 adds no patience change. §6 → Task 7. §7 → Tasks 8, 9. §8 → Task 10. §9 → Task 10 Step 5. §10 is the out-of-scope list. §11's requirements are distributed across every task's tests.

**Audit sites, all nine assigned:** `building.gd:23` → T3. `tenancy.gd:46` → T4. `game_state.gd:369` → T6. `game_state.gd:443` (`_expire`) → T6. `save_codec.gd:262` → T10. `save_codec.gd:410` → T10. `auto_dispatch.gd:88` → T6. `dispatch_policy.gd:65` → T6. `building_view.gd:198` → T8.

**Type consistency.** `FloorIndex.slot/holds/size/dig/grow_up` are used identically in Tasks 3 and 4. `spawn_from_sources`'s fourth parameter is `PackedInt32Array` in both its definition and every call. `_destination_for` returns `Vector2i` from Task 2 onward, including in Task 6's edit.

**Known gap, deliberately left:** `auto_dispatch.gd:88` and `dispatch_policy.gd:65` are assigned to Task 6 but that task's tests do not exercise automation into the basement. If Task 6's implementer finds the sweep ignoring basement calls, that is a real bug and needs a test in `tests/test_auto_dispatch.gd` — a swept car must answer a call at −1.
