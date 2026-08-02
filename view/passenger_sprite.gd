class_name PassengerSprite
extends ColorRect

## One waiting passenger. Pooled.
##
## The sprite carries TWO facts, because either alone is useless for dispatch:
## the fill ramps green -> red with remaining patience (how long you have), and
## the number is the destination floor (where this trip is going). An anonymous
## box tells you somebody is waiting, which the count already said.
##
## The number sits INSIDE the body rather than beside it. Beside it would need a
## second column of width per passenger, and the strip is a fixed 176 units --
## the whole point of fixing it was that a strip sized from leftovers reaches
## zero exactly when the building is busiest.

const GREEN := Color("4ade80")
const RED := Color("ef4444")

const WIDTH := 18.0
const HEIGHT := 16.0

var _label: Label

func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark ink, because the body ranges over green through red and both are
	# light enough that white text on them is the unreadable case.
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color("0b0f14"))
	_label.size = Vector2(WIDTH, HEIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func show_for(fraction: float, destination: int) -> void:
	visible = true
	color = RED.lerp(GREEN, clampf(fraction, 0.0, 1.0))
	_label.text = str(destination)

func destination_text() -> String:
	return _label.text if _label != null else ""

func recycle() -> void:
	visible = false
