class_name ShaftColumn
extends Control

## The touch target -- full column height, never the car. Both verbs dispatch:
## a drag sends the car where you release, a tap sends it where you touched.
##
## The surge branch below is unreachable for now -- Gesture stopped producing
## SURGE when the tap became a dispatch. It stays wired so re-enabling surge is
## a change in one place, once it has a gesture that does not collide.
##
## The column spans the FLOORS only; the ghost band is above it and belongs to
## the floor-purchase target. That inset is what keeps Gesture's cancel edge
## from falling inside the lobby's dispatch band.

## How many rider destinations the car lists before collapsing to a tail count.
const RIDERS_LISTED := 3

signal dispatch_requested(shaft_index: int, floor_index: int)
signal surge_requested(shaft_index: int)

var shaft_index: int = 0

var _gesture: Gesture
var _coords: BoardCoords
var _selector: FloorSelector
var _car_rect: ColorRect
var _car_label: Label
var _car_floor_provider: Callable

func setup(index: int, coords: BoardCoords, car_floor_provider: Callable) -> void:
	shaft_index = index
	_coords = coords
	_car_floor_provider = car_floor_provider
	_gesture = Gesture.new(coords)

	var shaft_bg := ColorRect.new()
	shaft_bg.color = Color("1b2430")
	shaft_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	shaft_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shaft_bg)

	_car_rect = ColorRect.new()
	_car_rect.color = Color("4cc2ff")
	_car_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_car_rect)

	_car_label = Label.new()
	_car_label.add_theme_font_size_override("font_size", 12)
	_car_label.add_theme_color_override("font_color", Color("06202e"))
	_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_car_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_rect.add_child(_car_label)

	_selector = FloorSelector.new()
	_selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_selector)
	_selector.configure(coords)

## position_row is FRACTIONAL -- a car mid-trip sits at 2.4 -- so this uses the
## continuous car_y rather than the integer floor mapping. Coercing to an int
## would make a moving car jump between floors instead of gliding.
func set_car_position(position_row: float) -> void:
	_car_rect.position = Vector2(3, _coords.car_y(position_row) + 2.0)
	_car_rect.size = Vector2(size.x - 6.0, _coords.row_height - 4.0)
	_car_label.size = _car_rect.size

## What is aboard, and where it is going. Capacity starts at FOUR, so a car is
## routinely full and "is there room" decides whether dispatching here does
## anything at all -- an opaque box makes that unknowable until after the doors
## close on nobody.
##
## Destinations are listed in queue order and truncated with a tail count rather
## than scrolled: the car is 90 units wide at the shipped column, and at the
## 40-floor cap it is 25.6 units tall, which is one line of text.
func set_riders(riders: Array, capacity: int) -> void:
	var text := "%d/%d" % [riders.size(), capacity]
	if not riders.is_empty():
		var shown := mini(riders.size(), RIDERS_LISTED)
		var floors := PackedStringArray()
		for i in range(shown):
			floors.append(str((riders[i] as Passenger).destination_row))
		text += "  " + " ".join(floors)
		if riders.size() > shown:
			text += "+%d" % (riders.size() - shown)
	_car_label.text = text

func car_text() -> String:
	return _car_label.text if _car_label != null else ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var local_y: float = event.position.y
		if pressed:
			_gesture.press(local_y, _car_floor_provider.call())
			_selector.show_at(_gesture.selected_row())
		else:
			var result := _gesture.release()
			_selector.hide_rail()
			match result:
				Gesture.Result.DISPATCH:
					dispatch_requested.emit(shaft_index, _gesture.selected_row())
				Gesture.Result.SURGE:
					surge_requested.emit(shaft_index)
				_:
					pass
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		_gesture.move(event.position.y)
		if _gesture.is_dragging():
			_selector.show_at(_gesture.selected_row())
