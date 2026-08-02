class_name PointerEvents
extends RefCounted

## Classifies pointer events into press / drag / release, and drops the
## duplicates that touch emulation produces.
##
## Godot emulates mouse events from touches by DEFAULT
## (input_devices/pointing/emulate_mouse_from_touch), so ONE physical touch
## reaches a Control's _gui_input TWICE: once as an
## InputEventScreenTouch and once as a synthetic InputEventMouseButton. Handling
## both families fires every tap target twice -- on iPhone a single tap on the
## ghost floor bought TWO floors, and a single tap on the trailing shaft slot
## bought TWO shafts.
##
## Nothing on the desktop shows it: a real mouse produces no touch event, so the
## whole class of bug lives only on the primary target. It is filtered here
## rather than by turning the project setting off, because the setting is what
## makes Godot's own scrolling and focus behaviour work under a thumb.
##
## The discriminator is the device id, verified on 4.7 rather than assumed:
## emulated mouse events carry -1, a real mouse carries a non-negative id, and
## touch events carry the touch index.
const EMULATED_DEVICE := -1

## True for the synthetic mouse event Godot fabricates from a touch. Its touch
## original is handled, so this copy must not be.
static func is_emulated_duplicate(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return event.device == EMULATED_DEVICE
	return false

static func is_press(event: InputEvent) -> bool:
	if is_emulated_duplicate(event):
		return false
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false

static func is_release(event: InputEvent) -> bool:
	if is_emulated_duplicate(event):
		return false
	if event is InputEventScreenTouch:
		return not event.pressed
	if event is InputEventMouseButton:
		return not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false

static func is_drag(event: InputEvent) -> bool:
	if is_emulated_duplicate(event):
		return false
	return event is InputEventScreenDrag or event is InputEventMouseMotion
