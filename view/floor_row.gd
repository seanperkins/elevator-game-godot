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
## overlapped the floor number at the capped 29.6-unit row; text in the strip
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

const MAX_INDIVIDUALS := 12
const VACANT_MAX_INDIVIDUALS := 9       # leaves room for the re-lease price
const SPRITE_PITCH := 14.0
const CHIP_SIZE := Vector2(12.0, 16.0)
const CROWD_BAR_BELOW := 40.0           # row height at or under which sprites collapse

const GUTTER_WIDTH := 64.0
const STRIP_WIDTH := 176.0
const COUNT_WIDTH := 26.0
const BAR_X := 30.0
const BAR_W := 4.0
const LABEL_X := 38.0
const SPRITE_X := GUTTER_WIDTH + 4.0
const PRICE_WIDTH := 40.0

const GREEN := Color("4ade80")
const RED := Color("ef4444")
const GREY := Color("3f3f46")

var row_index: int = 0

var _label: Label
var _count: Label
var _price: Label
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _crowd: ColorRect
var _sprites: Array[PassengerSprite] = []

func _ready() -> void:
	# A hairline at the top of the band: without it 40 rows read as one field.
	var rule := ColorRect.new()
	rule.color = Color("232c38")
	rule.size = Vector2(size.x, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.position = Vector2(0, 2)
	_count.size = Vector2(COUNT_WIDTH, 18)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)

	_bar_track = ColorRect.new()
	_bar_track.color = Color("1b2430")
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
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("7c8899"))
	_label.position = Vector2(LABEL_X, 3)
	add_child(_label)

	_crowd = ColorRect.new()
	_crowd.visible = false
	_crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crowd)

	# Right-aligned at the strip's edge. On a vacant floor the sprite cap drops
	# to 10, so sprite 9 ends at x = 204 and the price occupies [206, 240]:
	# they cannot overlap.
	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 11)
	_price.add_theme_color_override("font_color", GREEN)
	_price.size = Vector2(PRICE_WIDTH, 16)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_price.position = Vector2(GUTTER_WIDTH + STRIP_WIDTH - PRICE_WIDTH,
		(size.y - 16.0) * 0.5)
	_price.visible = false
	add_child(_price)

func set_row(index: int) -> void:
	row_index = index
	_label.text = str(index)

## Individual sprites while the row is tall enough to tell them apart; at or
## below CROWD_BAR_BELOW they collapse into one bar whose length is the crowd
## and whose colour is the WORST patience on the floor. The two tiers are
## mutually exclusive. The count is never affected and is always exact.
func set_waiting(passengers: Array) -> void:
	var total: int = passengers.size()
	_count.text = "" if total <= 0 else str(total)

	var cap: int = VACANT_MAX_INDIVIDUALS if _price.visible else MAX_INDIVIDUALS
	if size.y <= CROWD_BAR_BELOW:
		_hide_sprites()
		_draw_crowd_bar(total, cap)
		return

	_crowd.visible = false
	var shown: int = mini(total, cap)
	while _sprites.size() < shown:
		var s := PassengerSprite.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		s.set_chip(CHIP_SIZE, 11)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(
				SPRITE_X + float(i) * SPRITE_PITCH,
				(size.y - _sprites[i].size.y) * 0.5)
			_sprites[i].show_as(p.patience_fraction(),
				CALL_DOWN if p.direction() < 0 else CALL_UP)
		else:
			_sprites[i].recycle()

func _hide_sprites() -> void:
	for s in _sprites:
		s.recycle()

## Length is the crowd measured against the same 12-passenger cap, saturating
## beyond it: a floor with 12 waiting and one with 40 draw the same bar, and
## the exact count beside it is what distinguishes them.
func _draw_crowd_bar(total: int, cap: int) -> void:
	if total <= 0:
		_crowd.visible = false
		return
	_crowd.visible = true
	var span := float(cap) * SPRITE_PITCH
	var fraction := clampf(float(total) / float(cap), 0.0, 1.0)
	_crowd.position = Vector2(SPRITE_X, (size.y - 9.0) * 0.5)
	_crowd.size = Vector2(maxf(span * fraction, 3.0), 9.0)

## Called with the worst remaining patience on the floor so the crowd bar can
## colour itself; separate from set_waiting so the caller does the min once.
func set_crowd_colour(worst_fraction: float) -> void:
	_crowd.color = RED.lerp(GREEN, clampf(worst_fraction, 0.0, 1.0))

## Three states in one 4-unit bar.
##   tenanted   -- filled proportional to satisfaction, red->green
##   moving out -- red, the fill DRAINING over the countdown, so the bar is the
##                 countdown rather than labelling one
##   vacant     -- solid grey, and the re-lease price shows in the strip
func set_tenant(satisfaction: float, vacant: bool, moving_out: bool,
		ticks_left: int, relet_price: String) -> void:
	var full := size.y - 1.0
	if vacant:
		_bar_fill.color = GREY
		_bar_fill.position = Vector2(BAR_X, 1)
		_bar_fill.size = Vector2(BAR_W, full)
		_price.text = relet_price
		_price.visible = true
		return

	_price.visible = false
	var fraction := clampf(satisfaction, 0.0, 1.0)
	if moving_out:
		_bar_fill.color = RED
		fraction = clampf(float(ticks_left) / float(Tenancy.MOVE_OUT_TICKS), 0.0, 1.0)
	else:
		_bar_fill.color = RED.lerp(GREEN, fraction)
	var height := maxf(full * fraction, 1.0)
	_bar_fill.size = Vector2(BAR_W, height)
	_bar_fill.position = Vector2(BAR_X, 1.0 + (full - height))
