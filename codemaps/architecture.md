> Generated: 2026-08-03 | Token-lean format for LLM context

# Elevator Incremental — Architecture

Incremental/idle game about elevators, built for **iPhone via GitHub Pages**.
Godot 4.7, GDScript, GL Compatibility renderer, **threadless** web export.

## Layering (the load-bearing rule)

```
data/ (JSON)  ──loaded──▶  sim/ (pure logic, RefCounted)  ──signals──▶  view/ + ui/ (Nodes)
                game_root.gd binds sim to Nodes; sim never touches the scene tree
```

* **sim/** = pure. No Node. Unit-tested headlessly via GUT.
* **view/** + **ui/** = Nodes (Control). Read sim state, emit signals, never mutate logic.
* **game/game_root.gd** = the one owner. Pumps the sim at 20Hz, saves, binds views.
* **data/** = numeric coefficients loaded at runtime. No expression strings (no eval).
* Design constraints live in sim docstrings and `docs/superpowers/specs/*`; **user edits belong in CLAUDE.md, not these maps**.

## Vocabulary

They are **floors**, not rows. `sim/` was renamed to match `view/` and the
player (2026-08-03). The only surviving "row" is `ChipGrid`'s — genuine rows of
passenger chips *within* one floor's strip — and the v2 keys in `SaveCodec`'s
migration map.

## Module graph

```
      ┌─────────── game/game_root.gd (entry: game/game_root.tscn) ────────────┐
      │  60Hz _physics_process ──▶ GameState.tick (20Hz via SimClock)         │
      │  autosaves every 10s; saves on NOTIFICATION_APPLICATION_PAUSED        │
      └──────┬──────────────────────────┬──────────────────────┬──────────────┘
             ▼                          ▼                      ▼
   ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
   │ BuildingView       │   │ ManagementView     │   │ FloorPanel         │
   │  FloorRow + Hall-  │   │  upgrades +        │   │  lease / class /   │
   │  Column + Shaft-   │   │  dispatch presets  │   │  DaySparkline      │
   │  Column            │   │                    │   │                    │
   └────────────────────┘   └────────────────────┘   └────────────────────┘
```

## Data flow (one sim tick, fixed written order)

```
metrics.advance -> spawn -> move/doors -> deliver -> auto-dispatch
  -> expire -> tenancy.accrue -> note_ticks
```
Order is player-visible: **deliver BEFORE expire** → a passenger at exactly 0
patience when the doors open pays and extends the combo.

## Build / run

| Command | Purpose |
|---|---|
| `godot` | editor |
| `godot --headless --export-release "Web" build/web/index.html` | web build |
| `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` | whole GUT suite |
| `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/<f>.gd -gexit` | one file (`-gdir` needs a DIRECTORY) |
| `... -gunit_test_name=<name>` | one test (there is no `-ginclude`) |
| `ios/build.sh [--launch]` | export → xcodebuild → install on the paired iPhone |
| `godot -- --board=40x8` | dev-only oversized board; never a shipped default |

* **CI** (`.github/workflows/deploy.yml`) on push to `main`: install Godot 4.7 → run GUT → assert threadless export → build → deploy to Pages.
* **Specs** in `docs/superpowers/specs/`, **plans** in `docs/superpowers/plans/`, **backlog** in `docs/superpowers/backlog.md`.

## Key constants

| Source | Value | Meaning |
|---|---|---|
| `Building.MAX_FLOORS` | 40 | structural cap; board never scrolls past it |
| `Building.MAX_SHAFTS` | 8 | hard shaft cap |
| `upgrades.json` `floor.max_level` | 14 | **purchasable** cap = 20 floors. Deliberately below MAX_FLOORS — see the building-cost-curve spec |
| `SimClock.TICK_SECONDS` | 0.05 | sim runs at 20Hz (physics is 60Hz) |
| `SimClock.TICKS_PER_REAL_MINUTE` | 1200 | elapsed real time |
| `SimClock.TICKS_PER_SIM_MINUTE` | 600 | one traffic bucket = 30 real s → a day is 12 real minutes |
| `SimClock.START_MINUTE` | 6 | the day opens at the morning rush |
| `game_root.gd` START_* | floors 6, shafts 1, seed 20260802 | new-game defaults |
| `game_root.gd` HUD_HEIGHT / TOUCH_MIN | 96 / 88 | 88pt = 48pt at the 0.546 iPhone scale |
| `SaveCodec.VERSION` | 3 | v1/v2 migrate on read |

## Status

Milestones 1–3 and the board/management UI are built, tested, deployed.
Spec A (tenant kinds + floor class) is **built**: `TenantCatalog`, `TenantKind`,
`TrafficSource` and `Fitout` are live and `data/tenants.json` drives traffic.
Prestige (Spec C) does not exist — the 20-vs-40 floor gap is the room reserved
for it.
