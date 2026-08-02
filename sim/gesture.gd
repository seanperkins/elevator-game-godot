class_name Gesture
extends RefCounted

## Classifies a point stream on a shaft column into one verb.
##
## Verbs separate by GESTURE, never by tap cadence -- nothing here depends on
## double-tap timing, which also collides with mobile Safari's zoom heuristics.
##
## The mapping is ABSOLUTE: a detent is a floor's band on screen, so any floor
## is one short drag away. A relative mapping would make a lobby-to-top dispatch
## need 39 rows of travel on a board 40 rows tall.
##
## Screen y is converted to a FLOOR by BoardCoords -- the one definition of the
## bottom-up inversion. This class holds no coordinate arithmetic beyond the
## cancel edges.
##
## A detent is the floor's whole band, which is exactly the band FloorRow draws
## into. Snapping to the nearest multiple of the row height instead would anchor
## the detent on a band EDGE: a thumb resting over a floor's own label would
## select its neighbour, and the rail would sit half a row from what dispatches.

## SURGE is retained but NOT currently produced. A tap used to mean surge and
## now dispatches to the floor it landed on, because a tap on a floor obviously
## means "send the car here" and made the drag feel like the only way to say so.
## When surge is tuned it needs a gesture that does not collide -- long-press is
## the candidate, and unlike double-tap it does not fight Safari's zoom.
enum Result { NONE, SURGE, DISPATCH, CANCELLED }

const DRAG_THRESHOLD := 12.0     # < 14.8, half a row at the 40-floor ceiling

var _coords: BoardCoords
var _active := false
var _dragging := false
var _press_y := 0.0
var _current_y := 0.0
var _selected_row := 0

func _init(coords: BoardCoords) -> void:
	_coords = coords

func press(y: float, car_floor: int) -> void:
	_active = true
	_dragging = false
	_press_y = y
	_current_y = y
	_selected_row = clampi(car_floor, 0, _coords.floor_count - 1)

func move(y: float) -> void:
	if not _active:
		return
	_current_y = y
	if absf(y - _press_y) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging and not _is_beyond_edge(y):
		_selected_row = _coords.y_to_floor(y)

## A tap and a drag are the same verb; a tap is a drag of zero length. It
## resolves against the PRESS point, not the drift: below DRAG_THRESHOLD the
## thumb never committed to a direction, so where it happened to end up is
## noise. It also ignores the car's floor, which press() seeded the rail with
## for the drag's benefit.
func release() -> int:
	if not _active:
		return Result.NONE
	var out := Result.DISPATCH
	if _dragging:
		if _is_beyond_edge(_current_y):
			out = Result.CANCELLED
	else:
		_selected_row = _coords.y_to_floor(_press_y)
	_active = false
	_dragging = false
	return out

func selected_row() -> int:
	return _selected_row

func is_dragging() -> bool:
	return _dragging

## Cancel is a deliberate gesture: past the top or bottom of the column, with
## half a row of slop. The column spans exactly the floors -- the ghost band is
## outside it -- so this edge never falls inside the lobby's band.
##
## In practice only the top edge is reachable: the board's bottom is the bottom
## of the screen. The rule stays symmetric because asymmetry would be a special
## case with no benefit.
func _is_beyond_edge(y: float) -> bool:
	var h := _coords.row_height
	return y < -h * 0.5 or y > h * (float(_coords.floor_count) + 0.5)
