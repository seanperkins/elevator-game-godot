class_name ChipGrid
extends RefCounted

## Arranges people into a balanced block, wherever they are drawn.
##
## The CELL is the unit of packing. It used to be a square -- people were the
## same shape everywhere, and the same rule laid out the hall and the car. That
## invariant is gone: a hall person is a 20 x 40 cell and the car lays out its
## riders by rank through CarRack, not by this grid. What survives is the rule
## itself -- a balanced block with a centred short last rank.
##
## The shape is `rows = floor(sqrt(n))`, `cols = ceil(n / rows)`:
##
##   1 -> 1      4 -> 2+2      8 -> 4+4
##   2 -> 2      5 -> 3+2      9 -> 3+3+3
##   3 -> 3      6 -> 3+3     12 -> 4+4+4
##
## CEILING on the rows instead would give 8 as 3+3+2 -- one rank taller and
## visibly ragged. Flooring keeps blocks wide and short.
##
## When the area cannot hold the balanced shape the rule gives way rather than
## overflowing: too narrow adds ranks, too short adds columns, and a space too
## small for everyone shows what fits. Nothing is lost by that -- the exact
## count sits beside the strip.
##
## Pure geometry, no scene tree, so the packing is unit-tested headlessly.

const GAP := 4.0

## Columns and rows for `count` items, bounded by what the area can hold.
static func shape(count: int, max_cols: int, max_floors: int) -> Vector2i:
	if count <= 0 or max_cols <= 0 or max_floors <= 0:
		return Vector2i.ZERO
	var rows := maxi(int(sqrt(float(count))), 1)
	var cols := int(ceil(float(count) / float(rows)))
	if cols > max_cols:
		cols = maxi(max_cols, 1)
		rows = int(ceil(float(count) / float(cols)))
	if rows > max_floors:
		rows = maxi(max_floors, 1)
		cols = mini(int(ceil(float(count) / float(rows))), maxi(max_cols, 1))
	return Vector2i(cols, rows)

## How many the shape can actually show.
static func fits(grid: Vector2i) -> int:
	return grid.x * grid.y

## How many columns and rows of CELL fit an area, given the gaps between them.
## These take the CELL, never the pitch -- GAP is added here, so handing them
## `cell + GAP` double-counts it.
##
## ZERO is a real answer and must not be floored to one: a caller with less room
## than one cell has to fall back rather than draw a rank that overflows.
static func columns_for(width: float, cell_w: float) -> int:
	return maxi(int((width + GAP) / (cell_w + GAP)), 0)

static func rows_for(height: float, cell_h: float) -> int:
	return maxi(int((height + GAP) / (cell_h + GAP)), 0)

## Top-left of item `index`. Horizontally the block is centred in the area and
## each rank is centred on the block, so a short last rank is not left ragged.
##
## VERTICALLY THE BLOCK SITS ON THE FLOOR, not in the middle. People stand on
## something. Centring was invisible while the hall was always two ranks deep --
## the block then measured exactly the row height -- but a floor with four or
## fewer waiting is one rank, and centred it hovered half a person above the
## ground with a floor picture drawn underneath.
static func position_of(index: int, count: int, grid: Vector2i, area: Vector2,
		cell: Vector2) -> Vector2:
	if grid.x <= 0 or grid.y <= 0:
		return Vector2.ZERO
	var row := index / grid.x
	var col := index % grid.x
	var in_rank := clampi(count - row * grid.x, 1, grid.x)
	var rank_w := float(in_rank) * cell.x + float(in_rank - 1) * GAP
	var block_h := float(grid.y) * cell.y + float(grid.y - 1) * GAP
	return Vector2(
		(area.x - rank_w) * 0.5 + float(col) * (cell.x + GAP),
		area.y - block_h + float(row) * (cell.y + GAP))
