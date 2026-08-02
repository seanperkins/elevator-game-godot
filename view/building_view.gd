class_name BuildingView
extends Control

## Subscribes to the sim and renders it. Never mutates sim state -- input goes
## back the other way as explicit commands.

const LEFT_GUTTER := 56.0

var _state: GameState
var _row_height: float
var _shaft_width: float
var _columns: Array[ShaftColumn] = []
var _rows: Array[FloorRow] = []

func bind(state: GameState) -> void:
	_state = state
	_measure()
	_build_rows()
	_build_columns()

## Column width is derived from the board CAP, not the current shaft count, so
## buying a shaft never slides the ones already there out from under a thumb.
## (720 - 56) / 8 = 83 units, which is 45.3pt at the 0.546 iPhone scale -- still
## over the 44pt floor, and unlike a hardcoded 84 the eighth column fits.
func _measure() -> void:
	_row_height = size.y / float(maxi(_state.building.row_count, 1))
	_shaft_width = (size.x - LEFT_GUTTER) / float(Building.MAX_SHAFTS)

## How many passenger sprites fit to the right of the columns. At the shaft cap
## this is zero and rows fall back to the crowd count alone -- §8.5's cap is a
## tunable, and a sprite hidden under a column is worse than a number.
func _individual_budget() -> int:
	var occupied := LEFT_GUTTER + float(_state.building.cars.size()) * _shaft_width
	return int(maxf(size.x - occupied - 8.0, 0.0) / FloorRow.SPRITE_PITCH)

func _build_rows() -> void:
	var budget := _individual_budget()
	for i in range(_state.building.row_count):
		var row := FloorRow.new()
		row.position = Vector2(0, float(i) * _row_height)
		row.size = Vector2(size.x, _row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.set_row(i)
		row.set_individual_budget(budget)
		_rows.append(row)

func _build_columns() -> void:
	for i in range(_state.building.cars.size()):
		var col := ShaftColumn.new()
		col.position = Vector2(LEFT_GUTTER + float(i) * _shaft_width, 0)
		col.size = Vector2(_shaft_width - 4.0, size.y)
		add_child(col)
		var index := i
		col.setup(index, _row_height, _state.building.row_count,
			func() -> int: return _state.building.cars[index].current_row())
		col.dispatch_requested.connect(_on_dispatch)
		col.surge_requested.connect(_on_surge)
		_columns.append(col)

## Rows and shafts are purchasable, so the board must be able to rebuild.
func rebuild() -> void:
	for c in _columns:
		c.queue_free()
	for r in _rows:
		r.queue_free()
	_columns.clear()
	_rows.clear()
	_measure()
	_build_rows()
	_build_columns()

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
