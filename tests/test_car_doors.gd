extends GutTest

## The dwell as the player sees it. door_progress is sim data -- how far through
## the dwell -- and the aperture curve is the view's shaping of it, kept pure so
## the shape is pinned here rather than by watching a car.

func test_a_shut_car_reports_no_progress() -> void:
	var car := ElevatorCar.new(0)
	assert_eq(car.state, ElevatorCar.State.IDLE)
	assert_almost_eq(car.door_progress(), 1.0, 1e-9,
		"1.0 means shut, so a car that never opened is shut")

func test_progress_runs_from_zero_to_one_across_the_dwell() -> void:
	var car := ElevatorCar.new(0)
	car.door_ticks = 20
	car.dispatch_to(0)                       # already there, so the doors open
	assert_eq(car.state, ElevatorCar.State.DOORS)
	assert_almost_eq(car.door_progress(), 0.0, 1e-9, "just opened")
	car.step(10)
	assert_almost_eq(car.door_progress(), 0.5, 1e-9, "half way through")
	car.step(9)
	assert_almost_eq(car.door_progress(), 0.95, 1e-9, "nearly shut")

func test_a_faster_door_runs_the_same_curve_in_less_time() -> void:
	# The whole point of the upgrade being visible: the same shape, quicker.
	var car := ElevatorCar.new(0)
	car.door_ticks = 4
	car.dispatch_to(0)
	car.step(2)
	assert_almost_eq(car.door_progress(), 0.5, 1e-9,
		"half of four ticks is the same half as half of twenty")

func test_the_aperture_opens_holds_and_shuts() -> void:
	assert_almost_eq(ShaftColumn.aperture_for(0.0), 0.0, 1e-6, "shut at the start")
	assert_almost_eq(ShaftColumn.aperture_for(0.5), 1.0, 1e-6, "wide open mid-dwell")
	assert_almost_eq(ShaftColumn.aperture_for(1.0), 0.0, 1e-6, "shut again at the end")

func test_the_aperture_never_leaves_its_range() -> void:
	var p := -0.5
	while p <= 1.5:
		var a := ShaftColumn.aperture_for(p)
		assert_between(a, 0.0, 1.0, "aperture at progress %f" % p)
		p += 0.01

func test_the_aperture_rises_then_falls_without_jumping() -> void:
	var previous := ShaftColumn.aperture_for(0.0)
	var peaked := false
	var p := 0.01
	while p <= 1.0:
		var a := ShaftColumn.aperture_for(p)
		assert_lt(absf(a - previous), 0.2, "no jump at progress %f" % p)
		if a < previous:
			peaked = true
		elif a > previous:
			assert_false(peaked, "it must not reopen after starting to shut")
		previous = a
		p += 0.01
	assert_true(peaked, "and it does shut again")
