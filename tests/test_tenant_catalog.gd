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


# --- where a kind belongs, and whether it generates trips --------------------

func test_existing_kinds_default_to_the_tower_and_generate_trips() -> void:
	# The six shipped kinds carry neither field, so the defaults are what keeps
	# this change additive.
	for id in ["apartments", "shops", "office", "gym", "law_firm", "clinic"]:
		var k := cat.kind(id)
		assert_eq(k.where, TenantKind.Where.TOWER, "%s is a tower kind" % id)
		assert_false(k.entrance, "%s generates its own trips" % id)

func test_parking_is_a_basement_entrance_that_generates_nothing() -> void:
	var k := cat.kind("parking")
	assert_not_null(k, "parking is in the catalog")
	assert_eq(k.where, TenantKind.Where.BASEMENT)
	assert_true(k.entrance)
	assert_eq(k.base_fare, 0.0, "a garage earns nothing directly")
	for minute in range(0, 48):
		assert_eq(k.rate_at(minute), 0.0, "an entrance spawns no trips at %d" % minute)
		assert_eq(k.inbound_at(minute), 0.0)
		assert_eq(k.outbound_at(minute), 0.0)

func test_the_tower_picker_does_not_offer_the_garage() -> void:
	# available_for_class feeds BOTH the lease picker and the free-recovery
	# tenant (cheapest_for_class). Unfiltered, a 300-dollar garage undercuts
	# apartments and the no-fail rule starts leasing car parks on tower floors.
	for k in cat.available_for_class(3):
		assert_eq(k.where, TenantKind.Where.TOWER, "%s leaked into the tower picker" % k.id)
	var basement := cat.available_for_class(3, TenantKind.Where.BASEMENT)
	assert_eq(basement.size(), 1, "the basement picker offers exactly parking today")
	assert_eq(basement[0].id, "parking")

func test_the_recovery_tenant_is_never_a_garage() -> void:
	var cheapest := cat.cheapest_for_class(1)
	assert_not_null(cheapest)
	assert_eq(cheapest.where, TenantKind.Where.TOWER,
		"the free recovery tenant must generate traffic, and an entrance cannot")

func _write_catalog(kinds: Array) -> String:
	var path := "user://bad_catalog_%d.json" % randi()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"classes": [{"tier": 1, "cost": 0.0, "fare_multiplier": 1.0}],
		"kinds": kinds}))
	f.close()
	return path

func _full_curves() -> Dictionary:
	var flat := []
	for h in range(24):
		flat.append(0.5)
	var none := []
	for h in range(24):
		none.append(0.1)
	return {"rate": flat, "inbound": none, "outbound": none}

func test_an_entrance_carrying_curves_is_fatal() -> void:
	# tenants.json is fatal-if-malformed, and the two shapes must not blur: an
	# entrance with a rate array would spawn trips TO a car park.
	var c := _full_curves()
	var bad := TenantCatalog.new()
	assert_false(bad.load_from(_write_catalog([
		{"id": "a", "name": "A", "requires_class": 1, "lease_cost": 1.0,
			"base_fare": 3.0, "rate": c["rate"], "inbound": c["inbound"],
			"outbound": c["outbound"]},
		{"id": "x", "name": "X", "entrance": true, "where": "basement",
			"requires_class": 1, "lease_cost": 1.0, "base_fare": 0.0,
			"rate": c["rate"], "inbound": c["inbound"], "outbound": c["outbound"]},
	])), "an entrance with curves must be refused")

func test_a_source_with_empty_curves_is_fatal() -> void:
	# The other direction, because a one-way check passes vacuously against the
	# file that ships.
	var c := _full_curves()
	var bad := TenantCatalog.new()
	assert_false(bad.load_from(_write_catalog([
		{"id": "a", "name": "A", "requires_class": 1, "lease_cost": 1.0,
			"base_fare": 3.0, "rate": c["rate"], "inbound": c["inbound"],
			"outbound": c["outbound"]},
		{"id": "x", "name": "X", "requires_class": 1, "lease_cost": 1.0,
			"base_fare": 3.0, "rate": [], "inbound": [], "outbound": []},
	])), "a source with no curves must be refused")

func test_an_entrance_charging_a_fare_is_fatal() -> void:
	# An entrance generates no trips, so its fare could never be charged -- a
	# nonzero one is a data error hiding, not a tuning knob.
	var bad := TenantCatalog.new()
	var c := _full_curves()
	assert_false(bad.load_from(_write_catalog([
		{"id": "a", "name": "A", "requires_class": 1, "lease_cost": 1.0,
			"base_fare": 3.0, "rate": c["rate"], "inbound": c["inbound"],
			"outbound": c["outbound"]},
		{"id": "x", "name": "X", "entrance": true, "where": "basement",
			"requires_class": 1, "lease_cost": 1.0, "base_fare": 2.0,
			"rate": [], "inbound": [], "outbound": []},
	])), "an entrance with a fare must be refused")
