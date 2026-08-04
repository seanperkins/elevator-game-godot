class_name CarRack
extends RefCounted

## Where riders stand in a car, and how full it looks. Pure geometry, no scene
## tree, so every number is unit-tested headlessly -- the same treatment
## ChipGrid gets, and for the same reason: this is the part that will be wrong
## first.
##
## Riders stand in ONE rank on the floor of the car until capacity passes five,
## then a second rank stands behind and half a pitch across, so a back figure
## sits between two front badges rather than directly behind one.
##
## THE CELL BUDGET INCLUDES THE OFFSET. An earlier draft derived the cell to
## fill the car and then added the half-pitch on top; at capacities 10 and 12
## the back rank left the car by up to 19 units. The offset is paid for here.

const GAP := 4.0
## The widest a cell gets. Past this a four-rider car spreads into a line of
## lonely figures instead of a group.
const CELL_MAX := 40.0
## The narrowest cell that can still carry a two-digit badge.
const CELL_MIN := 30.0

const PIP_GAP := 3.0
## Below this a pip is a smear rather than a countable thing.
const PIP_MIN := 6.0
const PIP_H := 8.0
const PIP_INSET := 8.0

const INSET := 2.0
const BADGE_H := 30.0
const FIGURE_H := 22.0
const BAND := BADGE_H + FIGURE_H                    # 52
const ONE_RANK_MIN := INSET + PIP_H + BAND          # 62
const TWO_RANK_MIN := INSET + PIP_H + BAND * 2.0    # 114
const ONE_RANK_CAP := 5

## 0, 1 or 2. Three bands, because one rank and two ranks need different room:
## below 62 there is space for neither, and the header line carries everything.
static func ranks_for(capacity: int, car_h: float) -> int:
	if capacity <= 0 or car_h < ONE_RANK_MIN:
		return 0
	if car_h < TWO_RANK_MIN:
		return 1
	return 1 if capacity <= ONE_RANK_CAP else 2

## How many stand in the front rank. At two ranks the front takes the extra, so
## an odd capacity leans forward. At one rank in a short car the count is set by
## WIDTH -- one rank of twelve would be 14.7 units a cell.
static func front_count(capacity: int, car_w: float, ranks: int) -> int:
	if ranks <= 0 or capacity <= 0:
		return 0
	if ranks == 2:
		return int(ceil(float(capacity) / 2.0))
	var n := capacity
	while n > 1 and (car_w - GAP * float(n - 1)) / float(n) < CELL_MIN:
		n -= 1
	return n

static func cell_width(capacity: int, car_w: float, ranks: int) -> float:
	var front := front_count(capacity, car_w, ranks)
	if front <= 0:
		return 0.0
	if ranks == 2:
		# The +0.5 and the -GAP/2 are the half-pitch offset, budgeted rather
		# than added afterwards.
		return minf(CELL_MAX,
			(car_w - GAP * float(front - 1) - GAP * 0.5) / (float(front) + 0.5))
	return minf(CELL_MAX, (car_w - GAP * float(front - 1)) / float(front))

## Front rank first, then back. Index order is boarding order, so rider i is
## slot i.
static func slots(capacity: int, car_w: float, car_h: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ranks := ranks_for(capacity, car_h)
	if ranks <= 0:
		return out
	var front := front_count(capacity, car_w, ranks)
	var back := 0 if ranks == 1 else capacity - front
	var cell := cell_width(capacity, car_w, ranks)
	var pitch := cell + GAP
	var front_w := float(front) * cell + float(front - 1) * GAP
	var back_w := (float(back) * cell + float(back - 1) * GAP) if back > 0 else 0.0
	# Centre the COMPOSITION, not the front rank -- centring the front rank and
	# then offsetting the back is what pushed it out of the car.
	var comp := front_w if back <= 0 else maxf(front_w, pitch * 0.5 + back_w)
	var x0 := (car_w - comp) * 0.5
	# Feet sit INSET above the car floor; in the short band the rank is pushed
	# down to clear the pip strip instead.
	var front_top := maxf(INSET + PIP_H, car_h - INSET - BAND)
	var back_top := front_top - BAND
	for i in front:
		out.append(Rect2(x0 + float(i) * pitch, front_top, cell, BAND))
	for i in back:
		out.append(Rect2(x0 + pitch * 0.5 + float(i) * pitch, back_top, cell, BAND))
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
