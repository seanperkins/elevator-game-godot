class_name PrestigePanel
extends Control

## The tech tree, the yield projection, and the one irreversible action in the
## game.
##
## Its shape is ManagementView's, not FloorPanel's. The tree needs ~708 units
## idle and ~796 armed against FloorPanel's SHEET_FRACTION * 1280 = 589, and
## VBoxContainer honours custom_minimum_size -- so the overflow would draw
## OUTSIDE the sheet, over the board. 88-unit rows are not negotiable downward
## either: that is 48pt at the 0.546 board scale, and FloorPanel's own 72 is
## already below the touch floor, as that constant's comment admits.
##
## The panel EMITS, it does not mutate. A node purchase changes PERSISTENT
## state and must be written immediately, so it follows FloorPanel's
## lease_requested rather than ManagementView's direct _state.buy().
##
## Every dynamic string goes through Label, never BBCode -- same origin argument
## as ManagementView's header.

signal node_purchase_requested(id: String)
signal demolish_requested()

const BUTTON_HEIGHT := 88.0        # 48pt at the 0.546 iPhone scale
## Breathing room inside the safe area, so the tree does not run to the glass.
const EDGE_MARGIN := 16.0

var _state: GameState
var _armed: bool = false

var _box: VBoxContainer
var _scroll: ScrollContainer
var _yield_label: Label
var _rows: Dictionary = {}          # node id -> Button
var _rebuild_button: Button
var _confirm_button: Button
var _cancel_button: Button

func bind(state: GameState) -> void:
	_state = state
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var scrim := ColorRect.new()
	scrim.color = Color("05080c", 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	scrim.gui_input.connect(func(_e: InputEvent) -> void: close())

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_box)

	# The projection IS the confirmation: the number being decided on is on
	# screen before the button is reachable. With a $1,000 gate this line does
	# real work for the first half-hour of a new game.
	_yield_label = Label.new()
	_yield_label.add_theme_font_size_override("font_size", 18)
	_yield_label.custom_minimum_size = Vector2(0, 24)
	_box.add_child(_yield_label)

	_box.add_child(_heading("STRUCTURE"))
	for id in _state.meta.ids():
		if _state.meta.branch_of(id) == "structure":
			_box.add_child(_node_row(id))
	_box.add_child(_heading("MECHANICAL"))
	for id in _state.meta.ids():
		if _state.meta.branch_of(id) == "mechanical":
			_box.add_child(_node_row(id))

	# Grants apply at construction and restore_levels overwrites, so a
	# Mechanical node bought mid-run does nothing until the next rebuild. An
	# unexplained no-op reads as a bug.
	var note := Label.new()
	note.text = "Mechanical nodes apply from the next rebuild."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("7c8899"))
	_box.add_child(note)

	# A Confirm/Cancel PAIR, never a second tap on an armed button. The UI spec
	# establishes this project's one confirmation shape as a distinct labelled
	# control carrying the price; an armed button has no disarm path and stays
	# armed while the sim runs; and touch emulation delivers one physical tap
	# TWICE, which is why test_one_thumb_tap_buys_exactly_one_floor exists.
	# Arming on tap 1 and committing on tap 2 would let a stray double-tap
	# destroy a run, in a game whose stated invariant is that it has no fail
	# state.
	_rebuild_button = _action("REBUILD", func() -> void:
		_armed = true
		refresh())
	_confirm_button = _action("", func() -> void:
		_armed = false
		demolish_requested.emit())
	_cancel_button = _action("Cancel", func() -> void:
		_armed = false
		refresh())
	refresh()

## Insets the hardware has already claimed. This panel covers the WHOLE screen,
## including the HUD's band, so it is the only surface here that has to inset
## itself -- everything else is laid out inside a board that game_root has
## already inset. Without it the yield line sits under the Dynamic Island.
func set_insets(safe: Vector4) -> void:
	if _scroll == null:
		return
	_scroll.offset_left = safe.x + EDGE_MARGIN
	_scroll.offset_top = safe.y + EDGE_MARGIN
	_scroll.offset_right = -(safe.z + EDGE_MARGIN)
	_scroll.offset_bottom = -(safe.w + EDGE_MARGIN)

func open(state: GameState) -> void:
	_state = state
	_armed = false
	visible = true
	refresh()

func close() -> void:
	_armed = false
	visible = false

## The seam the scene tests read: asserting only that a tap "changed nothing"
## would pass with the whole confirmation step deleted.
func is_armed() -> bool:
	return _armed

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("5b6675"))
	l.custom_minimum_size = Vector2(0, 28)
	return l

func _action(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	_box.add_child(b)
	return b

func _node_row(id: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	var captured := id
	b.pressed.connect(func() -> void: node_purchase_requested.emit(captured))
	_rows[id] = b
	return b

## Annotations read the Meta's derivations rather than copying their formulas,
## so an annotation can never fabricate a cap.
func refresh() -> void:
	if _state == null:
		return
	var meta := _state.meta
	var earned := _state.economy.lifetime_earnings
	var bp := Prestige.yield_for(earned)
	if bp >= 1:
		_yield_label.text = "This building is worth %d Blueprint%s" % [
			bp, "" if bp == 1 else "s"]
	else:
		var needed := Prestige.DEMOLITION_FLOOR + Prestige.EARNINGS_PER_BLUEPRINT - earned
		_yield_label.text = "$%s more to earn your first Blueprint" % \
			NumberFormat.compact(maxf(needed, 0.0))

	for id in _rows.keys():
		var b: Button = _rows[id]
		var lvl := meta.level_of(id)
		if meta.is_maxed(id):
			b.text = "%s  MAX (Lv%d)\n%s" % [meta.name_of(id), lvl, meta.note_of(id)]
			b.disabled = true
			continue
		if meta.is_zero_delta(id, _state.upgrades):
			b.text = "%s  Lv%d\n%s (max effect)" % [
				meta.name_of(id), lvl, meta.note_of(id)]
			b.disabled = true
			continue
		b.text = "%s  Lv%d      %d BP\n%s" % [
			meta.name_of(id), lvl, meta.cost_of(id), meta.note_of(id)]
		b.disabled = not meta.can_buy(id, _state.upgrades)

	_rebuild_button.visible = not _armed
	_rebuild_button.disabled = bp < 1
	_confirm_button.visible = _armed
	_confirm_button.text = "Rebuild for %d Blueprint%s" % [bp, "" if bp == 1 else "s"]
	_cancel_button.visible = _armed
