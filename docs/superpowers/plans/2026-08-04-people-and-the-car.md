# People and the Car Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the labelled-square passenger with a drawn figure carrying a badge and a patience bar, put riders standing in ranks on the floor of a bigger car, and give the car a pip-strip load gauge.

**Architecture:** Two new pure-geometry classes (`CarRack`, joining `ChipGrid`) own all layout and are unit-tested headlessly; one new `Control` (`PersonSprite`) owns all drawing and exposes `parts()` so its geometry is testable without a viewport. `ShaftColumn` and `FloorRow` become thin consumers. Three board constants move, which is done **first** so every later task is built against the final geometry.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.7.1.

**Spec:** `docs/superpowers/specs/2026-08-04-passenger-and-car-design.md` — read §4.1.1 before touching any number.

## Global Constraints

- **Sim never touches the scene tree.** `Passenger` gains **no** field. Tint colours are derived in the view from `origin_floor`/`destination_floor`/`source_floor`.
- **Every geometric claim is derived against the DEVICE board (688 × ~1050), not the 720 × 1184 canvas.** `SafeArea.insets` floors both side insets at `CORNER_MARGIN = 16`; headless returns `Vector4.ZERO`, so the suite runs on the canvas and the game runs on the board. This is the mistake that broke three review rounds.
- **A colour is tested against every surface it lands on.** No new colour ships without a `tests/test_palette.gd` assertion against each ground it is drawn on.
- **No pigment is named outside `game/util/palette.gd`.** Call sites use roles.
- Final constants: `FLOOR_HEIGHT = 120`, `SHAFT_WIDTH = 230`, `FloorRow.STRIP_WIDTH = 144` → `SHAFT_AREA_X = 208`, column 226, **car 220 × 116**.
- Run the whole suite before every commit: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. `-gdir=<file>` and `-ginclude` print "Nothing was run" and exit 0 — a false green.
- Single test file: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_x.gd -gexit`.

---

## File Structure

| file | responsibility |
| --- | --- |
| `view/chip_grid.gd` | **modified.** Packing rule for the hall only; cell becomes a `Vector2`. |
| `view/car_rack.gd` | **new.** All car geometry: rank counts, cell width, slot rects, pip rects, guard bands. `RefCounted`, no scene tree. |
| `view/person_sprite.gd` | **new.** All person drawing; `parts()` and `redraw_count()` are the testable seams. Replaces `passenger_sprite.gd`. |
| `view/passenger_sprite.gd` | **deleted** with its `.uid`. |
| `view/floor_row.gd` | consumer: hall cell, `PersonSprite`, narrower strip. |
| `view/shaft_column.gd` | consumer: pips + ranks via `CarRack`; seat rack deleted. |
| `view/building_view.gd` | the two board constants and their docstrings. |
| `game/util/palette.gd` | eight new pigments, seven new roles, `SEAT_FREE` deleted. |
| `tests/test_board_geometry.gd` | **new.** The device-inset assertions. |
| `tests/test_car_rack.gd`, `tests/test_person_sprite.gd` | **new.** |

---

### Task 1: Move the board constants

Doing this first means every later task is built against the final car size. The seat rack survives this task unchanged — at 220 × 116 `ChipGrid` lays out all 12 seats — so the only failures are fixtures that hard-code the old geometry.

**Files:**
- Modify: `view/building_view.gd:28-39` (constants + docstrings), `view/floor_row.gd:39`
- Modify: `tests/test_board_input.gd:143`, `:199-209`, `:245-250`
- Create: `tests/test_board_geometry.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `BuildingView.FLOOR_HEIGHT = 120.0`, `BuildingView.SHAFT_WIDTH = 230.0`, `FloorRow.STRIP_WIDTH = 144.0`, `FloorRow.STRIP_RIGHT = 208.0`. Every later task depends on these.

- [ ] **Step 1: Write the failing geometry test**

Create `tests/test_board_geometry.gd`:

```gdscript
extends GutTest

## The board is NOT the canvas. SafeArea floors both side insets at
## CORNER_MARGIN, so a phone's board is 688 wide where the headless suite sees
## 720. Three review rounds broke on numbers derived at 720 and asserted at 720;
## these assert at both widths and require them to AGREE.

const CANVAS_W := 720.0

func _visible_shafts_at(board_w: float) -> int:
	return maxi(int((board_w - BuildingView.SHAFT_AREA_X) / BuildingView.SHAFT_WIDTH), 1)

func device_board_width() -> float:
	return CANVAS_W - 2.0 * SafeArea.CORNER_MARGIN

func test_two_shaft_columns_on_the_device_board() -> void:
	# The number that ships. At SHAFT_WIDTH 240 this is 1, while the headless
	# assertion below still reads 2 -- which is exactly how a one-column board
	# would have shipped green.
	assert_eq(_visible_shafts_at(device_board_width()), 2)

func test_two_shaft_columns_on_the_canvas_too() -> void:
	assert_eq(_visible_shafts_at(CANVAS_W), 2)

func test_the_two_surfaces_agree() -> void:
	# The property worth having: a width whose column count does not depend on
	# which surface you measure.
	assert_eq(_visible_shafts_at(device_board_width()),
		_visible_shafts_at(CANVAS_W), "device and canvas must agree")

func test_the_column_count_has_slack_against_a_deeper_inset() -> void:
	# 240 tiled 480 exactly and had none, so any inset at all cost a column.
	var viewport := device_board_width() - BuildingView.SHAFT_AREA_X
	assert_gte(viewport - 2.0 * BuildingView.SHAFT_WIDTH, 6.0,
		"at least 6 units spare beyond two columns")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_geometry.gd -gexit`
Expected: FAIL — at `SHAFT_WIDTH = 160` the device board gives `int(448/160) = 2` (passes) but the canvas gives `int(480/160) = 3`, so `test_two_shaft_columns_on_the_canvas_too` and `test_the_two_surfaces_agree` both fail.

- [ ] **Step 3: Move the constants**

In `view/building_view.gd`, replace the `SHAFT_WIDTH` block at `:28-34`:

```gdscript
## Two columns across the shaft viewport, on the DEVICE board -- not the canvas.
## SafeArea floors both side insets at CORNER_MARGIN 16, so the board is 688
## wide on a phone and 720 only headless; 230 gives two columns on both, with 20
## units of slack. 240 gives two on the canvas and ONE on the device, which is
## how a one-column board nearly shipped with a green suite.
##
## The column draws at 226 and the car at 220, which is what makes a two-digit
## destination badge 13.1pt at every capacity from 4 to 12 -- see the design
## spec's 4.3. The people strip yields 32 units to pay for it.
const SHAFT_WIDTH := 230.0
```

and the `FLOOR_HEIGHT` block at `:36-39`:

```gdscript
## Every floor, always. 120 units is 65.5pt at the 0.546 iPhone scale, and it is
## sized by the CAR rather than by the touch floor: a font-24 line box needs a
## 30-unit badge, so two ranks of riders need 2 + 8 + 52 + 52 = 114, which fits
## a 116-unit car. At 112 the badge falls to 27 and the font to 21.
const FLOOR_HEIGHT := 120.0
```

In `view/floor_row.gd:39`:

```gdscript
const STRIP_WIDTH := 144.0
```

- [ ] **Step 4: Run the geometry test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_geometry.gd -gexit`
Expected: PASS, 4 tests.

- [ ] **Step 5: Fix the visible-shafts assertion**

`tests/test_board_input.gd:143` reads `assert_eq(view.visible_shafts(), 3, "three columns on a 160-unit pitch")`. Replace:

```gdscript
	assert_eq(view.visible_shafts(), 2, "two columns on a 230-unit pitch")
```

- [ ] **Step 6: Fix the scroll fixture, which now taps off the board**

`tests/test_board_input.gd:199-209` scrolls 300 and taps floors 4, 9, 12. At `FLOOR_HEIGHT 120` on a 20-floor building, floor 4's band centre is `15*120 - 300 + 60 = 1560`, below the 1184-tall board, so that tap reaches nothing. Change the scroll to 700 (`max_scroll` is `20*120 - 1184 = 1216`, so 700 is in range):

```gdscript
	view.scroll_board_by(700.0)
```

New centres: floor 4 → 1160, floor 9 → 560, floor 12 → 200. All on board.

- [ ] **Step 7: Delete the vacuous placeholder test and replace it**

`tests/test_board_input.gd:245-250` (`test_a_tap_on_a_non_trailing_placeholder_does_nothing`) is not fixable by moving its coordinate, and it never tested what it claims. `slot_count() = min(owned + 1, 8)` and `buyable = owned`, so **the only placeholder on screen is always the trailing buyable one** — a non-trailing placeholder is unreachable below the cap. With three visible columns the tap landed past the last slot and hit nothing, passing vacuously; with two it lands on the buyable slot and buys a shaft.

Delete the test and add this in its place, which pins the rule the old one gestured at:

```gdscript
func test_only_the_slot_at_index_owned_takes_a_purchase_tap() -> void:
	# The old test tapped a "non-trailing placeholder", which cannot exist:
	# slot_count is min(owned + 1, MAX_SHAFTS), so the only placeholder is the
	# trailing buyable one. It passed by tapping past the last slot -- empty
	# space -- and inverted the moment two columns filled the viewport.
	var owned: int = root.state.building.cars.size()
	assert_eq(view.slot_count(), mini(owned + 1, Building.MAX_SHAFTS),
		"one placeholder beyond what is owned, capped")
	var before: int = owned
	await do_tap(column_x(0), floor_centre_y(1))
	assert_eq(root.state.building.cars.size(), before,
		"slot 0 is a built shaft, not a purchase target")
```

- [ ] **Step 8: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS. If a coordinate test not listed here fails, it is a fixture that hard-codes the old row height — read it before changing it. `tests/test_coords_scroll.gd:10` and `tests/test_pan_gesture.gd:9` both declare their own `const H := 88.0` and build their own `BoardCoords`, so they are synthetic fixtures and **must not** be changed. `tests/test_gesture.gd:5` declares `const H := 29.6` and never reads `FLOOR_HEIGHT` — **do not touch it**; "fixing" it to 56 would loosen the one bound that file exists to hold.

- [ ] **Step 9: Commit**

```bash
git add view/building_view.gd view/floor_row.gd tests/test_board_geometry.gd tests/test_board_input.gd
git commit -m "Size the board from the device, not the canvas"
```

---

### Task 2: The palette roles

**Files:**
- Modify: `game/util/palette.gd`
- Modify: `tests/test_palette.gd:102-111`, `:115-123`

**Interfaces:**
- Consumes: nothing.
- Produces: `Palette.PERSON_SHIRTS: Array[Color]` (5), `Palette.PERSON_SKINS: Array[Color]` (3), `Palette.PERSON_LEGS`, `Palette.BADGE_BG`, `Palette.BADGE_INK`, `Palette.PERSON_BAR_TRACK`, `Palette.PIP_LIT`. `Palette.SEAT_FREE` is **removed**.

- [ ] **Step 1: Write the failing palette tests**

Append to `tests/test_palette.gd`:

```gdscript
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
	# The ramp on BAR_TRACK measures 1.09:1 at full green -- quieter than
	# PATIENCE_IDLE, which is the colour that means nobody is here. The person's
	# bar is the only patience signal a stranger carries, so it gets its own
	# dark track and the WHOLE lerp is checked, not just the ends.
	for i in range(21):
		var t := float(i) / 20.0
		var fill := Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, t)
		assert_gt(_contrast(fill, Palette.PERSON_BAR_TRACK), 3.0,
			"patience is invisible at t=%.2f" % t)

func test_a_pip_reads_lit_hollow_and_against_the_car() -> void:
	assert_gt(_contrast(Palette.PIP_LIT, Palette.PERSON_BAR_TRACK), 3.0, "lit vs hollow")
	assert_gt(_contrast(Palette.PERSON_BAR_TRACK, Palette.CAR), 3.0,
		"a hollow pip against the car body")
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_palette.gd -gexit`
Expected: FAIL — `PERSON_SHIRTS` and the other roles do not exist yet.

- [ ] **Step 3: Add the pigments and roles**

In `game/util/palette.gd`, after the existing pigment block:

```gdscript
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
```

and in the roles section:

```gdscript
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
```

Delete the `SEAT_FREE` constant and its docstring — it named a seat, and there are no seats.

- [ ] **Step 4: Retire the two tests that pin a deleted pairing**

`tests/test_palette.gd:115-123` pins the patience ramp against `INK_ON_LIGHT` because "PassengerSprite … draws INK_ON_LIGHT on top". After this work no text is drawn on the ramp at all. **Delete that test.**

`tests/test_palette.gd:102-111` loops `for fill in [Palette.CAR, Palette.PATIENCE_OK, Palette.PATIENCE_LOW]`. Only `CAR` stays live — the header fallback still draws `INK_ON_LIGHT` there. Reduce the list:

```gdscript
	for fill in [Palette.CAR]:
```

and update its comment to say the patience fills were dropped because no ink lands on the ramp any more.

- [ ] **Step 5: Run to verify the palette tests pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_palette.gd -gexit`
Expected: PASS. `SEAT_FREE`'s removal will break `view/shaft_column.gd:32` — that is expected and fixed in Task 6; if the suite cannot parse, temporarily point `ShaftColumn.SEAT_FREE` at `Palette.PERSON_BAR_TRACK` and leave a `# removed in the pips task` comment.

- [ ] **Step 6: Run the full suite, then commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add game/util/palette.gd tests/test_palette.gd view/shaft_column.gd
git commit -m "Give the people their own pigments, and the patience bar a track it reads on"
```

---

### Task 3: ChipGrid takes a cell, not a square

**Files:**
- Modify: `view/chip_grid.gd:27,48-70` and its class docstring at `:4-25`
- Modify: `view/floor_row.gd:110-116`, `view/shaft_column.gd:185-186`
- Modify: `tests/test_chip_grid.gd:74,75,80,81,100,107,109`

**Interfaces:**
- Consumes: nothing.
- Produces: `ChipGrid.columns_for(width: float, cell_w: float) -> int`, `ChipGrid.rows_for(height: float, cell_h: float) -> int`, `ChipGrid.position_of(index: int, count: int, grid: Vector2i, area: Vector2, cell: Vector2) -> Vector2`. `ChipGrid.SIZE` is **removed**; `GAP` stays 4.0. `shape()` and `fits()` are unchanged.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_chip_grid.gd`:

```gdscript
const CELL := Vector2(20, 40)

func test_a_non_square_cell_packs_by_its_own_axes() -> void:
	# The rule does not change; only what it packs. A 20x40 person cell in the
	# 140-unit strip on a 120-unit row is what the hall now asks for.
	assert_eq(ChipGrid.columns_for(140.0, CELL.x), 6)
	assert_eq(ChipGrid.rows_for(120.0, CELL.y), 2)

func test_the_hall_block_exactly_fills_the_strip() -> void:
	# 6*20 + 5*4 = 140, and the strip is 140. This is an EQUALITY, not slack:
	# any increase to the cell or GAP drops the hall to five columns and ten
	# people, so it fails here rather than on a phone.
	var cols := ChipGrid.columns_for(140.0, CELL.x)
	assert_eq(cols * CELL.x + (cols - 1) * ChipGrid.GAP, 140.0,
		"the rank fills the strip exactly")

func test_position_of_steps_by_the_cell_it_is_given() -> void:
	var grid := ChipGrid.shape(4, 9, 9)
	var area := Vector2(200, 200)
	var a := ChipGrid.position_of(0, 4, grid, area, CELL)
	var b := ChipGrid.position_of(1, 4, grid, area, CELL)
	assert_almost_eq(b.x - a.x, CELL.x + ChipGrid.GAP, 0.01)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chip_grid.gd -gexit`
Expected: FAIL — `columns_for` takes one argument.

- [ ] **Step 3: Change the three signatures**

In `view/chip_grid.gd`, delete `const SIZE := 30.0` and replace `:48-70`:

```gdscript
## How many columns and rows of CELL fit an area, given the gaps between them.
## These take the CELL, never the pitch -- GAP is added here, so handing them
## `cell + GAP` double-counts it.
##
## ZERO is a real answer and must not be floored to one: a caller with less room
## than one cell has to fall back rather than draw a rank that overflows.
static func columns_for(width: float, cell_w: float) -> int:
	return maxi(int((width + GAP) / (cell_w + GAP)), 0)

static func rows_for(height: float, cell_h: float) -> int:
	return maxi(int((height + GAP) / (cell_h + GAP)), 0)

## Top-left of item `index`, with the block centred in the area and each rank
## centred on the block, so a short last rank is not left ragged.
static func position_of(index: int, count: int, grid: Vector2i, area: Vector2,
		cell: Vector2) -> Vector2:
	if grid.x <= 0 or grid.y <= 0:
		return Vector2.ZERO
	var row := index / grid.x
	var col := index % grid.x
	var in_rank := clampi(count - row * grid.x, 1, grid.x)
	var rank_w := float(in_rank) * cell.x + float(in_rank - 1) * GAP
	var block_h := float(grid.y) * cell.y + float(grid.y - 1) * GAP
	return Vector2(
		(area.x - rank_w) * 0.5 + float(col) * (cell.x + GAP),
		(area.y - block_h) * 0.5 + float(row) * (cell.y + GAP))
```

Update the class docstring at `:4-25`: it says "balanced block of **squares**" and "One rule for the hall and for the car". The cell is no longer square and the car is laid out by `CarRack` from Task 4 — say so. Also drop the "a board whose rows lose height as the building grows" clause, which describes the deleted squeeze model, and `columns_for`'s old "a car at the 40-floor cap is 25.6 units tall and a chip is 30" justification.

- [ ] **Step 4: Update the three call sites**

`view/floor_row.gd:110-116` — pass the hall cell (Task 5 replaces this wholesale, so the minimum here is to keep it compiling):

```gdscript
	var cell := Vector2(30, 30)
	var grid := ChipGrid.shape(mini(total, cap),
		ChipGrid.columns_for(area.x, cell.x), ChipGrid.rows_for(area.y, cell.y))
```

and thread `cell` into the `position_of` call below it.

`view/shaft_column.gd:185-186` — likewise, using `SEAT_SIZE`:

```gdscript
	var grid := ChipGrid.shape(capacity,
		ChipGrid.columns_for(area.x, SEAT_SIZE.x), ChipGrid.rows_for(area.y, SEAT_SIZE.y))
```

and thread `SEAT_SIZE` into its `position_of` call.

- [ ] **Step 5: Update the existing ChipGrid tests**

`tests/test_chip_grid.gd:74,75,80,81` reference `ChipGrid.SIZE`. Replace with a local `const SQUARE := 30.0` and pass it, keeping every assertion's meaning:

```gdscript
	assert_eq(ChipGrid.rows_for(SQUARE - 1.0, SQUARE), 0)
	assert_eq(ChipGrid.columns_for(SQUARE - 1.0, SQUARE), 0)
	assert_eq(ChipGrid.rows_for(SQUARE, SQUARE), 1)
	assert_eq(ChipGrid.columns_for(SQUARE, SQUARE), 1)
```

`:100,107,109` pass `ChipGrid.SIZE` to `position_of` — pass `Vector2(SQUARE, SQUARE)` and use `SQUARE` in the arithmetic.

- [ ] **Step 6: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add view/chip_grid.gd view/floor_row.gd view/shaft_column.gd tests/test_chip_grid.gd
git commit -m "Let the packing rule carry a cell that is not a square"
```

---

### Task 4: CarRack — all the car geometry, pure

**Files:**
- Create: `view/car_rack.gd`, `view/car_rack.gd.uid`
- Create: `tests/test_car_rack.gd`, `tests/test_car_rack.gd.uid`

**Interfaces:**
- Consumes: nothing (no scene tree, no `Palette`).
- Produces, all `static`:
  - `CarRack.ranks_for(capacity: int, car_h: float) -> int` — 0, 1 or 2
  - `CarRack.front_count(capacity: int, car_w: float, ranks: int) -> int`
  - `CarRack.cell_width(capacity: int, car_w: float, ranks: int) -> float`
  - `CarRack.slots(capacity: int, car_w: float, car_h: float) -> Array[Rect2]` — front rank first, then back; index order is boarding order
  - `CarRack.pips(capacity: int, car_w: float) -> Array[Rect2]` — empty when they would be unreadable
  - Constants `GAP`, `CELL_MAX`, `CELL_MIN`, `PIP_GAP`, `PIP_MIN`, `PIP_H`, `INSET`, `BADGE_H`, `FIGURE_H`, `BAND`, `ONE_RANK_MIN`, `TWO_RANK_MIN`, `ONE_RANK_CAP`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_car_rack.gd`:

```gdscript
extends GutTest

## The car's geometry, headless. Every number here is from the design spec's
## 4.2 table, which was derived against a 220-unit car -- SHAFT_WIDTH 230 less 4
## for the column and 6 for the car.

const W := 220.0
const H := 116.0

func test_one_rank_up_to_five_then_two() -> void:
	for cap in [4, 5]:
		assert_eq(CarRack.ranks_for(cap, H), 1, "capacity %d is one rank" % cap)
	for cap in [6, 8, 12]:
		assert_eq(CarRack.ranks_for(cap, H), 2, "capacity %d is two ranks" % cap)

func test_the_front_rank_takes_the_extra_rider() -> void:
	assert_eq(CarRack.front_count(7, W, 2), 4, "4 front, 3 behind")
	assert_eq(CarRack.front_count(9, W, 2), 5)
	assert_eq(CarRack.front_count(11, W, 2), 6)

func test_the_cell_matches_the_spec_table_at_every_capacity() -> void:
	# The budget INCLUDES the half-pitch offset, which is what an earlier draft
	# left out -- its back rank left the car by 15 units at capacity 10.
	var want := {4: 40.0, 5: 40.0, 6: 40.0, 7: 40.0, 8: 40.0,
		9: 36.73, 10: 36.73, 11: 30.46, 12: 30.46}
	for cap in want:
		assert_almost_eq(CarRack.cell_width(cap, W, CarRack.ranks_for(cap, H)),
			want[cap], 0.01, "cell at capacity %d" % cap)

func test_nothing_is_drawn_outside_the_car_at_any_capacity() -> void:
	# Not a sample of two. Capacity 10 is the case an earlier draft overflowed
	# while appearing in no test at all.
	for cap in range(4, 13):
		for r in CarRack.slots(cap, W, H):
			assert_gte(r.position.x, -0.01, "capacity %d slot starts left of the car" % cap)
			assert_lte(r.end.x, W + 0.01, "capacity %d slot ends right of the car" % cap)
			assert_gte(r.position.y, -0.01, "capacity %d slot above the car" % cap)
			assert_lte(r.end.y, H + 0.01, "capacity %d slot below the car" % cap)

func test_every_rider_gets_a_slot() -> void:
	for cap in range(4, 13):
		assert_eq(CarRack.slots(cap, W, H).size(), cap,
			"capacity %d must have %d slots" % [cap, cap])

func test_the_back_rank_is_offset_half_a_pitch() -> void:
	var s := CarRack.slots(8, W, H)
	var cell := CarRack.cell_width(8, W, 2)
	# front is 0..3, back is 4..7
	assert_almost_eq(s[4].position.x - s[0].position.x,
		(cell + CarRack.GAP) * 0.5, 0.01, "a back figure sits between two front ones")
	assert_lt(s[4].position.y, s[0].position.y, "the back rank is higher")

func test_a_two_digit_badge_fits_the_narrowest_cell() -> void:
	# Capacity 12 is the tight row: its width-derived font is exactly 24. If a
	# real font disagrees, cut the badge padding to 1 unit a side before
	# dropping the point size.
	var cell := CarRack.cell_width(12, W, 2)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("19", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	assert_lte(w + 4.0, cell, "two digits at font 24 must fit a %.2f-unit cell" % cell)

func test_pips_are_one_per_seat_and_sized_to_the_car() -> void:
	assert_eq(CarRack.pips(4, W).size(), 4)
	assert_eq(CarRack.pips(12, W).size(), 12)
	assert_almost_eq(CarRack.pips(4, W)[0].size.x, 48.75, 0.01)
	assert_almost_eq(CarRack.pips(12, W)[0].size.x, 14.25, 0.01)

func test_pips_have_a_gap_between_them_so_hollows_stay_countable() -> void:
	# Two adjacent hollows on a SHARED track merge into one dark band, which
	# defeats the one question pips exist to answer.
	var p := CarRack.pips(12, W)
	assert_almost_eq(p[1].position.x - p[0].end.x, CarRack.PIP_GAP, 0.01)

func test_a_short_car_drops_to_one_rank_then_to_none() -> void:
	assert_eq(CarRack.ranks_for(12, 113.0), 1, "not enough for two bands")
	assert_eq(CarRack.ranks_for(12, 61.0), 0, "not enough for one")
	assert_eq(CarRack.ranks_for(12, 18.0), 0, "the forced-height fixture")

func test_the_one_rank_band_is_sized_by_width_not_capacity() -> void:
	# One rank of twelve would be 14.7 units a cell -- narrower than the figure.
	assert_eq(CarRack.front_count(12, W, 1), 6, "as many as fit at CELL_MIN")
	assert_eq(CarRack.slots(12, W, 100.0).size(), 6, "the rest go to the header")

func test_pips_survive_every_band_including_a_car_too_short_for_figures() -> void:
	assert_eq(CarRack.pips(4, W).size(), 4, "occupancy stays exact with no picture")

func test_the_bounds_cases_produce_no_layout_rather_than_a_bad_one() -> void:
	assert_eq(CarRack.slots(0, W, H).size(), 0)
	assert_eq(CarRack.pips(0, W).size(), 0)
	assert_eq(CarRack.pips(-3, W).size(), 0)
	# Far past the shipped cap of 12, both representations bow out on a MEASURED
	# floor rather than drawing something illegible.
	assert_eq(CarRack.pips(200, W).size(), 0, "pips below PIP_MIN are not drawn")
	for r in CarRack.slots(40, W, H):
		assert_lte(r.end.x, W + 0.01, "no slot escapes even far past the cap")
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_car_rack.gd -gexit`
Expected: FAIL — `CarRack` does not exist.

- [ ] **Step 3: Write CarRack**

Create `view/car_rack.gd`:

```gdscript
class_name CarRack
extends RefCounted

## Where riders stand in a car, and how full it looks. Pure geometry, no scene
## tree, so every number is unit-tested headlessly -- the same treatment
## ChipGrid gets, and for the same reason: this is the part that will be wrong
## first.
##
## Riders stand in ONE rank on the floor of the car until capacity passes five,
## then a second rank stands behind and half a pitch across, so a back figure
## sits between two front badges rather than directly behind one.
##
## THE CELL BUDGET INCLUDES THE OFFSET. An earlier draft derived the cell to
## fill the car and then added the half-pitch on top; at capacities 10 and 12
## the back rank left the car by up to 19 units. The offset is paid for here.

const GAP := 4.0
## The widest a cell gets. Past this a four-rider car spreads into a line of
## lonely figures instead of a group.
const CELL_MAX := 40.0
## The narrowest cell that can still carry a two-digit badge.
const CELL_MIN := 30.0

const PIP_GAP := 3.0
## Below this a pip is a smear rather than a countable thing.
const PIP_MIN := 6.0
const PIP_H := 8.0
const PIP_INSET := 8.0

const INSET := 2.0
const BADGE_H := 30.0
const FIGURE_H := 22.0
const BAND := BADGE_H + FIGURE_H                    # 52
const ONE_RANK_MIN := INSET + PIP_H + BAND          # 62
const TWO_RANK_MIN := INSET + PIP_H + BAND * 2.0    # 114
const ONE_RANK_CAP := 5

## 0, 1 or 2. Three bands, because one rank and two ranks need different room:
## below 62 there is space for neither, and the header line carries everything.
static func ranks_for(capacity: int, car_h: float) -> int:
	if capacity <= 0 or car_h < ONE_RANK_MIN:
		return 0
	if car_h < TWO_RANK_MIN:
		return 1
	return 1 if capacity <= ONE_RANK_CAP else 2

## How many stand in the front rank. At two ranks the front takes the extra, so
## an odd capacity leans forward. At one rank in a short car the count is set by
## WIDTH -- one rank of twelve would be 14.7 units a cell.
static func front_count(capacity: int, car_w: float, ranks: int) -> int:
	if ranks <= 0 or capacity <= 0:
		return 0
	if ranks == 2:
		return int(ceil(float(capacity) / 2.0))
	var n := capacity
	while n > 1 and (car_w - GAP * float(n - 1)) / float(n) < CELL_MIN:
		n -= 1
	return n

static func cell_width(capacity: int, car_w: float, ranks: int) -> float:
	var front := front_count(capacity, car_w, ranks)
	if front <= 0:
		return 0.0
	if ranks == 2:
		# The +0.5 and the -GAP/2 are the half-pitch offset, budgeted rather
		# than added afterwards.
		return minf(CELL_MAX,
			(car_w - GAP * float(front - 1) - GAP * 0.5) / (float(front) + 0.5))
	return minf(CELL_MAX, (car_w - GAP * float(front - 1)) / float(front))

## Front rank first, then back. Index order is boarding order, so rider i is
## slot i.
static func slots(capacity: int, car_w: float, car_h: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ranks := ranks_for(capacity, car_h)
	if ranks <= 0:
		return out
	var front := front_count(capacity, car_w, ranks)
	var back := 0 if ranks == 1 else capacity - front
	var cell := cell_width(capacity, car_w, ranks)
	var pitch := cell + GAP
	var front_w := float(front) * cell + float(front - 1) * GAP
	var back_w := (float(back) * cell + float(back - 1) * GAP) if back > 0 else 0.0
	# Centre the COMPOSITION, not the front rank -- centring the front rank and
	# then offsetting the back is what pushed it out of the car.
	var comp := front_w if back <= 0 else maxf(front_w, pitch * 0.5 + back_w)
	var x0 := (car_w - comp) * 0.5
	# Feet sit INSET above the car floor; in the short band the rank is pushed
	# down to clear the pip strip instead.
	var front_top := maxf(INSET + PIP_H, car_h - INSET - BAND)
	var back_top := front_top - BAND
	for i in front:
		out.append(Rect2(x0 + float(i) * pitch, front_top, cell, BAND))
	for i in back:
		out.append(Rect2(x0 + pitch * 0.5 + float(i) * pitch, back_top, cell, BAND))
	return out

## One rect per seat, lit or hollow decided by the caller. Empty when a pip
## would be too small to count -- occupancy then falls to the header's number.
static func pips(capacity: int, car_w: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if capacity <= 0:
		return out
	var track := car_w - PIP_INSET * 2.0
	var w := (track - PIP_GAP * float(capacity - 1)) / float(capacity)
	if w < PIP_MIN:
		return out
	for i in capacity:
		out.append(Rect2(PIP_INSET + float(i) * (w + PIP_GAP), INSET, w, PIP_H))
	return out
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_car_rack.gd -gexit`
Expected: PASS, 14 tests. If `test_a_two_digit_badge_fits_the_narrowest_cell` fails, apply the spec's stated fallback in order: cut the badge padding from 2 units a side to 1 (change the `+ 4.0` to `+ 2.0` and record it), and only then drop capacities 11–12 to font 23.

- [ ] **Step 5: Add the uid files and commit**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add view/car_rack.gd view/car_rack.gd.uid tests/test_car_rack.gd tests/test_car_rack.gd.uid
git commit -m "Work out where riders stand, headlessly"
```

---

### Task 5: PersonSprite, and the hall that uses it

**Files:**
- Create: `view/person_sprite.gd`, `view/person_sprite.gd.uid`
- Create: `tests/test_person_sprite.gd`, `tests/test_person_sprite.gd.uid`
- Delete: `view/passenger_sprite.gd`, `view/passenger_sprite.gd.uid`
- Modify: `view/floor_row.gd` (constants, `set_waiting`, docstrings at `:19-23`, `:33`, `:34-35`, `:99-101`)
- Modify: `view/shaft_column.gd:25-26,249-254`, `tests/test_board_input.gd:379,397`

**Interfaces:**
- Consumes: `Palette.PERSON_SHIRTS`, `PERSON_SKINS`, `PERSON_LEGS`, `BADGE_BG`, `BADGE_INK`, `PERSON_BAR_TRACK` (Task 2).
- Produces:
  - `PersonSprite.HALL_CELL: Vector2` = `(20, 40)`, `PersonSprite.FIGURE: Vector2` = `(14, 22)`, `PersonSprite.HALL_BADGE: Vector2` = `(16, 14)`, `PersonSprite.BAR_W: float` = `4.0`
  - `PersonSprite.key_for(origin: int, destination: int, source: int) -> int`
  - `show_waiting(fraction: float, glyph: String, tint_key: int) -> void`
  - `show_riding(glyph: String, tint_key: int) -> void`
  - `set_cell(cell: Vector2, badge_h: float, font_size: int) -> void` — the car's per-capacity sizing, called by Task 6
  - `label_text() -> String`, `recycle() -> void`
  - `parts() -> Dictionary` with keys `badge`, `figure`, `bar`, `head`, `torso` (all `Rect2`; `bar` is `Rect2()` for a rider)
  - `redraw_count() -> int`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_person_sprite.gd`:

```gdscript
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
	p.show_waiting(1.0, FloorRow.CALL_UP, 0)
	assert_almost_eq((p.parts()["figure"] as Rect2).position.x, 1.0, 0.01)
	p.set_cell(Vector2(40, 52), 30.0, 24)
	p.show_riding("12", 0)
	assert_almost_eq((p.parts()["figure"] as Rect2).position.x,
		(40.0 - PersonSprite.FIGURE.x) * 0.5, 0.01, "centred in the car cell")

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
	p.set_cell(Vector2(36, 52), 30.0, 24)
	assert_gt(p.redraw_count(), m, "a changed cell must redraw")

func test_a_direction_that_is_not_bought_yet_draws_no_badge() -> void:
	# An empty badge is a blank dark box, which reads as an error state -- the
	# outcome CALL_UNKNOWN's empty string exists to avoid.
	p.show_waiting(1.0, FloorRow.CALL_UNKNOWN, 0)
	assert_eq((p.parts()["badge"] as Rect2).size, Vector2.ZERO)
	assert_eq(p.label_text(), FloorRow.CALL_UNKNOWN)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_person_sprite.gd -gexit`
Expected: FAIL — `PersonSprite` does not exist.

- [ ] **Step 3: Write PersonSprite**

Create `view/person_sprite.gd`:

```gdscript
class_name PersonSprite
extends Control

## One person, waiting on a floor or riding in a car. Pooled.
##
## Three parts, and which of them appear is the difference between the two
## states:
##
##   badge  -- a call ARROW while waiting (drawn, not typeset), the DESTINATION
##             FLOOR once aboard (typeset, two digits). Learning the floor by
##             picking someone up is the asymmetry the dispatch puzzle rests on.
##   figure -- decorative. Shirt and skin come from the passenger's own trip, so
##             a pooled sprite cannot flicker as the pool reshuffles.
##   bar    -- patience, and ONLY while waiting. Patience is frozen aboard
##             (GameState._expire skips riders), so a rider's bar would encode a
##             number that stopped moving at boarding.
##
## The hall arrow is DRAWN rather than set in a font because a 16x14 badge puts
## a glyph at 6.6pt, half what the chip it replaces managed -- and a triangle
## reads better at 14 units than any glyph. label_text() still reports the
## direction, so it stays the logical accessor: it says what the badge MEANS.
##
## parts() and redraw_count() are the testable seams; _draw() reads them and
## adds nothing of its own.

## The call glyphs live HERE, not in FloorRow, because this is the class that
## draws them -- FloorRow's CALL_UP/CALL_DOWN now point at these. The other
## direction would be a cycle: FloorRow builds PersonSprites.
const ARROW_UP := "\u25b2"
const ARROW_DOWN := "\u25bc"

const HALL_CELL := Vector2(20, 40)
const HALL_BADGE := Vector2(16, 14)
const FIGURE := Vector2(14, 22)
const BAR_W := 4.0
const HALL_FIGURE_TOP := 16.0

## Deliberate coefficients. For every trip shape the spawner emits, each
## freely-varying field's coefficient must be coprime to BOTH palette sizes --
## that is, to 15. Two earlier sets failed: (31,17,7) mod 4 put every inbound
## passenger in one shirt, and (3,7,11) with a separate skin sum could not be
## carried by a single key. Verified over floors 0..20 on all four shapes.
static func key_for(origin: int, destination: int, source: int) -> int:
	return origin * 4 + destination * 7 + source * 9

var _glyph: String = ""
var _fraction: float = 1.0
var _tint_key: int = 0
var _riding: bool = false
var _cell: Vector2 = HALL_CELL
var _badge_h: float = HALL_BADGE.y
var _font_size: int = 12
var _redraws: int = 0
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = _cell
	_label = Label.new()
	_label.add_theme_color_override("font_color", Palette.BADGE_INK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_sync_label()

## The car sizes its cells per capacity; the hall never calls this.
func set_cell(cell: Vector2, badge_h: float, font_size: int) -> void:
	if is_equal_approx(cell.x, _cell.x) and is_equal_approx(cell.y, _cell.y) \
			and is_equal_approx(badge_h, _badge_h) and font_size == _font_size:
		return
	_cell = cell
	_badge_h = badge_h
	_font_size = font_size
	size = cell
	_sync_label()
	_dirty()

func show_waiting(fraction: float, glyph: String, tint_key: int) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	# Quantised to what the bar can actually SHOW. Raw, this never matches:
	# patience decays every tick, so a busy hall would redraw at 20Hz forever.
	if visible and not _riding and _glyph == glyph and _tint_key == tint_key \
			and roundi(_fraction * FIGURE.y) == roundi(f * FIGURE.y):
		return
	visible = true
	_riding = false
	_fraction = f
	_glyph = glyph
	_tint_key = tint_key
	_sync_label()
	_dirty()

func show_riding(glyph: String, tint_key: int) -> void:
	if visible and _riding and _glyph == glyph and _tint_key == tint_key:
		return
	visible = true
	_riding = true
	_glyph = glyph
	_tint_key = tint_key
	_sync_label()
	_dirty()

func recycle() -> void:
	visible = false
	_dirty()

func label_text() -> String:
	return _glyph

func redraw_count() -> int:
	return _redraws

## The rects _draw() consumes. A rider has no bar and an unbought direction has
## no badge, and both are reported as a zero-size Rect2 rather than omitted, so
## a caller never has to test for a missing key.
func parts() -> Dictionary:
	var badge := Rect2()
	if _riding or _glyph != "":
		badge = Rect2(0, 0, _cell.x if _riding else HALL_BADGE.x, _badge_h)
	var band_w := _cell.x if _riding else HALL_BADGE.x
	var fig_top := _badge_h if _riding else HALL_FIGURE_TOP
	var figure := Rect2((band_w - FIGURE.x) * 0.5, fig_top, FIGURE.x, FIGURE.y)
	var bar := Rect2()
	if not _riding:
		var h := FIGURE.y * _fraction
		bar = Rect2(_cell.x - BAR_W, fig_top + (FIGURE.y - h), BAR_W, h)
	return {
		"badge": badge,
		"figure": figure,
		"bar": bar,
		"head": Rect2(figure.position + Vector2(3, 0), Vector2(8, 8)),
		"torso": Rect2(figure.position + Vector2(2, 9), Vector2(10, 9)),
	}

func _dirty() -> void:
	_redraws += 1
	queue_redraw()

func _sync_label() -> void:
	if _label == null:
		return
	# Only the CAR typesets. The hall's arrow is a drawn triangle.
	_label.visible = _riding
	_label.text = _glyph if _riding else ""
	_label.position = Vector2.ZERO
	_label.size = Vector2(_cell.x, _badge_h)
	_label.add_theme_font_size_override("font_size", _font_size)

func _draw() -> void:
	if not visible:
		return
	var q := parts()
	var badge: Rect2 = q["badge"]
	if badge.size != Vector2.ZERO:
		draw_rect(badge, Palette.BADGE_BG)
		if not _riding:
			_draw_arrow(badge)
	var bar: Rect2 = q["bar"]
	if bar.size != Vector2.ZERO:
		var track := Rect2(bar.position.x, (q["figure"] as Rect2).position.y,
			BAR_W, FIGURE.y)
		draw_rect(track, Palette.PERSON_BAR_TRACK)
		draw_rect(bar, Palette.PATIENCE_LOW.lerp(Palette.PATIENCE_OK, _fraction))
	var figure: Rect2 = q["figure"]
	var skin: Color = Palette.PERSON_SKINS[posmod(_tint_key, Palette.PERSON_SKINS.size())]
	var shirt: Color = Palette.PERSON_SHIRTS[posmod(_tint_key, Palette.PERSON_SHIRTS.size())]
	draw_circle((q["head"] as Rect2).get_center(), 4.0, skin)
	draw_rect(q["torso"], shirt)
	draw_rect(Rect2(figure.position + Vector2(2, 18), Vector2(4, 4)), Palette.PERSON_LEGS)
	draw_rect(Rect2(figure.position + Vector2(8, 18), Vector2(4, 4)), Palette.PERSON_LEGS)

func _draw_arrow(badge: Rect2) -> void:
	var c := badge.get_center()
	var up := _glyph == ARROW_UP
	var dy := 4.0 if up else -4.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -dy), c + Vector2(-5, dy), c + Vector2(5, dy)]),
		Palette.BADGE_INK)
```

- [ ] **Step 4: Run the sprite tests**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_person_sprite.gd -gexit`
Expected: PASS, 10 tests.

- [ ] **Step 5: Point FloorRow at it**

In `view/floor_row.gd`, first re-point the two call glyphs at the class that now
draws them, so `PersonSprite` does not have to reach back into `FloorRow`:

```gdscript
const CALL_UP := PersonSprite.ARROW_UP
const CALL_DOWN := PersonSprite.ARROW_DOWN
```

Then replace `_sprites: Array[PassengerSprite]` with `Array[PersonSprite]`, construct `PersonSprite.new()`, and rewrite the body of `set_waiting`'s loop:

```gdscript
	var cell := PersonSprite.HALL_CELL
	var area := Vector2(STRIP_RIGHT - SPRITE_X, size.y)
	var grid := ChipGrid.shape(mini(total, cap),
		ChipGrid.columns_for(area.x, cell.x), ChipGrid.rows_for(area.y, cell.y))
	var shown: int = mini(mini(total, cap), ChipGrid.fits(grid))
	grid = ChipGrid.shape(shown, ChipGrid.columns_for(area.x, cell.x),
		ChipGrid.rows_for(area.y, cell.y))
	while _sprites.size() < shown:
		var s := PersonSprite.new()
		add_child(s)
		_sprites.append(s)
	for i in range(_sprites.size()):
		if i < shown:
			var p: Passenger = passengers[i]
			_sprites[i].position = Vector2(SPRITE_X, 0) \
				+ ChipGrid.position_of(i, shown, grid, area, cell)
			_sprites[i].show_waiting(p.patience_fraction(),
				(CALL_DOWN if p.direction() < 0 else CALL_UP) if show_direction
				else CALL_UNKNOWN,
				PersonSprite.key_for(p.origin_floor, p.destination_floor, p.source_floor))
		else:
			_sprites[i].recycle()
```

Delete `const SPRITE_PITCH := 14.0` (`:33`) — dead since the ChipGrid work and flagged as open cleanup in two prior reviews. Update the docstrings at `:19-23` (the "original 14-unit pitch" rationale — the cell is 20 × 40 now), `:34-35` (the "same square … looks the same before and after boarding" claim, which is the half this design drops), and `:99-101` ("Rows are a fixed 88 units now" → 120).

- [ ] **Step 6: Keep ShaftColumn compiling**

`view/shaft_column.gd:25-26` and `:249-254` reference `PassengerSprite`. Until Task 6 rewrites them, swap the type and constructor:

```gdscript
const SEAT_SIZE := Vector2(30, 30)
const SEAT_FONT := 24
...
var _chips: Array[PersonSprite] = []
```

and in `_grow_pools`, construct `PersonSprite.new()`, calling `chip.set_cell(SEAT_SIZE, SEAT_SIZE.y, SEAT_FONT)` in place of `set_chip`, and `show_riding(str(p.destination_floor), PersonSprite.key_for(...))` in place of `show_as`.

**The car looks wrong between this task and Task 6, and that is expected.** A
30x30 cell with a 30-unit badge puts the figure below its own cell, so riders
will render as badges with their bodies clipped. The suite stays green because
`rider_destinations()` reads `_listed` and `free_slots_shown()` still counts the
seat rack, which this task leaves in place. Do not try to make the car look right
here; Task 6 replaces this whole path. If you would rather not ship a broken
frame at all, squash Tasks 5 and 6 into one commit.

- [ ] **Step 7: Delete PassengerSprite and fix its type references**

```bash
git rm view/passenger_sprite.gd view/passenger_sprite.gd.uid
```

`tests/test_board_input.gd:379` and `:397` declare `var sprite: PassengerSprite = …` — these are **parse** errors once the `class_name` is gone, not failing assertions. Change both to `PersonSprite`.

- [ ] **Step 8: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
godot --headless --import
git add -A view/person_sprite.gd view/person_sprite.gd.uid view/floor_row.gd view/shaft_column.gd tests/test_person_sprite.gd tests/test_person_sprite.gd.uid tests/test_board_input.gd
git commit -m "Draw a person instead of a labelled square"
```

---

### Task 6: The car — pips and ranks

**Files:**
- Modify: `view/shaft_column.gd` (constants `:25-32`, docstrings `:16-24`, `:29-30`, `:44-46`, `:213-215`, `set_riders` `:183-212`, `_draw_header_only` `:216-223`, `_grow_pools` `:240-254`, `seats_taken`/`free_slots_shown` `:260-272`)
- Modify: `tests/test_board_input.gd:445`, `:453`, `:467`

**Interfaces:**
- Consumes: `CarRack` (Task 4), `PersonSprite` (Task 5).
- Produces: `ShaftColumn.free_slots_shown()` and `seats_taken()` unchanged in name, now counting pips; `ShaftColumn.rider_destinations()` and `car_text()` unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_board_input.gd`:

```gdscript
func test_the_pips_count_the_seats_and_light_for_riders() -> void:
	board_riders([5, 2])
	var col: ShaftColumn = view._columns[0]
	assert_eq(col.seats_taken(), 2, "two lit")
	assert_eq(col.free_slots_shown(), 2, "two hollow of a four-seat car")

func test_capacity_is_legible_above_eight_where_the_rack_gave_up() -> void:
	# The seat rack fell back to a text line at capacity 9, so "Bigger Car"
	# bought something invisible. The pip strip does not.
	root.state.building.cars[0].capacity = 12
	view.refresh()
	assert_eq(view._columns[0].free_slots_shown(), 12,
		"all twelve pips, where the rack drew none")

func test_riders_stand_in_ranks_and_still_say_where_they_are_going() -> void:
	board_riders([12, 7])
	assert_eq(view._columns[0].rider_destinations(),
		PackedStringArray(["12", "7"]), "two digits on a standing figure")
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_input.gd -gexit`
Expected: FAIL — `free_slots_shown()` counts hollow seat `ColorRect`s, and at capacity 12 the rack falls back to the header so it returns 0.

- [ ] **Step 3: Rewrite `set_riders`**

Replace `view/shaft_column.gd:183-212`:

```gdscript
## What is aboard, where it is going, and how much room is left.
##
## The pips are the seat rack flattened: one per seat, lit for a rider, hollow
## for a free one. Capacity is 4 to 12 -- small and discrete -- so lit-vs-hollow
## answers "does one more fit" EXACTLY, which a needle could not. They draw at
## every capacity and in every guard band, so occupancy survives even when the
## figures do not.
func set_riders(riders: Array, capacity: int) -> void:
	var area := _car_rect.size
	_pips = CarRack.pips(capacity, area.x)
	_lit = mini(riders.size(), capacity)
	var slots := CarRack.slots(capacity, area.x, area.y)
	_car_rect.queue_redraw()

	if slots.is_empty():
		_draw_header_only(riders, capacity)
		return

	var cell := CarRack.cell_width(capacity, area.x, CarRack.ranks_for(capacity, area.y))
	_car_label.text = ""
	_grow_pools(slots.size())
	_listed = PackedStringArray()
	for i in range(_chips.size()):
		if i >= slots.size() or i >= riders.size():
			_chips[i].recycle()
			continue
		var p: Passenger = riders[i]
		_chips[i].set_cell(Vector2(cell, CarRack.BAND), CarRack.BADGE_H, CAR_FONT)
		_chips[i].position = slots[i].position
		_chips[i].show_riding(str(p.destination_floor),
			PersonSprite.key_for(p.origin_floor, p.destination_floor, p.source_floor))
		_listed.append(str(p.destination_floor))
	# Riders past the drawable rank are counted, not dropped -- the short-car
	# band shows fewer figures than the car holds.
	if riders.size() > slots.size():
		_car_label.text = "+%d" % (riders.size() - slots.size())
		_car_label.position = Vector2(0, CarRack.INSET + CarRack.PIP_H)
		_car_label.size = Vector2(area.x, HEADER_HEIGHT)
```

Add the state and the pip drawing. Near the other vars:

```gdscript
var _pips: Array[Rect2] = []
var _lit: int = 0
```

and connect the car's own draw pass — in `setup()`, after `_car_rect` is created:

```gdscript
	_car_rect.draw.connect(_draw_pips)
```

with:

```gdscript
## Two rects per pip: its own track, and a lit fill inset inside it. The track
## is PER PIP rather than one bar behind them all -- two adjacent hollows on a
## shared track merge into a single dark band, and counting free seats is the
## one job the strip has.
func _draw_pips() -> void:
	for i in _pips.size():
		_car_rect.draw_rect(_pips[i], Palette.PERSON_BAR_TRACK)
		if i < _lit:
			_car_rect.draw_rect((_pips[i] as Rect2).grow(-1.0), Palette.PIP_LIT)
```

- [ ] **Step 4: Repoint the counters and the pools**

```gdscript
## Pips, not seats -- but the question is the same one, so the names are.
func seats_taken() -> int:
	return _lit

func free_slots_shown() -> int:
	return maxi(_pips.size() - _lit, 0)
```

In `_grow_pools`, delete the seat `ColorRect` entirely (there are no seats) and grow only `_chips`. Delete `SEAT_SIZE`, `SEAT_FONT` and `SEAT_FREE`, and add:

```gdscript
## Today's PassengerSprite.FONT, kept: a font-24 line box is what the 30-unit
## badge was sized for, and it is 13.1pt at the 0.546 iPhone scale.
const CAR_FONT := 24
```

- [ ] **Step 5: Move the header below the pips**

In `_draw_header_only`, the label is anchored at `Vector2(0, 1)` — the pip strip's y now. Change it to sit below:

```gdscript
	_car_label.position = Vector2(0, CarRack.INSET + CarRack.PIP_H)
```

and in the same function stop hiding a `_seats` array that no longer exists.

- [ ] **Step 6: Update the docstrings this falsifies**

- `:16-24` — "The car is a rack of seats … the one case where the picture is gone and the number is all there is". The pips now draw in every band, so the last clause is false.
- `:29-30` — `HEADER_BUDGET := 16`, "Characters that fit across the car", sized for a 150-unit car. The car is 220.
- `:44-46` — "Opaque panels would hide the **seat rack**" → the figures.
- `:213-215` — `_draw_header_only`'s trigger, derived as "at the 40-floor cap the car is 25.6 units tall". The threshold is `CarRack.ONE_RANK_MIN` (62) now.

- [ ] **Step 7: Fix the three stale assertions**

`tests/test_board_input.gd:445` — the message "two digits fit on a 34-unit seat" is now false; the cell is 30.46–40. Reword to "two digits fit a standing rider's badge".
`:453` — `assert_eq(col.free_slots_shown(), 0, "no seats drawn")` in the forced-18-unit car. The pips still draw, so:

```gdscript
	assert_eq(col.free_slots_shown(), 4,
		"the picture is gone but occupancy is not -- pips draw in every band")
```

`:467` — `assert_lt(text.length(), 20, "the line stays inside the column")` was sized against a 150-unit car; leave the bound but update the message to name the 220-unit car.

- [ ] **Step 8: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add view/shaft_column.gd tests/test_board_input.gd
git commit -m "Stand the riders on the car floor, and flatten the rack into pips"
```

---

### Task 7: Reconcile the documents

The spec's §8 is the authority for this task; it lists every surface with a line number. A stale derivation in these files is what a future session reads as truth.

**Files:** `docs/superpowers/specs/2026-08-02-ui-design.md`, `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md`, `docs/superpowers/specs/2026-08-02-call-direction-upgrade-design.md`, `docs/superpowers/backlog.md`, `codemaps/*`

- [ ] **Step 1: Update the UI design spec**

| line | change |
| --- | --- |
| `:135` | the §3.1 coordinate table row — `240–720 / 480 / three columns on a 160-unit pitch` → `208–720 / 512 / two columns on a 230-unit pitch` |
| `:158` | the vacant-floor re-lease price — already gone from the code; strike it |
| `:163-165` | "The people strip is a **fixed** 176 units" → 144, with the reason |
| `:182-183` | "160-unit pitch … 156 units — 85pt" → 230 / 226 |
| `:186-192` | the five-on-96 rationale — record that it is extended, not reversed |
| `:209` | `# visible_shafts = 3` → 2 |
| `:212-213` | `max_scroll` worked example and "the pager caps at 5" → 6 |
| `:215` | "All three visible positions" → two |
| `:222-249` | **delete §3.5 entirely** — but see step 2 first |
| `:257` | "The shaft viewport shows three columns" → two |
| `:307` | "hide the seat rack" → the figures |
| `:525` | the code-shape row naming the vacant price and crowd-bar tier |
| `:565-566` | item 7's `N >= 29` density derivation, which goes with §3.5 |

- [ ] **Step 2: Carry the §8.5 supersession out before deleting §3.5**

`:239` is the only sentence superseding the *design* spec's §8.5 crowd-bar trigger. Delete §3.5 wholesale and design-spec §8.5 (`2026-08-01-…:673-694`) reverts to authoritatively describing a tier that cannot fire, plus a node budget derived from it. Either move that sentence into §3.3 before deleting, or add a correction directly to design-spec §8.5. Do one of the two — not neither.

- [ ] **Step 3: Update the remaining documents**

- `2026-08-01-elevator-incremental-design.md:599` — the module inventory lists `passenger_sprite`, a file this work deletes.
- `backlog.md:24` ("one square, or the seat rack stops telling the truth"), `:374` ("already anticipated in `passenger_sprite.gd`" — the file is deleted *and* the anticipation inverts, since the hall badge is now a drawn triangle rather than a rendered string), `:376-378`, `:573`, `:576`.
- `2026-08-02-call-direction-upgrade-design.md:88` — "`view/passenger_sprite.gd` — unchanged. `show_as(fraction, text)` already…".

- [ ] **Step 4: Regenerate the codemaps**

`codemaps/view.md` states the old constants at `:36` (`SHAFT_WIDTH=160`, `FLOOR_HEIGHT=88`), `:41` (the "88-unit pan strip"), `:53-54`, `:59-60` (the `PassengerSprite` section), and `:63-64` (`ChipGrid`'s `SIZE=30` and the three old signatures).

Run: `/cc-codemaps:update-codemaps`

Then confirm `codemaps/view.md`, `codemaps/tests.md` and `codemaps/architecture.md` mention `car_rack`, `person_sprite`, `test_car_rack`, `test_person_sprite`, `test_board_geometry` and no longer mention `passenger_sprite` or `SEAT_FREE`.

- [ ] **Step 5: Run the full suite and commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add docs/ codemaps/
git commit -m "Reconcile the documents with the people and the car"
```

---

## Verification on device

The suite runs where the safe-area insets are **zero**. Every claim below is one the suite structurally cannot make, which is why it is a list and not a test.

- [ ] Build and install: `./ios/build.sh`
- [ ] **Count the shaft columns. Two.** This is the check that would have caught the CRITICAL that survived two review rounds.
- [ ] Capacity 4, one shaft — one centred rank, four fat pips, digits legible at arm's length.
- [ ] A rider bound for a **two-digit** floor. `rider_destinations()` reads `_listed`, not the rendered `Label`, so no test can see a clipped badge.
- [ ] Capacity 12 — two ranks, twelve pips each in its own track, the half-pitch offset visible.
- [ ] **The call arrows** — ▲ distinct from ▼ at 14 units. The triangle replaced a font glyph precisely so this would read; nothing in the suite can confirm it did.
- [ ] A floor with twelve waiting — all twelve drawn, none clipped at the strip's right edge.
- [ ] A fresh green patience bar and a nearly-expired red one on screen together.
- [ ] A car mid-stop — doors translucent over the figures.
- [ ] A 10-floor building and a 20-floor one — the scroll cost, which is ~3.6 rows worse at the ladder's cap.
