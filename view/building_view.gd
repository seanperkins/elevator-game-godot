class_name BuildingView
extends Control

## Renders the sim and routes input back as explicit commands. Owns no
## coordinate arithmetic: every floor<->y conversion goes through BoardCoords.
##
## The board SCROLLS and its floors are a fixed height, so legibility no longer
## depends on how much has been built. BoardCoords carries the scroll offset,
## which means this view and the columns share one frame again -- there is no
## ghost-band offset to add, because the ghost floor now scrolls with the building
## like everything else.
##
## Columns do NOT scroll: they are fixed full-height touch strips, and what moves
## inside them is the car, positioned by the same scrolled transform. That is why
## a column's local y can be handed straight to y_to_floor.

signal floor_purchase_requested()
## At the purchasable cap the ghost band stops selling a floor and starts
## offering the only thing that raises it.
signal prestige_requested()
signal shaft_purchase_requested()
## Re-broadcast of the (recreated) HallColumn's floor_selected. hall_column is
## rebuilt whenever the board grows, and a fresh instance carries no
## connections, so the persistent consumer -- GameRoot -- binds to this instead.
signal hall_floor_selected(floor_index: int)

const SHAFT_AREA_X := FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH   # 208
## Two columns across the shaft viewport, on the DEVICE board -- not the canvas.
## SafeArea floors both side insets at CORNER_MARGIN 16, so the board is 688
## wide on a phone and 720 only headless; 230 gives two columns on both, with 20
## units of slack. 240 gives two on the canvas and ONE on the device, which is
## how a one-column board nearly shipped with a green suite.
##
## The column draws at 226 and the car at 220, which is what makes a two-digit
## destination badge 13.1pt at every capacity from 4 to 12 -- see the design
## spec's 4.3. The people strip yields 32 units to pay for it.
const SHAFT_WIDTH := 230.0

## Every floor, always. 120 units is 65.5pt at the 0.546 iPhone scale, and it is
## sized by the CAR rather than by the touch floor: a font-24 line box needs a
## 30-unit badge, so two ranks of riders need 2 + 8 + 52 + 52 = 114, which fits
## a 116-unit car. At 112 the badge falls to 27 and the font to 21.
const FLOOR_HEIGHT := 120.0

var _state: GameState
var _coords: BoardCoords
## Continuous, in units, not whole columns. Panning is smooth and the pager
## still works by stepping it a column at a time.
var _shaft_offset: float = 0.0

var _shaft_viewport: Control
var _ghost_floor: Control
var _ghost_label: Label
var _ghost_gesture: Gesture
var hall_column: HallColumn
var _columns: Array[ShaftColumn] = []
var _slots: Array[Control] = []
var _floors: Array[FloorRow] = []

func coords() -> BoardCoords:
	return _coords

func bind(state: GameState) -> void:
	_state = state
	# The board scrolls, so floors exist above and below the window. Without this
	# they draw straight over the HUD.
	clip_contents = true
	_shaft_viewport = Control.new()
	_shaft_viewport.clip_contents = true
	add_child(_shaft_viewport)
	_build_all()

func rebuild() -> void:
	for c in _shaft_viewport.get_children():
		c.queue_free()
	for r in _floors:
		r.queue_free()
	if _ghost_floor != null:
		_ghost_floor.queue_free()
		_ghost_floor = null
		_ghost_label = null
	if hall_column != null:
		hall_column.queue_free()
		hall_column = null
	_columns.clear()
	_slots.clear()
	_floors.clear()
	_build_all()
	# The viewport must stay on top of everything it was created before.
	move_child(_shaft_viewport, get_child_count() - 1)

func _build_all() -> void:
	var previous := _coords.scroll_offset if _coords != null else 0.0
	_coords = BoardCoords.fixed(0, _state.building.floor_count - 1, FLOOR_HEIGHT)
	_coords.set_viewport_height(size.y)
	# Buying a floor must not throw away where the player was looking.
	_coords.scroll_to(previous)

	_build_floors()
	# The hall column spans the full board height so its local y IS board y.
	# It is added BEFORE the ghost floor, which keeps the ghost's band on top and
	# so keeps the tap above the roof a floor purchase rather than a selection.
	_build_hall_column()
	if _state.building.floor_count < Building.MAX_FLOORS:
		_build_ghost_floor()

	_shaft_viewport.position = Vector2(SHAFT_AREA_X, 0.0)
	_shaft_viewport.size = Vector2(size.x - SHAFT_AREA_X, size.y)
	_build_slots()
	_build_columns()
	# The ghost band sits in the sky above the roof, where the full-height
	# columns also reach. It is added last so a tap there buys a floor rather
	# than dispatching a car it happens to overlap.
	if _ghost_floor != null:
		move_child(_ghost_floor, get_child_count() - 1)
	_reposition_floors()

## Scrolls the board and moves everything that rides on the offset. Called on
## every scroll and every rebuild, so there is one place that knows what moves.
func _reposition_floors() -> void:
	for i in range(_floors.size()):
		_floors[i].position = Vector2(0, _coords.floor_to_y(i))
	if _ghost_floor != null:
		_ghost_floor.position = Vector2(0,
			_coords.floor_to_y(_coords.top_floor) - FLOOR_HEIGHT)

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

func _build_floors() -> void:
	for i in range(_state.building.floor_count):
		var floor_index := FloorRow.new()
		floor_index.position = Vector2(0, _coords.floor_to_y(i))
		floor_index.size = Vector2(size.x, _coords.floor_height)
		floor_index.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(floor_index)
		floor_index.set_floor(i)
		_floors.append(floor_index)

## The hall region's one touch target, spanning x in [0, STRIP_RIGHT). It
## replaces BuildingView._gui_input's relet tap path: TAP selects a floor,
## DRAG pans. Its local y is board y, so a touch goes straight to y_to_floor
## with no offset arithmetic -- the property that kept ShaftColumn correct.
func _build_hall_column() -> void:
	hall_column = HallColumn.new()
	hall_column.position = Vector2.ZERO
	hall_column.size = Vector2(FloorRow.STRIP_RIGHT, size.y)
	hall_column.setup(_coords)
	hall_column.pan_requested.connect(pan_board_by)
	hall_column.floor_selected.connect(_on_hall_floor_selected)
	add_child(hall_column)

func _on_hall_floor_selected(floor_index: int) -> void:
	hall_floor_selected.emit(floor_index)

## A full-height empty floor above the top floor. A floor, not a button, so the next
## floor is always visibly there; at the cap the term simply leaves the divisor.
func _build_ghost_floor() -> void:
	_ghost_floor = Control.new()
	_ghost_floor.size = Vector2(size.x, FLOOR_HEIGHT)
	add_child(_ghost_floor)

	var bg := ColorRect.new()
	bg.color = Palette.GHOST_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_floor.add_child(bg)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.position = Vector2(FloorRow.LABEL_X, (FLOOR_HEIGHT - 20.0) * 0.5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_floor.add_child(label)
	_ghost_label = label

	_ghost_floor.gui_input.connect(_on_ghost_input)
	_ghost_gesture = Gesture.new(_coords)

## The ghost band keeps its TAP -- the floor above the roof buys a floor, not a
## selection, because y_to_floor clamps there. It also gains the hall region's
## PAN: a drag that starts on the ghost translates to scrolling, as it does on
## every column, so a glance down a taller-than-screen building is not blocked
## by the single floor of sky above the roof.
func _on_ghost_input(event: InputEvent) -> void:
	if PointerEvents.is_press(event):
		_ghost_gesture.press(event.position, _coords.top_floor + 1)
	elif PointerEvents.is_drag(event):
		_ghost_gesture.move(event.position)
		if _ghost_gesture.is_panning():
			var delta := _ghost_gesture.take_pan_delta()
			if delta != Vector2.ZERO:
				pan_board_by(delta)
	elif PointerEvents.is_release(event):
		if _ghost_gesture.release() == Gesture.Result.TAP:
			# Giving the tap a destination removes the silent no-op rather than
			# merely labelling it: Upgrades.purchase refuses at is_maxed and
			# game_root discards the result, so at the cap this band was
			# inviting a tap that did nothing at all.
			if _state.upgrades.is_maxed("floor"):
				prestige_requested.emit()
			else:
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
		# GHOST_BG, not SHAFT_BG: this slot is a shaft you have NOT bought, and
		# it sits directly under the ghost floor band, which recedes. Painting
		# it the shaft's own rust made an unbought slot read as a built shaft.
		bg.color = Palette.GHOST_BG
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)
		slot.set_meta("bg", bg)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 16)
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
				Palette.AFFORD if _state.economy.can_afford(
					_state.upgrades.cost_of("shaft")) else Palette.AFFORD_OFF)
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
			func() -> int: return _state.building.cars[index].current_floor())
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
		_columns[i].set_car_position(car.position_floor)
		_columns[i].set_riders(car.riders, car.capacity)
		# The sim owns the door PHASES; this only maps them to a panel width.
		_columns[i].set_doors(0.0 if car.state != ElevatorCar.State.DOORS
			else ShaftColumn.aperture_for(car.door_elapsed_ticks(), car.door_ticks,
				car.door_opening_ticks(), car.door_closing_ticks()))
	for i in range(_floors.size()):
		var waiting := _state.building.waiting_at(i)
		var vacant := _state.tenancy.is_vacant(i)
		_floors[i].set_tenant(
			_state.tenancy.satisfaction_at(i), vacant,
			_state.tenancy.is_moving_out(i),
			_state.tenancy.move_out_ticks_left(i))
		_floors[i].set_waiting(waiting,
			_state.upgrades.is_installed("call_direction"))
	if _ghost_label != null:
		if _state.upgrades.is_maxed("floor"):
			# 21 characters ends near x = 227 at font size 15 from LABEL_X = 38,
			# just inside FloorRow.STRIP_RIGHT (208). A 37-character string
			# would overrun into the shaft slot's own label.
			_ghost_label.text = "CAP REACHED — REBUILD"
			_ghost_label.add_theme_color_override("font_color", Palette.CAP_REACHED)
		else:
			var floor_cost := _state.upgrades.cost_of("floor")
			_ghost_label.text = "+ BUILD FLOOR  $%s" % NumberFormat.compact(floor_cost)
			_ghost_label.add_theme_color_override("font_color",
				Palette.AFFORD if _state.economy.can_afford(floor_cost) \
				else Palette.AFFORD_OFF)
	_position_slots(_state.building.cars.size())
