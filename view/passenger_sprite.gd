class_name PassengerSprite
extends ColorRect

## One passenger, waiting on a floor or riding in a car. Pooled.
##
## The body's fill ramps green -> red with remaining patience. What the LABEL
## says depends on where the passenger is, and that difference is the game:
##
##   waiting  -- an arrow. They pressed a hall call button, which is up or down;
##               the operator does not know their floor yet.
##   aboard   -- the floor number. They pressed a car button, so now you do.
##
## Learning the destination by picking someone up is the information asymmetry
## the dispatch puzzle rests on. A later upgrade puts a destination panel in the
## lobby and reveals floors before boarding, which is a real change in what the
## player can plan -- see set_call/set_destination's two callers.

## A square, the same everywhere. ChipGrid owns the size so the hall and the car
## cannot drift apart.
const WIDTH := ChipGrid.SIZE
const HEIGHT := ChipGrid.SIZE
## Bounded by the chip: ChipGrid.SIZE is 30, and a car seat holds TWO digits
## (ShaftColumn.SEAT_FONT is this constant), so this is the largest that clears
## both without clipping.
const FONT := 24

var _label: Label

func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark ink: the body ranges over green through red, and both are light
	# enough that white text on them is the unreadable case. Palette pins the
	# ramp's worst point at 4.03:1 against INK_ON_LIGHT.
	_label = Label.new()
	_label.add_theme_color_override("font_color", Palette.INK_ON_LIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_apply_size(Vector2(WIDTH, HEIGHT), FONT)

## Hall chips hold one glyph; car chips hold two digits, so they are wider.
## Same square, same colour ramp, different content -- which is the point.
func set_chip(chip_size: Vector2, font_size: int) -> void:
	_apply_size(chip_size, font_size)

func _apply_size(chip_size: Vector2, font_size: int) -> void:
	size = chip_size
	if _label == null:
		return
	_label.size = chip_size
	_label.add_theme_font_size_override("font_size", font_size)

func show_as(fraction: float, text: String) -> void:
	visible = true
	color = Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, clampf(fraction, 0.0, 1.0))
	_label.text = text

func label_text() -> String:
	return _label.text if _label != null else ""

func recycle() -> void:
	visible = false
