class_name FloorRow
extends Control

## One row of the board: index label, the people waiting on it, and a crowd
## count that takes over once individual sprites are capped.

const MAX_INDIVIDUALS := 12
const SPRITE_PITCH := 14.0
const RIGHT_MARGIN := 6.0

var row_index: int = 0

var _label: Label
var _crowd: Label
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

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.position = Vector2(4, 2)
	add_child(_label)

	_crowd = Label.new()
	_crowd.add_theme_font_size_override("font_size", 12)
	add_child(_crowd)

	_build_tenant_widgets()

func set_row(index: int) -> void:
	row_index = index
	_label.text = str(index)

## Individuals above the cap collapse into a count, so the worst case stays
## bounded no matter how badly the player is doing. Sprites are pooled per row
## and laid out from the right edge inward, which keeps them clear of the
## shaft columns while the building is still narrow.
func set_waiting(passengers: Array) -> void:
	var shown: int = mini(passengers.size(), MAX_INDIVIDUALS)
	while _sprites.size() < shown:
		var s := PassengerSprite.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(
				size.x - RIGHT_MARGIN - float(i + 1) * SPRITE_PITCH,
				(size.y - _sprites[i].size.y) * 0.5)
			_sprites[i].show_for(p.patience_fraction())
		else:
			_sprites[i].recycle()
	var overflow: int = passengers.size() - MAX_INDIVIDUALS
	_crowd.text = "" if overflow <= 0 else "+%d" % overflow
	# Immediately left of the run it counts, not parked in the row-index gutter.
	_crowd.position = Vector2(
		size.x - RIGHT_MARGIN - float(shown) * SPRITE_PITCH - 34.0,
		(size.y - 16.0) * 0.5)

func _build_tenant_widgets() -> void:
	_bar = ColorRect.new()
	_bar.position = Vector2(0, 1)
	_bar.size = Vector2(3, size.y - 1)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_tenant = Label.new()
	_tenant.add_theme_font_size_override("font_size", 10)
	_tenant.position = Vector2(6, size.y - 21)
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
