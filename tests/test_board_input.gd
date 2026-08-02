extends GutTest

## Drives the real scene with synthetic input. GUT provides a scene tree, so the
## board can be instantiated, sized, and touched exactly as a thumb would.
##
## Two things about this environment cost real time to find, and both are why
## the obvious version of this harness silently does nothing:
##
## 1. game_root.tscn anchors full-rect, so the scene resizes itself to whatever
##    GUT's parent happens to be (2000x2560) BEFORE _ready lays the board out.
##    The anchors are pinned to the top-left and the size set explicitly, so the
##    board under test is the 720x1280 board that ships.
##
## 2. The headless window is 0x0, which makes the root viewport's final
##    transform a 0.05 scale. Input.parse_input_event and push_input(event)
##    both apply its INVERSE, multiplying every coordinate by twenty and
##    landing every tap off the board -- with no error, because a miss is
##    indistinguishable from a tap on nothing. push_input(event, true) treats
##    the position as viewport-local and skips the transform entirely.
##
## 3. GUT's own runner GUI is a CanvasLayer at layer 128, and its TestOutput
##    panel spans x 652 to 1266 -- straight across the right of a 720-wide
##    board, where the fifth shaft slot lives. It takes the tap first. The
##    board goes on a HIGHER canvas layer so it is above GUT's chrome; without
##    this, taps at x >= 643 silently reach nothing.

const ROOT := preload("res://game/game_root.tscn")

const BOARD_SIZE := Vector2(720, 1280)

const GUT_GUI_LAYER := 128

var root: Control
var view: BuildingView

func before_each() -> void:
	var layer := CanvasLayer.new()
	layer.layer = GUT_GUI_LAYER + 1
	add_child_autofree(layer)
	root = ROOT.instantiate()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = BOARD_SIZE
	layer.add_child(root)
	await wait_physics_frames(2)
	view = root._view

func after_each() -> void:
	root = null
	view = null

## Board-frame y of the centre of a floor's band.
func floor_centre_y(f: int) -> float:
	return root.HUD_HEIGHT + view._ghost_height + view.coords().band_centre_y(f)

func column_x(slot: int) -> float:
	return BuildingView.SHAFT_AREA_X + float(slot) * BuildingView.SHAFT_WIDTH + 40.0

## in_local_coords = true: see the header. Without it every coordinate is
## multiplied by twenty and the whole file passes vacuously.
func inject(event: InputEvent) -> void:
	get_viewport().push_input(event, true)

func press_at(x: float, y: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(x, y)
	e.global_position = e.position
	inject(e)

func release_at(x: float, y: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = Vector2(x, y)
	e.global_position = e.position
	inject(e)

func drag_to(x: float, y: float) -> void:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(x, y)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	inject(e)

func do_drag(x: float, from_y: float, to_y: float) -> void:
	press_at(x, from_y)
	await wait_physics_frames(2)
	drag_to(x, to_y)
	await wait_physics_frames(2)
	release_at(x, to_y)
	await wait_physics_frames(2)

func do_tap(x: float, y: float) -> void:
	press_at(x, y)
	await wait_physics_frames(2)
	release_at(x, y)
	await wait_physics_frames(2)

# --- the harness must actually be touching the board -----------------------

func test_the_board_under_test_is_the_board_that_ships() -> void:
	# Every other test in this file is vacuous if the geometry is wrong: a miss
	# and a no-op look identical from the sim's side.
	assert_eq(root.size, BOARD_SIZE, "720x1280, not GUT's container")
	assert_eq(view.visible_shafts(), 5, "five columns on a 96-unit pitch")
	var col: ShaftColumn = view._columns[0]
	assert_true(col.get_global_rect().has_point(
		Vector2(column_x(0), floor_centre_y(1))),
		"the coordinates this file dispatches at are inside the column")

# --- the mirrored-board check ---------------------------------------------

func test_a_drag_onto_a_floors_band_dispatches_to_that_floor() -> void:
	# THE check. A mirrored board is self-consistent across gesture, rail and
	# car, so it passes casual play and every screenshot; only this catches it.
	for target in [5, 2, 0]:
		await do_drag(column_x(0), floor_centre_y(1), floor_centre_y(target))
		assert_eq(root.state.building.cars[0].target_row, target,
			"drag onto floor %d's band" % target)

func test_a_tap_on_a_column_dispatches_to_the_floor_tapped() -> void:
	# A tap is a dispatch of zero drag length. Same bottom-up transform, so this
	# would catch a mirror in the tap path even if the drag path were correct.
	for target in [4, 1, 3]:
		await do_tap(column_x(0), floor_centre_y(target))
		assert_eq(root.state.building.cars[0].target_row, target,
			"tap on floor %d's band" % target)

func test_a_tap_ignores_the_cars_current_floor() -> void:
	root.state.building.cars[0].position_row = 5.0
	await do_tap(column_x(0), floor_centre_y(2))
	assert_eq(root.state.building.cars[0].target_row, 2,
		"the floor touched, not the floor the car was parked on")

func test_the_car_renders_at_the_floor_it_is_on() -> void:
	# The car and the label must agree; they are the two surfaces that mirror
	# together.
	root.state.building.cars[0].position_row = 0.0
	view.refresh()
	var car_y: float = view._columns[0]._car_rect.position.y
	var lobby_y: float = view.coords().floor_to_y(0)
	assert_almost_eq(car_y, lobby_y + 2.0, 0.01,
		"the car at floor 0 draws in the lobby's band")

func test_the_rail_marker_agrees_with_the_selected_floor() -> void:
	press_at(column_x(0), floor_centre_y(1))
	await wait_physics_frames(2)
	drag_to(column_x(0), floor_centre_y(4))
	await wait_physics_frames(2)
	var marker_y: float = view._columns[0]._selector._marker.position.y
	assert_almost_eq(marker_y, view.coords().floor_to_y(4), 0.01)
	release_at(column_x(0), floor_centre_y(4))
	await wait_physics_frames(2)

# --- purchases -------------------------------------------------------------

func test_a_tap_in_the_ghost_band_buys_a_floor() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.row_count
	await do_tap(400.0, root.HUD_HEIGHT + view._ghost_height * 0.5)
	assert_eq(root.state.building.row_count, before + 1,
		"the ghost band is tappable at x=400, where the columns used to be")

func test_a_tap_in_the_ghost_band_does_not_dispatch() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.cars[0].target_row
	await do_tap(400.0, root.HUD_HEIGHT + view._ghost_height * 0.5)
	assert_eq(root.state.building.cars[0].target_row, before,
		"a floor purchase is not a dispatch: the columns stop below the band")

func test_every_shaft_up_to_the_cap_is_reachable() -> void:
	# With five visible slots and no ghost slot, five owned shafts fill every
	# position and shafts 6-8 are unbuyable forever.
	root.state.economy.accrue(1e12)
	for owned in range(1, Building.MAX_SHAFTS):
		var slot_index := owned - view.first_visible_shaft()
		if slot_index >= view.visible_shafts():
			view.scroll_to_end()
			await wait_physics_frames(2)
			slot_index = owned - view.first_visible_shaft()
		assert_between(slot_index, 0, view.visible_shafts() - 1,
			"a buyable slot must be on screen at owned=%d" % owned)
		await do_tap(column_x(slot_index), floor_centre_y(1))
		await wait_physics_frames(2)
		assert_eq(root.state.building.cars.size(), owned + 1,
			"bought shaft %d" % (owned + 1))
	assert_eq(root.state.building.cars.size(), Building.MAX_SHAFTS)

func test_a_tap_on_a_non_trailing_placeholder_does_nothing() -> void:
	root.state.economy.accrue(1e12)
	var before: int = root.state.building.cars.size()
	await do_tap(column_x(view.visible_shafts() - 1), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before,
		"only the trailing slot is buyable")

# --- paging ----------------------------------------------------------------

func buy_shafts(n: int) -> void:
	root.state.economy.accrue(1e12)
	for i in range(n):
		root.state.buy("shaft")
	# _physics_process notices the shape change and rebuilds; wait for it rather
	# than rebuilding by hand, so the columns under test are the shipped ones.
	await wait_physics_frames(2)
	view.scroll_to_end()
	await wait_physics_frames(2)

func test_a_paged_out_column_cannot_be_touched_through_the_people_strip() -> void:
	await buy_shafts(6)
	var targets := []
	for c in root.state.building.cars:
		targets.append(c.target_row)
	await do_drag(120.0, floor_centre_y(4), floor_centre_y(1))
	for i in range(root.state.building.cars.size()):
		assert_eq(root.state.building.cars[i].target_row, targets[i],
			"shaft %d must not move" % i)

func test_the_leftmost_visible_column_commands_its_own_shaft() -> void:
	await buy_shafts(6)
	var first := view.first_visible_shaft()
	assert_gt(first, 0, "the strip must actually be paged for this to mean anything")
	await do_drag(column_x(0), floor_centre_y(4), floor_centre_y(2))
	assert_eq(root.state.building.cars[first].target_row, 2)
	assert_ne(root.state.building.cars[0].target_row, 2,
		"shaft 0 is off screen and must not have moved")

# --- re-lease --------------------------------------------------------------

func vacate(row: int) -> void:
	while root.state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		root.state.tenancy.accrue_for_tick()
	view.refresh()

func test_a_tap_on_a_vacant_floors_gutter_opens_the_confirm() -> void:
	vacate(2)
	await do_tap(100.0, floor_centre_y(2))
	assert_true(root._relet_confirm.visible, "the confirm is shown")
	assert_eq(root._relet_confirm.floor_index, 2)

func test_a_tap_past_the_strip_reaches_the_column_not_the_confirm() -> void:
	vacate(2)
	await do_tap(300.0, floor_centre_y(2))
	assert_false(root._relet_confirm.visible,
		"x=300 is the shaft viewport, not the re-lease span")
	assert_eq(root.state.building.cars[0].target_row, 2,
		"and it reached the column, which now dispatches on a tap")

func test_a_tap_on_a_tenanted_floor_does_nothing() -> void:
	await do_tap(100.0, floor_centre_y(3))
	assert_false(root._relet_confirm.visible)

# --- the hall call: direction now, destination only once aboard -----------

func test_a_waiting_passenger_shows_its_call_direction_not_its_floor() -> void:
	# A hall call button is UP or DOWN. Where they are actually going is not
	# known to the operator until they board and press a car button, which is
	# the information asymmetry the whole dispatch puzzle rests on.
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0))
	view.refresh()
	var sprite: PassengerSprite = view._rows[2]._sprites[0]
	assert_true(sprite.visible, "the passenger is drawn")
	assert_eq(sprite.label_text(), FloorRow.CALL_UP, "floor 2 to floor 5 is a call up")
	assert_false(sprite.label_text().contains("5"),
		"the destination must NOT be readable from the hall")

func test_a_downward_call_shows_a_downward_arrow() -> void:
	root.state.building.enqueue(Passenger.new(4, 1, 900, 4.0))
	view.refresh()
	assert_eq(view._rows[4]._sprites[0].label_text(), FloorRow.CALL_DOWN)

func test_waiting_passengers_show_their_own_directions() -> void:
	for dest in [5, 0, 4]:
		root.state.building.enqueue(Passenger.new(2, dest, 900, 4.0))
	view.refresh()
	var shown := []
	for i in range(3):
		shown.append(view._rows[2]._sprites[i].label_text())
	assert_eq(shown, [FloorRow.CALL_UP, FloorRow.CALL_DOWN, FloorRow.CALL_UP],
		"in queue order, FIFO like boarding")

# --- the car as a set of seats --------------------------------------------

func board_riders(dests: Array) -> void:
	var car: ElevatorCar = root.state.building.cars[0]
	for d in dests:
		car.riders.append(Passenger.new(0, d, 900, 4.0))
	view.refresh()

func test_a_rider_reveals_its_destination_once_aboard() -> void:
	# The payoff of the asymmetry above: boarding is how you learn the floor.
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.rider_destinations(), PackedStringArray(["5", "2"]),
		"the car names the buttons its riders pressed")
	assert_string_contains(col.car_text(), "5")
	assert_string_contains(col.car_text(), "2")

func test_the_floors_are_in_the_header_where_there_is_room_for_type() -> void:
	# Four seats across a 50.2pt column leaves ~11pt each, which cannot hold two
	# legible digits. The header is full column width, so it can.
	board_riders([12, 7])
	assert_string_contains(view._columns[0].car_text(), "12",
		"a two-digit floor has to be readable somewhere")

func test_a_crowded_car_collapses_the_list_rather_than_overflowing() -> void:
	# The line cannot grow past the column, so it lists what fits and counts the
	# rest. Twelve two-digit floors would otherwise run into the next shaft.
	root.state.building.cars[0].capacity = 12
	board_riders([11, 22, 33, 24, 15, 26])
	var text: String = view._columns[0].car_text()
	assert_string_contains(text, "6/12", "the count is never dropped")
	assert_string_contains(text, "+", "and the remainder is counted, not clipped")
	assert_lt(text.length(), 16, "the line stays inside the column")

func test_seats_show_occupancy_without_carrying_text() -> void:
	# Textless seats can be short -- 12 units instead of 20 -- which is what
	# keeps the grid alive to ~30 floors instead of ~17.
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.seats_taken(), 2, "two filled")
	assert_eq(col.free_slots_shown(), 2, "two hollow")
	assert_lt(ShaftColumn.SEAT_SIZE.y, 16.0, "short, because it holds no glyph")

func test_free_seats_are_drawn_so_capacity_is_legible_at_a_glance() -> void:
	var car: ElevatorCar = root.state.building.cars[0]
	assert_eq(car.capacity, 4, "the shipped starting capacity")
	board_riders([5, 2])
	assert_eq(view._columns[0].free_slots_shown(), 2,
		"two aboard of four leaves two visible empty seats")

func test_an_empty_car_is_all_free_seats() -> void:
	view.refresh()
	assert_eq(view._columns[0].free_slots_shown(), 4)
	assert_eq(view._columns[0].rider_destinations().size(), 0)

func test_a_full_car_shows_no_free_seats() -> void:
	board_riders([1, 2, 3, 4])
	assert_eq(view._columns[0].free_slots_shown(), 0, "nothing more fits")
	assert_eq(view._columns[0].rider_destinations().size(), 4)

func test_raising_capacity_adds_visible_seats() -> void:
	root.state.building.cars[0].capacity = 7
	view.refresh()
	assert_eq(view._columns[0].free_slots_shown(), 7,
		"the capacity upgrade is only legible if the seats appear")

func test_the_occupancy_number_sits_at_the_top_of_the_car() -> void:
	board_riders([5])
	var col: ShaftColumn = view._columns[0]
	var car_height: float = col._car_rect.size.y
	assert_lt(col._car_label.position.y, car_height * 0.25,
		"the number reads from the top of the car, not its middle")
	assert_string_contains(col.car_text(), "1/4")

# --- what a real thumb delivers -------------------------------------------

## An iPhone tap arrives TWICE: as a touch, and as the synthetic mouse event
## emulate_mouse_from_touch fabricates from it (device -1). Both reach the same
## Control's _gui_input. These helpers replay that faithfully -- the mouse-only
## helpers above are the desktop path and cannot catch a double-fire.
func touch_event(x: float, y: float, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.device = 0
	e.pressed = pressed
	e.position = Vector2(x, y)
	return e

func emulated_mouse_event(x: float, y: float, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = PointerEvents.EMULATED_DEVICE
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = Vector2(x, y)
	e.global_position = e.position
	return e

func thumb_tap(x: float, y: float) -> void:
	inject(touch_event(x, y, true))
	inject(emulated_mouse_event(x, y, true))
	await wait_physics_frames(2)
	inject(touch_event(x, y, false))
	inject(emulated_mouse_event(x, y, false))
	await wait_physics_frames(2)

func test_one_thumb_tap_buys_exactly_one_floor() -> void:
	root.state.economy.accrue(1e9)
	var before: int = root.state.building.row_count
	await thumb_tap(400.0, root.HUD_HEIGHT + view._ghost_height * 0.5)
	assert_eq(root.state.building.row_count, before + 1,
		"one thumb, one floor -- touch emulation delivers the tap twice")

func test_one_thumb_tap_buys_exactly_one_shaft() -> void:
	root.state.economy.accrue(1e9)
	var before: int = root.state.building.cars.size()
	await thumb_tap(column_x(1), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before + 1,
		"one thumb, one shaft")

func test_a_thumb_tap_on_a_column_still_dispatches() -> void:
	await thumb_tap(column_x(0), floor_centre_y(3))
	assert_eq(root.state.building.cars[0].target_row, 3,
		"dropping the duplicate must not drop the gesture itself")
