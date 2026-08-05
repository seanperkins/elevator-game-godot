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

## A PERSON IS ONE SIZE EVERYWHERE, and that size is 28 x 44.
##
## It used to be 14 x 22, which is 7.6 x 12.0pt at the 0.546 iPhone scale --
## a whole person SHORTER than the single digit on their own badge, and 18% of
## the height of the floor they stood on. The cause was sizing the figure from
## the hall's tightest case (20-unit cells, so six columns fit a 140-unit strip)
## and then making "identical everywhere" a rule, which exported the hall's
## budget into a car with three times the room.
##
## The hall now draws EIGHT people rather than twelve. Nothing is lost: the
## count beside the strip has always been exact, and the strip has always shown
## what fits rather than everyone.
const FIGURE := Vector2(28, 44)
const BAR_W := 4.0
## One unit. Enough to separate at 26 x 41; more would read as a sticker border.
const OUTLINE := 1.0
## cell = figure + bar wide, badge + gap + figure tall.
## 12 tall, not 15. The hall's badge holds a DRAWN triangle rather than a glyph,
## so it gives up height cheaply -- and those three units are what let the figure
## grow to 44 while the cell stays 58 and the hall still shows eight.
const HALL_BADGE := Vector2(16, 12)
## The riding badge's font. A font-24 line box is what the 30-unit CarRack badge
## was sized for, and it is 13.1pt at the 0.546 iPhone scale.
const CAR_FONT := 24
const HALL_CELL := Vector2(FIGURE.x + BAR_W, HALL_BADGE.y + 2.0 + FIGURE.y)
const HALL_FIGURE_TOP := HALL_BADGE.y + 2.0

## The figure's parts as fractions of its box, so one size change moves all of
## them and the proportions survive it.
const HEAD_D := 0.57      ## of width
const HEAD_CY := 0.19     ## of height
const TORSO_X := 0.14
const TORSO_Y := 0.41
const TORSO_W := 0.71
const TORSO_H := 0.41
const LEG_W := 0.29
const LEG_H := 0.18
const LEG_Y := 0.82

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
## The RIDING badge and its font. A waiting person uses HALL_BADGE and no font
## at all -- the hall draws its arrow as a triangle -- so these only ever hold
## the car's numbers, and they are set together by set_cell.
var _badge_h: float = HALL_BADGE.y
var _font_size: int = CAR_FONT
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
##
## It used to take (cell, badge_h, font_size). The one caller passed
## CarRack.BADGE_H and 24 on every call and always had -- two parameters that
## could only ever hold one value each, and a `_font_size = 12` default that was
## never rendered. Those are constants, so they are constants here.
func set_cell(cell: Vector2) -> void:
	if is_equal_approx(cell.x, _cell.x) and is_equal_approx(cell.y, _cell.y):
		return
	_cell = cell
	_badge_h = CarRack.BADGE_H
	_font_size = CAR_FONT
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
	# EARLY-OUT, like every other setter here. FloorRow.set_waiting calls this on
	# every unused sprite on every refresh -- twelve per floor, forty floors, at
	# 60 fps -- so an unconditional _dirty() queued a redraw of the entire strip
	# every frame for sprites that are not even visible.
	if not visible:
		return
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
	# The band is what the figure may occupy: the whole cell in the car, and the
	# cell less the patience bar in the hall.
	var band_w := _cell.x if _riding else _cell.x - BAR_W
	var badge := Rect2()
	if _riding or _glyph != "":
		var bw := _cell.x if _riding else HALL_BADGE.x
		badge = Rect2((band_w - bw) * 0.5, 0, bw, _badge_h)
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
		"head": Rect2(figure.position
			+ Vector2((1.0 - HEAD_D) * 0.5 * FIGURE.x, 0),
			Vector2(HEAD_D * FIGURE.x, HEAD_D * FIGURE.x)),
		"torso": Rect2(figure.position + Vector2(TORSO_X * FIGURE.x, TORSO_Y * FIGURE.y),
			Vector2(TORSO_W * FIGURE.x, TORSO_H * FIGURE.y)),
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
		# The badge is dark too, so it needs the same help against dark scenery.
		draw_rect(badge.grow(OUTLINE), Palette.PERSON_OUTLINE)
		draw_rect(badge, Palette.BADGE_BG)
		if not _riding:
			_draw_arrow(badge)
	var bar: Rect2 = q["bar"]
	if bar.size != Vector2.ZERO:
		var track := Rect2(bar.position.x, (q["figure"] as Rect2).position.y,
			BAR_W, FIGURE.y)
		draw_rect(track.grow(OUTLINE), Palette.PERSON_OUTLINE)
		draw_rect(track, Palette.PERSON_BAR_TRACK)
		draw_rect(bar, Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, _fraction))
	var figure: Rect2 = q["figure"]
	var skin: Color = Palette.PERSON_SKINS[posmod(_tint_key, Palette.PERSON_SKINS.size())]
	var shirt: Color = Palette.PERSON_SHIRTS[posmod(_tint_key, Palette.PERSON_SHIRTS.size())]
	var head_r := HEAD_D * FIGURE.x * 0.5
	var lw := LEG_W * FIGURE.x
	var lh := LEG_H * FIGURE.y
	var ly := LEG_Y * FIGURE.y
	var leg_l := Rect2(figure.position + Vector2(TORSO_X * FIGURE.x, ly),
		Vector2(lw, lh))
	var leg_r := Rect2(figure.position
		+ Vector2((TORSO_X + TORSO_W) * FIGURE.x - lw, ly), Vector2(lw, lh))

	# EVERY part is outlined first, then every part filled -- so the result is one
	# silhouette rather than four outlined stickers with seams between them.
	# A person has to read against scenery this palette does not control.
	draw_circle((q["head"] as Rect2).get_center(), head_r + OUTLINE, Palette.PERSON_OUTLINE)
	draw_rect((q["torso"] as Rect2).grow(OUTLINE), Palette.PERSON_OUTLINE)
	draw_rect(leg_l.grow(OUTLINE), Palette.PERSON_OUTLINE)
	draw_rect(leg_r.grow(OUTLINE), Palette.PERSON_OUTLINE)

	draw_circle((q["head"] as Rect2).get_center(), head_r, skin)
	draw_rect(q["torso"], shirt)
	draw_rect(leg_l, Palette.PERSON_LEGS)
	draw_rect(leg_r, Palette.PERSON_LEGS)

func _draw_arrow(badge: Rect2) -> void:
	var c := badge.get_center()
	var up := _glyph == ARROW_UP
	var h := badge.size.y * 0.32
	var w := badge.size.x * 0.32
	var dy := h if up else -h
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -dy), c + Vector2(-w, dy), c + Vector2(w, dy)]),
		Palette.BADGE_INK)
