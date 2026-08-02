extends GutTest

## The first dispatch policy: sweep every floor, per shaft.
##
## It only ever moves an IDLE car. A car mid-travel is committed, and a car with
## its doors open is boarding -- stealing either would make automation feel like
## sabotage, and would silently undo the parked-car pickup rule.

var gs: GameState

func before_each() -> void:
	gs = GameState.new(6, 2, 4242)
	gs.spawner.curve = PackedFloat32Array()   # policy under test, not traffic
	for car in gs.building.cars:
		car.rows_per_tick = 1.0               # a floor a tick, so tests are short
		car.door_ticks = 2

## Buys n levels of Auto-Dispatch. Each level licences one more sweeping shaft.
func licence(n := 8) -> void:
	gs.economy.accrue(1e12)
	for i in range(n):
		assert_true(gs.buy("auto"), "licence %d" % (i + 1))

## Runs until the named car reaches `row`, or gives up. Returns the ticks taken.
func run_until_at(shaft: int, row: int, limit := 400) -> int:
	var car: ElevatorCar = gs.building.cars[shaft]
	for t in range(limit):
		gs.tick(1)
		if car.current_row() == row:
			return t
	return -1

func test_every_shaft_starts_manual() -> void:
	licence()
	for shaft in range(gs.building.cars.size()):
		assert_false(gs.auto.is_enabled(shaft), "shaft %d" % shaft)

func test_a_manual_car_never_moves_on_its_own() -> void:
	licence()
	gs.tick(200)
	assert_almost_eq(gs.building.cars[0].position_row, 0.0, 1e-9,
		"nobody told it to go anywhere")

func test_an_enabled_car_sets_off_by_itself() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	assert_ne(run_until_at(0, 1), -1, "it left the lobby unprompted")

func test_it_visits_every_floor_in_turn() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	var seen := {}
	var car: ElevatorCar = gs.building.cars[0]
	for t in range(600):
		gs.tick(1)
		if car.state == ElevatorCar.State.DOORS:
			seen[car.current_row()] = true
	for row in range(gs.building.row_count):
		assert_true(seen.has(row), "floor %d must get a visit" % row)

func test_it_turns_round_at_the_top_instead_of_leaving_the_building() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	var car: ElevatorCar = gs.building.cars[0]
	var top := gs.building.row_count - 1
	assert_ne(run_until_at(0, top), -1, "reached the top")
	for t in range(200):
		gs.tick(1)
		assert_between(car.position_row, 0.0, float(top),
			"stayed inside the building")
		if car.current_row() < top:
			return
	fail_test("it never came back down")

func test_it_turns_round_at_the_lobby_too() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	var car: ElevatorCar = gs.building.cars[0]
	assert_ne(run_until_at(0, gs.building.row_count - 1), -1)
	assert_ne(run_until_at(0, 0, 600), -1, "came back to the lobby")
	assert_ne(run_until_at(0, 1, 600), -1, "and set off up again")

func test_only_the_enabled_shaft_moves() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	gs.tick(200)
	assert_gt(gs.building.cars[0].position_row, 0.0, "shaft 0 is sweeping")
	assert_almost_eq(gs.building.cars[1].position_row, 0.0, 1e-9,
		"shaft 1 was not asked to")

func test_switching_it_back_off_stops_it_where_it_stands() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	gs.tick(60)
	assert_true(gs.set_auto(0, false))
	gs.tick(60)                                   # let it finish what it started
	var resting := gs.building.cars[0].position_row
	gs.tick(200)
	assert_almost_eq(gs.building.cars[0].position_row, resting, 1e-9,
		"it stays put once the policy is off")

func test_it_does_not_steal_a_car_that_is_boarding() -> void:
	licence()
	# The doors are open and someone is getting on. Sending it away here would
	# undo the parked-car rule and read as sabotage.
	var car: ElevatorCar = gs.building.cars[0]
	car.door_ticks = 20
	gs.building.enqueue(Passenger.new(0, 3, 900, 4.0))
	gs.tick(1)
	assert_eq(car.state, ElevatorCar.State.DOORS, "boarding")
	assert_true(gs.set_auto(0, true))
	gs.tick(1)
	assert_eq(car.state, ElevatorCar.State.DOORS, "still boarding, not dragged off")

func test_it_does_not_steal_a_car_in_transit() -> void:
	licence()
	var car: ElevatorCar = gs.building.cars[0]
	car.rows_per_tick = 0.1
	gs.dispatch(0, 5)
	gs.tick(2)
	assert_true(gs.set_auto(0, true))
	gs.tick(1)
	assert_eq(car.target_row, 5, "the trip the player asked for is not overridden")

func test_a_manual_dispatch_still_works_and_the_sweep_resumes() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	gs.tick(40)
	gs.dispatch(0, 4)
	assert_eq(gs.building.cars[0].target_row, 4, "the player still has the wheel")
	assert_ne(run_until_at(0, 4, 200), -1, "it goes where it was told")
	assert_ne(run_until_at(0, 5, 400), -1, "and then carries on sweeping")

func test_a_one_floor_building_does_not_thrash() -> void:
	var solo := GameState.new(1, 1, 7)
	solo.spawner.curve = PackedFloat32Array()
	solo.economy.accrue(1e9)
	solo.buy("auto")
	assert_true(solo.set_auto(0, true))
	solo.tick(100)
	assert_almost_eq(solo.building.cars[0].position_row, 0.0, 1e-9,
		"there is nowhere else to be")

func test_a_new_floor_joins_the_sweep() -> void:
	licence()
	assert_true(gs.set_auto(0, true))
	gs.economy.accrue(1e9)
	assert_true(gs.buy("row"))
	var top := gs.building.row_count - 1
	assert_ne(run_until_at(0, top, 900), -1, "the new top floor gets visited")

func test_a_new_shaft_starts_manual() -> void:
	gs.economy.accrue(1e9)
	assert_true(gs.buy("shaft"))
	var fresh := gs.building.cars.size() - 1
	assert_false(gs.auto.is_enabled(fresh),
		"automation is opt-in per car, including cars bought later")

func test_enabling_an_unknown_shaft_is_ignored() -> void:
	licence()
	assert_false(gs.set_auto(99, true))
	assert_false(gs.auto.is_enabled(99))
	gs.tick(10)

# --- the licence ------------------------------------------------------------

func test_automation_is_locked_until_it_is_bought() -> void:
	# Free automation from minute one would delete the manual loop the whole
	# early game is made of.
	assert_eq(gs.auto_licences(), 0)
	assert_false(gs.set_auto(0, true), "no licence, no sweep")
	assert_false(gs.auto.is_enabled(0))
	gs.tick(200)
	assert_almost_eq(gs.building.cars[0].position_row, 0.0, 1e-9)

func test_each_level_licences_one_more_shaft() -> void:
	licence(1)
	assert_eq(gs.auto_licences(), 1)
	assert_true(gs.set_auto(0, true), "the one shaft it paid for")
	assert_false(gs.set_auto(1, true), "and no more than that")
	licence(1)
	assert_true(gs.set_auto(1, true), "a second level, a second shaft")

func test_turning_one_off_frees_its_licence() -> void:
	licence(1)
	assert_true(gs.set_auto(0, true))
	assert_false(gs.set_auto(1, true))
	assert_true(gs.set_auto(0, false), "hand the licence back")
	assert_true(gs.set_auto(1, true), "and spend it elsewhere")

func test_re_enabling_an_already_swept_shaft_is_not_a_second_licence() -> void:
	licence(1)
	assert_true(gs.set_auto(0, true))
	assert_true(gs.set_auto(0, true), "idempotent, not a double spend")
	assert_false(gs.set_auto(1, true), "still only one licence in use")

func test_the_licence_is_enforced_in_the_sim_not_the_view() -> void:
	# The same reasoning as the zero-delta refusal: a greyed-out button is
	# bypassed by two taps queued during a stalled frame.
	assert_false(gs.set_auto(0, true))
	assert_eq(gs.auto.enabled_count(), 0)

func test_the_upgrade_stops_at_one_licence_per_shaft() -> void:
	licence(8)
	assert_true(gs.upgrades.is_maxed("auto"))
	assert_eq(gs.auto_licences(), Building.MAX_SHAFTS)
