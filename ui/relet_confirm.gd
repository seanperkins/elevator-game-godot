class_name ReletConfirm
extends Control

## The single confirmed action in the game.
##
## Every other purchase is a bare tap, because its target meets the 44pt floor
## and the price is on the target. A floor row cannot: at the 40-floor cap it is
## 29.6 units -- 16.16pt -- so a vertical miss onto an adjacent ALSO-VACANT floor
## would spend $40 on the wrong one. Naming the floor in the prompt is what makes
## that mistake recoverable.

signal confirmed(floor_index: int)

const BUTTON_HEIGHT := 88.0

var floor_index: int = -1

var _state: GameState
var _title: Label
var _confirm: Button

func bind(state: GameState) -> void:
	_state = state
	visible = false

	var bg := ColorRect.new()
	bg.color = Color("161c24")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = -16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_confirm = Button.new()
	_confirm.text = "RE-LEASE"
	_confirm.add_theme_font_size_override("font_size", 20)
	_confirm.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_confirm.pressed.connect(_on_confirm)
	box.add_child(_confirm)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	cancel.pressed.connect(close)
	box.add_child(cancel)

func open_for(p_floor_index: int) -> void:
	floor_index = p_floor_index
	# Task 17 deletes this file. relet_cost is gone and leasing now needs a
	# KIND, which a single confirm cannot carry, so the price and the
	# affordability gate are dropped for the interim.
	_title.text = "Re-lease floor %d" % floor_index
	_confirm.disabled = false
	visible = true

func close() -> void:
	visible = false
	floor_index = -1

func _on_confirm() -> void:
	var target := floor_index
	close()
	# Interim stand-in for the kind picker FloorPanel builds in Task 17:
	# confirm leases the apartments tenant the floor's class allows.
	if _state.lease(target, "apartments"):
		confirmed.emit(target)
