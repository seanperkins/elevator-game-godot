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
