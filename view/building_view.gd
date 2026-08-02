class_name BuildingView
extends Control

## Renders the sim and routes input back as explicit commands. Owns no
## coordinate arithmetic: every floor<->y conversion goes through BoardCoords.
##
## The board SCROLLS and its rows are a fixed height, so legibility no longer
## depends on how much has been built. BoardCoords carries the scroll offset,
## which means this view and the columns share one frame again -- there is no
## ghost-band offset to add, because the ghost row now scrolls with the building
## like everything else.
##
## Columns do NOT scroll: they are fixed full-height touch strips, and what moves
## inside them is the car, positioned by the same scrolled transform. That is why
## a column's local y can be handed straight to y_to_floor.

signal floor_purchase_requested()
signal shaft_purchase_requested()
signal relet_requested(floor_index: int)

const SHAFT_AREA_X := FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH   # 240
## Three columns across the 480-unit viewport. Five at a 96-unit pitch drew each
## at 92 units -- 50.2pt -- which cleared the 44pt touch floor but left a car
## 86 units wide, and four seats across that cannot hold a legible two-digit
## floor at the 0.546 iPhone scale. At 160 the column draws at 156 (85pt) and a
## seat is 34, which can. The cost is paging sooner: eight shafts is three pages
## rather than two.
const SHAFT_WIDTH := 160.0
const RELET_SPAN := SHAFT_AREA_X # the vacant-floor tap reaches the whole gutter+strip

## Every row, always. 88 units is 48pt at the 0.546 iPhone scale -- the same
## touch floor every other control uses -- and it no longer shrinks as the
## building grows, because the board scrolls instead of squeezing.
const ROW_HEIGHT := 88.0

var _state: GameState
var _coords: BoardCoords
## Continuous, in units, not whole columns. Panning is smooth and the pager
## still works by stepping it a column at a time.
var _shaft_offset: float = 0.0

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
	# The board scrolls, so rows exist above and below the window. Without this
	# they draw straight over the HUD.
	clip_contents = true
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
	var previous := _coords.scroll_offset if _coords != null else 0.0
	_coords = BoardCoords.fixed(0, _state.building.row_count - 1, ROW_HEIGHT)
	_coords.set_viewport_height(size.y)
	# Buying a floor must not throw away where the player was looking.
	_coords.scroll_to(previous)

	_build_rows()
	if _state.building.row_count < Building.MAX_ROWS:
		_build_ghost_floor()

	_shaft_viewport.position = Vector2(SHAFT_AREA_X, 0.0)
	_shaft_viewport.size = Vector2(size.x - SHAFT_AREA_X, size.y)
	_build_slots()
	_build_columns()
	# The ghost band sits in the sky above the roof, where the full-height
	# columns also reach. It is added last so a tap there buys a floor rather
	# than dispatching a car it happens to overlap.
	if _ghost_row != null:
		move_child(_ghost_row, get_child_count() - 1)
	_reposition_floors()

## Scrolls the board and moves everything that rides on the offset. Called on
## every scroll and every rebuild, so there is one place that knows what moves.
func _reposition_floors() -> void:
	for i in range(_rows.size()):
		_rows[i].position = Vector2(0, _coords.floor_to_y(i))
	if _ghost_row != null:
		_ghost_row.position = Vector2(0,
			_coords.floor_to_y(_coords.top_floor) - ROW_HEIGHT)

func scroll_board_by(delta: float) -> void:
	_coords.scroll_by(delta)
	_reposition_floors()

## One gesture, both axes.
func pan_board_by(delta: Vector2) -> void:
	if not is_zero_approx(delta.x):
		scroll_shafts_by(delta.x)
	if not is_zero_approx(delta.y):
		scroll_board_by(delta.y)

func scroll_shafts_by(delta: float) -> void:
	_shaft_offset = clampf(_shaft_offset + delta, 0.0, _max_shaft_offset())
	_position_columns()

func _max_shaft_offset() -> float:
	return maxf(float(slot_count()) * SHAFT_WIDTH
		- float(visible_shafts()) * SHAFT_WIDTH, 0.0)

func board_scroll_offset() -> float:
	return _coords.scroll_offset

func _build_rows() -> void:
	for i in range(_state.building.row_count):
		var row := FloorRow.new()
		row.position = Vector2(0, _coords.floor_to_y(i))
		row.size = Vector2(size.x, _coords.row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.set_row(i)
		_rows.append(row)

## A full-height empty row above the top floor. A row, not a button, so the next
## floor is always visibly there; at the cap the term simply leaves the divisor.
func _build_ghost_floor() -> void:
	_ghost_row = Control.new()
	_ghost_row.size = Vector2(size.x, ROW_HEIGHT)
	add_child(_ghost_row)

	var bg := ColorRect.new()
	bg.color = Color("141a21")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_row.add_child(bg)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.position = Vector2(FloorRow.LABEL_X, (ROW_HEIGHT - 20.0) * 0.5)
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
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)
		slot.set_meta("bg", bg)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.position = Vector2(6, 8)   # repositioned with the shaft each frame
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)

		slot.set_meta("label", label)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slots.append(slot)
	_position_slots(_state.building.cars.size())

func _position_slots(owned: int) -> void:
	var buyable := owned if owned < Building.MAX_SHAFTS else -1
	for i in range(_slots.size()):
		var index := first_visible_shaft() + i
		var slot := _slots[i]
		slot.position = Vector2(float(index) * SHAFT_WIDTH - _shaft_offset, 0)
		var bg: ColorRect = slot.get_meta("bg")
		bg.position = Vector2(0, _coords.floor_to_y(_coords.top_floor))
		bg.size = Vector2(SHAFT_WIDTH - 4.0, _coords.content_height())
		var label: Label = slot.get_meta("label")
		label.position = Vector2(6, bg.position.y + 8.0)
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
		col.pan_requested.connect(pan_board_by)
		_columns.append(col)
	_shaft_offset = clampf(_shaft_offset, 0.0, _max_shaft_offset())
	_position_columns()

## Paged-out columns are HIDDEN, not merely clipped. Godot's documentation says
## a clipped child receives no input either, but that was never verified on 4.7
## and hiding costs nothing.
func _position_columns() -> void:
	var window := _shaft_viewport.size.x
	for i in range(_columns.size()):
		var x := float(i) * SHAFT_WIDTH - _shaft_offset
		_columns[i].position = Vector2(x, 0)
		# Hidden rather than merely clipped, so a column scrolled out of the
		# window cannot take a tap through the people strip beside it.
		_columns[i].visible = x + SHAFT_WIDTH > 0.0 and x < window
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
	return clampi(int(round(_shaft_offset / SHAFT_WIDTH)), 0, max_scroll())

## The pager steps the same offset a whole column at a time.
func scroll_by(delta: int) -> void:
	scroll_shafts_by(float(delta) * SHAFT_WIDTH)

func scroll_to_end() -> void:
	_shaft_offset = _max_shaft_offset()
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
	if local.x >= RELET_SPAN:
		return
	var floor_index := _coords.y_to_floor(local.y)
	if _state.tenancy.is_vacant(floor_index):
		relet_requested.emit(floor_index)

## Touch emulation delivers one physical tap twice -- see PointerEvents. Reading
## both families here bought two floors, or two shafts, for one thumb.
func _is_tap(event: InputEvent) -> bool:
	return PointerEvents.is_release(event)

func refresh() -> void:
	if _state == null:
		return
	_reposition_floors()
	for i in range(_columns.size()):
		var car: ElevatorCar = _state.building.cars[i]
		_columns[i].set_car_position(car.position_row)
		_columns[i].set_riders(car.riders, car.capacity)
		# The sim owns the door PHASES; this only maps them to a panel width.
		_columns[i].set_doors(0.0 if car.state != ElevatorCar.State.DOORS
			else ShaftColumn.aperture_for(car.door_elapsed_ticks(), car.door_ticks,
				car.door_opening_ticks(), car.door_closing_ticks()))
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
	if _ghost_label != null:
		var row_cost := _state.upgrades.cost_of("row")
		_ghost_label.text = "+ BUILD FLOOR  $%s" % NumberFormat.compact(row_cost)
		_ghost_label.add_theme_color_override("font_color",
			Color("4ade80") if _state.economy.can_afford(row_cost) else Color("4a5563"))
	_position_slots(_state.building.cars.size())
