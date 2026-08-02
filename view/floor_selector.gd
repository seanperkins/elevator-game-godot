class_name FloorSelector
extends Control

## The drag rail. The marker covers the selected floor's whole band -- exactly
## the band the classifier selects -- so the highlight can never disagree with
## what releasing dispatches.
##
## The bubble normally sits ABOVE the thumb so the finger does not occlude the
## choice. For the top two bands there is no room above: the viewport is inset
## to the floors and clips, so the bubble flips below the marker instead.

const BUBBLE_OFFSET := 46.0

var _coords: BoardCoords
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

func configure(coords: BoardCoords) -> void:
	_coords = coords

func show_at(floor_index: int) -> void:
	visible = true
	var y := _coords.floor_to_y(floor_index)
	_marker.position = Vector2(0, y)
	_marker.size = Vector2(size.x, _coords.row_height)
	_bubble.text = str(floor_index)
	var above := y - BUBBLE_OFFSET
	_bubble.position = Vector2(4, above if above >= 0.0 \
		else y + _coords.row_height + 2.0)

func hide_rail() -> void:
	visible = false
