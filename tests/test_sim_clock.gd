extends GutTest

var clock: SimClock

func before_each() -> void:
	clock = SimClock.new()

func test_one_physics_frame_at_60hz_yields_no_whole_tick_alone() -> void:
	# 1/60 s = 0.01667 s, which is less than one 0.05 s tick.
	assert_eq(clock.take_ticks(1.0 / 60.0), 0, "a single 60Hz frame is under one tick")

func test_three_physics_frames_yield_exactly_one_tick() -> void:
	# 3 * 1/60 = 0.05 exactly. This is the 60 -> 20 Hz ratio.
	clock.take_ticks(1.0 / 60.0)
	clock.take_ticks(1.0 / 60.0)
	assert_eq(clock.take_ticks(1.0 / 60.0), 1, "three 60Hz frames make one sim tick")

func test_one_second_of_frames_yields_twenty_ticks() -> void:
	# 20/s is a rate over accumulated frames. It is NOT what a single one-second
	# frame delivers: that is a one-second stall, and the clamp below forfeits
	# most of it deliberately.
	var total := 0
	for i in range(60):
		total += clock.take_ticks(1.0 / 60.0)
	assert_eq(total, 20, "20 ticks per second at 60 Hz")

func test_a_one_second_frame_is_itself_a_hitch() -> void:
	assert_eq(clock.take_ticks(1.0), SimClock.MAX_TICKS_PER_FRAME,
		"one 1 s frame is a stall, not a second of normal play")

func test_accumulator_does_not_drift_over_many_frames() -> void:
	var total := 0
	for i in range(600):          # 600 frames at 60Hz = 10 s
		total += clock.take_ticks(1.0 / 60.0)
	assert_eq(total, 200, "10 s must be exactly 200 ticks, not 199 or 201")

func test_long_frame_is_clamped_and_the_excess_is_forfeited() -> void:
	# A 2 s hitch wants 40 ticks; the clamp allows 8.
	assert_eq(clock.take_ticks(2.0), 8, "clamped to MAX_TICKS_PER_FRAME")
	assert_almost_eq(clock.discarded_seconds, 1.6, 1e-9,
		"32 forfeited ticks * 0.05 s")

func test_clamped_time_does_not_spiral_into_the_next_frame() -> void:
	clock.take_ticks(2.0)                     # hitch
	assert_eq(clock.take_ticks(1.0 / 60.0), 0,
		"the leftover must be discarded, not queued")

func test_the_day_starts_at_the_morning_rush() -> void:
	# The traffic curve's first six buckets are the overnight trough, 0.4 to 0.8
	# spawns per simulated minute against a 45-second patience. A day starting at
	# bucket 0 shows a new player an empty building for six real minutes, which is
	# the first thing anyone sees.
	assert_eq(clock.sim_minute(), SimClock.START_MINUTE)
	assert_gt(SimClock.START_MINUTE, 0, "midnight is not where a session opens")

func test_sim_minute_advances_every_1200_ticks() -> void:
	var start := SimClock.START_MINUTE
	assert_eq(clock.sim_minute(), start)
	clock.note_ticks(1199)
	assert_eq(clock.sim_minute(), start, "1199 ticks is still the opening minute")
	clock.note_ticks(1)
	assert_eq(clock.sim_minute(), start + 1, "1200 ticks is one minute on")

func test_sim_minute_uses_integer_arithmetic() -> void:
	# Indexing by a float accumulator lands 1.27e-12 below 60.0 after 1200
	# additions of 0.05, so a >= 60.0 test fires one tick late.
	clock.note_ticks(1200 * 137)
	assert_eq(clock.sim_minute(), SimClock.START_MINUTE + 137,
		"exact at a high minute count")
