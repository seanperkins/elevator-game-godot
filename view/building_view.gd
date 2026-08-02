class_name BuildingView
extends Control

## Subscribes to the sim and renders it. Never mutates sim state -- input goes
## back the other way as explicit commands.

const SHAFT_WIDTH := 84.0        # >= 44pt at the 0.546 iPhone 15 scale
const LEFT_GUTTER := 56.0

var _state: GameState
var _row_height: float
var _columns: Array[ShaftColumn] = []
var _rows: Array[FloorRow] = []

func bind(state: GameState) -> void:
	_state = state
	_row_height = size.y / float(maxi(state.building.row_count, 1))
	_build_rows()
	_build_columns()

func _build_rows() -> void:
	for i in range(_state.building.row_count):
		var row := FloorRow.new()
		row.position = Vector2(0, float(i) * _row_height)
		row.size = Vector2(size.x, _row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.set_row(i)
		_rows.append(row)

func _build_columns() -> void:
	for i in range(_state.building.cars.size()):
		var col := ShaftColumn.new()
		col.position = Vector2(LEFT_GUTTER + float(i) * SHAFT_WIDTH, 0)
		col.size = Vector2(SHAFT_WIDTH - 4.0, size.y)
		add_child(col)
		var index := i
		col.setup(index, _row_height, _state.building.row_count,
			func() -> int: return _state.building.cars[index].current_row())
		col.dispatch_requested.connect(_on_dispatch)
		col.surge_requested.connect(_on_surge)
		_columns.append(col)

func _on_dispatch(shaft_index: int, row: int) -> void:
	_state.dispatch(shaft_index, row)

func _on_surge(_shaft_index: int) -> void:
	# Surge is Milestone 3+; the verb is wired now so the input model is
	# complete and testable on device.
	pass

func refresh() -> void:
	if _state == null:
		return
	for i in range(_columns.size()):
		_columns[i].set_car_position(_state.building.cars[i].position_row)
	for i in range(_rows.size()):
		_rows[i].set_waiting(_state.building.waiting_at(i))
		_rows[i].set_tenant(
			_state.tenancy.satisfaction_at(i),
			_state.tenancy.is_vacant(i),
			_state.tenancy.is_moving_out(i),
			_state.tenancy.move_out_ticks_left(i))
