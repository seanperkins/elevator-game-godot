# Floors you choose and invest in

**Status:** agreed, not yet built.
**Spec A of three.** B is signed floors and the basement; C is Demolish and
Blueprints. Built back to back, in that order.

Income is traffic, and traffic comes from tenants. So *which* tenant sits on a
floor is currently the largest untaken decision in the game: `relet()` restores
whatever was there, and every floor generates identical traffic at identical
hours. This spec makes a floor something you choose and something you invest in.

---

## 1. Why B comes before C

Prestige **resets the building**, so the reset path has to know the building's
shape. If signed floors arrive after prestige exists, the reset must learn about
a bottom floor retroactively. Build the shape, then build the thing that resets
it.

The basement is unreachable in the shipped game for exactly the duration of Spec
B, testable by dev flag only. Spec C lights it with a Structure node.

## 2. Prerequisite: the stairs penalty is dead

`Economy.note_expiry(fare := 0.0)` (`sim/economy.gd:39`) applies a stairs penalty
of one fare. The only production caller — `sim/game_state.gd:216` — passes no
argument, so every real expiry deducts `0.0 × 1.0 = 0`. The unit tests pass
because they call `Economy` directly. Nothing tested the wiring.

1. `economy.note_expiry(p.fare)` at the call site.
2. **Drop the default.** `func note_expiry(fare: float)`. The default *is* the
   bug's mechanism — a caller that forgets compiles and silently deducts nothing.
   Making it required turns this class of regression into a parse error.
3. A test **at the `GameState` level** that seeds cash first, runs a real expiry,
   and asserts the exact `min(fare, cash)` deduction.

The seeding is load-bearing: a fresh `GameState` holds `$0` and
`sim/economy.gd:42` caps the penalty at cash, so "assert cash fell" leaves
`$0 → $0` and fails against fixed and broken code alike.

Dropping the default breaks **two** bare callers, not one:

| Call | Test |
| --- | --- |
| `tests/test_economy.gd:40` | `test_expiry_resets_the_combo_and_the_streak` (`:36`) |
| `tests/test_economy.gd:47` | `test_expiry_does_not_take_cash_away` (`:44`) |

Both become `note_expiry(0.0)`; `:44` is renamed to say it tests the **zero-fare**
case, since it otherwise reads as contradicting `test_taking_the_stairs_costs_money`
(`:82`).

*(That §2 argues this exact discipline and then miscounted its own sweep is not
lost on me. It is why §5.2 applies the rule to `source_row` explicitly.)*

---

## 3. Ownership: three facts, three lifetimes

| Fact | Owner | Lives until |
| --- | --- | --- |
| **class** | `Fitout` *(new)* | never — it is built into the floor |
| **kind** | `Tenancy` | the tenant leaves |
| satisfaction, move-out clock | `Tenancy` | the tenant leaves |

**Things built into the floor persist; things built for the tenant leave with
them.** That is what makes replacing a tenant a real cost rather than a free
re-roll.

Both are **per-run**: prestige resets class and kind. Blueprints persist.

### 3.1 Two containers must grow together — one loop, not two

An earlier draft introduced a shared `FloorIndex` here to centralise the
floor→index mapping ahead of Spec B. That was wrong, and the reasoning is worth
keeping.

In Spec A the mapping is the **identity** (`bottom_floor` is always 0), so the
class earns nothing — and it *hides* the failure it appears to guard. The real,
historic failure is container **size** desync on floor purchase:
`sim/game_state.gd:53-54` grows `Tenancy` with an explicit catch-up loop
precisely because this desynced before, pinned by
`tests/test_game_state.gd:130-134`.

With direct indexing a desync is an **out-of-range access** — loud, caught. A
shared index object gives three counters that can disagree, so a short container
returns a valid-but-wrong index and a "the two containers agree" test **passes
anyway**, because both agree *through the object carrying the stale count*.

Spec A therefore does the load-bearing half only:

- `Fitout` indexes its dense array directly, as `Tenancy` does.
- `GameState` gains **one `_grow_per_floor_containers()`** that grows *every*
  per-floor container to `building.row_count`, replacing the inline `Tenancy`
  loop. One function rather than two identical ones, so forgetting a container is
  impossible rather than merely tested for — Spec B adds a third.
- A **mid-run floor-purchase test** asserts every container's length matches
  `row_count` and that the new floor has class 1 **and the vacancy/kind state
  §4.4 defines**.

`FloorIndex` returns in **Spec B**, where the mapping is genuinely non-identity.

---

## 4. What a tenant kind is

`data/tenants.json` **already exists and is dead** — it describes
`rent_per_minute` for a deli, a dentist and accountants, an income source removed
when rent was, and nothing loads it. This spec repurposes the file.

```json
{
  "classes": [
    { "tier": 1, "cost": 0,    "fare_multiplier": 1.00 },
    { "tier": 2, "cost": 400,  "fare_multiplier": 1.35 },
    { "tier": 3, "cost": 2500, "fare_multiplier": 1.80 }
  ],
  "kinds": [
    {
      "id": "office", "name": "Offices",
      "requires_class": 2, "lease_cost": 140.0, "base_fare": 4.0,
      "rate":     [24 floats],
      "inbound":  [24 floats],
      "outbound": [24 floats]
    }
  ]
}
```

- `rate` — trips per simulated minute generated by **one floor** of this kind,
  one bucket per simulated hour.
- `inbound` — share running **lobby → here**; `outbound` — share running
  **here → lobby**; the remainder is **interfloor**.

### 4.1 What "malformed" means

A file is malformed unless **all** hold:

- `rate`, `inbound`, `outbound` each have **exactly 24** entries.
- Every entry is finite and `>= 0`.
- `inbound[h] + outbound[h] <= 1.0` for every bucket — otherwise the interfloor
  remainder goes negative (`0.8 + 0.7 → −0.5`) and feeds a weighted pick.
- `id`s are unique; `lease_cost >= 0`; `base_fare > 0`.
- Every `requires_class` names a `tier` the `classes` array defines.
- `classes` tiers are contiguous from 1; `fare_multiplier > 0`; **every `cost` is
  finite and `>= 0`.** A negative cost is free money, not a discount:
  `Economy.can_afford(-400)` is `cash >= -400` → true, and `spend` then runs
  `cash -= -400` (`sim/economy.gd:50-56`), crediting $400.
- **`kinds` is non-empty and at least one kind has `requires_class == 1`.**
  Without this a file passing every other check can define one tier-3 kind, and
  both §9's no-fail guarantee ("the cheapest eligible kind is free") and §10's
  restore fallback would select from an **empty set** — the guarantee silently
  having no implementation.
- **Ties in `lease_cost` are broken by first appearance in the file**, so
  "cheapest eligible" is deterministic rather than dependent on JSON ordering.

**Refusal must propagate, and `_init` cannot return failure.** `GameState`
currently discards its loaders' results — `spawner.load_curve(...)` at
`sim/game_state.gd:37` and `upgrades.load_defs(...)` at `:41` both drop a
`false`. The mechanism: `GameState` sets an `invalid` flag, calls `push_error`,
and exposes `is_valid()`. **`SaveCodec.decode` returns `null`** — its documented
contract at `sim/save_codec.gd:69-70` — rather than propagating a poisoned
state. The catalog path is **injectable** so the §11 refusal test does not depend
on `res://data/tenants.json`.

`game/game_root.gd:_ready()` constructs unconditionally at `:50` and `:54` with
no alternative branch, so "the boot path refuses to start" needs a defined
behaviour rather than an intention. **On an invalid state the boot path shows a
static error screen naming the file and does not start the sim.** A malformed
shipped `tenants.json` is a build error a player can hit, and a blank board with
a console message they cannot see is indistinguishable from a hang.

### 4.2 The kinds

*(This is the **catalog** — what may be leased. The six-row **starting
assignment** is §4.3's `DEFAULT_ROSTER`, a different list that happens to be the
same length today. The word "roster" in this spec means only the latter.)*

| Class | Kind | Rhythm |
| --- | --- | --- |
| 1 | **Apartments** | out ~7am, in ~6pm; low volume |
| 1 | **Shops** | broad midday hump; interfloor-heavy |
| 2 | **Offices** | in ~8am, out ~5pm; high volume and spiky |
| 2 | **Gym** | twin peaks, early morning and evening |
| 3 | **Law Firm** | flat all day, low volume, high fare |
| 3 | **Clinic** | morning-weighted, moderate, high fare |

### 4.3 A new building

Six floors, all class 1: floor 0 **Shops**, floors 1–5 **Apartments**.

**Rows beyond the sixth arrive vacant, class 1, no kind**, so a constructed floor
and a purchased one (§4.4) agree. `GameState.new(rows, …)` is called with
`rows > 6` on two live paths and neither had a rule: `sim/save_codec.gd:77` (from
the save) and `game/game_root.gd:50` (the `--board=` debug override, which Spec B
leans on for basement testing).

**The divergence is by row index, not by entry point.** `Tenancy._init`
(`sim/tenancy.gd:36-38`) loops `_append_row()` once per row with nothing
distinguishing row 6 from row 0, so "diverge in `add_row()`" (§4.4) alone would
leave `GameState.new(40, …)` with **40 tenanted rows** — kindless ones, the exact
state §4.4 forbids. The rule: **`_init` tenants only the rows the default roster
covers; every row past that, and every row from `add_row()`, arrives vacant.**
`_append_row()` is still left alone, so §4.4's argument stands unchanged.

**The starting assignment has a name and one home:**
`GameState.DEFAULT_ROSTER: Array[String]` — six kind ids, `["shops",
"apartments", "apartments", "apartments", "apartments", "apartments"]`.

`Tenancy._init(row_count, tenanted_prefix)` takes the count as a second argument
and `GameState` passes `mini(row_count, DEFAULT_ROSTER.size())`, then applies the
**same array's entries** as those rows' kinds. Both uses derive from one list, so
they cannot drift.

*Not* the catalog's length. An earlier draft said `mini(row_count,
roster.size())` in a paragraph that bound "roster" to `tenants.json` — read
literally, adding a seventh **kind** would have tenanted a seventh **row**. The
two are both 6 today by coincidence, which is exactly the kind of coincidence a
spec should not encode.

**Ordering:** the catalog must load before `Tenancy` is constructed
(`sim/game_state.gd:39`). Nothing built before it — `clock`, `building`,
`spawner`, `economy` — needs the catalog, so the load slots in ahead with no
cycle, and §4.1's injectable path is an `_init` parameter available before any
member exists.

A **migrated v1 save** gets `apartments` on every **non-vacant** row (§10). Vacant
rows migrate with **no kind**, or the migration would violate §3's own lifetime
rule on the first load.

### 4.4 A purchased floor arrives vacant

`Tenancy.add_row()` (`sim/tenancy.gd:45-46`) delegates to `_append_row()`
(`:40-43`), which appends `_vacant = false` — so a bought floor arrives
**tenanted**. Under §4 a tenanted floor with no kind cannot spawn (§5 needs
`rate_at`), cannot price a fare (needs `base_fare`) and cannot draw a sparkline.
That state is reachable in the first minutes of play, through the game's primary
progression verb.

**Purchased floors arrive vacant, with class 1 and no kind.** The alternative —
a free default tenant — contradicts §8's headline that you choose who moves in,
and hands out a kind without charging the lease.

**The vacancy is never applied in `_append_row()`.** That helper is shared with
`Tenancy._init` (`sim/tenancy.gd:36-38`), whose first six rows must stay
*tenanted* per §4.3's default roster; flipping the append itself would make
**every floor of a new building vacant**. So `add_row()` (`sim/tenancy.gd:45-46`)
vacates after delegating, and `_init` vacates every row past the roster — see
§4.3, which states the rule as an index rule rather than an entry-point rule,
because an entry-point rule alone leaves `GameState.new(40, …)` fully tenanted
and kindless.

Consequences, owned rather than discovered — **two** tests invert, not one:

| Test | Line | Assertion |
| --- | --- | --- |
| `test_buying_a_row_extends_tenancy_too` | `tests/test_game_state.gd:134` | `assert_false(gs.tenancy.is_vacant(6), "the new row must have a tenant")` |
| `test_add_row_extends_tenancy` | `tests/test_tenancy.gd:122` | `assert_false(t.is_vacant(6))` |

Both are renamed to say the new row is vacant. The second is the `Tenancy`-level
twin of the first and fails for the same reason.
- Buying a floor now costs the floor **plus a lease**. That is the intended
  shape: "+ BUILD FLOOR" then choose a tenant is a two-step, and it is what
  teaches the panel.
- Buying a floor while `tenanted_count() < 2` yields a vacant floor whose
  cheapest eligible kind is free (§9). That is the no-fail guard working, not an
  exploit — the floor itself was paid for.

---

## 5. Spawning

`TrafficSpawner.spawn_for_tick(minute, sources)` where `sources` is an
`Array[TrafficSource]` — floor, `TenantKind`, fare multiplier — assembled and
cached by `GameState`.

1. `total = Σ source.rate_at(minute)`.
2. One Bernoulli trial against `total / TICKS_PER_MINUTE`.
3. Weighted pick of which source produced it.
4. Roll that source's inbound/outbound/interfloor mix.
5. Build the trip — inbound `LOBBY → F`, outbound `F → LOBBY`, interfloor
   `F → another tenanted floor` (uniform).
6. `fare = kind.base_fare × Fitout.fare_multiplier(source_floor)`

`sim/traffic_source.gd` (`TrafficSource`) holds floor, kind and multiplier, so
the spawner never learns about `Tenancy` or `Fitout`.

### 5.1 Satisfaction is credited to the generating floor

**This is the rule the first draft omitted, and omitting it was the fatal flaw.**

Satisfaction is attributed today by *endpoint* —
`tenancy.note_delivery(p.destination_row)` (`sim/game_state.gd:200`) and
`tenancy.note_expiry(p.origin_row)` (`:217`). That is correct *today* only
because `sim/traffic_spawner.gd:80-85` guarantees two tenanted endpoints, so
"endpoint" and "whose traffic this is" coincide. §5 makes the **lobby** an
endpoint of most trips and breaks that.

Under endpoint attribution, during a floor's outbound peak every expiry blames
the floor and every success credits floor 0. With `_DELIVERY_GAIN := 0.02` and
`_EXPIRY_LOSS := 0.05` (`sim/tenancy.gd:29-30`), that floor's satisfaction is
**monotonically non-increasing**: perfect service holds it flat (no expiries, no
credit — Δ = 0), and *any* imperfection is unrecoverable, because the only term
that could restore it went to floor 0. And floor 0 becomes uncapturable,
absorbing credit and blame from every other floor while its own kind choice is
meaningless.

§8 promises the move-out clock keeps its teeth. Endpoint attribution takes them
out.

**The rule:** satisfaction — credit *and* blame — goes to the floor that
generated the trip. The same floor that sets the fare.

This changes `sim/game_state.gd:200` and `:217`, and `tests/test_game_state.gd:124`
(`test_expiry_lowers_the_origin_rows_satisfaction`) is rewritten — its passenger
at `:126` must set `source_row = 3` explicitly for the assertion to mean
anything.

### 5.2 `Passenger.source_row` is required, with no default

`Passenger._init(origin, destination, patience, p_fare)` has **42** call sites,
all four-argument: `sim/traffic_spawner.gd:84` plus **41** across `tests/`
(`test_game_state` 18, `test_building` 8, `test_board_input` 6,
`test_elevator_car` 6, `test_auto_dispatch` 2, `test_passenger` 1).

The edit count is smaller than the site count: `tests/test_passenger.gd:4` is a
factory (`return Passenger.new(origin, dest, patience, fare)`), so that whole
file is fixed by one change.

`source_row` is a **required fifth parameter**. Defaulting it to `0` would make
every passenger built by anything that forgets attribute its satisfaction to
floor 0 — silently reconstructing the exact failure §5.1 calls fatal. Defaulting
it to `origin_row` changes delivery attribution from destination to origin, which
is a different bug.

This is §2's own argument applied to the field this spec introduces: the default
*is* the bug's mechanism, and a parse error across 41 sites is a better guard
than any test.

### 5.3 The cache must learn about **four** mutation paths

A cached `TrafficSource` holds floor, kind **and fare multiplier**, so it goes
stale when either `Tenancy` or `Fitout` changes. Four paths:

1. a **vacancy** set inside `accrue_for_tick()` (`sim/tenancy.gd:84-86`);
2. a **lease** (§8.2 replaces `relet()` entirely, so there is no separate relet
   path);
3. **`restore_row()`** (`sim/tenancy.gd:56-61`), called from
   `sim/save_codec.gd:101-104` — and §10 adds per-row `kind` restoration there;
4. a **class purchase**, which mutates **`Fitout`**.

**Path 4 is the one that defeats §6.** A revision counter on `Tenancy` alone
never moves for a class purchase, so upgrading a **tenanted** floor would leave
the stale ×1.00 multiplier cached until the next tenancy event — which on a
well-served floor may be never. That is precisely the inert button §6 exists to
argue against: the spec would ship the thing it rejects.

**The revision spans `Tenancy` and `Fitout`** — four paths, one value to compare.
Leaving "or `GameState.upgrade_class` rebuilds directly" as an alternative would
make §11.2's "the revision moves on all four paths" unsatisfiable for path 4
under half the choice, so the spec commits rather than offering an either/or a
downstream test silently assumes an answer to.

**Who owns it:** each class keeps its **own** monotonic counter, and `GameState`
compares `tenancy.revision() + fitout.revision()` against its cached baseline
with **`!=`, not `>`**. Each class stays independently constructible and
testable, and no third object holds state that can disagree with either (§3.1).

`!=` rather than `>` deliberately: `>` would be correct today, since both
counters only increment — but it silently stops working the moment any future
path swaps a container into a live `GameState` and resets a counter to zero.
`!=` costs nothing and does not depend on the monotonicity argument holding
forever.

**Path 3 is the one an earlier draft missed**, and it is the path every returning
player's session starts with: `GameState._init` builds the cache from §4.3's
default roster, `decode` then restores vacancies and kinds without moving the
counter, and every floor generates traffic with its *construction-default* kind
and fare.

`GameState` rebuilds the source list when the revision moves.

**A counter alone is not enough for §5.4.** It is floor-anonymous by
construction — it reports that something changed, not *which floor vacated* — and
§5.4 needs the row identity on the tick of vacancy. **`accrue_for_tick()` returns
the rows that vacated on that tick.** Its docstring at `sim/tenancy.gd:77-78`
("Returns nothing: tenants are not an income source, they are a traffic source")
exists to reject *rent*, not to reject all return values, but it says "returns
nothing" literally and so is **added to the rewrite list** in §5.5.

The alternative — `GameState` caching per-row vacancy and diffing it — is
rejected for the reason §3.1 rejects `FloorIndex`: it is a second copy of state
that can disagree with the first.

### 5.4 A move-out removes that floor's waiting passengers — **by source, not by queue**

An earlier draft accepted "a trip in flight when its floor is re-leased credits
the new tenant" as bounded. It is not: waiting queues are unbounded.

Its *fix* was also wrong, and wrong in both directions, because **queues are
indexed by `origin_row`** — `Building.enqueue` appends to `waiting[p.origin_row]`
(`sim/building.gd:44`):

- **Under-clears.** An **inbound** trip is `LOBBY → F`, so `origin_row = 0` and
  `source_row = F`. It waits in `waiting[0]`. Clearing `waiting[F]` removes none
  of them, and `waiting[0]` is exactly as unbounded as `waiting[F]` was. For the
  inbound-heavy kinds (§4.2's Offices, "in ~8am") that is the majority of the
  floor's peak traffic.
- **Over-clears.** `Tenancy` guarantees any row *including the lobby* may vacate
  (`sim/tenancy.gd:21-23`). When floor 0 vacates, `waiting[0]` holds **every
  other floor's inbound visitors** — clearing it would silently delete traffic
  generated by and credited to every other tenant in the building.

**The rule is source-scoped:** on floor F's vacancy, remove every waiting
passenger with `source_row == F`, from **all** queues. That is what "the tenant
left, so their visitors stop arriving" actually means — the visitors are the
inbound passengers standing in the lobby.

Removed passengers do **not** count as expiries: the expiries that caused the
move-out were already charged, and charging again would double-penalise one
failure.

What remains is genuinely bounded: passengers **already aboard a car**, capped by
total car capacity (8 shafts × 12 seats = 96). Those deliver normally and may
credit a replacement tenant.

The §11.2 test must assert the **property**, not the mechanism: *no waiting
passenger with `source_row == F` remains anywhere.* A test worded "clears that
floor's waiting queue" passes against the defective implementation.

*(The view is unaffected either way: it polls `waiting_at(i)` per frame,
`view/building_view.gd:311`, rather than tracking passengers, so silent removal
orphans nothing.)*

### 5.5 Stated edge cases

- **Floor 0 is not a normal endpoint unless it is tenanted.** When floor 0 is
  **vacant**, every kind's `inbound` and `outbound` weights collapse into
  interfloor — the same collapse applied to a tenant *on* floor 0, whose lobby
  trips would otherwise be lobby→lobby. This preserves the *property* asserted by
  `tests/test_traffic_spawner.gd:103-116`, and the guard at `:71`
  (`assert_ne(p.origin_row, p.destination_row)`) is the only existing defence
  against a degenerate trip — it must survive the rewrite in §11.1.
- **Fewer than two tenanted floors produces no traffic** — kept, but as a
  deliberate **policy guard** rather than arithmetic. Under §5 a lone tenant on
  floor F *could* generate lobby↔F traffic. Five blocks state a rule this spec
  changes and must be rewritten: `sim/tenancy.gd:15-19`,
  **`sim/tenancy.gd:116-118`** (the `MIN_ROWS_FOR_TRAFFIC` docstring, the
  rationale verbatim on the constant the guard reads),
  **`sim/tenancy.gd:77-78`** (`accrue_for_tick`'s "Returns nothing", which §5.3
  amends), `sim/traffic_spawner.gd:62-64`, and
  `tests/test_traffic_spawner.gd:74-75`. **`sim/traffic_spawner.gd:69-75`** — the
  `REFERENCE_ROWS` comment asserting the shipped opening is unchanged — is
  deleted with the constant.
- **The version bump is required by the new `kind` and `class` fields** — not by
  the changed RNG sequence. `sim/save_codec.gd:77` rebuilds from the seed without
  fast-forwarding, so the draw stream is already discontinuous across every load
  (§13).

### 5.6 Calibration, at both ends

**`REFERENCE_ROWS` scaling is deleted.** A per-floor rate summed over occupied
floors *is* the scaling `occupied / 6` provided; keeping both would give a
40-floor tower `40/6 ×` the traffic it already generates.

**The opening's daily total is pinned; its shape deliberately changes.** The
claim that this "keeps the shipped opening unchanged" was false and impossible:
§4.3 starts 5 Apartments (out-peak ~7am) and 1 Shops (midday), so the composite
peaks at hour **7**, while `data/traffic_walkup.json:4-9` peaks at hour **8**
(5.0 against 4.0). Both cannot hold.

**The concrete constraint:** Σ of the shipped curve's 24 buckets is **47.4**
trips per simulated day, so `5·Σ(Apartments) + 1·Σ(Shops) = 47.4`. That equation
is the §11 calibration test.

**And it is tight, which is the point of writing it down.** `Σ(Shops) >= 0`
forces **`Σ(Apartments) <= 9.48`** — a 24-bucket mean of `9.48 / 24 = 0.395`
trips per hour, which is the number an author should hold in their head.

How tight: a curve from §4.2's description ("out ~7am, in ~6pm; low volume") with
`A[7] = 1.2`, `A[8] = 0.9`, `A[18] = 1.2` spends 3.3 on three buckets, leaving 21.
A **flat 0.3 across all 21** sums to `3.3 + 6.3 = 9.6` and **breaks the ceiling by
1.3%**. Only an overnight trough buys the headroom back — 8 buckets at 0.1 and 13
at 0.3 gives 8.0, leaving `Σ(Shops) = 7.4`. Hour 8 alone spends `5 × 0.9 = 4.5`,
**9.5% of the whole day's budget**.

Author against the ceiling, not against the description.

**Second anchor.** Today, at the 40-row cap, peak demand is
`curve[8] × 40/6 = 33.3` trips/min. With **`Apartments[8] = 0.9`** — stated,
because the endgame figures derive from it — a 40-floor all-Offices tower at
2–4× Apartments is `40 × 1.8` to `40 × 3.6` = **72–144 trips/min**, i.e. 2.2× to
4.3× today's peak against unchanged delivery capacity (8 shafts, `4 + level` to
level 8 = 12 seats).

**Invariant:** `Σ rate < TICKS_PER_MINUTE` (1200). The Bernoulli form clips
silently at `p = 1` and emits at most one passenger per tick. The margin at the
table above is `1200/144` to `1200/72` = **8.3× to 16.7×** — ample, and not the
15–32× an earlier draft claimed. §5.6 deletes the only expression that bounded
the total, so the bound is written down rather than rediscovered.

**`data/traffic_walkup.json` survives** for `base_patience_ticks` (building-wide,
§14) and as the calibration reference. Its `buckets` stop driving the live sim.
**`base_fare` is orphaned and removed** — `sim/traffic_spawner.gd:11` and `:51`,
the `"base_fare"` key at `data/traffic_walkup.json:11`, and
`tests/test_traffic_spawner.gd:79-86`, which asserts `p.fare == spawner.base_fare`
at `:84`. Fares come from `kind.base_fare × multiplier`.

---

## 6. Class

Three tiers. Every floor starts at 1. Flat price per floor.

| Tier | Upgrade cost | Fare × | Unlocks |
| --- | --- | --- | --- |
| 1 | — | 1.00 | Apartments, Shops |
| 2 | $400 | 1.35 | + Offices, Gym |
| 3 | $2,500 | 1.80 | + Law Firm, Clinic |

**The fare multiplier is why the upgrade is not inert on a tenanted floor.**
Class gates leasing and leasing only happens on vacancy, so a class purchase with
no live effect pays nothing until the tenant leaves — a button you rationally
never press except in a crisis.

**The flat price is an early-game constraint and says so.** Converting a 40-floor
tower to class 3 is `40 × $2,900 = $116,000`, against a cumulative floor ladder of
≈ **$136M** — **0.085%**. Mid-game it bites (~15% of a full shaft ladder);
late-game it is free.

Purchases go through `GameState`, refused there rather than merely greyed.

---

## 7. Input: a hall column

`view/hall_column.gd` (`HallColumn`) — one `Control` over the hall region,
reusing `Gesture` and `PointerEvents` as `ShaftColumn` does. **TAP** →
`floor_selected(floor)`; **PAN** → `pan_requested(delta)`.

One input path rather than `_gui_input` per `FloorRow`, and a drag that crosses a
row boundary cannot become ambiguous.

**What it takes over from.** Not `FloorRow` — **`FloorRow` itself** is
`MOUSE_FILTER_IGNORE` (`view/building_view.gd:136`). The contested handler is
**`BuildingView._gui_input`** (`:283`), the current relet-tap path, which §8.1
retires.

**`HallColumn` introduces left-region panning; it does not preserve it.**
`BuildingView._gui_input` reads releases only and rows are `IGNORE`, so dragging
on the left does nothing today. The ghost-band drag forwarding below completes a
new capability rather than preventing a regression.

**Horizontal boundary.** `FloorRow.STRIP_RIGHT` = `64 + 176` = **240**
(`view/floor_row.gd:32`); `BuildingView.SHAFT_AREA_X` = **240** (`:21`).
`HallColumn` claims `x < 240` strictly, so a tap at exactly 240 is the shaft's.

**Vertical boundary.** The "+ BUILD FLOOR" ghost spans the hall region and must
keep its tap, because `y_to_floor` **clamps** above the roof
(`sim/coords.gd:99-104` returns `top_floor`) — a `HallColumn` that won would open
the top floor's panel instead of buying a floor, exactly when the roof is
scrolled into view. `HallColumn` therefore emits no `floor_selected` above the
roof, belt and braces, and is inserted below the ghost in the hall region.

**Stacking must survive `rebuild()`, not just `bind()`.** The ghost is moved last
in `_build_all()` (`view/building_view.gd:93-97`), but `rebuild()` then moves
`_shaft_viewport` last at **`:76`** — so after any floor or shaft purchase the
viewport is the last child, not the ghost. The conclusions hold (the viewport
sits at `x = 240`, `:89`, so it never contends with `x < 240`), but the invariant
§7 leans on is not the one the code holds, and `HallColumn`'s insertion point
must be re-established on every rebuild.

The ghost row gains **drag forwarding** to `pan_requested`, as `ShaftColumn` has.

---

## 8. The panel

`ui/floor_panel.gd` (`FloorPanel`) — a bottom sheet, inset by `SafeArea`, all
targets 44pt.

1. **Header** — floor, class, tenant, satisfaction bar.
2. **Sparkline** — the sitting tenant's day; absent when vacant.
3. **Upgrade class** — price and what it buys; refused by the sim regardless.
4. **Lease picker** — **only when vacant.** Each kind with sparkline and lease
   price; kinds above the floor's class greyed with the class they need. (Named
   the *picker*, not "the roster" — §4.3 has claimed that word for the starting
   assignment.)

You choose who moves **in**, not who moves **out**.

`view/day_sparkline.gd` (`DaySparkline`) — `_draw()`, 24 buckets, bar height
proportional to rate, split vertically by that minute's mix.

### 8.1 Retiring `ReletConfirm` — the UI surface

| Surface | What |
| --- | --- |
| `ui/relet_confirm.gd:1` | the class — delete |
| `game/game_root.gd:29` | `var _relet_confirm: ReletConfirm` |
| `game/game_root.gd:80` | `_view.relet_requested.connect(...)` |
| `game/game_root.gd:90-94` | construction, sizing, `add_child`, `bind` |
| `game/game_root.gd:159-160` | `_on_relet_requested` |
| `view/building_view.gd:19` | `signal relet_requested` — dead |
| `view/building_view.gd:29` | `const RELET_SPAN` — dead |
| `view/building_view.gd:280-291` | `_gui_input`, the current relet tap path |
| `view/building_view.gd:313-319` | `relet_cost` → price string → `set_tenant` |
| `view/floor_row.gd:142-146` | the `set_tenant` docstring describing the price in the strip |
| `view/floor_row.gd:148`, `:154` | `relet_price` param, `_price.text` |
| `view/floor_row.gd:28,33,42,91-102,118-120` | `VACANT_MAX_INDIVIDUALS`, `VACANT_STRIP_RIGHT`, `PRICE_WIDTH`, the `_price` Label, the sprite-cap arithmetic |
| `tests/test_board_input.gd:272,278,286` | three whole test functions, not four dangling assertions. `:278` (`test_a_tap_past_the_strip_reaches_the_column_not_the_confirm`) is the existing pin for §7's x-boundary and is **rewritten**, not deleted |

**The price leaves the strip**, so `VACANT_MAX_INDIVIDUALS := 9` and
`VACANT_STRIP_RIGHT` are deleted and a vacant row draws the full
`MAX_INDIVIDUALS := 12`.

### 8.2 Retiring `RELET_COST` — the pricing surface

§8.1 sweeps the UI; this sweeps the model underneath it, which an earlier draft
left entirely untouched. `relet(row)` becomes **`lease(row, kind_id)`**, and the
flat `RELET_COST` becomes a per-kind `lease_cost`.

| Surface | What |
| --- | --- |
| `sim/tenancy.gd:27` | `const RELET_COST := 40.0` — replaced by per-kind `lease_cost` |
| `sim/tenancy.gd:116-118` | the `MIN_ROWS_FOR_TRAFFIC` docstring (also §5.5) |
| `sim/tenancy.gd:121-122` | `relet_cost(_row)` — **deliberately ignores its row**, which a per-kind price cannot |
| `sim/tenancy.gd:124-129` | `relet(row)` — "restores whatever was there" is the behaviour this spec exists to replace |
| `sim/game_state.gd:58-66` | the `relet` **docstring** — "wiring the view straight to tenancy would have made re-leasing free forever" plus the cost-before-mutate paragraph §12 preserves. Describes a verb that stops existing |
| `sim/game_state.gd:67-76` | `GameState.relet` → `lease`, preserving the charge-before-mutate order §12 protects |
| `view/building_view.gd:313` | `_state.tenancy.relet_cost(i)` |
| `tests/test_tenancy.gd:68,80,91,99,108` | five test **functions** pinning relet pricing and restore (their assertions are at `:77,89,97,116` and their `relet()` calls at `:104,117`) |
| `tests/test_tenancy.gd:120-122` | `test_add_row_extends_tenancy` — also inverted by §4.4 |
| `tests/test_game_state.gd:147-190` | six tests: `_charges_the_cost`, `_is_free_when_nothing_is_tenanted`, `_is_refused_when_unaffordable_and_charges_nothing`, `_is_refused_on_a_tenanted_row`, `_is_refused_outside_the_building`, `_reads_the_cost_before_reletting` — the last one's closing assertion is `:190` ("free, not $40"), which is the §12 invariant |

Each of the six `GameState` tests has a `lease` equivalent; the last one —
cost-read ordering — is the §12 invariant and must survive verbatim in spirit.

---

## 9. The no-fail guarantee

When `tenanted_count() < 2`, **the cheapest eligible kind on the floor is free**
(ties broken by file order, §4.1).

An earlier draft made *every* kind free and claimed the class gate made that
safe. It does not: a floor already upgraded to class 3 offers Law Firm and
Clinic, so the recovery rule handed out a **free premium tenant** to anyone who
let occupancy collapse. Cheapest-eligible keeps the guarantee exact — a $0 player
can always lease and recover — while removing the reward.

§4.1's "at least one tier-1 kind exists" is what makes this implementable.

---

## 10. Save

`SaveCodec.VERSION` 1 → 2. Each row gains `kind` and `class`.

**The version gate accepts `{1, 2}`** — `sim/save_codec.gd:118` is
`!= VERSION` today — **with version-specific required fields.** Only v1 may
infer `kind` and `class`; a v2 row missing either is malformed and must not
silently receive v1 defaults.

**"No kind" has an explicit encoding: `"kind": null`.** v2 requires the field to
be *present*; a vacant row (or a purchased one, §4.4) carries `null`, and a
non-vacant row carries a valid string id. Without this, "a v2 row missing `kind`
is malformed" and "vacant floors have no kind" contradict each other, and a
legitimate save containing a newly bought floor is either rejected or restored
with a tenant it never had. A **vacant v2 round trip** is tested.

**A `rows` array shorter than `row_count` is malformed in v2.**
`sim/save_codec.gd:101` restores `mini(saved_rows.size(), row_count)` rows, so any
row beyond the saved array silently keeps a constructor default that contradicts
the save — a kind and class for rows 0–5, and **vacancy for every row past the
roster** (§4.3). The second is the more likely case in a tall building and the
worse one: it is the silent loss of a floor the player leased, not a phantom
tenant. v1 may still fall through (§4.3 defines what those rows get); v2 may not.

**A v1 save migrates rather than being refused.** Absent `class` is 1; absent
`kind` is `apartments` **on non-vacant rows only** — a vacant v1 row migrates
with no kind, or the first load violates §3's lifetime rule. The docstring at
`sim/save_codec.gd:17-19` says an old save "must either load or be refused", so
this is a clarification of which branch applies, not a contradiction to carve out.

**Restoration is cross-checked.** Independent validation lets
`{class: 1, kind: "law_firm"}` through — a known id skips the unknown-id
fallback and the class clamp never looks at the kind. Restoration asserts
`kind.requires_class <= class` and falls back to the cheapest eligible kind.

Class is **bounded at tier 3**, not prevented: clamping an edited `"class": 99`
yields 3, so hand-editing still reaches the top tier. This matches
`sim/upgrades.gd:48-51`, which likewise does not cap at `max_level`.

---

## 11. Tests

### 11.1 The spawner API sweep

`spawn_for_tick(minute, occupied: PackedInt32Array)` becomes
`spawn_for_tick(minute, sources: Array[TrafficSource])`. **Fourteen call sites in
`tests/test_traffic_spawner.gd` stop compiling**: lines 33, 34, 45, 46, 57, 64,
70, 77, 82, 109, 120, 137, 138, 151.

An earlier draft named one and claimed another "keeps passing". Both were wrong:
`test_only_tenanted_floors_generate_or_receive_trips` calls `spawn_for_tick` at
`:109` and cannot compile. Its *property* is preserved; its *text* is not, and a
rewritten test proves nothing about the old behaviour unless deliberately written
to.

Two sites pin invariants this spec changes and must be carried across
deliberately, not ported mechanically:

- **`:71`** `assert_ne(p.origin_row, p.destination_row)` — the only guard against
  the lobby→lobby trip §5.5's collapse exists to prevent.
- **`:84`** `p.fare == spawner.base_fare` — dies with `base_fare` (§5.6).

**Three symbols are being deleted, not one.** `rate_at_minute` and `curve` go
with `spawn_for_tick`, and sweeping only the first is round-2's finding repeating
one symbol over. Four further test functions in the same file have **no**
`spawn_for_tick` call and so appear nowhere in the list above:

| Line | Function | Symbol |
| --- | --- | --- |
| `:11` | `test_curve_has_one_entry_per_minute_of_the_day` (`:10`) | `spawner.curve` |
| `:14` | `test_rate_wraps_around_the_day` (`:13`) | `rate_at_minute` |
| `:19` | `test_rate_is_piecewise_constant_within_a_bucket` (`:17`) | `rate_at_minute` |
| `:22` | `test_rush_hour_rate_exceeds_the_overnight_rate` (`:21`) | `rate_at_minute` |

`:22` pins **rush > overnight**, a property worth carrying across deliberately
like `:71` and `:84`. (`:58` and `:152` also use `rate_at_minute` but sit inside
functions the fourteen-line list already condemns.)

**`:19` is a tautology and must be carried across *fixed*, not ported.** It reads
`assert_almost_eq(spawner.rate_at_minute(8), spawner.rate_at_minute(8), 1e-9)` —
it compares a value with itself and cannot fail. Whatever
`test_rate_is_piecewise_constant_within_a_bucket` was meant to pin, it does not
pin it today, and porting it unchanged would carry a test that is green by
construction onto the new curve.

Also affected beyond that file:

- The silencing idiom `spawner.curve = PackedFloat32Array()` at
  `tests/test_game_state.gd:216`, **`:261`** (`quiet_state`, the fixture behind
  six parked-car tests at `:267, 280, 289, 300, 311, 321`), and
  `tests/test_auto_dispatch.gd:13` and **`:136`**.
- `tests/test_game_state.gd:252-254` (`test_the_opening_rate_is_a_rush_rate`) — a
  whole test, not the single line `:253` — calls `spawner.rate_at_minute(...)`.
- `tests/test_game_state.gd:235-250` asserts >4 spawns in the opening three
  minutes, calibrated to a curve shape §5.6 deliberately changes. **Re-derived,
  not ported.**

### 11.2 New and changed tests

**Sim**

- **Satisfaction credit and blame both land on the generating floor** — asserted
  separately for an outbound delivery and an inbound expiry.
- **A tenanted floor 0 generates only interfloor trips**, none with
  `origin == destination`. This is §4.3's *shipped default*, so it is the code
  path from the first frame — and the collapse case an earlier draft left
  untested while testing the vacant one.
- **Class survives a tenant change; kind does not.**
- **A class-3 floor's *new* tenant is charged ×1.80** — the composition of the
  two tests above, and the point where §3's two lifetimes meet.
- **Upgrading the class of an *already tenanted* floor changes its fare on the
  very next spawn, with no intervening tenancy event** (§5.3 path 4). The test
  above cannot catch that failure: a *new* tenant means a `lease()`, which moves
  the revision and rebuilds the cache, so it passes whether or not `Fitout`
  invalidates. This is the one that discriminates, and without it the spec ships
  the inert button §6 argues against.
- **Every per-floor container matches `row_count`** after a mid-run
  `buy("row")`, and the new floor is **vacant, class 1, no kind** (§4.4).
- **`GameState.new(rows > 6, …)` tenants rows 0–5 per the roster and leaves every
  row past it vacant with no kind** (§4.3). Nothing else covers this: the
  `buy("row")` test and the save round-trips all pass whether or not `_init`
  applies the roster limit. It is also the state every `--board=` session and
  every pre-restore `decode` starts from, so it is the default a screenshot
  shows.
- **The draw count is independent of *source* count**, not floor count: inject an
  RNG whose `randf()` returns `0.0` so both buildings take the spawning branch
  (`sim/traffic_spawner.gd:78` is `if randf() >= per_tick: return`), then assert a
  6-source and a 40-source building take the same number of draws. Asserting
  equal counts *without* pinning the branch cannot pass — a larger `total` means
  a larger `p`, different branches, different counts, for exactly the reason
  `.state` comparison was rejected. The RNG seam is a **duck-typed member**, not
  a `RandomNumberGenerator` subclass, to avoid `NATIVE_METHOD_OVERRIDE`.

  **This test is spawner-level.** `spawn_for_tick` now takes a plain
  `Array[TrafficSource]`, and `TrafficSource` is a `RefCounted` the test builds
  directly — so a 6-source and a 40-source fixture need no `GameState`, no
  `lease()` calls and no seeded cash. (An earlier draft cited this test as a
  reason for §4.3's vacant rule, which was backwards: a vacant row is not a
  source, so under that rule a 40-*row* `GameState` has 6 sources and would need
  34 leases. §4.3 stands on its two real paths instead.)
- **The revision moves on all four paths** (§5.3) — vacancy, lease,
  `restore_row`, class purchase. An earlier draft tested only vacancy; of the
  three it missed, one is the path every load takes and one defeats §6.
  `accrue_for_tick()`'s returned row identity is asserted too, not just that the
  counter moved.
- **A move-out removes every waiting passenger with `source_row == F`, from all
  queues**, and charges no expiry (§5.4). Asserted as the property, including the
  inbound case — a lobby-queued passenger with `source_row == F` is removed while
  one with `source_row == G` survives. A test worded "clears that floor's queue"
  passes against the defective implementation.
- **`inbound[h] + outbound[h] > 1.0` is refused** — named separately from the
  other §4.1 rules, because it is the only one whose failure is silent (a
  negative share feeding a weighted pick) rather than a crash.
- **A catalog with no tier-1 kind is refused** (§4.1) — otherwise §9 has no
  implementation.
- Malformed `tenants.json` is fatal at `GameState` construction, via an
  **injectable** catalog path; `SaveCodec.decode` returns `null` rather than
  propagating an invalid state.
- The **starting roster's daily total is 47.4** (§5.6) — this replaces
  `tests/test_traffic_spawner.gd:142-153`, which asserts `REFERENCE_ROWS == 6`
  and will not compile.
- Offices peak inbound at **hour 8**; Apartments peak outbound at **hour 7** —
  each pinned to its own curve's peak.
- `Σ rate < TICKS_PER_MINUTE`, asserted as `MAX_ROWS × (largest single bucket in
  tenants.json) < 1200` — one assertion, exhaustive by construction. "Every
  kind combination" is 6⁴⁰ and is not a writable test.
- **A catalog with a negative class `cost` is refused** (§4.1) — the one
  malformed-file case that *credits* the player rather than crashing.
- Below two tenants the **cheapest eligible** kind is free and others are not.
- **A real expiry in `GameState` deducts cash**, with cash seeded and the exact
  `min(fare, cash)` asserted (§2).

**Save**

- v2 round-trips kind and class; a v1 save loads at class 1 / `apartments`, and a
  **vacant** v1 row loads with **no kind**.
- **A vacant v2 row round-trips as `"kind": null`** — the state a newly purchased
  floor is in, so this is the common case, not an edge one.
- A v2 row missing `kind` or `class` is refused, not defaulted; so is a v2 `rows`
  array shorter than `row_count`.
- `{class: 1, kind: "law_firm"}` falls back; an unknown id falls back; an
  out-of-range class bounds to 3.

**View**

- `HallColumn` tap selects the floor it looks like **after scrolling**; a drag
  pans and does not select.
- A tap on the **ghost band** buys a floor and does not open a panel; a drag
  starting there pans; both still hold **after a `rebuild()`** (§7).
- A tap at exactly `x = 240` reaches the shaft — the rewritten
  `tests/test_board_input.gd:278`.
- The lease picker is hidden while tenanted, including during a move-out
  countdown.
- `DaySparkline` draws 24 buckets; segment heights match the mix.

---

## 12. What must not regress

- The sim never touches the scene tree; `Fitout`, `TenantCatalog`, `TenantKind`
  and `TrafficSource` are `RefCounted`.
- One row↔y transform, with all consumers going through it.
- **One `_grow_per_floor_containers()`**, pinned by a mid-run buy test.
- Zero-delta and unaffordable purchases refused by the sim, not merely greyed.
- **`lease()` reads the cost before mutating tenancy** — the invariant
  `GameState.relet` carries today (`sim/game_state.gd:72-75`), since cost derives
  from `tenanted_count()` which leasing increments.
- The fixed tick order in `GameState`'s docstring is unchanged.
- 44pt touch targets. The one exception retires with `relet_confirm`.

---

## 13. Accepted limitations

- **The save does not persist RNG state.** `sim/save_codec.gd:77` restores from
  the seed without fast-forwarding, so the draw stream restarts on every load.
  **Pre-existing**, not introduced here; fixing it means persisting
  `RandomNumberGenerator.state` and is a separate change.
- **Passengers already aboard a car when their floor is re-leased credit the new
  tenant** — bounded by total car capacity, 8 shafts × 12 seats = **96** (§5.4).
  Waiting passengers, which were unbounded, are removed by `source_row` across
  all queues.
- **Hand-edited saves reach tier 3** (§10) — bounded, not prevented, consistent
  with `Upgrades.restore_levels`.

## 14. Deliberately not in this spec

- **Improvements** (tenant-scoped throughput) and **amenities** (floor-scoped
  tolerance).
- **`FloorIndex`** — deferred to Spec B, where the mapping is non-identity.
- **Tenants who will not mix.**
- **Per-kind patience.** Fares vary by kind and class; patience stays
  building-wide, which is why `traffic_walkup.json` survives.
- **Reputation gating which kinds exist at all.**
- **Offline earnings.** Still §9.1, still unsettled, still deliberately unbuilt.
