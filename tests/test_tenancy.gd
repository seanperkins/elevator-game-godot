extends GutTest

var t: Tenancy

func before_each() -> void:
	t = Tenancy.new(FloorIndex.new(0, 6), 6)

func test_every_row_starts_tenanted_and_content() -> void:
	for floor_index in range(6):
		assert_false(t.is_vacant(floor_index))
		assert_gt(t.satisfaction_at(floor_index), Tenancy.MOVE_OUT_THRESHOLD)

func test_delivery_raises_satisfaction() -> void:
	for i in range(50):
		t.note_expiry(0)
	var low := t.satisfaction_at(0)
	for i in range(20):
		t.note_delivery(0)
	assert_gt(t.satisfaction_at(0), low)

func test_satisfaction_is_clamped_to_one() -> void:
	for i in range(1000):
		t.note_delivery(0)
	assert_almost_eq(t.satisfaction_at(0), 1.0, 1e-9)

func test_satisfaction_is_clamped_to_zero() -> void:
	for i in range(1000):
		t.note_expiry(0)
	assert_almost_eq(t.satisfaction_at(0), 0.0, 1e-9)

func test_a_tenanted_floor_generates_traffic_and_a_vacant_one_does_not() -> void:
	# Rent is gone: what a tenant is worth is the trips they generate.
	assert_true(t.occupied_floors().has(0), "tenanted floors carry traffic")
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_false(t.occupied_floors().has(0), "a vacant floor is nobody to carry")

func test_dropping_below_the_threshold_starts_a_visible_countdown() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	assert_true(t.is_moving_out(0))
	assert_gt(t.move_out_ticks_left(0), 0, "the player gets a chance to recover it")

func test_recovering_above_the_threshold_cancels_the_countdown() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	assert_true(t.is_moving_out(0))
	for i in range(200):
		t.note_delivery(0)
	assert_false(t.is_moving_out(0))

func test_the_countdown_expiring_vacates_the_row() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_true(t.is_vacant(0))

func test_vacant_rows_earn_nothing() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_true(t.is_vacant(0), "the countdown ran out and they left")

func test_leasing_retenants_a_mostly_vacated_row() -> void:
	# Pricing moved out to GameState.lease_cost (Tenancy.lease never charges), so
	# what is left to pin here is the behaviour: leasing re-tenants a floor.
	var pair := Tenancy.new(FloorIndex.new(0, 2), 2)
	while pair.satisfaction_at(1) > Tenancy.MOVE_OUT_THRESHOLD:
		pair.note_expiry(1)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		pair.accrue_for_tick()
	assert_eq(pair.tenanted_count(), 1, "one left, one remains")
	pair.lease(1, "apartments")
	assert_false(pair.is_vacant(1), "leasing re-tenants the floor")

func test_leasing_the_last_vacant_row_retenants() -> void:
	# The single no-fail rule: recovery is always reachable, so
	# all-floors-vacant-and-broke can never be terminal.
	var solo := Tenancy.new(FloorIndex.new(0, 1), 1)
	while solo.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		solo.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		solo.accrue_for_tick()
	assert_eq(solo.tenanted_count(), 0)
	solo.lease(0, "apartments")
	assert_false(solo.is_vacant(0), "recovery is reachable")

func test_leasing_a_vacated_row_among_tenants_retenants() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_gt(t.tenanted_count(), 0)
	t.lease(0, "shops")
	assert_false(t.is_vacant(0))

func test_lease_restores_the_row() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	t.lease(0, "shops")
	assert_false(t.is_vacant(0))
	assert_gt(t.satisfaction_at(0), Tenancy.MOVE_OUT_THRESHOLD)

func test_recovery_is_reachable_from_the_worst_state() -> void:
	# Spec §9.2 test 4: drive every tenant out, assert recovery through lease.
	for floor_index in range(6):
		while t.satisfaction_at(floor_index) > Tenancy.MOVE_OUT_THRESHOLD:
			t.note_expiry(floor_index)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_eq(t.tenanted_count(), 0, "everyone left")
	t.lease(0, "shops")
	assert_true(t.occupied_floors().has(0), "and the floor carries traffic again")

func test_add_row_extends_tenancy_with_a_vacant_row() -> void:
	t.add_floor()
	assert_eq(t.floors(), 7)
	assert_true(t.is_vacant(6), "a purchased floor is leased, not granted")

func test_accrue_reports_which_rows_vacated() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	var vacated := PackedInt32Array()
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		var out := t.accrue_for_tick()
		if not out.is_empty():
			vacated = out
	assert_eq(vacated.size(), 1, "exactly one floor_index vacated")
	assert_eq(vacated[0], 0, "and the caller is told which")

func test_a_vacancy_moves_the_revision() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	var before := t.revision()
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_ne(t.revision(), before)

func test_restoring_a_row_moves_the_revision() -> void:
	# The path every returning player's session starts with: decode mutates
	# tenancy from outside, and a cache built at construction would otherwise
	# never learn about it.
	var before := t.revision()
	t.restore_floor(2, 0.5, true, 0)
	assert_ne(t.revision(), before)

func test_only_the_roster_prefix_starts_tenanted() -> void:
	var tall := Tenancy.new(FloorIndex.new(0, 10), 6)
	for floor_index in range(6):
		assert_false(tall.is_vacant(floor_index), "floor_index %d is in the roster" % floor_index)
	for floor_index in range(6, 10):
		assert_true(tall.is_vacant(floor_index), "floor_index %d is past the roster" % floor_index)
		assert_eq(tall.kind_at(floor_index), "", "and carries no kind")

func test_a_purchased_row_arrives_vacant() -> void:
	t.add_floor()
	assert_eq(t.floors(), 7)
	assert_true(t.is_vacant(6), "you choose who moves in")
	assert_eq(t.kind_at(6), "")

func test_a_kind_is_remembered_and_cleared_on_vacancy() -> void:
	t.set_kind(2, "office")
	assert_eq(t.kind_at(2), "office")
	while t.satisfaction_at(2) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(2)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_true(t.is_vacant(2))
	assert_eq(t.kind_at(2), "", "kind leaves with the tenant")


# --- the basement -----------------------------------------------------------

func test_a_dug_floor_is_vacant_and_addressable_by_its_negative_index() -> void:
	var ix := FloorIndex.new(0, 3)
	var t := Tenancy.new(ix, 3)
	ix.dig()
	t.dig()
	assert_true(t.is_vacant(-1), "digging excavates, it does not lease")
	assert_eq(t.kind_at(-1), "", "and it has no tenant kind")

func test_leasing_the_basement_does_not_disturb_the_lobby() -> void:
	# The silent-wrong-index failure this whole design is shaped against: an
	# off-by-one writes the LOBBY's tenancy when asked for -1, which is in range
	# and therefore raises nothing at all.
	var ix := FloorIndex.new(0, 3)
	var t := Tenancy.new(ix, 3)
	t.set_kind(0, "shops")
	ix.dig()
	t.dig()
	t.restore_floor(-1, 1.0, false, 0, "parking")
	assert_eq(t.kind_at(-1), "parking")
	assert_eq(t.kind_at(0), "shops", "the lobby is untouched")
	assert_false(t.is_vacant(0))

func test_digging_twice_keeps_the_first_basement_where_it_was() -> void:
	var ix := FloorIndex.new(0, 2)
	var t := Tenancy.new(ix, 2)
	ix.dig(); t.dig()
	t.restore_floor(-1, 1.0, false, 0, "parking")
	ix.dig(); t.dig()
	assert_eq(t.kind_at(-1), "parking", "the leased floor did not move")
	assert_true(t.is_vacant(-2), "the new one is the empty one")

func test_occupied_floors_reports_floors_not_slots() -> void:
	# The two were the same number while the bottom floor was 0. A basement makes
	# them diverge, and the spawner uses this list as floor indices.
	var ix := FloorIndex.new(0, 2)
	var t := Tenancy.new(ix, 2)
	ix.dig(); t.dig()
	t.restore_floor(-1, 1.0, false, 0, "parking")
	var occupied := t.occupied_floors()
	assert_true(occupied.has(-1), "the basement reports as floor -1, not slot 0")
	assert_true(occupied.has(0), "and the lobby as floor 0")
	assert_eq(occupied.size(), 3)

func test_a_vacating_basement_reports_its_floor_not_its_slot() -> void:
	# accrue_for_tick's return drives removal of that floor's waiting passengers.
	# A slot here removes the wrong floor's people, silently.
	var ix := FloorIndex.new(0, 2)
	var t := Tenancy.new(ix, 2)
	ix.dig(); t.dig()
	t.restore_floor(-1, 0.0, false, 1, "parking")
	var vacated := t.accrue_for_tick()
	assert_eq(vacated.size(), 1, "the garage gave up")
	assert_eq(vacated[0], -1, "reported as floor -1")
