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

const VERSION := 3
const SUPPORTED_VERSIONS := [1, 2, 3]

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
	if int(data.get("version", -1)) >= 3:
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
	}

## Rebuilds a state from a save. Returns null when the save is unusable, so the
## caller starts fresh rather than running on a half-applied one.
static func decode(p_data: Dictionary) -> GameState:
	var data := _migrate_to_v3(p_data)
	if not _is_usable(data):
		return null

	var floors: int = int(data["floor_count"])
	var cars: Array = data["cars"]
	var state := GameState.new(floors, maxi(cars.size(), 1), int(data["seed"]))

	state.clock.ticks_executed = int(data["ticks"])
	state.economy.cash = float(data["cash"])
	state.economy.lifetime_earnings = float(data.get("lifetime", 0.0))
	state.economy.combo = float(data.get("combo", 1.0))
	state.economy.streak = int(data.get("streak", 0))
	state.economy.riders_served = int(data.get("riders_served", 0))

	# Levels before cars: restoring a level runs no effect, so the car values
	# saved alongside them are the authority on what the cars actually are.
	state.upgrades.restore_levels(data.get("levels", {}))

	for i in range(mini(cars.size(), state.building.cars.size())):
		var saved: Dictionary = cars[i]
		var car: ElevatorCar = state.building.cars[i]
		car.position_floor = float(saved.get("position_floor", 0.0))
		car.target_floor = int(saved.get("target_floor", 0))
		car.capacity = int(saved.get("capacity", car.capacity))
		car.floors_per_tick = float(saved.get("floors_per_tick", car.floors_per_tick))
		car.door_ticks = int(saved.get("door_ticks", car.door_ticks))
		car.spring_multiplier = float(saved.get("spring_multiplier", 1.0))

	var version := int(data["version"])
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
		var r: Dictionary = saved_floors[floor_index]
		if version >= 2 and not (r.has("kind") and r.has("class")):
			return null
		var vacant := bool(r.get("vacant", false))
		state.tenancy.restore_floor(floor_index, float(r.get("satisfaction", 1.0)),
			vacant, int(r.get("move_out_left", 0)))
		state.fitout.set_tier(floor_index, clampi(int(r.get("class", 1)), 1,
			state.catalog.max_tier()))
		state.tenancy.set_kind(floor_index, _restore_kind(state, floor_index, version, r, vacant))

	# Policies go through set_policy, so a save cannot grant a shaft a policy
	# the hardware does not support or more licences than were bought.
	var policies: Array = data.get("policies", [])
	for shaft in range(mini(policies.size(), state.building.cars.size())):
		state.set_policy(shaft, int(policies[shaft]))

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
	return int(data["floor_count"]) >= 1
