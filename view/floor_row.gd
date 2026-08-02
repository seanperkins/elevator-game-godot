class_name FloorRow
extends Control

## One row of the board, laid out left to right and in fixed regions:
##
##   [count] [satisfaction] [index] | people waiting | shafts (scrollable)
##
## The waiting count is the leftmost thing on the row and never moves. It is
## the number a dispatch decision is actually made on, so it cannot be the
## element that shifts position with the shaft count, or sit unlabelled beside
## the row index where the two read as one number.
##
## The people strip is a fixed width too, so how many sprites a row can show
## no longer depends on how much space the columns have left over.

const MAX_INDIVIDUALS := 12
const SPRITE_PITCH := 14.0

const GUTTER_WIDTH := 64.0       # count, satisfaction bar, row index
const STRIP_WIDTH := 176.0       # 12 sprites at SPRITE_PITCH, plus margins
const COUNT_WIDTH := 26.0
const BAR_X := 30.0
const LABEL_X := 38.0

var row_index: int = 0

var _label: Label
var _count: Label
var _sprites: Array[PassengerSprite] = []
var _tenant: Label
var _bar: ColorRect

func _ready() -> void:
	# A hairline at the top of the band: without it 40 rows read as one field.
	var rule := ColorRect.new()
	rule.color = Color("232c38")
	rule.position = Vector2.ZERO
	rule.size = Vector2(size.x, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.position = Vector2(0, 2)
	_count.size = Vector2(COUNT_WIDTH, 18)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("7c8899"))
	_label.position = Vector2(LABEL_X, 3)
	add_child(_label)

	_build_tenant_widgets()

func set_row(index: int) -> void:
	row_index = index
	_label.text = str(index)

## Individuals above the cap collapse into the count alone, so the worst case
## stays bounded no matter how badly the player is doing.
func set_waiting(passengers: Array) -> void:
	var total: int = passengers.size()
	var shown: int = mini(total, MAX_INDIVIDUALS)
	while _sprites.size() < shown:
		var s := PassengerSprite.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(
				GUTTER_WIDTH + 4.0 + float(i) * SPRITE_PITCH,
				(size.y - _sprites[i].size.y) * 0.5)
			_sprites[i].show_for(p.patience_fraction())
		else:
			_sprites[i].recycle()
	_count.text = "" if total <= 0 else str(total)

func _build_tenant_widgets() -> void:
	_bar = ColorRect.new()
	_bar.position = Vector2(BAR_X, 1)
	_bar.size = Vector2(4, size.y - 1)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_tenant = Label.new()
	_tenant.add_theme_font_size_override("font_size", 10)
	_tenant.position = Vector2(LABEL_X, size.y - 21)
	add_child(_tenant)

## Green-to-red satisfaction bar, plus a visible move-out countdown so the
## player gets a chance to recover the tenant.
func set_tenant(satisfaction: float, vacant: bool, moving_out: bool, ticks_left: int) -> void:
	if _bar == null:
		_build_tenant_widgets()
	if vacant:
		_bar.color = Color("3f3f46")
		_tenant.text = "VACANT"
		return
	_bar.color = Color("ef4444").lerp(Color("4ade80"), clampf(satisfaction, 0.0, 1.0))
	_tenant.text = "leaving %ds" % int(ceilf(float(ticks_left) / 20.0)) if moving_out else ""
