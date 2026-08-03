# Prestige: demolish, Blueprints, and a ten-floor first run

**Status:** proposed, not agreed. Nothing here is built.
System **S5** of `2026-08-03-backlog-systems-design.md`, the first entry in that
document's build order, plus its decisions 12, 13 and 14.

**Provenance.** Two independent drafts of this spec were written and reviewed
against the code twice each. This document merges them and fixes what neither
caught. Where a claim replaces something a draft asserted, the correction is
stated rather than silently applied — a spec that quietly drops a wrong number
teaches nobody why it was wrong.

**Revision 2.** A six-seat review panel (two Codex personas, a Simplifier, a
Pentester, and two Skeptics on different models) read r1 against the code. It
found two genuine contradictions in §9, a Blueprint-minting hole on the demolish
refusal path, a poisoning route into the prestige input through an adjacent
unvalidated field, and — fairly — several arithmetic and citation slips of the
exact kind this document criticises elsewhere. All are fixed below and marked
**[r2]**. Nothing in the balance derivation changed; two reviewers independently
re-ran the simulation and reproduced §2 and §6.

A run ends today by running out of building: twenty floors, roughly 6.5 hours,
and then nothing. This adds the loop the base design has always assumed (§4, §11
milestone 5): demolish what you built, convert the run's earnings into
**Blueprints**, spend them on a permanent tech tree, and start again.

The balance in §2 and §6 is produced by `2026-08-03-prestige-ladder-sim.py`,
which sits beside this file. It validates its own supply model against the
cost-curve spec before it is used for anything. Run it; do not trust the tables.

---

## 0. Scope

**Ships:** the demolish action, the Blueprint currency and its conversion, a
five-node tech tree, the floor cap becoming a per-run number that starts at 10
and ladders to today's 20, save format v4, and the UI to drive all of it.

**Does not ship, deliberately:**

- **A cap above 20 floors.** §6 shows a rate-optimal player leaving a run at
  12–15 floors and a completionist needing 5+ hours to fill 20. Rungs promising
  25/30/35/40 would sell a ceiling nobody reaches, and §14 item 1 owns the
  unblocking. **The ladder must still reach 20**, because today's game already
  delivers 20 floors and a prestige system that lowers the reachable ceiling is
  a downgrade wearing a progression system's clothes.
- **Eras.** The base design ties era advancement to Structure nodes (§4) and
  gives each era its own art, tenant set and new rule (§3). That is a content
  programme, not a mechanic. Era 2 becomes a later node on a branch this spec
  builds.
- **The Human and Automation branches.** Decision 14 says only structure and
  mechanicals persist. §4 says what that costs and §14 item 5 says what it
  leaves orphaned.
- **A starting-floors node.** Cut, for four reasons in §4.
- Offline earnings and the catch-up integrator — still §9.1's problem.

**Prerequisite, not a footnote:** `SaveStore.save()` must become a real replace
before demolish ships. See §11.

---

## 1. The numbers that already exist

Three constants already describe the ceiling, and they were deliberately split:

| number | where | means |
| --- | --- | --- |
| `Building.MAX_FLOORS = 40` | `sim/building.gd:14` | structural — the board's limit |
| `floor.max_level = 14` | `data/upgrades.json` | purchasable — 6 + 14 = 20 floors |
| `START_FLOORS = 6` | `game/game_root.gd:9` | where a building begins |

The cost-curve spec §5 split the second from the first on purpose and wrote down
why: *"What this spec lowers is the purchasable ceiling, not the structural one.
They are now deliberately different numbers."* That gap is the room this ladder
lives in.

What changes is that **the purchasable cap stops being a constant.** It becomes a
value the persistent tech tree supplies, between 10 and 20.

**`data/upgrades.json` is not edited at all.** With the ladder topping out at 20,
`floor.max_level = 14` *is* the top rung, and the cost-curve spec's §5 note stays
true word for word.

> **Correction to both drafts.** One raised `floor.max_level` to 34 (to promise 40
> floors again); the other lowered it to 4 *and* raised `floor.growth` 1.10 → 1.24
> to compensate for the shorter ladder. Both are rejected. The growth change is
> the more dangerous of the two: at 1.24 the thirtieth floor purchase costs
> `200 × 1.24²⁹ = $102,390` and the ladder cumulates past $500,000 — reintroducing
> the exponential-outruns-linear-income failure the cost-curve spec was written to
> eliminate, in a spec whose own §1 still promised rungs at 25/30/35/40. Leaving
> the file alone is not laziness; it is the only option that keeps an agreed,
> implemented spec true.

**The saturation guard is untouched and the arithmetic is worth restating
correctly**, because one draft got it wrong twice: the spawner's guard is
`Building.MAX_FLOORS (40) × largest_bucket`, and `largest_bucket()` is computed
from data, not a constant. Its real value is **3.0** (`office`, hour 8, in
`data/tenants.json`), so the worst case is `40 × 3.0 = 120` against
`SimClock.TICKS_PER_SIM_MINUTE = 600` (`sim/sim_clock.gd:16`; the guard itself is
`TenantCatalog.largest_bucket()` at `sim/tenant_catalog.gd:157`, pinned by
`tests/test_tenant_catalog.gd`). `Building.MAX_FLOORS` stays 40 forever; the
ladder is a cap on the *purchasable* cap and never touches the constant the
saturation arithmetic is sized against.

---

## 2. The conversion, and the degenerate strategy it has to avoid

### 2.1 A bare square root pays you not to build

Both drafts used `blueprints(E) = floor(sqrt(E / D))` for some divisor `D`, and
both argued from the concavity that rebuilding early beats finishing the
building. That is correct, and neither followed it to the end. **Simulated, the
rate-optimal exit under a bare square root is nine minutes, at six floors:**

```
conversion            cap   exit  floors   BP   BP/h
sqrt(E/100)            10   0:09       6    1   6.67
sqrt(E/100)            15   0:09       6    1   6.67
sqrt(E/100)            20   0:09       6    1   6.67
```

A player who demolishes every nine minutes earns **6.67 BP/hour**; a player who
builds a proper two-hour run earns **2.0**. The optimal strategy is to never
build anything, which makes the prestige loop a button-mashing exploit and the
cap ladder decorative.

This is not fixable by changing the divisor. Scaling `D` scales the exit time but
not the shape — the first Blueprint is always the cheapest one, so leaving
immediately after it is always rate-optimal. **The scale invariance has to be
broken.**

### 2.2 The conversion that ships

```
blueprints(E) = floor( sqrt( max(0, E − DEMOLITION_FLOOR) / EARNINGS_PER_BLUEPRINT ) )

DEMOLITION_FLOOR       = 900.0
EARNINGS_PER_BLUEPRINT = 100.0
```

where `E` is **the run's** earnings — `Economy.lifetime_earnings`, which today
already means "since this `GameState` was constructed" and after this spec means
"since the last demolish".

A flat $900 of earnings pays for the demolition itself; past that the marginal
law is unchanged and still legible:

> **n Blueprints need $900 + $100n² of earnings, so the n-th one costs $100(2n − 1).**

| Blueprints | earnings needed | the n-th one costs |
| --- | --- | --- |
| 1 | $1,000 | $100 |
| 2 | $1,300 | $300 |
| 3 | $1,800 | $500 |
| 4 | $2,500 | $700 |
| 5 | $3,400 | $900 |
| 10 | $10,900 | $1,900 |
| 20 | $40,900 | $3,900 |

Each Blueprint still costs $200 more than the one before it — the property that
made the square root the right family in the first place (base design §4), and
which a logarithm does not have. With the offset:

```
conversion            cap   exit  floors   BP   BP/h
sqrt((E-900)/100)      10   2:25      10    4   1.66
sqrt((E-900)/100)      15   2:19      12    4   1.73
sqrt((E-900)/100)      20   2:19      12    4   1.73
```

Runs settle at **~2h20**, the first run reaches its 10-floor cap, and the exploit
is gone.

**Why 900, stated as the trade it is. [r2]** r1 claimed 900 was "the smallest
round offset that achieves both". That is false — 700 and 800 also kill the
degeneracy and also leave `height` doing real work. The honest argument is the
size of the incentive to climb the ladder rather than re-run the 10-floor board,
which the simulation now prints:

| offset | cap-10 BP/h | cap-15 BP/h | height inert? | gap |
| --- | --- | --- | --- | --- |
| 600 | 1.89 | 1.89 | **yes** | 0.0% |
| 700 | 1.80 | 1.83 | no | 1.8% |
| 800 | 1.71 | 1.78 | no | 3.7% |
| **900** | **1.66** | **1.73** | no | **4.3%** |
| 1000 | 1.60 | 1.69 | no | 5.3% |

At `600` the rate-optimal player stalls at 10 floors forever and the `height`
nodes buy nothing — worse than an exploit, because it is invisible. At `700` the
1.8% gap is inside the model's own noise, so a player has no reason to feel the
ladder. `900` is where the gap becomes a signal while the first run stays at
~2h25. `1000` widens the gap further and costs run length; that is the direction
to move if playtesting says the ladder reads as optional, and it is a
one-constant change.

**The gate is 1 Blueprint**, per the base design: *"The demolish action is gated
on yielding at least 1 Blueprint … Without the gate a new player can wipe a run
for nothing, which would be a self-inflicted fail state."* That is now **$1,000**
of earnings, about 70 minutes on a first run. The panel shows the shortfall the
whole way (§10), so the gate teaches rather than blocks.

### 2.3 `E` is per-run, and this is the load-bearing half

**`lifetime_earnings` resets on demolish.** One draft made it cumulative across
every run ever played and granted `floor(sqrt(total)) ` on each demolish, added
to the existing balance. That mints Blueprints without limit:

```
earn $5,000 → demolish → +7 BP  (balance 7)
demolish again immediately, lifetime still $5,000 → +7 BP  (balance 14)
again → 21 …
```

Demolish costs nothing but a run you are discarding anyway, and the gate only
asks for 1 BP, so the whole 94-Blueprint tree falls in under a minute. Per-run
`E` has no such hole: after a demolish `E` is 0 and a second demolish yields
nothing. §12 pins this with a test that fails loudly if the field is ever made to
persist.

If a cumulative reading is ever wanted, the only safe form is
`grant = yield_for(total) − already_granted`, with `already_granted` persisted.
That is strictly more state for no gameplay difference, which is why it is not
what ships.

### 2.4 The clamp, in float space

```gdscript
const MAX_YIELD := 1_000_000_000

static func yield_for(earnings: float) -> int:
    return int(minf(sqrt(maxf(earnings - DEMOLITION_FLOOR, 0.0) / EARNINGS_PER_BLUEPRINT),
                    float(MAX_YIELD)))
```

**The argument order in `maxf` is load-bearing and must not be tidied. [r2]**
`maxf(a, b)` returns `a > b ? a : b`, so `maxf(NAN - 900.0, 0.0)` returns `0.0`
and a NAN input is absorbed into a zero yield. Written the other way round,
`maxf(0.0, earnings - FLOOR)` returns `NAN`, and `minf(NAN, MAX_YIELD)` then
returns `MAX_YIELD` — a billion Blueprints from a poisoned save. §12 pins
`yield_for(NAN) == 0` so a future cleanup cannot silently flip it.

`mini()` takes ints, so clamping after the conversion does the out-of-range
`int()` cast *first*: `int(sqrt(1e308 / 100))` is `1e153` against an int64 max of
9.22e18. Out-of-range float→int is platform-defined — it saturates harmlessly on
arm64, and the ship target is a different toolchain (threadless WASM), so a
dev-machine test would pass either way. Clamping the float first removes the
question. `maxf` additionally guards a negative input to `sqrt`. The stored
`lifetime` field is separately validated finite at decode (§9).

### 2.5 What actually reads `lifetime_earnings`

`sim/save_codec.gd:104` encodes it, `:128` restores it, and
`tests/test_save_codec.gd:36-37` asserts the round trip with the comment
*"prestige is computed from this"*. The load-bearing claim is narrower than "no
one reads it": **no rule derives from it.** No gameplay code branches on the
value, `Economy.accrue()` (its only non-delivery writer) has zero production
callers, and `note_expiry` reduces cash without reducing it — so the yield is
gross delivered fares, unaffected by spending or by bad service. All three facts
stop being true the moment any non-delivery income ships.

---

## 3. What resets and what persists

Exhaustive against `SaveCodec.encode()`, because a field that is neither listed
nor considered is how a prestige system leaks value.

| state | on demolish |
| --- | --- |
| `economy.cash` | **0** |
| `economy.lifetime_earnings` | **0** — it *is* the yield input; §2.3 |
| `economy.combo`, `streak`, `riders_served` | reset |
| `building.floor_count` | back to `GameState.BASE_FLOORS` (6) |
| `building.cars` | back to `meta.starting_shafts()` cars |
| `upgrades` levels | reset, then raised to `meta.starting_level(id)` |
| `tenancy` | rebuilt from `GameState.DEFAULT_ROSTER` |
| `fitout` | every floor back to `BASE_TIER` |
| `auto` policies | every shaft back to MANUAL |
| `metrics` | empty |
| `clock.ticks_executed` | **0** — a new building opens at 06:00 |
| `spawner` seed | `GameState.BASE_SEED + meta.runs_completed` **after the increment below** — §7 step 4. **[r4]** Read pre-increment, run 2 draws `BASE_SEED + 0` and replays run 1's traffic forever; §12 asserts the literal `BASE_SEED + 1` after the first demolish rather than the symbolic form. |
| `version` | not run state; written by the codec |
| **`meta.blueprints`** | **+= yield** |
| **`meta.spent`** (node levels) | **kept** |
| **`meta.runs_completed`** | **+= 1** |

Everything in the top block resets because a **fresh `GameState` is
constructed**, not because a reset routine clears it. That is the whole argument
for building rather than wiping: `GameState.new` already initialises every
container from zero, so a wipe-in-place would be a second clearing path that can
only ever desync from the one construction uses.

**Class tiers resetting is what keeps decision 14's second half true.** `fitout`
returning to `BASE_TIER` means `TenantKind.requires_class` gates the roster from
scratch again, so every run genuinely re-earns its tenants and S3 stays a live
system rather than being exhausted after a few resets. "Tenancy rebuilt from
`DEFAULT_ROSTER`" alone does not establish that; the fitout row is what does.

**`career_earnings` is cut, not deferred. [r2]** r1 persisted it as a readout
nothing read, and left "show it or drop it" as an open item. That is a field with
no consumer landing in a **versioned** format, which is the one place an open item
is not free: adding a key to v5 later is a routine bump, while removing one that
shipped is not. It is dropped from `Meta`, from `to_dict()`/`restore()`, and from
the demolish. If a career readout is ever wanted it arrives with its panel row in
the same change, at which point it has a consumer and is no longer dead weight.

**The new seed is derived, not random**, so the game stays reproducible from a
save — the determinism `tests/test_traffic_spawner.gd` pins survives prestige
unchanged. `BASE_SEED` lives on `GameState`, not `game_root`; see §7.

---

## 4. The tree that ships

Five nodes, two branches. Every node's cost follows one law:

```
cost(level) = base × (level + 1)          # level is 0-indexed
```

**Structure**

| id | levels | each level | costs | total |
| --- | --- | --- | --- | --- |
| `height` | 2 | +5 to the floor cap (10 → 15 → 20) | 2, 4 | **6** |
| `shafts` | 3 | +1 starting shaft (1 → 4) | 5, 10, 15 | **30** |

**Mechanical**

| id | levels | each level | costs | total |
| --- | --- | --- | --- | --- |
| `motor` | 4 | +1 starting `speed` level | 2, 4, 6, 8 | **20** |
| `gearing` | 4 | +1 starting `doors` level | 2, 4, 6, 8 | **20** |
| `cabin` | 3 | +1 starting `capacity` level | 3, 6, 9 | **18** |

**94 Blueprints** to finish, against the ~4 BP a run of §6 — about 23 runs of
long tail, while the cap ladder itself is spent in two.

**No starting-floors node.** Both drafts had one; it is cut for four separate
reasons, any one of which would be worth a re-price and which together are worth
a deletion:

1. **It sells vacant floors.** `GameState.DEFAULT_ROSTER` is exactly six entries
   and `game_state.gd:65` takes `mini(floor_count, 6)`, so a 10-floor start is 6
   tenanted and 4 vacant — each needing a paid lease, and with
   `tenanted_count() >= MIN_FLOORS_FOR_TRAFFIC` the free-lease safety net does
   not apply.
2. **It is worth almost nothing.** The floors it skips are the *cheapest* on a
   1.10 curve — the first four total $928 plus $240 of leases, under two minutes
   of income at the point it would be bought.
3. **It changes the run's starting size**, which is the mutation that makes
   `SaveCodec.decode` refuse valid saves (§7 correction 1).
4. **It is the only part of this spec that contradicts base design §3 and §12**
   ("each era starts at 6 rows"; "prestige resets the board (6 of 40 rows)").

Cutting it means `starting_floors()` is always 6, no clamp against `height_cap()`
is needed, and the base design needs no revision. `shafts` keeps the
"start bigger" idea where it is worth real money.

**Every Mechanical node grants a *starting level* of an upgrade that already
exists.** It raises no ceiling and adds no effect: on a new run
`Upgrades._levels["speed"]` starts at `meta.starting_level("speed")` and the cars
are synced to it. The effect code, cost curve, annotations and save format are
all untouched.

**A node whose next level would change nothing is refused in the sim, not the
panel.** `Meta.is_zero_delta(id)` mirrors `Upgrades.is_zero_delta`, and
`Meta.buy()` refuses on it. `gearing` is the live case: `doors` reaches
`DOOR_TICKS_MIN` at level 8 and `gearing` tops out at 4, so it is currently
safe — but the refusal belongs where `sim/upgrades.gd:85` already puts it, under
a docstring ending *"so the refusal lives here"*, not in a view enforcing a rule
the sim does not hold.

**Two branches, not four.** Automation is the interesting omission and it is
deliberate: at eight shafts a full set of Auto-Dispatch licences costs
`200 × (2.6⁸ − 1) / 1.6 = $260,900`, by a wide margin the largest cash sink in
the game. Leaving it off means **every run re-earns its automation**, which keeps
a late run an active game rather than a spreadsheet that has already been solved.

---

## 5. Decision 12: branch is not the same as upgrade

> Decision 12: *"because 40 floors is unservable at base mechanicals, the player
> must buy both Structure and Mechanical to actually go taller."*

The premise is true and the conclusion is a **category error**: it concludes that
the *persistent branch* is required when the deficit closes with **in-run cash**.

Doubling speed and adding seats gets eight cars from 13.7 to ~32 trips/min
against a 40-floor building's 25.8 of demand, and costs
`speed → L4 = $370` plus `capacity → L2 = $348` — **$718**, about nine minutes of
a 40-floor building's income. Mechanical capability is not a wall.

So Mechanical earns its place on the tree for a different and better reason:
**it is what the player spends every run re-buying.** A node that skips that
re-purchase buys *time*, which is the only thing a prestige node can honestly
sell when the underlying upgrade is cheap.

Two figures worth stating because one draft got both wrong in the other
direction:

- Eight cars at level 0 supply `8 × 68.6 / F`, meeting `0.641F + 0.102` at
  **F = 29.2**. Base mechanicals cope to 29 floors — comfortably above this
  release's 20-floor ceiling, which is a second reason stopping the ladder at 20
  costs nothing.
- Eight cars at speed L4 / capacity L2 supply **~32/min**, not ~41. Supply does
  not scale linearly with speed, because door dwell is speed-independent. The
  model in §6 makes this checkable.

**Shafts are the expensive thing, and that is why the node exists but is not
required.** The last three shafts cost $94,171 against the 34-floor ladder's
$49,095 — **1.92×**, not "more than twice". Simulated (§6), a rational player
mostly routes *around* shafts by buying motors and doors instead, which is why
`shafts` is priced as the tree's long tail rather than its spine.

---

## 6. The ladder, simulated

`2026-08-03-prestige-ladder-sim.py` generates everything below. It **validates
before it is used**: the supply model

```
round_trip_s  = 2F / (20 × speed_floors_per_tick)  +  F × door_ticks / 20
trips_per_min = 60 × seats / round_trip_s
```

reproduces the cost-curve spec's supply column **exactly** at all five of its
data points (and both 40-floor figures to within the script's stated 1.0/min
tolerance — 174.5 against the doc's 174) **[r5]** (11.43, 7.62, 5.71, 4.29, 3.43 trips/min at 6/9/12/16/20 floors) and
both of its 40-floor figures (13.7/min for eight base cars, 174/min for eight
fully-upgraded ones). Demand is `0.641F + 0.102`, a least-squares fit to the same
table with residuals under 0.02/min. Fares are $3.09/trip, from $12.22/min over
3.95 trips/min at six floors. Leases are $60 (`data/tenants.json`).

The simulated player buys the cheapest thing that helps, every minute, cash
permitting: whatever most cheaply restores supply when supply is short, and a
floor plus its lease otherwise. **Combo is excluded**, so every earnings figure
is a floor, not a forecast.

**How big a floor, stated rather than waved at. [r2]** `Economy.credit_delivery`
applies `combo` to the very field the conversion consumes
(`paid = fare * combo; lifetime_earnings += paid`), and `COMBO_MAX = 10.0`
(`sim/economy.gd:9`). So `E` is understated by a factor in **[1, 10]**, and run
1's yield is somewhere in **[4, 15]** Blueprints against a `height` ladder that
costs 6 in total. At the top of that range the whole cap ladder is bought out of
run one and "the ladder is spent in two runs" becomes one run.

Two things bound the worry without removing it. The direction is safe — combo
accrues with time, so it pushes the rate-optimal exit *later*, reinforcing §2.1
rather than undermining it. And `note_expiry` resets combo to 1.0
(`sim/economy.gd:39-43`), so the 92%-served rows cannot sustain the cap. But the
100%-served rows have no modelled expiry at all, so the realised multiplier is
**unmeasured**, and it is a bigger lever on `E` than either the 1.8× class
multiplier or decision 19's fare change — both of which §14 already lists.
`COMBO_MAX` heads §14 item 2's list, and it must be measured against a real
run before `DEMOLITION_FLOOR` is treated as settled.

### The rate-optimal player — leaves when Blueprints/hour peaks

| run | cap | floors | cars | s/d/c | served | length | E | yield | spends |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 10 | 10 | 1 | 0/0/0 | 100% | 2:25 | $2,518 | **4** | `height` L1 → cap 15, `motor` L1 |
| 2 | 15 | 13 | 1 | 2/3/0 | 92% | 2:19 | $2,514 | **4** | `height` L2 → cap 20 |
| 3 | 20 | 13 | 1 | 2/3/0 | 92% | 2:19 | $2,514 | **4** | `motor` L2 |
| 4 | 20 | 13 | 1 | 2/3/0 | 92% | 2:18 | $2,506 | **4** | `gearing` L1 |
| 5 | 20 | 14 | 1 | 3/4/1 | 100% | 2:52 | $3,401 | **5** | `shafts` L1 |
| 6 | 20 | 15 | 2 | 2/1/0 | 100% | 2:50 | $3,411 | **5** | `motor` L3 |

### The completionist — fills the building, then leaves once the next node is funded

| run | cap | floors | cars | length | E | yield | spends |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 10 | 10 | 1 | 1:25 | $1,310 | **2** | `height` L1 → cap 15 |
| 2 | 15 | 15 | 1 | 3:09 | $3,827 | **5** | `height` L2 → cap 20 |
| 3 | 20 | 20 | 1 | 5:14 | $8,023 | **8** | `shafts` L1, `motor` L1, `gearing` L1 |
| 4 | 20 | 20 | 2 | 6:13 | $10,933 | **10** | `shafts` L2 |
| 5 | 20 | 20 | 3 | 11:24 | $23,433 | **15** | `shafts` L3 |
| 6 | 20 | 20 | 4 | 4:19 | $6,465 | **7** | `motor` L2, `cabin` L1 |

**Every row spends less than the same row earned, in both tables.** The script
now genuinely enforces this — `raise SystemExit` across the rate-optimal *and*
completionist walks. **[r4]** It is deliberately not `assert`: `python3 -O`
strips assertions, which would have quietly re-created the very false green this
check was added to answer. **[r2]** r1 claimed the assertion existed when the script
only printed a count and exited 0, and checked only one of the two tables: a
false green of exactly the shape §14 item 7 complains about. The check matters
because the single most common defect in a hand-written balance table is a row
that buys more than it could pay for — one draft's first table had run 5 spending
$121,214 against $33,000 of earnings, and the other's had run 1 reaching ten
floors (which costs $1,168 in floors and leases) on $524 of earnings.

**One honest caveat on the margin. [r2]** The affordability check compares spend
against **gross** `E`. `Economy.note_expiry` charges a fare per walker in *cash*
only (it does not touch `lifetime_earnings`, exactly as §2.5 says), and the
simulation omits that outflow. On the 92%-served rows it is ~$2/min — about $290
over a run whose modelled margin is $9 (run 2: $2,514 earned, $2,505 spent). The
excluded combo biases the other way and comfortably covers it in practice, but
the guarantee as stated is "spend < gross earnings", not "spend < spendable cash".

**Four things these tables say.**

1. **Run one is 1:25 to 2:25 and ends at the cap.** The cost-curve spec's "10
   floors at 1.3 h" is time to *ten floors*, and the numbers agree: the
   completionist fills the building at 1:25. A first loop measured in a couple of
   hours is a far better tutorial than a 6.5-hour one, and it is the strongest
   argument for shipping the 10-floor cap.
2. **The ladder is spent in two runs.** Both policies own cap 20 by run 2–3.
3. **The two policies are both viable, and neither dominates.** The rate-optimal
   player banks ~4 BP every 2h20; the completionist banks 8 in 5h14. Blueprints
   per hour favours leaving early (1.7 vs 1.5), which is the correct incentive for
   an idle game — but not by enough to make playing the building out feel wrong.
   That balance is what the §2.2 offset buys.
4. **Run length is stable for the rate-optimal player and grows for the
   completionist** — row 5's 11:24 is a player choosing to fund a 15-Blueprint
   node inside a single run instead of banking across two. That is a choice, not a
   wall, but §14 item 1 is where the underlying problem lives.

**What `base = 2` is calibrated against.** Run 1 yields 2–4 against `height` L1's
cost of 2; run 2 yields 4–5 against L2's 4. The cost law tracks the yield curve
because both are quadratic in the same variable — `cost = 2(n+1)` against a yield
growing as `sqrt(E)` on runs whose `E` grows roughly as the square. That is a
structural agreement rather than a fitted one, which is why it survived the table
being rebuilt three times.

### Run one is not a lock

Decision 13 says run one hard-caps at 10 floors and that shafts become a
second-run reveal. The cap is real; **the shaft lock is not, and should not be
added.** At 10 floors one car supplies 6.9 trips/min against 6.5 of demand — §6
row 1 shows 100% of demand served on one car. Shafts are irrelevant in run 1
because the arithmetic makes them irrelevant, not because a rule forbids them,
and a player who buys one anyway gets a small genuine improvement in wait times
rather than a disabled button. The teaching is identical; one version has a fail
state's shape and the other does not.

**And it must not ship early**, which is decision 13's real content: a 10-floor
cap with nothing behind it is a 1.5-hour wall where today's is 6.5 hours.
`height`'s level-0 value and the demolish action land in the same commit or
neither does.

---

## 7. The code

### `sim/meta.gd` — new, `class_name Meta extends RefCounted`

The persistent half of the game. Pure data plus the derivations; it knows nothing
about `GameState`, and `GameState` reads it, never the reverse.

```gdscript
const MAX_HEIGHT_CAP := 20           # this release's ladder top; NOT Building.MAX_FLOORS
const MAX_BLUEPRINTS := 1_000_000_000   # == Prestige.MAX_YIELD; see §9
const MAX_RUNS := 1_000_000

var blueprints: int = 0
var runs_completed: int = 0
var _spent: Dictionary = {}          # node id -> level
var _defs: Dictionary = {}           # node id -> {name, branch, base, max_level, note}

func load_defs(path: String) -> bool
func ids() -> PackedStringArray
func level_of(id: String) -> int
func is_maxed(id: String) -> bool
func is_zero_delta(id: String, up: Upgrades) -> bool   # [r2] see below
func cost_of(id: String) -> int                       # base * (level + 1)
func can_buy(id: String, up: Upgrades) -> bool        # affordable, not maxed, not zero-delta
func buy(id: String, up: Upgrades) -> bool

# Serialization. Without this pair SaveCodec cannot write the block without
# reaching into a private field.
func is_usable() -> bool                  # [r4] false until load_defs() succeeded;
                                          # backed by a stored flag, NOT by
                                          # `not _defs.is_empty()` -- see below
func to_dict() -> Dictionary               # [r4] deep -- never returns live _spent
func restore(data: Variant) -> bool       # ALL validation lives here; see §9

# The derivations. THE definitions -- the view annotates from these, so an
# annotation can never fabricate a cap by copying the formula.
func height_cap() -> int             # 10 + 5 * level_of("height"), <= MAX_HEIGHT_CAP
func starting_shafts() -> int        # 1 + level_of("shafts"), <= Building.MAX_SHAFTS
func starting_level(upgrade_id) -> int   # speed<-motor, doors<-gearing, capacity<-cabin
```

**`is_zero_delta` needs an `Upgrades`, and the signature must say so. [r2]** To
decide that `gearing` L4→L5 changes nothing, Meta must consult
`Upgrades.effect_value`, which is an **instance** method (`sim/upgrades.gd:129`)
even though its body reads no instance state. r1 gave the method no way to reach
it, so it had no implementable body. Two options, pick one in the plan: make
`effect_value` and `is_zero_delta` `static` on `Upgrades` (they qualify), or pass
the run's `Upgrades` in as above. The signature above assumes the latter because
it changes no existing code; `Meta.can_buy`/`buy` take the same parameter (the
block above is updated to match — **[r3]**, since r2 changed only
`is_zero_delta` and left `can_buy(id)` unable to evaluate the third of the three
conditions its own comment claims), and `ui/prestige_panel.gd` already holds the
state. §10's `game_root` call becomes `meta.buy(id, state.upgrades)`.

**`is_zero_delta` returns `false` for `height` and `shafts`. [r3]** They map to
no upgrade, so there is nothing to compare, and getting this wrong makes
**`height` permanently unbuyable** — the one node this whole spec exists for.
**[r4]** The real hazard is not `effect_value`'s return value:
`Upgrades.is_zero_delta` (`sim/upgrades.gd:163`) is guarded by `has_effect`
(`:151`), which is already false for `height`, `shafts` **and** for the
Mechanical *node* ids `motor`/`gearing`/`cabin` — none of which are Upgrades ids
at all. So `Meta` must map node id → upgrade id (`motor` → `speed`) **before**
consulting anything, and it is that mapping an implementer gets wrong. §12
already pins the id↔derivation agreement; this is the sentence that says which
direction the mapping runs.

**And it evaluates at the *Meta's* level, not the run's. [r5]** "Mirrors
`Upgrades.is_zero_delta`" plus a passed-in run `Upgrades` makes delegation
(`up.is_zero_delta("doors")`) the path of least resistance — and that reads the
**run's current** doors level (`sim/upgrades.gd:163-167`). A player whose run has
bought doors to L8+ (the `DOOR_TICKS_MIN` plateau) would see `gearing` refused as
zero-delta **even at gearing L0**, precisely while shopping the panel before a
demolish, though next run starts at doors ≤ 4 where the effect is real. The
correct form compares `effect_value(mapped_id, meta_level)` against
`meta_level + 1`. §12 pins it: *gearing is buyable while the run's doors sit at
the plateau*.

**The blueprint catalog path is injectable**, exactly as the tenant catalog is:
`load_defs` takes a path, `GameState._init` accepts a `blueprints_path`, and
`game_root` gains a `blueprints_path_override` beside the existing
`catalog_path_override` (`game/game_root.gd:17`). Without the seam the
malformed-file test in §12 has to mutate the shipped data file.

**`GameState._valid` must default to `false`. [r6]** `sim/game_state.gd:45` is
`var _valid: bool = true`. Verified on Godot 4.7: a constructor that errors
returns a **half-built object** with every field below the abort point at its
declared default, and the caller resumes normally — so any runtime error inside
`_init` yields a `GameState` whose `is_valid()` is **true** and whose `clock`,
`building` or `catalog` may be null. This spec makes that far worse than it is
today: §7 adds real work to `_init` (`load_defs`, `is_usable`, `set_max_level`,
five `grant_level` calls) and makes `is_valid()` the single enforcement point for
§8's fatal-data rule. A gate whose default is *pass* cannot do that job. Flip it:
`var _valid: bool = false`, set `_valid = true` as the **last** statement of
`_init`, and turn the existing `_valid = false` sites into early returns. One
line, and it converts every abort from "silently valid" to "refused".

**`Meta.is_usable()` must be a stored flag, not `not _defs.is_empty()`. [r6]**
`Upgrades.load_defs` — the precedent §7 points at — populates `_defs[id]` inside
its loop and `return false`s from inside it (`sim/upgrades.gd:30-43`), so a file
whose *third* node is bad leaves two valid entries behind and returns false. And
every §8 malformed rule is a mid-loop failure: duplicate id, `base` out of range,
`max_level` out of range, unknown `branch`. Under the obvious reading
(`not _defs.is_empty()`), a partial load reports **usable**, `ids()` returns a
subset, and `Meta.restore()`'s iterate-`ids()` rule then **drops every `spent`
entry for the missing nodes** — which the autosave persists ten seconds later.
That is exactly the silent tree loss this section exists to prevent, re-entered
through the check meant to prevent it. So: `is_usable()` returns a `_defs_loaded`
flag set true only on `load_defs`'s successful `return true`, and `load_defs`
**clears `_defs` on any failure**. Neither is derivable from the precedent.

**Every site that builds or copies a Meta checks the result and propagates
failure. [r4]** This is one rule, stated once, because r3 stated the guarantee in
prose (§8: "no 'skip the tree and play anyway' fallback") and left three paths
that ignore it:

- `GameState._init` checks `meta.is_usable()` **regardless of injection** (above).
- `Prestige.demolish` step 2 checks **both** `staged.load_defs()` and
  `staged.restore()`; either returning false means `return null`. Unchecked, a
  failed `load_defs` makes `restore`'s iterate-`ids()` rule drop every `spent`
  entry silently, and the demolish would then *save a Meta whose tree has been
  emptied* — permanent, unrecoverable loss of the thing this system exists to
  persist.
- `SaveStore.load_meta()` returns **null** on a failed defs load, and
  `game_root`'s cold-boot branch routes null into the existing error screen
  (`game_root.gd:74-78`, which already disables saving and physics, so the save
  file is preserved).

**The ordering invariant, which is a trap inside the fix above. [r4]**
`Upgrades.load_defs` sets `_levels[id] = 0` for every id it reads
(`sim/upgrades.gd:42`). A `Meta.load_defs` that mirrors it faithfully would
therefore **zero `_spent`** — so calling it *after* `restore()` silently wipes
the tree this rule exists to protect. Two requirements, stated together because
either alone is insufficient:

- **Defs load before any restore, on every path.** `salvage_meta`,
  `SaveStore.load_meta()` (including the no-save-file case, which must still
  return a defs-loaded empty Meta rather than a bare `Meta.new()`), `decode`'s
  meta build, and `demolish`'s `staged` all load first, then restore.
- **`Meta.load_defs` must not clear `_spent`** — or expose `has_defs()` and load
  only when absent. It reads definitions; it does not own player progress.

`SaveStore.load_meta(blueprints_path := "res://data/blueprints.json")` takes the
path, or `game_root.blueprints_path_override` cannot reach salvage and §12's
injectable-path test has nothing to inject into.

**It returns `null` on a defs failure, and the cold-boot branch must check it
before dereferencing. [r5]** r4 changed this contract and did not update the one
call site that receives it, so `salvaged.starting_shafts()` would abort `_ready`
*before* the `game_root.gd:74-78` guard the rule names — producing the black
screen §8 requires a named error screen for, in the exact scenario §8 legislates.
That is the fourth occurrence in this document's history of "fix one site, leave
the null-receiving sibling". **[r6]** The first attempt at the guard was itself
wrong — a bare `return` skips `game_root.gd:74-78` just as surely as an abort
does, since that branch sits *below* the cold-boot code inside `_ready`. The
snippet must draw the screen, clear `_saving_enabled` and stop `_physics_process`
itself, which makes §13's message parameterisation a **prerequisite** of this
branch rather than a follow-up.

**`to_dict()` and `restore()` must never alias `_spent`. [r4]** The staged clone
in §7 is independent only if the pair deep-copies at both ends. §9's
"iterate `ids()`" rule implies `restore` builds fresh storage, but nothing
forbade `to_dict()` returning the live dictionary — and a future tidy-up that
did so would re-create shared mutable state and quietly reopen the CRITICAL the
clone exists to close.

`load_defs` reading a file from `sim/` follows the precedent `Upgrades.load_defs`
and `TenantCatalog.load_from` already set. (The "no FileAccess" line is
`CLAUDE.md:37`, and it has meant "no *save* I/O" since Milestone 3 —
`sim/upgrades.gd:20`, `sim/tenant_catalog.gd:20` and `sim/traffic_spawner.gd:34`
all open files today.)

**`load_defs` must store `note`, which `Upgrades.load_defs` does not.**
`sim/upgrades.gd:36-41` keeps only name/base/growth/max_level, so
`Upgrades.note_of` (`:65-66`) indexes a key that is never set — a latent crash with
no callers today. §10's node rows render the note, so Meta's loader must keep it,
and `Upgrades.load_defs` should be fixed in the same pass rather than mirrored
faithfully into the same bug.

### `sim/prestige.gd` — new, `class_name Prestige extends RefCounted`

Static functions only. The one place that knows a run can end.

```gdscript
const MAX_YIELD := 1_000_000_000
const DEMOLITION_FLOOR := 900.0
const EARNINGS_PER_BLUEPRINT := 100.0

static func yield_for(earnings: float) -> int
static func can_demolish(state: GameState) -> bool     # yield_for(...) >= 1
static func demolish(state: GameState) -> GameState    # null when the gate refuses
```

**The order inside `demolish()` is load-bearing, and it took two revisions to
get right. [r3]**

```
1. bp = yield_for(state.economy.lifetime_earnings);  refuse if bp < 1
2. CLONE the Meta:  var staged := Meta.new()
                    if not staged.load_defs(state._blueprints_path): return null
                    if not staged.restore(state.meta.to_dict()): return null
                    # [r5] both bools checked HERE, in the block an implementer
                    # copies. Unchecked, a defs failure makes restore drop every
                    # `spent` level (it iterates ids()), and step 6 would then
                    # durably persist an emptied tree.
3. CREDIT THE CLONE ONLY:
       staged.blueprints = mini(staged.blueprints + bp, Meta.MAX_BLUEPRINTS)
       staged.runs_completed = mini(staged.runs_completed + 1, Meta.MAX_RUNS)
4. BUILD the fresh GameState against `staged`, seed = BASE_SEED + staged.runs_completed
5. VALIDATE: if not fresh.is_valid() -> return null. The handed state's Meta was
   never touched, so there is nothing to roll back.
6. return fresh          # the credit exists ONLY inside `fresh`
```

**Why a clone, having twice argued one was unnecessary.** r1 credited before
validating, which paid out on the invalid-catalog refusal. r2 moved the credit
last and claimed that made the operation atomic "with no clone" — true *inside*
`demolish()`, and false at the boundary that matters. `GameState` holds the Meta
**by reference**, so the moment `demolish()` returns, the credit is already
visible to the old run — and §11's next step can still fail. When it does:

- the old run plays on against a Meta credited with a yield it never spent, and
  `Meta.buy()` can spend it this session;
- worse, the 10-second autosave (`game_root.gd:268-270` → `SaveStore.save(state)`)
  then writes that credited Meta **beside the still-demolish-eligible building**,
  in one perfectly valid v4 payload. Storage failures on iOS are typically
  transient, so the next successful autosave makes the mint durable. Demolish
  again and the same `E` pays twice.

The clone removes the shared-mutable-state problem rather than sequencing around
it: the credit rides inside `fresh`, so it becomes real exactly when `fresh`'s
save commits, and a failure discards `fresh` entirely. §11's comment about the
old Meta being intact becomes true, rather than aspirational.

`mini(...)` at step 3 is not decoration: §9 clamps `blueprints` to
`MAX_BLUEPRINTS` at decode, so an uncapped credit could exceed a bound the next
load silently trims — the in-memory and on-disk invariants must be one statement.

§12 pins this with two assertions r1's suite lacked: on every refusal path
`blueprints` and `runs_completed` are unchanged, **and** on a *save* failure the
handed state's Meta is unchanged — which is the one the r2 shape would have
failed.

Returning `null` for a refusal matches `SaveCodec.decode`'s existing contract.

### `sim/game_state.gd`

Three constants move into the sim layer, because `game/game_root.gd` has **no
`class_name`** (line 1 is a bare `extends Control`) and `sim/` must not reach
into `game/` regardless:

```gdscript
const BASE_FLOORS := 6
const BASE_SHAFTS := 1
const BASE_SEED := 20260802
```

`game_root`'s `START_FLOORS` / `START_SHAFTS` / `START_SEED` become references.

`_init` gains **two** optional trailing parameters. `p_meta` goes *after*
`catalog_path`, because `tests/test_game_state.gd:208` pins the fourth position
as the catalog path:

```gdscript
func _init(floors: int, shafts: int, p_seed: int,
        catalog_path := "res://data/tenants.json",
        p_meta: Meta = null,
        blueprints_path := "res://data/blueprints.json") -> void:
    ...
    # [r4] The check is NOT conditional on p_meta. r3 guarded it with
    # `p_meta == null`, and after the salvage rewiring NO production path
    # constructs with a null Meta -- so the only enforcement of SS8's
    # malformed-data fatality sat on a branch nobody takes.
    meta = p_meta if p_meta != null else Meta.new()
    if p_meta == null and not meta.load_defs(blueprints_path):
        _valid = false
    if not meta.is_usable():        # true iff defs loaded; see Meta.is_usable()
        _valid = false
    building = Building.new(floors, shafts)          # verbatim -- see below
    ...
    upgrades.load_defs("res://data/upgrades.json")   # everything below is AFTER this
    _catalog_path = catalog_path                     # kept, so demolish can reuse it
    _blueprints_path = blueprints_path
    upgrades.set_max_level("floor", meta.height_cap() - BASE_FLOORS)
    upgrades.set_max_level("shaft", Building.MAX_SHAFTS - BASE_SHAFTS)
    upgrades.grant_level("floor", building.floor_count - BASE_FLOORS, building)
    upgrades.grant_level("shaft", building.cars.size() - BASE_SHAFTS, building)
    for id in ["speed", "doors", "capacity"]:
        upgrades.grant_level(id, meta.starting_level(id), building)
```

**Four corrections are packed into those lines.**

1. **`_init` does not resize the building.** An earlier draft had
   `Building.new(maxi(floors, meta.starting_floors()), maxi(shafts, ...))`. On the
   `SaveCodec.decode` path that expands a loaded building past
   `saved_floors.size()`, tripping the refusal at `save_codec.gd:156` — `decode`
   returns null, `game_root` starts a fresh game, and the 10-second autosave
   overwrites the only copy. **The saved size is the authority, full stop.** The
   Meta's starting size is applied by the callers that *begin* a run
   (`Prestige.demolish` and `game_root`'s cold-boot branch), never by `_init`.
2. **The caps are expressed against a constant baseline, not the current size.**
   `meta.height_cap() - building.floor_count` is a *level* budget measured
   against a *floor count*, and it is correct only at level 0. On reload,
   `save_codec.gd:124` rebuilds at the grown size and `:135` restores the
   cumulative purchase count on top, so a player who started at 6 with a cap of
   20 and bought 7 floors reloads to `max_level = 7` with `level_of("floor") = 7`
   — permanently capped 7 floors below what they paid for, with the ghost band
   silently no-opping. Against `BASE_FLOORS` the budget is the same number on
   every path.
3. **Granted size consumes its own price ladder.** `Upgrades.cost_of`
   (`upgrades.gd:76-80`) prices from `level_of`, so a run starting with four
   shafts would otherwise price the **fifth shaft at $500 instead of $5,324** —
   the exact limitation already documented for `--board=40x8` at
   `game_root.gd:159-166`, harmless for screenshots and a balance hole here.
   `grant_level` fixes it, and because `restore_levels` *overwrites* rather than
   maxes, a save still wins on reload exactly as its docstring argues for.
4. **The calls sit at the end of `_init`, after `load_defs`.** Following the
   snippet's visual order (`building` → `set_max_level`) writes a crash on an
   empty `_defs`.

`GameState` also keeps `_catalog_path` and `_blueprints_path`, which it currently
consumes and drops (`game_state.gd:47-58`) — without them `Prestige.demolish`
silently rebuilds against the shipped catalogs and defeats the overrides.

### `SaveCodec.decode` needs its own seam — the retained field cannot help it  **[r2]**

r1 claimed `save_codec.gd:124` "has the same latent bug today and is fixed by the
same field". **It is not.** `decode` is `static func decode(p_data: Dictionary)`
(`sim/save_codec.gd:117`) and *constructs* the first `GameState` from a
dictionary — there is no prior instance whose `_catalog_path` it could read. The
retained field genuinely fixes `Prestige.demolish`, which is handed a live state,
and does nothing here.

Left unfixed this is not cosmetic: §9's decode ordering names a `catalog_path`
that is undefined in `decode`'s scope, and §12's malformed-`blueprints.json` test
("through the injectable path … `decode` returns null") is **unwritable**, since
the seam stops at `GameState.new`.

The fix, named here rather than left to the implementer — **default-valued
trailing parameters**, which keep all 28 existing one-argument call sites in
`tests/` source-compatible:

```gdscript
static func decode(p_data: Dictionary,
        catalog_path := "res://data/tenants.json",
        blueprints_path := "res://data/blueprints.json") -> GameState
```

threaded through `SaveStore.load_state(catalog_path := …, blueprints_path := …)`
(signature at `game/save_store.gd:41`; the `decode` call it forwards to is `:52`) and `game_root`'s call (`game_root.gd:67`), which
already holds both override fields. **This signature change belongs in §12's
breakage list** as a scope item, even though it breaks no test.

**`decode` returning null on an invalid state is new behaviour.** It never calls
`is_valid()` today — and note `sim/game_state.gd:77-78` already *claims* it does
("SaveCodec.decode returns null rather than handing back a poisoned state"). That
docstring is currently aspirational; this spec is the right moment to make it
true, and §12 pins it.

### `sim/upgrades.gd`

Two additions:

```gdscript
## Blueprints raise per-run ceilings. data/ holds the ladder's top rung; the live
## cap is whatever the run was started with.
func set_max_level(id: String, level: int) -> void

## Levels the run BEGINS with -- granted size and Meta-granted mechanicals.
## Takes the Building because Upgrades owns no cars: _sync_car() needs an
## ElevatorCar (upgrades.gd:169), so a signature without it cannot keep its
## promise. Clamps to [0, max_level].
##
## It sets _levels[id] and _sync_cars each car. It NEVER calls _apply() and never
## changes building.floor_count or cars.size(). [r3] An implementer mirroring
## purchase() (upgrades.gd:82-94) would call building.add_floor() fourteen times --
## and on the decode path, where _init is handed the SAVED size, that grows the
## building past saved_floors.size() and every reload silently adds floors.
func grant_level(id: String, level: int, building: Building) -> void
```

**Both corrections here are r2.** r1's `grant_level(id, level)` had no way to
reach a car, so a Meta with `motor: 4` would report `level_of("speed") == 4`
while every car on the fresh board ran at base speed — the node silently doing
nothing, which is the exact failure §12's id↔derivation test exists to catch in
a different guise. And the clamp is not theoretical: `GameState.new(1, 1, 7)`
exists today (`tests/test_auto_dispatch.gd:142`), so
`grant_level("floor", floor_count - BASE_FLOORS)` passes **−5**. A negative level
makes `cost_of` price below base and `is_maxed` unreachable. `set_max_level`
clamps to `[0, ∞)` for the same reason, matching `restore_levels`'s existing
`maxi(..., 0)` discipline (`sim/upgrades.gd:48-51`).

`is_maxed()` (`sim/upgrades.gd:71`) is the only reader of `max_level`; `purchase`
gates on it at `:83`. **`cost_of()` does not read it** (`:76-80` reads base, growth and
`level_of`), so an implementer should not go looking for a change there.

One consequence worth stating because an implementer may "fix" it into a bug:
grants apply at construction only, and `restore_levels` overwrites, so **buying a
Mechanical node mid-run does nothing until the next demolish.** That is
intended — §10 says so on the panel.

---

## 8. `data/blueprints.json`

```json
{
  "comment": "cost = base * (level + 1). Effects are applied by id in meta.gd.",
  "nodes": [
    { "id": "height",  "name": "Taller Foundations", "branch": "structure",
      "base": 2, "max_level": 2, "note": "+5 floors you may build" },
    { "id": "shafts",  "name": "Sunk Shafts",        "branch": "structure",
      "base": 5, "max_level": 3, "note": "start with one more shaft" },
    { "id": "motor",   "name": "Standard Motor",     "branch": "mechanical",
      "base": 2, "max_level": 4, "note": "start with Stronger Motor fitted" },
    { "id": "gearing", "name": "Standard Gearing",   "branch": "mechanical",
      "base": 2, "max_level": 4, "note": "start with Faster Doors fitted" },
    { "id": "cabin",   "name": "Standard Cabin",     "branch": "mechanical",
      "base": 3, "max_level": 3, "note": "start with a Bigger Car fitted" }
  ]
}
```

Numeric coefficients over a fixed set of code-defined shapes, no expression
strings — the same rule `data/upgrades.json` follows, for the same reason.

**"Malformed" needs a definition, or the guard is decorative. [r2]** r1 said a
malformed file is fatal and never said what malformed meant. This file sets the
prices of a *persistent* currency, so a bad value is not merely a crash risk:
`"base": -2` makes every level of that node affordable at 0 Blueprints, and
`blueprints -= cost` then **credits** 2 BP per purchase — an unbounded mint from
a shipped-data typo. `load_defs` returns false unless every one of these holds:

- `nodes` is an Array, non-empty, and bounded (≤ 64 entries).
- Each entry is a Dictionary with `id`, `name`, `branch`, `base`, `max_level`.
- `id` is a non-empty String, and **unique** across the file.
- `branch` is exactly `"structure"` or `"mechanical"`.
- `base` is finite, integral, and in **`[1, 1_000_000]`**. The upper bound is not
  tidiness: `Meta.cost_of` is `base × (level + 1)` returning `int`, so
  `{"base": 1e18, "max_level": 64}` computes `1e18 × 65`, **wraps int64 negative**,
  and `can_buy` (`blueprints >= cost`) is then true at a zero balance while
  `blueprints -= cost` *credits*. That is the same unbounded mint the `-2` rule
  closes, re-entered through overflow. The bound's job is to keep
  `base × (max_level + 1)` overflow-free.
- `max_level` is finite, integral, and in `[1, 64]`.
- `name` and `note` are Strings (`note` optional, defaulting to `""`).

Same type-before-value ordering as §9, and for the same reason. §12 tests the
negative base and the duplicate id specifically — they are the two that convert a
typo into a currency exploit.

A malformed `blueprints.json` is then fatal, exactly as a malformed
`tenants.json` already is:

- `GameState` sets `_valid = false` and does not start the sim (`is_valid()`, the
  contract at `sim/game_state.gd:79`).
- `SaveCodec.decode` returns `null` rather than propagating a poisoned state.
- `game_root._ready()` shows the existing **named error screen**, now naming the
  blueprint file.
- `Prestige.demolish` refuses rather than swapping in a dead run.

There is no "skip the tree and play anyway" fallback. Blueprints gate the cap and
the second run; a game that cannot load its own tech tree is broken, and the
"blank board reads as a hang" reasoning that produced the error screen applies
unchanged. **This is a different case from a malformed *save*, which must not
refuse — see §9.**

---

## 9. Save format v4

```
const VERSION := 4
const SUPPORTED_VERSIONS := [1, 2, 3, 4]
```

`encode()` gains one top-level key, from `Meta.to_dict()`:

```json
"meta": { "blueprints": 7, "runs": 3, "spent": { "height": 2, "motor": 1 } }
```

The Meta rides in the same file as the run. It has to: a demolish must persist
the credited Blueprints and the discarded building in **one** write, or a crash
between two writes either duplicates or destroys the yield.

### Decode's ordering

`save_codec.gd:122-124` builds the `GameState` before it looks at anything else,
and every cap derivation lives in `_init`. So the Meta must exist first, and
grandfathering must run *after* migration, because v1 and v2 spell the key
`row_count` — reading `floor_count` first yields 0 and grants a 20-floor v2 save
a cap of 10. Stated verbatim, the required order is:

```
_migrate_to_v3  ->  _migrate_to_v4  ->  _is_usable
  ->  build/validate/grandfather the Meta
  ->  GameState.new(SAVED floors, SAVED shafts, seed, catalog_path, meta,
                    blueprints_path)          # [r5] r4 dropped the last argument
  ->  restore_levels  ->  cars  ->  floors  ->  policies
```

**Validation cannot start after migration, because migration itself throws.
[r4]** The order above says migrate-then-validate, and `_migrate_to_v3` casts
`version` at `sim/save_codec.gd:41` and assigns `levels` to a *typed* Dictionary
at `:55` — both before any check runs. So `{"version": {}}` or
`{"levels": 5}` aborts the whole call stack (see the crash-class table below)
before `decode` can return null and before `salvage_meta` can rescue anything.
A **type preflight** therefore runs first, ahead of migration:

```
preflight (top-level types only)  ->  _migrate_to_v3  ->  _migrate_to_v4
  ->  _is_usable  ->  build/validate the Meta  ->  GameState.new(...)
```

The earliest conversion is **not** `floor_count`: `decode` opens with
`_migrate_to_v3(p_data)` (`sim/save_codec.gd:118`) whose first statement is
`int(data.get("version", -1))` (`:41`), re-converted at `:206`. Preflight refuses
anything whose top-level shape cannot survive migration:
`data` is a Dictionary; `version` is a finite integral number; **`floor_count`
is a finite integral number in `[1, Building.MAX_FLOORS]`**; `levels`, `cars`,
`floors`, `policies` are of their declared container types when present.
**[r5]** `floor_count` was omitted from r4's list even though `{"floor_count": {}}`
is the worked example the whole crash-class table is built around — and its
conversion is at `sim/save_codec.gd:213`, *inside* `_is_usable`, so the preflight
is the only place under the new ordering where that check can live.
**`meta` is deliberately NOT preflighted. [r5]** r4 included it, which
contradicts §9's own rule that an absent *or malformed* v4 meta yields
`empty_meta()` and decodes successfully — a non-Dictionary `meta` would have
been refused by preflight and rescued by §9 simultaneously. `Meta.restore()`
already handles every malformed shape without throwing (it type-checks before
`maxi`, and iterates `ids()` rather than the parsed keys), so `meta` needs no
preflight and must not get one. It performs no clamping and no semantic checks — those stay where §9
puts them. Without it, the generative sweep §12 specifies fails on its very
first key.

**`_migrate_to_v4` is a separate function, not a phase appended inside
`_migrate_to_v3`.** That function early-returns at `version >= 3`
(`sim/save_codec.gd:40-42`), so a v4 phase nested inside it would never run for
the v3 saves that need it most.

### Two paths, two names — never both called "grandfather"  **[r2]**

This is r1's worst defect: it used one word for two behaviours and then wrote a
test for each, which could not both pass. It said *"at `version == 4` an absent
meta is malformed, not legacy"*, then *"a malformed meta falls through to the
grandfather path"*, then *"`meta` is `TYPE_DICTIONARY`, else grandfather"* — and
`data.get("meta")` on an erased key is `null`, which is not a Dictionary, so an
erased v4 meta **was** grandfathered: precisely the outcome the first rule
forbade, and the one r1 itself called "worse" because `spent` survives every
future demolish. A tampered — or merely truncated — v4 save would have been
handed `height` L2 for free, permanently.

The two behaviours are separate functions with separate names, and the rule is
one line:

```
legacy_meta(floor_count) -> height levels from the ladder inverse   # version <= 3 ONLY
empty_meta()             -> blueprints 0, runs 0, spent {}          # version == 4, absent OR malformed
```

> **Grandfather grants are gated on `version <= 3`. At `version == 4`, an absent
> or malformed meta yields an empty Meta — never a grant.**

"Does not refuse" and "receives grandfather grants" are different properties.
Both v4 paths do not refuse; neither grants. The empty-Meta outcome is *safe* for
a 20-floor v4 save because §7 correction 2 measures the cap budget against
`BASE_FLOORS`: the budget is `height_cap() - BASE_FLOORS` = **4** while
`restore_levels` puts `level_of("floor")` at 14, so `is_maxed` (`>=`,
`sim/upgrades.gd:71-74`) stops every further purchase, and the
building is untouched. The cost is a lost tech tree, which is the trade the next
subsection argues for.

### The v1–v3 path: grandfathering is keyed on the version, not on a missing key

A save at `version <= 3` has no Meta by definition and is granted the height
levels its building already implies:

```gdscript
# Exact, not approximate: the ladder is 10 + 5n, so this inverts it.
height_level = clampi(ceili((floor_count - 10) / 5.0), 0, 2)
```

| a legacy save with | grants | cap | floors kept |
| --- | --- | --- | --- |
| 6 floors | height 0 | 10 | all |
| 11 floors | height 1 | 15 | all |
| 14 floors | height 1 | 15 | all |
| 20 floors | height 2 | 20 | all |

The levels are **granted, not charged**: `blueprints` stays 0 and `spent` records
them. Charging for what is already built would present an existing player with a
building they cannot afford to keep. `lifetime` on a v2/v3 save is by definition
the current run's earnings, so the first yield needs no adjustment — though a
genuine **v1** save may lack the key entirely, in which case
`data.get("lifetime", 0.0)` returns 0 and a large v1 building's first demolish is
gated at zero. Acceptable; v1 predates the field.

Keying this on `not data.has("meta")` instead would route a **v4** save whose
meta key is absent into `legacy_meta()` — granting Structure levels permanently
to a truncated write or a tampered file. Hence the version gate above.

### A malformed v4 meta does not refuse — it yields `empty_meta()`

This is the one place this spec departs from the codec's usual all-or-nothing
rule, and the reason is mechanical: **in this codebase "refuse" means "delete".**
`decode` returns null → `game_root` starts a fresh game → the autosave overwrites
the only copy within `AUTOSAVE_SECONDS` (10). The base design permits refusal
only with compensating controls (§8.6: refuse-and-backup, the backup exempt from
the latch, and a session-wide `writes_disabled` latch on every write path) and
**none of the three exist** — `SaveStore` has no backup and `game_root` has no
latch.

The failure mode is therefore chosen deliberately: **losing a tech tree rather
than losing a building.** A cap below the floor count is already handled — the
budget is **4** against a restored `level_of("floor")` of 14, so `is_maxed` stops
every further purchase and the building is untouched. **[r5]** r4 claimed this
correction and did not land it — "clamps at 0" is the number the *pre-correction*
formula produced, so the sentence was still teaching the bug §7 correction 2
fixes, even though its conclusion happened to be true. (An audit of all 17
claimed r4 edits found this was the only one dropped; the rest landed.)

If refusal is ever preferred instead, §8.6's backup-before-refuse and the
`writes_disabled` latch become hard prerequisites of this spec. **Malformed
shipped data (§8) still refuses**; the asymmetry is between data the player
cannot have damaged and a file they can.

### Salvage the Meta when the *run* is refused  **[r2]**

r1 reasoned about the meta block and stopped there. But `decode` keeps four other
refusal paths — the unsupported-version guard, `_is_usable`'s missing-key check,
the v2+ short-`floors` rule (`sim/save_codec.gd:156`) and the missing kind/class
rule (`:161`) — and under v4 **every one of them now destroys the tech tree along
with the run.** §11's defence of the demolish write ("every other write can be
re-earned by playing on") was true when a discarded save cost a building; it
stops being true the moment the save carries permanent progress.

**The mechanism, named rather than implied. [r3]** r2 said "seed the fresh game
with whatever survives" and specified no channel for it — `decode` returns
`GameState` or `null`, `load_state()` returns the same, and `game_root.gd:69`
builds the fresh state itself with no Meta in scope. Three reviewers
independently showed the only in-`decode` reading contradicts **five** existing
tests that §12 declares safe (`test_save_codec.gd:120, :126, :131, :136, :211`,
each asserting `assert_null` on a payload that under v4 carries a salvageable
meta), and would falsify `SaveCodec`'s docstring at `:115-116` and
`SaveStore.load_state`'s at `:39-40` ("Null always means 'start a new game'").

So `decode` keeps returning `null`, unchanged, and salvage is a **separate,
explicitly-named function**:

```gdscript
## The tech tree is designed to outlive a discarded building, so a run we refuse
## must not take it down. Reads the RAW parsed dictionary (migration never
## touches the "meta" key, and migrating here would re-expose the int({}) abort
## the preflight guards decode against); uses data.get only. [r5]
static func salvage_meta(p_data: Dictionary,
        blueprints_path := "res://data/blueprints.json") -> Meta
```

`SaveStore` gains `load_meta()` alongside `load_state()`, and `game_root`'s
cold-boot branch (`game_root.gd:67-69`) becomes:

```gdscript
state = SaveStore.load_state()
if state == null:
    var salvaged := SaveStore.load_meta(blueprints_path)
    if salvaged == null:                 # [r6] defs failed to load -- SS8 is fatal
        _show_error_screen(blueprints_path)   # :74-78 is BELOW us; call it directly
        _saving_enabled = false
        set_physics_process(false)
        return
    state = GameState.new(GameState.BASE_FLOORS, salvaged.starting_shafts(),
            GameState.BASE_SEED + salvaged.runs_completed,
            catalog_path, salvaged, blueprints_path)
```

Every existing `assert_null` test stays green, both docstrings stay true, and
`decode`'s contract is untouched.

**Three rules the salvage must obey, all of them load-bearing:**

1. **Salvage never calls `legacy_meta()`.** That function derives free `height`
   levels from a `floor_count` the refusal has just declared untrustworthy. A
   hand-written `{"version": 3, "floor_count": 20, "floors": []}` is refused at
   `save_codec.gd:156` and would otherwise mint two `height` levels — the entire
   cap ladder, 6 BP — from a save that does not load. Salvage is
   `Meta.restore(data.get("meta"))` only, which yields `empty_meta()` for
   anything at version ≤ 3 (a legacy save has no meta block by definition, so
   this costs nothing real).
2. **Salvage reads the *unmigrated* dictionary, and must not migrate. [r5]**
   r4 required the migrated dict, which forces `load_meta`'s path to call
   `_migrate_to_v3` — whose first statement is `int(data.get("version", -1))`
   (`sim/save_codec.gd:41`), the exact `int({})` abort the preflight exists to
   prevent. But the preflight is specified inside *`decode`'s* flow, and salvage
   runs under a separate call, so it was never covered. Migration is unnecessary
   here: it touches only `V3_KEYS`, `V3_CAR_KEYS` and `levels`
   (`save_codec.gd:33-38, 55-58`) and **never touches the `"meta"` key**. So
   salvage reads `data.get("meta")` off the raw parsed dictionary, using
   `data.get` exclusively. This is strictly safer *and* preserves a recoverable
   tree that substituting `empty_meta()` would have zeroed.
3. **Salvage deliberately bypasses the version guard for the meta block**, so a
   save written by a future v5 has its `spent` reinterpreted under v4 semantics.
   `Meta.restore()`'s clamps bound the damage, and this is accepted — but it is
   written down, because the version guard is otherwise the only thing making
   "we do not read formats we do not understand" true.

This also fixes a gap r2 left elsewhere: §7 correction 1 says the Meta's
starting size is applied by "`game_root`'s cold-boot branch", but that branch
constructed with `START_SHAFTS` and an empty Meta, so a salvaged `shafts` L3
could never have been applied. The snippet above is where it lands, and the seed
follows §12's `BASE_SEED + runs_completed` derivation rather than resetting to
`BASE_SEED`.

One residual is accepted rather than fixed: an older **cached build** whose
`SUPPORTED_VERSIONS` predates 4 will refuse a v4 save through the version guard
and re-arm the autosave over it. Shipped builds cannot be patched retroactively;
Pages' short cache max-age keeps the window small. Stated so it is a known risk
rather than a surprise.

### Decode-side validation — the fields `Meta.restore()` never sees  **[r2]**

r1 filed every validation rule under a heading that said it all lived in
`Meta.restore()`, and then put `lifetime` in the list. **`lifetime` is a
top-level run key** (`sim/save_codec.gd:104` writes it, `:128` restores it) that
`Meta.restore()` — which receives only the meta sub-dictionary — cannot see. An
implementer following the heading ships without the single most load-bearing
check in the spec.

Worse, checking `lifetime` alone does not close the hole, because an adjacent
unvalidated field writes straight into it. `sim/save_codec.gd:129` restores
`combo` unchecked, and `Economy.credit_delivery` does:

```gdscript
var paid := fare * combo      # combo = INF  ->  paid = INF
cash += paid
lifetime_earnings += paid     # permanently INF
...
combo = minf(combo + COMBO_STEP, COMBO_MAX)   # silently heals to 10.0 next line
```

So `"combo": 1e400` — valid JSON, parsed to `INF` — poisons `lifetime_earnings`
on the first delivery, *after* any decode-time check on `lifetime` has run, and
then erases its own evidence. `yield_for(INF)` returns `MAX_YIELD`: a billion
Blueprints from one passenger.

These checks therefore live in **`SaveCodec.decode`**, beside the assignments:

| field | rule |
| --- | --- |
| `lifetime` | finite, `>= 0.0` |
| `combo` | finite, then `clampf(v, 1.0, Economy.COMBO_MAX)` — the clamp alone is not enough, since `clampf(NAN, 1, 10)` returns `NAN` |
| `cash` | finite, `>= 0.0` — `1e400` makes `can_afford` unconditionally true and `cash -= n` a permanent no-op |
| `ticks` | finite, integral, clamped in float space before `int()` (pre-existing at `:126`; it feeds `SimClock.sim_minute()` and traffic-bucket indexing) |
| `streak`, `riders_served` | finite, integral, `>= 0` — cosmetic, but free |

**This table is a floor, not a ceiling, and r2's version stopped two blocks
short. [r3]** Two more groups have to be in it.

**The crash-class fields. [r6 — the earlier justification here was false.]**
`int({})` is a GDScript runtime error (`Invalid call. Nonexistent 'int'
constructor.`), and earlier revisions inferred from that message that the error
*unwinds the call stack to the engine callback*, producing a black screen.
**Executed on Godot 4.7, that inference is wrong**: a runtime error aborts **only
the frame it occurs in**, and the caller resumes at the next statement with the
aborted call yielding its declared return type's default (`-> bool` → `false`,
`-> Dictionary` → `{}`, `-> RefCounted` → `null`). So the real behaviour today is
benign:

| poison | what happens | result |
| --- | --- | --- |
| `{"floor_count": {}}` | `_is_usable` aborts at `:213`, returns `false` | `decode` returns `null` — documented behaviour |
| `{"version": {}}` | `_migrate_to_v3` aborts at `:41`, returns `{}` | version `-1` → `decode` null |
| `{"cars": null}` | `_migrate_to_v3` aborts at `:48` | `decode` null |
| `{"levels": []}` | `_migrate_to_v3` aborts at `:55` | `decode` null |

**The preflight still earns its place, for two better reasons.** GUT treats
unhandled engine errors as test failures (`addons/gut/error_tracker.gd:35`,
raised at `gut.gd:624-625`), so §12's "returns null **without throwing**"
assertions are real and these errors are real noise. And the genuinely dangerous
shape is different from a crash:

- **A `void` callee that aborts leaves `decode` running.** `restore_levels`
  (`sim/save_codec.gd:135` → `sim/upgrades.gd:51`, `maxi(int(levels[id]), 0)`
  with no type check) is exactly this: `{"levels": {"speed": {}, "doors": 3}}`
  aborts it *mid-loop* and `decode` returns a **non-null, half-restored** state,
  with which levels survive depending on dictionary iteration order. That is the
  real violation of `save_codec.gd:17-21` ("never half-read into a state that
  looks fine and is not"), and the container-type row for `:135` does not reach
  it because the container is fine and the values are not.

**So the rule is: every conversion whose argument comes from the save must be
type-guarded in a frame that can still refuse** — in `decode`, not in a `void`
callee. Either type-check `levels`' values in `decode` before calling
`restore_levels`, or give `restore_levels` a `bool` return and refuse on `false`.

| site | code | rule |
| --- | --- | --- |
| `save_codec.gd:213` | `int(data["floor_count"]) >= 1` | numeric + range, **in the preflight** — `_is_usable` is too late. **[r5]** r3 called this "the first conversion executed"; it is not, and the paragraph above now says so |
| `:124` | `int(data["seed"])` | numeric → finite → clamp in float space before the cast (feeds `RandomNumberGenerator.seed`) |
| `:135` | `restore_levels(data.get("levels", {}))` | `TYPE_DICTIONARY` before the call; `upgrades.gd:49` iterates `.keys()` |
| `:138`, `:160` | `var saved: Dictionary = cars[i]` / `var r: Dictionary = saved_floors[floor_index]` | per-element `TYPE_DICTIONARY` check before each typed assignment |
| `:148`, `:172` | `var saved_floors: Array = …` / `var policies: Array = …` | **whole-value** `TYPE_ARRAY` check — **[r4]** r3 mislabelled `:172` as per-element |
| `:174` | `int(policies[shaft])` | per-element **numeric** check — the elements are integers, not dictionaries; an implementer following r3's row would silently drop every saved dispatch policy |
| `:55` | `var levels: Dictionary = out.get("levels", {})` **inside `_migrate_to_v3`** | covered by preflight, not by the table — it runs before `_is_usable` exists in the flow |
| `:163` | `var vacant := bool(r.get("vacant", false))` | `TYPE_BOOL` or numeric, else `false`. **[r6]** `bool()` has **no** Variant constructor for String, Dictionary or Array (verified), so `{"floors":[{"vacant":"x"}]}` aborts `decode`'s own frame — a safe `null`, but an engine error, and GUT fails the sweep on it. This was the only conversion on the whole decode path in no table, no bullet and no "more leaves" list |
| `:140-141` | `position_floor`, `target_floor` | numeric, finite, **and clamped to `[0, floor_count - 1]`** — `int(roundf(INF))` saturates to `9223372036854775807` on arm64 and is platform-defined on WASM, which is exactly the hazard §2.4 refuses to accept for `yield_for` |

**The per-car fields, which poison `lifetime_earnings` by the same route as
`combo`.** `save_codec.gd:140-145` restores four values unchecked, and §9's own
argument — a neighbouring field writes straight into the prestige input — does
not stop at `combo`:

| field | rule | why |
| --- | --- | --- |
| `capacity` | finite, integral, `[1, CAPACITY_BASE + capacity.max_level]` | `1000000000` delivers 1e9 riders in one door cycle ≈ $3.09e9 → `yield_for` = **5,559 BP**, 59× the whole tree, permanent |
| `floors_per_tick` | finite, `(0, SPEED_BASE × (1 + 0.25 × max_level)]` | `1e400` → `INF` position |
| `door_ticks` | finite, integral, `[DOOR_TICKS_MIN, DOOR_TICKS_BASE]` | |
| `spring_multiplier` | finite, `[1.0, SPRING_BASE]` (`= 4.0`, `sim/upgrades.gd:12`) | **[r4]** the only legitimate non-1.0 value; leaving one field of four unbounded invites treating the whole table as advisory |

Note the live counterexample one file over: `restore_levels`
(`sim/upgrades.gd:48-51`) does `maxi(int(levels[id]), 0)` with **no type check**,
so `{"levels": {"speed": {}}}` throws today. §9 teaches the rule; this is where
the codebase already breaks it.

**More leaves, because checking the containers is not checking the values.
[r4]** Per-element `TYPE_DICTIONARY` checks do not protect what is inside them.
Still unbounded or throwable after r3, **with the concrete bound each one takes
— r4 named the fields and left "an explicit bound or documented fallback", which
is a requirement rather than something an implementer can test [r5]**:

| field | bound |
| --- | --- |
| `floor_count` | **type** check in preflight (it is the `:213` abort site). A *range* bound is unnecessary — `Building._init` already does `clampi(p_floor_count, 1, MAX_FLOORS)` (`sim/building.gd:22`) and `int(9.3e18)` saturates to int64 max, which clamps to 40. **[r6]** There is no allocation DoS here; r5 implied one |
| `levels` values | `[0, that definition's max_level]` (they reach `int(levels[id])` at `sim/upgrades.gd:51`, which has no type check) |
| `position_floor`, `target_floor` | finite, `[0, floor_count - 1]` |
| `satisfaction` | finite, `[0.0, 1.0]` |
| `move_out_left` | integral, `[0, Tenancy.MOVE_OUT_TICKS]` |
| `class` | `[Fitout.BASE_TIER, catalog.max_tier()]` — the existing `test_an_out_of_range_class_bounds_to_the_top_tier` already pins this behaviour |
| policy elements | a valid `DispatchPolicy.Preset`, else fall back to MANUAL |

Every integral cast in the codec takes an explicit float-space bound before it,
the same shape `yield_for` already uses.

**Test it generatively and recursively — with a field-aware oracle. [r5]** r3
poisoned only top-level keys; r4 made it recursive but kept a single expected
outcome ("`decode` returns `null`"), which **contradicts the clamp policy stated
four paragraphs above**: `cash = -1` must clamp to 0, `combo = 1e400` must clamp,
a malformed `meta` must yield `empty_meta()` with the building intact, and
`floor.kind = null` is a value `encode()` legitimately emits. A single oracle
cannot express that. Three assertion classes:

| poison | expected |
| --- | --- |
| **any** value, any field | **never throws** — this is the universal invariant, and the one that matters |
| wrong *type* where a container or structural field is required (`{}`/`[]`/`"abc"` on `version`, `cars`, `floors`, `policies`, `levels`, `floor_count`) | `decode` returns `null` |
| out-of-range *numeric* on a clamped field (`-1`, `1e400`, `NAN` on `cash`, `lifetime`, `combo`, `ticks`, `streak`, `riders_served`, the per-car fields) | `decode` returns **non-null**, and the field reads back at its stated bound |
| any malformation of `meta` | `decode` returns non-null; the building survives; `spent` is empty |

Walk `SaveCodec.encode()`'s output recursively and poison every leaf in turn with
`{}`, `[]`, `null`, `"abc"`, `1e400`, `-1` and `NAN`, asserting the class-
appropriate outcome.

**What each poison actually does, so the assertions are not guesses. [r6]**
Verified: `int("abc") == 0` and `float("abc") == 0.0` — **no error**. A string is
*silently coerced to zero* everywhere except `bool()` sites (`:163`) and
typed-container assignments (`:55`, `:123`, `:138`, `:148`, `:160`, `:172`). So
for the numeric rows a string's job is to prove the **type rejection** fires, not
the finite/range check behind it — otherwise `{"cash": "abc"}` passes every stated
check and silently zeroes the player's money. `{"cars": null}` genuinely throws
("Unable to iterate on object of type 'Nil'"), while `for x in 5` does not, so a
numeric container is a preflight refusal rather than a crash. And
`is_finite(Dictionary)` is itself a runtime error, which is why "type first, then
value" is load-bearing inside the preflight too, not just in the tables. `null` earns its place: `{"cars": null}` is valid JSON,
and `Dictionary.get` returns the *stored* null rather than the default, so
`for car in out.get("cars", [])` at `sim/save_codec.gd:48` iterates null and
throws. Its sibling is `:55`, `var levels: Dictionary = out.get("levels", {})`,
where `{"levels": []}` assigns an Array to a Dictionary-typed local. **Both sit
inside `_migrate_to_v3`**, which is why the preflight above has to precede
migration rather than follow it. A hand-written matrix goes stale the moment a key is added, and
this spec adds one; a top-level-only sweep goes stale the moment a value nests.

**The consequence is clamp, not refuse. [r3]** r2 stated rules and never said
what a violation *does*. Every row above **clamps to the stated bound** (or, for
the type checks, refuses the whole save). Refusing on a bad `lifetime` would trip
the destructive path §9 exists to avoid.

Type-check before value-check throughout, for the reason below.

**A declared departure from base design §8.6. [r3]** That section says, in bold:
*"Reject, do not clamp, on the untrusted paths … any save whose version equals
current is rejected on out-of-range."* A v4 save is version-equals-current, and
this spec clamps **every clamping row in all three of §9's tables** — `blueprints`, `runs`, each
`spent` level, `combo`, `cash`, `lifetime`, `ticks`, `streak`, `riders_served`,
`height`, all four per-car fields, `position_floor`/`target_floor`, **`seed` and
`floor_count`**. **[r4/r5/r6]** Three revisions running, this list was a subset:
r3 enumerated some, r4 said "both tables" while §9 has **three**, r5 added two
more rows and still missed the crash-class table's own clamps. Stop maintaining a
roster — the rule is **every row in §9 that clamps rather than refuses**, and any
new clamped row is covered by construction.
**This is a deliberate override, stated here because r2 made it silently while
citing §8.6 approvingly three times.** The justification is the same
refuse-means-delete argument as the malformed-meta case — `SaveStore` has no
backup-before-refuse and `game_root` has no `writes_disabled` latch, so a
rejection deletes a building — and the codebase already establishes the house
style: `test_an_out_of_range_class_bounds_to_the_top_tier`
(`tests/test_save_codec.gd:213-218`) pins bounded-not-prevented. The second,
smaller override is §9's "int *or* integral float" rule, where §8.6 mandates a
`TYPE_FLOAT`-and-integral gate; that one is strictly better (§8.6's own rationale
is "would refuse every save the game itself wrote", and the in-memory round trip
at `tests/test_save_codec.gd:23` is the case it missed). Both are overrides of a
written rule and both now say so.

### Validation of the meta block, all of which lives in `Meta.restore()`

**Accept `TYPE_INT` *or* integral `TYPE_FLOAT`. [r2]** Godot's JSON parser
returns every number as `TYPE_FLOAT`, which is why a bare `TYPE_INT` check would
reject every real save. But r1 over-corrected into requiring `TYPE_FLOAT`, and
that **rejects the codec's own output**: `SaveCodec.encode()` returns a live
Dictionary holding GDScript ints (`ticks`, `streak`, `floor_count` …), and the
entire suite round-trips in memory — `SaveCodec.decode(SaveCodec.encode(before))`
at `tests/test_save_codec.gd:22`, with no `JSON.stringify` between. A valid Meta
carrying `blueprints: 7` would have been judged malformed and discarded. The rule
is "integral number", satisfied by either type.

**Type first, then value** — checking `>= 0` on a JSON string throws and kills
the refusal path before it engages.

- `meta` is `TYPE_DICTIONARY`, else `empty_meta()` (v4) / `legacy_meta()` (≤ v3).
- `blueprints`: numeric → `is_finite()` → integral → `>= 0` → **clamped to
  `Meta.MAX_BLUEPRINTS` in float space, before the `int()` cast**, mirroring
  `yield_for`'s shape exactly. r1 said "upper-bounded" with no number and put the
  bound *last*, after checks that may already have cast: `9.3e18` is finite,
  integral and `>= 0`, and reaches `int()` out of int64 range — the platform-defined
  conversion §2.4 already warns about. `MAX_BLUEPRINTS == Prestige.MAX_YIELD`
  deliberately, so a legitimately-clamped yield cannot fail its own decode on the
  next load.
- `runs`: same treatment, clamped to `Meta.MAX_RUNS`. It feeds
  `BASE_SEED + runs_completed` into `RandomNumberGenerator.seed`.
- `spent` is `TYPE_DICTIONARY`.
- **Read it by iterating `ids()` from `data/blueprints.json`, never the parsed
  dictionary's keys** (§8.6: "never iterate a parsed dictionary"). Unknown ids
  are dropped rather than stored. This is the most valuable line in the list, and
  it makes r1's "bound `spent`'s key count" bullet dead — you never iterate the
  parsed keys, so their number is irrelevant, and `JSON.parse_string`
  (`game/save_store.gd:49`) has already paid the allocation before any bound
  could apply. Dropped; a raw-text length cap in `SaveStore.load_state()` is the
  only place that would actually help, and that is pre-existing, not this spec's.
- Each level: **type-checked first** (`int({})` is an error in GDScript, not a 0,
  so a dictionary or array value must be rejected before `maxi` ever sees it),
  then integral, `maxi(..., 0)`, **and clamped to that node's `max_level`**. This
  one has teeth. `shafts` is incidentally caught by `Building.MAX_SHAFTS`;
  **`height` is not caught by `Building.MAX_FLOORS`** — what bounds it is
  `Meta.MAX_HEIGHT_CAP` (20), and an implementer who clamps to `MAX_FLOORS` (40)
  instead hands a tampered save `set_max_level("floor", 34)` and a 40-floor cap.
  `motor` and `cabin` are bounded by nothing downstream: `spent.motor = 999`
  gives `effect_value("speed", 999)` = **10.03 floors/tick**, and `cabin: 999`
  gives a **1,003**-seat car (`CAPACITY_BASE = 4`, `sim/upgrades.gd:11,136`).
- **A restored level above `max_level` is inert, not an error. [r3]** r2 told
  this story with two wrong details. The `--board=40x8` path sets
  `_saving_enabled = false` (`game_root.gd:63-65`), so such a save cannot exist
  without hand-editing; and the over-max level does **not** arrive through
  `grant_level`, which §7 clamps to `[0, max_level]` — it arrives through
  `restore_levels`, which has no upper clamp (`maxi(int(v), 0)`,
  `sim/upgrades.gd:48-51`). So: a hand-edited 40-floor save restores
  `level_of("floor") = 34` against a `max_level` of 14. `is_maxed` uses `>=`, so
  purchases stop correctly and the building is untouched; `cost_of` prices a
  purchase that can never happen. The two paths deliberately disagree — `_init`
  clamps, `restore_levels` does not — and that asymmetry is stated here so nobody
  "fixes" one to match the other.

The existing guards need no edit, and this is why they were written as they were:
the tenancy guards are `version >= 2` rather than `== 2` precisely so a version
bump does not silently stop covering current saves, and
`test_a_save_from_another_version_is_refused` (`test_save_codec.gd:117`) uses
`SaveCodec.VERSION + 1` and tracks the bump on its own.

---

## 10. UI

### `ui/prestige_panel.gd` — new

**Its shape is `ManagementView`'s, not `FloorPanel`'s.** FloorPanel is a bottom
sheet at `SHEET_FRACTION = 0.46` of the viewport with no `ScrollContainer`
anywhere in the file. The tree needs:

| item | height |
| --- | --- |
| yield line | 24 |
| 2 headings @ 28 | 56 |
| 5 node buttons @ 88 (two lines each, per `ManagementView._build_upgrade_row`) | 440 |
| REBUILD, or Confirm + Cancel when armed | 88 → **176** |
| separations and box insets | ~100 |
| **total** | **~708 idle, ~796 armed** |

against `0.46 × 1280 = 589` on the pinned test viewport. `VBoxContainer` honours
`custom_minimum_size`, so the overflow would draw *outside* the sheet, over the
board. 88 is not negotiable downward either — it is 48pt at the 0.546 board
scale, and FloorPanel's own 72 is already 39pt, below the touch floor, as that
constant's comment admits.

So: a full-height overlay wrapping a `ScrollContainer` + `VBoxContainer` +
`_heading`s (ManagementView's structure), with FloorPanel's scrim and explicit
close. It shows:

- **This building is worth N Blueprints**, recomputed each `refresh()`. At 0 it
  reads `$X more to earn your first Blueprint` — the projection is the
  confirmation, per the base design, so the number being decided on is on screen
  before the button is reachable. With the $1,000 gate this line does real work
  for the first hour of a new game.
- **The tree**, grouped under STRUCTURE and MECHANICAL, each row reading
  `name  Lv2      3 BP` over the node's note, disabled when maxed, unaffordable,
  or zero-delta — the three states `ManagementView.refresh()` already renders.
- A line stating that **Mechanical nodes apply from the next rebuild**, since §7
  makes that true and an unexplained no-op reads as a bug.
- **REBUILD**, disabled while the yield is under 1.

Every dynamic string goes through `Label`, never BBCode — same origin argument as
`ManagementView`'s header.

**The confirmation is a Confirm/Cancel pair, not a second tap on an armed
button.** Three reasons: the UI design spec §4.3 ("Re-leasing is the one
confirmed action") establishes the project's one confirmation shape as a
*distinct labelled control carrying the price*, with the scrim as Cancel; an
armed button has no disarm path and stays armed while the sim runs; and §4.1
rules out double-tap explicitly because it "fights mobile Safari's zoom
heuristics" — `test_one_thumb_tap_buys_exactly_one_floor` exists because touch
emulation delivers one physical tap twice. Arming on tap 1 and committing on tap
2 lets a stray double-tap destroy a run, in a game whose stated invariant is no
fail state.

So the first tap swaps the REBUILD row for **`Rebuild for 7 Blueprints` /
`Cancel`**, both 88 units, in the same VBox. Still no modal — nothing to survive
an iOS suspend, which `_notification` can trigger mid-dialog.

**The panel emits, it does not mutate.** `node_purchase_requested(id)` and
`demolish_requested` go to `game_root`, which calls `meta.buy()` / `Prestige` and
then `save_now()` — following `FloorPanel.lease_requested` rather than
`ManagementView`'s direct `_state.buy()`, because a node purchase mutates
*persistent* state and must be written immediately.

### `ui/management_view.gd`

A `REBUILD` heading at the bottom of the existing scroll opening the panel, and a
fourth `_stat` in the readout — a value of `7` under the caption `blueprints`,
which is the idiom `_stat()` takes. It fits: four captions plus separations come
to ~253 of ~720 units. The upgrade list needs no change; it is generated from
`upgrades.ids()` and already skips `shaft` and `floor`.

### `view/building_view.gd` — the ghost band

```gdscript
if _state.building.floor_count < Building.MAX_FLOORS:      # line 97
    _build_ghost_floor()
```

The band is gated on the **structural** cap, so at the purchasable cap it still
renders `+ BUILD FLOOR $759.50` — coloured **green** the moment the player can
afford it — and a tap silently does nothing, because `Upgrades.purchase` refuses
at `is_maxed` and `game_root.gd:112` discards the result. It does not merely
persist; it invites the tap. That is reachable today only after 6.5 hours; with a
10-floor first run it is reachable in 1.5 hours by every new player, which makes
it this spec's problem.

**Line 97 must not change.** It decides whether the band is *constructed*, and
the band must stay: `_on_ghost_input` is also the PAN handler, and its docstring
says the ghost's drag "translates to scrolling … so a glance down a
taller-than-screen building is not blocked". Deleting the band at the cap would
kill that 88-unit pan strip on precisely the tallest buildings.

Only the label changes, in `refresh()` (`:348-352`). At the cap it reads
**`CAP REACHED — REBUILD`** and the band's tap **opens the prestige panel**.
Length matters: a 37-character string is ~333 units at font size 15 from
`LABEL_X = 38`, which overruns `FloorRow.STRIP_RIGHT` (240) into the shaft slot's
own label; 21 characters ends near x = 227, just inside the strip, matching
today's `+ BUILD FLOOR  $12.3K`. Giving the tap a destination removes the silent
no-op rather than merely labelling it.

Rebuild timing already works: `_physics_process` calls `_view.rebuild()` whenever
`Vector2i(floor_count, cars.size())` changes, so buying the capping floor
triggers a rebuild and then a `refresh()`.

---

## 11. `game_root`: replace the views, and fix the save first

### The rebind trap

`BuildingView.bind()` (`building_view.gd:56`), `ManagementView.bind()`
(`management_view.gd:25`) and `FloorPanel.bind()` (`floor_panel.gd:38`) all
`add_child` unconditionally. **They are constructors wearing an accessor's
name**, and calling any of them a second time stacks a whole UI on top of the old
one. Only `BuildingView.rebuild()` frees first, and it never re-reads `_state`.
`FloorPanel` additionally holds `_state` (`:26`) and would read a dead run until
the next lease tap.

So demolish **replaces** rather than rebinds:

```gdscript
func _on_demolish() -> void:
    var next := Prestige.demolish(state)
    if next == null:
        return                       # the gate refused; NOTHING has changed (§7)
    # [r2] Write BEFORE swapping. save_now() returns bool now.
    if not save_now(next):
        _show_save_failed()          # old run and Meta still intact, on disk and in memory
        return
    state = next
    last_selected_floor = -1         # a stale index into a building that just shrank
    _rebuild_views()
    _view_button.text = "MANAGE"     # we were in Management when this fired
    _last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
    _refresh_pager()
```

**The write comes first, and its result is checked. [r2]** r1 swapped state,
rebuilt the UI, and *then* called `save_now()` — which discards
`SaveStore.save()`'s bool (`game_root.gd:268-270`), so no branch could even
observe a failure. On a quota refusal, a failed rename, or an IndexedDB error the
player would see the new run while the durable file still held the old,
still-demolish-eligible one; reload and the same `E` pays a second time, and the
10-second autosave would retry against the same broken condition. Fixing
`SaveStore.save()`'s atomicity (below) does not fix this — it is an ordering bug,
not a file-replacement bug. `save_now()` gains an **optional** `GameState`
parameter and a `bool` return — `func save_now(s: GameState = null) -> bool`,
falling back to `state` when null. **[r3]** A *required* parameter would turn two
unlisted tests red: `test_board_input.gd:611` (inside
`test_the_building_survives_a_restart`) and `:640` (inside
`test_a_debug_board_never_writes_over_a_save`) both call `root.save_now()` with
no argument. This spec applied exactly that default-valued-parameter discipline
to `decode` and failed to apply it here.

**`_rebuild_views()` covers exactly `_view`, `_management`, `panel` and the new
prestige panel** — lines 106–129 of `_ready`. It must **not** include the pager
buttons (`:134-143`) or `_view_button` (`:148-154`), which also `add_child`
unconditionally and would duplicate on every rebuild — the very trap this section
is about. `_view_button.text` is reset by hand because it lives outside the
extracted range and would otherwise read "BOARD" while the board is showing;
`_refresh_pager()` early-returns on `if _management.visible:` and so must run
after the new (hidden) management view exists.

Two further facts worth stating:

- **`queue_free()` is deferred to end of frame**, so without a guard the freed
  views remain children while the new ones are added, and input in that window
  reaches both trees. **[r2]** r1 named the window and left it open — then wrote
  a §12 test asserting exactly one `BuildingView` exists, which trips on it.
  `_rebuild_views()` therefore does `hide()` + `remove_child()` **synchronously**
  before `queue_free()` on each old view. Two lines, and it closes the race
  rather than documenting it.
- **Sibling order must be restored, or the panel scrim swallows the HUD.
  [r3, HYPOTHESIS — verify in the scene]** `_ready` builds `_view` (106),
  `_management` (116), `panel` (124), then the pager (134-143) and `_view_button`
  (148), so the buttons are *later* siblings and win input against the panel's
  full-rect `MOUSE_FILTER_STOP` scrim (`ui/floor_panel.gd:42-45`). A
  `remove_child` + `add_child` rebuild appends the three views **last**, putting
  `panel` above `_view_button` and the pager for the rest of the session — MANAGE
  stops being tappable while a floor panel is open. `_rebuild_views()` must
  `move_child()` each rebuilt node back to its original index. Marked HYPOTHESIS
  because it follows from Godot's documented child-order input semantics but was
  not run; §12's scene test asserts node counts and button text and would not
  catch it either way, so the test needs an input assertion if the hypothesis
  holds.
- **Nothing dangles into the discarded state.** No view and no `game_root`
  handler connects a `GameState` signal, so the old state, its cars and its
  riders are dropped by refcount. The lambda at `game_root.gd:112` resolves
  `state` through `self` at call time, so it follows the reassignment rather than
  capturing the dead sim.

### `SaveStore.save()` is not a replace, and demolish cannot ship until it is

```gdscript
if dir.file_exists(PATH):
    dir.remove(PATH)                     # save_store.gd:35-37
return dir.rename(TEMP_PATH, PATH) == OK
```

A crash between the `remove` and the `rename` leaves **no save at all** — the
building *and* the Blueprints. Ordering the demolish write cannot fix this;
`save_now()` (`game_root.gd:268-270`) also discards `SaveStore.save()`'s bool, so
the failure is silent and the 10-second autosave commits the new run regardless.

**One algorithm, not a menu. [r2]** r1 offered three alternatives as if
interchangeable; they are not. The `load_state()`-falls-back-to-`TEMP_PATH`
option only recovers when the crash lands inside the `remove`→`rename` window —
a crash during `f.store_string` leaves a *truncated* `TEMP_PATH`,
`JSON.parse_string` returns a non-Dictionary, `load_state` returns null,
`game_root.gd:69` starts fresh and the autosave commits over the wreckage. It is
strictly weaker. The specified fix is the real replace:

```
1. NORMALISE: if PATH is absent and BACKUP_PATH exists, rename BACKUP -> PATH.
              On failure, keep BACKUP and return false. (Recovery, not cleanup.)
2. write TEMP_PATH in full
3. remove a now-stale BACKUP_PATH        <- only once a complete TEMP exists
4. rename PATH -> BACKUP_PATH (if PATH exists)
5. rename TEMP_PATH -> PATH              <- THE COMMIT POINT
6. remove BACKUP_PATH; a failure here does NOT make the save unsuccessful
```

Every step's result is checked. **Rollback means restoring the invariant "if any
copy exists, `PATH` exists", not preserving `BACKUP` for its own sake. [r4]** r3
stated both "any failure rolls back to `BACKUP_PATH`" and "no failure path may
remove `BACKUP_PATH`", which contradict: rolling back a failed step 5 *means*
renaming `BACKUP` → `PATH`, which necessarily consumes `BACKUP`. The rule is:

- **restore `PATH` from `BACKUP` only when `PATH` is absent** — i.e. only after a
  failed step 5, which is the sole step that removes `PATH`. **[r5]** r4 said
  "before the commit point, a failure restores `PATH` from `BACKUP`", which is
  right at step 5 and actively harmful earlier: at a step-2 or step-3 failure
  with a *stale* backup present (the legitimate `{PATH, BACKUP}` start state),
  restoring renames a stale backup over the current `PATH` and silently
  **regresses the save** on any platform whose `rename` overwrites. Failures at
  steps 1-4 return `false` with `PATH` untouched;
- **after** the commit point (step 5 succeeded), nothing rolls back and step 6's
  failure is not an error;
- no failure path may **delete** the last copy — which is a different statement
  from never touching `BACKUP`.

**One source-selection routine, shared. [r4]** `load_state()` and `load_meta()`
must not choose independently, or the run and the Meta can come from *different
files* — and the autosave commits that mixture ten seconds later as one valid v4
payload. Concretely: `PATH` is truncated but parses, `BACKUP` holds a legitimate
older save; `decode(PATH)` refuses, and depending on unstated choices the salvage
reads the tampered `PATH`'s meta while the run comes from `BACKUP`, or vice
versa. So:

```
SaveStore._select() -> Dictionary   # the first of PATH, BACKUP that parses to a Dictionary
```

`load_state()` and `load_meta()` both operate on **that same parsed dictionary**,
and the fallback triggers on *parse* failure (not on `decode` refusal — a refused
run is exactly when salvage must still see its meta).

**State the consequence, because it bounds what the backup is for. [r6]** When
`PATH` parses but `decode` refuses it, `_select` never looks at `BACKUP`,
`game_root` starts fresh, and the next save's step 3 removes that good `BACKUP`.
So `BACKUP_PATH` protects against **truncation** (a parse failure), not against a
**refusal** — including the older-cached-build refusal §9 already accepts as a
residual. That is a property of the design rather than a defect, but the paragraph
claiming the backup answers "refuse means delete" must not overclaim it. **Collapse the two into one call returning `{state, meta}`. [r5]** r4 called
this "preferable", which leaves the stated invariant optional — and two separate
`_select()` calls re-parse and can disagree. It is mandatory: one selection, one
parsed dictionary, both consumers fed from it.
**Promotion and step 1 key on `_select`'s choice, not on file absence. [r5]**
Both r4 checks asked "is `PATH` absent", which conflates *`PATH` exists* with
*`PATH` is a usable copy*. Walk `{PATH corrupt-but-present, BACKUP good}`:
`_select` skips `PATH` and takes `BACKUP`; step 1 no-ops because `PATH` exists;
step 3 then removes `BACKUP` — **the only loadable copy** — and a crash before
the commit leaves `{PATH corrupt, TEMP complete}`, which the loader never reads
(TEMP-fallback was deliberately dropped as strictly weaker). Total loss. So: if
the selected source is `BACKUP`, remove the unusable `PATH` first, then rename;
on failure keep `BACKUP` and return `false`. `load_state()` promotes on
selection, so a recovered session never begins with `PATH` unusable, and
`has_save()`
(`game/save_store.gd:21-22`) learns `BACKUP_PATH` alongside `clear()` — otherwise
the "is there a save" predicate disagrees with the loader.

**Why this exact order, having got it wrong in both directions. [r4]** r2 had no
backup at all. r3 added an *unconditional leading* `remove(BACKUP_PATH)` to stop
the algorithm bricking itself — and that fix, reviewed, turned out to destroy
data: `load_state()` deliberately supports the state `PATH absent, BACKUP
present` (the crash-between-renames case), and deleting the backup *before*
writing TEMP leaves **no save at all** if the write then fails. The two hazards
are real and opposite:

- **Stale backup blocks rotation.** A crash between steps 5 and 6 leaves `PATH`
  and `BACKUP` both present. If step 4 then renames onto an existing
  destination — `DirAccess.rename`'s overwrite behaviour is platform-dependent —
  and the "check every step" rule turns one transient failure into a *permanent*
  save outage, since §11 now checks the bool and `_on_demolish` would call
  `_show_save_failed()` forever.
- **Eager cleanup destroys the last copy.** Removing that backup before a
  complete replacement exists is the data-loss mirror of the same bug.

Steps 1 and 3 separate the two: **recovery** promotes a backup-only state back
to `PATH` before anything is written, and **cleanup** waits until a complete
`TEMP` exists. Step 5 is the commit point, which is why step 6 cannot fail the
save: once `PATH` holds the new bytes the write *is* durable, and reporting
`false` there would make `_on_demolish` discard a demolish that actually
succeeded — re-creating the double-credit from the other side.

Two companions:

- **No failure path may delete the last *valid* copy. [r5]** r3 phrased this as
  "no failure path may remove `BACKUP_PATH`", which contradicts the rollback rule
  above — rolling back a failed commit *means* renaming `BACKUP` onto `PATH`, and
  after that succeeds the last valid copy **is** `PATH`. r4 disambiguated the
  rule and left this bullet standing verbatim, so the contradiction survived in a
  second location. The invariant is about the last copy, not about a filename.
- **`SaveStore.clear()` (`game/save_store.gd:54-61`) must learn about
  `BACKUP_PATH`.** It removes `PATH` and `TEMP_PATH` only. Left alone, "clear"
  leaves a loadable save behind and the next boot resurrects the building the
  player just deleted — and worse for the suite, `clear()` is
  `test_board_input.gd:39`'s `before_each`, whose comment says a real save "would
  silently become the fixture for every test in this file." A surviving
  `BACKUP_PATH` becomes exactly that fixture, in the one file with a written
  defence against it.

**`_show_save_failed()` must say whether it latches or permits retry.** It
permits retry — the staged-Meta design (§7) makes a retry safe, because nothing
was credited — but it must not silently re-arm the 10-second autosave against the
*old* state while the player believes the demolish happened. Specify: surface the
failure, leave the old run authoritative, and let the next explicit REBUILD try
again.

**Web durability is unverified. [r3]** This algorithm is specified against
desktop filesystem semantics, and the ship target is threadless WASM on mobile
Safari, where `user://` is IDBFS and Godot flushes asynchronously with flush
points tied to file-handle close rather than to `DirAccess` rename/remove. A tab
killed mid-sequence can therefore recover into a state the four-step walk above
never produces. `tests/test_save_store.gd` runs headless on desktop and cannot
observe any of it. **§0's prerequisite is discharged by this algorithm's logic
only**; the web durability claim needs checking on a real build before it is
believed.

**This is a prerequisite of the demolish**, because demolish is the one write
whose loss is unrecoverable. r1 justified that with "every other write can be
re-earned by playing on" — which stopped being true the moment the save carried
Blueprints (§9's salvage rule is the other half of that correction).

---

## 12. Tests

### Existing tests this breaks — five  **[r2]**

An empty Meta caps at 10 floors, and the cost-curve spec §6 already named the
tests that care: *"The five board tests in `test_board_input.gd` that build a
tall building buy exactly 14 rows."* Only 4 of those 14 purchases now succeed,
leaving a 10-floor board whose `content_height()` (880) is under the viewport
(1184), so `BoardCoords.scroll_to`'s travel is **0** and floor 12 does not exist.

| test | file:line | why |
| --- | --- | --- |
| `test_a_drag_pans_the_board_and_dispatches_nothing` | `test_board_input.gd:127` | scroll travel is 0 |
| `test_the_board_cannot_be_panned_off_either_end` | `:143` | scroll travel is 0 |
| `test_a_tap_after_scrolling_still_hits_the_floor_it_looks_like` | `:177` | targets floor 12 |
| `test_a_tap_on_the_hall_selects_the_floor_it_looks_like_after_scrolling` | `:272` | targets floor 12 |
| `test_a_drag_on_the_hall_pans_and_does_not_select` | `:286` | scroll travel is 0 |

The five board tests are about the *scroll transform*; their 20 floors are
incidental. Give the fixture a `build_to(n)` helper that grants the needed
`height` levels through a Meta before the scene is built — **and that helper must
call `load_defs` on that Meta. [r5]** Under §7's now-unconditional
`is_usable()` check, a bare `Meta.new()` sets `_valid = false`, which draws the
error screen and fails all five tests on an empty scene — a 15-floor building is
1320 units, past the 1184-unit window, so it scrolls.

**`test_row_purchases_stop_at_the_purchasable_cap` does not break, and r1 was
wrong to list it. [r2]** `test_upgrades.gd`'s `before_each` (`:7-11`) builds
`Upgrades` directly and calls `load_defs("res://data/upgrades.json")` — no
`GameState`, no `_init`, therefore no `set_max_level`. §1 and §13 both guarantee
that file is not edited, so `floor.max_level` stays 14 and every assertion in the
test still holds. r1's own justification for splitting it is the reason it
survives; listing it as red would cost an implementer a confused hour watching a
test refuse to fail. `test_a_maxed_upgrade_cannot_be_bought` (`:104`) is
unaffected for the same reason — and r1's aside that it "silently now pins
`6 + floor.max_level == Building.MAX_FLOORS`" was simply wrong arithmetic
(that reads 20 == 40); it pins the purchasable ceiling, which this spec does not
move.

The split is still worth doing, as **new coverage** rather than a forced
migration:

- in `test_upgrades.gd` — floor purchases stop at whatever `set_max_level` was
  handed, and never pass `Building.MAX_FLOORS`;
- in `test_meta.gd` — the cap a run gets is `meta.height_cap()`.

**Also scope items with no failing test. [r5]** r4 named only the first:
`SaveCodec.decode` grows two default-valued parameters (§7); `SaveStore.load_state`
(`game/save_store.gd:41`) and `SaveStore.load_meta` grow theirs; `game_root.save_now`
grows an optional `GameState` and a `bool` return; `SaveStore.has_save` and
`SaveStore.clear` both learn `BACKUP_PATH`. All 28 one-argument call sites in `tests/`
stay source-compatible, which is exactly why it needs listing here — a change
nothing goes red on is the kind that gets forgotten.

Confirmed **not** to break: all of `test_save_codec.gd` (its `played_state()`
buys one floor), `test_game_state.gd:175` and `:189`, `test_auto_dispatch.gd:155`,
`test_building.gd` and `test_coords_scroll.gd` (which drive their classes
directly).

### New — `tests/test_prestige.gd`

- `yield_for` boundaries: 0 → 0, $900 → 0, **$1,000 → 1**, $1,299 → 1,
  $1,300 → 2, $2,500 → 4; and `yield_for(1e308) == MAX_YIELD` and is finite.
- `demolish` refuses under the gate, returns null, and leaves the handed state
  untouched — cash, floors and tenancy all still there.
- **A successful demolish asserts §3's table row by row**, not a sample of it. A
  demolish that forgets `fitout` would hand the next run free class-3 floors at a
  1.8× fare multiplier forever and stay green.
- **Two demolishes in a row do not pay twice.** Earn $2,500, demolish (4 BP),
  earn $2,500, demolish (4 BP, not 8). This is the strongest test in the file: it
  fails loudly if `lifetime_earnings` is ever made to persist, which is the
  unbounded-minting hole of §2.3. `econ.accrue(2500.0)` is the cheap way to seed
  `E`, since `accrue` has no production callers.
- **Demolish-spam earns nothing.** Demolish, then demolish again with zero
  elapsed play: the second returns null. The gate and the reset together are what
  make this true, and the test names the strategy so nobody re-opens it.
- The seed asserts the **literal** `BASE_SEED + 1` after the first demolish, plus
  the derivation on a later run. **[r5]** §3 already requires the literal;
  asserting only the symbolic `BASE_SEED + runs_completed` lets the test
  reproduce the same pre/post-increment mistake on both sides and pass — which is
  exactly the ambiguity §3's `[r4]` note exists to close. Mere inequality is also
  insufficient: a run loaded from a save carries an unrelated seed.
- `demolish` refuses when the fresh state is `not is_valid()`.
- **On a failed *save*, the handed state's Meta is unchanged. [r3]** Demolish
  against a failing write and assert the live run's `blueprints` and
  `runs_completed` are untouched **and** that a subsequent autosave payload
  carries the uncredited balance.
  **The failure must be induced, not stubbed. [r4]** `SaveStore.save` is
  `static` and `game_root.save_now` calls it by class name (`game_root.gd:270`),
  so a GUT double is a different script and cannot intercept that call site —
  the same "named behaviour with no channel" defect this spec caught twice
  elsewhere, sitting on its single most important new test. Induce a real
  failure instead: **pre-create a directory at `user://save.json`** so the
  commit-point `rename(TEMP_PATH, PATH)` legitimately fails and `save()` returns
  `false` through its own code path.
  **This test lives at the scene boundary, not in `test_prestige.gd`, and it must
  clean up after itself. [r5]** `Prestige.demolish` is deliberately pure and
  never calls `SaveStore` — the write happens in `game_root.save_now(next)` — so
  a prestige unit test cannot exercise write-before-swap at all; it belongs in
  the `test_board_input.gd` scene suite, driven through the real Confirm handler.
  And the directory fixture **leaks**: `SaveStore.clear()` tests
  `file_exists(PATH)` (`game/save_store.gd:54`), which is false for a directory,
  so it survives `before_each` and becomes the fixture for every later test in
  the file — the contamination `test_board_input.gd:37-38` explicitly warns
  about. Either the test removes the directory itself, or `clear()` learns
  `dir_exists(PATH)`. This is the assertion the r2 shape would have
  failed, and no r2 test could see it.
- **On every refusal path inside `demolish`, the Meta is unchanged. [r2]** `blueprints` and
  `runs_completed` hold their prior values after a gate refusal *and* after an
  invalid-catalog refusal. r1's suite asserted only that the handed *state* was
  untouched, so the double-credit hole of §7 would have shipped green.
- `yield_for(NAN) == 0` — pins §2.4's `maxf` argument order against a tidy-up.

### New — `tests/test_meta.gd`

- `cost_of` follows `base × (level + 1)`; `buy` refuses without Blueprints, at
  `max_level`, and on zero-delta; **and succeeds at exactly `cost_of(id)`** — the
  `<` vs `<=` boundary.
- `height_cap()` walks 10 → 20; `starting_shafts()` walks 1 → 4.
- **The clamp tests must be non-vacuous.** Asserting `height_cap() <= MAX_FLOORS`
  when the ladder tops out at 20 passes with the clamp deleted. Load a defs file
  with an over-large `max_level` and assert the clamp still holds.
- **The `to_dict()` key names are pinned.** The dict key is `runs` while the
  field is `runs_completed` (and `blueprints`/`spent` match). A rename on one side
  would silently zero the count on every load. **[r4]**
- **Ids match the derivations.** Every id in `blueprints.json` is consumed by a
  derivation, every id a derivation switches on exists in the file, and each
  Mechanical node's target (`speed`, `doors`, `capacity`) exists in
  `upgrades.ids()`. A typo otherwise makes a node silently do nothing forever —
  the same class of bug `ElevatorCar.floors_per_tick == Upgrades.SPEED_BASE` is
  pinned against.
- A `GameState` built with a Meta starts with the granted shafts and upgrade
  levels, and `building.cars[0].floors_per_tick` reflects the granted `speed`
  level — the cars are synced, not merely counted.
- **A malformed `blueprints.json` is fatal**, through the injectable path:
  `is_valid()` is false, `decode` returns null, and the boot path shows the error
  screen naming the file.

### Changed — `tests/test_save_codec.gd`

- **The cap survives a reload** — with `height` L2, buy 7 floors, round-trip,
  keep buying, assert 20 is reachable. This is the test that catches §7's
  correction 2; every other codec test operates on a fresh or legacy state, which
  is exactly where the broken arithmetic happened to be right.
- **A save is not refused because the Meta grants more than it holds** — buy
  `shafts` mid-run at 8 floors, round-trip, assert non-null and
  `floor_count == 8`. Catches correction 1.
- **A v4 save with `meta` erased is not grandfathered** — encode a 20-floor
  state, `erase("meta")`, assert it does not come back with `height` levels in
  `spent`.
- **A malformed v4 meta yields an empty Meta rather than refusing** — the
  building survives, the tree does not, and `decode` is non-null. **[r3]** The
  title previously reused "grandfathers", the exact overloaded verb §9 splits
  into two names, for the path that must *not* grandfather. The inverse of this test is what a
  future reviewer will try to "fix"; §9 is the reason it is written this way.
- **A hostile-save matrix**, one case per §9 bullet, split across the two
  validation sites. In `Meta.restore()`: `spent.motor = 999` must not produce a
  10-floors-per-tick car; `spent.cabin = 999` must not produce a 1,003-seat car;
  `spent.height = 999` must not exceed `Meta.MAX_HEIGHT_CAP`; a non-integral
  `blueprints` (`3.7`), a string (`"abc"`), and a `spent` value that is a
  Dictionary must each be rejected **without throwing**; `blueprints = 9.3e18`
  must clamp rather than wrap through `int()`.
- **In `decode`, the fields `Meta.restore()` never sees. [r2]** `lifetime = 1e400`
  → `yield_for == 0`, not `MAX_YIELD`. **`combo = 1e400` → after one delivery,
  `lifetime_earnings` is finite** — the poisoning route of §9 that a `lifetime`
  check alone does not close, and the single most important new test in this list.
  `cash = 1e400` must not make `can_afford` unconditionally true.
- **An in-memory round trip survives validation** — `decode(encode(state))` with
  a populated Meta returns it intact. This is the test that catches a
  `TYPE_FLOAT`-only rule rejecting the codec's own GDScript ints.
- **A `blueprints.json` with `"base": -2` is refused**, as is one with duplicate
  ids, **and one with `"base": 1e18`** — the third is the overflow route to the
  same mint. **[r3]**
- **Generative crash sweep — see §9's field-aware oracle. [r5]** This bullet
  previously restated r3's top-level-`{}`-only version, which §9 was revised to
  reject; the fix had landed in the prose and not in the test spec an implementer
  writes from. The test is §9's: walk `encode()`'s output **recursively**,
  poison every leaf with `{} [] null "abc" 1e400 -1 NAN`, and assert the
  **class-appropriate** outcome (never throws, universally; `null` for structural
  type violations; non-null-and-bounded for clamped numerics; non-null with an
  empty tree for a malformed `meta`).
- **Per-car poisoning** — `{"cars": [{"capacity": 1000000000}]}` must not yield a
  five-figure Blueprint balance after one delivery.
- The real-device fixture decodes with a grandfathered height level, loses no
  floors, and is charged nothing; a legacy save at exactly 20 floors lands on the
  boundary the `ceili` inverts.
- **Blueprints survive the demolish write** — demolish, encode, decode, assert
  the credited balance, `runs_completed`, and the new smaller building all arrive
  in one payload.
- **The Meta survives a refused *run*, through `salvage_meta`. [r3]** A save
  whose `floors` array is short still makes `decode` return **null** — so
  `test_a_short_v2_rows_array_is_refused` (`tests/test_save_codec.gd:211`) and
  the four other `assert_null` tests at `:120`, `:126`, `:131`, `:136` all stay
  green — while `SaveStore.load_meta()` returns the saved `blueprints` and
  `spent`. r2's version asserted `decode` returned a state here, which
  contradicted all five.
- **Salvage never grants.** A hand-written `{"version": 3, "floor_count": 20,
  "floors": []}` salvages an **empty** Meta, not two `height` levels. **[r3]**

### New — cross-module constant pins  **[r3]**

The spec's own precedent is that numeric agreements across modules get pinned —
§12 cites `ElevatorCar.floors_per_tick == Upgrades.SPEED_BASE` by name. The
revision introduced two more and pinned neither:

- **`Meta.MAX_BLUEPRINTS == Prestige.MAX_YIELD`.** §9 calls the equality
  deliberate, so that a legitimately-clamped yield cannot fail its own decode on
  the next load. Raise `MAX_YIELD` later and a maxed save silently loses the
  difference on reload, with every test green. One assert.
- **`MAX_RUNS`** is introduced, justified (it feeds `RandomNumberGenerator.seed`)
  and appears in no test. The hostile matrix tests `blueprints = 9.3e18`; `runs`
  gets the same row.

### New — `tests/test_save_store.gd`  **[r2]**

§0 calls the real replace a prerequisite and §11 says demolish cannot ship
without it; r1 proposed **zero** coverage for it. A hard prerequisite with no
test is one that gets quietly dropped three commits later.

- `save()` returns `true` and `load_state()` is non-null after saving over an
  existing file.
- A pre-existing `PATH` **survives** a `save()` whose temp write fails — the
  rollback path, which is the whole point of the change.
- `load_state()` falls back to `BACKUP_PATH` when `PATH` is absent.
- **A pre-existing `BACKUP_PATH` does not break the next save** — pre-create it,
  assert `save()` still returns `true`. This is the bricking case. **[r3]**
- **`clear()` removes `BACKUP_PATH` too**, so it cannot survive as a fixture.
- **`has_save()` agrees with `load_state()`. [r5]** Write only a `BACKUP_PATH`
  and assert `has_save()` is true — otherwise
  `tests/test_board_input.gd:641`'s `assert_false(SaveStore.has_save())` silently
  stops meaning what it says.
- **The `_select()` invariant is pinned. [r5]** Write a `PATH` that parses but
  whose run `decode` refuses, and a `BACKUP` carrying a *different* meta; assert
  the salvaged meta comes from `PATH`. Without it, the run and the Meta can come
  from different files and the autosave commits the mixture — a silent-corruption
  class, and §12's own standard is that a hard prerequisite with no test gets
  dropped three commits later.

### New — a scene-level demolish test in `tests/test_board_input.gd`

§11 is the hardest code in this spec and neither draft proposed a test for it.
`test_board_input.gd` already instantiates `game_root.tscn` at 720×1280 with
synthetic input, which is exactly the harness. After a demolish driven through
the real scene:

- a tap in the ghost band buys **exactly one** floor — a duplicated
  `BuildingView` buys two, the same class of bug
  `test_one_thumb_tap_buys_exactly_one_floor` (`:514`) already guards;
- exactly one `BuildingView` and one `ManagementView` exist as children;
- the board is visible and `_view_button.text == "MANAGE"`;
- **a `thumb_tap` on REBUILD alone changes nothing. [r2]** `floor_count` and
  `blueprints` are untouched and the Confirm/Cancel row is visible; only a tap on
  Confirm demolishes. This is the single assertion §10's whole confirmation
  argument exists to buy, and r1 asserted only the post-demolish state — so the
  double-tap hazard it reasons about at length had no test at all.

Note `test_board_input.gd:49` caches `view = root._view` in `before_each`, so any
test crossing `_rebuild_views()` must re-read it or assert against a freed node.

### Changed — the ghost band test

At the cap: the band is **present**, its label reads the cap message, and a tap
**opens the prestige panel without changing `floor_count`**. A weaker version —
"a tap neither buys a floor nor errors" — is vacuously true today with no code at
all, and would pass with the entire §10 change deleted.

---

## 13. What deliberately does not change

- **`Building.MAX_FLOORS = 40` and `MAX_SHAFTS = 8`.** Still structural, still
  feeding the spawner's saturation guard (`40 × 3.0 = 120 < 600`). The tree's
  ceilings derive from them, so the guard cannot be outflanked by a Blueprint.
- **`data/upgrades.json`.** No edit at all — see §1.
- **The tick order.** Prestige adds no phase, reads no phase, and runs entirely
  between ticks.
- **The no-fail guarantee.** Demolish is opt-in, gated on a positive yield, and
  unreachable under $1,000 earned. Cash still floors at 0. A post-demolish
  building is a fresh install: 6 tenanted floors,
  `tenanted_count() >= MIN_FLOORS_FOR_TRAFFIC`, and `game_state.gd:133`'s
  free-lease guard still catches the all-vacant case.
- **`codemaps/` must be regenerated. [r3]** `CLAUDE.md` makes
  `codemaps/{architecture,sim,view,data,tests}.md` the per-file API reference, and
  this spec adds two `sim/` classes, a `data/` file and four test files — staling
  all five. Run `/cc-codemaps:update-codemaps` in the same change.
- **Docstrings this spec falsifies, and must update. [r3]** `sim/save_codec.gd:17-21`
  (the versioned-format history needs a v4 sentence); `game/save_store.gd:6-10`
  ("Writes are ATOMIC: the new save goes to a temp file which then replaces the
  real one" — false today at `:35-37`, and §11 changes it again);
  `game/save_store.gd:39-40` (the null-means-fresh contract, now joined by
  `load_meta`); `game/game_root.gd:159-166`'s "Known limit" paragraph; and
  `sim/game_state.gd:77-78`, which §7 already catches. The error screen string at
  `game_root.gd:215` is hardcoded `"No valid tenant catalog…"` with no text
  accessor (`:223` returns a bool), so §8's "now naming the blueprint file" and
  its §12 assertion require parameterising the message and exposing the text —
  otherwise the screen reads "No valid tenant catalog / res://data/blueprints.json".
- **Fares, rates and `data/tenants.json`.** §6 is denominated in today's fare on
  purpose; changing income here and calibrating a ladder against it in the same
  pass would leave neither checkable.
- **`Economy.COMBO_MAX = 10.0`. [r2]** Untouched — but §6 now states the [1, 10]
  band it puts on `E`, and §14 item 2 lists it as a thing that forces
  `DEMOLITION_FLOOR` to be re-derived once measured.
- **Blueprint spending never routes through the cash path** — no `can_afford` on
  cash, no `cash -=`. `Meta.buy()` is the only spender and `Prestige.demolish`
  the only crediter.
- **44pt touch targets** everywhere on the new screen; the demolish confirm is
  the second documented irreversible-action exception after re-lease.

---

## 14. Open items

1. **Income is linear in floors and each floor costs more than the last, and
   nothing on this tree changes that.** It is why the ladder stops at 20 (§0) and
   why the completionist's runs stretch to 5+ hours by run 3 (§6). The levers that
   would work are all income-side — the class multiplier (up to 1.8×), the fare
   itself, or the balance item's 4× riders at ¼ fare — and decision 14 excludes the
   first from persisting. **This gates extending the ladder past 20 floors**, and
   it should be answered before S5 ships rather than after, because the answer may
   change `height`'s costs.
2. **Three income-side levers are excluded from the model that sets
   `DEMOLITION_FLOOR`, and one of them is unmeasured. [r2]** In descending order
   of size: **`COMBO_MAX = 10.0`**, applied to the exact field the conversion
   consumes (§6) — run 1's yield is somewhere in [4, 15] BP against a 6-BP ladder,
   and the realised value has never been measured on a real run; the **1.8× class
   multiplier**; and **decision 19**. Measure combo first — it is the largest and
   the cheapest to check.
3. **Decision 19 invalidates §2 and §6 if it lands first.** "Target 8 trips/min at
   the starting building, fare ~$0.77 (4× riders, ¼ fare)" changes every earnings
   figure here, and `DEMOLITION_FLOOR = 900` is denominated in today's fare. If
   that ships first, re-run the simulation and **re-derive** the offset rather
   than scaling it — §2.1 shows the exit point is not a simple function of the
   constant.
4. **S4's sequencing rule is unaddressed.** The backlog is explicit: *"S4's
   signed-coordinate change is cheaper at six floors than at forty, and S5 makes
   the building taller. If both are wanted, the coordinate work comes first."*
   Keeping the building at today's 20 floors weakens the conflict but does not
   retire it — and decision 9 ("one budget, split") makes `Meta.height_cap()` the
   exact number the down axis will later have to split. Either do the coordinate
   work first or override the rule explicitly.
5. **The Automation branch has an orphan.** §4 drops it on the grounds that
   dispatch licences should be re-earned. Base §4's Automation is "dispatch
   policies, **offline cap, offline rate**" — the latter two are not per-run
   purchases and have no other home. When offline earnings ship, the branch
   returns and "two branches, not four" stops being true.
6. **Does a demolish keep the player's dispatch policies?** This spec resets them
   to MANUAL with the licences. Keeping the *preference* and reapplying it as
   licences are re-bought would remove a chore without granting power. Small
   enough to belong in the plan rather than here.
7. **Repo defect, found while writing this spec.** `CLAUDE.md`'s single-test
   commands do not work: `-gdir` takes a directory, and `-ginclude` does not exist
   at any GUT version in this checkout. Run as documented it prints
   `[GUT ERROR] Nothing was run` **and exits 0** — a false green before a commit.
   `codemaps/tests.md:10-11` already documents both correctly. The working forms
   are `-gtest=res://tests/test_x.gd` and `-gunit_test_name=test_name`.
   **[r2]** The premise is verified — `grep ginclude addons/gut/gut_cmdln.gd`
   returns nothing and `codemaps/tests.md:10-11` says so explicitly — but the
   *"and exits 0"* half was asserted without running Godot. Re-check it before
   quoting it as fact; the defect stands either way.
