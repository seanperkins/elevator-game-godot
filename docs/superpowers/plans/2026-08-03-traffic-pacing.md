# Traffic Pacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Halve the traffic bucket to 30 real seconds so the starting building's 47.4 trips/day arrives in a 12-minute day instead of 24, doubling trips per real minute.

**Architecture:** `SimClock.TICKS_PER_MINUTE` currently sets both the traffic bucket length (`sim_clock.gd:51`) and the Bernoulli denominator (`traffic_spawner.gd:65`). It is split into `TICKS_PER_REAL_MINUTE` (elapsed time) and `TICKS_PER_SIM_MINUTE` (one bucket). Task 1 performs that split at the *same value*, so it is a pure refactor with a green suite. Task 2 flips the value to 600, which is the only behavioural commit.

**Tech Stack:** Godot 4.7, GDScript, GUT test framework.

## Global Constraints

- `sim/` is pure `RefCounted` — no Nodes, no `FileAccess`. Do not add either.
- The sim runs at 20 Hz; `TICK_SECONDS := 0.05` does not change.
- 47.4 trips/day must remain true. No value in `data/tenants.json` changes.
- The tick order in `game_state.gd` is player-visible and does not change.
- Run the suite with: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Run one file with: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_sim_clock.gd -gexit`
- Local GUT must pass before merging.

---

### Task 1: Split the constant without changing behaviour

Rename `TICKS_PER_MINUTE` into two constants of the *same value* and point every
call site at whichever one it actually means. Nothing changes at runtime; the
suite must stay green. This task exists so Task 2's diff is small enough to
reason about.

**Files:**
- Modify: `sim/sim_clock.gd:9`, `sim/sim_clock.gd:51`
- Modify: `sim/traffic_spawner.gd:65`
- Modify: `sim/tenant_catalog.gd:154` (docstring only)
- Modify: `tests/test_tenant_catalog.gd:44`
- Modify: `tests/test_game_state.gd:96,120,318,444`
- Modify: `tests/test_sim_clock.gd:56,64`

**Interfaces:**
- Produces: `SimClock.TICKS_PER_REAL_MINUTE` (int, 1200) and
  `SimClock.TICKS_PER_SIM_MINUTE` (int, 1200 for now, 600 after Task 2).
  `SimClock.TICKS_PER_MINUTE` ceases to exist.

- [ ] **Step 1: Replace the constant declaration**

In `sim/sim_clock.gd`, replace line 9:

```gdscript
const TICKS_PER_MINUTE := 1200        # 60 s / 0.05 s
```

with:

```gdscript
## Elapsed real time. The metrics window (sim/metrics.gd) is the same length by
## its own construction, and tests use this to advance "a minute".
const TICKS_PER_REAL_MINUTE := 1200   # 60 s / 0.05 s
## One traffic bucket -- the unit data/tenants.json rates are quoted in. Split
## from the above because the spawner's Bernoulli denominator and the bucket
## length must move together: changing one alone leaves trips-per-real-minute
## exactly unchanged (see the pacing spec, section 2).
const TICKS_PER_SIM_MINUTE := 1200
```

- [ ] **Step 2: Point `sim_minute()` at the bucket constant**

In `sim/sim_clock.gd`, line 51 becomes:

```gdscript
	return START_MINUTE + ticks_executed / TICKS_PER_SIM_MINUTE
```

- [ ] **Step 3: Point the spawner at the bucket constant**

In `sim/traffic_spawner.gd`, line 65 becomes:

```gdscript
	if rng.randf() >= total / float(SimClock.TICKS_PER_SIM_MINUTE):
```

- [ ] **Step 4: Update the saturation guard's docstring**

In `sim/tenant_catalog.gd`, the `largest_bucket()` docstring says the worst case
"must stay under TICKS_PER_MINUTE". Replace that phrase with
`TICKS_PER_SIM_MINUTE` — the ceiling is the spawner's denominator, not a real
minute.

- [ ] **Step 5: Update the guard's test**

In `tests/test_tenant_catalog.gd:44`:

```gdscript
	assert_lt(float(Building.MAX_ROWS) * cat.largest_bucket(),
		float(SimClock.TICKS_PER_SIM_MINUTE))
```

- [ ] **Step 6: Update `tests/test_game_state.gd`, respecting the two meanings**

These four do **not** all mean the same thing. Use exactly this mapping:

| line | replace with | why |
| --- | --- | --- |
| 96 | `SimClock.TICKS_PER_SIM_MINUTE * 20` | the comment derives "~43.6 expected spawns" over twenty **buckets** |
| 120 | `SimClock.TICKS_PER_REAL_MINUTE * 3` | elapsed time; nobody is carried either way |
| 318 | `SimClock.TICKS_PER_REAL_MINUTE + BUCKET_SLACK` | the metrics window, 1200 ticks by `sim/metrics.gd:16` |
| 444 | `SimClock.TICKS_PER_SIM_MINUTE * 3` | the comment derives 2.5 trips/min over three **buckets**, "~7.5" |

Getting 96 or 444 wrong does not fail the suite — it leaves the tests passing
while their stated arithmetic becomes false. That is the specific mistake this
step exists to prevent.

- [ ] **Step 7: Update `tests/test_sim_clock.gd`**

Line 56's body and line 64's multiplier both refer to the sim minute:

```gdscript
func test_sim_minute_advances_every_1200_ticks() -> void:
	var start := SimClock.START_MINUTE
	assert_eq(clock.sim_minute(), start)
	clock.note_ticks(SimClock.TICKS_PER_SIM_MINUTE - 1)
	assert_eq(clock.sim_minute(), start, "one tick short is still the opening minute")
	clock.note_ticks(1)
	assert_eq(clock.sim_minute(), start + 1, "one bucket of ticks is one minute on")

func test_sim_minute_uses_integer_arithmetic() -> void:
	# Indexing by a float accumulator lands 1.27e-12 below 60.0 after 1200
	# additions of 0.05, so a >= 60.0 test fires one tick late.
	clock.note_ticks(SimClock.TICKS_PER_SIM_MINUTE * 137)
	assert_eq(clock.sim_minute(), SimClock.START_MINUTE + 137,
		"exact at a high minute count")
```

Leave the function name `test_sim_minute_advances_every_1200_ticks` alone for
now — Task 2 renames it, and doing it here would make this commit look
behavioural when it is not.

- [ ] **Step 8: Confirm no references remain**

Run: `grep -rn "TICKS_PER_MINUTE" --include="*.gd" . | grep -v addons`
Expected: **no output.** Any hit is a missed call site; a stale reference will
not compile in Godot, but catching it here is faster than reading a parse error.

- [ ] **Step 9: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS, 433 tests. This task changes no behaviour, so any failure is a
mis-edit, not a balance effect.

- [ ] **Step 10: Commit**

```bash
git add sim/sim_clock.gd sim/traffic_spawner.gd sim/tenant_catalog.gd tests/
git commit -m "Split TICKS_PER_MINUTE into real and sim minutes

One constant was setting both the traffic bucket length and the spawner's
Bernoulli denominator. Same value for now -- no behaviour change -- so the
pacing commit that follows has a diff small enough to reason about."
```

---

### Task 2: Halve the bucket

The behavioural commit. One value changes; everything that encoded the old
number is corrected alongside it.

**Files:**
- Modify: `sim/sim_clock.gd` (the `TICKS_PER_SIM_MINUTE` value and the `START_MINUTE` docstring)
- Modify: `tests/test_sim_clock.gd:48,56`
- Modify: `tests/test_game_state.gd:84` (comment only)
- Test: `tests/test_traffic_spawner.gd` (new test)

**Interfaces:**
- Consumes: `SimClock.TICKS_PER_SIM_MINUTE` from Task 1.
- Produces: no new symbols.

- [ ] **Step 1: Write the failing pacing test**

This is the test that catches "changed the bucket length but not the
denominator", which nets zero. It is deterministic — no statistics — because it
pins the Bernoulli threshold directly with a stubbed RNG.

Add to `tests/test_traffic_spawner.gd`:

```gdscript
func test_the_spawn_threshold_is_one_bucket_not_one_real_minute() -> void:
	# Two apartment sources at bucket 6 sum to 2 x 0.5 = 1.0 trips/bucket, so
	# the per-tick threshold is 1.0 / TICKS_PER_SIM_MINUTE. At 600 that is
	# 0.001667; at the old 1200 it was 0.000833. A draw of 0.001 therefore
	# spawns under the correct denominator and does NOT under the stale one,
	# which is exactly the mistake this pins: halving the bucket length while
	# leaving the spawner dividing by a real minute changes nothing at all.
	var cat := TenantCatalog.new()
	cat.load_from("res://data/tenants.json")
	var apt := cat.kind("apartments")
	assert_eq(apt.rate_at(6), 0.5, "the fixture this test's arithmetic rests on")

	var sources := _sources(2, apt)

	var below := TrafficSpawner.new(1)
	below.rng = CountingRng.new(0.001)
	assert_eq(below.spawn_from_sources(6, sources, true).size(), 1,
		"0.001 is under 1.0/600 and must spawn")

	var above := TrafficSpawner.new(1)
	above.rng = CountingRng.new(0.002)
	assert_eq(above.spawn_from_sources(6, sources, true).size(), 0,
		"0.002 is over 1.0/600 and must not")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_traffic_spawner.gd -gexit -ginclude="test_the_spawn_threshold_is_one_bucket_not_one_real_minute"`
Expected: FAIL on the first assertion — at the current 1200, a draw of 0.001 is
above the 0.000833 threshold, so nothing spawns and the size is 0, not 1.

- [ ] **Step 3: Halve the constant**

In `sim/sim_clock.gd`:

```gdscript
const TICKS_PER_SIM_MINUTE := 600
```

Update its comment to say `# one traffic bucket = 30 real seconds`.

- [ ] **Step 4: Run the new test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_traffic_spawner.gd -gexit -ginclude="test_the_spawn_threshold_is_one_bucket_not_one_real_minute"`
Expected: PASS.

- [ ] **Step 5: Correct the `START_MINUTE` docstring**

In `sim/sim_clock.gd`, the docstring above `START_MINUTE` argues that "a day
starting at bucket 0 showed a new player an empty building for about six real
minutes". Six buckets at 30 seconds is now **three** real minutes. Change the
number, keep the argument — it is still the reason `START_MINUTE` is 6, and a
45-second patience against a 30-second bucket makes the point more sharply, not
less.

- [ ] **Step 6: Correct the same claim in `tests/test_sim_clock.gd:48`**

`test_the_day_starts_at_the_morning_rush` repeats "an empty building for six
real minutes" in its comment. It still passes — this is a comment fix — but
leaving it makes two files disagree about the same number.

- [ ] **Step 7: Rename the test that hardcodes 1200 in its name**

In `tests/test_sim_clock.gd`, rename:

```gdscript
func test_sim_minute_advances_every_bucket() -> void:
```

The boundary it guards is "one bucket", not "1200 ticks". Pinning the literal in
the name is what made it a maintenance item rather than a stable guard.

- [ ] **Step 8: Correct the spawn-count comment in `tests/test_game_state.gd:84`**

The comment reads "Twenty minutes spans the morning rush (~43.6 expected
spawns) ... unlike the overnight trough's 1.4." Those figures are per twenty
**buckets** and stay correct now that line 96 uses `TICKS_PER_SIM_MINUTE`, but
the words "Twenty minutes" now mean ten real minutes. Reword to "Twenty buckets"
so the unit is unambiguous.

- [ ] **Step 9: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS, 434 tests (433 plus the new one).

If `test_game_state.gd:444` fails (`assert_gt(spawned.size(), 4)`), do **not**
weaken the assertion. It means Step 6 of Task 1 was applied wrongly — that test
must be counting three buckets, and under `TICKS_PER_REAL_MINUTE` it would be
counting six and drawing at half the rate.

- [ ] **Step 10: Commit**

```bash
git add sim/sim_clock.gd tests/
git commit -m "Halve the traffic bucket to 30 real seconds

The starting building's 47.4 trips/day is the figure spec 5.6 targets, but a
day was 24 real minutes, so it landed at 1.97 trips/min. The day now passes in
12 minutes; trips/day is unchanged.

The new spawner test pins the Bernoulli denominator to the bucket length --
moving one without the other nets exactly zero change."
```

---

### Task 3: Play-test and record the difficulty effect

The spec names a risk it does not pre-emptively mitigate: car speed, door
timings and the 45-second patience are all in real time, so this doubles the
load on the starting single car without giving it anything. This task decides
whether that landed well. It ships no code by default.

**Files:**
- Modify (only if the play-test says so): `data/traffic_walkup.json`

- [ ] **Step 1: Build and run on device**

Run: `ios/build.sh --launch`

- [ ] **Step 2: Play the opening for at least two full days (24 real minutes)**

Watch for: expiries during the bucket-7 peak, whether satisfaction on any row
drops toward `Tenancy.MOVE_OUT_THRESHOLD`, and how long the first $200 floor
takes. Expect roughly **$12/minute** against the old $6.

- [ ] **Step 3: Decide, and record the decision**

If the opening is merely busier — ship it, and this task ends here.

If passengers routinely expire before the single car can reach them, raise
`base_patience_ticks` in `data/traffic_walkup.json` from 900. It is the one
patience knob the spawner reads (`sim/traffic_spawner.gd:43`, floored at 1) and
a data-only edit. Re-run the full suite after any change.

Either way, append a short note to
`docs/superpowers/specs/2026-08-02-traffic-pacing-design.md` section 5 recording
what was observed, so the next reader knows the risk was checked rather than
forgotten.

- [ ] **Step 4: Commit any change**

```bash
git add data/traffic_walkup.json docs/superpowers/specs/2026-08-02-traffic-pacing-design.md
git commit -m "Record the pacing play-test outcome"
```
