# People, and the car they stand in

**Status:** design, not yet built.
**Supersedes parts of** `2026-08-02-ui-design.md` §3.3 and §3.5 — see §8.

## 1. Why

The mid-century palette landed (`898ee4d`) and the board is now cream, rust and
teal, sampled from `brand/art/dir3_in_game.png`. What did not change is what a
person *is*: a 30 × 30 `ColorRect` whose fill lerps green → red with patience and
whose label says either a call arrow or a floor number.

That square is the last thing on the board that does not belong to the theme, and
it cannot be made to. The colour ramp **is** the patience encoding, so the body
cannot carry an illustration — `modulate` multiplies, and a tinted person is a
person the ramp has ruined. The mockup already solves this: its people are
decorative, and patience lives in a separate green → red thermometer beside them.
Adopting the look therefore *requires* moving the encoding, which is a deliberate
change to something the UI spec pins, not a side effect of importing art.

Three things follow from that one move, and this spec covers all three because
they cannot be built separately:

1. A person becomes a **figure with a badge and a bar**, not a labelled square.
2. Riders **stand on the floor of the car** rather than sitting in a rack of
   seats — which deletes the thing that showed how full the car was.
3. So the car needs a **load gauge**, because the rack was the gauge.

### 1.1 Two things found while reading, which shaped the design

**Patience is frozen once aboard.** `Passenger.decay` is called only from
`GameState._expire`, which skips riders, and `waited_ticks()`'s docstring states
the invariant outright. So a car chip has always coloured itself from a number
that stopped moving at boarding: the patience encoding inside the car is inert.
**The car needs no patience representation at all**, which is what buys the room
for two ranks of figures.

**§3.5's crowd bar cannot fire.** It triggers below a 40-unit row; rows have been
a fixed 88 since the board learned to scroll. `FloorRow`'s own docstring says a
representation that never appears is worse than none — so this spec deletes the
tier from the document rather than leaving it dead in it.

**§3.3's vacant-floor price is already gone.** The spec still describes a re-lease
price right-aligned in the strip, with the sprite cap dropping from 12 to 10 on
that floor. The lease picker moved into `FloorPanel`; `FloorRow.set_tenant` draws
only the bar. Nothing narrows the strip any more, which is why §3 below can claim
the full twelve on every floor.

## 2. The person

One node, three parts, in a **20 × 40** cell:

```
   ( ▲ )      badge    16 × 14 at (2, 0)
    ●         figure   14 × 22 at (0, 16)      bar   4 × 22 at (16, 16)
   ███ █          head   ⌀8, centred (7, 20)
   █ █ █          torso  10 × 9  at (2, 25)
                  legs 2× 4 × 4  at (2, 34) and (8, 34)
```

- **The badge** carries the glyph: a call arrow while waiting, the destination
  floor once aboard. That asymmetry is the dispatch puzzle and is unchanged —
  only where the glyph is drawn moves.
- **The figure** is decorative. Its shirt and skin are chosen from the palette,
  not from game state.
- **The bar** is patience: `PATIENCE_LOW → PATIENCE_OK` over a `BAR_TRACK`
  ground, filling from the bottom, the same ramp and the same direction as the
  tenant bar in the gutter.

**The figure is identical everywhere** — same size, same parts, in the hall and
in the car. Only the bar differs: a rider has no patience, so a rider has no bar,
and the car's cell is **16 × 38** rather than 20 × 40.

### 2.1 The shirt must be stable, and must not touch the sim

Sprites are pooled. If a shirt colour were random per frame, or keyed to the pool
slot, a crowd would flicker as people boarded and the pool reshuffled.

The colour is therefore **hashed from the passenger's own immutable fields**:

```
index = (origin_floor * 31 + destination_floor * 17 + source_floor * 7)
        % PERSON_SHIRTS.size()
```

Same passenger, same shirt, wherever and whenever it is drawn. Two passengers
making the identical trip share a shirt, which is acceptable and occasionally
useful — a knot of one colour is a knot of people going the same way.

`Passenger` gains **no field**. A cosmetic id on a sim class would be the layering
violation this codebase is built to refuse, and the hash makes it unnecessary.

### 2.2 Two entry points, no flag

```gdscript
func show_waiting(fraction: float, glyph: String, key: int) -> void
func show_riding(glyph: String, key: int) -> void
```

Not one call with a `has_patience` boolean. `FloorRow.set_waiting`'s
`show_direction` parameter is required rather than defaulted for exactly this
reason — a defaulted flag lets a future caller opt out of a rule silently, which
is the class of bug `note_expiry(fare)`'s default caused.

## 3. The hall

The packing rule does not change. `ChipGrid`'s `floor(sqrt(n))` shape, its
centred short last rank, and its refusal to floor a too-small area at one rank
are all kept verbatim. What changes is that **the cell stops being square**:
`SIZE: float` becomes a cell `Vector2`, threaded through `columns_for`,
`rows_for` and `position_of`.

Measured against the real strip — `SPRITE_X = 68` to `STRIP_RIGHT = 240`, so 172
units wide, on an 88-unit row, at a 24 × 44 pitch:

```
columns_for(172, 24) = (172 + 4) / 28 = 6
rows_for(88, 40)     = (88 + 4) / 44  = 2
shape(12, 6, 2)      = 6 x 2          = 12
```

**All twelve now fit.** `MAX_INDIVIDUALS = 12` has been effectively 10 since the
30-unit square met the fixed 88-unit row (`shape(12, 5, 2)` yields 5 × 2). The
constant becomes true for the first time, on every floor, because nothing
narrows the strip any more (§1.1).

## 4. The car

A car is **150 × 84** — `SHAFT_WIDTH (160) − 4` for the column, `− 6` for the
car, on an 88-unit row less 4.

```
┌──────────────────────────────────┐  y 0   pip strip, 6 tall, inset 8 each side
│ ██ ██ ██ ██ ░░ ░░                │
│    ( 9 )  ( 3 )  ( 11 )          │  y 6   back rank, 38 tall, offset half a pitch
│      ●      ●      ●             │
│  ( 3 )  ( 7 )  ( 7 )  ( 2 )      │  y 44  front rank, 38 tall, on the car floor
│    ●      ●      ●      ●        │
└──────────────────────────────────┘  y 82
```

### 4.1 The ranks

Riders fill the **front rank left to right**; when it is full the rest stand
behind and above, offset half a pitch so a back figure sits in the gap between
two front badges rather than directly behind one.

```
PITCH      = CAR_CELL.x (16) + GAP (4) = 20
front_cols = floor((150 + 4) / 20) = 7
back_cols  = front_cols - 1        = 6      # the half-pitch offset costs one slot
max drawn  = 13                             # capacity caps at 12
```

The back rank losing a slot to its own offset is what keeps the two ranks from
ever needing to overflow: 13 slots against a maximum capacity of 12
(`CAPACITY_BASE 4 + max_level 8`).

**At capacity 4 there is only ever one rank** and the upper band stays empty. The
car looks emptier when it is emptier, which reinforces the gauge instead of
competing with it.

### 4.2 The pips are the seat rack, flattened

One pip per seat, lit for a rider and hollow for a free seat. Capacity runs 4 to
12 — small and discrete — so lit-versus-hollow still answers *"does one more
fit"* **exactly**, which is the entire argument the seat rack was built on and
the reason this is not a needle or a continuous bar. A needle at 3-of-4 versus
4-of-4 is a few degrees of sweep, and "is there room" would stop being a count
and start being a judgement.

```
width = 150 - 16 = 134,  gap 3
capacity  4 -> pip 31.2 wide
capacity 12 -> pip  8.4 wide
```

`free_slots_shown()` and `seats_taken()` keep their names and count pips. Most of
the car's existing tests therefore keep working unchanged, which is the point of
keeping them.

### 4.3 What is kept, and what is lost

**Kept:** the translucent doors slide over the whole car and the riders stay
legible while shut (§3.7); the header fallback for a car too short to draw
figures in, unreachable at a fixed 88-unit row but tested and free; the exact
per-rider destination.

**Lost, deliberately:** *"a passenger looks and packs identically before and after
boarding"* (§3.3). Standing on a floor is not a sqrt-balanced grid, and it cannot
be made into one. What survives is the half that carries the meaning — **a person
looks the same everywhere**, same figure, same badge, only the glyph changing
from a call arrow to a floor. The packing half is the price of people standing in
the lift, and it is being paid on purpose.

## 5. Colour

New **roles** only; every one points at a pigment already sampled from
`dir3_in_game.png`, except the skin and shirt sets, which are sampled from the
same file as part of this work. Nothing outside `palette.gd` names a pigment.

| role | requirement |
| --- | --- |
| `PERSON_SKINS` | three tones, sampled from the mockup's people |
| `PERSON_SHIRTS` | four, sampled; must separate from each other and from `CAR` |
| `PERSON_LEGS` | `BROWN_DARK` |
| `BADGE_BG` | `TEAL_INK` |
| `BADGE_INK` | `CREAM_PALE` |
| `PIP_LIT` | `CREAM_PALE` |
| `PIP_FREE` | `TEAL_DARK` — today's `SEAT_FREE`, re-pointed |

**The badge lands on two different grounds** — cream in the hall, teal on the car
— and must read on both. `TEAL_INK` measures roughly 3.5:1 against `CAR` and far
more against `APP_BG`, clearing the 3:1 threshold for a graphic element on the
worse of the two.

That dual requirement is the whole reason it is written down. `AFFORD_OFF` was
tuned against `APP_BG` while being drawn on `GHOST_BG`, measured 2.03:1 in its
test and 1.29:1 on screen, and "+ BUILD FLOOR $200" was effectively invisible
while the suite stayed green. **A colour is tested against every surface it lands
on, or the test is worse than none.**

## 6. Code shape

| file | change |
| --- | --- |
| `view/person_sprite.gd` | **new.** Replaces `passenger_sprite.gd`. One `Control` that `_draw()`s badge, figure and bar; one `Label` child for the glyph. |
| `view/car_rack.gd` | **new**, `RefCounted`, no scene tree. Given rider count, capacity and car size, returns rank slots and pip rects. Pure geometry, unit-tested headlessly like `ChipGrid`. |
| `view/chip_grid.gd` | `SIZE: float` → cell `Vector2`, threaded through the three functions. The shape rule itself is untouched. |
| `view/shaft_column.gd` | seat rack → pips + ranks, via `CarRack`. Query methods keep their names. |
| `view/floor_row.gd` | same `ChipGrid` call, new cell, `PersonSprite`. |
| `game/util/palette.gd` | the roles in §5. |
| `view/passenger_sprite.gd` | **deleted.** |

`CarRack` exists so `ShaftColumn` does not grow a second layout engine inside a
file that is already 299 lines and already owns doors, gestures and the car's
position.

**The node budget does not move.** A person is one `Control` plus one `Label` —
exactly what a `ColorRect` plus a `Label` costs today. §8.5's count is unaffected.

## 7. Tests

**New — `tests/test_car_rack.gd`:**

1. The front rank fills left to right before anyone stands behind.
2. Overflow goes to the back rank, offset half a pitch.
3. `front_cols = 7`, `back_cols = 6`, so 13 slots cover the capacity cap of 12.
4. Pips number exactly `capacity`; lit pips number exactly `riders.size()`.
5. Nothing — pip or slot — is positioned outside the car's rect, at capacity 4
   and at 12.

**New — `tests/test_person_sprite.gd`:**

6. Badge, figure and bar fit the cell and do not overlap each other.
7. The shirt index is stable for a given passenger and independent of which pool
   slot draws it.
8. A rider has no patience bar; a waiting passenger has one.

**Changed:**

9. `tests/test_chip_grid.gd` — every packing assertion kept, retargeted to the
   cell parameter.
10. `tests/test_board_input.gd` — `label_text()` reads the badge; the seat
    assertions read pips. Plus **new**: all twelve waiting passengers are drawn
    on a floor with twelve, which is false today.
11. `tests/test_palette.gd` — the badge is measured against **both** `APP_BG` and
    `CAR`; the patience ramp is measured against `BAR_TRACK`.

**Docs:** `2026-08-02-ui-design.md` §3.3 and §3.5 rewritten per §8;
`codemaps/view.md` regenerated.

## 8. Deltas against the UI design spec

- **§3.3** — "People are squares, packed by one rule everywhere" becomes "people
  are figures, packed by one rule *in the hall*". The car's rank layout is stated
  separately (§4.1 here). The vacant-floor price and its 10-sprite cap are struck:
  the code has not drawn them since the lease picker moved to `FloorPanel`.
- **§3.5 "Density tiers" is deleted, not amended.** Rows are a fixed 88, so the
  ≤ 40-unit crowd-bar tier can never fire. The section's remaining content — the
  12-sprite cap and the always-exact count — folds into §3.3.
- **§3.7** is unchanged and still correct: the doors slide over the car, and
  translucency now protects a view of *figures* rather than of a seat rack.
- The **seat rack** disappears from the document wherever it is described as the
  car's occupancy display; the pip strip replaces it, with §4.2's argument for
  why it is segmented rather than continuous.

## 9. Out of scope

- **Generated raster art.** The figures are primitives. The pipeline discussed
  earlier — Nano Banana at 4×, magenta key, despill, downsample — is not being
  built, and `PersonSprite` is the seam where a texture could replace `_draw()`
  later without touching the strip, the car or the tests.
- **Animation.** Nobody walks, turns, or steps through the doors. Figures appear
  and disappear exactly where sprites do today.
- **Freight, multi-slot occupancy, and anything that makes a person take more
  than one slot.** The backlog's freight entry needs `Passenger` to gain a size
  and `ElevatorCar.board()` to sum units; a rank of fixed slots is compatible
  with that later and does not attempt it now.
- **The destination-entry panel.** It would put a floor on a *waiting* badge
  instead of an arrow. The badge is sized for one glyph; two digits is the width
  change that upgrade has to buy, exactly as §3.3 already says.

## 10. Verification

Every number above is arithmetic until something renders it. Before the work is
called done, on device:

1. Capacity 4, one shaft — the single rank, and four pips.
2. Capacity 12, three shafts — both ranks, the half-pitch offset, and an 8.4-unit
   pip still readable at the 0.546 iPhone scale.
3. A floor with twelve waiting — the claim in §3 that all twelve now fit.
4. A car mid-stop — the doors translucent over figures, riders still legible.

If (2) fails to read at 8.4 units, the fallback is stated now rather than
improvised then: **the pip strip grows from 6 to 10 units and the 2-unit gap
between a badge and the head below it closes**, taking each rank band from 38 to
36. That is `10 + 36 + 36 = 82`, still inside the car's 84, and it costs a
touching badge rather than a shorter figure — the figure must stay identical to
the hall's (§2) or the one property §4.3 preserves is gone too.
