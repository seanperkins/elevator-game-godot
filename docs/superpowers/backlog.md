# Backlog

Ideas raised during play-testing that are not built. Each records the design
question it opens, because most of them are not "add a feature" — they touch
something the current code assumes.

---

## Freight and non-human loads

**Idea.** Cargo that takes more space and weighs more than a person.

**Why it matters beyond flavour.** It is what makes **Load Weighing** worth
buying. Today capacity is a headcount and a full car is `riders >= capacity`, so
the weigher only ever prevents a wasted stop. With loads of differing size, the
question becomes *what* fits, and a car half-full of freight is a genuinely
different dispatch problem.

**What it touches.**
- `Passenger` gains a size (car units) and possibly a weight.
- `ElevatorCar.board()` stops counting heads and starts summing units; capacity
  becomes units, not people.
- `ChipGrid` draws one cell per passenger in the hall; a car lays its riders out
  by rank via `CarRack` — freight needs to occupy more than one cell, or the pips
  stop telling the truth.
- The load sensor gets a real job: refuse a hall call when the *remaining units*
  cannot take the smallest waiting load.

**Open question.** Does freight expire like a person's patience? A pallet has no
patience, but a delivery window might.

**Sizes, dwell and the premium (added 2026-08-03).** Three refinements that
sharpen this from "bigger passenger" into its own mechanic:

- **Discrete sizes, not a continuum.** A load takes **2 or 4 slots** against the
  base capacity of 4 (`Upgrades.CAPACITY_BASE`). At 4 slots one load *is* the
  whole starting car, which is the interesting case: the first freight job
  forces a dedicated trip, and `capacity` stops being an abstract number.
- **Unloading takes time.** This is the part with real teeth. Dwell is a fixed
  constant today — `ElevatorCar.door_ticks` (20) is the WHOLE stop regardless of
  how many people get on or off, and `deliver()` empties the car instantly. Make
  freight dwell longer than a person and **dwell becomes load-dependent for the
  first time**, which turns every stop into a cost you can reason about. Note
  this cuts against `doors` (Faster Doors): that upgrade currently buys down a
  constant, and would start buying down something variable.
- **It pays more.** The premium is what makes a slow, bulky load worth taking
  instead of four fares. That trade — one big slow payment against four small
  fast ones — is the actual decision the mechanic exists to create, and it only
  works if the numbers are set against the delivery *rate*, not the fare.

**Sequencing.** The dwell change is the risky one: it touches the tick order's
move/doors phase, which is player-visible and pinned by tests. Sizes and the
premium can land first and are testable on their own.

---

## Back / service entrance

**Idea.** A second entrance so freight does not appear in the lobby rush.

**Why it matters.** It is the first thing that makes a *zoning* policy
meaningful: "this shaft serves the service entrance, that one serves the lobby".
Without a second source, every policy is about time; with one, policies become
about place.

**What it touches.** Passengers currently spawn on a floor and want another
floor. A named entrance means an origin has a *kind*, and `DispatchPolicy` gains
a block: which entrances a shaft serves. That fits the existing block model —
it is another `Source` — which is a good sign the decomposition holds.

---

## Building downward: parking, then mining, then whatever is down there

**Idea.** Floors below the lobby. The first few are parking; keep digging and it
becomes mining; keep going and there is something alive down there.

**This is a second growth axis, not a feature.** Up and down would have
different economies, which is what makes it worth doing rather than just more
floors:

- **Up** is *service*. People, fares, patience, tenant mix. You are paid for
  moving somebody who chose to be there.
- **Down** is *extraction*. Depth costs time and buys material. Nobody down
  there is in a hurry, but what comes up is heavy.

That split gives the game a second currency with an honest source — the thing
the reputation-gate entry is reaching for. Materials come out of the ground
rather than being conjured from satisfaction, and they buy the structural things
money currently buys, which frees fares to buy service.

**It also makes freight load-bearing rather than flavour.** Ore has to be
hauled. A mining floor is a permanent freight source with no patience and real
bulk, which is exactly the load the weigher, the capacity upgrade and the
service entrance all exist to handle. Down-axis content would make three
backlog items pay off at once.

**Monsters are the down-axis era ladder.** The design spec already has an era
ladder going up — Walk-Up to Orbital Tether — where each era inflates what a row
*means*. A downward ladder mirrors it: parking, storage, bedrock, caverns,
something that objects to being disturbed. Same structure, opposite direction,
and it reuses the era machinery rather than inventing a parallel one.

### The structural conflict, which is the real work

**The board never scrolls vertically, and that is load-bearing.** §3.5 rejected
vertical scrolling explicitly: dispatch is an absolute drag onto a floor's band,
so a scrolled board can only dispatch to what is on screen, and "any floor is one
short drag away" is the property the whole input model rests on.

Two-directional growth breaks that. Forty up and twenty down is sixty rows on a
board that fits forty at 29.6 units — already 16pt, already the reason the
crowd-bar tier exists.

Three ways out, none free:

1. **One budget, split.** The 40-row cap becomes a total: dig a basement and you
   lose a tower floor. Keeps every rule intact and makes depth a genuine
   sacrifice. Cheapest, and probably the best first answer.
2. **Two boards, one switch.** Above ground and below ground as separate
   surfaces, each obeying the no-scroll rule, with shafts that span both. Costs
   a navigation layer the design has so far refused, and a dispatch across the
   boundary becomes invisible.
3. **Shrink the row.** More rows on the same board. Already at 16pt; this is not
   available.

**Coordinates.** `BoardCoords` maps bottom-up from floor 0 over `[0, N)`. Signed
floors mean an origin offset and a `y_to_floor` that returns negatives. The
one-transform rule is what makes this survivable — there is a single definition
to change and four consumers that follow — but it is still much cheaper while N
is small. `DispatchPolicy.LOBBY = 0` stops meaning "the bottom", and
`is_spring_trip` has to decide whether the launch starts at the lobby or the
lowest floor.

**Ghost bands.** There is a "+ BUILD FLOOR" band above the top floor. Digging
needs its own affordance below the bottom one, and the two cannot share.

**Recommendation.** If this is wanted at all, do the coordinate work *before* the
era ladder and before the board grows. Retrofitting a signed origin through four
consumers is exactly the change the one-transform rule was written to survive,
but surviving it is still cheaper at six floors than at forty.

---

## Total satisfaction as a reputation gate

**Idea.** The building's overall satisfaction gates which tenants will move in.

**This is a better answer than spending it.** A currency has to be *spent*, and
spending satisfaction means every purchase nudges a tenant toward leaving —
strange goods to sell. A gate never spends it, so satisfaction keeps its
retention job and gains a second one: a well-run building attracts better
tenants, a badly-run one gets whoever will take it.

**Why it fits what already exists.** Satisfaction is per-row and already
aggregated for the no-fail guard (`tenanted_count`). A building-wide mean is the
same shape of number. And it composes exactly with tenant kinds: a premium
tenant is one with a reputation requirement, better traffic, and probably a
harder pattern to serve.

**The loop it makes.** Serve people well → reputation rises → better tenants
unlock → more traffic → harder to serve → reputation is at risk again. That is
self-limiting rather than compounding, which is the opposite of the problem the
goodwill idea had, and it needs no cap.

**Open questions.**
- Mean or minimum? A mean lets one excellent floor hide a neglected one. A
  minimum makes every floor matter and is much harsher.
- Does a tenant leave if reputation falls below what they required, or only if
  *their own* satisfaction drops? Losing tenants to a building-wide average
  would be brutal and hard to read.
- Ratchet or live? If reputation can fall, unlocked tenants can become
  unavailable mid-game, which is either good pressure or a trap.

---

## A second currency (superseded by the gate above, kept for the reasoning)

**Idea.** Satisfaction as a spendable currency, unlocking elevator music and
other comforts.

**The conflict to resolve first.** Satisfaction already exists and already has a
job. It is a per-row 0–1 value that decides whether a tenant **stays**, and since
rent was removed and traffic tied to tenants, losing a tenant means losing that
floor's fares. So satisfaction is already an income lever — an indirect, delayed,
all-or-nothing one.

Spending that same number would mean every purchase edges a tenant toward
leaving, which is a strange thing to sell.

**Suggested split.**
- **Satisfaction** stays a per-row *state*: it decides who stays.
- A second currency — *goodwill*, say — **accrues from** satisfaction, the way
  rent used to. High satisfaction earns goodwill per minute; spending goodwill
  does not lower satisfaction.

That gives the new currency its own source without touching the tenancy loop,
and gives satisfaction a second, continuous reason to matter. At the moment it
does nothing at all until a tenant is nearly gone, which makes it easy to ignore
right up until it is expensive.

**What it would buy.** Comforts rather than throughput — music, better lighting,
lobby plants — so the two currencies do not compete for the same purchases.
Comforts could feed back into satisfaction, but note the loop: satisfaction earns
goodwill, goodwill buys comfort, comfort raises satisfaction. That compounds, and
per the design spec's rule about uncapped compounding, it needs a cap decided up
front.

---

## Tenant kinds with their own traffic patterns

**Idea.** An office floor and a residential floor generate different traffic at
different hours. The player leases for a mix they can actually serve.

**Why this is the strongest idea in this list.** Income is now traffic, and
traffic now comes from tenants — so tenant *choice* becomes the first real
strategic decision on the board, and `relet` stops being "restore what was
there" and becomes "decide what moves in".

**It also produces the real elevator problem for free.** Office traffic in the
morning is **inbound** — everyone goes lobby-to-floor — and in the evening it
reverses. Residential is the mirror. Retail peaks midday and is interfloor.
Those are precisely the up-peak / down-peak / interfloor regimes real elevator
engineering is organised around, and they arrive as a *consequence* of tenant
mix rather than as a mechanic bolted on. A tower of nothing but offices has a
brutal 8am spike; a mixed one is smoother but never quiet. That is a genuine
optimisation with no dominant answer.

**What it touches.**
- `Tenancy` gains a kind per row, and the save has to carry it.
- `TrafficSpawner` currently rolls ONE Bernoulli trial per tick against a single
  building-wide curve. Per-kind curves mean either a trial per occupied row, or
  one trial against the summed rate and then a weighted pick of which row it
  came from — the latter keeps the cost independent of building height, which
  matters at forty floors.
- Origin and destination are currently uniform random. Directional flow is the
  whole point, so a kind needs to state where its traffic *goes*, not just how
  much there is.
- The re-lease confirm becomes a tenant picker, which is a real UI, not a
  relabel.

**Watch for.** The no-fail guarantee is currently "free re-lease below two
tenants". If tenants have prices, that guard has to survive: there must always
be something the player can afford, or the fail state comes back through the
tenant menu.

---

## Tenants who will not mix

**Idea.** Some tenant kinds refuse to share a building — or a neighbourhood of
floors — with others.

**Why it is more than flavour.** It turns leasing from a per-floor choice into a
*layout* problem. Without it, the optimal building is "whatever pays most on
every floor" and there is one right answer. With it, a high-paying tenant can
cost you the two floors either side of it, and the question becomes what a
floor is worth *given its neighbours*.

**What it touches.** Only the leasing decision, if the rule is checked at
lease time — `Tenancy` gains a compatibility check and the tenant picker greys
out what will not fit. It gets much harder if an existing tenant can become
unhappy because of somebody who moved in later, because then the player can be
punished for a choice made three floors away and needs to be told why.

**Recommendation.** Check at lease time only, at least at first. A refusal the
player can see before committing is a puzzle; a penalty applied afterwards is a
mystery.

---

## Premium tenants worth a dedicated shaft

**Idea.** A tenant whose fares are high enough that devoting a whole shaft to
their floor pays.

**Why it fits.** It is the reason zoning exists in real buildings, and it gives
the shaft-count decision a second dimension: not just "can I serve everyone"
but "is this floor worth a car of its own". It also gives `DispatchPolicy` an
obvious new block — *serve only these floors* — which the existing decomposition
already has a slot for, since sources are a set.

**What it needs first.** Per-tenant fares. `base_fare` is currently one number
on the spawner for the whole building, so fares are uniform; a tenant kind has
to be able to carry its own.

---

## Move-in and move-out as elevator jobs

**Idea.** A tenant arriving or leaving occupies a car for a long time and blocks
other riders.

**Why it fits.** It gives churn a cost beyond the re-lease fee: losing a tenant
does not just cost $40, it costs a car out of service while the move happens.
That sharpens satisfaction management considerably — right now a lost tenant is
an inconvenience, and this makes it an outage.

**What it touches.** It is the same machinery as freight: a load that occupies
more than one unit of car and takes several trips. If freight lands first, a
move is freight with a schedule attached. Worth building them together rather
than twice.

**Open question.** Is a move something the player dispatches deliberately, or a
background job that seizes a car? The first is a decision, the second is a
disruption to route around. The second is more interesting and much more
annoying; it probably wants a warning first.

---

## The floor that eats people

**Idea.** A floor where a creature lives. Passengers delivered there are eaten.
Feed it enough and something unlocks. Alternatively — or afterwards — you send
knights or agents down to clear it out.

**Why it is more than a joke.** It inverts the game's goal on exactly one floor.
Everywhere else a delivered passenger is income and a lost one is a penalty;
here delivery *is* the loss, and the loss is the currency. That makes it a
genuine decision rather than a hazard to route around: the player chooses to
feed it, and pays in the only resource the game has been teaching them to
protect.

It also makes the dispatch policies suddenly dangerous. "Answer calls" will
happily carry people to a floor that eats them, and a sweep will stop there
because it stops everywhere. Automation becomes something you have to *aim*,
which is a real cost for a purchase that currently has none.

**The knights are the better half.** Feeding is passive; clearing it out is a
job the elevator has to do — carrying something heavy, slow and one-way to a
specific floor. That is the freight machinery and the move-in machinery, used
for a fight. It also gives the down-axis a verb: you do not only dig toward the
creature, you have to ship an answer to it.

**What it touches.**
- A floor gains a kind that is neither tenant nor vacancy — a third state the
  tenancy model does not have.
- `GameState._deliver` currently pays a fare and raises satisfaction for every
  arrival. An eaten passenger does neither, and probably damages the building's
  reputation instead, which is the reputation gate's first real pressure.
- The stairs penalty and the no-fail guarantee both assume losing a passenger is
  always bad. Here it is bought on purpose, so the guard has to distinguish
  "lost through neglect" from "spent deliberately".

**Open question.** Does the creature floor generate hall calls — people who want
to go there — or does the player have to carry victims to it? The first is
sinister and passive; the second makes the player unambiguously complicit, which
is more interesting and much darker.

---

## Build-your-own dispatch algorithm

**Idea.** A screen where players assemble a policy from the blocks they own.

**Already prepared for.** `DispatchPolicy` is four orthogonal blocks — where to
look, how to choose, what to do when idle, what to do when full — and the named
presets are just combinations. Each hardware purchase unlocks a block rather than
a finished behaviour, so this screen is *exposing what a player already owns*,
not a new system.

**What is missing.** Only the UI, plus persistence of a custom policy (the codec
saves a preset id today, so a custom policy needs its blocks saved instead).

---

## Destination-entry panel

**Idea.** The lobby kiosk that reveals where waiting passengers are going before
they board.

**Where it fits.** Waiting passengers currently show a drawn call arrow (up/down)
because that is all a hall button knows. This is the hardware that changes what
the player can plan, and `PersonSprite` renders it today as a triangle drawn in
`_draw()` rather than a font glyph.

**Note.** It also changes the *hall* rendering, not just the policy: the waiting
badge would need to show a floor rather than an arrow, which is a width change
the strip has to absorb. (The *riding* badge already carries two digits — that
was the point of the car resize.)

---

## Emergency personnel commandeer a car

**Idea.** Firefighters, paramedics and the like carry elevator keys. They take
control of a car and use it how *they* want — the player does not get a say, and
does not get it back until they are done.

**Why it fits.** Everything that currently commands a car is either the player
(`GameState.dispatch`) or a policy the player bought (`AutoDispatch`). This is
the first actor that is **neither** — the building acting on the player rather
than for them. That is a genuinely new pressure, and it costs nothing in new
systems: a commandeered car is a car temporarily removed from the pool, which
the dispatch problem already knows how to be starved by.

**What it touches.**
- `AutoDispatch` only ever commands an IDLE car, and a manual dispatch already
  wins over the sweep — so a third, *higher* priority already has a shape to
  slot into. The docstring's rule that "a manual dispatch always wins" becomes
  "a key wins over everything".
- `ElevatorCar` needs a state (or an owner) meaning "not yours", so the board
  cannot dispatch it and the policy will not pick it up.
- The view has to *say so*. A car that ignores taps with no explanation reads as
  a bug — this is the same trap the ghost-floor work hit.

**Open questions.** Does a commandeered car keep serving its riders, or dump
them? Is it triggered by an event (a fire on a floor), by tenant kind (a
hospital or clinic floor), or randomly? Random is cheapest and the least
interesting; tied to a tenant kind it becomes a reason to think about *who* you
lease to, which connects it to Spec A.

**The risk to weigh:** taking control away from the player is only fun if it is
legible and bounded. An unexplained, unbounded seizure is indistinguishable from
the game being broken.

---

## Lower the fare, raise the ridership

**Idea.** Cut the money per rider and increase how many riders there are, so the
same income arrives as many small payments instead of few large ones.

**Why it matters.** It changes what the player is optimising. At a base fare of
$3.00 and roughly 0.64 trips/min per apartment floor, individual trips are
*visible* — you can watch a single fare arrive. Push the fare down and the count
up and the unit of play stops being the trip and becomes **throughput**, which
is what makes capacity, dwell time and dispatch quality matter. A car that
carries 4 instead of 3 is currently a rounding error; under high ridership it is
the whole game.

**What it touches.**
- `base_fare` and the `rate` arrays in `data/tenants.json` — both, in opposite
  directions, holding income roughly constant.
- The saturation guard: `TrafficSpawner` runs **one Bernoulli trial per tick**
  and emits at most one passenger, so the summed rate must stay under
  `SimClock.TICKS_PER_SIM_MINUTE` (600). `TenantCatalog.largest_bucket()` and its
  test pin this. Today's headroom is large — `MAX_ROWS (40) x 1.2` = 48 — but
  this idea spends exactly that headroom, and a rate rise past ~15x would start
  clipping silently at p = 1.
- Queue rendering: `FloorRow.MAX_INDIVIDUALS` is 12 and `ChipGrid` draws one
  square each. Many more waiting people means the chip grid stops being able to
  show them, and the count beside them carries more of the load.

**Why it is worth doing (2026-08-03).** It is one of the two honest answers to
the live balance problem: floors cost `1.45^n` while each adds a flat
$1.93/min, so payback runs 135 min at floor 7 and 697 min at floor 12 and the
building stalls there. More riders per floor makes per-floor income *scale* with
the upgrades you buy instead of being a constant, which attacks the stall from
the income side rather than by flattening the cost curve.

**Open question.** How far? A 10x rider count at a 10x lower fare is a different
game, not a tuned one — the arithmetic holds but the feel does not survive it.
This wants a target trips/minute chosen first, then the fare derived from it.

---

## The fare is what the rider thought of the trip (2026-08-03)

**Idea (yours).** A delivered fare scales with **that rider's remaining
patience** at the moment the doors open, not with a global multiplier. Red pays
$0, yellow $1, green $3 — the same colour ramp `Passenger.patience_fraction()`
already drives on the chip.

**Why it is more than a tuning knob.** Today service quality reaches income by
two blunt routes: `Economy.note_expiry` charges a penalty for the people you
*lost*, and `combo` multiplies everything for as long as you lose nobody. Both
are all-or-nothing at the boundary — a rider delivered with 1% patience left
pays exactly what one delivered instantly pays. This makes the *margin* pay,
which is the thing the player is actually steering: it rewards shortening waits
rather than merely avoiding expiries, and it gives a partial credit for the
near-miss that currently reads as a full success.

**It is also a candidate answer to the prestige-variance problem.** Measured
while building S5, `combo` multiplies `lifetime_earnings` — the exact field the
Blueprint conversion consumes — by between **2.5× and 7.6×** depending on how
well the shafts are worked, and the square root only partly compresses that.
A per-rider fare puts service quality into the fare itself, which is a smoother
and more legible signal than a global streak multiplier that resets to 1.0 on a
single expiry. If it ships, ask whether `COMBO_MAX` should come down with it —
two multipliers for one behaviour is how a number stops being readable.

**What it touches.**
- `Economy.credit_delivery(fare)` gains the rider's patience fraction, or takes
  the `Passenger`. `GameState._deliver()` (`sim/game_state.gd:307`) is the one
  call site.
- `Passenger.patience_fraction()` already exists and already colours the chip,
  so the player can *see* the input before this pays them for it — which is the
  condition decision 20 imposes on any retroactive-feeling penalty.
- **Every balance figure denominated in today's flat $3.09/trip**, which is all
  of the prestige spec's §2 and §6 and the whole building cost curve. Expected
  income per trip falls to somewhere in [$0, $3] with a mean set by how well the
  building is run, so `DEMOLITION_FLOOR` and the Blueprint tree's costs both
  need re-deriving from the ladder simulation rather than scaling.

**Sequencing.** This is decision 19's neighbour and carries the same warning:
it invalidates the prestige balance if it lands after it. Either it goes in
before S5's numbers are trusted, or S5 ships first and this re-runs
`2026-08-03-prestige-ladder-sim.py` and re-derives the offset. **Do not scale
the constants by hand** — §2.1 shows the rate-optimal exit is not a simple
function of them.

**Open question.** Three bands or a continuous ramp? Bands are legible and
teach the colour ramp; a continuous `fare × patience_fraction` is simpler code
and has no cliff for a rider to fall off one tick early. The cliff is the
argument for continuous: this game's tick order was deliberately built so a
passenger at exactly 0.0 patience still pays, and a band boundary re-creates
exactly the knife-edge that ordering exists to remove.

---

## Show the time of day — BUILT 2026-08-04

**Shipped, and larger than this entry proposed.** The HUD's `09:00` label is
gone; in its place is a full-width `DaySparkline` showing the **whole
building's** day with a playhead on the current hour (`5d2188d`).

Two things this entry did not anticipate:

- **The amalgamation is the feature, not the playhead.** This entry proposed a
  playhead on a *kind's* curve. Summing every tenanted floor is what makes it a
  decision aid — a tower of offices shows one brutal spike where a mixed one is
  smoother but never quiet, and that is the shape you are steering.
- **It had to be sim-side.** `sim/building_day.gd` sums the same
  `TrafficSource` array the spawner consumes, the same way, and reproduces the
  lobby collapse exactly (no usable lobby → everything interfloor, including a
  tenant *on* floor 0). A chart that disagreed with the traffic would be worse
  than no chart, so nine tests pin the agreement.

**What was already there and only needed wiring:** `set_now()`, `playhead_bar()`
and `COLOUR_NOW` all existed and were tested — built for the lease picker and
never pointed at the clock.

**The naming trap below was real and is still unresolved in the code:**
`sim_minute()` still returns an hour bucket. `hour_of_day()` exists and is what
callers use, but the misleading name survives.

**Still open:** the numeric hour is gone entirely. The playhead's position
implies it, but there is no way to read `14:00` exactly. One label if wanted.

<details><summary>Original entry</summary>

**Idea.** Put the hour on screen. Right now traffic swings hard between the
overnight trough and the 07:00 peak and the player has no way to know which they
are in — a quiet building looks identical to a broken one.

**It is already modelled; only the display is missing.** `SimClock.sim_minute()
returns the bucket index and `TenantKind.BUCKETS` is 24, so
`posmod(sim_minute(), 24)` **is** the hour. `START_MINUTE` is 6, so a session
opens at 06:00. Nothing new has to be simulated or saved.

**It moves at a readable speed now.** Post-pacing a bucket is 30 real seconds
(`TICKS_PER_SIM_MINUTE` = 600), so the day is 12 real minutes and the clock
advances about two hours per real minute — fast enough to feel alive, slow
enough to read. Before the pacing change it was half that and would have felt
static.

**Where it goes.** `DaySparkline` already draws a kind's whole day as 24 bars,
one per hour. A **playhead on that sparkline** is the strongest version of this:
it answers "what time is it" and "what is about to happen to my traffic" in one
mark, and it costs one more `_draw()` call on a widget that already exists and
already has bar_heights() as a tested seam. A bare `07:00` label in the
management header is the cheap version and says much less.

**The naming trap.** `sim_minute()` returns an *hour* bucket, not a minute. Any
UI that surfaces it as "minute" will be wrong, and the method name will actively
mislead whoever writes it. Either rename it on the way in, or at minimum do not
propagate the word outward. The same confusion already cost real time when
`TICKS_PER_MINUTE` turned out to be doing two jobs (see the traffic-pacing spec).

</details>

**Open question.** Does the clock show anywhere on the board, or only in
management? The board is 393pt wide and every unit of the gutter is already
spoken for — the floor-number label had to be capped at 22pt for exactly this
reason — so "somewhere on the board" is a real layout decision, not a free one.

---

## A roster of floor kinds (2026-08-03)

Five kinds raised together. They are recorded as one entry because they sort
cleanly by **what they cost to build**, and three of them turn out to need the
same two primitives rather than five separate mechanics.

### Tier 1 — pure data, no code at all

A kind is `{id, name, requires_class, lease_cost, base_fare, rate[24],
inbound[24], outbound[24]}` in `data/tenants.json`. Anything expressible as a
shape over 24 hourly buckets is a **data edit and nothing else** — the spawner,
the catalog and `DaySparkline` already handle arbitrary kinds.

- **Restaurant.** Busy at meal times: spikes at buckets 12–13 and 18–20, near
  dead overnight. Inbound-heavy before each spike, outbound after. This is the
  sharpest *shape* in the roster and the best argument for the sparkline.
- **Hotel.** Consistently busy — a flat, high curve with no trough. Interesting
  precisely because it is the opposite of Apartments: no rush to plan around,
  just steady load. It makes "can I serve this at all" the question instead of
  "when".

These two are worth doing first and separately. They cost hours, not days, and
they prove the kind system carries real variety before anything harder is built.

### Tier 2 — needs multi-slot occupancy

Both of these need a passenger to take up **more than one seat**, which is
exactly the primitive the freight entry above already requires (`Passenger`
gains a size, `ElevatorCar.board()` sums units instead of counting heads, a car
draws more than one figure per slot). Build it once and all three land.

- **Hospital.** A gurney takes 2 slots plus 2 first responders = **4 slots**,
  i.e. the entire base car (`Upgrades.CAPACITY_BASE` is 4). One gurney is a
  dedicated trip. Directional too: gurneys arrive through the lobby *or* leave
  from the hospital floor, so it generates both inbound and outbound heavy
  loads rather than a symmetric mix.
- **Hotel luggage.** A guest sometimes carries luggage and takes 2 slots. The
  cheap version of the same mechanic, and a reason Hotel might be Tier 2 rather
  than Tier 1 if the luggage lands with it.

The hospital is the strongest case for **Load Weighing**: a car that cannot fit
a 4-slot gurney should not stop for it, and today's headcount capacity cannot
express that.

### Tier 3 — needs a passenger that escapes

- **Haunted floor.** Sometimes a ghost gets out.
- **Research floor.** Sometimes an experiment gets loose.

Both are the same primitive: an entity that **leaves the normal
spawn → board → deliver → expire lifecycle** and does something else. That is a
genuinely new thing in the sim — every passenger today is delivered or expires,
and `GameState`'s tick order has no phase for "and then something wanders off".

**Open question, and it is the whole design:** what does an escaped thing *do*?
If it only costs money it is a random tax with no decision in it. It earns its
place only if the player can respond — catch it, contain it, route around it —
which means it needs to change what the elevator should do next.

Related but distinct: **The floor that eats people** above inverts delivery
(arriving *is* the loss). These invert departure. Worth keeping separate.

### Sequencing

Tier 1 first, alone. Tier 2 rides on the freight work and should be scheduled
with it, not before it. Tier 3 wants its own design pass — it is the only one of
the five that adds a phase to the tick order, which is player-visible and pinned
by tests.

---

## From the people-and-car review (2026-08-04)

Issues found by a nine-seat review panel over the shipped people-and-car
changeset, plus my own verification against the current tree. Items already
fixed by later commits are omitted; these all still reproduce.

### The design spec says 240, the code ships 230

`2026-08-04-passenger-and-car-design.md:645` (§6 code-shape table) reads
`SHAFT_WIDTH 160 → 240`, but `view/building_view.gd:37` is `230.0`. The
spec's own §4.1.1 explains why 230 (240 would drop the device board to one
column), so the table is stale, not the code. Fix the row and re-read the
spec for any other `240` left over from an earlier draft. *(auditor, cartographer)*

### `PIP_FREE` is a phantom role

`2026-08-04-passenger-and-car-design.md:593` (§5 table) lists `PIP_FREE` ("the
pip's own track") as a role. The code never implements it — `_draw_pips`
(`view/shaft_column.gd`) paints every hollow pip with `Palette.PERSON_BAR_TRACK`,
reusing the patience-track role. Two documents now disagree about a colour that
does not exist. Delete the row, or restate it as "hollow = `PERSON_BAR_TRACK`, no
new role". *(simplifier)*

### `PersonSprite.recycle()` redraws even when already hidden

`view/person_sprite.gd:129-131` — `recycle()` sets `visible = false` and calls
`_dirty()` unconditionally. `FloorRow.set_waiting()` calls it on every unused
sprite each refresh, so the whole strip queues a redraw every frame, violating
the "Setters early-out on unchanged args" contract the spec's §2.4 is built on.
Return early when the sprite is already recycled. *(cartographer)*

### The ghost band cannot reach prestige at the cap

At the 10-floor cap (10 × 120 = 1200 > the 1184 viewport) the ghost band sits
above the window and cannot be tapped, so `_on_ghost_input`'s
`prestige_requested.emit()` branch (`view/building_view.gd:219`) is dead — the
cap's only board-level route to the prestige panel is gone. The management
view still opens it, so this is a UX gap, not a blocker. Either make the capped
band reachable (count the ghost row into the scrollable content) or remove the
dead branch. *(auditor, fable)*

### The pip strip re-records every frame

`set_riders` calls `_car_rect.queue_redraw()` unconditionally each
`BuildingView.refresh()`, and `_draw_pips` re-emits up to 2×capacity `draw_rect`
commands per car per frame (~192 at 8 cars × cap 12) — the same per-frame cost
`PersonSprite`'s redraw suppression exists to avoid. Add a `(_lit, _pips)`
fingerprint gate like the sprite's. *(fable, opus)*

### Stale comments and test messages from the old geometry

The old constants survive in comments and test messages, all verified present:

- `view/floor_row.gd:16-17` — "the crowd bar, whose LENGTH is the encoding",
  but the crowd bar is deleted and rows are a fixed 120.
- `view/building_view.gd:313-314` and `:223` — "five owned shafts fill all five
  visible positions"; there are two visible columns now. The slot docstring
  still describes five positions.
- `view/shaft_column.gd:30-31` — "Today's PassengerSprite.FONT, kept" — a
  dangling reference to the deleted class.
- `tests/test_board_input.gd` — `:343` "x = 240 belongs to the shaft, not the
  hall" (SHAFT_AREA_X is 208); `:386` "the chip is still drawn" (it is a
  figure); `:442` "Four filled squares of four IS the count" (pips, not
  squares); `:767` "the 88-unit pan strip" (rows are 120, and at the cap the
  band is off-screen anyway).
- `tests/test_palette.gd:102-104` — "INK_ON_LIGHT is drawn on the car AND on the
  patience chips" — the patience-chip half was deleted two lines below by the
  same change; the sentence contradicts itself.
- `tests/test_gesture.gd:4-5` — `H := 29.6` is the old capped row height. The
  assertion still passes (12 < 14.8 < 60) and the spec says not to "fix" it,
  but the header comment is stale.
- `tests/test_coords_scroll.gd:10` / `tests/test_pan_gesture.gd:9` — `const H :=
  88.0`. Scale-invariant, so they pass and test the transform correctly, but the
  design spec's §8 item 19 said to re-derive or justify them and this pass
  neither re-derived nor justified. *(cartographer, opus, fable)*

### `set_cell` carries two always-constant arguments

`view/person_sprite.gd:93` — `set_cell(cell, badge_h, font_size)` has exactly one
caller (`view/shaft_column.gd`), always passing `CarRack.BADGE_H` (30) and
`CAR_FONT` (24); the hall never calls it. And the `_font_size = 12` default is
never rendered. Collapse to `set_cell(cell)` with the two constants read from
`CarRack`/a `PersonSprite` constant, or say what future caller will pass
something different. *(simplifier)*

### The call-direction spec and plan document the deleted call

`2026-08-02-call-direction-upgrade-design.md:75-83` still shows the `show_as(...)`
call, while the live caller is `show_waiting(...)` (`view/floor_row.gd:120`); the
implementation plan `2026-08-03-call-direction-upgrade.md:192-197` repeats it.
Update both. *(cartographer)*

### The pager readout timing is untested

`game/game_root.gd` hides the readout when `max_scroll() == 0`, and the column
widening moved that boundary to `owned = 2`. The spec itself
(`2026-08-04-passenger-and-car-design.md:358`) acknowledges no test pins it.
Worth a test: at owned = 2 the readout appears. *(opus)*

---

## A background for every floor (2026-08-04)

**Idea (yours).** A floor that has a tenant shows what that place *is* — the
door to a club, a row of apartment doors, part of a dance floor, a bar. A floor
with nothing shows the shell it actually is: columns, cement bags, bare
concrete.

**Why it is more than decoration.** Right now a floor's identity is a word in
the panel and a curve in the sparkline. Nothing on the board says what a floor
*is* — a leased apartment and a leased gym are the same cream band with the same
people on it. Scenery would make the building legible at a glance, and it would
make the vacant floors read as *unfinished* rather than merely empty, which is
the difference between "I have not got to that yet" and "nothing is there".

It also pays off Spec A. Tenant kinds already differ in traffic shape, class and
fare; the one thing they do not differ in is how they LOOK, so the strategic
choice the design spent a whole spec on is invisible on the board.

**What it touches, and this is the hard part.**

- **It reverses a decision this codebase just made deliberately.** The
  people-and-car spec (§9) rules generated raster art out of scope, and
  `PersonSprite` is drawn with primitives *specifically* so nothing needs a
  texture. The shipped `.pck` is **160 KB**; the exclusion of `brand/art/`
  bought 0.17 MB of that. Per-kind backgrounds are the first real art asset in
  the project and the first thing to make that number move.
- **The threadless web export is the binding constraint**, not the phone. Pages
  cannot set the COOP/COEP headers, so this ships single-threaded to mobile
  Safari, and every KB is a KB somebody downloads before the game starts.
- **A floor band is 144 x 120 units** on a 720-wide canvas — roughly 79 x 66 pt.
  That is a small canvas for "a bar" to read as a bar rather than as noise
  behind the people standing on it.
- **The people have to stay readable on top of it.** The whole palette argument
  in the people-and-car spec is contrast against TWO known grounds, cream and
  the car's teal. A per-kind background makes the ground a variable, and eight
  decorative pigments that were solved against two grounds would need re-solving
  against N. That is the AFFORD_OFF failure waiting to happen at scale.

**The cheap version worth considering first.** Not illustration — a per-kind
**motif** drawn with the same primitives the people use: a doorway shape, a
counter line, a row of bollards for the shell. Costs no bytes, cannot break the
contrast argument (it is drawn from the palette), and answers "what is this
floor" without answering "what does this place look like". If that reads well,
the illustrated version is a swap behind the same seam; if it does not, the
question was never about fidelity.

**The measured answer to "how big" (2026-08-04).** Everything left of the shafts
is `x 0 -> FloorRow.STRIP_RIGHT` (208) and a floor is `BuildingView.FLOOR_HEIGHT`
(120) tall. Both are fixed constants, so an asset never has to scale
responsively:

| region | canvas units | ratio | @3x px |
| --- | --- | --- | --- |
| people strip only | 140 x 120 | 7:6 | 229 x 196 |
| **gutter + strip** | **208 x 120** | **26:15** | **341 x 196** |
| full row incl. shafts | 688 x 120 | 86:15 | 1127 x 196 |

Take 208 x 120. The shafts are opaque, so a full-row asset wastes ~70% of every
file, and the gutter is only 64 units of quiet chrome. Author at **416 x 240**
(2x canvas units — integer relationship, 22% of headroom over @3x). The scale
chain: 720 units -> 393 pt is **0.546 pt/unit**, x3 on a modern iPhone, so one
unit is ~1.64 device pixels.

**And the reason to hesitate before drawing any of it:** raster assets PIN those
two constants, and both moved twice on 2026-08-04 alone — `FLOOR_HEIGHT` 88 ->
112 -> 120 and `STRIP_WIDTH` 176 -> 144, each for legibility reasons that only
appeared on the device. A finished asset set would have been invalidated three
times in a day. Either keep the outer ~8 units of each edge empty so a constant
change crops instead of rescaling, or build the primitive-motif version first
and find out whether the idea reads at 114 x 66 pt before buying the pipeline.

**Open questions.**
- Does a vacant floor's construction look apply to a floor that has *never* been
  leased, or also to one whose tenant just left? Those are different states and
  the tenancy model distinguishes them (`MOVE_OUT_TICKS`).
- Does the scenery scroll with the band or sit behind it? A parallax layer would be
  cheap and would make the board feel like a building rather than a list.
- Is it per KIND or per CLASS? Fitout tiers already change a floor's fare
  multiplier; scenery that reflected the tier would make an upgrade visible,
  which no other upgrade in the game manages.

---

## Not in this list, and deliberately

**Offline earnings.** Saving is built; accruing while closed is not. §9.1 of the
design spec is the least settled part of it, and a wrong guess there is a
balance decision that is hard to walk back. A save that loses nothing is worth
having before one that invents something.

---

## From implementing the tenant/class plan (2026-08-02)

Ideas that surfaced while building, kept out of the plan because they are
follow-on work, not this work.

### Class as an anticipatory investment, and a vacant-floor signal

`Fitout` persists through tenant change, so a class-3 floor stays class 3 while
vacant. That makes a class upgrade something you can buy *ahead of* a tenant —
upgrade the floor, then wait/attract who it deserves. The FloorPanel already
filters the lease picker by the floor's class. Worth deciding whether "upgrade
a vacant floor" is a read-as-strategy or an accidental no-op, and whether a
vacant premium floor should draw better tenants on its own (a softer, place-based
variant of the reputation gate — the building's *hardware*, not its service,
advertises).

### Lease cost does not know about the floor's class

`lease_cost` is a flat per-kind number, so putting a tier-1 apartment on a
class-3 floor costs exactly what it costs on a class-1 floor. A plausible second
lever: scale the lease by floor class (the building is nicer, letting costs
more). It gives class a role *while the floor is vacant*, not just as a gate,
and it makes the "upgrade then lease" order a real economy. Mirror question:
should upgrading a tenanted floor retroactively raise that tenant's lease? (I
lean no — a signed lease at the old price — which is also what the current
fare-only-multiplier behaviour implies.)

### The lobby tenant's direction is invisible

Floor 0 carries a tenant (Shops in the roster), but because the lobby is a
pinch-point endpoint, its inbound/outbound weights collapse to interfloor —
the right *handling*, but it means "a tenant at the door" cannot express a
directional pattern. Not a bug (verified by
`test_a_tenanted_lobby_generates_only_interfloor_trips`), but if a floor-0 kind
is ever meant to have a direction (e.g. a doorman-screening tenant), this is the
seam.

### Plan-correctness rulings (do not re-fix)

These are decision records, not ideas — recorded so a later reviewer does not
"discover" them anew and spend a cycle asking.

- **Task 3 delivery test** as written never dispatched the car back to the
  lobby, so no delivery ever happened; and a full minute is exactly long enough
  for 30 manual expiries' 1200-tick move-out countdown to vacate the floor,
  which makes `note_delivery` (a no-op on a vacant row) suppress the asserted
  credit. Fixed with short (200-tick) windows plus an explicit return dispatch.
- **Task 2 factory** kept its defaulted params (the plan's snippet made them
  required, which would break the file's short calls); it passes `source =
  origin` as the fallback. The *constructor* stays required — only the test
  factory defaults.
- **Task 7** the plan anticipated the `buy` test failing as "Task 9's" but also
  demanded a green commit. I inverted that one assertion early (a purchased row
  is vacant) so every commit stayed green; Task 9 then replaced the whole test.
- **Task 9** `GameState._init` must NOT `push_error` on a bad catalog: GUT
  counts `push_error` as a test error, turning the malformed-catalog refusal
  test red for the wrong reason. `is_valid()` is the contract; the boot path
  (Task 18) draws the path on a screen.
- **Task 10** two rulings. (a) The source-driven `rng` had to be seeded from
  `p_seed` in `TrafficSpawner._init`, or determinism (pinned in
  `test_the_sim_is_deterministic_for_a_given_seed`) silently broke; the now-dead
  `_rng` was deleted. (b) The re-derived opening-traffic test must count off a
  signal into an Array, not `var spawned := 0`: GDScript lambdas capture ints by
  value (verified empirically), so a captured counter reads back zero. The
  pre-existing test already documented this.
- **Plan test counts** were consistently +1 off (arithmetic): actuals were
  388/392/396/399/402/405/408 where the plan printed 389+1. Cosmetic; the suite
  is green at whatever it is.
- **Tasks 13, 15, 17 wrote tests against assumptions that do not hold.**
  (a) Task 13's move-out test gave every passenger patience 900 but ticked 1201
  ticks, so even the intended survivor expired naturally; and the parked car at
  floor 0 boards any origin-0 passenger (via `answer_call`), turning them into
  riders. It needed ambient traffic silenced (one tenanted floor), patience far
  past the window, and the car sent to the roof first. (b) The view-layer tests
  (Tasks 15/17) assume a `_board(...)`/`last_selected_floor`/`root.panel`
  harness that is NOT what `test_board_input.gd` is -- it uses global
  `root`/`view` + `do_tap`/`do_drag` + a `ReletConfirm` reached through
  `BuildingView._gui_input`. Any view-layer implementation must either build
  that harness or (preferred) adapt the tests to the real one.
