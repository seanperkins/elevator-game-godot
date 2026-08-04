class_name ManagementView
extends Control

## One scrolling surface: a live readout, then a list under headings. No tabs --
## a second navigation layer inside a view you already navigated to, solving a
## length problem this list does not have yet.
##
## Every dynamic string goes through Label, never RichTextLabel with bbcode:
## upgrade levels come from a user:// save at Milestone 6, on a github.io origin
## shared with every other Pages site on the account (see main.gd).

## Opening the prestige panel is a view change, so it is announced rather than
## performed: game_root owns which surface is showing.
signal prestige_requested()

const BUTTON_HEIGHT := 88.0       # 48pt at the 0.546 iPhone scale
const MARGIN := 12.0

var _state: GameState
var _floors: Dictionary = {}        # id -> Button
var _riders: Label
var _wait: Label
var _gaveup: Label
var _dispatch_box: VBoxContainer
var _dispatch_note: Label
var _shaft_buttons: Array[Button] = []
var _shafts_shown: int = -1
var _scroll: ScrollContainer
var _drag: DragScroll

## Runs BEFORE the buttons get the event, which is the only place a drag can be
## taken away from them. See DragScroll.
func _input(event: InputEvent) -> void:
	if not visible or _drag == null:
		return
	if _drag.handle(event, get_global_rect()):
		get_viewport().set_input_as_handled()

func bind(state: GameState) -> void:
	_state = state

	var bg := ColorRect.new()
	bg.color = Palette.PANEL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_drag = DragScroll.new(_scroll)
	var scroll := _scroll

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_build_readout())
	box.add_child(_heading("SPEND"))
	for id in _state.upgrades.ids():
		if id == "shaft" or id == "floor":
			continue          # bought on the board, where they appear
		box.add_child(_build_upgrade_row(id))

	# Dispatch policy has no place on the board -- it is a property of a shaft
	# rather than of anywhere in the building -- which is exactly the split rule
	# that puts it here.
	box.add_child(_heading("DISPATCH"))
	_dispatch_note = Label.new()
	_dispatch_note.add_theme_font_size_override("font_size", 18)
	_dispatch_note.add_theme_color_override("font_color", Palette.INK_MUTED)
	box.add_child(_dispatch_note)
	_dispatch_box = VBoxContainer.new()
	_dispatch_box.add_theme_constant_override("separation", 6)
	box.add_child(_dispatch_box)

	# Last, under everything you could spend cash on: it is the thing you do
	# when there is nothing left to buy.
	box.add_child(_heading("REBUILD"))
	var rebuild := Button.new()
	rebuild.text = "Demolish and start again"
	rebuild.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	rebuild.add_theme_font_size_override("font_size", 24)
	rebuild.pressed.connect(func() -> void: prestige_requested.emit())
	box.add_child(rebuild)
	refresh()

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Palette.INK_FAINT)
	l.custom_minimum_size = Vector2(0, 28)
	return l

## Three numbers over a rolling ~60-simulated-second window. They are honest
## JOINTLY, not individually: average wait excludes expiries, so as service
## collapses it improves while "gave up" climbs.
func _build_readout() -> Control:
	var panel := PanelContainer.new()
	# A margin, or the leftmost caption is clipped by the panel's own edge --
	# which is what "riders / min" was doing, losing its first two characters.
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	panel.add_child(pad)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	pad.add_child(rows)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	rows.add_child(cols)

	_riders = _stat(cols, "riders / min")
	_wait = _stat(cols, "avg wait")
	_gaveup = _stat(cols, "gave up")

	# The window was documented only in metrics.gd, so on screen these three
	# numbers had no timescale at all -- "13 riders/min" could as easily have
	# been the whole run. It is a rolling 60 SIMULATED seconds (Metrics.BUCKETS).
	var window := Label.new()
	window.text = "over the last 60 seconds"
	window.add_theme_font_size_override("font_size", 15)
	window.add_theme_color_override("font_color", Palette.INK_FAINT)
	rows.add_child(window)
	return panel

## One column of the readout. Equal minimum widths, so the three columns line up
## on a grid instead of each being as wide as its own caption -- which is what
## made the row read as ragged.
const STAT_WIDTH := 150.0

func _stat(parent: Control, caption: String) -> Label:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(STAT_WIDTH, 0)
	col.add_theme_constant_override("separation", 0)
	parent.add_child(col)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 30)
	col.add_child(value)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", Palette.INK_FAINT)
	col.add_child(cap)
	return value

func _build_upgrade_row(id: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation", 12)
	b.add_theme_font_size_override("font_size", 24)
	var captured := id
	b.pressed.connect(func() -> void: _state.buy(captured))
	_floors[id] = b
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

	for id in _floors.keys():
		var b: Button = _floors[id]
		var label_name := _state.upgrades.name_of(id)
		var lvl := _state.upgrades.level_of(id)
		# A one-level fitting has no ladder to place you on, so it never shows a
		# number: "Lv1" reads as the first of several when there is no second.
		var single := _state.upgrades.is_single_level(id)
		if _state.upgrades.is_maxed(id):
			b.text = ("%s  UNLOCKED" % label_name) if single \
				else ("%s  MAX (Lv%d)" % [label_name, lvl])
			b.disabled = true
			continue
		if _state.upgrades.is_zero_delta(id):
			b.text = "%s  Lv%d\n%s (max effect)" % [
				label_name, lvl, _effect_text(id, lvl, lvl)]
			b.disabled = true
			continue
		var cost := _state.upgrades.cost_of(id)
		var head := ("%s      $%s" % [label_name, NumberFormat.compact(cost)]) if single \
			else ("%s  Lv%d      $%s" % [label_name, lvl, NumberFormat.compact(cost)])
		b.text = "%s\n%s" % [head, _effect_text(id, lvl, lvl + 1)]
		b.disabled = not _state.economy.can_afford(cost)

## One toggle per shaft, plus how many licences are left. Buttons are built as
## shafts are bought, so a shaft purchased on the board turns up here.
func _refresh_dispatch() -> void:
	var shafts := _state.building.cars.size()
	while _shaft_buttons.size() < shafts:
		var index := _shaft_buttons.size()
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("h_separation", 12)
		b.add_theme_font_size_override("font_size", 24)
		# `index` is captured by value, which is the one place that helps.
		b.pressed.connect(func() -> void: _cycle_policy(index))
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
		var preset := _state.auto.preset_of(i)
		b.text = "Shaft %d      %s" % [i + 1, DispatchPolicy.preset_name(preset)]
		# Disabled only when there is nothing it could be changed to: no licence
		# left and nothing running here to turn off.
		b.disabled = not _state.auto.is_enabled(i) and used >= licences

## Steps a shaft through the policies whose hardware is installed. Each tap is
## one step, and set_policy is the authority on whether a step is allowed --
## the button never decides for itself.
func _cycle_policy(shaft: int) -> void:
	var presets: Array = _state.available_presets()
	if presets.is_empty():
		return
	var at := presets.find(_state.auto.preset_of(shaft))
	for step in range(1, presets.size() + 1):
		if _state.set_policy(shaft, presets[(at + step) % presets.size()]):
			return

func _effect_text(id: String, from_level: int, to_level: int) -> String:
	var a := _state.upgrades.effect_value(id, from_level)
	var b := _state.upgrades.effect_value(id, to_level)
	match id:
		"doors":
			return "doors %d → %d ticks" % [int(a), int(b)]
		"speed":
			return "speed %.2f → %.2f floors/tick" % [a, b]
		"capacity":
			return "capacity %d → %d" % [int(a), int(b)]
		"auto":
			return "%d → %d shafts may run themselves" % [int(a), int(b)]
		_:
			return ""
