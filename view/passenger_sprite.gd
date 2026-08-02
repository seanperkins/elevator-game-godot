class_name PassengerSprite
extends ColorRect

## Pooled. Colour ramps green -> red with remaining patience.

const GREEN := Color("4ade80")
const RED := Color("ef4444")

func _ready() -> void:
	size = Vector2(10, 14)

func show_for(fraction: float) -> void:
	visible = true
	color = RED.lerp(GREEN, clampf(fraction, 0.0, 1.0))

func recycle() -> void:
	visible = false
