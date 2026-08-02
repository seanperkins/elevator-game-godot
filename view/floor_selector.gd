class_name FloorSelector
extends Control

## The drag rail. Detents at each row; a magnified label follows the thumb,
## OFFSET ABOVE IT so the finger does not occlude the choice.
##
## The marker covers the row's whole band, which is exactly the band the
## gesture classifier selects, so the highlight can never disagree with what
## releasing dispatches.

var _row_height: float = 32.0
var _bubble: Label
var _marker: ColorRect

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_marker = ColorRect.new()
	_marker.color = Color("4cc2ff", 0.35)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)

	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 34)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)

func configure(row_height: float) -> void:
	_row_height = row_height

func show_at(row: int) -> void:
	visible = true
	_marker.position = Vector2(0, float(row) * _row_height)
	_marker.size = Vector2(size.x, _row_height)
	_bubble.text = str(row)
	_bubble.position = Vector2(4, float(row) * _row_height - 46.0)  # above the thumb

func hide_rail() -> void:
	visible = false
