# Skeptic review — Round 3 (final) — claude-fable-skeptic-r3

Plan reviewed: `.tmp/ai-review-bb331901/plan.md` (read in full), with `revisions.txt`.
Grounding performed this session: `main.gd` (probe: `_test_persistence()` at
`main.gd:104`, write-before-read at `main.gd:107-114`, called from `_ready()` at
`main.gd:23` and `_on_tap()` at `main.gd:85`; `bbcode_enabled = true` at
`main.gd:77`), `export_presets.cfg:26` (`variant/thread_support=false`, column 0),
`export_presets.cfg:40-42` (empty PWA icon fields), `project.godot` (no
`[physics]` section; 720x1280 `canvas_items`/`expand`). All of the plan's
file-level claims I checked are accurate.

Engine-source verification (fetched this session from godotengine/godot master,
the 4.x line the plan targets — caveat: master, not a `4.7` tag):

- `platform/web/web_main.cpp`: the web main loop is
  `emscripten_set_main_loop(main_loop_callback, -1, false)` — pure
  `requestAnimationFrame`, no timer fallback in Godot's code.
- `platform/web/os_web.cpp`: `OS_Web::main_loop_iterate()` is the **only** place
  the IndexedDB sync runs — `file_access_close_callback` merely sets
  `idb_needs_sync = true`; `godot_js_os_fs_sync()` is called on the *next main
  loop iteration*.

These two facts drive the one new CRITICAL below.

---

## Closure of my round-2 findings

| Round-2 finding | Status |
| --- | --- |
| CRITICAL-1 — 1e-9 catch-up/live agreement unachievable | **Closed.** §9.1's Test A/Test B split (plan.md:614-627) is the right shape: exactness only where a same-finite-sum argument exists, an engineering budget plus a no-exploit ratio bound for economics. One residue: the exactness claim is broken by the new residual carry (MAJOR-3 below). |
| MAJOR-1 — discrete/analytic seam unowned in both directions | **Closed in intent.** §7.2 now owns both directions (plan.md:281-287, 309-319) and names catch-up the winner on the boundary. The clearing is anchored to the wrong event (MAJOR-2 below), but the seam is no longer unowned. |
| MAJOR-2 — shaft purchases vs the 44 pt column guarantee | **Closed.** §3's 8-shaft board constant with the 85-unit arithmetic and the cars-per-shaft growth valve (plan.md:88-94). |
| MAJOR-3 — A2HS storage isolation orphaning the Safari save | **Closed.** §7.3's guided migration (export before prompt, paste-on-first-standalone-launch, container check in §10.1) is the correct fix. A small second-order residue remains (MINOR-2). |
| MAJOR-4 — web platform never registers `visibilitychange` | **Closed in intent.** §7.1 names the JavaScriptBridge glue. But the accompanying threading rule neuters it on the primary target (CRITICAL-1 below). |
| MINOR — single-flight dropping the hide-save | **Closed** (coalescing dirty-flag, plan.md:557-562). |
| MINOR — sub-minute remainder | **Closed** (residual carry, plan.md:299-307), with a new alignment consequence (MAJOR-3). |
| MINOR — lobby rationale overclaiming | **Closed** (§5.3 single rule). |
| MINOR — PWA/service-worker update flow | **Closed** (version skew declared routine, plan.md:370-374), with a new UX consequence (MAJOR-4). |

Also genuinely good in this revision, stated for the record: the sim-clock anchor
makes a *lost* save benign by construction (the previous consistent snapshot is
loaded and catch-up re-credits the gap — no corruption, only replay); the 7-step
load sequence with type-before-value and structural-before-migration ordering is
correct; the probe fix is structural as demanded.

---

## New findings — the revised machinery, traced for partial success

### CRITICAL-1 — The Hidden pipeline cannot execute as specified on the primary target

Two independent breaks, both verified against engine source, both introduced by
this revision's own text.

**(a) The flag is consumed by a loop that has already stopped.** §7.1 (plan.md:253-254):
the JS `visibilitychange` callback "sets a flag consumed at the top of the next
`_physics_process`; it never mutates sim state inline." But the web main loop is
`emscripten_set_main_loop(..., -1, ...)` — rAF-driven — and §7.1's own premise
(plan.md:231-232) is that `requestAnimationFrame` stops when hidden. rAF
callbacks only run in the rendering steps of a *visible* document, and on iOS the
content process is suspended shortly after backgrounding. So "the next
`_physics_process`" is at **resume**. The Hidden row of the state table
(plan.md:239 — "Save immediately, quiesce, stop ticking") never runs while
hidden; a tab jetsammed while hidden — the dominant death on the primary target,
per §7.1 itself — dies having never executed the hidden-save. The design is
internally inconsistent: its threading rule defers the save to a callback its own
platform model says will not come.

**(b) Even a synchronous write is not durable, because the IDB sync also lives in
the stopped loop.** Verified in `OS_Web::main_loop_iterate()`: `FileAccess.close()`
only sets `idb_needs_sync`; the actual `godot_js_os_fs_sync()` call happens on
the next main-loop iteration. §8.6 already knows close ≠ durable and offers "the
timer plus save-on-hide" as the mitigation (plan.md:564-566) — but on iOS the
save-on-hide is precisely the save this mechanism cannot flush, and §8.6's own
coalescing rationale calls the hidden-save "the most important save in the
design" (plan.md:559-562).

**What partial success leaves behind:** every hidden-kill silently reverts up to
30 seconds of play — including purchases — and the sim-clock anchor *masks* the
loss economically (the time is re-credited on the next launch), so the symptom is
"my upgrade vanished," untraceable and trust-destroying, on the single most
common way to leave the game.

**Fix (sentence-scale, but it must be in the design because it contradicts two
normative sentences):** the `visibilitychange → hidden` handler must
*synchronously* invoke the save (serialisation reads sim state; it does not
mutate it, so the no-inline-mutation rule can stand) **and force the FS→IndexedDB
sync from the JS side** (the engine exposes no GDScript API for this; the glue
must call the engine's syncfs path directly — name this in §7.1 alongside the
listener glue). The flag-and-consume pattern remains correct for everything else
(quiesce/clearing, which moves to resume per MAJOR-2). §10.1's device checklist
should add: create a save via phone-lock, kill the tab from the app switcher
*without ever resuming*, relaunch, and verify the pre-lock state — the current
checklist's reload/force-quit items all pass through a resumed or still-live
session and would not catch this.

### MAJOR-1 — Catch-up never commits the watermark, as written; beyond-cap forfeiture is unstated

§7.2 (plan.md:263-264): "`sim_wall_time` advances only by *executed* ticks
(`ticks_executed x 0.05`)." Catch-up executes no ticks — it runs 60 s analytic
steps — so under the literal rule, catch-up credits `elapsed` and leaves
`sim_wall_time` untouched. The next boundary recomputes
`now − sim_wall_time` over the already-credited window: the same hour awarded
twice — the *exact* defect ("no committed watermark," plan.md:272-273) this
anchor was introduced to close, reintroduced by the anchor's own normative
sentence. §8.3's "single authority for how much time has been economically
credited" (plan.md:444) implies the opposite: catch-up must advance it. The two
sentences contradict, and the doc never resolves which wins.

Second gap, genuinely unresolvable from the doc: **beyond-cap time.** Away 3 days
with an 8 h cap → 8 h credited. If the watermark advances only by the *credited*
window, the player remains 64 h behind and every close/reopen harvests another
capped window — unbounded offline income from repeated relaunches. Nothing states
that beyond-cap time is forfeited. The correct rule is one sentence: *catch-up
atomically sets `sim_wall_time = now − residual`* (credit and commit are one step,
so no coalesced save can snapshot credited-cash-with-stale-watermark — require
catch-up to be synchronous at load, or advance the watermark per step). Test 9
(plan.md:647) checks `elapsed` boundaries, not commitment; add: "relaunch
immediately after a beyond-cap catch-up yields `elapsed ≈ 0`."

"By construction" (plan.md:278-279) is currently claimed but the construction —
the commit step — is absent from the text.

### MAJOR-2 — Passenger clearing is anchored to the wrong event

§7.2 (plan.md:309-311) clears the waiting population "on Hidden." Three problems:

1. **It cannot run there** (CRITICAL-1a: no iteration executes at hide-time), and
   it *should not* run inside the JS callback (the plan's own no-inline-mutation
   rule, correctly).
2. **It misses the paths that never pass through Hidden.** The 30-second timer
   saves live discrete state during active play. A tab that dies while visible
   (Safari tab crash, the §10 reload-during-wasm-compile OOM, swipe-kill of a
   foregrounded app) leaves a timer save full of passengers with seconds-scale
   patience. Cold start hours later loads them into an hours-older world —
   the mass-expiry event §7.2 exists to prevent, on a path Test 12
   (plan.md:651-652, "after a multi-hour *resume*") will not cover.
3. **Clearing on *every* hide punishes the most common action.** A 3-second
   app-switch during rush wipes the board and folds the in-flight passengers into
   a ~0-second window's statistics — their fares are simply lost, repeatedly,
   for glancing at a text message.

All three have one fix: clearing/parking is a function of **elapsed time at the
catch-up boundary** (load *and* resume), not of the hide event. Saves always
carry live discrete state; at the boundary, if `elapsed` exceeds a threshold on
the patience scale (minutes), clear and fold into catch-up; below it, resume the
discrete state intact and let the gap ride as §8.3-style sim-time lag (the
sim-clock anchor credits it at the next real boundary — each second still
credited exactly once). Test 12 should then be stated for *cold start from a
mid-play timer save*, the case the current wording misses.

### MAJOR-3 — The residual carry breaks the bucket alignment that Test A's exactness depends on

§7.2 (plan.md:301-302): "run `floor(total / 60)` steps, store `total mod 60`
back" — fixed 60-second strides starting at an arbitrary phase. §9.1's Test A
(plan.md:614-620) claims the integrated rate is "the same finite sum" at 1e-9
because curves are piecewise-constant on minute buckets — but that holds only for
**bucket-aligned** windows. A stride starting at phase φ spans two buckets and
reads only `curve[floor(start)]`; per window the error is `φ · (c(q+k) − c(q))`.
Concretely: residual 30 s across a rush boundary stepping from 1/min to 10/min
misattributes 4.5 expected spawns — small, but ~10^8 times the 1e-9 bound.
Consequence: Test A and Test 10 (120 × 29 s ≡ 58 min, plan.md:648-649) **fail as
specified** whenever the residual is nonzero — or get written bucket-aligned and
never exercise the real resume path. Either way the round-2 CRITICAL-1 spiral
(loosen the tolerance until meaningless) reopens.

Fix is one sentence: the integrator advances to the next bucket boundary first
(partial step), then whole buckets, then banks the tail as the residual. For
piecewise-constant curves this is exact at any phase, restoring both tests at
1e-9 honestly.

### MAJOR-4 — The routine version-skew event offers save destruction as its only actionable recovery

§7.3 (plan.md:370-374) declares old-client-meets-newer-save "an ordinary
post-deploy event." §8.6's refusal path (plan.md:547-555) latches writes —
correct, and it is precisely what preserves the save until a capable client
arrives — but the recovery it presents is "discard the unreadable save and start
fresh" or import. In the skew case the player holds a *perfectly good* save that
a reload (service-worker update) would read; the one clearly-actionable button
destroys it, and a confused player facing a blocking error will press it. The
partial success: the latch protects the data; the offered exit deletes it.

Fix: the "version above newest known" refusal must be a *distinct* UX — "the game
has updated; reload to continue" (ideally triggering the SW update) — with
discard reserved for genuinely unmigratable saves. Related gap in the same
paragraph: "the blocking message names the backup file, since a web player cannot
browse `user://`" (plan.md:554-555) — naming a file the player *cannot reach* is
not an affordance. The dialog should offer the backup **as an export string**
(the §7.3 codec already exists), so import — the designated recovery path —
has something to import. And note for §14: the backup write itself must be exempt
from the latch it precedes (trivial ordering, worth one line).

### MINOR-1 — The anchor formula mixes timebases; one premise is doubtful

`elapsed = clampf(now − sim_wall_time, …)` with `now` = `Time.get_ticks_msec()`
in-session (plan.md:327-330) and unix time at cold start requires
`sim_wall_time` to be comparable to **both** — but ticks_msec is
process-relative and unix-anchored persistence is needed for cold start. A
coherent implementation exists (capture the `(unix, ticks)` pair at session
start; keep `sim_wall_time` unix-anchored; derive in-session `now` from the
monotonic delta), but the doc states the formula as normative without it; a naive
implementation subtracts across timebases. §14 material — but the formula is the
design's centerpiece, so pin the dual-anchor in §7.2. Separately: "desktop Chrome
runs hidden tabs at ~1 Hz" (plan.md:275-277) is doubtful under a pure-rAF loop
(verified: no timer fallback in Godot's `web_main.cpp`; Chrome delivers zero rAF
to hidden tabs). UNVERIFIED whether some emscripten version adds a hidden-tab
fallback; harmless either way — with zero hidden ticks the anchor still credits
correctly — but the rationale anecdote is probably wrong as stated.

### MINOR-2 — A2HS migration's partial success leaves two live, diverging saves

After paste-import into the standalone app, the Safari-side save remains and the
Safari entry point stays reachable via history/bookmark. A player who later opens
the Safari URL sees the *old* building — loss-shaped confusion, and silent
divergence if they play there. Cheap fix: a successful standalone import is
followed (next time the Safari copy loads) by a "this building moved to your
home-screen app" notice — a migrated tombstone flag in the Safari save, written
as part of the §7.3 export flow. The clipboard-loss risk in the guided flow is
already covered by the on-screen string, since the player can return to the
Safari tab; fine as designed.

---

## Direct answers to "what does partial success leave behind?"

- **Sim-clock anchor:** without an atomic commit + cap forfeiture (MAJOR-1), a
  partially-applied catch-up leaves a stale watermark → double-credit and
  repeat-relaunch cap harvesting. With the fix, partial success is provably
  benign: any consistent earlier snapshot just replays.
- **Hidden-boundary clearing:** partial success (clearing runs only on the
  Hidden path) leaves the timer-save/cold-start path resurrecting stale
  passengers — the mass-expiry event returns exactly where Test 12 doesn't look
  (MAJOR-2).
- **Residual carry:** conserves *time* perfectly but samples the *curve* at the
  wrong phase — partial success is an exactness test that fails or a test that
  doesn't test the shipped path (MAJOR-3).
- **writes_disabled latch:** succeeds at preserving the bytes and then hands the
  player a destruction button during a routine deploy (MAJOR-4).
- **A2HS guided migration:** succeeds at moving the save and leaves a live stale
  twin behind in Safari (MINOR-2).

## The one fatal flaw

CRITICAL-1. The revision's Hidden machinery — the load-bearing answer to "mobile
Safari is the primary target" — defers both the save and its durability flush to
main-loop iterations that its own platform model says stop at exactly that
moment. Everything downstream (§7.2's boundary, §8.6's "timer plus save-on-hide"
mitigation, the coalescing rationale's "most important save") assumes the hidden
save lands. It cannot, as specified, on the platform this plan is for.

## Verdict

All five fixes are sentence-to-paragraph scale and none disturbs the
architecture — this is a surgical revision, not a rethink. But CRITICAL-1 and
MAJOR-1..3 are category (a): normative text that, followed as written, silently
loses purchases on the primary target's most common exit path, re-opens the
double-credit exploit the revision claims closed "by construction," and specifies
named tests that cannot pass. Those are not §14 implementation details; they are
the revised design's own sentences.

VERDICT: REVISE — concerns above should be addressed first
