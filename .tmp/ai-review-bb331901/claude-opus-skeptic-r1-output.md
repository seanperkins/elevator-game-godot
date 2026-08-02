# Skeptic Review — Elevator Incremental Design Spec (r1)

Reviewer: Claude Opus Skeptic
Repo root: `/Users/sean/sites/elevator-game-godot`
Plan under review corresponds to `/Users/sean/sites/elevator-game-godot/docs/superpowers/specs/2026-08-01-elevator-incremental-design.md` (327 lines, headings match the submitted text).

---

## 0. Citation grounding (done first)

**Forward-looking citations — absent, correctly so.** The plan's §8.2 layout cites
`sim/`, `data/`, `game/`, `view/`, `ui/`, `tests/` and symbols `game_state`,
`building`, `elevator`, `passenger`, `traffic_spawner`, `tenancy`, `dispatcher`,
`economy`. I checked each directory: all seven are **absent**. The only `.gd` file
in the repo (excluding `.godot/`) is `/Users/sean/sites/elevator-game-godot/main.gd`.
This is a design spec for unwritten code, so absence is expected — **not** a
fabricated-identifier finding. I flag it only so no reviewer mistakes these for
existing modules.

**Backward-looking claims — all verified true.** Every factual claim the plan makes
about the *current* repo checks out:

| Plan claim (§10) | Verified at |
| --- | --- |
| `variant/thread_support=false` | `export_presets.cfg:26` |
| VRAM texture compression off | `export_presets.cfg:27` (desktop), `export_presets.cfg:28` (mobile) |
| 720x1280 base viewport | `project.godot:15`, `project.godot:16` |
| `canvas_items` stretch with `expand` | `project.godot:17`, `project.godot:18` |
| Portrait | `project.godot:19` (`window/handheld/orientation=1`) |
| GL Compatibility renderer | `project.godot:27`, `project.godot:28` |
| Milestone 0 probe exercises render/frame-loop/touch/text/`user://` | `main.gd:26-31` (frame loop), `main.gd:69-74` (touch), `main.gd:88-99` (text), `main.gd:104-123` (`user://` round-trip) |
| wasm payload ~39 MB uncompressed | `build/web/index.wasm` = **39,509,339 bytes** = 39.51 MB decimal |
| CI builds on push to `main`, deploys to Pages | `.github/workflows/deploy.yml:3-6`, `:81-84`, `:86-94` |

No fabricated identifiers. Grounding is clean.

---

## CRITICAL

### C1. The analytic offline model is mathematically incompatible with the time-of-day traffic curve, and §9's offline test cannot pass as written

§5.1 specifies traffic as "a time-of-day curve … morning up-rush from the lobby,
midday churn between middle floors, evening down-rush." §8.5 specifies offline
progress as "computes throughput and rent rates **at save time** and multiplies by
elapsed time with an idle penalty — **the same numbers the live sim produces**,
arrived at in one step."

These cannot both hold. The analytic model evaluates the rate at a single instant
t₀ and integrates it as a constant over [t₀, t₀+Δ]. The live sim integrates a
time-varying rate. The error is:

    error_ratio = r(t₀) / ( (1/Δ) ∫[t₀ → t₀+Δ] r(t) dt )
                = (rate at save time) / (mean rate over the offline window)

Nothing in the plan bounds this ratio. With the offline cap at Δ = 4 h and a
day-cycle rush curve, the save instant lands anywhere on the curve. If peak is
merely 2× the daily mean — a conservative shape for a curve whose entire design
purpose (§5.1) is that "a building that coped yesterday drowns today" — then:

- Save at the rush peak, return 4 h later → paid `4 h × r_peak` = **8 h of mean
  earnings** for 4 h of absence.
- Save at the overnight trough → paid a fraction of what the live sim would give.

The first case is a straightforward exploit: quit at 8:55 am every day. The second
punishes players for closing at the wrong time. Both are invisible to the player
and neither is a balance knob — they are artifacts of the model.

§9 then asserts a test that cannot pass: *"running N ticks live and computing N
ticks analytically must agree within a stated tolerance."* The tolerance is never
stated, and no fixed tolerance exists — the discrepancy is a function of where t₀
falls on the curve and how long Δ is, and it grows without bound as the Automation
branch (§4) raises the offline cap.

**Fix — pick one, and write it into §8.5:**
1. Integrate the curve analytically instead of sampling it. If traffic curves are
   piecewise-linear or a small sum of sinusoids, `∫ r(t) dt` has a closed form; the
   model becomes `∫` over the actual elapsed window, and the §9 test acquires a
   real tolerance (float rounding only, ~1e-9 relative).
2. Coarse-step the model: replay at 1 step per simulated minute rather than per
   tick. 4 h = 240 steps versus 288,000 ticks — a 1200× reduction, cheap enough to
   run at load, and it tracks the curve exactly.
3. Declare offline rate curve-independent by design (a flat "automated rate" that
   deliberately ignores rush hours), and state that §9's test compares against a
   *flat-curve* live run only.

Option 2 is the recommendation: it keeps one code path shaped like the live sim,
makes the §9 test meaningful, and the arithmetic (240 steps) is trivially in budget.

Whichever you pick, §9 must name the numeric tolerance. "Within a stated tolerance"
with no stated tolerance is not a test.

---

## MAJOR

### M1. 20 ticks/s from `_physics_process` does not follow from the current project settings

§8.3: "The sim advances in fixed ticks (20/s) driven from `_physics_process`."

I grepped `/Users/sean/sites/elevator-game-godot/project.godot` for
`physics|autoload|config/version|max_fps|low_processor` — **exit status 1, zero
matches**. There is no `[physics]` section. Godot's default
`physics/common/physics_ticks_per_second` is 60, so `_physics_process` will fire
**60×/s, three times the rate the plan specifies**. Every rate constant tuned
against "20/s" would run 3× fast.

The plan must state which of the two it means:
- Set `physics/common/physics_ticks_per_second=20` in `project.godot` — simplest,
  but it also drops input polling and physics interpolation for the whole game to
  20 Hz, which will be visible in the car-lerp animation on a 60 fps device unless
  the view interpolates between sim states.
- Keep physics at 60 and run a 3:1 accumulator in `game_root`. Preserves render
  smoothness; costs an accumulator and a `while` loop.

Either is fine. Silence is not — this is the kind of thing that gets discovered
after the fare curve is tuned.

### M2. Intra-tick ordering is unspecified, which defeats the stated determinism requirement

§8.3 calls determinism "a requirement, not a nicety," justified by tests asserting
"after 600 ticks with this config, throughput is N." But the plan never specifies
the order of operations *within* a tick. At minimum these five must be ordered:

    spawn → move/door → deliver → expire → accrue rent

The ordering is directly player-visible and directly affects money:

- A passenger whose patience hits exactly 0.0 on the same tick a car opens its
  doors: does it pay a fare and extend the combo streak (§6), or expire, pay
  nothing, drop satisfaction, and break the streak? Deliver-before-expire and
  expire-before-deliver produce different cash *and* different multiplier state.
- Does a passenger spawned on tick T have its patience decremented on tick T
  (patience = P − 1 tick at first observation) or on T+1? Off-by-one on every
  patience budget in the game.
- Rent accrual before or after satisfaction is updated by this tick's deliveries —
  a one-tick lag in every rent number.

A deterministic sim is only reproducible if the order is fixed and written down.
Add an explicit ordered list to §8.3, and add a GUT test that pins the exact-zero
patience boundary in both directions.

### M3. The plan models two states (open / closed); iOS Safari has three

§7: "The sim runs while the window is open. While closed, progress accrues at a
reduced automated rate."

§10 makes the iPhone web build the primary delivery target. On a phone, the
dominant transition is neither of the two modeled states: the user locks the screen
or switches apps, and the tab is **backgrounded but not closed**.

**[HYPOTHESIS — verify on the device before treating as a finding]** Godot's web
main loop is driven by `requestAnimationFrame`, which browsers suspend for hidden
tabs. If that holds, a backgrounded tab neither ticks the live sim nor triggers the
offline path (which §7 implies runs at load). Time spent backgrounded is then
silently worth **zero** — worse than the offline rate the player paid Blueprints to
improve. This is cheap to verify: extend the Milestone 0 probe to log
`Time.get_unix_time_from_system()` deltas across a background/foreground cycle on
the actual iPhone, alongside the still-outstanding Safari confirmation §10 already
owes.

Related and **not** hypothetical: `physics/common/max_physics_steps_per_frame`
(default 8, and confirmed absent from `project.godot` by the grep in M1) clamps
catch-up. At 20 Hz that is 8/20 = **0.4 s of sim time per rendered frame**. Any
stall longer than that is permanently lost from sim time while wall-clock keeps
running — so sim-tick-count and wall-clock diverge, and the offline model (which is
wall-clock based) and the live sim (tick based) disagree by the accumulated drift.

**Fix:** define the third state explicitly. On regaining focus, compute wall-clock
elapsed and route anything over a small threshold (say 5 s) through the same
offline/catch-up path used at load. That also makes the catch-up path exercised
constantly rather than once per session, which is good for finding bugs in it.

### M4. "Save version is checked before parse" is not implementable as written

§8.6: "Versioned JSON in `user://` … Save version is checked before parse; unknown
future versions refuse to load rather than corrupting state."

If the version field lives inside the JSON document, you cannot read it before
parsing the document. As specified this is a contradiction. Two ways out — say
which:
- Store the version outside the payload: a first line, a filename suffix
  (`save.v3.json`), or a sidecar file. Then a pre-parse check is real.
- Parse first, then check the version before *interpreting* — safe with
  `JSON.parse_string`, which cannot execute anything, and honest about ordering.

The second is fine; just fix the sentence, because the current wording implies a
safety property the code will not have.

**And the refusal path has an unhandled boundary:** if a v4 save is refused on a v3
build, what does the player see? The plan doesn't say. The default outcome is a
fresh game — and then §8.6's autosave *timer* fires and **overwrites the v4 save
with a v3 blank**. That is total data loss on any downgrade or Pages rollback,
caused by the very mechanism meant to prevent corruption. Required: on a refused
load, disable autosave for the session and surface a blocking message. Add a test
for it — §9's "migration test per version bump" covers upgrades only.

### M5. Save-on-quit does not exist on the primary platform, and the timer interval is unstated

§8.6: saves are "written on a timer and on quit." On web/iOS there is no reliable
quit notification — a tab evicted by Safari under memory pressure, or killed from
the app switcher, fires nothing. On the primary target, §8.6 degrades to
**timer-only**.

The plan never states the interval, so the worst-case loss window is unspecified.
This is not academic: the save timestamp is also the t₀ input to the offline model
(C1). A stale save means both lost progress *and* an offline window computed from
the wrong instant.

**Fix:** state the interval (30 s is typical), and additionally save on
`NOTIFICATION_APPLICATION_FOCUS_OUT` / visibility change, which *does* fire on
backgrounding, rather than relying on a close event that will not come.

### M6. §9 makes unit tests the seat of correctness; nothing runs them

§9: sim/ is "heavily unit tested with GUT … This is where correctness lives."

Current state:
- `addons/` — **absent**. GUT is not vendored, not a submodule, not installed.
- `tests/` — **absent**.
- `.github/workflows/deploy.yml` — I enumerated every step in the `build` job:
  checkout (`:25`), install Godot + templates (`:27-39`), import (`:44-45`), verify
  templates (`:47-55`), export (`:57-64`), report build shape (`:68-75`), nojekyll
  (`:78-79`), configure-pages (`:81`), upload-pages-artifact (`:82-84`); then the
  `deploy` job (`:86-94`). **There is no test step.** Nothing gates a push to
  `main` on the sim being correct.

A plan whose entire correctness argument rests on a headless test suite needs that
suite in CI before Milestone 1, not after Milestone 7. Add a `test` job running
`godot --headless -s addons/gut/gut_cmdln.gd -gexit`, and make `build` depend on
it. Add the GUT install to §11 as a prerequisite of Milestone 1.

### M7. `export_filter="all_resources"` will ship the test suite and GUT inside the game payload

`export_presets.cfg:9` is `export_filter="all_resources"` and
`export_presets.cfg:11` is `exclude_filter=""`. Adding `tests/` and `addons/gut/`
to the project therefore packs both into the exported `.pck` — test scripts and the
entire GUT addon downloaded by every player.

Current `.pck` is 7,128 bytes, so today this is invisible; GUT plus a real spec
suite is on the order of a megabyte, on top of a payload §10 already calls out as
worth watching.

**Fix:** set `exclude_filter="tests/*,addons/gut/*"` in `export_presets.cfg` at the
same time GUT lands. Cheap now, annoying to notice later.

### M8. "No fail state" is stated as an invariant but has an unhandled zero-boundary

§5.3 asserts "**No fail state.** Bad play means slow progress, never a loss
screen," and §12 records it as a decision taken.

The boundary that breaks it: every floor's satisfaction falls below the move-out
threshold, every tenant departs, and cash is 0. §5.3 says "Vacant floors earn
nothing and **can be re-leased**." If re-leasing costs money, the state
`all floors vacant ∧ cash = 0` is terminal — no income, no way to buy income. That
is a loss state without a loss screen, which is worse than a loss screen.

The plan does not say whether re-leasing costs anything, nor whether passengers
still spawn for vacant floors (if they don't, fares dry up too and the lock is
airtight).

**Fix — state one explicitly in §5.3:** re-leasing the first vacant floor is free;
or a floor's satisfaction floors out above the move-out threshold; or the lobby
floor can never go vacant. Then add a GUT test that drives every tenant out with
zero cash and asserts recovery is reachable.

### M9. The era ladder does not inflate between Walk-Up and Highrise, contradicting §3's premise

§3: "A row always means 'one stop,' but **what a stop *is* inflates each era**."
The table immediately below it gives:

| Era | A row represents | Height at 40 rows (≈3.5 m/floor) | Growth vs prior |
| --- | --- | --- | --- |
| Walk-Up | one floor | ~140 m | — |
| Highrise | **one floor** | ~140 m | **1.0×** |
| Megatower | ~50 floors | 2,000 floors ≈ 7 km | 50× |
| Stratosphere | 1 km | 40 km | 5.7× |
| Orbital Tether | ~80 km | 3,200 km | 80× |

Era 2 inflates the unit by exactly 1.0×. Worse, §3 also says prestige resets the
board ("early Walk-Up starts at 6 rows and expands"), and §12 confirms "prestige
resets height." So entering Highrise takes the player from a 40-floor building back
to a **6-floor** building measured in identical units — era 2 begins strictly
shorter than era 1 ended, in absolute metres, with no compensating change in what a
row means.

The growth sequence 1×, 1×, 50×, 5.7×, 80× is also erratic enough that per-era
Blueprint thresholds (§13) will be hard to make feel continuous.

This is a design consistency issue, not a bug, and it has an easy fix: give
Highrise a unit that inflates (e.g. Highrise row = 3 floors, matching its
sky-lobby/express-shaft mechanic, giving ~420 m and a 3× step), or fold Highrise's
express-shaft mechanic into late Walk-Up and drop it as a separate era. Either way
§3's sentence and §3's table must stop contradicting each other.

---

## MINOR

### N1. "GDScript floats reach ~1e308, comfortably past a five-era game" is an unsupported quantitative claim, and one reading of §6 overflows

§8.5 asserts headroom without estimating the five-era ceiling, so the claim is
currently unverifiable. Meanwhile §6's combo is specified only as "a rising income
multiplier." Take the most natural implementation — multiplicative per delivery
with no cap, step +1%:

    1.01^n = 1e308
    n = 308 × ln(10) / ln(1.01) = 308 × 2.302585 / 0.00995033 = 71,270 deliveries

A single uninterrupted streak of ~71,270 deliveries produces `INF`. Once any
currency is `INF`, every downstream comparison and the sqrt prestige conversion
degrade silently — no crash, no error, just a game that stops making sense. For an
incremental with automation running rush hours unattended, 71,270 consecutive
deliveries is not an exotic scenario.

The point is not that the combo *will* be 1.01-per-delivery; it is that §8.5
declares safety while §6 leaves the curve unstated and §13 doesn't list it. Two
fixes, both cheap: state a hard cap on the combo multiplier in §6, and add
"expected peak magnitude per era" to §13 so the 1e308 claim becomes checkable.

### N2. The number formatter's suffix ladder is understated by 97 entries, and has a classic rounding boundary

§8.5 gives three examples: `12.4K / 8.1M / 2.3aa`. Working out what the ladder must
actually cover, at 1e3 per step with K/M/B/T then two-letter suffixes from `aa`:

    aa = 1e15, so index into the two-letter ladder = (308 − 15) / 3 = 97.67 → 97
    97 = 3×26 + 19 → 'a'+3, 'a'+19 = "dt"

Covering the float range needs **98** two-letter suffixes (`aa` … `dt`), not the
one the spec names. A two-letter ladder supplies 26×26 = 676, so the scheme is
sufficient — but the table has to be generated, not hand-written, and §8.5 should
say so.

**Rounding boundary (test this explicitly):** with one decimal place, 999,950
formats as 999,950/1000 = 999.95 → rounds to **"1000.0K"** instead of "1.0M". Same
bug at every rung: 999.95 → "1000.0", 999,999,950 → "1000.0M". The magnitude
selection must happen *after* rounding, not before.

**Other formatter boundaries with no test named in §9:** 0, values < 1000 (does
`0` render as `"0"` or `"0.0"`?), exactly 1000, negative values (can any displayed
quantity go negative — a debt mechanic, a delta in the welcome-back summary?), and
`INF`/`NAN` (per N1, reachable).

### N3. The sprite worst case is capped per-floor but never computed globally

§8.5 caps individuals at "~12 per floor before collapsing into a crowd bar." With
the §3 board at ~40 rows:

    40 rows × 12 individuals = 480 individual sprites

plus 40 crowd bars, plus car nodes (shaft count unstated), plus per-floor tenant
and satisfaction widgets. So the worst case is ~480–600 pooled nodes, not the
"hundreds of passengers [that] will not survive as individual nodes" the same
paragraph warns about — the cap lands right back in "hundreds."

That is probably fine on GL Compatibility in mobile Safari, but the plan asserts
the cap solves the problem without doing the multiplication. State the number, and
budget it: if 480 `Sprite2D`s at 60 fps in WebGL 2 on the target iPhone is not
verified, the per-floor cap should be a tunable constant with a global ceiling
above it, so it can be lowered without touching layout code.

### N4. The Orbital Tether era has no defined tenancy, which is where all income comes from

§3 gives Orbital Tether "climbers haul cargo, **not people**." But rent is the soft
currency and §5.3 defines income entirely in terms of floors holding tenants with
satisfaction driven by passenger wait times. §5.1's passenger model (origin,
destination, patience, fare) and §2's "passengers who expire **take the stairs**"
both stop making sense at 80 km per row.

Era 5 therefore needs a substitute for tenancy, satisfaction, patience, and the
stairs fallback — four of the game's core systems. §13's "open items" list does not
mention it, so it is currently an unowned gap rather than a deferred decision. Add
it to §13 explicitly (it does not need solving now; it needs owning).

### N5. Determinism across platforms is asserted more broadly than it holds

§8.3: seeded RNG gives "the same answer every run." Integer assertions (throughput
counts, riders served) will hold. Float accumulations — position lerps, satisfaction
decay, compounding cash — can differ in the last bits between the CI Linux x86-64
build and the wasm build in Safari, particularly through transcendental functions.

Not a blocker, and §8.5's "never compare currency with `==`" already points the
right way. Make it explicit in §9: sim tests assert exact equality on integer
counts and use a relative epsilon on floats.

### N6. Prestige at low lifetime earnings can wipe a run for zero Blueprints

§4 converts lifetime earnings to Blueprints via "a square-root family" curve. For
any `BP = floor(sqrt(E)/k)`, all `E < k²` yield **BP = 0** — the player demolishes,
loses the building, cash, and every per-run upgrade, and receives nothing. §5.3
promises no fail state; this is a self-inflicted one, reachable by a new player
pressing the shiny button.

**Fix:** gate the demolish button on `BP ≥ 1`, and show the projected Blueprint
yield before confirming. Add a boundary test at `E = 0` and at `E = k² − 1`.

---

## Consistency sweep — every surface this plan touches

Not reported clean; here is exactly what I checked and its state. All seven paths
below were read or grepped in this session.

| # | File | State today | What this plan requires |
| --- | --- | --- | --- |
| 1 | `/Users/sean/sites/elevator-game-godot/project.godot` | `run/main_scene="res://main.tscn"` (`:9`) points at the Milestone 0 probe. No `[physics]` section, no `[autoload]`, no `config/version` (grep for `physics\|autoload\|config/version\|max_fps\|low_processor` → exit 1). | Repoint `main_scene` at Milestone 1; add tick-rate setting per M1; add autoload if `game_root` is a singleton; add `config/version` to align with save versioning (§8.6). **Plan mentions none of these.** |
| 2 | `main.gd` / `main.tscn` / `main.gd.uid` | The probe. `main.gd` is 123 lines. | §11 Milestone 1 replaces the screen. Plan never says whether the probe is deleted, kept as a debug scene, or converted into a smoke test. Decide — the `user://` check at `main.gd:104-123` is worth keeping somewhere. |
| 3 | `README.md` | "Status — Milestone 0 … The deployed build **is not the game**"; local-run snippet has `godot` and the export command only. | Status line must change at Milestone 1; snippet should gain the GUT test command once M6 is addressed. Not listed in the plan. |
| 4 | `export_presets.cfg` | `export_filter="all_resources"` (`:9`), `exclude_filter=""` (`:11`). | Needs `exclude_filter` per M7. |
| 5 | `.github/workflows/deploy.yml` | 94 lines, `build` + `deploy` jobs, no test step (steps enumerated in M6). | Needs a `test` job that `build` depends on, per M6. |
| 6 | `.gitignore` | Ignores `.godot/`, `.import/`, `export.cfg`, `*.translation`, `.DS_Store`, `build/`; `export_presets.cfg` deliberately tracked with a comment. | `addons/` is not ignored (correct — GUT should be vendored). No entry for GUT run artifacts. Minor. |
| 7 | `docs/superpowers/specs/2026-08-01-elevator-incremental-design.md` | 327 lines; headings match the submitted plan. | The spec itself — every fix above lands here. |

Nothing else in the repo is touched: the only `.gd` file is `main.gd`, and
`sim/`, `data/`, `game/`, `view/`, `ui/`, `tests/`, `addons/` are all absent.

---

## Test coverage — behaviors in this plan with no test that would catch a regression

§9 covers sim broadly, the offline model, and save round-trip/migration. Behaviors
named in the plan that no described test would catch:

1. **Intra-tick ordering** (M2) — no test pins deliver-vs-expire at exactly zero
   patience, or whether tick-T spawns decay on tick T.
2. **Dispatch policies** (§5.4) — four named policies (nearest / look-ahead /
   zoning / predictive); §9 never mentions policy tests. Each needs a fixed-scenario
   test asserting which car is assigned, or a policy regression is undetectable.
3. **Blueprint conversion** (§4, N6) — no test at `E = 0`, at the first
   `BP = 1` threshold, or for the wipe-for-nothing case.
4. **Combo multiplier** (§6, N1) — no test for rise, for decay on a bad delivery,
   or for the cap (which does not exist yet).
5. **Number formatter** (§8.5, N2) — no test named at all. Needs: 0, <1000, exactly
   1000, the 999,950 rounding boundary, the top of the suffix ladder, `INF`.
6. **Offline boundaries** (§7) — no test for `elapsed ≤ 0` (device clock moved
   backwards, or NTP correction, yields negative elapsed × positive rate =
   **negative cash**), for `elapsed` exactly at the cap, or for `elapsed` far beyond
   the cap.
7. **Refused-load path** (M4) — §9's migration tests cover upgrades only; the
   unknown-future-version refusal and its autosave-overwrite hazard are untested.
8. **Move-out recovery / no-fail-state invariant** (M8) — no test drives all
   tenants out at zero cash and asserts recovery is reachable.
9. **Tenant satisfaction floor/ceiling** (§5.3) — satisfaction is "continuous" with
   a threshold; no test at exactly the threshold in either direction.

Items 1, 5, 6, and 8 are the ones I would not ship Milestone 1 without.

---

## Security

**No user-controlled content reaches a shell, query, template, or eval today.**
Here is precisely what I checked:

1. **`.github/workflows/deploy.yml`** — every `run:` block. Shell interpolations are
   `${GODOT_VERSION}` (from `env:` at `:19`, literal `"4.7"`), `$base`, `$HOME`,
   `$dir` — all workflow-local. The only `${{ }}` expression is
   `${{ steps.deployment.outputs.page_url }}` at `:91`, used in `environment.url`,
   **not** in a shell string. No `github.event.*` value reaches any `run:` block, so
   there is no script-injection vector. `permissions:` at `:8-11` is correctly
   scoped (`contents: read`). Clean.
2. **`main.gd`** — `FileAccess.open` on a hardcoded literal path (`main.gd:105`);
   serialization via `JSON.stringify` (`:111`) and `JSON.parse_string` (`:118`).
   No `str_to_var`, no `bytes_to_var`, no `OS.execute`, no `Expression`. Clean.
3. **`project.godot`** — no autoloads, no custom command-line handling.
4. **Repo-wide** — `main.gd` is the only `.gd` file, so there is nothing else to check.

**Three forward-looking surfaces the plan should close before they open:**

- **S1 (the real one). Never load a Godot `Resource` from `user://`.** §8.7 says
  balance data lives in `data/` "as Godot Resources **or** JSON." Resources under
  `res://` are fine — they ship inside the signed `.pck`. But `ResourceLoader.load()`
  on a `user://` path deserializes a `.tres`, which can carry a `script` reference
  and instantiate it. Save files live in `user://` (§8.6), and on web that is
  IndexedDB — trivially editable from Safari's devtools. Write the rule into §8.6:
  **anything under `user://` is parsed with `JSON.parse_string` only**;
  `ResourceLoader.load()` and `str_to_var(..., true)` are never called on a user
  path. Single-player, so the blast radius is self-inflicted — but this is the one
  way a save file becomes code execution, and it costs one sentence to prevent.

- **S2. BBCode is a live template sink.** `main.gd:77` already sets
  `bbcode_enabled = true` on the readout, and today feeds it only engine values
  (`main.gd:90-99`). The game adds strings the player or the save file influences —
  tenant names, the §7 "while you were away" summary, §6 event toasts. Any of those
  interpolated into a bbcode label lets `[img]http://…[/img]` fire a network request
  from a page on `github.io`, and `[url=…]` render a clickable link. Rule for §8.4:
  bbcode labels take only literal author-written markup; all dynamic text goes
  through a plain `Label`, or through `[lb]`-escaping.

- **S3. Don't put formulas in the data files.** §8.7's goal — "tuning does not
  require code changes" — is often implemented by storing cost curves as expression
  strings and running them through Godot's `Expression` class. That is an eval, and
  once `data/` can be reached from a save or a future mod path it is an eval on
  untrusted input. Keep `data/` to numeric coefficients over a fixed set of
  code-defined curve shapes.

None of these is exploitable in the current tree. All three are one sentence in the
spec now versus a rewrite later.

---

## What is good, and should not be relitigated

Stated so the fixes above aren't mistaken for a rejection of the approach:

- **§8.1 (sim knows nothing about the scene tree)** is the right call and is what
  makes the rest of this reviewable at all. Every finding above is testable
  *because* of that rule.
- **§8.3 determinism** as a stated requirement is unusual discipline for an
  incremental and is what makes §13's balancing tractable. M2 strengthens it rather
  than disputing it.
- **§10's threadless-export reasoning** is correct and verified against the repo
  (`export_presets.cfg:26`). The COOP/COEP constraint on Pages is real and the
  workaround is the right one.
- **Milestone 0 existing at all** — proving `user://` persistence on the riskiest
  platform before writing game code is exactly the right order, and `main.gd:104-123`
  does a genuine write-read-compare rather than assuming.
- **§10's payload note is accurate but pessimistic.** Measured:
  `build/web/index.wasm` = 39,509,339 bytes, `gzip -9` = 10,052,184 bytes — a
  **3.93× reduction**. Pages serves gzip, so the actual first-load transfer is
  ~10.05 MB plus `index.js` (279,815 bytes) ≈ **10.3 MB**, not 39 MB. Worth
  correcting in §10, since 10 MB changes "acceptable over wifi" to "acceptable over
  LTE" and moves this well down the worry list.

---

## Summary

| ID | Severity | Issue |
| --- | --- | --- |
| C1 | CRITICAL | Analytic offline model incompatible with time-of-day curves; §9's offline test has no achievable tolerance |
| M1 | MAJOR | 20 ticks/s contradicts the default 60 Hz `_physics_process`; no `[physics]` section in `project.godot` |
| M2 | MAJOR | Intra-tick ordering unspecified, defeating the stated determinism requirement |
| M3 | MAJOR | Backgrounded-tab state unmodeled on the primary (iOS) target; `max_physics_steps_per_frame` drift |
| M4 | MAJOR | "Version checked before parse" not implementable; refused load + autosave timer destroys the newer save |
| M5 | MAJOR | Save-on-quit does not fire on web/iOS; timer interval unstated |
| M6 | MAJOR | GUT absent, `tests/` absent, no test job in CI — §9's correctness argument is unenforced |
| M7 | MAJOR | `export_filter="all_resources"` with empty `exclude_filter` ships tests and GUT to players |
| M8 | MAJOR | "No fail state" invariant breaks at all-vacant ∧ zero-cash |
| M9 | MAJOR | Era ladder does not inflate Walk-Up → Highrise, contradicting §3's own premise |
| N1 | MINOR | 1e308 headroom asserted without an estimate; an uncapped 1% combo overflows at 71,270 deliveries |
| N2 | MINOR | Suffix ladder needs 98 entries, not 1; 999,950 → "1000.0K" rounding boundary |
| N3 | MINOR | Per-floor sprite cap never multiplied out (40 × 12 = 480 nodes) |
| N4 | MINOR | Orbital Tether has no tenancy/satisfaction/patience model, and it isn't in §13 |
| N5 | MINOR | Cross-platform float determinism asserted too broadly |
| N6 | MINOR | Prestige below the first Blueprint threshold wipes a run for zero gain |

C1, M2, M4, M8 and M9 are spec-text changes with no code cost — they are cheapest
now and expensive after Milestone 3. M1, M6 and M7 are single-line config changes
that should land alongside Milestone 1.

VERDICT: REVISE — concerns above should be addressed first
