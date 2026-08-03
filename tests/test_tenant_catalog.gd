extends GutTest

var cat: TenantCatalog

func before_each() -> void:
	cat = TenantCatalog.new()
	assert_true(cat.load_from("res://data/tenants.json"), "the shipped file loads")

func test_a_class_gates_which_kinds_may_lease() -> void:
	var t1 := cat.available_for_class(1)
	var ids := PackedStringArray()
	for k in t1:
		ids.append(k.id)
	assert_eq(ids.size(), 2, "class 1 offers exactly the tier-1 kinds")
	assert_true(ids.has("apartments") and ids.has("shops"))
	assert_eq(cat.available_for_class(3).size(), 6, "class 3 offers everything")

func test_the_starting_roster_totals_the_shipped_curve() -> void:
	# spec §5.6: the opening's daily VOLUME is pinned even though its shape
	# deliberately changes. 1 Shops + 5 Apartments must total what
	# data/traffic_walkup.json totalled: 47.4 trips per simulated day.
	var apartments := 0.0
	var shops := 0.0
	for h in range(24):
		apartments += cat.kind("apartments").rate_at(h)
		shops += cat.kind("shops").rate_at(h)
	assert_almost_eq(5.0 * apartments + shops, 47.4, 1e-4)

func test_offices_are_inbound_at_eight_and_apartments_outbound_at_seven() -> void:
	# The mirror is the whole point of the feature, so it is asserted
	# directly rather than inferred from a total. Each kind is pinned at the
	# hour ITS OWN curve peaks -- apartments are on a falling shoulder by 8.
	var office := cat.kind("office")
	assert_gt(office.inbound_at(8), office.outbound_at(8) * 3.0)
	var apt := cat.kind("apartments")
	assert_gt(apt.outbound_at(7), apt.inbound_at(7) * 3.0)

func test_the_total_rate_cannot_saturate_the_bernoulli_trial() -> void:
	# spec §5.6: the spawner clips silently at p = 1 and emits at most one
	# passenger per tick. MAX_FLOORS x the largest single bucket is the
	# worst case, exhaustive by construction -- "every kind combination" is
	# 6^40 and is not a writable test.
	assert_lt(float(Building.MAX_FLOORS) * cat.largest_bucket(),
		float(SimClock.TICKS_PER_SIM_MINUTE))

func _catalog_from(data: Dictionary) -> TenantCatalog:
	var c := TenantCatalog.new()
	var path := "user://test_tenants_%d.json" % randi()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var ok := c.load_from(path)
	DirAccess.remove_absolute(path)
	return c if ok else null

func _valid_kind(overrides: Dictionary) -> Dictionary:
	var k := {
		"id": "k1", "name": "K1", "requires_class": 1,
		"lease_cost": 10.0, "base_fare": 1.0,
		"rate": [], "inbound": [], "outbound": [],
	}
	for h in range(24):
		(k["rate"] as Array).append(0.1)
		(k["inbound"] as Array).append(0.3)
		(k["outbound"] as Array).append(0.3)
	for key in overrides:
		k[key] = overrides[key]
	return k

const _CLASSES := [
	{ "tier": 1, "cost": 0, "fare_multiplier": 1.0 },
]

func test_a_negative_class_cost_is_refused() -> void:
	# The one malformed case that CREDITS the player instead of crashing:
	# can_afford(-400) is true and spend runs cash -= -400.
	assert_null(_catalog_from({
		"classes": [{ "tier": 1, "cost": -400, "fare_multiplier": 1.0 }],
		"kinds": [_valid_kind({})],
	}))

func test_an_impossible_direction_mix_is_refused() -> void:
	# inbound + outbound > 1 makes the interfloor remainder negative, which
	# feeds a weighted pick -- silent, unlike every other malformed case.
	var bad := []
	for h in range(24):
		bad.append(0.8)
	assert_null(_catalog_from({
		"classes": _CLASSES,
		"kinds": [_valid_kind({ "inbound": bad, "outbound": bad })],
	}))

func test_a_catalog_with_no_tier_one_kind_is_refused() -> void:
	# Otherwise the no-fail guarantee selects from an empty set.
	assert_null(_catalog_from({
		"classes": [
			{ "tier": 1, "cost": 0, "fare_multiplier": 1.0 },
			{ "tier": 2, "cost": 400, "fare_multiplier": 1.35 },
		],
		"kinds": [_valid_kind({ "requires_class": 2 })],
	}))

func test_a_short_bucket_array_is_refused() -> void:
	assert_null(_catalog_from({
		"classes": _CLASSES,
		"kinds": [_valid_kind({ "rate": [0.1, 0.1, 0.1] })],
	}))
