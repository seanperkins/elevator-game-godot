# Skeptic Review — Elevator Incremental Design Spec (r1)

Reviewer: Claude Fable Skeptic. Grounding performed against the actual repo:
Milestone 0 artifacts exist as claimed (`/Users/sean/sites/elevator-game-godot/main.gd`,
`project.godot`, `export_presets.cfg`, `.github/workflows/deploy.yml`, `build/web/`),
and the threadless-export claim is real (`export_presets.cfg:26`,
`variant/thread_support=false`). The design is strong on architecture discipline
(sim/view split, determinism, data-driven balance). The findings below are ordered
by how much they threaten the two core promises of an incremental: *progress
persists* and *time away counts*.

---

## CRITICAL 1 — The "open vs. closed" dichotomy is false on the primary target, and "save on quit" never fires there

§7 models exactly two states: window open (live sim) and closed (offline model).
§8.6 saves "on a timer and on quit." §10 declares mobile Safari the primary
delivery target. These three statements are mutually incompatible.

On iOS Safari the dominant state is neither open nor closed — it is **suspended**:
the player switches apps, locks the phone, or leaves the tab backgrounded.
In that state `requestAnimationFrame` stops, so Godot's main loop and
`_physics_process` stop — no ticks, no live sim. But no unload happened either,
so on resume there is no load boundary to trigger the offline model. Trace the
runtime path: player plays for 10 minutes, presses the home button, comes back
tomorrow. The tab thaws mid-frame, `_physics_process` resumes, and 20 hours of
real time have silently produced *zero* earnings — less than if the player had
force-quit the tab. The most natural way to "leave" the game on the target
platform is its worst-rewarded path. Desktop hidden tabs behave the same
(rAF throttled to zero), so "leave the tab open overnight" also earns nothing
despite §7's "the sim runs while the window is open."

Compounding it: **there is no reliable quit event on iOS Safari.** Swiping the
tab away or the OS jettisoning the suspended page fires neither Godot's
`NOTIFICATION_WM_CLOSE_REQUEST` nor a dependable `beforeunload`. "On quit" is a
desktop concept; on the primary target that save simply never happens. The only
dependable hook is `visibilitychange → hidden`.

Second-order detail (UNVERIFIED for 4.7 specifics, long-standing Godot web
behavior): `user://` on web is an in-memory Emscripten FS synced to IndexedDB
asynchronously via `FS.syncfs`. A save "written" moments before the page is
killed may never reach IndexedDB. Save-on-hide plus the timer mitigates, but the
design should not assume `FileAccess.close()` means durable on web — Milestone
0's round-trip check (`main.gd:104-123`) proves read-back within a live session,
not durability across a kill.

**Fix direction:** make the state machine three-state. On `visibilitychange:
hidden` — save immediately and record a timestamp. On visible — compute elapsed
time and run the offline model as catch-up. This also cleanly resolves the
desktop hidden-tab case. It should be designed in §7 now, because it changes
what the offline model is *for* (it runs many times a day, not once per
return-from-closure).

## CRITICAL 2 — Safari's 7-day ITP eviction deletes the save file for exactly the players an idle game targets

Since Safari 13.1 / iOS 13.4, WebKit's Intelligent Tracking Prevention deletes
**all script-writable storage — explicitly including IndexedDB** — after seven
days of Safari use without user interaction with the site. Web apps added to the
home screen are exempt (they get their own use counter). Verified via:
[WebKit 7-day cap coverage (Search Engine Land)](https://searchengineland.com/what-safaris-7-day-cap-on-script-writeable-storage-means-for-pwa-developers-332519),
[Didomi summary of the policy](https://support.didomi.io/apple-adds-a-7-day-cap-on-all-script-writable-storage),
[Apple Developer Forums — PWA data persistence beyond 7 days](https://developer.apple.com/forums/thread/710157).

`user://` on web *is* IndexedDB (the plan says so itself, §10 Milestone 0). So:
a player drifts away for a week — the single most ordinary event in an
incremental's life — and returns to a deleted building. No fail state by design
(§5.3), except the platform ships one. This cannot be caught by the outstanding
"confirm on the user's actual iPhone" check, because it takes seven days of
Safari use to manifest; it will instead surface as unreproducible "my save
vanished" reports.

Note `export_presets.cfg:35` currently has `progressive_web_app/enabled=false`.

**Fix direction (pick at least one, in the design, not later):** (a) prompt
"Add to Home Screen" prominently — installed web apps are exempt, and this suits
an idle game anyway; (b) enable the PWA export and manifest to make installation
first-class; (c) provide manual save export/import (copyable string) as the
escape hatch; (d) accept and document the loss window explicitly. Doing nothing
is the only wrong option.

## MAJOR 3 — The offline analytic model is harder than §8.4 admits, and §8.1 contradicts §8.4 about what it even is

§8.1 sells the sim/view split partly on "offline progress is the same code run
differently." §7/§8.4 then specify the opposite: an analytic model, explicitly
*not* replayed ticks. One of these is the design; the spec should stop claiming
both.

The analytic model as specified — "computes throughput and rent rates at save
time and multiplies by elapsed time" — is wrong for this sim, for reasons the
spec itself creates:

- **Time-of-day curves (§5.1)** mean the instantaneous rate at save time is not
  the mean rate. Save during the morning rush and the snapshot rate is several
  times the daily average; multiply by 4 hours and offline progress dwarfs live
  play. This is also a save-scumming exploit: quit at peak rush with a hot
  combo, every time.
- **Tenancy feedback (§5.3)** couples the rate to itself: satisfaction scales
  rent, expirations lower satisfaction, low satisfaction triggers move-outs, and
  §7's welcome-back screen promises to report "any tenants lost" — so the
  offline model must evolve tenancy state, not multiply a scalar. That is a
  coupled dynamic system (integrate the traffic curve, cap by capacity, decay
  satisfaction, fire move-out countdowns), not one multiplication.
- **The §9 agreement test as stated will be flaky or vacuous.** "N ticks live vs.
  N ticks analytic within tolerance" depends on where in the day-cycle the
  window starts and whether a move-out threshold was crossed. Either the
  analytic model integrates the curves (then the test is meaningful) or it
  snapshots (then no fixed tolerance survives a rush-hour boundary).

**Fix direction:** define the offline model as integrating the same data-driven
curves over the elapsed window (they live in `data/` already, §8.7), with
capacity as a throughput ceiling and a stated rule for offline tenancy decay.
State the anti-exploit rule: offline rate derives from a trailing average or
curve integral, never the instantaneous rate at save time.

## MAJOR 4 — "Refuse to load unknown future versions" plus autosave-on-timer destroys the future save

§8.6, second-order trace: a player runs the game on two devices or rolls back a
cached build. Old client loads, sees save version N+1, refuses to load — good —
then starts a fresh game and the save timer fires, overwriting the version-N+1
save with a fresh version-N save. The refusal protected the process and
destroyed the data. Refusing to load must also disable (or redirect) saving for
that session, and ideally the refused save is copied to a backup slot first. One
sentence in the spec prevents a data-loss bug that will otherwise pass every
round-trip test in §9, because those tests never exercise the refusal branch
followed by a save.

## MAJOR 5 — The three click verbs collide on a sub-HIG moving touch target at scale

At the §3 ceiling, 40 rows in a 1280-unit-tall viewport (`project.godot:15-16`)
gives 32 px per row; a car inside a shaft is smaller still, and moving. Apple's
HIG floor for touch targets is ~44 pt. Now overlay the verbs from §2 and §6:
tap a car (dispatch step 1), rapid-tap a *moving* car (surge), rapid-tap a stuck
car (event response). Three verbs, one tiny moving target, distinguished only by
tap cadence — on a platform where rapid double-taps also trigger browser zoom
heuristics unless explicitly suppressed. Early game (6 rows) is fine; the spec
promises surge "relevant in every era" (§2), so the collision arrives exactly
when rows are thinnest. This is a design-level gap, not polish: it needs a hit
model (shaft-level tap zones, enlarged hitboxes, or verb disambiguation by
target state) stated in §2/§3, or surge quietly dies in later eras and the
active-play multiplier (§6) loses its input.

## MINOR 6 — Tick-time vs. wall-time drift is unhandled

§8.3 drives 20 ticks/s from `_physics_process`, unspecified whether via
`physics_ticks_per_second=20` or accumulation at 60. Either way, Godot clamps
physics catch-up after long frames (`max_physics_steps_per_frame`), so hitches
drop ticks and sim time falls behind wall clock. Harmless per frame; it matters
because the offline/catch-up model (Finding 1) computes from wall-clock
timestamps while the live sim advances in ticks — the spec should name which
clock is authoritative for earnings so small stalls don't double-pay or unpay.

## MINOR 7 — Megatower row abstraction leaves intra-row traffic undefined

§3 makes a Megatower row "a district (~50 floors)" while §5.1 passengers have an
origin *floor* and destination *floor* and the era's stated mechanic is
"residents generate 24h internal traffic." If origin and destination collapse to
rows, traffic inside a district never touches an elevator; if they stay floors,
the sim's stop model no longer matches the board. One definition sentence in §3
("passenger endpoints are rows; a row's internal traffic is abstracted into its
spawn rate") closes it.

## MINOR 8 — 39 MB wasm: the iOS risk is memory, not just download

§10 frames the payload as a bandwidth cost. On older iPhones the sharper risk is
mobile Safari's per-tab memory ceiling during wasm compilation plus game heap —
tab reloads under memory pressure, which on this platform also silently re-kills
suspended sessions (feeds Finding 1). UNVERIFIED for current Safari versions;
worth one line in the risk register and a check during the outstanding
real-device pass.

---

## The one fatal flaw

The plan designs persistence and idle accrual — the two promises an incremental
lives or dies on — around a desktop browser lifecycle (open/closed, save-on-quit,
durable storage), then names mobile Safari as the primary target, where the
dominant lifecycle state is *suspended*, quit events don't fire, and storage
self-deletes after seven days of absence. Every individual fix is cheap
(three-state lifecycle, save-on-hide, home-screen install path, refusal-disables-
saving); none is cheap after ship, because each failure presents as silent player
data loss.

Findings 1–2 must be addressed in the spec before Milestone 6 is designed;
Finding 3's contradiction should be resolved now since §8.1 uses it to justify
the architecture.

VERDICT: REVISE — concerns above should be addressed first
