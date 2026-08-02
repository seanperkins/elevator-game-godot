extends GutTest

var gs: GameState

func before_each() -> void:
	gs = GameState.new(6, 1, 4242)

func test_dispatch_moves_the_named_car() -> void:
	assert_true(gs.dispatch(0, 3))
	assert_eq(gs.building.cars[0].target_row, 3)

func test_dispatch_rejects_an_unknown_shaft() -> void:
	assert_false(gs.dispatch(9, 3))

func test_dispatch_rejects_a_row_outside_the_building() -> void:
	assert_false(gs.dispatch(0, 99))
	assert_false(gs.dispatch(0, -1))

func test_ticking_advances_the_clock() -> void:
	gs.tick(100)
	assert_eq(gs.clock.ticks_executed, 100)

func test_delivery_beats_expiry_at_exactly_zero_patience() -> void:
	# THE boundary. Order is deliver -> expire, so a passenger reaching exactly
	# 0 on the tick the doors open is delivered, pays, and extends the combo.
	var p := Passenger.new(0, 1, 1, 10.0)
	gs.building.enqueue(p)
	var car: ElevatorCar = gs.building.cars[0]
	car.dispatch_to(0)                 # doors open at row 0
	var delivered := []
	gs.passenger_delivered.connect(func(pp, _paid): delivered.append(pp))
	var expired := []
	gs.passenger_expired.connect(func(pp): expired.append(pp))
	gs.tick(1)
	assert_eq(expired.size(), 0, "must not expire at exactly zero")

func test_expiry_fires_below_zero_patience() -> void:
	var p := Passenger.new(0, 1, 0, 10.0)
	gs.building.enqueue(p)
	var expired := []
	gs.passenger_expired.connect(func(pp): expired.append(pp))
	gs.tick(2)                         # patience goes to -2
	assert_eq(expired.size(), 1)
	assert_eq(gs.building.waiting_at(0).size(), 0, "expired leave the queue")

func test_expiry_breaks_the_combo() -> void:
	gs.economy.credit_delivery(10.0)
	assert_gt(gs.economy.combo, 1.0)
	gs.building.enqueue(Passenger.new(0, 1, 0, 10.0))
	gs.tick(2)
	assert_almost_eq(gs.economy.combo, 1.0, 1e-9)

func test_a_full_trip_boards_delivers_and_pays() -> void:
	var car: ElevatorCar = gs.building.cars[0]
	car.rows_per_tick = 1.0            # one row per tick, fast for the test
	# Two ticks of dwell, not one: doors are stepped in the move/doors phase,
	# which runs BEFORE deliver, so a one-tick dwell opened between ticks shuts
	# before anyone can board. At the shipped 20-tick dwell this is invisible.
	car.door_ticks = 2
	gs.building.enqueue(Passenger.new(0, 2, 100000, 10.0))
	gs.dispatch(0, 0)                  # open at row 0 to board
	gs.tick(1)
	assert_eq(car.riders.size(), 1, "boarded while the doors were open")
	gs.dispatch(0, 2)
	gs.tick(5)
	assert_eq(car.riders.size(), 0, "alighted at row 2")
	assert_gt(gs.economy.cash, 0.0, "the fare was paid")
	assert_eq(gs.economy.riders_served, 1)

func test_passengers_only_board_a_car_at_their_own_row() -> void:
	var car: ElevatorCar = gs.building.cars[0]
	gs.building.enqueue(Passenger.new(4, 0, 100000, 10.0))
	gs.dispatch(0, 0)
	gs.tick(1)
	assert_eq(car.riders.size(), 0, "the car is at row 0, they wait at row 4")

func test_spawned_passengers_join_the_waiting_queues() -> void:
	# Counted off the signal, not off total_waiting(): patience is 900 ticks, so
	# over a window this long a spawn can arrive and expire without ever showing
	# up in a queue snapshot. Twenty minutes spans the morning rush (~43.6
	# expected spawns), so zero is not a plausible seed, unlike the overnight
	# trough's 1.4.
	# An Array, not an int: GDScript lambdas capture by value, so a captured
	# counter would increment a copy and read back zero.
	var spawned := []
	gs.passenger_spawned.connect(func(p): spawned.append(p))
	gs.tick(SimClock.TICKS_PER_MINUTE * 20)
	assert_gt(spawned.size(), 0, "traffic must actually appear")
	assert_gt(gs.building.total_waiting(), 0, "and it queues on its origin row")

func test_the_sim_is_deterministic_for_a_given_seed() -> void:
	var a := GameState.new(6, 1, 777)
	var b := GameState.new(6, 1, 777)
	a.tick(12000)
	b.tick(12000)
	assert_eq(a.building.total_waiting(), b.building.total_waiting(),
		"identical seeds must give identical waiting counts")
	assert_eq(a.economy.riders_served, b.economy.riders_served)

func test_ticking_zero_is_a_no_op() -> void:
	gs.tick(0)
	assert_eq(gs.clock.ticks_executed, 0)

func test_rent_accrues_while_the_sim_runs() -> void:
	var before := gs.economy.cash
	gs.tick(SimClock.TICKS_PER_MINUTE)
	assert_gt(gs.economy.cash, before, "tenants pay rent every tick")

func test_expiry_lowers_the_origin_rows_satisfaction() -> void:
	var before := gs.tenancy.satisfaction_at(0)
	gs.building.enqueue(Passenger.new(0, 1, 0, 10.0))
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(0), before)

func test_buying_a_row_extends_tenancy_too() -> void:
	gs.economy.accrue(1e9)
	assert_true(gs.buy("row"))
	assert_eq(gs.building.row_count, 7)
	assert_false(gs.tenancy.is_vacant(6), "the new row must have a tenant")

func test_buying_without_cash_fails() -> void:
	assert_false(gs.buy("shaft"))
	assert_eq(gs.building.cars.size(), 1)
