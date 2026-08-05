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
	assert_eq(Array(m.ids()),
		["height", "shafts", "motor", "gearing", "cabin", "depth"],
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

func test_the_shaft_ceiling_walks_two_to_eight() -> void:
	# The node moves the CEILING, not the number of shafts a run opens with.
	# 2 -> 4 -> 6 -> 8, landing exactly on the hard cap.
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_eq(m.shaft_cap(), Meta.BASE_SHAFT_CAP, "run one plays under the base cap")
	for i in range(3):
		assert_true(m.buy("shafts", u), "shafts level %d" % i)
		assert_eq(m.shaft_cap(), Meta.BASE_SHAFT_CAP + Meta.SHAFT_PER_LEVEL * (i + 1),
			"level %d" % (i + 1))
	assert_eq(m.shaft_cap(), Building.MAX_SHAFTS,
		"a maxed node reaches the hard cap exactly -- no unreachable shafts, and "
		+ "none advertised that Building cannot build")

func test_every_run_still_opens_with_one_shaft() -> void:
	# The whole point of the ceiling: shafts are re-earned with CASH every run.
	# If the tree also handed them over, the price would stop mattering as the
	# tree grew, which is what the node used to do.
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	for i in range(3):
		assert_true(m.buy("shafts", u), "shafts level %d" % i)
	assert_eq(m.starting_shafts(), Meta.BASE_STARTING_SHAFTS,
		"a maxed tree still starts you with one")

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
	assert_eq(m.level_of("shafts"), 64, "the level is real")
	assert_eq(m.shaft_cap(), Meta.MAX_SHAFT_CAP, "bounded by this release's ladder")

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
		var structural := id == "height" or id == "shafts" or id == "depth"
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

# --- what a run built against a Meta actually starts with --------------------

func test_the_base_shafts_agree_across_modules() -> void:
	# Meta cannot reference GameState (GameState reads Meta, never the
	# reverse), so the agreement needs pinning rather than deriving.
	assert_eq(Meta.BASE_STARTING_SHAFTS, GameState.BASE_SHAFTS, "one number, two files")

func test_a_fresh_run_caps_at_ten_floors() -> void:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1)
	assert_true(s.is_valid(), "valid")
	for i in range(20):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 10, "run one stops at the ladder's first rung")

func test_a_meta_with_height_raises_the_run_cap() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_true(m.buy("height", u), "L1")
	assert_true(m.buy("height", u), "L2")
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	for i in range(30):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 20, "the ladder's top rung")

func test_a_run_starts_with_one_shaft_and_the_ceiling_it_paid_for() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_true(m.buy("shafts", u), "shafts")
	assert_true(m.buy("motor", u), "motor L1")
	assert_true(m.buy("motor", u), "motor L2")
	var s := GameState.new(GameState.BASE_FLOORS, m.starting_shafts(), 1,
		"res://data/tenants.json", m)
	assert_eq(s.building.cars.size(), 1, "you still open with one shaft")
	# The ceiling is enforced on PURCHASE. Buy until the run refuses and count
	# what was actually built -- a getter would only restate the assignment.
	s.economy.cash = 1_000_000.0
	while not s.upgrades.is_maxed("shaft"):
		assert_true(s.buy("shaft"), "shaft %d" % s.building.cars.size())
	assert_eq(s.building.cars.size(), m.shaft_cap(),
		"the run may buy up to the ceiling the tree bought, and no further")
	assert_eq(m.shaft_cap(), Meta.BASE_SHAFT_CAP + Meta.SHAFT_PER_LEVEL,
		"which at one level is four")
	assert_eq(s.upgrades.level_of("speed"), 2, "and the granted motor level")
	assert_almost_eq(s.building.cars[0].floors_per_tick,
		s.upgrades.effect_value("speed", 2), 1e-9,
		"the cars are SYNCED, not merely counted")

func test_a_run_that_already_exceeds_the_ceiling_keeps_its_shafts() -> void:
	# THE LIVE-SAVE CASE. A building from before the ceiling existed can hold six
	# cars on a tree that pays for two. grant_level clamps the upgrade COUNTER to
	# the new budget, and the worry is that this reads as "you own one shaft" and
	# takes five away. It does not: the codec rebuilds the Building at its saved
	# size and the counter only prices what is still for sale.
	var m := loaded()
	var s := GameState.new(GameState.BASE_FLOORS, 6, 1, "res://data/tenants.json", m)
	assert_eq(s.building.cars.size(), 6, "the cars the save had are still there")
	assert_true(s.upgrades.is_maxed("shaft"), "and no more are for sale")
	s.economy.cash = 1_000_000.0
	assert_false(s.buy("shaft"), "the sim refuses, not merely the view")
	assert_eq(s.building.cars.size(), 6, "and nothing was taken away")

func test_init_never_resizes_the_building() -> void:
	# The saved size is the authority. Expanding here past saved_floors.size()
	# trips the codec's refusal, decode returns null, the boot path starts a
	# fresh game, and the autosave overwrites the only copy.
	var m := loaded()
	m.blueprints = 100
	assert_true(m.buy("shafts", upgrades()), "shafts L1")
	var s := GameState.new(8, 1, 1, "res://data/tenants.json", m)
	assert_eq(s.building.floor_count, 8, "floors as handed")
	assert_eq(s.building.cars.size(), 1, "shafts as handed, despite shafts L1")

func test_a_malformed_blueprint_catalog_is_fatal() -> void:
	# There is no "skip the tree and play anyway" fallback: Blueprints gate the
	# cap and the second run.
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json",
		null, "res://data/does_not_exist.json")
	assert_false(s.is_valid(), "fatal")
	assert_eq(s.invalid_what(), "blueprint catalog", "and it names itself")
	assert_eq(s.invalid_path(), "res://data/does_not_exist.json", "by path")

func test_an_injected_meta_whose_defs_failed_is_still_fatal() -> void:
	# The check is NOT conditional on p_meta. After the salvage rewiring no
	# production path constructs with a null Meta, so a `p_meta == null` guard
	# would put the only enforcement of the fatal-data rule on a branch nobody
	# takes.
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json",
		Meta.new())
	assert_false(s.is_valid(), "a bare Meta.new() has no defs")

func test_the_cap_budget_is_measured_against_the_base_size() -> void:
	# Against the CURRENT size it is a level budget measured against a floor
	# count -- correct only at level 0. A player who started at 6 with a cap of
	# 20 and bought 7 floors would reload permanently capped 7 floors below
	# what they paid for, with the ghost band silently no-opping.
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_true(m.buy("height", u), "L1")
	assert_true(m.buy("height", u), "L2")
	var s := GameState.new(13, 1, 1, "res://data/tenants.json", m)
	s.upgrades.restore_levels({"floor": 7})
	for i in range(20):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 20, "still reachable after a reload")

func test_the_run_keeps_the_paths_it_was_built_against() -> void:
	# Without them a demolish silently rebuilds against the shipped catalogs
	# and defeats every override.
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1)
	assert_eq(s.catalog_path(), "res://data/tenants.json", "catalog")
	assert_eq(s.blueprints_path(), "res://data/blueprints.json", "blueprints")

# --- the dev-unlock flag ----------------------------------------------------

func test_dev_unlocked_defaults_false_and_round_trips() -> void:
	var m := loaded()
	assert_false(m.dev_unlocked, "locked by default")
	m.dev_unlocked = true
	var clone := loaded()
	assert_true(clone.restore(m.to_dict()), "restores")
	assert_true(clone.dev_unlocked, "and the flag rode along")

func test_a_meta_with_no_dev_key_restores_false() -> void:
	# The pre-feature save. It has no `dev` key at all, and must not inherit a
	# stale value from whatever the Meta held before.
	var m := loaded()
	m.dev_unlocked = true
	assert_true(m.restore({"blueprints": 3}), "restores")
	assert_false(m.dev_unlocked, "absent key reads false, not stale-true")

func test_a_non_bool_dev_restores_false_without_throwing() -> void:
	# THE test for the guard. Rewriting meta.gd's check as
	# `not not d.get("dev")` or `bool(d.get("dev", false))` unlocks the panel
	# from a poisoned save -- a non-empty String booleanizes true -- and without
	# this test the whole suite still passes. Type first, then value.
	for bad in ["true", "abc", 1, 1.0, {}, [], null]:
		var m := loaded()
		assert_true(m.restore({"dev": bad}), "%s does not refuse" % [bad])
		assert_false(m.dev_unlocked, "%s must not unlock the panel" % [bad])


# --- the depth ceiling ------------------------------------------------------

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
	assert_lte(Meta.MAX_DEPTH_CAP, Building.MAX_DEPTH,
		"and the ladder never advertises what the engine cannot build")

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

func test_digging_yields_a_vacant_floor_with_grown_containers() -> void:
	var m := loaded()
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1,
		"res://data/tenants.json", m)
	s.economy.cash = 1_000_000.0
	assert_true(s.buy("dig"))
	assert_true(s.tenancy.is_vacant(-1), "excavation is not a lease")
	assert_eq(s.tenancy.floors(), s.building.total_floors(),
		"tenancy grew with the building")
	assert_eq(s.fitout.tier_at(-1), Fitout.BASE_TIER, "fitout too")

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
