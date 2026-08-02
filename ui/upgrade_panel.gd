class_name UpgradePanel
extends Control

## A bottom sheet, not a side column. The board is capped at 8 shafts of 84
## units plus a 56-unit gutter -- 728 of the 720-unit width -- so anything
## permanently occupying horizontal space would make the last shafts
## unreachable, and §3's 44pt guarantee is what fixes those widths.
##
## Buttons are 88 units tall so they clear the 44pt touch floor at the
## 0.546 iPhone scale (88 * 0.546 = 48pt).

const BUTTON_HEIGHT := 88.0
const MARGIN := 12.0

var _state: GameState
var _buttons: Dictionary = {}       # id -> Button

func bind(state: GameState) -> void:
	_state = state

	var sheet := ColorRect.new()
	sheet.color = Color("161c24")
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP   # do not leak taps to the board
	add_child(sheet)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = MARGIN
	box.offset_top = MARGIN
	box.offset_right = -MARGIN
	box.offset_bottom = -MARGIN
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	for id in _state.upgrades.ids():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		b.add_theme_font_size_override("font_size", 20)
		var captured := id
		b.pressed.connect(func() -> void: _state.buy(captured))
		box.add_child(b)
		_buttons[id] = b
	refresh()

func refresh() -> void:
	if _state == null:
		return
	for id in _buttons.keys():
		var b: Button = _buttons[id]
		var lvl := _state.upgrades.level_of(id)
		if _state.upgrades.is_maxed(id):
			b.text = "%s  MAX (%d)" % [_state.upgrades.name_of(id), lvl]
			b.disabled = true
			continue
		var cost := _state.upgrades.cost_of(id)
		b.text = "%s  Lv%d      $%s" % [
			_state.upgrades.name_of(id), lvl, NumberFormat.compact(cost)]
		b.disabled = not _state.economy.can_afford(cost)
