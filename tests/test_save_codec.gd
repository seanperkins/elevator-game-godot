extends GutTest

## What must survive quitting the app. Round trips are asserted against a state
## the player actually played into, not a fresh one, because every bug here is
## a field somebody forgot to carry.

func played_state() -> GameState:
	var gs := GameState.new(6, 1, 4242)
	gs.economy.accrue(50000.0)
	gs.buy("floor")
	gs.buy("shaft")
	gs.buy("doors")
	gs.buy("capacity")
	gs.buy("auto")
	gs.buy("hall_buttons")
	gs.buy("car_buttons")
	gs.set_policy(0, DispatchPolicy.Preset.ANSWER_CALLS)
	gs.tick(600)
	return gs

func test_a_fresh_save_round_trips() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_not_null(after, "a save we just wrote must load")

func test_the_building_you_built_survives() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.building.floor_count, before.building.floor_count, "floors")
	assert_eq(after.building.cars.size(), before.building.cars.size(), "shafts")

func test_the_money_survives() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_almost_eq(after.economy.cash, before.economy.cash, 1e-6)
	assert_almost_eq(after.economy.lifetime_earnings,
		before.economy.lifetime_earnings, 1e-6, "prestige is computed from this")
	assert_eq(after.economy.riders_served, before.economy.riders_served)

func test_the_upgrades_survive() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	for id in before.upgrades.ids():
		assert_eq(after.upgrades.level_of(id), before.upgrades.level_of(id), id)

func test_restoring_levels_does_not_build_the_building_twice() -> void:
	# The trap: replaying a "floor" or "shaft" level as a PURCHASE would apply its
	# structural effect again, so a saved 7-floor building would load as 13.
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.building.floor_count, 7, "six plus the one that was bought")
	assert_eq(after.building.cars.size(), 2)

func test_the_cars_keep_what_the_upgrades_gave_them() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	for i in range(before.building.cars.size()):
		assert_eq(after.building.cars[i].door_ticks,
			before.building.cars[i].door_ticks, "car %d doors" % i)
		assert_eq(after.building.cars[i].capacity,
			before.building.cars[i].capacity, "car %d capacity" % i)

func test_tenant_satisfaction_survives() -> void:
	# Rent is scaled by it, so losing it would silently hand back income the
	# player had already lost.
	var before := played_state()
	before.tenancy.note_expiry(2)
	before.tenancy.note_expiry(2)
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_almost_eq(after.tenancy.satisfaction_at(2),
		before.tenancy.satisfaction_at(2), 1e-6)

func test_a_vacancy_cannot_be_reloaded_away() -> void:
	# Otherwise quitting is a free re-lease, and the whole cost is optional.
	var before := played_state()
	while before.tenancy.satisfaction_at(1) > Tenancy.MOVE_OUT_THRESHOLD:
		before.tenancy.note_expiry(1)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		before.tenancy.accrue_for_tick()
	assert_true(before.tenancy.is_vacant(1), "vacated")
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_true(after.tenancy.is_vacant(1), "still vacant after a reload")

func test_the_dispatch_policy_survives() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.auto.preset_of(0), before.auto.preset_of(0))
	assert_true(after.auto.is_enabled(0))

func test_a_save_cannot_grant_a_policy_the_hardware_does_not_support() -> void:
	# Policies are restored through set_policy, so an edited save cannot install
	# call-driven dispatch on a building with no call buttons.
	var data := SaveCodec.encode(GameState.new(6, 1, 1))
	data["policies"] = [DispatchPolicy.Preset.ANSWER_CALLS]
	var after := SaveCodec.decode(data)
	assert_false(after.auto.is_enabled(0), "refused: no buttons, no licence")

func test_the_traffic_seed_survives() -> void:
	# Traffic is deterministic from the seed; forgetting it makes the reloaded
	# building quietly a different one.
	var before := GameState.new(6, 1, 987654)
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.spawner.seed_value(), 987654)

func test_the_clock_survives_so_the_day_does_not_restart() -> void:
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.clock.ticks_executed, before.clock.ticks_executed)
	assert_eq(after.clock.sim_minute(), before.clock.sim_minute(),
		"reloading must not put the building back to the morning rush")

# --- refusing what it cannot read ------------------------------------------

func test_an_empty_save_is_refused() -> void:
	assert_null(SaveCodec.decode({}), "start fresh rather than half-load")

func test_a_save_from_another_version_is_refused() -> void:
	var data := SaveCodec.encode(GameState.new(6, 1, 1))
	data["version"] = SaveCodec.VERSION + 1
	assert_null(SaveCodec.decode(data))

func test_a_save_missing_a_required_field_is_refused() -> void:
	for key in ["seed", "ticks", "cash", "floor_count", "cars"]:
		var data := SaveCodec.encode(GameState.new(6, 1, 1))
		data.erase(key)
		assert_null(SaveCodec.decode(data), "missing %s" % key)

func test_a_nonsense_row_count_is_refused() -> void:
	var data := SaveCodec.encode(GameState.new(6, 1, 1))
	data["floor_count"] = 0
	assert_null(SaveCodec.decode(data))

func test_a_corrupt_cars_field_is_refused() -> void:
	var data := SaveCodec.encode(GameState.new(6, 1, 1))
	data["cars"] = "not an array"
	assert_null(SaveCodec.decode(data))

# --- what it deliberately does NOT do --------------------------------------

func test_loading_does_not_invent_offline_earnings() -> void:
	# Scope line. Offline accrual is the design's least settled area (§9.1) and
	# is not modelled: a reload resumes exactly where it stopped. If this ever
	# starts failing, somebody has added catch-up without designing it.
	var before := played_state()
	var data := SaveCodec.encode(before)
	var after := SaveCodec.decode(data)
	assert_almost_eq(after.economy.cash, before.economy.cash, 1e-6,
		"no time passed, so no money appeared")
	assert_eq(after.clock.ticks_executed, before.clock.ticks_executed,
		"and no ticks were run to catch up")

# --- v2: a kind and a class per floor ------------------------------------------

## A version-1 dictionary: floors carry no kind or class, exactly what the old
## formatter wrote.
func _v1_save() -> Dictionary:
	var data := SaveCodec.encode(GameState.new(6, 1, 7))
	data["version"] = 1
	for r in data["floors"]:
		r.erase("kind")
		r.erase("class")
	return data

func test_a_vacant_row_round_trips_as_a_null_kind() -> void:
	# The state a newly purchased floor is in, so this is the common case.
	var gs := GameState.new(6, 1, 7)
	gs.economy.accrue(1e9)
	gs.buy("floor")
	var back := SaveCodec.decode(SaveCodec.encode(gs))
	assert_not_null(back)
	assert_true(back.tenancy.is_vacant(6))
	assert_eq(back.tenancy.kind_at(6), "")

func test_v2_round_trips_kind_and_class() -> void:
	var gs := GameState.new(6, 1, 7)
	gs.economy.accrue(1e6)
	gs.upgrade_class(2)
	var back := SaveCodec.decode(SaveCodec.encode(gs))
	assert_eq(back.fitout.tier_at(2), 2)
	assert_eq(back.tenancy.kind_at(0), "shops")

func test_a_v1_save_migrates() -> void:
	var data := _v1_save()
	var back := SaveCodec.decode(data)
	assert_not_null(back)
	assert_eq(back.fitout.tier_at(0), 1)
	assert_eq(back.tenancy.kind_at(0), "apartments")

func test_a_vacant_v1_row_migrates_with_no_kind() -> void:
	var data := _v1_save()
	(data["floors"] as Array)[2]["vacant"] = true
	var back := SaveCodec.decode(data)
	assert_true(back.tenancy.is_vacant(2))
	assert_eq(back.tenancy.kind_at(2), "", "a vacant floor has no tenant")

func test_a_kind_the_restored_class_cannot_lease_falls_back() -> void:
	# Independent validation lets this through: a known id skips the
	# unknown-id fallback and the class clamp never looks at the kind.
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["floors"] as Array)[3]["kind"] = "law_firm"
	(data["floors"] as Array)[3]["class"] = 1
	var back := SaveCodec.decode(data)
	assert_eq(back.tenancy.kind_at(3), "apartments",
		"falls back to the cheapest eligible kind")

func test_a_short_v2_rows_array_is_refused() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["floors"] as Array).resize(3)
	assert_null(SaveCodec.decode(data))

func test_an_out_of_range_class_bounds_to_the_top_tier() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["floors"] as Array)[1]["class"] = 99
	var back := SaveCodec.decode(data)
	assert_eq(back.fitout.tier_at(1), 3, "bounded, not prevented")

# --- v3: "row" became "floor" -----------------------------------------------

## The fixture is a REAL v2 save, pulled off the device before the rename. A
## hand-written one would only prove the migration matches my idea of v2.
func _real_v2_save() -> Dictionary:
	return {
		"version": 2, "seed": 20260802, "ticks": 29838,
		"cash": 51.73, "lifetime": 355.73, "combo": 1.16, "streak": 8,
		"riders_served": 46, "policies": [0],
		"row_count": 7,
		"cars": [{
			"capacity": 4, "door_ticks": 20, "position_row": 0.0,
			"rows_per_tick": 0.06, "spring_multiplier": 1.0, "target_row": 0,
		}],
		"levels": {
			"auto": 0, "capacity": 0, "car_buttons": 0, "doors": 0,
			"hall_buttons": 0, "load_sensor": 0, "lobby_parking": 0,
			"row": 1, "shaft": 0, "speed": 2, "spring": 0,
		},
		"rows": [
			{"class": 1, "kind": "apartments", "move_out_left": 0,
			 "satisfaction": 0.99, "vacant": false},
		],
	}

func test_a_v2_save_still_loads_after_the_floor_rename() -> void:
	var data := _real_v2_save()
	(data["rows"] as Array).resize(7)
	for i in range(1, 7):
		data["rows"][i] = {"class": 1, "kind": "apartments",
			"move_out_left": 0, "satisfaction": 0.9, "vacant": false}
	var back := SaveCodec.decode(data)
	assert_not_null(back, "a v2 save must survive the rename, not reset the run")
	assert_eq(back.building.floor_count, 7, "row_count became floor_count")
	assert_eq(back.economy.riders_served, 46)
	assert_almost_eq(back.building.cars[0].floors_per_tick, 0.06, 1e-9,
		"rows_per_tick became floors_per_tick")

func test_the_v2_row_upgrade_level_becomes_the_floor_level() -> void:
	var data := _real_v2_save()
	(data["rows"] as Array).resize(7)
	for i in range(1, 7):
		data["rows"][i] = {"class": 1, "kind": "apartments",
			"move_out_left": 0, "satisfaction": 0.9, "vacant": false}
	var back := SaveCodec.decode(data)
	assert_eq(back.upgrades.level_of("floor"), 1,
		"levels.row carried across to levels.floor")
	assert_eq(back.upgrades.level_of("speed"), 2, "untouched ids still load")

func test_migrating_does_not_mutate_the_callers_dictionary() -> void:
	# decode() takes p_data and duplicates; a caller that reloads twice must not
	# find its own dictionary rewritten under it.
	var data := _real_v2_save()
	(data["rows"] as Array).resize(7)
	for i in range(1, 7):
		data["rows"][i] = {"class": 1, "kind": "apartments",
			"move_out_left": 0, "satisfaction": 0.9, "vacant": false}
	SaveCodec.decode(data)
	assert_true(data.has("row_count"), "the original still spells it row_count")
	assert_false(data.has("floor_count"))

# --- v4: the tech tree rides in the same file as the run --------------------

## A state whose Meta carries a balance, a run count AND a spent level, since
## those are three independent things the codec can drop separately.
##
## 20 - cost_of("height") = 14 is the balance the tests below assert: buy()
## SPENDS, so seeding a balance and then buying leaves less than was seeded.
func meta_state() -> GameState:
	var m := Meta.new()
	assert_true(m.load_defs("res://data/blueprints.json"), "defs")
	m.blueprints = 20
	m.runs_completed = 3
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	assert_true(m.buy("height", s.upgrades), "a node the save must carry")
	assert_eq(m.blueprints, 14, "the fixture's balance, after the purchase")
	return s

func test_a_populated_meta_round_trips_in_memory() -> void:
	# The test that catches a TYPE_FLOAT-only rule rejecting the codec's own
	# GDScript ints: encode() returns a live Dictionary and the whole suite
	# round-trips with no JSON.stringify between.
	var before := meta_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_not_null(after, "decodes")
	assert_eq(after.meta.blueprints, 14, "blueprints")
	assert_eq(after.meta.runs_completed, 3, "runs")
	assert_eq(after.meta.level_of("height"), 1, "spent")

func test_a_populated_meta_survives_real_json() -> void:
	var before := meta_state()
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(SaveCodec.encode(before))), OK, "parses")
	var after := SaveCodec.decode(json.data as Dictionary)
	assert_not_null(after, "decodes")
	assert_eq(after.meta.blueprints, 14, "every number arrives as TYPE_FLOAT here")
	assert_eq(after.meta.level_of("height"), 1, "spent")

func test_the_cap_survives_a_reload() -> void:
	# Every other codec test operates on a fresh or legacy state, which is
	# exactly where the broken cap arithmetic happened to be right.
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	m.blueprints = 100
	# BEFORE the run is constructed: the cap is applied in _init, so a node
	# bought mid-run does nothing until the next rebuild -- which is the
	# documented behaviour, not an accident to work around.
	var scratch := Upgrades.new()
	scratch.load_defs("res://data/upgrades.json")
	assert_true(m.buy("height", scratch), "L1")
	assert_true(m.buy("height", scratch), "L2")
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	for i in range(7):
		s.economy.cash = 1_000_000.0
		assert_true(s.buy("floor"), "floor %d" % i)
	var after := SaveCodec.decode(SaveCodec.encode(s))
	assert_not_null(after, "decodes")
	for i in range(20):
		after.economy.cash = 1_000_000.0
		after.buy("floor")
	assert_eq(after.building.floor_count, 20, "twenty is still reachable")

func test_a_save_is_not_refused_because_the_meta_grants_more_than_it_holds() -> void:
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	m.blueprints = 100
	var s := GameState.new(8, 1, 1, "res://data/tenants.json", m)
	assert_true(m.buy("shafts", s.upgrades), "shafts mid-run")
	var after := SaveCodec.decode(SaveCodec.encode(s))
	assert_not_null(after, "not refused")
	assert_eq(after.building.floor_count, 8, "at the size it was saved at")
	assert_eq(after.building.cars.size(), 1, "and the shafts it was saved with")

func test_a_v4_save_with_the_meta_erased_is_not_grandfathered() -> void:
	# Keying on a missing key rather than on the version would hand a truncated
	# or tampered v4 file the whole cap ladder, permanently.
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	var s := GameState.new(20, 1, 1, "res://data/tenants.json", m)
	var data := SaveCodec.encode(s)
	data.erase("meta")
	var after := SaveCodec.decode(data)
	assert_not_null(after, "still loads")
	assert_eq(after.meta.level_of("height"), 0, "and grants nothing")

func test_a_malformed_v4_meta_yields_an_empty_meta_rather_than_refusing() -> void:
	# In this codebase "refuse" means "delete": decode returns null, the boot
	# path starts a fresh game, and the autosave overwrites the only copy
	# within ten seconds. Losing a tech tree beats losing a building. The
	# INVERSE of this test is what a future reviewer will try to "fix".
	var s := meta_state()
	var data := SaveCodec.encode(s)
	data["meta"] = "not a dictionary"
	var after := SaveCodec.decode(data)
	assert_not_null(after, "the building survives")
	assert_eq(after.building.floor_count, GameState.BASE_FLOORS, "intact")
	assert_eq(after.meta.blueprints, 0, "the tree does not")

func test_a_legacy_save_is_granted_the_height_its_building_implies() -> void:
	for pair in [[6, 0, 10], [11, 1, 15], [14, 1, 15], [20, 2, 20]]:
		var m := Meta.new()
		m.load_defs("res://data/blueprints.json")
		var s := GameState.new(pair[0], 1, 1, "res://data/tenants.json", m)
		var data := SaveCodec.encode(s)
		data["version"] = 3
		data.erase("meta")
		var after := SaveCodec.decode(data)
		assert_not_null(after, "%d floors decodes" % pair[0])
		assert_eq(after.meta.level_of("height"), pair[1], "%d floors -> height" % pair[0])
		assert_eq(after.meta.height_cap(), pair[2], "%d floors -> cap" % pair[0])
		assert_eq(after.building.floor_count, pair[0], "and loses no floors")
		assert_eq(after.meta.blueprints, 0, "granted, never charged")

func test_a_malformed_blueprint_catalog_refuses_the_decode() -> void:
	# Malformed SHIPPED data still refuses. The asymmetry is between data the
	# player cannot have damaged and a file they can.
	var s := meta_state()
	assert_null(SaveCodec.decode(SaveCodec.encode(s), "res://data/tenants.json",
		"res://data/does_not_exist.json"), "fatal")

func test_decode_refuses_an_invalid_state_rather_than_handing_it_back() -> void:
	# game_state.gd already CLAIMS this; it has been aspirational until now.
	var s := meta_state()
	assert_null(SaveCodec.decode(SaveCodec.encode(s),
		"res://data/does_not_exist.json"), "null, not a poisoned state")

func test_the_preflight_refuses_shapes_migration_would_abort_on() -> void:
	# Each of these aborts inside _migrate_to_v3 today, BEFORE any check runs.
	# GUT fails a test on unhandled engine errors, so "without throwing" is a
	# real and observable assertion rather than a wish.
	for poison in [{"version": {}}, {"cars": null}, {"levels": []},
			{"floor_count": {}}]:
		var data := SaveCodec.encode(GameState.new(6, 1, 1))
		for key in poison:
			data[key] = poison[key]
		assert_null(SaveCodec.decode(data), "%s is refused" % [poison])

func test_blueprints_survive_the_demolish_write() -> void:
	# The demolish and the discarded building arrive in ONE payload. A crash
	# between two writes would either duplicate the yield or destroy it.
	var s := meta_state()
	s.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	var next := Prestige.demolish(s)
	assert_not_null(next, "demolished")
	var after := SaveCodec.decode(SaveCodec.encode(next))
	assert_not_null(after, "decodes")
	assert_eq(after.meta.blueprints, 18, "14 banked plus 4 earned")
	assert_eq(after.meta.runs_completed, 4, "the run was counted")
	assert_eq(after.building.floor_count, GameState.BASE_FLOORS,
		"and the smaller building came in the same payload")

func test_the_real_device_fixture_is_grandfathered_and_charged_nothing() -> void:
	# _real_v2_save() is a REAL v2 save pulled off the device before the
	# rename -- the only input in this file nobody wrote. Padded exactly as the
	# tests beside it already pad it.
	var data := _real_v2_save()
	(data["rows"] as Array).resize(7)
	for i in range(1, 7):
		data["rows"][i] = {"class": 1, "kind": "apartments",
			"move_out_left": 0, "satisfaction": 0.9, "vacant": false}
	var after := SaveCodec.decode(data)
	assert_not_null(after, "a v2 save still loads under v4")
	assert_eq(after.building.floor_count, 7, "and loses no floors")
	assert_eq(after.meta.blueprints, 0, "granted, never charged")
	assert_eq(after.meta.level_of("height"), 0, "seven floors implies no height")
	assert_eq(after.meta.height_cap(), 10, "so it gets the base cap")
