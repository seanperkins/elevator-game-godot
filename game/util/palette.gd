class_name Palette
extends RefCounted

## Every colour the game draws, in one place.
##
## The theme is the mid-century travel poster in `brand/art/` -- deep teal
## ground, terracotta cars, cream ink, gold and vermilion for the two things
## that are urgent. Before this file the palette was 41 hex literals spread
## across ten scripts, and a retheme meant finding all of them.
##
## TWO TIERS, on purpose:
##
##   PIGMENTS are named for what they ARE. They are the poster's ink set, and
##   nothing outside this file should reference them.
##   ROLES are named for what they DO. Every call site uses these.
##
## The split is what makes the theme cheap to change. Re-mixing a pigment moves
## everything painted with it; re-pointing a role changes one thing everywhere
## it appears, without touching a single call site. A flat list of 41 constants
## would give the second and not the first.
##
## CONTRAST IS PART OF THE DESIGN, not a nicety applied afterwards. Every ratio
## below is measured (WCAG relative luminance) against the surface the thing is
## actually drawn on, and the value was chosen to match what the old dark-blue
## palette DID rather than to hit a generic target -- a "dim" label that stops
## being readable is a bug, and a "dim" label promoted to full contrast breaks
## the hierarchy just as badly. Ratios are quoted per role below.

# ---------------------------------------------------------------- pigments --
# The poster's ink set. Do not reference these outside this file: a call site
# that says TERRACOTTA cannot be re-themed, one that says CAR can.

const TEAL_INK := Color("0d1f21")     ## nearly black, the bottom of the ground
const TEAL_DOOR := Color("17303a")
const TEAL_SHADOW := Color("18302f")
const TEAL_DEEP := Color("1f3a3d")    ## the ground itself
const TEAL_MID := Color("24403f")
const TEAL_LIGHT := Color("2a4a4d")
const TEAL_RULE := Color("3a5a5c")
const TEAL_SEAT := Color("3a6b6e")
const SKY := Color("6fb3b8")

const CREAM := Color("e5d9b5")
const SAGE_PALE := Color("a8bdb0")
const SAGE := Color("9db3a6")
const SAGE_DIM := Color("6f8a80")
const SLATE_IDLE := Color("3f4f4a")

const ROSE := Color("c98f9c")
const GOLD := Color("e0a33e")
const TERRACOTTA := Color("d98e5a")
const VERMILION := Color("d1553a")
const OLIVE := Color("9ec46f")
const BROWN_DARK := Color("2b1a12")
const BROWN_DIM := Color("7d6b52")

# ---------------------------------------------------------------- surfaces --
# A ladder from the darkest ground up. Keep them in this order: the board reads
# as depth only because each layer sits a step lighter than the one behind it.

## Behind everything -- the HUD strip and the board's own backdrop.
const APP_BG := TEAL_DEEP
## Full-screen overlays: management, prestige, the dev panel.
const PANEL_BG := TEAL_SHADOW
## A card floating ON an overlay, and the floor panel's body.
const CARD_BG := TEAL_MID
## Dims the board behind FloorPanel. Alpha carried from the old 0.62: enough to
## push the board back, not so much that you lose the floor you just tapped.
const SCRIM := Color("0d1f21", 0.62)
## A shaft's rail, and an empty (unbought) shaft slot -- deliberately the same,
## because an empty slot IS a shaft you have not paid for yet.
const SHAFT_BG := TEAL_MID
## The ghost floor and ghost shaft: one step lighter than SHAFT_BG so "could
## exist" reads as nearer than "does exist" without needing an outline.
const GHOST_BG := TEAL_LIGHT
## The hairline at the top of a floor band. Without it 40 floors read as one
## field -- see FloorRow._ready.
const RULE := TEAL_RULE
## The unfilled part of a crowd bar.
const BAR_TRACK := TEAL_SHADOW

# --------------------------------------------------------------------- ink --

## Primary text on any dark surface. 8.62:1 on APP_BG.
const INK := CREAM
## The floor number in the gutter. 6.11:1 on APP_BG -- the old palette's floor
## number measured 5.98:1 on the old board, so this is the same weight.
const INK_FLOOR := SAGE_PALE
## Secondary notes under a control. 6.28:1 on PANEL_BG (old: 5.14:1).
const INK_MUTED := SAGE
## Tertiary labels -- row captions, units. 3.74:1 on PANEL_BG (old: 3.17:1).
## Dimmer than INK_MUTED on purpose; the gap IS the hierarchy.
const INK_FAINT := SAGE_DIM
## Ink on a LIGHT fill: the car, and the patience chips. A warm near-black
## rather than a neutral one, so it belongs to the poster.
##
## This is the role the first theme pass got wrong. It painted cream on the
## terracotta car, which measures 2.14:1 -- the floor number on a moving car,
## unreadable. Dark brown on terracotta is 6.33:1, and the old palette's dark
## ink on the old blue car was 8.35:1, so this restores the intent.
const INK_ON_LIGHT := BROWN_DARK

# ------------------------------------------------------------------ the car --

## The car itself. Terracotta is the poster's one warm mass against the teal,
## and the car is the thing the player's eye must track.
const CAR := TERRACOTTA
## An empty seat in the rack.
const SEAT_FREE := TEAL_SEAT
## The doors, translucent so the seat rack stays readable while shut -- see
## ShaftColumn.DOOR_COLOUR's docstring for why that matters.
const DOOR := Color("17303a", 0.55)

# ----------------------------------------------------------- affordability --

## A price you can pay. 6.11:1 on APP_BG.
const AFFORD := OLIVE
## A price you cannot. 2.37:1 on APP_BG -- low BY DESIGN, and measured against
## the old palette's 2.31:1 for the same state. The first theme pass used a
## brown at 1.86:1, which crossed from "dim" into "not there".
const AFFORD_OFF := BROWN_DIM
## The build cap: not a price, a wall. 5.48:1 on APP_BG.
const CAP_REACHED := GOLD

# --------------------------------------------------------------- patience --
# The ramp a waiting passenger walks down. PATIENCE_LOW -> PATIENCE_OK is
# lerped, so BOTH ends -- and everything between -- must stay light enough for
# INK_ON_LIGHT to read on top. Measured across the ramp the worst point is
# 4.03:1, at the vermilion end.

const PATIENCE_OK := OLIVE
const PATIENCE_LOW := VERMILION
## Nobody waiting: the bar is present but inert, so it sits barely above its
## own track (1.62:1, against the old palette's 1.50:1).
const PATIENCE_IDLE := SLATE_IDLE

# ---------------------------------------------------------------- traffic --
# DaySparkline's three series. These must separate from each other by HUE, not
# just lightness -- they are thin strokes, and they overlap, so two series that
# differ only in chroma read as one series with a light end.
#
# That is exactly what the first draft did: it used a sand for INTER, which sits
# at hue 40 against GOLD's 37 -- three degrees apart, i.e. "gold and pale gold".
# Clay rose is 51 degrees off the gold and 162 off the sky, and teal/gold/rose
# is the poster's own three-way split.

const TRAFFIC_IN := SKY          ## incoming visitors, up      (hue 184)
const TRAFFIC_OUT := GOLD        ## leavers, down              (hue  37)
const TRAFFIC_INTER := ROSE      ## neither, blunt             (hue 347)

# ------------------------------------------------------------------ theme --

## The DEFAULT colour of text, applied once at the root so it is inherited.
##
## Without this, a Label that nobody explicitly coloured draws in Godot's stock
## WHITE -- and 16 of the game's 31 text nodes were in exactly that state, which
## is why the panels read as half-themed: the upgrade names, the prices and the
## money counter were never part of the palette at all.
##
## Colouring all 16 by hand would work once and then rot, because the next Label
## anyone adds starts white again. A theme makes cream the DEFAULT and leaves
## add_theme_color_override for the deliberate exceptions -- the dark ink on the
## car and on the patience chips, which still win, because a node override beats
## an inherited theme.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	# A Button has four states and inherits NONE of them from Label. Left unset,
	# a button reverts to white the moment the pointer touches it.
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CAP_REACHED)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", AFFORD_OFF)
	return t
## The now-marker, a wash over whatever it crosses.
const TRAFFIC_NOW := Color("e5d9b5", 0.18)
