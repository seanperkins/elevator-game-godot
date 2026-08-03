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
	var p := Passenger.new(0, 1, 1, 10.0, 0)
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
	# Row 3, not row 0: the car parks at the lobby and now answers calls there,
	# so a passenger left at floor 0 is rescued before it can expire. The row was
	# always incidental here -- this test is about the patience boundary.
	var p := Passenger.new(3, 1, 0, 10.0, 3)
	gs.building.enqueue(p)
	var expired := []
	gs.passenger_expired.connect(func(pp): expired.append(pp))
	gs.tick(2)                         # patience goes to -2
	assert_eq(expired.size(), 1)
	assert_eq(gs.building.waiting_at(3).size(), 0, "expired leave the queue")

func test_expiry_breaks_the_combo() -> void:
	gs.economy.credit_delivery(10.0)
	assert_gt(gs.economy.combo, 1.0)
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_almost_eq(gs.economy.combo, 1.0, 1e-9)

func test_a_full_trip_boards_delivers_and_pays() -> void:
	var car: ElevatorCar = gs.building.cars[0]
	car.rows_per_tick = 1.0            # one row per tick, fast for the test
	# Two ticks of dwell, not one: doors are stepped in the move/doors phase,
	# which runs BEFORE deliver, so a one-tick dwell opened between ticks shuts
	# before anyone can board. At the shipped 20-tick dwell this is invisible.
	car.door_ticks = 2
	gs.building.enqueue(Passenger.new(0, 2, 100000, 10.0, 0))
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
	gs.building.enqueue(Passenger.new(4, 0, 100000, 10.0, 4))
	gs.dispatch(0, 0)
	gs.tick(1)
	assert_eq(car.riders.size(), 0, "the car is at row 0, they wait at row 4")

func test_spawned_passengers_join_the_waiting_queues() -> void:
	# Counted off the signal, not off total_waiting(): patience is 900 ticks, so
	# over a window this long a spawn can arrive and expire without ever showing
	# up in a queue snapshot. Twenty minutes spans the morning rush (~43.6
	# expected spawns), so zero is not a plausible seed, unlike the overnight
	# trough's 1.4.
	#
	# The queue is sampled DURING the run rather than at the end. A closing
	# snapshot only ever worked by accident: twenty minutes from the opening
	# minute wraps past the trough, so the final minutes are legitimately quiet
	# and everyone who spawned has long since expired.
	# Arrays, not ints: GDScript lambdas capture by value, so a captured counter
	# would increment a copy and read back zero.
	var spawned := []
	gs.passenger_spawned.connect(func(p): spawned.append(p))
	var queued := []
	for i in range(SimClock.TICKS_PER_MINUTE * 20):
		gs.tick(1)
		if gs.building.total_waiting() > 0:
			queued.append(i)
	assert_gt(spawned.size(), 0, "traffic must actually appear")
	assert_false(queued.is_empty(), "and it queues on its origin row")

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

func test_an_idle_building_earns_nothing() -> void:
	# The point of removing rent: no money for doing nothing. Income has to be
	# bought, with automation, rather than arriving on a timer.
	var before := gs.economy.cash
	gs.tick(SimClock.TICKS_PER_MINUTE * 3)
	assert_almost_eq(gs.economy.cash, before, 1e-9,
		"nobody was carried, so nobody paid")

func test_a_real_expiry_deducts_the_stairs_penalty() -> void:
	# Seeded first: a fresh GameState holds $0 and economy.gd:42 caps the
	# penalty at available cash, so "assert cash fell" would leave $0 -> $0
	# and fail against the fixed code exactly as it fails against the broken
	# code. The seeding is what makes this test able to distinguish them.
	gs.economy.accrue(100.0)
	var before := gs.economy.cash
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))
	gs.tick(2)
	assert_almost_eq(gs.economy.cash, before - 10.0, 1e-9,
		"one expiry costs exactly min(fare, cash)")

func test_expiry_lowers_the_origin_rows_satisfaction() -> void:
	var before := gs.tenancy.satisfaction_at(3)
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(3), before)

func test_buying_a_row_extends_tenancy_too() -> void:
	gs.economy.accrue(1e9)
	assert_true(gs.buy("row"))
	assert_eq(gs.building.row_count, 7)
	assert_false(gs.tenancy.is_vacant(6), "the new row must have a tenant")

func test_buying_without_cash_fails() -> void:
	assert_false(gs.buy("shaft"))
	assert_eq(gs.building.cars.size(), 1)

## Drives a row out of its lease and returns once it is vacant.
func vacate(state: GameState, row: int) -> void:
	while state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		state.tenancy.accrue_for_tick()

func test_relet_charges_the_cost() -> void:
	vacate(gs, 0)
	gs.economy.accrue(1000.0)
	var before := gs.economy.cash
	assert_true(gs.relet(0))
	assert_false(gs.tenancy.is_vacant(0))
	assert_almost_eq(gs.economy.cash, before - Tenancy.RELET_COST, 1e-6,
		"re-leasing has never actually charged before this")

func test_relet_is_free_when_nothing_is_tenanted() -> void:
	for row in range(gs.building.row_count):
		vacate(gs, row)
	assert_eq(gs.tenancy.tenanted_count(), 0)
	var before := gs.economy.cash
	assert_true(gs.relet(0), "the no-fail guarantee")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_relet_is_refused_when_unaffordable_and_charges_nothing() -> void:
	vacate(gs, 0)
	assert_lt(gs.economy.cash, Tenancy.RELET_COST)
	var before := gs.economy.cash
	assert_false(gs.relet(0))
	assert_true(gs.tenancy.is_vacant(0), "still vacant")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_relet_is_refused_on_a_tenanted_row() -> void:
	gs.economy.accrue(1000.0)
	var before := gs.economy.cash
	assert_false(gs.relet(2))
	assert_almost_eq(gs.economy.cash, before, 1e-6, "must not charge")

func test_relet_is_refused_outside_the_building() -> void:
	gs.economy.accrue(1000.0)
	assert_false(gs.relet(-1))
	assert_false(gs.relet(99))

func test_relet_reads_the_cost_before_reletting() -> void:
	# relet_cost is derived from tenanted_count, and relet() flips it. Reletting
	# first would turn the free last-row case into a $40 charge.
	var solo := GameState.new(1, 1, 5)
	vacate(solo, 0)
	var before := solo.economy.cash
	assert_true(solo.relet(0))
	assert_almost_eq(solo.economy.cash, before, 1e-6, "free, not $40")

const BUCKET_SLACK := 40   # one bucket either side of the boundary

func test_deliveries_reach_the_metrics_window() -> void:
	var car: ElevatorCar = gs.building.cars[0]
	car.rows_per_tick = 1.0
	car.door_ticks = 2
	gs.building.enqueue(Passenger.new(0, 2, 100000, 10.0, 0))
	gs.dispatch(0, 0)
	gs.tick(1)
	gs.dispatch(0, 2)
	gs.tick(5)
	assert_eq(gs.metrics.deliveries(), 1)
	assert_gte(gs.metrics.average_wait_seconds(), 0.0, "a real wait was recorded")

func test_expiries_reach_the_metrics_window() -> void:
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_eq(gs.metrics.expiries(), 1)

func test_the_metrics_window_advances_with_the_sim() -> void:
	# The spawner is silenced: over the 1,240 ticks this waits, ambient traffic
	# spawns and expires on its own -- seed 4242 produces exactly one such expiry
	# -- and the window would refill with it. This asserts that the ORIGINAL
	# event ages out, so the traffic has to go.
	gs.spawner.curve = PackedFloat32Array()
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_eq(gs.metrics.expiries(), 1)
	gs.tick(SimClock.TICKS_PER_MINUTE + BUCKET_SLACK)
	assert_eq(gs.metrics.expiries(), 0, "it left the window")

func test_a_spawned_passenger_first_decays_on_the_next_tick() -> void:
	# Spec §8.3: "A passenger spawned on tick T first decays on tick T+1."
	# No test has ever pinned this, and the code decays on tick T because
	# _tick_once spawns and then expires within the same call.
	# Row 3 again: a passenger the lobby car picks up stops decaying entirely,
	# because riders are being served. That would hide the boundary.
	var p := Passenger.new(3, 1, 100, 1.0, 3)
	gs.building.enqueue(p)
	gs.tick(1)
	assert_eq(p.patience_ticks, 99,
		"one tick of decay for one tick of waiting")

func test_the_opening_minutes_carry_real_traffic() -> void:
	# The cold start a player actually experiences. Starting the day at midnight
	# opened on the curve's overnight trough -- 0.4, 0.3, 0.2 spawns per simulated
	# minute -- so a new player watched an empty building for about six real
	# minutes, and a 900-tick patience meant the rare night passenger was gone
	# before anyone looked.
	#
	# Counted off the signal into an Array: GDScript lambdas capture by value, so
	# a captured int would increment a copy and read back zero. Three simulated
	# minutes of rush is ~11.4 expected spawns against ~0.9 for the trough, so
	# this discriminates rather than riding the seed.
	var spawned := []
	gs.passenger_spawned.connect(func(p): spawned.append(p))
	gs.tick(SimClock.TICKS_PER_MINUTE * 3)
	assert_gt(spawned.size(), 4,
		"the opening minutes must be busy, not the 0.9-spawn overnight trough")

func test_the_opening_rate_is_a_rush_rate() -> void:
	assert_gt(gs.spawner.rate_at_minute(gs.clock.sim_minute()), 2.0,
		"the day opens on real traffic, not the 0.4/min trough")

# --- a parked car answers a call at its own floor --------------------------

## Silences traffic so these assert the rule and not the seed.
func quiet_state(rows := 6, shafts := 1) -> GameState:
	var st := GameState.new(rows, shafts, 4242)
	st.spawner.curve = PackedFloat32Array()
	return st

func test_a_parked_car_opens_its_doors_for_someone_on_its_own_floor() -> void:
	# A car sitting at a floor ignoring the person standing next to it reads as
	# broken, not as a rule. It opens its doors; it still does not MOVE.
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	st.tick(1)
	assert_eq(car.state, ElevatorCar.State.IDLE, "parked at the lobby")
	st.building.enqueue(Passenger.new(0, 4, 900, 4.0, 0))
	# The doors have to finish opening first: a stop is open, board, shut.
	st.tick(car.door_opening_ticks() + 1)
	assert_eq(car.riders.size(), 1, "they got on")
	assert_true(st.building.waiting_at(0).is_empty(), "and left the queue")

func test_answering_a_call_is_not_dispatch_automation() -> void:
	# The doors open; the car goes nowhere. Choosing the destination stays the
	# player's job -- that is Milestone 4, and this is not a piece of it.
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	st.tick(1)
	st.building.enqueue(Passenger.new(0, 4, 900, 4.0, 0))
	st.tick(3)
	assert_eq(car.target_row, 0, "still targeting the floor it is parked on")
	assert_almost_eq(car.position_row, 0.0, 1e-9, "and it has not moved")

func test_a_parked_car_ignores_a_call_on_a_different_floor() -> void:
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	st.tick(1)
	st.building.enqueue(Passenger.new(3, 5, 900, 4.0, 3))
	st.tick(5)
	assert_eq(car.riders.size(), 0, "it is at floor 0, they are at floor 3")
	assert_eq(st.building.waiting_at(3).size(), 1, "still waiting")

func test_a_full_parked_car_does_not_open_its_doors() -> void:
	# Cycling the doors for someone who cannot board is worse than doing
	# nothing: it costs dwell and shows an opening the player cannot use.
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	st.tick(1)
	for i in range(car.capacity):
		car.riders.append(Passenger.new(0, 5, 900, 4.0, 0))
	st.building.enqueue(Passenger.new(0, 4, 900, 4.0, 0))
	st.tick(3)
	assert_eq(car.state, ElevatorCar.State.IDLE, "doors stay shut")
	assert_eq(st.building.waiting_at(0).size(), 1, "nobody boarded")

func test_a_moving_car_does_not_answer_calls_it_passes() -> void:
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	car.rows_per_tick = 0.2
	st.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	st.dispatch(0, 5)
	st.tick(3)
	assert_eq(car.state, ElevatorCar.State.MOVING, "still travelling")
	assert_eq(car.riders.size(), 0, "a passing car does not stop")

func test_a_parked_car_keeps_answering_as_people_arrive() -> void:
	var st := quiet_state()
	var car: ElevatorCar = st.building.cars[0]
	car.door_ticks = 2
	st.tick(1)
	st.building.enqueue(Passenger.new(0, 4, 900, 4.0, 0))
	st.tick(4)
	assert_eq(car.riders.size(), 1)
	st.building.enqueue(Passenger.new(0, 2, 900, 4.0, 0))
	st.tick(4)
	assert_eq(car.riders.size(), 2, "the doors reopen for the next one")
