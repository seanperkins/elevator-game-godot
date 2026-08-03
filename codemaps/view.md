> Generated: 2026-08-03 | Token-lean format for LLM context

# view/ + ui/ — render layer (`extends Control`, scene-tree only)

Read sim state, emit signals, never mutate logic. Bound to sim by `game/game_root.gd`.

## game/game_root.gd (entry Control)
`START_FLOORS=6, START_SHAFTS=1, START_SEED=20260802, DEFAULT_CATALOG="res://data/tenants.json", HUD_HEIGHT=96, TOUCH_MIN=88, AUTOSAVE_SECONDS=10`.
* `_ready()` binds `GameState` → BuildingView + ManagementView + FloorPanel; reads safe-area insets; builds the HUD (cash, rate, view toggle, pager).
* `_physics_process(delta)` pumps the sim; autosaves on a 10 s timer and on `NOTIFICATION_APPLICATION_PAUSED`.
* `_debug_board_override()` — `--board=40x8`, dev only, never a shipped default.

## BuildingView (`building_view.gd`) — the board
Signals: `floor_purchase_requested`, `shaft_purchase_requested`, `floor_selected(floor_index)`.
Constants: `SHAFT_AREA_X = FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH` (=240), `SHAFT_WIDTH=160`, **`FLOOR_HEIGHT=88`**.
Owns `BoardCoords`; scrolls board and shaft strip independently. `bind(state)`, `rebuild()`, `refresh()`, `scroll_board_by`, `pan_board_by`, `scroll_shafts_by`, `visible_shafts()`, `slot_count()`, `max_scroll()`, ghost floor + purchase bands.
`refresh()` passes `upgrades.is_installed("call_direction")` into every `FloorRow.set_waiting`.

## FloorRow (`floor_row.gd`) — one floor band
Constants: `GUTTER_WIDTH=64`, `STRIP_WIDTH=176`, `COUNT_WIDTH=26`, `LABEL_X=38`, `SPRITE_X=68`, `MAX_INDIVIDUALS=12`, `CALL_UP="▲"`, `CALL_DOWN="▼"`, **`CALL_UNKNOWN=""`**.
Fonts: floor number **22**, waiting count 18. The floor number is capped by the UI spec's 26-unit gutter budget (x 38–64) — bigger needs the gutter widened first.
`set_floor(index)`, `set_waiting(passengers, show_direction: bool)` (**required arg**, so a caller cannot silently opt out of the upgrade gate), `set_tenant(satisfaction, vacant, moving_out, ticks_left)`.

## ShaftColumn (`shaft_column.gd`) — one elevator shaft
Signals: `dispatch_requested(shaft, floor_index)`, `surge_requested(shaft)`, `pan_requested(delta)`.
`SEAT_SIZE=(ChipGrid.SIZE, ChipGrid.SIZE)`, `SEAT_FONT=PassengerSprite.FONT`.
Draws the car, sliding doors, rider seats (pool sized to capacity), header. `setup(...)`, `set_car_position`, `set_riders(riders, capacity)`, `set_doors(open_fraction)`. `_gui_input` → Gesture → tap dispatch / pan.

## HallColumn (`hall_column.gd`)
The hall-call strip beside the shafts.

## PassengerSprite (`passenger_sprite.gd`, `extends ColorRect`)
Recycled chip, `ChipGrid.SIZE` square, **`FONT=24`**. Body colour ramps RED→GREEN with patience; the Label carries the glyph. `set_chip(size, font)`, `show_as(fraction, text)`, `label_text()`, `recycle()`.
It renders whatever string it is handed — which is why the call-direction gate needed no change here.

## ChipGrid (`chip_grid.gd`, RefCounted) — crowd layout math
`SIZE=30`, `GAP=4`. Pure packing: `shape(n, cols, rows)`, `columns_for(w)`, `rows_for(h)`, `fits(grid)`, `position_of(i, n, grid, area)`.
**Its `rows` are rows of chips inside one floor's strip — genuine layout rows, deliberately not renamed to floors.**

## DaySparkline (`day_sparkline.gd`)
A kind's whole day as 24 bars, one per simulated hour, each split by that hour's directional mix. Volume and direction at once, because a number cannot show a shape. `bar_heights()` and `segment_shares()` are the tested seams; `_draw()` reads them.

## PointerEvents / SafeArea (RefCounted)
Input classification (incl. `EMULATED_DEVICE=-1`) and safe-area inset math (`CORNER_MARGIN=16`). Not Nodes.

## ui/management_view.gd — upgrades + dispatch panel
`bind(state)`, `refresh()`, `_cycle_policy(shaft)`. `BUTTON_HEIGHT=88`, `MARGIN=12`.
Builds the readout (riders served, avg wait, gave-ups), one row per upgrade (name, level, effect, cost, Buy — greyed on max / unaffordable / zero-delta), and the per-shaft dispatch toggle cycling `PRESET_ORDER`.
The upgrade list is **generated from the catalog**, so a new id in `upgrades.json` appears with no UI change.

## ui/floor_panel.gd — the per-floor sheet
Replaced `relet_confirm.gd`. Opens on a floor tap: lease a kind, upgrade the floor class, and compare kinds via `DaySparkline`.
Fonts: header 18, upgrade 16, buttons 15.
