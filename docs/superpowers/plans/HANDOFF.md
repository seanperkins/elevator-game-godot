# Handoff prompt — execute Milestones 1–3

Copy everything below the line into a fresh session started in
`/Users/sean/sites/elevator-game-godot`.

---

You are picking up an in-progress Godot 4.7 game project. All design work is
done and committed; your job is to implement it.

## What this is

An incremental/idle game about elevators. You drag on a shaft column to send a
car to a floor, deliver passengers before their patience runs out, earn fares
and rent, and buy your way out of doing it by hand. It is played on an iPhone
through GitHub Pages, so the web export is the primary target.

## Read these first, in this order

1. `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md` — the
   design spec. Sections §2.1 (input model), §3 (board constants), §5 (systems),
   §8.3 (tick model and intra-tick order) and §8.5 are the ones you will need
   constantly.
2. `docs/superpowers/plans/2026-08-02-elevator-milestones-1-3.md` — the
   implementation plan. 14 tasks, each with exact file paths, real test code,
   real implementation code, and a commit.

## Your task

Execute the plan task-by-task, starting at **Task 0**.

Use the `superpowers:executing-plans` skill (batched, with checkpoints) or
`superpowers:subagent-driven-development` (a fresh subagent per task) — ask the
user which they prefer before starting if they have not said.

Do not skip Task 0. It vendors GUT, adds the CI test gate, and fixes the
Milestone 0 probe. Everything after it assumes a working `godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.

## Ground truth already verified — do not re-derive

- Godot 4.7.stable is at `/opt/homebrew/bin/godot`. Export templates for 4.7 are
  installed locally.
- GUT **9.7.1** at commit `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` runs
  headless on 4.7 and **exits 0 on pass, 1 on failure** — confirmed by running
  a deliberately failing test.
- `godot --headless --import` run twice: both exit 0.
- SHA-256 of the Godot 4.7 Linux zip: `0b1a6c54c2c619c12e169fe9241edda4b81080b519451cec2984bf0d2c6cb73c`
- SHA-256 of the 4.7 export templates tpz: `9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec`
- Live build: <https://seanperkins.github.io/elevator-game-godot/> — every push
  to `main` rebuilds and redeploys.

## Gotchas that cost real time to find

- **The sandbox blocks Godot's user data dir.** Running `godot` (not just
  `--headless --import`) fails with "Could not create directory:
  ~/Library/Application Support/Godot/..." and then crashes with signal 11.
  That is a sandbox denial, not a code bug. Re-run with
  `dangerouslyDisableSandbox: true`.
- **Godot 4.7 reports some export config errors with an empty message body.**
  If `--export-release` prints "Cannot export project with preset ... due to
  configuration errors:" and then nothing, the cause is usually an
  `export_presets.cfg` option the platform rejects. It previously bit us on
  `vram_texture_compression/for_mobile=true`, which needs "Import ETC2 ASTC" in
  project settings. Bisect the preset options; do not guess.
- **Don't put backticks in a `git commit -m` string.** They break shell quoting.
  Use a message file with `git commit -F`.
- **Regex with `.{0,120}` against minified JS will hang.** `build/web/index.js`
  is one 280 KB line. Use python or a fixed-string search.

## Non-negotiable constraints

These come from the spec and were each established for a reason:

- **The sim never touches the scene tree.** Nothing under `sim/` may reference
  `Node`, `get_node`, or a scene. It is all `RefCounted` so it can be tested
  headlessly.
- **20 sim ticks/second accumulated from 60 Hz physics.** One tick per
  `_physics_process` call runs the sim at 3x speed.
- **The intra-tick order is fixed:** `spawn → move/doors → deliver → expire →
  accrue rent → update combo`. Deliver precedes expire, so a passenger reaching
  exactly 0.0 patience as the doors open is delivered and pays.
- **Touch targets are shaft columns, never cars.** At 40 rows a row is ~17.5 pt
  on an iPhone 15, well under Apple's 44 pt floor. Verbs separate by gesture
  (drag = dispatch, tap = surge), never by tap cadence.
- **Board caps: 40 rows, 8 shafts.** These are design inputs, not incidental.
- **Web export stays threadless.** GitHub Pages cannot set COOP/COEP headers.
- **GL Compatibility renderer.** Forward+ needs WebGPU and is unsafe in Safari.
- **`data/` holds numeric coefficients only** — never expression strings.
  Running stored formulas through `Expression` is an eval.

## Out of scope

Milestones 4–7 are not in this plan: dispatch automation, prestige/Blueprints,
save/offline/lifecycle, eras past Walk-Up, staff, events, freight.

**Do not implement the save or offline systems.** §7 and §9.1 of the spec are
the least-settled part of the design — three rounds of multi-model review kept
finding defects in that machinery, and it needs its own focused design pass
before Milestone 6. If you find yourself writing a save file, stop and ask.

The surge *verb* is wired in Task 10 but is intentionally a no-op. That is not
a bug.

## Working style

- TDD as written: the failing test first, watch it fail, then the minimal
  implementation, then watch it pass, then commit.
- Commit per task, with a message explaining *why* rather than restating the
  diff.
- Run the full suite before each commit, not just the file you touched.
- If the plan says something that turns out to be wrong when you run it, say so
  and fix the plan — do not silently work around it. Several tasks encode
  findings from review; a workaround may be re-opening a closed defect.
