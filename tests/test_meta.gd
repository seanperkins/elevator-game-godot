extends GutTest

## Meta is the persistent half of the game. Its loader is the only defence
## between a typo in shipped data and an unbounded Blueprint mint, so the
## malformed cases below are the point of the file, not its edges.

const DEFS := "res://data/blueprints.json"

func loaded() -> Meta:
	var m := Meta.new()
	assert_true(m.load_defs(DEFS), "the shipped catalog loads")
	return m

## Writes a defs file to user:// so a malformed-data test never has to mutate
## the shipped one.
func write_defs(nodes: Array) -> String:
	var path := "user://test_blueprints.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"nodes": nodes}))
	f.close()
	return path

func ok_node(overrides: Dictionary = {}) -> Dictionary:
	var n := {"id": "height", "name": "Taller Foundations", "branch": "structure",
		"base": 2, "max_level": 2, "note": "+5 floors"}
	for k in overrides:
		n[k] = overrides[k]
	return n

func test_the_shipped_catalog_loads_and_is_usable() -> void:
	var m := loaded()
	assert_true(m.is_usable(), "usable")
	assert_eq(Array(m.ids()), ["height", "shafts", "motor", "gearing", "cabin"],
		"every node, in file order")

func test_a_missing_file_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs("res://data/does_not_exist.json"), "refused")
	assert_false(m.is_usable(), "and not usable")

func test_a_negative_base_is_refused() -> void:
	# `blueprints -= cost` with a negative cost CREDITS. One typo, unbounded mint.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"base": -2})])), "refused")
	assert_false(m.is_usable(), "and not usable")

func test_an_enormous_base_is_refused() -> void:
	# base * (max_level + 1) must not wrap int64 negative -- can_buy would then
	# be true at a zero balance and the subtraction would credit.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"base": 1e18, "max_level": 64})])),
		"refused")

func test_a_duplicate_id_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node(), ok_node()])), "refused")

func test_an_unknown_branch_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"branch": "wizardry"})])), "refused")

func test_a_missing_required_key_is_refused() -> void:
	for key in ["id", "name", "branch", "base", "max_level"]:
		var node := ok_node()
		node.erase(key)
		var m := Meta.new()
		assert_false(m.load_defs(write_defs([node])), "missing %s is refused" % key)

func test_a_partial_load_reports_unusable_and_keeps_nothing() -> void:
	# The failure that matters: a file whose SECOND node is bad leaves the first
	# behind. If is_usable() read `not _defs.is_empty()` it would say yes, ids()
	# would return a subset, and restore()'s iterate-ids() rule would then drop
	# every spent level for the missing nodes -- which the autosave persists ten
	# seconds later.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node(),
		ok_node({"id": "shafts", "base": -1})])), "refused")
	assert_false(m.is_usable(), "not usable, despite one good entry")
	assert_eq(m.ids().size(), 0, "and nothing kept")

func test_load_defs_does_not_clear_progress() -> void:
	# Upgrades.load_defs zeroes _levels; a faithful mirror here would wipe the
	# tree whenever defs happened to load after a restore.
	var m := loaded()
	m.blueprints = 9
	assert_true(m.load_defs(DEFS), "a second load succeeds")
	assert_eq(m.blueprints, 9, "and reads definitions without touching progress")

func test_the_note_survives_the_load() -> void:
	assert_string_contains(loaded().note_of("height"), "floors", "the panel renders it")

func test_the_branches_are_readable() -> void:
	var m := loaded()
	assert_eq(m.branch_of("height"), "structure", "structure")
	assert_eq(m.branch_of("motor"), "mechanical", "mechanical")
	assert_eq(m.name_of("shafts"), "Sunk Shafts", "the display name")
