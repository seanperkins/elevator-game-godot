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
	# The hierarchy IS the gap. Any two tiers that land on the same luminance
	# read as one tier, and the panels lose their primary/secondary structure
	# even though every individual label still passes a contrast check.
	var tiers := [Palette.INK, Palette.INK_FLOOR, Palette.INK_MUTED, Palette.INK_FAINT]
	for i in range(tiers.size() - 1):
		assert_gt(_relative_luminance(tiers[i]), _relative_luminance(tiers[i + 1]),
			"ink tier %d must be brighter than tier %d" % [i, i + 1])

func test_every_ink_reads_on_the_surface_it_is_drawn_on() -> void:
	assert_gt(_contrast(Palette.INK, Palette.APP_BG), 4.5, "INK on APP_BG")
	assert_gt(_contrast(Palette.INK_FLOOR, Palette.APP_BG), 4.5, "floor number on APP_BG")
	assert_gt(_contrast(Palette.INK_MUTED, Palette.PANEL_BG), 4.5, "notes on PANEL_BG")
	# The faint tier is allowed to be dimmer than 4.5 -- it is tertiary -- but
	# not so dim it stops being text.
	assert_gt(_contrast(Palette.INK_FAINT, Palette.PANEL_BG), 3.0, "faint labels on PANEL_BG")

# -------------------------------------------------------------- surfaces --

func test_the_surface_ladder_ascends() -> void:
	# The board reads as depth only because each layer sits a step lighter than
	# the one behind it. Reordering any pair inverts the figure and the ground.
	var ladder := [Palette.PANEL_BG, Palette.APP_BG, Palette.CARD_BG,
		Palette.GHOST_BG, Palette.RULE]
	for i in range(ladder.size() - 1):
		assert_lt(_relative_luminance(ladder[i]), _relative_luminance(ladder[i + 1]),
			"surface %d must be darker than surface %d" % [i, i + 1])

# ------------------------------------------------------------- the car --

func test_the_car_label_reads_against_the_car() -> void:
	# The regression this exists for: the first theme pass painted cream on the
	# terracotta car, which measures 2.14:1 -- a floor number, on the one thing
	# on screen that moves, that you cannot read.
	assert_gt(_contrast(Palette.INK_ON_LIGHT, Palette.CAR), 4.5,
		"the car's floor number must read against the car body")

# -------------------------------------------------------------- patience --

func test_the_patience_ramp_carries_its_label_at_every_point() -> void:
	# PassengerSprite lerps LOW -> OK and draws INK_ON_LIGHT on top, so it is
	# not enough for the two ENDS to work. A ramp between two individually-fine
	# colours can still pass through a midpoint that swallows the label.
	for i in range(21):
		var t := float(i) / 20.0
		var body := Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, t)
		assert_gt(_contrast(Palette.INK_ON_LIGHT, body), 3.5,
			"ink must read on the patience ramp at t=%.2f" % t)

func test_the_idle_bar_is_present_but_inert() -> void:
	# A vacant floor's bar is not information, it is absence of it. It has to be
	# visible against its own track and must NOT compete with a live bar.
	var c := _contrast(Palette.PATIENCE_IDLE, Palette.BAR_TRACK)
	assert_gt(c, 1.2, "the idle bar must be distinguishable from its track")
	assert_lt(c, 2.5, "the idle bar must not read as loud as a live one")

# --------------------------------------------------------- affordability --

func test_an_unaffordable_price_is_dim_but_not_gone() -> void:
	# Deliberately low: "you cannot buy this" should recede. The first theme
	# pass took it to 1.86:1, which crossed from dim into absent, and the
	# player loses the price as well as the affordability.
	var c := _contrast(Palette.AFFORD_OFF, Palette.APP_BG)
	assert_gt(c, 2.0, "an unaffordable price must still be legible")
	assert_lt(c, 3.5, "an unaffordable price must not look purchasable")

func test_an_affordable_price_outranks_an_unaffordable_one() -> void:
	assert_gt(_contrast(Palette.AFFORD, Palette.APP_BG),
		_contrast(Palette.AFFORD_OFF, Palette.APP_BG),
		"affordable must be louder than unaffordable")

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
