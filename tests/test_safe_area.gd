extends GutTest

## Canvas units, not pixels. The board is 720x1280 canvas; an iPhone 16 Pro is
## 1206x2622 physical, so an inset read straight from DisplayServer would be
## about 3x too large -- the Dynamic Island alone would eat a third of the HUD.

const CANVAS := Vector2(720, 1280)

func test_no_reported_safe_area_means_no_insets() -> void:
	# Desktop and headless report an empty rect. Reading that as "all unsafe"
	# would collapse the board to nothing.
	assert_eq(SafeArea.insets(Vector2i(1206, 2622), Rect2i(), CANVAS), Vector4.ZERO)

func test_a_zero_window_is_survivable() -> void:
	# The headless window is 0x0, which would divide by zero.
	assert_eq(SafeArea.insets(Vector2i.ZERO, Rect2i(0, 0, 100, 100), CANVAS),
		Vector4.ZERO)

func test_pixels_are_converted_to_canvas_units() -> void:
	# A 2622px-tall screen showing 1280 canvas units: a 200px island is 97.6
	# units, not 200.
	var got := SafeArea.insets(Vector2i(1206, 2622),
		Rect2i(0, 200, 1206, 2622 - 200 - 100), CANVAS)
	assert_almost_eq(got.y, 200.0 * 1280.0 / 2622.0, 0.01, "top")
	assert_almost_eq(got.w, 100.0 * 1280.0 / 2622.0, 0.01, "bottom")

func test_the_bottom_inset_is_what_is_left_below_the_safe_rect() -> void:
	var got := SafeArea.insets(Vector2i(100, 1000), Rect2i(0, 0, 100, 900),
		Vector2(100, 1000))
	assert_almost_eq(got.w, 100.0, 0.01, "1000 - (0 + 900)")

func test_sides_get_a_corner_allowance_even_when_the_safe_rect_is_square() -> void:
	# The safe rect is a rectangle and the screen is not: a full-width safe area
	# still has its corners clipped by the curve.
	var got := SafeArea.insets(Vector2i(1206, 2622), Rect2i(0, 200, 1206, 2300),
		CANVAS)
	assert_almost_eq(got.x, SafeArea.CORNER_MARGIN, 0.01, "left")
	assert_almost_eq(got.z, SafeArea.CORNER_MARGIN, 0.01, "right")

func test_a_reported_side_inset_wins_when_it_is_larger() -> void:
	var got := SafeArea.insets(Vector2i(1000, 1000), Rect2i(300, 0, 400, 1000),
		Vector2(1000, 1000))
	assert_almost_eq(got.x, 300.0, 0.01, "landscape-style inset beats the margin")

func test_insets_are_never_negative() -> void:
	# A safe rect larger than the window is nonsense, but it must not produce a
	# negative inset that pushes content off the other edge.
	var got := SafeArea.insets(Vector2i(100, 100), Rect2i(-10, -10, 200, 200),
		Vector2(100, 100))
	assert_gte(got.y, 0.0)
	assert_gte(got.w, 0.0)
