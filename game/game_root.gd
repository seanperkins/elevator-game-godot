extends Control

## Owns the sim and pumps it. Physics stays at Godot's default 60 Hz and the
## clock accumulates to 20 Hz -- one tick per callback would run the sim 3x fast.

const START_ROWS := 6
const START_SHAFTS := 1
const START_SEED := 20260802

const HUD_HEIGHT := 96.0
const SHEET_FRACTION := 0.5      # the upgrade sheet covers the lower half
const TOUCH_MIN := 88.0          # 48pt at the 0.546 iPhone scale

var state: GameState
var _view: BuildingView
var _cash_label: Label
var _rate_label: Label
var _panel: UpgradePanel
var _toggle: Button
var _prev_shaft: Button
var _next_shaft: Button
var _pager_label: Label
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
	_cash_label.position = Vector2(16, 10)
	add_child(_cash_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.position = Vector2(16, 48)
	add_child(_rate_label)

	_view = BuildingView.new()
	_view.position = Vector2(0, HUD_HEIGHT)
	_view.size = Vector2(size.x, size.y - HUD_HEIGHT)
	add_child(_view)
	_view.bind(state)

	# Paging the shaft strip is a tap, never a swipe: the dispatch drag is
	# vertical and arcs sideways by more than half a column (§2.1), so any
	# horizontal read on the board itself would steal the primary verb.
	_prev_shaft = _pager_button("<", 236.0, func() -> void: _view.scroll_by(-1))
	_next_shaft = _pager_button(">", 420.0, func() -> void: _view.scroll_by(1))

	_pager_label = Label.new()
	_pager_label.add_theme_font_size_override("font_size", 14)
	_pager_label.add_theme_color_override("font_color", Color("7c8899"))
	_pager_label.position = Vector2(328, 38)
	_pager_label.size = Vector2(88, 20)
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pager_label)

	_panel = UpgradePanel.new()
	_panel.position = Vector2(0, size.y * (1.0 - SHEET_FRACTION))
	_panel.size = Vector2(size.x, size.y * SHEET_FRACTION)
	_panel.visible = false
	add_child(_panel)
	_panel.bind(state)

	_toggle = Button.new()
	_toggle.text = "UPGRADES"
	_toggle.add_theme_font_size_override("font_size", 20)
	_toggle.size = Vector2(200, TOUCH_MIN)
	_toggle.position = Vector2(size.x - 208, 4)
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)

	_last_shape = Vector2i(state.building.row_count, state.building.cars.size())
	_refresh_pager()

func _pager_button(label: String, x: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 24)
	b.size = Vector2(TOUCH_MIN, TOUCH_MIN)
	b.position = Vector2(x, 4)
	b.pressed.connect(on_press)
	b.pressed.connect(_refresh_pager)
	add_child(b)
	return b

func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "CLOSE" if _panel.visible else "UPGRADES"

## Hidden entirely while every shaft is on screen -- a disabled control the
## player has never needed is just noise on a 393pt-wide phone.
func _refresh_pager() -> void:
	var total := state.building.cars.size()
	var pageable := _view.max_scroll() > 0
	_prev_shaft.visible = pageable
	_next_shaft.visible = pageable
	_pager_label.visible = pageable
	if not pageable:
		return
	var first := _view.first_visible_shaft()
	var last := mini(first + _view.visible_shafts(), total)
	_prev_shaft.disabled = first <= 0
	_next_shaft.disabled = first >= _view.max_scroll()
	_pager_label.text = "shafts %d-%d of %d" % [first + 1, last, total]

func _physics_process(delta: float) -> void:
	var ticks := state.clock.take_ticks(delta)
	if ticks > 0:
		state.tick(ticks)
	_view.refresh()

	var shape := Vector2i(state.building.row_count, state.building.cars.size())
	if shape != _last_shape:
		var bought_shaft := shape.y > _last_shape.y
		_view.rebuild()
		if bought_shaft:
			_view.scroll_to_end()   # show the shaft that was just paid for
		_last_shape = shape
		_refresh_pager()
	_panel.refresh()

	_cash_label.text = "$" + NumberFormat.compact(state.economy.cash)
	var rent := 0.0
	for row in range(state.building.row_count):
		rent += state.tenancy.rent_at(row)
	_rate_label.text = "%s/min   combo %.2fx" % [
		NumberFormat.compact(rent), state.economy.combo]
