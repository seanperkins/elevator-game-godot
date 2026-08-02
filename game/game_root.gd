extends Control

## Owns the sim and pumps it. Physics stays at Godot's default 60 Hz and the
## clock accumulates to 20 Hz -- one tick per callback would run the sim 3x fast.

const START_ROWS := 6
const START_SHAFTS := 1
const START_SEED := 20260802

var state: GameState
var _view: BuildingView
var _cash_label: Label

func _ready() -> void:
	state = GameState.new(START_ROWS, START_SHAFTS, START_SEED)

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 28)
	_cash_label.position = Vector2(16, 8)
	add_child(_cash_label)

	_view = BuildingView.new()
	_view.position = Vector2(0, 56)
	_view.size = Vector2(size.x, size.y - 56)
	add_child(_view)
	_view.bind(state)

func _physics_process(delta: float) -> void:
	var ticks := state.clock.take_ticks(delta)
	if ticks > 0:
		state.tick(ticks)
	_view.refresh()
	_cash_label.text = "$" + NumberFormat.compact(state.economy.cash)
