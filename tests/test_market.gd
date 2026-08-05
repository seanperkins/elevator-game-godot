extends GutTest

const SEED := 12345

var tenancy: Tenancy
var fitout: Fitout
var catalog: TenantCatalog
var market: Market

func before_each() -> void:
	var index := FloorIndex.new(0, 6)
	tenancy = Tenancy.new(index, 6)
	fitout = Fitout.new(index)
	catalog = TenantCatalog.new()
	assert_true(catalog.load_from("res://data/tenants.json"))
	market = Market.new(SEED)

func _vacate(floor_index: int) -> void:
	tenancy.restore_floor(floor_index, 1.0, true, 0)

func _step() -> void:
	market.step(tenancy, fitout, catalog, 6)

func test_a_vacant_floor_fills_exactly_fill_ticks_after_first_sighting() -> void:
	_vacate(3)
	_step()
	assert_eq(market.fill_ticks_left(3), Market.FILL_TICKS, "sighting tick arms the clock")
	for i in range(Market.FILL_TICKS - 1):
		_step()
	assert_true(tenancy.is_vacant(3), "one tick early is still vacant")
	_step()
	assert_false(tenancy.is_vacant(3))
	assert_ne(tenancy.kind_at(3), "")
	assert_eq(market.fill_ticks_left(3), 0)

func test_a_filled_floor_arrives_content() -> void:
	_vacate(3)
	_step()
	for i in range(Market.FILL_TICKS):
		_step()
	assert_almost_eq(tenancy.satisfaction_at(3), 1.0, 1e-9)
	assert_false(tenancy.is_moving_out(3))

func test_a_tenanted_floor_never_gets_a_countdown() -> void:
	_step()
	for f in range(6):
		assert_eq(market.fill_ticks_left(f), 0)

func test_a_floor_tenanted_by_other_means_drops_its_countdown() -> void:
	_vacate(3)
	_step()
	tenancy.lease(3, "shops")
	_step()
	assert_eq(market.fill_ticks_left(3), 0, "the scan self-heals")

func test_the_draw_respects_the_floors_class() -> void:
	for i in range(200):
		var k := catalog.kind(market.draw_kind(1, catalog))
		assert_eq(k.requires_class, 1)

func test_the_draw_leans_toward_the_top_tier() -> void:
	var top := 0
	for i in range(300):
		if catalog.kind(market.draw_kind(3, catalog)).requires_class == 3:
			top += 1
	# weights 9/9/3/3/1/1 -> expected ~69%. Seeded, so the count is run-stable.
	assert_between(top, 150, 260)

func test_basement_kinds_never_appear_in_a_tower_draw() -> void:
	for i in range(200):
		assert_ne(market.draw_kind(3, catalog), "parking")

func test_same_seed_same_sequence() -> void:
	var a := Market.new(SEED)
	var b := Market.new(SEED)
	for i in range(20):
		assert_eq(a.draw_kind(3, catalog), b.draw_kind(3, catalog))

func test_the_tier_is_read_at_fill_time_not_vacancy_time() -> void:
	var above_one := 0
	for trial in range(20):
		var index := FloorIndex.new(0, 6)
		tenancy = Tenancy.new(index, 6)
		fitout = Fitout.new(index)
		market = Market.new(SEED + trial)
		_vacate(3)
		_step()                       # countdown armed while the floor is class 1
		fitout.set_tier(3, 3)         # upgraded mid-countdown
		for i in range(Market.FILL_TICKS):
			_step()
		if catalog.kind(tenancy.kind_at(3)).requires_class > 1:
			above_one += 1
	assert_gt(above_one, 0, "a mid-countdown upgrade improves the pending draw")

func test_restore_floor_resumes_a_partial_countdown() -> void:
	_vacate(3)
	market.restore_floor(3, 5)
	for i in range(4):
		_step()
	assert_true(tenancy.is_vacant(3))
	_step()
	assert_false(tenancy.is_vacant(3))
