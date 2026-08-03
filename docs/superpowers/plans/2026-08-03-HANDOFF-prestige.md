# Handoff prompt — plan and build S5 (Prestige / Blueprints)

Copy everything below the line into a fresh session started in
`/Users/sean/sites/elevator-game-godot`.

---

You are picking up an in-progress Godot 4.7 game. Milestones 1–3, the board and
management UI, and the cost-curve work are built, tested and deployed. Your job
is system **S5 — prestige**: demolish the building, convert the run's earnings
into Blueprints, spend them on a permanent tech tree, start again.

There is a **design spec but no implementation plan**. Writing the plan is step
one.

## What this is

An incremental/idle game about elevators, played on an iPhone through GitHub
Pages, so the threadless web export is the primary target. You drag on a shaft
column to send a car to a floor, deliver passengers before their patience runs
out, and buy your way out of doing it by hand.

## Read these first, in this order

1. **`docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md`** —
   the spec. ~2,200 lines. It is the product of four multi-model review rounds
   and is unusually dense with *"do not do the obvious thing, here is why"*.
   §7 (the code), §9 (save format v4 and validation) and §11 (the save
   algorithm) are where the hard-won detail lives.
2. **`docs/superpowers/specs/2026-08-03-prestige-ladder-sim.py`** — the
   simulation that produces every number in §2 and §6. Run it
   (`python3 <path>`). It validates its supply model against the cost-curve spec
   and **raises** on drift or on an unaffordable row. Do not hand-edit a balance
   table; change the script and re-read its output.
3. **`docs/superpowers/specs/2026-08-03-backlog-systems-design.md`** — decisions
   12, 13, 14 and 19, which S5 implements (and, for 12, partly revises).
4. `docs/superpowers/specs/2026-08-03-building-cost-curve-design.md` — the cost
   curves §2/§6 are denominated in. Short.
5. `CLAUDE.md` and `codemaps/` for the architecture. **Note `CLAUDE.md`'s
   single-test commands are wrong** — see Ground truth below.

## Your task

1. **Write the plan** with `superpowers:writing-plans`, into
   `docs/superpowers/plans/2026-08-03-prestige-and-blueprints.md`.
2. **Execute it** with `superpowers:executing-plans`, TDD, commit per task.

Sequence the plan so the two prerequisites land first (below). §12 of the spec
is already a near-complete test list — use it as the spine.

## Prerequisites — these ship before demolish does

- **`SaveStore.save()` must become a real replace.** Today it is
  `remove(PATH)` then `rename(TEMP, PATH)` (`game/save_store.gd:35-37`), so a
  crash in that window leaves **no save at all**. §11 specifies the six-step
  replacement exactly, including why each step is where it is. Demolish is the
  one write whose loss is unrecoverable.
- **The error screen must name its file.** `game_root.gd:215` is a hardcoded
  `"No valid tenant catalog\n\n%s\n\nCannot start."` and `:223` exposes only a
  bool. §8 and §12 both require it to name `blueprints.json`, and the cold-boot
  branch in §9 calls it directly.

## Ground truth — verified, do not re-derive

- Godot **4.7.stable.official.5b4e0cb0f** at `/opt/homebrew/bin/godot`.
- **Test commands (`CLAUDE.md` is wrong; `codemaps/tests.md:10-11` is right):**
  - whole suite: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
  - one file: `-gtest=res://tests/test_x.gd` — **`-gdir` takes a directory, not a file**
  - one test: `-gunit_test_name=test_name` — **`-ginclude` does not exist**
  - The documented-but-wrong form prints `[GUT ERROR] Nothing was run` **and
    exits 0** — a false green. Fix `CLAUDE.md` in this pass.
- Run `godot --headless --import` after adding any file with a new `class_name`.
- **The sandbox blocks Godot's user data dir.** Any `godot` run fails with
  "Could not create directory: ~/Library/Application Support/Godot/…" then
  signal 11. Re-run with `dangerouslyDisableSandbox: true`.
- **GUT fails a test on unhandled engine errors** (`addons/gut/error_tracker.gd:35`,
  raised at `gut.gd:624-625`). This makes §12's "returns null **without
  throwing**" assertions real and observable.

### GDScript semantics measured on this checkout

These cost four review rounds to establish. Several contradict the intuitive
reading, and one contradicts an earlier round's *inference*.

- **A runtime error aborts only the frame it occurs in.** The caller resumes at
  the next statement and the aborted call yields its declared return type's
  default: `-> bool` → `false`, `-> Dictionary` → `{}`, `-> RefCounted` → `null`,
  `-> int` → `0`. It does **not** unwind to the engine callback.
- **A constructor that errors returns a half-built object** — every field below
  the abort point at its declared default — and the caller resumes. This is why
  `GameState._valid` must default to `false`.
- `int({})`, `float({})`, `bool({})`, `bool("abc")` → *"Nonexistent X
  constructor"* errors. But **`int("abc") == 0` and `float("abc") == 0.0` with no
  error** — strings coerce silently everywhere except `bool()` and typed-container
  assignment.
- `int(INF) == int(roundf(INF)) == int(1e308) == int(9.3e18) ==
  9223372036854775807` on arm64 (platform-defined; WASM unverified).
  `int(NAN) == 0`.
- `maxf(NAN - 900.0, 0.0) == 0.0` but `maxf(0.0, NAN - 900.0) == nan`;
  `minf(NAN, 1e9) == 1e9`; `clampf(NAN, 1, 10) == nan`. **Argument order in
  `yield_for` is load-bearing** — §12 pins `yield_for(NAN) == 0`.
- `JSON.parse_string('{"c": 1e400}')` → `inf`. **`Dictionary.get` returns a
  *stored* `null` rather than the default**, so `for car in data.get("cars", [])`
  throws on `{"cars": null}`. `for x in 5` iterates 0..4 and does *not* throw.
- `is_finite(Dictionary)` is itself a runtime error — "type first, then value" is
  load-bearing inside the preflight, not just in the tables.
- **`DirAccess.rename` onto an existing destination silently overwrites**
  (`err == 0`). The save algorithm's ordering depends on not relying on this.
- `dir.file_exists(path)` is **false** for a directory; `DirAccess.remove` works
  on an empty one. This is what makes §12's directory-at-`user://save.json`
  failure fixture work — and what makes it leak past `SaveStore.clear()`.

## Non-negotiable constraints

Each is a review finding that was expensive to discover. A "simplification" here
reopens a closed defect. The spec explains every one; this is the index.

**Prestige transaction**

- **`Prestige.demolish` stages a *cloned* Meta and credits the clone.** It took
  three attempts to get right. `GameState` holds the Meta **by reference**, so
  crediting the shared object before the caller's save can fail leaves the live
  run holding Blueprints it never earned — and the 10-second autosave then makes
  that durable beside a still-demolish-eligible building. Order: clone → credit
  clone → build → validate → return.
- **`_on_demolish` writes before swapping state**, and checks the returned bool.
- **`E` is per-run.** `lifetime_earnings` resets because a fresh `GameState` is
  constructed. Making it cumulative mints Blueprints without limit — demolish
  twice with no play in between and it pays twice.

**Save/decode**

- **`decode` keeps returning `null` on refusal.** Five existing tests assert it
  (`tests/test_save_codec.gd:120, :126, :131, :136, :211`). Salvage is a
  *separate* `SaveCodec.salvage_meta` + `SaveStore.load_meta`.
- **Salvage never calls `legacy_meta()`** — it would mint the whole cap ladder
  from a `floor_count` the refusal just declared untrustworthy.
- **Salvage reads the *unmigrated* dictionary.** Migration never touches the
  `"meta"` key, and migrating there re-exposes the aborts the preflight guards.
- **`GameState._valid` defaults to `false`**, set true as the last statement of
  `_init`.
- **`Meta.is_usable()` is a stored flag**, not `not _defs.is_empty()`. A partial
  defs load would otherwise report usable, and `restore`'s iterate-`ids()` rule
  then silently drops every `spent` entry for the missing nodes.
- **Defs load before any restore, and `Meta.load_defs` must not clear `_spent`**
  — `Upgrades.load_defs` zeroes `_levels` (`sim/upgrades.gd:42`), and a faithful
  mirror would wipe the tree.
- **`to_dict()`/`restore()` never alias `_spent`**, or the clone re-creates
  shared mutable state.
- **Clamp, don't refuse, for save data; refuse for shipped data.** This is a
  declared departure from base design §8.6, for a stated reason: `SaveStore` has
  no backup-before-refuse and `game_root` has no `writes_disabled` latch, so
  refusing a save deletes a building.
- **Read `spent` by iterating `ids()`, never the parsed dictionary's keys.**
- **Type-guard every save-derived conversion in a frame that can still refuse** —
  in `decode`, not in a `void` callee. `restore_levels` aborting mid-loop returns
  a non-null, half-restored state.

**Sim/view**

- **`_init` never resizes the building**; the saved size is the authority.
- **Cap budgets are measured against `BASE_FLOORS`, not the current size** — the
  other way is a level budget measured against a floor count and halves on reload.
- **`grant_level` never calls `_apply`** and takes the `Building` (Upgrades owns
  no cars; `_sync_car` needs an `ElevatorCar`).
- **The ghost band stays at the cap** — `_on_ghost_input` is also the pan handler.
  Only the label changes, and the tap opens the prestige panel.
- **Confirm/Cancel pair, never an armed double-tap** — touch emulation delivers
  one physical tap twice (`tests/test_board_input.gd:514` exists for this).
- **`_rebuild_views()` frees synchronously and restores sibling order** via
  `move_child`, or the panel scrim covers the HUD.

## The working habit that matters most

This document states each rule in **prose, in a code block, in a test bullet, and
sometimes in a scope list**. Across four review rounds, the single most common
defect — mine and the reviewers' — was changing one copy and leaving its sibling
stale, and three times the stale copy was the one an implementer executes.

**After every edit, grep for the phrasing the old rule used and confirm every hit
is either updated or a deliberate quote.** It costs one command and it caught
three real misses that no reviewer flagged. Do the same when the plan and the
spec disagree: fix both, then grep.

## Known open — decide these, don't discover them

- **`COMBO_MAX = 10.0` is unmeasured.** `Economy.credit_delivery` applies combo
  to `lifetime_earnings`, the exact field the conversion consumes, so run 1
  yields somewhere in **[4, 15] BP against a 6-BP ladder** — the difference
  between the cap ladder taking one run and two. **Measure it on a real run
  before treating `DEMOLITION_FLOOR = 900` as settled.** This is the single
  biggest open question in the spec.
- **Web durability is unverified.** §11's algorithm is specified against desktop
  filesystem semantics and ships to IDBFS, where Godot flushes asynchronously on
  file-handle close rather than on `DirAccess` rename/remove. The headless test
  pins the *logic* only.
- **The `move_child` sibling-order fix is a HYPOTHESIS.** Its premise (child
  order in `_ready`) was confirmed by reading; the input-routing consequence
  needs a scene run.
- **No reviewer ever examined module boundaries.** The Architect seat
  (`antigravity`) was quota-locked across all four rounds while every round moved
  boundaries. If something about the `Meta`/`Prestige`/`GameState`/`SaveCodec`
  split feels wrong as you build it, that instinct has not been checked by
  anyone — take it seriously rather than assuming it was reviewed.
- **~33 spec fixes carry no review.** Rounds 1–3 were reviewed; the `[r5]` and
  `[r6]` edits applied after round 4 were not. They are mostly propagation fixes
  and one-line corrections, and the judgement was that a compiler and the test
  suite settle them faster than a fifth review round. If one looks wrong, it may
  well be.

## Out of scope

Eras, the Human and Automation branches, a starting-floors node, offline
earnings and the catch-up integrator. A cap above 20 floors — §0 explains why,
and §14 item 1 owns unblocking it.

**Do not extend the ladder past 20 floors.** Income is linear in floors while
each floor costs more than the last, so rungs above 20 sell a ceiling nobody
reaches. That is an income-side problem, and decision 14 excludes the one lever
that would fix it from persisting.

## Working style

- TDD as written: failing test first, watch it fail, minimal implementation,
  watch it pass, commit.
- Full suite before each commit. 143+ tests pass on `main` — keep them passing.
- Commit per task, message explaining *why*. Use `git commit -F` if the message
  needs backticks.
- **Regenerate `codemaps/`** (`/cc-codemaps:update-codemaps`) — two new `sim/`
  classes, a new `data/` file and several new test files stale all five maps.
- If the spec says something that turns out to be wrong when you run it, **say so
  and fix the spec**. Most of it encodes a review finding, so a workaround may be
  reopening a closed defect — but four rounds of review did not make it perfect,
  and one premise (GDScript stack unwinding) survived three rounds before being
  measured and found false.
