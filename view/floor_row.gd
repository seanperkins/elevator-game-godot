class_name FloorRow
extends Control

## One floor of the board, in four fixed regions:
##
##   [count] [tenant bar] [floor no.] | people strip | (shafts, drawn above)
##
## The waiting count is leftmost and never moves. It is the number a dispatch
## decision is made on, so it cannot shift with the shaft count, and it cannot
## sit unlabelled beside the floor number where the two read as one value.
##
## There is no tenant status TEXT. The 4-unit bar carries all three states --
## satisfaction, a draining move-out countdown, and vacancy. Text in the gutter
## overlapped the floor number at the capped 29.6-unit floor; text in the strip
## overlapped the sprites, and vacant floors still spawn passengers, so the two
## co-occur. In the dense tier it would sit on the crowd bar, whose LENGTH is
## the encoding.

## A waiting passenger shows its CALL DIRECTION, not its destination: they
## pressed a hall button, which is up or down. One glyph fits the original
## 14-unit pitch, so the strip still holds twelve. (Two digits would have cost
## roughly 18 units each and dropped it to eight -- which is what the destination
## panel upgrade will have to buy, when it lands.)
const CALL_UP := "\u25b2"
const CALL_DOWN := "\u25bc"
## Waiting, direction withheld -- before the call_direction upgrade is fitted.
## The empty string rather than a glyph: the chip's colour already carries
## patience, so a "?" would add no information and reads as an error state
## rather than as information not yet bought.
const CALL_UNKNOWN := ""

const MAX_INDIVIDUALS := 12
const SPRITE_PITCH := 14.0
## People are laid out by ChipGrid -- the same square, the same packing rule as
## inside a car, so a passenger looks the same before and after boarding.
const STRIP_RIGHT := GUTTER_WIDTH + STRIP_WIDTH          # 208

const GUTTER_WIDTH := 64.0
const STRIP_WIDTH := 144.0
const COUNT_WIDTH := 26.0
const BAR_X := 30.0
const BAR_W := 4.0
const LABEL_X := 38.0
const SPRITE_X := GUTTER_WIDTH + 4.0

var floor_index: int = 0

var _label: Label
var _count: Label
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _sprites: Array[PassengerSprite] = []

func _ready() -> void:
	# A hairline at the top of the band: without it 40 floors read as one field.
	var rule := ColorRect.new()
	rule.color = Palette.RULE
	rule.size = Vector2(size.x, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 18)
	_count.position = Vector2(0, 2)
	_count.size = Vector2(COUNT_WIDTH, 18)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)

	_bar_track = ColorRect.new()
	_bar_track.color = Palette.BAR_TRACK
	_bar_track.position = Vector2(BAR_X, 1)
	_bar_track.size = Vector2(BAR_W, size.y - 1)
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_track)

	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(BAR_X, 1)
	_bar_fill.size = Vector2(BAR_W, size.y - 1)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_fill)

	_label = Label.new()
	# Capped by the gutter budget, not by taste: the UI spec's coordinate table
	# gives the floor number x 38-64, i.e. 26 units, and the people strip starts
	# at SPRITE_X. Two digits (floors run to Building.MAX_FLOORS) at 22 come to
	# ~24 units. Going further needs the gutter widened first -- an earlier
	# draft overlapped this label by ~12 units and it was a real bug.
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Palette.INK_FLOOR)
	_label.position = Vector2(LABEL_X, 3)
	add_child(_label)

func set_floor(index: int) -> void:
	floor_index = index
	_label.text = str(index)

## Everyone waiting, drawn as squares. There used to be a second tier -- below a
## 40-unit floor the sprites collapsed into a single crowd bar -- because floors
## shrank as the building grew and eventually could not hold a chip. Rows are a
## fixed 88 units now, so that tier could never fire again, and a representation
## that never appears is worse than no representation. The count beside them is
## still exact regardless of how many are drawn.
## `show_direction` is required rather than defaulted to true: a default would
## let a future caller silently opt out of the gate, which is the same class of
## bug the note_expiry(fare) default caused.
func set_waiting(passengers: Array, show_direction: bool) -> void:
	var total: int = passengers.size()
	_count.text = "" if total <= 0 else str(total)

	var cap := MAX_INDIVIDUALS
	var area := Vector2(STRIP_RIGHT - SPRITE_X, size.y)
	var grid := ChipGrid.shape(mini(total, cap),
		ChipGrid.columns_for(area.x), ChipGrid.rows_for(area.y))
	var shown: int = mini(mini(total, cap), ChipGrid.fits(grid))
	grid = ChipGrid.shape(shown, ChipGrid.columns_for(area.x),
		ChipGrid.rows_for(area.y))
	while _sprites.size() < shown:
		var s := PassengerSprite.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(SPRITE_X, 0) \
				+ ChipGrid.position_of(i, shown, grid, area)
			_sprites[i].show_as(p.patience_fraction(),
				(CALL_DOWN if p.direction() < 0 else CALL_UP) if show_direction
				else CALL_UNKNOWN)
		else:
			_sprites[i].recycle()

## Three states in one 4-unit bar.
##   tenanted   -- filled proportional to satisfaction, red->green
##   moving out -- red, the fill DRAINING over the countdown, so the bar is the
##                 countdown rather than labelling one
##   vacant     -- solid grey; the lease picker now lives in the FloorPanel,
##                 so the strip keeps the full sprite cap on every floor
func set_tenant(satisfaction: float, vacant: bool, moving_out: bool,
		ticks_left: int) -> void:
	var full := size.y - 1.0
	if vacant:
		_bar_fill.color = Palette.PATIENCE_IDLE
		_bar_fill.position = Vector2(BAR_X, 1)
		_bar_fill.size = Vector2(BAR_W, full)
		return

	var fraction := clampf(satisfaction, 0.0, 1.0)
	if moving_out:
		_bar_fill.color = Palette.PATIENCE_LOW
		fraction = clampf(float(ticks_left) / float(Tenancy.MOVE_OUT_TICKS), 0.0, 1.0)
	else:
		_bar_fill.color = Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, fraction)
	var height := maxf(full * fraction, 1.0)
	_bar_fill.size = Vector2(BAR_W, height)
	_bar_fill.position = Vector2(BAR_X, 1.0 + (full - height))
