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

## Parking garage below the lobby

**Idea.** Floors beneath the lobby.

**This is the largest of these.** Everything currently assumes **floor 0 is the
lobby and the bottom of the board**:

- `BoardCoords` builds an edge table over `[0, N)` and maps bottom-up from 0.
  Negative floors mean the table needs an origin offset, and `y_to_floor` has to
  return negatives.
- `DispatchPolicy.LOBBY = 0` is the parking target for Lobby Parking; with a
  basement, "home" and "floor 0" stop being the same idea.
- `ElevatorCar.is_spring_trip` defines the launch as `from == 0` to the top. Does
  the spring launch from the *lowest* floor or from the lobby?
- The ghost floor sits above the top floor. A basement needs its own "+ DIG"
  affordance below the lobby, and the two cannot share the band.

**Recommendation.** Do this *before* the era ladder rather than after — retrofitting
an origin offset through a coordinate system that four consumers depend on is
exactly the kind of change the one-transform rule exists to make survivable, but
it is still cheaper while N is small.

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
