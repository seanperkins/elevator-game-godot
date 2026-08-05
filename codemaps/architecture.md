> Generated: 2026-08-05 | Token-lean format for LLM context

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
      │  _rebuild_views() replaces all four on a demolish                     │
      └──────┬─────────────┬──────────────────┬──────────────────┬───────────┘
             ▼             ▼                  ▼                  ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
   │ BuildingView │ │ Management-  │ │ FloorPanel   │ │ PrestigePanel    │
   │ FloorRow +   │ │ View         │ │ lease/class/ │ │ tech tree +      │
   │ Hall/Shaft-  │ │ upgrades +   │ │ DaySparkline │ │ Confirm/Cancel   │
   │ Column       │ │ dispatch     │ │              │ │ REBUILD          │
   └──────────────┘ └──────────────┘ └──────────────┘ └──────────────────┘
```

## The two halves of the save

```
  a RUN (discarded on demolish)          the META (persists)
  cash, lifetime_earnings, combo,        blueprints, runs_completed,
  floors, cars, upgrades, tenancy,       spent{node -> level}
  fitout, policies, metrics, clock
        │                                        │
        └──────── ONE v4 payload, one write ─────┘
```
Both ride in the same file because a demolish must persist the credited
Blueprints and the discarded building together — a crash between two writes
either duplicates the yield or destroys it. A refused RUN still surrenders its
Meta via `SaveCodec.salvage_meta`.

## Data flow (one sim tick, fixed written order)

```
metrics.advance -> spawn -> move/doors -> deliver -> auto-dispatch
  -> expire -> tenancy.accrue -> market.step -> note_ticks
```
Order is player-visible: **deliver BEFORE expire** → a passenger at exactly 0
patience when the doors open pays and extends the combo. **Market AFTER
tenancy.accrue** → a floor vacated this tick starts its fill countdown this
tick (vacant tower floors refill via `sim/market.gd`, 600 ticks, free).

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
| `upgrades.json` `floor.max_level` | 14 | the ladder's TOP rung = 20 floors. The LIVE cap is per-run, from `Meta.height_cap()`, and starts at **10** |
| `Meta.MAX_HEIGHT_CAP` | 20 | this release's ladder top; **not** MAX_FLOORS |
| `Prestige.DEMOLITION_FLOOR` | 900.0 | flat earnings offset; breaks the square root's scale invariance |
| `Meta.MAX_BLUEPRINTS` | 1e9 | **== `Prestige.MAX_YIELD`**, pinned by a test |
| `SimClock.TICK_SECONDS` | 0.05 | sim runs at 20Hz (physics is 60Hz) |
| `SimClock.TICKS_PER_REAL_MINUTE` | 1200 | elapsed real time |
| `SimClock.TICKS_PER_SIM_MINUTE` | 600 | one traffic bucket = 30 real s → a day is 12 real minutes |
| `SimClock.START_MINUTE` | 6 | the day opens at the morning rush |
| `game_root.gd` START_* | floors 6, shafts 1, seed 20260802 | new-game defaults |
| `game_root.gd` HUD_HEIGHT / TOUCH_MIN | 96 / 88 | 88pt = 48pt at the 0.546 iPhone scale |
| `SaveCodec.VERSION` | 4 | v1/v2/v3 migrate on read; v4 adds the `meta` block |
| `SaveStore` paths | save.json / .tmp / **.bak** | writes are a real replace, not delete-then-rename |

## Status

Milestones 1–3, the board/management UI, the cost-curve work, Spec A (tenant
kinds + floor class), **S5 (prestige)**, the **people-and-car** pass and the
**tenant market** (market-drawn tenants, renovation evicts, basement-only
lease) are built and tested. 786 GUT tests.

S5: a run caps at **10 floors** and ladders to 20 via the `height` node.
`sim/meta.gd` owns the persistent tree, `sim/prestige.gd` the demolish (which
BUILDS a fresh GameState against a CLONED Meta rather than wiping the live one).
Save format v4. `data/blueprints.json` is fatal-if-malformed.

People-and-car: a passenger is a drawn figure (`view/person_sprite.gd`) with a
badge and a patience bar, the hall packs a 20×40 cell via `ChipGrid`, and riders
stand in ranks on the car floor laid out by `view/car_rack.gd`, with a pip strip
as the occupancy gauge. The board constants moved to `FLOOR_HEIGHT=120`,
`SHAFT_WIDTH=230` (`FloorRow.STRIP_WIDTH=144`), derived against the DEVICE board.

Measured, and load-bearing for any balance work: run 1 yields **13 BP**, because
`combo` multiplies `lifetime_earnings` — the field the conversion consumes — by
~7.6x on a well-played 10-floor run. The tree's costs are denominated in that.
