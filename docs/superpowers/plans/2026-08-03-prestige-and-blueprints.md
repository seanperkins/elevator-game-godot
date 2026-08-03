# Prestige and Blueprints (S5) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Ship the demolish action, the Blueprint currency, a five-node
persistent tech tree, a per-run floor cap that starts at 10 and ladders to 20,
save format v4, and the UI to drive all of it.

**Architecture:** Two new pure-sim classes. `sim/meta.gd` owns the persistent
half of the game (Blueprints, node levels, and the derivations a run starts
from); `sim/prestige.gd` owns the one operation that ends a run, and does it by
**building a fresh `GameState` against a cloned Meta** rather than by wiping the
live one. `GameState` reads the Meta and never writes it. The Meta rides in the
save file beside the run, so a demolish is one write. `game_root` swaps the whole
state and rebuilds its views.

**Tech Stack:** Godot 4.7 (`/opt/homebrew/bin/godot`), GDScript, GUT for tests,
JSON data files under `data/`.

## Source documents

Read before starting; this plan is a build order, not a replacement for them.

- `docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md` — **the
  spec.** Every task below cites the section it implements. §7 (code), §9 (save
  format), §11 (the save algorithm) carry the hard-won detail.
- `docs/superpowers/specs/2026-08-03-prestige-ladder-sim.py` — produces every
  number in §2 and §6. Run it (`python3 <path>`); it validates its supply model
  against the cost-curve spec and **raises** on drift. Verified reproducing on
  2026-08-03. Do not hand-edit a balance table — change the script.
- `docs/superpowers/specs/2026-08-03-backlog-systems-design.md` — decisions 12,
  13, 14, 19.
- `CLAUDE.md`, `codemaps/` — architecture.

---

## Global Constraints

- **Layering.** `sim/` is pure `RefCounted`: no Nodes, no scene tree. `view/` and
  `ui/` read sim state and emit signals; they never mutate logic. `game_root.gd`
  is the single owner.
- **`data/` holds numeric coefficients only** — never expression strings.
- **The tick order does not change.** Prestige adds no phase and runs entirely
  between ticks.
- **`Building.MAX_FLOORS = 40` and `Building.MAX_SHAFTS = 8` do not change.**
  They are structural, and the spawner's saturation guard (`40 × 3.0 = 120`
  against `TICKS_PER_SIM_MINUTE = 600`) is sized against them.
- **`data/upgrades.json` is not edited at all.** The ladder tops out at 20 floors,
  so `floor.max_level = 14` *is* the top rung (spec §1).
- **The ladder must not be extended past 20 floors** (spec §0 / §14 item 1).
- **Every dynamic string renders through `Label`, never BBCode** — the build
  shares a `github.io` origin with every other Pages site on the account.
- **Touch targets are 88 units** (48pt at the 0.546 board scale). Not negotiable
  downward.
- **Clamp, don't refuse, for *save* data; refuse for *shipped* data.** This is a
  declared override of base design §8.6, because `SaveStore` has no
  backup-before-refuse and `game_root` has no `writes_disabled` latch, so
  refusing a save deletes a building (spec §9).
- **Type-check before value-check, everywhere.** `is_finite(Dictionary)` and
  `int({})` are themselves runtime errors.
- **Clamp integral casts in float space before `int()`.** Out-of-range float→int
  is platform-defined and the ship target (threadless WASM) is a different
  toolchain from the dev machine.

## Ground truth — verified, do not re-derive

- Godot **4.7.stable.official.5b4e0cb0f** at `/opt/homebrew/bin/godot`.
- **Test commands** (`CLAUDE.md` is wrong today; Task 1 fixes it):
  - whole suite: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
  - one file: `-gtest=res://tests/test_x.gd` — **`-gdir` takes a directory**
  - one test: `-gunit_test_name=test_name` — **`-ginclude` does not exist**
    (confirmed: `grep ginclude addons/gut/gut_cmdln.gd` returns nothing)
- Run `godot --headless --import` after adding any file with a new `class_name`.
- **The sandbox blocks Godot's user data dir.** Every `godot` invocation fails
  with "Could not create directory: ~/Library/Application Support/Godot/…" then
  signal 11. Re-run with `dangerouslyDisableSandbox: true`.
- **GUT fails a test on unhandled engine errors** (`addons/gut/error_tracker.gd:35`,
  raised at `gut.gd:624-625`). This is what makes the "returns null **without
  throwing**" assertions real.

### GDScript semantics measured on this checkout

Several contradict the intuitive reading. Do not "simplify" against them.

- **A runtime error aborts only the frame it occurs in.** The caller resumes at
  the next statement and the aborted call yields its declared return type's
  default (`-> bool` → `false`, `-> Dictionary` → `{}`, `-> RefCounted` → `null`,
  `-> int` → `0`). It does **not** unwind to the engine callback.
- **A constructor that errors returns a half-built object**, every field below
  the abort point at its declared default, and the caller resumes. This is why
  `GameState._valid` must default to `false`.
- `int({})`, `float({})`, `bool({})`, `bool("abc")` are errors. But
  **`int("abc") == 0` and `float("abc") == 0.0` with no error** — strings coerce
  silently everywhere except `bool()` and typed-container assignment.
- `int(INF) == int(1e308) == int(9.3e18) == 9223372036854775807` on arm64
  (platform-defined; WASM unverified). `int(NAN) == 0`.
- `maxf(NAN - 900.0, 0.0) == 0.0` but `maxf(0.0, NAN - 900.0) == nan`;
  `clampf(NAN, 1, 10) == nan`. **Argument order in `yield_for` is load-bearing.**
- `JSON.parse_string('{"c": 1e400}')` → `inf`. **`Dictionary.get` returns a
  *stored* `null` rather than the default**, so `for car in data.get("cars", [])`
  throws on `{"cars": null}`. `for x in 5` iterates 0..4 and does not throw.
- **`DirAccess.rename` onto an existing destination silently overwrites**
  (`err == 0`). The save algorithm must not rely on this.
- `dir.file_exists(path)` is **false** for a directory; `DirAccess.remove` works
  on an empty one.

## Decisions made in this plan (the spec left them open)

1. **`Meta.is_zero_delta` takes the run's `Upgrades`** rather than making
   `Upgrades.effect_value` static — spec §7 offers both and this one changes no
   existing call site. It evaluates at the **Meta's** level, never the run's.
2. **A demolish resets dispatch policies to MANUAL** (spec §14 item 6). The
   licences (`upgrades.level_of("auto")`) reset with everything else, so a
   retained preference is state that either does nothing or grants free
   automation. Revisit if playtesting says the re-toggle is a chore.
3. **S5 ships before S4's signed-coordinate work** (spec §14 item 4), overriding
   the backlog's sequencing rule explicitly. The reason the rule exists is that
   the coordinate change is cheaper on a short building — and this ladder tops
   out at 20 floors, which the game already delivers today. S5 does not make the
   building taller than S4 would already have to handle.
4. **`SaveStore` exposes `load_all()` returning `{state, meta}` from one
   `_select()`**, and `load_state()` / `load_meta()` remain thin wrappers so the
   28 existing one-argument call sites in `tests/` stay source-compatible.
   `game_root` calls **only** `load_all`, which is what makes §11's
   "one selection, one parsed dictionary, both consumers fed from it" true in
   production. Spec §9's cold-boot snippet is updated to match in Task 17.
5. **`DEMOLITION_FLOOR` is measured before it is trusted** — Task 2. The spec's
   900 is derived from a model that excludes combo, and `COMBO_MAX = 10.0`
   multiplies the exact field the conversion consumes.

## The working habit that matters most

The spec states each rule **in prose, in a code block, in a test bullet, and
sometimes in a scope list**. Across four review rounds the most common defect was
changing one copy and leaving its sibling stale, and three times the stale copy
was the one an implementer executes.

**After every edit to a spec or plan, grep for the phrasing the old rule used and
confirm every hit is either updated or a deliberate quote.** One command; it
caught three real misses no reviewer flagged.

## Working style

- TDD as written: failing test first, **watch it fail**, minimal implementation,
  watch it pass, commit.
- **Full suite before every commit.** 143+ tests pass on `main`; keep them
  passing. A commit whose suite was not run is not done.
- One commit per task, message explaining *why*. Use `git commit -F` when the
  message needs backticks.
- If the spec turns out to be wrong when you run it, **say so and fix the spec**
  in the same commit. Most of it encodes a review finding, so a workaround may be
  reopening a closed defect — but four rounds did not make it perfect, and one
  premise (GDScript stack unwinding) survived three rounds before being measured
  and found false.

---

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `sim/meta.gd` | `class_name Meta` — the persistent half: Blueprints, node levels, the defs loader, and the derivations a run starts from. Knows nothing about `GameState`. |
| `sim/prestige.gd` | `class_name Prestige` — static only. The one place that knows a run can end. |
| `data/blueprints.json` | the five nodes' numeric coefficients |
| `ui/prestige_panel.gd` | the tree, the yield line, and the Confirm/Cancel rebuild |
| `tests/test_meta.gd` | Meta unit tests |
| `tests/test_prestige.gd` | conversion and demolish tests |
| `tests/test_save_store.gd` | the real-replace algorithm |
| `tools/measure_combo.gd` | Task 2's headless measurement harness (deleted at the end of Task 2) |

**Modified**

| file | change |
| --- | --- |
| `game/save_store.gd` | six-step real replace, `BACKUP_PATH`, `_select`, `load_all`, `has_save`, `clear` |
| `game/game_root.gd` | `BASE_*` references, parameterised error screen, cold-boot salvage, `_on_demolish`, `_rebuild_views`, `save_now` signature, prestige panel wiring |
| `sim/game_state.gd` | `BASE_FLOORS`/`BASE_SHAFTS`/`BASE_SEED`, `meta`, retained paths, `_valid` default false, `_init`'s cap and grant wiring |
| `sim/save_codec.gd` | v4, preflight, `_migrate_to_v4`, meta encode/decode, `salvage_meta`, the validation tables |
| `sim/upgrades.gd` | `set_max_level`, `grant_level`, the `note` loader fix |
| `view/building_view.gd` | the ghost band's label and tap at the cap |
| `ui/management_view.gd` | REBUILD heading, `blueprints` stat |
| `tests/test_board_input.gd` | `build_to(n)` fixture, scene-level demolish tests, ghost-band-at-cap test |
| `tests/test_save_codec.gd` | v4 coverage, the hostile matrix, the generative sweep |
| `tests/test_upgrades.gd` | `set_max_level` / `grant_level` coverage |
| `CLAUDE.md` | test commands, status |
| `codemaps/*.md` | regenerated |

---

## Task 1: Fix the documented test commands

**Why first:** every later task's verification runs through these. The documented
form prints `[GUT ERROR] Nothing was run` — a false green before a commit. Spec
§14 item 7 flags it and asks for the exit code to be re-checked rather than
quoted.

**Files:**
- Modify: `CLAUDE.md:29-31`

- [ ] **Step 1: Measure the failure mode rather than quoting it**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_tenancy.gd -gexit; echo "exit=$?"
```

(Run with `dangerouslyDisableSandbox: true`.) Record the exit code. Expected:
`[GUT ERROR] Nothing was run`. The spec claims exit 0 without having run it —
whatever you observe is what goes in the file.

- [ ] **Step 2: Verify the working forms**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tenancy.gd -gexit
grep -c ginclude addons/gut/gut_cmdln.gd   # expect 0
```

- [ ] **Step 3: Correct `CLAUDE.md`**

Replace the two bullets under Commands with:

```markdown
- **Run a single test file:** `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_tenancy.gd -gexit` — **`-gdir` takes a directory, not a file.**
- **Run one named test:** add `-gunit_test_name=test_name`. There is no `-ginclude`.
- The `-gdir=<file>` / `-ginclude` forms print `[GUT ERROR] Nothing was run` and do **not** run your test — a false green before a commit.
```

- [ ] **Step 4: Update the spec's open item**

In `…-prestige-and-blueprints-design.md` §14 item 7, replace the unverified
*"and exits 0"* clause with the exit code measured in Step 1.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md
git commit -m "Fix the documented single-test commands, which never ran anything

-gdir takes a directory and -ginclude does not exist at any GUT version in
this checkout, so both documented forms printed 'Nothing was run'. Every
verification step in the prestige work runs through these."
```

---

## Task 2: Measure the realised combo multiplier, and settle `DEMOLITION_FLOOR`

**Why:** spec §6 and §14 item 2 call this the single biggest open question.
`Economy.credit_delivery` applies `combo` to `lifetime_earnings` — the exact
field `yield_for` consumes — and `COMBO_MAX = 10.0`. The §6 model **excludes
combo**, so run 1's yield is somewhere in **[4, 15] BP against a 6-BP ladder**:
the difference between the cap ladder taking one run and two. `DEMOLITION_FLOOR`
cannot be treated as settled until this is a number.

**Files:**
- Create: `tools/measure_combo.gd` (deleted in Step 6)
- Modify: `docs/superpowers/specs/2026-08-03-prestige-ladder-sim.py` (only if the
  measurement moves the constant)
- Modify: `docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md`
  §2.2, §6, §14 item 2

- [ ] **Step 1: Write the harness**

This is a measurement, not a shipped feature, so it is a `-s` script rather than
a GUT test. It runs the **real** sim with a greedy buy policy close to §6's, and
reports what a first run actually earns.

```gdscript
extends SceneTree

## Measures what a real run earns, WITH combo, against the combo-free model in
## the prestige spec's §6. Deleted once its number is recorded -- it exists to
## answer one question, not to be maintained.
##
## Run: godot --headless -s tools/measure_combo.gd

const RUN_TICKS := 174_000        # 2h25m at 20Hz, the spec's rate-optimal exit
const REPORT_EVERY := 12_000      # every 10 real minutes

func _init() -> void:
	for cap in [10, 20]:
		_run(cap)
	quit()

func _run(cap_floors: int) -> void:
	var state := GameState.new(6, 1, 20260802)
	# Stand in for the cap this spec has not built yet.
	var max_floors := cap_floors - 6
	var fare_sum := 0.0        # what the fares would have paid at combo 1.0
	state.passenger_delivered.connect(
		func(p: Passenger, _paid: float) -> void: fare_sum += p.fare)

	print("\n=== cap %d floors ===" % cap_floors)
	print("  min   floors  cash        lifetime    combo   mult")
	for tick in range(RUN_TICKS):
		state.tick(1)
		_buy_something(state, max_floors)
		if (tick + 1) % REPORT_EVERY == 0:
			var mult := state.economy.lifetime_earnings / maxf(fare_sum, 0.0001)
			print("  %4d  %6d  %10.0f  %10.0f  %5.2f  %5.2fx" % [
				(tick + 1) / 1200, state.building.floor_count,
				state.economy.cash, state.economy.lifetime_earnings,
				state.economy.combo, mult])
	var e := state.economy.lifetime_earnings
	print("  E = %.0f   combo-free E = %.0f   realised multiplier = %.2fx"
		% [e, fare_sum, e / maxf(fare_sum, 0.0001)])
	for offset in [900.0, 1500.0, 3000.0, 6000.0]:
		print("    yield at DEMOLITION_FLOOR=%.0f : %d BP"
			% [offset, int(sqrt(maxf(e - offset, 0.0) / 100.0))])

## The spec's simulated player: the cheapest thing that helps, every sim minute.
## Floors first while the cap allows, then whatever mechanical upgrade is
## affordable, cheapest first.
func _buy_something(state: GameState, max_floors: int) -> void:
	if state.clock.ticks_executed % 600 != 0:
		return
	if state.upgrades.level_of("floor") < max_floors:
		if state.buy("floor"):
			# A new floor is worth nothing untenanted.
			var top := state.building.floor_count - 1
			var kinds := state.available_kinds(top)
			if not kinds.is_empty():
				state.lease(top, kinds[0].id)
			return
	var best := ""
	var best_cost := INF
	for id in ["speed", "doors", "capacity"]:
		if state.upgrades.is_maxed(id) or state.upgrades.is_zero_delta(id):
			continue
		var c := state.upgrades.cost_of(id)
		if c < best_cost:
			best_cost = c
			best = id
	if not best.is_empty():
		state.buy(best)
```

- [ ] **Step 2: Run it**

```bash
godot --headless --import
godot --headless -s tools/measure_combo.gd
```

(Both with `dangerouslyDisableSandbox: true`.) Expect a few minutes of wall
clock for 348,000 ticks.

- [ ] **Step 3: Apply the decision rule**

Let `M` be the realised multiplier at cap 10 and `E₁` the run-1 earnings.

| observation | action |
| --- | --- |
| `yield_for(E₁)` lands in **[2, 6] BP** | `DEMOLITION_FLOOR = 900` stands. Record `M` and `E₁` in §6 and close §14 item 2. |
| `yield_for(E₁) > 6 BP` | The cap ladder falls out of run one. Raise the offset: in the python sim, multiply the fare (`FARE`) by `M`, re-run, and read the new offset off its section-6 table using the **same** criteria the spec used — `height` not inert, and a gap outside model noise. Then update §2.2's constant, its table, §6's tables, and `Prestige.DEMOLITION_FLOOR`. |
| `yield_for(E₁) < 2 BP` | Run one cannot fund `height` L1 and the ladder stalls. Lower the offset by the same procedure. |

**Do not scale the offset by `M`.** Spec §2.1 shows the exit point is not a
simple function of the constant; re-derive it from the simulation.

- [ ] **Step 4: Record the measurement in the spec**

Rewrite §14 item 2's first clause from *"the realised value has never been
measured on a real run"* to the measured multiplier, the date, and the harness
that produced it. Add the same figure to §6's *"How big a floor"* paragraph,
replacing the `[1, 10]` band with the measured value.

- [ ] **Step 5: Grep for stale siblings**

```bash
grep -rn "COMBO_MAX\|\[4, 15\]\|\[1, 10\]\|900" docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md
```

Every hit is either updated or a deliberate quote of a superseded claim. This is
the habit the spec's own history says matters most.

- [ ] **Step 6: Delete the harness and commit**

```bash
rm tools/measure_combo.gd tools/measure_combo.gd.uid
git add -A docs/superpowers/specs tools
git commit -F - <<'EOF'
Measure what a run actually earns, so DEMOLITION_FLOOR is a number and not a hope

`Economy.credit_delivery` applies combo to `lifetime_earnings`, which is the
exact field the Blueprint conversion consumes, and the §6 model excludes it.
That left run 1's yield somewhere in [4, 15] BP against a 6-BP ladder -- the
difference between the cap ladder taking one run and two. Now measured on the
real sim.
EOF
```

---

## Task 3: `SaveStore` becomes a real replace

**Why:** spec §0 calls this a prerequisite and §11 says demolish cannot ship
without it. Today `save()` is `remove(PATH)` then `rename(TEMP, PATH)`
(`game/save_store.gd:35-37`), so a crash in that window leaves **no save at
all** — the building *and* the Blueprints.

**Files:**
- Modify: `game/save_store.gd`
- Test: `tests/test_save_store.gd` (create)

**Interfaces:**
- Produces:
  - `const BACKUP_PATH := "user://save.json.bak"`
  - `static func save(state: GameState) -> bool` (unchanged signature, real replace)
  - `static func has_save() -> bool` — true when `PATH` **or** `BACKUP_PATH` exists
  - `static func clear() -> void` — removes `PATH`, `TEMP_PATH`, `BACKUP_PATH`, and a *directory* at `PATH`
  - `static func load_all(catalog_path := "res://data/tenants.json", blueprints_path := "res://data/blueprints.json") -> Dictionary` — `{"state": GameState (may be null), "meta": Meta (may be null)}`, from **one** `_select()`
  - `static func load_state(catalog_path := …, blueprints_path := …) -> GameState`
  - `static func load_meta(blueprints_path := …) -> Meta`

`load_all`'s Meta half lands in Task 12 — this task builds the file handling and
`_select`, and leaves `load_all` returning `{"state": …, "meta": null}` with a
`# Task 12` marker. Everything else here is final.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_save_store.gd`:

```gdscript
extends GutTest

## The save file is the one thing a player cannot re-earn, and after prestige it
## carries permanent progress. These tests are about the FILE HANDLING only --
## what goes in it is test_save_codec.gd's job.

func before_each() -> void:
	SaveStore.clear()

func after_each() -> void:
	SaveStore.clear()

func fresh() -> GameState:
	return GameState.new(6, 1, 1)

func write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_a_save_over_an_existing_file_succeeds_and_loads_back() -> void:
	assert_true(SaveStore.save(fresh()), "first save")
	assert_true(SaveStore.save(fresh()), "second save, over the first")
	assert_not_null(SaveStore.load_state(), "the replaced file still loads")

func test_a_pre_existing_backup_does_not_brick_the_next_save() -> void:
	# The bricking case: a crash between the commit and the cleanup leaves both
	# PATH and BACKUP present, and an algorithm that cannot rename onto an
	# existing destination would then fail forever.
	assert_true(SaveStore.save(fresh()), "seed a real save")
	write_raw(SaveStore.BACKUP_PATH, "{}")
	assert_true(SaveStore.save(fresh()), "a stale backup must not block rotation")

func test_load_state_falls_back_to_the_backup_when_the_save_is_gone() -> void:
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	assert_false(FileAccess.file_exists(SaveStore.PATH), "PATH is gone")
	assert_not_null(SaveStore.load_state(), "the backup is loadable")

func test_has_save_agrees_with_load_state() -> void:
	# Otherwise test_board_input.gd:641's assert_false(has_save()) silently
	# stops meaning what it says.
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	assert_true(SaveStore.has_save(), "a backup-only state still has a save")

func test_clear_removes_the_backup_too() -> void:
	assert_true(SaveStore.save(fresh()), "seed")
	write_raw(SaveStore.BACKUP_PATH, "{}")
	SaveStore.clear()
	assert_false(FileAccess.file_exists(SaveStore.BACKUP_PATH),
		"a surviving backup becomes the fixture for every later test")

func test_a_save_whose_temp_write_fails_leaves_the_old_save_intact() -> void:
	# A DIRECTORY at TEMP_PATH makes FileAccess.open fail for real, through
	# save()'s own code path, rather than through a double the static call
	# site could never see.
	assert_true(SaveStore.save(fresh()), "seed a real save")
	var dir := DirAccess.open("user://")
	if dir.file_exists(SaveStore.TEMP_PATH):
		dir.remove(SaveStore.TEMP_PATH)
	dir.make_dir(SaveStore.TEMP_PATH)
	assert_false(SaveStore.save(fresh()), "the write cannot succeed")
	assert_not_null(SaveStore.load_state(), "and the old save survived it")
	dir.remove(SaveStore.TEMP_PATH)

func test_a_corrupt_save_beside_a_good_backup_is_recovered() -> void:
	# _select skips the unparseable PATH; step 1 must then REMOVE it before
	# promoting, or step 3 deletes the only loadable copy.
	assert_true(SaveStore.save(fresh()), "seed")
	var dir := DirAccess.open("user://")
	dir.rename(SaveStore.PATH, SaveStore.BACKUP_PATH)
	write_raw(SaveStore.PATH, "{ this is not json")
	assert_not_null(SaveStore.load_state(), "the good backup is selected")
	assert_true(SaveStore.save(fresh()), "and the next save is not blocked")
	assert_not_null(SaveStore.load_state(), "which still loads")
```

- [ ] **Step 2: Run them and watch them fail**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_store.gd -gexit
```

Expected: failures on `BACKUP_PATH` not existing and on the rollback cases.

- [ ] **Step 3: Implement the replace**

Rewrite `game/save_store.gd`'s constants, `save`, `has_save`, `clear`, and add
`_select` / `load_all`:

```gdscript
const PATH := "user://save.json"
const TEMP_PATH := "user://save.json.tmp"
## The previous save, kept only across the write. It protects against a
## TRUNCATED file (a parse failure), NOT against a decode REFUSAL: when PATH
## parses but decode refuses it, _select never looks here and the next save's
## step 3 removes it. That is a property of the design, not a defect.
const BACKUP_PATH := "user://save.json.bak"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(BACKUP_PATH)

## Replaces the save file, and is a REAL replace: no window exists in which
## neither PATH nor BACKUP_PATH holds a complete save. Every step's result is
## checked, and the rule on failure is "restore the invariant 'if any copy
## exists, PATH exists'", not "preserve BACKUP for its own sake".
static func save(state: GameState) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false

	# 1. RECOVERY, not cleanup: promote a backup-only (or unusable-PATH) state
	#    before anything is written. Keyed on whether PATH is a USABLE copy,
	#    not merely on whether it exists -- {PATH corrupt, BACKUP good} would
	#    otherwise no-op here and lose the only loadable copy at step 3.
	if FileAccess.file_exists(BACKUP_PATH) and not _parses(PATH):
		if dir.file_exists(PATH) and dir.remove(PATH) != OK:
			return false
		if dir.rename(BACKUP_PATH, PATH) != OK:
			return false          # keep BACKUP; PATH is untouched

	# 2. Write the whole new save before anything durable is disturbed.
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(SaveCodec.encode(state)))
	f.close()

	# 3. CLEANUP, and only now: a stale backup would otherwise block step 4 on
	#    any platform whose rename refuses an existing destination, and
	#    removing it any earlier is the data-loss mirror of the same bug.
	if dir.file_exists(BACKUP_PATH) and dir.remove(BACKUP_PATH) != OK:
		return false

	# 4. Rotate. PATH may legitimately be absent on a first save.
	if dir.file_exists(PATH) and dir.rename(PATH, BACKUP_PATH) != OK:
		return false

	# 5. THE COMMIT POINT.
	if dir.rename(TEMP_PATH, PATH) != OK:
		# The only step that removes PATH, so the only one that rolls back.
		if dir.file_exists(BACKUP_PATH):
			dir.rename(BACKUP_PATH, PATH)
		return false

	# 6. PATH already holds the new bytes, so the write IS durable. Reporting
	#    false here would make _on_demolish discard a demolish that succeeded.
	if dir.file_exists(BACKUP_PATH):
		dir.remove(BACKUP_PATH)
	return true

static func _parses(path: String) -> bool:
	return typeof(_read(path)) == TYPE_DICTIONARY

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

## ONE source selection, shared. Two independent choices would let the run and
## the Meta come from DIFFERENT files, and the autosave commits that mixture ten
## seconds later as one valid payload. The fallback triggers on a PARSE failure,
## never on a decode refusal -- a refused run is exactly when salvage must still
## see its meta.
static func _select() -> Variant:
	var primary: Variant = _read(PATH)
	if typeof(primary) == TYPE_DICTIONARY:
		return primary
	var backup: Variant = _read(BACKUP_PATH)
	if typeof(backup) == TYPE_DICTIONARY:
		return backup
	return null

## The run and the Meta, both read from the same parsed dictionary.
static func load_all(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> Dictionary:
	var parsed: Variant = _select()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"state": null, "meta": null}   # Task 12 returns a defs-loaded Meta here
	return {
		"state": SaveCodec.decode(parsed as Dictionary),
		"meta": null,                          # Task 12
	}

static func load_state() -> GameState:
	return load_all()["state"]

static func clear() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for path in [PATH, TEMP_PATH, BACKUP_PATH]:
		if dir.file_exists(path):
			dir.remove(path)
		elif dir.dir_exists(path):
			# file_exists() is FALSE for a directory, so a test fixture that
			# pre-creates one at PATH would otherwise survive before_each and
			# become the fixture for every later test in that file.
			dir.remove(path)
```

Note `load_state()` keeps its zero-argument form here; Task 10 adds the
`catalog_path` / `blueprints_path` defaults once `decode` grows them.

- [ ] **Step 4: Update the class docstring**

`game/save_store.gd:6-10` currently claims writes are atomic, which was false at
`:35-37`. Replace with:

```gdscript
## Writes are a REAL REPLACE, not a delete-then-rename: the new save goes to a
## temp file, the current save rotates to BACKUP_PATH, and only then does the
## temp file become the save. No window exists in which neither PATH nor
## BACKUP_PATH holds a complete save. A phone killed mid-write is the ordinary
## case, not the exotic one.
##
## BACKUP_PATH protects against TRUNCATION (a parse failure), not against a
## decode REFUSAL -- see _select().
##
## Web durability is UNVERIFIED: user:// on the ship target is IDBFS, where
## Godot flushes asynchronously on file-handle close rather than on DirAccess
## rename/remove, so a tab killed mid-sequence can recover into a state this
## algorithm never produces. The headless tests pin the logic only.
```

- [ ] **Step 5: Run the tests and the whole suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_store.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: new file passes; the whole suite still green.

- [ ] **Step 6: Commit**

```bash
git add game/save_store.gd tests/test_save_store.gd
git commit -F - <<'EOF'
Make SaveStore.save a real replace, before anything irreplaceable rides in it

save() removed the save file and then renamed the temp over it, so a crash in
that window left no save at all. That was survivable while a lost save cost a
building you could rebuild; prestige puts permanent progress in the same file,
and demolish is the one write whose loss cannot be re-earned by playing on.

The order is load-bearing in both directions: promoting a backup-only state
happens BEFORE anything is written (recovery), and removing a stale backup
happens only once a complete temp file exists (cleanup). Doing either the
other way round loses data -- one bricks rotation, the other deletes the last
copy.
EOF
```

---

## Task 4: `_valid` defaults to false, and the error screen names its file

**Why:** spec §7 [r6] and §13. A constructor that errors returns a **half-built
object** with the caller resuming, so today any runtime error inside
`GameState._init` yields a state whose `is_valid()` is `true` and whose `clock`
or `catalog` may be null. This spec adds real work to `_init` and makes
`is_valid()` the single enforcement point for §8's fatal-data rule; a gate whose
default is *pass* cannot do that job. And `game_root.gd:215` hardcodes
`"No valid tenant catalog"`, so §8's "now naming the blueprint file" is
unimplementable and §12's assertion unwritable.

**Files:**
- Modify: `sim/game_state.gd:45`, `:47-74`
- Modify: `game/game_root.gd:74-78`, `:207-224`
- Test: `tests/test_game_state.gd`, `tests/test_board_input.gd:620-635`

**Interfaces:**
- Produces:
  - `GameState.invalid_what() -> String` — `"tenant catalog"`, `"blueprint catalog"`, or `""` when valid
  - `GameState.invalid_path() -> String` — the offending path, `""` when valid
  - `game_root._show_error_screen(what: String, path: String) -> void`
  - `game_root.error_screen_text() -> String`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_game_state.gd`:

```gdscript
func test_a_malformed_catalog_names_itself() -> void:
	var bad := GameState.new(6, 1, 1, "res://data/does_not_exist.json")
	assert_false(bad.is_valid(), "invalid")
	assert_eq(bad.invalid_what(), "tenant catalog", "which file kind")
	assert_eq(bad.invalid_path(), "res://data/does_not_exist.json", "which file")

func test_a_valid_state_names_nothing() -> void:
	var good := GameState.new(6, 1, 1)
	assert_true(good.is_valid(), "valid")
	assert_eq(good.invalid_what(), "", "nothing to name")
```

Append to `tests/test_board_input.gd` (beside the existing bad-catalog test):

```gdscript
func test_the_error_screen_names_the_file_it_refused() -> void:
	var layer := CanvasLayer.new()
	layer.layer = GUT_GUI_LAYER + 1
	add_child_autofree(layer)
	var bad: Control = ROOT.instantiate()
	bad.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bad.size = BOARD_SIZE
	bad.catalog_path_override = "res://data/does_not_exist.json"
	layer.add_child(bad)
	await wait_physics_frames(2)
	assert_true(bad.error_screen_visible(), "the screen is up")
	assert_string_contains(bad.error_screen_text(), "does_not_exist.json",
		"a player who cannot read a console still learns which file")
	assert_string_contains(bad.error_screen_text(), "tenant catalog", "and what it is")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit
```

Expected: `invalid_what` not found.

- [ ] **Step 3: Flip the default and record the reason**

In `sim/game_state.gd`, replace `var _valid: bool = true` (`:45`) with:

```gdscript
## Defaults to FALSE and is set true as the LAST statement of _init.
##
## Verified on Godot 4.7: a constructor that errors returns a HALF-BUILT object
## -- every field below the abort point at its declared default -- and the
## caller resumes normally. A gate that defaults to `pass` therefore reports a
## state with a null `clock` as valid. It is the single enforcement point for
## the fatal-shipped-data rule, so its default is refuse.
var _valid: bool = false

## Which file made this state invalid, so the boot path can name it on screen
## rather than on a console the player cannot see.
var _invalid_what: String = ""
var _invalid_path: String = ""
```

Turn the existing catalog failure into an early return, and set `_valid = true`
as the last statement of `_init`:

```gdscript
	catalog = TenantCatalog.new()
	if not catalog.load_from(catalog_path):
		# No push_error: GUT counts it as a test error, which turns the
		# malformed-catalog refusal test red for the wrong reason.
		_invalid_what = "tenant catalog"
		_invalid_path = catalog_path
		return
```

…and at the end of `_init`:

```gdscript
	auto = AutoDispatch.new()
	_valid = true
```

Add the accessors beside `is_valid()`:

```gdscript
func invalid_what() -> String:
	return _invalid_what

func invalid_path() -> String:
	return _invalid_path
```

- [ ] **Step 4: Parameterise the error screen**

In `game/game_root.gd`, replace `_show_error_screen` and add the text accessor:

```gdscript
## A named refusal to start: the file is the offence, so it is on the screen. A
## blank board with a console message a player cannot see is indistinguishable
## from a hang.
func _show_error_screen(what: String, path: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_error_label = Label.new()
	_error_label.text = "No valid %s\n\n%s\n\nCannot start." % [what, path]
	_error_label.add_theme_font_size_override("font_size", 20)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error_label.set_anchors_preset(Control.PRESET_CENTER)
	_error_label.size = Vector2(size.x, 200)
	add_child(_error_label)

func error_screen_text() -> String:
	return "" if _error_label == null else _error_label.text
```

And the caller at `:74-78`:

```gdscript
	if state == null or not state.is_valid():
		if state == null:
			_show_error_screen("tenant catalog", catalog_path)
		else:
			_show_error_screen(state.invalid_what(), state.invalid_path())
		_saving_enabled = false
		set_physics_process(false)
		return
```

- [ ] **Step 5: Run the full suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all green. If `test_a_malformed_catalog_makes_the_state_invalid`
(`tests/test_game_state.gd:207`) goes red, it is dereferencing a field past the
early return — it should assert `is_valid()` only.

- [ ] **Step 6: Commit**

```bash
git add sim/game_state.gd game/game_root.gd tests/test_game_state.gd tests/test_board_input.gd
git commit -F - <<'EOF'
Default _valid to false, and let the error screen name the file it refused

A GDScript constructor that errors does not unwind -- it returns a half-built
object and the caller resumes -- so `var _valid := true` reported a GameState
with a null clock as valid. Prestige adds real work to _init and makes
is_valid() the single enforcement point for the fatal-shipped-data rule, and a
gate whose default is `pass` cannot do that job.

The error screen was hardcoded to "No valid tenant catalog", so the blueprint
catalog could only ever have been announced under the wrong file's name.
EOF
```

---

## Task 5: `data/blueprints.json` and `Meta.load_defs`

**Why:** spec §8. This file sets the prices of a *persistent* currency, so a bad
value is not merely a crash risk: `"base": -2` makes every level affordable at 0
Blueprints and `blueprints -= cost` then **credits** — an unbounded mint from a
shipped-data typo. `"base": 1e18` with `max_level: 64` reaches the same mint
through int64 overflow.

**Files:**
- Create: `data/blueprints.json`, `sim/meta.gd`, `tests/test_meta.gd`
- Modify: `sim/upgrades.gd:36-41` (the `note` fix)

**Interfaces:**
- Produces:
  - `class_name Meta extends RefCounted`
  - `const MAX_HEIGHT_CAP := 20`, `MAX_BLUEPRINTS := 1_000_000_000`, `MAX_RUNS := 1_000_000`
  - `const NODE_TO_UPGRADE := {"motor": "speed", "gearing": "doors", "cabin": "capacity"}`
  - `var blueprints: int`, `var runs_completed: int`
  - `func load_defs(path: String) -> bool`
  - `func is_usable() -> bool`
  - `func ids() -> PackedStringArray`
  - `func name_of(id: String) -> String`, `func note_of(id: String) -> String`, `func branch_of(id: String) -> String`

- [ ] **Step 1: Write `data/blueprints.json`**

```json
{
  "comment": "cost = base * (level + 1). Effects are applied by id in meta.gd.",
  "nodes": [
    { "id": "height",  "name": "Taller Foundations", "branch": "structure",
      "base": 2, "max_level": 2, "note": "+5 floors you may build" },
    { "id": "shafts",  "name": "Sunk Shafts",        "branch": "structure",
      "base": 5, "max_level": 3, "note": "start with one more shaft" },
    { "id": "motor",   "name": "Standard Motor",     "branch": "mechanical",
      "base": 2, "max_level": 4, "note": "start with Stronger Motor fitted" },
    { "id": "gearing", "name": "Standard Gearing",   "branch": "mechanical",
      "base": 2, "max_level": 4, "note": "start with Faster Doors fitted" },
    { "id": "cabin",   "name": "Standard Cabin",     "branch": "mechanical",
      "base": 3, "max_level": 3, "note": "start with a Bigger Car fitted" }
  ]
}
```

- [ ] **Step 2: Write the failing tests**

Create `tests/test_meta.gd`:

```gdscript
extends GutTest

## Meta is the persistent half of the game. Its loader is the only defence
## between a typo in shipped data and an unbounded Blueprint mint, so the
## malformed cases below are the point of the file, not its edges.

const DEFS := "res://data/blueprints.json"

func loaded() -> Meta:
	var m := Meta.new()
	assert_true(m.load_defs(DEFS), "the shipped catalog loads")
	return m

## Writes a defs file to user:// so a malformed-data test never has to mutate
## the shipped one.
func write_defs(nodes: Array) -> String:
	var path := "user://test_blueprints.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"nodes": nodes}))
	f.close()
	return path

func ok_node(overrides: Dictionary = {}) -> Dictionary:
	var n := {"id": "height", "name": "Taller Foundations", "branch": "structure",
		"base": 2, "max_level": 2, "note": "+5 floors"}
	for k in overrides:
		n[k] = overrides[k]
	return n

func test_the_shipped_catalog_loads_and_is_usable() -> void:
	var m := loaded()
	assert_true(m.is_usable(), "usable")
	assert_eq(Array(m.ids()), ["height", "shafts", "motor", "gearing", "cabin"],
		"every node, in file order")

func test_a_missing_file_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs("res://data/does_not_exist.json"), "refused")
	assert_false(m.is_usable(), "and not usable")

func test_a_negative_base_is_refused() -> void:
	# `blueprints -= cost` with a negative cost CREDITS. One typo, unbounded mint.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"base": -2})])), "refused")
	assert_false(m.is_usable(), "and not usable")

func test_an_enormous_base_is_refused() -> void:
	# base * (max_level + 1) must not wrap int64 negative -- can_buy would then
	# be true at a zero balance and the subtraction would credit.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"base": 1e18, "max_level": 64})])),
		"refused")

func test_a_duplicate_id_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node(), ok_node()])), "refused")

func test_an_unknown_branch_is_refused() -> void:
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node({"branch": "wizardry"})])), "refused")

func test_a_partial_load_reports_unusable_and_keeps_nothing() -> void:
	# The failure that matters: a file whose SECOND node is bad leaves the first
	# behind. If is_usable() read `not _defs.is_empty()` it would say yes, ids()
	# would return a subset, and restore()'s iterate-ids() rule would then drop
	# every spent level for the missing nodes -- which the autosave persists ten
	# seconds later.
	var m := Meta.new()
	assert_false(m.load_defs(write_defs([ok_node(),
		ok_node({"id": "shafts", "base": -1})])), "refused")
	assert_false(m.is_usable(), "not usable, despite one good entry")
	assert_eq(m.ids().size(), 0, "and nothing kept")

func test_load_defs_does_not_clear_progress() -> void:
	# Upgrades.load_defs zeroes _levels; a faithful mirror here would wipe the
	# tree whenever defs happened to load after a restore.
	var m := loaded()
	m.blueprints = 9
	assert_true(m.load_defs(DEFS), "a second load succeeds")
	assert_eq(m.blueprints, 9, "and reads definitions without touching progress")

func test_the_note_survives_the_load() -> void:
	assert_string_contains(loaded().note_of("height"), "floors", "the panel renders it")
```

Append to `tests/test_upgrades.gd`:

```gdscript
func test_an_upgrade_note_survives_the_load() -> void:
	# note_of() indexed a key load_defs never set -- a latent crash with no
	# callers, until the prestige panel gave it one.
	var u := Upgrades.new()
	assert_true(u.load_defs("res://data/upgrades.json"), "loads")
	assert_string_contains(u.note_of("auto"), "shaft", "the note is there")
	assert_eq(u.note_of("speed"), "", "and an upgrade with no note reads empty")
```

- [ ] **Step 3: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta.gd -gexit
```

Expected: `Meta` not found.

- [ ] **Step 4: Implement `sim/meta.gd`'s loader**

```gdscript
class_name Meta
extends RefCounted

## The persistent half of the game: Blueprints, the tech tree's levels, and the
## derivations a fresh run starts from. Pure data. It knows nothing about
## GameState -- GameState reads it, never the reverse.
##
## Definitions are data; EFFECTS are code, exactly as in Upgrades. data/ holds
## numeric coefficients over a fixed set of code-defined shapes and never
## expression strings.

const BASE_HEIGHT_CAP := 10
const HEIGHT_PER_LEVEL := 5
## This release's ladder top. NOT Building.MAX_FLOORS -- an implementer who
## clamps to 40 instead hands a tampered save a 40-floor cap.
const MAX_HEIGHT_CAP := 20
## Deliberately == Prestige.MAX_YIELD, so a legitimately clamped yield cannot
## fail its own decode on the next load. Pinned by a test.
const MAX_BLUEPRINTS := 1_000_000_000
const MAX_RUNS := 1_000_000
const BASE_STARTING_SHAFTS := 1

const MAX_NODES := 64
const MAX_BASE := 1_000_000
const MAX_NODE_LEVEL := 64

## Node id -> the Upgrades id whose STARTING level it grants. The mapping runs
## in THIS direction, and it is the thing an implementer gets wrong:
## Upgrades.has_effect is false for `motor`/`gearing`/`cabin`, which are not
## Upgrades ids at all. Structure nodes appear here deliberately not at all --
## they are read by height_cap() and starting_shafts() instead.
const NODE_TO_UPGRADE := {"motor": "speed", "gearing": "doors", "cabin": "capacity"}

var blueprints: int = 0
var runs_completed: int = 0

var _spent: Dictionary = {}         # node id -> level
var _defs: Dictionary = {}          # node id -> {name, branch, base, max_level, note}
## A STORED flag, never `not _defs.is_empty()`: every malformed rule below is a
## mid-loop failure, and a partial load reporting "usable" makes restore()'s
## iterate-ids() rule silently drop every spent level for the missing nodes.
var _defs_loaded: bool = false

## Reads definitions. It does NOT own player progress: unlike
## Upgrades.load_defs (upgrades.gd:42) it never touches _spent, because defs
## must be loadable on every path and calling it after a restore would
## otherwise wipe the tree it exists to protect.
func load_defs(path: String) -> bool:
	if _defs_loaded:
		return true
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var list: Variant = (parsed as Dictionary).get("nodes")
	if typeof(list) != TYPE_ARRAY:
		return false
	var nodes := list as Array
	if nodes.is_empty() or nodes.size() > MAX_NODES:
		return false

	# Built into a LOCAL and only published on success, so a mid-loop refusal
	# cannot leave a subset behind.
	var built := {}
	for entry in nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var e := entry as Dictionary
		for key in ["id", "name", "branch", "base", "max_level"]:
			if not e.has(key):
				return false
		if typeof(e["id"]) != TYPE_STRING or (e["id"] as String).is_empty():
			return false
		var id: String = e["id"]
		if built.has(id):
			return false
		if typeof(e["name"]) != TYPE_STRING:
			return false
		if typeof(e["branch"]) != TYPE_STRING:
			return false
		if e["branch"] != "structure" and e["branch"] != "mechanical":
			return false
		# The upper bound on base is not tidiness: cost_of is base * (level + 1)
		# returning int, so 1e18 * 65 wraps int64 negative, can_buy is then true
		# at a zero balance, and `blueprints -= cost` CREDITS.
		if not _is_integral_in(e["base"], 1, MAX_BASE):
			return false
		if not _is_integral_in(e["max_level"], 1, MAX_NODE_LEVEL):
			return false
		var note: Variant = e.get("note", "")
		if typeof(note) != TYPE_STRING:
			return false
		built[id] = {
			"name": e["name"],
			"branch": e["branch"],
			"base": int(e["base"]),
			"max_level": int(e["max_level"]),
			"note": note,
		}

	_defs = built
	_defs_loaded = true
	return true

func is_usable() -> bool:
	return _defs_loaded

func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		out.append(id)
	return out

func name_of(id: String) -> String:
	return str(_defs[id]["name"]) if _defs.has(id) else id

func note_of(id: String) -> String:
	return str(_defs[id]["note"]) if _defs.has(id) else ""

func branch_of(id: String) -> String:
	return str(_defs[id]["branch"]) if _defs.has(id) else ""

## Numeric, finite, integral, and within [lo, hi]. TYPE FIRST: is_finite() on a
## Dictionary is itself a runtime error, so the order is load-bearing rather
## than stylistic.
static func _is_integral_in(v: Variant, lo: int, hi: int) -> bool:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	if t == TYPE_FLOAT:
		var fv: float = v
		if not is_finite(fv) or fv != floorf(fv):
			return false
	var n := int(v)
	return n >= lo and n <= hi
```

- [ ] **Step 5: Fix `Upgrades.load_defs`'s missing `note`**

`sim/upgrades.gd:36-41` keeps only name/base/growth/max_level, so `note_of`
(`:65-66`) indexes a key that is never set. Add it:

```gdscript
			_defs[id] = {
				"name": str(entry.get("name", id)),
				"base": float(entry.get("base", 10.0)),
				"growth": float(entry.get("growth", 1.5)),
				"max_level": int(entry.get("max_level", 1)),
				# note_of() has indexed this key since it was written; without
				# it the accessor is a latent crash, and the prestige panel is
				# its first caller.
				"note": str(entry.get("note", "")),
			}
```

- [ ] **Step 6: Import, run, commit**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add data/blueprints.json sim/meta.gd sim/meta.gd.uid sim/upgrades.gd tests/test_meta.gd tests/test_meta.gd.uid tests/test_upgrades.gd
git commit -F - <<'EOF'
Add the blueprint catalog and the loader that refuses to mint currency

This file sets the prices of a PERSISTENT currency, so "malformed" needs a
definition or the guard is decorative: `"base": -2` makes every level free and
turns `blueprints -= cost` into a credit, and `"base": 1e18` reaches the same
mint through int64 overflow. Both are refused, along with duplicate ids and
unknown branches.

is_usable() is a stored flag rather than `not _defs.is_empty()`, because every
one of those refusals is mid-loop: a partial load reporting "usable" would let
restore()'s iterate-ids() rule silently drop the tree.

Also fixes Upgrades.note_of, which has indexed a key load_defs never set.
EOF
```

---

## Task 6: `Meta`'s tree, derivations, and serialization

**Why:** spec §7 and §9's meta-block validation.

**Files:**
- Modify: `sim/meta.gd`
- Test: `tests/test_meta.gd`

**Interfaces:**
- Produces:
  - `func level_of(id: String) -> int`, `func is_maxed(id: String) -> bool`
  - `func cost_of(id: String) -> int` — `base * (level + 1)`
  - `func is_zero_delta(id: String, up: Upgrades) -> bool`
  - `func can_buy(id: String, up: Upgrades) -> bool`, `func buy(id: String, up: Upgrades) -> bool`
  - `func to_dict() -> Dictionary` — keys `blueprints`, `runs`, `spent`; deep
  - `func restore(data: Variant) -> bool` — false **only** when defs are not loaded
  - `func height_cap() -> int`, `func starting_shafts() -> int`, `func starting_level(upgrade_id: String) -> int`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_meta.gd`:

```gdscript
func upgrades() -> Upgrades:
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	return u

func test_cost_follows_base_times_level_plus_one() -> void:
	var m := loaded()
	assert_eq(m.cost_of("height"), 2, "level 0")
	m.blueprints = 100
	assert_true(m.buy("height", upgrades()), "buy L1")
	assert_eq(m.cost_of("height"), 4, "level 1")

func test_a_purchase_at_exactly_the_cost_succeeds() -> void:
	# The < vs <= boundary.
	var m := loaded()
	m.blueprints = 2
	assert_true(m.buy("height", upgrades()), "exactly affordable")
	assert_eq(m.blueprints, 0, "and spends it all")

func test_a_purchase_one_short_is_refused() -> void:
	var m := loaded()
	m.blueprints = 1
	assert_false(m.buy("height", upgrades()), "refused")
	assert_eq(m.level_of("height"), 0, "and nothing changed")

func test_buying_past_max_level_is_refused() -> void:
	var m := loaded()
	m.blueprints = 1000
	var u := upgrades()
	assert_true(m.buy("height", u), "L1")
	assert_true(m.buy("height", u), "L2")
	assert_false(m.buy("height", u), "L3 does not exist")
	assert_eq(m.level_of("height"), 2, "and the level held")

func test_height_and_shafts_are_never_zero_delta() -> void:
	# They map to no upgrade, so there is nothing to compare. Getting this
	# wrong makes `height` permanently unbuyable -- the one node this whole
	# system exists for.
	var m := loaded()
	assert_false(m.is_zero_delta("height", upgrades()), "height")
	assert_false(m.is_zero_delta("shafts", upgrades()), "shafts")

func test_gearing_is_buyable_while_the_runs_doors_sit_at_the_plateau() -> void:
	# The node's zero-delta is evaluated at the META's level, never the run's.
	# Delegating to up.is_zero_delta("doors") would refuse gearing at L0 for a
	# player shopping the panel late in a run -- exactly when they are shopping.
	var u := upgrades()
	u.restore_levels({"doors": 10})        # past DOOR_TICKS_MIN
	assert_true(u.is_zero_delta("doors"), "the RUN's doors are maxed out")
	var m := loaded()
	assert_false(m.is_zero_delta("gearing", u), "gearing is still worth buying")

func test_the_ladder_walks_ten_to_twenty() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_eq(m.height_cap(), 10, "run one")
	m.buy("height", u)
	assert_eq(m.height_cap(), 15, "L1")
	m.buy("height", u)
	assert_eq(m.height_cap(), 20, "L2")

func test_shafts_walk_one_to_four() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	assert_eq(m.starting_shafts(), GameState.BASE_SHAFTS, "run one starts where a new game does")
	for i in range(3):
		m.buy("shafts", u)
	assert_eq(m.starting_shafts(), 4, "three levels")

func test_the_height_clamp_is_not_vacuous() -> void:
	# Asserting height_cap() <= 20 against a 2-level ladder passes with the
	# clamp deleted. Load a defs file that could exceed it.
	var m := Meta.new()
	assert_true(m.load_defs(write_defs([ok_node({"max_level": 64})])), "loads")
	assert_true(m.restore({"spent": {"height": 64}}), "restores")
	assert_eq(m.level_of("height"), 64, "the level is real")
	assert_eq(m.height_cap(), Meta.MAX_HEIGHT_CAP, "and the cap still holds")

func test_starting_levels_map_node_ids_to_upgrade_ids() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	m.buy("motor", u)
	m.buy("gearing", u)
	assert_eq(m.starting_level("speed"), 1, "motor -> speed")
	assert_eq(m.starting_level("doors"), 1, "gearing -> doors")
	assert_eq(m.starting_level("capacity"), 0, "cabin unbought")
	assert_eq(m.starting_level("shaft"), 0, "structure maps to no upgrade")

func test_every_id_is_consumed_by_a_derivation_and_every_target_exists() -> void:
	# A typo makes a node silently do nothing forever -- the same class of bug
	# ElevatorCar.floors_per_tick == Upgrades.SPEED_BASE is pinned against.
	var m := loaded()
	var u := upgrades()
	var upgrade_ids := Array(u.ids())
	for id in m.ids():
		var structural := id == "height" or id == "shafts"
		var mechanical := Meta.NODE_TO_UPGRADE.has(id)
		assert_true(structural or mechanical, "%s is read by some derivation" % id)
		if mechanical:
			assert_true(upgrade_ids.has(Meta.NODE_TO_UPGRADE[id]),
				"%s targets a real upgrade" % id)
	for node_id in Meta.NODE_TO_UPGRADE:
		assert_true(Array(m.ids()).has(node_id),
			"%s is switched on but not in the file" % node_id)

func test_to_dict_pins_its_key_names() -> void:
	# The dict key is `runs` while the field is `runs_completed`. A rename on
	# one side would silently zero the count on every load.
	var m := loaded()
	m.blueprints = 3
	m.runs_completed = 5
	m.buy("height", upgrades())
	var d := m.to_dict()
	assert_true(d.has("blueprints") and d.has("runs") and d.has("spent"), "keys")
	assert_eq(d["runs"], 5, "runs, not runs_completed")

func test_to_dict_never_aliases_the_live_tree() -> void:
	# The staged clone in Prestige.demolish is independent only if the pair
	# deep-copies at BOTH ends.
	var m := loaded()
	m.blueprints = 100
	m.buy("height", upgrades())
	var d := m.to_dict()
	(d["spent"] as Dictionary)["height"] = 99
	assert_eq(m.level_of("height"), 1, "the live tree is untouched")

func test_restore_is_a_deep_copy_too() -> void:
	var source := loaded()
	source.blueprints = 100
	source.buy("height", upgrades())
	var d := source.to_dict()
	var clone := loaded()
	assert_true(clone.restore(d), "restores")
	source.buy("height", upgrades())
	assert_eq(clone.level_of("height"), 1, "the clone did not follow")

func test_restore_into_an_unloaded_meta_is_refused() -> void:
	# Restoring with no defs would iterate an empty ids() and DROP every level.
	var m := Meta.new()
	assert_false(m.restore({"blueprints": 5}), "refused")

func test_a_malformed_meta_block_restores_an_empty_tree_without_throwing() -> void:
	for bad in [null, 5, "abc", [], {"spent": 7}]:
		var m := loaded()
		assert_true(m.restore(bad), "%s is an empty Meta, not a refusal" % [bad])
		assert_eq(m.blueprints, 0, "no blueprints")
		assert_eq(m.level_of("height"), 0, "no levels")

func test_hostile_levels_are_clamped_to_their_nodes_max() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"motor": 999, "cabin": 999, "height": 999}}), "restores")
	assert_eq(m.level_of("motor"), 4, "not a 10-floors-per-tick car")
	assert_eq(m.level_of("cabin"), 3, "not a 1,003-seat car")
	assert_eq(m.height_cap(), Meta.MAX_HEIGHT_CAP, "not a 40-floor cap")

func test_unknown_ids_in_spent_are_dropped() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"wizardry": 3}}), "restores")
	assert_eq(m.level_of("wizardry"), 0, "read by iterating OUR ids, never theirs")

func test_a_non_integral_or_wrongly_typed_blueprints_is_rejected_without_throwing() -> void:
	for bad in [3.7, "abc", {}, [], null]:
		var m := loaded()
		assert_true(m.restore({"blueprints": bad}), "no refusal")
		assert_eq(m.blueprints, 0, "%s falls back to zero" % [bad])

func test_a_huge_blueprints_clamps_rather_than_wrapping() -> void:
	var m := loaded()
	assert_true(m.restore({"blueprints": 9.3e18, "runs": 9.3e18}), "restores")
	assert_eq(m.blueprints, Meta.MAX_BLUEPRINTS, "clamped in float space")
	assert_eq(m.runs_completed, Meta.MAX_RUNS, "runs too -- it feeds the RNG seed")

func test_a_spent_value_that_is_a_container_is_rejected_without_throwing() -> void:
	var m := loaded()
	assert_true(m.restore({"spent": {"height": {}}}), "no refusal")
	assert_eq(m.level_of("height"), 0, "int({}) is an error, so type comes first")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta.gd -gexit
```

- [ ] **Step 3: Implement**

Append to `sim/meta.gd`:

```gdscript
func level_of(id: String) -> int:
	return int(_spent.get(id, 0))

func is_maxed(id: String) -> bool:
	if not _defs.has(id):
		return true
	return level_of(id) >= int(_defs[id]["max_level"])

func cost_of(id: String) -> int:
	if not _defs.has(id):
		return 0
	return int(_defs[id]["base"]) * (level_of(id) + 1)

## True when the next level of this node would change nothing, mirroring
## Upgrades.is_zero_delta -- which is why the refusal lives in the sim rather
## than in a view enforcing a rule the sim does not hold.
##
## It takes an Upgrades because effect_value is an instance method, and it
## evaluates at THIS META's level, never the run's: a run whose doors sit at
## the DOOR_TICKS_MIN plateau would otherwise see `gearing` refused at L0,
## precisely while the player is shopping the panel before a demolish.
##
## Returns false for `height` and `shafts`: they map to no upgrade, so there is
## nothing to compare. Getting that wrong makes `height` permanently unbuyable.
func is_zero_delta(id: String, up: Upgrades) -> bool:
	if not NODE_TO_UPGRADE.has(id):
		return false
	var target: String = NODE_TO_UPGRADE[id]
	var lvl := level_of(id)
	return is_equal_approx(up.effect_value(target, lvl), up.effect_value(target, lvl + 1))

func can_buy(id: String, up: Upgrades) -> bool:
	if not _defs.has(id) or is_maxed(id):
		return false
	if is_zero_delta(id, up):
		return false
	return blueprints >= cost_of(id)

## The ONLY spender of Blueprints. Spending never routes through the cash path:
## no can_afford, no `cash -=`.
func buy(id: String, up: Upgrades) -> bool:
	if not can_buy(id, up):
		return false
	blueprints -= cost_of(id)          # before the level moves, or it prices the next one
	_spent[id] = level_of(id) + 1
	return true

## Deep. Never returns the live _spent: the staged clone in Prestige.demolish is
## independent only if this pair deep-copies at both ends, and a tidy-up that
## returned the live dictionary would quietly re-create shared mutable state.
func to_dict() -> Dictionary:
	return {
		"blueprints": blueprints,
		"runs": runs_completed,          # the KEY is `runs`; the field is `runs_completed`
		"spent": _spent.duplicate(true),
	}

## ALL meta-block validation lives here. It returns false ONLY when there are no
## definitions to validate against -- a malformed or absent block is an EMPTY
## Meta, not a refusal, because in this codebase "refuse" means "delete": decode
## returns null, game_root starts fresh, and the autosave overwrites the only
## copy within ten seconds. Losing a tech tree beats losing a building.
func restore(data: Variant) -> bool:
	if not _defs_loaded:
		return false
	blueprints = 0
	runs_completed = 0
	_spent = {}                        # fresh storage; never aliased from `data`
	if typeof(data) != TYPE_DICTIONARY:
		return true
	var d := data as Dictionary
	blueprints = _clamped_int(d.get("blueprints"), 0, MAX_BLUEPRINTS)
	runs_completed = _clamped_int(d.get("runs"), 0, MAX_RUNS)
	var spent: Variant = d.get("spent")
	if typeof(spent) != TYPE_DICTIONARY:
		return true
	# Iterate OUR ids, never the parsed dictionary's keys. Unknown ids are
	# dropped rather than stored, and the parsed key count is then irrelevant.
	for id in ids():
		var raw: Variant = (spent as Dictionary).get(id)
		if raw == null:
			continue
		var lvl := _clamped_int(raw, 0, int(_defs[id]["max_level"]))
		if lvl > 0:
			_spent[id] = lvl
	return true

## 10 + 5n, capped. The DEFINITION -- the view annotates from this, so an
## annotation can never fabricate a cap by copying the formula.
func height_cap() -> int:
	return mini(BASE_HEIGHT_CAP + HEIGHT_PER_LEVEL * level_of("height"), MAX_HEIGHT_CAP)

func starting_shafts() -> int:
	return mini(BASE_STARTING_SHAFTS + level_of("shafts"), Building.MAX_SHAFTS)

## The level an upgrade BEGINS a run at. Takes an Upgrades id, not a node id.
func starting_level(upgrade_id: String) -> int:
	for node_id in NODE_TO_UPGRADE:
		if NODE_TO_UPGRADE[node_id] == upgrade_id:
			return level_of(node_id)
	return 0

## Clamps in FLOAT space before the int() cast, because out-of-range float->int
## is platform-defined and the ship target is a different toolchain from the
## machine this is tested on. Type first: is_finite(Dictionary) is an error.
static func _clamped_int(v: Variant, lo: int, hi: int) -> int:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return lo
	var fv := float(v)
	if not is_finite(fv) or fv != floorf(fv):
		return lo
	return int(clampf(fv, float(lo), float(hi)))
```

- [ ] **Step 4: Run the file, then the suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 5: Commit**

```bash
git add sim/meta.gd tests/test_meta.gd
git commit -F - <<'EOF'
Give Meta its tree, its derivations, and a restore that cannot be poisoned

height_cap() and starting_shafts() are THE definitions, so the panel annotates
from them rather than copying a formula and dropping a clamp.

is_zero_delta evaluates at the Meta's level, not the run's: delegating to
up.is_zero_delta("doors") reads the run's current doors, which would refuse
`gearing` at L0 for any player whose run had reached the DOOR_TICKS_MIN
plateau -- precisely while they are shopping the panel before a demolish.

restore() returns false only when there are no definitions to validate
against. A malformed block is an EMPTY Meta, not a refusal, because refusing
here means the autosave overwrites the building ten seconds later.
EOF
```

---

## Task 7: `Upgrades.set_max_level` and `grant_level`

**Why:** spec §7. The cap stops being a constant, and a run has to be able to
*begin* with levels it did not buy.

**Files:**
- Modify: `sim/upgrades.gd`
- Test: `tests/test_upgrades.gd`

**Interfaces:**
- Produces:
  - `func set_max_level(id: String, level: int) -> void` — clamps to `[0, ∞)`
  - `func grant_level(id: String, level: int, building: Building) -> void` — clamps to `[0, max_level]`, syncs cars, **never** calls `_apply`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_upgrades.gd`:

```gdscript
func test_set_max_level_moves_the_purchasable_ceiling() -> void:
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	u.set_max_level("floor", 4)
	for i in range(4):
		assert_false(u.is_maxed("floor"), "purchase %d is allowed" % i)
		u.restore_levels({"floor": i + 1})
	assert_true(u.is_maxed("floor"), "and the fifth is not")

func test_set_max_level_never_goes_negative() -> void:
	# GameState.new(1, 1, 7) exists today, so floor_count - BASE_FLOORS is -5.
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	u.set_max_level("floor", -5)
	assert_true(u.is_maxed("floor"), "a negative budget is no budget")

func test_grant_level_sets_the_level_without_building_anything() -> void:
	# An implementer mirroring purchase() would call building.add_floor()
	# fourteen times -- and on the decode path, where _init is handed the SAVED
	# size, that grows the building past saved_floors.size() and every reload
	# silently adds floors.
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	var b := Building.new(6, 1)
	u.set_max_level("floor", 14)
	u.grant_level("floor", 4, b)
	assert_eq(u.level_of("floor"), 4, "the level moved")
	assert_eq(b.floor_count, 6, "the building did not")

func test_grant_level_syncs_the_cars() -> void:
	# A Meta with motor: 4 reporting level_of("speed") == 4 while every car ran
	# at base speed is the node silently doing nothing.
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	var b := Building.new(6, 2)
	u.grant_level("speed", 4, b)
	assert_almost_eq(b.cars[0].floors_per_tick,
		u.effect_value("speed", 4), 0.0001, "car 0")
	assert_almost_eq(b.cars[1].floors_per_tick,
		u.effect_value("speed", 4), 0.0001, "every car, not just the first")

func test_grant_level_clamps_to_the_max() -> void:
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	var b := Building.new(6, 1)
	u.set_max_level("floor", 4)
	u.grant_level("floor", 99, b)
	assert_eq(u.level_of("floor"), 4, "clamped up")
	u.grant_level("shaft", -5, b)
	assert_eq(u.level_of("shaft"), 0, "clamped down -- a negative level prices below base")

func test_a_granted_shaft_consumes_its_own_price_ladder() -> void:
	# Otherwise a run starting with four shafts prices the FIFTH at $500 rather
	# than $5,324 -- the limitation already documented for --board=40x8, which
	# is harmless for screenshots and a balance hole here.
	var u := Upgrades.new()
	u.load_defs("res://data/upgrades.json")
	var b := Building.new(6, 4)
	var first_price := u.cost_of("shaft")
	u.grant_level("shaft", 3, b)
	assert_gt(u.cost_of("shaft"), first_price * 5.0, "the ladder was consumed")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrades.gd -gexit
```

- [ ] **Step 3: Implement**

Append to `sim/upgrades.gd`:

```gdscript
## Blueprints raise per-run ceilings. data/ holds the ladder's TOP rung; the
## live cap is whatever the run was started with. is_maxed() is the only reader
## of max_level (purchase gates on it at :83) -- cost_of does NOT read it, so
## there is nothing to change there.
##
## Clamped to [0, inf): GameState.new(1, 1, 7) exists in the suite today, and a
## budget of floor_count - BASE_FLOORS is then negative.
func set_max_level(id: String, level: int) -> void:
	if not _defs.has(id):
		return
	_defs[id]["max_level"] = maxi(level, 0)

## Levels the run BEGINS with -- granted size and Meta-granted mechanicals.
##
## Takes the Building because Upgrades owns no cars: _sync_car() needs an
## ElevatorCar (:169), so a signature without it cannot keep its promise and a
## Meta with motor: 4 would report level_of("speed") == 4 while every car ran
## at base speed.
##
## It sets _levels[id] and syncs each car. It NEVER calls _apply() and never
## changes building.floor_count or cars.size(): an implementer mirroring
## purchase() (:82-94) would call building.add_floor() fourteen times, and on
## the decode path -- where _init is handed the SAVED size -- that grows the
## building past saved_floors.size() and every reload silently adds floors.
##
## Grants apply at construction only, and restore_levels overwrites, so buying
## a Mechanical node mid-run does nothing until the next demolish. That is
## intended; the panel says so.
func grant_level(id: String, level: int, building: Building) -> void:
	if not _defs.has(id):
		return
	_levels[id] = clampi(level, 0, int(_defs[id]["max_level"]))
	for car in building.cars:
		_sync_car(car)
```

- [ ] **Step 4: Run, then the suite, then commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrades.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add sim/upgrades.gd tests/test_upgrades.gd
git commit -F - <<'EOF'
Let a run begin with levels it did not buy, and with a cap it was given

grant_level takes the Building because Upgrades owns no cars -- _sync_car
needs an ElevatorCar -- so a signature without it would set level_of("speed")
to 4 while every car still ran at base speed.

It never calls _apply(). Mirroring purchase() would call add_floor() fourteen
times, and on the decode path _init is handed the SAVED size, so every reload
would silently grow the building past its own saved floors array.

Granting also consumes the price ladder, so a run starting with four shafts
prices the fifth at $5,324 rather than $500.
EOF
```

---

## Task 8: `GameState` learns about the Meta, and the cap becomes 10

**Why:** spec §7. This is the task that makes the first run cap at 10 floors, so
it is also the task where the five board tests go red.

**Files:**
- Modify: `sim/game_state.gd`, `game/game_root.gd:9-11`
- Test: `tests/test_meta.gd`, `tests/test_board_input.gd`

**Interfaces:**
- Consumes: `Meta` (Tasks 5–6), `Upgrades.set_max_level` / `grant_level` (Task 7)
- Produces:
  - `const GameState.BASE_FLOORS := 6`, `BASE_SHAFTS := 1`, `BASE_SEED := 20260802`
  - `var GameState.meta: Meta`
  - `GameState._init(floors, shafts, p_seed, catalog_path := …, p_meta: Meta = null, blueprints_path := "res://data/blueprints.json")`
  - `GameState.catalog_path() -> String`, `GameState.blueprints_path() -> String`
  - `tests/test_board_input.gd: func build_to(n: int) -> void` (fixture helper)

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_meta.gd`:

```gdscript
func test_a_fresh_run_caps_at_ten_floors() -> void:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1)
	assert_true(s.is_valid(), "valid")
	for i in range(20):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 10, "run one stops at the ladder's first rung")

func test_a_meta_with_height_raises_the_run_cap() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	m.buy("height", u)
	m.buy("height", u)
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	for i in range(30):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 20, "the ladder's top rung")

func test_a_run_starts_with_the_granted_shafts_and_synced_cars() -> void:
	var m := loaded()
	m.blueprints = 100
	var u := upgrades()
	m.buy("shafts", u)
	m.buy("motor", u)
	m.buy("motor", u)
	var s := GameState.new(GameState.BASE_FLOORS, m.starting_shafts(), 1,
		"res://data/tenants.json", m)
	assert_eq(s.building.cars.size(), 2, "the granted shaft is there")
	assert_eq(s.upgrades.level_of("speed"), 2, "and the granted motor level")
	assert_almost_eq(s.building.cars[0].floors_per_tick,
		s.upgrades.effect_value("speed", 2), 0.0001,
		"the cars are SYNCED, not merely counted")

func test_init_never_resizes_the_building() -> void:
	# The saved size is the authority. Expanding here past saved_floors.size()
	# trips save_codec.gd:156, decode returns null, game_root starts fresh, and
	# the autosave overwrites the only copy.
	var m := loaded()
	m.blueprints = 100
	m.buy("shafts", upgrades())
	var s := GameState.new(8, 1, 1, "res://data/tenants.json", m)
	assert_eq(s.building.floor_count, 8, "floors as handed")
	assert_eq(s.building.cars.size(), 1, "shafts as handed, despite shafts L1")

func test_a_malformed_blueprint_catalog_is_fatal() -> void:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json",
		null, "res://data/does_not_exist.json")
	assert_false(s.is_valid(), "there is no skip-the-tree-and-play-anyway fallback")
	assert_eq(s.invalid_what(), "blueprint catalog", "and it names itself")

func test_an_injected_meta_whose_defs_failed_is_still_fatal() -> void:
	# The check is NOT conditional on p_meta: after the salvage rewiring no
	# production path constructs with a null Meta, so a p_meta == null guard
	# would put the only enforcement of the fatal-data rule on a branch nobody
	# takes.
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json",
		Meta.new())
	assert_false(s.is_valid(), "a bare Meta.new() has no defs")

func test_the_cap_budget_is_measured_against_the_base_size() -> void:
	# Against the CURRENT size it is a level budget measured against a floor
	# count -- correct only at level 0. A player who started at 6 with a cap of
	# 20 and bought 7 floors would reload permanently capped 7 floors below
	# what they paid for.
	var m := loaded()
	m.blueprints = 100
	m.buy("height", upgrades())
	m.buy("height", upgrades())
	var s := GameState.new(13, 1, 1, "res://data/tenants.json", m)
	s.upgrades.restore_levels({"floor": 7})
	for i in range(20):
		s.economy.cash = 1_000_000.0
		s.buy("floor")
	assert_eq(s.building.floor_count, 20, "still reachable after a reload")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta.gd -gexit
```

- [ ] **Step 3: Implement `GameState`**

Add the constants and fields, and rewrite `_init`:

```gdscript
## The size and seed a building BEGINS at. They live here rather than in
## game_root because game/game_root.gd has no class_name (line 1 is a bare
## `extends Control`) and sim/ must not reach into game/ regardless.
const BASE_FLOORS := 6
const BASE_SHAFTS := 1
const BASE_SEED := 20260802

## The persistent half of the game. GameState READS it and never writes it --
## crediting is Prestige's job, spending is Meta.buy's.
var meta: Meta

## Kept rather than consumed and dropped, so Prestige.demolish can rebuild
## against the same catalogs this run used instead of silently reverting to the
## shipped ones and defeating every override.
var _catalog_path: String = ""
var _blueprints_path: String = ""

func _init(floors: int, shafts: int, p_seed: int,
		catalog_path := "res://data/tenants.json",
		p_meta: Meta = null,
		blueprints_path := "res://data/blueprints.json") -> void:
	_catalog_path = catalog_path
	_blueprints_path = blueprints_path

	meta = p_meta if p_meta != null else Meta.new()
	if p_meta == null:
		meta.load_defs(blueprints_path)
	# NOT conditional on p_meta. An injected Meta whose defs failed is exactly
	# the case a `p_meta == null` guard waves through, and after the salvage
	# rewiring no production path constructs with a null Meta at all.
	if not meta.is_usable():
		_invalid_what = "blueprint catalog"
		_invalid_path = blueprints_path
		return

	clock = SimClock.new()
	# VERBATIM: _init never resizes the building. The Meta's starting size is
	# applied by the callers that BEGIN a run -- Prestige.demolish and
	# game_root's cold-boot branch -- because on the decode path the saved size
	# is the authority, full stop.
	building = Building.new(floors, shafts)
	spawner = TrafficSpawner.new(p_seed)
	spawner.load_curve("res://data/traffic_walkup.json")
	economy = Economy.new()

	catalog = TenantCatalog.new()
	if not catalog.load_from(catalog_path):
		_invalid_what = "tenant catalog"
		_invalid_path = catalog_path
		return

	var prefix := mini(building.floor_count, DEFAULT_ROSTER.size())
	tenancy = Tenancy.new(building.floor_count, prefix)
	fitout = Fitout.new(building.floor_count)
	for floor_index in range(prefix):
		tenancy.set_kind(floor_index, DEFAULT_ROSTER[floor_index])

	upgrades = Upgrades.new()
	upgrades.load_defs("res://data/upgrades.json")
	metrics = Metrics.new()
	auto = AutoDispatch.new()

	# Everything below is AFTER load_defs: following the reading order above
	# (building -> set_max_level) writes a crash on an empty _defs.
	#
	# The budgets are measured against the BASE size, not the current one. The
	# other way round is a LEVEL budget measured against a FLOOR COUNT, correct
	# only at level 0 -- and on reload save_codec.gd:124 rebuilds at the grown
	# size while :135 restores the cumulative purchase count on top of it.
	upgrades.set_max_level("floor", meta.height_cap() - BASE_FLOORS)
	upgrades.set_max_level("shaft", Building.MAX_SHAFTS - BASE_SHAFTS)
	upgrades.grant_level("floor", building.floor_count - BASE_FLOORS, building)
	upgrades.grant_level("shaft", building.cars.size() - BASE_SHAFTS, building)
	for id in ["speed", "doors", "capacity"]:
		upgrades.grant_level(id, meta.starting_level(id), building)

	_valid = true

func catalog_path() -> String:
	return _catalog_path

func blueprints_path() -> String:
	return _blueprints_path
```

- [ ] **Step 4: Point `game_root`'s constants at the sim**

In `game/game_root.gd`, replace lines 9-11:

```gdscript
const START_FLOORS := GameState.BASE_FLOORS
const START_SHAFTS := GameState.BASE_SHAFTS
const START_SEED := GameState.BASE_SEED
const DEFAULT_BLUEPRINTS := "res://data/blueprints.json"

## Test seam, beside catalog_path_override: lets a test hand in a missing or
## malformed blueprint catalog and assert the boot path does the right thing,
## without mutating the shipped file.
var blueprints_path_override: String = ""
```

and thread the blueprints path through `_ready`'s construction the same way
`catalog_path` already is:

```gdscript
	var blueprints_path := blueprints_path_override
	if blueprints_path.is_empty():
		blueprints_path = DEFAULT_BLUEPRINTS
```

with both `GameState.new(...)` calls in `_ready` taking
`(floors, shafts, START_SEED, catalog_path, null, blueprints_path)`.

- [ ] **Step 5: Fix the five board tests the 10-floor cap breaks**

An empty Meta caps at 10 floors, so only 4 of the 14 floor purchases in these
tests now succeed, leaving a 10-floor board whose `content_height()` (880) is
under the 1184 viewport — scroll travel is 0 and floor 12 does not exist.

| test | line | why |
| --- | --- | --- |
| `test_a_drag_pans_the_board_and_dispatches_nothing` | `:127` | scroll travel is 0 |
| `test_the_board_cannot_be_panned_off_either_end` | `:143` | scroll travel is 0 |
| `test_a_tap_after_scrolling_still_hits_the_floor_it_looks_like` | `:177` | targets floor 12 |
| `test_a_tap_on_the_hall_selects_the_floor_it_looks_like_after_scrolling` | `:272` | targets floor 12 |
| `test_a_drag_on_the_hall_pans_and_does_not_select` | `:286` | scroll travel is 0 |

These five are about the **scroll transform**; their 20 floors are incidental.
Add a fixture helper and route them through it:

```gdscript
## Raises the running state's floor cap through the Meta, then builds to n
## floors. It grants height on the state the scene ALREADY built rather than
## constructing a replacement, because the scene reads its state in _ready and
## swapping it needs _rebuild_views(), which does not exist until Task 16.
##
## Buying through meta.buy() rather than poking _spent keeps the helper honest:
## if the ladder's costs move, this goes red rather than silently diverging
## from what a player can actually reach.
func build_to(n: int) -> void:
	var meta: Meta = root.state.meta
	meta.blueprints = 1000
	while meta.height_cap() < n and not meta.is_maxed("height"):
		assert_true(meta.buy("height", root.state.upgrades), "height level")
	root.state.upgrades.set_max_level("floor",
		meta.height_cap() - GameState.BASE_FLOORS)
	while root.state.building.floor_count < n:
		root.state.economy.cash = 1_000_000.0
		assert_true(root.state.buy("floor"),
			"floor %d" % root.state.building.floor_count)
	await wait_physics_frames(2)
```

Replace each of the five tests' floor-buying loop with `await build_to(20)`.

- [ ] **Step 6: Run the full suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: green. `test_row_purchases_stop_at_the_purchasable_cap` and
`test_a_maxed_upgrade_cannot_be_bought` in `tests/test_upgrades.gd` do **not**
break — that file's `before_each` builds `Upgrades` directly with no
`GameState`, therefore no `set_max_level`. If you find yourself trying to make
them fail, stop: the spec explains at length why they survive.

- [ ] **Step 7: Commit**

```bash
git add sim/game_state.gd game/game_root.gd tests/test_meta.gd tests/test_board_input.gd
git commit -F - <<'EOF'
Make the floor cap a per-run number the Meta supplies, starting at 10

The cost-curve work deliberately split the purchasable cap (20) from the
structural one (40) and wrote down why; this is the ladder that lives in that
gap. data/upgrades.json is not edited at all -- with the ladder topping out at
20, floor.max_level = 14 IS the top rung.

Two things are load-bearing and read wrong at a glance:

_init never resizes the building. Expanding to the Meta's starting size on the
decode path grows it past saved_floors.size(), which trips the codec's refusal,
starts a fresh game, and lets the autosave overwrite the only copy ten seconds
later. The Meta's size is applied by the callers that BEGIN a run.

The cap budget is measured against BASE_FLOORS, not the current floor count.
Against the current size it is a level budget measured against a floor count --
correct only at level 0, and on reload it caps a player below what they paid
for.

The five board tests that build a tall building now grant height first. They
are about the scroll transform; their twenty floors were incidental.
EOF
```

---

## Task 9: `Prestige` — the conversion and the demolish

**Why:** spec §2 and §7. The order inside `demolish()` took three attempts to get
right, and two of the three wrong versions mint Blueprints.

**Files:**
- Create: `sim/prestige.gd`, `tests/test_prestige.gd`
- Test: `tests/test_meta.gd` (the cross-module pin)

**Interfaces:**
- Consumes: `Meta` (Tasks 5–6), `GameState` (Task 8)
- Produces:
  - `const Prestige.MAX_YIELD := 1_000_000_000`, `DEMOLITION_FLOOR`, `EARNINGS_PER_BLUEPRINT := 100.0`
  - `static func yield_for(earnings: float) -> int`
  - `static func can_demolish(state: GameState) -> bool`
  - `static func demolish(state: GameState) -> GameState` — null on any refusal

> `DEMOLITION_FLOOR` is whatever Task 2 settled on. The tests below are written
> against **900.0**; if Task 2 moved it, re-derive the boundary figures from the
> same law — *n* Blueprints need `DEMOLITION_FLOOR + 100n²` of earnings.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_prestige.gd`:

```gdscript
extends GutTest

## Prestige is the one place that knows a run can end. It is pure: it never
## calls SaveStore -- the write happens in game_root.save_now(next) -- which is
## why write-before-swap is tested at the scene boundary instead of here.

const F := Prestige.DEMOLITION_FLOOR

func played(earnings: float) -> GameState:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1)
	assert_true(s.is_valid(), "valid")
	# accrue() has no production callers, which makes it the cheap way to seed E.
	s.economy.accrue(earnings)
	return s

func test_the_conversion_walks_its_boundaries() -> void:
	assert_eq(Prestige.yield_for(0.0), 0, "nothing earned")
	assert_eq(Prestige.yield_for(F), 0, "the floor itself pays nothing")
	assert_eq(Prestige.yield_for(F + 100.0), 1, "the first blueprint")
	assert_eq(Prestige.yield_for(F + 399.0), 1, "one short of the second")
	assert_eq(Prestige.yield_for(F + 400.0), 2, "the second")
	assert_eq(Prestige.yield_for(F + 1600.0), 4, "the fourth")

func test_an_enormous_earnings_clamps_and_stays_finite() -> void:
	assert_eq(Prestige.yield_for(1e308), Prestige.MAX_YIELD, "clamped")
	assert_true(is_finite(float(Prestige.yield_for(1e308))), "finite")

func test_a_nan_earnings_yields_nothing() -> void:
	# Pins maxf's ARGUMENT ORDER against a tidy-up: maxf(NAN - F, 0.0) is 0.0,
	# but maxf(0.0, NAN - F) is NAN and minf(NAN, MAX_YIELD) is MAX_YIELD --
	# a billion Blueprints from a poisoned save.
	assert_eq(Prestige.yield_for(NAN), 0, "absorbed")

func test_max_yield_equals_the_metas_ceiling() -> void:
	# Raise one later and a maxed save silently loses the difference on reload,
	# with every test green.
	assert_eq(Prestige.MAX_YIELD, Meta.MAX_BLUEPRINTS, "one statement, two files")

func test_a_demolish_under_the_gate_is_refused_and_changes_nothing() -> void:
	var s := played(F)
	s.economy.cash = 500.0
	var before_floors := s.building.floor_count
	assert_null(Prestige.demolish(s), "refused")
	assert_eq(s.economy.cash, 500.0, "cash untouched")
	assert_eq(s.building.floor_count, before_floors, "floors untouched")
	assert_false(s.tenancy.is_vacant(0), "tenancy untouched")

func test_a_refusal_leaves_the_metas_balance_untouched() -> void:
	var s := played(F)
	s.meta.blueprints = 7
	s.meta.runs_completed = 3
	assert_null(Prestige.demolish(s), "refused")
	assert_eq(s.meta.blueprints, 7, "no credit on a refusal")
	assert_eq(s.meta.runs_completed, 3, "and no run counted")

func test_a_successful_demolish_credits_only_the_new_state() -> void:
	# GameState holds the Meta BY REFERENCE, so crediting the shared object
	# would leave the live run holding Blueprints it never earned -- and the
	# ten-second autosave then writes that credited Meta beside a still
	# demolish-eligible building.
	var s := played(F + 1600.0)
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.meta.blueprints, 4, "the fresh run is credited")
	assert_eq(s.meta.blueprints, 0, "the handed run is NOT")
	assert_eq(next.meta.runs_completed, 1, "one run banked")
	assert_eq(s.meta.runs_completed, 0, "on the clone only")

func test_a_successful_demolish_resets_every_row_of_the_table() -> void:
	# Row by row, not a sample: a demolish that forgets `fitout` hands the next
	# run free class-3 floors at a 1.8x fare multiplier forever, and stays green.
	var s := played(F + 1600.0)
	s.economy.cash = 5000.0
	s.economy.combo = 4.0
	s.economy.streak = 40
	s.economy.riders_served = 99
	s.buy("floor")
	s.fitout.set_tier(0, 3)
	s.clock.note_ticks(5000)
	var next := Prestige.demolish(s)
	assert_not_null(next, "allowed")
	assert_eq(next.economy.cash, 0.0, "cash")
	assert_eq(next.economy.lifetime_earnings, 0.0, "lifetime -- it IS the yield input")
	assert_eq(next.economy.combo, 1.0, "combo")
	assert_eq(next.economy.streak, 0, "streak")
	assert_eq(next.economy.riders_served, 0, "riders")
	assert_eq(next.building.floor_count, GameState.BASE_FLOORS, "floors")
	assert_eq(next.building.cars.size(), next.meta.starting_shafts(), "cars")
	assert_eq(next.upgrades.level_of("floor"), 0, "upgrade levels")
	assert_false(next.tenancy.is_vacant(0), "tenancy rebuilt from the roster")
	assert_eq(next.fitout.tier_at(0), Fitout.BASE_TIER,
		"class tiers -- this row is what keeps 'every run re-earns its tenants' true")
	assert_eq(next.auto.preset_of(0), DispatchPolicy.Preset.MANUAL, "policies")
	assert_eq(next.metrics.deliveries(), 0, "metrics")
	assert_eq(next.clock.ticks_executed, 0, "the clock -- a new building opens at 06:00")

func test_the_new_seed_is_derived_from_the_run_count() -> void:
	# The LITERAL, not the symbolic form: asserting BASE_SEED + runs_completed
	# lets a pre/post-increment mistake reproduce on both sides and pass. And
	# mere inequality is insufficient -- a loaded run carries an unrelated seed.
	var s := played(F + 1600.0)
	var next := Prestige.demolish(s)
	assert_eq(next.spawner.seed_value(), GameState.BASE_SEED + 1,
		"run 2 must not replay run 1's traffic forever")
	next.economy.accrue(F + 1600.0)
	var third := Prestige.demolish(next)
	assert_eq(third.spawner.seed_value(), GameState.BASE_SEED + 2, "and run 3")

func test_two_demolishes_do_not_pay_twice_for_one_run() -> void:
	# The strongest test in the file: it fails loudly if lifetime_earnings is
	# ever made to persist, which is the unbounded-minting hole.
	var s := played(F + 1600.0)
	var second := Prestige.demolish(s)
	assert_eq(second.meta.blueprints, 4, "first demolish")
	second.economy.accrue(F + 1600.0)
	var third := Prestige.demolish(second)
	assert_eq(third.meta.blueprints, 8, "4 + 4, not 4 + 8")

func test_demolish_spam_earns_nothing() -> void:
	var s := played(F + 1600.0)
	var second := Prestige.demolish(s)
	assert_not_null(second, "the first one is allowed")
	assert_null(Prestige.demolish(second), "with no play in between, nothing")

func test_a_demolish_into_an_invalid_state_is_refused() -> void:
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json",
		null, "res://data/blueprints.json")
	s.economy.accrue(F + 1600.0)
	s._catalog_path = "res://data/does_not_exist.json"
	assert_null(Prestige.demolish(s), "refused rather than swapping in a dead run")
	assert_eq(s.meta.blueprints, 0, "and nothing was credited on the way")

func test_the_tree_survives_the_demolish() -> void:
	var s := played(F + 1600.0)
	s.meta.blueprints = 10
	assert_true(s.meta.buy("height", s.upgrades), "buy a node")
	var next := Prestige.demolish(s)
	assert_eq(next.meta.level_of("height"), 1, "spent levels are kept")
	assert_eq(next.meta.height_cap(), 15, "and the next run gets the cap it paid for")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_prestige.gd -gexit
```

- [ ] **Step 3: Implement `sim/prestige.gd`**

```gdscript
class_name Prestige
extends RefCounted

## Static functions only. The one place that knows a run can end.
##
## Demolish BUILDS a fresh GameState rather than wiping the live one. Every
## container GameState.new already initialises from zero stays initialised from
## zero, so a wipe-in-place would be a second clearing path that can only ever
## desync from the one construction uses.

## == Meta.MAX_BLUEPRINTS, deliberately: a legitimately clamped yield must not
## fail its own decode on the next load. Pinned by a test.
const MAX_YIELD := 1_000_000_000
## A flat sum of earnings that pays for the demolition itself. It exists to
## break the SCALE INVARIANCE of a bare square root: without it the first
## Blueprint is always the cheapest, so leaving immediately is always
## rate-optimal and the whole loop is a button-mashing exploit.
const DEMOLITION_FLOOR := 900.0
const EARNINGS_PER_BLUEPRINT := 100.0

## n Blueprints need DEMOLITION_FLOOR + 100n^2 of earnings, so the n-th one
## costs $100(2n - 1) -- each $200 more than the one before it, which is the
## property that made the square root the right family and which a logarithm
## does not have.
##
## THE ARGUMENT ORDER IN maxf IS LOAD-BEARING AND MUST NOT BE TIDIED.
## maxf(a, b) returns `a > b ? a : b`, so maxf(NAN - FLOOR, 0.0) is 0.0 and a
## NAN input is absorbed into a zero yield. Written the other way round it
## returns NAN, and minf(NAN, MAX_YIELD) then returns MAX_YIELD -- a billion
## Blueprints from a poisoned save.
##
## The clamp is in FLOAT space because mini() takes ints, which would do the
## out-of-range cast first: int(sqrt(1e308 / 100)) is 1e153 against an int64
## max of 9.22e18, and out-of-range float->int is platform-defined.
static func yield_for(earnings: float) -> int:
	return int(minf(sqrt(maxf(earnings - DEMOLITION_FLOOR, 0.0) / EARNINGS_PER_BLUEPRINT),
			float(MAX_YIELD)))

## The gate is 1 Blueprint. Without it a new player can wipe a run for nothing,
## which would be a self-inflicted fail state in a game whose stated invariant
## is that there is none.
static func can_demolish(state: GameState) -> bool:
	return yield_for(state.economy.lifetime_earnings) >= 1

## Returns the run that REPLACES this one, or null when anything refuses.
##
## The order is load-bearing and it took three attempts to get right:
##
##   1. compute the yield and refuse under the gate
##   2. CLONE the Meta, checking BOTH bools
##   3. credit the CLONE only
##   4. build the fresh state against the clone
##   5. validate; the handed Meta was never touched, so there is nothing to
##      roll back
##   6. return -- the credit exists ONLY inside `fresh`
##
## Crediting the live Meta instead is not merely untidy. GameState holds it BY
## REFERENCE, so the credit becomes visible to the old run the moment this
## returns -- and the caller's save can still fail. When it does, the old run
## plays on holding Blueprints it never earned, Meta.buy() can spend them, and
## the ten-second autosave writes that credited Meta beside a still
## demolish-eligible building in one perfectly valid payload. Demolish again
## and the same earnings pay twice.
##
## Both bools at step 2 are checked HERE, in the block an implementer copies:
## unchecked, a failed defs load makes restore drop every spent level (it
## iterates ids()), and step 6 would then durably persist an emptied tree.
static func demolish(state: GameState) -> GameState:
	var bp := yield_for(state.economy.lifetime_earnings)
	if bp < 1:
		return null

	var staged := Meta.new()
	if not staged.load_defs(state.blueprints_path()):
		return null
	if not staged.restore(state.meta.to_dict()):
		return null

	# mini() is not decoration: the codec clamps `blueprints` to MAX_BLUEPRINTS
	# at decode, so an uncapped credit would exceed a bound the next load
	# silently trims. The in-memory and on-disk invariants are one statement.
	staged.blueprints = mini(staged.blueprints + bp, Meta.MAX_BLUEPRINTS)
	staged.runs_completed = mini(staged.runs_completed + 1, Meta.MAX_RUNS)

	# The seed is derived, not random, so the game stays reproducible from a
	# save. Read AFTER the increment: pre-increment, run 2 draws BASE_SEED + 0
	# and replays run 1's traffic forever.
	var fresh := GameState.new(GameState.BASE_FLOORS, staged.starting_shafts(),
			GameState.BASE_SEED + staged.runs_completed,
			state.catalog_path(), staged, state.blueprints_path())
	if not fresh.is_valid():
		return null
	return fresh
```

- [ ] **Step 4: Run, then the suite**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_prestige.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 5: Commit**

```bash
git add sim/prestige.gd sim/prestige.gd.uid tests/test_prestige.gd tests/test_prestige.gd.uid tests/test_meta.gd
git commit -F - <<'EOF'
Convert a run's earnings into Blueprints, and stage the credit on a clone

The conversion carries a flat offset because a bare sqrt(E/D) is degenerate:
the first Blueprint is always the cheapest, so leaving after nine minutes at
six floors earns 6.67 BP/hour against a proper two-hour run's 2.0. Scaling the
divisor moves the exit time and not the shape -- the scale invariance has to
be broken, not tuned.

demolish credits a CLONED Meta, not the live one. GameState holds the Meta by
reference, so crediting it before the caller's save can fail leaves the old run
holding Blueprints it never earned -- and the ten-second autosave then writes
that credited Meta beside a still-demolish-eligible building, in one perfectly
valid payload. The same earnings would pay twice on the next reload.

E is per-run. Making lifetime_earnings cumulative mints without limit, so the
test that demolishes twice for 4 + 4 rather than 4 + 8 is the strongest one in
the file.
EOF
```

---

## Task 10: Save format v4 — the meta block, the preflight, and decode's ordering

**Why:** spec §9. The Meta rides in the same file as the run because a demolish
must persist the credited Blueprints and the discarded building in **one** write.

**Files:**
- Modify: `sim/save_codec.gd`
- Test: `tests/test_save_codec.gd`

**Interfaces:**
- Consumes: `Meta` (Tasks 5–6), `GameState._init`'s new parameters (Task 8)
- Produces:
  - `const SaveCodec.VERSION := 4`, `SUPPORTED_VERSIONS := [1, 2, 3, 4]`
  - `static func decode(p_data: Dictionary, catalog_path := "res://data/tenants.json", blueprints_path := "res://data/blueprints.json") -> GameState`
  - `encode()` gains a top-level `"meta"` key from `Meta.to_dict()`
  - `static func _preflight(data: Dictionary) -> bool`
  - `static func _migrate_to_v4(data: Dictionary) -> Dictionary`
  - `static func _legacy_meta(floor_count: int, blueprints_path: String) -> Meta` — **`version <= 3` only**
  - `static func _empty_meta(blueprints_path: String) -> Meta`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_save_codec.gd`:

```gdscript
func meta_state() -> GameState:
	var m := Meta.new()
	assert_true(m.load_defs("res://data/blueprints.json"), "defs")
	m.blueprints = 7
	m.runs_completed = 3
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	assert_true(m.buy("height", s.upgrades), "a node the save must carry")
	return s

func test_a_populated_meta_round_trips_in_memory() -> void:
	# The test that catches a TYPE_FLOAT-only rule rejecting the codec's own
	# GDScript ints: encode() returns a live Dictionary, and the whole suite
	# round-trips with no JSON.stringify between.
	var before := meta_state()
	var after := SaveCodec.decode(SaveCodec.encode(before))
	assert_not_null(after, "decodes")
	assert_eq(after.meta.blueprints, 7, "blueprints")
	assert_eq(after.meta.runs_completed, 3, "runs")
	assert_eq(after.meta.level_of("height"), 1, "spent")

func test_the_cap_survives_a_reload() -> void:
	# Every other codec test operates on a fresh or legacy state, which is
	# exactly where the broken cap arithmetic happened to be right.
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	m.blueprints = 100
	var s := GameState.new(GameState.BASE_FLOORS, 1, 1, "res://data/tenants.json", m)
	m.buy("height", s.upgrades)
	m.buy("height", s.upgrades)
	for i in range(7):
		s.economy.cash = 1_000_000.0
		assert_true(s.buy("floor"), "floor %d" % i)
	var after := SaveCodec.decode(SaveCodec.encode(s))
	assert_not_null(after, "decodes")
	for i in range(20):
		after.economy.cash = 1_000_000.0
		after.buy("floor")
	assert_eq(after.building.floor_count, 20, "twenty is still reachable")

func test_a_save_is_not_refused_because_the_meta_grants_more_than_it_holds() -> void:
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	m.blueprints = 100
	var s := GameState.new(8, 1, 1, "res://data/tenants.json", m)
	m.buy("shafts", s.upgrades)
	var after := SaveCodec.decode(SaveCodec.encode(s))
	assert_not_null(after, "not refused")
	assert_eq(after.building.floor_count, 8, "at the size it was saved at")

func test_a_v4_save_with_the_meta_erased_is_not_grandfathered() -> void:
	# Keying on a missing key rather than on the version would hand a truncated
	# or tampered v4 file the whole cap ladder, permanently.
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	var s := GameState.new(20, 1, 1, "res://data/tenants.json", m)
	var data := SaveCodec.encode(s)
	data.erase("meta")
	var after := SaveCodec.decode(data)
	assert_not_null(after, "still loads")
	assert_eq(after.meta.level_of("height"), 0, "and grants nothing")

func test_a_malformed_v4_meta_yields_an_empty_meta_rather_than_refusing() -> void:
	# In this codebase "refuse" means "delete": decode returns null, game_root
	# starts fresh, and the autosave overwrites the only copy within ten
	# seconds. Losing a tech tree beats losing a building. The INVERSE of this
	# test is what a future reviewer will try to "fix".
	var s := meta_state()
	var data := SaveCodec.encode(s)
	data["meta"] = "not a dictionary"
	var after := SaveCodec.decode(data)
	assert_not_null(after, "the building survives")
	assert_eq(after.building.floor_count, GameState.BASE_FLOORS, "intact")
	assert_eq(after.meta.blueprints, 0, "the tree does not")

func test_a_legacy_save_is_granted_the_height_its_building_implies() -> void:
	for pair in [[6, 0, 10], [11, 1, 15], [14, 1, 15], [20, 2, 20]]:
		var m := Meta.new()
		m.load_defs("res://data/blueprints.json")
		var s := GameState.new(pair[0], 1, 1, "res://data/tenants.json", m)
		var data := SaveCodec.encode(s)
		data["version"] = 3
		data.erase("meta")
		var after := SaveCodec.decode(data)
		assert_not_null(after, "%d floors decodes" % pair[0])
		assert_eq(after.meta.level_of("height"), pair[1], "%d floors -> height" % pair[0])
		assert_eq(after.meta.height_cap(), pair[2], "%d floors -> cap" % pair[0])
		assert_eq(after.building.floor_count, pair[0], "and loses no floors")
		assert_eq(after.meta.blueprints, 0, "granted, never charged")

func test_a_malformed_blueprint_catalog_refuses_the_decode() -> void:
	# Malformed SHIPPED data still refuses. The asymmetry is between data the
	# player cannot have damaged and a file they can.
	var s := meta_state()
	assert_null(SaveCodec.decode(SaveCodec.encode(s), "res://data/tenants.json",
		"res://data/does_not_exist.json"), "fatal")

func test_decode_refuses_an_invalid_state_rather_than_handing_it_back() -> void:
	# game_state.gd already CLAIMS this; it has been aspirational until now.
	var s := meta_state()
	assert_null(SaveCodec.decode(SaveCodec.encode(s),
		"res://data/does_not_exist.json"), "null, not a poisoned state")

func test_the_preflight_refuses_shapes_migration_would_abort_on() -> void:
	# Each of these aborts inside _migrate_to_v3 today, BEFORE any check runs.
	# GUT fails a test on unhandled engine errors, so "without throwing" is a
	# real and observable assertion.
	for poison in [{"version": {}}, {"cars": null}, {"levels": []},
			{"floor_count": {}}]:
		var data := SaveCodec.encode(GameState.new(6, 1, 1))
		for key in poison:
			data[key] = poison[key]
		assert_null(SaveCodec.decode(data), "%s is refused" % [poison])

func test_blueprints_survive_the_demolish_write() -> void:
	# The demolish and the discarded building arrive in ONE payload. A crash
	# between two writes would either duplicate the yield or destroy it.
	var s := meta_state()
	s.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	var next := Prestige.demolish(s)
	assert_not_null(next, "demolished")
	var after := SaveCodec.decode(SaveCodec.encode(next))
	assert_not_null(after, "decodes")
	assert_eq(after.meta.blueprints, 11, "7 banked plus 4 earned")
	assert_eq(after.meta.runs_completed, 4, "the run was counted")
	assert_eq(after.building.floor_count, GameState.BASE_FLOORS,
		"and the smaller building came in the same payload")

func test_the_real_device_fixture_is_grandfathered_and_charged_nothing() -> void:
	# _real_v2_save() (:222) is a REAL v2 save pulled off the device before the
	# rename -- the only input in this file nobody wrote. Padded exactly as the
	# two tests below it already pad it.
	var data := _real_v2_save()
	(data["rows"] as Array).resize(7)
	for i in range(1, 7):
		data["rows"][i] = {"class": 1, "kind": "apartments",
			"move_out_left": 0, "satisfaction": 0.9, "vacant": false}
	var after := SaveCodec.decode(data)
	assert_not_null(after, "a v2 save still loads under v4")
	assert_eq(after.building.floor_count, 7, "and loses no floors")
	assert_eq(after.meta.blueprints, 0, "granted, never charged")
	assert_eq(after.meta.level_of("height"), 0, "seven floors implies no height")
	assert_eq(after.meta.height_cap(), 10, "so it gets the base cap")

func test_a_v3_save_still_migrates_its_keys() -> void:
	# _migrate_to_v4 must be a SEPARATE function: _migrate_to_v3 early-returns
	# at version >= 3, so a v4 phase nested inside it would never run for the
	# v3 saves that need it most.
	var s := GameState.new(7, 1, 99)
	var data := SaveCodec.encode(s)
	data["version"] = 2
	data["row_count"] = data["floor_count"]
	data.erase("floor_count")
	data["rows"] = data["floors"]
	data.erase("floors")
	var after := SaveCodec.decode(data)
	assert_not_null(after, "a v2 save still loads")
	assert_eq(after.building.floor_count, 7, "with its floors")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_codec.gd -gexit
```

- [ ] **Step 3: Implement**

In `sim/save_codec.gd`:

```gdscript
const VERSION := 4
const SUPPORTED_VERSIONS := [1, 2, 3, 4]
```

Extend the class docstring (`:17-21`) with a v4 sentence:

```gdscript
## v4 adds a `meta` block: the persistent Blueprints and tech tree. It rides in
## the same file as the run because a demolish must persist the credited
## Blueprints and the discarded building in ONE write -- a crash between two
## writes either duplicates the yield or destroys it.
```

Add the meta key to `encode()`'s returned dictionary:

```gdscript
		"floors": floors,
		"meta": state.meta.to_dict(),
```

Add the preflight, the v4 migration, and the two named meta builders:

```gdscript
## Refuses top-level shapes that MIGRATION ITSELF would abort on, which is why
## it has to run before _migrate_to_v3 rather than after it: that function's
## first statement is int(data.get("version", -1)) (:41) and it assigns `levels`
## to a typed Dictionary (:55), both before any check exists in the flow.
##
## TYPE ONLY. It performs no clamping and no semantic checks -- those live in
## decode beside the assignments they guard. And `meta` is deliberately NOT
## preflighted: §9's rule is that an absent OR malformed v4 meta yields an
## empty Meta and decodes successfully, so refusing a non-Dictionary meta here
## would contradict the rescue three functions away. Meta.restore() already
## handles every malformed shape without throwing.
##
## Type first, then value, throughout: is_finite(Dictionary) is itself a
## runtime error.
static func _preflight(data: Dictionary) -> bool:
	if not _is_number(data.get("version", 0)):
		return false
	if not _is_number(data.get("floor_count", 1)):
		return false
	if data.has("levels") and typeof(data["levels"]) != TYPE_DICTIONARY:
		return false
	for key in ["cars", "floors", "policies"]:
		if data.has(key) and typeof(data[key]) != TYPE_ARRAY:
			return false
	return true

## Numeric, finite and integral. A stored `null` counts as absent for the
## callers above, which pass a default in.
static func _is_number(v: Variant) -> bool:
	if v == null:
		return true
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t != TYPE_FLOAT:
		return false
	var fv: float = v
	return is_finite(fv) and fv == floorf(fv)

## A separate function, NOT a phase appended inside _migrate_to_v3: that one
## early-returns at version >= 3 (:40-42), so a v4 phase nested inside it would
## never run for the v3 saves that need it most.
##
## v4 adds a key rather than moving one, so there is nothing to rewrite -- the
## meta block's absence is handled by the version-gated builders below.
static func _migrate_to_v4(data: Dictionary) -> Dictionary:
	return data

## The height levels a legacy building already implies. version <= 3 ONLY.
##
## Exact, not approximate: the ladder is 10 + 5n, so this inverts it. The levels
## are GRANTED, not charged -- blueprints stays 0 -- because charging for what
## is already built would present an existing player with a building they
## cannot afford to keep.
##
## Keying this on `not data.has("meta")` instead would route a V4 save whose
## meta key is absent here, granting Structure levels permanently to a
## truncated write or a tampered file. Hence the version gate at the call site.
static func _legacy_meta(floor_count: int, blueprints_path: String) -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	var level := clampi(ceili((floor_count - 10) / 5.0), 0, 2)
	m.restore({"spent": {"height": level}})
	return m

## blueprints 0, runs 0, spent {}. version == 4, absent OR malformed.
##
## "Does not refuse" and "receives grandfather grants" are different properties.
## Both v4 paths do not refuse; NEITHER grants.
static func _empty_meta(blueprints_path: String) -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	return m
```

Rewrite `decode`'s opening to the required order —
`preflight → _migrate_to_v3 → _migrate_to_v4 → _is_usable → build the Meta →
GameState.new → restore_levels → cars → floors → policies`:

```gdscript
static func decode(p_data: Dictionary,
		catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> GameState:
	if not _preflight(p_data):
		return null
	var data := _migrate_to_v4(_migrate_to_v3(p_data))
	if not _is_usable(data):
		return null

	var floors: int = int(data["floor_count"])
	var version := int(data["version"])

	# The Meta must exist before GameState.new, because every cap derivation
	# lives in _init. And grandfathering runs AFTER migration, because v1 and
	# v2 spell the key `row_count` -- reading floor_count first yields 0 and
	# grants a 20-floor v2 save a cap of 10.
	var meta: Meta
	if version <= 3:
		meta = _legacy_meta(floors, blueprints_path)
	else:
		meta = _empty_meta(blueprints_path)
		if meta != null and not meta.restore(data.get("meta")):
			return null
	if meta == null:
		return null            # malformed SHIPPED data is fatal

	var cars: Array = data["cars"]
	var state := GameState.new(floors, maxi(cars.size(), 1), int(data["seed"]),
		catalog_path, meta, blueprints_path)
	if not state.is_valid():
		return null
	...
```

The rest of `decode`'s body is unchanged in this task; Task 11 adds its
validation. Note `version` moves above `GameState.new` — delete the later
`var version := int(data["version"])` at the old `:147`.

Thread the new parameters through `SaveStore`:

```gdscript
static func load_all(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> Dictionary:
	var parsed: Variant = _select()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"state": null, "meta": null}     # Task 12
	return {
		"state": SaveCodec.decode(parsed as Dictionary, catalog_path, blueprints_path),
		"meta": null,                            # Task 12
	}

static func load_state(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> GameState:
	return load_all(catalog_path, blueprints_path)["state"]
```

and update `game_root`'s call at `:67` to
`SaveStore.load_all(catalog_path, blueprints_path)["state"]` (Task 12 replaces
this with the full salvage branch).

- [ ] **Step 4: Run, then the suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_codec.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: green, including the five existing `assert_null` tests at
`tests/test_save_codec.gd:120, :126, :131, :136, :211` — `decode`'s refusal
contract is unchanged.

- [ ] **Step 5: Commit**

```bash
git add sim/save_codec.gd game/save_store.gd game/game_root.gd tests/test_save_codec.gd
git commit -F - <<'EOF'
Save format v4: the tech tree rides in the same file as the run

It has to. A demolish must persist the credited Blueprints and the discarded
building in ONE write, or a crash between two writes either duplicates the
yield or destroys it.

Two names, never one. legacy_meta() grants the height levels a building
already implies and is gated on version <= 3; empty_meta() grants nothing and
covers a v4 meta that is absent OR malformed. Using one word for both
behaviours is how an erased v4 save ends up handed the whole cap ladder for
free, permanently -- `data.get("meta")` on an erased key is null, which is not
a Dictionary, so a "malformed falls through to grandfather" rule catches it.

Validation cannot start after migration, because migration itself throws:
_migrate_to_v3's first statement casts `version` and it assigns `levels` to a
typed Dictionary, both before any check runs. Hence a type preflight ahead of
everything.
EOF
```

---

## Task 11: Decode-side validation — the fields `Meta.restore()` never sees

**Why:** spec §9. Checking `lifetime` alone does not close the hole, because
`combo` writes straight into it: `"combo": 1e400` is valid JSON, parses to `INF`,
poisons `lifetime_earnings` on the first delivery *after* any decode-time check
has run, and then heals itself to 10.0 on the next line. `yield_for(INF)` returns
`MAX_YIELD` — a billion Blueprints from one passenger.

**Files:**
- Modify: `sim/save_codec.gd`
- Test: `tests/test_save_codec.gd`

**Interfaces:**
- Produces (private helpers on `SaveCodec`):
  - `static func _num(v: Variant, fallback: float) -> float` — finite, else fallback
  - `static func _bounded(v: Variant, lo: float, hi: float, fallback: float) -> float`
  - `static func _bounded_int(v: Variant, lo: int, hi: int, fallback: int) -> int` — clamps in float space before `int()`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_save_codec.gd`:

```gdscript
func test_a_poisoned_lifetime_yields_nothing() -> void:
	var data := SaveCodec.encode(played_state())
	data["lifetime"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_eq(Prestige.yield_for(after.economy.lifetime_earnings), 0, "no mint")

func test_a_poisoned_combo_cannot_poison_lifetime_on_the_first_delivery() -> void:
	# The single most important test here: a `lifetime` check alone does not
	# close this, because credit_delivery multiplies the field the conversion
	# consumes and then heals the combo on the very next line.
	var data := SaveCodec.encode(played_state())
	data["combo"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_true(after.economy.combo <= Economy.COMBO_MAX, "clamped to the cap")
	after.economy.credit_delivery(3.0)
	assert_true(is_finite(after.economy.lifetime_earnings), "and lifetime survived it")

func test_a_nan_combo_is_replaced_rather_than_clamped() -> void:
	# clampf(NAN, 1, 10) returns NAN, so the clamp alone is not enough.
	var data := SaveCodec.encode(played_state())
	data["combo"] = NAN
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_true(is_finite(after.economy.combo), "finite")

func test_a_poisoned_cash_does_not_make_everything_free() -> void:
	var data := SaveCodec.encode(played_state())
	data["cash"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_true(is_finite(after.economy.cash), "finite")
	assert_false(after.economy.can_afford(1e308), "can_afford is not unconditionally true")

func test_a_negative_cash_clamps_to_zero() -> void:
	var data := SaveCodec.encode(played_state())
	data["cash"] = -1
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_eq(after.economy.cash, 0.0, "floored")

func test_a_capacity_of_a_billion_does_not_mint_blueprints() -> void:
	# 1e9 riders in one door cycle is ~$3.09e9, which is 5,559 BP -- 59x the
	# whole tree, permanently.
	var data := SaveCodec.encode(played_state())
	(data["cars"] as Array)[0]["capacity"] = 1000000000
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	assert_true(after.building.cars[0].capacity
		<= Upgrades.CAPACITY_BASE + 8, "bounded by its own max_level")

func test_every_per_car_field_is_bounded() -> void:
	var data := SaveCodec.encode(played_state())
	var car: Dictionary = (data["cars"] as Array)[0]
	car["floors_per_tick"] = 1e400
	car["door_ticks"] = -50
	car["spring_multiplier"] = 1e400
	car["position_floor"] = 1e400
	car["target_floor"] = 1e400
	var after := SaveCodec.decode(data)
	assert_not_null(after, "clamped, not refused")
	var c: ElevatorCar = after.building.cars[0]
	assert_true(is_finite(c.floors_per_tick) and c.floors_per_tick > 0.0, "speed")
	assert_true(c.door_ticks >= Upgrades.DOOR_TICKS_MIN, "doors")
	assert_true(c.spring_multiplier >= 1.0 and c.spring_multiplier <= Upgrades.SPRING_BASE,
		"spring")
	assert_true(c.position_floor >= 0.0
		and c.position_floor <= float(after.building.floor_count - 1), "position")
	assert_true(c.target_floor >= 0
		and c.target_floor <= after.building.floor_count - 1, "target")

func test_a_levels_value_that_is_a_container_refuses_rather_than_half_restoring() -> void:
	# restore_levels is a void callee: aborting mid-loop leaves decode running
	# and returns a NON-NULL, half-restored state, with which levels survive
	# depending on dictionary iteration order.
	var data := SaveCodec.encode(played_state())
	(data["levels"] as Dictionary)["speed"] = {}
	assert_null(SaveCodec.decode(data), "refused whole, never half-read")

func test_a_policy_element_that_is_not_a_preset_falls_back_to_manual() -> void:
	var data := SaveCodec.encode(played_state())
	(data["policies"] as Array)[0] = 9999
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_eq(after.auto.preset_of(0), DispatchPolicy.Preset.MANUAL, "fell back")

func test_a_non_boolean_vacant_does_not_throw() -> void:
	# bool() has NO Variant constructor for String, Dictionary or Array, so
	# {"vacant": "x"} aborts decode's own frame -- a safe null, but an engine
	# error, and GUT fails the sweep on it.
	var data := SaveCodec.encode(played_state())
	(data["floors"] as Array)[0]["vacant"] = "x"
	var after := SaveCodec.decode(data)
	assert_not_null(after, "not refused")
	assert_false(after.tenancy.is_vacant(0), "and reads as tenanted")

func test_a_generative_poison_sweep_never_throws() -> void:
	# Walk encode()'s output recursively and poison every leaf in turn. A
	# hand-written matrix goes stale the moment a key is added, and this spec
	# adds one; a top-level-only sweep goes stale the moment a value nests.
	#
	# Three assertion classes, because one oracle cannot express the policy:
	# structural type violations refuse, clamped numerics come back bounded,
	# and any malformation of `meta` comes back with an empty tree.
	var structural := ["version", "cars", "floors", "policies", "levels", "floor_count"]
	var poisons: Array = [{}, [], null, "abc", 1e400, -1, NAN]
	var checked := 0
	for path in _leaf_paths(SaveCodec.encode(played_state()), []):
		for poison in poisons:
			var data := SaveCodec.encode(played_state())
			_poke(data, path, poison)
			var after := SaveCodec.decode(data)
			checked += 1
			var top := str(path[0])
			if top == "meta":
				assert_not_null(after, "meta:%s poisoned with %s must not refuse"
					% [path, poison])
				if after != null:
					assert_eq(after.meta.blueprints, 0, "%s -> empty tree" % [path])
			elif structural.has(top) and path.size() == 1 \
					and typeof(poison) != TYPE_FLOAT and typeof(poison) != TYPE_INT:
				assert_null(after, "%s poisoned with %s must refuse" % [path, poison])
	assert_gt(checked, 100, "the sweep actually walked the payload")

## Every leaf path in a nested Dictionary/Array, as an array of keys/indices.
func _leaf_paths(value: Variant, prefix: Array) -> Array:
	var out := []
	match typeof(value):
		TYPE_DICTIONARY:
			for k in (value as Dictionary):
				out.append_array(_leaf_paths((value as Dictionary)[k], prefix + [k]))
		TYPE_ARRAY:
			for i in range((value as Array).size()):
				out.append_array(_leaf_paths((value as Array)[i], prefix + [i]))
		_:
			if not prefix.is_empty():
				out.append(prefix)
	return out

func _poke(container: Variant, path: Array, value: Variant) -> void:
	var node: Variant = container
	for i in range(path.size() - 1):
		node = node[path[i]]
	node[path[path.size() - 1]] = value
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_codec.gd -gexit
```

Expect failures **and** GUT-reported engine errors — the errors are the point.

- [ ] **Step 3: Implement the validation**

Add the helpers to `sim/save_codec.gd`:

```gdscript
## Every conversion whose argument comes from the save is type-guarded in a
## frame that can still refuse -- in decode, never in a void callee.
## restore_levels is exactly the counterexample: it does maxi(int(levels[id]), 0)
## with no type check, so a container value aborts it MID-LOOP and decode
## returns a non-null, half-restored state.
##
## The consequence of a violation is CLAMP, not refuse, for every row below.
## Refusing a save deletes a building: decode returns null, game_root starts
## fresh, and the autosave overwrites the only copy within ten seconds. This is
## a deliberate override of base design §8.6's reject-do-not-clamp rule, stated
## here rather than made silently.
static func _num(v: Variant, fallback: float) -> float:
	var t := typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return fallback
	var fv := float(v)
	return fv if is_finite(fv) else fallback

## clampf(NAN, 1, 10) returns NAN, so the finite check has to come first and
## cannot be folded into the clamp.
static func _bounded(v: Variant, lo: float, hi: float, fallback: float) -> float:
	return clampf(_num(v, fallback), lo, hi)

## Clamps in FLOAT space before the int() cast: int(roundf(INF)) saturates to
## 9223372036854775807 on arm64 and is platform-defined on WASM, which is
## exactly the hazard yield_for refuses to accept.
static func _bounded_int(v: Variant, lo: int, hi: int, fallback: int) -> int:
	return int(_bounded(v, float(lo), float(hi), float(fallback)))
```

Rewrite the assignments in `decode`:

```gdscript
	state.clock.ticks_executed = _bounded_int(data["ticks"], 0, 1 << 60, 0)
	state.economy.cash = _bounded(data["cash"], 0.0, 1e15, 0.0)
	state.economy.lifetime_earnings = _bounded(data.get("lifetime", 0.0), 0.0, 1e15, 0.0)
	state.economy.combo = _bounded(data.get("combo", 1.0), 1.0, Economy.COMBO_MAX, 1.0)
	state.economy.streak = _bounded_int(data.get("streak", 0), 0, 1 << 40, 0)
	state.economy.riders_served = _bounded_int(data.get("riders_served", 0), 0, 1 << 40, 0)

	# Type-guard the levels HERE, in a frame that can still refuse, because
	# restore_levels is void and aborting inside it half-restores.
	var levels: Dictionary = data.get("levels", {})
	for id in levels.keys():
		var t := typeof(levels[id])
		if t != TYPE_INT and t != TYPE_FLOAT:
			return null
	state.upgrades.restore_levels(levels)
```

and the per-car block, which restores four values unchecked today and poisons
`lifetime_earnings` by the same route as `combo`:

```gdscript
	var top_floor := float(state.building.floor_count - 1)
	var max_speed := Upgrades.SPEED_BASE * (1.0 + 0.25 * 12.0)
	var max_seats := Upgrades.CAPACITY_BASE + 8
	for i in range(mini(cars.size(), state.building.cars.size())):
		if typeof(cars[i]) != TYPE_DICTIONARY:
			return null
		var saved: Dictionary = cars[i]
		var car: ElevatorCar = state.building.cars[i]
		car.position_floor = _bounded(saved.get("position_floor", 0.0), 0.0, top_floor, 0.0)
		car.target_floor = _bounded_int(saved.get("target_floor", 0), 0,
			state.building.floor_count - 1, 0)
		# A billion seats delivers a billion riders in one door cycle, which is
		# 5,559 Blueprints -- 59x the whole tree, permanently.
		car.capacity = _bounded_int(saved.get("capacity", car.capacity), 1, max_seats,
			car.capacity)
		car.floors_per_tick = _bounded(saved.get("floors_per_tick", car.floors_per_tick),
			0.0001, max_speed, car.floors_per_tick)
		car.door_ticks = _bounded_int(saved.get("door_ticks", car.door_ticks),
			Upgrades.DOOR_TICKS_MIN, Upgrades.DOOR_TICKS_BASE, car.door_ticks)
		# The only legitimate non-1.0 value; leaving one field of four unbounded
		# invites treating the whole table as advisory.
		car.spring_multiplier = _bounded(saved.get("spring_multiplier", 1.0), 1.0,
			Upgrades.SPRING_BASE, 1.0)
```

the per-floor block:

```gdscript
	for floor_index in range(mini(saved_floors.size(), state.building.floor_count)):
		if typeof(saved_floors[floor_index]) != TYPE_DICTIONARY:
			return null
		var r: Dictionary = saved_floors[floor_index]
		if version >= 2 and not (r.has("kind") and r.has("class")):
			return null
		# bool() has no Variant constructor for String, Dictionary or Array, so
		# a bare bool(r.get("vacant")) aborts decode's own frame on {"vacant": "x"}.
		var raw_vacant: Variant = r.get("vacant", false)
		var vacant := raw_vacant if typeof(raw_vacant) == TYPE_BOOL \
			else (typeof(raw_vacant) in [TYPE_INT, TYPE_FLOAT] and _num(raw_vacant, 0.0) != 0.0)
		state.tenancy.restore_floor(floor_index,
			_bounded(r.get("satisfaction", 1.0), 0.0, 1.0, 1.0), vacant,
			_bounded_int(r.get("move_out_left", 0), 0, Tenancy.MOVE_OUT_TICKS, 0))
		state.fitout.set_tier(floor_index,
			_bounded_int(r.get("class", 1), Fitout.BASE_TIER, state.catalog.max_tier(),
				Fitout.BASE_TIER))
		state.tenancy.set_kind(floor_index,
			_restore_kind(state, floor_index, version, r, vacant))
```

and the policies:

```gdscript
	var policies: Array = data.get("policies", [])
	for shaft in range(mini(policies.size(), state.building.cars.size())):
		# Per-element NUMERIC, not dictionary: the elements are integers, and a
		# per-element TYPE_DICTIONARY check here silently drops every saved
		# dispatch policy.
		var preset := _bounded_int(policies[shaft], 0, 1 << 20,
			DispatchPolicy.Preset.MANUAL)
		if not DispatchPolicy.PRESET_ORDER.has(preset):
			preset = DispatchPolicy.Preset.MANUAL
		state.set_policy(shaft, preset)
```

Finally, bound the seed at `:124` (it feeds `RandomNumberGenerator.seed`):

```gdscript
	var state := GameState.new(floors, maxi(cars.size(), 1),
		_bounded_int(data["seed"], 0, 1 << 60, 0), catalog_path, meta, blueprints_path)
```

(`DispatchPolicy.PRESET_ORDER` is an `Array` of the five `Preset` values,
`sim/dispatch_policy.gd:141`. `state.set_policy` already refuses a preset whose
hardware is not installed, so this fallback bounds the *value* rather than
replacing that check.)

- [ ] **Step 4: Run the file, then the suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_codec.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: green, with **no** engine errors reported by GUT. If the generative
sweep reports a throw, that is a real defect in the guard, not a noisy test.

- [ ] **Step 5: Commit**

```bash
git add sim/save_codec.gd tests/test_save_codec.gd
git commit -F - <<'EOF'
Bound every save-derived value, because one of them multiplies the prestige input

Checking `lifetime` does not close the hole. `combo` is restored unchecked
beside it, and credit_delivery does `paid = fare * combo; lifetime_earnings +=
paid` and then heals the combo to 10.0 on the very next line -- so
`"combo": 1e400` (valid JSON, parses to INF) poisons lifetime on the first
delivery, AFTER any decode-time check on lifetime has run, and erases its own
evidence. yield_for(INF) is a billion Blueprints from one passenger. A saved
`capacity` of 1e9 gets there by a different road.

Violations CLAMP rather than refuse. That is a deliberate override of the base
design's reject-do-not-clamp rule: SaveStore has no backup-before-refuse and
game_root has no writes_disabled latch, so a rejection deletes a building.

The type checks stay in decode rather than in the void callees they guard --
restore_levels aborting mid-loop returns a non-null, half-restored state, which
is the real violation of "never half-read into a state that looks fine".
EOF
```

---

## Task 12: Salvage the Meta when the *run* is refused

**Why:** spec §9. `decode` keeps four other refusal paths, and under v4 every one
of them destroys the tech tree along with the run. The defence of the demolish
write — "every other write can be re-earned by playing on" — stops being true the
moment the save carries permanent progress.

**Files:**
- Modify: `sim/save_codec.gd`, `game/save_store.gd`, `game/game_root.gd:67-78`
- Test: `tests/test_save_codec.gd`, `tests/test_save_store.gd`

**Interfaces:**
- Produces:
  - `static func SaveCodec.salvage_meta(p_data: Dictionary, blueprints_path := "res://data/blueprints.json") -> Meta`
  - `SaveStore.load_all` returns a real Meta (defs-loaded even with no save file; `null` only on a defs failure)
  - `static func SaveStore.load_meta(blueprints_path := …) -> Meta`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_save_codec.gd`:

```gdscript
func test_the_meta_survives_a_refused_run() -> void:
	# decode still returns NULL here -- five existing assert_null tests depend
	# on that contract, and both docstrings say "null always means start a new
	# game". Salvage is a separate, explicitly named function.
	var s := meta_state()
	var data := SaveCodec.encode(s)
	(data["floors"] as Array).clear()          # the short-floors refusal
	assert_null(SaveCodec.decode(data), "the run is refused")
	var salvaged := SaveCodec.salvage_meta(data)
	assert_not_null(salvaged, "the tree is not")
	assert_eq(salvaged.blueprints, 7, "blueprints")
	assert_eq(salvaged.level_of("height"), 1, "spent")

func test_salvage_never_grants() -> void:
	# legacy_meta derives free height levels from a floor_count the refusal has
	# just declared untrustworthy: a hand-written 20-floor v3 save with an
	# empty floors array would otherwise mint the entire cap ladder.
	var salvaged := SaveCodec.salvage_meta(
		{"version": 3, "floor_count": 20, "floors": []})
	assert_not_null(salvaged, "salvages")
	assert_eq(salvaged.level_of("height"), 0, "an EMPTY meta, not two free levels")

func test_salvage_reads_the_unmigrated_dictionary_without_throwing() -> void:
	# It must not migrate: _migrate_to_v3's first statement is
	# int(data.get("version", -1)), the exact abort the preflight guards decode
	# against -- and salvage runs under a separate call the preflight never
	# covers. Migration touches only V3_KEYS, V3_CAR_KEYS and `levels`, never
	# the "meta" key, so there is nothing to gain by it.
	var salvaged := SaveCodec.salvage_meta({"version": {}, "cars": null,
		"meta": {"blueprints": 5}})
	assert_not_null(salvaged, "no throw, no null")
	assert_eq(salvaged.blueprints, 5, "and the meta was still read")

func test_salvage_returns_null_when_the_shipped_catalog_is_broken() -> void:
	assert_null(SaveCodec.salvage_meta({}, "res://data/does_not_exist.json"), "fatal")
```

Append to `tests/test_save_store.gd`:

```gdscript
func test_the_run_and_the_meta_come_from_the_same_file() -> void:
	# Two independent source selections would let them come from DIFFERENT
	# files, and the autosave commits that mixture ten seconds later as one
	# valid payload.
	var m := Meta.new()
	m.load_defs("res://data/blueprints.json")
	m.blueprints = 11
	var s := GameState.new(6, 1, 1, "res://data/tenants.json", m)
	var data := SaveCodec.encode(s)
	(data["floors"] as Array).clear()          # PATH parses, decode refuses it
	write_raw(SaveStore.PATH, JSON.stringify(data))

	var other := Meta.new()
	other.load_defs("res://data/blueprints.json")
	other.blueprints = 99
	write_raw(SaveStore.BACKUP_PATH,
		JSON.stringify(SaveCodec.encode(
			GameState.new(6, 1, 1, "res://data/tenants.json", other))))

	var loaded := SaveStore.load_all()
	assert_null(loaded["state"], "the run is refused")
	assert_eq((loaded["meta"] as Meta).blueprints, 11,
		"and the meta came from PATH, not from the backup")

func test_no_save_file_still_yields_a_usable_empty_meta() -> void:
	var loaded := SaveStore.load_all()
	assert_null(loaded["state"], "nothing to load")
	assert_not_null(loaded["meta"], "but a defs-loaded Meta, not a bare Meta.new()")
	assert_true((loaded["meta"] as Meta).is_usable(), "usable")

func test_a_broken_blueprint_catalog_makes_the_meta_null() -> void:
	var loaded := SaveStore.load_all("res://data/tenants.json",
		"res://data/does_not_exist.json")
	assert_null(loaded["meta"], "so the boot path can show a named error screen")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_codec.gd -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_save_store.gd -gexit
```

- [ ] **Step 3: Implement `salvage_meta`**

Append to `sim/save_codec.gd`:

```gdscript
## The tech tree is designed to outlive a discarded building, so a run we refuse
## must not take it down. decode keeps four other refusal paths -- the
## unsupported-version guard, _is_usable's missing-key check, the v2+ short
## floors rule (:156) and the missing kind/class rule (:161) -- and under v4
## every one of them would otherwise destroy permanent progress.
##
## decode's own contract is UNCHANGED: it still returns null on refusal, which
## five existing tests and two docstrings depend on. This is a separate,
## explicitly named function.
##
## Three rules, all load-bearing:
##
## 1. It NEVER calls _legacy_meta(). That derives free height levels from a
##    floor_count the refusal has just declared untrustworthy -- a hand-written
##    {"version": 3, "floor_count": 20, "floors": []} would mint the whole cap
##    ladder from a save that does not load.
## 2. It reads the UNMIGRATED dictionary, using data.get exclusively.
##    _migrate_to_v3's first statement is int(data.get("version", -1)), the
##    exact abort the preflight guards decode against -- and salvage runs under
##    a separate call the preflight never covers. Migration touches only
##    V3_KEYS, V3_CAR_KEYS and `levels`, and never the "meta" key.
## 3. It deliberately bypasses the version guard for the meta block, so a save
##    written by a future v5 has its `spent` reinterpreted under v4 semantics.
##    Meta.restore()'s clamps bound the damage. Written down because the version
##    guard is otherwise the only thing making "we do not read formats we do not
##    understand" true.
static func salvage_meta(p_data: Dictionary,
		blueprints_path := "res://data/blueprints.json") -> Meta:
	var m := Meta.new()
	if not m.load_defs(blueprints_path):
		return null
	m.restore(p_data.get("meta"))
	return m
```

Complete `SaveStore.load_all`:

```gdscript
static func load_all(catalog_path := "res://data/tenants.json",
		blueprints_path := "res://data/blueprints.json") -> Dictionary:
	var parsed: Variant = _select()
	if typeof(parsed) != TYPE_DICTIONARY:
		# No save file is still a defs-loaded Meta, never a bare Meta.new():
		# GameState checks is_usable() unconditionally, so a bare one would
		# make a brand-new game invalid.
		return {"state": null, "meta": SaveCodec.salvage_meta({}, blueprints_path)}
	var data := parsed as Dictionary
	return {
		"state": SaveCodec.decode(data, catalog_path, blueprints_path),
		"meta": SaveCodec.salvage_meta(data, blueprints_path),
	}

static func load_meta(blueprints_path := "res://data/blueprints.json") -> Meta:
	return load_all("res://data/tenants.json", blueprints_path)["meta"]
```

- [ ] **Step 4: Rewire `game_root`'s cold boot**

Replace `game/game_root.gd:66-78`:

```gdscript
	else:
		# ONE source selection, so the run and the Meta can never come from
		# different files -- the autosave would commit that mixture ten seconds
		# later as one valid payload.
		var loaded := SaveStore.load_all(catalog_path, blueprints_path)
		state = loaded["state"]
		if state == null:
			var salvaged: Meta = loaded["meta"]
			if salvaged == null:
				# A bare `return` here would skip the guard below just as
				# surely as an abort would: that branch sits BELOW this code
				# inside _ready, so this draws the screen itself.
				_show_error_screen("blueprint catalog", blueprints_path)
				_saving_enabled = false
				set_physics_process(false)
				return
			# The Meta's starting size is applied by the callers that BEGIN a
			# run, and this is one of them: a salvaged `shafts` L3 could never
			# have been applied by a branch that constructed with START_SHAFTS.
			state = GameState.new(GameState.BASE_FLOORS, salvaged.starting_shafts(),
				GameState.BASE_SEED + salvaged.runs_completed,
				catalog_path, salvaged, blueprints_path)
```

- [ ] **Step 5: Run the suite and commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add sim/save_codec.gd game/save_store.gd game/game_root.gd tests/test_save_codec.gd tests/test_save_store.gd
git commit -F - <<'EOF'
Let a refused run take the building down without taking the tech tree with it

decode keeps four refusal paths besides the meta block, and under v4 every one
of them destroys permanent progress. The defence of the demolish write --
"every other write can be re-earned by playing on" -- stopped being true the
moment the save carried Blueprints.

decode's contract is untouched: it still returns null, which five existing
assert_null tests and two docstrings depend on. Salvage is a separate,
explicitly named function that reads the UNMIGRATED dictionary, because
migration's first statement is the very int({}) abort the preflight exists to
prevent and salvage runs under a call the preflight never covers.

Salvage never grandfathers. legacy_meta derives free height levels from a
floor_count the refusal just declared untrustworthy, so a hand-written
20-floor save with an empty floors array would mint the entire cap ladder from
a file that does not load.
EOF
```

---

## Task 13: `ui/prestige_panel.gd`

**Why:** spec §10. The tree needs ~708 units idle and ~796 armed against
`FloorPanel`'s `0.46 × 1280 = 589` sheet, and `VBoxContainer` honours
`custom_minimum_size` — so the overflow would draw *outside* the sheet, over the
board. Its shape is `ManagementView`'s, not `FloorPanel`'s.

**Files:**
- Create: `ui/prestige_panel.gd`
- Test: `tests/test_board_input.gd` (Task 16 drives it through the scene)

**Interfaces:**
- Produces:
  - `class_name PrestigePanel extends Control`
  - `signal node_purchase_requested(id: String)`
  - `signal demolish_requested()`
  - `func bind(state: GameState) -> void`
  - `func open(state: GameState) -> void`, `func close() -> void`
  - `func refresh() -> void`
  - `func is_armed() -> bool` — the test seam for the Confirm/Cancel row

- [ ] **Step 1: Write the panel**

```gdscript
class_name PrestigePanel
extends Control

## The tech tree, the yield projection, and the one irreversible action in the
## game.
##
## Its shape is ManagementView's, not FloorPanel's: a full-height overlay
## wrapping a ScrollContainer, because the tree needs ~708 units idle and ~796
## armed against FloorPanel's 0.46 x 1280 = 589 sheet, and VBoxContainer honours
## custom_minimum_size -- so the overflow would draw OUTSIDE the sheet, over the
## board. 88 is not negotiable downward either: it is 48pt at the 0.546 board
## scale, and FloorPanel's own 72 is already below the touch floor.
##
## The panel EMITS, it does not mutate. A node purchase changes PERSISTENT
## state and must be written immediately, so it follows FloorPanel.lease_requested
## rather than ManagementView's direct _state.buy().
##
## Every dynamic string goes through Label, never BBCode -- same origin argument
## as ManagementView's header.

signal node_purchase_requested(id: String)
signal demolish_requested()

const BUTTON_HEIGHT := 88.0        # 48pt at the 0.546 iPhone scale

var _state: GameState
var _armed: bool = false

var _scrim: ColorRect
var _box: VBoxContainer
var _yield_label: Label
var _apply_note: Label
var _rows: Dictionary = {}          # node id -> Button
var _rebuild_button: Button
var _confirm_button: Button
var _cancel_button: Button

func bind(state: GameState) -> void:
	_state = state
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_scrim = ColorRect.new()
	_scrim.color = Color("05080c", 0.62)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed:
			close())

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)

	# The projection IS the confirmation, per the base design: the number being
	# decided on is on screen before the button is reachable. With a $1,000 gate
	# this line does real work for the first hour of a new game.
	_yield_label = Label.new()
	_yield_label.add_theme_font_size_override("font_size", 18)
	_yield_label.custom_minimum_size = Vector2(0, 24)
	_box.add_child(_yield_label)

	_box.add_child(_heading("STRUCTURE"))
	for id in _state.meta.ids():
		if _state.meta.branch_of(id) == "structure":
			_box.add_child(_node_row(id))
	_box.add_child(_heading("MECHANICAL"))
	for id in _state.meta.ids():
		if _state.meta.branch_of(id) == "mechanical":
			_box.add_child(_node_row(id))

	# Grants apply at construction and restore_levels overwrites, so a
	# Mechanical node bought mid-run does nothing until the next rebuild. An
	# unexplained no-op reads as a bug.
	_apply_note = Label.new()
	_apply_note.text = "Mechanical nodes apply from the next rebuild."
	_apply_note.add_theme_font_size_override("font_size", 13)
	_apply_note.add_theme_color_override("font_color", Color("7c8899"))
	_box.add_child(_apply_note)

	# A Confirm/Cancel PAIR, never a second tap on an armed button. The UI spec
	# establishes the project's one confirmation shape as a distinct labelled
	# control carrying the price; an armed button has no disarm path and stays
	# armed while the sim runs; and touch emulation delivers one physical tap
	# TWICE, which is why test_one_thumb_tap_buys_exactly_one_floor exists.
	_rebuild_button = _action("REBUILD", func() -> void:
		_armed = true
		refresh())
	_confirm_button = _action("", func() -> void:
		_armed = false
		demolish_requested.emit())
	_cancel_button = _action("Cancel", func() -> void:
		_armed = false
		refresh())
	refresh()

func open(state: GameState) -> void:
	_state = state
	_armed = false
	visible = true
	refresh()

func close() -> void:
	_armed = false
	visible = false

func is_armed() -> bool:
	return _armed

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("5b6675"))
	l.custom_minimum_size = Vector2(0, 28)
	return l

func _action(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	_box.add_child(b)
	return b

func _node_row(id: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	var captured := id
	b.pressed.connect(func() -> void: node_purchase_requested.emit(captured))
	_rows[id] = b
	return b

## Annotations read the Meta's derivations rather than copying their formulas,
## so an annotation can never fabricate a cap.
func refresh() -> void:
	if _state == null:
		return
	var meta := _state.meta
	var earned := _state.economy.lifetime_earnings
	var bp := Prestige.yield_for(earned)
	if bp >= 1:
		_yield_label.text = "This building is worth %d Blueprint%s" % [
			bp, "" if bp == 1 else "s"]
	else:
		var needed := Prestige.DEMOLITION_FLOOR + Prestige.EARNINGS_PER_BLUEPRINT - earned
		_yield_label.text = "$%s more to earn your first Blueprint" % \
			NumberFormat.compact(maxf(needed, 0.0))

	for id in _rows.keys():
		var b: Button = _rows[id]
		var lvl := meta.level_of(id)
		if meta.is_maxed(id):
			b.text = "%s  MAX (Lv%d)\n%s" % [meta.name_of(id), lvl, meta.note_of(id)]
			b.disabled = true
			continue
		if meta.is_zero_delta(id, _state.upgrades):
			b.text = "%s  Lv%d\n%s (max effect)" % [meta.name_of(id), lvl, meta.note_of(id)]
			b.disabled = true
			continue
		b.text = "%s  Lv%d      %d BP\n%s" % [
			meta.name_of(id), lvl, meta.cost_of(id), meta.note_of(id)]
		b.disabled = not meta.can_buy(id, _state.upgrades)

	_rebuild_button.visible = not _armed
	_rebuild_button.disabled = bp < 1
	_confirm_button.visible = _armed
	_confirm_button.text = "Rebuild for %d Blueprint%s" % [bp, "" if bp == 1 else "s"]
	_cancel_button.visible = _armed
```

- [ ] **Step 2: Wire it into the scene**

The panel has to exist as `root._prestige` before Task 15's ghost-band test can
assert it opened. In `game/game_root.gd`, add the field:

```gdscript
var _prestige: PrestigePanel
```

construct it in `_ready` immediately after `panel` (`:124-129`):

```gdscript
	_prestige = PrestigePanel.new()
	_prestige.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_prestige)
	_prestige.bind(state)
	_prestige.node_purchase_requested.connect(_on_node_purchase)
```

and add the two handlers:

```gdscript
func _on_prestige_requested() -> void:
	_prestige.open(state)

## A node purchase mutates PERSISTENT state, so it is written immediately
## rather than waiting for the ten-second autosave. It follows
## FloorPanel.lease_requested rather than ManagementView's direct _state.buy().
func _on_node_purchase(id: String) -> void:
	if state.meta.buy(id, state.upgrades):
		save_now()
		_prestige.refresh()
```

**`demolish_requested` is deliberately left unconnected until Task 16**, where
`_on_demolish` and `_rebuild_views()` land together. The Confirm button is inert
for three tasks, and Task 16's first test is what makes it live — connecting it
to a stub here would be a half-implementation nothing tests.

- [ ] **Step 3: Import and check it compiles**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: green, with no parse errors reported for the new file. The panel has
no behavioural test yet — Task 16 drives it through the real scene, which is
where the confirmation argument's one load-bearing assertion lives.

- [ ] **Step 4: Commit**

```bash
git add ui/prestige_panel.gd ui/prestige_panel.gd.uid game/game_root.gd
git commit -F - <<'EOF'
Add the prestige panel, shaped like ManagementView rather than FloorPanel

The tree needs ~708 units idle and ~796 armed against FloorPanel's 589-unit
sheet, and VBoxContainer honours custom_minimum_size -- so the overflow would
draw outside the sheet and over the board. 88-unit rows are not negotiable
downward: that is 48pt at the board scale, and FloorPanel's own 72 is already
below the touch floor.

The confirmation is a Confirm/Cancel pair, not a second tap on an armed
button. Touch emulation delivers one physical tap twice, which is why
test_one_thumb_tap_buys_exactly_one_floor exists; arming on tap 1 and
committing on tap 2 would let a stray double-tap destroy a run, in a game whose
stated invariant is that it has no fail state.
EOF
```

---

## Task 14: `ManagementView` gains a Blueprints readout and a way in

**Why:** spec §10. Four captions plus separations come to ~253 of ~720 units, so
the fourth `_stat` fits. The upgrade list needs no change — it is generated from
`upgrades.ids()` and already skips `shaft` and `floor`.

**Files:**
- Modify: `ui/management_view.gd`
- Test: `tests/test_board_input.gd`

**Interfaces:**
- Produces: `signal ManagementView.prestige_requested()`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_board_input.gd`:

```gdscript
func test_management_shows_the_blueprint_balance() -> void:
	root.state.meta.blueprints = 7
	root._management.refresh()
	assert_eq(root._management._blueprints.text, "7", "the balance is on screen")
```

- [ ] **Step 2: Run and watch it fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_input.gd -gunit_test_name=test_management_shows_the_blueprint_balance -gexit
```

- [ ] **Step 3: Implement**

In `ui/management_view.gd`, add the signal and the field:

```gdscript
signal prestige_requested()

var _blueprints: Label
```

extend `_build_readout()`:

```gdscript
	_riders = _stat(floor_index, "riders / min")
	_wait = _stat(floor_index, "avg wait")
	_gaveup = _stat(floor_index, "gave up")
	_blueprints = _stat(floor_index, "blueprints")
	return panel
```

add the heading and button at the bottom of `bind()`, after the dispatch box:

```gdscript
	box.add_child(_heading("REBUILD"))
	var rebuild := Button.new()
	rebuild.text = "Demolish and start again"
	rebuild.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	rebuild.add_theme_font_size_override("font_size", 18)
	rebuild.pressed.connect(func() -> void: prestige_requested.emit())
	box.add_child(rebuild)
	refresh()
```

and one line in `refresh()`:

```gdscript
	_gaveup.text = Metrics.format_rate(m.expiries())
	_blueprints.text = str(_state.meta.blueprints)
```

Then connect it in `game/game_root.gd`, beside `_management.bind(state)`:

```gdscript
	_management.prestige_requested.connect(_on_prestige_requested)
```

- [ ] **Step 4: Run and commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add ui/management_view.gd tests/test_board_input.gd
git commit -m "Put the Blueprint balance and the way into the tree in Management

Four captions plus separations come to ~253 of ~720 units, so the fourth
_stat fits without moving anything. The upgrade list needs no change -- it is
generated from upgrades.ids() and already skips shaft and floor."
```

---

## Task 15: The ghost band at the cap

**Why:** spec §10. The band is gated on the **structural** cap
(`building_view.gd:97`), so at the purchasable cap it still renders
`+ BUILD FLOOR $759.50`, coloured **green** the moment the player can afford it,
and a tap silently does nothing. It does not merely persist — it invites the tap.
That is reachable today only after 6.5 hours; with a 10-floor first run every new
player reaches it in about 1.5.

**Files:**
- Modify: `view/building_view.gd:348-352`, `:196-207`
- Test: `tests/test_board_input.gd`

**Interfaces:**
- Produces: `signal BuildingView.prestige_requested()`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_board_input.gd`:

```gdscript
func test_at_the_cap_the_ghost_band_says_so_and_opens_the_panel() -> void:
	# A weaker version -- "a tap neither buys a floor nor errors" -- is
	# vacuously true today with no code at all, and would pass with the whole
	# change deleted.
	await build_to(10)
	assert_eq(root.state.building.floor_count, 10, "at the cap")
	view.refresh()
	assert_string_contains(view._ghost_label.text, "REBUILD",
		"the band names what to do instead")
	var before := root.state.building.floor_count
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before, "no floor was bought")
	assert_true(root._prestige.visible, "and the panel opened")

func test_below_the_cap_the_ghost_band_still_buys_a_floor() -> void:
	root.state.economy.cash = 1_000_000.0
	var before := root.state.building.floor_count
	await do_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1, "still the primary verb")
	assert_false(root._prestige.visible, "and no panel")
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_input.gd -gexit
```

- [ ] **Step 3: Implement**

In `view/building_view.gd`, add the signal beside `floor_purchase_requested`:

```gdscript
signal prestige_requested()
```

**Line 97 does not change.** It decides whether the band is *constructed*, and
the band must stay: `_on_ghost_input` is also the PAN handler, so deleting the
band at the cap would kill that 88-unit pan strip on precisely the tallest
buildings. Only the label and the tap's destination change.

In `refresh()` (`:348-352`):

```gdscript
	if _ghost_label != null:
		if _state.upgrades.is_maxed("floor"):
			# 21 characters ends near x = 227, just inside FloorRow.STRIP_RIGHT
			# (240) at font size 15 from LABEL_X = 38. A 37-character string
			# would overrun into the shaft slot's own label.
			_ghost_label.text = "CAP REACHED — REBUILD"
			_ghost_label.add_theme_color_override("font_color", Color("f0b429"))
		else:
			var floor_cost := _state.upgrades.cost_of("floor")
			_ghost_label.text = "+ BUILD FLOOR  $%s" % NumberFormat.compact(floor_cost)
			_ghost_label.add_theme_color_override("font_color",
				Color("4ade80") if _state.economy.can_afford(floor_cost) else Color("4a5563"))
```

and in `_on_ghost_input` (`:205-207`):

```gdscript
	elif PointerEvents.is_release(event):
		if _ghost_gesture.release() == Gesture.Result.TAP:
			# Giving the tap a destination removes the silent no-op rather than
			# merely labelling it: Upgrades.purchase refuses at is_maxed and
			# game_root discards the result, so at the cap this band invited a
			# tap that did nothing.
			if _state.upgrades.is_maxed("floor"):
				prestige_requested.emit()
			else:
				floor_purchase_requested.emit()
```

- [ ] **Step 4: Wire the signal in `game_root`**

Beside the existing ghost connections at `:112-114`. `_on_prestige_requested`
already exists from Task 13:

```gdscript
	_view.prestige_requested.connect(_on_prestige_requested)
```

- [ ] **Step 5: Run and commit**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add view/building_view.gd game/game_root.gd tests/test_board_input.gd
git commit -F - <<'EOF'
Give the ghost band something to say, and somewhere to go, at the cap

The band is gated on the STRUCTURAL cap, so at the purchasable one it kept
rendering "+ BUILD FLOOR $759.50" -- green the moment the player could afford
it -- and the tap silently did nothing. It did not merely persist; it invited
the tap. That was a 6.5-hour problem before this release and is a 1.5-hour one
after it.

Line 97 does not move. It decides whether the band is CONSTRUCTED, and
_on_ghost_input is also the pan handler, so deleting the band at the cap would
kill the 88-unit pan strip on precisely the tallest buildings.
EOF
```

---

## Task 16: `game_root` swaps the state, and the scene tests that prove it

**Why:** spec §11. `BuildingView.bind()`, `ManagementView.bind()` and
`FloorPanel.bind()` all `add_child` unconditionally — **they are constructors
wearing an accessor's name**, and calling any of them a second time stacks a
whole UI on top of the old one.

**Files:**
- Modify: `game/game_root.gd`
- Test: `tests/test_board_input.gd`

**Interfaces:**
- Produces:
  - `var game_root._prestige: PrestigePanel`
  - `func game_root.save_now(s: GameState = null) -> bool`
  - `func game_root._rebuild_views() -> void`
  - `func game_root._on_demolish() -> void`
  - `func game_root._show_save_failed() -> void`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_board_input.gd`:

```gdscript
## test_board_input.gd:49 caches `view = root._view` in before_each, so any test
## crossing _rebuild_views() must re-read it or assert against a freed node.
func demolish_now() -> void:
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._confirm_button.pressed.emit()
	await wait_physics_frames(2)
	view = root._view

func test_a_tap_on_rebuild_alone_changes_nothing() -> void:
	# The single assertion the whole Confirm/Cancel argument exists to buy.
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	root._prestige.open(root.state)
	var floors := root.state.building.floor_count
	var bp := root.state.meta.blueprints
	await thumb_tap_button(root._prestige._rebuild_button)
	assert_eq(root.state.building.floor_count, floors, "the building is still there")
	assert_eq(root.state.meta.blueprints, bp, "and nothing was credited")
	assert_true(root._prestige.is_armed(), "the confirm row is showing")
	assert_true(root._prestige._confirm_button.visible, "with a labelled control")

func test_a_demolish_replaces_the_run() -> void:
	await build_to(9)
	var before := root.state
	await demolish_now()
	assert_ne(root.state, before, "a new state entirely")
	assert_eq(root.state.building.floor_count, GameState.BASE_FLOORS, "a fresh building")
	assert_eq(root.state.meta.blueprints, 4, "credited")

func test_a_demolish_leaves_exactly_one_of_each_view() -> void:
	# bind() add_childs unconditionally, so calling it twice stacks a whole UI.
	await demolish_now()
	var boards := 0
	var managements := 0
	for child in root.get_children():
		if child is BuildingView:
			boards += 1
		if child is ManagementView:
			managements += 1
	assert_eq(boards, 1, "one board")
	assert_eq(managements, 1, "one management view")

func test_a_tap_in_the_ghost_band_after_a_demolish_buys_exactly_one_floor() -> void:
	# A duplicated BuildingView buys two -- the same class of bug
	# test_one_thumb_tap_buys_exactly_one_floor already guards.
	await demolish_now()
	root.state.economy.cash = 1_000_000.0
	var before := root.state.building.floor_count
	await thumb_tap(400.0, ghost_centre_y())
	assert_eq(root.state.building.floor_count, before + 1, "exactly one")

func test_the_board_is_showing_after_a_demolish() -> void:
	await demolish_now()
	assert_true(root._view.visible, "the board")
	assert_false(root._management.visible, "not management")
	assert_eq(root._view_button.text, "MANAGE",
		"the button lives outside the rebuilt range and is reset by hand")

func test_the_pager_and_view_button_are_not_duplicated_by_a_demolish() -> void:
	await demolish_now()
	var buttons := 0
	for child in root.get_children():
		if child is Button:
			buttons += 1
	assert_eq(buttons, 3, "two pager buttons and one view button, as _ready built them")

func test_a_demolish_that_cannot_be_saved_changes_nothing() -> void:
	# The failure is INDUCED, not stubbed: SaveStore.save is static and
	# game_root calls it by class name, so a GUT double is a different script
	# and cannot intercept that call site. A DIRECTORY at user://save.json makes
	# the commit-point rename fail through save()'s own code path.
	var dir := DirAccess.open("user://")
	SaveStore.clear()
	dir.make_dir(SaveStore.PATH)
	root.state.economy.accrue(Prestige.DEMOLITION_FLOOR + 1600.0)
	var before := root.state
	root._prestige.open(root.state)
	root._prestige._rebuild_button.pressed.emit()
	root._prestige._confirm_button.pressed.emit()
	await wait_physics_frames(2)
	assert_eq(root.state, before, "the old run is still authoritative")
	assert_eq(root.state.meta.blueprints, 0, "and nothing was credited")
	var payload := SaveCodec.encode(root.state)
	assert_eq((payload["meta"] as Dictionary)["blueprints"], 0,
		"an autosave would carry the uncredited balance")
	# The fixture LEAKS: clear() tests file_exists(PATH), which is false for a
	# directory, so it would survive before_each and become the fixture for
	# every later test in this file.
	dir.remove(SaveStore.PATH)
	assert_false(dir.dir_exists(SaveStore.PATH), "cleaned up")
```

Add the two tap helpers if `thumb_tap_button` does not already exist:

```gdscript
func thumb_tap_button(b: Button) -> void:
	b.pressed.emit()
	await wait_physics_frames(1)
```

- [ ] **Step 2: Run and watch them fail**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_board_input.gd -gexit
```

- [ ] **Step 3: Implement**

In `game/game_root.gd`, extract the four view constructions out of `_ready` into
`_rebuild_views()` and call it from `_ready` in their place. `_prestige` and its
two handlers already exist from Task 13; this moves them and adds the
`demolish_requested` connection:

```gdscript
## Rebuilds exactly the four views that hold a GameState. It must NOT include
## the pager buttons or _view_button, which also add_child unconditionally and
## would duplicate on every rebuild -- the very trap this function is about.
func _rebuild_views() -> void:
	for old in [_view, _management, panel, _prestige]:
		if old == null:
			continue
		# queue_free() is deferred to end of frame, so without this the freed
		# views remain children while the new ones are added and input in that
		# window reaches BOTH trees.
		old.hide()
		remove_child(old)
		old.queue_free()

	_view = BuildingView.new()
	_view.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_view.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	add_child(_view)
	_view.bind(state)
	_view.floor_purchase_requested.connect(func() -> void: state.buy("floor"))
	_view.shaft_purchase_requested.connect(_on_buy_shaft)
	_view.hall_floor_selected.connect(_on_hall_floor_selected)
	_view.prestige_requested.connect(_on_prestige_requested)

	_management = ManagementView.new()
	_management.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_management.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	_management.visible = false
	add_child(_management)
	_management.bind(state)
	_management.prestige_requested.connect(_on_prestige_requested)

	panel = FloorPanel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.bind(state)
	panel.lease_requested.connect(_on_lease_requested)
	panel.upgrade_requested.connect(_on_upgrade_requested)

	_prestige = PrestigePanel.new()
	_prestige.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_prestige)
	_prestige.bind(state)
	_prestige.node_purchase_requested.connect(_on_node_purchase)
	_prestige.demolish_requested.connect(_on_demolish)

	# Sibling order decides input. _ready builds the views BEFORE the pager and
	# _view_button, so those are later siblings and win against the panels'
	# full-rect MOUSE_FILTER_STOP scrims. A remove_child + add_child rebuild
	# appends the views LAST, which would put the scrims above MANAGE for the
	# rest of the session.
	if _view_button != null:
		move_child(_view_button, get_child_count() - 1)
		move_child(_prev_shaft, get_child_count() - 1)
		move_child(_next_shaft, get_child_count() - 1)
		move_child(_pager_label, get_child_count() - 1)
```

> **The `move_child` fix is a HYPOTHESIS** (spec §11). Its premise — the child
> order in `_ready` — was confirmed by reading; the input-routing consequence
> was not run. `test_a_tap_in_the_ghost_band_after_a_demolish_buys_exactly_one_floor`
> exercises it. If it passes with the `move_child` block deleted, say so and
> correct the spec rather than keeping code no test justifies.

Add the remaining handlers:

```gdscript
func _on_demolish() -> void:
	var next := Prestige.demolish(state)
	if next == null:
		return                       # the gate refused; NOTHING has changed
	# The WRITE COMES FIRST, and its result is checked. Swapping state and then
	# saving would show the player the new run while the durable file still
	# held the old, still-demolish-eligible one -- reload and the same earnings
	# pay a second time. Fixing SaveStore's atomicity does not fix this; it is
	# an ordering bug, not a file-replacement bug.
	if not save_now(next):
		_show_save_failed()          # old run and Meta still intact, on disk and in memory
		return
	state = next
	last_selected_floor = -1         # a stale index into a building that just shrank
	_rebuild_views()
	_view_button.text = "MANAGE"     # it lives outside the rebuilt range
	_last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
	_refresh_pager()                 # early-returns on _management.visible, so it runs last

## Permits retry rather than latching: the staged-Meta design makes a retry
## safe, because nothing was credited. But it must not silently re-arm the
## autosave against the OLD state while the player believes the demolish
## happened, so the old run stays authoritative and the next explicit REBUILD
## tries again.
func _show_save_failed() -> void:
	_prestige.close()
	_cash_label.text = "SAVE FAILED — try REBUILD again"

## Optional parameter, not a required one: test_board_input.gd:611 and :640
## both call save_now() with no argument.
func save_now(s: GameState = null) -> bool:
	var target := s if s != null else state
	if not _saving_enabled or target == null:
		return false
	return SaveStore.save(target)
```

- [ ] **Step 4: Run the suite**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: green. If `test_the_building_survives_a_restart` or
`test_a_debug_board_never_writes_over_a_save` go red, `save_now`'s parameter is
required rather than optional.

- [ ] **Step 5: Commit**

```bash
git add game/game_root.gd tests/test_board_input.gd
git commit -F - <<'EOF'
Replace the views on a demolish, and write before swapping

BuildingView.bind(), ManagementView.bind() and FloorPanel.bind() all add_child
unconditionally -- they are constructors wearing an accessor's name, and
calling any of them a second time stacks a whole UI on top of the old one. So
demolish REPLACES rather than rebinds, freeing synchronously first because
queue_free is deferred to end of frame and input in that window reaches both
trees.

The write comes first and its result is checked. Swapping state and then saving
would show the player the new run while the durable file still held the old,
still-demolish-eligible one; reload and the same earnings pay twice, and the
ten-second autosave would retry against the same broken condition. That is an
ordering bug, not a file-replacement bug, so the atomicity fix does not close
it.

save_now takes an OPTIONAL GameState: two existing tests call it with no
argument.
EOF
```

---

## Task 17: Docstrings, codemaps, and the spec's own consistency

**Why:** spec §13. `CLAUDE.md` makes `codemaps/` the per-file API reference, and
this change adds two `sim/` classes, a `data/` file and three test files —
staling all five maps. Several docstrings now describe code that no longer
exists.

**Files:**
- Modify: `sim/save_codec.gd:17-21`, `sim/game_state.gd:76-78`,
  `game/game_root.gd:159-166`, `CLAUDE.md`, `codemaps/*.md`,
  `docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md`

- [ ] **Step 1: Update the docstrings the change falsified**

- `sim/game_state.gd:76-78` claims *"SaveCodec.decode returns null rather than
  handing back a poisoned state"*. That was aspirational until Task 10; confirm
  the wording now matches and note that `_valid` defaults to false.
- `game/game_root.gd:159-166`'s "Known limit" paragraph says the debug board
  starts with N shafts while `level_of("shaft")` stays 0, so the ghost slot
  prices the first shaft rather than the next. `grant_level` in `_init` fixes
  that; delete the paragraph or rewrite it to say what is still true.
- `game/save_store.gd:39-40`'s null-means-fresh contract is now joined by
  `load_meta` / `load_all`; add a sentence.

- [ ] **Step 2: Reconcile the spec with what was built**

Every place the implementation departed from the spec gets fixed **in the spec**,
not worked around:

- §9's cold-boot snippet calls `SaveStore.load_meta(blueprints_path)`; the built
  code calls `SaveStore.load_all(...)` so the run and the Meta provably share one
  selection. Update the snippet.
- §2.2's `DEMOLITION_FLOOR` and §6's tables carry whatever Task 2 settled.
- §11's `move_child` HYPOTHESIS is now either confirmed by
  `test_a_tap_in_the_ghost_band_after_a_demolish_buys_exactly_one_floor` or
  disproved. Say which, and drop the marker.
- §14 item 6 (dispatch policies) is decided: reset to MANUAL. Record the reason.
- §14 item 4 (S4 sequencing) is decided: overridden explicitly. Record the reason.

Then grep, which is the habit that matters most here:

```bash
grep -rn "load_meta\|HYPOTHESIS\|DEMOLITION_FLOOR\|900" docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md
grep -rn "career_earnings\|grandfather" docs/superpowers/specs/2026-08-03-prestige-and-blueprints-design.md
```

Every hit is either updated or a deliberate quote of a superseded claim.

- [ ] **Step 3: Update `CLAUDE.md`'s status**

Replace the Status paragraph:

```markdown
**Status:** Milestones 1–3, the board/management UI, the cost-curve work and
**S5 (prestige)** are built, tested and deployed. A run now caps at 10 floors and
ladders to 20 through the `height` node; `sim/meta.gd` owns the persistent tree
and `sim/prestige.gd` the demolish. Save format is **v4**. Spec A (tenant kinds +
floor class) is built.
```

- [ ] **Step 4: Regenerate the codemaps**

```
/cc-codemaps:update-codemaps
```

Two new `sim/` classes, a new `data/` file and three new test files stale all
five maps. Do not hand-edit them — they are generated, and user notes belong in
`CLAUDE.md`.

- [ ] **Step 5: Full suite, then commit**

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
git add -A
git commit -F - <<'EOF'
Reconcile the docs with the code, and regenerate the codemaps

Several docstrings described code that no longer exists: game_state.gd claimed
decode refused a poisoned state before it did, save_store.gd claimed atomic
writes it did not have, and game_root's "known limit" paragraph described a
shaft-pricing hole that grant_level closed.

The spec is corrected rather than worked around, including the two open items
this plan decided (dispatch policies reset; S4's sequencing rule overridden
explicitly) and the cold-boot snippet, which now reads through load_all so the
run and the Meta provably share one source selection.
EOF
```

---

## Verification before calling this done

Run all of these and read the output. Evidence before assertions.

```bash
# The whole suite, from a clean import.
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# The threadless export CI asserts on.
godot --headless --export-release "Web" build/web/index.html
```

Then, by hand, in the editor or a browser:

- [ ] A new game caps at **10 floors**, and the ghost band reads
      `CAP REACHED — REBUILD` rather than offering a purchase.
- [ ] Tapping that band opens the prestige panel.
- [ ] The panel's yield line counts down in dollars before the first Blueprint,
      then reads a Blueprint count.
- [ ] REBUILD arms; **Cancel disarms**; only Confirm demolishes.
- [ ] After a demolish the board shows six floors, the HUD reads `$0`, and
      MANAGE still works — the `move_child` hypothesis is exactly what this
      checks.
- [ ] Buying `height` L1 and rebuilding yields a run that reaches 15 floors.
- [ ] Kill the tab mid-play and reload: the building and the Blueprint balance
      both come back. **Web durability is the one thing the headless tests
      cannot pin** (spec §11) — `user://` is IDBFS on the ship target and Godot
      flushes asynchronously on file-handle close rather than on `DirAccess`
      rename/remove.

## Out of scope, deliberately

Eras. The Human and Automation branches. A starting-floors node. Offline
earnings and the catch-up integrator. **A cap above 20 floors** — income is
linear in floors while each floor costs more than the last, so rungs above 20
would sell a ceiling nobody reaches. That is an income-side problem and spec §14
item 1 owns unblocking it.

## Two things nobody has checked

Stated so they are known risks rather than surprises.

- **No reviewer ever examined module boundaries.** The Architect seat was
  quota-locked across all four review rounds while every round moved boundaries.
  If something about the `Meta` / `Prestige` / `GameState` / `SaveCodec` split
  feels wrong as you build it, that instinct has not been checked by anyone —
  take it seriously rather than assuming it was reviewed.
- **~33 spec fixes carry no review.** The `[r5]` and `[r6]` edits applied after
  round 4 were never read by a reviewer. They are mostly propagation fixes and
  one-line corrections, and the judgement was that a compiler and the test suite
  settle them faster than a fifth round. If one looks wrong, it may well be.
