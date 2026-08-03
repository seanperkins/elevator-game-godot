extends GutTest

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

func test_a_trip_must_go_somewhere() -> void:
	# Was :71. The only guard against a degenerate lobby-to-lobby trip, which
	# is exactly what the floor-0 collapse rule exists to prevent.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var s := TrafficSpawner.new(31)
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(4, cat.kind("apartments"), 1.0),
	]
	for tick in range(20000):
		for p in s.spawn_from_sources(12, sources, true):
			assert_ne(p.origin_row, p.destination_row)

func test_the_spawn_threshold_is_one_bucket_not_one_real_minute() -> void:
	# Two apartment sources at bucket 6 sum to 2 x 0.5 = 1.0 trips/bucket, so
	# the per-tick threshold is 1.0 / TICKS_PER_SIM_MINUTE. At 600 that is
	# 0.001667; at a real minute's 1200 it would be 0.000833. A draw of 0.001
	# therefore spawns under the correct denominator and does NOT under the
	# stale one -- which is exactly the mistake this pins. Halving the bucket
	# length while leaving the spawner dividing by a real minute changes
	# nothing at all: the day and the day's traffic scale together.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_eq(apt.rate_at(6), 0.5, "the fixture this test's arithmetic rests on")

	var sources := _sources(2, apt)

	var below := TrafficSpawner.new(1)
	below.rng = CountingRng.new(0.001)
	assert_eq(below.spawn_from_sources(6, sources, true).size(), 1,
		"0.001 is under 1.0/600 and must spawn")

	var above := TrafficSpawner.new(1)
	above.rng = CountingRng.new(0.002)
	assert_eq(above.spawn_from_sources(6, sources, true).size(), 0,
		"0.002 is over 1.0/600 and must not")

func test_rush_hour_generates_more_than_the_overnight_trough() -> void:
	# Was :22, which used the deleted rate_at_minute. The property is worth
	# keeping; the symbol is not.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_gt(apt.rate_at(7), apt.rate_at(2))

func test_the_curve_wraps_around_the_day() -> void:
	# Was :19, which compared rate_at_minute(8) with ITSELF and could not
	# fail. Its NAME claimed piecewise-constancy within a bucket, but under
	# one-bucket-per-hour with an integer minute index there are no minutes
	# "inside" a bucket to be constant across -- the property has no referent,
	# which is presumably how it decayed into a tautology unnoticed.
	#
	# What is actually worth pinning at that boundary is the wrap, so this
	# carries :19 across as the check it can meaningfully make.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_almost_eq(apt.rate_at(8), apt.rate_at(8 + 24), 1e-9,
		"the same hour a day later is the same bucket")
	assert_almost_eq(apt.rate_at(0), apt.rate_at(-24), 1e-9,
		"and posmod handles a negative index")
