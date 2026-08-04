class_name Palette
extends RefCounted

## Every colour the game draws, in one place.
##
## The theme is the mid-century travel poster in `brand/art/dir3_in_game.png`.
## The pigments below are SAMPLED from that mockup, not invented to resemble it
## -- the file is the reference, and where code and mockup disagree the mockup
## wins.
##
## TWO TIERS, on purpose:
##
##   PIGMENTS are named for what they ARE. Nothing outside this file should
##   reference them.
##   ROLES are named for what they DO. Every call site uses these.
##
## The split is what makes the theme cheap to change. Re-mixing a pigment moves
## everything painted with it; re-pointing a role changes one thing everywhere,
## without touching a call site. This file has now been re-pointed once -- from
## a dark ground to a light one, and with the car and shaft masses swapped --
## and not one call site changed. That is the whole argument for the split.
##
## THIS IS A LIGHT THEME, which inverts two things that are easy to get wrong:
##
##   "Dim" means CLOSER TO THE GROUND, and on cream that means LIGHTER. A
##   receding label here is a pale tan; the dark palette's dim brown would be
##   darker than the body text and would advance instead of recede.
##   The surface ladder DESCENDS in luminance as layers come forward, where the
##   dark palette's ascended.
##
## Measured: the mockup's median luma is ~206, with 42% of pixels above 180. The
## dark palette measured 52.5 and 0.0% above 180 -- which is why no amount of
## sprite art could have closed the gap on its own.

# ---------------------------------------------------------------- pigments --
# Sampled from brand/art/dir3_in_game.png. Do not reference outside this file.

## The page the whole game sits on -- 17.6% of the mockup, its commonest colour.
const CREAM := Color("f7eed1")
const CREAM_PALE := Color("fbf4dc")
const TAN := Color("e7d5ad")
const TAN_DEEP := Color("d5bd92")
## One step past TAN_DEEP, so the hairline and the ghost band are not the same
## colour. They were, in the first light draft -- two ladder rungs at identical
## luminance, which the surface test caught as a zero-size step.
const TAN_RULE := Color("c0a677")

## Teal is an ACCENT here (~10% of the mockup), not the ground. It WAS the
## ground in the dark palette, which is most of why that read as another game.
const TEAL := Color("649a8c")        ## the car body
const TEAL_DARK := Color("306b65")   ## its shadow side
const TEAL_INK := Color("1f3f3c")    ## dark enough to be text

## The shafts: in the mockup these are the dark vertical masses, and the CARS
## are the pale teal capsules riding inside them. The dark palette had this
## exactly backwards -- teal shaft, terracotta car.
const RUST := Color("9d4227")
const RUST_LIGHT := Color("c76d48")

const GOLD := Color("cc9737")
const VERMILION := Color("c4462c")
const BROWN_DARK := Color("2b1a0c")
const BROWN_FAINT := Color("bda67e")

## The people. EIGHT pigments on eight distinct luminance rungs, spaced 1.25
## apart and dodging the APP_BG and CAR bands -- because contrast is luminance
## only, so eight colours that merely differ in hue would fail their own test.
## A first attempt at plausible mid-century colours failed six constraints; this
## ladder was solved rather than picked, and the tightest pair measures 1.24.
const SHIRT_TEAL := Color("193337")
const SHIRT_PLUM := Color("5a3144")
const SHIRT_SLATE := Color("404d5f")
const SHIRT_RUST := Color("8e4630")
const SHIRT_GOLD := Color("907538")
const SKIN_DEEP := Color("8e5e3c")
const SKIN_MID := Color("d09562")
const SKIN_PALE := Color("ceb092")

# ---------------------------------------------------------------- surfaces --
# A ladder from the page FORWARD. On a light theme each layer that comes
# forward sits a step DARKER, the opposite of the dark palette -- but the
# requirement is unchanged: adjacent layers must separate, or the board
# flattens into one field.

## The page behind everything.
const APP_BG := CREAM
## Full-screen overlays: management, prestige, the dev panel. Paper laid on the
## page, so a shade brighter than it.
const PANEL_BG := CREAM_PALE
## A card floating on an overlay, and the floor panel's body.
const CARD_BG := TAN
## Dims the board behind FloorPanel. A scrim on a LIGHT ground has to work
## harder to read as "pushed back" than one on a dark ground did.
const SCRIM := Color("1f3f3c", 0.45)
## A shaft's rail. NOT the empty slot next to it: an unbought shaft uses
## GHOST_BG, like the ghost floor does.
##
## These were the same colour, on the argument that "an empty slot IS a shaft
## you have not paid for yet". On the dark theme both were dark and it passed
## unnoticed; on cream the rust is the heaviest mass on screen, so an unbought
## slot rendered as a fully built shaft while the ghost FLOOR directly above it
## correctly receded. Two ghosts, two different answers.
const SHAFT_BG := RUST
## The lit edge of a shaft, where the mockup catches light down both sides.
const SHAFT_EDGE := RUST_LIGHT
## The ghost floor and ghost shaft. "Could exist" must read quieter than
## anything real, which on a light ground means closer to the page.
const GHOST_BG := TAN_DEEP
## The hairline at the top of a floor band.
const RULE := TAN_RULE
## The unfilled part of a crowd bar.
const BAR_TRACK := TAN_DEEP

# --------------------------------------------------------------------- ink --
# Dark on pale. The tiers are ordered by CONTRAST against the ground, not by
# luminance: contrast ordering is what survives a theme inversion, and the test
# pins it that way for exactly that reason.

## Primary text.
const INK := TEAL_INK
## The floor number in the gutter.
const INK_FLOOR := Color("2b5d56")
## Secondary notes under a control.
const INK_MUTED := Color("4d6b61")
## Tertiary labels -- row captions, units.
const INK_FAINT := Color("768a7f")
## Dark ink on a COLOURED fill -- the patience chips and the car.
##
## Both are mid-luminance, which is the worst case for text: on the mockup's
## pale teal car, cream measures 2.77:1 and this brown 5.21:1, so dark wins on
## a fill that a dark theme would have wanted pale ink for. The mockup cannot
## settle it -- its car carries no floor number at all.
const INK_ON_LIGHT := BROWN_DARK

# ------------------------------------------------------------------ the car --

## The car body: the pale teal capsule the mockup rides inside each rust shaft.
const CAR := TEAL
## The band across the car -- the doors' seam, pale against the body.
const CAR_BAND := CREAM_PALE
## The doors, translucent so the figures stay readable while shut -- see
## ShaftColumn.DOOR_COLOUR's docstring for why that matters.
const DOOR := Color("306b65", 0.55)

# ----------------------------------------------------------- affordability --

## A price you can pay.
##
## Measured against GHOST_BG, which is where both of these are actually drawn
## -- the ghost floor band and the empty shaft slot. Tuning them against the
## page was the bug: the band is darker than the page, so AFFORD_OFF measured
## 2.03:1 there but only 1.29:1 where it lands, and "+ BUILD FLOOR $200" was
## effectively not on screen.
const AFFORD := Color("3d5c14")
## A price you cannot. Low contrast BY DESIGN -- and on a light ground "low"
## means PALE -- but "dim" and "absent" are different, and this crossed that
## line once already on the dark theme too.
const AFFORD_OFF := Color("9a8258")
## The build cap: not a price, a wall.
const CAP_REACHED := RUST

# --------------------------------------------------------------- patience --
# The ramp a waiting passenger walks down. PATIENCE_LOW -> PATIENCE_OK is
# lerped and INK_ON_LIGHT is drawn on top, so BOTH ends -- and everything
# between -- must stay light enough to carry it.

const PATIENCE_OK := Color("9ec46f")
const PATIENCE_LOW := Color("e07a52")
## Nobody waiting: present but inert, so it sits just off its own track.
const PATIENCE_IDLE := Color("ab9670")

# ---------------------------------------------------------------- people --

## A person's shirt and skin, chosen by PersonSprite from the passenger's own
## trip. FIVE and THREE, not four and three: the sizes are coprime to the tint
## key's surviving coefficients, which is what stops a whole traffic class
## wearing one colour -- see the design spec's 2.3.
const PERSON_SHIRTS: Array[Color] = [
	SHIRT_TEAL, SHIRT_PLUM, SHIRT_SLATE, SHIRT_RUST, SHIRT_GOLD]
const PERSON_SKINS: Array[Color] = [SKIN_DEEP, SKIN_MID, SKIN_PALE]
const PERSON_LEGS := BROWN_DARK

## The badge above a person's head. It lands on TWO grounds -- cream in the hall
## and mid teal in the car -- so it is measured against both: 9.87:1 and 3.57:1.
const BADGE_BG := TEAL_INK
const BADGE_INK := CREAM_PALE

## The track under a person's patience bar, and under each pip.
##
## NOT BAR_TRACK, which the gutter's tenant bar uses. The patience ramp measures
## 1.09:1 against BAR_TRACK at full green -- quieter than PATIENCE_IDLE, the
## colour that means nobody is here. The tenant bar survives that pairing because
## it drains by HEIGHT in a fixed position; a person's bar is 4x22 and its
## fill/track boundary IS the encoding. On this track the ramp is 5.63:1 at red
## and 8.42:1 at green.
const PERSON_BAR_TRACK := BROWN_DARK
## A pip with a rider in it. 15.19:1 on the track.
const PIP_LIT := CREAM_PALE

# ---------------------------------------------------------------- traffic --
# DaySparkline's three series. They separate by HUE, not lightness -- they are
# thin strokes and they overlap, so two series differing only in chroma read as
# one series with a light end. On a light ground they must also be DARK enough
# to show, which the dark palette's pale series would not be.

const TRAFFIC_IN := Color("2a707a")    ## incoming visitors, up
const TRAFFIC_OUT := Color("8f5a1a")   ## leavers, down
const TRAFFIC_INTER := Color("83405a") ## neither, blunt
## The now-marker, a wash over whatever it crosses.
const TRAFFIC_NOW := Color("1f3f3c", 0.18)

# ------------------------------------------------------------------ theme --

## The DEFAULT colour of text, applied once at the root so it is inherited.
##
## Without this a Label nobody explicitly coloured draws in Godot's stock WHITE,
## which was merely wrong on the dark ground and is invisible on cream. 16 of
## the game's 31 text nodes were in that state.
##
## A theme makes ink the DEFAULT and leaves add_theme_color_override for the
## deliberate exceptions, which still win.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	# A Button has four states and inherits NONE of them from Label. Left unset,
	# a button reverts to white the moment the pointer touches it.
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CAP_REACHED)
	t.set_color("font_focus_color", "Button", INK)
	# NOT AFFORD_OFF, which is the mistake this replaced. ManagementView sets
	# `disabled = not can_afford(cost)` on every upgrade row, so at $0 the whole
	# panel is disabled -- and painting that with the deliberately-recessive
	# "cannot buy" colour double-dims it, because Godot already dims a disabled
	# button. Measured on the light theme it produced pale tan on tan: a panel
	# of prices nobody could read. Disabled must stay LEGIBLE; the affordability
	# signal is the greyed state itself, not a second colour.
	t.set_color("font_disabled_color", "Button", INK_MUTED)

	# Buttons also need a BOX. Without one they fall back to Godot's stock grey
	# slab, which merely looked out of place on the dark ground and looks like a
	# rendering bug on cream. The mockup's controls are rounded capsules, so
	# that is what these are.
	t.set_stylebox("normal", "Button", _capsule(CARD_BG))
	t.set_stylebox("hover", "Button", _capsule(TAN_DEEP))
	t.set_stylebox("pressed", "Button", _capsule(TAN_RULE))
	t.set_stylebox("focus", "Button", _capsule(CARD_BG))
	t.set_stylebox("disabled", "Button", _capsule(PANEL_BG))

	# Everything else that ships with a stylebox of its own. A theme that covers
	# only Label and Button leaves these on Godot's stock DARK panel chrome,
	# which is how a slab of grey ended up behind the management readout
	# (PanelContainer) and the floor panel's satisfaction bar (ProgressBar).
	# Neither is a Label or a Button, so neither inherited any of the above.
	t.set_stylebox("panel", "PanelContainer", _capsule(CARD_BG))
	t.set_stylebox("background", "ProgressBar", _capsule(BAR_TRACK))
	t.set_stylebox("fill", "ProgressBar", _capsule(PATIENCE_OK))
	return t

## A rounded pill in one fill. Content margins are left at Godot's defaults on
## purpose: the board's touch targets are positioned by hand against the UI
## spec's coordinate table, and a stylebox that added padding would move them.
static func _capsule(fill: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(10)
	return b
