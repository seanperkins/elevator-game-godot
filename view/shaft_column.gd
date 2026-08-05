class_name ShaftColumn
extends Control

## The touch target -- full board height, never the car. TAP dispatches to the
## floor tapped; DRAG pans the board, because a building can now be taller than
## the screen and looking around it is a thing you have to be able to do.
##
## The column control spans the whole board so its local y IS board y, which is
## what lets it hand a touch straight to y_to_floor with no offset arithmetic.
## Only its background is drawn over the building.

signal dispatch_requested(shaft_index: int, floor_index: int)
signal surge_requested(shaft_index: int)
signal pan_requested(delta: Vector2)

## Riders stand on the car's floor in ranks, and a strip of pips across the top
## shows how full the car is. The destination is learned by picking someone up,
## exactly as the seat rack taught it.
##
## There is NO occupancy count while the pips are drawn: lit-versus-hollow IS
## the count. The header line returns only when the car is too short for even
## one rank of figures -- the one case where the picture is gone and the number
## is all there is. The pips keep drawing in every band.
const HEADER_HEIGHT := 20.0
const HEADER_FONT := 16
## Characters that fit across the car at HEADER_FONT, in the no-room fallback.
## Sized for the 220-unit car.
const HEADER_BUDGET := 16

## A font-24 line box is what the 30-unit badge was sized for, and it is 13.1pt
## at the 0.546 iPhone scale. It lives on PersonSprite now, beside the badge it
## sizes; this alias is kept because the header measurements below read it.
## (It was inherited from PassengerSprite.FONT, a class that no longer exists.)
const CAR_FONT := PersonSprite.CAR_FONT

## The doors, as the player sees them: two panels that part over the car.
##
## The dwell is otherwise invisible -- a stop looks exactly like standing still
## -- so the upgrade that dominates early trip time has nothing on screen.
##
## The phases come from ElevatorCar, which owns them because "you cannot board
## through a shut door" is a rule. This only maps ticks to a panel width, and
## the mapping is pinned to the rule by test: the panels are wide open exactly
## when, and only when, the car will accept someone.
##
## They are translucent on purpose. Opaque panels would hide the figures for
## the ~95% of the time a car is shut, which is most of when the player needs to
## read who is aboard and where they are going.
const DOOR_COLOUR := Palette.DOOR

## 0.0 shut, 1.0 wide open. Pure, so the shape is testable without a car.
static func aperture_for(elapsed: int, total: int, opening: int, closing: int) -> float:
	if total <= 0:
		return 0.0
	var e := clampi(elapsed, 0, total)
	if e < opening:
		return float(e) / float(opening)
	if closing > 0 and e >= total - closing:
		return clampf(float(total - e) / float(closing), 0.0, 1.0)
	return 1.0

var shaft_index: int = 0

var _gesture: Gesture
var _coords: BoardCoords
var _shaft_bg: ColorRect
## The two lit rails, left and right. Sized in _layout with the shaft itself so
## they cannot drift out of alignment with it.
var _shaft_edges: Array[ColorRect] = []
## How wide each lit rail is, as a fraction of the shaft. Measured off the
## mockup: its shaft spans x 208-328, with light bands at 208-224 and 304-328,
## so roughly an eighth of the width per side.
const EDGE_FRACTION := 0.125
var _car_rect: ColorRect
var _car_label: Label
var _door_left: ColorRect
var _door_right: ColorRect
var _pips: Array[Rect2] = []
var _lit: int = 0
## What the pip strip last DREW. Compared against, never read for meaning.
var _pip_key: String = ""
var _pip_redraws: int = 0
var _chips: Array[PersonSprite] = []
var _listed: PackedStringArray = PackedStringArray()
var _car_floor_provider: Callable

func setup(index: int, coords: BoardCoords, car_floor_provider: Callable) -> void:
	shaft_index = index
	_coords = coords
	_car_floor_provider = car_floor_provider
	_gesture = Gesture.new(coords)

	# The column CONTROL spans the whole board so its local y is board y and can
	# be handed straight to y_to_floor -- one frame, no offset arithmetic. What
	# is DRAWN is only the building: a shaft that runs up through the sky above
	# the roof reads as scaffolding rather than a lift.
	_shaft_bg = ColorRect.new()
	_shaft_bg.color = Palette.SHAFT_BG
	_shaft_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shaft_bg)

	# Lit edges down both sides, as the mockup draws them: the shaft is not a
	# flat slab there, it is a dark core with the light catching its corners.
	#
	# This matters more here than it does in the mockup, because the layouts
	# differ. The mockup puts people BETWEEN two narrow shafts (~31% of its
	# width); this board keeps people on the left and shafts on the right, so
	# the shafts are a much larger share of the screen and a solid dark rust
	# becomes the heaviest thing on a cream page. The edges break that mass up.
	for i in 2:
		var edge := ColorRect.new()
		edge.color = Palette.SHAFT_EDGE
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(edge)
		_shaft_edges.append(edge)

	_car_rect = ColorRect.new()
	_car_rect.color = Palette.CAR
	_car_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_car_rect)
	_car_rect.draw.connect(_draw_pips)

	# Anchored at the TOP of the car and read against the light body. In the
	# header bands it sits below the pip strip; in the rank bands it is cleared.
	#
	# DARK ink, on a car that is now a MID-luminance teal rather than either
	# extreme. Measured on the mockup's own car colour: cream 2.77:1, this brown
	# 5.21:1. A pale-ink role was written for this and then deleted, because on
	# a mid fill there is no light-ink answer that reads.
	_car_label = Label.new()
	_car_label.add_theme_font_size_override("font_size", HEADER_FONT)
	_car_label.add_theme_color_override("font_color", Palette.INK_ON_LIGHT)
	_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_car_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_rect.add_child(_car_label)

	_door_left = _make_door()
	_door_right = _make_door()

## position_floor is FRACTIONAL -- a car mid-trip sits at 2.4 -- so this uses the
## continuous car_y rather than the integer floor mapping. Coercing to an int
## would make a moving car jump between floors instead of gliding.
func _make_door() -> ColorRect:
	var d := ColorRect.new()
	d.color = DOOR_COLOUR
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# NO z_index. It used to be 1, to sit above riders that _grow_pools adds
	# later -- but z_index is not local: a CanvasItem at z 1 draws above EVERY
	# z-0 node in the canvas layer, so the doors also outranked the FloorPanel
	# and two translucent panels rendered as a car-shaped smear across an open
	# bottom sheet. Ordering among siblings is what was wanted, so _raise_doors()
	# does it by tree position instead.
	d.visible = false
	_car_rect.add_child(d)
	return d

## Keep the doors last among the car's children, so they draw over the riders.
## Called whenever the rider pool grows, because those chips are added after the
## doors were.
func _raise_doors() -> void:
	if _door_left != null:
		_car_rect.move_child(_door_left, -1)
	if _door_right != null:
		_car_rect.move_child(_door_right, -1)

## `open_fraction` is 0.0 shut through 1.0 wide open. The panels meet in the
## middle when shut and retract to the car's edges when open.
func set_doors(open_fraction: float) -> void:
	var half := _car_rect.size.x * 0.5
	var w := half * (1.0 - clampf(open_fraction, 0.0, 1.0))
	_door_left.position = Vector2.ZERO
	_door_left.size = Vector2(w, _car_rect.size.y)
	_door_right.position = Vector2(_car_rect.size.x - w, 0.0)
	_door_right.size = Vector2(w, _car_rect.size.y)
	_door_left.visible = w > 0.5
	_door_right.visible = w > 0.5

func door_width() -> float:
	return _door_left.size.x if _door_left != null else 0.0

func set_car_position(position_floor: float) -> void:
	_shaft_bg.position = Vector2(0, _coords.floor_to_y(_coords.top_floor))
	_shaft_bg.size = Vector2(size.x, _coords.content_height())

	# Same y extent as the shaft, so the rails start and stop with the building
	# rather than running up through the sky above the roof.
	var edge_w := maxf(size.x * EDGE_FRACTION, 1.0)
	for i in _shaft_edges.size():
		var edge: ColorRect = _shaft_edges[i]
		edge.position = Vector2(0.0 if i == 0 else size.x - edge_w,
			_shaft_bg.position.y)
		edge.size = Vector2(edge_w, _shaft_bg.size.y)
	_car_rect.position = Vector2(3, _coords.car_y(position_floor) + 2.0)
	_car_rect.size = Vector2(size.x - 6.0, _coords.floor_height - 4.0)
	_car_label.size = _car_rect.size

## What is aboard, where it is going, and how much room is left.
##
## The pips are the seat rack flattened: one per seat, lit for a rider, hollow
## for a free one. Capacity is 4 to 12 -- small and discrete -- so lit-vs-hollow
## answers "does one more fit" EXACTLY, which a needle could not. They draw at
## every capacity and in every guard band, so occupancy survives even when the
## figures do not.
func set_riders(riders: Array, capacity: int) -> void:
	var area := _car_rect.size
	_pips = CarRack.pips(capacity, area.x)
	_lit = mini(riders.size(), capacity)
	var slots := CarRack.slots(capacity, area.x, area.y)
	# GATED, for the same reason PersonSprite gates its own. _draw_pips emits up
	# to 2 x capacity draw_rect calls per car per frame -- ~192 across eight cars
	# at capacity 12 -- and the picture only changes when the lit count or the
	# pip geometry does. Occupancy changes on a delivery, not on a frame.
	var fingerprint := "%d/%d/%.2f" % [_lit, _pips.size(), area.x]
	if fingerprint != _pip_key:
		_pip_key = fingerprint
		_car_rect.queue_redraw()

	if slots.is_empty():
		_draw_header_only(riders, capacity)
		return

	var cell := CarRack.cell_width(capacity, area.x, CarRack.ranks_for(capacity, area.y))
	_car_label.text = ""
	_grow_pools(slots.size())
	_listed = PackedStringArray()
	for i in range(_chips.size()):
		if i >= slots.size() or i >= riders.size():
			_chips[i].recycle()
			continue
		var p: Passenger = riders[i]
		_chips[i].set_cell(Vector2(cell, CarRack.BAND))
		_chips[i].position = slots[i].position
		_chips[i].show_riding(str(p.destination_floor),
			PersonSprite.key_for(p.origin_floor, p.destination_floor, p.source_floor))
		_listed.append(str(p.destination_floor))
	# Riders past the drawable rank are counted, not dropped -- the short-car
	# band shows fewer figures than the car holds.
	if riders.size() > slots.size():
		_car_label.text = "+%d" % (riders.size() - slots.size())
		_car_label.position = Vector2(0, CarRack.INSET + CarRack.PIP_H)
		_car_label.size = Vector2(area.x, HEADER_HEIGHT)

## The car is too short for even one rank of figures -- below CarRack's
## ONE_RANK_MIN. The picture is gone, so the count comes back, with as many
## destinations as the line can hold. The pips keep drawing.
func _draw_header_only(riders: Array, capacity: int) -> void:
	for chip in _chips:
		chip.recycle()
	_car_label.text = _header_for(riders, capacity)
	_car_label.position = Vector2(0, CarRack.INSET + CarRack.PIP_H)
	_car_label.size = Vector2(_car_rect.size.x, HEADER_HEIGHT)

func _header_for(riders: Array, capacity: int) -> String:
	_listed = PackedStringArray()
	var head := "%d/%d" % [riders.size(), capacity]
	var tail := ""
	for p in riders:
		var floor_text := str((p as Passenger).destination_floor)
		var candidate := tail + " " + floor_text
		if head.length() + candidate.length() > HEADER_BUDGET:
			break
		tail = candidate
		_listed.append(floor_text)
	if _listed.size() < riders.size():
		tail += "+%d" % (riders.size() - _listed.size())
	return head + tail

func _grow_pools(count: int) -> void:
	var grew := false
	while _chips.size() < count:
		var chip := PersonSprite.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_car_rect.add_child(chip)
		chip.recycle()
		_chips.append(chip)
		grew = true
	if grew:
		_raise_doors()

## Counts what the strip actually RE-RECORDED, the same seam PersonSprite
## exposes. Without it set_riders' gate can only be tested by asserting its own
## assignment back to itself.
func pip_redraw_count() -> int:
	return _pip_redraws

## Two rects per pip: its own track, and a lit fill inset inside it. The track
## is PER PIP rather than one bar behind them all -- two adjacent hollows on a
## shared track merge into a single dark band, and counting free seats is the
## one job the strip has.
func _draw_pips() -> void:
	_pip_redraws += 1
	for i in _pips.size():
		_car_rect.draw_rect(_pips[i], Palette.PERSON_BAR_TRACK)
		if i < _lit:
			_car_rect.draw_rect((_pips[i] as Rect2).grow(-1.0), Palette.PIP_LIT)

## Destinations the car is actually showing, in boarding order.
func rider_destinations() -> PackedStringArray:
	return _listed

## Pips, not seats -- but the question is the same one, so the names are.
func seats_taken() -> int:
	return _lit

func free_slots_shown() -> int:
	return maxi(_pips.size() - _lit, 0)

func car_text() -> String:
	return _car_label.text if _car_label != null else ""

## Routed through PointerEvents, which drops the synthetic mouse copy that touch
## emulation makes of every touch. Without it one thumb ran the state machine
## twice per gesture.
## Routed through PointerEvents, which drops the synthetic mouse copy that touch
## emulation makes of every touch. Without it one thumb ran the state machine
## twice per gesture.
func _gui_input(event: InputEvent) -> void:
	if PointerEvents.is_press(event):
		_gesture.press(event.position, _car_floor_provider.call())
	elif PointerEvents.is_release(event):
		match _gesture.release():
			Gesture.Result.TAP:
				dispatch_requested.emit(shaft_index, _gesture.selected_floor())
			Gesture.Result.SURGE:
				surge_requested.emit(shaft_index)
			_:
				pass
	elif PointerEvents.is_drag(event):
		_gesture.move(event.position)
		if _gesture.is_panning():
			var delta := _gesture.take_pan_delta()
			if delta != Vector2.ZERO:
				pan_requested.emit(delta)
