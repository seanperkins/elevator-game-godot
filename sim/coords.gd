class_name BoardCoords
extends RefCounted

## The single floor<->y identity for the board. Floors run bottom-up, and the
## bottom is not necessarily zero: a building with a basement runs from a
## negative floor upward.
##
## ROW HEIGHT IS FIXED, and the board scrolls to whatever does not fit. It used
## to be derived -- `1184 / floors` -- so every floor fitted one screen, and
## that single expression was upstream of every compromise the board made: 16pt
## floors at the cap, the crowd-bar tier, the seat rack collapsing to text, the
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
var floor_height: float
var scroll_offset: float = 0.0

## Content ABOVE the top floor that scrolling has to be able to reach: the ghost
## band. It is not part of content_height(), because it is not part of the
## building -- floor_to_y, y_to_floor and the edge table must keep answering
## about floors that exist. It only widens the scroll clamp.
##
## Without it the band sits at floor_to_y(top) - floor_height, which is above the
## window at every legal offset once the building is taller than the viewport.
## That is a UX bug with teeth: at the run's floor cap the band stops selling a
## floor and starts offering PRESTIGE, so the board's only route to demolishing
## vanished exactly when it became the thing you wanted.
var headroom: float = 0.0
## The mirror: content BELOW the bottom floor that scrolling must reach -- the
## dig band. Widens the UPPER clamp for the same reason headroom widens the
## lower one: the band is a control, and a control the scroll range cannot
## reach is not a control.
var footroom: float = 0.0

var _viewport_height: float = 0.0
var _edges: PackedFloat64Array = PackedFloat64Array()

## Floors `bottom` through `top` INCLUSIVE, every one `height` tall.
static func fixed(bottom: int, top: int, height: float) -> BoardCoords:
	var c := BoardCoords.new(maxi(top - bottom + 1, 1), height)
	c.bottom_floor = bottom
	c.top_floor = maxi(top, bottom)
	return c

func _init(p_floor_count: int, p_floor_height: float) -> void:
	floor_count = maxi(p_floor_count, 1)
	floor_height = maxf(p_floor_height, 0.001)
	top_floor = floor_count - 1
	for k in range(floor_count + 1):
		_edges.append(float(k) * floor_height)

var floor_count: int:
	set(value):
		_floor_count = maxi(value, 1)
	get:
		return _floor_count
var _floor_count: int = 1

## How tall the whole building is, scrolled or not.
func content_height() -> float:
	return float(floor_count) * floor_height

## The window the board is looking through. Needed to clamp scrolling: you can
## see past the roof only if there is nothing below to come into view.
func set_viewport_height(height: float) -> void:
	_viewport_height = maxf(height, 0.0)
	scroll_to(scroll_offset)

## Clamped to the building, plus whatever headroom is asked for. Scrolling past
## either end shows nothing useful and makes the board feel broken rather than
## roomy.
##
## The lower bound is NEGATIVE by the headroom the sky above the roof does not
## already show. A short building already floats down on _ground_offset with the
## band visible above it, so there is nothing to reveal and the bound stays 0;
## it is the tall building, where the ground offset is zero, that needs to scroll
## back past the roof.
func scroll_to(offset: float) -> void:
	var travel := maxf(content_height() + footroom - _viewport_height, 0.0)
	var sky := maxf(headroom - _ground_offset(), 0.0)
	scroll_offset = clampf(offset, -sky, travel)

func scroll_by(delta: float) -> void:
	scroll_to(scroll_offset + delta)

## A building STANDS ON THE GROUND. When it is shorter than the window, the
## slack goes above it -- the lobby stays at the bottom of the screen and the
## empty space is sky, which is also where the "+ BUILD FLOOR" band lives. Left
## unhandled, a six-floor tower hangs from the top of the board with a void
## beneath it and the ghost floor off-screen entirely.
##
## FOOTROOM COMES OUT OF THE GROUND, not out of the scroll range, on a short
## building: the building stands on the dig band -- the earth -- rather than on
## the screen edge, so the band is visible without scrolling. On a tall building
## the ground offset is zero either way and the band is reached by scrolling
## through the widened travel in scroll_to.
func _ground_offset() -> float:
	return maxf(_viewport_height - content_height() - footroom, 0.0)

## Top edge of floor f's band, in the scrolled window.
func floor_to_y(f: int) -> float:
	return _unscrolled_y(f) + _ground_offset() - scroll_offset

func band_centre_y(f: int) -> float:
	return floor_to_y(f) + floor_height * 0.5

## Continuous form, for a car at a fractional floor like 2.4 -- or -1.5, on the
## way into the basement. Agrees with floor_to_y bit-for-bit at integers.
func car_y(position_floor: float) -> float:
	return (float(top_floor) - position_floor) * floor_height \
		+ _ground_offset() - scroll_offset

## The floor whose band contains y, by comparison against the same edges
## floor_to_y returns, so the round trip is exact by construction.
func y_to_floor(y: float) -> int:
	var local := y + scroll_offset - _ground_offset()
	var k := 0
	while k < floor_count - 1 and local >= _edges[k + 1]:
		k += 1
	return top_floor - k

func _unscrolled_y(f: int) -> float:
	return _edges[clampi(top_floor - f, 0, floor_count - 1)]
