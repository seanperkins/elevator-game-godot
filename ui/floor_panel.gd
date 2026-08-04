class_name FloorPanel
extends Control

## The whole feature's surface: what this floor is, what its day looks like,
## what upgrading costs, and -- only when vacant -- who will take it.
##
## A bottom sheet over the board, inset by the safe area. It is a panel, not a
## modal: the sim keeps running behind it, and dismissing it (tap the scrim) is
## a close, never a view change.
##
## The lease picker is hidden while a tenant sits there, including while a
## move-out countdown runs. You choose who moves in, not who moves out, so
## tenant churn stays driven by satisfaction and the move-out clock keeps its
## teeth.
##
## Purchases are REFUSED by the sim, not merely greyed here (§12): the buttons
## are informative, the refusal is authoritative. picker_visible() and
## is_locked() are the seams the input tests read.

signal lease_requested(floor_index: int, kind_id: String)
signal upgrade_requested(floor_index: int)

const BUTTON_HEIGHT := 72.0            # 39pt at the 0.546 board scale
const SHEET_FRACTION := 0.46

var _state: GameState
var _floor: int = -1

var _bg: ColorRect
var _box: VBoxContainer
var _header: Label
var _bar: ProgressBar
var _sparkline: DaySparkline
var _upgrade: Button
var _picker: VBoxContainer
var _lease_buttons: Array[Button] = []

func bind(state: GameState) -> void:
	_state = state
	visible = false

	_bg = ColorRect.new()
	_bg.color = Palette.SCRIM
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_bg.gui_input.connect(func(_e: InputEvent) -> void: close())

	var sheet := Control.new()
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_top = -int(size.y * SHEET_FRACTION)
	sheet.offset_bottom = 0
	sheet.offset_left = 0
	sheet.offset_right = 0
	add_child(sheet)

	var panel := ColorRect.new()
	panel.color = Palette.CARD_BG
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.add_child(panel)

	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = 16
	_box.offset_right = -16
	_box.offset_top = 12
	_box.offset_bottom = -12
	_box.add_theme_constant_override("separation", 10)
	sheet.add_child(_box)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 24)
	_box.add_child(_header)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_box.add_child(_bar)

	_sparkline = DaySparkline.new()
	_sparkline.custom_minimum_size = Vector2(0, 56)
	_box.add_child(_sparkline)

	_upgrade = Button.new()
	_upgrade.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_upgrade.add_theme_font_size_override("font_size", 22)
	_upgrade.pressed.connect(_on_upgrade)
	_box.add_child(_upgrade)

	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 6)
	_box.add_child(_picker)

## Populates the sheet for `floor` and shows it. Safe to call repeatedly -- the
## panel is rebuilt from current state each time, never once.
func show_floor(state: GameState, floor_index: int) -> void:
	_state = state
	_floor = floor_index
	var vacant := _state.tenancy.is_vacant(floor_index)
	var tier := _state.fitout.tier_at(floor_index)
	var kind_id := _state.tenancy.kind_at(floor_index)
	var kind := _state.catalog.kind(kind_id)

	var tenant := "" if kind == null else (" ·  " + kind.display_name)
	_header.text = "Floor %d%s   Class %d" % [floor_index, "" if vacant else tenant, tier]

	_bar.value = _sat_fraction(vacant) * 100.0
	_sparkline.show_kind(kind)
	_sparkline.set_now(_state.clock.hour_of_day())

	var cost := _state.class_upgrade_cost(floor_index)
	_upgrade.text = "UPGRADE CLASS  $%s" % NumberFormat.compact(cost)
	_upgrade.disabled = not is_finite(cost) or not _state.economy.can_afford(cost)

	_rebuild_picker(vacant)
	visible = true

func _sat_fraction(vacant: bool) -> float:
	if vacant:
		return 0.0
	return clampf(_state.tenancy.satisfaction_at(_floor), 0.0, 1.0)

## The lease picker is present only while the floor is vacant. Rebuilt each
## show so the available kinds and prices reflect the current class and cash.
func _rebuild_picker(vacant: bool) -> void:
	for b in _lease_buttons:
		b.queue_free()
	_lease_buttons.clear()
	_picker.visible = vacant
	if not vacant:
		return
	for k in _state.available_kinds(_floor):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		b.add_theme_font_size_override("font_size", 20)
		var cost := _state.lease_cost(_floor, k.id)
		var locked := is_locked(k.id)
		b.text = "%s  $%s%s" % [k.display_name, NumberFormat.compact(cost),
			"  (locked)" if locked else ""]
		b.disabled = locked or not _state.economy.can_afford(cost)
		var r := _floor
		var id := k.id
		b.pressed.connect(func() -> void: lease_requested.emit(r, id))
		_picker.add_child(b)
		_lease_buttons.append(b)

func picker_visible() -> bool:
	return _picker != null and _picker.visible and _state != null and _floor >= 0 \
		and _state.tenancy.is_vacant(_floor)

## A kind the floor's current class cannot host.
func is_locked(kind_id: String) -> bool:
	if _state == null or _floor < 0:
		return true
	var k := _state.catalog.kind(kind_id)
	if k == null:
		return true
	return k.requires_class > _state.fitout.tier_at(_floor)

func _on_upgrade() -> void:
	upgrade_requested.emit(_floor)

func close() -> void:
	visible = false
	_floor = -1
