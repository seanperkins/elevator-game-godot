extends GutTest

## The palette's RELATIONSHIPS, not its values.
##
## Nothing here pins a hex. Re-mixing a pigment is meant to be a one-line
## change, and a test that asserts CAR == "d98e5a" would make every retheme a
## test edit -- which trains you to update the expectation without reading it.
##
## What these pin is what has to stay true of ANY palette for the board to be
## readable: ink brighter than the surface under it, each surface a step lighter
## than the one behind it, the patience ramp light enough for its own label at
## every point along the lerp, and three traffic series that are actually three
## colours. Each of those has already been broken once by a plausible-looking
## colour choice -- the cases are named in the tests.

## WCAG relative luminance. NOT Color.get_luminance(), which weights the
## sRGB-encoded components directly without linearising them; the two disagree
## most in exactly the dark range this palette lives in.
func _relative_luminance(c: Color) -> float:
	var parts := [c.r, c.g, c.b]
	var out := []
	for p in parts:
		out.append(p / 12.92 if p <= 0.04045 else pow((p + 0.055) / 1.055, 2.4))
	return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]

func _contrast(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Shortest arc between two hues, in degrees. Wrapping matters: the rose sits at
## 347 and the gold at 37, which is 50 degrees apart, not 310.
func _hue_gap(a: Color, b: Color) -> float:
	var d := fmod(absf(a.h - b.h) * 360.0, 360.0)
	return minf(d, 360.0 - d)

# ------------------------------------------------------------------- ink --

func test_ink_tiers_are_strictly_ordered() -> void:
	# The hierarchy IS the gap. Any two tiers that land on the same weight read
	# as one tier, and the panels lose their primary/secondary structure even
	# though every individual label still passes a contrast check.
	#
	# Ordered by CONTRAST against the ground, not by luminance. Luminance
	# ordering is a dark-theme accident: there, louder meant brighter, so the
	# two agreed. On a light ground louder means DARKER and a luminance test
	# would demand precisely the wrong thing. Contrast is what actually means
	# "louder", in either theme -- this test survived the inversion unchanged
	# in intent and only changed in measure.
	var tiers := [Palette.INK, Palette.INK_FLOOR, Palette.INK_MUTED, Palette.INK_FAINT]
	for i in range(tiers.size() - 1):
		assert_gt(_contrast(tiers[i], Palette.APP_BG), _contrast(tiers[i + 1], Palette.APP_BG),
			"ink tier %d must be louder than tier %d against the ground" % [i, i + 1])

func test_every_ink_reads_on_the_surface_it_is_drawn_on() -> void:
	assert_gt(_contrast(Palette.INK, Palette.APP_BG), 4.5, "INK on APP_BG")
	assert_gt(_contrast(Palette.INK_FLOOR, Palette.APP_BG), 4.5, "floor number on APP_BG")
	assert_gt(_contrast(Palette.INK_MUTED, Palette.PANEL_BG), 4.5, "notes on PANEL_BG")
	# The faint tier is allowed to be dimmer than 4.5 -- it is tertiary -- but
	# not so dim it stops being text.
	assert_gt(_contrast(Palette.INK_FAINT, Palette.PANEL_BG), 3.0, "faint labels on PANEL_BG")

func test_the_move_out_alarm_reads_and_is_not_mistakable_for_an_ordinary_floor() -> void:
	# The floor number turns ALARM when that floor's tenant is leaving, and it is
	# the board's ONLY tenant-state signal since the gutter bar went. Two things
	# have to hold: it is still legible, and it does not read as the normal ink.
	assert_gt(_contrast(Palette.ALARM, Palette.APP_BG), 3.0,
		"the alarm floor number must still be text")
	assert_gt(_hue_gap(Palette.ALARM, Palette.INK_FLOOR), 90.0,
		"alarm and ordinary floor numbers must not read as the same colour")

func test_the_patience_ramp_would_not_have_worked_as_the_alarm() -> void:
	# Pins the reason ALARM is VERMILION rather than the ramp's red. PATIENCE_LOW
	# was solved against a bar track; the floor number sits on the ground, and a
	# future edit "unifying the two reds" would silently make the alarm vanish.
	assert_lt(_contrast(Palette.PATIENCE_LOW, Palette.APP_BG), 3.0,
		"PATIENCE_LOW on the ground is why it is not the alarm")

# -------------------------------------------------------------- surfaces --

func test_the_surface_ladder_is_monotonic_and_separated() -> void:
	# The board reads as depth only because each layer steps away from the one
	# behind it. What matters is that the steps are MONOTONIC and big enough to
	# see -- not which direction they run.
	#
	# The direction is a property of the theme, not of the design: the dark
	# palette's ladder ascended in luminance, this light one descends. Pinning
	# "ascends" made the test fail on a correct light palette, which is the test
	# doing its job -- it forced this to be a decision rather than a drift.
	var ladder := [Palette.PANEL_BG, Palette.APP_BG, Palette.CARD_BG,
		Palette.GHOST_BG, Palette.RULE]
	var lums := []
	for c in ladder:
		lums.append(_relative_luminance(c))
	var descending: bool = lums[0] > lums[1]
	for i in range(lums.size() - 1):
		if descending:
			assert_gt(lums[i], lums[i + 1],
				"surface ladder must not reverse at step %d" % i)
		else:
			assert_lt(lums[i], lums[i + 1],
				"surface ladder must not reverse at step %d" % i)
		# A step too small to see is the same failure as a reversal: the two
		# layers merge and the board flattens.
		assert_gt(absf(lums[i] - lums[i + 1]), 0.01,
			"surfaces %d and %d must be distinguishable" % [i, i + 1])

# ------------------------------------------------------------- the car --

func test_the_car_label_reads_against_the_car() -> void:
	# The regression this exists for: a theme pass painted cream on a terracotta
	# car at 2.14:1 -- a floor number, on the one thing on screen that moves,
	# that you cannot read. Which ink is correct flipped when the car became the
	# dark mass; that it must READ did not.
	assert_gt(_contrast(Palette.INK_ON_LIGHT, Palette.CAR), 4.5,
		"the car's floor number must read against the car body")

func test_the_fill_ink_beats_the_alternative_on_every_fill_it_lands_on() -> void:
	# INK_ON_LIGHT is drawn on the car AND on the patience chips, all of which
	# are mid-luminance. Mid fills are the worst case for text, and the trap is
	# picking the ink from the theme's mood ("light theme, so pale ink") rather
	# than from the fill. Pin the comparison instead of the conclusion: whatever
	# INK_ON_LIGHT is, it must beat the ground colour used as ink on the same
	# fill -- otherwise the palette is choosing the losing option.
	# The patience fills were dropped from the list: no ink lands on the ramp any
	# more, so only the car stays live.
	for fill in [Palette.CAR]:
		assert_gt(_contrast(Palette.INK_ON_LIGHT, fill), _contrast(Palette.APP_BG, fill),
			"INK_ON_LIGHT must out-read the page colour on every fill it sits on")

# -------------------------------------------------------------- patience --

# The idle-bar test lived here. It pinned PATIENCE_IDLE against BAR_TRACK -- the
# grey a VACANT floor's gutter bar was painted. That bar is gone (the shell
# scenery says "nothing is here" better than a grey stripe did) and the pigment
# went with it, so there is nothing left to assert.

# --------------------------------------------------------- affordability --

func test_an_unaffordable_price_is_dim_but_not_gone() -> void:
	# Deliberately low: "you cannot buy this" should recede. It has crossed from
	# dim into ABSENT twice -- 1.86:1 on the dark theme, and 1.29:1 on the light
	# one, where the player simply could not see "+ BUILD FLOOR $200".
	#
	# Measured against GHOST_BG, because that is what these are drawn on: the
	# ghost floor band and the empty shaft slot. The earlier version of this
	# test measured against APP_BG and passed at 2.03 while the real, darker
	# surface underneath was at 1.29 -- a green test over an invisible label.
	# Assert against the surface a thing LANDS on, not the one nearby.
	var c := _contrast(Palette.AFFORD_OFF, Palette.GHOST_BG)
	assert_gt(c, 1.8, "an unaffordable price must still be legible")
	assert_lt(c, 3.0, "an unaffordable price must not look purchasable")

func test_an_affordable_price_outranks_an_unaffordable_one() -> void:
	assert_gt(_contrast(Palette.AFFORD, Palette.GHOST_BG), 4.0,
		"an affordable price must read clearly on the ghost band")
	assert_gt(_contrast(Palette.AFFORD, Palette.GHOST_BG),
		_contrast(Palette.AFFORD_OFF, Palette.GHOST_BG),
		"affordable must be louder than unaffordable")

func test_the_cap_notice_reads_on_the_ghost_band() -> void:
	# "CAP REACHED -- REBUILD" replaces the price in the same band, so it lands
	# on the same surface and needs the same check.
	assert_gt(_contrast(Palette.CAP_REACHED, Palette.GHOST_BG), 3.0,
		"the cap notice must read on the ghost band")

# -------------------------------------------------------------- traffic --

func test_the_three_traffic_series_are_three_colours() -> void:
	# These are thin strokes and they overlap, so separating them by lightness
	# alone fails: two series that differ only in chroma read as one series with
	# a light end. The draft this pins against used a sand at hue 40 against the
	# gold's 37 -- three degrees, i.e. "gold and pale gold".
	var series := {
		"inbound": Palette.TRAFFIC_IN,
		"outbound": Palette.TRAFFIC_OUT,
		"interfloor": Palette.TRAFFIC_INTER,
	}
	var names := series.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			assert_gt(_hue_gap(series[names[i]], series[names[j]]), 40.0,
				"%s and %s must differ in hue" % [names[i], names[j]])

func test_every_traffic_series_reads_on_the_panel() -> void:
	for c in [Palette.TRAFFIC_IN, Palette.TRAFFIC_OUT, Palette.TRAFFIC_INTER]:
		assert_gt(_contrast(c, Palette.PANEL_BG), 4.5, "traffic series on PANEL_BG")

# ------------------------------------------------------------------ people --

## Every figure lands on TWO grounds -- cream in the hall, mid teal in the car --
## so each pigment is measured against both. 1.2 rather than 3:1 because these
## are decorative fills, not information: it is the same floor the idle tenant
## bar already uses. A stated requirement with no test is what put AFFORD_OFF on
## screen at 1.29:1 with a green suite.
const DECOR_MIN := 1.2

func test_shirts_separate_from_each_other() -> void:
	for i in Palette.PERSON_SHIRTS.size():
		for j in range(i + 1, Palette.PERSON_SHIRTS.size()):
			assert_gt(_contrast(Palette.PERSON_SHIRTS[i], Palette.PERSON_SHIRTS[j]),
				DECOR_MIN, "shirts %d and %d read as one colour" % [i, j])

func test_skins_separate_from_each_other() -> void:
	for i in Palette.PERSON_SKINS.size():
		for j in range(i + 1, Palette.PERSON_SKINS.size()):
			assert_gt(_contrast(Palette.PERSON_SKINS[i], Palette.PERSON_SKINS[j]),
				DECOR_MIN, "skins %d and %d read as one colour" % [i, j])

func test_every_shirt_separates_from_every_skin() -> void:
	# The torso/head boundary is an edge inside a 14x22 figure.
	for shirt in Palette.PERSON_SHIRTS:
		for skin in Palette.PERSON_SKINS:
			assert_gt(_contrast(shirt, skin), DECOR_MIN, "head vanishes into torso")

func test_every_shirt_separates_from_the_legs() -> void:
	for shirt in Palette.PERSON_SHIRTS:
		assert_gt(_contrast(shirt, Palette.PERSON_LEGS), DECOR_MIN)

func test_every_person_pigment_reads_on_both_grounds() -> void:
	# The hall is cream and the car is mid teal. A pigment tuned against one and
	# drawn on the other is the AFFORD_OFF story.
	for c in Palette.PERSON_SHIRTS + Palette.PERSON_SKINS:
		assert_gt(_contrast(c, Palette.APP_BG), DECOR_MIN, "lost on the page")
		assert_gt(_contrast(c, Palette.CAR), DECOR_MIN, "lost on the car")

func test_the_badge_reads_on_both_grounds_and_carries_its_glyph() -> void:
	assert_gt(_contrast(Palette.BADGE_BG, Palette.APP_BG), 3.0, "badge on the page")
	assert_gt(_contrast(Palette.BADGE_BG, Palette.CAR), 3.0, "badge on the car")
	assert_gt(_contrast(Palette.BADGE_INK, Palette.BADGE_BG), 4.5, "the glyph")

func test_the_patience_ramp_reads_on_the_person_bar_track_at_every_point() -> void:
	# The ramp on BAR_TRACK measures 1.09:1 at full green -- quieter than the grey
	# that used to mean "nobody is here". The person's bar is the only patience
	# signal a stranger carries, so it gets its own dark track and the WHOLE lerp
	# is checked, not just the ends.
	for i in range(21):
		var t := float(i) / 20.0
		var fill := Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, t)
		assert_gt(_contrast(fill, Palette.PERSON_BAR_TRACK), 3.0,
			"patience is invisible at t=%.2f" % t)

func test_a_pip_reads_lit_hollow_and_against_the_car() -> void:
	assert_gt(_contrast(Palette.PIP_LIT, Palette.PERSON_BAR_TRACK), 3.0, "lit vs hollow")
	assert_gt(_contrast(Palette.PERSON_BAR_TRACK, Palette.CAR), 3.0,
		"a hollow pip against the car body")

## An outlined figure is separated from ANY background, which is what lets floor
## scenery use colours this palette does not control. Measured against the
## generated apartments art, a rust shirt on a rust door was 1.07 -- invisible.
func test_an_outlined_figure_reads_against_every_possible_background() -> void:
	var fills: Array[Color] = []
	fills.append_array(Palette.PERSON_SHIRTS)
	fills.append_array(Palette.PERSON_SKINS)
	fills.append(Palette.PERSON_LEGS)
	fills.append(Palette.BADGE_BG)
	fills.append(Palette.PERSON_BAR_TRACK)
	# Sweep every luminance a background could have, not a sample of pigments.
	for i in range(101):
		var bg := Color(1, 1, 1).lerp(Color(0, 0, 0), float(i) / 100.0)
		for fill in fills:
			# Separated if EITHER the outline clears the ground, or the fill does.
			var best: float = maxf(_contrast(Palette.PERSON_OUTLINE, bg),
				_contrast(fill, bg))
			assert_gt(best, 1.2,
				"a figure vanishes on a background at step %d" % i)
