extends GutTest

## 40 floors in the 1184-unit board = 29.6 units per floor. Not 32: the board
## is 1184, not the full 1280, because the HUD takes 96.
const H := 29.6
const FLOORS := 40

var g: Gesture

func before_each() -> void:
	g = Gesture.new(BoardCoords.new(FLOORS, H))

## Column-local y of the centre of floor f's band, bottom-up.
func centre_of(f: int) -> float:
	return float(FLOORS - 1 - f) * H + H * 0.5

func test_threshold_is_under_half_a_row() -> void:
	# Half a row is 14.8 at the real board height, not the 16 the design spec
	# still says. Under it, or dispatching to the floor your thumb is on is
	# unreachable.
	assert_lt(Gesture.DRAG_THRESHOLD, H * 0.5)

func test_press_and_release_in_place_is_surge() -> void:
	g.press(centre_of(10), 10)
	assert_eq(g.release(), Gesture.Result.SURGE)

func test_tiny_wobble_is_still_surge() -> void:
	g.press(centre_of(10), 10)
	g.move(centre_of(10) + Gesture.DRAG_THRESHOLD - 0.1)
	assert_eq(g.release(), Gesture.Result.SURGE)

func test_crossing_the_threshold_becomes_a_drag() -> void:
	g.press(centre_of(10), 10)
	g.move(centre_of(10) + Gesture.DRAG_THRESHOLD + 0.1)
	assert_true(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.DISPATCH)

func test_the_board_is_bottom_up() -> void:
	# The top of the column is the TOP floor; the bottom is the lobby.
	g.press(centre_of(20), 20)
	g.move(0.0)
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), FLOORS - 1, "y=0 is the top floor")

	g.press(centre_of(20), 20)
	g.move(float(FLOORS) * H - 1.0)
	g.release()
	assert_eq(g.selected_row(), 0, "the bottom of the column is the lobby")

func test_mapping_is_absolute_not_relative() -> void:
	# Any floor is one short drag away. A relative mapping would need 39 rows of
	# travel to reach the top.
	g.press(centre_of(0), 0)
	g.move(centre_of(20))
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), 20)

func test_dispatch_to_the_floor_under_the_thumb_is_reachable() -> void:
	# From the band centre a minimal nudge in EITHER direction stays on the
	# floor, which is what the sub-half-row threshold buys.
	for direction in [1.0, -1.0]:
		g.press(centre_of(12), 12)
		g.move(centre_of(12) + direction * (Gesture.DRAG_THRESHOLD + 0.1))
		assert_eq(g.release(), Gesture.Result.DISPATCH)
		assert_eq(g.selected_row(), 12,
			"nudged %s" % ("down" if direction > 0.0 else "up"))

func test_selection_snaps_to_the_band_under_the_thumb() -> void:
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 1 - 7) * H + 1.0)        # just inside floor 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 7) * H - 1.0)            # last unit of floor 7
	g.release()
	assert_eq(g.selected_row(), 7)
	g.press(centre_of(0), 0)
	g.move(float(FLOORS - 7) * H + 1.0)            # over into floor 6
	g.release()
	assert_eq(g.selected_row(), 6)

func test_horizontal_movement_is_ignored() -> void:
	# The pointer is captured on drag-start; only y is read.
	g.press(centre_of(0), 0)
	g.move(centre_of(10))
	assert_eq(g.release(), Gesture.Result.DISPATCH)
	assert_eq(g.selected_row(), 10)

func test_dragging_past_the_top_cancels() -> void:
	g.press(centre_of(20), 20)
	g.move(-H)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_dragging_past_the_bottom_cancels() -> void:
	g.press(centre_of(20), 20)
	g.move(float(FLOORS) * H + H)
	assert_eq(g.release(), Gesture.Result.CANCELLED)

func test_the_lobbys_whole_band_dispatches_and_never_cancels() -> void:
	# The trap the viewport inset exists to avoid: with the ghost floor in the
	# column, the cancel edge fell inside the lobby's band -- the highest-traffic
	# target in the game -- and half of it silently cancelled.
	for floors in [6, 28, 29, 39, 40]:
		var h := 1184.0 / float(floors + (1 if floors < 40 else 0))
		var gg := Gesture.new(BoardCoords.new(floors, h))
		var top := float(floors - 1) * h
		for frac in [0.01, 0.25, 0.5, 0.75, 0.99]:
			gg.press(h * 0.5, floors - 1)
			gg.move(top + h * frac)
			assert_eq(gg.release(), Gesture.Result.DISPATCH,
				"N=%d, %.0f%% into the lobby's band" % [floors, frac * 100.0])
			assert_eq(gg.selected_row(), 0)

func test_returning_from_beyond_the_edge_still_dispatches() -> void:
	g.press(centre_of(20), 20)
	g.move(-H)
	g.move(centre_of(3))
	assert_eq(g.release(), Gesture.Result.DISPATCH, "cancel is judged at release")
	assert_eq(g.selected_row(), 3)

func test_release_without_press_is_none() -> void:
	assert_eq(g.release(), Gesture.Result.NONE)

func test_rail_starts_at_the_cars_floor() -> void:
	g.press(centre_of(4), 12)
	assert_eq(g.selected_row(), 12, "before any movement, the car's floor")

func test_a_second_press_resets_state() -> void:
	g.press(centre_of(0), 0)
	g.move(centre_of(10))
	g.release()
	g.press(centre_of(0), 3)
	assert_false(g.is_dragging())
	assert_eq(g.release(), Gesture.Result.SURGE)
