# People, and the car they stand in

**Status:** design, not yet built. Reviewed by a five-seat panel over **three
rounds**, and revised after each. Round 1 found the patience bar was invisible
against its own track; round 2 found the back rank left the car and one tint key
could not carry two palettes; round 3 found the board is 688 units wide on a
phone, not 720, which is why §4.1.1 exists.
**Supersedes parts of** `2026-08-02-ui-design.md` §3.1, §3.3, §3.5 and §3.7 — see §8.

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

Three things follow from that one move:

1. A person becomes a **figure with a badge and a bar**, not a labelled square.
2. Riders **stand on the floor of the car** rather than sitting in a rack of
   seats — which deletes the thing that showed how full the car was.
3. So the car needs a **load gauge**, because the rack was the gauge.

And a fourth, decided during review: **the car gets bigger** (§4.1), because at
150 × 84 none of the above fits at a legible size.

### 1.1 Four things found by reading the code, which shaped the design

**Patience is frozen once aboard.** `Passenger.decay` is called only from
`GameState._expire`, which decays the waiting queues alone
(`sim/game_state.gd:413-418`), and `waited_ticks()`'s docstring states the
invariant (`sim/passenger.gd:39-45`). So a car chip has always coloured itself
from a number that stopped moving at boarding: the patience encoding inside the
car is inert. **The car needs no patience representation at all.**

**§3.5's crowd bar cannot fire.** It triggers below a 40-unit row; rows have been
a fixed 88 since the board learned to scroll (`view/building_view.gd:39`).
`FloorRow`'s own docstring says a representation that never appears is worse than
none (`view/floor_row.gd:97-102`) — so this spec deletes the tier from the
document rather than leaving it dead in it.

**§3.3's vacant-floor price is already gone.** The lease picker moved into
`FloorPanel`; `FloorRow.set_tenant` draws only the bar
(`view/floor_row.gd:139-156`). Nothing narrows the strip, which is why §3 can
claim the full twelve on every floor.

**The seat rack already stops drawing at capacity 9.** This is load-bearing and
was stated backwards in the first draft. The rack is laid out by
`ChipGrid.shape(capacity, …)` against the car (`view/shaft_column.gd:185-186`):

```
columns_for(150) = int((150 + 4) / 34) = 4
rows_for(84)     = int((84  + 4) / 34) = 2
shape(12, 4, 2)  = 4 x 2 = 8 seats  <  capacity 12
  -> ChipGrid.fits(grid) < capacity  ->  _draw_header_only
```

So today the picture survives to capacity 8 and reverts to a text line at 9 — the
"Bigger Car" upgrade buys something the player cannot see. The fallback is **not**
"unreachable at a fixed row height": it fires on **capacity**, in the shipped
game. §4.4 is the answer to it.

## 2. The person

One node, three parts. The **hall** cell is **20 × 40**:

```
    ▲         badge    16 × 14 at (0, 0)      a DRAWN triangle, not a font glyph
    ●         figure   14 × 22 at (1, 16)     bar  4 × 22 at (16, 16)
   ███ █          head   ⌀8, centred at figure-local (7, 4)
   █ █ █          torso  10 × 9  at figure-local (2, 9)
                  legs 2× 4 × 4  at figure-local (2, 18) and (8, 18)
```

- **The badge** carries the glyph: a call arrow while waiting, the destination
  floor once aboard. That asymmetry is the dispatch puzzle and is unchanged —
  only where the glyph is drawn moves.
- **The figure** is decorative. Its shirt and skin come from the palette, not
  from game state.
- **The bar** is patience: `PATIENCE_LOW → PATIENCE_OK` over a
  **`PERSON_BAR_TRACK`** ground (§5 — *not* `BAR_TRACK`, which cannot carry it),
  filling from the bottom.

### 2.1 The hall arrow is drawn, not typeset

A 16 × 14 badge holding a font glyph puts the call arrow at **font 12 = 6.6 pt**
at the 0.546 scale. Today it is font 24 = 13.1 pt
(`view/passenger_sprite.gd:25`), and §4.1 spends a shaft column on the argument
that 7.1 pt is disqualifying. Halving the point size of the one glyph that feeds
dispatch decisions, in that same document, is not a trade worth making silently.

So the hall badge **does not use the font at all**: `▲` and `▼` are drawn as
filled triangles in `_draw()`. The badge is already a drawn shape, a triangle
reads better at 14 units than any glyph, and the pt question disappears.

`label_text()` still returns the direction string, so it remains the logical
accessor the existing tests read (`tests/test_board_input.gd:379-416`) — it
reports what the badge *means*, not what a `Label` renders. Only the car's badge
uses the `Label`.

### 2.2 Where the figure sits, exactly

**The figure is identical everywhere** — same 14 × 22 box, same parts, same
internal proportions, in the hall and in the car. What is *not* fixed is its x
offset:

> **The figure is centred within its cell's figure band** — the cell width less
> the bar column. In the hall that band is 16 wide, so the figure lands at x = 1.
> In a 32–40-unit car cell it lands at `(cell − 14) / 2`.

The first draft pinned "figure at x = 1" in both contexts, which centres it in the
hall and strands it against the badge's left edge in the car, contradicting §4.2's
own diagram. Centring is the rule; x = 1 is what it degenerates to in the hall.

Two other differences, stated rather than implied:

- **A rider has no bar** (patience is frozen aboard), so the car cell drops the
  4-unit bar column.
- **A rider's badge is larger** — two digits, not one glyph, and typeset. §4.3.

### 2.3 Shirt and skin must be stable, spread, and must not touch the sim

Sprites are pooled. A colour keyed to the pool slot, or rolled per frame, makes a
crowd flicker as people board and the pool reshuffles. Both colours are therefore
**derived from the passenger's own immutable fields, from one key**:

```
key   = origin_floor * 4 + destination_floor * 7 + source_floor * 9
shirt = key % PERSON_SHIRTS.size()     # size 5
skin  = key % PERSON_SKINS.size()      # size 3
```

**The coefficients and the palette sizes are load-bearing, not arbitrary**, and
they have now failed twice, so the rule is written down rather than re-derived:

> For every trip shape the spawner emits, **each freely-varying field's
> coefficient in the surviving key must be coprime to both palette sizes** — that
> is, to 15.

Stated as a *sum* it would be wrong: interfloor's surviving key is `13F + 7G` and
`13 + 7 = 20`, which shares 5 with 15. The claim that holds is per varying field —
`13` and `7` are each coprime to 15, so varying either sweeps every residue.

The spawner emits exactly three shapes (`sim/traffic_spawner.gd:77-107`):

| trip | `(o, d, s)` | surviving key | `% 5` | `% 3` |
| --- | --- | --- | --- | --- |
| inbound | `(0, F, F)` | `16F` | `F % 5` — all five | `F % 3` — all three |
| outbound | `(F, 0, F)` | `13F` | `3F % 5` — all five | `F % 3` — all three |
| interfloor | `(F, G, F)` | `13F + 7G` | `(3F + 2G) % 5` | `(F + G) % 3` |
| interfloor, lobby source | `(0, G, 0)` | `7G` | `2G % 5` — all five | `G % 3` — all three |

The fourth row is not a fourth shape: `sim/traffic_spawner.gd:94` sets
`lobby_usable = lobby_tenanted and chosen.floor_index != LOBBY`, so a floor-0
tenant's trip is interfloor with `origin = source = 0`. It is the `F = 0` case of
row three, and it is called out because both previous key failures were exactly
this kind of degenerate substitution — §7's spread test spans floor **0** to 20
for that reason, not 1 to 20.

Two earlier attempts are recorded because each looked right:

- `(31, 17, 7) % 4` — mod 4 those are `(3, 1, 3)`, so inbound gives `24F % 4 = 0`:
  **every inbound passenger in one shirt**, on the busiest strip on the board.
- `(3, 7, 11)` with `skin = (o+d+s) % 3` — a *different* key, not recoverable from
  the first. An implementer reducing the single key mod 3 gets `(d + 2s)`, so
  inbound gives `3F ≡ 0`: the same collapse, on skins.

`(4, 7, 9)` is verified over floors 1–20 on all three shapes: all five shirts and
all three skins occur. **Two passengers making the identical trip still share both
colours** — no function of three fields can separate them, and that is accepted.
What is not accepted is a whole traffic class collapsing, and §7 tests the spread.

`Passenger` gains **no field**. A cosmetic id on a sim class would be the layering
violation this codebase refuses, and the derivation makes it unnecessary.

### 2.4 Two entry points, no flag; the sprite owns the modulo

```gdscript
func show_waiting(fraction: float, glyph: String, tint_key: int) -> void
func show_riding(glyph: String, tint_key: int) -> void
func label_text() -> String     # KEPT — read by tests/test_board_input.gd:379-416
func recycle() -> void          # KEPT — called by floor_row.gd and shaft_column.gd
```

Not one call with a `has_patience` boolean. `FloorRow.set_waiting`'s
`show_direction` is required rather than defaulted for exactly this reason — a
defaulted flag lets a future caller opt out of a rule silently, which is the class
of bug `note_expiry(fare)`'s default caused (`sim/economy.gd:39`).

`tint_key` is the **raw** key from §2.3, and one key is now sufficient for both
channels — which is the whole point of choosing coefficients coprime to 15.
`PersonSprite` applies both modulos, so neither palette size leaves the drawing
layer.

**`_draw()` needs telling, and needs not to be told too often.** `PersonSprite`
renders in `_draw()`, so `show_waiting`, `show_riding` and `recycle` must each end
in `queue_redraw()`. But `BuildingView.refresh()` calls these on every floor and
column **every frame** (`game/game_root.gd:638` → `view/building_view.gd:340-374`),
so an unconditional redraw re-records ~150 canvas items at 60 Hz on the threadless
web export this project ships. Each setter therefore early-outs when nothing that
affects the drawing has changed. **The key is
`(quantised_fraction, glyph, tint_key, size)` — all four:**

- **`size`**, because the car cell is a function of capacity (§4.2: 40 → 36.73 →
  30.46) and capacity changes mid-run when "Bigger Car" is bought. A rider aboard
  across that purchase is called with byte-identical arguments; without `size` in
  the key the setter early-outs and that rider keeps a 40-wide badge in a 30-wide
  slot, overlapping its neighbour until delivery.
- **`quantised_fraction`**, not the raw float. `GameState._expire` decays every
  waiting passenger every tick (`sim/game_state.gd:413-425`), so a raw fraction
  changes at 20 Hz and the early-out never fires for anyone waiting. The bar is 22
  units tall, so `round(fraction * 22)` is the resolution the drawing can actually
  show: a waiting sprite then redraws ~22 times across its whole patience life
  instead of ~900.

Riders go to zero redraws and waiting sprites drop from 60 Hz to ~22 total, which
is what makes "the steady-state redraw rate is near zero" true. Said of the
unquantised key it would have been false — 60 Hz to 20 Hz is an improvement, not
a near-zero.

**Pre-`call_direction`, a waiting person draws no badge at all** — not an empty
one. `FloorRow.CALL_UNKNOWN` is the empty string today because "the chip's colour
already carries patience" (`view/floor_row.gd:26-30`); once the badge is a filled
`BADGE_BG` shape, an empty one is a blank dark box — the "reads as an error state"
outcome that comment exists to avoid. `tests/test_board_input.gd:379-383` pins
`label_text() == ""` and still passes; §7 adds the badge-not-drawn assertion it
cannot make.

## 3. The hall

The packing rule does not change. `ChipGrid`'s `floor(sqrt(n))` shape, its centred
short last rank, and its refusal to floor a too-small area at one rank are kept
verbatim. What changes is that **the cell stops being square**: `SIZE: float`
becomes a cell `Vector2`, threaded through `columns_for`, `rows_for` and
`position_of`.

`columns_for` and `rows_for` add `GAP` internally (`view/chip_grid.gd:52-56`), so
they take the **cell**, never the pitch. §4.1 narrows the strip from 176 to 144 to
buy the shafts their width, so it now runs `SPRITE_X = 68` to `STRIP_RIGHT = 208`
— **140 units** — on a 120-unit row:

```
columns_for(140, 20) = (140 + 4) / (20 + 4) = 6
rows_for (120, 40)   = (120 + 4) / (40 + 4) = 2
shape(12, 6, 2)      = 6 x 2                = 12
    rank fits: 6*20 + 5*4 = 140 <= 140      block fits: 2*40 + 1*4 = 84 <= 120
```

**All twelve still fit — but the rank fills the strip exactly**, 140 into 140,
where the old 172-unit strip had 32 units to spare. That is the price of §4.1's
width, and it is a real constraint rather than a comfortable one: **any later
increase to the person cell or `GAP` drops the hall to five columns and ten
people**. §7 pins the equality so the next change to either constant fails loudly.
`MAX_INDIVIDUALS = 12` has been effectively 10 since the 30-unit square met the
88-unit row (`columns_for(172) = 5`, `rows_for(88) = 2`, `shape(12, 5, 2)` → 5 × 2).
The constant becomes true for the first time, on every floor. A third rank is not
available (`rows_for(120, 40) = 2`) and is not wanted — 12 is the cap.

## 4. The car

### 4.1 It gets bigger, on both axes

At 150 × 84 nothing here fits legibly: two ranks of riders leave a badge of ~16
units, which is font 13 and **7.1 pt** at the 0.546 iPhone scale — below the
~13 pt the UI spec spent a page of shaft paging to buy
(`2026-08-02-ui-design.md:186-192`), and near the ~6 pt it explicitly rejected.

Both board constants move:

```
FLOOR_HEIGHT       88 -> 120        car height  84 -> 116
SHAFT_WIDTH       160 -> 230        car width  150 -> 220
FloorRow.STRIP_WIDTH 176 -> 144     column     156 -> 226   (SHAFT_WIDTH - 4)
  => SHAFT_AREA_X   240 -> 208                 car = column - 6
```

**Height is cheap.** The board is 1184 tall (1280 less the 96-unit HUD), so rows
on screen go 13.5 → 9.9. The board already scrolls and a base run caps at 10
floors, so this costs about one row of scrolling at the cap and nothing before it.

**120 rather than 112, for one reason:** a font-24 line box needs a 30-unit badge,
and two ranks then need `2 + 8 + 52 + 52 = 114`, which fits a 116-unit car. At 112
the car is 108, the badge falls to 27, and the font to 21 — which is the trap §4.3
exists to avoid.

**Width is derived from the DEVICE board, not the canvas — see §4.1.1.** The
strip yields 32 units to the shafts so the column can be 230 and still leave two
columns on a phone:

```
                       device (688)      headless (720)
shaft viewport         688 - 208 = 480   720 - 208 = 512
visible_shafts()       int(480/230) = 2  int(512/230) = 2      <- they AGREE
slack beyond 2 columns 20 units          52 units
```

This **supersedes** the 160-unit decision at
`2026-08-02-ui-design.md:182-183,186-192` rather than contradicting it: that
decision chose three columns over five to make a two-digit seat legible, and this
extends the same reasoning one step further, for the same reason, at the same kind
of cost.

### 4.1.1 The canvas is not the board, and this rule is why

Three review rounds each broke on the same mistake in a new place: **a number
derived against one surface and tested against another.** The third instance was
the board's own width, and it is the reason the numbers above are what they are.

`game/game_root.gd:290` sizes the board `size.x - _safe.x - _safe.z`, and
`SafeArea.insets` floors **both** side insets at `CORNER_MARGIN = 16`
(`view/safe_area.gd:21,40-44`) whenever a safe rect is reported at all — pinned by
`tests/test_safe_area.gd:32-38` for a full-width rect. So:

| | canvas | **device** |
| --- | --- | --- |
| board width | 720 | **688** |
| board height | 1184 (1280 - 96 HUD) | **~1050** |

`insets` returns `Vector4.ZERO` only for a zero-size window — the headless case —
so **the suite runs on the canvas and the game runs on the board.** Two
consequences that were wrong in earlier drafts of this spec:

- **Today's board shows TWO shaft columns on a phone, not three.**
  `int(448/160) = 2`. The UI spec's "three columns" has always been a
  desktop-only figure, and an earlier draft of this spec priced its cost against
  it. The real change here is 2 -> 2: **no column is lost at all.**
- **`SHAFT_WIDTH = 240` would have shipped ONE column** (`int(448/240) = 1`),
  leaving 212 units of viewport the pager cannot reach — while
  `assert_eq(visible_shafts(), 2)` passed green headless. 240 tiles 480 exactly,
  so it had no slack for any inset whatsoever.

**Rule, and it applies to every number in this document:** a geometric claim is
derived against the device board and tested against a non-zero inset. §7 adds the
inset test that would have caught this.

Vertically the same correction applies: rows on screen go `1050/88 = 11.9` to
`1050/120 = 8.7`, so a 10-floor run plus its ghost band (11 rows) stops fitting
without scrolling. See the cost list.

The full cost list, so none of it is discovered later:

- **The people strip narrows 176 → 144.** All twelve waiting still fit, but
  exactly (§3) — the slack is gone.
- **No shaft column is lost.** On device it is 2 before and 2 after (§4.1.1); the
  "3 → 2" an earlier draft advertised was measuring the canvas. Eight shafts is
  four pages rather than three, because `max_scroll` counts slots against visible
  columns and the column got wider.
- **The pager readout appears one shaft earlier.** `game/game_root.gd:574` hides
  it when `max_scroll() == 0`, and `max_scroll = min(owned+1, 8) − visible_shafts`
  (`view/building_view.gd:312-315`). No test pins it today.
- **Scrolling, worst case.** At the 10-floor base cap (11 rows with the ghost) a
  device board of ~1050 goes from fitting to needing ~2.3 rows of scroll. **At the
  prestige ladder's 20-floor cap it is worse**: ~7.5 rows of scroll today against
  ~11.1 after, roughly 3.6 more. §10 verifies at 20 floors, not only 10.

What the two axes buy together is §4.3: **13.1 pt digits at every capacity from
4 to 12** — the UI spec's own precedent, held rather than spent.

### 4.2 The layout

```
┌─────────────────────────────────────────────┐  y 2   pip strip, 8 tall, inset 8
│ ▓███▓ ▓███▓ ▓███▓ ▓███▓ ▓░░░▓ ▓░░░▓         │        one track rect PER PIP
│                                             │
│   ( 9 )    ( 3 )    ( 11 )    ( 2 )         │  y 10  back rank badge, 30 tall
│     ●        ●        ●         ●           │  y 40  back rank figure, 22
│                                             │
│   ( 3 )    ( 7 )    ( 7 )     ( 5 )         │  y 62  front rank badge, 30
│     ●        ●        ●         ●           │  y 92  front rank figure, 22
│    ███      ███      ███       ███          │        feet at y 114
└─────────────────────────────────────────────┘  y 116
```

Vertical is fixed and capacity-independent, and the 2-unit inset is **in** the
sum, not additional to it:

```
inset 2 + pips 8 + band 52 + band 52 = 114   <=  116     2 units spare
band = badge 30 + figure 22
```

Horizontal follows capacity. **The front rank takes the extra rider** at odd
capacities, and the **two-rank composition's bounding box is centred** — not the
front rank alone, which is what pushed the offset back rank outside the car:

```
ranks = 1 if capacity <= 5 else 2
front = capacity if ranks == 1 else ceil(capacity / 2)
back  = capacity - front
cell  = min(CELL_MAX 40, ...)      # offset-aware, below
pitch = cell + GAP 4
back rank is offset +pitch/2 from the front rank's origin
```

**The cell budget must include the offset**, or the back rank leaves the car:

```
one rank : cell <= (220 - GAP*(front-1)) / front
two ranks: cell <= (220 - GAP*(front-1) - GAP/2) / (front + 0.5)
```

Verified at every capacity — `left` and `right` are the composition's bounds
inside the 220-unit car, and `w-font` is the font the cell width alone would
allow, shown so the height-limit claim is checkable rather than asserted:

| cap | ranks | front | back | cell | left | right | w-font | font | pt |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | 1 | 4 | 0 | 40.00 | 24.0 | 196.0 | 32 | 24 | 13.1 |
| 5 | 1 | 5 | 0 | 40.00 | 2.0 | 218.0 | 32 | 24 | 13.1 |
| 6 | 2 | 3 | 3 | 40.00 | 35.0 | 185.0 | 32 | 24 | 13.1 |
| 7 | 2 | 4 | 3 | 40.00 | 24.0 | 196.0 | 32 | 24 | 13.1 |
| 8 | 2 | 4 | 4 | 40.00 | 13.0 | 207.0 | 32 | 24 | 13.1 |
| 9 | 2 | 5 | 4 | 36.73 | 10.2 | 209.8 | 29 | 24 | 13.1 |
| 10 | 2 | 5 | 5 | 36.73 | 0.0 | 220.0 | 29 | 24 | 13.1 |
| 11 | 2 | 6 | 5 | 30.46 | 8.6 | 211.4 | 24 | 24 | 13.1 |
| 12 | 2 | 6 | 6 | 30.46 | 0.0 | 220.0 | **24** | 24 | 13.1 |

Capacities 10 and 12 touch the car edge exactly; that is inside the car, and the
car is itself inset 3 units within its column.

**Capacity 12 is the tight one and must be measured, not assumed.** Its
width-derived font is exactly 24 — `int((30.46 − 4)/1.1) = int(24.05)` — so it
clears by 0.05 units against a nominal 1.1-em two-digit advance. §7's measurement
test exists for precisely this row. If a real `Font.get_string_size` disagrees,
the stated fallback is to cut the badge's horizontal padding from 2 units a side
to 1, which buys ~2 units; failing that, capacities 11–12 take font 23 (12.6 pt)
and §4.3's table records it.

**Odd capacities are pinned conservatively, deliberately.** At odd capacity the
back rank is one cell shorter, so it ends *inside* the front rank and the
composition is the front rank alone — the offset costs nothing. The budget still
applies the two-rank formula (capacity 9 gets 36.73 where 40 would fit). Harmless,
because the font is height-limited either way, and one formula is worth more than
1.5 units of cell.

**At capacity ≤ 5 there is one rank** and the upper band stays empty: the car looks
emptier when it is emptier. The half-pitch offset puts a back figure between two
front badges rather than directly behind one.

The first draft deleted a `back_cols = front_cols − 1` rule on the evidence that
"at pitch 20 a seventh offset slot spanned x 130–146 inside 150". That was true of
a 16-unit cell in a car with slack, and does not transfer to a cell formula that
saturates the width by construction. The rule is not restored — the **budget** is
what fixes it, and the offset is now paid for rather than assumed free.

### 4.3 The badge is two digits, at the spec's own point size

A rider's badge carries the **destination floor**, routinely two digits: the
prestige ladder is shipped and runs a building from 10 to 20 floors
(`sim/meta.gd`), so floors 10–19 ride cars today. This is not the deferred
destination-entry upgrade — §9's "sized for one glyph" is true of the **waiting**
badge only.

The badge is the full cell wide and **30 units tall**, so the font is bounded by
its line box (`~1.25 × font`) at **24** — exactly today's `PassengerSprite.FONT`,
and **13.1 pt** at 0.546.

**This is the point of the resize, and the first version of it got the trade
backwards.** At a 108-unit car the badge is 27, the font 21, and 11.5 pt — so the
plan would have paid a shaft column to make digits *12% smaller* than they are
today across capacities 4–8, where most play happens. The honest ledger:

| | today | this design |
| --- | --- | --- |
| digit size | 13.1 pt, capacities 4–8 only | **13.1 pt, capacities 4–12** |
| riders drawn as figures | capacity ≤ 8, text above | **every capacity** |
| capacity legible | ≤ 8, then text only | **every capacity** (§4.4) |
| glyph contrast | `INK_ON_LIGHT` on the ramp, 5.63:1 worst | `CREAM_PALE` on `TEAL_INK`, **10.40:1** |

The font is still *checked* rather than assumed: §7 measures a two-digit string
with `Font.get_string_size` against the **narrowest** cell — 30.46 at capacity 12
— and asserts it fits with padding. §4.2 states what happens if it does not.

### 4.4 The pips are the seat rack, flattened

One pip per seat, lit for a rider and hollow for a free seat. Capacity runs 4 to
12 — small and discrete — so lit-versus-hollow answers *"does one more fit"*
**exactly**, which is the argument the seat rack was built on and the reason this
is not a needle or a continuous bar.

**The track is per-pip, not a continuous bar.** Each pip is its own
`PERSON_BAR_TRACK` rect with car body showing in the 3-unit gaps; a lit pip is
`PIP_LIT` inset 1 unit inside its track. A continuous track was the first draft's
answer and it fails the one job pips have: two adjacent hollows on a shared track
merge into one dark band, so free seats stop being individually countable.

```
strip width = 220 - 16 = 204,  gap 3
capacity  4 -> pip 48.75 wide
capacity 12 -> pip 14.25 wide
```

**Pips are `draw_rect` calls, not nodes** — two rects per pip (track, and the lit
fill inset 1 unit) inside `PersonSprite`'s sibling `_draw()` on the car. As nodes
they would take a car from `3 x capacity` to `4 x capacity`, which is a real
change to §8.5's ledger; as draw calls the car's node count *falls*, because the
seat `ColorRect`s go away entirely.

Contrast, all measured with `tests/test_palette.gd`'s formula:

| pair | ratio | |
| --- | --- | --- |
| `PIP_LIT` vs its track | **15.19:1** | the lit/hollow read |
| track vs `CAR` | **5.21:1** | a hollow pip against the car body |
| *(counterfactual)* `SEAT_FREE` vs `CAR` | 1.92:1 | why the track exists |

That last row is today's `SEAT_FREE` (`TEAL_DARK`) on `CAR` — the pairing a naive
"hollow pip = darker teal" would have inherited, far under the 3:1 §5 applies to a
graphic element, on an element 15 units wide. `SEAT_FREE` is deleted by §5, so the
figure is a counterfactual, not a property of anything this design ships.

`free_slots_shown()` and `seats_taken()` keep their names and count pips. And
because the strip is independent of the figures, **capacity is legible at every
capacity** — the "Bigger Car" upgrade stops buying something invisible above 8.

### 4.5 The height guard has three bands, not one

`_draw_header_only` (`view/shaft_column.gd:216-223`; `_header_for` is `225-238`) is kept as a guard on a
public view boundary — `set_riders` is called with whatever size the car has, and
`tests/test_board_input.gd:451` and `:459` force `size.y = 18.0`. It needs **three**
bands, because one rank and two ranks have different heights:

| car height | behaviour |
| --- | --- |
| `< 62` | no rank at all — header line only; pips still draw |
| `62 ≤ h < 114` | **one rank of `slots` riders** (below); the header carries the rest |
| `≥ 114` | ranks by capacity, per §4.2 |

**Band 2's rank is sized by width, not by capacity**, or it overruns: one rank of
`capacity` cells at capacity 12 gives `cell = (220 − 44)/12 = 14.7`, narrower than
the 14-unit figure and far under a two-digit badge. So:

```
slots = largest n <= capacity with (220 - GAP*(n-1))/n >= CELL_MIN 30
      = 6 at CELL_MIN 30       # (220 - 20)/6 = 33.3 >= 30; 7 gives 28.9
riders beyond `slots` are counted in the header line, exactly as today's
_header_for already does ("7/12  3 7 7 +4")
```

**Where the header goes when pips are present.** Today it is anchored at the car's
top (`view/shaft_column.gd:123-129`), which is where §4.2 now puts the pip strip.
In bands 1 and 2 the header sits **below the pips**, at y 12; in band 1, if the car
is too short for both, the pips win and the header is not drawn — occupancy is
exact and destinations are the thing being given up. At the band's lower edge
(exactly 62) there is no room for a header at all, which is the same rule.

`62 = 2 + 8 + 52` (inset, pips, one band); `114` is §4.2's full budget. The first
draft named only 62, which would have drawn two ranks into a box that cannot hold
them and run the second rank up to 48 units out of the bottom.

At a 120-unit row none of the first two bands is reachable in production. They are
guards, not representations — which is why they are kept where §1.1's crowd-bar
tier is deleted.

**The pips keep drawing in every band.** This changes
`tests/test_board_input.gd:453`, which asserts `free_slots_shown() == 0` in the
short-car case; the assertion becomes the pip count.

### 4.6 What is kept, and what is lost

**Kept:** the translucent doors slide over the car and riders stay legible while
shut (§3.7); the exact per-rider destination at every capacity; the exact
occupancy at every capacity; the 13.1 pt digit.

**Lost, deliberately:** *"a passenger looks and packs identically before and after
boarding"* (§3.3) — standing in ranks is not a sqrt-balanced grid. What survives is
the half that carries the meaning: **a person looks the same everywhere**. And
**one visible shaft column** (§4.1), which is the price of the rest.

## 5. Colour

New **roles** only; every one points at a pigment already in `palette.gd`, except
the skin and shirt sets, sampled from `dir3_in_game.png` as part of this work.
Nothing outside `palette.gd` names a pigment.

| role | pigment | requirement |
| --- | --- | --- |
| `PERSON_SKINS` | three, sampled | ≥ 1.2 from each other, and from `APP_BG`, `CAR` and every shirt |
| `PERSON_SHIRTS` | five, sampled | ≥ 1.2 from each other, and from `APP_BG` and `CAR` |
| `PERSON_LEGS` | `BROWN_DARK` | 5.21:1 on `CAR` |
| `BADGE_BG` | `TEAL_INK` | 3.57:1 on `CAR`, 9.87:1 on `APP_BG` |
| `BADGE_INK` | `CREAM_PALE` | 10.40:1 on `BADGE_BG` |
| `PERSON_BAR_TRACK` | `BROWN_DARK` | the patience track **and** each pip's track |
| `PIP_LIT` | `CREAM_PALE` | 15.19:1 on the track |
| `PIP_FREE` | the pip's own track | 5.21:1 on `CAR` |

`SEAT_FREE` is **deleted**, not re-pointed: it named a seat, and there are no seats.

Every figure lands on **two** grounds — cream in the hall and mid teal in the car —
so the shirt and skin requirements name both. 1.2 rather than 3:1 because these are
decorative fills, not information: the threshold is the one
`tests/test_palette.gd:127-130` already uses for the idle bar. A stated requirement
with no test is the pattern §5.1 exists to bury, so §7 tests these.

### 5.1 Why the patience bar gets its own track

The first draft put the person's bar on `BAR_TRACK`, the gutter tenant bar's
ground. Measured with `tests/test_palette.gd`'s own formula:

| fill vs `BAR_TRACK` (`d5bd92`) | ratio |
| --- | --- |
| `PATIENCE_LOW` (`e07a52`) | 1.63:1 |
| ramp midpoint | 1.38:1 |
| `PATIENCE_OK` (`9ec46f`) | **1.09:1** |

`PATIENCE_IDLE` measures 1.57:1 against the same track, and
`tests/test_palette.gd:129-130` asserts `> 1.2` for it with the comment *"the idle
bar must be distinguishable from its track"*. **A full patience bar would read
quieter than the bar that means nobody is here**, and below the floor this suite
already set for a deliberately inert element. The ramp test §7 mandates could not
have passed at any honest threshold.

On `PERSON_BAR_TRACK` (`BROWN_DARK`, `2b1a0c`) the ramp's **worst** point over 21
samples is **5.63:1** (at red), rising to 8.42:1 at green, and the track reads
5.21:1 against `CAR`.

The gutter tenant bar keeps `BAR_TRACK` — it drains by *height* in a fixed
position, so its boundary is not the whole encoding. The person's bar is the only
patience signal a stranger carries, on a 4 × 22-unit target.

**This is the principle, and it is why it is written down.** `AFFORD_OFF` was tuned
against `APP_BG` while drawn on `GHOST_BG`, measured 2.03:1 in its test and 1.29:1
where it landed, and "+ BUILD FLOOR $200" was invisible while the suite stayed
green. **A colour is tested against every surface it lands on, or the test is worse
than none** — and the first draft of this spec broke that rule on the two surfaces
it invented, then the second broke it again on the eight colours it adds.

## 6. Code shape

| file | change |
| --- | --- |
| `view/person_sprite.gd` | **new.** Replaces `passenger_sprite.gd`. One `Control` that `_draw()`s badge, figure and bar, plus the hall's triangle; one `Label` child for the car's digits. Keeps `label_text()` and `recycle()`. Setters `queue_redraw()` only on change (§2.4). **Exposes `parts() -> Dictionary`** (badge / figure / bar / head / torso rects) and **`redraw_count() -> int`**, which are what §7.9-7.15 assert against — `_draw()` consumes exactly those rects and nothing else. |
| `view/car_rack.gd` | **new**, `RefCounted`, no scene tree. Given rider count, capacity and car size, returns rank slots and per-pip rects, or which guard band applies (§4.5). Pure geometry, unit-tested headlessly like `ChipGrid`. |
| `view/chip_grid.gd` | `SIZE: float` → cell `Vector2` on `columns_for`, `rows_for`, `position_of`. The shape rule is untouched. |
| `view/shaft_column.gd` | seat rack → pips + ranks, via `CarRack`. `SEAT_SIZE`, `SEAT_FREE`, `SEAT_FONT` deleted. Query methods keep their names. |
| `view/floor_row.gd` | new cell, `PersonSprite`, drawn arrow, no badge on `CALL_UNKNOWN`. Delete the dead `SPRITE_PITCH := 14.0` (`view/floor_row.gd:33`), flagged as open cleanup in two prior reviews. |
| `view/building_view.gd` | `FLOOR_HEIGHT` 88 → 120, `SHAFT_WIDTH` 160 → 240. |
| `game/util/palette.gd` | the roles in §5; `SEAT_FREE` removed. |
| `view/passenger_sprite.gd` | **deleted**, with its `.uid`. |

**Every live `PassengerSprite` type reference**, which becomes a *parse* error
rather than a failing assertion when the `class_name` goes:
`tests/test_board_input.gd:379`, `:397` (`var sprite: PassengerSprite = …`), and
`view/shaft_column.gd:26` (`SEAT_FONT := PassengerSprite.FONT`).

**Every live `ChipGrid.SIZE` reference:** `view/chip_grid.gd:27,53,56,66,67,69,70`;
`view/passenger_sprite.gd:20,21,22` (file deleted); `view/shaft_column.gd:25`;
`tests/test_chip_grid.gd:74,75,80,81,100,107,109`. (An earlier draft also listed
`view/shaft_column.gd:26`; that line is `SEAT_FONT := PassengerSprite.FONT` and
contains no `ChipGrid.SIZE`. It is deleted regardless, but the list is meant to be
exact.)

**Docstrings inside the files above that state what this change falsifies** — the
prose is not covered by "the shape rule is untouched":

- `view/floor_row.gd:19-23` — ties the one-glyph rule to "the original 14-unit pitch"
- `view/floor_row.gd:34-35` — "the same square… a passenger looks the same before
  and after boarding", the invariant §4.6 drops
- `view/floor_row.gd:99-100` — "Rows are a fixed **88** units now"
- `view/chip_grid.gd:4-9` — "balanced block of **squares**… One rule for the hall
  and for the car"; `:48-51` — "columns and rows of `SIZE`… a chip is 30"
- `view/shaft_column.gd:16-24` — "The car is a rack of seats"; `:44-46` — "Opaque
  panels would hide the **seat rack**"
- `view/building_view.gd:28-33` — the `SHAFT_WIDTH` docstring, every clause of
  which becomes false: "Three columns across the 480-unit viewport", "At 160 the
  column draws at 156 (85pt) and a seat is 34, which can", "eight shafts is three
  pages rather than two". This is the single most load-bearing prose the change
  invalidates — it is the rationale §4.1 supersedes
- `view/building_view.gd:36-38` — the `FLOOR_HEIGHT` docstring: "88 units is 48pt
  at the 0.546 iPhone scale — the same touch floor every other control uses". At
  120 that is 65.5 pt
- `view/building_view.gd:219` — "All **five** visible positions", already stale,
  becomes two
- `view/floor_row.gd:38-39` — `STRIP_WIDTH := 176.0` and the "fixed 176 units"
  argument at `docs/…ui-design.md:163-165`, which §4.1 revises to 144

**`.uid` files:** add `view/car_rack.gd.uid`, `tests/test_car_rack.gd.uid`,
`tests/test_person_sprite.gd.uid`; delete `view/passenger_sprite.gd.uid`. Commit
`b9da5c6` exists because this was missed once already.

**A testable seam, because the drawing is not observable.** `_draw()` output
cannot be inspected headlessly and Godot exposes no "is a redraw queued" query, so
five of §7's tests would be unwritable against a bare `_draw()`. The codebase has
already solved this — `view/day_sparkline.gd:13` names `bar_heights()` and
`segment_shares()` as "the testable seams; `_draw()` reads" — and `CarRack` gets
the same treatment for the car. `parts()` and `redraw_count()` give the person it
too. Without them §7.9-7.15 are aspirations, not tests.

**Input bounds, geometrically rather than by special case.** `capacity` cannot
exceed 12 in the shipped game (`CAPACITY_BASE 4` + `max_level 8`), but
`set_riders(riders, capacity)` is a public view boundary and "cells keep
shrinking" is not a guarantee — at capacity 25 the cell drops below the 14-unit
figure, and above ~72 the pip width goes negative. So both representations
degrade on a **measured floor** rather than on a capacity number:

```
rank draws while cell >= CELL_MIN 30      else -> header line (§4.5's band 1)
pips draw while pip_w >= PIP_MIN 6        else -> the header's "n/capacity" count
capacity <= 0            -> no pips, no rank
riders.size() > capacity -> lit pips clamp to the pip count; the rank draws what fits
```

At capacity 12 both hold comfortably (`cell 30.46 >= 30`, `pip 14.25 >= 6`). The
rule needs no upper bound because it is stated in units, not seats — which is the
only form that stays true if capacity is ever raised.

**Node budget: still inside §8.5's provision, but it does move.** A person is a
`Control` + `Label` where it was a `ColorRect` + `Label` — flat per person — but §3
raises drawn people per row from 10 to 12, so +4 nodes per row. §8.5 provisions 12
per row at 3 nodes each (`2026-08-01-elevator-incremental-design.md:673-694`), so
the conclusion holds and the first draft's "the budget does not move" did not.

## 7. Tests

The gate is the whole suite green:
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`, non-zero
exit on any failure. §10's device checks are additional, not a substitute.

**New — `tests/test_board_geometry.gd`. This is the test the whole review was
missing**, and it is listed first because it guards the class of bug that broke
three rounds running: a number derived on the canvas and asserted on the canvas.

1. `visible_shafts()` **against a non-zero safe area**. Drive `BuildingView` at
   the device board width (720 − 2 × `SafeArea.CORNER_MARGIN` = 688), not the
   canvas 720, and assert **2**. At `SHAFT_WIDTH = 240` this reads 1 while the
   headless `assert_eq(…, 2)` reads green — which is exactly how the first draft
   of §4.1 shipped a one-column board on paper.
2. The same at the canvas width, also 2 — the two surfaces must **agree**, and
   §4.1 chose 230 over 240 partly to make them.
3. Rows on screen at the device board height, against §4.1's scroll claims at both
   the 10-floor and 20-floor caps.

**New — `tests/test_car_rack.gd`:**

1. One rank at capacity ≤ 5, two above; the front rank takes the extra at odd
   capacities.
2. The composition is centred, and the back rank is offset half a pitch.
3. `cell` matches §4.2's table at **every capacity 4–12** — not a sample. Capacity
   10 is explicitly included: it is the case the first draft's formula overflowed
   by 15 units while appearing in no test.
4. **Nothing is positioned outside the car rect at any capacity 4–12**, likewise
   not a sample of two.
5. A two-digit string at font 24 fits the **32**-unit cell (capacity 12) with
   padding, measured with `Font.get_string_size`. §4.3 rests on this.
6. Pips number exactly `capacity`; lit pips exactly `riders.size()`; each pip has
   its own track rect with a gap between (§4.4).
7. All three height bands (§4.5): `< 62` header only, `62 ≤ h < 114` one rank of
   exactly `slots` riders with the remainder in the header, `≥ 114` by capacity.
   Assert the band-2 **cell** too, not just "one rank" — the literal reading of an
   earlier draft put 12 cells in 220 units and overran every badge.
8. Header-vs-pip placement in bands 1 and 2 (§4.5): the header sits below the
   pips, and is dropped rather than overlapping them when the car is too short.
9. The geometric floors in §6: the rank stops at `cell < 30`, the pips at
   `pip_w < 6`, `capacity <= 0`, and `riders.size() > capacity`.

**New — `tests/test_person_sprite.gd`:**

9. Badge, figure and bar fit the cell and do not overlap, in both cells.
10. The figure is **centred in its figure band** in both cells — x = 1 in the hall,
    `(cell − 14)/2` in the car (§2.2).
11. The tint key is stable for a given passenger and independent of pool slot.
12. **Spread**: over inbound, outbound and interfloor trips across floors **0**–20
    — floor 0 included, because the lobby-source substitution `(0, G, 0)` is the
    degenerate case and both previous hash failures were degenerate substitutions —
    all five shirts and all three skins occur.
13. A rider has no patience bar; a waiting passenger has one.
14. `CALL_UNKNOWN` draws no badge at all.
15. A setter called twice with identical arguments does not request a second
    redraw — **and one called with a changed argument does**, including a changed
    `size` alone (§2.4). The suppression is the risky half; testing only that it
    suppresses is how a stale badge ships.

**Changed:**

16. `tests/test_chip_grid.gd` — every packing assertion kept, retargeted to the
    cell. **Plus the hall equality from §3**: `6*20 + 5*4 == 140 == STRIP_RIGHT −
    SPRITE_X`, so the next change to the cell or `GAP` fails loudly instead of
    silently dropping the hall to ten people.
17. `tests/test_board_input.gd` — `label_text()` reads the badge; seat assertions
    read pips; `:453` becomes the pip count (§4.5); **`:143`
    (`assert_eq(view.visible_shafts(), 3, …)`) is a hard failure and must become 2**;
    `:445`'s message string "two digits fit on a 34-unit seat" passes but reads
    false. Plus **new**: twelve waiting all drawn, and a two-digit rider badge at
    font 24.
18. `tests/test_palette.gd` — add `BADGE_INK`/`BADGE_BG`; `BADGE_BG` vs `APP_BG`
    and `CAR`; the ramp vs `PERSON_BAR_TRACK` across all 21 samples; `PIP_LIT` vs
    track; track vs `CAR`; **and each shirt and skin against `APP_BG`, `CAR`, each
    other, and skin-vs-shirt** (§5). **Two existing tests pin a pairing this change deletes**, and both must go, not
    just the obvious one: `tests/test_palette.gd:115-123` (the ramp-carries-its-
    label test, whose "PassengerSprite draws INK_ON_LIGHT on top" comment is at
    `:116`), and `tests/test_palette.gd:102-111`
    (`test_the_fill_ink_beats_the_alternative_on_every_fill_it_lands_on`), whose
    fill list is `[CAR, PATIENCE_OK, PATIENCE_LOW]`. After this change no ink lands
    on the ramp at all — only the `CAR` entry stays live, because the header
    fallback still draws `INK_ON_LIGHT` there. Drop the two patience fills, keep
    `CAR`.
19. **Files that hard-code the row height**, which will not fail but will silently
    drift to testing a height the game no longer uses:
    `tests/test_coords_scroll.gd:10` and `tests/test_pan_gesture.gd:9`, both
    `const H := 88.0`. Re-derive or state why 88 is still the right fixture.
    **`tests/test_gesture.gd` is NOT one of them** — an earlier draft claimed its
    "14.8 at 88" bound becomes 56; 14.8 is half of that file's own `const H := 29.6`
    (`tests/test_gesture.gd:5`), it never reads `FLOOR_HEIGHT`, and "fixing" it
    would replace a historical worst-case bound with one 3.8× looser.

## 8. Deltas against the UI design spec

Every surface that must change, file and line, verified by grep:

| surface | line | why |
| --- | --- | --- |
| `2026-08-02-ui-design.md` §3.1 coordinate table | 135 | `\| 240–720 \| 480 \| shaft viewport: three columns on a 160-unit pitch \|` — the authoritative coordinate row |
| same §3.3 | 182-183 | "Columns sit on a **160-unit pitch**… drawn and hit-tested at **156 units — 85pt**" |
| same | 186-192 | the five-on-96 rationale and "three pages rather than two" — §4.1 supersedes, one step further, same reasoning |
| same | 167-180 | "people are squares, packed by one rule everywhere"; "the same rule lays out a car's seats" is the half §4.6 drops |
| same | 158 | the vacant-floor re-lease price, gone from code already |
| same §3.4 | 209 | `max_scroll = … # visible_shafts = 3` → 2 |
| same | 213 | "at `owned = 8`… the pager caps at 5" → `min(9,8) − 2 = 6` |
| same | 215 | "**All three visible positions** still draw a placeholder" → two |
| same §3.5 | 222-249 | **deleted, not amended** — the tier cannot fire. Line 225's 12-cap folds into §3.3 |
| same | 239 | "**This replaces spec §8.5's crowd-bar trigger**" — see the warning below |
| same §3.7 | 307 | "hide the seat rack" → the figures; the argument is unchanged |
| same §8 item 7 | 565-566 | the density tier's `N >= 29` derivation, which goes with §3.5 |
| `2026-08-01-…-design.md` §8.5 | 673-694 | see the warning below |
| same §3.3 | 163-165 | "The people strip is a **fixed** 176 units" — §4.1 makes it 144 |
| `2026-08-01-…-design.md` | 599 | the module inventory line `view/ building_view, shaft_column, elevator_car, passenger_sprite,` — the file this plan deletes. (§8's "clean" claim was true for the *class name* and false for the *file*.) |
| `backlog.md` | 24 | "one square, or the seat rack stops telling the truth" |
| same | 374 | the destination-entry entry: "already anticipated in `passenger_sprite.gd`" — the file is deleted **and** the anticipation inverts, since the hall badge now draws a triangle rather than rendering whatever string it is handed |
| same | 376-378 | "chips would need to show a floor rather than an arrow, which is a width change the strip has to absorb" — §4.3 changes the answer for the *riding* badge |
| same | 573 | "more than one **seat**" — freight, deferred in §9 |
| same | 576 | "`ChipGrid` draws more than one square" |
| `2026-08-02-call-direction-upgrade-design.md` | 88 | "`view/passenger_sprite.gd` — unchanged. `show_as(fraction, text)` already…" |
| `codemaps/view.md` | 53, 54, 59 | `SEAT_SIZE`, `SEAT_FONT`, the `PassengerSprite` section |
| same | 63-64 | the `ChipGrid` section: "`SIZE=30`, `GAP=4`… `columns_for(w)`, `rows_for(h)`" — §6 changes the constant *and* both signatures |
| `codemaps/tests.md`, `codemaps/architecture.md` | — | gain `car_rack`, `test_car_rack`, `test_person_sprite` |

**Deleting §3.5 has a second-order effect that must not be missed.** Line 239 is
the only sentence superseding the *design* spec's §8.5 crowd-bar trigger. Delete
§3.5 wholesale and design-spec §8.5 reverts to authoritatively describing a tier
§1.1 proves cannot fire, plus a node budget derived from it (`675-679`). Either
carry the supersession sentence out of §3.5 before deleting, or give design-spec
§8.5 its own correction.

Checked and clean: `codemaps/data.md`, `codemaps/sim.md`, and
`2026-08-01-elevator-incremental-design.md` for `seat`/`PassengerSprite` (zero hits).

## 9. Out of scope

- **Generated raster art.** The figures are primitives. `PersonSprite` is the seam
  where a texture could replace `_draw()` later.
- **Animation.** Nobody walks, turns, or steps through the doors.
- **Freight and multi-slot occupancy.** Ranks of centred slots are compatible with
  the backlog's freight work and do not attempt it.
- **The destination-entry panel.** It would put a *floor* on a **waiting** badge,
  which is sized for one drawn arrow — two digits is the width change that upgrade
  has to buy. (The **riding** badge already carries two digits; that is §4.3.)
- **Re-tuning for two visible shafts.** §4.1 costs a column and moves when the
  pager appears; whether the 8-shaft cap or the pager wants rebalancing is a
  separate question.

## 10. Verification

Every number here is arithmetic until something renders it. On device, after the
suite is green:

1. **Capacity 4, one shaft** — one centred rank, four fat pips, digits at 13.1 pt.
2. **A rider bound for a two-digit floor** — the case §4.3 exists for, and the one
   no test of `rider_destinations()` can see, because it reads `_listed` and not the
   rendered Label (`view/shaft_column.gd:256-258`).
3. **Capacity 12** — two ranks, twelve 15-unit pips each in its own track, the
   half-pitch offset, and the composition touching both car edges.
4. **The call arrows, at arm's length** — §2.1 replaces a font glyph with a drawn
   triangle; nothing in the suite can tell you whether ▲ reads as distinct from ▼
   at 14 units.
5. **A floor with twelve waiting** — §3's claim that all twelve now fit.
6. **The patience bar** — a fresh green bar and a nearly-expired red one on the
   same screen, both legible against `PERSON_BAR_TRACK`.
7. **Two shafts and the pager** — §4.1's cost, including the readout now appearing
   at `owned = 2`.
8. **A car mid-stop** — doors translucent over figures, riders still legible.
9. **A 10-floor building, and a 20-floor one** — §4.1's scroll cost, at the base
   cap and at the prestige ladder's cap where it is ~3.6 rows worse.
10. **Count the shaft columns on the actual phone.** Two. This is the one check
    that would have caught §4.1.1's CRITICAL, and no headless test can stand in
    for it — the suite runs where the insets are zero.
