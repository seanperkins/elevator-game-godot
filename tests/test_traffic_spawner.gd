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
	small.spawn_from_sources(8, _sources(6, kind), true, PackedInt32Array())

	var large := TrafficSpawner.new(1)
	large.rng = CountingRng.new(0.0)
	large.spawn_from_sources(8, _sources(40, kind), true, PackedInt32Array())

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
		for p in s.spawn_from_sources(9, sources, true, PackedInt32Array()):
			if p.source_floor == 0:
				assert_ne(p.origin_floor, p.destination_floor, "a trip must go somewhere")

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
		for p in s.spawn_from_sources(8, sources, true, PackedInt32Array()):
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
		for p in s.spawn_from_sources(12, sources, true, PackedInt32Array()):
			assert_ne(p.origin_floor, p.destination_floor)

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
	assert_eq(below.spawn_from_sources(6, sources, true, PackedInt32Array()).size(), 1,
		"0.001 is under 1.0/600 and must spawn")

	var above := TrafficSpawner.new(1)
	above.rng = CountingRng.new(0.002)
	assert_eq(above.spawn_from_sources(6, sources, true, PackedInt32Array()).size(), 0,
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

func test_an_inbound_trip_is_flagged_not_encoded_as_floor_minus_one() -> void:
	# _destination_for returned -1 to mean "inbound, swap the endpoints". That
	# was safe only while floors started at 0. The FIRST floor dug is -1, so the
	# sentinel becomes a real destination and inbound traffic silently starts
	# delivering people INTO the basement. The flag is separate now.
	var sp := TrafficSpawner.new(1)
	assert_true(sp.load_curve("res://data/traffic_walkup.json"), "curve loads")
	var cat := TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"), "catalog loads")
	var sources: Array[TrafficSource] = [
		TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(4, cat.kind("office"), 1.0),
	]
	var saw_inbound := false
	for minute in range(0, 48):
		var d := sp._destination_for(sources[1], sources, minute, true, false)
		assert_between(d.y, 0, 2, "the flag is a flag")
		if d.y == 1:
			saw_inbound = true
			assert_ne(d.x, -1, "an inbound trip must not encode itself as floor -1")
	assert_true(saw_inbound, "the office takes inbound trips at some hour")


# --- the second entrance -----------------------------------------------------

func _cat() -> TenantCatalog:
	var c := TenantCatalog.new()
	assert_true(c.load_from("res://data/tenants.json"), "catalog loads")
	return c

func _two_tenants(cat: TenantCatalog) -> Array[TrafficSource]:
	return [TrafficSource.new(0, cat.kind("shops"), 1.0),
		TrafficSource.new(4, cat.kind("office"), 1.0)] as Array[TrafficSource]

func test_with_no_entrances_the_spawner_is_bit_identical() -> void:
	# THE additive test: same seed, same sequence, at every minute. Anything this
	# catches is a change to a building that has not dug at all.
	var cat := _cat()
	var a := TrafficSpawner.new(99); assert_true(a.load_curve("res://data/traffic_walkup.json"))
	var b := TrafficSpawner.new(99); assert_true(b.load_curve("res://data/traffic_walkup.json"))
	for minute in range(0, 400):
		var x := a.spawn_from_sources(minute % 48, _two_tenants(cat), true,
			PackedInt32Array())
		var y := b.spawn_from_sources(minute % 48, _two_tenants(cat), true,
			PackedInt32Array())
		assert_eq(x.size(), y.size(), "minute %d" % minute)
		if not x.is_empty():
			assert_eq(x[0].origin_floor, y[0].origin_floor, "same origin at %d" % minute)
			assert_eq(x[0].destination_floor, y[0].destination_floor, "same destination")

func test_the_trial_count_does_not_depend_on_depth() -> void:
	# The seed-sequence property. The rate is scaled INSIDE one trial; a trial
	# per entrance would make the sequence depend on how deep the building is,
	# exactly as a trial per floor would make it depend on how tall.
	var cat := _cat()
	var sp := TrafficSpawner.new(7); assert_true(sp.load_curve("res://data/traffic_walkup.json"))
	var quiet := CountingRng.new(0.99)   # trial always fails: exactly 1 draw/tick
	sp.rng = quiet
	for minute in range(0, 100):
		sp.spawn_from_sources(minute % 48, _two_tenants(cat), true,
			PackedInt32Array([-1, -2, -3]))
	assert_eq(quiet.draws, 100,
		"a tick that spawns nothing costs one draw at any depth")

func test_arrivals_appear_at_the_entrances_and_nowhere_below() -> void:
	var cat := _cat()
	var sp := TrafficSpawner.new(3); assert_true(sp.load_curve("res://data/traffic_walkup.json"))
	var seen := {}
	# Hour 8, the office's inbound peak, hammered: the trial is per TICK and a
	# sim minute is 600 of them, so a spread over the day spawns too few trips
	# to see a 23% door share.
	for i in range(40000):
		for p in sp.spawn_from_sources(8, _two_tenants(cat), true,
				PackedInt32Array([-1, -2])):
			seen[p.origin_floor] = true
			assert_gte(p.origin_floor, -2, "never below the bottom entrance")
	assert_true(seen.has(-1), "the first garage takes arrivals")
	assert_true(seen.has(-2), "so does the second")

func test_an_arrival_is_credited_to_the_floor_that_generated_it() -> void:
	# The project invariant: income follows source_floor, not the endpoint.
	var cat := _cat()
	var sp := TrafficSpawner.new(11); assert_true(sp.load_curve("res://data/traffic_walkup.json"))
	for i in range(20000):
		for p in sp.spawn_from_sources(8, _two_tenants(cat), true,
				PackedInt32Array([-1])):
			if p.origin_floor == -1:
				assert_ne(p.source_floor, -1,
					"the garage did not generate this trip, the tenant did")

func test_a_vacant_lobby_collapses_lobby_trips_but_not_garage_ones() -> void:
	# The exception, both directions of travel. A driver parks at -1 and rides
	# up; a leaver rides down and drives away. Neither needs a lobby tenant, so
	# parking keeps a building earning with floor 0 unleased.
	var cat := _cat()
	var sources: Array[TrafficSource] = [
		TrafficSource.new(4, cat.kind("office"), 1.0),
		TrafficSource.new(6, cat.kind("gym"), 1.0)]
	var sp := TrafficSpawner.new(5); assert_true(sp.load_curve("res://data/traffic_walkup.json"))
	var via_garage := 0
	var via_lobby := 0
	for i in range(20000):
		for p in sp.spawn_from_sources(8, sources, false,
				PackedInt32Array([-1])):
			if p.origin_floor == -1 or p.destination_floor == -1:
				via_garage += 1
			elif p.origin_floor == 0 or p.destination_floor == 0:
				via_lobby += 1
	assert_gt(via_garage, 0, "garage trips survive a vacant lobby")
	assert_eq(via_lobby, 0, "lobby trips do not")

func test_a_leaver_exits_through_the_garage_when_the_lobby_is_vacant() -> void:
	# Outbound gets the door draw too. Without it, "parking keeps the building
	# earning" holds for arrivals while leavers are still shipped to a vacant
	# lobby -- half the exception, silently.
	var cat := _cat()
	var sources: Array[TrafficSource] = [
		TrafficSource.new(4, cat.kind("apartments"), 1.0),
		TrafficSource.new(6, cat.kind("apartments"), 1.0)]
	var sp := TrafficSpawner.new(17); assert_true(sp.load_curve("res://data/traffic_walkup.json"))
	var exits := 0
	# Hour 7, the apartments' outbound peak.
	for i in range(20000):
		for p in sp.spawn_from_sources(7, sources, false,
				PackedInt32Array([-1])):
			assert_ne(p.destination_floor, 0, "no trip may end at a vacant lobby")
			if p.destination_floor == -1:
				exits += 1
	assert_gt(exits, 0, "apartments generate leavers, and they leave via the garage")
