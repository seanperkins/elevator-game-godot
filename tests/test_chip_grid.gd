extends GutTest

## Room enough that nothing is constrained, so these pin the PREFERRED shape.
const ROOMY := 99

func shape_of(count: int) -> Vector2i:
	return ChipGrid.shape(count, ROOMY, ROOMY)

func test_one_is_alone() -> void:
	assert_eq(shape_of(1), Vector2i(1, 1))

func test_two_sit_side_by_side() -> void:
	assert_eq(shape_of(2), Vector2i(2, 1))

func test_three_sit_side_by_side() -> void:
	assert_eq(shape_of(3), Vector2i(3, 1))

func test_four_are_two_over_two() -> void:
	assert_eq(shape_of(4), Vector2i(2, 2), "not a row of four")

func test_five_are_three_over_two() -> void:
	assert_eq(shape_of(5), Vector2i(3, 2))

func test_six_are_three_over_three() -> void:
	assert_eq(shape_of(6), Vector2i(3, 2))

func test_eight_are_four_over_four() -> void:
	# floor(sqrt(8)) = 2 rows, so four across. Ceiling instead would give three
	# rows of 3+3+2, which is taller and reads as ragged.
	assert_eq(shape_of(8), Vector2i(4, 2))

func test_nine_are_a_square() -> void:
	assert_eq(shape_of(9), Vector2i(3, 3))

func test_twelve_are_three_ranks_of_four() -> void:
	assert_eq(shape_of(12), Vector2i(4, 3))

func test_every_count_has_room_for_everyone() -> void:
	for n in range(1, 41):
		var s := shape_of(n)
		assert_gte(s.x * s.y, n, "%d must fit in %dx%d" % [n, s.x, s.y])

func test_the_shape_is_never_wider_than_it_has_to_be() -> void:
	# The last rank may be short, but there must never be a whole empty rank.
	for n in range(1, 41):
		var s := shape_of(n)
		assert_lte((s.y - 1) * s.x, n - 1,
			"%d in %dx%d leaves an empty rank" % [n, s.x, s.y])

func test_a_narrow_space_uses_more_rows() -> void:
	# Two columns is all that fits, so twelve becomes six ranks rather than
	# spilling out of the area.
	assert_eq(ChipGrid.shape(12, 2, ROOMY), Vector2i(2, 6))

func test_a_short_space_uses_more_columns() -> void:
	# One rank is all that fits -- a dense board -- so the balanced shape gives
	# way and the people line up, which is what the old single row did.
	assert_eq(ChipGrid.shape(4, ROOMY, 1), Vector2i(4, 1))
	assert_eq(ChipGrid.shape(12, ROOMY, 1), Vector2i(12, 1))

func test_a_space_too_small_for_everyone_shows_what_fits() -> void:
	# The count beside the strip carries the exact total, so showing fewer is
	# honest rather than lossy.
	var s := ChipGrid.shape(12, 3, 2)
	assert_eq(s, Vector2i(3, 2))
	assert_lt(s.x * s.y, 12)

func test_zero_has_no_shape() -> void:
	assert_eq(shape_of(0), Vector2i.ZERO)

func test_a_space_that_holds_nothing_reports_nothing() -> void:
	# Flooring this at one rank is how a 30-unit chip ends up drawn inside a
	# 25.6-unit car. The caller needs the truth so it can fall back to text.
	assert_eq(ChipGrid.rows_for(ChipGrid.SIZE - 1.0), 0)
	assert_eq(ChipGrid.columns_for(ChipGrid.SIZE - 1.0), 0)
	assert_eq(ChipGrid.shape(4, 0, ROOMY), Vector2i.ZERO)
	assert_eq(ChipGrid.shape(4, ROOMY, 0), Vector2i.ZERO)

func test_a_space_that_holds_exactly_one_reports_one() -> void:
	assert_eq(ChipGrid.rows_for(ChipGrid.SIZE), 1)
	assert_eq(ChipGrid.columns_for(ChipGrid.SIZE), 1)

func test_ranks_are_centred_so_a_short_last_rank_is_not_ragged() -> void:
	# Five in a 3x2: the lower rank of two sits centred under the upper three.
	var s := ChipGrid.shape(5, ROOMY, ROOMY)
	var area := Vector2(200, 200)
	var first := ChipGrid.position_of(0, 5, s, area)
	var third := ChipGrid.position_of(2, 5, s, area)
	var fourth := ChipGrid.position_of(3, 5, s, area)
	var fifth := ChipGrid.position_of(4, 5, s, area)
	assert_almost_eq((fourth.x + fifth.x) * 0.5, (first.x + third.x) * 0.5, 0.01,
		"the short rank shares the full rank's centre line")
	assert_gt(fourth.y, first.y, "and sits below it")

func test_a_full_rank_spans_evenly() -> void:
	var s := ChipGrid.shape(4, ROOMY, ROOMY)
	var area := Vector2(200, 200)
	var a := ChipGrid.position_of(0, 4, s, area)
	var b := ChipGrid.position_of(1, 4, s, area)
	assert_almost_eq(b.x - a.x, ChipGrid.SIZE + ChipGrid.GAP, 0.01)

func test_the_block_is_centred_in_its_area() -> void:
	var s := ChipGrid.shape(2, ROOMY, ROOMY)
	var area := Vector2(200, 100)
	var a := ChipGrid.position_of(0, 2, s, area)
	var b := ChipGrid.position_of(1, 2, s, area)
	var block_centre := (a.x + b.x + ChipGrid.SIZE) * 0.5
	assert_almost_eq(block_centre, 100.0, 0.01, "horizontally centred")
	assert_almost_eq(a.y, (100.0 - ChipGrid.SIZE) * 0.5, 0.01, "vertically centred")
