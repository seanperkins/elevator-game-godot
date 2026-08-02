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

## A second currency: satisfaction

**Idea.** Satisfaction as a spendable currency, unlocking elevator music and
other comforts.

**The conflict to resolve first.** Satisfaction already exists and already has a
job: `Tenancy._satisfaction` is a per-row 0–1 value that **scales rent**. If the
same number is also spent, then spending it cuts income, which makes every
purchase a rent cut — probably not the intent.

**Suggested split.**
- **Satisfaction** stays what it is: per-row, a rate, not a stock.
- A second currency — *goodwill*, say — **accrues from** satisfaction over time,
  the way rent accrues from it now. High satisfaction earns goodwill per minute;
  spending goodwill does not lower satisfaction.

That keeps the existing balance intact and gives the new currency its own source.
It also gives satisfaction a second reason to matter, which it needs: right now a
player can ignore it until a tenant threatens to leave.

**What it would buy.** Comforts rather than throughput — music, better lighting,
lobby plants — so the two currencies do not compete for the same purchases.
Comforts could feed back into satisfaction, but note the loop: satisfaction earns
goodwill, goodwill buys comfort, comfort raises satisfaction. That compounds, and
per the design spec's rule about uncapped compounding, it needs a cap decided up
front.

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
