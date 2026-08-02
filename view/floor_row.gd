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
