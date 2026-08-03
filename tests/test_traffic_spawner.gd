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
		count_a += a.spawn_for_tick(tick / 1200, PackedInt32Array([0, 1, 2, 3, 4, 5])).size()
		count_b += b.spawn_for_tick(tick / 1200, PackedInt32Array([0, 1, 2, 3, 4, 5])).size()
	assert_eq(count_a, count_b, "same seed must give the same sequence")

func test_different_seeds_diverge() -> void:
	var a := TrafficSpawner.new(1)
	var b := TrafficSpawner.new(2)
	a.load_curve("res://data/traffic_walkup.json")
	b.load_curve("res://data/traffic_walkup.json")
	var ca := 0
	var cb := 0
	for tick in range(20000):
		ca += a.spawn_for_tick(tick / 1200, PackedInt32Array([0, 1, 2, 3, 4, 5])).size()
		cb += b.spawn_for_tick(tick / 1200, PackedInt32Array([0, 1, 2, 3, 4, 5])).size()
	assert_ne(ca, cb, "independent seeds should not coincide over 20k ticks")

func test_spawn_count_tracks_the_curve_over_a_minute() -> void:
	# Rate is spawns-per-minute; a minute is 1200 ticks. Over many minutes the
	# realised count should land near the rate. Stochastic, so assert a band,
	# not an exact integer.
	var total := 0
	var minutes := 200
	for m in range(minutes):
		for t in range(1200):
			total += spawner.spawn_for_tick(8, PackedInt32Array([0, 1, 2, 3, 4, 5])).size()   # pin to minute 8
	var expected := spawner.rate_at_minute(8) * float(minutes)
	assert_between(float(total), expected * 0.85, expected * 1.15,
		"realised spawns within 15%% of the curve over 200 minutes")

func test_spawned_passengers_are_inside_the_building() -> void:
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, PackedInt32Array([0, 1, 2, 3, 4, 5])):
			assert_between(p.origin_row, 0, 5, "origin in range")
			assert_between(p.destination_row, 0, 5, "destination in range")

func test_origin_and_destination_are_never_equal() -> void:
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, PackedInt32Array([0, 1, 2, 3, 4, 5])):
			assert_ne(p.origin_row, p.destination_row, "a trip must go somewhere")

func test_no_spawns_without_two_tenanted_floors() -> void:
	# Traffic comes from tenants, and a trip needs an origin AND a destination,
	# so one occupied floor generates exactly as much as none.
	for t in range(1000):
		assert_eq(spawner.spawn_for_tick(8, PackedInt32Array([0])).size(), 0)

func test_passengers_carry_the_configured_patience_and_fare() -> void:
	var found := false
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, PackedInt32Array([0, 1, 2, 3, 4, 5])):
			assert_eq(p.patience_ticks, spawner.base_patience_ticks)
			assert_almost_eq(p.fare, spawner.base_fare, 1e-9)
			found = true
	assert_true(found, "the test needs at least one spawn to be meaningful")

func test_missing_curve_file_fails_cleanly() -> void:
	var s := TrafficSpawner.new(1)
	assert_false(s.load_curve("res://data/does_not_exist.json"))

func test_patience_is_floored_at_one_tick() -> void:
	# waited_ticks()'s contract needs initial patience >= 1, and the curve file
	# is data. A zero in data must not silently break the metric.
	var f := FileAccess.open("user://zero_patience.json", FileAccess.WRITE)
	f.store_string('{"buckets":[5.0],"base_patience_ticks":0,"base_fare":4.0}')
	f.close()
	var s := TrafficSpawner.new(7)
	assert_true(s.load_curve("user://zero_patience.json"))
	assert_eq(s.base_patience_ticks, 1, "clamped, not zero")


func test_only_tenanted_floors_generate_or_receive_trips() -> void:
	# A vacant floor is nobody to carry. This is what makes losing a tenant
	# cost money now that rent is gone.
	var occupied := PackedInt32Array([0, 3, 5])
	var seen := {}
	for t in range(4000):
		for p in spawner.spawn_for_tick(8, occupied):
			seen[p.origin_row] = true
			seen[p.destination_row] = true
	assert_false(seen.has(1), "floor 1 is vacant and must not appear")
	assert_false(seen.has(2), "nor floor 2")
	assert_false(seen.has(4), "nor floor 4")
	assert_true(seen.has(0) and seen.has(3) and seen.has(5),
		"the tenanted floors do carry traffic")

func test_an_empty_building_generates_nothing() -> void:
	for t in range(500):
		assert_eq(spawner.spawn_for_tick(8, PackedInt32Array()).size(), 0)

func test_traffic_grows_with_the_number_of_tenants() -> void:
	# With rent gone this is the ONLY reason to build a floor: a new tenant is
	# new people making trips. Without it a tall building carries no more than a
	# short one, just over longer distances.
	var small := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var large := PackedInt32Array()
	for f in range(24):
		large.append(f)
	var a := TrafficSpawner.new(31337)
	var b := TrafficSpawner.new(31337)
	a.load_curve("res://data/traffic_walkup.json")
	b.load_curve("res://data/traffic_walkup.json")
	var small_total := 0
	var large_total := 0
	for t in range(1200 * 20):
		small_total += a.spawn_for_tick(8, small).size()
		large_total += b.spawn_for_tick(8, large).size()
	assert_gt(large_total, small_total * 2,
		"four times the tenants must carry substantially more traffic")

func test_the_shipped_six_floor_start_matches_the_curve_exactly() -> void:
	# REFERENCE_ROWS is 6, so a new game behaves precisely as the data says and
	# the curve file keeps its stated meaning.
	var floors := PackedInt32Array([0, 1, 2, 3, 4, 5])
	assert_eq(TrafficSpawner.REFERENCE_ROWS, floors.size())
	var total := 0
	var minutes := 200
	for m in range(minutes):
		for t in range(1200):
			total += spawner.spawn_for_tick(8, floors).size()
	var expected := spawner.rate_at_minute(8) * float(minutes)
	assert_between(float(total), expected * 0.85, expected * 1.15)

class CountingRng:
	var draws: int = 0
	var _next: float
	func _init(next_value: float) -> void:
		_next = next_value
	func randf() -> float:
		draws += 1
		return _next
	func randi_range(a: int, b: int) -> int:
		draws += 1
		return a

func _sources(n: int, kind: TenantKind) -> Array[TrafficSource]:
	var out: Array[TrafficSource] = []
	for i in range(n):
		out.append(TrafficSource.new(i, kind, 1.0))
	return out

func test_the_draw_count_is_independent_of_source_count() -> void:
	# Pin the BRANCH first: a 40-source building has a larger total and so a
	# larger p, which means a different branch and a different draw count for
	# reasons that have nothing to do with the property being tested. An RNG
	# returning 0.0 makes both take the spawning path (the guard is
	# `if randf() >= per_tick: return`), and only then is a count comparison
	# meaningful.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var kind := cat.kind("apartments")

	var small := TrafficSpawner.new(1)
	small.rng = CountingRng.new(0.0)
	small.spawn_from_sources(8, _sources(6, kind), true)

	var large := TrafficSpawner.new(1)
	large.rng = CountingRng.new(0.0)
	large.spawn_from_sources(8, _sources(40, kind), true)

	assert_eq(large.rng.draws, small.rng.draws,
		"the weighted pick costs a constant number of draws, not one per source")

func test_a_tenanted_lobby_generates_only_interfloor_trips() -> void:
	# The shipped starting building puts Shops on floor 0, so this is the
	# default code path from the first frame -- an inbound trip for floor 0
	# would be lobby -> lobby.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(99)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(3, cat.kind("apartments"), 1.0),
	]
	for tick in range(20000):
		for p in s.spawn_from_sources(9, sources, true):
			if p.source_row == 0:
				assert_ne(p.origin_row, p.destination_row, "a trip must go somewhere")

func test_the_fare_comes_from_the_kind_and_the_floors_class() -> void:
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(7)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(2, cat.kind("office"), 1.8),
		TrafficSource.new(5, cat.kind("office"), 1.8),
	]
	var seen := false
	for tick in range(20000):
		for p in s.spawn_from_sources(8, sources, true):
			assert_almost_eq(p.fare, 4.0 * 1.8, 1e-5)
			seen = true
	assert_true(seen, "the fixture must actually spawn something")
