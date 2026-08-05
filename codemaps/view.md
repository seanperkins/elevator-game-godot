> Generated: 2026-08-05 | Token-lean format for LLM context

# view/ + ui/ — render layer (`extends Control`, scene-tree only)

Read sim state, emit signals, never mutate logic. Bound to sim by `game/game_root.gd`.

## game/game_root.gd (entry Control)
`START_FLOORS/START_SHAFTS/START_SEED` are refs to `GameState.BASE_*`.
`DEFAULT_CATALOG`, `DEFAULT_BLUEPRINTS`, `HUD_HEIGHT=96`, `TOUCH_MIN=88`, `AUTOSAVE_SECONDS=10`.
Overrides: `catalog_path_override`, `blueprints_path_override`.
* `_ready()` reads safe-area insets, calls `_rebuild_views()`, then builds the
  HUD (cash, rate, clock, view toggle, shaft readout, DEV) — and calls
  `_restack()` again afterwards, because the first call ran before those nodes
  existed.
* Cold boot uses **`SaveStore.load_all()`** (one source selection). A refused run
  still salvages its Meta; a null Meta draws the error screen and stops.
* `_rebuild_views()` replaces `_view`/`_management`/`panel`/`_prestige`/`_dev` —
  `bind()` add_childs unconditionally, so it frees SYNCHRONOUSLY (queue_free is
  deferred) and then calls `_restack()`.
* **`_restack()` gives the two kinds of surface OPPOSITE answers.** `FloorPanel`
  is a bottom SHEET, so the HUD sits ABOVE it and MANAGE stays reachable —
  confirmed by measurement: without it `_view_button` lands at index 7 against
  the sheet's 11 and a real tap on MANAGE is swallowed by its scrim.
  `PrestigePanel` and `DevPanel` are full-screen OVERLAYS and go above the HUD
  in turn, or MANAGE and the shaft readout draw across their content.
* `_on_demolish()` — **writes before swapping** and checks the bool. Swapping
  first shows the new run while the durable file still holds the old,
  still-demolish-eligible one. `save_now(s: GameState = null) -> bool`.
* `_physics_process(delta)` pumps the sim; autosaves on a 10 s timer and on `NOTIFICATION_APPLICATION_PAUSED`.
* `_show_error_screen(what, path)` + `error_screen_text()` — parameterised, so
  the blueprint catalog is not announced as "No valid tenant catalog".
* `_debug_board_override()` — `--board=40x8`, dev only, never a shipped default.

## BuildingView (`building_view.gd`) — the board
Signals: `floor_purchase_requested`, `shaft_purchase_requested`, `hall_floor_selected(floor_index)`, **`prestige_requested`**.
Constants: `SHAFT_AREA_X = FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH` (=208), `SHAFT_WIDTH=230`, **`FLOOR_HEIGHT=120`**. The numbers are derived against the DEVICE board (688 wide on a phone, 720 headless); `tests/test_board_geometry.gd` pins two columns on both.
Owns `BoardCoords`; scrolls board and shaft strip independently. `bind(state)`, `rebuild()`, `refresh()`, `scroll_board_by`, `pan_board_by`, `scroll_shafts_by`, `visible_shafts()`, `slot_count()`, `max_scroll()`, ghost floor + purchase bands.
`refresh()` passes `upgrades.is_installed("call_direction")` into every `FloorRow.set_waiting`.
**The ghost band at the cap**: line ~100 gates CONSTRUCTION on the STRUCTURAL cap
and must not change — `_on_ghost_input` is also the pan handler, so deleting the
band would kill the pan strip on the tallest buildings. Only the label
(`CAP REACHED — REBUILD`, 21 chars to stay inside `FloorRow.STRIP_RIGHT`) and the
tap's destination change. NB `rebuild()` moves the shaft viewport last, so after
any rebuild the ghost only wins input on the hall side of `SHAFT_AREA_X`.

## FloorRow (`floor_row.gd`) — one floor band
Constants: `GUTTER_WIDTH=64`, `STRIP_WIDTH=144`, `COUNT_WIDTH=26`, `LABEL_X=38`, `SPRITE_X=68`, `MAX_INDIVIDUALS=12`, `CALL_UP/CALL_DOWN` point at `PersonSprite.ARROW_UP/DOWN`, **`CALL_UNKNOWN=""`**.
Fonts: floor number **22**, waiting count 18. The floor number is capped by the UI spec's 26-unit gutter budget (x 38–64) — bigger needs the gutter widened first.
`set_floor(index)`, `set_waiting(passengers, show_direction: bool)` (**required arg**, so a caller cannot silently opt out of the upgrade gate), `set_tenant(satisfaction, vacant, moving_out, ticks_left)`. The hall strip packs `PersonSprite.HALL_CELL` (20×40) via `ChipGrid` — six across, two deep, all twelve.

## ShaftColumn (`shaft_column.gd`) — one elevator shaft
Signals: `dispatch_requested(shaft, floor_index)`, `surge_requested(shaft)`, `pan_requested(delta)`.
`CAR_FONT=24`. Riders stand in ranks laid out by `CarRack`; a pip strip across the car top (one rect per seat, lit/hollow) is the occupancy gauge, drawn in every band via `_car_rect.draw` → `_draw_pips`. `setup(...)`, `set_car_position`, `set_riders(riders, capacity)`, `set_doors(open_fraction)`, `seats_taken()`/`free_slots_shown()` (count pips), `rider_destinations()`. `_gui_input` → Gesture → tap dispatch / pan.

## HallColumn (`hall_column.gd`)
The hall-call strip beside the shafts.

## PersonSprite (`person_sprite.gd`, `extends Control`) — one person
Recycled. Three parts drawn in `_draw()`: badge (call arrow while waiting, DESTINATION once aboard), decorative figure (shirt/skin from `Palette`, keyed by `key_for(origin, destination, source)`), patience bar (waiter only). Hall cell 20×40; car cells per capacity via `set_cell`. `parts()` and `redraw_count()` are the testable seams. `show_waiting(fraction, glyph, tint_key)`, `show_riding(glyph, tint_key)`, `label_text()`, `recycle()`. Setters early-out on unchanged args. Replaces the deleted `passenger_sprite.gd`.

## CarRack (`car_rack.gd`, RefCounted) — car geometry, pure
No scene tree. `GAP=4`, `CELL_MAX=40`, `CELL_MIN=30`, `PIP_MIN=6`, `PIP_H=8`, `INSET=2`, `BADGE_H=30`, `FIGURE_H=22`, `BAND=52`, `ONE_RANK_MIN=62`, `TWO_RANK_MIN=114`, `ONE_RANK_CAP=5`. `ranks_for(capacity, car_h)` (0/1/2 bands), `front_count`, `cell_width` (offset-aware), `slots(capacity, w, h)` (front rank first, then half-pitch-offset back), `pips(capacity, w)` (empty below `PIP_MIN`). Unit-tested headlessly.

## ChipGrid (`chip_grid.gd`, RefCounted) — hall packing math
`GAP=4`. Pure packing for the HALL only (the car uses `CarRack`): `shape(n, cols, rows)`, `columns_for(w, cell_w)`, `rows_for(h, cell_h)`, `fits(grid)`, `position_of(i, n, grid, area, cell)`. Takes a cell `Vector2`, never a pitch.
**Its `rows` are rows of chips inside one floor's strip — genuine layout rows, deliberately not renamed to floors.**

## DaySparkline (`day_sparkline.gd`)
A kind's whole day as 24 bars, one per simulated hour, each split by that hour's directional mix. Volume and direction at once, because a number cannot show a shape. `bar_heights()` and `segment_shares()` are the tested seams; `_draw()` reads them.

## PointerEvents / SafeArea (RefCounted)
Input classification (incl. `EMULATED_DEVICE=-1`) and safe-area inset math (`CORNER_MARGIN=16`). Not Nodes.

## ui/management_view.gd — upgrades + dispatch panel
`bind(state)`, `refresh()`, `_cycle_policy(shaft)`. `BUTTON_HEIGHT=88`, `MARGIN=12`.
Signal: `prestige_requested`. Builds the readout (riders/min, avg wait, gave-up,
**blueprints**), a REBUILD heading at the bottom, one row per upgrade (name, level, effect, cost, Buy — greyed on max / unaffordable / zero-delta), and the per-shaft dispatch toggle cycling `PRESET_ORDER`.
The upgrade list is **generated from the catalog**, so a new id in `upgrades.json` appears with no UI change.

## ui/dev_panel.gd — cheats, behind seven taps on the cash readout
Signals: `cash_requested`, `earnings_requested`, `blueprints_requested`,
`speed_requested`, `unlock_requested`, `reset_requested`. `bind/open/close/
refresh/set_insets/set_speed/is_reset_armed`.
Rows: `+$10K cash` (cash only), `+$10K earned` (**also** `lifetime_earnings`, so
it moves the Blueprint yield — the two are separate so a cash cheat cannot mint
Blueprints), `+5 Blueprints`, speed `1x/2x/4x`, `Fit everything to LvN` (skips
`floor`/`shaft`; `maxi`, so it never demotes), and `Reset save` behind its own
Confirm/Cancel — it destroys the save, the backup AND the Meta, which is
strictly more than the prestige REBUILD does.
The unlock flag lives in the save's `meta` block, so `SaveCodec.VERSION` stays 4.

## ui/prestige_panel.gd — the tech tree and the demolish
Signals: `node_purchase_requested(id)`, `demolish_requested`. `BUTTON_HEIGHT=88`.
`bind/open/close/refresh/is_armed`.
Shaped like ManagementView (full-height overlay + ScrollContainer), NOT
FloorPanel: the tree needs ~708 units idle / ~796 armed against FloorPanel's
589-unit sheet, and VBoxContainer honours `custom_minimum_size`, so the overflow
would draw outside the sheet and over the board.
Shows the yield projection (or the shortfall in dollars), STRUCTURE and
MECHANICAL node rows (disabled when maxed / unaffordable / zero-delta), a note
that Mechanical nodes apply from the next rebuild, and REBUILD.
**Confirm/Cancel PAIR, never an armed double-tap** — touch emulation delivers one
physical tap twice, so arming on tap 1 and committing on tap 2 lets a stray
double-tap destroy a run. It EMITS rather than mutates: a node purchase changes
persistent state and is written immediately.
**Both overlays have an explicit `← BACK` first row and NO scrim.** A scrim was
copied from FloorPanel and was unreachable — buried under the opaque full-rect
bg — so opening either panel trapped the player until they force-quit. A
full-screen opaque overlay has no visible "outside" for a scrim to be.

## ui/floor_panel.gd — the per-floor sheet
Replaced `relet_confirm.gd`. Opens on a floor tap: upgrade the floor class and
compare kinds via `DaySparkline`. The lease picker is **basement-only**
(parking); a vacant TOWER floor shows `NEW TENANT IN Ns` instead — the market
fills it (`_fill_label`, refreshed per `show_floor`, not per frame, like the
LEAVING label). `picker_visible()` / `is_locked()` are the input-test seams.
Fonts: header 18, upgrade 16, buttons 15.
