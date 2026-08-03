extends GutTest

var up: Upgrades
var econ: Economy
var b: Building

func before_each() -> void:
	up = Upgrades.new()
	assert_true(up.load_defs("res://data/upgrades.json"))
	econ = Economy.new()
	b = Building.new(6, 1)

func test_definitions_load() -> void:
	assert_gt(up.ids().size(), 0)
	assert_eq(up.name_of("doors"), "Faster Doors")

func test_levels_start_at_zero() -> void:
	assert_eq(up.level_of("doors"), 0)

func test_call_direction_is_a_one_shot_that_installs() -> void:
	assert_eq(up.level_of("call_direction"), 0, "not fitted on a fresh building")
	assert_false(up.is_installed("call_direction"))
	econ.accrue(1000.0)
	assert_true(up.purchase("call_direction", econ, b), "bought at $50")
	assert_true(up.is_installed("call_direction"))

func test_call_direction_cannot_be_bought_twice() -> void:
	econ.accrue(1000.0)
	assert_true(up.purchase("call_direction", econ, b))
	assert_false(up.purchase("call_direction", econ, b),
		"max_level 1 stops a second purchase")

func test_cost_grows_with_level() -> void:
	var first := up.cost_of("doors")
	econ.accrue(1e9)
	up.purchase("doors", econ, b)
	assert_gt(up.cost_of("doors"), first)

func test_purchase_fails_without_cash() -> void:
	assert_false(up.purchase("doors", econ, b))
	assert_eq(up.level_of("doors"), 0, "a failed purchase must not level up")

func test_purchase_debits_exactly_the_cost() -> void:
	var cost := up.cost_of("doors")
	econ.accrue(cost)
	assert_true(up.purchase("doors", econ, b))
	assert_almost_eq(econ.cash, 0.0, 1e-6)

func test_doors_upgrade_reduces_dwell() -> void:
	var before := b.cars[0].door_ticks
	econ.accrue(1e9)
	up.purchase("doors", econ, b)
	assert_lt(b.cars[0].door_ticks, before)

func test_door_ticks_never_reach_zero() -> void:
	econ.accrue(1e12)
	for i in range(50):
		up.purchase("doors", econ, b)
	assert_gt(b.cars[0].door_ticks, 0, "doors must always take some time")

func test_speed_upgrade_increases_travel_rate() -> void:
	var before := b.cars[0].floors_per_tick
	econ.accrue(1e9)
	up.purchase("speed", econ, b)
	assert_gt(b.cars[0].floors_per_tick, before)

func test_capacity_upgrade_adds_seats() -> void:
	var before := b.cars[0].capacity
	econ.accrue(1e9)
	up.purchase("capacity", econ, b)
	assert_eq(b.cars[0].capacity, before + 1)

func test_shaft_upgrade_adds_a_column() -> void:
	econ.accrue(1e9)
	up.purchase("shaft", econ, b)
	assert_eq(b.cars.size(), 2)

func test_shaft_purchases_stop_at_the_board_cap() -> void:
	econ.accrue(1e12)
	for i in range(20):
		up.purchase("shaft", econ, b)
	assert_eq(b.cars.size(), Building.MAX_SHAFTS, "8 columns is a board constant")
	assert_true(up.is_maxed("shaft"))

func test_row_upgrade_adds_a_row() -> void:
	econ.accrue(1e9)
	up.purchase("floor", econ, b)
	assert_eq(b.floor_count, 7)

func test_row_purchases_stop_at_the_purchasable_cap() -> void:
	# The PURCHASABLE ceiling (floor.max_level) and the STRUCTURAL one
	# (Building.MAX_FLOORS) are deliberately different numbers -- see the
	# building-cost-curve spec. A run tops out at 20 floors, while the board can
	# still hold 40 and the spawner's saturation guard is sized against that 40.
	# This used to assert the two were equal, which is the assumption the spec
	# changes; what still has to hold is that purchases never exceed the board.
	econ.accrue(1e15)
	for i in range(60):
		up.purchase("floor", econ, b)
	assert_true(up.is_maxed("floor"), "purchases stop at floor.max_level")
	assert_eq(b.floor_count, 20, "which tops the building at 20 floors")
	assert_lt(b.floor_count, Building.MAX_FLOORS, "and never past the board cap")

func test_a_maxed_upgrade_cannot_be_bought() -> void:
	econ.accrue(1e15)
	for i in range(60):
		up.purchase("floor", econ, b)
	var cash_before := econ.cash
	assert_false(up.purchase("floor", econ, b))
	assert_almost_eq(econ.cash, cash_before, 1e-6, "and must not charge")

func test_unknown_id_is_refused() -> void:
	econ.accrue(1e9)
	assert_false(up.purchase("nonexistent", econ, b))

func test_new_shafts_inherit_current_upgrade_levels() -> void:
	econ.accrue(1e9)
	up.purchase("speed", econ, b)
	up.purchase("shaft", econ, b)
	assert_almost_eq(b.cars[1].floors_per_tick, b.cars[0].floors_per_tick, 1e-9,
		"a newly bought car must not be slower than the one you have")

func test_effect_value_matches_what_the_car_gets() -> void:
	econ.accrue(1e9)
	up.purchase("doors", econ, b)
	assert_almost_eq(up.effect_value("doors", up.level_of("doors")),
		float(b.cars[0].door_ticks), 1e-9,
		"the query and the car must read one definition")

func test_effect_value_honours_the_door_floor() -> void:
	# The clamp is why the view may not duplicate the formula: without it the
	# annotation would read "doors 4 -> 2 ticks", a fabricated number.
	assert_almost_eq(up.effect_value("doors", 8), 4.0, 1e-9)
	assert_almost_eq(up.effect_value("doors", 12), 4.0, 1e-9)

func test_zero_delta_is_detected_at_the_door_floor() -> void:
	econ.accrue(1e12)
	for i in range(7):
		assert_true(up.purchase("doors", econ, b), "level %d" % i)
	assert_eq(up.level_of("doors"), 7)
	assert_false(up.is_zero_delta("doors"), "7 -> 8 still changes the value")
	assert_true(up.purchase("doors", econ, b))
	assert_eq(up.level_of("doors"), 8)
	assert_true(up.is_zero_delta("doors"), "8 -> 9 changes nothing")

func test_a_zero_delta_purchase_is_refused_by_the_sim() -> void:
	# Enforcing this only in the view is not enough: two taps queued during a
	# stalled frame would buy level 8 and then charge $832 for level 9.
	econ.accrue(1e12)
	for i in range(8):
		up.purchase("doors", econ, b)
	var cash_before := econ.cash
	assert_false(up.purchase("doors", econ, b), "refused")
	assert_almost_eq(econ.cash, cash_before, 1e-6, "and not charged")
	assert_eq(up.level_of("doors"), 8, "and not levelled")

func test_speed_and_capacity_never_saturate() -> void:
	assert_false(up.is_zero_delta("speed"))
	assert_false(up.is_zero_delta("capacity"))

func test_structural_upgrades_have_no_effect_value() -> void:
	assert_false(up.has_effect("shaft"))
	assert_false(up.has_effect("floor"))
	assert_false(up.is_zero_delta("shaft"), "never blocks a structural purchase")

func test_a_fresh_car_matches_the_curve_at_level_zero() -> void:
	# The starting car is never _sync_car'd -- it runs on ElevatorCar's own
	# defaults -- so those defaults and the level-0 upgrade values have to agree.
	# They did only by coincidence, which is the kind of thing that silently
	# drifts the first time somebody tunes one of them.
	var fresh := ElevatorCar.new(0)
	assert_almost_eq(fresh.floors_per_tick, up.effect_value("speed", 0), 1e-9, "speed")
	assert_eq(fresh.door_ticks, int(up.effect_value("doors", 0)), "doors")
	assert_eq(fresh.capacity, int(up.effect_value("capacity", 0)), "capacity")
