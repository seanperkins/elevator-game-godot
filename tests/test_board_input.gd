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
## offsets this: the board scrolls, so the ghost floor rides the same transform as
## every floor and there is one frame again.
func floor_centre_y(f: int) -> float:
	return root.HUD_HEIGHT + view.coords().band_centre_y(f)

## The "+ BUILD FLOOR" band sits one floor above the top floor and scrolls with it.
func ghost_centre_y() -> float:
	return root.HUD_HEIGHT + view.coords().floor_to_y(view.coords().top_floor) \
		- BuildingView.FLOOR_HEIGHT * 0.5

## Screen x, so it carries the exterior. SHAFT_AREA_X is measured from the
## BUILDING's left wall, and the building no longer starts at the screen edge.
func column_x(slot: int) -> float:
	return BuildingView.EXTERIOR_LEFT + BuildingView.SHAFT_AREA_X \
		+ float(slot) * BuildingView.SHAFT_WIDTH + 40.0

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

## Raises the running state's floor cap through the Meta, then builds to n
## floors.
##
## A fresh run caps at 10 floors, so the tests that need a taller-than-screen
## board have to buy the `height` levels first. Those tests are about the SCROLL
## TRANSFORM; their twenty floors are incidental, which is why this is a fixture
## rather than a rewrite of what they assert.
##
## It grants height on the state the scene ALREADY built rather than
## constructing a replacement, because the scene reads its state in _ready.
## Buying through meta.buy() rather than poking _spent keeps the helper honest:
## if the ladder's costs move, this goes red rather than quietly diverging from
## what a player can reach.
func build_to(n: int) -> void:
	var meta: Meta = root.state.meta
	meta.blueprints = 1000
	while meta.height_cap() < n and not meta.is_maxed("height"):
		assert_true(meta.buy("height", root.state.upgrades), "height level")
	root.state.upgrades.set_max_level("floor",
		meta.height_cap() - GameState.BASE_FLOORS)
	root.state.economy.accrue(1e9)
	while root.state.building.floor_count < n:
		assert_true(root.state.buy("floor"),
			"floor %d" % root.state.building.floor_count)
	await wait_physics_frames(2)

# --- the harness must actually be touching the board -----------------------

func test_the_board_under_test_is_the_board_that_ships() -> void:
	# Every other test in this file is vacuous if the geometry is wrong: a miss
	# and a no-op look identical from the sim's side.
	assert_eq(root.size, BOARD_SIZE, "720x1280, not GUT's container")
	assert_eq(view.visible_shafts(), 2, "two columns on a 230-unit pitch")
	assert_almost_eq(view.coords().floor_height, BuildingView.FLOOR_HEIGHT, 0.01,
		"floors are a fixed height now, not squeezed to fit")
	var col: ShaftColumn = view._columns[0]
	assert_true(col.get_global_rect().has_point(
		Vector2(column_x(0), floor_centre_y(1))),
		"the coordinates this file dispatches at are inside the column")

# --- the mirrored-board check ---------------------------------------------

func test_a_drag_pans_the_board_and_dispatches_nothing() -> void:
	# The verb swap: looking around is not commanding. A drag that used to send
	# a car now moves the window.
	await build_to(20)                    # taller than the screen, so it can scroll
	await wait_physics_frames(2)
	var target: int = root.state.building.cars[0].target_floor
	var before: float = view.board_scroll_offset()
	# Floor 12, not 6: unscrolled, a twenty-floor building puts floor 6's centre
	# just past the bottom of the board, so the press would land on nothing.
	await do_drag(column_x(0), floor_centre_y(12), floor_centre_y(12) - 250.0)
	assert_ne(view.board_scroll_offset(), before, "the board moved")
	assert_eq(root.state.building.cars[0].target_floor, target,
		"and the car did not")

func test_the_board_cannot_be_panned_off_either_end() -> void:
	await build_to(20)
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
		assert_eq(root.state.building.cars[0].target_floor, target,
			"tap on floor %d's band" % target)

func test_a_tap_ignores_the_cars_current_floor() -> void:
	root.state.building.cars[0].position_floor = 5.0
	await do_tap(column_x(0), floor_centre_y(2))
	assert_eq(root.state.building.cars[0].target_floor, 2,
		"the floor touched, not the floor the car was parked on")

func test_the_car_renders_at_the_floor_it_is_on() -> void:
	# The car and the label must agree; they are the two surfaces that mirror
	# together.
	root.state.building.cars[0].position_floor = 0.0
	view.refresh()
	var car_y: float = view._columns[0]._car_rect.position.y
	var lobby_y: float = view.coords().floor_to_y(0)
	assert_almost_eq(car_y, lobby_y + 2.0, 0.01,
		"the car at floor 0 draws in the lobby's band")

func test_a_tap_after_scrolling_still_hits_the_floor_it_looks_like() -> void:
	# THE mirrored-board check, now with an offset in it. A board that is wrong
	# by a scroll offset is self-consistent on screen and catastrophic in play.
	await build_to(20)
	await wait_physics_frames(2)
	# 760, and it has moved twice: once when FLOOR_HEIGHT went 88 -> 120, once
	# when HUD_HEIGHT went 96 -> 132 and took 36 units off the board. The three
	# taps below must all land ON the board, so the number is bounded at both
	# ends -- floor 4 at 1100 must clear the viewport's bottom and floor 12 at
	# 140 must stay below its top.
	view.scroll_board_by(760.0)
	await wait_physics_frames(2)
	for target in [4, 9, 12]:
		await do_tap(column_x(0), floor_centre_y(target))
		assert_eq(root.state.building.cars[0].target_floor, target,
			"tap on floor %d after scrolling" % target)

# --- purchases -------------------------------------------------------------

func test_a_tap_in_the_ghost_band_buys_a_floor() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.floor_count
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1,
		"the ghost band is tappable at x=400, where the columns used to be")

func test_a_tap_in_the_ghost_band_does_not_dispatch() -> void:
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.cars[0].target_floor
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.cars[0].target_floor, before,
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

func test_only_the_slot_at_index_owned_takes_a_purchase_tap() -> void:
	# The old test tapped a "non-trailing placeholder", which cannot exist:
	# slot_count is min(owned + 1, MAX_SHAFTS), so the only placeholder is the
	# trailing buyable one. It passed by tapping past the last slot -- empty
	# space -- and inverted the moment two columns filled the viewport.
	var owned: int = root.state.building.cars.size()
	assert_eq(view.slot_count(), mini(owned + 1, Building.MAX_SHAFTS),
		"one placeholder beyond what is owned, capped")
	var before: int = owned
	await do_tap(column_x(0), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before,
		"slot 0 is a built shaft, not a purchase target")

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
		targets.append(c.target_floor)
	await do_tap(120.0, floor_centre_y(1))
	for i in range(root.state.building.cars.size()):
		assert_eq(root.state.building.cars[i].target_floor, targets[i],
			"shaft %d must not move" % i)

func test_the_leftmost_visible_column_commands_its_own_shaft() -> void:
	await buy_shafts(6)
	var first := view.first_visible_shaft()
	assert_gt(first, 0, "the strip must actually be paged for this to mean anything")
	await do_tap(column_x(0), floor_centre_y(2))
	assert_eq(root.state.building.cars[first].target_floor, 2)
	assert_ne(root.state.building.cars[0].target_floor, 2,
		"shaft 0 is off screen and must not have moved")

# --- the hall column: select, pan, and the ghost keeps its band -----------

func vacate(floor_index: int) -> void:
	while root.state.tenancy.satisfaction_at(floor_index) > Tenancy.MOVE_OUT_THRESHOLD:
		root.state.tenancy.note_expiry(floor_index)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		root.state.tenancy.accrue_for_tick()
	view.refresh()

func test_a_tap_on_the_hall_selects_the_floor_it_looks_like_after_scrolling() -> void:
	# THE mirrored-board check for the hall: a board wrong by a scroll offset is
	# self-consistent on screen and catastrophic in play.
	await build_to(20)
	await wait_physics_frames(2)
	var target := 12
	view.pan_board_by(Vector2(0, 300))
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	await do_tap(100.0, floor_centre_y(target))
	assert_eq(root.last_selected_floor, target)

func test_a_drag_on_the_hall_pans_and_does_not_select() -> void:
	await build_to(20)
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	var before: float = view.board_scroll_offset()
	await do_drag(100.0, 400.0, 250.0)
	assert_eq(root.last_selected_floor, -1, "a pan is not a selection")
	assert_ne(view.board_scroll_offset(), before, "the board moved")

func test_a_tap_on_the_ghost_band_buys_a_floor_and_opens_no_panel() -> void:
	root.last_selected_floor = -1
	root.state.economy.accrue(1e6)
	var before: int = root.state.building.floor_count
	await do_tap(100.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1, "the ghost buys a floor")
	assert_eq(root.last_selected_floor, -1,
		"a tap above the roof is a purchase, not the top floor's panel")

func test_the_ghost_still_wins_after_a_rebuild() -> void:
	# rebuild() moves the shaft viewport last, so "the ghost is the last child"
	# holds only on the first build; the ghost must still beat the hall column.
	root.state.economy.accrue(1e6)
	view.rebuild()
	await wait_physics_frames(2)
	root.last_selected_floor = -1
	var before: int = root.state.building.floor_count
	await do_tap(100.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1)
	assert_eq(root.last_selected_floor, -1)

func test_a_tap_at_exactly_the_shaft_boundary_reaches_the_shaft() -> void:
	# Rewritten from test_a_tap_past_the_strip_reaches_the_column_not_the_confirm.
	await do_tap(BuildingView.EXTERIOR_LEFT + BuildingView.SHAFT_AREA_X,
		floor_centre_y(1))
	assert_eq(root.last_selected_floor, -1,
		"the first pixel past the strip belongs to the shaft, not the hall")
	assert_eq(root.state.building.cars[0].target_floor, 1,
		"and it reached the shaft, which dispatches on a tap")

# --- the floor panel --------------------------------------------------------

func test_the_lease_picker_is_hidden_while_the_floor_is_tenanted() -> void:
	root.panel.show_floor(root.state, 3)
	assert_false(root.panel.picker_visible(), "you choose who moves in, not out")

func test_the_lease_picker_appears_when_the_floor_is_vacant() -> void:
	root.state.tenancy.restore_floor(3, 1.0, true, 0)
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
	root.state.tenancy.restore_floor(3, 1.0, true, 0)
	root.panel.show_floor(root.state, 3)
	assert_true(root.panel.is_locked("law_firm"), "law firm needs class 3")
	assert_false(root.panel.is_locked("apartments"))

# --- the hall call: direction now, destination only once aboard -----------

func fit(id: String) -> void:
	# test_auto_dispatch.gd has its own fit() against that suite's `gs`; this
	# file drives the real scene and reaches state through root.state. The
	# accrue is load-bearing: a fresh GameState holds $0, so buy() would fail
	# and the arrow would stay hidden for the wrong reason entirely.
	root.state.economy.accrue(1e12)
	assert_true(root.state.buy(id), "fitted %s" % id)

func test_a_waiting_passenger_hides_its_direction_until_the_upgrade() -> void:
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	var sprite: PersonSprite = view._floors[2]._sprites[0]
	assert_true(sprite.visible, "the chip is still drawn -- someone IS waiting")
	assert_eq(sprite.label_text(), FloorRow.CALL_UNKNOWN,
		"which way they are going is not readable until it is bought")

func test_buying_call_direction_reveals_the_arrow() -> void:
	fit("call_direction")
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	assert_eq(view._floors[2]._sprites[0].label_text(), FloorRow.CALL_UP)

func test_a_waiting_passenger_shows_its_call_direction_not_its_floor() -> void:
	# A hall call button is UP or DOWN. Where they are actually going is not
	# known to the operator until they board and press a car button, which is
	# the information asymmetry the whole dispatch puzzle rests on.
	fit("call_direction")
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	var sprite: PersonSprite = view._floors[2]._sprites[0]
	assert_true(sprite.visible, "the passenger is drawn")
	assert_eq(sprite.label_text(), FloorRow.CALL_UP, "floor 2 to floor 5 is a call up")
	assert_false(sprite.label_text().contains("5"),
		"the destination must NOT be readable from the hall")

func test_a_downward_call_shows_a_downward_arrow() -> void:
	fit("call_direction")
	root.state.building.enqueue(Passenger.new(4, 1, 900, 4.0, 4))
	view.refresh()
	assert_eq(view._floors[4]._sprites[0].label_text(), FloorRow.CALL_DOWN)

func test_waiting_passengers_show_their_own_directions() -> void:
	fit("call_direction")
	for dest in [5, 0, 4]:
		root.state.building.enqueue(Passenger.new(2, dest, 900, 4.0, 2))
	view.refresh()
	var shown := []
	for i in range(3):
		shown.append(view._floors[2]._sprites[i].label_text())
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
		PackedStringArray(["12", "7"]), "two digits fit a standing rider's badge")

func test_the_count_returns_when_the_row_is_too_short_for_seats() -> void:
	# Below CarRack's ONE_RANK_MIN no rank of figures fits, the picture is gone,
	# and the number is all there is -- but the pips keep drawing.
	var col: ShaftColumn = view._columns[0]
	col._car_rect.size.y = 18.0
	col.set_riders([Passenger.new(0, 5, 900, 4.0, 0)], 4)
	assert_eq(col.free_slots_shown(), 3,
		"the picture is gone but occupancy is not -- pips draw in every band "
		+ "(one of four is lit)")
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
	assert_lt(text.length(), 20, "the line stays inside the 220-unit car")

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

func test_the_pips_count_the_seats_and_light_for_riders() -> void:
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.seats_taken(), 2, "two lit")
	assert_eq(col.free_slots_shown(), 2, "two hollow of a four-seat car")

func test_capacity_is_legible_above_eight_where_the_rack_gave_up() -> void:
	# The seat rack fell back to a text line at capacity 9, so "Bigger Car"
	# bought something invisible. The pip strip does not.
	root.state.building.cars[0].capacity = 12
	view.refresh()
	assert_eq(view._columns[0].free_slots_shown(), 12,
		"all twelve pips, where the rack drew none")

func test_riders_stand_in_ranks_and_still_say_where_they_are_going() -> void:
	board_riders([12, 7])
	assert_eq(view._columns[0].rider_destinations(),
		PackedStringArray(["12", "7"]), "two digits on a standing figure")


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
	var before: int = root.state.building.floor_count
	await thumb_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1,
		"one thumb, one floor -- touch emulation delivers the tap twice")

func test_one_thumb_tap_buys_exactly_one_shaft() -> void:
	root.state.economy.accrue(1e9)
	var before: int = root.state.building.cars.size()
	await thumb_tap(column_x(1), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before + 1,
		"one thumb, one shaft")

func test_a_thumb_tap_on_a_column_still_dispatches() -> void:
	await thumb_tap(column_x(0), floor_centre_y(3))
	assert_eq(root.state.building.cars[0].target_floor, 3,
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
	assert_true(root.state.buy("floor"))
	assert_true(root.state.buy("shaft"))
	var floors: int = root.state.building.floor_count
	var shafts: int = root.state.building.cars.size()
	var cash: float = root.state.economy.cash
	root.save_now()

	var reloaded := SaveStore.load_state()
	assert_not_null(reloaded, "a save was written")
	assert_eq(reloaded.building.floor_count, floors)
	assert_eq(reloaded.building.cars.size(), shafts)
	assert_almost_eq(reloaded.economy.cash, cash, 1e-6)

func test_an_invalid_state_shows_an_error_screen_and_does_not_start_the_sim() -> void:
	# A malformed shipped tenants.json must be a named error, not a blank board
	# with a console message a player cannot see -- which reads as a hang.
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var bad := ROOT.instantiate()
	bad.catalog_path_override = "res://data/does_not_exist.json"
	bad.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bad.position = Vector2.ZERO
	bad.size = BOARD_SIZE
	layer.add_child(bad)
	await wait_physics_frames(2)
	assert_true(bad.error_screen_visible(), "the boot path names the offence")
	assert_false(bad.sim_running(), "and refuses to run the sim against it")
	assert_string_contains(bad.error_screen_text(), "does_not_exist.json",
		"the file is the offence, so it is on the screen")
	assert_string_contains(bad.error_screen_text(), "tenant catalog",
		"and the screen says what kind of file it was")

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
	var before: int = root.state.building.cars[0].target_floor
	press_at(column_x(0), floor_centre_y(3))
	await wait_physics_frames(2)
	drag_to(column_x(0) - 250.0, floor_centre_y(3))
	await wait_physics_frames(2)
	release_at(column_x(0) - 250.0, floor_centre_y(3))
	await wait_physics_frames(2)
	assert_eq(root.state.building.cars[0].target_floor, before,
		"looking sideways is not commanding either")

# --- the way into the tree, and the balance ---------------------------------

func test_the_prestige_panel_shows_the_blueprint_balance() -> void:
	# It used to sit in the management readout, beside three service numbers
	# measured over a rolling 60-second window -- so a lifetime currency read as
	# a fourth one on the same clock. It belongs where it is spent.
	root.state.meta.blueprints = 7
	root._prestige.refresh()
	assert_string_contains(root._prestige._balance_label.text, "7",
		"the balance is on the screen that spends it")

func test_the_balance_shows_even_before_this_run_is_worth_anything() -> void:
	root.state.meta.blueprints = 3
	root.state.economy.lifetime_earnings = 0.0
	root._prestige.refresh()
	assert_string_contains(root._prestige._balance_label.text, "3",
		"what you can spend does not depend on what this run has earned")

func test_the_readout_states_the_window_its_numbers_cover() -> void:
	# "13 riders/min" with no timescale could as easily have been the whole run.
	var found := false
	for n in root._management.find_children("*", "Label", true, false):
		if (n as Label).text.contains("60 seconds"):
			found = true
	assert_true(found, "the rolling window is stated on screen")

func test_management_opens_the_prestige_panel() -> void:
	assert_false(root._prestige.visible, "closed to begin with")
	root._management.prestige_requested.emit()
	await wait_physics_frames(1)
	assert_true(root._prestige.visible, "and the heading opens it")

# --- the ghost band at the purchasable cap ----------------------------------

func test_at_the_cap_the_ghost_band_says_so_and_the_panel_opens() -> void:
	# A weaker version -- "a tap neither buys a floor nor errors" -- is
	# vacuously true today with no code at all, and would pass with the whole
	# change deleted.
	await build_to(10)
	assert_eq(root.state.building.floor_count, 10, "at the cap")
	view.refresh()
	assert_string_contains(view._ghost_label.text, "REBUILD",
		"the band names what to do instead")
	# At 120-unit rows the cap building (10 x 120 = 1200 units) no longer fits
	# the 1184-unit board, so the ghost band -- one row above the roof -- sits
	# off-screen and cannot be tapped. The cap's path to the prestige panel is
	# the management view; this pins it from the cap state.
	root._management.prestige_requested.emit()
	await wait_physics_frames(1)
	assert_true(root._prestige.visible, "and the panel opened")

func test_below_the_cap_the_ghost_band_still_buys_a_floor() -> void:
	root.state.economy.accrue(1e9)
	var before: int = root.state.building.floor_count
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1, "still the primary verb")
	assert_false(root._prestige.visible, "and no panel")

func test_the_ghost_band_survives_at_the_cap_so_the_pan_strip_does() -> void:
	# Line 97 gates CONSTRUCTION on the structural cap, and _on_ghost_input is
	# also the pan handler. Deleting the band at the purchasable cap would kill
	# the 88-unit pan strip on precisely the tallest buildings.
	await build_to(10)
	view.refresh()
	assert_not_null(view._ghost_floor, "the band is still there")

# --- the demolish, driven through the real scene ----------------------------

## before_each caches `view = root._view`, so any test crossing _rebuild_views()
## must re-read it or assert against a freed node.
func demolish_now() -> void:
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._confirm_button.pressed.emit()
	await wait_physics_frames(2)
	view = root._view

func test_a_tap_on_rebuild_alone_changes_nothing() -> void:
	# The single assertion the whole Confirm/Cancel argument exists to buy.
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	var floors: int = root.state.building.floor_count
	var bp: int = root.state.meta.blueprints
	root._prestige._rebuild_button.pressed.emit()
	await wait_physics_frames(1)
	assert_eq(root.state.building.floor_count, floors, "the building is still there")
	assert_eq(root.state.meta.blueprints, bp, "and nothing was credited")
	assert_true(root._prestige.is_armed(), "the confirm row is showing")
	assert_true(root._prestige._confirm_button.visible, "with a labelled control")
	assert_false(root._prestige._rebuild_button.visible, "in place of REBUILD")

func test_cancel_disarms_without_demolishing() -> void:
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	var floors: int = root.state.building.floor_count
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._cancel_button.pressed.emit()
	await wait_physics_frames(1)
	assert_false(root._prestige.is_armed(), "disarmed")
	assert_eq(root.state.building.floor_count, floors, "and the run survived")

func test_a_demolish_replaces_the_run() -> void:
	await build_to(9)
	var before: GameState = root.state
	before.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	# Computed from the state rather than hardcoded: build_to deliberately
	# inflates both the balance and the earnings to reach nine floors, so a
	# literal here would be asserting the fixture rather than the conversion.
	var expected: int = before.meta.blueprints \
		+ Prestige.yield_for(before.economy.lifetime_earnings)
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._confirm_button.pressed.emit()
	await wait_physics_frames(2)
	view = root._view
	assert_ne(root.state, before, "a new state entirely")
	assert_eq(root.state.building.floor_count, GameState.BASE_FLOORS,
		"a fresh building, nine floors shorter")
	assert_eq(root.state.meta.blueprints, expected, "credited exactly the yield")
	assert_eq(root.state.meta.runs_completed, 1, "and the run was counted")

func test_a_demolish_leaves_exactly_one_of_each_view() -> void:
	# bind() add_childs unconditionally, so calling it twice stacks a whole UI.
	await demolish_now()
	var boards := 0
	var managements := 0
	for child in root.get_children():
		if child is BuildingView:
			boards += 1
		if child is ManagementView:
			managements += 1
	assert_eq(boards, 1, "one board")
	assert_eq(managements, 1, "one management view")

func test_a_tap_in_the_ghost_band_after_a_demolish_buys_exactly_one_floor() -> void:
	# A duplicated BuildingView buys two -- the same class of bug
	# test_one_thumb_tap_buys_exactly_one_floor already guards. This is also
	# what exercises the move_child sibling-order restoration.
	await demolish_now()
	root.state.economy.accrue(1e9)
	var before: int = root.state.building.floor_count
	await thumb_tap(100.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1, "exactly one")

func test_the_board_is_showing_after_a_demolish() -> void:
	await demolish_now()
	assert_true(root._view.visible, "the board")
	assert_false(root._management.visible, "not management")
	assert_eq(root._view_button.text, "MANAGE",
		"the button lives outside the rebuilt range and is reset by hand")

func test_the_hud_buttons_are_not_duplicated_by_a_demolish() -> void:
	await demolish_now()
	var buttons := 0
	for child in root.get_children():
		if child is Button:
			buttons += 1
	assert_eq(buttons, 2, "MANAGE and DEV, as _ready built them")

func test_manage_is_still_tappable_after_a_demolish() -> void:
	# The sibling-order hypothesis, asserted rather than assumed: a rebuild
	# appends the panels LAST, and their full-rect MOUSE_FILTER_STOP scrims
	# would then win input against MANAGE for the rest of the session.
	await demolish_now()
	# FloorPanel is a bottom SHEET: the sim runs behind it and the HUD stays
	# reachable, so MANAGE must be a LATER sibling than its full-rect scrim.
	assert_gt(root.get_children().find(root._view_button),
		root.get_children().find(root.panel),
		"MANAGE is a later sibling than the floor sheet's scrim")
	# And the consequence, through real hit-testing rather than pressed.emit(),
	# which bypasses it.
	root.panel.show_floor(root.state, 1)
	await wait_physics_frames(1)
	assert_true(root.panel.visible, "a sheet is open over the board")
	await do_tap(612.0, 48.0)
	assert_true(root._management.visible, "MANAGE is still reachable through it")

func test_the_prestige_panel_covers_the_hud_it_overlays() -> void:
	# The opposite answer to the test above, and the bug that shipped: the
	# prestige panel is a full-screen OVERLAY, not a sheet. Left among the views
	# it draws underneath the pager and MANAGE, which then sit on top of the
	# tech tree -- and the board bleeds through wherever the panel is not.
	await demolish_now()
	var kids := root.get_children()
	assert_gt(kids.find(root._prestige), kids.find(root._view_button),
		"the overlay is above MANAGE")
	assert_gt(kids.find(root._prestige), kids.find(root._pager_label),
		"and above the shaft readout")
	assert_gt(kids.find(root._prestige), kids.find(root._dev_button),
		"and above DEV")

func test_the_prestige_panel_insets_itself_from_the_hardware() -> void:
	# It is the one surface that covers the HUD band, so it cannot rely on the
	# board's inset. Without this the yield line sits under the Dynamic Island.
	root._prestige.set_insets(Vector4(5.0, 60.0, 5.0, 30.0))
	root._prestige.open(root.state)
	await wait_physics_frames(1)
	var r: Rect2 = root._prestige._scroll.get_global_rect()
	assert_almost_eq(r.position.y, 60.0 + PrestigePanel.EDGE_MARGIN, 0.5,
		"clear of the top inset")
	assert_almost_eq(r.position.x, 5.0 + PrestigePanel.EDGE_MARGIN, 0.5,
		"and the left one")

func test_a_demolish_that_cannot_be_saved_changes_nothing() -> void:
	# The failure is INDUCED, not stubbed: SaveStore.save is static and
	# game_root calls it by class name, so a GUT double is a different script
	# and cannot intercept that call site. A DIRECTORY at user://save.json makes
	# the commit-point rename fail through save()'s own code path.
	var dir := DirAccess.open("user://")
	SaveStore.clear()
	dir.make_dir(SaveStore.PATH)
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	var before: GameState = root.state
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._confirm_button.pressed.emit()
	await wait_physics_frames(2)
	assert_eq(root.state, before, "the old run is still authoritative")
	assert_eq(root.state.meta.blueprints, 0, "and nothing was credited")
	var payload := SaveCodec.encode(root.state)
	assert_eq((payload["meta"] as Dictionary)["blueprints"], 0,
		"an autosave would carry the uncredited balance")
	# The fixture LEAKS: clear() tested file_exists(PATH), which is false for a
	# directory, so without dir_exists it would survive before_each and become
	# the fixture for every later test in this file.
	SaveStore.clear()
	assert_false(dir.dir_exists(SaveStore.PATH), "cleaned up by clear()")

# --- the developer panel ----------------------------------------------------

func cash_centre() -> Vector2:
	var r: Rect2 = root._cash_label.get_global_rect()
	return r.position + r.size * 0.5

func tap_cash(times: int) -> void:
	var c := cash_centre()
	for i in range(times):
		await do_tap(c.x, c.y)

func test_the_dev_button_is_hidden_until_it_is_found() -> void:
	assert_false(root.state.meta.dev_unlocked, "locked on a fresh save")
	assert_false(root._dev_button.visible, "and the button is not there")

func test_six_taps_reveal_nothing_and_the_seventh_reveals_dev() -> void:
	await tap_cash(6)
	assert_false(root._dev_button.visible, "six is not seven")
	await tap_cash(1)
	assert_true(root.state.meta.dev_unlocked, "unlocked")
	assert_true(root._dev_button.visible, "and DEV is on the HUD")

func test_taps_outside_the_window_do_not_accumulate() -> void:
	# The flag persists forever once set, so idle taps spread across a session
	# must not arm it -- there would be no way back but wiping the save.
	await tap_cash(4)
	root._dev_last_tap -= root.DEV_TAP_WINDOW + 1.0
	await tap_cash(4)
	assert_false(root.state.meta.dev_unlocked, "the count restarted")

func test_the_unlock_survives_a_reload() -> void:
	await tap_cash(7)
	assert_true(root.state.meta.dev_unlocked, "unlocked")
	var after := SaveCodec.decode(SaveCodec.encode(root.state))
	assert_not_null(after, "decodes")
	assert_true(after.meta.dev_unlocked, "and it rode along in the meta block")

func test_dev_cash_does_not_touch_the_prestige_yield() -> void:
	# THE test for this feature. Economy.accrue() raises lifetime_earnings, which
	# is the field yield_for consumes, so routing dev money through it would mint
	# Blueprints on every use. This goes red if the two money rows are ever
	# "simplified" into one.
	var before := Prestige.yield_for(root.state.economy.lifetime_earnings)
	root._on_dev_cash(10000.0)
	assert_almost_eq(root.state.economy.cash, 10000.0, 1.0, "the cash arrived")
	assert_eq(Prestige.yield_for(root.state.economy.lifetime_earnings), before,
		"and the yield did not move")

func test_dev_earnings_is_the_one_row_that_moves_the_yield() -> void:
	root._on_dev_earnings(10000.0)
	assert_almost_eq(root.state.economy.cash, 10000.0, 1.0, "cash")
	assert_gt(Prestige.yield_for(root.state.economy.lifetime_earnings), 0,
		"and this one is the prestige tester")

func test_dev_blueprints_are_clamped_like_the_demolish_clamps() -> void:
	root.state.meta.blueprints = Meta.MAX_BLUEPRINTS
	root._on_dev_blueprints(5)
	assert_eq(root.state.meta.blueprints, Meta.MAX_BLUEPRINTS,
		"the in-memory and on-disk bounds are one statement")

func test_fitting_upgrades_never_builds_the_building() -> void:
	# grant_level deliberately never calls _apply, so granting `floor` would
	# claim floors had been bought while the building still had six -- and the
	# next autosave makes that desync durable.
	var floors: int = root.state.building.floor_count
	var shafts: int = root.state.building.cars.size()
	root._on_dev_unlock(2)
	assert_eq(root.state.building.floor_count, floors, "no floors appeared")
	assert_eq(root.state.building.cars.size(), shafts, "no shafts appeared")
	assert_eq(root.state.upgrades.level_of("floor"), 0, "and `floor` was skipped")
	assert_eq(root.state.upgrades.level_of("shaft"), 0, "as was `shaft`")
	assert_eq(root.state.upgrades.level_of("speed"), 2, "but speed was fitted")
	assert_almost_eq(root.state.building.cars[0].floors_per_tick,
		root.state.upgrades.effect_value("speed", 2), 1e-9, "and the cars synced")

func test_fitting_upgrades_costs_nothing() -> void:
	root.state.economy.cash = 0.0
	root._on_dev_unlock(1)
	assert_eq(root.state.economy.cash, 0.0, "granted, never charged")

# NOTE: the test that used to live here measured a single _physics_process(1.0)
# and asserted at_4x == at_1x * 4. That is the HITCH case -- a one-second frame
# -- where both speeds are clamped to MAX_TICKS_PER_FRAME. It passed only
# because the implementation multiplied the already-clamped count, so it pinned
# the clamp-defeating behaviour AS the contract. Replaced by the pair below:
# one asserts the hitch stays clamped, the other measures 4x across real 60fps
# frames, which is the only way the multiplier is observable at all.

func test_reset_save_starts_over_and_clears_the_file() -> void:
	await build_to(9)
	root.save_now()
	assert_true(SaveStore.has_save(), "there is a save to clear")
	root._on_dev_reset()
	await wait_physics_frames(2)
	view = root._view
	assert_eq(root.state.building.floor_count, GameState.BASE_FLOORS, "a fresh building")
	assert_false(SaveStore.has_save(), "and the file is gone")

func test_the_dev_panel_is_the_topmost_child_while_open() -> void:
	await tap_cash(7)
	root._dev.open(root.state)
	await wait_physics_frames(1)
	assert_true(root._dev.visible, "open")
	var kids := root.get_children()
	assert_eq(kids.find(root._dev), kids.size() - 1,
		"nothing draws through it, HUD included")

func test_the_shaft_pager_buttons_are_gone_but_the_readout_stays() -> void:
	# Sideways dragging replaced them; test_a_sideways_drag_pans_across_the_shafts
	# covers that half. This is the half that says they are not still there.
	for child in root.get_children():
		if child is Button:
			assert_ne((child as Button).text, "<", "no back pager")
			assert_ne((child as Button).text, ">", "no forward pager")
	assert_not_null(root._pager_label,
		"the readout stays -- it is the only cue that shafts exist off-screen")

func test_the_overlays_are_stacked_correctly_on_the_very_first_boot() -> void:
	# Not after a demolish -- on the boot a player actually starts from.
	# _ready builds the views BEFORE the HUD, so the restack inside
	# _rebuild_views runs while _view_button is still null and skips it. Without
	# a second call at the end of _ready, MANAGE draws over the prestige tree
	# until the first rebuild.
	var kids := root.get_children()
	assert_gt(kids.find(root._prestige), kids.find(root._view_button),
		"the prestige overlay is above MANAGE from the start")
	assert_gt(kids.find(root._dev), kids.find(root._view_button),
		"and so is the dev overlay")
	assert_gt(kids.find(root._view_button), kids.find(root.panel),
		"while MANAGE stays above the floor SHEET")

# --- the overlays must be escapable ----------------------------------------

func button_centre(b: Button) -> Vector2:
	var r: Rect2 = b.get_global_rect()
	return r.position + r.size * 0.5

func test_the_prestige_panel_can_be_closed_by_a_real_tap() -> void:
	# The scrim cannot do this job: bind() adds scrim, THEN an opaque full-rect
	# bg, THEN the scroll -- so the scrim is buried under two later siblings and
	# its gui_input never fires. A full-screen panel has no visible "outside" to
	# tap anyway, so it needs an explicit control.
	root._prestige.open(root.state)
	await wait_physics_frames(1)
	assert_true(root._prestige.visible, "open")
	var c := button_centre(root._prestige._close_button)
	await do_tap(c.x, c.y)
	assert_false(root._prestige.visible, "and a real tap closes it")

func test_the_dev_panel_can_be_closed_by_a_real_tap() -> void:
	await tap_cash(7)
	root._dev.open(root.state)
	await wait_physics_frames(1)
	assert_true(root._dev.visible, "open")
	var c := button_centre(root._dev._close_button)
	await do_tap(c.x, c.y)
	assert_false(root._dev.visible, "and a real tap closes it")

func test_closing_the_prestige_panel_disarms_it() -> void:
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	assert_true(root._prestige.is_armed(), "armed")
	var c := button_centre(root._prestige._close_button)
	await do_tap(c.x, c.y)
	assert_false(root._prestige.is_armed(),
		"leaving must not leave a live Confirm waiting for the next visit")

func test_a_dev_reset_does_not_immediately_rewrite_the_save() -> void:
	# _since_save is not reset by a plain state swap, so if the autosave timer
	# was already past AUTOSAVE_SECONDS the very next frame writes the fresh
	# state back out -- "Reset save" that leaves a save behind.
	root.save_now()
	assert_true(SaveStore.has_save(), "a save to clear")
	root._since_save = root.AUTOSAVE_SECONDS + 1.0
	root._on_dev_reset()
	await wait_physics_frames(2)
	assert_false(SaveStore.has_save(),
		"the autosave timer must not fire straight after a reset")

func test_a_throwaway_board_cannot_delete_a_real_save() -> void:
	# game_root's own words: "A debug board is a throwaway: it neither loads a
	# save nor overwrites one, so taking a screenshot cannot cost somebody their
	# building." _saving_enabled gates save_now(), but _on_dev_reset called
	# SaveStore.clear() unconditionally -- and clear() takes BACKUP_PATH too, so
	# there is nothing to recover from. Seven taps arm DEV in memory even on a
	# board that was constructed specifically not to be able to touch the save.
	root.save_now()
	assert_true(SaveStore.has_save(), "a real save exists")
	root._saving_enabled = false
	root._on_dev_reset()
	await wait_physics_frames(1)
	assert_true(SaveStore.has_save(),
		"a session that may not WRITE a save must not DELETE one either")

func test_a_hitch_is_still_clamped_at_speed() -> void:
	# THE point of SimClock.MAX_TICKS_PER_FRAME: "a hitch cannot spiral".
	# Multiplying the already-CLAMPED count defeats it -- the clamp grants 8 and
	# the multiplier turns that into 32, so the frame after a hitch does four
	# times the work the guard exists to bound.
	root._on_dev_speed(4)
	var before: int = root.state.clock.ticks_executed
	root._physics_process(1.0)          # a one-second hitch
	var ran: int = root.state.clock.ticks_executed - before
	assert_true(ran <= SimClock.MAX_TICKS_PER_FRAME,
		"a hitch frame ran %d ticks against a clamp of %d"
			% [ran, SimClock.MAX_TICKS_PER_FRAME])

func test_four_times_speed_really_is_four_times_over_real_frames() -> void:
	# At 60fps the sim wants 20/60 = 0.333 ticks per frame, so a single frame
	# grants 0 or 1 and the accumulator carries the remainder. The multiplier is
	# only observable across many frames -- a one-frame measurement says nothing.
	var frame := 1.0 / 60.0
	root._on_dev_speed(1)
	var a: int = root.state.clock.ticks_executed
	for i in range(60):
		root._physics_process(frame)
	var at_1x: int = root.state.clock.ticks_executed - a
	root._on_dev_speed(4)
	var b: int = root.state.clock.ticks_executed
	for i in range(60):
		root._physics_process(frame)
	var at_4x: int = root.state.clock.ticks_executed - b
	assert_almost_eq(float(at_4x), float(at_1x) * 4.0, 2.0,
		"one real second: %d ticks at 1x, %d at 4x" % [at_1x, at_4x])

func test_reset_needs_a_confirm_because_it_destroys_more_than_rebuild_does() -> void:
	# Reset wipes the save, the BACKUP and the whole Meta -- Blueprints, nodes,
	# run count. The prestige REBUILD destroys strictly less and is confirmed.
	await tap_cash(7)
	root._dev.open(root.state)
	root.save_now()
	var bp: int = root.state.meta.blueprints
	root._dev._reset_button.pressed.emit()
	await wait_physics_frames(1)
	assert_true(root._dev.is_reset_armed(), "armed, not fired")
	assert_true(SaveStore.has_save(), "and nothing deleted yet")
	assert_eq(root.state.meta.blueprints, bp, "nor the tree touched")
	root._dev._reset_cancel.pressed.emit()
	await wait_physics_frames(1)
	assert_false(root._dev.is_reset_armed(), "Cancel disarms")
	assert_true(SaveStore.has_save(), "and the save is still there")

func test_leaving_the_dev_panel_disarms_the_reset() -> void:
	await tap_cash(7)
	root._dev.open(root.state)
	root._dev._reset_button.pressed.emit()
	assert_true(root._dev.is_reset_armed(), "armed")
	root._dev.close()
	assert_false(root._dev.is_reset_armed(),
		"a live Delete must not be waiting on the next visit")

func test_the_dev_button_does_not_overlap_the_shaft_readout() -> void:
	# These used OPPOSITE inset conventions -- the label at 328 + _safe.x, DEV
	# derived from _view_button's (size.x - 208 - _safe.z). At the 16-unit
	# minimum SafeArea floors to, that overlapped by 32 units on a real phone
	# while sitting exactly ADJACENT at the zero insets a headless test sees, so
	# no rect-intersection assertion could ever have caught it. Assert the
	# relative anchoring instead, which cannot drift with the insets.
	var label_right: float = root._pager_label.position.x + root._pager_label.size.x
	assert_almost_eq(root._dev_button.position.x - label_right, 8.0, 0.01,
		"the readout is anchored 8 units left of DEV, whatever the insets are")


# --- the doors must not escape their own car ------------------------------

func test_the_doors_carry_no_z_index() -> void:
	# z_index is NOT local: a CanvasItem at z 1 draws above EVERY z-0 node in
	# the canvas layer, so doors at z 1 rendered over the open FloorPanel as a
	# car-shaped sage smear. Ordering among siblings is what was wanted.
	var col: ShaftColumn = view._columns[0]
	assert_eq(col._door_left.z_index, 0, "a door must not outrank the whole layer")
	assert_eq(col._door_right.z_index, 0)

func test_the_doors_stay_above_the_riders_by_tree_order() -> void:
	# The property the z_index was protecting: riders are pooled lazily, so they
	# are added AFTER the doors and would otherwise draw over them.
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	var kids := col._car_rect.get_children()
	assert_true(kids[kids.size() - 1] == col._door_right
		or kids[kids.size() - 1] == col._door_left, "a door is drawn last")
	var first_door := mini(kids.find(col._door_left), kids.find(col._door_right))
	for chip in col._chips:
		assert_lt(kids.find(chip), first_door, "every rider is behind the doors")


# --- the move-out alarm -----------------------------------------------------
#
# The gutter tenant bar is gone; these pin what replaced it. Deleting the bar
# without them would have quietly dropped a CANCELLABLE countdown -- delivering
# to that floor clears it -- leaving the player no reason to dispatch there.

func test_the_floor_number_turns_to_the_alarm_while_its_tenant_is_leaving() -> void:
	var f := 1
	root.state.tenancy.lease(f, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f]._label.get_theme_color("font_color"), Palette.INK_FLOOR,
		"a settled floor is ordinary ink")
	# restore_floor is the public seam for putting a floor into a given state;
	# driving satisfaction down to the threshold takes a minute of sim time.
	root.state.tenancy.restore_floor(f, 0.0, false, Tenancy.MOVE_OUT_TICKS, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f]._label.get_theme_color("font_color"), Palette.ALARM,
		"a floor whose tenant is leaving is the alarm colour")

func test_the_alarm_clears_when_the_tenant_is_talked_round() -> void:
	# The whole point of keeping this on the board: it is an alarm you can act on.
	var f := 1
	root.state.tenancy.restore_floor(f, 0.0, false, Tenancy.MOVE_OUT_TICKS, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f]._label.get_theme_color("font_color"), Palette.ALARM)
	# Enough deliveries to climb back over the move-out threshold.
	for i in 40:
		root.state.tenancy.note_delivery(f)
	assert_false(root.state.tenancy.is_moving_out(f), "deliveries cancel the move-out")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f]._label.get_theme_color("font_color"), Palette.INK_FLOOR,
		"and the board stops shouting about it")

func test_the_panel_carries_the_countdown_the_board_no_longer_draws() -> void:
	# The board keeps the alarm; the remaining seconds moved here, because the bar
	# that used to DRAIN over the countdown is gone.
	var f := 1
	root.state.tenancy.restore_floor(f, 0.0, false, Tenancy.MOVE_OUT_TICKS, "apartments")
	root.panel.show_floor(root.state, f)
	await wait_physics_frames(1)
	assert_string_contains(root.panel._header.text, "LEAVING IN",
		"the panel says the tenant is going")
	assert_string_contains(root.panel._header.text, "60s",
		"MOVE_OUT_TICKS is one simulated minute at 20 Hz")
	root.state.tenancy.restore_floor(f, 1.0, false, 0, "apartments")
	root.panel.show_floor(root.state, f)
	await wait_physics_frames(1)
	assert_false(root.panel._header.text.contains("LEAVING"),
		"and says nothing about it when nobody is leaving")


# --- floor scenery ----------------------------------------------------------

func test_a_tenanted_floor_shows_its_kind_and_a_vacant_one_shows_the_shell() -> void:
	# The board asks for scenery by KIND. A vacant floor has no kind to ask with,
	# so it asks by the VACANT sentinel instead -- an empty id means "no art",
	# which is not the same thing as "the construction shell".
	var f := 1
	root.state.tenancy.lease(f, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f].scenery_id(), "apartments")
	# restore_floor is the only public path back to vacant -- a tenant otherwise
	# leaves through the move-out countdown, which is a minute of sim time.
	root.state.tenancy.restore_floor(f, 1.0, true, 0, "")
	view.refresh()
	await wait_physics_frames(1)
	assert_eq(view._floors[f].scenery_id(), FloorScenery.VACANT,
		"a vacant floor draws the construction shell")

func test_the_scenery_stops_where_the_shafts_begin() -> void:
	# It covers the gutter and the people strip and nothing under a shaft --
	# a shaft is opaque, so any pixel beyond STRIP_RIGHT is never seen.
	root.state.tenancy.lease(1, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	var s: TextureRect = view._floors[1]._scenery
	assert_almost_eq(s.size.x, FloorRow.STRIP_RIGHT, 0.01)
	assert_almost_eq(s.size.y, BuildingView.FLOOR_HEIGHT, 0.01)
	assert_almost_eq(s.position.x, 0.0, 0.01)

func test_the_scenery_is_behind_everything_else_in_the_row() -> void:
	root.state.tenancy.lease(1, "apartments")
	view.refresh()
	await wait_physics_frames(1)
	var row: FloorRow = view._floors[1]
	assert_eq(row.get_children().find(row._scenery), 0,
		"first child, so the people and the numbers draw over it")
