class_name FloorIndex
extends RefCounted

## Which array slot a FLOOR occupies. There is exactly one of these per building:
## Building, Tenancy and Fitout share the same instance by reference, so a
## desync between them is not a bug to test for -- it is unrepresentable.
##
## Fitout's docstring rejected a shared index object, and was right to while the
## bottom floor was always 0: the mapping was the identity and earned nothing.
## Digging deletes that precondition. What the rejection got right, and what this
## class is shaped by, is that a COPIED offset turns a container desync from a
## loud out-of-range access into a silent valid-but-wrong index -- floor -1
## reading floor -2's slot, in range, wrong answer, and an "the arrays are the
## same length" test passing straight through it. One instance, not three.

## The lowest floor in the building: -depth.
var bottom: int = 0
## One past the top: floor_count.
var above: int = 1

func _init(p_bottom: int = 0, p_above: int = 1) -> void:
	bottom = p_bottom
	above = maxi(p_above, p_bottom + 1)

## The array slot for a floor. Callers MUST have checked holds() first; this does
## not bounds-check, because a caller that skips the check should fail loudly on
## the array access rather than quietly here.
func slot(f: int) -> int:
	return f - bottom

func holds(f: int) -> bool:
	return f >= bottom and f < above

func size() -> int:
	return above - bottom

## A new floor at the BOTTOM. Every existing floor's slot shifts up by one, which
## is why callers insert at the front of their arrays rather than appending.
func dig() -> void:
	bottom -= 1

func grow_up() -> void:
	above += 1
