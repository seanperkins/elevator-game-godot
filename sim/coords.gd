class_name BoardCoords
extends RefCounted

## The single row<->y identity for the board. Floors run bottom-up: floor 0 is
## the lobby at the bottom, and y = 0 is the TOP floor's top edge.
##
## All coordinates are COLUMN-LOCAL. The board frame offsets them by the ghost
## band -- board_y = ghost_height + local_y -- and BuildingView owns that offset.
##
## The mapping is an edge table rather than a division, deliberately. Computing
## y_to_floor as N-1-floor(y/h) is not an identity in IEEE double: at N=29,
## 28*h = 1105.0666666666666 and dividing by h gives 27.999999999999996, so the
## lobby's own top edge resolves to floor 1. Twelve of the forty floor counts
## have at least one floor that fails that way. Comparing against the same
## stored edges makes the round trip exact by construction.

var floor_count: int
var row_height: float

var _edges: PackedFloat64Array = PackedFloat64Array()

func _init(p_floor_count: int, p_row_height: float) -> void:
	floor_count = maxi(p_floor_count, 1)
	row_height = maxf(p_row_height, 0.001)
	for k in range(floor_count + 1):
		_edges.append(float(k) * row_height)

## Top edge of floor f's band. Exact: a stored value, not a computation.
func floor_to_y(f: int) -> float:
	return _edges[clampi(floor_count - 1 - f, 0, floor_count - 1)]

func band_centre_y(f: int) -> float:
	return floor_to_y(f) + row_height * 0.5

## Continuous form, for a car at a fractional row like 2.4. Agrees with
## floor_to_y bit-for-bit at integer positions -- the same expression.
func car_y(position_row: float) -> float:
	return (float(floor_count - 1) - position_row) * row_height

## The floor whose band contains y, found by comparison against the same edges
## floor_to_y returns. Linear over at most 40 bands, once per touch event.
func y_to_floor(y: float) -> int:
	var k := 0
	while k < floor_count - 1 and y >= _edges[k + 1]:
		k += 1
	return floor_count - 1 - k
