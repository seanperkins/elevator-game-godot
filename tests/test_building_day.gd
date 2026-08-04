extends GutTest

## The building's day. These pin that the chart is the SAME arithmetic the
## spawner runs -- a picture of traffic that disagrees with the traffic is worse
## than no picture.

func _kind(id: String, rate: Array, inbound: Array, outbound: Array) -> TenantKind:
	var k := TenantKind.new()
	k.id = id
	k.display_name = id
	k.rate = PackedFloat32Array(rate)
	k.inbound = PackedFloat32Array(inbound)
	k.outbound = PackedFloat32Array(outbound)
	return k

## A kind whose every hour is the same, so the arithmetic is readable.
func _flat(id: String, rate: float, inbound: float, outbound: float) -> TenantKind:
	var r := []
	var i := []
	var o := []
	for _h in range(TenantKind.BUCKETS):
		r.append(rate)
		i.append(inbound)
		o.append(outbound)
	return _kind(id, r, i, o)

func _sources(specs: Array) -> Array[TrafficSource]:
	var out: Array[TrafficSource] = []
	for s in specs:
		out.append(TrafficSource.new(s[0], s[1], 1.0))
	return out

func test_an_empty_building_has_a_flat_empty_day() -> void:
	var rates := BuildingDay.rates([] as Array[TrafficSource])
	assert_eq(rates.size(), TenantKind.BUCKETS, "always 24 buckets")
	for r in rates:
		assert_almost_eq(r, 0.0, 0.0001)
	assert_almost_eq(BuildingDay.peak([] as Array[TrafficSource]), 0.0, 0.0001)

func test_the_day_is_the_sum_of_its_floors() -> void:
	# The spawner does `total += s.rate_at(minute)`; so does this.
	var s := _sources([[1, _flat("a", 2.0, 0.5, 0.5)], [2, _flat("b", 3.0, 0.5, 0.5)]])
	for r in BuildingDay.rates(s):
		assert_almost_eq(r, 5.0, 0.0001, "two floors at 2 and 3 make 5")
	assert_almost_eq(BuildingDay.peak(s), 5.0, 0.0001)

func test_the_shape_survives_the_sum() -> void:
	# One floor peaking at 08:00 and another at 18:00 must produce a day with
	# BOTH peaks -- that is the entire point of amalgamating.
	var morning := []
	var evening := []
	for h in range(TenantKind.BUCKETS):
		morning.append(10.0 if h == 8 else 1.0)
		evening.append(10.0 if h == 18 else 1.0)
	var half := []
	for _h in range(TenantKind.BUCKETS):
		half.append(0.5)
	var s := _sources([
		[1, _kind("m", morning, half, half)],
		[2, _kind("e", evening, half, half)]])
	var r := BuildingDay.rates(s)
	assert_almost_eq(r[8], 11.0, 0.0001, "the morning spike survives")
	assert_almost_eq(r[18], 11.0, 0.0001, "and so does the evening one")
	assert_almost_eq(r[12], 2.0, 0.0001, "midday is the quiet sum")

func test_the_mix_is_weighted_by_rate_not_by_floor_count() -> void:
	# A floor generating ten trips a minute must dominate one generating one.
	# Averaging per floor would report a 50/50 building that does not exist.
	var loud := _flat("loud", 10.0, 1.0, 0.0)     # all inbound
	var quiet := _flat("quiet", 1.0, 0.0, 1.0)    # all outbound
	var m := BuildingDay.mix(_sources([[1, loud], [2, quiet]]), 8, true)
	assert_almost_eq(m.x, 10.0 / 11.0, 0.001, "inbound share follows the volume")
	assert_almost_eq(m.y, 1.0 / 11.0, 0.001)

func test_the_mix_sums_to_one_when_anything_is_running() -> void:
	var m := BuildingDay.mix(_sources([[1, _flat("a", 4.0, 0.3, 0.2)]]), 0, true)
	assert_almost_eq(m.x + m.y + m.z, 1.0, 0.0001)

func test_an_empty_building_has_no_mix_rather_than_a_third_each() -> void:
	# ZERO, not (1/3, 1/3, 1/3): "nothing is happening" and "an even mix" are
	# different statements, and the widget draws them differently.
	assert_eq(BuildingDay.mix([] as Array[TrafficSource], 8, true), Vector3.ZERO)

func test_a_vacant_lobby_collapses_every_trip_to_interfloor() -> void:
	# The spawner's rule: without a usable lobby there is no inbound or outbound
	# endpoint, so the whole building's traffic is interfloor.
	var s := _sources([[3, _flat("a", 4.0, 1.0, 0.0)]])
	var m := BuildingDay.mix(s, 8, false)
	assert_almost_eq(m.z, 1.0, 0.0001, "all interfloor")
	assert_almost_eq(m.x, 0.0, 0.0001, "nothing is inbound to a vacant lobby")

func test_a_tenant_on_the_lobby_is_interfloor_even_when_the_lobby_is_tenanted() -> void:
	# Its lobby trips would run lobby -> lobby. The spawner excludes it with
	# `chosen.floor_index != LOBBY`, and so does this.
	var s := _sources([[DispatchPolicy.LOBBY, _flat("shops", 4.0, 1.0, 0.0)]])
	assert_almost_eq(BuildingDay.mix(s, 8, true).z, 1.0, 0.0001)

func test_the_mix_ignores_hours_a_floor_generates_nothing_in() -> void:
	var night := []
	var day := []
	var one := []
	var zero := []
	for h in range(TenantKind.BUCKETS):
		night.append(0.0 if h == 8 else 5.0)
		day.append(5.0 if h == 8 else 0.0)
		one.append(1.0)
		zero.append(0.0)
	# At hour 8 only the second floor is generating, and it is all inbound.
	var s := _sources([
		[1, _kind("night", night, zero, one)],
		[2, _kind("day", day, one, zero)]])
	var m := BuildingDay.mix(s, 8, true)
	assert_almost_eq(m.x, 1.0, 0.0001, "the sleeping floor must not vote")
