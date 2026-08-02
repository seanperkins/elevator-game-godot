# Code Review — ChipGrid refactor (uncommitted work)

Review date: 2026-08-02
Scope: the uncommitted diff on `main` —
  - new `view/chip_grid.gd` + `tests/test_chip_grid.gd`
  - modified `view/floor_row.gd`, `view/passenger_sprite.gd`, `view/shaft_column.gd`

No code changes made by the reviewer.

## Verified
- Full test suite passes headlessly: **244/244 tests, 3085 asserts** (GUT 9.7.1,
  Godot 4.7 headless), including the new ChipGrid suites.
- `chip_grid.gd`, `floor_row.gd`, `passenger_sprite.gd`, `shaft_column.gd` all
  load cleanly (no parse/resolve errors).

## Findings (most important first)

### 1. [Medium — regression] Vacant-floor crowd bar collides with the re-lease price
File: `view/floor_row.gd` (`_draw_crowd_bar`, line ~166)

The crowd-bar span changed from `float(cap) * SPRITE_PITCH` (14·cap) to the
fixed `CROWD_SPAN := 168.0`. For **non-vacant** rows that's unchanged (12·14 =
168) and harmless. For **vacant** rows `cap` = 9 (`VACANT_MAX_INDIVIDUALS`), so
the old span was **126 → bar right edge x=194**, which stayed clear of the
re-lease price that occupies `[200, 240]` in the same strip.

With the fixed 168 span the bar's right edge reaches **x=236**, overlapping the
price column. Because `fraction = total/cap`, the collision starts whenever a
vacant floor has **≥ 8 people waiting** (`68 + 168·(total/9) > 200` → total > 7.07).
Short, dense rows (the crowd-bar tier) on a vacant floor that is still spawning
passengers are exactly the case.

Fix direction: make the vacant span reference the narrowed strip, e.g.
`CROWD_SPAN` stays for non-vacant but the bar uses
`(VACANT_STRIP_RIGHT - SPRITE_X)` as its full-width reference when
`_price.visible` — matching the same distinction the individual-tier `area.x`
already makes at line ~131.

### 2. [Low — confirm intent] Hall individual tier shows far fewer people in the mid-height band
File: `view/floor_row.gd` (`set_waiting`)

Because chips are now 30-unit squares packed by ChipGrid, the number of
individual sprites a row shows depends on its height:
- `size.y ≥ ~98` → 12 people (4×3)
- `size.y ∈ [64, 98)` → 10 people (5×2)
- `size.y ∈ [41, 64)` → **5 people** (5×1)

Previously the hall always showed `min(total, 12)` in the single-row 14-unit
strip for any row above the crowd-bar threshold. So rows in roughly 64–101
units now show 10–5 instead of 12. The exact count label keeps it honest, and
the "same square everywhere" goal is a defensible reason — but this is a real
visible reduction and the `CROWD_BAR_BELOW := 40` threshold may now sit oddly
(individuals are already gutted well above 40). Worth confirming it reads
intended on a real build, not just the test grid.

### 3. [Low — cleanup] Dead constant `SPRITE_PITCH`
File: `view/floor_row.gd` line 29

`SPRITE_PITCH := 14.0` is now unused — its only consumer (the old `position`
computation) was removed. Remove or repurpose it.

### 4. [Low — doc] Duplicated / stale class comment in ShaftColumn
File: `view/shaft_column.gd` lines 15–22

Two nearly identical paragraphs now describe the car's seats (the SEATS block
and the "rack of seats" block are the same idea written twice — looks like an
edit left both). Also "three rows of four" (line ~19) is stale: seats are now
packed by ChipGrid into a balanced block, so capacity 12 happens to be 4×3 but
capacity 5 is 3×2, etc.

## Notes (non-issues checked)
- `ChipGrid.shape` correctly handles constrained space; the "shows what fits"
  case is capped by `fits()` in both callers, and the header/`_draw_header_only`
  fallback in the car is consistent with `rows_for` returning 0 for the
  25.6-unit car at the 40-floor cap.
- Hall sprites (default 30×30/font 20) and car chips
  (`set_chip(SEAT_SIZE, SEAT_FONT)`) resolve to the same square — the
  unification is real and consistent.
- `position_of` guards divide-by-zero (grid ≤ 0 → ZERO) and centres short
  ranks; the test suite pins the preferred shapes and the no-overflow rule.
