class_name Gesture
extends RefCounted

## Classifies a point stream on a shaft column into one verb.
##
## Verbs separate by GESTURE, never by tap cadence -- nothing here depends on
## double-tap timing, which also collides with mobile Safari's zoom heuristics.
##
## The mapping is ABSOLUTE: detent i is row i's band on screen. A relative
## mapping (finger displacement driving detent displacement) would make a
## lobby-to-top dispatch need 1,248 units of travel on a 1,280-unit board.
## Release-in-place is surge because the THRESHOLD was not crossed, not because
## of where the rail was anchored -- which is why the threshold must stay under
## half a row.
##
## A detent is the row's whole band, [i*h, (i+1)*h), which is exactly the band
## FloorRow i draws into. Snapping to the nearest multiple of the row height
## instead would anchor the detent on the row's top EDGE: a thumb resting over
## row i's own label would select row i+1, and the rail highlight would sit
## half a row away from what release dispatches.

enum Result { NONE, SURGE, DISPATCH, CANCELLED }

const DRAG_THRESHOLD := 12.0     # < 16.0 (half a row at the 40-row ceiling)

var _row_height: float
var _row_count: int
var _active := false
var _dragging := false
var _press_y := 0.0
var _current_y := 0.0
var _selected_row := 0

func _init(row_height: float, row_count: int) -> void:
	_row_height = maxf(row_height, 1.0)
	_row_count = maxi(row_count, 1)

func press(y: float, car_row: int) -> void:
	_active = true
	_dragging = false
	_press_y = y
	_current_y = y
	_selected_row = clampi(car_row, 0, _row_count - 1)

func move(y: float) -> void:
	if not _active:
		return
	_current_y = y
	if absf(y - _press_y) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging and not _is_beyond_edge(y):
		_selected_row = _row_at(y)

func release() -> int:
	if not _active:
		return Result.NONE
	var out := Result.SURGE
	if _dragging:
		out = Result.CANCELLED if _is_beyond_edge(_current_y) else Result.DISPATCH
	_active = false
	_dragging = false
	return out

func selected_row() -> int:
	return _selected_row

func is_dragging() -> bool:
	return _dragging

func _row_at(y: float) -> int:
	return clampi(int(floorf(y / _row_height)), 0, _row_count - 1)

## Cancel is a deliberate gesture: past the top or bottom of the board. Half a
## row of slop outside it, so overshooting the first or last row by a few units
## dispatches rather than silently cancelling.
func _is_beyond_edge(y: float) -> bool:
	return y < -_row_height * 0.5 or y > _row_height * (float(_row_count) + 0.5)
