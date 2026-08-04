extends GutTest

## The car's geometry, headless. Every number here is from the design spec's
## 4.2 table, which was derived against a 220-unit car -- SHAFT_WIDTH 230 less 4
## for the column and 6 for the car.

const W := 220.0
const H := 116.0

func test_one_rank_up_to_five_then_two() -> void:
	for cap in [4, 5]:
		assert_eq(CarRack.ranks_for(cap, H), 1, "capacity %d is one rank" % cap)
	for cap in [6, 8, 12]:
		assert_eq(CarRack.ranks_for(cap, H), 2, "capacity %d is two ranks" % cap)

func test_the_front_rank_takes_the_extra_rider() -> void:
	assert_eq(CarRack.front_count(7, W, 2), 4, "4 front, 3 behind")
	assert_eq(CarRack.front_count(9, W, 2), 5)
	assert_eq(CarRack.front_count(11, W, 2), 6)

func test_the_cell_matches_the_spec_table_at_every_capacity() -> void:
	# The budget INCLUDES the half-pitch offset, which is what an earlier draft
	# left out -- its back rank left the car by 15 units at capacity 10.
	var want := {4: 40.0, 5: 40.0, 6: 40.0, 7: 40.0, 8: 40.0,
		9: 36.73, 10: 36.73, 11: 30.46, 12: 30.46}
	for cap in want:
		assert_almost_eq(CarRack.cell_width(cap, W, CarRack.ranks_for(cap, H)),
			want[cap], 0.01, "cell at capacity %d" % cap)

func test_nothing_is_drawn_outside_the_car_at_any_capacity() -> void:
	# Not a sample of two. Capacity 10 is the case an earlier draft overflowed
	# while appearing in no test at all.
	for cap in range(4, 13):
		for r in CarRack.slots(cap, W, H):
			assert_gte(r.position.x, -0.01, "capacity %d slot starts left of the car" % cap)
			assert_lte(r.end.x, W + 0.01, "capacity %d slot ends right of the car" % cap)
			assert_gte(r.position.y, -0.01, "capacity %d slot above the car" % cap)
			assert_lte(r.end.y, H + 0.01, "capacity %d slot below the car" % cap)

func test_every_rider_gets_a_slot() -> void:
	for cap in range(4, 13):
		assert_eq(CarRack.slots(cap, W, H).size(), cap,
			"capacity %d must have %d slots" % [cap, cap])

func test_the_back_rank_is_offset_half_a_pitch() -> void:
	var s := CarRack.slots(8, W, H)
	var cell := CarRack.cell_width(8, W, 2)
	# front is 0..3, back is 4..7
	assert_almost_eq(s[4].position.x - s[0].position.x,
		(cell + CarRack.GAP) * 0.5, 0.01, "a back figure sits between two front ones")
	assert_lt(s[4].position.y, s[0].position.y, "the back rank is higher")

func test_a_two_digit_badge_fits_the_narrowest_cell() -> void:
	# Capacity 12 is the tight row: its width-derived font is exactly 24. The
	# real fallback font renders "19" at font 24 as 27.0 units -- 1.125 em, not
	# the nominal 1.1 em -- so the 2-unit-per-side padding (31 total) no longer
	# clears a 30.46-unit cell. The spec's FIRST fallback applies: padding drops
	# to 1 unit a side (29 total), which clears with 1.46 units spare. The glyph
	# is centred in the badge, so the slack is 1.73 units a side, not 1.
	var cell := CarRack.cell_width(12, W, 2)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("19", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	assert_lte(w + 2.0, cell, "two digits at font 24 must fit a %.2f-unit cell" % cell)

func test_pips_are_one_per_seat_and_sized_to_the_car() -> void:
	assert_eq(CarRack.pips(4, W).size(), 4)
	assert_eq(CarRack.pips(12, W).size(), 12)
	assert_almost_eq(CarRack.pips(4, W)[0].size.x, 48.75, 0.01)
	assert_almost_eq(CarRack.pips(12, W)[0].size.x, 14.25, 0.01)

func test_pips_have_a_gap_between_them_so_hollows_stay_countable() -> void:
	# Two adjacent hollows on a SHARED track merge into one dark band, which
	# defeats the one question pips exist to answer.
	var p := CarRack.pips(12, W)
	assert_almost_eq(p[1].position.x - p[0].end.x, CarRack.PIP_GAP, 0.01)

func test_a_short_car_drops_to_one_rank_then_to_none() -> void:
	assert_eq(CarRack.ranks_for(12, 113.0), 1, "not enough for two bands")
	assert_eq(CarRack.ranks_for(12, 61.0), 0, "not enough for one")
	assert_eq(CarRack.ranks_for(12, 18.0), 0, "the forced-height fixture")

func test_the_one_rank_band_is_sized_by_width_not_capacity() -> void:
	# One rank of twelve would be 14.7 units a cell -- narrower than the figure.
	assert_eq(CarRack.front_count(12, W, 1), 6, "as many as fit at CELL_MIN")
	assert_eq(CarRack.slots(12, W, 100.0).size(), 6, "the rest go to the header")

func test_pips_survive_every_band_including_a_car_too_short_for_figures() -> void:
	assert_eq(CarRack.pips(4, W).size(), 4, "occupancy stays exact with no picture")

func test_the_bounds_cases_produce_no_layout_rather_than_a_bad_one() -> void:
	assert_eq(CarRack.slots(0, W, H).size(), 0)
	assert_eq(CarRack.pips(0, W).size(), 0)
	assert_eq(CarRack.pips(-3, W).size(), 0)
	# Far past the shipped cap of 12, both representations bow out on a MEASURED
	# floor rather than drawing something illegible.
	assert_eq(CarRack.pips(200, W).size(), 0, "pips below PIP_MIN are not drawn")
	for r in CarRack.slots(40, W, H):
		assert_lte(r.end.x, W + 0.01, "no slot escapes even far past the cap")
