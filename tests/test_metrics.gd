extends GutTest

var m: Metrics

func before_each() -> void:
	m = Metrics.new()

## Runs n ticks, advancing first exactly as GameState does.
func run_ticks(n: int) -> void:
	for i in range(n):
		m.advance()

func test_an_empty_window_reports_nothing() -> void:
	assert_eq(m.deliveries(), 0)
	assert_eq(m.expiries(), 0)
	assert_almost_eq(m.average_wait_seconds(), -1.0, 1e-9,
		"no deliveries is a sentinel, not zero")

func test_a_partial_window_counts_everything_in_it() -> void:
	for i in range(5):
		m.advance()
		m.record_delivery(200)
	assert_eq(m.deliveries(), 5)

func test_average_wait_is_in_seconds() -> void:
	m.advance()
	m.record_delivery(200)       # 200 ticks * 0.05 = 10 s
	m.record_delivery(600)       # 30 s
	assert_almost_eq(m.average_wait_seconds(), 20.0, 1e-6)

func test_expiries_are_counted_separately() -> void:
	m.advance()
	m.record_expiry()
	m.record_expiry()
	assert_eq(m.expiries(), 2)
	assert_eq(m.deliveries(), 0)

func test_an_event_on_the_rollover_tick_is_counted() -> void:
	# Tick 1200 rolls into bucket 0 and clears it. Advancing FIRST means the
	# event lands in the freshly cleared bucket, not one about to be wiped.
	run_ticks(1200)
	m.record_delivery(100)
	assert_eq(m.deliveries(), 1, "counted on the rollover tick itself")

func test_that_event_survives_to_the_end_of_its_bucket() -> void:
	run_ticks(1200)
	m.record_delivery(100)
	run_ticks(19)
	assert_eq(m.deliveries(), 1, "still counted 19 ticks later")

func test_events_leave_the_window_after_a_full_wrap() -> void:
	m.advance()
	m.record_delivery(100)
	run_ticks(1200)              # a full wrap back onto that bucket
	assert_eq(m.deliveries(), 0, "the bucket was cleared on the way past")

func test_a_window_wrapped_more_than_once_holds_only_recent_events() -> void:
	for i in range(3000):
		m.advance()
		if i % 100 == 0:
			m.record_delivery(100)
	# 3000 ticks in, only the last ~1200 ticks of events remain: i = 1900,
	# 2000 ... 2900 is at most 12 of them.
	assert_between(m.deliveries(), 1, 12,
		"a wrapped window must not accumulate forever")

func test_negative_wait_is_floored_at_zero() -> void:
	m.advance()
	m.record_delivery(-5)
	assert_almost_eq(m.average_wait_seconds(), 0.0, 1e-9)

func test_format_wait_renders_a_dash_when_there_is_no_data() -> void:
	# The first thing a new player sees. Never "0", never "nan".
	assert_eq(Metrics.format_wait(-1.0), "—")

func test_format_wait_renders_whole_seconds() -> void:
	assert_eq(Metrics.format_wait(12.4), "12s")
	assert_eq(Metrics.format_wait(0.0), "0s")

func test_format_rate_renders_a_plain_count() -> void:
	assert_eq(Metrics.format_rate(0), "0")
	assert_eq(Metrics.format_rate(18), "18")
