extends GutTest

var f: Fitout

func before_each() -> void:
	f = Fitout.new(6)

func test_every_floor_starts_at_tier_one() -> void:
	for floor_index in range(6):
		assert_eq(f.tier_at(floor_index), 1)

func test_a_new_row_starts_at_tier_one() -> void:
	f.add_floor()
	assert_eq(f.floors(), 7)
	assert_eq(f.tier_at(6), 1)

func test_setting_a_tier_moves_the_revision() -> void:
	var before := f.revision()
	f.set_tier(2, 3)
	assert_eq(f.tier_at(2), 3)
	assert_ne(f.revision(), before, "a class purchase must invalidate the cache")

func test_an_out_of_range_row_reads_tier_one_and_writes_nothing() -> void:
	assert_eq(f.tier_at(99), 1)
	var before := f.revision()
	f.set_tier(99, 3)
	assert_eq(f.revision(), before)
