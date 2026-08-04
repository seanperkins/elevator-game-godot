extends GutTest

## The board is NOT the canvas. SafeArea floors both side insets at
## CORNER_MARGIN, so a phone's board is 688 wide where the headless suite sees
## 720. Three review rounds broke on numbers derived at 720 and asserted at 720;
## these assert at both widths and require them to AGREE.
##
## AND THE BOARD IS NOT THE BUILDING. The building starts at EXTERIOR_LEFT, so
## every width here comes off `board - EXTERIOR_LEFT`. Measuring from the screen
## edge overstates the shaft viewport by 20 units, which is more than the slack
## the two columns have.

const CANVAS_W := 720.0

func _building_width_at(board_w: float) -> float:
	return board_w - BuildingView.EXTERIOR_LEFT

func _viewport_at(board_w: float) -> float:
	return _building_width_at(board_w) - BuildingView.SHAFT_AREA_X

func _visible_shafts_at(board_w: float) -> int:
	return maxi(int(_viewport_at(board_w) / BuildingView.SHAFT_WIDTH), 1)

func device_board_width() -> float:
	return CANVAS_W - 2.0 * SafeArea.CORNER_MARGIN

func test_two_shaft_columns_on_the_device_board() -> void:
	# The number that ships. At SHAFT_WIDTH 240 this is 1, while the headless
	# assertion below still reads 2 -- which is exactly how a one-column board
	# would have shipped green.
	assert_eq(_visible_shafts_at(device_board_width()), 2)

func test_two_shaft_columns_on_the_canvas_too() -> void:
	assert_eq(_visible_shafts_at(CANVAS_W), 2)

func test_the_two_surfaces_agree() -> void:
	# The property worth having: a width whose column count does not depend on
	# which surface you measure.
	assert_eq(_visible_shafts_at(device_board_width()),
		_visible_shafts_at(CANVAS_W), "device and canvas must agree")

func test_the_column_count_has_slack_against_a_deeper_inset() -> void:
	# 240 tiled 480 exactly and had none, so any inset at all cost a column.
	assert_gte(_viewport_at(device_board_width()) - 2.0 * BuildingView.SHAFT_WIDTH, 6.0,
		"at least 6 units spare beyond two columns")

# --- the exterior -----------------------------------------------------------

func test_the_exterior_is_paid_for_by_the_gutter() -> void:
	# The margin is not free space that happened to be lying around. It is the
	# 16 units the gutter released when the tenant bar was deleted (64 -> 48),
	# plus the 4 the viewport already had. Widening the gutter again takes the
	# world outside the building back out, and this states the arithmetic so that
	# a later "just give the gutter a few more units" fails here.
	assert_eq(FloorRow.GUTTER_WIDTH, 48.0)
	assert_lte(BuildingView.EXTERIOR_LEFT, 64.0 - FloorRow.GUTTER_WIDTH + 4.0,
		"the exterior cannot be wider than what was freed to pay for it")

func test_the_gutter_still_holds_both_labels() -> void:
	# What the 48 has to fit: a two-digit count at font 18 (~19.8 units) and a
	# two-digit floor number at font 22 (~24.2). Floors run to MAX_FLOORS, so two
	# digits is the real case, and an overlap here is the bug an earlier draft
	# shipped -- the number ran into the people strip.
	assert_gte(FloorRow.COUNT_WIDTH, 19.8, "the waiting count needs two digits")
	assert_gte(FloorRow.LABEL_X, FloorRow.COUNT_WIDTH,
		"the floor number cannot start inside the count")
	assert_gte(FloorRow.GUTTER_WIDTH - FloorRow.LABEL_X, 24.2,
		"the floor number needs two digits before the strip begins")
	assert_lte(Building.MAX_FLOORS, 99, "three digits would need a wider gutter")

func test_the_near_side_face_fits_inside_its_margin() -> void:
	# The face is drawn INSIDE the exterior; what is left over is the sky the
	# neighbour stands in. A face as wide as the margin leaves no outside at all.
	assert_lt(BuildingView.SIDE_FACE, BuildingView.EXTERIOR_LEFT,
		"the side face must leave some sky")
	assert_gte(BuildingView.EXTERIOR_LEFT - BuildingView.SIDE_FACE, 8.0,
		"and enough of it to read as sky rather than as a second edge")

func test_the_far_wall_is_only_reachable_by_scrolling() -> void:
	# The building runs flush to the right edge of the screen. The far wall sits
	# at the end of the slot run, so with the shafts unscrolled it is off-window
	# whenever the building is wider than the viewport -- which is every board
	# with more slots than visible columns.
	var viewport := _viewport_at(device_board_width())
	var slots := 3                      # two owned plus the trailing ghost slot
	var wall_x := float(slots) * BuildingView.SHAFT_WIDTH
	assert_gt(wall_x, viewport, "unscrolled, the far wall is past the window")
	# ...and scrolling fully right brings it in, with room to see past it.
	var max_offset := (float(slots) - 2.0) * BuildingView.SHAFT_WIDTH
	assert_lt(wall_x - max_offset, viewport,
		"at full right scroll the wall is on screen")
	assert_gte(viewport - (wall_x - max_offset), 6.0,
		"and there is sky visible beyond it")
