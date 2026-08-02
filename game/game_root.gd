extends Control

## Owns the sim and pumps it. Physics stays at Godot's default 60 Hz and the
## clock accumulates to 20 Hz -- one tick per callback would run the sim 3x fast.

const START_ROWS := 6
const START_SHAFTS := 1
const START_SEED := 20260802

const HUD_HEIGHT := 96.0
const SHEET_FRACTION := 0.5      # the upgrade sheet covers the lower half

var state: GameState
var _view: BuildingView
var _cash_label: Label
var _rate_label: Label
var _panel: UpgradePanel
var _toggle: Button
var _last_shape := Vector2i.ZERO

func _ready() -> void:
	state = GameState.new(START_ROWS, START_SHAFTS, START_SEED)

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 28)
	_cash_label.position = Vector2(16, 12)
	add_child(_cash_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.position = Vector2(16, 48)
	add_child(_rate_label)

	# The board keeps the full width: 8 shafts of 84 plus the 56 gutter already
	# spend it, so the upgrade UI has to be a sheet over the board, not beside it.
	_view = BuildingView.new()
	_view.position = Vector2(0, HUD_HEIGHT)
	_view.size = Vector2(size.x, size.y - HUD_HEIGHT)
	add_child(_view)
	_view.bind(state)

	_panel = UpgradePanel.new()
	_panel.position = Vector2(0, size.y * (1.0 - SHEET_FRACTION))
	_panel.size = Vector2(size.x, size.y * SHEET_FRACTION)
	_panel.visible = false
	add_child(_panel)
	_panel.bind(state)

	# 88 units clears the 44pt floor at the 0.546 iPhone scale.
	_toggle = Button.new()
	_toggle.text = "UPGRADES"
	_toggle.add_theme_font_size_override("font_size", 20)
	_toggle.size = Vector2(200, 88)
	_toggle.position = Vector2(size.x - 208, 4)
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)

	_last_shape = Vector2i(state.building.row_count, state.building.cars.size())

func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "CLOSE" if _panel.visible else "UPGRADES"

func _physics_process(delta: float) -> void:
	var ticks := state.clock.take_ticks(delta)
	if ticks > 0:
		state.tick(ticks)
	_view.refresh()

	var shape := Vector2i(state.building.row_count, state.building.cars.size())
	if shape != _last_shape:
		_view.rebuild()
		_last_shape = shape
	_panel.refresh()

	_cash_label.text = "$" + NumberFormat.compact(state.economy.cash)
	var rent := 0.0
	for row in range(state.building.row_count):
		rent += state.tenancy.rent_at(row)
	_rate_label.text = "%s/min   combo %.2fx" % [
		NumberFormat.compact(rent), state.economy.combo]
