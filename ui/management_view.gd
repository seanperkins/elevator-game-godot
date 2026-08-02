class_name ManagementView
extends Control

## One scrolling surface: a live readout, then a list under headings. No tabs --
## a second navigation layer inside a view you already navigated to, solving a
## length problem this list does not have yet.
##
## Every dynamic string goes through Label, never RichTextLabel with bbcode:
## upgrade levels come from a user:// save at Milestone 6, on a github.io origin
## shared with every other Pages site on the account (see main.gd).

const BUTTON_HEIGHT := 88.0       # 48pt at the 0.546 iPhone scale
const MARGIN := 12.0

var _state: GameState
var _rows: Dictionary = {}        # id -> Button
var _riders: Label
var _wait: Label
var _gaveup: Label
var _dispatch_box: VBoxContainer
var _dispatch_note: Label
var _shaft_buttons: Array[Button] = []
var _shafts_shown: int = -1

func bind(state: GameState) -> void:
	_state = state

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_build_readout())
	box.add_child(_heading("SPEND"))
	for id in _state.upgrades.ids():
		if id == "shaft" or id == "row":
			continue          # bought on the board, where they appear
		box.add_child(_build_upgrade_row(id))

	# Dispatch policy has no place on the board -- it is a property of a shaft
	# rather than of anywhere in the building -- which is exactly the split rule
	# that puts it here.
	box.add_child(_heading("DISPATCH"))
	_dispatch_note = Label.new()
	_dispatch_note.add_theme_font_size_override("font_size", 13)
	_dispatch_note.add_theme_color_override("font_color", Color("7c8899"))
	box.add_child(_dispatch_note)
	_dispatch_box = VBoxContainer.new()
	_dispatch_box.add_theme_constant_override("separation", 6)
	box.add_child(_dispatch_box)
	refresh()

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("5b6675"))
	l.custom_minimum_size = Vector2(0, 28)
	return l

## Three numbers over a rolling ~60-simulated-second window. They are honest
## JOINTLY, not individually: average wait excludes expiries, so as service
## collapses it improves while "gave up" climbs.
func _build_readout() -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	_riders = _stat(row, "riders / min")
	_wait = _stat(row, "avg wait")
	_gaveup = _stat(row, "gave up")
	return panel

func _stat(parent: Control, caption: String) -> Label:
	var col := VBoxContainer.new()
	parent.add_child(col)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 22)
	col.add_child(value)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color("5b6675"))
	col.add_child(cap)
	return value

func _build_upgrade_row(id: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	var captured := id
	b.pressed.connect(func() -> void: _state.buy(captured))
	_rows[id] = b
	return b

## Annotations state MECHANICAL effects read from Upgrades -- never a predicted
## metric, and never a formula copied into the view. Duplicating
## maxi(20 - 2*level, 4) and dropping the clamp would render "doors 4 -> 2".
func refresh() -> void:
	if _state == null:
		return
	var m := _state.metrics
	_riders.text = Metrics.format_rate(m.deliveries())
	_wait.text = Metrics.format_wait(m.average_wait_seconds())
	_gaveup.text = Metrics.format_rate(m.expiries())

	_refresh_dispatch()

	for id in _rows.keys():
		var b: Button = _rows[id]
		var label_name := _state.upgrades.name_of(id)
		var lvl := _state.upgrades.level_of(id)
		if _state.upgrades.is_maxed(id):
			b.text = "%s  MAX (Lv%d)" % [label_name, lvl]
			b.disabled = true
			continue
		if _state.upgrades.is_zero_delta(id):
			b.text = "%s  Lv%d\n%s (max effect)" % [
				label_name, lvl, _effect_text(id, lvl, lvl)]
			b.disabled = true
			continue
		var cost := _state.upgrades.cost_of(id)
		b.text = "%s  Lv%d      $%s\n%s" % [
			label_name, lvl, NumberFormat.compact(cost),
			_effect_text(id, lvl, lvl + 1)]
		b.disabled = not _state.economy.can_afford(cost)

## One toggle per shaft, plus how many licences are left. Buttons are built as
## shafts are bought, so a shaft purchased on the board turns up here.
func _refresh_dispatch() -> void:
	var shafts := _state.building.cars.size()
	while _shaft_buttons.size() < shafts:
		var index := _shaft_buttons.size()
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		b.add_theme_font_size_override("font_size", 18)
		# `index` is captured by value, which is the one place that helps.
		b.pressed.connect(func() -> void:
			_state.set_auto(index, not _state.auto.is_enabled(index)))
		_dispatch_box.add_child(b)
		_shaft_buttons.append(b)
	_shafts_shown = shafts

	var licences := _state.auto_licences()
	var used := _state.auto.enabled_count()
	if licences <= 0:
		_dispatch_note.text = "Buy Auto-Dispatch to let a shaft run itself."
	else:
		_dispatch_note.text = "%d of %d shafts on auto." % [used, licences]

	for i in range(_shaft_buttons.size()):
		var b: Button = _shaft_buttons[i]
		b.visible = i < shafts
		if not b.visible:
			continue
		var on := _state.auto.is_enabled(i)
		b.text = "Shaft %d      %s" % [i + 1, "EVERY FLOOR" if on else "manual"]
		# Disabled only when turning it ON would need a licence there is not.
		b.disabled = not on and used >= licences

func _effect_text(id: String, from_level: int, to_level: int) -> String:
	var a := _state.upgrades.effect_value(id, from_level)
	var b := _state.upgrades.effect_value(id, to_level)
	match id:
		"doors":
			return "doors %d → %d ticks" % [int(a), int(b)]
		"speed":
			return "speed %.2f → %.2f rows/tick" % [a, b]
		"capacity":
			return "capacity %d → %d" % [int(a), int(b)]
		"auto":
			return "%d → %d shafts may run themselves" % [int(a), int(b)]
		_:
			return ""
