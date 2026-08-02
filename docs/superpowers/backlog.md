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
- `ChipGrid` draws one square per passenger — freight needs to occupy more than
  one square, or the seat rack stops telling the truth.
- The load sensor gets a real job: refuse a hall call when the *remaining units*
  cannot take the smallest waiting load.

**Open question.** Does freight expire like a person's patience? A pallet has no
patience, but a delivery window might.

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

**Where it fits.** Waiting passengers currently show a call arrow (up/down)
because that is all a hall button knows. This is the hardware that changes what
the player can plan, and it is already anticipated in `passenger_sprite.gd`.

**Note.** It also changes the *hall* rendering, not just the policy: chips would
need to show a floor rather than an arrow, which is a width change the strip has
to absorb.

---

## Not in this list, and deliberately

**Offline earnings.** Saving is built; accruing while closed is not. §9.1 of the
design spec is the least settled part of it, and a wrong guess there is a
balance decision that is hard to walk back. A save that loses nothing is worth
having before one that invents something.
