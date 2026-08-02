extends GutTest

func test_zero() -> void:
	assert_eq(NumberFormat.compact(0.0), "0")

func test_small_integers_have_no_decimal() -> void:
	assert_eq(NumberFormat.compact(7.0), "7")
	assert_eq(NumberFormat.compact(999.0), "999")

func test_exactly_one_thousand() -> void:
	assert_eq(NumberFormat.compact(1000.0), "1.0K")

func test_thousands() -> void:
	assert_eq(NumberFormat.compact(12400.0), "12.4K")

func test_millions() -> void:
	assert_eq(NumberFormat.compact(8100000.0), "8.1M")

func test_billions_and_trillions() -> void:
	assert_eq(NumberFormat.compact(2.0e9), "2.0B")
	assert_eq(NumberFormat.compact(2.0e12), "2.0T")

func test_the_rounding_boundary() -> void:
	# 999950/1000 = 999.95 -> rounds to 1000.0 -> "1000.0K" if the magnitude is
	# chosen BEFORE rounding. Magnitude must be chosen after.
	assert_eq(NumberFormat.compact(999950.0), "1.0M")

func test_the_rounding_boundary_repeats_at_every_rung() -> void:
	assert_eq(NumberFormat.compact(999950000.0), "1.0B")

func test_two_letter_ladder_starts_after_trillions() -> void:
	assert_eq(NumberFormat.compact(1.0e15), "1.0aa")

func test_two_letter_ladder_advances() -> void:
	assert_eq(NumberFormat.compact(1.0e18), "1.0ab")

func test_negative_values_keep_their_sign() -> void:
	assert_eq(NumberFormat.compact(-12400.0), "-12.4K")

func test_infinity_is_reported_not_formatted() -> void:
	assert_eq(NumberFormat.compact(INF), "∞")

func test_nan_is_reported_not_formatted() -> void:
	assert_eq(NumberFormat.compact(NAN), "NaN")

func test_the_ladder_covers_the_float_range() -> void:
	# 98 two-letter entries are needed to reach ~1e308; the table is generated,
	# not hand-written, so this must not fall off the end.
	var s := NumberFormat.compact(1.0e300)
	assert_false(s.is_empty())
	assert_false(s.contains("?"), "no gap in the ladder at 1e300")
