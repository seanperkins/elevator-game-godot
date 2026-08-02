class_name ChipGrid
extends RefCounted

## Arranges people into a balanced block of squares, wherever they are drawn.
##
## One rule for the hall and for the car, so a passenger looks and packs the
## same before and after boarding -- only the label changes, from a call arrow
## to the floor they pressed.
##
## The shape is `rows = floor(sqrt(n))`, `cols = ceil(n / rows)`:
##
##   1 -> 1      4 -> 2+2      8 -> 4+4
##   2 -> 2      5 -> 3+2      9 -> 3+3+3
##   3 -> 3      6 -> 3+3     12 -> 4+4+4
##
## CEILING on the rows instead would give 8 as 3+3+2 -- one rank taller and
## visibly ragged. Flooring keeps blocks wide and short, which also suits a
## board whose rows lose height as the building grows.
##
## When the area cannot hold the balanced shape the rule gives way rather than
## overflowing: too narrow adds ranks, too short adds columns, and a space too
## small for everyone shows what fits. Nothing is lost by that -- the exact
## count sits beside the strip and the car states its own occupancy.
##
## Pure geometry, no scene tree, so the packing is unit-tested headlessly.

const SIZE := 30.0     # a square: people are the same shape everywhere
const GAP := 4.0

## Columns and rows for `count` items, bounded by what the area can hold.
static func shape(count: int, max_cols: int, max_rows: int) -> Vector2i:
	if count <= 0 or max_cols <= 0 or max_rows <= 0:
		return Vector2i.ZERO
	var rows := maxi(int(sqrt(float(count))), 1)
	var cols := int(ceil(float(count) / float(rows)))
	if cols > max_cols:
		cols = maxi(max_cols, 1)
		rows = int(ceil(float(count) / float(cols)))
	if rows > max_rows:
		rows = maxi(max_rows, 1)
		cols = mini(int(ceil(float(count) / float(rows))), maxi(max_cols, 1))
	return Vector2i(cols, rows)

## How many the shape can actually show.
static func fits(grid: Vector2i) -> int:
	return grid.x * grid.y

## How many columns and rows of SIZE fit an area, given the gaps between them.
## ZERO is a real answer and must not be floored to one: a car at the 40-floor
## cap is 25.6 units tall and a chip is 30, so nothing fits and the caller has
## to fall back to text rather than draw a rank that overflows its own car.
static func columns_for(width: float) -> int:
	return maxi(int((width + GAP) / (SIZE + GAP)), 0)

static func rows_for(height: float) -> int:
	return maxi(int((height + GAP) / (SIZE + GAP)), 0)

## Top-left of item `index`, with the block centred in the area and each rank
## centred on the block, so a short last rank is not left ragged.
static func position_of(index: int, count: int, grid: Vector2i, area: Vector2) -> Vector2:
	if grid.x <= 0 or grid.y <= 0:
		return Vector2.ZERO
	var row := index / grid.x
	var col := index % grid.x
	var in_rank := clampi(count - row * grid.x, 1, grid.x)
	var rank_w := float(in_rank) * SIZE + float(in_rank - 1) * GAP
	var block_h := float(grid.y) * SIZE + float(grid.y - 1) * GAP
	return Vector2(
		(area.x - rank_w) * 0.5 + float(col) * (SIZE + GAP),
		(area.y - block_h) * 0.5 + float(row) * (SIZE + GAP))
