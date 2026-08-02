# Handoff prompt — implement the Board and Management UI

Copy everything below the line into a fresh session started in
`/Users/sean/sites/elevator-game-godot`.

---

You are picking up an in-progress Godot 4.7 game. Milestones 1–3 are built,
tested and deployed; your job is to rebuild its UI from a design that has been
through two rounds of multi-model review.

## What this is

An incremental/idle game about elevators. You drag on a shaft column to send a
car to a floor, deliver passengers before their patience runs out, earn fares
and rent, and buy your way out of doing it by hand. It is played on an iPhone
through GitHub Pages, so the web export is the primary target.

## Read these first, in this order

1. `docs/superpowers/specs/2026-08-02-ui-design.md` — the UI design. §3.2 (the
   coordinate transform), §3.4 (ghost floor and ghost shaft), §4 (input) and §8
   (verification) are the ones you will need constantly.
2. `docs/superpowers/plans/2026-08-02-ui-board-and-management.md` — the plan.
   15 tasks, each with exact file paths, real test code, real implementation
   code, and a commit.
3. `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md` — the
   original game design, for background. Note that §2.1, §3, §8.2, §8.3 and
   §8.5 of it are **out of date**; Task 15 fixes them, and the UI design's §9
   lists exactly what is wrong.

## Your task

Execute the plan task-by-task, starting at **Task 1**.

Use `superpowers:executing-plans`. The tasks are sequential — Task 9 will not
parse until Task 10 lands — so the per-task-subagent approach fits badly here.

## Ground truth already verified — do not re-derive

- Godot 4.7.stable is at `/opt/homebrew/bin/godot`; export templates installed.
- Test command: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
  Exits 0 on pass, 1 on failure. Add `-gtest=res://tests/<file>` for one file.
- Run `godot --headless --import` after adding any file with a new `class_name`,
  or the next run will not see it.
- 143 tests pass on `main` right now. Keep them passing.
- Live build: <https://seanperkins.github.io/elevator-game-godot/> — every push
  to `main` runs the test gate, then builds and deploys.

## Gotchas that cost real time to find

- **The sandbox blocks Godot's user data dir.** Any `godot` invocation fails
  with "Could not create directory: ~/Library/Application Support/Godot/..." and
  then crashes with signal 11. That is a sandbox denial, not a code bug. Re-run
  with `dangerouslyDisableSandbox: true`. This applies to `--import` and the test
  runner too.
- **GDScript lambdas capture by value.** `var n := 0; sig.connect(func(): n += 1)`
  increments a copy and reads back zero. Use an Array and `append`.
- **A `-s` script main loop is uncapped**, so a frame counter compresses an
  intended ten-second sequence into a fraction of a second. Schedule synthetic
  input on accumulated `delta`, not on frame counts.
- **`Input.parse_input_event` is processed asynchronously.** Reading state on the
  line after you inject a release reads the state *before* it. Wait frames.
- **Don't put backticks in a `git commit -m` string.** Use `git commit -F`.

## Non-negotiable constraints

Each of these is a review finding that was expensive to discover. A
"simplification" here reopens a closed defect.

- **The sim never touches the scene tree.** Nothing under `sim/` may reference
  `Node`, `get_node`, or a scene.
- **One row↔y transform, in `sim/coords.gd`, with four consumers.** The board is
  bottom-up. Flipping only the row layout mirrors every dispatch
  *self-consistently* — gesture, rail and car all agree with each other and
  disagree only with the floor labels — so it passes casual play and every
  screenshot. `tests/test_board_input.gd` exists to catch exactly this.
- **`y_to_floor` compares against a stored edge table; it does not divide.**
  `N-1-floor(y/h)` is not an identity in IEEE double: at 29 floors the lobby's
  own top edge resolves to floor 1, and twelve of the forty floor counts have at
  least one floor that fails that way.
- **The shaft viewport spans the floors only, not the ghost band.** That inset is
  what keeps the cancel edge out of the lobby's dispatch band and what makes the
  ghost band tappable.
- **There must always be one trailing empty shaft slot below the cap.** Without
  it, five owned shafts fill all five visible positions and shafts 6–8 are
  unbuyable forever, while `tests/test_upgrades.gd` stays green.
- **`GameState.relet` reads `relet_cost` *before* reletting.** The cost derives
  from `tenanted_count()`, which `relet()` changes, so the order decides whether
  the last row costs nothing or forty dollars.
- **Metrics advances first in the tick order and owns its own tick counter.**
  `clock.note_ticks(1)` runs last, so deriving the bucket index from `SimClock`
  files every event one bucket behind.
- **Zero-delta upgrade levels are refused by `Upgrades.purchase()`,** not only
  greyed in the view. Two taps queued during a stalled frame would otherwise buy
  door level 8 and then charge $832 for level 9.
- **No tenant status text on the board.** Two earlier placements each collided
  with something. The 4-unit bar carries all three states.
- **Board caps: 40 floors, 8 shafts. Touch targets 44pt.** The one exception is
  the re-lease confirm, which exists *because* a floor row cannot meet it.

## Out of scope

Milestones 4–7: dispatch automation, prestige/Blueprints, save/offline/lifecycle,
eras past Walk-Up, staff, events, freight. Juice and animation beyond what
exists. Surge stays a wired no-op.

**Do not implement the save or offline systems.** §7 and §9.1 of the original
design spec are the least-settled part of the design and need their own focused
pass before Milestone 6. If you find yourself writing a save file, stop and ask.

## Working style

- TDD as written: the failing test first, watch it fail, then the minimal
  implementation, then watch it pass, then commit.
- Run the full suite before each commit, not just the file you touched.
- Commit per task, with a message explaining *why* rather than restating the diff.
- **Verify the view by driving it, not by asserting it looks fine.** Task 11
  builds the harness; before it exists, a throwaway `-s` script that instantiates
  `game_root.tscn`, injects input and saves a PNG is the way to see the board.
  Screenshots go to `user://` — the path is printed by
  `ProjectSettings.globalize_path`.
- If the plan says something that turns out to be wrong when you run it, say so
  and fix the plan. Several tasks encode findings from review; a workaround may
  be re-opening a closed defect. The plan itself names one known rough edge at
  the end of its Self-Review section.
