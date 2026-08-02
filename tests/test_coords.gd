extends GutTest

## The board is 1184 units tall and holds floors + a ghost floor below the cap.
func height_for(floors: int) -> float:
	var ghost := 1 if floors < 40 else 0
	return 1184.0 / float(floors + ghost)

func test_floor_zero_is_the_bottom_band() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_almost_eq(c.floor_to_y(0), 5.0 * height_for(6), 1e-9,
		"the lobby's top edge is one row above the column's bottom")
	assert_almost_eq(c.floor_to_y(5), 0.0, 1e-9, "the top floor starts at y=0")

func test_round_trip_is_exact_at_every_floor_count() -> void:
	# N-1-floor(y/h) is NOT an identity in IEEE double: at N=29 the lobby's top
	# edge divides to 27.999999999999996 and resolves to floor 1. Twelve of the
	# forty floor counts have at least one floor that fails that way, so this
	# asserts all of them rather than a sample.
	for floors in range(1, 41):
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.y_to_floor(c.floor_to_y(f)), f,
				"N=%d floor %d must round-trip" % [floors, f])

func test_band_centres_round_trip_too() -> void:
	for floors in [6, 28, 29, 40]:
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.y_to_floor(c.band_centre_y(f)), f,
				"N=%d floor %d centre" % [floors, f])

func test_y_to_floor_is_monotonic_downward() -> void:
	# Walking down the column must walk down the floor numbers, never jump.
	var c := BoardCoords.new(29, height_for(29))
	var previous := c.y_to_floor(0.0)
	assert_eq(previous, 28, "the top of the column is the top floor")
	var y := 1.0
	while y < 29.0 * height_for(29):
		var f := c.y_to_floor(y)
		assert_true(f == previous or f == previous - 1,
			"floor stepped from %d to %d at y=%f" % [previous, f, y])
		previous = f
		y += 3.0
	assert_eq(previous, 0, "the bottom of the column is the lobby")

func test_y_above_the_column_clamps_to_the_top_floor() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_eq(c.y_to_floor(-500.0), 5)

func test_y_below_the_column_clamps_to_the_lobby() -> void:
	var c := BoardCoords.new(6, height_for(6))
	assert_eq(c.y_to_floor(99999.0), 0)

func test_car_y_is_continuous() -> void:
	# A car at 2.4 is between floors and must render there, not snap.
	var h := height_for(6)
	var c := BoardCoords.new(6, h)
	assert_almost_eq(c.car_y(0.0), 5.0 * h, 1e-9)
	assert_almost_eq(c.car_y(0.5), 4.5 * h, 1e-9)
	assert_almost_eq(c.car_y(5.0), 0.0, 1e-9)

func test_car_y_agrees_exactly_with_floor_to_y_at_integers() -> void:
	# The car and the row it stops at must not disagree by a float hair.
	for floors in [6, 29, 40]:
		var c := BoardCoords.new(floors, height_for(floors))
		for f in range(floors):
			assert_eq(c.car_y(float(f)), c.floor_to_y(f),
				"N=%d floor %d: car and row must be bit-identical" % [floors, f])

func test_a_single_floor_building_is_valid() -> void:
	var c := BoardCoords.new(1, 1184.0)
	assert_eq(c.y_to_floor(0.0), 0)
	assert_eq(c.y_to_floor(1183.0), 0)
	assert_almost_eq(c.floor_to_y(0), 0.0, 1e-9)
