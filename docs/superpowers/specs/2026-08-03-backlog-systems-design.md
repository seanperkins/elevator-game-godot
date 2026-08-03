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

---

# Decisions (2026-08-03)

Every open question above, answered. Three answers changed the design rather
than just picking from it; those are marked **[revises]**.

## Terminology, first — because it was overloaded  **[revises]**

`Tenancy` uses **tenant** to mean *the business occupying a whole floor*. But an
apartment floor also has **residents** — individual people who move in and out
of it. Those are different things at different scales, and the move-in/move-out
entry silently meant both.

From here:

| Word | Means | Modelled by |
| --- | --- | --- |
| **tenant** | the floor's occupant — a kind, one per floor | `Tenancy` + `TenantKind` |
| **resident** | an individual living or working on a floor | not modelled; a source of events |
| **passenger** | anyone in a car or queue | `Passenger` |

Nothing in the code models a resident today, and probably nothing needs to. A
resident's move is an *event on a floor*, not an entity.

## S7 — Floor events **[revises: new system]**

> "I want to have some floors that need to confiscate the lift at times for
> events. This is just the first one I thought of."

This generalises two things I had filed separately. A resident moving out and a
hospital emergency are the same mechanic: **a floor's kind occasionally
generates an event that takes a car for a while.** Move-in/move-out is one
instance, not a system of its own.

| Floor kind | Event | Shape |
| --- | --- | --- |
| Apartments | a resident moves in or out | several trips, bulky, no urgency |
| Hospital | emergency | one trip, urgent, priority |
| Hotel | group check-in / luggage run | several trips, bulky |
| Restaurant | a delivery | one trip, bulky, timed |
| Office | a fit-out | long, one-way |

**One law for taking a car**, settled by the S6 answers and now shared:
`key > manual > policy`, and **all three take only an IDLE car**. `AutoDispatch`
already refuses to command a moving or boarding car — "a car in transit is
committed to the trip it was given, and taking either would read as sabotage" —
so this extends an existing rule rather than adding a second one. Riders always
reach their floor first.

Because events are driven by the floor's kind, **seizure becomes a cost you
accepted when you leased**, not weather. That connects S7 to S3 and to the kind
roster, and it gives the hospital a real downside worth pricing.

**Consequence for churn:** losing a tenant no longer costs only a re-lease fee —
it costs a car out of service while the move happens. Churn becomes an outage.

## The answers

### S1 — Loads
1. **Capacity is an integer budget.** `board()` admits anything where
   `sum(slots) <= capacity`. No adjacency, no packing pass; `ChipGrid` renders a
   wider chip and `take_boardable(floor, limit)` already has the seam.
2. **Load dwell is additive, and gets its own upgrade.** **[revises]** —
   `dwell = car.door_ticks + load.extra_ticks`. Faster Doors buys down only the
   base. A *separate* freight-speed upgrade buys down the surcharge, so freight
   dwell is its own purchasable axis instead of a side effect. It joins the
   one-shot hardware family the same way `call_direction` did.
3. **No load is patience-free — they get a long delivery window.** Reuses
   `patience_ticks`, the existing `_expire()` phase, and keeps
   `patience_fraction()` meaningful so the chip still colour-ramps. No new tick
   phase, and no permanently blocked seat.

### S2 — Places
4. **An entrance is its own object**, `{id, floor, kind}`, so one floor can have
   both a lobby door and a loading bay. `Passenger` carries an `entrance_id`
   alongside `origin_floor`.
5. **A car boards someone only if its shaft serves that entrance kind.**
   **[revises]** — so a shaft wired only to the service entrance *cannot* pick up
   lobby passengers, even standing among them. This makes the separate entrance
   object load-bearing rather than decorative: `answer_call()` gains a filter on
   the waiting passengers' entrance, not on the floor. A shaft serving both
   entrances behaves exactly as today.

### S3 — Reputation
6. **Mean, with the minimum shown in the HUD.** The mean gates leasing; the
   minimum is displayed so a neglected floor nags without locking the game.
7. **Ratchet the unlock, live for the display.** Once earned, a kind stays
   leasable — mirroring `Fitout`, where a purchased class tier never lapses.
8. **Reputation never evicts.** Reputation gates who *arrives*; satisfaction
   decides who *stays*. Two numbers, two jobs, and the existing move-out
   countdown remains the only eviction path.

### S4 — The down axis
9. **One budget, split.** The floor cap is a total — dig a basement, lose a tower
   floor. Nearly free now that the purchasable cap (20) is already separate from
   the structural one (40), and prestige raising the cap then funds both
   directions at once.
10. **A shaft spans both axes, and reaching down is a purchase.** One column
    renders the whole range, so the balance cost — a longer round trip on every
    sweep — lands as something the player opted into rather than a silent tax.
11. **Ore is a real load.** Slots 4, long delivery window, no urgency. The mine
    becomes a permanent freight source, which is exactly the load S1's weigher
    and S2's service entrance exist to handle.

### S5 — Prestige
12. **A Structure node bought with Blueprints raises the cap**, not the demolish
    itself. The base design already defines that branch as "starting rows,
    starting shafts, era unlocks"; a max-floors node is that branch's job. And
    because 40 floors is unservable at base mechanicals, the player must buy
    *both* Structure and Mechanical to actually go taller.
13. **Run one hard-caps at 10 floors — shipping in the same release as
    prestige.** A 10-floor building needs exactly one car, so run one teaches
    floors, tenants and manual dispatch with shafts held back as a second-run
    reveal. **This must not ship early:** a 1.3 h wall with nothing behind it
    would be strictly worse than today's 6.5 h one.
14. **Only structure and mechanicals persist.** Tenant kinds reset, so every run
    re-earns its roster and S3 stays a live system rather than being exhausted
    after a few resets.

### S6 — Deviant floors
15. **The creature floor generates its own hall calls.** It is a `TrafficSource`
    with a rate whose delivery pays nothing and costs reputation — reusing the
    spawner, the tenancy slot and the chip rendering unchanged. It also lands the
    design goal: Answer Calls will carry people there and a sweep stops
    everywhere, so **automation becomes something you must aim**.
16. **A seized car finishes its current trip first** (see S7's shared law).
17. **Seizures are tied to tenant kind**, not random — see S7.
18. **A deliberate feed costs reputation only.** It bypasses
    `Economy.note_expiry()` (combo break, stairs penalty) and
    `Tenancy.note_expiry()` (floor satisfaction), both of which exist to punish
    *neglect*. "Lost through neglect" and "spent on purpose" stay genuinely
    different events.

### Balance
19. **Target 8 trips/min at the starting building, fare ~$0.77** (4x riders,
    1/4 fare). One car supplies 11.4/min at 6 floors, so the opening is busy but
    servable, and it leaves ~3x headroom before the Bernoulli ceiling at ~12x.
    The unit of play moves from the trip to throughput, which is what makes
    capacity and dwell matter.

### Tenants who will not mix
20. **Checked live — neighbours can sour after the fact.** **[revises my
    recommendation]** I argued for lease-time only, on the grounds that a
    retroactive penalty is a mystery. Overruled, and the requirement that comes
    with it is explicit: **the board must show, per floor, why satisfaction is
    falling.** Without that surface this is indistinguishable from a bug in the
    satisfaction system — the same trap the ghost-floor work hit. That surface is
    now a prerequisite of this entry, not a nicety.

## What this changes about the order

S7 absorbs move-in/move-out out of S1 and the actor half of S6, and it depends
only on S1 (loads) plus the kind roster. That makes it cheaper than S6 and
worth doing earlier:

1. **S5 Prestige** — with the 10-floor first run
2. **S1 Loads** — including the freight-speed upgrade
3. **S3 Reputation**
4. **S7 Floor events** — needs S1; makes churn an outage
5. **S2 Places**
6. UI items
7. **S4 Down axis** — coordinates early regardless
8. **S6 Deviant floors** — needs S1 and S3

The one prerequisite now on the critical path that was not before: **a per-floor
"why is this falling?" surface**, required by decision 20 and reusable by S6's
reputation damage and S7's outages.
