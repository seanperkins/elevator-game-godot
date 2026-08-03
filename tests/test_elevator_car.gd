extends GutTest

var car: ElevatorCar

func before_each() -> void:
	car = ElevatorCar.new(0)
	car.floors_per_tick = 0.1     # 10 ticks per floor = 0.5 s per floor
	car.door_ticks = 20         # 1 s dwell
	car.capacity = 4

func test_starts_idle_at_its_start_row() -> void:
	assert_eq(car.state, ElevatorCar.State.IDLE)
	assert_almost_eq(car.position_floor, 0.0, 1e-9)


## Opens the doors AND waits out the opening slide. Boarding is only possible
## once the doors are actually open -- a stop is open, board, shut -- so a test
## about capacity or arrivals has to be past the slide before it means anything.
func open_fully(floor_index := 0) -> void:
	car.dispatch_to(floor_index)
	car.step(car.door_opening_ticks())

func test_dispatch_sets_target_and_moves() -> void:
	car.dispatch_to(5)
	assert_eq(car.target_floor, 5)
	assert_eq(car.state, ElevatorCar.State.MOVING)

func test_dispatch_to_current_row_opens_doors_without_moving() -> void:
	car.dispatch_to(0)
	assert_eq(car.state, ElevatorCar.State.DOORS,
		"already there -- open, do not travel")

func test_moves_toward_target_over_ticks() -> void:
	car.dispatch_to(5)
	car.step(10)                        # 10 ticks * 0.1 floors = 1 floor
	assert_almost_eq(car.position_floor, 1.0, 1e-9)

func test_arrival_opens_doors_and_snaps_position() -> void:
	car.dispatch_to(2)
	car.step(25)                        # overshoots 2.0 floors worth
	assert_almost_eq(car.position_floor, 2.0, 1e-9, "snapped, never past target")
	assert_eq(car.state, ElevatorCar.State.DOORS)

func test_doors_close_after_dwell_and_car_goes_idle() -> void:
	car.dispatch_to(1)
	car.step(10)                        # arrive, doors open
	assert_eq(car.state, ElevatorCar.State.DOORS)
	car.step(19)
	assert_eq(car.state, ElevatorCar.State.DOORS, "still dwelling at 19 of 20")
	car.step(1)
	assert_eq(car.state, ElevatorCar.State.IDLE, "dwell complete")

func test_moves_downward_too() -> void:
	car = ElevatorCar.new(10)
	car.floors_per_tick = 0.1
	car.dispatch_to(8)
	car.step(10)
	assert_almost_eq(car.position_floor, 9.0, 1e-9)

func test_current_row_rounds_to_nearest() -> void:
	car.dispatch_to(5)
	car.step(14)                        # 1.4 floors
	assert_eq(car.current_floor(), 1)
	car.step(2)                         # 1.6 floors
	assert_eq(car.current_floor(), 2)

func test_is_available_only_when_doors_are_open() -> void:
	assert_false(car.is_available(), "idle but doors shut")
	car.dispatch_to(0)
	assert_false(car.is_available(), "stopped, but the doors are still sliding")
	car.step(car.door_opening_ticks())
	assert_true(car.is_available(), "open")

func test_boarding_respects_capacity() -> void:
	open_fully()
	for i in range(4):
		assert_true(car.board(Passenger.new(0, 3, 100, 1.0, 0)), "seat %d" % i)
	assert_false(car.board(Passenger.new(0, 3, 100, 1.0, 0)), "car is full")
	assert_eq(car.riders.size(), 4)

func test_boarding_marks_the_passenger() -> void:
	open_fully()
	var p := Passenger.new(0, 3, 100, 1.0, 0)
	car.board(p)
	assert_true(p.boarded)

func test_take_arrivals_returns_only_riders_for_this_row() -> void:
	open_fully()
	var here := Passenger.new(0, 3, 100, 1.0, 0)
	var elsewhere := Passenger.new(0, 7, 100, 1.0, 0)
	car.board(here)
	car.board(elsewhere)
	car.dispatch_to(3)
	car.step(30)                        # travel 3 floors, arrive
	car.step(car.door_opening_ticks())  # and let the doors finish opening
	var out := car.take_arrivals()
	assert_eq(out.size(), 1)
	assert_eq(out[0].destination_floor, 3)
	assert_eq(car.riders.size(), 1, "the other rider stays aboard")

func test_take_arrivals_is_empty_when_doors_are_shut() -> void:
	open_fully()
	car.board(Passenger.new(0, 0, 100, 1.0, 0))
	car.step(25)                        # doors closed again
	assert_eq(car.take_arrivals().size(), 0)
