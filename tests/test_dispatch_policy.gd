extends GutTest

## The blocks, tested as blocks. Every rule here is pure arithmetic over floor
## numbers, so the whole dispatch model is pinned without a building or a scene.

const N := 10

func floors(values: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in values:
		out.append(v)
	return out

func every_floor() -> DispatchPolicy:
	return DispatchPolicy.preset_policy(DispatchPolicy.Preset.EVERY_FLOOR)

func calls() -> DispatchPolicy:
	return DispatchPolicy.preset_policy(DispatchPolicy.Preset.ANSWER_CALLS)

# --- where to look ---------------------------------------------------------

func test_every_floor_considers_all_of_them_but_not_where_it_is() -> void:
	var got := every_floor().candidates(3, 5, floors([]), floors([]))
	assert_eq(got, floors([0, 1, 2, 4]), "never travel to where you already are")

func test_every_floor_needs_no_sensors_which_is_why_it_is_wasteful() -> void:
	# Given nothing at all, it still wants to visit everywhere. That is the
	# honest cost of a controller with no call buttons attached.
	assert_eq(every_floor().candidates(0, 4, floors([]), floors([])).size(), 3)
	assert_eq(DispatchPolicy.preset_requires(DispatchPolicy.Preset.EVERY_FLOOR).size(), 0)

func test_hall_calls_only_consider_floors_with_someone_on_them() -> void:
	var got := calls().candidates(0, N, floors([4, 7]), floors([]))
	assert_eq(got, floors([4, 7]))

func test_car_calls_are_where_the_riders_want_off() -> void:
	var got := calls().candidates(0, N, floors([]), floors([2, 9]))
	assert_eq(got, floors([2, 9]))

func test_the_two_call_sources_merge_without_duplicates() -> void:
	var got := calls().candidates(0, N, floors([3, 5]), floors([5, 8]))
	assert_eq(got, floors([3, 5, 8]), "floor 5 is wanted twice and listed once")

func test_calls_outside_the_building_are_ignored() -> void:
	var got := calls().candidates(0, 5, floors([99]), floors([-2]))
	assert_true(got.is_empty(), "a stale call must not send a car off the board")

# --- how to choose ---------------------------------------------------------

func test_sweep_carries_on_the_way_it_was_going() -> void:
	var got := calls().choose(5, N, floors([2, 8]), floors([]), 1)
	assert_eq(got.x, 8, "8 is ahead; 2 is behind, even though it is nearer")
	assert_eq(got.y, 1, "still heading up")

func test_sweep_turns_round_only_when_nothing_is_left_ahead() -> void:
	var got := calls().choose(5, N, floors([2]), floors([]), 1)
	assert_eq(got.x, 2)
	assert_eq(got.y, -1, "reversed")

func test_sweep_takes_the_first_it_meets_not_the_furthest() -> void:
	var got := calls().choose(0, N, floors([3, 6, 9]), floors([]), 1)
	assert_eq(got.x, 3)

func test_nearest_takes_the_closest_in_either_direction() -> void:
	var policy := DispatchPolicy.preset_policy(DispatchPolicy.Preset.NEAREST_CALL)
	var got := policy.choose(5, N, floors([3, 9]), floors([]), 1)
	assert_eq(got.x, 3, "two floors away, against the direction of travel")

func test_nearest_breaks_a_tie_the_way_it_is_already_pointing() -> void:
	# Otherwise a car between two equidistant calls dithers on the spot.
	var policy := DispatchPolicy.preset_policy(DispatchPolicy.Preset.NEAREST_CALL)
	assert_eq(policy.choose(5, N, floors([3, 7]), floors([]), 1).x, 7)
	assert_eq(policy.choose(5, N, floors([3, 7]), floors([]), -1).x, 3)

func test_the_shipped_sweep_falls_out_of_the_general_rule() -> void:
	# "Every floor" is not special-cased anywhere: it is (EVERY_FLOOR, SWEEP,
	# STAY), and stepping it produces exactly the floor-by-floor walk that
	# shipped. If this fails, the decomposition is lying.
	var policy := every_floor()
	var at := 0
	var dir := 1
	var walked := []
	for i in range(12):
		var got := policy.choose(at, 4, floors([]), floors([]), dir)
		at = got.x
		dir = got.y
		walked.append(at)
	assert_eq(walked, [1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0], "up, down, repeat")

# --- nothing to do ---------------------------------------------------------

func test_with_no_calls_it_stays_put_by_default() -> void:
	assert_eq(calls().choose(6, N, floors([]), floors([]), 1).x, DispatchPolicy.STAY_PUT)

func test_lobby_parking_sends_an_idle_car_home() -> void:
	var policy := DispatchPolicy.preset_policy(DispatchPolicy.Preset.CALLS_THEN_LOBBY)
	assert_eq(policy.choose(6, N, floors([]), floors([]), 1).x, 0)

func test_a_car_already_home_stays_there() -> void:
	var policy := DispatchPolicy.preset_policy(DispatchPolicy.Preset.CALLS_THEN_LOBBY)
	assert_eq(policy.choose(0, N, floors([]), floors([]), 1).x, DispatchPolicy.STAY_PUT,
		"no cycling the doors on the spot")

func test_work_beats_going_home() -> void:
	var policy := DispatchPolicy.preset_policy(DispatchPolicy.Preset.CALLS_THEN_LOBBY)
	assert_eq(policy.choose(6, N, floors([8]), floors([]), 1).x, 8)

# --- when full -------------------------------------------------------------

func test_without_a_load_sensor_a_full_car_still_stops_for_hall_calls() -> void:
	# It cannot tell. It burns a whole dwell opening on people who cannot board.
	var policy := calls()
	assert_false(policy.bypass_when_full)
	assert_eq(policy.choose(0, N, floors([4]), floors([]), 1, true).x, 4)

func test_a_load_sensor_makes_a_full_car_pass_hall_calls() -> void:
	var policy := calls()
	policy.bypass_when_full = true
	assert_eq(policy.choose(0, N, floors([4]), floors([]), 1, true).x,
		DispatchPolicy.STAY_PUT, "nobody could have got on anyway")

func test_a_full_car_still_delivers_the_people_inside_it() -> void:
	# Bypassing hall calls must never strand the riders already aboard.
	var policy := calls()
	policy.bypass_when_full = true
	assert_eq(policy.choose(0, N, floors([4]), floors([7]), 1, true).x, 7)

func test_the_load_sensor_changes_nothing_while_there_is_room() -> void:
	var policy := calls()
	policy.bypass_when_full = true
	assert_eq(policy.choose(0, N, floors([4]), floors([]), 1, false).x, 4)

# --- degenerate ------------------------------------------------------------

func test_a_one_floor_building_never_moves() -> void:
	assert_eq(every_floor().choose(0, 1, floors([0]), floors([0]), 1).x,
		DispatchPolicy.STAY_PUT)

# --- what the hardware buys ------------------------------------------------

func test_calls_need_both_kinds_of_button() -> void:
	var need := DispatchPolicy.preset_requires(DispatchPolicy.Preset.ANSWER_CALLS)
	assert_true(need.has("hall_buttons"), "to know who is waiting")
	assert_true(need.has("car_buttons"), "to know where they are going")

func test_lobby_parking_is_its_own_fitting() -> void:
	var need := DispatchPolicy.preset_requires(DispatchPolicy.Preset.CALLS_THEN_LOBBY)
	assert_true(need.has("lobby_parking"))
