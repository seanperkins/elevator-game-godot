class_name HallColumn
extends Control

## The hall region's touch target: TAP opens that floor's panel, DRAG pans the
## board. One input path rather than _gui_input on every FloorRow, so a drag
## crossing a row boundary cannot become ambiguous.
##
## What it takes over from is NOT FloorRow -- FloorRow itself is
## MOUSE_FILTER_IGNORE. It is BuildingView._gui_input, the relet tap path.
##
## It INTRODUCES left-region panning rather than preserving it: today
## BuildingView._gui_input reads releases only, so dragging on the left does
## nothing at all.
##
## Spans the full board height so its local y IS board y and a touch goes
## straight to y_to_floor with no offset arithmetic -- the property that kept
## ShaftColumn correct once the board began to scroll.

signal floor_selected(floor_index: int)
signal pan_requested(delta: Vector2)

var _gesture: Gesture
var _coords: BoardCoords

func setup(coords: BoardCoords) -> void:
	_coords = coords
	_gesture = Gesture.new(coords)

func _gui_input(event: InputEvent) -> void:
	if PointerEvents.is_press(event):
		_gesture.press(event.position, 0)
	elif PointerEvents.is_release(event):
		if _gesture.release() == Gesture.Result.TAP:
			# Belt and braces against the roof clamp: y_to_floor returns
			# top_floor for any y above the building, so a tap in the sky
			# would otherwise select the top floor rather than doing nothing.
			if event.position.y >= _coords.floor_to_y(_coords.top_floor):
				floor_selected.emit(_gesture.selected_row())
	elif PointerEvents.is_drag(event):
		_gesture.move(event.position)
		if _gesture.is_panning():
			var delta := _gesture.take_pan_delta()
			if delta != Vector2.ZERO:
				pan_requested.emit(delta)
