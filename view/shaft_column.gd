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

## The car is a set of SEATS, not a box with a number on it. Every seat is
## drawn: occupied ones hold the same chip the passenger had in the hall (now
## showing the floor they pressed), empty ones are dim outlines, so "how many
## more fit" is a glance rather than arithmetic. Capacity starts at four and
## upgrades to twelve, which is three rows of four.
## The car reads as a header line plus a rack of seats.
##
## The FLOORS live in the header, not on the seats. A shaft column is 92 units
## -- 50.2 pt on the iPhone -- so four seats across leaves each about 11 pt of
## width, and two digits in that space land near 6 pt whatever font is chosen.
## Moving the numbers to a full-width line buys roughly 9 pt of type without
## giving up a visible shaft.
##
## Seats therefore carry no text, which is what lets them be short: 12 units
## instead of 20. That is why the grid survives to about 30 floors rather than
## 17. Filled means taken and is tinted by that rider's patience; hollow means
## free, so remaining room is a glance rather than a subtraction.
const SEAT_SIZE := Vector2(20.0, 12.0)
const SEAT_PITCH := Vector2(22.0, 14.0)
const SEATS_PER_ROW := 4
const HEADER_HEIGHT := 20.0
const HEADER_FONT := 16
## Characters that fit across an 86-unit car at HEADER_FONT. Destinations are
## listed until the budget runs out and then collapse to a tail count, so a
## twelve-seat car cannot push the line past the column.
const HEADER_BUDGET := 11

const SEAT_FREE := Color("1b6d92")
const GREEN := Color("4ade80")
const RED := Color("ef4444")

signal dispatch_requested(shaft_index: int, floor_index: int)
signal surge_requested(shaft_index: int)

var shaft_index: int = 0

var _gesture: Gesture
var _coords: BoardCoords
var _selector: FloorSelector
var _car_rect: ColorRect
var _car_label: Label
var _seats: Array[ColorRect] = []
var _listed: PackedStringArray = PackedStringArray()
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

	# Anchored at the TOP of the car and read against the light body. Centred
	# vertically it collided with the seats and sat where nothing else does.
	_car_label = Label.new()
	_car_label.add_theme_font_size_override("font_size", HEADER_FONT)
	_car_label.add_theme_color_override("font_color", Color("06202e"))
	_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
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

## What is aboard, where it is going, and how much room is left.
##
## Capacity starts at FOUR, so a car is routinely full and "is there room"
## decides whether dispatching here does anything at all.
##
## The grid is dropped when it will not fit -- at the 40-floor cap the car is
## 25.6 units tall, which is one line of text and nothing else. The header stays
## at every size, so the count and the floors are never lost, only the picture.
func set_riders(riders: Array, capacity: int) -> void:
	_car_label.text = _header_for(riders, capacity)
	_car_label.position = Vector2(0, 1)
	_car_label.size = Vector2(_car_rect.size.x, HEADER_HEIGHT)

	var rows := int(ceil(float(maxi(capacity, 1)) / float(SEATS_PER_ROW)))
	if HEADER_HEIGHT + float(rows) * SEAT_PITCH.y > _car_rect.size.y:
		for seat in _seats:
			seat.visible = false
		return

	_grow_seats(capacity)
	var grid_w := float(mini(capacity, SEATS_PER_ROW)) * SEAT_PITCH.x \
		- (SEAT_PITCH.x - SEAT_SIZE.x)
	var left := maxf((_car_rect.size.x - grid_w) * 0.5, 0.0)
	for i in range(_seats.size()):
		if i >= capacity:
			_seats[i].visible = false
			continue
		_seats[i].visible = true
		_seats[i].position = Vector2(
			left + float(i % SEATS_PER_ROW) * SEAT_PITCH.x,
			HEADER_HEIGHT + float(i / SEATS_PER_ROW) * SEAT_PITCH.y)
		if i < riders.size():
			var p: Passenger = riders[i]
			_seats[i].color = RED.lerp(GREEN, clampf(p.patience_fraction(), 0.0, 1.0))
		else:
			_seats[i].color = SEAT_FREE

## "2/4  5 12". Destinations are listed until the character budget runs out,
## then collapse to a tail count, because the line cannot grow past the column.
func _header_for(riders: Array, capacity: int) -> String:
	_listed = PackedStringArray()
	var head := "%d/%d" % [riders.size(), capacity]
	var tail := ""
	for p in riders:
		var floor_text := str((p as Passenger).destination_row)
		var candidate := tail + " " + floor_text
		if head.length() + candidate.length() > HEADER_BUDGET:
			break
		tail = candidate
		_listed.append(floor_text)
	if _listed.size() < riders.size():
		tail += "+%d" % (riders.size() - _listed.size())
	return head + tail

func _grow_seats(capacity: int) -> void:
	while _seats.size() < capacity:
		var seat := ColorRect.new()
		seat.color = SEAT_FREE
		seat.size = SEAT_SIZE
		seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_car_rect.add_child(seat)
		_seats.append(seat)

## The destinations the header is actually showing, in boarding order.
func rider_destinations() -> PackedStringArray:
	return _listed

func seats_taken() -> int:
	var n := 0
	for seat in _seats:
		if seat.visible and seat.color != SEAT_FREE:
			n += 1
	return n

func free_slots_shown() -> int:
	var n := 0
	for seat in _seats:
		if seat.visible and seat.color == SEAT_FREE:
			n += 1
	return n

func car_text() -> String:
	return _car_label.text if _car_label != null else ""

## Routed through PointerEvents, which drops the synthetic mouse copy that touch
## emulation makes of every touch. Without it one thumb ran the state machine
## twice per gesture.
func _gui_input(event: InputEvent) -> void:
	if PointerEvents.is_press(event):
		_gesture.press(event.position.y, _car_floor_provider.call())
		_selector.show_at(_gesture.selected_row())
	elif PointerEvents.is_release(event):
		var result := _gesture.release()
		_selector.hide_rail()
		match result:
			Gesture.Result.DISPATCH:
				dispatch_requested.emit(shaft_index, _gesture.selected_row())
			Gesture.Result.SURGE:
				surge_requested.emit(shaft_index)
			_:
				pass
	elif PointerEvents.is_drag(event):
		_gesture.move(event.position.y)
		if _gesture.is_dragging():
			_selector.show_at(_gesture.selected_row())
