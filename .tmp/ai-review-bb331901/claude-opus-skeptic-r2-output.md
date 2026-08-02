# Opus Skeptic — Round 2 Re-Review

Plan reviewed: `/Users/sean/sites/elevator-game-godot/.tmp/ai-review-bb331901/plan.md` (631 lines, read in full).
Repo root resolved via `git rev-parse --show-toplevel` → `/Users/sean/sites/elevator-game-godot`.

## 0. Citation grounding

Every repo fact the plan asserts, checked before I reasoned on it. All confirmed:

| Plan claim | Verified against | Result |
| --- | --- | --- |
| `project.godot` has no `[physics]` section | `/Users/sean/sites/elevator-game-godot/project.godot` (29 lines; sections `application`, `display`, `input_devices`, `rendering` only) | CONFIRMED |
| 720x1280, `canvas_items`, `expand`, portrait | `project.godot:15-19` | CONFIRMED |
| GL Compatibility renderer | `project.godot:27-28` | CONFIRMED |
| `variant/thread_support=false` | `export_presets.cfg:26` | CONFIRMED |
| `export_filter="all_resources"` with empty `exclude_filter` | `export_presets.cfg:9,11` | CONFIRMED |
| `progressive_web_app/enabled=false` | `export_presets.cfg:35` | CONFIRMED |
| VRAM compression off, ETC2 ASTC rationale | `export_presets.cfg:27-28,45-48` | CONFIRMED |
| `_test_persistence()` writes before reading, called from `_ready()` | `main.gd:23`, `main.gd:104-123` (`FileAccess.open(path, FileAccess.WRITE)` at `main.gd:107`, read at `main.gd:114`) | CONFIRMED |
| `godot --headless --import \|\| true` | `.github/workflows/deploy.yml:45` | CONFIRMED |
| three `test -f` checks are the only build gate | `deploy.yml:62-64` | CONFIRMED |
| `pages: write` / `id-token: write` at workflow scope | `deploy.yml:8-11` | CONFIRMED |
| Mutable `GODOT_VERSION: "4.7"` release URL, `sudo mv` to `/usr/local/bin`, executed | `deploy.yml:19,30-34` | CONFIRMED |
| Actions unpinned | `deploy.yml:25,81,82,95` (`checkout@v4`, `configure-pages@v5`, `upload-pages-artifact@v3`, `deploy-pages@v4`) | CONFIRMED |
| `export_credentials.cfg` untracked but unignored | `git ls-files` (11 files, not present); `.gitignore` has `export.cfg` not `export_credentials.cfg`; file does not exist on disk | CONFIRMED |
| `index.wasm` = 39,509,339 bytes raw | `build/web/index.wasm` | CONFIRMED exactly |
| gzipped = 10,052,184 bytes | `gzip -9 -c index.wasm \| wc -c` → 10052184 | CONFIRMED exactly |
| The SharedArrayBuffer grep branch is unreachable | `grep -l SharedArrayBuffer build/web/index.js build/web/index.html` → matches `index.js` | CONFIRMED |
| Proposed guard `grep -qx 'variant/thread_support=false' export_presets.cfg` | run against the real file | CONFIRMED — exits 0 |

No fabricated identifiers found. This is a marked improvement over round 1 — every file-level claim in §10.1/§10.2 is grounded.

---

## 1. Round-1 findings: status

**Resolved, acknowledged explicitly:**

- **M1 (tick rate)** — §8.3 now pins physics at Godot's default 60 Hz with a 0.05 s fixed-step accumulator in `game_root`. Correct, and the "would have run 3x fast" diagnosis is right (60/20 = 3). Resolved.
- **M2 (intra-tick ordering)** — §8.3 writes the order down (`spawn → move/doors → deliver → expire → accrue rent → update combo`) and pins the exact-zero-patience tie-break in both directions, with §9 item 1 as the test. Resolved.
- **M4 (version-before-parse)** — §8.6's 6-step sequence is implementable as written. Resolved. (New hole in the *refused-load* half — see MAJOR-F.)
- **M5 (save-on-quit / timer interval)** — 30 s stated in both §7.1 and §8.6, quit demoted to a desktop nicety. Resolved.
- **M6 (GUT / CI test job)** — §10.2 requires a `test` job that `build` depends on, plus vendoring GUT at a tag. Resolved.
- **M7 (export_filter ships tests)** — §10.2 adds `exclude_filter="tests/*,addons/gut/*"`. Resolved.
- **M9 (era ladder does not inflate)** — Highrise is now 4 floors/row. Full ladder arithmetic re-derived below and every figure is exact. Resolved.
- **N1 (combo overflow)** — hard cap added, and the bound is right: `308·ln10/ln1.01 = 71,273.63`, so "about 71,270" is accurate. (For the record the true float64 bound is `log10(1.7977e308)·ln10/ln1.01 = 71,332.6`; the plan's figure is the conservative one, which is the correct direction.) Resolved.
- **N2 (suffix ladder / 999,950)** — **98 is exactly right**: entries at `10^(15+3n)` for n = 0…97 top out at `10^306`, and n = 98 would be `10^309` > `1.7977e308`. And the rounding-order claim checks out: `999950/1000 = 999.95` → rounds to `1000.0` → `"1000.0K"` under naive ordering, `"1.0M"` when magnitude is selected after rounding. Resolved.
- **N5 (cross-platform float determinism)** — §9 now specifies exact equality on integer counts, relative epsilon on floats, with the CI-Linux-vs-Safari-wasm rationale. Resolved.
- **N6 (prestige below the first BP threshold)** — §4 gates demolish on yielding ≥1 BP with projected yield shown; §9 item 7 tests `E = 0` and the first `BP = 1` threshold. Resolved.

**Not resolved:** C1 (see below). **Partially resolved:** M3, M8, N3, N4.

---

## 2. Arithmetic checks on the new material

All computed, not eyeballed.

**§3 era ladder — every figure exact.**

| Era | unit (m) | 40 rows | stated | growth | stated |
| --- | --- | --- | --- | --- | --- |
| Walk-Up | 3.5 | 140.0 m | ~140 m ✓ | — | — |
| Highrise | 14.0 | 560.0 m | ~560 m ✓ | 4.000 | 4x ✓ |
| Megatower | 175.0 | 7,000 m | ~7 km ✓ | 12.500 | 12.5x ✓ |
| Stratosphere | 1,000 | 40,000 m | 40 km ✓ | 5.714 | 5.7x ✓ |
| Orbital Tether | 80,000 | 3,200,000 m | 3,200 km ✓ | 80.000 | 80x ✓ |

Cumulative 3.5 → 80,000 m = 22,857.14x, and `4 × 12.5 × 5.7143 × 80 = 22,857.14`. Internally consistent.

**§7.2 coarse-step count — exact.** 4 h = 240 min = 240 steps. 4 × 3600 × 20 = 288,000 ticks. 288,000 / 240 = **exactly 1200**. "~1200x" is correct.

**§8.5 combo overflow — correct** (above).

**§10 payload — the two hard figures are exact, the derived one drifts slightly.** See MINOR-b.

---

## CRITICAL

### C1 (UNRESOLVED, restated in new form) — §9's 1e-9 relative tolerance is still unachievable; the coarse-step rewrite did not make it achievable

§9 now says: "N minutes coarse-stepped must match N minutes lived, to a **relative tolerance of 1e-9** (float rounding only). This is a real bound because both paths integrate the same curve."

It is not a real bound, for two independent reasons, either of which alone kills it.

**(a) The two paths use step sizes 1200x apart, so they are different quadrature rules, not the same computation.** 1e-9 relative is float64-rounding territory; it is only reachable when two computations are *algebraically identical*. Live sim h = 0.05 s; catch-up h = 60 s. Discretisation error for a rate curve r(t) with characteristic angular frequency ω:

| curve feature | ω (rad/s) | midpoint rule, `(h²/24)·ω²` | left-endpoint/Euler, `(h/2)·ω` |
| --- | --- | --- | --- |
| daily sinusoid, period 86,400 s | 7.27e-5 | **7.9e-7** | 2.2e-3 |
| rush ramp, period 1,800 s | 3.49e-3 | **1.8e-3** | 1.0e-1 |
| rush ramp, period 600 s | 1.05e-2 | **1.6e-2** | 3.1e-1 |

The *smoothest curve the design could possibly have* — a pure daily sinusoid, integrated with the *best* one-point rule — misses 1e-9 by a factor of **~800**. §5.1 explicitly promises sharper features than that ("morning up-rush… midday churn… evening down-rush"), which puts the realistic figure at 1.8e-3 to 1.6e-2 — six to seven orders of magnitude outside the stated tolerance.

**(b) The live sim is stochastic; the catch-up model cannot be.** §8.3 makes "a seeded RNG for spawns" a hard requirement. The live path consumes RNG draws at tick granularity (288,000 ticks per 4 h); the coarse path has 240 steps. The two consume the sequence at different rates, so the draws diverge on step 1 and never re-converge — you cannot construct a seed that makes them agree. Even granting perfectly matched expectations, the realised count over the window has relative standard deviation `1/√N`:

| N passengers in window | relative sd |
| --- | --- |
| 1e3 | 3.2e-2 |
| 1e5 | 3.2e-3 |
| 1e7 | 3.2e-4 |

At an absurdly generous 10 million passengers the intrinsic spread is still **3.2e-4**, five and a half orders of magnitude looser than 1e-9.

**(c) And the quantity being compared isn't even the same quantity.** Live earnings depend on delivery, which depends on car position, capacity, and door dwell (§5.2). §7.2's catch-up uses "capacity as a throughput ceiling" — a different model. Asserting float-epsilon agreement between a discrete-event dispatch simulation and a throughput-ceiling integral is a category error, not a tight tolerance.

The round-1 diagnosis was "no fixed tolerance survives a rush-hour boundary." The rewrite fixed the *exploit* (correctly and well — see below) but carried the unachievable tolerance forward verbatim. As written, §9's headline sim test cannot be made to pass, and a team implementing this will discover it at Milestone 6.

**What is genuinely fixed and should be kept:** the exploit analysis is right. `r(t₀)/mean(r)` is unbounded, and a 2x peak really does pay 8 h of mean earnings for a 4 h absence at the peak. Curve integration is the correct fix. The problem is only the tolerance claim attached to it.

**Recommended fix — pick one and state which:**

1. **Make the paths algebraically identical for one measurable quantity.** Define the traffic curve in `data/` as piecewise-constant on 1-simulated-minute buckets (it is data anyway, §8.7) and have the live spawner read `curve[floor(sim_minute)]`. Then `∫r dt` over any whole number of minutes is the *same finite sum* in both paths, and 1e-9 becomes a legitimate bound — **but only on expected spawn count / integrated rate, not on realised earnings.** Test that quantity at 1e-9; that is a real, valuable regression guard.
2. **Give the end-to-end comparison a design budget, not a float budget.** e.g. "catch-up earnings over any 4 h window are within 5% of the mean of 100 seeded live runs," plus the property that actually matters: `max over t₀ of (catch-up / lived) ≤ 1.0 + δ` — a *no-exploit* test, which is what round 1 was really about. A ratio bound is checkable and is the thing that protects the economy.
3. Do both. (1) catches integrator regressions; (2) catches economy regressions.

---

## MAJOR

### MAJOR-A — §3's "era N+1 begins shorter than era N ended" is false for half the ladder, and impossible for Orbital Tether at *any* row count

§3: "each era starts at 6 rows and expands as the player buys floors. Because prestige resets row count, era N+1 begins shorter in absolute metres than era N ended."

At 6 starting rows:

| transition | era N ended (40 rows) | era N+1 starts (6 rows) | claim |
| --- | --- | --- | --- |
| Walk-Up → Highrise | 140 m | 84 m | holds |
| Highrise → Megatower | 560 m | **1,050 m** | **VIOLATED (1.9x)** |
| Megatower → Stratosphere | 7,000 m | 6,000 m | holds (barely, 0.86x) |
| Stratosphere → Orbital | 40,000 m | **480,000 m** | **VIOLATED (12x)** |

The invariant holds iff growth factor < 40/6 = 6.667. Growth factors are 4, 12.5, 5.71, 80 — it fails for exactly the two eras above that line.

Worse, it is not tunable away for era 5. The maximum starting row count that satisfies it is `40 × 1000 / 80000 = 0.5 rows`. **Even a 1-row starting board (80 km) exceeds the 40-row Stratosphere ceiling (40 km).** No integer row count ≥ 1 can satisfy the claim.

This is not pedantry: §12 records "prestige resets height rather than scrolling or zone-collapsing the view" as a *decision*, and §3 offers this invariant as the reason the reset reads as a reset. In Megatower and Orbital Tether the demolish makes the building immediately **taller** in absolute metres, so the stated rationale is inverted precisely where the growth factors are largest.

**Fix:** delete the invariant and replace it with the true one — "the *board* always resets to 6 of 40 rows; absolute height is not monotone across the ladder, and the Megatower and Orbital Tether transitions raise absolute height on entry." Then say what carries the felt reset instead (row count, cash, upgrades). If the invariant is actually wanted, the growth factors have to change, and §3 already declares them "deliberately uneven."

### MAJOR-B — §7.2 does not specify what happens to the sub-minute remainder, and §7.1 makes that the common case

§7.2 coarse-steps "at one step per simulated minute" and clamps `elapsed = clampf(now - saved_at, 0.0, offline_cap)`. It never says what happens to `elapsed mod 60`.

§7.1 makes this load-bearing: "the catch-up model runs many times a day rather than once per session." A phone user backgrounds and foregrounds constantly, so most catch-up invocations have `elapsed` well under one minute.

Both truncation policies are broken:

- **Truncate** (`floor(elapsed/60)` steps, remainder discarded): a player who checks another app for 45 s earns **zero**. Do that 40 times a day and up to 30 minutes/day vanishes. A player who app-switches every 30 s earns nothing, forever.
- **Round up / always run ≥1 step**: press home, immediately reopen — free minute. Repeat. This is a *new* free-money exploit, structurally identical to the quit-at-rush-peak exploit §7.2 was rewritten to kill, and cheaper to execute.

**Fix:** carry the residual. Persist `catchup_residual_seconds` in the save (§8.6 already persists the *live* fractional-tick accumulator — this is the offline analogue and its absence is conspicuous next to it). On resume: `total = residual + elapsed`; run `floor(total/60)` steps; store `total mod 60` back. This is exactly-conservative in both directions and makes the "background 120 times at 29 s" case equal the "one 58-minute absence" case, which should be §9's test.

### MAJOR-C — §8.3's "surrendered to the catch-up model" has no defined input; §7.2 accepts only `now - saved_at`

§8.3: "The accumulator is clamped to a maximum catch-up per frame; time beyond that clamp is surrendered to the catch-up model (§7.2) rather than spiral-stepped. Wall-clock is authoritative for earnings… Where they disagree after a stall, the catch-up model reconciles."

§7.2's only entry point is `elapsed = clampf(now - saved_at, 0.0, offline_cap)`. A mid-session frame hitch has **no `saved_at`** — nothing was saved, the session never left Active. So the surrender in §8.3 is unimplementable against the interface §7.2 defines. "Reconciles" is doing all the work and is undefined.

This also creates a double-credit path on any platform where hidden ≠ stopped. Desktop Chrome throttles hidden tabs to ~1 Hz rather than zero. Suppose the per-frame accumulator clamp is 0.25 s and a tab sits hidden for 1 hour before §7.1's hidden flag is honoured (or if the flag only stops *spawning* and not *ticking*): 3,600 throttled frames × 0.25 s = **900 s = 15 min of live sim executed while hidden**, while `saved_at` was stamped at hide time so resume pays a **full 60 min** of catch-up. Total credited: 75 min for 60 min elapsed — a repeatable **25% over-credit** triggered by hiding a desktop tab.

**Fix — one line, and it removes both problems:** anchor the catch-up window on the **sim clock**, not on the save timestamp. Maintain `sim_wall_time` advanced only by *executed* ticks (`ticks_executed × 0.05`). Then everywhere — resume, cold start, post-hitch — `elapsed = clampf(now - sim_wall_time, 0.0, offline_cap)`, and `saved_at` becomes a diagnostic field rather than an economic input. Time is then credited exactly once by construction, whether it was lived, throttled, hidden, or hitched. §7.2's rule and §8.3's surrender become the same mechanism instead of two that don't meet.

### MAJOR-D — §5.3's two no-fail rules contradict each other; rule 2 is dead and §9 test 4 is unwritable

§5.3:
> - The lobby row can never go vacant, so fares never dry up completely.
> - Re-leasing a vacant row is free when the player holds no other tenanted row.

If the lobby can never go vacant, the player *always* holds a tenanted row. So the guard on rule 2 — "holds no other tenanted row" — is **never satisfied**, and the free re-lease never fires. Rule 2 is unreachable code given rule 1.

§9 item 4 then asks for a test that cannot be set up: *"drive every tenant out at zero cash, assert recovery is reachable."* Rule 1 forbids driving every tenant out. The named must-have test contradicts the rule it is meant to verify.

The text is also ambiguous on whether "no *other* tenanted row" means "other than the row being re-leased" or "other than the lobby" — under the first reading rule 2 is dead, under the second it is live but unstated.

**Fix:** pick one mechanism, not two. Either (a) rule 1 alone — lobby is permanently tenanted, and §9 item 4 becomes "drive out every *non-lobby* tenant at zero cash; assert lobby fares alone fund a re-lease within N minutes" (which needs a stated bound on N, or the guarantee is only asymptotic); or (b) rule 2 alone — any row may vacate, and re-leasing is free whenever zero rows are tenanted, which makes §9 item 4 exactly writable as stated. (b) is the cleaner guarantee and the one that survives era 5 (see MINOR-d).

### MAJOR-E — §8.6 step 4 calls `is_finite()` without a prior type check, and the import path has no size or depth bound

Step 4: "Validate: every numeric field `is_finite()`…"

Two holes, both on the path the section itself declares untrusted:

1. **No type gate before the finiteness gate.** `is_finite()` takes a float. A save containing `{"cash": "1000"}` or `{"cash": {}}` — trivially produced by devtools or a pasted import string — hits `is_finite()` with a non-numeric Variant and raises at runtime. The result is a **crash during validation**, which happens at step 4, i.e. *before* the step-6 construct and before the refused-load protection engages. The protection that §8.6 correctly added (backup + disable autosave) never runs, because the validator died first. Order matters: `typeof(v) in [TYPE_FLOAT, TYPE_INT]` must precede `is_finite(v)`, and a type mismatch must be a *rejection*, routed through the same refusal path as a bad version.

   Note the `is_finite()` rule is otherwise well-motivated and should stay: JSON has no `Infinity` literal, but `1e400` is *syntactically valid JSON* and Godot's parser yields `INF` for it. So the attack is real and `is_finite()` is the right defence — it just needs to be reachable.

2. **No bound on the decoded input.** §7.3 adds "manual save export/import as a copyable string," and §8.6 acknowledges "an export/import string feature would make another player's file remote input." Neither section bounds length or nesting depth. `JSON.parse_string` on a 200 MB pasted string is a memory kill on a phone whose wasm heap is already the §10 risk; Godot's JSON parser is recursive-descent, so `[[[[…]]]]` at 100k depth is a stack overflow. Neither is caught by any of the three stated rules (JSON-only, no `str_to_var`, no `ResourceLoader.load`) — those all defend against *code execution*, correctly, but say nothing about *resource exhaustion*.

   **Fix:** reject before parse if `len(text) > SAVE_MAX_BYTES` (1 MiB is generous for this schema); after parse, walk the document by explicit known-key traversal rather than generic recursion, so unexpected depth is structurally unreachable.

### MAJOR-F — "A refused load disables autosave" leaves the §7.1 write paths open, which are the ones that fire first

§8.6: "**A refused load disables autosave for that session** and surfaces a blocking message." §8.6 also enumerates three write triggers: "a 30-second timer, on visibility-hidden, and on focus-out (§7.1)."

"Autosave" naturally reads as *the timer*. But the very next thing a confused player does when a blocking error appears is switch apps to look it up — firing `visibilitychange → hidden`, whose §7.1 behaviour is "**Save immediately**". That save destroys the newer file within *seconds*, well before the 30 s timer would have. The M4 fix is defeated by the M3/M5 fix.

Note the asymmetry that makes this sharp: §7.1's hidden-save is specified as unconditional and immediate; §8.6's disable is specified against a term that doesn't obviously cover it.

**Fix:** state it as a single latch, not a property of one timer. "A refused load sets `writes_disabled` for the session. Every write path — timer, visibility-hidden, focus-out, quit, and manual save — checks it. Only an explicit user action ('discard the unreadable save and start fresh', with the backup path shown) clears it." Also worth stating: the blocking message should name the backup file path, since on web the player cannot browse `user://`.

### MAJOR-G — §2.1 makes the most common dispatch gesture unreachable

§2.1 defines dispatch as "Press anywhere on a shaft column… Drag up or down to pick a floor; release to dispatch," and surge as "press and release **without crossing the drag threshold**." The rail's label "follows the thumb," so the initial detent is the row you pressed.

Therefore: **press on row R and release without moving = surge, not dispatch to R.** Sending a car to the row your thumb is already on — the single most natural dispatch, "there's a passenger *there*" — requires dragging off row R and back onto it, on a board where §2.1 itself measures rows at 32 units. That is the fiddliest gesture on the board assigned to the most frequent intent.

The round-1 fix correctly killed cadence-based disambiguation. But gesture-based disambiguation has its own degenerate case and §2.1 does not address it.

**Fix (spec-level, cheap):** anchor the rail's initial detent at the **car's current row**, not the press row. Then "release in place" is a dispatch to where the car already is — a genuine no-op — and classifying it as surge is free of ambiguity, while dispatching to the pressed row is always a real drag. State this explicitly; it is the difference between a coherent model and a bug report at Milestone 1.

### MAJOR-H — §2.1's 44 pt rule caps shaft count at ~7, but shafts are an unbounded repeatable purchase everywhere else

§2.1: "The touch target is always the shaft column — full board height, **at least 44 pt wide**."

With `canvas_items` + `expand` at a 720x1280 base (verified `project.godot:15-18`), Godot scales by `min(w/720, h/1280)` and widens the other axis:

| device (CSS px) | scale | 1 pt in base units | visible width | 44 pt | max columns |
| --- | --- | --- | --- | --- | --- |
| iPhone 15 (393x659) | 0.5148 | 1.942 | 763 u | 85.5 u | **8.93** |
| iPhone SE (375x553) | 0.4320 | 2.315 | 868 u | 101.8 u | **8.52** |
| iPad (820x1080) | 0.8438 | 1.185 | 972 u | 52.1 u | 18.64 |

So **8 columns edge-to-edge on iPhone, and 6–7 once a floor-label gutter and screen margins exist.** Meanwhile §2 step 4 says "Rent buys shafts," §4's Structure branch buys "starting shafts," §5.4's zoning has "cars claim row ranges," and §6's express shafts "assign a shaft to a row range" — none of which reads like a system with a ceiling of six.

This is a *new* constraint created by the §2.1 fix, and it is a real design input, not a nit: a 40-row board with 6 shafts and range-zoning is a very different game from one with 20.

**Fix:** state the shaft ceiling in §3 alongside the 40-row ceiling — it is the same kind of UI constant. Then either accept ~6–8 and make later shaft purchases upgrade *cars per shaft* instead (which the express/zoning mechanics support fine), or state the escape hatch (columns narrow below 44 pt past N shafts and drag capture compensates) and own the HIG deviation deliberately rather than by accident.

### MAJOR-I — §8.5's ~600-node worst case assumes one node per passenger, contradicting §2

§8.5: "Worst case is `40 rows x 12 = 480` individual sprites, plus 40 crowd bars, car nodes, and per-row tenant widgets — call it ~600 pooled nodes."

The multiplication `40 × 12 = 480` is correct, and it is good that it is finally multiplied out (round-1 N3). But §2 describes a passenger as "sprites standing on floors **with a destination bubble and a draining patience meter**" — three visual elements, and §5.1 adds that patience is "a colour ramp from green to red," i.e. the meter is a real node with a modulated style, not a texture swap on the body.

Recount at 2–3 nodes per passenger:

| component | count |
| --- | --- |
| passengers (480 × 3: body, bubble, meter) | 1,440 |
| crowd bars (40 × 2: bar + count label) | 80 |
| tenant widgets (40 × 3: name, rent, satisfaction) | 120 |
| cars (unbounded — at 8 shafts × 2 cars × 2 nodes) | 32 |
| **total** | **~1,672** |

At a conservative 2 nodes/passenger it is still ~1,190. Either way the estimate is **2–2.8x** the stated figure, and "that is still 'hundreds'" becomes "that is thousands" — which is exactly the threshold where Godot's Control-node layout cost on GL Compatibility in mobile Safari stops being free.

Second gap: **car count is unbounded**. There is no maximum shaft count anywhere in the plan (see MAJOR-H), so "car nodes" is not a bounded term in a worst-case calculation. A worst case with a free variable in it is not a worst case.

**Fix:** recount with an explicit nodes-per-passenger constant, state the shaft/car ceiling, and carry the *node* budget (not the sprite budget) into the "measured on the target iPhone before Milestone 3" check. The mitigation §8.5 already proposes — global ceiling above the per-row cap — is right; it just needs to be sized against the real number.

### MAJOR-J — §7.1 depends on `visibilitychange`, which GDScript does not surface; the mechanism is unspecified

§7.1's entire three-state design keys on `visibilitychange` (both edges), and §7.3 and §8.6 both hang off it. §8.2 lists `game/lifecycle (visibility/focus)` as the module.

But `visibilitychange` is a DOM event with no GDScript equivalent. Godot surfaces `NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_WM_WINDOW_FOCUS_OUT`, which are *blur*, not *visibility* — and on iOS Safari those two diverge exactly where it matters (locking the phone reliably fires `visibilitychange`; blur behaviour is inconsistent). Reaching the real event requires `JavaScriptBridge.get_interface("document")` plus `JavaScriptBridge.create_callback`, which exists only in web builds and needs an `OS.has_feature("web")` guard with a notification-based desktop fallback.

The round-1 M3 fix rests entirely on an event the plan never says how to obtain. Given §7.1 is the most load-bearing new section and §10.1's exit criteria include "Background/foreground cycle logs a sane wall-clock delta (validates §7.1)," the mechanism belongs in the plan.

**Fix:** one paragraph in §7.1 or §8.2 naming `JavaScriptBridge` + `create_callback` for web, `NOTIFICATION_APPLICATION_FOCUS_OUT` as the desktop fallback, and the platform guard. Also state the reentrancy rule: a JS callback fires **outside** the Godot main loop, so it must set a flag consumed at the top of the next `_physics_process`, never mutate sim state inline. (HYPOTHESIS on the precise reentrancy hazard — I have not verified Godot 4.7's callback dispatch point — but the flag-and-consume pattern is free and removes the question.)

### MAJOR-K — Test coverage gaps in exactly the sections the revision rewrote

§9's nine named tests are a real improvement and each maps to a claim in the body — I checked all nine cross-references and they land (§5.3→4, §6→8, §8.3→1, §8.5→2, §8.6→5, §4→7, §7.2→3, §5.4→6, §5.3→9). But the revision's largest new surfaces have none:

1. **§2.1's gesture classifier — zero coverage.** §9 dismisses input as "View and UI — thin by construction; smoke tests and manual play." That was defensible when input was "tap a car." It is not defensible now: §2.1 is a *state machine over a point stream* (press → threshold → detent quantisation → in/out-of-column → release) and it is pure logic, headlessly testable without a scene tree, exactly like `sim/`. It also has three named boundaries (drag threshold, column edge, release row) and a documented degenerate case (MAJOR-G). This is the single largest untested surface in the plan.
2. **§8.6 atomic single-flight write — untested.** "A save in progress blocks a second save rather than interleaving" and "a crash mid-write leaves the previous save intact" are both assertable (inject a failure between temp-write and replace; assert the live save is byte-identical to before).
3. **The hostile-save rejection matrix.** §9 item 5 covers *version* refusal only. Given §8.6 declares the save untrusted, the security test is the matrix: wrong type per field, `1e400`, negative counts, counts above the era's legal range, unknown string ids, oversized input, deep nesting. Without it, MAJOR-E ships silently.
4. **§7.1 path equivalence.** "Resumed and Cold start share one code path" is stated as a design property with no test. Assert `hidden for N then resumed == cold start after N` for several N including 0, sub-minute, at the cap, and beyond.
5. **§7.2 remainder conservation** (MAJOR-B): 120 × 29 s resumes == one 58 min absence.
6. **Cross-reference failure:** §7.3 promises "Treat 'no save found' as a normal, **tested** startup path" — §9's list has no such item. Either add it or drop the word.

---

## MINOR

**MINOR-a — §10.2 says 8 `SharedArrayBuffer` occurrences; the actual count is 9.**
Measured: `grep -o 'SharedArrayBuffer' build/web/index.js | wc -l` → **9**; `index.html` → 0; both audio worklets → 0. The load-bearing claim is unaffected and verified correct: `grep -l "SharedArrayBuffer" build/web/*.js build/web/*.html` matches `index.js`, so `deploy.yml:73`'s `|| echo "none (good: threadless)"` branch is genuinely unreachable. I also ran the proposed replacement guard against the real file and it **exits 0** — `export_presets.cfg:26` is exactly `variant/thread_support=false` with no leading whitespace, so `grep -qx` matches. Correct as written. Just fix "8" to "9", or write "several" and stop being falsifiable on a number that changes with every template bump.

**MINOR-b — the payload figure quotes `gzip -9`, which is not what Pages serves.**
Verified exactly: raw 39,509,339 ✓, `gzip -9` 10,052,184 ✓ — both dead-on. But GitHub Pages fronts with Fastly, which compresses at a default level, not `-9`. Measured `gzip -6`: wasm 10,111,664, js 68,747. Full transfer accounting:

| | gzip -9 | gzip -6 |
| --- | --- | --- |
| index.wasm | 10,052,184 | 10,111,664 |
| index.js | 68,479 | 68,747 |
| pck + html + pngs + worklets | 49,681 | 49,681 |
| **total** | **10.17 MB** | **10.23 MB** |

"~10.3 MB" is a 0.7% over-estimate against the realistic case — conservative, so no action needed on the conclusion. Worth a parenthetical that 10,052,184 is the `-9` floor and the served figure is ~10.11 MB, so nobody re-derives it later and thinks the number moved.

**MINOR-c — §2.1 conflates viewport units with pt, understating its own case.**
"at the §3 board ceiling a row is roughly 32 px in a 1280-unit-tall viewport, well under Apple's ~44 pt touch-target floor." 1280/40 = **32.0 units** exactly ✓. But 32 *units* is 32 × 0.5148 = **16.5 pt** on an iPhone 15 and **13.8 pt** on an SE — the row is 2.7–3.2x under the floor, not 1.4x. The conclusion is right and the real numbers make it stronger; the comparison as written is unit-inconsistent. (Also: 1280 units assumes the whole viewport is board, with no HUD — §8.2 has `ui/hud`. With a 200-unit HUD a row is 27 units = 13.9 pt.)

**MINOR-d — the no-fail guarantee has no era-5 mechanism, and §13 does not list it.**
§12 records "runs never fail — guaranteed by §5.3's two rules" without qualification. §5.3's rules are both *tenancy* rules. §13 correctly owns that Orbital Tether has no tenants and that "tenancy, satisfaction, patience, and the stairs fallback — four core systems — need substitutes in era 5." The no-fail guarantee is a **fifth** casualty and is not on the list — the lobby-never-vacates rule is vacuous where there are no tenants. Add it to §13's sentence so it isn't discovered at Milestone 7 alongside the others.

**MINOR-e — §8.2 module sweep is not clean.** I checked every system named in §5, §6, §7 against the §8.2 tree. Present and correct: `catch_up` (§7.2) ✓, `floor_selector` (§2.1) ✓, `lifecycle` (§7.1) ✓, `number_format` under `game/util/` (§8.5) ✓, `dispatcher` (§5.4) ✓, `tenancy` (§5.3) ✓, `traffic_spawner` (§5.1) ✓, `elevator` (§5.2) ✓, `prestige_panel` (§4) ✓, `event_toast` (§6) ✓, `tests/` (§9) ✓. **Absent:** the smooth-operation combo (§6 — a capped multiplier with its own §9 test and its own overflow analysis, with no sim home; presumably `economy`), prestige/Blueprint conversion (§4, Milestone 5 — `ui/prestige_panel` exists but no sim counterpart), and staff / freight / events / power budget (§6, Milestone 7). Save/export-import string (§7.3) and the Add-to-Home-Screen prompt (§7.3) also have no home. Most of these are late-milestone and the tree is honestly a Milestone-1–6 tree; combo and prestige are the two that belong now, since both carry named §9 tests.

**MINOR-f — §10.1's own instruction routes save content into a bbcode sink, violating §8.4.**
§8.4's rule is right and well-argued: "BBCode labels take only author-written literal markup… Any dynamic text… goes through a plain `Label` or is `[lb]`-escaped." But `main.gd:76-79` creates a `RichTextLabel` with `bbcode_enabled = true` and feeds it `_readout_text()` (`main.gd:88-99`), and §10.1 instructs: "**Display the previous session's tap count** and a `restored: yes/no` line." That value comes from `JSON.parse_string` of `user://pipeline_check.save` (`main.gd:118`) — a file editable from Safari devtools. §11 keeps the probe as a permanent debug scene. So the first edit the plan asks for is the first violation of §8.4, in a scene that ships. Current risk is nil (`%d` on a String errors rather than renders), but the fix is to set `bbcode_enabled = false` — the readout uses no markup at all — and to say so in §10.1 so the rule is applied where it is first needed.

**MINOR-g — the proposed CI guard matches any preset.** `grep -qx 'variant/thread_support=false' export_presets.cfg` passes if *any* `[preset.N.options]` block has it. There is one preset today (`export_presets.cfg:1`), so it is correct now; if a debug or desktop preset lands it silently stops asserting anything about the Web preset. Minor hardening: assert the count, or parse the Web preset's block.

**MINOR-h — §8.6 has no rule for a version *below* the migration floor.** Step 3 checks version, §9 item 5 tests "unknown *future* version refuses." A version older than the oldest migration (or a `version` key that is absent, or non-integer) has no stated outcome. Old-save-too-old should route through the same refuse-and-backup path, and it deserves a line since it is the case that actually happens in a long-lived idle game.

**MINOR-i — the committed spec is still the pre-review version.** `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md` is 327 lines; `plan.md` is 631. Not a defect in the plan, but the revision has to land in the repo or Milestone 1 will be built against the old document.

**MINOR-j (HYPOTHESIS — ergonomic, needs the §10.1 device check)** — §2.1's "Dragging outside the column cancels" sets the horizontal cancel tolerance to **half the minimum target width**: a 44 pt column means ±22 pt from centre. A vertical thumb drag traces an arc and routinely deviates more than that over a full-column travel. If this bears out on device, the primary verb self-cancels. Cheap insurance regardless: capture the pointer on drag-start and ignore horizontal position until release, with cancel expressed as a deliberate gesture (drag past the top/bottom of the board, or onto an explicit cancel affordance). §10.1 already lists "Touch registers, including a drag gesture along a column" — worth extending that criterion to "a full-height drag along a column does not cancel."

---

## Security sweep (does user-controlled content reach a shell string, query, template, or eval?)

Enumerated, file by file and sink by sink:

| sink | status |
| --- | --- |
| **eval — `Expression`** | §8.7 bans expression strings in `data/`, coefficients only over code-defined curve shapes. **Correct and adopted.** |
| **eval — `str_to_var` / `bytes_to_var(…, true)`** | §8.6 bans both, with the right reason (Variant parser can construct an `Object`; `script` property = ACE). **Correct and adopted.** |
| **eval — `load()` / `ResourceLoader.load()` on `user://`** | §8.6 bans it, including paths *derived from* save content. **Correct and adopted** — the derived-path clause is the part most specs miss. |
| **template — BBCode** | §8.4's rule is correct (`[img]` = network request, `[url=]` = clickable link). One live violation at `main.gd:76-79` + §10.1 — MINOR-f. |
| **shell — CI** | `deploy.yml` interpolates only `${{ env.GODOT_VERSION }}` (`deploy.yml:19`) and `${{ steps.deployment.outputs.page_url }}` (`deploy.yml:91`). No `github.event.*` reaches a `run:` block. **No injection surface today.** The supply-chain items §10.2 raises (mutable URL, no SHA verification, `sudo mv`, workflow-scope `id-token: write` reaching the build job) are all confirmed against the file and correctly diagnosed. |
| **resource exhaustion — save parse** | **Not covered.** MAJOR-E(2). |
| **type confusion — save validation** | **Not covered.** MAJOR-E(1). |
| **query** | No database, no query sink. N/A. |

The code-execution surface is well covered — genuinely so; the three §8.6 rules close the routes that matter in Godot. The gap is entirely on the *availability* and *type-safety* side of the same untrusted input.

---

## Summary

The revision is substantial and mostly right. Nine of ten round-1 MAJORs are properly closed, five of six MINORs are closed with correct arithmetic, and the two hardest fixes — curve-integrating catch-up and the three-state lifecycle — are the right designs. Every era-ladder figure, the 1200x step reduction, the 71,270 combo bound, the 98-entry suffix ladder, and both hard payload numbers check out exactly.

What blocks approval is that C1 was answered with a better *model* but the same unachievable *tolerance*, and that the three largest new sections each introduce a defect of their own: §7.2 drops the sub-minute remainder, §8.3's surrender has no interface into §7.2, and §5.3's two no-fail rules cancel each other out along with their own test. MAJOR-C's fix (anchor catch-up on the sim clock, not `saved_at`) resolves two findings at once and is one line of spec.

VERDICT: REVISE — concerns above should be addressed first
