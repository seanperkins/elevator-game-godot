extends GutTest

func make_p(origin := 0, dest := 5, patience := 100, fare := 10.0) -> Passenger:
	return Passenger.new(origin, dest, patience, fare)

func test_stores_its_trip() -> void:
	var p := make_p(2, 7)
	assert_eq(p.origin_row, 2)
	assert_eq(p.destination_row, 7)

func test_starts_unboarded() -> void:
	assert_false(make_p().boarded)

func test_decay_reduces_patience() -> void:
	var p := make_p(0, 5, 100)
	p.decay(30)
	assert_eq(p.patience_ticks, 70)

func test_is_not_expired_at_exactly_zero_patience() -> void:
	# The intra-tick order is deliver -> expire, so a passenger reaching
	# exactly 0 on the tick its doors open is DELIVERED and pays.
	var p := make_p(0, 5, 10)
	p.decay(10)
	assert_eq(p.patience_ticks, 0)
	assert_false(p.is_expired(), "zero is not yet expired")

func test_is_expired_below_zero() -> void:
	var p := make_p(0, 5, 10)
	p.decay(11)
	assert_true(p.is_expired())

func test_patience_never_reports_negative_fraction() -> void:
	var p := make_p(0, 5, 10)
	p.decay(50)
	assert_eq(p.patience_fraction(), 0.0, "clamped for the colour ramp")

func test_patience_fraction_is_one_when_fresh() -> void:
	assert_almost_eq(make_p(0, 5, 100).patience_fraction(), 1.0, 1e-9)

func test_direction_is_up_for_ascending_trips() -> void:
	assert_eq(make_p(1, 9).direction(), 1)

func test_direction_is_down_for_descending_trips() -> void:
	assert_eq(make_p(9, 1).direction(), -1)

func test_waited_ticks_counts_time_spent_waiting() -> void:
	var p := make_p(0, 5, 900)
	p.decay(120)
	assert_eq(p.waited_ticks(), 120)

func test_waited_ticks_is_zero_for_a_fresh_passenger() -> void:
	assert_eq(make_p(0, 5, 900).waited_ticks(), 0)

func test_waited_ticks_at_the_zero_patience_boundary() -> void:
	# The passenger delivered on the tick it reaches 0 waited its whole patience.
	var p := make_p(0, 5, 900)
	p.decay(900)
	assert_eq(p.patience_ticks, 0)
	assert_eq(p.waited_ticks(), 900)

func test_waited_ticks_is_clamped_at_zero_for_nonpositive_patience() -> void:
	# _initial_patience is maxi(patience, 1), so a zero-patience passenger reads
	# one tick high. The contract is: meaningful for patience >= 1, never
	# negative, and pinned here rather than left to discovery.
	var p := make_p(0, 5, 0)
	assert_eq(p.waited_ticks(), 1, "documented: one high below the floor")
	p.decay(3)
	assert_eq(p.waited_ticks(), 4, "still one high, and still not negative")

func test_waited_ticks_is_never_negative() -> void:
	# The only way past the floor is a patience the spawner clamps away, but the
	# clamp is the stated half of the contract, so it is asserted.
	var p := make_p(0, 5, 10)
	p.decay(-50)                 # patience above its own initial value
	assert_eq(p.waited_ticks(), 0, "clamped at zero, never negative")
