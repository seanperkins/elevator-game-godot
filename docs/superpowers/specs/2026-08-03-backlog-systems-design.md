# The backlog as six systems

**Status:** design pass only. Nothing here is agreed or built.

Fourteen live backlog items. Designed individually they are fourteen features;
designed as systems they are **six**, and three of them collapse several
entries into a single primitive. This document is the grouping, the dependency
order, and the decisions each system still needs.

Two entries are already built and are excluded: *Tenant kinds with their own
traffic patterns* (shipped as Spec A) and *Show the time of day* (shipped
2026-08-03). *A second currency* is excluded as explicitly superseded by S3.

---

## The map

| System | Absorbs | Cost |
| --- | --- | --- |
| **S1 Loads** | freight, hospital gurneys, hotel luggage, move-in/move-out, knights, ore haulage | large, high leverage |
| **S2 Places** | service entrance, premium dedicated shaft, zoning | medium |
| **S3 Reputation** | reputation gate, second currency (superseded), premium tenant requirements | small |
| **S4 The down axis** | parking, mining, monsters, era ladder downward | very large, structural |
| **S5 Prestige** | the floor-cap ladder, the 20-vs-40 gap | medium |
| **S6 Deviant floors** | the floor that eats people, haunted, research, emergency personnel | medium, needs S1 + S3 |

Plus two that are UI-only and depend on nothing: **destination-entry panel** and
**build-your-own dispatch**. And one pure balance question: **fare vs
ridership**.

---

## S1 — Loads

**The primitive.** A thing in a car is currently a `Passenger`: one seat, one
fare, one patience, instant unload. Generalise it to a **load** with

- `slots: int` — how much of the car it occupies (1 for a person)
- `dwell_ticks: int` — how long its stop takes (0 = the car's normal dwell)
- `patience_ticks: int` — 0 or absent meaning "does not expire"

That single change is what five backlog entries are all asking for:

| Entry | slots | dwell | patience |
| --- | --- | --- | --- |
| Hotel luggage | 2 | normal | normal |
| Hospital gurney + 2 responders | 4 | long | short (urgent) |
| Freight / pallet | 2–4 | long | delivery window, or none |
| Mining ore (S4) | 2–4 | long | none |
| Move-in / move-out | 4, repeated | long | none |
| Knights (S6) | 4 | long | none |

**What it touches.**
- `ElevatorCar.board()` stops counting heads and sums slots; `capacity` becomes
  slots, not people. `Upgrades.CAPACITY_BASE` (4) stays 4 — one gurney *is* the
  whole starting car, which is the point.
- **Dwell becomes load-dependent.** `door_ticks` is a fixed constant today and
  `_deliver()` empties the car instantly. This is the deepest change: it touches
  the move/doors phase of a tick order that is player-visible and pinned by
  tests.
- `ChipGrid` must draw a 2- or 4-slot load as one wide chip, or the seat rack
  stops telling the truth.
- **Load Weighing finally has a job.** Today it only prevents a wasted stop.
  With slots it answers "can what is waiting even fit", which a headcount
  cannot express.

**Why it is first among the big ones.** It is the only system that other
systems *need*: S4's ore and S6's knights are both loads. Building it once
retires five entries.

**Open questions.**
1. Does a load occupy contiguous slots, or is capacity a pure integer budget?
   Contiguous is realistic and much harder to render; a budget is simpler and
   probably indistinguishable in play.
2. Does `doors` (Faster Doors) buy down the *base* dwell only, or load dwell
   too? It currently buys down a constant; making load dwell immune keeps
   freight slow forever, which may be the intent.
3. Does a no-patience load block a seat indefinitely if never delivered? If so
   it is a trap; if it expires silently it is not really patience-free.

---

## S2 — Places

**The primitive.** An origin gains a **kind**. Today a passenger spawns on a
floor and wants another floor; there is exactly one way into the building.
Introduce named entrances — lobby, service entrance, and later the basement —
and `DispatchPolicy` gains a block: *which entrances this shaft serves*.

**Why the decomposition already fits.** `DispatchPolicy.Source` is a bitmask
(`EVERY_FLOOR=1, HALL_CALLS=2, CAR_CALLS=4`) and the presets are just
combinations. An entrance filter is another member of that set, which is a good
sign the existing model holds rather than needing replacement.

**What it unlocks.**
- **Service entrance**: freight stops appearing in the lobby rush. This is what
  makes zoning mean *place* rather than *time* — every policy today is about
  when, none about where.
- **Premium dedicated shaft**: a "serve only these floors" block. Per-tenant
  fares already exist (`TenantKind.base_fare` plus the class multiplier), so the
  prerequisite the backlog noted is **already satisfied**.

**Open questions.**
1. Is an entrance a property of a floor, or a separate object? A floor with two
   doors is more realistic; an entrance-as-floor is far cheaper and probably
   enough.
2. Does a shaft that serves no entrance still answer hall calls on the floors it
   passes? If not, zoning becomes very punishing very fast.

---

## S3 — Reputation

**The primitive.** A building-wide aggregate of per-floor satisfaction, used as
a **gate, not a currency**. A currency has to be spent, and spending
satisfaction means every purchase nudges a tenant toward leaving — strange goods
to sell. A gate never spends it, so satisfaction keeps its retention job and
gains a second: a well-run building attracts better tenants.

**Shape.** `Tenancy.reputation() -> float`, and `TenantKind` gains
`requires_reputation`. Leasing is gated the same way `requires_class` already
gates it, so the tenant picker greys out what will not come — one more
requirement on a path that already exists.

**The loop.** Serve people well → reputation rises → better tenants unlock →
more traffic → harder to serve → reputation at risk. Self-limiting rather than
compounding, which is exactly the failure the goodwill idea had, and it needs no
cap.

**Open questions.**
1. **Mean or minimum?** A mean lets one excellent floor hide a neglected one; a
   minimum makes every floor matter and is much harsher. *Suggested: mean, with
   the minimum shown in the HUD so neglect is visible without being fatal.*
2. **Ratchet or live?** If reputation can fall, unlocked tenants can become
   unavailable mid-game — either good pressure or a trap. *Suggested: ratchet
   the unlock, live for the display, so you cannot lose access to something you
   already earned.*
3. Does a tenant leave when reputation falls below what they required? Losing
   tenants to a building-wide average would be brutal and hard to read.
   *Suggested: no. Their own satisfaction already does that job.*

---

## S4 — The down axis

**The idea.** Floors below the lobby: parking first, then mining, then something
that objects to being disturbed. Up is **service** (people, fares, patience);
down is **extraction** (depth costs time, buys material).

**Why it is worth the cost.** It gives the game a second currency with an honest
source — materials come out of the ground rather than being conjured from
satisfaction — and it makes freight load-bearing rather than flavour. A mining
floor is a permanent freight source with no patience and real bulk, which is
exactly the load S1, the weigher and S2's service entrance all exist to handle.

### The structural conflict, which is the real work

**The board never scrolls vertically, and that is load-bearing.** Dispatch is an
absolute drag onto a floor's band, so "any floor is one short drag away" is the
property the entire input model rests on. Forty up plus twenty down is sixty
bands on a board that already shows forty at 16pt.

Three ways out:

1. **One budget, split.** The floor cap becomes a total — dig a basement, lose a
   tower floor. Every rule stays intact and depth becomes a genuine sacrifice.
   **Recommended.** It is also nearly free now that the purchasable cap (20) is
   already separate from the structural one (40).
2. **Two boards, one switch.** Above and below as separate surfaces. Costs a
   navigation layer the design has refused, and cross-boundary dispatch becomes
   invisible.
3. **Shrink the band.** Already at 16pt. Not available.

**Coordinates.** `BoardCoords` maps bottom-up from floor 0 over `[0, N)`. Signed
floors mean an origin offset and a `y_to_floor` that returns negatives.
`DispatchPolicy.LOBBY = 0` stops meaning "the bottom". The one-transform rule is
what makes this survivable — one definition, four consumers — **but it is far
cheaper at six floors than at forty.** If the down axis is wanted at all, do the
coordinate work early, before the board grows.

**Open questions.**
1. Does a shaft span both axes, or do basements need their own? Spanning is
   simpler to render and much harder to balance.
2. Is ore a load (S1) or a resource counter? A counter is cheap and skips the
   whole point; a load makes the elevator matter, which is the reason to build
   it.

---

## S5 — Prestige and the floor-cap ladder

**The idea (yours).** Each demolish raises how tall you may build. The first run
caps at 10 floors.

**It already has room reserved.** The cost-curve work deliberately split the
**purchasable** cap (20 floors, `floor.max_level = 14`) from the **structural**
one (`Building.MAX_FLOORS = 40`). That gap is exactly where this ladder lives —
prestige raises `max_level` toward 40 rather than inventing a new mechanism.

**Why a 10-floor first run is right.** A 10-floor building needs exactly **one
car** — demand 6.5/min against a single car's 6.9/min supply. So run one teaches
floors, tenants and manual dispatch with no shafts at all, and **shafts become a
second-run unlock**. That is a genuinely clean tutorial that costs nothing to
build.

**The constraint that gives Blueprints a job.** 40 floors is *not* serviceable at
base mechanicals: 8 cars supply 13.7 trips/min against 25.8 demand. Fully
upgraded — speed L12, 4-tick doors, 12 seats — they supply 174/min. So height
across runs **requires** the Mechanical branch. Prestige stops being a flat
multiplier and becomes the thing that makes the next cap survivable.

| run | cap | cars needed | why it ends |
| --- | --- | --- | --- |
| 1 | 10 | 1 | cap reached; no shafts yet |
| 2 | 15 | 2 | cap |
| 3 | 20 | 4 | cap |
| 4+ | 25 → 40 | 6–8 + mechanicals | cap, gated on Mechanical nodes |

**Open questions.**
1. Does the cap rise per demolish, or per Structure node bought with Blueprints?
   Per-node is more player-controlled and fits the existing tech-tree design;
   per-demolish is simpler and guarantees progress.
2. Does run one *really* cap at 10, or does it cap at 20 with 10 as a soft
   target? Shipping a 1.3 h hard wall before prestige exists would be worse than
   today's 6.5 h one — **so this must not ship before prestige does.**
3. Do Blueprints persist floor *kinds* unlocked, or only structure? Persisting
   kinds makes later runs feel richer; persisting only structure keeps each run
   a fresh tenancy puzzle.

---

## S6 — Deviant floors

**The primitive.** Two, actually, and they are worth separating:

**(a) A floor state that is neither tenant nor vacancy.** The creature floor, the
haunted floor, the research floor. `Tenancy` has exactly two states today; this
is a third, and `GameState._deliver()` — which pays a fare and raises
satisfaction for every arrival — needs a branch where delivery pays nothing and
*damages* reputation instead. That is S3's first real pressure.

**(b) An actor that is not a fare-paying passenger.** Emergency personnel
commandeering a car; a ghost or experiment that escapes. This is the first thing
in the game that is neither the player nor a policy the player bought — the
building acting *on* them.

**Why (b) has a slot already.** `AutoDispatch` only commands IDLE cars and a
manual dispatch always wins, so a priority order exists. A key simply inserts
above it: **key > manual > policy**.

**What makes it fun rather than a tax.** An escape or a seizure that only costs
money is a random tax with no decision in it. It earns its place only if the
player can respond — catch it, contain it, route around it — which means it must
change what the elevator should do next. The knights are the good version of
this: clearing the creature is a *job*, using S1's load machinery for a fight.

**Open questions.**
1. Does the creature floor generate hall calls, or must the player carry victims
   to it? The first is sinister and passive; the second makes the player
   complicit, which is darker and more interesting.
2. A commandeered car — does it keep serving its riders or dump them? And is it
   triggered randomly, or by tenant kind (a hospital or clinic floor)? Tied to
   tenant kind it becomes a reason to think about *who you lease to*, which
   connects it to S3.
3. The no-fail guarantee and the stairs penalty both assume losing a passenger
   is always bad. Here it is bought deliberately, so the guard must distinguish
   "lost through neglect" from "spent on purpose".

---

## The two UI-only items

Neither needs a system; both are **exposing what the player already owns**.

**Build-your-own dispatch.** `DispatchPolicy` is already four orthogonal blocks
and the presets are already just combinations. Missing: the screen, and
persistence — `SaveCodec` stores a preset id today, so a custom policy needs its
blocks saved instead. That is a v4 migration, and the v3 one is now a worked
example.

**Destination-entry panel.** The reader half of the `call_direction` upgrade that
shipped tonight. Note it changes *hall rendering*, not just policy: chips would
show a floor number rather than an arrow, which is a width change the 176-unit
strip has to absorb — and `FloorRow.CALL_UNKNOWN` already proves the chip label
is a free variable.

---

## The one balance question

**Lower the fare, raise the ridership.** Moves the unit of play from the trip to
throughput, which is what would make capacity, dwell and dispatch quality matter
— and it is the other honest answer to flat per-floor income.

**The constraint that bounds it:** the spawner runs one Bernoulli trial per tick
and emits at most one passenger, so the summed rate must stay under
`TICKS_PER_SIM_MINUTE` (600). Today's headroom is `MAX_FLOORS (40) x 1.2` = 48.
A rate rise past roughly **12x** starts clipping silently at p = 1. That is the
ceiling, and it is not far away.

**Open question.** How far? A 10x rider count at a 10x lower fare is a different
game, not a tuned one. This wants a target trips/minute chosen first and the
fare derived from it — not the other way round.

---

## Suggested order

1. **S5 Prestige** — closes the run loop, uses a gap that already exists, and is
   the only thing that makes the current 20-floor cap read as completion.
2. **S1 Loads** — the biggest unlock; retires five entries.
3. **S3 Reputation** — small, and S6 needs it.
4. **S2 Places** — zoning; makes S1's freight worth separating.
5. **UI items** — cheap, independent, good filler between the big ones.
6. **S4 Down axis** — most expensive. *But do its coordinate work early*,
   before the board grows, even if the content comes much later.
7. **S6 Deviant floors** — last, because it needs S1 and S3 to exist first.

**The one sequencing rule that matters:** S4's signed-coordinate change is
cheaper at six floors than at forty, and S5 makes the building taller. If both
are wanted, the coordinate work comes first.
