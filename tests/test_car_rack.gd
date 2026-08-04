extends GutTest

## The car's geometry, headless.
##
## ONE rank. A second was built and then removed: a person is 26 x 41, so a band
## is 30 + 41 = 71, and two of those need 142 units in the 106 a 116-unit car has
## after its pip strip. Two ranks only fit figures too small to be worth drawing
## -- at 14 x 22 a person was 7.6 x 12.0pt, shorter than one digit of their own
## badge. The car now does what the hall does: fewer people, drawn properly,
## with the count carrying the rest.

const W := 220.0
const H := 116.0

func test_there_is_one_rank_or_none() -> void:
	for cap in [4, 5, 6, 8, 12]:
		assert_eq(CarRack.ranks_for(cap, H), 1, "capacity %d draws a rank" % cap)
	assert_eq(CarRack.ranks_for(12, 80.0), 0, "a car under 81 has no room")

func test_the_rank_draws_as_many_as_it_can_at_a_legible_size() -> void:
	# Six is what a 220-unit car fits at CELL_MIN 32. Past that the riders are
	# counted, not drawn -- and the PIPS stay exact regardless.
	assert_eq(CarRack.front_count(4, W, 1), 4)
	assert_eq(CarRack.front_count(6, W, 1), 6)
	assert_eq(CarRack.front_count(12, W, 1), 6, "twelve do not fit legibly")

func test_the_cell_never_falls_below_a_two_digit_badge() -> void:
	for cap in range(4, 13):
		var cell := CarRack.cell_width(cap, W, 1)
		assert_gte(cell, CarRack.CELL_MIN,
			"capacity %d gives a %.2f cell, under CELL_MIN" % [cap, cell])

func test_the_cell_matches_the_derived_table() -> void:
	var want := {4: 52.0, 5: 40.8, 6: 33.33, 8: 33.33, 12: 33.33}
	for cap in want:
		assert_almost_eq(CarRack.cell_width(cap, W, 1), want[cap], 0.01,
			"cell at capacity %d" % cap)

func test_nothing_is_drawn_outside_the_car_at_any_capacity() -> void:
	for cap in range(4, 13):
		for r in CarRack.slots(cap, W, H):
			assert_gte(r.position.x, -0.01, "capacity %d starts left of the car" % cap)
			assert_lte(r.end.x, W + 0.01, "capacity %d ends right of the car" % cap)
			assert_gte(r.position.y, -0.01, "capacity %d above the car" % cap)
			assert_lte(r.end.y, H + 0.01, "capacity %d below the car" % cap)

func test_the_block_is_centred() -> void:
	var s := CarRack.slots(4, W, H)
	var left: float = s[0].position.x
	var right: float = W - s[s.size() - 1].end.x
	assert_almost_eq(left, right, 0.01, "even margins either side")

func test_the_riders_stand_on_the_car_floor() -> void:
	for r in CarRack.slots(6, W, H):
		assert_almost_eq(r.end.y, H - CarRack.INSET, 0.01, "feet on the floor")

func test_a_two_digit_badge_fits_the_narrowest_cell() -> void:
	# CELL_MIN exists for this. If a real font disagrees, cut the badge padding
	# to 1 unit a side before dropping the point size.
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("19", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	assert_lte(w + 4.0, CarRack.CELL_MIN,
		"two digits at font 24 must fit a %.0f-unit cell" % CarRack.CELL_MIN)

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

func test_pips_outlive_the_figures() -> void:
	# The point of the strip: occupancy stays exact in a car with no room to
	# draw anybody, which is where the old seat rack gave up entirely.
	assert_eq(CarRack.slots(12, W, 40.0).size(), 0, "no room for a rank")
	assert_eq(CarRack.pips(12, W).size(), 12, "but every seat still counted")

func test_the_bounds_cases_produce_no_layout_rather_than_a_bad_one() -> void:
	assert_eq(CarRack.slots(0, W, H).size(), 0)
	assert_eq(CarRack.pips(0, W).size(), 0)
	assert_eq(CarRack.pips(-3, W).size(), 0)
	# Far past the shipped cap of 12, both representations bow out on a MEASURED
	# floor rather than drawing something illegible.
	assert_eq(CarRack.pips(200, W).size(), 0, "pips below PIP_MIN are not drawn")
	for r in CarRack.slots(40, W, H):
		assert_lte(r.end.x, W + 0.01, "no slot escapes even far past the cap")
