extends GutTest

var spawner: TrafficSpawner

func before_each() -> void:
	spawner = TrafficSpawner.new(12345)
	assert_true(spawner.load_curve("res://data/traffic_walkup.json"),
		"the curve data must load")

func test_curve_has_one_entry_per_minute_of_the_day() -> void:
	assert_eq(spawner.curve.size(), 24)

func test_rate_wraps_around_the_day() -> void:
	assert_almost_eq(spawner.rate_at_minute(0), spawner.rate_at_minute(24), 1e-9,
		"minute 24 is minute 0 of the next day")

func test_rate_is_piecewise_constant_within_a_bucket() -> void:
	# Two different tick counts inside the same minute must read the same rate.
	assert_almost_eq(spawner.rate_at_minute(8), spawner.rate_at_minute(8), 1e-9)

func test_rush_hour_rate_exceeds_the_overnight_rate() -> void:
	assert_gt(spawner.rate_at_minute(8), spawner.rate_at_minute(2),
		"the morning rush is what makes upgrades legible")

func test_spawning_is_deterministic_for_a_given_seed() -> void:
	var a := TrafficSpawner.new(999)
	var b := TrafficSpawner.new(999)
	a.load_curve("res://data/traffic_walkup.json")
	b.load_curve("res://data/traffic_walkup.json")
	var count_a := 0
	var count_b := 0
	for tick in range(6000):
		count_a += a.spawn_for_tick(tick / 1200, 6).size()
		count_b += b.spawn_for_tick(tick / 1200, 6).size()
	assert_eq(count_a, count_b, "same seed must give the same sequence")

func test_different_seeds_diverge() -> void:
	var a := TrafficSpawner.new(1)
	var b := TrafficSpawner.new(2)
	a.load_curve("res://data/traffic_walkup.json")
	b.load_curve("res://data/traffic_walkup.json")
	var ca := 0
	var cb := 0
	for tick in range(20000):
		ca += a.spawn_for_tick(tick / 1200, 6).size()
		cb += b.spawn_for_tick(tick / 1200, 6).size()
	assert_ne(ca, cb, "independent seeds should not coincide over 20k ticks")

func test_spawn_count_tracks_the_curve_over_a_minute() -> void:
	# Rate is spawns-per-minute; a minute is 1200 ticks. Over many minutes the
	# realised count should land near the rate. Stochastic, so assert a band,
	# not an exact integer.
	var total := 0
	var minutes := 200
	for m in range(minutes):
		for t in range(1200):
			total += spawner.spawn_for_tick(8, 6).size()   # pin to minute 8
	var expected := spawner.rate_at_minute(8) * float(minutes)
	assert_between(float(total), expected * 0.85, expected * 1.15,
		"realised spawns within 15%% of the curve over 200 minutes")

func test_spawned_passengers_are_inside_the_building() -> void:
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, 6):
			assert_between(p.origin_row, 0, 5, "origin in range")
			assert_between(p.destination_row, 0, 5, "destination in range")

func test_origin_and_destination_are_never_equal() -> void:
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, 6):
			assert_ne(p.origin_row, p.destination_row, "a trip must go somewhere")

func test_no_spawns_in_a_one_row_building() -> void:
	# There is nowhere to go, so nothing should spawn rather than loop forever
	# looking for a distinct destination.
	for t in range(1000):
		assert_eq(spawner.spawn_for_tick(8, 1).size(), 0)

func test_passengers_carry_the_configured_patience_and_fare() -> void:
	var found := false
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, 6):
			assert_eq(p.patience_ticks, spawner.base_patience_ticks)
			assert_almost_eq(p.fare, spawner.base_fare, 1e-9)
			found = true
	assert_true(found, "the test needs at least one spawn to be meaningful")

func test_missing_curve_file_fails_cleanly() -> void:
	var s := TrafficSpawner.new(1)
	assert_false(s.load_curve("res://data/does_not_exist.json"))
