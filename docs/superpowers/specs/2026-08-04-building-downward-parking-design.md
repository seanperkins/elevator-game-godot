# Building downward, part one: parking

**Status:** design approved 2026-08-04, not yet implemented.

Floors below the lobby. This spec covers **only** the first of the three
subsystems the backlog entry describes — the down axis itself, plus parking as
the reason it exists. Materials, mining, basement tenant kinds beyond parking,
and the depth era ladder are explicitly out of scope (§10).

---

## 1. Why the backlog entry's analysis no longer applies

The entry (`docs/superpowers/backlog.md`, "Building downward") is built on a
constraint that has since dissolved, and reading it without this section will
send an implementer down a path that is no longer necessary.

It says: *"The board never scrolls vertically, and that is load-bearing. §3.5
rejected vertical scrolling explicitly."* It then offers "three ways out, none
free", of which the recommended one is **one budget, split** — dig a basement
and lose a tower floor.

None of that holds:

- **The board scrolls.** `BoardCoords.scroll_offset` exists, rows are a fixed
  `FLOOR_HEIGHT = 120`, and dispatch became a tap. The entire conflict was
  downstream of the absolute-drag input model, which is gone.
- **`BoardCoords` is already signed.** `bottom_floor` is a field, `fixed(bottom,
  top, height)` computes its count as `top - bottom + 1`, and `y_to_floor`
  returns `top_floor - k`, which goes negative correctly today. Its docstring
  says so in as many words: *"a building with a basement runs from a negative
  floor upward."*
- **The band-below affordance is already half-built.** `BoardCoords.headroom`
  (2026-08-04) widens the scroll clamp so the ghost band above the roof is
  reachable. The dig band is its mirror.

So the sacrifice-a-floor-per-basement rule is **not** adopted. Depth and height
are independent budgets.

---

## 2. Coordinates: floors go signed, arrays stay dense

`Building` gains one field:

```gdscript
## Floors dug below the lobby. The building runs -depth .. floor_count - 1.
var depth: int = 0
```

**`floor_count` keeps meaning "tower floors"** — the count of floors at index 0
and above. It does *not* become the total. Two accessors carry the rest:

```gdscript
func bottom_floor() -> int:  return -depth
func total_floors() -> int:  return floor_count + depth
func has_floor(f: int) -> bool: return f >= -depth and f < floor_count
```

### Dense arrays, one translation

Four arrays are per-floor and all of them now span the basement:
`Building.waiting`, `Tenancy._satisfaction`, `Tenancy._vacant`,
`Tenancy._move_out_left`, and `Fitout._tier`. Every one stays **dense and
zero-based from the BOTTOM floor**, with exactly one translation per owner:

### ONE depth, shared by reference — and why `Fitout`'s docstring must change

`sim/fitout.gd:12-16` says it indexes its array directly and that **a shared
index object was considered and rejected**:

> *in a building whose bottom floor is always 0 the mapping is the identity, so
> it earns nothing, and it converts a container-size desync from a loud
> out-of-range access into a silent valid-but-wrong index that an "the containers
> agree" test would pass through.*

The first half of that argument is a **precondition this spec deletes** — the
bottom floor is no longer always 0, so the mapping stops being the identity and
starts earning its keep.

The second half survives and is the real hazard. With `f + _depth` copied into
`Tenancy` and `Fitout`, a `_depth` that is stale by one maps floor −1 onto floor
−2's slot: in range, wrong answer, and an "arrays are the same length" test
passes straight through it.

So the resolution is not to copy the offset into three owners. It is to have
**one**, shared by reference:

```gdscript
class_name FloorIndex
extends RefCounted

## Which array slot a FLOOR occupies. There is exactly one of these per building
## and Tenancy, Fitout and Building share the same instance by reference, so a
## desync is not a bug to test for -- it is unrepresentable.
##
## Fitout's docstring rejected this, correctly, while the bottom floor was always
## 0: the mapping was the identity and earned nothing. Digging deletes that
## precondition. What the rejection got right and still applies is that a COPIED
## offset turns a desync into a silent wrong answer, which is exactly why this is
## shared rather than duplicated.
var bottom: int = 0        ## the lowest floor: -depth
var above: int = 1         ## one past the top: floor_count

func slot(f: int) -> int:   return f - bottom
func holds(f: int) -> bool: return f >= bottom and f < above
func size() -> int:         return above - bottom
func dig() -> void:         bottom -= 1
func grow_up() -> void:     above += 1
```

`Building` constructs it and passes the same instance to `Tenancy` and `Fitout`.
Every per-floor accessor becomes `_array[_index.slot(f)]` guarded by
`_index.holds(f)`, so an out-of-building floor is refused rather than wrapped.

**`Fitout`'s docstring must be rewritten as part of this work**, not left
contradicting the code. A comment that argues against what the file now does is
worse than no comment, and this one is load-bearing enough that the next reader
will believe it.

`dig()` inserts at the front of each array and increments depth; `add_floor()`
appends, as it does today. Front insertion is O(n) on at most 48 entries and
happens once per purchase.

### THE HAZARD THIS SECTION EXISTS FOR

**Nine sites loop `range(floor_count)`**, and here they are, because a number
without a list is a number nobody checks:

| site | what it means |
| --- | --- |
| `sim/building.gd:23` | building `waiting` at construction — **every floor** |
| `sim/tenancy.gd:46` | sizing the tenancy arrays — **every floor** |
| `sim/game_state.gd:369` | building the `TrafficSource` list — **every floor** |
| `sim/game_state.gd:443` | (audit at implementation) |
| `sim/save_codec.gd:262` | encoding `floors` — **every floor** |
| `sim/save_codec.gd:410` | decoding `floors` — **every floor** |
| `sim/auto_dispatch.gd:88` | sweep targets — **every floor** |
| `sim/dispatch_policy.gd:65` | scanning for calls — **every floor** |
| `view/building_view.gd:198` | building `FloorRow`s — **every floor** |

Every one is currently correct *because* floors start at 0. Once a basement
exists each is one of two things, and they must be separated deliberately rather
than by whichever the implementer touched first:

- **"every floor in the building"** — must become
  `range(bottom_floor(), floor_count)`. Refreshing rows, building the traffic
  source list, encoding the save, accruing move-out countdowns.
- **"every tower floor"** — must stay `range(floor_count)`. Anything reasoning
  about the tower specifically.

An audit of all 13 is a required step of the implementation plan, not a
side-effect of it. A missed one does not crash; it silently skips the basement,
which reads as "parking does nothing".

### The view

`BoardCoords.fixed(-building.depth, building.floor_count - 1, FLOOR_HEIGHT)`.
Nothing in `BoardCoords` changes except §7's `footroom`.

### Cars

`ElevatorCar` positions are floats over the floor range and already tolerate
negatives — `BoardCoords.car_y` documents the case (*"or -1.5, on the way into
the basement"*). What needs auditing is every clamp of a car target to
`[0, floor_count)`; those become `[bottom_floor(), floor_count)`.

---

## 3. Parking is a tenant kind

A basement floor is **leased like any other floor**: it has a tenant kind,
satisfaction, a move-out countdown and a fitout tier, and a dug-but-unleased
basement is vacant and draws the construction shell.

This costs the index work in §2 — the alternative, parking as pure
infrastructure, would have left `Tenancy` and `Fitout` untouched at 0..N. It is
worth paying for three reasons, and the first is the largest:

1. **The next two specs are basement floor KINDS.** Mining, storage, bedrock,
   caverns. As a tenant kind, each is one more entry in `data/tenants.json`. As
   infrastructure, each needs a parallel model or a migration off one.
2. **Satisfaction gives parking the same feedback loop the tower has.** Serve
   drivers badly and the garage empties: expiries at the parking floor drive its
   satisfaction down, and it moves out like any tenant, taking its arrivals with
   it. That is the existing loop, not a new one.
3. **A vacant basement is free.** The construction-shell scenery, the lease
   picker, the floor panel and the class upgrade all work already.

**The lease picker on a basement floor offers only `parking` today.** A choice
with one option is not a choice, and that is accepted: it is the seam the mining
spec fills, and building it now costs nothing because the picker already filters
by `requires_class`.

### Where a kind may be leased

`TenantKind` gains one field beside `requires_class`:

```gdscript
## Which half of the building this kind belongs to. A garage cannot be leased on
## floor 7 and an office cannot be leased at -2; without this the picker offers
## every kind everywhere and the first thing a player does is put a car park on
## the roof.
enum Where { TOWER, BASEMENT }
var where: Where = Where.TOWER
```

Read from `data/tenants.json` as `"where": "basement"`, defaulting to `tower`
when absent so the six existing kinds need no edit.

---

## 4. Traffic: parking is an ENTRANCE, not a source

### The distinction, and why it needs a flag

A normal tenant kind *generates* trips: its `rate` says how many, and `inbound`
/ `outbound` say whether they run to or from the lobby.

**A garage generates nothing.** Nobody rides to a car park for its own sake.
What a garage does is change where *other floors'* inbound trips originate — it
is a second front door. A garage with an `inbound` weight would mean "trips from
the lobby to the garage", which is nonsense the traffic model would happily
spawn.

So `TenantKind` gains a second field:

```gdscript
## An ENTRANCE kind does not generate trips; it RECEIVES arrivals that other
## floors generate. A visitor comes in through it, they are not going to it.
## Entrance floors join the entrance set instead of the source list.
var entrance: bool = false
```

The mine, when it arrives, is a normal source and not an entrance — it genuinely
generates trips, of freight, going up. The flag keeps that distinction available
rather than assuming "basement" and "entrance" are the same thing.

### What the kind looks like in data

```json
{ "id": "parking", "name": "Parking", "where": "basement", "entrance": true,
  "requires_class": 0, "lease_cost": 300.0, "base_fare": 0.0,
  "rate": [], "inbound": [], "outbound": [] }
```

`base_fare` is **0** because a garage earns nothing directly (§4), and the three
curve arrays are **empty** because an entrance generates no trips. That is a
shape `TenantCatalog` does not currently accept — it validates that the arrays
are present and correctly sized, which is the right check for a source and the
wrong one for an entrance.

**So the catalog's validation branches on `entrance`**, and this is a
fatal-if-malformed file: an entrance kind must have empty curves, a source kind
must have full ones, and either holding the other's shape is a load failure
rather than a silently ignored field. `rate_at`, `inbound_at` and `outbound_at`
must return 0 for an entrance rather than indexing an empty array.

### The model

Today one Bernoulli trial per tick runs against the summed rate of every
`TrafficSource`, then a weighted pick chooses which source produced the trip,
then `_destination_for` decides inbound / outbound / interfloor. Inbound trips
originate at `LOBBY = 0`.

Parking changes two things and nothing else:

1. **The summed rate is scaled** by `1 + PARK_BONUS * leased_entrances`, where
   `leased_entrances` counts basement floors with a *tenanted* entrance kind —
   a vacant garage adds nothing, which is what makes §3's satisfaction loop bite.
2. **When a trip is inbound**, the entrance is drawn: with probability
   `PARK_BONUS * n / (1 + PARK_BONUS * n)` it is a parking floor, chosen
   uniformly among the leased ones; otherwise it is the lobby.

**One Bernoulli trial per tick is preserved.** That is not incidental tidiness —
the existing docstring explains that a trial per occupied floor would make the
seed sequence depend on building height, and the same argument applies to depth.
Scaling the summed rate keeps the draw count fixed.

```gdscript
## Extra inbound arrivals per LEASED parking floor, as a fraction of the
## building's base rate. THIS NUMBER IS A GUESS AND MUST BE MEASURED before it
## ships -- see §9. Run 1 digs 2, so it is a +30% traffic swing on a board that
## now also caps at two shafts.
const PARK_BONUS := 0.15
```

### Uniform entrance choice is a diminishing return, for free

Arrivals spread uniformly across leased parking floors, so digging deeper moves a
*fixed* share of arrivals further from their destination. The marginal value of
depth therefore falls without any explicit curve: the fourth parking floor adds
the same trips as the first, but they cost more car time to serve.

### Income credit is unchanged

The project invariant is that income is credited to the floor that *generated*
the trip (`Passenger.source_floor`), not the endpoint. A visitor parking at −2
and riding to an office on 7 is the office's visitor: `source_floor = 7`,
`origin_floor = -2`. Nothing in `Economy` changes.

**The garage earns nothing directly, and that is deliberate.** Its value is the
traffic it enables, which is the same rule the design already states for every
tenant: *"a tenant's only value is the traffic it generates"*. A garage that also
charged a fare would be rent by another name.

### The garage's satisfaction

A parking floor's satisfaction responds to the passengers who *originate there* —
`note_delivery` and `note_expiry` already take a floor, and an arrival waiting in
the garage is waiting at floor −2. So the loop closes with no new machinery: slow
service in the basement empties the basement.

### The lobby-collapse rule gets a parking exception

Inbound traffic currently collapses to interfloor whenever floor 0 is vacant,
because a lobby that nobody leases is not a usable endpoint
(`TrafficSpawner._destination_for`, `BuildingDay.mix`).

**Parking arrivals do not collapse.** A driver who parks at −2 and rides to an
office never needs a lobby tenant; the collapse rule exists because an untenanted
*lobby* cannot be an endpoint, and a leased parking floor is a different
endpoint that is not untenanted.

The consequence is worth stating plainly because it looks like a loophole and is
not: **parking keeps a building earning with no leased lobby.** That
*strengthens* the no-fail-state invariant — a stranded player with a vacant lobby
and a leased basement still has a working building. It does not weaken the reason
re-leasing is free below two tenanted floors; it adds a second way out of the
same hole.

`BuildingDay` must reproduce this exactly, as it already reproduces the
collapse — the day chart is derived from the same sources and would otherwise
draw a curve the sim does not spawn.

---

## 5. The brake is car time, not patience

Depth is bounded by two things, and only one of them is new.

**The soft brake is throughput, and it already exists.** A trip from −4 is four
floors longer than one from the lobby. It occupies a car for longer, so everyone
else waits longer, so more of them expire. You dig until your shafts cannot
cope, buy speed / capacity / another shaft, and dig again.

**State precisely why this is second-order, so nobody "fixes" it.** Patience is
frozen aboard — a rider's bar stops draining the moment the doors open, and
`test_a_rider_has_no_patience_bar_and_a_waiter_does` pins it. A longer *ride*
therefore does not burn the rider's own patience. It burns car time. An
implementer who notices the gap and adds in-transit patience drain would be
changing a deliberate rule, not closing an oversight.

**The hard ceiling is the tree** (§6).

---

## 6. Digging: a `dig` upgrade under a `depth` node

The shape floors and shafts both now follow — a per-run cash price under a
permanent meta ceiling.

### The run-side purchase

`data/upgrades.json` gains:

```json
{ "id": "dig", "name": "Dig Down", "base": 400.0, "growth": 1.35, "max_level": 8 }
```

Between a floor (200 / 1.1) and a shaft (500 / 2.2): excavation costs more than
adding a storey and less than sinking a shaft. `max_level` is the hard ceiling;
the run's actual budget is set from the tree.

`Upgrades._apply` gains one arm:

```gdscript
		"dig":
			return building.dig()
```

`GameState` gains, beside the two that are already there:

```gdscript
	upgrades.set_max_level("dig", meta.depth_cap())
	upgrades.grant_level("dig", building.depth, building)
```

The budget is `depth_cap()` with no base subtraction, unlike `floor` and
`shaft`: a building starts at depth 0, so every level of `dig` is a purchase.

**Digging produces a VACANT basement floor.** It is excavation, not a lease; the
floor then goes through the ordinary lease flow. This is why `Tenancy` and
`Fitout` must grow on `dig()` and not on lease.

### The tree-side ceiling

`data/blueprints.json` gains a fourth structure node:

```json
{ "id": "depth", "name": "Deep Excavation", "branch": "structure",
  "base": 9, "max_level": 3, "note": "+2 floors you may dig" }
```

`sim/meta.gd`:

```gdscript
const BASE_DEPTH_CAP := 2
const DEPTH_PER_LEVEL := 2
const MAX_DEPTH_CAP := 8

func depth_cap() -> int:
	return mini(BASE_DEPTH_CAP + DEPTH_PER_LEVEL * level_of("depth"), MAX_DEPTH_CAP)
```

2 → 4 → 6 → 8, landing exactly on `MAX_DEPTH_CAP`, and clamped to this
release's ladder top rather than to any engine limit — the same reason
`height_cap` clamps to `MAX_HEIGHT_CAP` and not `Building.MAX_FLOORS`.

`base: 9` sits between `height` (6) and `shafts` (15). A first run digs 2
without spending anything, so the node is a widening rather than an unlock, and
it is reachable after one good run where `shafts` is not (§9).

### `MAX_FLOORS` still bounds the tower only

`Building.MAX_FLOORS = 40` continues to cap `floor_count`. Depth is capped
separately by `MAX_DEPTH_CAP`. A maxed building is 40 up and 8 down: 48 rows,
which the scrolling board handles the same way it handles 40.

### Naming: `lobby_parking` already exists and is a different thing

`Upgrades` has an id `lobby_parking`, which is **cars returning to the lobby
when idle** (`DispatchPolicy.WhenIdle.RETURN_TO_LOBBY`) — parking a car, nothing
to do with a garage.

Nothing in this feature may be named `parking` in code except the tenant kind id
itself, which is player-facing data. The identifiers are `depth`, `dig`,
`depth_cap`, `PARK_BONUS`, `entrance`.

---

## 7. The board

### The dig band

`BoardCoords` gains `footroom`, the exact mirror of `headroom`:

```gdscript
## Content BELOW the bottom floor that scrolling must reach: the dig band.
## Mirrors `headroom`, and widens the UPPER clamp for the same reason.
var footroom: float = 0.0
```

`scroll_to`'s travel becomes `content_height() + footroom - viewport_height`,
floored at 0. `BuildingView` sets it to `FLOOR_HEIGHT` while the run may still
dig, and 0 at the ceiling — the same conditional shape `headroom` uses against
`Building.MAX_FLOORS`.

The band draws at `floor_to_y(bottom_floor) + FLOOR_HEIGHT`, reads
`+ DIG  $<cost>`, and takes a tap the way the ghost band does. At the depth
ceiling it says so rather than inviting a tap that does nothing — the same
refusal the ghost band makes at the floor cap.

### Floor numbering

Basement floors display as **P1, P2, P3** counting downward, not −1, −2, −3.
The index stays signed everywhere in code and in `BoardCoords`; only
`FloorRow.set_floor`'s label differs. Two characters fit the 25-unit gutter that
`test_board_geometry` pins; a minus sign plus a digit is the same width but
reads as a subtraction.

### Scenery

A leased parking floor draws `art/floors/parking.png`, generated against the
existing style block and scale table in `brand/floor-art-prompts.md` — a flat
elevation of a garage: bays marked on the floor, a low concrete beam, a ramp
edge. An unleased one draws the existing construction shell, with no change:
`FloorScenery` already answers `VACANT` for a floor with no kind, and a dug
basement is exactly that.

### The floor panel

Works unchanged. A basement floor opens the same sheet, shows the same
satisfaction bar and class upgrade, and offers a lease picker filtered to
`Where.BASEMENT` — one entry today.

The day sparkline for an entrance kind shows *arrivals*, not generated trips.
`DaySparkline` reads `TrafficSource` rates, so an entrance kind needs its curve
derived from the arrivals it receives rather than from a `rate` array it does not
have. Simplest correct answer: an entrance kind's sparkline shows the building's
inbound curve scaled by its share, which is what the player actually wants to
know — *when is my garage busy*.

---

## 8. Save format: additive within v4

`SaveCodec.VERSION` stays **4** and no migration is written.

This is safe for a checked reason, not by assumption: the decoder already reads
optional keys as `data.get("floor_count", 1)` (`save_codec.gd:141`), so an
absent key takes a default rather than throwing. `Meta.dev_unlocked` was added
inside v4 on exactly this argument.

- **`depth`** rides in the building block: `"depth": state.building.depth`,
  decoded as `_bounded_int(data.get("depth", 0), 0, Meta.MAX_DEPTH_CAP, 0)`.
  Bounded against the *ladder top*, not `MAX_FLOORS` — a hand-written save must
  not mint a 40-deep basement.
- **The `floors` array grows downward.** It is written
  `for f in range(bottom_floor(), floor_count)` and is `total_floors()` long;
  entry `i` is floor `i - depth`. `depth` is decoded first, so the mapping is
  unambiguous.
- **A v1–v3 save decodes to depth 0**, its `floors` array starts at floor 0, and
  the mapping degenerates to the identity. Correct: it was written by a build
  that could not dig.
- **A save whose `floors` length disagrees with `floor_count + depth` is
  malformed** and takes the existing refusal path. This is a new consistency
  check and it matters: the two numbers used to be one.
- `waiting` is not persisted today and still is not, so the dense-from-bottom
  layout has no save consequence.

---

## 9. The one number that must be measured

`PARK_BONUS = 0.15` is a guess, and this spec says so rather than presenting it
as derived. It must be measured on the real sim before it ships, the way the
13-Blueprint first-run yield was.

The reason it is risky in *this* release specifically: run 1 now caps at **two
shafts** (2026-08-04), and depth 2 is available from run 1 with no tree spend.
So a first run's traffic can rise ~30% against the tightest shaft budget the
game has ever had. The failure mode is not "digging is weak" — it is "digging is
a trap a new player takes and then drowns in".

What to measure, on a well-played 10-floor run at 2 shafts:

1. Expiry rate at depth 0 vs depth 2 leased. If depth 2 more than doubles
   expiries, `PARK_BONUS` is too high or `BASE_DEPTH_CAP` should be 1.
2. Net `lifetime_earnings` at depth 0 vs depth 2. Digging must be *positive* at
   run 1's shaft budget or nobody will ever dig twice.
3. Whether the trip-length tax is perceptible at depth 2. Two floors is a small
   tax; if depth 2 is a free +30%, the brake does not engage until depths the
   tree gates anyway, and the ceiling is doing all the work.
4. Whether the garage's own satisfaction ever falls enough to move out. If it
   cannot, §4's feedback loop is decorative and the entrance should instead
   scale its share by satisfaction directly.

---

## 10. Out of scope

Named because the backlog entry bundles them and an implementer will be tempted:

- **Materials as a second currency**, mining floors, ore. The next spec.
- **Hauling / freight.** Depends on materials.
- **Basement tenant kinds beyond parking** — storage, a nightclub, the mine.
  `Where.BASEMENT` and `entrance` are the seams they will use; no second kind is
  added here.
- **The depth era ladder** — bedrock, caverns, something that objects to being
  disturbed.
- **Offline earnings**, which the backlog already excludes deliberately.

---

## 11. Testing

The suite is the specification of behaviour here, so these are requirements.

**Coordinates**

- All 13 `range(floor_count)` sites are audited, and a test at depth > 0 covers
  each one that became `range(bottom_floor(), floor_count)`. The regression is
  silent: a missed site skips the basement and reads as "parking does nothing".
- `Tenancy`, `Fitout` and `waiting` round-trip a negative floor: leased at −2,
  read back at −2, at every depth. Digging again does not move what is already
  there — the front-insertion bug this guards is invisible until you dig twice.
- `has_floor` rejects `-depth - 1` and `floor_count`.
- A car dispatched below 0 arrives; a car target clamps to
  `[bottom_floor, floor_count)` and not to `[0, floor_count)`.

**Traffic**

- The draw count per tick is independent of depth — the seed-sequence property.
- With `depth = 0` the spawner is bit-identical to today for a given seed. This
  is the test that says the feature is additive.
- A VACANT parking floor adds no arrivals; leasing it adds them. This is the
  test that makes §3's feedback loop real rather than decorative.
- Arrivals appear at leased parking floors in roughly the modelled share over a
  long run, and never below `bottom_floor`.
- An entrance kind is never chosen as a trip SOURCE, at any hour.
- `TenantCatalog` refuses an entrance kind carrying curve arrays, and refuses a
  source kind with empty ones. Both directions, because a one-directional check
  passes vacuously against the file that ships.
- `source_floor` is the tenant floor, not the parking floor.
- **A vacant lobby collapses lobby arrivals but NOT parking arrivals**, and
  `BuildingDay` reproduces the same split.

**Leasing**

- A basement floor cannot be leased a tower kind, and floor 7 cannot be leased
  `parking`. Both directions, because the picker filters and the sim must refuse
  independently.
- A garage's satisfaction falls when arrivals waiting there expire, and it moves
  out like any tenant, and its arrivals stop when it does.

**Digging**

- `depth_cap` walks 2/4/6/8 and lands exactly on `MAX_DEPTH_CAP`.
- A run may dig to `depth_cap()` and no further, and the sim refuses the
  purchase rather than the view hiding it.
- Digging yields a VACANT floor, not a leased one.
- **The live-save case**, as for shafts: a save with more depth than the current
  tree pays for keeps its basement and is simply sold no more.

**Board**

- The dig band is reachable at every depth on a building taller than the window,
  and asks for no footroom at the depth ceiling.
- A basement floor labels as `P1`, and its index is still −1.

**Save**

- `depth` survives a round trip; a save without the key decodes to 0; a save
  claiming depth 99 is bounded to `MAX_DEPTH_CAP`.
- The `floors` array round-trips basement entries in order, and a save whose
  length disagrees with `floor_count + depth` is refused.
