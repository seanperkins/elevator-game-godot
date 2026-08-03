> Generated: 2026-08-02 | Token-lean format for LLM context

# view/ + ui/ — render layer (`extends Control`, scene-tree only)

Read sim state, emit signals, never mutate logic. Bound to sim by `game/game_root.gd`.

## game/game_root.gd (entry Control)
`const START_ROWS=6, START_SHAFTS=1, START_SEED=20260802, HUD_HEIGHT=96, TOUCH_MIN=88, AUTOSAVE_SECONDS=10`.
* `_ready()` binds `GameState` → BuildingView + ManagementView + ReletConfirm; reads safe-area insets, builds HUD (cash, rate, view toggle, pager prev/next).
* `_physics_process(delta)` → pumps sim; autosaves on 10s timer and `NOTIFICATION_APPLICATION_PAUSED`.
* `_debug_board_override()` — `--board=40x8` CLI override for screenshots/dev, never a shipped default.
* `_refresh_pager()` counts visible SHAFTS (excludes ghost).

## BuildingView (`view/building_view.gd`) — the board
Signals: `floor_purchase_requested`, `shaft_purchase_requested`, `relet_requested(floor_index)`.
Layout constants: `SHAFT_AREA_X = FloorRow.GUTTER_WIDTH + FloorRow.STRIP_WIDTH` (=240), `SHAFT_WIDTH=160`, `ROW_HEIGHT=88`, `RELET_SPAN`. Owns `BoardCoords`; scrolls board and shaft strip independently.
`bind(state)`, `rebuild()`, `refresh()`, `scroll_board_by`, `pan_board_by`, `scroll_shafts_by`, `visible_shafts()`, `slot_count()`, `max_scroll()`, `_on_dispatch(shaft,floor)`, ghost floor/purchase bands. Dispatch for a tap via `Gesture`.

## ShaftColumn (`view/shaft_column.gd`) — one elevator shaft
Signals: `dispatch_requested(shaft, floor)`, `surge_requested(shaft)`, `pan_requested(delta)`.
Draws the moving car, sliding doors, rider seats (ColorRect pool sized to capacity), header (rider destinations). `setup(index, coords, car_floor_provider)`, `set_car_position`, `set_riders(riders, capacity)`, `set_doors(open_fraction=0.0..1.0)`. Sizes from ChipGrid. Handles `_gui_input` → Gesture → tap dispatch / pan.

## FloorRow (`view/floor_row.gd`) — one floor band
Constants: `GUTTER_WIDTH=64`, `STRIP_WIDTH=176`, `COUNT_WIDTH=26`, `SPRITE_PITCH=14`, `MAX_INDIVIDUALS=12`, `VACANT_MAX_INDIVIDUALS=9`, colours GREEN/RED/GREY.
Renders floor label, waiting count, satisfaction bar (track+fill), PassengerSprite crowd. `set_row(index)`, `set_waiting(passengers)`, `set_tenant(satisfaction, vacant, moving_out, ...)`.

## ChipGrid (`view/chip_grid.gd`, RefCounted) — crowd layout math
`const SIZE=30, GAP=4`. Pure packing: where passenger chips go in a row/gutter. Not a Node.

## PassengerSprite (`view/passenger_sprite.gd`, `extends ColorRect`)
Recycled chip: size `ChipGrid.SIZE`, shows patience fraction as colour + a Label. `set_chip`, `show_as(fraction, text)`, `recycle()`.

## PointerEvents / SafeArea (`view/pointer_events.gd`, `view/safe_area.gd`, RefCounted)
Input-event classification (incl. `EMULATED_DEVICE=-1`) and safe-area inset math (`CORNER_MARGIN=16`). Not Nodes.

## ui/management_view.gd — upgrades + dispatch panel
Signals/API: `bind(state)`, `refresh()`, `_cycle_policy(shaft)`.
Constants: `BUTTON_HEIGHT=88`, `MARGIN=12`. Builds readout (riders served, avg wait, gave-ups), a per-upgrade row (name + level + effect + cost + Buy, greyed on max/unaffordable/zero-delta), and the per-shaft dispatch toggle (cycles a policy through `PRESET_ORDER`).

## ui/relet_confirm.gd — re-lease dialog
Signals: `confirmed(floor_index)`. `BUTTON_HEIGHT=88`. `open_for(floor_index)`, `close()`. Shown when a vacant floor is tapped; calls `GameState.relet` on confirm.
