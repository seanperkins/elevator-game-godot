# Skeptic Re-Review (Round 2) — Elevator Incremental Design Spec

Grounding: every repo citation in the plan was verified this session and all check out
exactly — `_test_persistence()` writes before reading and is called from `_ready()`
(main.gd:104-123, main.gd:23); `project.godot` has no `[physics]` section;
`progressive_web_app/enabled=false` (export_presets.cfg:35); `export_filter="all_resources"`
with empty `exclude_filter` (export_presets.cfg:9-11); mutable `GODOT_VERSION: "4.7"` URL,
`sudo mv` to /usr/local/bin (deploy.yml:19,30-34); workflow-scope `pages: write` /
`id-token: write` (deploy.yml:8-11); `--import || true` (deploy.yml:45); the
SharedArrayBuffer grep with no `exit 1` (deploy.yml:72-73). The payload numbers are
byte-exact: index.wasm is 39,509,339 bytes and `gzip -9` produces 10,052,184 bytes
(both re-measured this session). The plan's arithmetic also checks out: 308·ln10/ln1.01
≈ 71,276 (~71,270 as stated); the suffix ladder needs 98 two-letter entries
((308−15)/3 ≈ 98); the era table's meters all multiply correctly.

## Round-1 concerns — status

1. **iOS Safari lifecycle (CRITICAL, r1)** — addressed in structure by §7.1's three-state
   model and save-on-hidden + 30s timer, with save-on-quit correctly demoted. However the
   implementation premise is falsified by engine source — see MAJOR-4 below.
2. **Safari ITP 7-day IndexedDB deletion (CRITICAL, r1)** — addressed in §7.3. I verified
   the WebKit post this session: the 7-day script-writable-storage cap is real and
   home-screen web apps are exempt with their own use counter ("Web applications added to
   the home screen are not part of Safari and thus have their own counter of days of use").
   The mitigation set is right — but the A2HS mitigation itself opens a new save-loss path,
   see MAJOR-3.
3. **Offline model underspecified / contradicting §8.1 (MAJOR, r1)** — the coarse-step
   integrator and the §8.1 correction are genuine improvements, and the rate-sampling
   exploit is dead. But the replacement validation claim is mathematically unachievable —
   see CRITICAL-1.
4. **Version refusal + autosave clobbering the newer save (MAJOR, r1)** — fully addressed
   by §8.6 (disable autosave, back up the refused file, blocking message). Good fix.
5. **Click-verb collision on 32px moving targets (MAJOR, r1)** — addressed by §2.1
   column-drag with gesture-separated verbs. Sound design. It relocates rather than
   eliminates the geometry problem, though — see MAJOR-2.
6. **Tick/wall-clock drift (MINOR, r1)** — §8.3 now writes the model down, but the
   "surrender to the catch-up model" reconciliation creates a fare double-count —
   see MAJOR-1b.
7. **Megatower row abstraction (MINOR, r1)** — addressed cleanly by §3's row-semantics
   rule. Acknowledged.
8. **39MB wasm (MINOR, r1)** — corrected to ~10.05MB gzipped; I reproduced both numbers
   byte-exactly. The reframing to wasm-compilation memory as the real risk is correct.

The revision quality is high. The remaining findings are almost all in the seams of the
*new* machinery — exactly where they were predicted to be.

## New findings

### CRITICAL-1 — §9's catch-up validation (1e-9 vs. the live sim) is mathematically unachievable

§9 states: "N minutes coarse-stepped must match N minutes lived, to a relative tolerance
of 1e-9 (float rounding only). This is a real bound because both paths integrate the same
curve." That last sentence is false. Only the **spawner** integrates the curve. The live
sim's earnings are emergent from the discrete simulation:

- **Spawns are stochastic.** §8.3 mandates "a seeded RNG for spawns." A random spawner
  draws against the curve, so N-minute spawn counts deviate from the curve integral by
  O(√N) — at, say, ~2,400 spawns in a 4-hour window, that is ~2% relative deviation,
  seven orders of magnitude above 1e-9. (A deterministic fractional-accumulator spawner
  would remove this term, but that contradicts "seeded RNG for spawns" as written.)
- **Fares are per-delivery, not per-spawn.** Live income depends on which passengers are
  actually delivered before patience expires — a function of dispatch policy, car count,
  capacity, door dwell, and travel time. The catch-up model approximates all of that as
  "capacity as a throughput ceiling" (§7.2). A ceiling is not the emergent throughput of
  a dispatcher under rush load; the two diverge most exactly during rush hours, the
  windows that dominate earnings.
- **Rent is satisfaction-scaled** (§5.3), and satisfaction evolves from realized wait
  times — emergent again.

There is also an internal contradiction: §7.2 says "the offline cap and **rate** improve
through the Automation branch." If offline rate is an upgradeable fraction, offline ≠ live
*by design* at base level, and the identity test asserts something the design itself
forbids.

This repeats the *shape* of the round-1 error: a stated tolerance the two code paths
cannot meet. The consequence is concrete: at Milestone 6 the test fails permanently, the
tolerance gets loosened until it is meaningless, and the offline model's actual semantics
get improvised under schedule pressure — the exact underspecification round 1 flagged,
now hidden behind a false precision claim. The plan explicitly leans on this test
("what lets the catch-up model be validated at all," §8.3), so the whole offline
economy's validation strategy is currently impossible as specified.

**Fix:** split the claim in two. (a) The analytic model is normative for offline
earnings; test it for **self-consistency** across step sizes (1-minute vs. 1-second
steps of the same integrator) at 1e-9 — that is where a float-rounding bound is real.
(b) Test **fidelity** against the live sim statistically: fixed seed, fixed building
configs, 24h windows, assert agreement within a loose engineering tolerance (e.g. ±10%)
and document that offline pays out of the analytic model, never the live sim. And decide
explicitly whether base offline rate is 100% of the analytic model or a fraction.

### MAJOR-1 — The discrete/analytic boundary is unowned, in both directions

Two facets, same root: nothing specifies what happens to the live sim's *micro-state*
where the catch-up model takes over.

**(a) Resume mass-expiry.** §8.6 saves the full discrete state — waiting passengers, cars,
RNG, tick counter, accumulator. §7.2's catch-up evolves *aggregates* (cash, satisfaction,
tenancy) over the hidden window. On Resume, the live sim restarts from the saved discrete
state: every passenger who was standing on a floor 4 hours ago still has their saved
patience timer, which is on a seconds-to-minutes scale. Unless something reconciles, the
first live ticks after every resume deliver a mass-expiry event — satisfaction craters,
the combo dies, the player is punished for the single most common daily action (§7.1
correctly observes this path runs "many times a day"). The welcome-back summary would
report a healthy window and then the screen fills with expiring passengers. The plan
needs an explicit rule: e.g. clear the passenger population at Hidden, fold the waiting
count into the catch-up window's stats, resume cars idle at their last stop, and define
combo policy across a resume. Note the tension this exposes: §8.6 saves continuation
state so a resumed run matches an uninterrupted one, but running catch-up guarantees it
cannot; the plan should say which property wins on which path.

**(b) In-session stall double-count.** §8.3: the accumulator clamps per-frame catch-up
and "time beyond that clamp is surrendered to the catch-up model," with "wall-clock
authoritative for earnings." Trace a routine mobile-Safari GC/jank stall of 1–2 seconds:
the surrendered window is credited by the analytic model at expected fare+rent rate — but
the discrete passengers mid-flight during the stall are still in the sim, and when
ticking resumes they are *also* delivered and pay again. The analytic model cannot remove
the individuals it statistically "delivered." Result: income systematically inflates in
proportion to jank; slower devices earn more per real second, and inducing stalls is an
exploit. **Fix:** in-session stalls should never route through the earnings-bearing
catch-up model. Tick through them at the clamped rate and let sim time lag wall-clock —
deliveries land late and nothing double-pays. Reserve §7.2 exclusively for the
Hidden→Resumed boundary where micro-state is reconciled per (a), and specify the elapsed
threshold that separates the two regimes (currently no number owns this boundary).

### MAJOR-2 — Shaft count collides with the ≥44pt column guarantee, and nothing caps it

§2.1's guarantee is per-column width ≥44pt; §5.1's core loop is "the player buys a shaft"
as the answer to rush. No section caps shafts per era, and §3's no-scroll rule covers only
rows. The geometry: base viewport is 720 units wide (project.godot:15), `canvas_items` +
`expand` maps those 720 units across a ~390pt iPhone width, so 44pt ≈ 81 units and the
screen fits ~8.8 columns at *zero* margin — realistically 6–7 after floor labels, HUD
gutters, and any inter-shaft spacing. The round-1 finding (touch targets degrade exactly
when the mechanic matters most) recurs on the horizontal axis: the economy's primary
capacity lever silently breaks its own input guarantee at ~7 purchases. Either cap
shafts-per-era at the number that fits (and design upgrade ladders around cars-per-shaft,
speed, capacity instead), or specify the >7 behavior now (shaft *banks* sharing a column
target? horizontal paging, which needs a §3 amendment?). Discovering this at Milestone 3
forces a UI redesign; it belongs in §13 at minimum, owned like the Orbital Tether item.

### MAJOR-3 — The Add-to-Home-Screen mitigation orphans the existing Safari save

The §7.3 exemption works because a home-screen web app "is not part of Safari" (verified,
WebKit blog 10218) — and that same separation means the standalone app has its own storage
container. iOS home-screen web apps do not share IndexedDB/localStorage with the Safari
tab the player has been using (UNVERIFIED in this session as to the exact container
mechanics, but this is long-standing, widely documented iOS behavior and is the natural
reading of "not part of Safari"). Consequence: the player with a week-old building follows
our own prominently-displayed A2HS prompt, taps the new icon, and opens an *empty
building* — while the Safari-side save keeps aging toward ITP deletion. The adopted
mitigation causes precisely the loss it exists to prevent. The plan already has the
bridge (manual export/import string, §7.3); it just never connects it to the install
flow. **Fix:** make A2HS a guided migration — export (or auto-copy to clipboard /
display the string) before prompting install, and on first standalone launch with no
save found, ask "played in Safari? paste your save" rather than silently starting fresh.
This costs almost nothing and is needed even if the container turns out to be shared on
some iOS version. Verify container isolation on the real device as part of the §10.1
device pass (install A2HS after creating a save; check whether it appears).

### MAJOR-4 — Godot 4.7's web export does not deliver `visibilitychange`; §7.1's Hidden trigger needs custom glue

Verified in engine source this session (4.7 branch): the web display layer registers only
`blur`/`focus` listeners (platform/web/js/libs/library_godot_display.js:75,721) and maps
window blur to `WINDOW_EVENT_FOCUS_OUT` (platform/web/display_server_web.cpp:1177,1182).
No file in the web platform JS registers `visibilitychange` or reads `visibilityState`.
So an implementer who builds `game/lifecycle` on Godot's focus notifications — the
obvious reading — gets a Hidden state that fires on desktop tab-switch but can silently
miss the primary path the section was written for: phone lock and app-switch on iOS,
where `visibilitychange` is the reliable signal and window `blur` is not (blur firing on
iOS backgrounding is UNVERIFIED and widely reported flaky; that unreliability is the
standard reason the page-lifecycle guidance says to use `visibilitychange`). The failure
is silent: everything works in desktop testing, and on the phone the save rides only the
30s timer — which itself stops when hidden, so the last ≤30 seconds of play are routinely
lost, including whatever purchase prompted the player to put the phone down. **Fix:** one
sentence in §7.1/§8.2 stating that the lifecycle module must register a
`visibilitychange` listener via `JavaScriptBridge` (callback into GDScript) because the
engine does not surface it, and a §10.1 exit criterion already covers proving it on
device ("background/foreground cycle logs a sane wall-clock delta") — make explicit that
this criterion must be exercised via *phone lock*, not just app-switch.

## Minor findings

**MINOR-1 — Single-flight save can drop the hide-save.** §8.6: "A save in progress blocks
a second save rather than interleaving." If the 30s timer save is mid-flight when
`visibilitychange` fires, the hide-save is blocked — i.e. dropped — and the page then
suspends with the newest state unsaved. Specify coalescing semantics (queue-latest, run
after the in-flight write completes) rather than drop.

**MINOR-2 — Sub-minute remainder in the coarse-step model.** One step per simulated
minute leaves `elapsed % 60s` unspecified, and `elapsed < 60s` entirely so. Rapid
app-switching (the notification-check pattern, dozens of cycles/day) would shave up to a
minute per cycle if remainders are dropped. Specify a final fractional step, and specify
the threshold below which the live accumulator ticks through instead (same unowned
boundary as MAJOR-1b).

**MINOR-3 — The lobby rule's rationale fails in the state it exists for.** §5.3 claims
"the lobby row can never go vacant, so fares never dry up completely" — but if every
*other* row is vacant, lobby-origin passengers have no destination that generates traffic,
so fares do dry up; recovery in the all-vacant state rests entirely on the free-re-lease
rule (which does suffice). Harmless as designed — §9's test 4 will exercise the truth —
but the sentence overclaims and could mislead an implementer into treating the lobby as a
sufficient income floor.

**MINOR-4 — PWA service worker update flow is new, unexamined machinery.** Enabling
`progressive_web_app/enabled` adds Godot's service-worker cache: after every deploy,
installed players run the previous build for at least one launch, making old-client
encounters with newer-schema saves (the §8.6 refusal path) an ordinary post-deploy event
rather than a rare rollback. §8.6 handles it without data loss, so this is only a UX and
testing note: understand Godot's SW update/activation behavior before Milestone 6, and
add a version-skew launch to the test matrix. Also note export_presets.cfg:40-42 has
empty PWA icon paths — required fields for a first-class install prompt.

## Verdict

The round-1 fixes are real: the exploit-bearing offline model is gone, the
refused-load/autosave interaction is correctly closed, the input model is genuinely
better, and every repo citation and number I checked was exact. But the new machinery has
one impossible load-bearing claim (the 1e-9 live-sim agreement test), an unowned seam
between the discrete sim and the analytic model that punishes players on every resume and
inflates income under jank, and two verified platform gaps (engine has no
`visibilitychange`; A2HS storage isolation) sitting directly under the two round-1
CRITICALs' fixes.

VERDICT: REVISE — concerns above should be addressed first
