class_name Upgrades
extends RefCounted

## Definitions are data; EFFECTS are code. data/ holds numeric coefficients over
## a fixed set of code-defined shapes and never expression strings, because
## running stored formulas through Expression is an eval.

const DOOR_TICKS_BASE := 20
const DOOR_TICKS_MIN := 4
const SPEED_BASE := 0.1
const CAPACITY_BASE := 4

var _defs: Dictionary = {}          # id -> {name, base, growth, max_level}
var _levels: Dictionary = {}        # id -> int

func load_defs(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var list: Variant = parsed.get("upgrades")
	if typeof(list) != TYPE_ARRAY:
		return false
	for entry in (list as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var id: String = str(entry.get("id", ""))
		if id.is_empty():
			return false
		_defs[id] = {
			"name": str(entry.get("name", id)),
			"base": float(entry.get("base", 10.0)),
			"growth": float(entry.get("growth", 1.5)),
			"max_level": int(entry.get("max_level", 1)),
		}
		_levels[id] = 0
	return true

func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		out.append(id)
	return out

func name_of(id: String) -> String:
	return str(_defs[id]["name"]) if _defs.has(id) else id

func level_of(id: String) -> int:
	return int(_levels.get(id, 0))

func is_maxed(id: String) -> bool:
	if not _defs.has(id):
		return true
	return level_of(id) >= int(_defs[id]["max_level"])

func cost_of(id: String) -> float:
	if not _defs.has(id):
		return INF
	var d: Dictionary = _defs[id]
	return float(d["base"]) * pow(float(d["growth"]), float(level_of(id)))

func purchase(id: String, econ: Economy, building: Building) -> bool:
	if not _defs.has(id) or is_maxed(id):
		return false
	if is_zero_delta(id):
		return false            # a level that changes nothing is not for sale
	var cost := cost_of(id)
	if not econ.can_afford(cost):
		return false
	if not _apply(id, building):
		return false                # structural refusal: do not charge
	econ.spend(cost)
	_levels[id] = level_of(id) + 1
	return true

## Returns false if the effect could not be applied, so the player is not
## charged for a purchase that did nothing.
func _apply(id: String, building: Building) -> bool:
	match id:
		"shaft":
			if not building.add_shaft():
				return false
			_sync_car(building.cars[building.cars.size() - 1])
			return true
		"row":
			return building.add_row()
		"auto":
			return true          # licences a shaft; nothing on a car changes
		"doors", "speed", "capacity":
			# Level up first so _sync_car reads the new value.
			_levels[id] = level_of(id) + 1
			for car in building.cars:
				_sync_car(car)
			_levels[id] = level_of(id) - 1
			return true
		_:
			return false

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
		"auto":
			# How many shafts may run a dispatch policy at once. Not a car
			# property, so _sync_car never reads it.
			return float(level)
		_:
			return 0.0

func has_effect(id: String) -> bool:
	return id == "doors" or id == "speed" or id == "capacity" or id == "auto"

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
