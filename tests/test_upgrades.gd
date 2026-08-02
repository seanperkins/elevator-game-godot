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
	var before := b.cars[0].rows_per_tick
	econ.accrue(1e9)
	up.purchase("speed", econ, b)
	assert_gt(b.cars[0].rows_per_tick, before)

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
	up.purchase("row", econ, b)
	assert_eq(b.row_count, 7)

func test_row_purchases_stop_at_the_board_cap() -> void:
	econ.accrue(1e15)
	for i in range(60):
		up.purchase("row", econ, b)
	assert_eq(b.row_count, Building.MAX_ROWS, "the board never scrolls")

func test_a_maxed_upgrade_cannot_be_bought() -> void:
	econ.accrue(1e15)
	for i in range(60):
		up.purchase("row", econ, b)
	var cash_before := econ.cash
	assert_false(up.purchase("row", econ, b))
	assert_almost_eq(econ.cash, cash_before, 1e-6, "and must not charge")

func test_unknown_id_is_refused() -> void:
	econ.accrue(1e9)
	assert_false(up.purchase("nonexistent", econ, b))

func test_new_shafts_inherit_current_upgrade_levels() -> void:
	econ.accrue(1e9)
	up.purchase("speed", econ, b)
	up.purchase("shaft", econ, b)
	assert_almost_eq(b.cars[1].rows_per_tick, b.cars[0].rows_per_tick, 1e-9,
		"a newly bought car must not be slower than the one you have")
