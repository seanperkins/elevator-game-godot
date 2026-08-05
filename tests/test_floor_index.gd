extends GutTest

## The floor -> array slot mapping, and the ONLY copy of it. Building, Tenancy
## and Fitout share one instance, so "the three agree" is not a property to test
## -- it is unrepresentable. What IS worth testing is the mapping itself and its
## refusal at the edges, because every per-floor array in the sim is behind it.

func test_a_ground_only_building_is_the_identity() -> void:
	# The case that made a shared index earn nothing before basements existed --
	# it must still be free.
	var ix := FloorIndex.new(0, 10)
	for f in range(0, 10):
		assert_eq(ix.slot(f), f, "floor %d" % f)
	assert_eq(ix.size(), 10)

func test_the_basement_occupies_the_front_of_the_array() -> void:
	var ix := FloorIndex.new(-2, 10)
	assert_eq(ix.slot(-2), 0, "the deepest floor is slot 0")
	assert_eq(ix.slot(-1), 1)
	assert_eq(ix.slot(0), 2, "the lobby is no longer slot 0")
	assert_eq(ix.slot(9), 11)
	assert_eq(ix.size(), 12)

func test_it_refuses_floors_outside_the_building() -> void:
	# The hazard Fitout's old docstring named: an offset turns an out-of-range
	# access into an in-range WRONG one. holds() is what stops that.
	var ix := FloorIndex.new(-2, 10)
	assert_false(ix.holds(-3), "below the basement")
	assert_false(ix.holds(10), "above the roof")
	assert_true(ix.holds(-2))
	assert_true(ix.holds(9))

func test_digging_moves_the_bottom_and_growing_moves_the_top() -> void:
	var ix := FloorIndex.new(0, 1)
	ix.dig()
	assert_eq(ix.bottom, -1)
	assert_eq(ix.slot(-1), 0, "the new floor takes slot 0")
	assert_eq(ix.slot(0), 1, "and everything above shifts up one")
	ix.grow_up()
	assert_eq(ix.above, 2)
	assert_eq(ix.size(), 3)

func test_digging_twice_does_not_move_what_was_already_there() -> void:
	# The front-insertion bug that is invisible until you dig a SECOND time.
	var ix := FloorIndex.new(0, 3)
	ix.dig()
	var first := ix.slot(-1)
	ix.dig()
	assert_eq(ix.slot(-2), 0, "the newest floor is at the front")
	assert_eq(ix.slot(-1), first + 1, "and the older one moved up exactly one")
