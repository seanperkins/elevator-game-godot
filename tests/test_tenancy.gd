extends GutTest

var t: Tenancy

func before_each() -> void:
	t = Tenancy.new(6, 6)

func test_every_row_starts_tenanted_and_content() -> void:
	for row in range(6):
		assert_false(t.is_vacant(row))
		assert_gt(t.satisfaction_at(row), Tenancy.MOVE_OUT_THRESHOLD)

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
	assert_true(t.occupied_rows().has(0), "tenanted floors carry traffic")
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_false(t.occupied_rows().has(0), "a vacant floor is nobody to carry")

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

func test_a_single_tenant_can_never_be_charged_to_re_lease() -> void:
	# A trip needs two floors, so one tenant earns exactly what none does.
	# Charging to escape that would be a fail state with a price on the exit.
	var pair := Tenancy.new(2, 2)
	while pair.satisfaction_at(1) > Tenancy.MOVE_OUT_THRESHOLD:
		pair.note_expiry(1)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		pair.accrue_for_tick()
	assert_eq(pair.tenanted_count(), 1, "one left, one remains")
	assert_almost_eq(pair.relet_cost(1), 0.0, 1e-9,
		"one tenant cannot generate traffic, so the way back must be free")

func test_reletting_the_last_row_is_free() -> void:
	# The single no-fail rule: recovery is always reachable, so
	# all-rows-vacant-and-broke can never be terminal.
	var solo := Tenancy.new(1, 1)
	while solo.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		solo.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		solo.accrue_for_tick()
	assert_eq(solo.tenanted_count(), 0)
	assert_almost_eq(solo.relet_cost(0), 0.0, 1e-9, "free when nothing is tenanted")

func test_reletting_costs_money_while_other_rows_still_pay() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_gt(t.tenanted_count(), 0)
	assert_gt(t.relet_cost(0), 0.0)

func test_relet_restores_the_row() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	t.relet(0)
	assert_false(t.is_vacant(0))
	assert_gt(t.satisfaction_at(0), Tenancy.MOVE_OUT_THRESHOLD)

func test_recovery_is_reachable_from_the_worst_state() -> void:
	# Spec §9.2 test 4: drive every tenant out at zero cash, assert recovery.
	for row in range(6):
		while t.satisfaction_at(row) > Tenancy.MOVE_OUT_THRESHOLD:
			t.note_expiry(row)
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		t.accrue_for_tick()
	assert_eq(t.tenanted_count(), 0, "everyone left")
	assert_almost_eq(t.relet_cost(0), 0.0, 1e-9, "so re-leasing must be free")
	t.relet(0)
	assert_true(t.occupied_rows().has(0), "and the floor carries traffic again")

func test_add_row_extends_tenancy_with_a_vacant_row() -> void:
	t.add_row()
	assert_eq(t.rows(), 7)
	assert_true(t.is_vacant(6), "a purchased floor is leased, not granted")

func test_accrue_reports_which_rows_vacated() -> void:
	while t.satisfaction_at(0) > Tenancy.MOVE_OUT_THRESHOLD:
		t.note_expiry(0)
	var vacated := PackedInt32Array()
	for i in range(Tenancy.MOVE_OUT_TICKS + 1):
		var out := t.accrue_for_tick()
		if not out.is_empty():
			vacated = out
	assert_eq(vacated.size(), 1, "exactly one row vacated")
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
	t.restore_row(2, 0.5, true, 0)
	assert_ne(t.revision(), before)

func test_only_the_roster_prefix_starts_tenanted() -> void:
	var tall := Tenancy.new(10, 6)
	for row in range(6):
		assert_false(tall.is_vacant(row), "row %d is in the roster" % row)
	for row in range(6, 10):
		assert_true(tall.is_vacant(row), "row %d is past the roster" % row)
		assert_eq(tall.kind_at(row), "", "and carries no kind")

func test_a_purchased_row_arrives_vacant() -> void:
	t.add_row()
	assert_eq(t.rows(), 7)
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
