class_name Meta
extends RefCounted

## The persistent half of the game: Blueprints, the tech tree's levels, and the
## derivations a fresh run starts from. Pure data. It knows nothing about
## GameState -- GameState reads it, never the reverse.
##
## Definitions are data; EFFECTS are code, exactly as in Upgrades. data/ holds
## numeric coefficients over a fixed set of code-defined shapes and never
## expression strings, because running stored formulas through Expression is an
## eval.

const BASE_HEIGHT_CAP := 10
const HEIGHT_PER_LEVEL := 5
## This release's ladder top. NOT Building.MAX_FLOORS -- an implementer who
## clamps to 40 instead hands a tampered save a 40-floor cap.
const MAX_HEIGHT_CAP := 20
## Deliberately == Prestige.MAX_YIELD, so a legitimately clamped yield cannot
## fail its own decode on the next load. Pinned by a test.
const MAX_BLUEPRINTS := 1_000_000_000
const MAX_RUNS := 1_000_000
const BASE_STARTING_SHAFTS := 1

const MAX_NODES := 64
const MAX_BASE := 1_000_000
const MAX_NODE_LEVEL := 64

## Node id -> the Upgrades id whose STARTING level it grants. The mapping runs
## in THIS direction, and it is the thing an implementer gets wrong:
## Upgrades.has_effect is false for `motor`, `gearing` and `cabin`, which are
## not Upgrades ids at all. The Structure nodes are deliberately absent -- they
## map to no upgrade and are read by height_cap() and starting_shafts()
## instead.
const NODE_TO_UPGRADE := {"motor": "speed", "gearing": "doors", "cabin": "capacity"}

var blueprints: int = 0
var runs_completed: int = 0

var _spent: Dictionary = {}         # node id -> level
var _defs: Dictionary = {}          # node id -> {name, branch, base, max_level, note}
## A STORED flag, never `not _defs.is_empty()`: every malformed rule below is a
## mid-loop failure, and a partial load reporting "usable" makes restore()'s
## iterate-ids() rule silently drop every spent level for the missing nodes.
var _defs_loaded: bool = false

## Reads definitions. It does NOT own player progress: unlike
## Upgrades.load_defs (upgrades.gd:42) it never touches _spent, because defs
## must be loadable on every path and calling it after a restore would
## otherwise wipe the tree it exists to protect.
##
## "Malformed" is defined rather than gestured at, because this file sets the
## prices of a PERSISTENT currency: `"base": -2` makes every level affordable at
## zero Blueprints and turns `blueprints -= cost` into a credit.
func load_defs(path: String) -> bool:
	if _defs_loaded:
		return true
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var json := JSON.new()
	var text := f.get_as_text()
	f.close()
	if json.parse(text) != OK:
		return false
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var list: Variant = (parsed as Dictionary).get("nodes")
	if typeof(list) != TYPE_ARRAY:
		return false
	var nodes := list as Array
	if nodes.is_empty() or nodes.size() > MAX_NODES:
		return false

	# Built into a LOCAL and published only on success, so a mid-loop refusal
	# cannot leave a subset behind for is_usable() to report as fine.
	var built := {}
	for entry in nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var e := entry as Dictionary
		for key in ["id", "name", "branch", "base", "max_level"]:
			if not e.has(key):
				return false
		if typeof(e["id"]) != TYPE_STRING or (e["id"] as String).is_empty():
			return false
		var id: String = e["id"]
		if built.has(id):
			return false
		if typeof(e["name"]) != TYPE_STRING:
			return false
		if typeof(e["branch"]) != TYPE_STRING:
			return false
		if e["branch"] != "structure" and e["branch"] != "mechanical":
			return false
		# The upper bound on base is not tidiness: cost_of is base * (level + 1)
		# returning int, so 1e18 * 65 wraps int64 NEGATIVE, can_buy is then true
		# at a zero balance, and the subtraction CREDITS. Its job is to keep
		# base * (max_level + 1) overflow-free.
		if not _is_integral_in(e["base"], 1, MAX_BASE):
			return false
		if not _is_integral_in(e["max_level"], 1, MAX_NODE_LEVEL):
			return false
		var note: Variant = e.get("note", "")
		if typeof(note) != TYPE_STRING:
			return false
		built[id] = {
			"name": e["name"],
			"branch": e["branch"],
			"base": int(e["base"]),
			"max_level": int(e["max_level"]),
			"note": note,
		}

	_defs = built
	_defs_loaded = true
	return true

## True iff load_defs() has succeeded. Backed by the flag, not by the contents.
func is_usable() -> bool:
	return _defs_loaded

func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		out.append(id)
	return out

func name_of(id: String) -> String:
	return str(_defs[id]["name"]) if _defs.has(id) else id

func note_of(id: String) -> String:
	return str(_defs[id]["note"]) if _defs.has(id) else ""

func branch_of(id: String) -> String:
	return str(_defs[id]["branch"]) if _defs.has(id) else ""

# --- the tree ---------------------------------------------------------------

func level_of(id: String) -> int:
	return int(_spent.get(id, 0))

func is_maxed(id: String) -> bool:
	if not _defs.has(id):
		return true
	return level_of(id) >= int(_defs[id]["max_level"])

func cost_of(id: String) -> int:
	if not _defs.has(id):
		return 0
	return int(_defs[id]["base"]) * (level_of(id) + 1)

## True when the next level of this node would change nothing, mirroring
## Upgrades.is_zero_delta -- which is why the refusal lives in the sim rather
## than in a view enforcing a rule the sim does not hold.
##
## It takes an Upgrades because effect_value is an instance method, and it
## evaluates at THIS META's level, never the run's. Delegating to
## up.is_zero_delta(target) would read the run's CURRENT level: a player whose
## run had bought doors past the DOOR_TICKS_MIN plateau would see `gearing`
## refused even at gearing L0, precisely while shopping the panel before a
## demolish -- though the next run starts at doors <= 4, where the effect is
## real.
##
## Returns false for `height` and `shafts`: they map to no upgrade, so there is
## nothing to compare. Getting that wrong makes `height` permanently unbuyable.
func is_zero_delta(id: String, up: Upgrades) -> bool:
	if not NODE_TO_UPGRADE.has(id):
		return false
	var target: String = NODE_TO_UPGRADE[id]
	var lvl := level_of(id)
	return is_equal_approx(up.effect_value(target, lvl), up.effect_value(target, lvl + 1))

func can_buy(id: String, up: Upgrades) -> bool:
	if not _defs.has(id) or is_maxed(id):
		return false
	if is_zero_delta(id, up):
		return false
	return blueprints >= cost_of(id)

## The ONLY spender of Blueprints. Spending never routes through the cash path:
## no can_afford, no `cash -=`.
func buy(id: String, up: Upgrades) -> bool:
	if not can_buy(id, up):
		return false
	blueprints -= cost_of(id)      # BEFORE the level moves, or it prices the next one
	_spent[id] = level_of(id) + 1
	return true

# --- serialization ----------------------------------------------------------

## Deep. Never returns the live _spent: the staged clone in Prestige.demolish is
## independent only if this pair deep-copies at both ends, and a tidy-up that
## returned the live dictionary would quietly re-create the shared mutable state
## the clone exists to remove.
func to_dict() -> Dictionary:
	return {
		"blueprints": blueprints,
		"runs": runs_completed,        # the KEY is `runs`; the field is `runs_completed`
		"spent": _spent.duplicate(true),
	}

## ALL meta-block validation lives here. It returns false ONLY when there are no
## definitions to validate against -- a malformed or absent block is an EMPTY
## Meta, not a refusal, because in this codebase "refuse" means "delete":
## decode returns null, the boot path starts a fresh game, and the autosave
## overwrites the only copy within ten seconds. Losing a tech tree beats losing
## a building.
func restore(data: Variant) -> bool:
	if not _defs_loaded:
		return false
	blueprints = 0
	runs_completed = 0
	_spent = {}                        # fresh storage; never aliased from `data`
	if typeof(data) != TYPE_DICTIONARY:
		return true
	var d := data as Dictionary
	blueprints = _clamped_int(d.get("blueprints"), 0, MAX_BLUEPRINTS)
	runs_completed = _clamped_int(d.get("runs"), 0, MAX_RUNS)
	var spent: Variant = d.get("spent")
	if typeof(spent) != TYPE_DICTIONARY:
		return true
	# Iterate OUR ids, never the parsed dictionary's keys. Unknown ids are
	# dropped rather than stored, which also makes the parsed key count
	# irrelevant -- JSON parsing has already paid that allocation anyway.
	for id in ids():
		var raw: Variant = (spent as Dictionary).get(id)
		if raw == null:
			continue
		var lvl := _clamped_int(raw, 0, int(_defs[id]["max_level"]))
		if lvl > 0:
			_spent[id] = lvl
	return true

# --- the derivations --------------------------------------------------------
#
# THE definitions. The panel annotates from these, so an annotation can never
# fabricate a cap by copying the formula and dropping a clamp.

func height_cap() -> int:
	return mini(BASE_HEIGHT_CAP + HEIGHT_PER_LEVEL * level_of("height"), MAX_HEIGHT_CAP)

func starting_shafts() -> int:
	return mini(BASE_STARTING_SHAFTS + level_of("shafts"), Building.MAX_SHAFTS)

## The level an upgrade BEGINS a run at. Takes an Upgrades id, not a node id.
func starting_level(upgrade_id: String) -> int:
	for node_id in NODE_TO_UPGRADE:
		if NODE_TO_UPGRADE[node_id] == upgrade_id:
			return level_of(node_id)
	return 0

## Clamps in FLOAT space before the int() cast, because out-of-range float->int
## is platform-defined (it saturates on arm64; the ship target is threadless
## WASM, a different toolchain) and a dev-machine test would pass either way.
## Type first: is_finite(Dictionary) is itself a runtime error.
static func _clamped_int(v: Variant, lo: int, hi: int) -> int:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return lo
	var fv := float(v)
	if not is_finite(fv) or fv != floorf(fv):
		return lo
	return int(clampf(fv, float(lo), float(hi)))

## Numeric, finite, integral, and within [lo, hi]. TYPE FIRST: is_finite() on a
## Dictionary is itself a runtime error, so the order is load-bearing rather
## than stylistic.
static func _is_integral_in(v: Variant, lo: int, hi: int) -> bool:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	if t == TYPE_FLOAT:
		var fv: float = v
		if not is_finite(fv) or fv != floorf(fv):
			return false
	var n := int(v)
	return n >= lo and n <= hi
