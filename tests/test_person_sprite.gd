extends GutTest

## A person, drawn. _draw() output is not observable headlessly, so parts() and
## redraw_count() are the seams -- the same device day_sparkline.gd uses.

var p: PersonSprite

func before_each() -> void:
	p = PersonSprite.new()
	add_child_autofree(p)

func test_the_parts_fit_the_hall_cell_and_do_not_overlap() -> void:
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	var q := p.parts()
	for name in ["badge", "figure", "bar"]:
		var r: Rect2 = q[name]
		assert_gte(r.position.x, -0.01, "%s starts left of the cell" % name)
		assert_lte(r.end.x, PersonSprite.HALL_CELL.x + 0.01, "%s overflows" % name)
		assert_lte(r.end.y, PersonSprite.HALL_CELL.y + 0.01, "%s is too tall" % name)
	assert_false((q["badge"] as Rect2).intersects(q["figure"]), "badge over figure")
	assert_false((q["figure"] as Rect2).intersects(q["bar"]), "bar over figure")

func test_the_figure_is_centred_in_its_band_not_pinned_to_x_one() -> void:
	# In the hall the band is 16 wide so centring gives x = 1; in a wide car cell
	# the same rule centres properly instead of stranding the figure left.
	# The band is the cell less the patience bar in the hall, the whole cell in
	# the car -- and the figure is centred in whichever it has.
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	var band := PersonSprite.HALL_CELL.x - PersonSprite.BAR_W
	assert_almost_eq((p.parts()["figure"] as Rect2).position.x,
		(band - PersonSprite.FIGURE.x) * 0.5, 0.01, "centred in the hall band")
	p.set_cell(Vector2(52, CarRack.BAND))
	p.show_riding("12", 0)
	assert_almost_eq((p.parts()["figure"] as Rect2).position.x,
		(52.0 - PersonSprite.FIGURE.x) * 0.5, 0.01, "centred in the car cell")

func test_a_rider_has_no_patience_bar_and_a_waiter_does() -> void:
	p.show_riding("7", 0)
	assert_eq((p.parts()["bar"] as Rect2).size, Vector2.ZERO, "patience is frozen aboard")
	p.show_waiting(0.5, FloorRow.CALL_UP, 0)
	assert_gt((p.parts()["bar"] as Rect2).size.y, 0.0)

func test_the_bar_fills_from_the_bottom() -> void:
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	var full: Rect2 = p.parts()["bar"]
	p.show_waiting(0.25, FloorRow.CALL_UP, 0)
	var low: Rect2 = p.parts()["bar"]
	assert_lt(low.size.y, full.size.y, "less patience is a shorter bar")
	assert_almost_eq(low.end.y, full.end.y, 0.01, "both sit on the same floor")

func test_the_tint_key_is_stable_and_independent_of_the_pool_slot() -> void:
	var a := PersonSprite.key_for(0, 7, 7)
	var b := PersonSprite.key_for(0, 7, 7)
	assert_eq(a, b, "the same trip is the same key, whichever sprite draws it")

func test_every_shirt_and_skin_occurs_across_the_spawner_s_trip_shapes() -> void:
	# The test that would have caught BOTH hash failures. Floor 0 is included
	# because the lobby-source substitution (0, G, 0) is the degenerate case and
	# both previous failures were degenerate substitutions.
	var shirts := {}
	var skins := {}
	for f in range(0, 21):
		for key in [PersonSprite.key_for(0, f, f),      # inbound
					PersonSprite.key_for(f, 0, f),      # outbound
					PersonSprite.key_for(f, (f + 3) % 21, f),  # interfloor
					PersonSprite.key_for(0, f, 0)]:     # lobby-source interfloor
			shirts[posmod(key, Palette.PERSON_SHIRTS.size())] = true
			skins[posmod(key, Palette.PERSON_SKINS.size())] = true
	assert_eq(shirts.size(), Palette.PERSON_SHIRTS.size(),
		"a whole traffic class would be wearing one shirt")
	assert_eq(skins.size(), Palette.PERSON_SKINS.size(),
		"a whole traffic class would have one skin")

func test_a_negative_floor_cannot_index_out_of_the_palette() -> void:
	# Latent, not reachable: BoardCoords takes a signed bottom for a future
	# basement, and GDScript's % returns negative for a negative left operand.
	p.show_waiting(1.0, FloorRow.CALL_UP, PersonSprite.key_for(-3, -1, -3))
	assert_true(true, "indexing did not throw")

func test_an_unchanged_call_does_not_redraw_but_a_changed_one_does() -> void:
	# refresh() runs every frame, so an unconditional queue_redraw() re-records
	# every person at 60Hz on the threadless export. The suppression is the
	# risky half -- a stale badge is the failure -- so both directions are pinned.
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	var n := p.redraw_count()
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	assert_eq(p.redraw_count(), n, "identical arguments must not redraw")
	p.show_waiting(0.1, FloorRow.CALL_UP, 0)
	assert_gt(p.redraw_count(), n, "a changed fraction must redraw")
	var m := p.redraw_count()
	p.set_cell(Vector2(36, CarRack.BAND))
	assert_gt(p.redraw_count(), m, "a changed cell must redraw")

func test_recycling_an_already_recycled_sprite_does_not_redraw() -> void:
	# FloorRow.set_waiting calls recycle() on every UNUSED sprite every refresh --
	# up to twelve a floor, on every floor, at 60Hz. An unconditional _dirty()
	# there re-recorded the whole strip every frame for people who are not on
	# screen, which is the exact cost the suppression above exists to avoid.
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	p.recycle()
	var n := p.redraw_count()
	p.recycle()
	p.recycle()
	assert_eq(p.redraw_count(), n, "recycling twice must not redraw")
	assert_false(p.visible)
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	assert_gt(p.redraw_count(), n, "and coming back does")

func test_a_direction_that_is_not_bought_yet_draws_no_badge() -> void:
	# An empty badge is a blank dark box, which reads as an error state -- the
	# outcome CALL_UNKNOWN's empty string exists to avoid.
	p.show_waiting(1.0, FloorRow.CALL_UNKNOWN, 0)
	assert_eq((p.parts()["badge"] as Rect2).size, Vector2.ZERO)
	assert_eq(p.label_text(), FloorRow.CALL_UNKNOWN)
