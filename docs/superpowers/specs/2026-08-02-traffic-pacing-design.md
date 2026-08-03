# A day that arrives twice as fast

**Status:** agreed, not yet built.

The starting building generates **47.40 trips/day**, which is exactly the figure
§5.6 of the base design targets and exactly what `data/tenants.json` sums to. The
implementation is faithful. The problem is that a *day* is 24 real minutes, so
that budget spreads to **1.97 trips/minute** — and at a $3 apartment fare that is
about $6/minute against a $200 "Build a Floor". The first floor is roughly
thirty-five minutes of average play.

This spec halves the bucket length so the same day arrives in twelve minutes.
Traffic per day is unchanged; traffic per *real* minute doubles.

---

## 1. The measured baseline

Computed from `data/tenants.json` for the starting building (1 shops +
5 apartments), which is what a fresh save produces:

| | trips/min |
| --- | --- |
| trough (bucket 0) | 0.50 |
| **average** | **1.97** |
| peak (bucket 7) | 6.10 |

A new game starts at bucket 6 (`SimClock.START_MINUTE`), immediately before the
07:00 peak, so the opening climbs to ~6/min and falls back. That swing is
deliberate and this spec does not touch its shape — only its rate.

## 2. `TICKS_PER_MINUTE` is doing two jobs

This is the whole reason the change is not a one-line edit.

Expected spawns during one bucket are

```
total_rate / divisor  x  bucket_ticks
```

where the *divisor* is the Bernoulli denominator in `sim/traffic_spawner.gd:65`
and *bucket_ticks* is the bucket length implied by `sim/sim_clock.gd:51`. Both
are `TICKS_PER_MINUTE` today, so the expression collapses to `total_rate` — which
is what makes the per-bucket rates in `data/tenants.json` mean "trips in this
bucket", and what makes them sum to 47.4 trips/day.

Change the bucket length alone and **both the day and the trips/day halve**,
netting exactly zero change in trips per real minute. The two must move together.

## 3. The change

**1. `sim/sim_clock.gd`** — split the overloaded constant:

```gdscript
const TICKS_PER_REAL_MINUTE := 1200   # 60 s / 0.05 s -- elapsed time
const TICKS_PER_SIM_MINUTE  := 600    # one traffic bucket = 30 real seconds
```

`sim_minute()` divides by `TICKS_PER_SIM_MINUTE`.

The `START_MINUTE` docstring argues from "a day starting at bucket 0 showed a new
player an empty building for about six real minutes". That trough is now three
minutes. The argument survives; the number in it does not, and must be corrected
rather than left to rot.

**2. `sim/traffic_spawner.gd:65`** — divide by `TICKS_PER_SIM_MINUTE`. This is
the edit that actually doubles throughput, and pairing it with (1) is what keeps
expected-spawns-per-bucket equal to the bucket's rate.

**3. `sim/tenant_catalog.gd:154`** — the docstring names `TICKS_PER_MINUTE` as
the saturation ceiling. The real ceiling is now the spawner's divisor, 600.

**4. `tests/test_tenant_catalog.gd:44`** — the assertion must compare against
`TICKS_PER_SIM_MINUTE`. Leaving it at 1200 does not fail; it silently stops
guarding the invariant it exists to guard, which is worse.

**5. `tests/test_sim_clock.gd`** — three tests know the old divisor. Two of them
**fail** under the change; they are not cosmetic:

| line | test | why |
| --- | --- | --- |
| 48 | `test_the_day_starts_at_the_morning_rush` | passes, but its comment says the trough "shows a new player an empty building for six real minutes". Now three. Comment only. |
| 56 | `test_sim_minute_advances_every_1200_ticks` | **fails.** `note_ticks(1199)` is one minute on at a 600-tick divisor, not "still the opening minute". Rename and re-pin to 599/600. |
| 64 | `test_sim_minute_uses_integer_arithmetic` | **fails.** `note_ticks(1200 * 137)` yields `START_MINUTE + 274`. Must multiply by `TICKS_PER_SIM_MINUTE`. |

Test 56 should stop hardcoding the number in its name and body — the boundary it
guards is "one bucket", not "1200 ticks", and pinning the literal is what made it
break rather than adapt.

**6. `tests/test_game_state.gd`** — four uses, and they do **not** all mean the
same thing. Two count real time; two count traffic buckets. Renaming all four to
`TICKS_PER_REAL_MINUTE` would leave both bucket-counting tests still passing
while their arithmetic silently became wrong, which is the worst outcome
available here.

| line | means | becomes |
| --- | --- | --- |
| 96 | **buckets** — the comment derives "~43.6 expected spawns" over twenty buckets | `TICKS_PER_SIM_MINUTE` |
| 120 | real time — "an idle building earns nothing" over three minutes | `TICKS_PER_REAL_MINUTE` |
| 318 | real time — the metrics window (`sim/metrics.gd:16`, 1200 ticks) | `TICKS_PER_REAL_MINUTE` |
| 444 | **buckets** — the comment derives `shops.rate_at(6) + 5 x apartments.rate_at(6)` = 2.5 trips/min, "~7.5 over three minutes" | `TICKS_PER_SIM_MINUTE` |

Lines 96 and 444 keep their comments' arithmetic true only under
`TICKS_PER_SIM_MINUTE`. Under the real-minute constant both would span twice the
buckets, still pass, and quietly document the wrong numbers.

Line 318 was checked specifically: it exercises the metrics window, and
`sim/metrics.gd:16` defines that window independently as
`BUCKET_TICKS (20) x BUCKETS (60)` = 1200 ticks. It is a real minute by
construction and does not follow the sim minute.

## 4. What stays true

- **47.4 trips/day.** §5.6 needs no revision. A day simply passes in twelve
  real minutes rather than twenty-four.
- **The traffic shape.** Every bucket keeps its relative weight; no value in
  `data/tenants.json` changes.
- **Determinism.** The seed sequence is untouched — the same number of `randf()`
  draws happen per tick, just against a larger probability.

## 5. The balance consequence, stated plainly

Everything else in the sim is measured in real time: car speed
(`ElevatorCar.rows_per_tick`), door timings, and the 900-tick (45 s)
`base_patience_ticks`. Doubling arrivals per real minute therefore **doubles the
load on the starting single car without giving it anything**. Early expiries will
rise, which feeds satisfaction and then move-outs.

The no-fail-state invariants still hold — cash floors at 0, and re-leasing is
free while fewer than 2 rows are tenanted — so this cannot strand a player. But
the opening gets harder as well as richer, and that is the risk this spec
knowingly takes.

If it overshoots, the cheapest counterweight is raising `base_patience_ticks` in
`data/traffic_walkup.json`. That is a data edit, it is the one patience knob the
spawner reads, and it does not disturb anything above.

**Outcome, play-tested on device 2026-08-03.** The risk did not materialise. The
opening reads as busier rather than punishing, and no patience change was
needed — `base_patience_ticks` stays at 900. Recorded here so a later reader
knows this was checked and cleared, not overlooked.

## 6. Verification

- The full GUT suite passes (433 tests at time of writing).
- `tests/test_tenant_catalog.gd` asserts saturation headroom against the new
  ceiling: `MAX_ROWS (40) x largest bucket (1.2)` = 48, well under 600.
- A test pinning the pacing itself: at a known seed, ticking one bucket's worth
  of ticks yields spawn counts consistent with that bucket's summed rate. This
  is the test that would have caught "changed the bucket length only", which is
  the failure mode §2 describes.
