class_name PersonSprite
extends Control

## One person, waiting on a floor or riding in a car. Pooled.
##
## Three parts, and which of them appear is the difference between the two
## states:
##
##   badge  -- a call ARROW while waiting (drawn, not typeset), the DESTINATION
##             FLOOR once aboard (typeset, two digits). Learning the floor by
##             picking someone up is the asymmetry the dispatch puzzle rests on.
##   figure -- decorative. Shirt and skin come from the passenger's own trip, so
##             a pooled sprite cannot flicker as the pool reshuffles.
##   bar    -- patience, and ONLY while waiting. Patience is frozen aboard
##             (GameState._expire skips riders), so a rider's bar would encode a
##             number that stopped moving at boarding.
##
## The hall arrow is DRAWN rather than set in a font because a 16x14 badge puts
## a glyph at 6.6pt, half what the chip it replaces managed -- and a triangle
## reads better at 14 units than any glyph. label_text() still reports the
## direction, so it stays the logical accessor: it says what the badge MEANS.
##
## parts() and redraw_count() are the testable seams; _draw() reads them and
## adds nothing of its own.

## The call glyphs live HERE, not in FloorRow, because this is the class that
## draws them -- FloorRow's CALL_UP/CALL_DOWN now point at these. The other
## direction would be a cycle: FloorRow builds PersonSprites.
const ARROW_UP := "▲"
const ARROW_DOWN := "▼"

const HALL_CELL := Vector2(20, 40)
const HALL_BADGE := Vector2(16, 14)
const FIGURE := Vector2(14, 22)
const BAR_W := 4.0
const HALL_FIGURE_TOP := 16.0

## Deliberate coefficients. For every trip shape the spawner emits, each
## freely-varying field's coefficient must be coprime to BOTH palette sizes --
## that is, to 15. Two earlier sets failed: (31,17,7) mod 4 put every inbound
## passenger in one shirt, and (3,7,11) with a separate skin sum could not be
## carried by a single key. Verified over floors 0..20 on all four shapes.
static func key_for(origin: int, destination: int, source: int) -> int:
	return origin * 4 + destination * 7 + source * 9

var _glyph: String = ""
var _fraction: float = 1.0
var _tint_key: int = 0
var _riding: bool = false
var _cell: Vector2 = HALL_CELL
var _badge_h: float = HALL_BADGE.y
var _font_size: int = 12
var _redraws: int = 0
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = _cell
	_label = Label.new()
	_label.add_theme_color_override("font_color", Palette.BADGE_INK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_sync_label()

## The car sizes its cells per capacity; the hall never calls this.
func set_cell(cell: Vector2, badge_h: float, font_size: int) -> void:
	if is_equal_approx(cell.x, _cell.x) and is_equal_approx(cell.y, _cell.y) \
			and is_equal_approx(badge_h, _badge_h) and font_size == _font_size:
		return
	_cell = cell
	_badge_h = badge_h
	_font_size = font_size
	size = cell
	_sync_label()
	_dirty()

func show_waiting(fraction: float, glyph: String, tint_key: int) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	# Quantised to what the bar can actually SHOW. Raw, this never matches:
	# patience decays every tick, so a busy hall would redraw at 20Hz forever.
	if visible and not _riding and _glyph == glyph and _tint_key == tint_key \
			and roundi(_fraction * FIGURE.y) == roundi(f * FIGURE.y):
		return
	visible = true
	_riding = false
	_fraction = f
	_glyph = glyph
	_tint_key = tint_key
	_sync_label()
	_dirty()

func show_riding(glyph: String, tint_key: int) -> void:
	if visible and _riding and _glyph == glyph and _tint_key == tint_key:
		return
	visible = true
	_riding = true
	_glyph = glyph
	_tint_key = tint_key
	_sync_label()
	_dirty()

func recycle() -> void:
	visible = false
	_dirty()

func label_text() -> String:
	return _glyph

func redraw_count() -> int:
	return _redraws

## The rects _draw() consumes. A rider has no bar and an unbought direction has
## no badge, and both are reported as a zero-size Rect2 rather than omitted, so
## a caller never has to test for a missing key.
func parts() -> Dictionary:
	var badge := Rect2()
	if _riding or _glyph != "":
		badge = Rect2(0, 0, _cell.x if _riding else HALL_BADGE.x, _badge_h)
	var band_w := _cell.x if _riding else HALL_BADGE.x
	var fig_top := _badge_h if _riding else HALL_FIGURE_TOP
	var figure := Rect2((band_w - FIGURE.x) * 0.5, fig_top, FIGURE.x, FIGURE.y)
	var bar := Rect2()
	if not _riding:
		var h := FIGURE.y * _fraction
		bar = Rect2(_cell.x - BAR_W, fig_top + (FIGURE.y - h), BAR_W, h)
	return {
		"badge": badge,
		"figure": figure,
		"bar": bar,
		"head": Rect2(figure.position + Vector2(3, 0), Vector2(8, 8)),
		"torso": Rect2(figure.position + Vector2(2, 9), Vector2(10, 9)),
	}

func _dirty() -> void:
	_redraws += 1
	queue_redraw()

func _sync_label() -> void:
	if _label == null:
		return
	# Only the CAR typesets. The hall's arrow is a drawn triangle.
	_label.visible = _riding
	_label.text = _glyph if _riding else ""
	_label.position = Vector2.ZERO
	_label.size = Vector2(_cell.x, _badge_h)
	_label.add_theme_font_size_override("font_size", _font_size)

func _draw() -> void:
	if not visible:
		return
	var q := parts()
	var badge: Rect2 = q["badge"]
	if badge.size != Vector2.ZERO:
		draw_rect(badge, Palette.BADGE_BG)
		if not _riding:
			_draw_arrow(badge)
	var bar: Rect2 = q["bar"]
	if bar.size != Vector2.ZERO:
		var track := Rect2(bar.position.x, (q["figure"] as Rect2).position.y,
			BAR_W, FIGURE.y)
		draw_rect(track, Palette.PERSON_BAR_TRACK)
		draw_rect(bar, Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, _fraction))
	var figure: Rect2 = q["figure"]
	var skin: Color = Palette.PERSON_SKINS[posmod(_tint_key, Palette.PERSON_SKINS.size())]
	var shirt: Color = Palette.PERSON_SHIRTS[posmod(_tint_key, Palette.PERSON_SHIRTS.size())]
	draw_circle((q["head"] as Rect2).get_center(), 4.0, skin)
	draw_rect(q["torso"], shirt)
	draw_rect(Rect2(figure.position + Vector2(2, 18), Vector2(4, 4)), Palette.PERSON_LEGS)
	draw_rect(Rect2(figure.position + Vector2(8, 18), Vector2(4, 4)), Palette.PERSON_LEGS)

func _draw_arrow(badge: Rect2) -> void:
	var c := badge.get_center()
	var up := _glyph == ARROW_UP
	var dy := 4.0 if up else -4.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -dy), c + Vector2(-5, dy), c + Vector2(5, dy)]),
		Palette.BADGE_INK)
