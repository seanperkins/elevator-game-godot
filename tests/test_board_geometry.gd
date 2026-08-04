extends GutTest

## The board is NOT the canvas. SafeArea floors both side insets at
## CORNER_MARGIN, so a phone's board is 688 wide where the headless suite sees
## 720. Three review rounds broke on numbers derived at 720 and asserted at 720;
## these assert at both widths and require them to AGREE.

const CANVAS_W := 720.0

func _visible_shafts_at(board_w: float) -> int:
	return maxi(int((board_w - BuildingView.SHAFT_AREA_X) / BuildingView.SHAFT_WIDTH), 1)

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
	var viewport := device_board_width() - BuildingView.SHAFT_AREA_X
	assert_gte(viewport - 2.0 * BuildingView.SHAFT_WIDTH, 6.0,
		"at least 6 units spare beyond two columns")
