class_name FloorRow
extends Control

## One floor of the board, in four fixed regions:
##
##   [count] [floor no.] | people strip | (shafts, drawn above)
##
## The waiting count is leftmost and never moves. It is the number a dispatch
## decision is made on, so it cannot shift with the shaft count, and it cannot
## sit unlabelled beside the floor number where the two read as one value.
##
## THE GUTTER TENANT BAR IS GONE. A 4-unit column at x 30-34 spanning every row
## stacked into one continuous line down the left of the board, and once every
## floor had a picture behind it that line was the thing you saw instead of the
## building. Its three states were rehomed rather than dropped:
##
##   vacancy      -- the construction-shell scenery. A floor that looks like bare
##                   concrete does not also need a grey bar saying so.
##   satisfaction -- the FloorPanel, which already drew it as a ProgressBar. It
##                   is a number you consult, not one you scan for.
##   moving out   -- THE FLOOR NUMBER TURNS VERMILION. This one had to stay on
##                   the board: the countdown is cancellable (`note_delivery`
##                   clears it when satisfaction recovers), so it is a call to
##                   dispatch to that floor within the simulated minute, and an
##                   alarm you have to open a panel to see is not an alarm.
##
## What is lost is the countdown's PROGRESS -- the old bar drained, so it was the
## clock rather than a label for one. The remaining ticks moved to the panel
## header; the board keeps the alarm, which is the actionable half.

## A waiting passenger shows its CALL DIRECTION, not its destination: they
## pressed a hall button, which is up or down. The glyphs live in PersonSprite,
## which draws them as triangles -- FloorRow only names them.
const CALL_UP := PersonSprite.ARROW_UP
const CALL_DOWN := PersonSprite.ARROW_DOWN
## Waiting, direction withheld -- before the call_direction upgrade is fitted.
## The empty string rather than a glyph: a "?" would add no information and
## reads as an error state rather than as information not yet bought.
const CALL_UNKNOWN := ""

const MAX_INDIVIDUALS := 12
## People are laid out by ChipGrid with PersonSprite.HALL_CELL -- a person stands
## rather than sits, on the floor rather than centred in the band. The car no
## longer shares this rule: riders stand in ranks there.
const STRIP_RIGHT := GUTTER_WIDTH + STRIP_WIDTH          # 192

## 64 until the tenant bar went. The bar held x 30-34 and the layout was built
## around it; with it gone the gutter carries two labels and the space between
## them, which measures 48:
##
##   count   0-20   two digits at font 18 come to ~19.8 units
##   (gap)  20-23
##   number 23-48   two digits at font 22 come to ~24.2 units, so 24 was 0.2
##                  short -- caught by test_board_geometry, not by looking
##
## THE 16 UNITS THIS RELEASED ARE NOT SPARE -- they are what buys the exterior in
## BuildingView. Widening this again takes them straight back out of the world
## outside the building, and on a 688-unit device board there is nowhere else for
## them to come from. See BuildingView.EXTERIOR_LEFT.
const GUTTER_WIDTH := 48.0
const STRIP_WIDTH := 144.0
const COUNT_WIDTH := 20.0
const LABEL_X := 23.0
const SPRITE_X := GUTTER_WIDTH + 4.0

var floor_index: int = 0

var _label: Label
var _count: Label
var _sprites: Array[PersonSprite] = []
var _scenery: TextureRect

func _ready() -> void:
	# FIRST child, so everything else in the row draws over it. It covers x 0 to
	# STRIP_RIGHT -- the whole board left of the shafts -- and is simply absent
	# for a kind with no art yet, which is most of them.
	_scenery = TextureRect.new()
	_scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scenery.stretch_mode = TextureRect.STRETCH_SCALE
	_scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scenery.visible = false
	add_child(_scenery)

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

	_label = Label.new()
	# Capped by the gutter budget, not by taste: x 23-48 is 25 units and two
	# digits at 22 come to ~24.2, so there is 0.8 of room. Going further needs
	# the gutter widened first, which now costs the building's exterior -- an
	# earlier draft overlapped this label by ~12 units and it was a real bug.
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Palette.INK_FLOOR)
	_label.position = Vector2(LABEL_X, 3)
	add_child(_label)

func set_floor(index: int) -> void:
	floor_index = index
	# Basements read as P1, P2 counting DOWN. The index stays signed everywhere;
	# only the label differs. "-1" is the same width in the gutter but reads as
	# a subtraction.
	_label.text = str(index) if index >= 0 else "P%d" % -index

## Everyone waiting, drawn as figures. Rows are a fixed 120 units, and the strip
## packs HALL_CELL (32 x 58) four across and two deep -- eight of a possible
## twelve. The count beside them is exact regardless of how many are drawn, which
## is what lets the figures be legible rather than complete.
## `show_direction` is required rather than defaulted to true: a default would
## let a future caller silently opt out of the gate, which is the same class of
## bug the note_expiry(fare) default caused.
func set_waiting(passengers: Array, show_direction: bool) -> void:
	var total: int = passengers.size()
	_count.text = "" if total <= 0 else str(total)

	var cap := MAX_INDIVIDUALS
	var cell := PersonSprite.HALL_CELL
	var area := Vector2(STRIP_RIGHT - SPRITE_X, size.y)
	var grid := ChipGrid.shape(mini(total, cap),
		ChipGrid.columns_for(area.x, cell.x), ChipGrid.rows_for(area.y, cell.y))
	var shown: int = mini(mini(total, cap), ChipGrid.fits(grid))
	grid = ChipGrid.shape(shown, ChipGrid.columns_for(area.x, cell.x),
		ChipGrid.rows_for(area.y, cell.y))
	while _sprites.size() < shown:
		var s := PersonSprite.new()
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(SPRITE_X, 0) \
				+ ChipGrid.position_of(i, shown, grid, area, cell)
			_sprites[i].show_waiting(p.patience_fraction(),
				(CALL_DOWN if p.direction() < 0 else CALL_UP) if show_direction
				else CALL_UNKNOWN,
				PersonSprite.key_for(p.origin_floor, p.destination_floor, p.source_floor))
		else:
			_sprites[i].recycle()

## What this floor looks like: a tenant kind id, or FloorScenery.VACANT for the
## construction shell. An empty id -- a kind whose image has not been drawn --
## leaves the plain cream ground.
func set_scenery(kind_id: String) -> void:
	if _scenery == null:
		return
	var tex := FloorScenery.texture_for(kind_id)
	_scenery.texture = tex
	_scenery.visible = tex != null
	_scenery.position = Vector2.ZERO
	_scenery.size = Vector2(STRIP_RIGHT, size.y)

## The scenery a row is showing, or "" -- the seam a test reads, since a
## TextureRect's pixels are not observable headlessly.
func scenery_id() -> String:
	if _scenery == null or _scenery.texture == null:
		return ""
	return (_scenery.texture as Texture2D).resource_path.get_file().get_basename()

## The one tenant state the board still carries: this floor's tenant is leaving.
##
## VERMILION, not the patience ramp's PATIENCE_LOW. The ramp is a light rust that
## was solved for contrast against a bar track, and the floor number sits on the
## scenery's cream instead -- where PATIENCE_LOW measures under 2:1 and vanishes.
func set_moving_out(moving_out: bool) -> void:
	_label.add_theme_color_override("font_color",
		Palette.ALARM if moving_out else Palette.INK_FLOOR)
