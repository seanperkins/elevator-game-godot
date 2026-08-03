> Generated: 2026-08-02 | Token-lean format for LLM context

# Elevator Incremental — Architecture

Incremental/idle game about elevators, built for **iPhone via GitHub Pages**.
Godot 4.7, GDScript, GL Compatibility renderer, **threadless** web export.

## Layering (the load-bearing rule)

```
data/ (JSON)  ──loaded──▶  sim/ (pure logic, RefCounted)  ──signals──▶  view/ + ui/ (Nodes)
                game_root.gd binds sim to Nodes; never touches scene tree
```

* **sim/** = pure. No scene tree, no Node. Unit-tested headlessly via GUT.
* **view/** + **ui/** = Nodes (Control). Read sim state, emit signals, never mutate logic.
* **game_root.gd** = the one owner. Pumps the sim at 20Hz, saves, binds views.
* **data/** = numeric coefficients loaded at runtime. No expression strings (no eval).
* Design constraints live in sim docstrings and `docs/superpowers/specs/*`; **user edits belong in CLAUDE.md, not these maps**.

## Module graph

```
            ┌────────────── game/game_root.gd (entry: game/game_root.tscn) ──────────────┐
            │  60Hz _physics_process ──▶ GameState.tick (20Hz via SimClock)              │
            │  autosaves every 10s; saves on NOTIFICATION_APPLICATION_PAUSED             │
            └───────┬───────────────────────────────────┬────────────────────────────────┘
                     ▼                                   ▼
      ┌────────────────────────┐            ┌─────────────────────────────┐
      │ BuildingView  (board)  │            │ ManagementView (upgrades/   │
      │  Floors + ShaftColumns │            │   dispatch panel)           │
      └────────────────────────┘            └─────────────────────────────┘
              ui/relet_confirm.gd (vacant-floor re-lease dialog)
```

## Data flow (one sim tick, fixed written order)

```
metrics.advance -> spawn -> move/doors -> deliver -> auto-dispatch
  -> expire -> advance tenancy -> note_ticks
```
Order is player-visible: **deliver BEFORE expire** → a passenger at exactly 0
patience when the doors open pays and extends the combo.

## Build / run

| Command | Purpose |
|---|---|
| `godot` | editor |
| `godot --headless --export-release "Web" build/web/index.html` | web build |
| `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` | run GUT tests |
| `godot -- --board=40x8` | dev-only oversized board (screenshots); not a shipped default |
| `godot --headless --import` (×2) | CI asset import |

* **CI** (`.github/workflows/deploy.yml`) on push to `main`: install Godot 4.7 → run GUT → assert threadless export → build → deploy to Pages.
* **Design specs** in `docs/superpowers/specs/`, **implementation plans** in `docs/superpowers/plans/` (see `HANDOFF.md`).

## Key constants

| Source | Value | Meaning |
|---|---|---|
| `Building.MAX_ROWS` | 40 | hard floor cap; board never scrolls vertically |
| `Building.MAX_SHAFTS` | 8 | hard shaft cap |
| `SimClock.TICK_SECONDS` | 0.05 | sim runs at 20Hz (physics is 60Hz) |
| `game_root.gd START_*` | rows 6, shafts 1, seed 20260802 | new-game defaults |
| `game_root.gd` HUD_HEIGHT / TOUCH_MIN | 96 / 88 | 88pt = 48pt at 0.546 iPhone scale |
| `BrowserView` coords | `BoardCoords` | single row↔y identity; fixed row height, scrollable |

## Branch: tenant-kinds-and-floor-class (in progress)

Spec A "Floors you choose and invest in" is **agreed, not yet built**
(`docs/superpowers/specs/2026-08-02-tenant-kinds-and-floor-class-design.md`).
Groundwork landed: `Passenger.source_row` (floor that generated the trip) and
the stair penalty default dropped. See sim.md `Fitout`/kind roadmap.
