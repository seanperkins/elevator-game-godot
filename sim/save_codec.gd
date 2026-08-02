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
## refused, never be half-read into a state that looks fine and is not.

const VERSION := 1

static func encode(state: GameState) -> Dictionary:
	var cars := []
	for car in state.building.cars:
		cars.append({
			"position_row": car.position_row,
			"target_row": car.target_row,
			"capacity": car.capacity,
			"rows_per_tick": car.rows_per_tick,
			"door_ticks": car.door_ticks,
			"spring_multiplier": car.spring_multiplier,
		})

	var levels := {}
	for id in state.upgrades.ids():
		levels[id] = state.upgrades.level_of(id)

	var policies := []
	for shaft in range(state.building.cars.size()):
		policies.append(state.auto.preset_of(shaft))

	# Tenancy is stored per row rather than as a summary: satisfaction is what
	# rent is scaled by, and a vacancy the player has not paid to re-lease is a
	# debt they would otherwise reload their way out of.
	var rows := []
	for row in range(state.building.row_count):
		rows.append({
			"satisfaction": state.tenancy.satisfaction_at(row),
			"vacant": state.tenancy.is_vacant(row),
			"move_out_left": state.tenancy.move_out_ticks_left(row),
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
		"row_count": state.building.row_count,
		"cars": cars,
		"levels": levels,
		"policies": policies,
		"rows": rows,
	}

## Rebuilds a state from a save. Returns null when the save is unusable, so the
## caller starts fresh rather than running on a half-applied one.
static func decode(data: Dictionary) -> GameState:
	if not _is_usable(data):
		return null

	var rows: int = int(data["row_count"])
	var cars: Array = data["cars"]
	var state := GameState.new(rows, maxi(cars.size(), 1), int(data["seed"]))

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
		car.position_row = float(saved.get("position_row", 0.0))
		car.target_row = int(saved.get("target_row", 0))
		car.capacity = int(saved.get("capacity", car.capacity))
		car.rows_per_tick = float(saved.get("rows_per_tick", car.rows_per_tick))
		car.door_ticks = int(saved.get("door_ticks", car.door_ticks))
		car.spring_multiplier = float(saved.get("spring_multiplier", 1.0))

	var saved_rows: Array = data.get("rows", [])
	for row in range(mini(saved_rows.size(), state.building.row_count)):
		var r: Dictionary = saved_rows[row]
		state.tenancy.restore_row(row, float(r.get("satisfaction", 1.0)),
			bool(r.get("vacant", false)), int(r.get("move_out_left", 0)))

	# Policies go through set_policy, so a save cannot grant a shaft a policy
	# the hardware does not support or more licences than were bought.
	var policies: Array = data.get("policies", [])
	for shaft in range(mini(policies.size(), state.building.cars.size())):
		state.set_policy(shaft, int(policies[shaft]))

	return state

## A save has to be recognisably one of ours, of a version we understand, and
## carry the fields decode indexes without a default. Anything else is refused
## whole rather than partly applied.
static func _is_usable(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION:
		return false
	for key in ["seed", "ticks", "cash", "row_count", "cars"]:
		if not data.has(key):
			return false
	if typeof(data["cars"]) != TYPE_ARRAY:
		return false
	return int(data["row_count"]) >= 1
