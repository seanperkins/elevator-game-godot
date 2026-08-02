class_name BuildingView
extends Control

## Subscribes to the sim and renders it. Never mutates sim state -- input goes
## back the other way as explicit commands.
##
## The shaft columns live in a clipped viewport that pages sideways rather than
## being squeezed to fit. Fitting all eight on screen at once cost either the
## 44pt touch guarantee or the entire people strip; paging costs neither, and
## dispatch stops being a per-shaft chore once automation lands.

const SHAFT_AREA_X := FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH
const SHAFT_WIDTH := 96.0        # 52.4pt at the 0.546 iPhone 15 scale

var _state: GameState
var _row_height: float
var _scroll_index: int = 0
var _shaft_viewport: Control
var _columns: Array[ShaftColumn] = []
var _rows: Array[FloorRow] = []

func bind(state: GameState) -> void:
	_state = state
	_row_height = size.y / float(maxi(state.building.row_count, 1))
	_build_rows()

	_shaft_viewport = Control.new()
	_shaft_viewport.position = Vector2(SHAFT_AREA_X, 0)
	_shaft_viewport.size = Vector2(size.x - SHAFT_AREA_X, size.y)
	_shaft_viewport.clip_contents = true
	add_child(_shaft_viewport)

	_build_columns()

## Rows and shafts are purchasable, so the board must be able to rebuild.
func rebuild() -> void:
	for c in _shaft_viewport.get_children():
		c.queue_free()          # columns and their empty slots alike
	for r in _rows:
		r.queue_free()
	_columns.clear()
	_rows.clear()
	_row_height = size.y / float(maxi(_state.building.row_count, 1))
	_build_rows()
	# The viewport must stay on top of the rows it was created after.
	move_child(_shaft_viewport, get_child_count() - 1)
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

## Empty slots behind the columns. With one shaft the viewport is otherwise
## five columns of nothing, and the early game is where most play time is --
## an unbuilt slot reads as room to grow, a void reads as a broken layout.
func _build_slots() -> void:
	for i in range(visible_shafts()):
		var slot := ColorRect.new()
		slot.color = Color("151b23")
		slot.position = Vector2(float(i) * SHAFT_WIDTH, 0)
		slot.size = Vector2(SHAFT_WIDTH - 4.0, size.y)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shaft_viewport.add_child(slot)

func _build_columns() -> void:
	_build_slots()
	for i in range(_state.building.cars.size()):
		var col := ShaftColumn.new()
		col.size = Vector2(SHAFT_WIDTH - 4.0, size.y)
		_shaft_viewport.add_child(col)
		var index := i
		col.setup(index, _row_height, _state.building.row_count,
			func() -> int: return _state.building.cars[index].current_row())
		col.dispatch_requested.connect(_on_dispatch)
		col.surge_requested.connect(_on_surge)
		_columns.append(col)
	_scroll_index = clampi(_scroll_index, 0, max_scroll())
	_position_columns()

## Paged-out columns are HIDDEN, not merely clipped. clip_contents stops the
## drawing but not the hit-testing, and a column scrolled off the left sits
## under the people strip -- a tap there would dispatch a shaft the player
## cannot see.
func _position_columns() -> void:
	var last_visible := _scroll_index + visible_shafts()
	for i in range(_columns.size()):
		_columns[i].position = Vector2(float(i - _scroll_index) * SHAFT_WIDTH, 0)
		_columns[i].visible = i >= _scroll_index and i < last_visible

## How many whole columns the viewport can show at once.
func visible_shafts() -> int:
	return maxi(int(_shaft_viewport.size.x / SHAFT_WIDTH), 1)

func max_scroll() -> int:
	return maxi(_state.building.cars.size() - visible_shafts(), 0)

func first_visible_shaft() -> int:
	return _scroll_index

func scroll_by(delta: int) -> void:
	_scroll_index = clampi(_scroll_index + delta, 0, max_scroll())
	_position_columns()

## Called when a shaft is bought, so the thing just paid for is on screen.
func scroll_to_end() -> void:
	_scroll_index = max_scroll()
	_position_columns()

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
