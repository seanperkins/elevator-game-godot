extends GutTest

var econ: Economy

func before_each() -> void:
	econ = Economy.new()

func test_starts_empty() -> void:
	assert_almost_eq(econ.cash, 0.0, 1e-9)
	assert_almost_eq(econ.combo, 1.0, 1e-9, "combo starts at 1x, not 0")
	assert_eq(econ.riders_served, 0)

func test_delivery_credits_the_fare() -> void:
	var paid := econ.credit_delivery(10.0)
	assert_almost_eq(paid, 10.0, 1e-9, "first delivery pays face value")
	assert_almost_eq(econ.cash, 10.0, 1e-9)
	assert_eq(econ.riders_served, 1)

func test_delivery_raises_the_combo() -> void:
	econ.credit_delivery(10.0)
	assert_almost_eq(econ.combo, 1.0 + Economy.COMBO_STEP, 1e-9)

func test_combo_multiplies_later_fares() -> void:
	econ.credit_delivery(10.0)              # combo now 1.02
	var paid := econ.credit_delivery(10.0)
	assert_almost_eq(paid, 10.2, 1e-9)

func test_combo_is_hard_capped() -> void:
	# Uncapped compounding reaches infinity in a long automated streak and
	# silently poisons every downstream number.
	for i in range(100000):
		econ.credit_delivery(1.0)
	assert_almost_eq(econ.combo, Economy.COMBO_MAX, 1e-9)
	assert_true(is_finite(econ.cash), "cash must never become INF")

func test_expiry_resets_the_combo_and_the_streak() -> void:
	econ.credit_delivery(10.0)
	econ.credit_delivery(10.0)
	assert_gt(econ.streak, 0)
	econ.note_expiry()
	assert_almost_eq(econ.combo, 1.0, 1e-9, "one bad delivery kills it")
	assert_eq(econ.streak, 0)

func test_expiry_does_not_take_cash_away() -> void:
	econ.credit_delivery(10.0)
	var before := econ.cash
	econ.note_expiry()
	assert_almost_eq(econ.cash, before, 1e-9)

func test_lifetime_earnings_only_ever_rises() -> void:
	econ.credit_delivery(10.0)
	econ.spend(5.0)
	assert_almost_eq(econ.lifetime_earnings, 10.0, 1e-9,
		"spending must not reduce lifetime earnings -- prestige reads it")

func test_accrue_adds_rent_without_touching_the_combo() -> void:
	econ.accrue(3.5)
	assert_almost_eq(econ.cash, 3.5, 1e-9)
	assert_almost_eq(econ.combo, 1.0, 1e-9)
	assert_eq(econ.riders_served, 0, "rent is not a rider")

func test_spend_succeeds_when_affordable() -> void:
	econ.accrue(50.0)
	assert_true(econ.spend(20.0))
	assert_almost_eq(econ.cash, 30.0, 1e-9)

func test_spend_fails_and_changes_nothing_when_unaffordable() -> void:
	econ.accrue(10.0)
	assert_false(econ.spend(20.0))
	assert_almost_eq(econ.cash, 10.0, 1e-9, "a failed purchase must not debit")

func test_spend_exactly_all_cash_succeeds() -> void:
	econ.accrue(20.0)
	assert_true(econ.spend(20.0), "boundary: exactly affordable")
	assert_almost_eq(econ.cash, 0.0, 1e-9)

func test_can_afford_matches_spend_at_the_boundary() -> void:
	econ.accrue(20.0)
	assert_true(econ.can_afford(20.0))
	assert_false(econ.can_afford(20.01))

func test_taking_the_stairs_costs_money() -> void:
	# Bad service is actively expensive, not merely unprofitable.
	econ.accrue(100.0)
	econ.note_expiry(4.0)
	assert_almost_eq(econ.cash, 96.0, 1e-6, "a fare's worth of goodwill")

func test_the_stairs_penalty_cannot_push_you_into_debt() -> void:
	# The design has a hard no-fail rule, and a debt that outruns income is a
	# fail state wearing a number.
	econ.accrue(1.0)
	econ.note_expiry(4.0)
	assert_almost_eq(econ.cash, 0.0, 1e-9, "floored, not negative")

func test_the_penalty_on_an_empty_purse_is_nothing() -> void:
	assert_almost_eq(econ.cash, 0.0, 1e-9)
	for i in range(50):
		econ.note_expiry(4.0)
	assert_almost_eq(econ.cash, 0.0, 1e-9, "still zero, never below it")

func test_an_expiry_still_breaks_the_combo() -> void:
	econ.credit_delivery(10.0)
	assert_gt(econ.combo, 1.0)
	econ.note_expiry(4.0)
	assert_almost_eq(econ.combo, 1.0, 1e-9)
