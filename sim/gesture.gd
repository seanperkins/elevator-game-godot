class_name Gesture
extends RefCounted

## Tells a TAP from a PAN on a shaft column, and nothing else.
##
## It used to classify dispatch itself: a drag onto a floor's band, with detents,
## cancel edges and a rail preview. That model is what forced the board to fit on
## one screen -- an absolute drag can only reach what is visible, so scrolling
## and dispatch-by-drag could not coexist. Handing dispatch to the tap freed the
## drag, and the freed drag is what lets the board be taller than the screen.
##
## What that bought: a fixed 48pt row at any building height, no density tiers,
## no floor cap, and floors below the lobby. What it cost: the rail preview and
## the cancel gesture, both of which existed because a 16pt target invited
## mistakes that a 48pt one does not.
##
## A tap resolves against the PRESS point, never the drift. Below the threshold
## the thumb never committed to a direction, so where it happened to end up is
## noise -- and it means the threshold no longer gates precision, only intent.

enum Result { NONE, TAP, PAN, SURGE }

## Only has to beat thumb wobble now. It used to have to stay under half a row,
## because a drag that crossed a band boundary changed the target.
const DRAG_THRESHOLD := 12.0

var _coords: BoardCoords
var _active := false
var _panning := false
var _press_y := 0.0
var _last_y := 0.0
var _pan_delta := 0.0
var _selected_row := 0

func _init(coords: BoardCoords) -> void:
	_coords = coords

func press(y: float, car_floor: int) -> void:
	_active = true
	_panning = false
	_press_y = y
	_last_y = y
	_pan_delta = 0.0
	_selected_row = car_floor

func move(y: float) -> void:
	if not _active:
		return
	if not _panning and absf(y - _press_y) > DRAG_THRESHOLD:
		_panning = true
		# The travel that PROVED it was a pan belongs to the pan, or the board
		# jumps by the threshold the moment panning starts.
		_pan_delta += _press_y - _last_y
	if _panning:
		_pan_delta += _last_y - y
	_last_y = y

## How far to move the board since this was last asked, and then zero. The view
## adds each report to the offset, so returning a cumulative total would
## accelerate the board away from the thumb.
func take_pan_delta() -> float:
	var d := _pan_delta
	_pan_delta = 0.0
	return d

func release() -> int:
	if not _active:
		return Result.NONE
	var out := Result.PAN if _panning else Result.TAP
	if out == Result.TAP:
		_selected_row = _coords.y_to_floor(_press_y)
	_active = false
	_panning = false
	return out

func selected_row() -> int:
	return _selected_row

func is_panning() -> bool:
	return _panning

## Kept for the harness and for the day surge gets a gesture of its own; a pan
## is not a dispatch and never was one.
func is_dragging() -> bool:
	return _panning
