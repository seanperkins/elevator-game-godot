# Opus Skeptic — Round 4 verification pass

Scope: disposition of my round-3 findings against the current text, plus regressions
introduced by the fixes. No new lines of inquiry.

Read in full: `/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md`
(988 lines) and my own
`/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/claude-opus-skeptic-r3-output.md`.

Engine claims were executed, not asserted, on `godot 4.7.stable.official.5b4e0cb0f`
(`/opt/homebrew/bin/godot --headless --script`). Scripts and raw output are in the
session scratchpad (`verify.gd`, `verify2.gd`, `verify3.gd`).

---

## Part 0 — Disposition table

| Round-3 finding | Status |
| --- | --- |
| **CRITICAL-1** beyond-cap absence re-harvested | **CLOSED** (verified numerically) — but the fix introduces **REGRESSION-1** |
| **CRITICAL-2** one formula spanning two clock epochs | **CLOSED** — but introduces **REGRESSION-2** |
| **MAJOR-3** Test A's unstated alignment preconditions | **CLOSED** (both (a) and (b) written down); see REGRESSION-2 and the 10x error in the drift figure |
| **MAJOR-4** ceiling / 100% / ratio-bound contradiction | **CLOSED** as to the contradiction; the binding constraint on the new knob is unstated (**MINOR-o**) |
| **MAJOR-5** reconciliation missed in-car passengers | **CLOSED** |
| **MAJOR-6** reconciliation scoped to Hidden vs. test 11 | **CLOSED** |
| **MAJOR-7** flag-and-consume defeats the hidden-save | **CLOSED**; the §10.1 exit-criterion half **NOT CLOSED** |
| **MAJOR-8** `SAVE_MAX_BYTES` doesn't bound depth | **CLOSED by refutation** — I reproduced the refutation myself; see note on test 14 |
| **MAJOR-9** `catchup_residual_seconds` unbounded | **CLOSED** |
| **MAJOR-10** rail mapping vs. cancel gesture | **CLOSED** |
| MINOR-a step 6→7 cross-ref | CLOSED (§7.2 l.439 now says "step 7 (construction)") |
| MINOR-b test 14 targets `saved_at` | CLOSED (l.804 now names `sim_wall_time` and `catchup_residual_seconds`) |
| MINOR-c backup vs. latch ordering | CLOSED (l.672) |
| MINOR-d "without data loss" only in the byte sense | CLOSED (l.686: backup offered as an export string; discard withheld on version-skew) |
| MINOR-e coalescing unreachable | NOT CLOSED — harmless, and now *more* defensible; see below |
| MINOR-f node table labelled worst case | CLOSED (l.597–602: "subtotal", "real ceiling is ~1,850") |
| MINOR-g cars-per-shaft uncapped | CLOSED (l.102–104, l.605–606, test 18) |
| MINOR-h scale-factor inconsistency | CLOSED (0.546 used in both §2.1 and §3); see REGRESSION-5 |
| MINOR-i 71,270 vs 71,333 | NOT CLOSED, immaterial |
| MINOR-j "any integer row count" | CLOSED (l.128–129 "any *playable* row count") |
| MINOR-k `--import` twice unverified | CLOSED (l.918–919 adds the confirm-before-gating caveat) |
| MINOR-l JSON float round-trip | NOT CLOSED — now measured, still minor; see below |
| **MINOR-m version gate must be `TYPE_INT`** | **WITHDRAWN — I was wrong. Verified below.** |
| MINOR-n `tests/` scope; no shaft-cap test | HALF CLOSED — test 18 added; §8.2 l.540 scope sentence still narrower than §9.2 |

---

## Part 1 — MINOR-m: I was wrong, and the plan is right

Executed on 4.7.stable:

```
A1 typeof(JSON.parse_string('{"version": 1}')["version"])   = 3   (TYPE_INT=2, TYPE_FLOAT=3)
A2 typeof(JSON.parse_string('{"version": 1.0}')["version"]) = 3
A3 1 == floor(1)                                            = true
A4 typeof(1.5) = 3, integral = false
```

`TYPE_INT` never occurs for a JSON number, so a `typeof(v) == TYPE_INT` gate would
refuse every save the game writes — exactly as §8.6 l.634–636 states. My round-3
rationale ("a hostile document writing `"version": 1.0` must take the refusal
path") is also unachievable in principle: A1 and A2 are the same Variant type and
the same value, so `1` and `1.0` are not distinguishable after parse. The plan's
*`TYPE_FLOAT` and integral (`v == floor(v)`) and within `[migration_floor,
current]`* is the correct gate, and A4 confirms the integrality check is what
discriminates. The pentester is right; I withdraw MINOR-m.

Test 17 (l.807–808, "a freshly-written save loads") is the right regression guard
for it.

---

## Part 2 — The two new design decisions the brief flagged

### 2.1 `offline_efficiency` and Test B (was MAJOR-4)

**The contradiction is resolved.** The three round-3 claims were jointly
unsatisfiable because deleting the rate fraction left no term below the ceiling.
§7.2 l.423–432 restores it: offline pays `offline_efficiency x ceiling` with
efficiency starting well below 1 and raised by Automation "toward a stated maximum
that is still below 1". §9.1 l.757–763 turns Test B into a concrete inequality —
`catch-up / lived <= 1.0` over a named matrix of dispatch tiers and upgrade states,
for every `t₀` phase. That is checkable: it names the quantity, the sweep, and the
bound. MAJOR-4 CLOSED.

**Two residual problems, both specification rather than design (MINOR-o):**

1. **The stated justification does not support the conclusion.** l.762–763: "it is
   checkable because §7.2's `offline_efficiency` sits below the ceiling by
   construction." Efficiency `< 1` is not sufficient. The test asserts
   `efficiency x ceiling <= lived`, i.e. `efficiency <= lived / ceiling`. Lived
   throughput is not bounded below by any fraction of the ceiling — it falls with
   dispatch quality and is ~0 for a player who never dispatches. The actual binding
   constraint is `offline_efficiency <= min over the matrix of (lived / ceiling)`,
   which is a *tuning* result the matrix produces, not a property that holds by
   construction. Write the constraint down and Test B becomes a genuine gate on the
   constant; leave it as "below 1" and Test B is a coin flip at Milestone 6, which
   is the tolerance-loosening failure mode §9.1 l.740–741 correctly diagnosed about
   the old 1e-9.

2. **"Active play must never be worse than idling, for any player state" (l.760–761)
   over-claims what the test checks.** The test sweeps a *named matrix*; "any player
   state" includes states outside it (a manual pre-Milestone-4 player who idles the
   board has `lived → 0` and the ratio diverges). Scope the sentence to the matrix,
   or state that the matrix's worst tier is defined to be the floor of supported
   play.

Also: `offline_efficiency` is a new balance constant with a test-bearing constraint
and it is **not in §13's open items** (l.966–980), unlike every other constant of
its kind.

### 2.2 The watermark rule (was CRITICAL-1 and CRITICAL-2)

**CRITICAL-2 is CLOSED.** §7.2 l.293–294 redefines `sim_wall_time` as a Unix-epoch
instant, and l.304–311 gives the dual-anchor rule: capture `(unix_now,
ticks_msec_now)` at session start, derive in-session `now = unix_at_start +
(ticks_msec() - ticks_at_start)/1000`, read `Time.get_unix_time_from_system()`
directly on cold start. Both `now` values are then in the epoch domain, the
subtraction is well-typed, and the monotonic clock supplies only the delta — so
l.434–436's claim that in-session DST/NTP/manual changes cannot move a window is
true. The "cold start credits the full cap unconditionally" defect is gone.

**CRITICAL-1's specific exploit is CLOSED.** I ran the scenario (`verify2.gd`,
block K): 4 h cap, 24 h absence, then five 1-second resumes.

```
cycle 1: elapsed=14400 truncated=true  cumulative = 4.000 h
cycle 2: elapsed=1     truncated=false cumulative = 4.000 h
cycle 3: elapsed=2                     cumulative = 4.000 h
cycle 4: elapsed=4                     cumulative = 4.000 h
cycle 5: elapsed=8                     cumulative = 4.000 h
cycle 6: elapsed=16                    cumulative = 4.000 h
```

4.000 h total, not the 20 h my round-3 finding harvested. The `sim_wall_time =
now - residual` commit plus zeroing the residual on a clamp-truncated window
(l.328–329) does exactly what l.321–327 claims. §9.2 test 9's successive-resume
invariant (l.789–792) passes.

**But the fix introduces a new leak — see REGRESSION-1, which is the blocking
finding of this pass.**

---

## Part 3 — Regressions introduced by the fixes

### REGRESSION-1 (CRITICAL) — the residual is now carried in two places, so short hide/resume cycles credit up to 15x real time

Three rules in §7.2 are individually stated and mutually inconsistent:

- l.301 `elapsed = clampf(now - sim_wall_time, 0.0, offline_cap)`
- l.314–315 "applying a window sets `sim_wall_time = now - residual`"
- l.388–389 "On resume, `total = residual + elapsed`, run `floor(total / 60)` steps,
  store `total mod 60` back"

Setting the watermark *back* by `residual` means the next window's `elapsed`
already contains those residual seconds. Line 389 then adds the same residual a
second time out of the persisted field. The remainder is carried twice per cycle.

I implemented the three rules literally and ran the plan's own test 10
(l.793: "120 resumes of 29 s equals one 58-minute absence"). `verify2.gd`, block H:

```
i=1  now=29   elapsed=29  total=29   steps=0  cum=0    resid=29
i=2  now=58   elapsed=58  total=87   steps=1  cum=60   resid=27
i=3  now=87   elapsed=56  total=83   steps=1  cum=120  resid=23
i=4  now=116  elapsed=52  total=75   steps=1  cum=180  resid=15
i=5  now=145  elapsed=44  total=59   steps=0  cum=180  resid=59
i=6  now=174  elapsed=88  total=147  steps=2  cum=300  resid=27
...
PLAN-AS-WRITTEN: 120 x 29 s -> credited 7140 sim-s for 3480 real-s (ratio 2.0517)
```

**7,140 sim-seconds credited for 3,480 real seconds.** The plan's stated expectation
(l.392–393, "120 background cycles of 29 seconds equal one 58-minute absence") is
3,480. Test 10 fails as specified, and l.331–333's governing invariant — "total
credited sim-seconds is at most real elapsed seconds" — is violated by 2.05x.

The multiplier grows as the cycle shortens (`verify3.gd`, 20,000 simulated seconds
per row):

| background cycle | credited / real |
| --- | --- |
| 1 s | **14.997** |
| 3 s | 9.997 |
| 5 s | 5.997 |
| 10 s | 2.997 |
| 29 s | 2.063 |
| 60 s | 1.000 |
| 120 s | 1.000 |

The 1-second row is the mechanism: the residual follows the doubling map
`r → (g + 2r) mod 60`, which for `g = 1` cycles through {3, 7, 15, 31} and banks a
whole 60-second step every fourth cycle. This is precisely the exploit l.390–391
says the carry rule exists to prevent — "rounding up means press-home-and-reopen is
free money, a new exploit structurally identical to the one this model was rewritten
to kill." `offline_efficiency < 1` damps it but does not remove it: at efficiency
0.3 a 1-second cycle still pays 4.5x.

**Second, independent symptom of the same root cause.** l.294–296 says
`sim_wall_time` "advances in exactly two places — forward by `0.05` per executed
tick, and by the atomic commit." The commit can move it *backward*: after active
play has tick-advanced the watermark to `now`, a resume sets it to `now - residual`,
i.e. up to 60 s behind. Those 60 seconds were already credited by executed ticks and
will be credited again by catch-up at the next boundary. So the leak is not confined
to rapid cycling — ordinary alternation of play and backgrounding pays for the same
seconds twice.

**Fix (pick exactly one carrier — I verified both are exactly conservative):**

- Variant A — `sim_wall_time = now` on commit; residual carried only in the field.
  120 x 29 s → **credited 3,480 for 3,480** ✓
- Variant B — `sim_wall_time = now - residual` on commit; `total = elapsed` only, no
  re-add. 120 x 29 s → **credited 3,480 for 3,480** ✓

Variant B is closer to the current text and keeps the watermark self-describing, but
it needs the additional rule that the watermark is monotonically non-decreasing and
is never set behind the tick-advanced value. Either way, the `residual` line
(l.388–389) and the commit line (l.314–315) cannot both stand as written.

### REGRESSION-2 (MAJOR) — redefining `sim_wall_time` as an epoch instant severed catch-up's curve-bucket index

MAJOR-3(a) is closed by l.371–372: "**The minute index is integer arithmetic** —
`ticks_executed / 1200`, never a float accumulator." MAJOR-3(b) is closed by
l.363–365's partial-step / whole-buckets / tail rule. Both are correct, and I
confirmed the residual-as-phase reading is self-consistent (`φ = 30, elapsed = 100`
→ `total = 130`, two boundary crossings, tail 10; durations 30 + 60 + 10 = 100 ✓).

But `ticks_executed / 1200` is the *live* path's index, and l.317–319 states
"catch-up executes no ticks." So during catch-up the bucket index has no stated
derivation, and the two candidates are both defective:

- If catch-up advances `ticks_executed` by 1,200 per step, then l.295's "forward by
  0.05 per executed tick" also advances `sim_wall_time` by 60 per step — on top of
  the atomic commit. A third double-count.
- If it does not, the index is frozen across the window and every catch-up step
  reads the same bucket, which is exactly the failure l.366–369 quantifies at ~4e-3
  and which Test A exists to catch.

In round 3 this was implicit: `sim_wall_time = ticks_executed x 0.05` made the
bucket index `sim_wall_time / 60` by definition. Making the watermark an epoch
instant removed that identity without replacing it. Test A's premise (l.750–753,
"the *integrated rate* over any whole number of minutes is the same finite sum in
both paths") depends on the two paths indexing the same curve, so this is directly
load-bearing on the 1e-9 bound.

One sentence closes it: state that catch-up advances the sim-minute index by one per
executed step (and that this index, not `sim_wall_time`, selects the bucket), and
that catch-up steps are not "executed ticks" for the purposes of l.295.

### REGRESSION-3 (MINOR) — "In-session stalls never route through catch-up" is now literally false

l.348: "**In-session stalls never route through catch-up.**" l.399–400, two
paragraphs later: below the reconciliation threshold "the gap rides as sim-time lag,
**which the anchor credits at the next boundary**." Both cannot be true — the anchor
is `now - sim_wall_time`, and a stall is exactly a period in which `sim_wall_time`
did not advance, so the stall gap is inside the next boundary's `elapsed` by
construction.

The economic consequence is bounded and small (a stall's worth of seconds, credited
once), and the *double-pay* worry of l.349–351 only bites when `elapsed` is below the
reconciliation threshold — in which case the surviving discrete passengers are
delivered again on top of the analytic credit. Restate as "in-session stalls are not
*routed* to catch-up at the moment they occur; the lag they create is credited once
at the next boundary," and note that below the reconciliation threshold the window is
minutes-scale so the overlap is negligible.

### REGRESSION-4 (MINOR) — §9.2's test list is misnumbered

l.806–810 runs `… 15, 17, 18, 16`. Test 16 ("no save found") is now last, after 18.
Eighteen tests, four of which changed number between rounds — the list is referenced
by number elsewhere in the document, so renumber once and leave it.

### REGRESSION-5 (MINOR) — §3 caps shafts at 8 while its own sentence says 6–7

The MINOR-h fix put 0.546 into both sections; the arithmetic now reproduces exactly
(32 x 0.546 = 17.47 pt ✓ l.43; 44 / 0.546 = 80.6 units ✓ l.96; 720 / 80.6 = 8.93 ✓
l.97). But l.97–98 concludes "realistically **6–7** once a row-label gutter and
margins exist" and l.95 then states "**8 shafts maximum**." Working the gutter back
out: 8 columns at 80.6 units need `720 - g >= 645`, i.e. a gutter up to **75 units =
41 pt**, which is ample; getting down to 7 columns requires a gutter of **155 units =
85 pt**, and 6 requires **236 units = 129 pt** — a third of the screen for row
labels. So 8 is the defensible number and "6–7" is the unsupported one. Delete the
6–7 aside or state the gutter budget it assumes.

---

## Part 4 — Items not closed, with what changed

**MAJOR-7 secondary — §10.1 exit criteria.** The main finding is closed: l.263–272
makes the hidden-save synchronous inside the JS callback and forces
`godot_js_os_fs_sync()` from the glue, with the `emscripten_set_main_loop(..., -1,
...)` and `idb_needs_sync` grounding, and l.275–277 confines the deferred flag to
sim-state mutation only. That is the right split and it repairs §8.6's
"firing the immediate hidden-save" argument. Not closed: l.874–876's phone-lock exit
criterion still only requires "a sane wall-clock delta" be logged. The thing at risk
is whether the save **landed** — require `restored: yes` after a phone-lock plus
force-kill, or the criterion does not test the mechanism the section was rewritten
for.

**MAJOR-8 — closed by refutation, and I reproduced it.** l.494–497 says depths of
1,500 / 5,000 / 100,000 return `null` cleanly. Confirmed:

```
ERROR: Parse JSON failed. Error at line 0: JSON structure is too deep
   at: parse_string (core/io/json.cpp:629)
B depth 1500   -> null
B depth 5000   -> null
B depth 100000 -> null
```

There is an explicit parser depth guard; my stack-overflow premise was wrong and the
plan's correction is right, including "do not build a pre-parse depth scanner on the
assumption of a crash." I also confirmed the two adjacent §7.3 claims: `1e400` parses
to `inf` as `TYPE_FLOAT` with `is_finite() == false` (so l.653–655's reasoning
holds), and `Marshalls.base64_to_utf8("not base64!!!")` returns `""` with a logged
error and no crash (l.498–500 ✓).

One consequence: **§9.2 test 14 (l.802–804) no longer lists deep nesting.** The
clean-`null` behaviour is an engine property that a future Godot could change, and
the container-count pre-scan (l.496–497) is now the only thing standing between a
pathological document and the parser. Put one deep-nesting case back in the matrix as
a guard on the engine behaviour the plan is relying on.

**MINOR-e — coalescing.** Still unreachable at the GDScript level (single-threaded,
threadless export, `visibilitychange` cannot preempt a frame). But l.263 now makes
the hidden-save force an IndexedDB sync from JS, and that sync *is* asynchronous — so
"a save requested while one is in flight" is now reachable at the IDB layer. Keep the
rule; the motivating scenario in l.694–698 is still the wrong one.

**MINOR-l — measured.** `JSON.stringify` defaults to ~15 significant digits:

```
default    {"t":1785000000.12346}    round-trip delta = 4.05e-06 s
full_prec  {"t":1785000000.123456}   round-trip delta = 0.0
```

`catchup_residual_seconds` (magnitude < 60) round-trips exactly at default
precision; `sim_wall_time` at epoch magnitude loses ~4 microseconds per save/load.
Economically nil, and §9's relative-epsilon rule (l.735–736) covers test 11 at
4e-6 / 1.785e9 = 2.3e-15. But it is a one-word fix — pass `full_precision = true`, or
store the watermark as integer seconds plus a separate fraction — and §8.6's
continuation-state list (l.704–705) is where it belongs now that an economic
invariant reads that field.

**§7.2 l.372–374 drift figure is 10x low.** "After 1200 additions of 0.05 the
accumulated value differs from 60.0 by ~1e-13." Measured:

```
accum 1200 x 0.05 = 59.99999999999872813   delta = -1.27e-12
1200 * 0.05       = 60.00000000000000000   delta =  0.0
```

**1.27e-12**, not ~1e-13, and the sign matters for the argument: the accumulator
lands *below* 60.0, so a `>= 60.0` bucket test fires one tick **late**. The
conclusion (index by integer tick count) is right and the downstream 8e-5 cost
estimate is unaffected; only the stated constant is wrong.

**MINOR-n half.** Test 18 (l.809) closes the shaft-cap gap. §8.2 l.540 still scopes
`tests/` to "GUT specs against `sim/` and `game/save_codec`" while §9.2 names tests
against `game/util/number_format` (test 3) and `save_manager` (tests 15, 16).
One-word fix.

---

## Assessment

Nine of my ten round-3 CRITICAL/MAJOR findings are genuinely closed, and closed the
right way — not by softening the claim but by naming the mechanism (the atomic
commit, the dual-anchor clock, the integer minute index, the phase-aligned partial
step, reconciliation keyed on `elapsed`, the synchronous hidden-save, the absolute
rail mapping with a `< 16` unit threshold, the `[0, 60)` bound). Two of them were
closed by *refuting* me with executed evidence — the JSON depth guard and the
`TYPE_FLOAT` version gate — and on both counts the plan is right and I was wrong. I
verified both against the engine rather than conceding on assertion, and I have
withdrawn MINOR-m.

What blocks approval is REGRESSION-1. The CRITICAL-1 fix closed the beyond-cap
re-harvest (verified: 4.000 h, not 20 h) but introduced a shorter-period leak of the
same family, because the sub-minute remainder is now carried by two mechanisms that
were each correct alone. It is not a subtle edge: the plan's own test 10 fails at
2.05x, the plan's own governing invariant is violated, and a 1-second background
cycle credits 15 seconds. It is also a one-line repair — delete one of the two
carriers — and I have verified numerically that either choice is exactly
conservative.

REGRESSION-2 is the other thing I would not ship without: the epoch redefinition
silently removed the identity that gave catch-up its curve-bucket index, and Test A's
1e-9 bound rests on both paths indexing the same buckets. One sentence.

Everything else in Part 3 and Part 4 is a sentence-level repair that should not gate
anything, with the possible exception of §10.1's phone-lock criterion, which is cheap
to strengthen and is the only on-device check of the §7.1 rewrite.

VERDICT: REVISE — concerns above should be addressed first
