# Code Review — parked calls + one packing rule (batch 4570b89..93ca986)

Review date: 2026-08-02
Scope: commits `4570b89` (morning-rush day start) through `93ca986` (parked car
answers calls):
  - sim: `elevator_car.gd` (`answer_call`), `game_state.gd` (call wiring),
    `sim_clock.gd` (`START_MINUTE` offset)
  - view: new `chip_grid.gd`, `pointer_events.gd`; reworked `floor_row.gd`,
    `shaft_column.gd`, `passenger_sprite.gd`, `building_view.gd`

No code changes made by the reviewer.

## Verified
- Full suite passes headlessly: **250/250 tests, 3098 asserts** (GUT, Godot 4.7
  headless). No functional regression from this batch.
- `car_arrived` is now emitted but has **no listener** anywhere in the tree
  (grep finds the declaration and the single emit at `game_state.gd:111`, no
  subscribers). Not introduced here, but worth knowing it's dead signal surface.
- `answer_call` wired in `_move_and_doors`, so a door opened by it is DOORS by
  the time `_deliver` runs — the written tick order is preserved. Tests cover
  it (five tests moved off floor 0 to keep the car from rescuing the fixture).

## Headline: the prior review's four findings are all still open

`docs/review-2026-08-02-chip-grid.md` (still untracked on disk) reviewed this
exact chip-grid work before it was committed as part of this batch. None of its
four findings were actioned in `92e38ec` and friends — re-verified below against
current code. They are not new, but they are live.

### 1. [Medium — regression, open] Vacant-floor crowd bar overlaps the re-lease price
File: `view/floor_row.gd` (`_draw_crowd_bar`)

The bar's span is the fixed `CROWD_SPAN := 168.0`. On a **non-vacant** row that
is the old full strip and fine. On a **vacant** row `cap` = 9
(`VACANT_MAX_INDIVIDUALS`), and the bar's right edge is `SPRITE_X(68) + 168 =
236`, which sits under the re-lease price occupying ~`[200, 240]` in the same
strip. The overlap starts once a vacant floor has ≥ 8 waiting
(`68 + 168*(total/9) > 200` → total > 7.07). A vacant floor at the top of a tall
building is short, lands in the crowd-bar tier, and still spawns passengers —
exactly the collision case.

`set_waiting` gained `VACANT_STRIP_RIGHT` for the **individual** tier but
`_draw_crowd_bar` never uses it. Fix direction (from the prior review, still
correct): give the bar a `VACANT_STRIP_RIGHT - SPRITE_X` reference when
`_price.visible`, mirroring the individual tier's `area.x` choice at line ~131.

### 2. [Med/Low — confirm intent, open] Mid-height rows show fewer people than before
File: `view/floor_row.gd` (`set_waiting`)

ChipGrid packs 30-unit squares by available area, so the count shown now depends
on row height: `size.y ≥ ~98` → 12; `[64, 98)` → 10; `[41, 64)` → **5**. The
pre-refactor strip showed `min(total,12)` in one 14-unit row at any height above
the crowd-bar threshold, so ~64–101-unit rows show 5–10 instead of 12. The exact
count label keeps it honest and "one square everywhere" is defensible — but
confirm it reads intended on a real build (the DEBUG run in the screenshots, not
just the test grid). `CROWD_BAR_BELOW := 40` also now sits oddly: individuals are
already gutted well above 40.

### 3. [Low — cleanup, open] Dead constant `SPRITE_PITCH`
File: `view/floor_row.gd:29`

`SPRITE_PITCH := 14.0` now has no consumers (grep confirms only the definition —
its last use was the removed `position` computation). Remove or repurpose.

### 4. [Low — doc, open] Duplicated / stale class comment in ShaftColumn
File: `view/shaft_column.gd`

Two near-identical paragraphs describe the car's seats (the `## The car is a set
of SEATS…` block and the `## The car is a rack of seats…` block both landed in
this batch). Also "three rows of four" is stale now that seats pack by ChipGrid
— capacity 12 happens to be 4×3, but 5 is 3×2, etc.

## New findings in this batch

### 5. [Low — behavior note] Auto-answer has no dispatch-intent check
File: `sim/game_state.gd` (`_move_and_doors`), `sim/elevator_car.gd`
(`answer_call`)

Any car that is IDLE, below capacity, and at a floor with any waiter opens its
doors — even a car the player parked with a specific dispatch in mind, or a
staging car mid-composition for a surge. This is consistent with the commit's
documented rule ("choosing where it goes stays the player's job"), and it never
moves the car, so it's benign. Calling it out only so the trade-off is explicit:
an idle, mostly-full car left parked at a busy floor will pre-board riders and
return to capacity, so a later player dispatch to a different floor starts with
a car that's already full of leftover cargo.

### 6. [Low — edge] One-tick lag before a full-but-emptying parked car answers
File: `sim/game_state.gd` (`_move_and_doors`)

`answer_call` checks `riders.size() >= capacity` in `_move_and_doors`, but seats
only free up in the later `_deliver` (alight-before-board). So a parked car that
is full, and will empty on this very tick, declines the call this tick and
answers the next. Invisible in practice (door open/close is many ticks); noting
only for completeness — the fix would be to check capacity after alighting,
which would couple `_move_and_doors` to `_deliver` ordering and isn't worth it.

## Notes (checked, not issues)
- `PointerEvents.is_emulated_duplicate` (device id `-1`) is verified against 4.7
  and the touch/mouse double-fire reasoning holds; the board and shaft both route
  through it now and the dedicated `test_board_input` suite pins single-fire.
- `ChipGrid.shape` / `fits` correctly degrade to "shows what fits" and the car's
  `_draw_header_only` fallback is consistent with `rows_for` → 0 at the 40-floor
  cap (25.6-unit car vs 30-unit chip). `position_of` guards divide-by-zero and
  centres ragged last ranks.
- `sim_clock.START_MINUTE` is an offset on the reading, not on
  `ticks_executed` — so elapsed-time metrics/tests are untouched, and
  `spawner` wraps via `posmod(minute, curve.size())`, so the offset cannot index
  past the curve end. Sound.
