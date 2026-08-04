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

# --- the fields Meta.restore() never sees -----------------------------------

func test_a_poisoned_lifetime_yields_nothing() -> void:
	var data := SaveCodec.encode(played_state())
	data["lifetime"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_eq(Prestige.yield_for(after.economy.lifetime_earnings), 0, "no mint")

func test_a_poisoned_combo_cannot_poison_lifetime_on_the_first_delivery() -> void:
	# The single most important test here. A `lifetime` check alone does not
	# close this: credit_delivery multiplies the field the conversion consumes
	# and then heals the combo to 10.0 on the very next line, erasing its own
	# evidence. yield_for(INF) is a billion Blueprints from one passenger.
	var data := SaveCodec.encode(played_state())
	data["combo"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_true(after.economy.combo <= Economy.COMBO_MAX, "clamped to the cap")
	after.economy.credit_delivery(3.0)
	assert_true(is_finite(after.economy.lifetime_earnings), "and lifetime survived it")

func test_a_nan_combo_is_replaced_rather_than_clamped() -> void:
	# clampf(NAN, 1, 10) returns NAN, so the clamp alone is not enough.
	var data := SaveCodec.encode(played_state())
	data["combo"] = NAN
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_true(is_finite(after.economy.combo), "finite")

func test_a_poisoned_cash_does_not_make_everything_free() -> void:
	var data := SaveCodec.encode(played_state())
	data["cash"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_true(is_finite(after.economy.cash), "finite")
	assert_false(after.economy.can_afford(1e308), "can_afford is not unconditional")

func test_a_negative_cash_clamps_to_zero() -> void:
	var data := SaveCodec.encode(played_state())
	data["cash"] = -1
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_eq(after.economy.cash, 0.0, "floored")

func test_a_string_where_a_number_belongs_falls_back_rather_than_coercing() -> void:
	# int("abc") == 0 and float("abc") == 0.0 with NO error, so a string is the
	# poison that proves the TYPE check fires rather than the finite/range check
	# behind it -- without one, every string silently coerces.
	#
	# For `cash` the fallback IS zero, because decode constructs a fresh state
	# and there is no prior value to keep. So the money is lost either way; what
	# the type check buys is that the loss is a decision rather than an accident,
	# and that the same rule protects `combo` and the per-car fields, where the
	# fallback is a real value and the coercion would be catastrophic.
	var data := SaveCodec.encode(played_state())
	data["cash"] = "abc"
	data["combo"] = "abc"
	(data["cars"] as Array)[0]["capacity"] = "abc"
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused -- refusing here would delete the building")
	assert_eq(after.economy.cash, 0.0, "cash has no prior value to fall back to")
	assert_eq(after.economy.combo, 1.0, "combo falls back to its neutral value")
	# Not to zero, and not to the restored LEVEL either: restore_levels runs no
	# effect by design (the saved car values are the authority), so the fallback
	# is the value the constructor gave the car. A seat is lost; a car frozen at
	# capacity 0 is not.
	assert_eq(after.building.cars[0].capacity, Upgrades.CAPACITY_BASE,
		"capacity falls back to the constructor's value, never to zero")

func test_a_capacity_of_a_billion_does_not_mint_blueprints() -> void:
	# 1e9 riders in one door cycle is ~$3.09e9, which is 5,559 BP -- 59x the
	# whole tree, permanently.
	var data := SaveCodec.encode(played_state())
	(data["cars"] as Array)[0]["capacity"] = 1000000000
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_true(after.building.cars[0].capacity <= Upgrades.CAPACITY_BASE + 8,
		"bounded by its own max_level")

func test_every_per_car_field_is_bounded() -> void:
	var data := SaveCodec.encode(played_state())
	var car: Dictionary = (data["cars"] as Array)[0]
	car["floors_per_tick"] = 1e400
	car["door_ticks"] = -50
	car["spring_multiplier"] = 1e400
	car["position_floor"] = 1e400
	car["target_floor"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	var c: ElevatorCar = after.building.cars[0]
	assert_true(is_finite(c.floors_per_tick) and c.floors_per_tick > 0.0, "speed")
	assert_true(c.door_ticks >= Upgrades.DOOR_TICKS_MIN, "doors")
	assert_true(c.spring_multiplier >= 1.0
		and c.spring_multiplier <= Upgrades.SPRING_BASE, "spring")
	assert_true(c.position_floor >= 0.0
		and c.position_floor <= float(after.building.floor_count - 1), "position")
	assert_true(c.target_floor >= 0
		and c.target_floor <= after.building.floor_count - 1, "target")

func test_a_levels_value_that_is_a_container_refuses_rather_than_half_restoring() -> void:
	# restore_levels is a VOID callee: aborting mid-loop leaves decode running
	# and returns a NON-NULL, half-restored state, with which levels survive
	# depending on dictionary iteration order. That is the real violation of
	# "never half-read into a state that looks fine and is not".
	var data := SaveCodec.encode(played_state())
	(data["levels"] as Dictionary)["speed"] = {}
	assert_null(SaveCodec.decode(data), "refused whole, never half-read")

func test_a_policy_element_that_is_not_a_preset_falls_back_to_manual() -> void:
	var data := SaveCodec.encode(played_state())
	(data["policies"] as Array)[0] = 9999
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_eq(after.auto.preset_of(0), DispatchPolicy.Preset.MANUAL, "fell back")

func test_a_non_boolean_vacant_does_not_throw() -> void:
	# bool() has NO Variant constructor for String, Dictionary or Array, so a
	# bare bool(r.get("vacant")) aborts decode's own frame on {"vacant": "x"} --
	# a safe null, but an engine error, and GUT fails the sweep on it.
	var data := SaveCodec.encode(played_state())
	(data["floors"] as Array)[0]["vacant"] = "x"
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_false(after.tenancy.is_vacant(0), "and reads as tenanted")

func test_a_poisoned_satisfaction_is_bounded() -> void:
	var data := SaveCodec.encode(played_state())
	(data["floors"] as Array)[0]["satisfaction"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_true(after.tenancy.satisfaction_at(0) <= 1.0, "bounded")

func test_a_poisoned_seed_still_produces_a_usable_run() -> void:
	var data := SaveCodec.encode(played_state())
	data["seed"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	after.tick(10)
	assert_true(true, "and ticking it does not throw")

# --- the generative sweep ---------------------------------------------------

## Every leaf path in a nested Dictionary/Array, as an array of keys/indices.
func leaf_paths(value: Variant, prefix: Array) -> Array:
	var out := []
	match typeof(value):
		TYPE_DICTIONARY:
			for k in (value as Dictionary):
				out.append_array(leaf_paths((value as Dictionary)[k], prefix + [k]))
		TYPE_ARRAY:
			for i in range((value as Array).size()):
				out.append_array(leaf_paths((value as Array)[i], prefix + [i]))
		_:
			if not prefix.is_empty():
				out.append(prefix)
	return out

func poke(container: Variant, path: Array, value: Variant) -> void:
	var node: Variant = container
	for i in range(path.size() - 1):
		node = node[path[i]]
	node[path[path.size() - 1]] = value

## Whatever decode hands back must be a state the sim can actually run. This is
## the general invariant, which does not go stale when a key is added -- unlike
## a hand-written table of expected outcomes, and this spec adds a key.
func assert_sane(s: GameState, why: String) -> void:
	assert_true(s.building.floor_count >= 1
		and s.building.floor_count <= Building.MAX_FLOORS, "%s: floor_count" % why)
	assert_true(is_finite(s.economy.cash) and s.economy.cash >= 0.0, "%s: cash" % why)
	assert_true(is_finite(s.economy.lifetime_earnings)
		and s.economy.lifetime_earnings >= 0.0, "%s: lifetime" % why)
	assert_true(is_finite(s.economy.combo) and s.economy.combo >= 1.0
		and s.economy.combo <= Economy.COMBO_MAX, "%s: combo" % why)
	assert_true(s.meta.blueprints >= 0
		and s.meta.blueprints <= Meta.MAX_BLUEPRINTS, "%s: blueprints" % why)
	for c in s.building.cars:
		assert_true(is_finite(c.floors_per_tick) and c.floors_per_tick > 0.0,
			"%s: speed" % why)
		assert_true(c.capacity >= 1 and c.capacity <= Upgrades.CAPACITY_BASE + 8,
			"%s: capacity" % why)
		assert_true(c.position_floor >= 0.0
			and c.position_floor <= float(s.building.floor_count - 1),
			"%s: position" % why)

func test_a_generative_poison_sweep_never_throws() -> void:
	# Walk encode()'s output RECURSIVELY and poison every leaf in turn. A
	# hand-written matrix goes stale the moment a key is added, and a
	# top-level-only sweep goes stale the moment a value nests -- v4 does both.
	#
	# GUT fails a test on unhandled engine errors, so "never throws" is an
	# assertion this harness genuinely makes rather than a wish.
	var poisons: Array = [{}, [], null, "abc", 1e400, -1, NAN]
	var checked := 0
	for path in leaf_paths(SaveCodec.encode(played_state()), []):
		for poison in poisons:
			var data := SaveCodec.encode(played_state())
			poke(data, path, poison)
			var after := SaveCodec.decode(data)
			checked += 1
			if after != null:
				assert_sane(after, "%s = %s" % [path, poison])
	assert_gt(checked, 300, "the sweep actually walked the payload")

func test_the_structural_fields_refuse_a_wrong_type() -> void:
	# The other half of the oracle: these are not clamped, they are refused,
	# because a container that is not a container has no salvageable reading.
	var wrong := {
		"version": [{}, [], "abc", null],
		"floor_count": [{}, [], "abc", null],
		"cars": [{}, "abc", null, 5],
		"floors": [{}, "abc", null, 5],
		"policies": [{}, "abc", null, 5],
		"levels": [[], "abc", null, 5],
	}
	for key in wrong:
		for poison in wrong[key]:
			var data := SaveCodec.encode(played_state())
			data[key] = poison
			assert_null(SaveCodec.decode(data), "%s = %s is refused" % [key, poison])

func test_poisoning_the_meta_never_costs_the_building() -> void:
	# Losing a tech tree beats losing a building, and this is the sweep's
	# version of that rule.
	for path in leaf_paths(SaveCodec.encode(played_state()), []):
		if str(path[0]) != "meta":
			continue
		for poison in [{}, [], null, "abc", 1e400, -1, NAN]:
			var data := SaveCodec.encode(played_state())
			poke(data, path, poison)
			var after := SaveCodec.decode(data)
			assert_not_null(after, "%s = %s must not refuse" % [path, poison])
			if after != null:
				assert_eq(after.building.floor_count, 7,
					"%s = %s keeps the building" % [path, poison])

# --- salvage: a refused RUN must not take the tree down ----------------------

func test_the_meta_survives_a_refused_run() -> void:
	# decode still returns NULL here -- five existing assert_null tests depend
	# on that contract, and both docstrings say "null always means start a new
	# game". Salvage is a separate, explicitly named function.
	var s := meta_state()
	var data := SaveCodec.encode(s)
	(data["floors"] as Array).clear()          # the short-floors refusal
	assert_null(SaveCodec.decode(data), "the run is refused")
	var salvaged := SaveCodec.salvage_meta(data)
	assert_not_null(salvaged, "the tree is not")
	assert_eq(salvaged.blueprints, 14, "blueprints")
	assert_eq(salvaged.level_of("height"), 1, "spent")

func test_salvage_never_grants() -> void:
	# legacy_meta derives free height levels from a floor_count the refusal has
	# just declared untrustworthy: a hand-written 20-floor v3 save with an empty
	# floors array would otherwise mint the entire cap ladder from a file that
	# does not load.
	var salvaged := SaveCodec.salvage_meta(
		{"version": 3, "floor_count": 20, "floors": []})
	assert_not_null(salvaged, "salvages")
	assert_eq(salvaged.level_of("height"), 0, "an EMPTY meta, not two free levels")

func test_salvage_reads_the_unmigrated_dictionary_without_throwing() -> void:
	# It must not migrate: _migrate_to_v3's first statement is
	# int(data.get("version", -1)), the exact abort the preflight guards decode
	# against -- and salvage runs under a separate call the preflight never
	# covers. Migration touches only V3_KEYS, V3_CAR_KEYS and `levels`, and
	# never the "meta" key, so there is nothing to gain by it.
	var salvaged := SaveCodec.salvage_meta({"version": {}, "cars": null,
		"meta": {"blueprints": 5}})
	assert_not_null(salvaged, "no throw, no null")
	assert_eq(salvaged.blueprints, 5, "and the meta was still read")

func test_salvage_returns_null_when_the_shipped_catalog_is_broken() -> void:
	assert_null(SaveCodec.salvage_meta({}, "res://data/does_not_exist.json"), "fatal")

func test_salvage_of_a_save_with_no_meta_is_an_empty_usable_meta() -> void:
	var salvaged := SaveCodec.salvage_meta({})
	assert_not_null(salvaged, "not null")
	assert_true(salvaged.is_usable(), "defs loaded, so a run can be built on it")
	assert_eq(salvaged.blueprints, 0, "and it grants nothing")
