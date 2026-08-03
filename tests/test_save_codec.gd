extends GutTest

## What must survive quitting the app. Round trips are asserted against a state
## the player actually played into, not a fresh one, because every bug here is
## a field somebody forgot to carry.

func played_state() -> GameState:
	var gs := GameState.new(6, 1, 4242)
	gs.economy.accrue(50000.0)
	gs.buy("row")
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
	assert_eq(after.building.row_count, before.building.row_count, "floors")
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
	# The trap: replaying a "row" or "shaft" level as a PURCHASE would apply its
	# structural effect again, so a saved 7-floor building would load as 13.
	var before := played_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_eq(after.building.row_count, 7, "six plus the one that was bought")
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
	for key in ["seed", "ticks", "cash", "row_count", "cars"]:
		var data := SaveCodec.encode(GameState.new(6, 1, 1))
		data.erase(key)
		assert_null(SaveCodec.decode(data), "missing %s" % key)

func test_a_nonsense_row_count_is_refused() -> void:
	var data := SaveCodec.encode(GameState.new(6, 1, 1))
	data["row_count"] = 0
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

# --- v2: a kind and a class per row ------------------------------------------

## A version-1 dictionary: rows carry no kind or class, exactly what the old
## formatter wrote.
func _v1_save() -> Dictionary:
	var data := SaveCodec.encode(GameState.new(6, 1, 7))
	data["version"] = 1
	for r in data["rows"]:
		r.erase("kind")
		r.erase("class")
	return data

func test_a_vacant_row_round_trips_as_a_null_kind() -> void:
	# The state a newly purchased floor is in, so this is the common case.
	var gs := GameState.new(6, 1, 7)
	gs.economy.accrue(1e9)
	gs.buy("row")
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
	(data["rows"] as Array)[2]["vacant"] = true
	var back := SaveCodec.decode(data)
	assert_true(back.tenancy.is_vacant(2))
	assert_eq(back.tenancy.kind_at(2), "", "a vacant floor has no tenant")

func test_a_kind_the_restored_class_cannot_lease_falls_back() -> void:
	# Independent validation lets this through: a known id skips the
	# unknown-id fallback and the class clamp never looks at the kind.
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array)[3]["kind"] = "law_firm"
	(data["rows"] as Array)[3]["class"] = 1
	var back := SaveCodec.decode(data)
	assert_eq(back.tenancy.kind_at(3), "apartments",
		"falls back to the cheapest eligible kind")

func test_a_short_v2_rows_array_is_refused() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array).resize(3)
	assert_null(SaveCodec.decode(data))

func test_an_out_of_range_class_bounds_to_the_top_tier() -> void:
	var gs := GameState.new(6, 1, 7)
	var data := SaveCodec.encode(gs)
	(data["rows"] as Array)[1]["class"] = 99
	var back := SaveCodec.decode(data)
	assert_eq(back.fitout.tier_at(1), 3, "bounded, not prevented")
