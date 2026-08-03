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
	# game_root loads a save on start, so a real one left by playing the game
	# would silently become the fixture for every test in this file.
	SaveStore.clear()
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

## Board-frame y of the centre of a floor's band. The ghost band no longer
## offsets this: the board scrolls, so the ghost row rides the same transform as
## every floor and there is one frame again.
func floor_centre_y(f: int) -> float:
	return root.HUD_HEIGHT + view.coords().band_centre_y(f)

## The "+ BUILD FLOOR" band sits one row above the top floor and scrolls with it.
func ghost_centre_y() -> float:
	return root.HUD_HEIGHT + view.coords().floor_to_y(view.coords().top_floor) \
		- BuildingView.ROW_HEIGHT * 0.5

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
	assert_eq(view.visible_shafts(), 3, "three columns on a 160-unit pitch")
	assert_almost_eq(view.coords().row_height, BuildingView.ROW_HEIGHT, 0.01,
		"rows are a fixed height now, not squeezed to fit")
	var col: ShaftColumn = view._columns[0]
	assert_true(col.get_global_rect().has_point(
		Vector2(column_x(0), floor_centre_y(1))),
		"the coordinates this file dispatches at are inside the column")

# --- the mirrored-board check ---------------------------------------------

func test_a_drag_pans_the_board_and_dispatches_nothing() -> void:
	# The verb swap: looking around is not commanding. A drag that used to send
	# a car now moves the window.
	root.state.economy.accrue(1e9)
	for i in range(14):
		root.state.buy("row")           # taller than the screen, so it can scroll
	await wait_physics_frames(2)
	var target: int = root.state.building.cars[0].target_row
	var before: float = view.board_scroll_offset()
	# Floor 12, not 6: unscrolled, a twenty-floor building puts floor 6's centre
	# just past the bottom of the board, so the press would land on nothing.
	await do_drag(column_x(0), floor_centre_y(12), floor_centre_y(12) - 250.0)
	assert_ne(view.board_scroll_offset(), before, "the board moved")
	assert_eq(root.state.building.cars[0].target_row, target,
		"and the car did not")

func test_the_board_cannot_be_panned_off_either_end() -> void:
	root.state.economy.accrue(1e9)
	for i in range(14):
		root.state.buy("row")
	await wait_physics_frames(2)
	await do_drag(column_x(0), floor_centre_y(12), floor_centre_y(12) + 5000.0)
	assert_almost_eq(view.board_scroll_offset(), 0.0, 0.01, "not past the ground")
	await do_drag(column_x(0), floor_centre_y(12), floor_centre_y(12) - 5000.0)
	assert_gt(view.board_scroll_offset(), 0.0, "and it did move the other way")

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

func test_a_tap_after_scrolling_still_hits_the_floor_it_looks_like() -> void:
	# THE mirrored-board check, now with an offset in it. A board that is wrong
	# by a scroll offset is self-consistent on screen and catastrophic in play.
	root.state.economy.accrue(1e9)
	for i in range(14):
		root.state.buy("row")
	await wait_physics_frames(2)
	view.scroll_board_by(300.0)
	await wait_physics_frames(2)
	for target in [4, 9, 12]:
		await do_tap(column_x(0), floor_centre_y(target))
		assert_eq(root.state.building.cars[0].target_row, target,
			"tap on floor %d after scrolling" % target)

# --- purchases -------------------------------------------------------------

func test_a_tap_in_the_ghost_band_buys_a_floor() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.row_count
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.row_count, before + 1,
		"the ghost band is tappable at x=400, where the columns used to be")

func test_a_tap_in_the_ghost_band_does_not_dispatch() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.cars[0].target_row
	await do_tap(400.0, ghost_centre_y())
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
	await do_tap(120.0, floor_centre_y(1))
	for i in range(root.state.building.cars.size()):
		assert_eq(root.state.building.cars[i].target_row, targets[i],
			"shaft %d must not move" % i)

func test_the_leftmost_visible_column_commands_its_own_shaft() -> void:
	await buy_shafts(6)
	var first := view.first_visible_shaft()
	assert_gt(first, 0, "the strip must actually be paged for this to mean anything")
	await do_tap(column_x(0), floor_centre_y(2))
	assert_eq(root.state.building.cars[first].target_row, 2)
	assert_ne(root.state.building.cars[0].target_row, 2,
		"shaft 0 is off screen and must not have moved")

# --- the hall column: select, pan, and the ghost keeps its band -----------

func vacate(row: int) -> void:
	while root.state.tenancy.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		root.state.tenancy.accrue_for_tick()
	view.refresh()

func test_a_tap_on_the_hall_selects_the_floor_it_looks_like_after_scrolling() -> void:
	# THE mirrored-board check for the hall: a board wrong by a scroll offset is
	# self-consistent on screen and catastrophic in play.
	root.state.economy.accrue(1e9)
	for i in range(14):
		root.state.buy("row")
	await wait_physics_frames(2)
	var target := 12
	view.pan_board_by(Vector2(0, 300))
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	await do_tap(100.0, floor_centre_y(target))
	assert_eq(root.last_selected_floor, target)

func test_a_drag_on_the_hall_pans_and_does_not_select() -> void:
	root.state.economy.accrue(1e9)
	for i in range(14):
		root.state.buy("row")
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	var before: float = view.board_scroll_offset()
	await do_drag(100.0, 400.0, 250.0)
	assert_eq(root.last_selected_floor, -1, "a pan is not a selection")
	assert_ne(view.board_scroll_offset(), before, "the board moved")

func test_a_tap_on_the_ghost_band_buys_a_floor_and_opens_no_panel() -> void:
	root.last_selected_floor = -1
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.row_count
	await do_tap(100.0, ghost_centre_y())
	assert_eq(root.state.building.row_count, before + 1, "the ghost buys a floor")
	assert_eq(root.last_selected_floor, -1,
		"a tap above the roof is a purchase, not the top floor's panel")

func test_the_ghost_still_wins_after_a_rebuild() -> void:
	# rebuild() moves the shaft viewport last, so "the ghost is the last child"
	# holds only on the first build; the ghost must still beat the hall column.
	root.state.economy.accrue(1e6)
	view.rebuild()
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	var before: int = root.state.building.row_count
	await do_tap(100.0, ghost_centre_y())
	assert_eq(root.state.building.row_count, before + 1)
	assert_eq(root.last_selected_floor, -1)

func test_a_tap_at_exactly_the_shaft_boundary_reaches_the_shaft() -> void:
	# Rewritten from test_a_tap_past_the_strip_reaches_the_column_not_the_confirm.
	await do_tap(BuildingView.SHAFT_AREA_X, floor_centre_y(1))
	assert_eq(root.last_selected_floor, -1, "x = 240 belongs to the shaft, not the hall")
	assert_eq(root.state.building.cars[0].target_row, 1,
		"and it reached the shaft, which dispatches on a tap")

# --- the floor panel --------------------------------------------------------

func test_the_lease_picker_is_hidden_while_the_floor_is_tenanted() -> void:
	root.panel.show_floor(root.state, 3)
	assert_false(root.panel.picker_visible(), "you choose who moves in, not out")

func test_the_lease_picker_appears_when_the_floor_is_vacant() -> void:
	root.state.tenancy.restore_row(3, 1.0, true, 0)
	root.panel.show_floor(root.state, 3)
	assert_true(root.panel.picker_visible())

func test_a_floor_counting_down_to_move_out_still_counts_as_tenanted() -> void:
	while root.state.tenancy.satisfaction_at(3) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(3)
	assert_true(root.state.tenancy.is_moving_out(3))
	root.panel.show_floor(root.state, 3)
	assert_false(root.panel.picker_visible(),
		"the move-out clock keeps its teeth")

func test_kinds_above_the_floors_class_are_shown_locked() -> void:
	root.state.tenancy.restore_row(3, 1.0, true, 0)
	root.panel.show_floor(root.state, 3)
	assert_true(root.panel.is_locked("law_firm"), "law firm needs class 3")
	assert_false(root.panel.is_locked("apartments"))

# --- the hall call: direction now, destination only once aboard -----------

func test_a_waiting_passenger_shows_its_call_direction_not_its_floor() -> void:
	# A hall call button is UP or DOWN. Where they are actually going is not
	# known to the operator until they board and press a car button, which is
	# the information asymmetry the whole dispatch puzzle rests on.
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	var sprite: PassengerSprite = view._rows[2]._sprites[0]
	assert_true(sprite.visible, "the passenger is drawn")
	assert_eq(sprite.label_text(), FloorRow.CALL_UP, "floor 2 to floor 5 is a call up")
	assert_false(sprite.label_text().contains("5"),
		"the destination must NOT be readable from the hall")

func test_a_downward_call_shows_a_downward_arrow() -> void:
	root.state.building.enqueue(Passenger.new(4, 1, 900, 4.0, 4))
	view.refresh()
	assert_eq(view._rows[4]._sprites[0].label_text(), FloorRow.CALL_DOWN)

func test_waiting_passengers_show_their_own_directions() -> void:
	for dest in [5, 0, 4]:
		root.state.building.enqueue(Passenger.new(2, dest, 900, 4.0, 2))
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
		car.riders.append(Passenger.new(0, d, 900, 4.0, 0))
	view.refresh()

func test_a_rider_reveals_its_destination_once_aboard() -> void:
	# The payoff of the asymmetry above: boarding is how you learn the floor.
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.rider_destinations(), PackedStringArray(["5", "2"]),
		"the same little square, now showing the car button they pressed")

func test_no_occupancy_count_is_printed_while_the_seats_are_drawn() -> void:
	# Four filled squares of four IS the count. Printing "4/4" beside them says
	# it twice and spends the only line of type the car has.
	board_riders([5, 2])
	assert_eq(view._columns[0].car_text(), "",
		"the rack is the count; do not restate it")

func test_seats_carry_the_floor_now_that_the_column_is_wide_enough() -> void:
	board_riders([12, 7])
	assert_eq(view._columns[0].rider_destinations(),
		PackedStringArray(["12", "7"]), "two digits fit on a 34-unit seat")

func test_the_count_returns_when_the_row_is_too_short_for_seats() -> void:
	# At the 40-floor cap a car is 25.6 units tall: no rank of seats fits, the
	# picture is gone, and the number is all there is.
	var col: ShaftColumn = view._columns[0]
	col._car_rect.size.y = 18.0
	col.set_riders([Passenger.new(0, 5, 900, 4.0, 0)], 4)
	assert_eq(col.free_slots_shown(), 0, "no seats drawn")
	assert_string_contains(col.car_text(), "1/4", "so the count comes back")
	assert_string_contains(col.car_text(), "5", "with the floors it can fit")

func test_the_fallback_line_collapses_rather_than_overflowing() -> void:
	var col: ShaftColumn = view._columns[0]
	col._car_rect.size.y = 18.0
	var riders := []
	for d in [11, 22, 33, 24, 15, 26]:
		riders.append(Passenger.new(0, d, 900, 4.0, 0))
	col.set_riders(riders, 12)
	var text: String = col.car_text()
	assert_string_contains(text, "6/12", "the count is never dropped")
	assert_string_contains(text, "+", "and the remainder is counted, not clipped")
	assert_lt(text.length(), 20, "the line stays inside the column")

func test_seats_show_taken_and_free_at_a_glance() -> void:
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.seats_taken(), 2, "two filled")
	assert_eq(col.free_slots_shown(), 2, "two hollow")

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
	await thumb_tap(400.0, ghost_centre_y())
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

# --- the dwell is visible --------------------------------------------------

func test_a_shut_car_has_its_doors_closed_across_the_middle() -> void:
	view.refresh()
	var col: ShaftColumn = view._columns[0]
	assert_almost_eq(col.door_width(), col._car_rect.size.x * 0.5, 0.01,
		"two panels meeting in the middle")

func test_the_doors_part_while_the_car_is_boarding() -> void:
	# The stop is otherwise indistinguishable from standing still.
	var car: ElevatorCar = root.state.building.cars[0]
	car.door_ticks = 20
	car.dispatch_to(0)
	car.step(10)                        # mid-dwell: wide open
	view.refresh()
	assert_almost_eq(view._columns[0].door_width(), 0.0, 0.01, "fully retracted")

func test_the_doors_are_mid_slide_as_they_open() -> void:
	var car: ElevatorCar = root.state.building.cars[0]
	car.door_ticks = 20
	car.dispatch_to(0)
	car.step(2)                         # ~10% in: part way through the slide
	view.refresh()
	var col: ShaftColumn = view._columns[0]
	assert_between(col.door_width(), 0.01, col._car_rect.size.x * 0.5 - 0.01,
		"caught between shut and open, which is what makes the dwell legible")

# --- dispatch policy lives in Management -----------------------------------

func open_management() -> void:
	root._on_toggle_view()
	await wait_physics_frames(2)

func test_a_shaft_cannot_be_automated_before_the_upgrade_is_bought() -> void:
	await open_management()
	root._management._shaft_buttons[0].emit_signal("pressed")
	await wait_physics_frames(2)
	assert_false(root.state.auto.is_enabled(0), "no licence, no sweep")
	assert_true(root._management._shaft_buttons[0].disabled, "and the button says so")

func test_the_toggle_puts_a_shaft_on_auto_once_licensed() -> void:
	root.state.economy.accrue(1e9)
	assert_true(root.state.buy("auto"))
	await open_management()
	assert_false(root._management._shaft_buttons[0].disabled)
	root._management._shaft_buttons[0].emit_signal("pressed")
	await wait_physics_frames(2)
	assert_true(root.state.auto.is_enabled(0))
	assert_string_contains(root._management._shaft_buttons[0].text, "EVERY FLOOR")

func test_the_toggle_turns_it_off_again() -> void:
	root.state.economy.accrue(1e9)
	root.state.buy("auto")
	await open_management()
	root._management._shaft_buttons[0].emit_signal("pressed")
	await wait_physics_frames(2)
	root._management._shaft_buttons[0].emit_signal("pressed")
	await wait_physics_frames(2)
	assert_false(root.state.auto.is_enabled(0))
	assert_string_contains(root._management._shaft_buttons[0].text, "manual")

func test_a_shaft_bought_on_the_board_gets_a_toggle() -> void:
	root.state.economy.accrue(1e12)
	assert_true(root.state.buy("shaft"))
	await open_management()
	assert_gte(root._management._shaft_buttons.size(), 2,
		"the new shaft turns up in the dispatch list")

# --- persistence, end to end -----------------------------------------------

func test_the_building_survives_a_restart() -> void:
	# The whole point: quitting must not cost you what you built.
	root.state.economy.accrue(1e6)
	assert_true(root.state.buy("row"))
	assert_true(root.state.buy("shaft"))
	var floors: int = root.state.building.row_count
	var shafts: int = root.state.building.cars.size()
	var cash: float = root.state.economy.cash
	root.save_now()

	var reloaded := SaveStore.load_state()
	assert_not_null(reloaded, "a save was written")
	assert_eq(reloaded.building.row_count, floors)
	assert_eq(reloaded.building.cars.size(), shafts)
	assert_almost_eq(reloaded.economy.cash, cash, 1e-6)

func test_a_debug_board_never_writes_over_a_save() -> void:
	# --board is for screenshots. Letting it save would mean taking one costs
	# somebody their building.
	SaveStore.clear()
	root.state.economy.accrue(1e6)
	root._saving_enabled = false
	root.save_now()
	assert_false(SaveStore.has_save(), "nothing written")

func test_a_sideways_drag_pans_across_the_shafts() -> void:
	# Eight shafts are wider than the screen just as a tall building is taller
	# than it. Looking around is one gesture in both axes.
	root.state.economy.accrue(1e12)
	for i in range(5):
		root.state.buy("shaft")
	await wait_physics_frames(2)
	view.scroll_shafts_by(-9999.0)          # back to the first shaft
	await wait_physics_frames(2)
	assert_eq(view.first_visible_shaft(), 0)
	await do_drag(column_x(1), floor_centre_y(2), floor_centre_y(2))
	# a purely horizontal drag: same y, different x
	press_at(column_x(1), floor_centre_y(2))
	await wait_physics_frames(2)
	drag_to(column_x(1) - 200.0, floor_centre_y(2))
	await wait_physics_frames(2)
	release_at(column_x(1) - 200.0, floor_centre_y(2))
	await wait_physics_frames(2)
	assert_gt(view.first_visible_shaft(), 0, "the strip moved sideways")

func test_a_sideways_pan_does_not_dispatch() -> void:
	root.state.economy.accrue(1e12)
	for i in range(5):
		root.state.buy("shaft")
	await wait_physics_frames(2)
	var before: int = root.state.building.cars[0].target_row
	press_at(column_x(0), floor_centre_y(3))
	await wait_physics_frames(2)
	drag_to(column_x(0) - 250.0, floor_centre_y(3))
	await wait_physics_frames(2)
	release_at(column_x(0) - 250.0, floor_centre_y(3))
	await wait_physics_frames(2)
	assert_eq(root.state.building.cars[0].target_row, before,
		"looking sideways is not commanding either")
