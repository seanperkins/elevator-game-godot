extends GutTest

## The tap-vs-pan classifier shared by every column (and the hall). 40 floors
## in the board = 29.6 units per floor.
const H := 29.6
const FLOORS := 40

var g: Gesture

func before_each() -> void:
	g = Gesture.new(BoardCoords.new(FLOORS, H))

## Board-local y of the centre of floor f's band, bottom-up.
func centre_of(f: int) -> float:
	return float(FLOORS - 1 - f) * H + H * 0.5

## Press on floor f, with the car parked on `car_floor`.
func press(f: int, car_floor: int) -> void:
	g.press(Vector2(0, centre_of(f)), car_floor)

func test_threshold_is_under_half_a_row() -> void:
	# Half a floor is 14.8 at the real board height. Under it, or dispatching to
	# the floor your thumb is on is unreachable.
	assert_lt(Gesture.DRAG_THRESHOLD, H * 0.5)

func test_a_tap_resolves_to_the_floor_under_the_thumb() -> void:
	# A tap is a dispatch to where you touched. It reads the PRESS point, not
	# the car's floor.
	press(10, 30)
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), 10, "the floor touched, not the car's floor")

func test_a_tap_anywhere_in_a_band_selects_that_band() -> void:
	for frac in [0.01, 0.5, 0.99]:
		g.press(Vector2(0, float(FLOORS - 1 - 7) * H + H * frac), 0)
		assert_eq(g.release(), Gesture.Result.TAP)
		assert_eq(g.selected_floor(), 7, "%.0f%% into floor 7's band" % [frac * 100.0])

func test_a_tap_on_the_lobby_selects_the_lobby() -> void:
	press(0, 20)
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), 0)

func test_a_wobble_under_the_threshold_is_still_a_tap() -> void:
	# Below DRAG_THRESHOLD nothing is a drag, so a tap resolves against the
	# press point rather than where the thumb drifted to.
	press(10, 30)
	g.move(Vector2(0, centre_of(10) + Gesture.DRAG_THRESHOLD - 0.1))
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), 10)

func test_crossing_the_threshold_becomes_a_pan() -> void:
	press(10, 10)
	g.move(Vector2(0, centre_of(10) + Gesture.DRAG_THRESHOLD + 0.1))
	assert_true(g.is_panning())
	assert_eq(g.release(), Gesture.Result.PAN)

func test_a_pan_keeps_the_cars_floor_untouched() -> void:
	# A pan is a pan, not a selection: the selected floor is not rewritten on a
	# drag, exactly so the board can move without commanding anything.
	press(10, 7)
	g.move(Vector2(0, centre_of(10) - Gesture.DRAG_THRESHOLD - 0.1))
	g.release()
	assert_eq(g.selected_floor(), 7)

func test_the_board_is_bottom_up() -> void:
	g.press(Vector2(0, 0.0), 0)
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), FLOORS - 1, "the top of the column is the top floor")

	g.press(Vector2(0, float(FLOORS) * H - 1.0), 0)
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), 0, "the bottom of the column is the lobby")

func test_pan_delta_is_cumulative_and_consumed() -> void:
	press(10, 10)
	g.move(Vector2(0, centre_of(10) - 20.0))
	g.move(Vector2(0, centre_of(10) - 30.0))
	var d := g.take_pan_delta()
	assert_ne(d, Vector2.ZERO, "the accumulated travel is reported")
	assert_eq(g.take_pan_delta(), Vector2.ZERO, "and handed out exactly once")

func test_release_without_press_is_none() -> void:
	assert_eq(g.release(), Gesture.Result.NONE)

func test_rail_starts_at_the_cars_floor() -> void:
	press(4, 12)
	assert_eq(g.selected_floor(), 12, "before any movement, the car's floor")

func test_a_second_press_resets_state() -> void:
	press(0, 0)
	g.move(Vector2(0, centre_of(10)))
	g.release()
	press(0, 3)
	assert_false(g.is_panning(), "the previous drag must not carry over")
	assert_eq(g.release(), Gesture.Result.TAP)
	assert_eq(g.selected_floor(), 0, "the second press's own floor, not floor 10")
