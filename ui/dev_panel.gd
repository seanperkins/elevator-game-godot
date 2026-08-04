class_name DevPanel
extends Control

## Cheats, for testing the game against itself. Reached by tapping the cash
## readout seven times, which is the only thing keeping it out of a player's way
## -- it ships in the web export like everything else.
##
## Shaped like PrestigePanel and for the same reasons: a full-screen overlay
## wrapping a ScrollContainer, the topmost child so nothing draws through it,
## inset from the safe area, dismissed by an explicit BACK control.
##
## It EMITS, it does not mutate. Several of these actions touch persistent state
## and have to be written immediately, and game_root owns the save.
##
## No Confirm/Cancel on `Reset save`, deliberately. The prestige REBUILD has one
## because it destroys a run the player earned; every row in here is a cheat
## reached by seven intentional taps, and confirming one row would suggest the
## others are safe.

signal cash_requested(amount: float)
signal earnings_requested(amount: float)
signal blueprints_requested(amount: int)
signal speed_requested(multiplier: int)
signal unlock_requested(level: int)
signal reset_requested()

const BUTTON_HEIGHT := 88.0
const EDGE_MARGIN := 16.0
const GRANT := 10000.0
const GRANT_BLUEPRINTS := 5

var _state: GameState
var _scroll: ScrollContainer
var _close_button: Button
var _box: VBoxContainer
var _speed_buttons: Dictionary = {}     # multiplier -> Button
var _speed: int = 1
var _readout: Label
var _reset_button: Button
var _reset_confirm: Button
var _reset_cancel: Button
var _reset_armed: bool = false

func bind(state: GameState) -> void:
	_state = state
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# NO SCRIM. This is a full-screen OPAQUE overlay, so there is no visible
	# 'outside' to tap -- the scrim was copied from FloorPanel, which is a
	# bottom sheet where the scrim IS the visible outside. Worse, it was
	# added first and then buried under the opaque bg below, so its
	# gui_input never fired and close() was unreachable: opening this panel
	# trapped the player until they force-quit. An explicit control does
	# the job the scrim only appeared to.

	var bg := ColorRect.new()
	bg.color = Palette.PANEL_BG
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

	# First row: leaving must not require scrolling past every cheat.
	_close_button = _action("← BACK", func() -> void: close())

	# Gives the grants visible feedback. +5 Blueprints otherwise produces no
	# on-screen change at all, so you cannot tell it worked.
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 16)
	_readout.add_theme_color_override("font_color", Color("7c8899"))
	_readout.custom_minimum_size = Vector2(0, 24)
	_box.add_child(_readout)

	_box.add_child(_heading("MONEY"))
	# The two money rows are separate ON PURPOSE and must not be merged.
	# Economy.accrue() adds to cash AND lifetime_earnings, and
	# lifetime_earnings is the exact field Prestige.yield_for consumes -- so a
	# single "give me money" button would mint Blueprints on every use and a
	# cheated run's Blueprint count would mean nothing.
	_action("+$10K cash", func() -> void: cash_requested.emit(GRANT))
	_action("+$10K earned  (raises yield)",
		func() -> void: earnings_requested.emit(GRANT))
	_action("+%d Blueprints" % GRANT_BLUEPRINTS,
		func() -> void: blueprints_requested.emit(GRANT_BLUEPRINTS))

	_box.add_child(_heading("SPEED"))
	for n in [1, 2, 4]:
		var captured: int = n
		_speed_buttons[n] = _action("%dx" % n,
			func() -> void: speed_requested.emit(captured))

	_box.add_child(_heading("UPGRADES"))
	var note := Label.new()
	note.text = "Fits mechanicals and hardware. Floors and shafts are bought on the board."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Palette.INK_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(note)
	for level in [1, 2, 3]:
		var captured_level: int = level
		_action("Fit everything to Lv%d" % level,
			func() -> void: unlock_requested.emit(captured_level))

	_box.add_child(_heading("DANGER"))
	var danger := Label.new()
	danger.text = "Reset also deletes the backup and the tech tree — Blueprints, nodes and run count."
	danger.add_theme_font_size_override("font_size", 13)
	danger.add_theme_color_override("font_color", Color("7c8899"))
	danger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(danger)
	# This row DOES get a Confirm/Cancel pair, reversing the original decision.
	# The rationale for refusing one was "confirming one row would suggest the
	# others are safe" -- but the panel already singles this row out under a
	# DANGER heading, so that line is crossed either way, and the asymmetry the
	# rationale missed is that Reset destroys strictly MORE than the prestige
	# REBUILD does: the save, the backup, and the whole Meta. REBUILD is
	# confirmed for less, in a game whose stated invariant is no fail state.
	_reset_button = _action("Reset save and start over", func() -> void:
		_reset_armed = true
		refresh())
	_reset_confirm = _action("Delete everything", func() -> void:
		_reset_armed = false
		reset_requested.emit())
	_reset_cancel = _action("Cancel", func() -> void:
		_reset_armed = false
		refresh())
	refresh()

## Insets the hardware has already claimed. This panel covers the WHOLE screen,
## HUD band included, so it is one of the two surfaces that has to inset itself.
func set_insets(safe: Vector4) -> void:
	if _scroll == null:
		return
	SafeArea.box_overlay(_scroll, safe, EDGE_MARGIN)

func open(state: GameState) -> void:
	_state = state
	_reset_armed = false
	visible = true
	refresh()

func close() -> void:
	_reset_armed = false
	visible = false

func is_reset_armed() -> bool:
	return _reset_armed

## game_root owns the multiplier; this only renders which one is live.
func set_speed(multiplier: int) -> void:
	_speed = multiplier
	refresh()

func refresh() -> void:
	if _state == null:
		return
	_readout.text = "$%s    %d Blueprints    %d runs" % [
		NumberFormat.compact(_state.economy.cash), _state.meta.blueprints,
		_state.meta.runs_completed]
	for n in _speed_buttons.keys():
		var b: Button = _speed_buttons[n]
		b.disabled = (n == _speed)
	_reset_button.visible = not _reset_armed
	_reset_confirm.visible = _reset_armed
	_reset_cancel.visible = _reset_armed

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.INK_FAINT)
	l.custom_minimum_size = Vector2(0, 28)
	return l

func _action(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	_box.add_child(b)
	return b
