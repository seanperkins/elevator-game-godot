extends GutTest

## Prestige is the one place that knows a run can end. It is deliberately PURE:
## it never calls SaveStore -- the write happens in game_root.save_now(next) --
## which is why write-before-swap is tested at the scene boundary instead of
## here.

const F := Prestige.DEMOLITION_FLOOR

func played(earnings: float) -> GameState:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1)
	assert_true(s.is_valid(), "valid")
	# accrue() has no production callers, which makes it the cheap way to seed E.
	s.economy.accrue(earnings)
	return s

func test_the_conversion_walks_its_boundaries() -> void:
	assert_eq(Prestige.yield_for(0.0), 0, "nothing earned")
	assert_eq(Prestige.yield_for(F), 0, "the floor itself pays nothing")
	assert_eq(Prestige.yield_for(F + 100.0), 1, "the first blueprint")
	assert_eq(Prestige.yield_for(F + 399.0), 1, "one short of the second")
	assert_eq(Prestige.yield_for(F + 400.0), 2, "the second")
	assert_eq(Prestige.yield_for(F + 1600.0), 4, "the fourth")

func test_the_nth_blueprint_costs_two_hundred_more_than_the_last() -> void:
	# The property that made the square root the right family, and which a
	# logarithm does not have.
	for n in range(1, 8):
		var needed := F + 100.0 * float(n * n)
		assert_eq(Prestige.yield_for(needed), n, "%d BP at its exact threshold" % n)
		assert_eq(Prestige.yield_for(needed - 1.0), n - 1, "and one dollar short")

func test_an_enormous_earnings_clamps_and_stays_finite() -> void:
	assert_eq(Prestige.yield_for(1e308), Prestige.MAX_YIELD, "clamped")
	assert_true(is_finite(float(Prestige.yield_for(1e308))), "finite")

func test_a_nan_earnings_yields_nothing() -> void:
	# Pins maxf's ARGUMENT ORDER against a tidy-up: maxf(NAN - F, 0.0) is 0.0,
	# but maxf(0.0, NAN - F) is NAN and minf(NAN, MAX_YIELD) is MAX_YIELD --
	# a billion Blueprints from a poisoned save.
	assert_eq(Prestige.yield_for(NAN), 0, "absorbed")

func test_a_negative_earnings_yields_nothing() -> void:
	assert_eq(Prestige.yield_for(-1e9), 0, "and sqrt is never handed a negative")

func test_max_yield_equals_the_metas_ceiling() -> void:
	# Raise one later and a maxed save silently loses the difference on reload,
	# with every test green.
	assert_eq(Prestige.MAX_YIELD, Meta.MAX_BLUEPRINTS, "one statement, two files")

func test_can_demolish_agrees_with_the_gate() -> void:
	assert_false(Prestige.can_demolish(played(F)), "under")
	assert_true(Prestige.can_demolish(played(F + 100.0)), "at one blueprint")

func test_a_demolish_under_the_gate_is_refused_and_changes_nothing() -> void:
	var s := played(F)
	s.economy.cash = 500.0
	var before_floors := s.building.floor_count
	assert_null(Prestige.demolish(s), "refused")
	assert_eq(s.economy.cash, 500.0, "cash untouched")
	assert_eq(s.building.floor_count, before_floors, "floors untouched")
	assert_false(s.tenancy.is_vacant(0), "tenancy untouched")

func test_a_refusal_leaves_the_metas_balance_untouched() -> void:
	var s := played(F)
	s.meta.blueprints = 7
	s.meta.runs_completed = 3
	assert_null(Prestige.demolish(s), "refused")
	assert_eq(s.meta.blueprints, 7, "no credit on a refusal")
	assert_eq(s.meta.runs_completed, 3, "and no run counted")

func test_a_successful_demolish_credits_only_the_new_state() -> void:
	# GameState holds the Meta BY REFERENCE, so crediting the shared object
	# would leave the live run holding Blueprints it never earned -- and the
	# ten-second autosave then writes that credited Meta beside a still
	# demolish-eligible building, in one perfectly valid payload.
	var s := played(F + 1600.0)
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.meta.blueprints, 4, "the fresh run is credited")
	assert_eq(s.meta.blueprints, 0, "the handed run is NOT")
	assert_eq(next.meta.runs_completed, 1, "one run banked")
	assert_eq(s.meta.runs_completed, 0, "on the clone only")

func test_the_staged_meta_is_a_clone_not_the_live_one() -> void:
	var s := played(F + 1600.0)
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_ne(next.meta, s.meta, "a different object entirely")

func test_a_successful_demolish_resets_every_row_of_the_table() -> void:
	# Row by row, not a sample: a demolish that forgets `fitout` hands the next
	# run free class-3 floors at a 1.8x fare multiplier forever, and stays green.
	var s := played(F + 1600.0)
	s.economy.cash = 5000.0
	s.economy.combo = 4.0
	s.economy.streak = 40
	s.economy.riders_served = 99
	assert_true(s.buy("floor"), "a floor to discard")
	s.fitout.set_tier(0, 3)
	s.clock.note_ticks(5000)
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.economy.cash, 0.0, "cash")
	assert_eq(next.economy.lifetime_earnings, 0.0, "lifetime -- it IS the yield input")
	assert_eq(next.economy.combo, 1.0, "combo")
	assert_eq(next.economy.streak, 0, "streak")
	assert_eq(next.economy.riders_served, 0, "riders")
	assert_eq(next.building.floor_count, GameState.BASE_FLOORS, "floors")
	assert_eq(next.building.cars.size(), next.meta.starting_shafts(), "cars")
	assert_eq(next.upgrades.level_of("floor"), 0, "upgrade levels")
	assert_false(next.tenancy.is_vacant(0), "tenancy rebuilt from the roster")
	assert_eq(next.fitout.tier_at(0), Fitout.BASE_TIER,
		"class tiers -- this row is what keeps 'every run re-earns its tenants' true")
	assert_eq(next.auto.preset_of(0), DispatchPolicy.Preset.MANUAL, "policies")
	assert_eq(next.metrics.deliveries(), 0, "metrics")
	assert_eq(next.clock.ticks_executed, 0, "the clock -- a new building opens at 06:00")

func test_the_new_seed_is_derived_from_the_run_count() -> void:
	# The LITERAL, not the symbolic form: asserting BASE_SEED + runs_completed
	# lets a pre/post-increment mistake reproduce on both sides and pass. And
	# mere inequality is insufficient -- a run loaded from a save carries an
	# unrelated seed.
	var s := played(F + 1600.0)
	var next := Prestige.demolish(s)
	assert_eq(next.spawner.seed_value(), GameState.BASE_SEED + 1,
		"run 2 must not replay run 1's traffic forever")
	next.economy.accrue(F + 1600.0)
	var third := Prestige.demolish(next)
	assert_eq(third.spawner.seed_value(), GameState.BASE_SEED + 2, "and run 3")

func test_two_demolishes_do_not_pay_twice_for_one_run() -> void:
	# The strongest test in the file: it fails loudly if lifetime_earnings is
	# ever made to persist, which is the unbounded-minting hole.
	var s := played(F + 1600.0)
	var second := Prestige.demolish(s)
	assert_eq(second.meta.blueprints, 4, "first demolish")
	second.economy.accrue(F + 1600.0)
	var third := Prestige.demolish(second)
	assert_eq(third.meta.blueprints, 8, "4 + 4, not 4 + 8")

func test_demolish_spam_earns_nothing() -> void:
	var s := played(F + 1600.0)
	var second := Prestige.demolish(s)
	assert_not_null(second, "the first one is allowed")
	assert_null(Prestige.demolish(second), "with no play in between, nothing")

func test_a_demolish_into_an_invalid_state_is_refused() -> void:
	var s := played(F + 1600.0)
	s._catalog_path = "res://data/does_not_exist.json"
	assert_null(Prestige.demolish(s), "refused rather than swapping in a dead run")
	assert_eq(s.meta.blueprints, 0, "and nothing was credited on the way")
	assert_eq(s.meta.runs_completed, 0, "nor counted")

func test_a_demolish_with_an_unloadable_blueprint_catalog_is_refused() -> void:
	var s := played(F + 1600.0)
	s._blueprints_path = "res://data/does_not_exist.json"
	assert_null(Prestige.demolish(s), "refused")
	assert_eq(s.meta.blueprints, 0, "and the tree was not emptied on the way")

func test_the_tree_survives_the_demolish() -> void:
	var s := played(F + 1600.0)
	s.meta.blueprints = 10
	assert_true(s.meta.buy("height", s.upgrades), "buy a node")
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.meta.level_of("height"), 1, "spent levels are kept")
	assert_eq(next.meta.height_cap(), 15, "and the next run gets the cap it paid for")

func test_the_next_run_starts_with_what_the_tree_bought() -> void:
	var s := played(F + 1600.0)
	s.meta.blueprints = 100
	assert_true(s.meta.buy("shafts", s.upgrades), "shafts")
	assert_true(s.meta.buy("motor", s.upgrades), "motor")
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.building.cars.size(), 2, "the granted shaft")
	assert_eq(next.upgrades.level_of("speed"), 1, "the granted motor level")
	assert_almost_eq(next.building.cars[0].floors_per_tick,
		next.upgrades.effect_value("speed", 1), 1e-9, "and the cars are synced")

func test_a_demolish_carries_the_dev_unlock_across() -> void:
	# meta.gd states this as a designed property; it works only because
	# to_dict/restore happen to round-trip the flag, and nothing pinned it.
	# Rebuilding is a game action, not a factory reset.
	var s := played(F + 1600.0)
	s.meta.dev_unlocked = true
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_true(next.meta.dev_unlocked, "the panel stays found across a rebuild")
