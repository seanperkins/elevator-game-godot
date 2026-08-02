extends GutTest

## The scrolling board's transform: a FIXED row height, a scroll offset, and
## floors that may go below zero.
##
## The old model derived height from the floor count so everything fitted one
## screen. This one fixes the height and moves the window instead, which is what
## makes a 48pt row and a basement possible at the same time.

const H := 88.0

func tower(top: int, bottom := 0) -> BoardCoords:
	return BoardCoords.fixed(bottom, top, H)

func test_a_row_is_the_same_height_however_tall_the_building() -> void:
	# The whole point: legibility stops depending on how much you have built.
	for top in [5, 39, 200]:
		assert_almost_eq(tower(top).row_height, H, 1e-9, "top=%d" % top)

func test_floors_still_run_bottom_up() -> void:
	var c := tower(5)
	assert_gt(c.floor_to_y(0), c.floor_to_y(5), "the lobby is below the top floor")

func test_the_top_floor_sits_at_the_top_when_unscrolled() -> void:
	var c := tower(5)
	assert_almost_eq(c.floor_to_y(5), 0.0, 1e-9)

func test_scrolling_moves_the_floors_and_nothing_else() -> void:
	var c := tower(5)
	var before := c.floor_to_y(2)
	c.scroll_to(H * 2.0)
	assert_almost_eq(c.floor_to_y(2), before - H * 2.0, 1e-9,
		"the window moved, the building did not")

func test_the_round_trip_survives_scrolling() -> void:
	# The guarantee the edge table exists for, now with an offset on top.
	var c := tower(39)
	for offset in [0.0, 1.0, H * 0.5, H * 7.0, H * 12.3]:
		c.scroll_to(offset)
		for f in range(40):
			assert_eq(c.y_to_floor(c.floor_to_y(f)), f,
				"floor %d at offset %f" % [f, offset])

func test_band_centres_round_trip_too() -> void:
	var c := tower(39)
	c.scroll_to(H * 3.5)
	for f in range(40):
		assert_eq(c.y_to_floor(c.band_centre_y(f)), f, "floor %d" % f)

# --- floors below the lobby ------------------------------------------------

func test_a_basement_floor_is_below_the_lobby() -> void:
	var c := tower(5, -3)
	assert_gt(c.floor_to_y(-3), c.floor_to_y(0), "the basement is below floor 0")

func test_the_round_trip_works_below_zero() -> void:
	var c := tower(10, -5)
	for offset in [0.0, H * 2.0, H * 9.5]:
		c.scroll_to(offset)
		for f in range(-5, 11):
			assert_eq(c.y_to_floor(c.floor_to_y(f)), f,
				"floor %d at offset %f" % [f, offset])

func test_the_lobby_is_not_the_bottom_when_there_is_a_basement() -> void:
	var c := tower(5, -2)
	assert_eq(c.bottom_floor, -2)
	assert_eq(c.floor_count, 8, "-2 through 5 inclusive")

func test_car_y_is_continuous_across_the_lobby() -> void:
	# A car descending into the basement must glide, not jump at zero.
	var c := tower(5, -2)
	assert_almost_eq(c.car_y(0.0) - c.car_y(-0.5), -H * 0.5, 1e-9)
	assert_almost_eq(c.car_y(-0.5) - c.car_y(-1.0), -H * 0.5, 1e-9)

func test_car_y_still_agrees_exactly_with_floor_to_y() -> void:
	var c := tower(10, -4)
	c.scroll_to(H * 2.0)
	for f in range(-4, 11):
		assert_eq(c.car_y(float(f)), c.floor_to_y(f), "floor %d" % f)

# --- the window --------------------------------------------------------------

func test_content_height_is_every_floor_at_full_height() -> void:
	assert_almost_eq(tower(5, -2).content_height(), 8.0 * H, 1e-9)

func test_scrolling_is_clamped_to_the_building() -> void:
	# You cannot scroll past the roof or below the deepest floor.
	var c := tower(9)            # ten floors, 880 units of content
	c.set_viewport_height(400.0)
	c.scroll_to(-500.0)
	assert_almost_eq(c.scroll_offset, 0.0, 1e-9, "not above the roof")
	c.scroll_to(99999.0)
	assert_almost_eq(c.scroll_offset, 880.0 - 400.0, 1e-9, "not below the floor")

func test_a_building_shorter_than_the_screen_does_not_scroll() -> void:
	var c := tower(2)            # three floors, 264 units
	c.set_viewport_height(800.0)
	c.scroll_to(300.0)
	assert_almost_eq(c.scroll_offset, 0.0, 1e-9, "nothing to scroll to")

func test_y_above_the_building_clamps_to_the_top_floor() -> void:
	assert_eq(tower(5).y_to_floor(-9999.0), 5)

func test_y_below_the_building_clamps_to_the_bottom_floor() -> void:
	assert_eq(tower(5, -3).y_to_floor(9999.0), -3)

# --- a building stands on the ground ---------------------------------------

func test_a_short_building_sits_at_the_bottom_of_the_screen() -> void:
	# Left unhandled, a six-floor tower hangs from the top of the board with a
	# void beneath it -- and the "+ BUILD FLOOR" band off-screen above.
	var c := tower(5)
	c.set_viewport_height(1184.0)
	assert_almost_eq(c.floor_to_y(0) + H, 1184.0, 1e-9,
		"the lobby's bottom edge is the bottom of the window")

func test_the_slack_goes_above_the_building_not_below_it() -> void:
	var c := tower(5)
	c.set_viewport_height(1184.0)
	assert_gt(c.floor_to_y(5), 0.0, "there is sky above the top floor")

func test_a_building_taller_than_the_window_starts_at_the_roof() -> void:
	var c := tower(39)
	c.set_viewport_height(1184.0)
	assert_almost_eq(c.floor_to_y(39), 0.0, 1e-9, "no slack to distribute")

func test_the_round_trip_survives_the_ground_offset() -> void:
	var c := tower(5)
	c.set_viewport_height(1184.0)
	for f in range(6):
		assert_eq(c.y_to_floor(c.floor_to_y(f)), f, "floor %d" % f)
		assert_eq(c.y_to_floor(c.band_centre_y(f)), f, "floor %d centre" % f)

func test_the_car_still_agrees_with_the_row_on_the_ground() -> void:
	var c := tower(5)
	c.set_viewport_height(1184.0)
	for f in range(6):
		assert_eq(c.car_y(float(f)), c.floor_to_y(f), "floor %d" % f)
