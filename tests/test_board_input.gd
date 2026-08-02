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
