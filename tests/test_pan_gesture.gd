extends GutTest

## Drag is no longer dispatch. It moves the window; a TAP dispatches.
##
## The classifier's only job now is telling those two apart, which is a much
## smaller question than the one it used to answer -- and the reason the board
## is allowed to scroll at all.

const H := 88.0

var g: Gesture

func before_each() -> void:
	g = Gesture.new(BoardCoords.fixed(0, 19, H))

func test_a_press_and_release_in_place_is_a_tap() -> void:
	g.press(Vector2(0.0, 300.0), 0)
	assert_eq(g.release(), Gesture.Result.TAP)

func test_a_tap_reports_the_floor_it_landed_on() -> void:
	var coords := BoardCoords.fixed(0, 19, H)
	coords.set_viewport_height(1184.0)
	var gg := Gesture.new(coords)
	var y := coords.band_centre_y(7)
	gg.press(Vector2(0.0, y), 0)
	assert_eq(gg.release(), Gesture.Result.TAP)
	assert_eq(gg.selected_floor(), 7, "the floor under the thumb, not the car's")

func test_a_small_wobble_is_still_a_tap() -> void:
	# A thumb never lands perfectly still. Below the threshold it is a tap, and
	# it resolves against where the thumb went DOWN, not where it drifted.
	var coords := BoardCoords.fixed(0, 19, H)
	coords.set_viewport_height(1184.0)
	var gg := Gesture.new(coords)
	var y := coords.band_centre_y(7)
	gg.press(Vector2(0.0, y), 0)
	gg.move(Vector2(0.0, y + Gesture.DRAG_THRESHOLD - 0.1))
	assert_eq(gg.release(), Gesture.Result.TAP)
	assert_eq(gg.selected_floor(), 7)

func test_crossing_the_threshold_becomes_a_pan() -> void:
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 300.0 + Gesture.DRAG_THRESHOLD + 1.0))
	assert_true(g.is_panning())
	assert_eq(g.release(), Gesture.Result.PAN)

func test_the_content_follows_the_thumb() -> void:
	# Sign convention, stated once: a thumb moving UP carries the building up
	# with it, which is a LARGER scroll offset. Get this backwards and the board
	# runs away from the finger, which is the classic broken-scroll feel.
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 260.0))
	assert_almost_eq(g.take_pan_delta().y, 40.0, 1e-6, "thumb up 40, content up 40")
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 340.0))
	assert_almost_eq(g.take_pan_delta().y, -40.0, 1e-6, "and down the other way")

func test_a_pan_reports_only_what_changed_since_it_was_last_asked() -> void:
	# Incremental, not cumulative: the view adds each report to the offset, so a
	# running total would accelerate the board away from the thumb.
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 260.0))
	assert_almost_eq(g.take_pan_delta().y, 40.0, 1e-6)
	g.move(Vector2(0.0, 250.0))
	assert_almost_eq(g.take_pan_delta().y, 10.0, 1e-6, "10 more, not 50")

func test_taking_the_delta_consumes_it() -> void:
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 260.0))
	g.take_pan_delta().y
	assert_almost_eq(g.take_pan_delta().y, 0.0, 1e-9,
		"a frame with no movement pans by nothing")

func test_panning_reports_both_axes() -> void:
	# Eight shafts are wider than the screen just as forty floors are taller.
	# Looking around is one gesture, not a drag plus a pair of pager buttons.
	g.press(Vector2(300.0, 300.0), 0)
	g.move(Vector2(260.0, 250.0))
	var d := g.take_pan_delta()
	assert_almost_eq(d.x, 40.0, 1e-6, "content follows the thumb sideways too")
	assert_almost_eq(d.y, 50.0, 1e-6)

func test_movement_before_the_threshold_is_not_thrown_away() -> void:
	# The board must not jump when the pan begins: the travel that proved it was
	# a pan is part of the pan.
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 300.0 - Gesture.DRAG_THRESHOLD - 1.0))
	assert_almost_eq(g.take_pan_delta().y, Gesture.DRAG_THRESHOLD + 1.0, 1e-6)

func test_a_pan_does_not_dispatch() -> void:
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 600.0))
	assert_eq(g.release(), Gesture.Result.PAN, "looking around is not commanding")

func test_a_second_press_starts_clean() -> void:
	g.press(Vector2(0.0, 300.0), 0)
	g.move(Vector2(0.0, 600.0))
	g.release()
	g.press(Vector2(0.0, 300.0), 0)
	assert_false(g.is_panning())
	assert_almost_eq(g.take_pan_delta().y, 0.0, 1e-9, "no carry-over from the last drag")
	assert_eq(g.release(), Gesture.Result.TAP)

func test_release_without_press_is_nothing() -> void:
	assert_eq(g.release(), Gesture.Result.NONE)

func test_the_threshold_is_small_enough_that_tapping_stays_easy() -> void:
	# It only has to beat thumb wobble now, not half a floor: a tap resolves
	# against the press point, so the threshold no longer gates precision.
	assert_lt(Gesture.DRAG_THRESHOLD, H * 0.5)
