class_name SaveCodec
extends RefCounted

## Turns a GameState into a plain Dictionary and back.
##
## SCOPE, deliberately narrow: this persists what you built. It does NOT model
## time passing while the game is closed. Loading resumes exactly where you left
## off, as though no time had passed at all -- no offline earnings, no catch-up
## integrator. That machinery is §9.1 of the design spec and is the least
## settled part of it; guessing at it here would bake in a decision that wants
## its own pass. A save that loses nothing is worth having before one that
## invents something.
##
## Pure data in, pure data out, no FileAccess: the round trip is unit-tested
## headlessly and the file handling lives in SaveStore.
##
## FORMAT IS VERSIONED. A save written by an older build must either load or be
## refused, never be half-read into a state that looks fine and is not. v2 adds a
## kind and a class per floor; v1 migrates -- §4.3 defines what floors past the
## roster get, so a v1 fallthrough is read, not refused. v3 renames the domain
## vocabulary from "row" to "floor" and migrates the keys on read.
##
## v4 adds a `meta` block: the persistent Blueprints and tech tree. It rides in
## the same file as the run because a demolish must persist the credited
## Blueprints and the discarded building in ONE write -- a crash between two
## writes either duplicates the yield or destroys it. A save at version <= 3 has
## no meta by definition and is GRANTED the height levels its building already
## implies; a v4 save whose meta is absent or malformed gets an EMPTY one and is
## never granted anything.

const VERSION := 4
const SUPPORTED_VERSIONS := [1, 2, 3, 4]

## Bounds for the save-derived values that have no natural ceiling elsewhere.
## MAX_MONEY is far past any reachable balance and exists only to keep INF out
## of a currency: once any of these is INF every comparison degrades silently.
const MAX_MONEY := 1e15
## CAPACITY_BASE + capacity.max_level, and MIN_SPEED keeps a car from being
## frozen in place by a saved zero.
const MAX_CAPACITY := Upgrades.CAPACITY_BASE + 8
const MAX_SPEED := Upgrades.SPEED_BASE * (1.0 + 0.25 * 12.0)
const MIN_SPEED := 0.0001
## An upper bound for restored upgrade LEVELS. Deliberately far above any real
## max_level: restore_levels has no upper clamp on purpose (a level above
## max_level is inert, not an error), so this bounds only the CAST, not the
## documented behaviour. Without it a finite, integral, out-of-range float --
## 1e300 -- passes the type guard below and saturates to int64 max on arm64,
## with the ship target's behaviour undefined.
const MAX_LEVEL := 1 << 20

## v3 is a KEY RENAME, not a format change: a v1 or v2 save differs only in how
## these are spelled. Migration runs before _is_usable, which indexes the new
## names.
##
## `version` is deliberately NOT rewritten. The v1 and v2 branches further down
## still have to know which one they are reading, and a save that claimed to be
## v3 after a key rename would skip the tenancy migration it still needs.
const V3_KEYS := {"row_count": "floor_count", "rows": "floors"}
const V3_CAR_KEYS := {
	"position_row": "position_floor",
	"target_row": "target_floor",
	"rows_per_tick": "floors_per_tick",
}

static func _migrate_to_v3(data: Dictionary) -> Dictionary:
	# Float-compared for the same reason _is_usable is: an out-of-range cast to
	# int64 saturates on arm64 and returns INT64_MIN on x86-64, so a version of
	# 1e300 skipped this migration on one target and ran it on the other.
	#
	# No observable difference TODAY -- _is_usable refuses such a save on both,
	# so only the path there diverged, not the outcome. Changed anyway, because
	# the identical shape one function away is what cost a day of red CI, and
	# for every version a real save can hold the two forms agree exactly.
	if float(data.get("version", -1)) >= 3.0:
		return data
	var out := data.duplicate(true)
	for old in V3_KEYS:
		if out.has(old):
			out[V3_KEYS[old]] = out[old]
			out.erase(old)
	for car in out.get("cars", []):
		if typeof(car) != TYPE_DICTIONARY:
			continue
		for old in V3_CAR_KEYS:
			if car.has(old):
				car[V3_CAR_KEYS[old]] = car[old]
				car.erase(old)
	var levels: Dictionary = out.get("levels", {})
	if levels.has("row"):
		levels["floor"] = levels["row"]
		levels.erase("row")
	return out

## Refuses top-level shapes that MIGRATION ITSELF would abort on, which is why
## it runs before _migrate_to_v3 rather than after it.
##
## TYPE ONLY. It performs no clamping and no semantic checks -- those live in
## decode beside the assignments they guard.
##
## `meta` is deliberately NOT preflighted: the rule elsewhere is that an absent
## OR malformed v4 meta yields an empty Meta and decodes successfully, so
## refusing a non-Dictionary meta here would contradict the rescue three
## functions away. Meta.restore() already handles every malformed shape without
## throwing, because it type-checks before maxi and iterates ids() rather than
## the parsed keys.
##
## Type first, then value, throughout: is_finite(Dictionary) is itself a
## runtime error.
## Every conversion whose argument comes from the save is type-guarded in a
## frame that can still refuse -- in decode, never in a `void` callee.
## restore_levels is exactly the counterexample: it does maxi(int(levels[id]), 0)
## with no type check, so a container value aborts it MID-LOOP and decode
## returns a non-null, HALF-restored state.
##
## The consequence of a violation is CLAMP, not refuse, for every row these
## guard. That is a deliberate override of the base design's
## reject-do-not-clamp rule, stated rather than made silently: SaveStore has no
## backup-before-refuse for a REFUSED (as opposed to truncated) save and
## game_root has no writes_disabled latch, so a rejection deletes a building.
static func _num(v: Variant, fallback: float) -> float:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return fallback
	var fv := float(v)
	return fv if is_finite(fv) else fallback

## clampf(NAN, 1, 10) returns NAN, so the finite check has to come first and
## cannot be folded into the clamp.
static func _bounded(v: Variant, lo: float, hi: float, fallback: float) -> float:
	return clampf(_num(v, fallback), lo, hi)

## Clamps in FLOAT space before the int() cast: int(roundf(INF)) saturates to
## 9223372036854775807 on arm64 and is platform-defined on WASM, which is
## exactly the hazard yield_for refuses to accept.
static func _bounded_int(v: Variant, lo: int, hi: int, fallback: int) -> int:
	return int(_bounded(v, float(lo), float(hi), float(fallback)))

static func _preflight(data: Dictionary) -> bool:
	if not _is_number(data.get("version", 0)):
		return false
	if not _is_number(data.get("floor_count", 1)):
		return false
	# {"levels": []} assigns an Array to a Dictionary-typed local at :55.
	if data.has("levels") and typeof(data["levels"]) != TYPE_DICTIONARY:
		return false
	# {"cars": null} genuinely throws -- Dictionary.get returns the STORED null
	# rather than the default, so `for car in out.get("cars", [])` iterates it.
	for key in ["cars", "floors", "policies"]:
		if data.has(key) and typeof(data[key]) != TYPE_ARRAY:
			return false
	return true

## Numeric, finite and integral.
##
## A STORED null is rejected, while an ABSENT key is not: Dictionary.get returns
## the stored null but the caller's own default when the key is missing, so
## rejecting null here refuses {"version": null} and still lets a v1 save with
## no such key through to the checks that handle it.
static func _is_number(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t != TYPE_FLOAT:
		return false
	var fv: float = v
	return is_finite(fv) and fv == floorf(fv)

## A SEPARATE function, not a phase appended inside _migrate_to_v3: that one
## early-returns at version >= 3 (:40-42), so a v4 phase nested inside it would
## never run for the v3 saves that need it most.
##
## v4 adds a key rather than moving one, so there is nothing to rewrite -- an
## absent meta block is handled by the version-gated builders below.
static func _migrate_to_v4(data: Dictionary) -> Dictionary:
	return data

## The height levels a legacy building already implies. version <= 3 ONLY.
##
## Exact, not approximate: the ladder is 10 + 5n, so this inverts it. The levels
## are GRANTED, not charged -- blueprints stays 0 -- because charging for what
## is already built would present an existing player with a building they cannot
## afford to keep.
##
## Keying this on `not data.has("meta")` instead would route a V4 save whose
## meta key is absent here, granting Structure levels permanently to a truncated
## write or a tampered file. Hence the version gate at the call site.
static func _legacy_meta(floor_count: int, blueprints_path: String) -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	m.restore({"spent": {"height": clampi(ceili((floor_count - 10) / 5.0), 0, 2)}})
	return m

## blueprints 0, runs 0, spent {}. version == 4, absent OR malformed.
##
## "Does not refuse" and "receives grandfather grants" are different properties.
## Both v4 paths do not refuse; NEITHER grants.
static func _empty_meta(blueprints_path: String) -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	return m

## The tech tree is designed to outlive a discarded building, so a run we refuse
## must not take it down. decode keeps four refusal paths besides the meta block
## -- the unsupported-version guard, _is_usable's missing-key check, the v2+
## short-floors rule and the missing kind/class rule -- and under v4 every one of
## them would otherwise destroy permanent progress along with the run.
##
## decode's own contract is UNCHANGED: it still returns null on refusal, which
## five existing tests and two docstrings depend on. This is a separate,
## explicitly named function.
##
## Three rules, all load-bearing:
##
## 1. It NEVER calls _legacy_meta(). That derives free height levels from a
##    floor_count the refusal has just declared untrustworthy -- a hand-written
##    {"version": 3, "floor_count": 20, "floors": []} would mint the whole cap
##    ladder from a save that does not load.
## 2. It reads the UNMIGRATED dictionary, using data.get exclusively.
##    _migrate_to_v3's first statement is int(data.get("version", -1)), the exact
##    abort the preflight guards decode against -- and salvage runs under a
##    separate call the preflight never covers. Migration is unnecessary here: it
##    touches only V3_KEYS, V3_CAR_KEYS and `levels`, and never the "meta" key.
## 3. It deliberately bypasses the version guard for the meta block, so a save
##    written by a future v5 has its `spent` reinterpreted under v4 semantics.
##    Meta.restore()'s clamps bound the damage. Written down because the version
##    guard is otherwise the only thing making "we do not read formats we do not
##    understand" true.
static func salvage_meta(p_data: Dictionary,
		blueprints_path := "res://data/blueprints.json") -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	m.restore(p_data.get("meta"))
	return m

static func encode(state: GameState) -> Dictionary:
	var cars := []
	for car in state.building.cars:
		cars.append({
			"position_floor": car.position_floor,
			"target_floor": car.target_floor,
			"capacity": car.capacity,
			"floors_per_tick": car.floors_per_tick,
			"door_ticks": car.door_ticks,
			"spring_multiplier": car.spring_multiplier,
		})

	var levels := {}
	for id in state.upgrades.ids():
		levels[id] = state.upgrades.level_of(id)

	var policies := []
	for shaft in range(state.building.cars.size()):
		policies.append(state.auto.preset_of(shaft))

	# Tenancy is stored per floor rather than as a summary: satisfaction is what
	# rent is scaled by, and a vacancy the player has not paid to re-lease is a
	# debt they would otherwise reload their way out of.
	var floors := []
	for floor_index in range(state.building.floor_count):
		floors.append({
			"satisfaction": state.tenancy.satisfaction_at(floor_index),
			"vacant": state.tenancy.is_vacant(floor_index),
			"move_out_left": state.tenancy.move_out_ticks_left(floor_index),
			# null, not absent: v2 requires the field present, and a vacant or
			# newly purchased floor genuinely has no kind. Without an explicit
			# encoding "a missing kind is malformed" and "vacant floors have no
			# kind" contradict each other.
			"kind": null if state.tenancy.kind_at(floor_index).is_empty() \
				else state.tenancy.kind_at(floor_index),
			"class": state.fitout.tier_at(floor_index),
		})

	return {
		"version": VERSION,
		"seed": state.spawner.seed_value(),
		"ticks": state.clock.ticks_executed,
		"cash": state.economy.cash,
		"lifetime": state.economy.lifetime_earnings,
		"combo": state.economy.combo,
		"streak": state.economy.streak,
		"riders_served": state.economy.riders_served,
		"floor_count": state.building.floor_count,
		"cars": cars,
		"levels": levels,
		"policies": policies,
		"floors": floors,
		"meta": state.meta.to_dict(),
	}

## Rebuilds a state from a save. Returns null when the save is unusable, so the
## caller starts fresh rather than running on a half-applied one.
## The two trailing parameters are default-valued so all 28 existing
## one-argument call sites stay source-compatible. They exist because decode
## CONSTRUCTS the first GameState from a dictionary -- there is no prior
## instance whose retained paths it could read -- so without them a test cannot
## hand it a malformed blueprint catalog without mutating the shipped file.
static func decode(p_data: Dictionary,
		catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> GameState:
	# Validation cannot start after migration, because migration itself throws:
	# _migrate_to_v3's first statement casts `version` (:41) and it assigns
	# `levels` to a TYPED Dictionary (:55), both before any check exists in the
	# flow.
	if not _preflight(p_data):
		return null
	var data := _migrate_to_v4(_migrate_to_v3(p_data))
	if not _is_usable(data):
		return null

	# Bounded rather than cast raw: _is_number admits any finite integral float,
	# including 1e300, and Building._init's clampi would only see a saturated
	# value.
	var floors: int = _bounded_int(data["floor_count"], 1, Building.MAX_FLOORS, 1)
	var version := int(data["version"])

	# The Meta must exist before GameState.new, because every cap derivation
	# lives in _init. And grandfathering runs AFTER migration, because v1 and v2
	# spell the key `row_count` -- reading floor_count first yields 0 and grants
	# a 20-floor v2 save a cap of 10.
	var meta: Meta
	if version <= 3:
		meta = _legacy_meta(floors, blueprints_path)
	else:
		meta = _empty_meta(blueprints_path)
		if meta != null and not meta.restore(data.get("meta")):
			return null
	if meta == null:
		return null                 # malformed SHIPPED data is fatal

	var cars: Array = data["cars"]
	# The seed feeds RandomNumberGenerator.seed, so it takes a float-space bound
	# before the cast like every other integral conversion here.
	var state := GameState.new(floors, maxi(cars.size(), 1),
		_bounded_int(data["seed"], 0, 1 << 60, 0), catalog_path, meta, blueprints_path)
	if not state.is_valid():
		return null

	state.clock.ticks_executed = _bounded_int(data["ticks"], 0, 1 << 60, 0)
	state.economy.cash = _bounded(data["cash"], 0.0, MAX_MONEY, 0.0)
	state.economy.lifetime_earnings = _bounded(data.get("lifetime", 0.0), 0.0,
		MAX_MONEY, 0.0)
	# `combo` is restored beside `lifetime` and writes straight INTO it:
	# credit_delivery does `paid = fare * combo; lifetime_earnings += paid` and
	# then heals the combo on the next line, so "combo": 1e400 poisons the
	# prestige input on the first delivery, after any check on `lifetime` has
	# run, and erases its own evidence.
	state.economy.combo = _bounded(data.get("combo", 1.0), 1.0, Economy.COMBO_MAX, 1.0)
	state.economy.streak = _bounded_int(data.get("streak", 0), 0, 1 << 40, 0)
	state.economy.riders_served = _bounded_int(data.get("riders_served", 0), 0,
		1 << 40, 0)

	# Levels before cars: restoring a level runs no effect, so the car values
	# saved alongside them are the authority on what the cars actually are.
	#
	# Type-guarded HERE, in a frame that can still refuse, because
	# restore_levels is void: aborting inside it half-restores and hands back a
	# non-null state whose surviving levels depend on iteration order.
	var levels: Dictionary = data.get("levels", {})
	var bounded_levels := {}
	for id in levels.keys():
		var lt := typeof(levels[id])
		if lt != TYPE_INT and lt != TYPE_FLOAT:
			return null
		# The type guard alone is a MID-LOOP-ABORT guard, not a value bound.
		# restore_levels does maxi(int(levels[id]), 0) with no clamp, so a
		# finite out-of-range float reaches a platform-defined conversion.
		bounded_levels[id] = _bounded_int(levels[id], 0, MAX_LEVEL, 0)
	state.upgrades.restore_levels(bounded_levels)

	var top_floor := float(state.building.floor_count - 1)
	for i in range(mini(cars.size(), state.building.cars.size())):
		if typeof(cars[i]) != TYPE_DICTIONARY:
			return null
		var saved: Dictionary = cars[i]
		var car: ElevatorCar = state.building.cars[i]
		# int(roundf(INF)) saturates to int64 max on arm64 and is
		# platform-defined on WASM, so these are clamped in float space first.
		car.position_floor = _bounded(saved.get("position_floor", 0.0), 0.0,
			top_floor, 0.0)
		car.target_floor = _bounded_int(saved.get("target_floor", 0), 0,
			state.building.floor_count - 1, 0)
		# A saved capacity of 1e9 delivers a billion riders in one door cycle,
		# which is ~$3.09e9 and 5,559 Blueprints -- 59x the whole tree,
		# permanently. Same route into lifetime_earnings as `combo`.
		car.capacity = _bounded_int(saved.get("capacity", car.capacity), 1,
			MAX_CAPACITY, car.capacity)
		car.floors_per_tick = _bounded(saved.get("floors_per_tick",
			car.floors_per_tick), MIN_SPEED, MAX_SPEED, car.floors_per_tick)
		car.door_ticks = _bounded_int(saved.get("door_ticks", car.door_ticks),
			Upgrades.DOOR_TICKS_MIN, Upgrades.DOOR_TICKS_BASE, car.door_ticks)
		# The only legitimate non-1.0 value. Leaving one field of four unbounded
		# invites treating the whole set as advisory.
		car.spring_multiplier = _bounded(saved.get("spring_multiplier", 1.0), 1.0,
			Upgrades.SPRING_BASE, 1.0)

	var saved_floors: Array = data.get("floors", [])
	# v1 may fall through -- §4.3 defines what floors past the roster get.
	# v2 may not: a short array silently keeps a constructor default that
	# contradicts the save, and past the roster that default is VACANCY, i.e.
	# the silent loss of a floor the player leased.
	# `>= 2`, not `== 2`: v3 is v2's format with renamed keys, so it inherits
	# this refusal. Pinning the literal is how the guard silently stopped
	# covering current saves the moment VERSION moved.
	if version >= 2 and saved_floors.size() < state.building.floor_count:
		return null

	for floor_index in range(mini(saved_floors.size(), state.building.floor_count)):
		if typeof(saved_floors[floor_index]) != TYPE_DICTIONARY:
			return null
		var r: Dictionary = saved_floors[floor_index]
		if version >= 2 and not (r.has("kind") and r.has("class")):
			return null
		# bool() has NO Variant constructor for String, Dictionary or Array, so
		# a bare bool(r.get("vacant")) aborts decode's own frame on
		# {"vacant": "x"} -- a safe null, but an engine error all the same.
		var raw_vacant: Variant = r.get("vacant", false)
		var vacant := false
		if typeof(raw_vacant) == TYPE_BOOL:
			vacant = raw_vacant
		elif typeof(raw_vacant) == TYPE_INT or typeof(raw_vacant) == TYPE_FLOAT:
			vacant = _num(raw_vacant, 0.0) != 0.0
		state.tenancy.restore_floor(floor_index,
			_bounded(r.get("satisfaction", 1.0), 0.0, 1.0, 1.0), vacant,
			_bounded_int(r.get("move_out_left", 0), 0, Tenancy.MOVE_OUT_TICKS, 0))
		state.fitout.set_tier(floor_index,
			_bounded_int(r.get("class", 1), Fitout.BASE_TIER, state.catalog.max_tier(),
				Fitout.BASE_TIER))
		state.tenancy.set_kind(floor_index, _restore_kind(state, floor_index, version, r, vacant))

	# Policies go through set_policy, so a save cannot grant a shaft a policy
	# the hardware does not support or more licences than were bought.
	var policies: Array = data.get("policies", [])
	for shaft in range(mini(policies.size(), state.building.cars.size())):
		# Per-element NUMERIC, not per-element Dictionary: the elements are
		# integers, and a container check here would silently drop every saved
		# dispatch policy.
		var preset := _bounded_int(policies[shaft], 0, 1 << 20,
			DispatchPolicy.Preset.MANUAL)
		if not DispatchPolicy.PRESET_ORDER.has(preset):
			preset = DispatchPolicy.Preset.MANUAL
		state.set_policy(shaft, preset)

	return state

## A vacant floor has no kind. A v1 floor infers `apartments`; a v2 floor carries an
## explicit id or null. Either way the result is cross-checked against the
## restored class, because independent validation lets {class: 1, kind:
## "law_firm"} through -- a known id skips the unknown-id fallback and the
## class clamp never looks at the kind.
static func _restore_kind(state: GameState, floor_index: int, version: int,
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
	var tier := state.fitout.tier_at(floor_index)
	if k == null or k.requires_class > tier:
		var fallback := state.catalog.cheapest_for_class(tier)
		return "" if fallback == null else fallback.id
	return id

## A save has to be recognisably one of ours, of a version we understand, and
## carry the fields decode indexes without a default. Anything else is refused
## whole rather than partly applied.
static func _is_usable(data: Dictionary) -> bool:
	if not SUPPORTED_VERSIONS.has(int(data.get("version", -1))):
		return false
	for key in ["seed", "ticks", "cash", "floor_count", "cars"]:
		if not data.has(key):
			return false
	if typeof(data["cars"]) != TYPE_ARRAY:
		return false
	# Compared as a FLOAT, deliberately. `int(data["floor_count"]) >= 1` looks
	# equivalent and is not: the cast of an out-of-range float to int64 is
	# platform-defined, and the two targets this ships to disagree about it.
	#
	#   arm64 (macOS, iOS):  int(1e300) saturates to INT64_MAX -> >= 1 is TRUE
	#   x86-64 (Linux CI):   cvttsd2si returns the "integer indefinite" value
	#                        INT64_MIN -> >= 1 is FALSE
	#
	# So a save with floor_count 1e300 was accepted here and REFUSED in CI, on
	# the same commit -- a green local suite over a red pipeline, for a whole
	# day. _bounded_int exists precisely to keep such values away from a raw
	# cast, but this guard runs BEFORE any bounding and had one of its own.
	#
	# The float comparison is exact for every finite value and identical on both
	# targets. _preflight has already established this is a finite, integral
	# number, so there is nothing the cast bought.
	return float(data["floor_count"]) >= 1.0
