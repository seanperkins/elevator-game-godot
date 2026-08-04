class_name DragScroll
extends RefCounted

## Lets a thumb drag a ScrollContainer whose content is made of buttons.
##
## A Button is MOUSE_FILTER_STOP, so it consumes the press before the
## ScrollContainer beneath it ever sees one -- and a panel that IS a list of
## buttons therefore only scrolls in the few units of gap between them. That is
## what "scrolling doesn't work properly" on the management screen was.
##
## The board already had this problem and already answered it: a tap commands, a
## drag pans (`sim/gesture.gd`). This is the same answer for a list, and it
## borrows the same threshold so a thumb behaves identically on both surfaces.
##
## THE RELEASE MATTERS AS MUCH AS THE DRAG. These buttons spend money and one of
## them demolishes the building, so a drag that ends over a button must not also
## press it. Once panning starts, this swallows the release.

## Shared with Gesture on purpose: one wobble tolerance for the whole game.
const THRESHOLD := Gesture.DRAG_THRESHOLD

var _scroll: ScrollContainer
var _down := false
var _panning := false
var _press := Vector2.ZERO
var _last := Vector2.ZERO

func _init(scroll: ScrollContainer) -> void:
	_scroll = scroll

func is_panning() -> bool:
	return _panning

## Call from the owner's `_input`, which runs BEFORE the buttons get their turn.
## Returns true when the event has been consumed and the caller should mark it
## handled -- doing that here would couple this to a viewport it does not own.
##
## `rect` is the owner's screen rect: events outside it belong to somebody else,
## and the management screen sits under a HUD that is still live.
func handle(event: InputEvent, rect: Rect2) -> bool:
	if _scroll == null:
		return false
	if PointerEvents.is_press(event):
		if not rect.has_point(event.position):
			return false
		_down = true
		_panning = false
		_press = event.position
		_last = event.position
		return false                      # a press is still a press until it moves
	if PointerEvents.is_drag(event) and _down:
		if not _panning and _press.distance_to(event.position) < THRESHOLD:
			return false                  # thumb wobble, not intent
		_panning = true
		# Content follows the thumb: drag UP and the list moves up, which is the
		# direction every other scrolling surface on the phone uses.
		_scroll.scroll_vertical -= int(event.position.y - _last.y)
		_last = event.position
		return true
	if PointerEvents.is_release(event):
		var was := _panning
		_down = false
		_panning = false
		return was                        # swallow the release that ended a drag
	return false
