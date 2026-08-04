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

# --- the tree, the derivations, and the serialization pair -------------------

func upgrades() -> Upgrades:
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	return u

func test_cost_follows_base_times_level_plus_one() -> void:
	var m := loaded()
	assert_eq(m.cost_of("height"), 6, "level 0")
	m.blueprints = 100
	assert_true(m.buy("height", upgrades()), "buy L1")
	assert_eq(m.cost_of("height"), 12, "level 1")

func test_a_purchase_at_exactly_the_cost_succeeds() -> void:
	# The < vs <= boundary.
	var m := loaded()
	m.blueprints = 6
	assert_true(m.buy("height", upgrades()), "exactly affordable")
	assert_eq(m.blueprints, 0, "and spends it all")

func test_a_purchase_one_short_is_refused() -> void:
	var m := loaded()
	m.blueprints = 5
	assert_false(m.buy("height", upgrades()), "refused")
	assert_eq(m.level_of("height"), 0, "and nothing changed")

func test_buying_past_max_level_is_refused() -> void:
	var m := loaded()
	m.blueprints = 1000
	var u := upgrades()
	assert_true(m.buy("height", u), "L1")
	assert_true(m.buy("height", u), "L2")
	assert_false(m.buy("height", u), "L3 does not exist")
	assert_eq(m.level_of("height"), 2, "and the level held")

func test_an_unknown_node_cannot_be_bought() -> void:
	var m := loaded()
	m.blueprints = 1000
	assert_false(m.buy("wizardry", upgrades()), "refused")
	assert_eq(m.blueprints, 1000, "and charged nothing")

func test_height_and_shafts_are_never_zero_delta() -> void:
	# They map to no upgrade, so there is nothing to compare. Getting this
	# wrong makes `height` permanently unbuyable -- the one node this whole
	# system exists for.
	var m := loaded()
	assert_false(m.is_zero_delta("height", upgrades()), "height")
	assert_false(m.is_zero_delta("shafts", upgrades()), "shafts")

func test_gearing_is_buyable_while_the_runs_doors_sit_at_the_plateau() -> void:
	# The node's zero-delta is evaluated at the META's level, never the run's.
	# Delegating to up.is_zero_delta("doors") would read the RUN's doors and
	# refuse gearing at L0 for any player whose run had reached the
	# DOOR_TICKS_MIN plateau -- precisely while they are shopping the panel
	# before a demolish, though the next run starts at doors <= 4.
	var u := upgrades()
	u.restore_levels({"doors": 10})
	assert_true(u.is_zero_delta("doors"), "the RUN's doors are maxed out")
	var m := loaded()
	assert_false(m.is_zero_delta("gearing", u), "gearing is still worth buying")

func test_the_ladder_walks_ten_to_twenty() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_eq(m.height_cap(), 10, "run one")
	m.buy("height", u)
	assert_eq(m.height_cap(), 15, "L1")
	m.buy("height", u)
	assert_eq(m.height_cap(), 20, "L2")

func test_shafts_walk_one_to_four() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_eq(m.starting_shafts(), Meta.BASE_STARTING_SHAFTS, "run one")
	for i in range(3):
		assert_true(m.buy("shafts", u), "shafts level %d" % i)
	assert_eq(m.starting_shafts(), 4, "three levels")

func test_the_height_clamp_is_not_vacuous() -> void:
	# Asserting height_cap() <= 20 against a 2-level ladder passes with the
	# clamp deleted. Load a defs file that could exceed it.
	var m := Meta.new()
	assert_true(m.load_defs(write_defs([ok_node({"max_level": 64})])), "loads")
	assert_true(m.restore({"spent": {"height": 64}}), "restores")
	assert_eq(m.level_of("height"), 64, "the level is real")
	assert_eq(m.height_cap(), Meta.MAX_HEIGHT_CAP, "and the cap still holds")

func test_the_shaft_clamp_is_not_vacuous() -> void:
	var m := Meta.new()
	assert_true(m.load_defs(write_defs([ok_node({"id": "shafts", "max_level": 64})])),
		"loads")
	assert_true(m.restore({"spent": {"shafts": 64}}), "restores")
	assert_eq(m.starting_shafts(), Building.MAX_SHAFTS, "bounded by the hard cap")

func test_starting_levels_map_node_ids_to_upgrade_ids() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_true(m.buy("motor", u), "motor")
	assert_true(m.buy("gearing", u), "gearing")
	assert_eq(m.starting_level("speed"), 1, "motor -> speed")
	assert_eq(m.starting_level("doors"), 1, "gearing -> doors")
	assert_eq(m.starting_level("capacity"), 0, "cabin unbought")
	assert_eq(m.starting_level("shaft"), 0, "structure maps to no upgrade")

func test_every_id_is_consumed_by_a_derivation_and_every_target_exists() -> void:
	# A typo makes a node silently do nothing forever -- the same class of bug
	# ElevatorCar.floors_per_tick == Upgrades.SPEED_BASE is pinned against.
	var m := loaded()
	var upgrade_ids := Array(upgrades().ids())
	for id in m.ids():
		var structural := id == "height" or id == "shafts"
		var mechanical := Meta.NODE_TO_UPGRADE.has(id)
		assert_true(structural or mechanical, "%s is read by some derivation" % id)
		if mechanical:
			assert_true(upgrade_ids.has(Meta.NODE_TO_UPGRADE[id]),
				"%s targets a real upgrade" % id)
	for node_id in Meta.NODE_TO_UPGRADE:
		assert_true(Array(m.ids()).has(node_id),
			"%s is switched on but not in the file" % node_id)

func test_to_dict_pins_its_key_names() -> void:
	# The dict key is `runs` while the field is `runs_completed`. A rename on
	# one side would silently zero the count on every load.
	var m := loaded()
	m.blueprints = 30
	m.runs_completed = 5
	assert_true(m.buy("height", upgrades()), "so `spent` is not vacuously empty")
	var d := m.to_dict()
	assert_true(d.has("blueprints") and d.has("runs") and d.has("spent"), "keys")
	assert_eq(d["runs"], 5, "runs, not runs_completed")
	assert_eq((d["spent"] as Dictionary)["height"], 1, "and spent carries the level")

func test_to_dict_never_aliases_the_live_tree() -> void:
	# The staged clone in Prestige.demolish is independent only if the pair
	# deep-copies at BOTH ends.
	var m := loaded()
	m.blueprints = 100
	m.buy("height", upgrades())
	var d := m.to_dict()
	(d["spent"] as Dictionary)["height"] = 99
	assert_eq(m.level_of("height"), 1, "the live tree is untouched")

func test_restore_is_a_deep_copy_too() -> void:
	var source := loaded()
	source.blueprints = 100
	source.buy("height", upgrades())
	var clone := loaded()
	assert_true(clone.restore(source.to_dict()), "restores")
	source.buy("height", upgrades())
	assert_eq(clone.level_of("height"), 1, "the clone did not follow")

func test_restore_into_an_unloaded_meta_is_refused() -> void:
	# Restoring with no defs would iterate an empty ids() and DROP every level.
	var m := Meta.new()
	assert_false(m.restore({"blueprints": 5}), "refused")

func test_a_malformed_meta_block_restores_an_empty_tree_without_throwing() -> void:
	for bad in [null, 5, "abc", [], {"spent": 7}]:
		var m := loaded()
		assert_true(m.restore(bad), "%s is an empty Meta, not a refusal" % [bad])
		assert_eq(m.blueprints, 0, "no blueprints")
		assert_eq(m.level_of("height"), 0, "no levels")

func test_hostile_levels_are_clamped_to_their_nodes_max() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"motor": 999, "cabin": 999, "height": 999}}),
		"restores")
	assert_eq(m.level_of("motor"), 4, "not a 10-floors-per-tick car")
	assert_eq(m.level_of("cabin"), 3, "not a 1,003-seat car")
	assert_eq(m.height_cap(), Meta.MAX_HEIGHT_CAP, "not a 40-floor cap")

func test_unknown_ids_in_spent_are_dropped() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"wizardry": 3}}), "restores")
	assert_eq(m.level_of("wizardry"), 0, "read by iterating OUR ids, never theirs")

func test_a_non_integral_or_wrongly_typed_blueprints_is_rejected_without_throwing() -> void:
	for bad in [3.7, "abc", {}, [], null]:
		var m := loaded()
		assert_true(m.restore({"blueprints": bad}), "no refusal")
		assert_eq(m.blueprints, 0, "%s falls back to zero" % [bad])

func test_a_huge_blueprints_clamps_rather_than_wrapping() -> void:
	var m := loaded()
	assert_true(m.restore({"blueprints": 9.3e18, "runs": 9.3e18}), "restores")
	assert_eq(m.blueprints, Meta.MAX_BLUEPRINTS, "clamped in float space")
	assert_eq(m.runs_completed, Meta.MAX_RUNS, "runs too -- it feeds the RNG seed")

func test_a_spent_value_that_is_a_container_is_rejected_without_throwing() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"height": {}}}), "no refusal")
	assert_eq(m.level_of("height"), 0, "int({}) is an error, so type comes first")

func test_a_negative_blueprints_clamps_to_zero() -> void:
	var m := loaded()
	assert_true(m.restore({"blueprints": -5, "spent": {"height": -3}}), "restores")
	assert_eq(m.blueprints, 0, "floored")
	assert_eq(m.level_of("height"), 0, "and so is the level")
