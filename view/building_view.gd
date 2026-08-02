class_name BuildingView
extends Control

## Renders the sim and routes input back as explicit commands. Owns no
## coordinate arithmetic: every floor<->y conversion goes through BoardCoords.
##
## Frames: BoardCoords is COLUMN-LOCAL (y=0 is the top floor). This view works
## in the BOARD frame, which is offset downward by the ghost band --
## board_y = ghost_height + local_y. A naive use of the local transform here
## draws the top floor inside the ghost band and leaves the bottom band empty.

signal floor_purchase_requested()
signal shaft_purchase_requested()
signal relet_requested(floor_index: int)

const SHAFT_AREA_X := FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH   # 240
const SHAFT_WIDTH := 96.0        # pitch; columns draw at 92 = 50.2pt
const RELET_SPAN := SHAFT_AREA_X # the vacant-floor tap reaches the whole gutter+strip

var _state: GameState
var _coords: BoardCoords
var _ghost_height: float = 0.0
var _scroll_index: int = 0

var _shaft_viewport: Control
var _ghost_row: Control
var _ghost_label: Label
var _columns: Array[ShaftColumn] = []
var _slots: Array[Control] = []
var _rows: Array[FloorRow] = []

func coords() -> BoardCoords:
	return _coords

func bind(state: GameState) -> void:
	_state = state
	_shaft_viewport = Control.new()
	_shaft_viewport.clip_contents = true
	add_child(_shaft_viewport)
	_build_all()

func rebuild() -> void:
	for c in _shaft_viewport.get_children():
		c.queue_free()
	for r in _rows:
		r.queue_free()
	if _ghost_row != null:
		_ghost_row.queue_free()
		_ghost_row = null
		_ghost_label = null
	_columns.clear()
	_slots.clear()
	_rows.clear()
	_build_all()
	# The viewport must stay on top of the rows it was created before.
	move_child(_shaft_viewport, get_child_count() - 1)

func _build_all() -> void:
	var floors := _state.building.row_count
	var ghost := 1 if floors < Building.MAX_ROWS else 0
	var h := size.y / float(floors + ghost)
	_ghost_height = h * float(ghost)
	_coords = BoardCoords.new(floors, h)

	_build_rows()
	if ghost == 1:
		_build_ghost_floor()

	# The viewport spans the FLOORS only. That frees the ghost band for its own
	# tap and keeps Gesture's cancel edge off the lobby's band.
	_shaft_viewport.position = Vector2(SHAFT_AREA_X, _ghost_height)
	_shaft_viewport.size = Vector2(size.x - SHAFT_AREA_X, size.y - _ghost_height)
	_build_slots()
	_build_columns()

func _build_rows() -> void:
	for i in range(_state.building.row_count):
		var row := FloorRow.new()
		row.position = Vector2(0, _ghost_height + _coords.floor_to_y(i))
		row.size = Vector2(size.x, _coords.row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.set_row(i)
		_rows.append(row)

## A full-height empty row above the top floor. A row, not a button, so the next
## floor is always visibly there; at the cap the term simply leaves the divisor.
func _build_ghost_floor() -> void:
	_ghost_row = Control.new()
	_ghost_row.position = Vector2.ZERO
	_ghost_row.size = Vector2(size.x, _ghost_height)
	add_child(_ghost_row)

	var bg := ColorRect.new()
	bg.color = Color("141a21")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_row.add_child(bg)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.position = Vector2(FloorRow.LABEL_X, (_ghost_height - 20.0) * 0.5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_row.add_child(label)
	_ghost_label = label

	_ghost_row.gui_input.connect(_on_ghost_input)

func _on_ghost_input(event: InputEvent) -> void:
	if _is_tap(event):
		floor_purchase_requested.emit()

## All five visible positions draw a placeholder so the early board reads as
## room to grow. Only the TRAILING one -- index `owned` -- is priced and takes
## the tap; the rest are inert and visually flatter.
func _build_slots() -> void:
	for i in range(visible_shafts()):
		var slot := Control.new()
		slot.size = Vector2(SHAFT_WIDTH - 4.0, _shaft_viewport.size.y)
		_shaft_viewport.add_child(slot)

		var bg := ColorRect.new()
		bg.color = Color("151b23")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.position = Vector2(6, 8)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)

		slot.set_meta("label", label)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slots.append(slot)
	_position_slots(_state.building.cars.size())

func _position_slots(owned: int) -> void:
	var buyable := owned if owned < Building.MAX_SHAFTS else -1
	for i in range(_slots.size()):
		var index := _scroll_index + i
		var slot := _slots[i]
		slot.position = Vector2(float(i) * SHAFT_WIDTH, 0)
		var label: Label = slot.get_meta("label")
		if index == buyable:
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			label.text = "+ SHAFT\n$%s" % NumberFormat.compact(
				_state.upgrades.cost_of("shaft"))
			label.add_theme_color_override("font_color",
				Color("4ade80") if _state.economy.can_afford(
					_state.upgrades.cost_of("shaft")) else Color("4a5563"))
			if not slot.gui_input.is_connected(_on_slot_input):
				slot.gui_input.connect(_on_slot_input)
		else:
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = ""
			if slot.gui_input.is_connected(_on_slot_input):
				slot.gui_input.disconnect(_on_slot_input)

func _on_slot_input(event: InputEvent) -> void:
	if _is_tap(event):
		shaft_purchase_requested.emit()

func _build_columns() -> void:
	for i in range(_state.building.cars.size()):
		var col := ShaftColumn.new()
		col.size = Vector2(SHAFT_WIDTH - 4.0, _shaft_viewport.size.y)
		_shaft_viewport.add_child(col)
		var index := i
		col.setup(index, _coords,
			func() -> int: return _state.building.cars[index].current_row())
		col.dispatch_requested.connect(_on_dispatch)
		col.surge_requested.connect(_on_surge)
		_columns.append(col)
	_scroll_index = clampi(_scroll_index, 0, max_scroll())
	_position_columns()

## Paged-out columns are HIDDEN, not merely clipped. Godot's documentation says
## a clipped child receives no input either, but that was never verified on 4.7
## and hiding costs nothing.
func _position_columns() -> void:
	var last := _scroll_index + visible_shafts()
	for i in range(_columns.size()):
		_columns[i].position = Vector2(float(i - _scroll_index) * SHAFT_WIDTH, 0)
		_columns[i].visible = i >= _scroll_index and i < last
	_position_slots(_state.building.cars.size())

func visible_shafts() -> int:
	return maxi(int((size.x - SHAFT_AREA_X) / SHAFT_WIDTH), 1)

## Counts the trailing ghost slot, so the eighth shaft is reachable. Without it,
## five owned shafts fill all five visible positions and shafts 6-8 are dead.
func slot_count() -> int:
	return mini(_state.building.cars.size() + 1, Building.MAX_SHAFTS)

func max_scroll() -> int:
	return maxi(slot_count() - visible_shafts(), 0)

func first_visible_shaft() -> int:
	return _scroll_index

func scroll_by(delta: int) -> void:
	_scroll_index = clampi(_scroll_index + delta, 0, max_scroll())
	_position_columns()

func scroll_to_end() -> void:
	_scroll_index = max_scroll()
	_position_columns()

func _on_dispatch(shaft_index: int, floor_index: int) -> void:
	_state.dispatch(shaft_index, floor_index)

func _on_surge(_shaft_index: int) -> void:
	# Surge is Milestone 3+; the verb is wired so the input model is complete.
	pass

## A vacant floor's whole gutter-plus-strip span is the re-lease target. The
## 26-unit gutter alone is ~16pt tall at the cap, far under the touch floor, and
## the confirm (ui/relet_confirm.gd) exists for the same reason.
func _gui_input(event: InputEvent) -> void:
	if not _is_tap(event):
		return
	var local: Vector2 = event.position
	if local.x >= RELET_SPAN or local.y < _ghost_height:
		return
	var floor_index := _coords.y_to_floor(local.y - _ghost_height)
	if _state.tenancy.is_vacant(floor_index):
		relet_requested.emit(floor_index)

func _is_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not event.pressed
	if event is InputEventMouseButton:
		return not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false

func refresh() -> void:
	if _state == null:
		return
	for i in range(_columns.size()):
		var car: ElevatorCar = _state.building.cars[i]
		_columns[i].set_car_position(car.position_row)
		_columns[i].set_riders(car.riders, car.capacity)
	for i in range(_rows.size()):
		var waiting := _state.building.waiting_at(i)
		var vacant := _state.tenancy.is_vacant(i)
		var cost := _state.tenancy.relet_cost(i)
		var price := "FREE" if cost <= 0.0 else "$" + NumberFormat.compact(cost)
		# Tenant first: set_waiting reads the vacancy to pick its sprite cap.
		_rows[i].set_tenant(
			_state.tenancy.satisfaction_at(i), vacant,
			_state.tenancy.is_moving_out(i),
			_state.tenancy.move_out_ticks_left(i), price)
		_rows[i].set_waiting(waiting)
		_rows[i].set_crowd_colour(_worst_patience(waiting))
	if _ghost_label != null:
		var row_cost := _state.upgrades.cost_of("row")
		_ghost_label.text = "+ BUILD FLOOR  $%s" % NumberFormat.compact(row_cost)
		_ghost_label.add_theme_color_override("font_color",
			Color("4ade80") if _state.economy.can_afford(row_cost) else Color("4a5563"))
	_position_slots(_state.building.cars.size())

func _worst_patience(waiting: Array) -> float:
	var worst := 1.0
	for p in waiting:
		worst = minf(worst, p.patience_fraction())
	return worst
