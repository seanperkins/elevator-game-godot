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
	# up in a queue snapshot. Twenty BUCKETS spans the morning rush (~43.6
	# expected spawns), so zero is not a plausible seed, unlike the overnight
	# trough's 1.4. Buckets, not real minutes -- one bucket is thirty seconds,
	# so this is ten real minutes of ticks.
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
	for i in range(SimClock.TICKS_PER_SIM_MINUTE * 20):
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
	gs.tick(SimClock.TICKS_PER_REAL_MINUTE * 3)
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

func test_delivery_credits_the_generating_floor_not_the_destination() -> void:
	# An outbound trip: floor 4's tenant sent somebody to the lobby.
	# The credit belongs to 4, which generated it, not to 0, which received it.
	for i in range(30):
		gs.tenancy.note_expiry(4)
	var before := gs.tenancy.satisfaction_at(4)
	var lobby_before := gs.tenancy.satisfaction_at(0)
	var p := Passenger.new(4, 0, 900, 4.0, 4)
	gs.building.cars[0].dispatch_to(4)
	gs.building.enqueue(p)
	# Short windows, deliberately NOT a full minute: 30 expiries start a
	# 1200-tick move-out countdown, so a full minute is just long enough for
	# floor 4 to VACATE -- and note_delivery is a no-op on a vacant row, which
	# would suppress the very credit this test asserts.
	gs.tick(200)                         # car reaches 4, doors open, boards
	gs.building.cars[0].dispatch_to(0)   # send it back so the rider alights
	gs.tick(200)                         # travel down, alight, credit the source
	assert_gt(gs.tenancy.satisfaction_at(4), before, "the generator is credited")
	assert_almost_eq(gs.tenancy.satisfaction_at(0), lobby_before, 1e-9,
		"the lobby received the trip but did not generate it")

func test_expiry_blames_the_generating_floor_not_the_origin() -> void:
	# An inbound trip: floor 3's visitor gave up in the lobby.
	# The blame belongs to 3, not to the lobby they were standing in.
	var before := gs.tenancy.satisfaction_at(3)
	var lobby_before := gs.tenancy.satisfaction_at(0)
	gs.building.enqueue(Passenger.new(0, 3, 0, 10.0, 3))
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(3), before, "the generator is blamed")
	assert_almost_eq(gs.tenancy.satisfaction_at(0), lobby_before, 1e-9,
		"the lobby held the queue but did not generate it")

func test_expiry_lowers_the_generating_rows_satisfaction() -> void:
	var before := gs.tenancy.satisfaction_at(3)
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_lt(gs.tenancy.satisfaction_at(3), before)

func test_buying_a_row_grows_every_per_floor_container() -> void:
	gs.economy.accrue(1e9)
	assert_true(gs.buy("row"))
	assert_eq(gs.building.row_count, 7)
	assert_eq(gs.tenancy.rows(), 7)
	assert_eq(gs.fitout.rows(), 7, "one loop grows every container")
	assert_true(gs.tenancy.is_vacant(6), "a purchased floor is leased, not granted")
	assert_eq(gs.tenancy.kind_at(6), "")
	assert_eq(gs.fitout.tier_at(6), 1)

func test_buying_without_cash_fails() -> void:
	assert_false(gs.buy("shaft"))
	assert_eq(gs.building.cars.size(), 1)

func test_a_tall_new_building_tenants_only_the_roster() -> void:
	# The state every --board= session and every pre-restore decode starts
	# from. Neither the buy("row") test nor the save round-trips cover it:
	# both pass whether or not _init applies the roster limit.
	var tall := GameState.new(12, 1, 4242)
	for row in range(6):
		assert_false(tall.tenancy.is_vacant(row))
		assert_ne(tall.tenancy.kind_at(row), "")
	for row in range(6, 12):
		assert_true(tall.tenancy.is_vacant(row), "row %d" % row)
		assert_eq(tall.tenancy.kind_at(row), "")
		assert_eq(tall.fitout.tier_at(row), 1)

func test_the_starting_roster_is_shops_over_apartments() -> void:
	assert_eq(gs.tenancy.kind_at(0), "shops")
	for row in range(1, 6):
		assert_eq(gs.tenancy.kind_at(row), "apartments")

func test_a_malformed_catalog_makes_the_state_invalid() -> void:
	var bad := GameState.new(6, 1, 1, "res://data/does_not_exist.json")
	assert_false(bad.is_valid())

## Silences traffic so a rule test asserts the rule, not the seed. One tenanted
## floor cannot generate a trip (a trip needs two floors), so nothing spawns.
## Replaces `spawner.curve = PackedFloat32Array()`, which set a field that is
## gone.
func _silence(state: GameState) -> void:
	for row in range(1, state.building.row_count):
		state.tenancy.restore_row(row, 1.0, true, 0)

## Drives a row out of its lease and returns once it is vacant.
func vacate(state: GameState, row: int) -> void:
	while state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		state.tenancy.accrue_for_tick()

func test_leasing_charges_the_kinds_price_and_sets_the_kind() -> void:
	gs.economy.accrue(1000.0)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	var before := gs.economy.cash
	assert_true(gs.lease(3, "apartments"))
	assert_false(gs.tenancy.is_vacant(3))
	assert_eq(gs.tenancy.kind_at(3), "apartments")
	assert_almost_eq(gs.economy.cash, before - 60.0, 1e-6)

func test_a_kind_above_the_floors_class_is_refused() -> void:
	gs.economy.accrue(1e6)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	assert_false(gs.lease(3, "law_firm"), "class 1 cannot take a tier-3 tenant")
	assert_true(gs.tenancy.is_vacant(3))

func test_only_the_cheapest_eligible_kind_is_free_below_two_tenants() -> void:
	# The guarantee must be exact -- a $0 player can always recover -- without
	# rewarding collapse. An already-upgraded floor would otherwise hand out a
	# free premium tenant.
	for row in range(1, 6):
		gs.tenancy.restore_row(row, 1.0, true, 0)
	gs.fitout.set_tier(3, 3)
	gs.economy.cash = 0.0
	assert_false(gs.lease(3, "law_firm"), "the expensive one is not free")
	assert_true(gs.lease(3, "apartments"), "the cheapest eligible one is")

func test_leasing_is_free_when_nothing_is_tenanted() -> void:
	for row in range(gs.building.row_count):
		vacate(gs, row)
	assert_eq(gs.tenancy.tenanted_count(), 0)
	var before := gs.economy.cash
	assert_true(gs.lease(0, "apartments"), "the no-fail guarantee")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_leasing_is_refused_when_unaffordable_and_charges_nothing() -> void:
	# Row 0 vacated but rows 1-5 stay tenanted, so a full $60 apartments lease
	# applies -- and a $0 player cannot take it.
	vacate(gs, 0)
	assert_lt(gs.economy.cash, 60.0, "apartments lease $60 while traffic earns")
	var before := gs.economy.cash
	assert_false(gs.lease(0, "apartments"))
	assert_true(gs.tenancy.is_vacant(0), "still vacant")
	assert_almost_eq(gs.economy.cash, before, 1e-6)

func test_leasing_is_refused_on_a_tenanted_row() -> void:
	gs.economy.accrue(1000.0)
	var before := gs.economy.cash
	assert_false(gs.lease(2, "apartments"))
	assert_almost_eq(gs.economy.cash, before, 1e-6, "must not charge")

func test_leasing_is_refused_outside_the_building() -> void:
	gs.economy.accrue(1000.0)
	assert_false(gs.lease(-1, "apartments"))
	assert_false(gs.lease(99, "apartments"))

func test_lease_reads_the_cost_before_mutating_tenancy() -> void:
	# Cost derives from tenanted_count(), which leasing increments, so the
	# order decides whether the last row costs nothing or full price.
	for row in range(1, 6):
		gs.tenancy.restore_row(row, 1.0, true, 0)
	gs.economy.cash = 0.0
	var before := gs.economy.cash
	assert_true(gs.lease(3, "apartments"))
	assert_almost_eq(gs.economy.cash, before, 1e-6, "free, not $60")

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
	_silence(gs)
	gs.building.enqueue(Passenger.new(3, 1, 0, 10.0, 3))   # off the car's floor
	gs.tick(2)
	assert_eq(gs.metrics.expiries(), 1)
	gs.tick(SimClock.TICKS_PER_REAL_MINUTE + BUCKET_SLACK)
	assert_eq(gs.metrics.expiries(), 0, "it left the window")

func test_upgrading_a_tenanted_floor_changes_its_fare_on_the_next_spawn() -> void:
	# THE discriminating test. A class purchase mutates Fitout, not Tenancy,
	# so a Tenancy-scoped revision would leave the stale x1.00 cached until
	# the next tenancy event -- which on a well-served floor may be never.
	# The "new tenant is charged x1.80" test cannot catch that: a lease moves
	# the revision and rebuilds the cache, so it passes either way.
	gs.economy.accrue(1e6)
	var before := 0.0
	for s in gs._sources():
		if s.floor_row == 3:
			before = s.fare_multiplier
	assert_almost_eq(before, 1.0, 1e-9)
	assert_true(gs.upgrade_class(3))
	var after := 0.0
	for s in gs._sources():
		if s.floor_row == 3:
			after = s.fare_multiplier
	assert_almost_eq(after, 1.35, 1e-9,
		"the upgrade pays immediately, with no intervening tenancy event")

func test_a_class_upgrade_is_refused_when_unaffordable_or_maxed() -> void:
	gs.economy.cash = 10.0
	assert_false(gs.upgrade_class(3), "cannot afford $400")
	assert_eq(gs.fitout.tier_at(3), 1)
	gs.economy.accrue(1e6)
	assert_true(gs.upgrade_class(3))
	assert_true(gs.upgrade_class(3))
	assert_eq(gs.fitout.tier_at(3), 3)
	assert_false(gs.upgrade_class(3), "tier 3 is the top of the ladder")

func test_class_survives_a_tenant_change_and_kind_does_not() -> void:
	# The headline invariant: things built into the floor persist, things
	# built for the tenant leave with them.
	gs.economy.accrue(1e6)
	assert_true(gs.upgrade_class(3))
	assert_true(gs.upgrade_class(3))
	while gs.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(3)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(3))
	assert_eq(gs.tenancy.kind_at(3), "", "kind leaves with the tenant")
	assert_eq(gs.fitout.tier_at(3), 3, "class is built into the floor")

func test_a_new_tenant_on_a_class_three_floor_is_charged_the_multiplier() -> void:
	gs.economy.accrue(1e6)
	gs.upgrade_class(3)
	gs.upgrade_class(3)
	gs.tenancy.restore_row(3, 1.0, true, 0)
	assert_true(gs.lease(3, "law_firm"))
	for s in gs._sources():
		if s.floor_row == 3:
			assert_almost_eq(s.kind.base_fare * s.fare_multiplier, 9.0 * 1.8, 1e-5)

func test_a_move_out_removes_that_floors_waiting_passengers_from_every_queue() -> void:
	# The inbound case is the one that matters: those passengers stand in the
	# LOBBY queue, so a rule phrased over "that floor's queue" misses them
	# entirely -- and for inbound-heavy kinds that is most of the floor's
	# traffic.
	#
	# Ambient traffic is silenced (one tenanted floor cannot spawn a trip) so
	# the three manual passengers below are the only ones in any queue; and
	# they outlive the move-out window, because patience 900 would expire the
	# survivor naturally inside 1201 ticks and this test must distinguish
	# source removal from ordinary expiry.
	for row in range(gs.building.row_count):
		if row != 4:
			gs.tenancy.restore_row(row, 1.0, true, 0)
	# Send the car to the roof FIRST and let it get away from the lobby: a car
	# parked at floor 0 answers the origin-0 calls below and BOARDs them,
	# turning waiting passengers into riders. Once parked at 5 it stays there
	# (auto is off and nothing is dispatched), so the lobby queue is never
	# served for the rest of the test.
	gs.building.cars[0].dispatch_to(5)
	gs.tick(200)
	var mine := Passenger.new(0, 4, 100000, 4.0, 4)     # inbound, belongs to 4
	var theirs := Passenger.new(0, 2, 100000, 4.0, 2)   # inbound, belongs to 2
	var also_mine := Passenger.new(4, 0, 100000, 4.0, 4)  # outbound, belongs to 4
	gs.building.enqueue(mine)
	gs.building.enqueue(theirs)
	gs.building.enqueue(also_mine)
	var cash_before := gs.economy.cash

	while gs.tenancy.satisfaction_at(4) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(4)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(4))

	var left: Array[Passenger] = []
	for row in range(gs.building.row_count):
		for p in gs.building.waiting_at(row):
			left.append(p)
	for p in left:
		assert_ne(p.source_row, 4, "no passenger from the vacated floor remains")
	var survivors := 0
	for p in left:
		if p.source_row == 2:
			survivors += 1
	assert_eq(survivors, 1, "another floor's lobby queue is untouched")
	assert_gte(gs.economy.cash, cash_before,
		"removal is not an expiry -- the failure was already charged")

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
	# Re-derived from the roster: at START_MINUTE the starting building
	# (1 Shops + 5 Apartments) sums to shops.rate_at(6) + 5 x apartments.rate_at(6)
	# = 0.0 + 5 x 0.5 = 2.5 trips/min, so ~7.5 over three minutes. Four is a
	# comfortable floor for a Bernoulli draw at that rate.
	#
	# An Array, deliberately: GDScript lambdas capture local ints by value, so a
	# captured counter increments a copy and reads back zero.
	var spawned := []
	gs.passenger_spawned.connect(func(p): spawned.append(p))
	gs.tick(SimClock.TICKS_PER_SIM_MINUTE * 3)
	assert_gt(spawned.size(), 4, "the opening is a rush, not a trickle")

func test_the_opening_rate_is_a_rush_rate() -> void:
	# Re-derived from the roster, since rate_at_minute is gone: the opening hour
	# must carry real traffic, not the old overnight trough.
	var sum := gs.catalog.kind("shops").rate_at(SimClock.START_MINUTE) \
		+ 5.0 * gs.catalog.kind("apartments").rate_at(SimClock.START_MINUTE)
	assert_gt(sum, 2.0, "the day opens on real traffic")

func test_the_source_cache_rebuilds_when_a_floor_vacates() -> void:
	while gs.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		gs.tenancy.note_expiry(3)
	gs.tick(Tenancy.MOVE_OUT_TICKS + 1)
	assert_true(gs.tenancy.is_vacant(3))
	for s in gs._sources():
		assert_ne(s.floor_row, 3, "a vacated floor stops generating traffic")

# --- a parked car answers a call at its own floor --------------------------

## Silences traffic so these assert the rule and not the seed.
func quiet_state(rows := 6, shafts := 1) -> GameState:
	var st := GameState.new(rows, shafts, 4242)
	_silence(st)
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
