extends GutTest

var g: Gesture

func before_each() -> void:
	# 40 rows in a 1280-unit board = 32 units per row.
	g = Gesture.new(32.0, 40)

func test_threshold_is_under_half_a_row() -> void:
	# Strictly under 16 units, or dispatching to the row your thumb is already
	# on becomes unreachable.
	assert_lt(Gesture.DRAG_THRESHOLD, 16.0)

func test_press_and_release_in_place_is_surge() -> void:
	g.press(100.0, 0)
	assert_eq(g.release(), Gesture.Result.SURGE)

func test_tiny_wobble_is_still_surge() -> void:
	g.press(100.0, 0)
	g.move(100.0 + Gesture.DRAG_THRESHOLD - 0.1)
	assert_eq(g.release(), Gesture.Result.SURGE, "under threshold")

func test_crossing_the_threshold_becomes_a_drag() -> void:
	g.press(100.0, 0)
	g.move(100.0 + Gesture.DRAG_THRESHOLD + 0.1)
	assert_true(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.DISPATCH)

func test_mapping_is_absolute_not_relative() -> void:
	# Detent i sits at row i's screen position, so any row is one short drag.
	# A relative mapping would need 39*32 = 1248 units to reach the top.
	g.press(0.0, 0)
	g.move(32.0 * 20.0 + 1.0)          # drag onto row 20's band
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), 20)

func test_dispatch_to_the_row_under_the_thumb_is_reachable() -> void:
	# Press inside row 5, nudge past the threshold, release: must select row 5.
	# This is what forces DRAG_THRESHOLD under half a row. At the band centre a
	# minimal nudge in EITHER direction stays on row 5, which only holds while
	# the threshold is under 16; from the last unit of the band only the nudge
	# away from that edge does, which is inherent to any absolute mapping.
	var centre := 32.0 * 5.0 + 16.0
	for direction in [1.0, -1.0]:
		g.press(centre, 0)
		g.move(centre + direction * (Gesture.DRAG_THRESHOLD + 0.1))
		assert_eq(g.release(), Gesture.Result.DISPATCH)
		assert_eq(g.selected_row(), 5,
			"centre of row 5, nudged %s, still row 5"
			% ("down" if direction > 0.0 else "up"))

	g.press(32.0 * 5.0 + 1.0, 0)                          # top of the band
	g.move(32.0 * 5.0 + 1.0 + Gesture.DRAG_THRESHOLD + 0.1)
	g.release()
	assert_eq(g.selected_row(), 5, "nudged away from the near edge")

	g.press(32.0 * 6.0 - 1.0, 0)                          # bottom of the band
	g.move(32.0 * 6.0 - 1.0 - Gesture.DRAG_THRESHOLD - 0.1)
	g.release()
	assert_eq(g.selected_row(), 5, "nudged away from the near edge")

func test_selection_snaps_to_the_row_band_under_the_thumb() -> void:
	# Detent i IS row i's band, [i*h, (i+1)*h) -- the same band FloorRow i draws
	# into. Rounding to the nearest multiple of the row height instead would put
	# the detent on the row's top edge, so a thumb over row 7's own label would
	# select row 8, and the highlight would sit half a row off what releasing
	# actually dispatches.
	g.press(0.0, 0)
	g.move(32.0 * 7.0 + 1.0)           # just inside row 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(0.0, 0)
	g.move(32.0 * 8.0 - 1.0)           # last unit of row 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(0.0, 0)
	g.move(32.0 * 8.0 + 1.0)           # over the boundary
	g.release()
	assert_eq(g.selected_row(), 8)

func test_horizontal_movement_is_ignored() -> void:
	# The pointer is captured on drag-start. A vertical thumb drag traces an
	# arc exceeding half a column width, so horizontal cancel would make the
	# primary verb self-cancel.
	g.press(0.0, 0)
	g.move(32.0 * 10.0)
	assert_eq(g.release(), Gesture.Result.DISPATCH, "no horizontal input exists")
	assert_eq(g.selected_row(), 10)

func test_dragging_past_the_top_cancels() -> void:
	g.press(32.0 * 5.0, 0)
	g.move(-40.0)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_dragging_past_the_bottom_cancels() -> void:
	g.press(32.0 * 5.0, 0)
	g.move(32.0 * 40.0 + 40.0)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_returning_from_beyond_the_edge_still_dispatches() -> void:
	g.press(32.0 * 5.0, 0)
	g.move(-40.0)
	g.move(32.0 * 3.0)
	assert_eq(g.release(), Gesture.Result.DISPATCH, "cancel is judged at release")
	assert_eq(g.selected_row(), 3)

func test_release_without_press_is_none() -> void:
	assert_eq(g.release(), Gesture.Result.NONE)

func test_rail_starts_at_the_cars_row() -> void:
	# Presentation only, but it is what lets the player see the no-op.
	g.press(500.0, 12)
	assert_eq(g.selected_row(), 12, "before any movement, the car's row")

func test_a_second_press_resets_state() -> void:
	g.press(0.0, 0)
	g.move(32.0 * 10.0)
	g.release()
	g.press(0.0, 3)
	assert_false(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.SURGE)
