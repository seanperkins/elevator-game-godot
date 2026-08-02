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
## The car is a rack of seats. Each one is the same little square the passenger
## was in the hall, now showing the floor they pressed instead of a call arrow:
## the destination is learned by picking someone up.
##
## There is NO occupancy count while the rack is drawn. Four filled squares of
## four is the count -- printing "4/4" beside it says the same thing twice and
## spends the only line of type the car has. The count returns only when the row
## is too short to draw seats at all, which is the one case where the picture is
## gone and the number is all there is.
const SEAT_SIZE := Vector2(ChipGrid.SIZE, ChipGrid.SIZE)
const SEAT_FONT := PassengerSprite.FONT
const HEADER_HEIGHT := 20.0
const HEADER_FONT := 16
## Characters that fit across the car at HEADER_FONT, in the no-room fallback.
const HEADER_BUDGET := 16

const SEAT_FREE := Color("1b6d92")

signal dispatch_requested(shaft_index: int, floor_index: int)
signal surge_requested(shaft_index: int)

var shaft_index: int = 0

var _gesture: Gesture
var _coords: BoardCoords
var _selector: FloorSelector
var _car_rect: ColorRect
var _car_label: Label
var _seats: Array[ColorRect] = []
var _chips: Array[PassengerSprite] = []
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

## What is aboard, where it is going, and how much room is left -- as a picture
## when there is room to draw one, and as a line of text when there is not.
##
## Capacity starts at FOUR, so a car is routinely full and "is there room"
## decides whether dispatching here does anything at all. Hollow seats answer
## that at a glance; a subtraction does not.
func set_riders(riders: Array, capacity: int) -> void:
	var area := _car_rect.size
	var grid := ChipGrid.shape(capacity,
		ChipGrid.columns_for(area.x), ChipGrid.rows_for(area.y))
	# Every seat or none: a rack that shows six of eight answers "how many more
	# fit" with a lie, which is the one question it exists to answer.
	if ChipGrid.fits(grid) < capacity:
		_draw_header_only(riders, capacity)
		return

	_car_label.text = ""
	_grow_pools(capacity)
	_listed = PackedStringArray()
	for i in range(_seats.size()):
		if i >= capacity:
			_seats[i].visible = false
			_chips[i].recycle()
			continue
		var at := ChipGrid.position_of(i, capacity, grid, area)
		if i < riders.size():
			_seats[i].visible = false
			var p: Passenger = riders[i]
			_chips[i].position = at
			_chips[i].show_as(p.patience_fraction(), str(p.destination_row))
			_listed.append(str(p.destination_row))
		else:
			_chips[i].recycle()
			_seats[i].visible = true
			_seats[i].position = at

## The row is too short for even one rank of seats -- at the 40-floor cap the
## car is 25.6 units tall. The picture is gone, so the count comes back, with as
## many destinations as the line can hold.
func _draw_header_only(riders: Array, capacity: int) -> void:
	for seat in _seats:
		seat.visible = false
	for chip in _chips:
		chip.recycle()
	_car_label.text = _header_for(riders, capacity)
	_car_label.position = Vector2(0, 1)
	_car_label.size = Vector2(_car_rect.size.x, HEADER_HEIGHT)

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

func _grow_pools(capacity: int) -> void:
	while _seats.size() < capacity:
		var seat := ColorRect.new()
		seat.color = SEAT_FREE
		seat.size = SEAT_SIZE
		seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_car_rect.add_child(seat)
		_seats.append(seat)

		var chip := PassengerSprite.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_car_rect.add_child(chip)
		chip.set_chip(SEAT_SIZE, SEAT_FONT)
		chip.recycle()
		_chips.append(chip)

## Destinations the car is actually showing, in boarding order.
func rider_destinations() -> PackedStringArray:
	return _listed

func seats_taken() -> int:
	var n := 0
	for chip in _chips:
		if chip.visible:
			n += 1
	return n

func free_slots_shown() -> int:
	var n := 0
	for seat in _seats:
		if seat.visible:
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
