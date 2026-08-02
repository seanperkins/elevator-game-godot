extends GutTest

## A stop is three things, not one: the doors slide open, people move, the doors
## slide shut. Modelling it as a single dwell in which boarding happens on the
## first tick was invisible until the doors were drawn -- and then it read as
## passengers stepping through shut doors.
##
## The sim owns the PHASES (how many ticks of each) because "you cannot board a
## car whose doors are shut" is a rule, not decoration. The view owns only the
## mapping from those ticks to a panel width.

func opened_car(dwell: int) -> ElevatorCar:
	var car := ElevatorCar.new(0)
	car.door_ticks = dwell
	car.dispatch_to(0)          # already there, so the doors start opening
	return car

func test_a_stop_begins_with_the_doors_shut() -> void:
	var car := opened_car(20)
	assert_eq(car.state, ElevatorCar.State.DOORS, "the stop has begun")
	assert_false(car.is_available(), "but nobody can board through a shut door")

func test_boarding_waits_for_the_doors_to_finish_opening() -> void:
	var car := opened_car(20)
	assert_eq(car.door_opening_ticks(), 5, "a quarter of the stop, at level 0")
	car.step(4)
	assert_false(car.is_available(), "still sliding")
	car.step(1)
	assert_true(car.is_available(), "open")

func test_boarding_stops_again_as_the_doors_shut() -> void:
	var car := opened_car(20)
	car.step(5)
	assert_true(car.is_available())
	car.step(9)                       # elapsed 14 of 20, closing starts at 15
	assert_true(car.is_available(), "still open")
	car.step(1)
	assert_false(car.is_available(), "shutting: too late to get in")

func test_faster_doors_open_sooner() -> void:
	# The upgrade buys a shorter stop AND a shorter wait inside it.
	var slow := opened_car(20)
	var fast := opened_car(4)
	assert_lt(fast.door_opening_ticks(), slow.door_opening_ticks())
	fast.step(fast.door_opening_ticks())
	assert_true(fast.is_available(), "open after one tick at the door floor")

func test_the_shortest_possible_dwell_still_lets_someone_board() -> void:
	# Degenerate but reachable in tests and in tuning: a stop must never be so
	# short that the open window vanishes and boarding becomes impossible.
	for dwell in range(1, 25):
		var car := opened_car(dwell)
		var boardable := 0
		for i in range(dwell):
			if car.is_available():
				boardable += 1
			car.step(1)
		assert_gt(boardable, 0, "dwell of %d must have an open window" % dwell)

func test_the_doors_are_shut_again_when_the_stop_ends() -> void:
	var car := opened_car(20)
	car.step(20)
	assert_eq(car.state, ElevatorCar.State.IDLE)
	assert_false(car.is_available())

# --- the view's mapping ----------------------------------------------------

func test_the_panels_are_shut_when_the_stop_starts() -> void:
	assert_almost_eq(ShaftColumn.aperture_for(0, 20, 5, 5), 0.0, 1e-6)

func test_the_panels_are_wide_open_exactly_when_boarding_opens() -> void:
	# THE agreement. If these drift apart, people move through shut doors again.
	assert_almost_eq(ShaftColumn.aperture_for(5, 20, 5, 5), 1.0, 1e-6)

func test_the_panels_stay_open_for_the_whole_boarding_window() -> void:
	for elapsed in range(5, 16):
		assert_almost_eq(ShaftColumn.aperture_for(elapsed, 20, 5, 5), 1.0, 1e-6,
			"open at tick %d" % elapsed)

func test_the_panels_shut_as_the_stop_ends() -> void:
	assert_almost_eq(ShaftColumn.aperture_for(20, 20, 5, 5), 0.0, 1e-6)

func test_the_aperture_never_leaves_its_range() -> void:
	for dwell in [1, 2, 4, 7, 20]:
		var car := ElevatorCar.new(0)
		car.door_ticks = dwell
		for elapsed in range(-2, dwell + 3):
			var a := ShaftColumn.aperture_for(elapsed, dwell,
				car.door_opening_ticks(), car.door_closing_ticks())
			assert_between(a, 0.0, 1.0, "dwell %d at tick %d" % [dwell, elapsed])

func test_the_panels_are_open_whenever_the_car_will_accept_someone() -> void:
	# Swept across every dwell the upgrade curve can produce, because this is
	# the invariant the whole change exists to hold.
	for dwell in range(1, 25):
		var car := opened_car(dwell)
		for elapsed in range(dwell):
			if car.is_available():
				assert_almost_eq(ShaftColumn.aperture_for(elapsed, dwell,
					car.door_opening_ticks(), car.door_closing_ticks()), 1.0, 1e-6,
					"dwell %d, tick %d: boarding with the panels not open"
						% [dwell, elapsed])
			car.step(1)
