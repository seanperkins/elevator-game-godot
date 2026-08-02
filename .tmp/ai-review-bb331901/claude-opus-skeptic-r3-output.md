# Opus Skeptic — Round 3 (final) review

Reviewed: `/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md` (835 lines)
and `revisions.txt` (151 lines), both read in full.

All repository citations below were re-derived from tool output in this session
(`/Users/sean/sites/elevator-game-godot/...`). Every quantitative claim shows its
arithmetic.

---

## Part 0 — Disposition of my round-2 findings

| Finding | Status | Note |
| --- | --- | --- |
| **C1** 1e-9 catch-up tolerance unachievable | **Closed in principle, conditionally reopened** | The piecewise-constant-bucket construction is a legitimate way to make 1e-9 real (see the float budget in Part 1). But the plan does not state the two alignment preconditions the construction requires → **MAJOR-3**. |
| **A** era-height invariant false/impossible | **CLOSED** | Deleted, and the replacement arithmetic checks out (Part 2, sweep items 1–2). |
| **B** sub-minute remainder unspecified | **CLOSED** | `catchup_residual_seconds` carry is correct and exactly conservative (sweep item 17). Residual *range validation* is a new gap → MAJOR-9. |
| **C** §8.3 "surrendered to catch-up" had no interface | **CLOSED** | §8.3 now says nothing is surrendered; in-session stalls lag instead. The double-pay argument in §7.2 is correct. The sim-clock anchor it introduced has its own defects → CRITICAL-1, CRITICAL-2. |
| **D** §5.3 two no-fail rules cancelling | **CLOSED** | One rule. I traced the terminal states: 0 tenanted → free re-lease; 1 tenanted at satisfaction 0 → below threshold → move-out countdown → 0 tenanted. Recovery is reachable by construction and §9.2 test 4 is writable. |
| **E** `is_finite()` without a type gate; no import size/depth bound | **Half closed** | Type gate closed, with the exact `{"cash": {}}` case named. Size bound closed. **Depth bound not closed** → MAJOR-8. |
| **F** refused-load disable not covering §7.1's hidden-save | **CLOSED** | "*Every* write path checks it — timer, visibility-hidden, focus-out, quit, manual save." Backup/latch *ordering* is a new gap → MINOR-c. |
| **G** release-in-place classified as surge | **Addressed, new defect introduced** | → MAJOR-10. |
| **H** 44 pt rule caps shafts | **CLOSED** | 8-shaft cap is now a board constant with a correct derivation (sweep items 8–10). Residual: the cap moved to cars-per-shaft → MINOR-g. |
| **I** ~600-node estimate | **CLOSED** | Recount is arithmetically correct (sweep item 3). Table is still a floor, not a worst case → MINOR-f. |
| **J** `visibilitychange` with no stated mechanism | **Half closed** | API named and grounded. The flag-and-consume rule defeats the guarantee the section exists for → MAJOR-7. |
| **K** test gaps (gesture, atomic write, hostile-field matrix) | **CLOSED** | Tests 2, 15, 14. New gaps listed under CRITICAL-1, MAJOR-9, MINOR-b, MINOR-n. |

Prior MINORs a–j: I re-checked each against the revised text; all are either
incorporated or now moot. Not re-litigated.

---

## Part 1 — Arithmetic in the new material

### §8.5 node recount — correct

| component | stated | recomputed |
| --- | --- | --- |
| passengers 40 × 12 × 3 | 1,440 | 1,440 ✓ |
| crowd bars 40 × 2 | 80 | 80 ✓ |
| tenant widgets 40 × 3 | 120 | 120 ✓ |
| cars 8 × 2 × 2 | 32 | 32 ✓ |
| sum | 1,672 | 1,440+80+120+32 = **1,672** ✓ |

"roughly 2.8x an earlier estimate": 1,672 / 600 = 2.79 ✓.

### §3 shaft-ceiling derivation — sound, with an internal scale inconsistency

- Row height: 1280 units / 40 rows = **32 units** exactly ✓ (plan says "exactly 32").
- §2.1 asserts scale ≈ 0.51 on an iPhone 15 → 32 × 0.51 = 16.3 pt ("roughly 16.5 pt").
- §3 asserts 44 pt ≈ 85 units → implied scale 44/85 = **0.518**.
- Actual iPhone 15 is 393 × 852 pt; `canvas_items`+`expand` scales by
  min(393/720, 852/1280) = min(**0.5458**, 0.6656) = **0.5458**. Browser chrome
  only shrinks the height term, which is not the binding one, so 0.5458 stands.
  That gives a row of 32 × 0.5458 = **17.5 pt** and 44/0.5458 = **80.6 units**.

So the two sections disagree with each other (0.51 vs 0.518) and both disagree
with the device (0.546). This is **MINOR-h**, not a MAJOR, because the conclusion
survives at every value: 720/80.6 = **8.93** and 720/85 = **8.47**, so 8 is the
edge-to-edge ceiling either way, and 17.5 pt is still 2.5× under 44 pt. The
±22 pt half-width figure is 44/2 ✓.

### §9.1 quadrature and stochastic floor — correct, and the methodology is consistent

Composite midpoint relative error ≈ (h²/24)·|f''/f| ≈ h²ω²/24 for a sinusoidal feature.

- Daily sinusoid, T = 1440 min, h = 1 min: ω = 2π/1440 = 4.3633e-3;
  ω² = 1.9037e-5; /24 = **7.93e-7** → plan's "~7.9e-7" ✓.
- Half-hour rush ramp, T = 30 min: ω = 2π/30 = 0.20944; ω² = 4.3865e-2;
  /24 = **1.828e-3** → plan's "~1.8e-3" ✓. Same rule, same constant. Consistent.
- Stochastic floor: 1/√(1e7) = 1/3162.3 = **3.162e-4** → "3.2e-4" ✓.
- 1200× step ratio: 60 s/min ÷ 0.05 s/tick = **1200** ✓.
- 4 h: 240 min-steps vs 240 × 1200 = **288,000** ticks ✓.

**Is 1e-9 actually reachable?** Yes, and I checked the float budget rather than
taking it on faith. GDScript `float` is IEEE-754 binary64 (ε = 2.22e-16). Worst
case is a 24 h cap = 1,728,000 ticks of sequential accumulation; the naive bound
is n·ε/2 = 1.728e6 × 1.11e-16 = **1.9e-10**, an order of magnitude under 1e-9,
and RMS growth (√n·ε) is 1.5e-13. At a 4 h cap it is 3.2e-11. So the tolerance is
legitimate *given bucket alignment* — see MAJOR-3, which is where it breaks.

### §10 payload — correct; I measured it

Measured in `/Users/sean/sites/elevator-game-godot/build/web/`:

| file | raw | gzip -9 | gzip -6 |
| --- | --- | --- | --- |
| index.wasm | **39,509,339** | **10,052,184** | **10,111,664** |
| index.js | 279,815 | 68,479 | 68,747 |
| index.html | 5,449 | 2,201 | 2,202 |
| index.pck | 7,128 | 5,603 | 5,605 |
| pngs (3) | 26,833 | — | — |

- "39,509,339 bytes raw" ✓ exact.
- "10,052,184 at gzip -9" ✓ exact.
- "~10.11 MB served": gzip -6 (the usual default level) = 10,111,664 = **10.112 MB** ✓.
- "full first-load transfer ~10.2 MB": 10,111,664 + 68,747 + 2,202 + 5,605 + 26,833
  = **10,215,051 B = 10.215 MB** ✓. (9.74 MiB if you prefer binary.)

### Other numbers checked

- Combo infinity: ln(1e308)/ln(1.01) = 709.196/9.95033e-3 = **71,273** → plan's
  "~71,270" ✓ *given the plan's own 1e308 in §8.5*. Against true DBL_MAX
  (1.7977e308) it is 709.783/9.95033e-3 = **71,333**. Immaterial; noted as MINOR-i
  only because the plan elsewhere cites 1e308 as approximate.
- Suffix ladder "98 two-letter entries": ⌈308/3⌉ = 103 magnitude tiers, minus
  {none, K, M, B, T} = 5 → **98** ✓.
- "999,950 formats as 1000.0K": 999950/1000 = 999.95 → round to 1 dp = **1000.0** ✓.
- Residual conservation: 120 × 29 s = **3,480 s = 58 min** ✓, and the
  `total mod 60` carry makes ⌊3480/60⌋ = 58 steps with residual 0 — exactly
  conservative with no drift.
- Era table: 40×3.5 = 140 ✓; 40×14 = 560 ✓; 40×175 = 7,000 ✓; 40×1,000 = 40,000 ✓;
  40×80,000 = 3,200,000 ✓. Growth 14/3.5 = 4 ✓; 175/14 = 12.5 ✓; 1000/175 = 5.71 ✓;
  80000/1000 = 80 ✓.
- Era-start heights at 6 rows: Megatower 6×175 = **1,050 m** vs 560 ✓ matches text;
  Orbital 6×80,000 = **480,000 m** vs 40,000 ✓ matches text. Highrise 6×14 = 84 < 140
  and Stratosphere 6×1,000 = 6,000 < 7,000, so "false for two of four" ✓ exact.

---

## CRITICAL findings

### CRITICAL-1 — Beyond-cap absences leave uncredited time on the books; the anchor lets it be re-harvested

§7.2 defines the watermark as advancing *only* by executed ticks
(`sim_wall_time = ticks_executed × 0.05`) and the window as
`elapsed = clampf(now - sim_wall_time, 0.0, offline_cap)`. The plan never states
what `sim_wall_time` becomes after a catch-up whose `elapsed` was **truncated by
the clamp**. Both readings are stated in the document and they cannot both hold:

- "advances only by executed ticks" → it advances by the *credited* amount only.
- "the single authority for how much time has been economically credited" (§8.3)
  → it must advance by *something* when catch-up credits time.

Take the first (literal) reading with `offline_cap = 4 h`:

1. Away 24 h. Resume: `elapsed = 24 h`, clamped to 4 h. Credit 4 h.
   `sim_wall_time += 4 h`. **20 h remain on the books.**
2. Background for 1 s, resume: `elapsed = 20 h + 1 s`, clamped to 4 h. Credit 4 h.
3. Repeat. Five cycles, ~5 s of real time, harvests the full 24 h.

The offline cap is defeated entirely, by a gesture the player performs anyway.
This is the same defect class §7.2 was rewritten to kill, relocated into the fix.

The correct rule is `sim_wall_time = now` after any catch-up (discarding the
uncapped excess), which is *not* "advances only by executed ticks" and must be
written down as an exception. Note the residual interacts: the carry is
`total mod 60`, which is only correct when `elapsed` was **not** truncated —
on a truncated window the residual must be zeroed, not carried, or the excess
leaks back in through the residual field.

**No test covers this.** §9.2 test 9 checks "far beyond the cap" (one resume) and
test 11 checks path equivalence (one boundary). Neither exercises *two successive
resumes*. The missing invariant is the load-bearing one:

> over any sequence of hide/resume cycles, Σ credited sim-seconds ≤ real elapsed
> seconds, and ≤ n_cycles × offline_cap.

### CRITICAL-2 — `elapsed = now − sim_wall_time` cannot span the two clock epochs the same section mandates

§7.2 presents one formula and emphasises its universality: "**Everywhere** —
resume, cold start, after a hitch — the window is: `elapsed = clampf(now -
sim_wall_time, 0.0, offline_cap)`". Ten lines later it mandates two different
clocks:

- Hidden→Resumed: `Time.get_ticks_msec()` — monotonic, **epoch = engine start**,
  starts at 0.
- Cold start: `Time.get_unix_time_from_system()` — **epoch = 1970**, ≈ 1.77e9 now.

`sim_wall_time` is defined as `ticks_executed × 0.05`, i.e. seconds since sim
start — engine-relative, a small number. On the cold-start path:

```
elapsed = clampf(1.77e9 - 3600, 0.0, offline_cap) = offline_cap
```

**Every cold start pays the full offline cap**, including one taken five seconds
after the last. Force-quit and relaunch is unlimited money. If instead
`sim_wall_time` is stored on the unix epoch, the resume path's
`get_ticks_msec()` term is nonsense (a few-thousand-second value minus 1.77e9 →
clamps to 0, so *no hidden window is ever credited*), and the stated benefit
"removes DST/NTP and in-session clock manipulation entirely from the common path"
is false because you are back on the system clock.

There is a coherent design here, but it is two fields, not one: a persisted
unix-epoch anchor for cold start and an engine-relative anchor for in-session
resume, with a stated rule for keeping them consistent. §8.6's continuation-state
list names a single `sim_wall_time`.

---

## MAJOR findings

### MAJOR-3 — Test A's 1e-9 rests on two unstated alignment preconditions; without them the true error is ~1e-3

The construction is right in outline and the float budget clears 1e-9 by 5×
(Part 1). Two things break it, and neither is written down.

**(a) The minute index must come from an integer tick count.** The plan writes
`curve[floor(sim_minute)]` without pinning `sim_minute`'s derivation. If it is a
float accumulator (the natural implementation, since §8.6 persists a "fractional-tick
accumulator"), the bucket boundary can land one tick early or late: after 1200
additions of 0.05 the accumulated value differs from 60.0 by ~1e-13, and 60.0 is
exactly the comparison point. One tick using the wrong bucket costs
(1/1200)·Δcurve/curve; at a 10% inter-bucket step that is **8.3e-5** — five orders
of magnitude over 1e-9. Fix: index by `ticks_executed / 1200` in **integer**
arithmetic. (`sim_wall_time = ticks_executed × 0.05` by *multiplication* happens
to round upward — 1200 × 0.05 = 60.000000000000007 — so it is safe; repeated
addition is not.)

**(b) Catch-up's minute steps must be phase-aligned to the curve's buckets.**
`sim_wall_time` at the moment of hiding is at an arbitrary phase φ ∈ [0,60) within
a bucket. Catch-up then runs `floor(total/60)` steps of exactly one minute each,
so **every** step straddles a bucket boundary with the same φ, while the live path
splits it (1−φ) / φ across two buckets. The per-step errors telescope, leaving a
boundary term:

```
error = φ · (curve[end] − curve[start]) / ∫
```

Bounded, but for a 240-minute window with a peak-to-mean swing of 1.0 that is up to
**4e-3** — again far above 1e-9, and above Test A's whole reason for existing.
Fix: catch-up must run a partial step to the next bucket boundary, then whole
buckets, then a partial tail (or equivalently keep `sim_wall_time` bucket-aligned).

As written, Test A passes only if authored with `t₀` at a bucket boundary — i.e.
only if the test is written to avoid the case that breaks it.

### MAJOR-4 — "100% of the analytic model" + "throughput ceiling" + "max(catch-up/lived) ≤ 1+δ" cannot all three hold

Round 3 made three changes that are individually reasonable and jointly
contradictory:

1. §7.2: "Base offline rate is **100% of the analytic model**; the Automation
   branch raises the *cap*, not the rate." (The rate fraction was deleted
   specifically so it would not "muddle §9's fidelity test".)
2. §7.2: the model uses "capacity as a **throughput ceiling**".
3. §9.1 Test B: "`max over t₀ of (catch-up / lived) <= 1.0 + δ`" — and §8.1
   confirms catch-up does **not** model dispatch: "catch-up is a separate
   coarse-step integrator."

A throughput *ceiling* is by definition ≥ what any actual dispatch achieves.
§9.1 itself says so: "live earnings also depend on dispatch, capacity, and door
dwell, while catch-up uses a throughput ceiling: these are different quantities."
So `catch-up / lived` ≥ 1 structurally, and grows as the player's dispatch quality
falls below the ceiling — a player on the "Nearest car" policy (§5.4 tier 1) or one
who simply plays badly gets a ratio well above 1, and idling strictly beats playing.
Test B fails for every player state below the reference configuration, and the
±5% band is undefined because "the mean of N seeded live runs" does not name the
dispatch policy or upgrade state the runs use.

Deleting the rate fraction removed the only knob that could reconcile these.
Either the analytic model needs an efficiency term derived from the player's
current dispatch policy and upgrades, or offline must pay a stated fraction of
the ceiling. §14 does not cover this — it is a design decision, not an
implementation detail.

### MAJOR-5 — The boundary reconciliation covers waiting passengers only; the in-car population still produces the event it exists to prevent

§7.2: "the **waiting** passenger population is cleared and folded into the
catch-up window's statistics, and cars are parked idle at their last stop."

Passengers *inside* cars are not waiting. §2 gives every passenger a draining
patience meter and §8.3's order is `deliver → expire` with no exemption for riders.
So after a multi-hour resume the car population — 8 shafts × 2 cars × capacity,
order 100 people against 40 × 12 = 480 waiting, roughly 20% — still has
hours-stale seconds-scale patience timers and expires en masse on the first live
tick. §6 is explicit that the combo "decays on a bad delivery", singular: **one**
surviving in-car expiry kills the combo. The stated goal ("satisfaction craters
and the combo dies, punishing the player for the single most common daily action")
is therefore not achieved by the stated fix.

§9.2 test 12 says "no mass-expiry event in the first live ticks after a multi-hour
resume" — it would fail as specified.

Secondary: "cars are parked idle at their last stop" teleports a mid-flight car
backwards to its previous stop; parking at its current interpolated position (or
completing to its next stop) is the non-lossy choice.

### MAJOR-6 — The reconciliation rule is stated for one path, but §9.2 test 11 demands both paths be identical

§7.2 scopes it precisely: "**Where §8.6's continuation state and the catch-up model
disagree, catch-up wins on the Hidden→Resumed path**; continuation state exists so
a *cold start with no elapsed time* resumes identically."

§7.1's table says cold start takes "Same catch-up path as Resumed", and §9.2 test
11 asserts "hidden-for-N-then-resumed **equals** cold-start-after-N, for N of 0,
sub-minute, at the cap, and beyond."

For N > 0 these are inconsistent: on the Hidden path the waiting population is
cleared; on the cold-start path the save contains a waiting population (the
hidden-save is written *before* — or independently of — the clearing, and in any
case a save written by the 30 s timer during normal play contains one), and §7.2's
"catch-up wins" clause is explicitly restricted to Hidden→Resumed. Restoring it
reproduces the mass-expiry that MAJOR-5's rule exists to prevent, on the more
common of the two paths (§7.3 makes cold start after a long gap the expected case).

Fix: make the reconciliation a property of **catch-up with elapsed > 0**, not of
the Hidden transition. Then test 11 is true by construction and MAJOR-5's ordering
question disappears.

### MAJOR-7 — Flag-and-consume means the save-on-hidden never runs on the primary target

§7.1 states both:

- "**The JS callback fires outside the Godot main loop.** It sets a flag consumed
  at the top of the next `_physics_process`; it never mutates sim state inline."
- "**There is no reliable quit event on the primary target.** ... Saving hangs off
  `visibilitychange`/focus-out plus a 30-second timer."

These are incompatible on iOS Safari. `visibilitychange` fires as an ordinary task
and its handler runs; `requestAnimationFrame` — which drives Godot's main loop —
stops at the same moment. So the flag is set and **no `_physics_process` ever runs
to consume it** until the tab becomes visible again. If the tab is evicted while
hidden (the case the section exists for), the last save is up to 30 s stale and
the hidden-save contributed nothing.

This also invalidates a downstream argument: §8.6 justifies latching *every* write
path with "the first thing a player does when a blocking error appears is switch
apps to look it up, **firing the immediate hidden-save**" — an event that, under
the flag rule, does not fire.

Fix: split the two concerns. The *save* is pure serialisation plus `FileAccess`
and can run synchronously inside the JS callback; only sim-state mutation
(the §7.2 reconciliation) defers to the flag. Also: §10.1's phone-lock exit
criterion currently only requires "a sane wall-clock delta" be logged — it should
require that the hidden-save **landed**, since that is the thing at risk.

*HYPOTHESIS (verify on device, §10.1):* that `visibilitychange` handlers run while
`rAF` is stopped on iOS Safari. Well established for desktop and for iOS in
general, but it is the load-bearing assumption of the fix and §10.1 is where it
gets confirmed.

### MAJOR-8 — `SAVE_MAX_BYTES` does not bound nesting depth; §9.2 test 14's "deep nesting" cannot pass

§7.3 diagnoses this exactly right — "Godot's JSON parser is recursive-descent, so
an over-long or deeply nested paste is a memory kill or **stack overflow — a hard
crash, which means the 'reject cleanly' path never runs**" — and then specifies
only two byte caps, neither of which bounds depth.

A 1 MiB document (§8.6 step 1's stated cap, "generous for this schema") consisting
of `[[[[...` is 1,048,576 levels deep. An 8 MiB stack at ~100–200 B per recursion
frame overflows at ~40k–80k levels — **one to two orders of magnitude before the
byte cap engages**. Step 1 rejects nothing here, step 2 crashes the process, and
steps 3–7 never run. The same holds for the import path with its decoded-size cap.

§9.2 test 14 lists "deep nesting" among the cases the plan expects to reject
cleanly. As specified it cannot.

Fix: a parse-free pre-scan before `JSON.parse_string` — count total `[` + `{`
occurrences (not depth, which needs string-awareness) and reject above a generous
bound. A legitimate save for this schema has a bounded, small container count.

### MAJOR-9 — `catchup_residual_seconds` has no stated range; a hostile value is an unbounded loop

§8.6 adds `catchup_residual_seconds` to the persisted schema. §7.2 uses it as
`total = residual + elapsed; run floor(total/60) steps`.

`elapsed` is bounded by `clampf(..., 0.0, offline_cap)`. `residual` is bounded by
nothing the plan states. A save (editable in devtools, writable by any other site
on the shared origin per §7.3, or pasted via import) carrying
`catchup_residual_seconds: 1e18` yields `floor(1e18/60) = 1.67e16` coarse steps —
a hang on load, before any UI exists to escape it. §8.6's generic "every count in
its era's legal range" does not name it, and this is the one field where the range
is not obvious from the schema.

Fix (one line): reject unless `0.0 <= residual < 60.0`. Add it to the §9.2 test 14
matrix, and independently bound the step loop by `(offline_cap + 60)/60`.

Related, lower severity: a hostile far-*future* `sim_wall_time` makes
`now - sim_wall_time` negative forever, so `clampf` returns 0 and catch-up is
permanently dead. Griefable from a co-tenant origin. §12 accepts shared-origin
exposure, so this is acceptable if stated; it currently is not.

### MAJOR-10 — The §2.1 rail fix is geometrically inconsistent with its own cancel gesture

The round-3 change: "**The rail's initial detent is the car's current row, not the
pressed row.**" Its justification is that otherwise "dispatching a car to the row
your thumb is already on ... would require dragging away and back."

That justification only holds if the rail maps finger *displacement* to detent
displacement (relative mapping). Under relative mapping the plan contradicts
itself:

- Car at row 0, target row 39: required drag = 39 × 32 = **1,248 units** on a
  1,280-unit board, minus whatever the HUD takes. Physically unreachable from any
  press point above the very bottom.
- §2.1 also says "Cancel is a deliberate gesture: **drag past the top or bottom of
  the board**." Under relative mapping, any long dispatch *is* a drag to the board
  edge — the primary verb triggers cancel, which is exactly the failure mode the
  pointer-capture rule was added to avoid, moved from the horizontal axis to the
  vertical one.

Under the alternative (absolute) mapping — detent *i* sits at row *i*'s screen
position — reaching any row is one short drag and cancel is unambiguous, but then
the stated benefit evaporates: pressing row R and dragging to row R still means
leaving R and returning, unless the drag *threshold* (an §13 open item) is smaller
than half a row, i.e. under 16 units ≈ 8 pt. In that reading, release-in-place is
surge because the **threshold** was not crossed, not because of where the detent
was anchored, and the anchoring is a highlight rule with no behavioural content.

§9.2 test 2 asserts both "dispatch to the pressed row" and "rail anchored at the
car's row" as if independent; they are in tension and the plan needs to say which
mapping it means. If absolute (which I recommend), the argument in §2.1 should be
restated in terms of the threshold, and §13's "drag threshold" open item acquires
a hard constraint: **strictly less than 16 units**, or dispatch-to-the-pressed-row
is unreachable.

---

## MINOR findings

- **a — §7.2 cross-reference is off by one.** "Catch-up runs strictly after §8.6
  **step 6**, on validated values." Round 3 added a 7th step (construction from an
  explicit key allowlist); the sim object does not exist until step 7. The
  reference was not updated.
- **b — §9.2 test 14 hostile-input matrix tests the field that was just demoted.**
  It names "`NAN` in `saved_at`". Round 3 made `saved_at` "a diagnostic field, not
  an economic input" and introduced `sim_wall_time` and `catchup_residual_seconds`
  as the economically load-bearing ones. The matrix should target those.
- **c — backup write vs. `writes_disabled` latch ordering is unspecified.** The
  refusal path both *writes a backup* and *latches every write path*; §8.6 says
  "*Every* write path checks it". If the latch is set first, the backup — which
  the blocking message names — is never written. State that the backup precedes
  the latch, or is explicitly exempt.
- **d — "§8.6 handles it without data loss" (§7.3) is true only in the byte
  sense.** The backup lands in `user://`, which §8.6 itself notes "a web player
  cannot browse". The only recovery affordance is *import*, which requires a save
  the player previously exported. Concrete loss path, using §7.3's own claim that
  version skew is "an ordinary post-deploy event": old client refuses the v3 save,
  writes backup B, player taps "discard and start fresh" → real save is now a fresh
  v2, building lives only in B, and a second refusal cycle overwrites B. Either add
  a "restore from backup" action or narrow the claim.
- **e — the coalescing rule is unreachable on the primary target.** Serialise →
  temp write → close → validate → replace is entirely synchronous GDScript, and
  `variant/thread_support=false` (verified: `export_presets.cfg:26`) forbids a
  worker. JS is single-threaded, so a `visibilitychange` task cannot preempt a
  main-loop frame. There is no window in which "a save requested while one is in
  flight" can occur. Harmless as written, but the motivating scenario in §8.6
  cannot happen, and the real risk in that scenario is MAJOR-7, not coalescing.
- **f — the §8.5 table is a floor, not a worst case.** It omits the 40 `floor_row`
  and 8 `shaft_column` containers (§8.2 names both), plus `hud`, `upgrade_panel`,
  and passengers rendered *inside* cars. Call it +150–200, so ~1,850. The
  conclusion ("thousands, not hundreds") is unaffected; the label "worst case" is
  what is wrong.
- **g — §8.5's "The car term is bounded only because §3 caps shafts" is now
  false.** §3 explicitly redirects growth to "**cars per shaft**", and §4's
  Mechanical branch sells it with no stated cap; the table hardcodes ×2. The node
  consequence is small (8 × 4 × 2 = 64, i.e. +32 on 1,672 ≈ +2%), but the sentence
  asserts a bound that no longer exists, and cars-per-shaft needs its own ceiling
  for the same reason shafts did.
- **h — scale-factor inconsistency**, quantified in Part 1: §2.1 uses 0.51, §3
  implies 0.518, the iPhone 15 gives 0.5458 (row = 17.5 pt, 44 pt = 80.6 units,
  8.9 columns). Every conclusion survives; pick one number.
- **i — 71,270** is derived from the plan's own rounded 1e308; true DBL_MAX gives
  **71,333**. Immaterial, noted only because the section is making a precision claim.
- **j — "unachievable at any integer row count"** for Orbital: 0 is an integer.
  The intended claim is "any *playable* row count" — 1 row × 80 km = 80,000 m is
  already 2× the 40,000 m it must beat.
- **k — "run `--import` twice and require the second to exit 0"** is an unverified
  empirical claim being promoted to a hard CI gate. `deploy.yml:41-43` asserts the
  nonzero status is a clean-checkout artefact, but nothing has confirmed the second
  run returns 0. Verify before gating, or CI is red on the first push.
- **l — the anchor is now a float persisted through Godot's JSON.**
  *HYPOTHESIS:* `JSON.stringify` uses ~14 significant digits and is not
  round-trip-exact for binary64. At unix-epoch magnitude (1.77e9) that leaves
  ~1e-5 s of resolution on `sim_wall_time` — adequate — and ~1e-12 s on a
  sub-60 `residual`. Worth one sentence in the schema section now that an economic
  invariant depends on the field's exactness.
- **m — the version type gate must be `typeof(v) == TYPE_INT` specifically.**
  "non-integer" is doing real work in §8.6 step 3; a hostile document writing
  `"version": 1.0` must take the refusal path, and this only works if the check is
  on the Variant type, not on `int(v) == v`.
- **n — §8.2 scopes `tests/` to "GUT specs against `sim/` and `game/save_codec`",
  but §9.2 names tests outside that scope**: test 3 targets
  `game/util/number_format`, tests 15 and 16 target `save_manager`. Also no test
  asserts that shaft purchases stop at the §3 cap of 8 — a new invariant with no
  regression guard.

---

## Consistency sweep — what I actually checked

Grounded against source in this session (files read: `main.gd`, `main.tscn`,
`project.godot`, `export_presets.cfg`, `.gitignore`, `.github/workflows/deploy.yml`,
`build/web/*`):

1. `project.godot` has **no `[physics]` section** → `_physics_process` at 60 Hz ✓
   (§8.3's premise holds; the file ends at `[rendering]`, line 25).
2. `export_presets.cfg:26` is exactly `variant/thread_support=false` at **column 0**
   → §10.2's `grep -qx` assertion matches ✓ (I ran it).
3. `SharedArrayBuffer` in the built JS: **9 occurrences across 8 lines** in
   `index.js`, 0 in `index.html` and both audio worklets → §10.2's "9 occurrences"
   ✓ (occurrence count, not line count — the round-2 correction 8→9 was right).
4. `deploy.yml:73`'s `grep -l ... || echo "none (good: threadless)"` — I ran the
   same grep against the built output; it prints `index.js`, so the "none" branch
   is **unreachable** ✓ and there is no `exit 1` ✓.
5. `deploy.yml:45` is `godot --headless --import || true` ✓.
6. Actions in the workflow: `actions/checkout@v4` (25), `actions/configure-pages@v5`
   (81), `actions/upload-pages-artifact@v3` (82), `actions/deploy-pages@v4` (94) —
   **four, all first-party** ✓, so §10.2's "a rule saying third-party would pin
   nothing" is exactly right.
7. `configure-pages` runs in the **`build`** job (line 81) ✓ — §10.2's
   `pages: read` note is correct.
8. Permissions are workflow-level only (`deploy.yml:8-11`), no per-job scoping ✓.
9. `.gitignore` does **not** contain `export_credentials.cfg` ✓ (it has
   `export.cfg`, which is a different file).
10. `export_presets.cfg:11` `exclude_filter=""` ✓ — currently ships tests.
11. The `.pck` path table stores plain `res://`-prefixed paths (I dumped them:
    `res://main.gd`, `res://main.tscn`, `res://icon.svg`) → §10.2's
    `grep -qa 'res://tests/' build/web/index.pck` is a workable gate ✓, and works
    despite `script_export_mode=2` rewriting content to `.gdc`, because the path
    table keeps the `.gd` path.
12. `progressive_web_app/icon_144x144`, `_180x180`, `_512x512` all `=""` (lines
    40–42) ✓ — "currently empty" is correct.
13. `progressive_web_app/ensure_cross_origin_isolation_headers=false` (line 36) ✓.
14. `html/head_include=""` (line 33) ✓ — the CSP is not yet present.
15. `main.gd`: `_test_persistence()` called from `_ready()` (line 23) **and**
    `_on_tap()` (line 85) ✓; it opens with `FileAccess.WRITE` (107) **before**
    reading (114) ✓; `_readout.bbcode_enabled = true` (77) ✓. Every §10.1 claim
    about the probe is accurate. Note the probe currently displays
    `_persist_status`, not a `restored` field — the latter is new work, correctly
    specified.
16. §8.2 module list vs. everything referenced elsewhere: `economy(combo)`,
    `prestige`, `gesture`, `catch_up`, `save_codec`, `a2hs_prompt` all present ✓.
    Only gap is the `tests/` scope sentence (MINOR-n).
17. §9.2 test count: 8 before Milestone 1 + 8 before Milestone 6 = **16** ✓,
    matching revisions.txt.
18. Arithmetic sweep: all 20 quantitative claims in Part 1 recomputed; the only
    discrepancies are MINOR-h (scale factor) and MINOR-i (71,270 vs 71,333).

**Security sweep** (does user-controlled content reach a shell string, query,
template, or eval?):

- Shell — CI only; `GODOT_VERSION` is a workflow constant, no save/import content
  reaches a shell ✓.
- Eval — `str_to_var`/`bytes_to_var` banned (§8.6) ✓; `variant_to_base64` banned on
  **both** sides (§7.3) ✓; `Expression` on `data/` banned (§8.7) ✓;
  `load()`/`ResourceLoader.load()` on `user://` or save-derived paths banned ✓.
- Template — BBCode: `bbcode_enabled = false` named as the only unconditional off
  switch (§8.4) ✓, correctly noting `.text` parses markup the same as
  `append_text()`; `[img]` beacon and `[url=]`/`meta_clicked`→`shell_open` both
  called out ✓; the probe readout is fixed (§10.1) ✓.
- Mass assignment — `Object.set()` iteration banned, explicit allowlist ✓.
- **Residual holes**: MAJOR-8 (depth) and MAJOR-9 (unbounded loop from
  `catchup_residual_seconds`). Both are user-controlled content reaching a
  resource bound with no gate.

---

## Assessment

The sim-clock anchor was the right structural call and it does close MAJOR-C,
the missing watermark, and the throttled-hidden-tab over-credit. The §5.3, §3,
§8.5, §8.6-validation-ordering and test-list revisions are correct and I have
closed those findings. The arithmetic in the new material is, with two immaterial
exceptions, right — including the parts I most expected to be hand-waved (the
midpoint-error figures use a consistent rule and reproduce to two digits, and the
payload numbers match the bytes on disk exactly).

What blocks approval is that the new machinery has not been carried all the way
through its own boundaries. Two of the findings are unlimited-money exploits in
the anchor itself (CRITICAL-1, CRITICAL-2), reachable by ordinary play rather than
by attack — the same defect class §7.2 was rewritten to eliminate, relocated into
the fix. Four more (MAJOR-3 through MAJOR-6) are cases where the plan states a
test it cannot pass as specified, which is worse than an untested behaviour
because it converts into tolerance-loosening at Milestone 6 — the exact failure
mode §9.1 correctly diagnosed about the old 1e-9.

None of these is a redesign. CRITICAL-1 and CRITICAL-2 are a watermark-update rule
and a second clock field. MAJOR-3 is an integer index plus a partial first step.
MAJOR-5/6 collapse into one change: make reconciliation a property of catch-up
rather than of the Hidden transition. MAJOR-8 and MAJOR-9 are a pre-scan and a
range check. MAJOR-4 is the only one that is a genuine design decision rather
than a specification repair, and it needs deciding here rather than in §14,
because §14 owes field lists and shell logic, not economic policy.

I have been deliberate about the (a)/(b) line the brief drew. Everything above the
MINOR section is a statement in the document that is **wrong or self-contradictory**,
not a detail the implementation plan could reasonably be left to fill in. The
MINORs are the opposite and should not gate anything.

VERDICT: REVISE — concerns above should be addressed first
