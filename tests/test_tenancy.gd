extends GutTest

var t: Tenancy

func before_each() -> void:
	t = Tenancy.new(6)

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
	var pair := Tenancy.new(2)
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
	var solo := Tenancy.new(1)
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

func test_add_row_extends_tenancy() -> void:
	t.add_row()
	assert_false(t.is_vacant(6))
