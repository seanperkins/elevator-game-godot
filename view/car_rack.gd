class_name CarRack
extends RefCounted

## Where riders stand in a car, and how full it looks. Pure geometry, no scene
## tree, so every number is unit-tested headlessly -- the same treatment
## ChipGrid gets, and for the same reason: this is the part that will be wrong
## first.
##
## RIDERS STAND IN ONE RANK on the floor of the car, as many as can be drawn at
## a legible size. A second rank was built first and then removed: a person is
## 26 x 41 (see PersonSprite -- at 14 x 22 a whole person was shorter than one
## digit of their own badge), so a band is 30 + 41 = 71, and two of those need
## 142 units in the 106 a 116-unit car has after its pip strip. Two ranks are
## only possible with figures too small to be worth drawing.
##
## So the car does what the hall does: draw fewer people, properly, and let the
## count carry the rest. The PIPS remain exact at every capacity, so nothing
## about "is there room" depends on how many figures fit.

const GAP := 4.0
## The widest a cell gets. Past this a four-rider car spreads into a line of
## lonely figures instead of a group.
const CELL_MAX := 52.0
## The narrowest cell that can still carry a two-digit badge: two digits at
## font 24 measure ~26.4 units, plus 2 units of padding a side.
const CELL_MIN := 32.0

const PIP_GAP := 3.0
## Below this a pip is a smear rather than a countable thing.
const PIP_MIN := 6.0
const PIP_H := 8.0
const PIP_INSET := 8.0

const INSET := 2.0
const BADGE_H := 30.0
const FIGURE_H := 41.0
const BAND := BADGE_H + FIGURE_H            # 71
## Below this there is no room for a rank at all and the header line is the
## whole story -- though the pips still draw.
const ONE_RANK_MIN := INSET + PIP_H + BAND  # 81

## 0 or 1. There is no two-rank case; see the class docstring.
static func ranks_for(capacity: int, car_h: float) -> int:
	if capacity <= 0 or car_h < ONE_RANK_MIN:
		return 0
	return 1

## How many stand in the rank: as many as fit at CELL_MIN, capped by capacity.
## Riders past this are counted in the header rather than drawn.
static func front_count(capacity: int, car_w: float, ranks: int) -> int:
	if ranks <= 0 or capacity <= 0:
		return 0
	var n := capacity
	while n > 1 and (car_w - GAP * float(n - 1)) / float(n) < CELL_MIN:
		n -= 1
	return n

static func cell_width(capacity: int, car_w: float, ranks: int) -> float:
	var front := front_count(capacity, car_w, ranks)
	if front <= 0:
		return 0.0
	return minf(CELL_MAX, (car_w - GAP * float(front - 1)) / float(front))

## One rect per drawn rider, centred as a block, feet INSET above the car floor.
## Fewer than `capacity` when the car cannot draw them all legibly.
static func slots(capacity: int, car_w: float, car_h: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ranks := ranks_for(capacity, car_h)
	if ranks <= 0:
		return out
	var front := front_count(capacity, car_w, ranks)
	var cell := cell_width(capacity, car_w, ranks)
	var block := float(front) * cell + float(front - 1) * GAP
	var x0 := (car_w - block) * 0.5
	# Feet sit INSET above the floor; in a short car the rank is pushed down to
	# clear the pip strip instead.
	var top := maxf(INSET + PIP_H, car_h - INSET - BAND)
	for i in front:
		out.append(Rect2(x0 + float(i) * (cell + GAP), top, cell, BAND))
	return out

## One rect per seat, lit or hollow decided by the caller. Empty when a pip
## would be too small to count -- occupancy then falls to the header's number.
static func pips(capacity: int, car_w: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if capacity <= 0:
		return out
	var track := car_w - PIP_INSET * 2.0
	var w := (track - PIP_GAP * float(capacity - 1)) / float(capacity)
	if w < PIP_MIN:
		return out
	for i in capacity:
		out.append(Rect2(PIP_INSET + float(i) * (w + PIP_GAP), INSET, w, PIP_H))
	return out
