class_name BoardCoords
extends RefCounted

## The single row<->y identity for the board. Floors run bottom-up, and the
## bottom is not necessarily zero: a building with a basement runs from a
## negative floor upward.
##
## ROW HEIGHT IS FIXED, and the board scrolls to whatever does not fit. It used
## to be derived -- `1184 / floors` -- so every floor fitted one screen, and
## that single expression was upstream of every compromise the board made: 16pt
## rows at the cap, the crowd-bar tier, the seat rack collapsing to text, the
## 40-floor limit, and a basement competing with the tower for screen height.
## Those were not six problems. They were one problem counted six times.
##
## Scrolling only became available once dispatch became a TAP. While dispatch
## was an absolute drag, a scrolled board could only dispatch to what was on
## screen, which is why §3.5 rejected it -- a conclusion that followed from the
## input model rather than standing on its own.
##
## All coordinates are COLUMN-LOCAL. The board frame offsets them by the ghost
## band, and BuildingView owns that offset.
##
## The mapping stays an edge table rather than a division. A fixed height makes
## `floor(y/h)` better behaved than the derived one -- where at 29 floors the
## lobby's own top edge resolved to floor 1 -- but "better behaved" is not
## "exact", and the round-trip guarantee costs one array.

var bottom_floor: int = 0
var top_floor: int = 0
var row_height: float
var scroll_offset: float = 0.0

var _viewport_height: float = 0.0
var _edges: PackedFloat64Array = PackedFloat64Array()

## Floors `bottom` through `top` INCLUSIVE, every one `height` tall.
static func fixed(bottom: int, top: int, height: float) -> BoardCoords:
	var c := BoardCoords.new(maxi(top - bottom + 1, 1), height)
	c.bottom_floor = bottom
	c.top_floor = maxi(top, bottom)
	return c

func _init(p_floor_count: int, p_row_height: float) -> void:
	floor_count = maxi(p_floor_count, 1)
	row_height = maxf(p_row_height, 0.001)
	top_floor = floor_count - 1
	for k in range(floor_count + 1):
		_edges.append(float(k) * row_height)

var floor_count: int:
	set(value):
		_floor_count = maxi(value, 1)
	get:
		return _floor_count
var _floor_count: int = 1

## How tall the whole building is, scrolled or not.
func content_height() -> float:
	return float(floor_count) * row_height

## The window the board is looking through. Needed to clamp scrolling: you can
## see past the roof only if there is nothing below to come into view.
func set_viewport_height(height: float) -> void:
	_viewport_height = maxf(height, 0.0)
	scroll_to(scroll_offset)

## Clamped to the building. Scrolling past either end shows nothing useful and
## makes the board feel broken rather than roomy.
func scroll_to(offset: float) -> void:
	var travel := maxf(content_height() - _viewport_height, 0.0)
	scroll_offset = clampf(offset, 0.0, travel)

func scroll_by(delta: float) -> void:
	scroll_to(scroll_offset + delta)

## Top edge of floor f's band, in the scrolled window.
func floor_to_y(f: int) -> float:
	return _unscrolled_y(f) - scroll_offset

func band_centre_y(f: int) -> float:
	return floor_to_y(f) + row_height * 0.5

## Continuous form, for a car at a fractional floor like 2.4 -- or -1.5, on the
## way into the basement. Agrees with floor_to_y bit-for-bit at integers.
func car_y(position_row: float) -> float:
	return (float(top_floor) - position_row) * row_height - scroll_offset

## The floor whose band contains y, by comparison against the same edges
## floor_to_y returns, so the round trip is exact by construction.
func y_to_floor(y: float) -> int:
	var local := y + scroll_offset
	var k := 0
	while k < floor_count - 1 and local >= _edges[k + 1]:
		k += 1
	return top_floor - k

func _unscrolled_y(f: int) -> float:
	return _edges[clampi(top_floor - f, 0, floor_count - 1)]
