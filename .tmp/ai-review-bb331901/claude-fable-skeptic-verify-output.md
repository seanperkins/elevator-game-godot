# Skeptic verification pass — claude-fable-skeptic-verify

Scope: closure check of my round-3 findings against the current
`.tmp/ai-review-bb331901/plan.md` (read in full this session), plus regressions
introduced by the fixes. Engine claims re-verified this session against the
**`4.7-stable` tag** (fetched from godotengine/godot — r3 had only master) and
against this project's own shipped glue at
`/Users/sean/sites/elevator-game-godot/build/web/index.js`.

---

## CRITICAL-1 — Hidden-save pipeline cannot execute as specified: **CLOSED**

§7.1 (plan.md:263-287) now mandates exactly what r3 demanded: the hidden-save
runs synchronously inside the JS callback, the FS→IndexedDB sync is forced from
the JS side, and only sim-state mutation defers to the resume flag. I traced
every link of that chain against source this session:

- **The premises still hold on the 4.7-stable tag** (r3 verified only master):
  `web_main.cpp:176` is `emscripten_set_main_loop(main_loop_callback, -1, false)`
  — pure rAF, no timer fallback; `os_web.cpp:78-85` is the **only** place
  `godot_js_os_fs_sync()` is called, and file-close merely sets `idb_needs_sync`
  (`os_web.cpp:238,250`). §7.1's engine paragraph is accurate as written.
- **Synchronous execution inside the callback is real on this build.** The JS
  wrapper created by `create_callback` invokes the wasm function directly
  (`library_godot_javascript_singleton.js:219-233` — `func(p_ref, …)` inline in
  the event handler), and on the C++ side `JavaScriptObjectImpl::callback` calls
  `_callback` → `obj->_callable.call(arg)` directly
  (`javascript_bridge_singleton.cpp:257-282`). The **only** deferred branch is
  gated on `PROXY_TO_PTHREAD_ENABLED` off the main thread
  (`javascript_bridge_singleton.cpp:271-276`) — which cannot engage in the §10
  threadless build. So the GDScript callable runs synchronously inside the
  browser's `visibilitychange` dispatch, before iOS suspends the page.
- **Safety wrt the main loop: safe.** JS is single-threaded; the handler can
  never interleave with a `main_loop_iterate` in progress. Serialisation +
  `FileAccess` writes are MEMFS operations, synchronous and loop-independent.
  The plan's no-inline-mutation rule is the right remaining constraint.
- **The JS-side force is implementable with the shipped template.**
  `godot_js_eval` with `p_use_global_ctx = false` executes a **direct** `eval`
  inside the module scope (`library_godot_javascript_singleton.js:346-355`), and
  in this project's built glue the filesystem object survives minification
  literally (`var FS={` and `FS.syncfs` both present in `build/web/index.js`,
  confirmed by grep this session). So
  `JavaScriptBridge.eval("FS.syncfs(false, function(){})", false)` reaches the
  real syncfs.

**Residue that partial success leaves behind — two items, both cheap, one
load-bearing:**

(a) **A trap API with exactly the right name and exactly the wrong behaviour.**
`JavaScriptBridge.force_fs_sync()` is script-exposed and documented as "Force
synchronization of the persistent file system" (`doc/classes/JavaScriptBridge.xml:50-56`)
— but its implementation only sets `idb_needs_sync = true`
(`javascript_bridge_singleton.cpp:412-414` → `os_web.cpp:263-267`); the actual
sync still runs solely in `main_loop_iterate()`, the loop §7.1 says has stopped.
An implementer told to "force the filesystem sync" will find this method first,
call it inside the callback, and silently rebuild CRITICAL-1(b) while appearing
to comply. §7.3 states the plan's own doctrine — "named explicitly because a ban
list is what gets grepped" — so §7.1 should name
`JavaScriptBridge.force_fs_sync()` as **banned for the hidden path** (it
schedules on the dead loop), one sentence.

(b) **The §10.1 checklist never gained the only test that catches (a).** r3
asked for: create a save via phone-lock, kill the tab from the app switcher
*without ever resuming*, relaunch, verify pre-lock state. The current exit
criteria (plan.md:866-877) have "restored: yes after a Safari force-quit and
relaunch" — a tester who force-quits a *foregrounded* session passes that item
even when the hidden-sync is broken, because an earlier visible-frame
`main_loop_iterate` already flushed. Given (a), this checklist variant is the
difference between catching the trap on device and shipping it.

Also worth one recorded line: the synchronicity guarantee is **coupled to the
threadless export**. Under `PROXY_TO_PTHREAD` the callback becomes
`call_deferred` — consumed at resume — so a future flip to the threaded template
(e.g. after moving to a custom domain with COOP/COEP) silently reopens
CRITICAL-1. §7.1 or §10 should note the coupling.

Also: `GodotFS.sync()` refuses re-entry ("Already syncing!" returns a resolved
promise without syncing — `library_godot_os.js:191-199`), so the §14
implementation must force via `FS.syncfs` directly or chain on the pending
promise as `finish_async` does (`library_godot_os.js:255-264`), or a hide that
races the engine's own timer-save sync silently skips the flush. §14 material;
naming it here so it isn't rediscovered in production.

## MAJOR-1 — Watermark never commits; beyond-cap forfeiture unstated: **CLOSED, with a REGRESSION (see below)**

§7.2 now has the atomic commit (`sim_wall_time = now - residual`, credit and
commit one transaction — plan.md:313-319), explicit beyond-cap forfeiture with
the correct anti-harvest rationale, and residual-zeroing on clamped windows
(plan.md:321-329). The governing conservation invariant is stated and §9.2
test 9 now checks successive-resume conservation directly (plan.md:789-792).
All four of r3's demands are in the text.

## REGRESSION-1 (MAJOR) — the fix collides with a retained pre-fix sentence: the residual is now credited twice

plan.md:388-390 still says: "On resume, `total = residual + elapsed`, run
`floor(total / 60)` steps, store `total mod 60` back." That sentence predates the
commit rule and is now wrong, because after a commit the residual is *already
embedded in the watermark*: with `sim_wall_time = now₀ − r₀`, the next boundary
computes `elapsed = now₁ − sim_wall_time = Δ + r₀` — and `total = residual +
elapsed` adds `r₀` a second time. Every boundary over-credits by the carried
residual.

Concretely, in §9.2 test 10's own scenario (29-second cycles): cycle 1 banks
r=29; cycle 2 computes elapsed = 29+29 = 58, total = 29+58 = 87, credits 60
sim-seconds against 58 real seconds — the conservation invariant
(plan.md:331-333) is violated on the third resume, and the divergence compounds
(~1.7x over six cycles by hand-trace). Algebraically the two sentences are
consistent **only when the residual is zero**: credited time
`total − r_new = 2r_prev + Δ − r_new` exceeds watermark movement
`Δ + r_prev − r_new` by exactly `r_prev` per cycle.

The same stale sentence also contradicts the MAJOR-3 fix it sits next to: with
phase-aligned stepping (partial step to the bucket boundary, whole buckets, bank
the tail — plan.md:363-365), the banked tail equals `total mod 60` only when the
window starts at phase 0; at any other phase the `floor(total/60)` /
`total mod 60` arithmetic disagrees with the stepping rule the paragraph above
it mandates.

Tests 9/10 would catch this in implementation — but the implementer then faces
two contradictory normative sentences on the design's centerpiece formula and
must guess which one the tests encode. This is precisely the defect class my r3
verdict named ("normative text that specifies named tests that cannot pass").

**Fix is one sentence:** replace plan.md:388-390 with `total = elapsed` (the
watermark already carries the residual), keeping "carried, never dropped or
rounded up" as the *rationale* for the commit rule's `now − residual` form. Note
the simplification this enables: under the commit rule,
`catchup_residual_seconds` is derivable and could be dropped from the schema
entirely — which would also structurally delete the hostile-residual entry in
the §9.2 matrix rather than defending it.

## MAJOR-2 — Clearing anchored to the Hidden event: **CLOSED, with a REGRESSION (see below)**

§7.2 (plan.md:396-418) now keys reconciliation on `elapsed` at any catch-up
boundary, covers cold start by construction, clears in-car passengers with the
correct §6-combo rationale, parks cars at interpolated positions, and preserves
sub-threshold discrete state. All three r3 problems are addressed as stated, and
test 11 pins path equivalence.

## REGRESSION-2 (MAJOR) — the fix conflates the crediting window with the staleness window: accumulated lag guarantees an eventual board wipe on a seconds-long app-switch

`elapsed = now − sim_wall_time` measures *uncredited time*. The clearing
threshold needs *staleness of the discrete state* — how long that state has been
frozen. The fix uses one number for both, and the plan's own rules force them
apart: sub-threshold windows are **not** credited and do **not** move the
watermark ("the gap rides as sim-time lag, which the anchor credits at the next
boundary" — plan.md:398-400), and §8.3's per-frame clamp makes each short hide's
excess a *permanent* watermark deficit. So the deficit accumulates across
app-switches — and across sessions, since the watermark persists.

Consequence, guaranteed-eventual rather than edge-case: a habitual
quick-switcher (60 x 30 s glances ≈ 30 min of accumulated deficit against a
minutes-scale threshold) eventually crosses the threshold, and then **one more
3-second app-switch computes `elapsed` in the minutes and wipes every waiting
and in-car passenger** — the exact "punishes a three-second app-switch"
behaviour MAJOR-2 existed to prevent, resurfacing through the deficit channel.
Secondary effect: for that player the credit is deferred indefinitely — minutes
of earned time invisibly parked until the spurious wipe pays it.

**Fix, sentence-scale:** decide staleness and crediting on different clocks —
credit on `now − sim_wall_time` (unchanged), but clear on the age of the
*discrete snapshot*: hidden-window duration at resume, `now − saved_at` at cold
start. `saved_at` is already in the save and §7.2 already demoted it to
"diagnostic, not an economic input" — clearing is not an economic input, so
using it there is consistent with the anchor doctrine. (Alternative: credit
sub-threshold windows analytically too, which stops the deficit accumulating —
also sound, since the clamp means the gap's spawns never occur discretely, so
there is no double-pay — but it runs the integrator on every glance.)

## MAJOR-3 — Residual carry breaks Test A's bucket alignment: **CLOSED**

The phase-aligned stepping rule (plan.md:363-369) is exactly the r3 fix,
including the correct failure arithmetic for the alternative. For
piecewise-constant curves it is exact at any phase; Test A's 1e-9 claim is
honest again. The only defect is the stale neighbouring sentence already covered
in REGRESSION-1 — one edit resolves both.

## MAJOR-4 — Version-skew dialog offers destruction: **CLOSED**

§8.6 (plan.md:676-691) now splits the refusal UX: skew → "the game has updated;
reload to continue," discard explicitly not offered; discard reserved for
genuinely unmigratable saves; backup offered as an export string; import
available under the latch and clearing it plus the dirty flag. All four r3
demands present. Feasibility of "ideally triggering the service-worker update"
is engine-supported — `OS_Web` exposes the `pwa_update_available` signal and
`pwa_update()` (`os_web.cpp:255-260, 269-271`), verified this session. Partial
success residue is benign: if the new SW has not finished installing, the first
reload can land on the same old client and repeat the dialog — a bounded
annoyance with zero data loss, since the latch holds. No change demanded.

## MINOR-1 — Anchor formula mixes timebases: **CLOSED, one UNVERIFIED platform risk the fix newly hardens**

The clock-domains paragraph (plan.md:305-311) pins exactly the dual-anchor r3
asked for, and the Chrome-throttling anecdote is gone. One risk the now-normative
"ticks-only in-session" rule (plan.md:433-436) inherits: Godot's web clock
bottoms out in `performance.now()` (present in the built glue at
`build/web/index.js`), and the HR-time spec permits the monotonic clock to pause
across device sleep — historically observed on iOS. If it pauses across phone
lock, Hidden→Resumed computes `elapsed ≈ 0` on the **primary path**: no credit
and no welcome-back until the next cold start (the epoch-domain watermark makes
the credit *deferred*, not lost — conservation holds). **UNVERIFIED on device**
— and §10.1's "phone lock … sane wall-clock delta" item (plan.md:874-876) is the
right probe and will answer it. Worth one contingency line in §7.2: if the
device check shows a paused monotonic clock, the Resumed boundary reads unix
time like cold start does — §12 already accepts the clock-manipulation exposure
that implies.

## MINOR-2 — A2HS migration leaves a diverging Safari twin: **NOT CLOSED**

§7.3's guided migration (plan.md:458-465) is unchanged from round 3 on this
point: after a successful standalone import, the Safari-side save persists,
reachable and silently diverging (the text itself notes it "keeps aging toward
deletion"). The r3 tombstone suggestion — a migrated-flag written during the
export flow so the Safari copy shows "this building moved to your home-screen
app" — is absent. Minor, but it was on the list and no text addresses it.

---

## Verdict

The engine-facing fix — the one that had to be right — is right: every load-
bearing claim in the new §7.1 checks out against the 4.7-stable tag and this
project's own built template, down to the threadless-build condition that makes
the synchronous callback true. §7.2's commit/forfeiture, phase alignment, and
the skew UX are likewise genuinely closed.

But the round of edits introduced two defects of exactly the class that drove my
r3 REVISE: REGRESSION-1 leaves two contradictory normative sentences on the
centerpiece formula — followed as written, the economy over-credits every
carried residual and the section's own governing invariant and tests 9/10
cannot pass; REGRESSION-2 re-creates the punished-app-switch behaviour MAJOR-2
was opened for, as a guaranteed-eventual outcome rather than an edge case. Both
fixes are sentence-scale (one formula replacement; one clock-of-record choice),
plus two one-liners from CRITICAL-1's residue (ban
`JavaScriptBridge.force_fs_sync()` for the hidden path; add the
killed-while-hidden-never-resumed device check).

VERDICT: REVISE — concerns above should be addressed first
