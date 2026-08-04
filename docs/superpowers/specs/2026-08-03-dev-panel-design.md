# A developer panel, behind seven taps

**Status:** agreed, not built.

A hidden panel for testing the game against itself: grant money, grant
Blueprints, run the sim at 2x or 4x, fit every upgrade, wipe the save. Reached by
tapping the cash readout seven times, which reveals a **DEV** button beside
MANAGE and keeps it revealed.

It exists because the balance work has outrun the ability to check it. The
prestige measurement (`2026-08-03-prestige-and-blueprints-design.md` §6) needed a
2h25 headless harness to answer one question, and the answer moved a constant.
Anything that shortens that loop pays for itself.

---

## 0. Scope

**Ships:** the seven-tap unlock, its persistence, the DEV button, the panel, six
kinds of action, and the removal of the shaft pager the button replaces.

**Does not ship:**

- **A build-time gate.** The panel is in the web export and reachable by anyone
  who taps the cash seven times. That is accepted: this is a personal project on
  a personal Pages site, the gate costs a visitor nothing to defeat and nothing
  to stumble into, and a `OS.is_debug_build()` gate would make the panel useless
  on the exact Release build that runs on the phone.
- **A tainted-save marker.** A cheated save is not flagged and does not refuse to
  load. §4 keeps the one action that could corrupt the *prestige* economy
  explicitly separate instead, which is the part that matters.
- **Undo.** Every action is immediate and permanent. `Reset save` is the undo.

---

## 1. The shaft pager comes out, and the reason it was there is stale

`game/game_root.gd:141-143` justifies the pager:

> Paging the shaft strip is a tap, never a swipe: the dispatch drag is vertical
> and arcs sideways by more than half a column (§2.1), so any horizontal read on
> the board itself would steal the primary verb.

**That is no longer true, and the tests prove it.**
`view/building_view.gd:285` connects **every shaft column's** `pan_requested` to
`pan_board_by`, which handles both axes; `Gesture` already separates a tap
(dispatch) from a drag past `DRAG_THRESHOLD` (pan). Two tests pin the result:
`test_a_sideways_drag_pans_across_the_shafts` drags on a shaft column and asserts
the strip moves, and `test_a_sideways_pan_does_not_dispatch` asserts the same
drag sends no car. The conflict the comment fears was resolved by the gesture
split; the comment outlived it.

So the two pager **buttons** are removed and the comment with them, which frees
x 236–508 — exactly where DEV goes.

**The pager LABEL stays.** `shafts 1-2 of 2` is the only thing on screen telling
you that shafts exist off the right edge; a drag affordance you have not
discovered yet cannot tell you that. It keeps its position and its
visible-only-when-pageable rule, and `_refresh_pager()` keeps updating it — it
simply stops having buttons to enable and disable.

---

## 2. The unlock

Seven taps on the cash readout.

```
DEV_TAPS  := 7
DEV_TAP_WINDOW := 2.0     # seconds; a longer gap resets the count
```

The window is not decoration. The flag persists forever once set, so without it
seven idle taps spread across a two-hour session would arm the panel by accident
and there would be no way to put it back except wiping the save.

**The cash label has to opt into input.** `Label` defaults to
`MOUSE_FILTER_IGNORE`, so it receives nothing today. It becomes
`MOUSE_FILTER_STOP` with `custom_minimum_size = Vector2(200, 88)`. The text still
draws top-left, so **nothing moves on screen** — the change is a comfortable
88-unit-tall target where there was a 39-unit one. The rate and clock labels sit
inside that rect and keep `MOUSE_FILTER_IGNORE`, so taps fall through to the cash
label rather than being eaten.

This is the one place a touch target is deliberately *not* a discoverable
control, so the usual "44pt and reachable" rule is about reliability rather than
discovery, and it is satisfied.

---

## 3. Where the flag lives — the `meta` block, and NOT a version bump

`Meta` gains one field:

```gdscript
var dev_unlocked: bool = false
```

carried by the pair that already exists:

```
to_dict()  ->  {"blueprints": …, "runs": …, "spent": {…}, "dev": true}
restore()  ->  dev_unlocked = (typeof(d.get("dev")) == TYPE_BOOL) and d["dev"]
```

**This is deliberately not save format v5.** The brainstorm chose "in the save
file" over a separate `user://` file, for one file rather than two — and the meta
block delivers exactly that at none of the cost, because it is a dictionary
`Meta.restore` already validates key by key and already tolerates absent and
malformed shapes without throwing. So:

- `SaveCodec.VERSION` stays **4**. `SUPPORTED_VERSIONS` is untouched.
- No `_migrate_to_v5`. A v4 save without the key restores `dev_unlocked = false`,
  which is the correct answer for a save written before the feature existed.
- The generative poison sweep needs no new case: `meta` is already swept
  recursively, and the type guard above cannot throw on any of `{} [] null
  "abc" 1e400 -1 NAN`.
- The rule that the sweep asserts for `meta` — *never refuses, building
  survives* — stays true by construction.

Two consequences worth stating because they are behaviour, not accident:

- **A demolish keeps DEV unlocked.** `Prestige.demolish` clones the Meta through
  `to_dict`/`restore`, so the flag rides across with `blueprints` and `spent`.
  Correct: rebuilding is a game action, not a factory reset.
- **`Reset save` re-locks DEV**, because it clears the file the flag lives in.
  Accepted in the brainstorm, and the seven taps are three seconds.

---

## 4. The panel

Shaped like `PrestigePanel` and for the same reasons: a full-screen overlay
wrapping a `ScrollContainer`, **the topmost child** so nothing draws through it,
inset from the safe area, closed by a scrim tap. 88-unit rows.

`ui/dev_panel.gd`, `class_name DevPanel extends Control`.

```gdscript
signal cash_requested(amount: float)
signal earnings_requested(amount: float)
signal blueprints_requested(amount: int)
signal speed_requested(multiplier: int)
signal unlock_requested(level: int)
signal reset_requested()
```

It **emits, never mutates** — the same rule `PrestigePanel` follows, for the same
reason: several of these actions touch persistent state and must be written
immediately, and `game_root` owns the save.

| row | effect | why it is written this way |
| --- | --- | --- |
| `+$10K cash` | `economy.cash += 10000.0` | |
| `+$10K earned` | `cash += 10000.0` **and** `lifetime_earnings += 10000.0` | |
| `+5 Blueprints` | `meta.blueprints = mini(meta.blueprints + 5, Meta.MAX_BLUEPRINTS)` | the clamp mirrors `Prestige.demolish`, so the in-memory and on-disk bounds stay one statement |
| `Speed 1x / 2x / 4x` | §5 | |
| `Fit upgrades → L1 / L2 / L3` | §6 | |
| `Reset save` | `SaveStore.clear()`, fresh `GameState`, `_rebuild_views()` | |

**The two money rows are separate on purpose, and this is the load-bearing part
of the whole design.** `Economy.accrue()` adds to `cash` *and*
`lifetime_earnings`, and `lifetime_earnings` is the exact field
`Prestige.yield_for` consumes. A single "give me money" button calling `accrue`
would mint Blueprints on every use, so a cheated run's Blueprint count would mean
nothing — and bounding that field is what the whole of the prestige spec's §9
exists to do. So:

- **`+$10K cash` must not call `accrue`.** It writes `cash` directly. The yield
  is unchanged, and a save cheated this way still reports an honest one.
- **`+$10K earned` is the prestige tester**, and is labelled as such on the
  button (`+$10K earned (raises yield)`), because a row that silently moves the
  Blueprint conversion is the kind of thing that gets mistaken for a bug.

`Reset save` is the only irreversible-looking action here, but it is **not**
given a Confirm/Cancel pair. The prestige REBUILD has one because it destroys a
run the player earned; this panel is reached by seven deliberate taps and every
row in it is a cheat. A confirmation on one row and not the others would suggest
the others are safe.

---

## 5. Speed multiplies EXECUTED ticks, not requested ones

```gdscript
var _speed: int = 1                     # 1, 2 or 4; session-only

# in _physics_process
var ticks := state.clock.take_ticks(delta)
if ticks > 0:
    state.tick(ticks * _speed)
```

**`SimClock.MAX_TICKS_PER_FRAME` is not touched**, and that is the point. It
clamps `take_ticks` to 8 so a frame hitch drains the accumulator instead of
spiralling, and `discarded_seconds` records what was forfeited. Raising it to
reach 4x would trade a hitch guard for a debug feature.

The naive alternative is worse than it looks. At 60 fps the sim wants
`0.05 s / (1/60)` ≈ **3.33 ticks per frame**, so asking the clock for 4x means
13.3 against a cap of 8 — the button would say 4x and silently deliver **2.4x**,
which is exactly the sort of quiet lie the balance work has been fighting.
Multiplying the granted count instead makes 4x really 4x and leaves the clamp
doing its job.

`clock.ticks_executed` advances by the multiplied count (each `_tick_once` calls
`note_ticks(1)`), so the day, the traffic buckets and the metrics all speed up
together — which is what "speed up the game" has to mean.

**Session-only.** `_speed` resets to 1 on launch and is not saved. A persisted 4x
is a bug report waiting to happen.

---

## 6. Fitting upgrades, and the two ids it must skip

```gdscript
for id in state.upgrades.ids():
    if id == "floor" or id == "shaft":
        continue
    state.upgrades.grant_level(id, level, state.building)
```

**`floor` and `shaft` are excluded, and it is not tidiness.** `grant_level`
deliberately never calls `_apply` — its docstring says so, because on the decode
path applying structural effects grows a building past its own saved `floors`
array. So granting `floor` level 3 would claim three floors had been bought while
the building still had six, and the next autosave makes that desync durable:
`restore_levels` would put `level_of("floor")` at 3 against a 6-floor building,
and the purchasable cap arithmetic would then be measured against a lie.

`ManagementView` already skips exactly these two ids, for the same underlying
reason — they are bought on the board, not in a list.

`grant_level` clamps to `[0, max_level]`, so `L3` on a hardware upgrade whose
`max_level` is 1 fits it once and stops. Cars are synced, so `speed`, `doors` and
`capacity` take effect on the board immediately.

**It grants, it does not charge.** No cash is spent, which is the whole point.

---

## 7. `game_root`

```gdscript
var _dev: DevPanel
var _dev_taps: int = 0
var _dev_last_tap: float = 0.0
var _speed: int = 1
```

- `_dev_button` is built beside `_view_button`, 88 wide, at
  `_view_button.position.x - 96`, and is **visible only when
  `state.meta.dev_unlocked`**.
- `_rebuild_views()` gains `_dev` alongside `_prestige`, and both are moved above
  the HUD — `_prestige` and `_dev` are overlays, `panel` is a sheet, and §11 of
  the prestige spec explains why those want opposite sibling orders.
- Every handler that mutates persistent state calls `save_now()` immediately:
  the Blueprint grant, the unlock itself, and `Reset save`. Cash, earnings, speed
  and upgrade grants ride the ten-second autosave like ordinary play.

---

## 8. Tests

**`tests/test_meta.gd`**
- `dev_unlocked` defaults false; round-trips through `to_dict`/`restore`.
- A non-bool `dev` (`{} [] "abc" 1 null`) restores **false without throwing**.
- A Meta with no `dev` key restores false — the pre-feature save.

**`tests/test_save_codec.gd`**
- `SaveCodec.VERSION` is still **4** — pins the deliberate absence of a bump.
- A v4 save with `dev: true` round-trips it.
- The existing recursive poison sweep covers the new key by construction; assert
  it still reports non-null with the building intact for every poison on
  `meta.dev`.

**`tests/test_prestige.gd`**
- A demolish carries `dev_unlocked` across to the fresh run.

**`tests/test_board_input.gd`** (scene level)
- Six taps on the cash label reveal nothing; the seventh reveals DEV.
- Taps more than `DEV_TAP_WINDOW` apart do not accumulate.
- The unlock survives a save round trip, and DEV is visible on the next boot.
- `+$10K cash` raises cash and leaves `Prestige.yield_for` **unchanged** — the
  test that would catch someone "simplifying" the two money rows into one.
- `+$10K earned` raises both, and the yield with them.
- `Fit upgrades → L2` leaves `floor_count` and `cars.size()` untouched while
  `level_of("speed")` reaches 2 and the cars are synced to it.
- `Speed 4x` runs four times the ticks of `1x` over the same delta.
- `Reset save` returns a 6-floor building and clears the save file.
- The DEV panel is the topmost child while open, like the prestige panel.
- **The pager buttons are gone and sideways dragging still pages the strip** —
  `test_a_sideways_drag_pans_across_the_shafts` already covers the second half;
  the first is a new assertion that `_prev_shaft`/`_next_shaft` no longer exist.

---

## 9. What deliberately does not change

- **`SaveCodec.VERSION` stays 4.** §3.
- **`SimClock.MAX_TICKS_PER_FRAME` stays 8.** §5.
- **`Economy.accrue()` is not called by any dev action.** §4.
- **`grant_level` still never calls `_apply`.** §6 works around it rather than
  weakening it; the decode path depends on that guarantee.
- **The prestige panel's Confirm/Cancel pair.** It guards a run the player
  earned. Nothing in the dev panel is in that category.
- **The pager label and `_refresh_pager()`'s visibility rule.** §1.
