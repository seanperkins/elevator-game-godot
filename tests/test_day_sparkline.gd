extends GutTest

## DaySparkline is a pure Control-seamed widget: it needs no scene root, so
## these tests construct it bare, give it a size, and read the seams
## (bar_heights, segment_shares) that _draw() itself reads.

var cat: TenantCatalog

func before_each() -> void:
	cat = TenantCatalog.new()
	cat.load_from("res://data/tenants.json")

func _apartments() -> TenantKind:
	return cat.kind("apartments")

func _sparkline() -> DaySparkline:
	var s := DaySparkline.new()
	s.size = Vector2(240, 48)
	return s

func test_it_draws_one_bar_per_simulated_hour() -> void:
	var s := _sparkline()
	s.show_kind(_apartments())
	assert_eq(s.bar_heights().size(), 24)

func test_bar_height_is_proportional_to_rate() -> void:
	var s := _sparkline()
	var k := _apartments()
	s.show_kind(k)
	var h := s.bar_heights()
	# hour 7 is the out-peak (1.2) and hour 2 the overnight trough (0.1); the
	# heights share the kind's ratio because both are normalised to its own max.
	assert_almost_eq(h[7] / h[2], k.rate_at(7) / k.rate_at(2), 1e-3)

func test_the_segments_match_the_mix() -> void:
	var s := _sparkline()
	var k := _apartments()
	s.show_kind(k)
	var seg := s.segment_shares(7)
	assert_almost_eq(seg.x, k.inbound_at(7), 1e-5)
	assert_almost_eq(seg.y, k.outbound_at(7), 1e-5)
	assert_almost_eq(seg.x + seg.y + seg.z, 1.0, 1e-5)

func test_the_mix_collapses_to_interfloor_when_it_must() -> void:
	# Shops is all 0.25/0.25, so interfloor holds the rest -- the three slices
	# always account for the whole bar.
	var s := _sparkline()
	s.show_kind(cat.kind("shops"))
	var seg := s.segment_shares(12)
	assert_almost_eq(seg.z, 0.5, 1e-5)

# --- the playhead ------------------------------------------------------------

func test_no_playhead_until_an_hour_is_set() -> void:
	# A sparkline in the floor panel with no clock bound must not claim it is
	# midnight -- the absence of a marker and "the marker is at 0" are different
	# statements, and only one of them is true.
	var s := _sparkline()
	s.show_kind(_apartments())
	assert_eq(s.playhead_bar(), -1, "-1 means no marker, not bucket zero")

func test_the_playhead_marks_the_current_hour() -> void:
	var s := _sparkline()
	s.show_kind(_apartments())
	s.set_now(7)
	assert_eq(s.playhead_bar(), 7)

func test_the_playhead_wraps_with_the_curve() -> void:
	# set_now takes whatever SimClock.hour_of_day gives it; a caller passing a
	# raw sim_minute must land on the same bar the spawner reads.
	var s := _sparkline()
	s.show_kind(_apartments())
	s.set_now(30)
	assert_eq(s.playhead_bar(), 6, "30 mod 24")
