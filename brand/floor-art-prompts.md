# Floor scenery — image prompts

Seven images: one per tenant kind, plus the vacant shell. Each is the background
of one floor band, drawn **behind** the little people the game draws itself.

Target: **416 × 240 px, ratio 26:15** (2× the 208 × 120 canvas units the region
occupies). See `docs/superpowers/backlog.md` § "A background for every floor" for
where those numbers come from.

No transparency is needed — these are opaque and replace the cream ground
entirely, so there is no chroma key and no despill step.

---

## The contrast rule — relaxed, and why

**This used to be a hard constraint and no longer is.** Every person the game
draws now carries a 1-unit pale outline (`bbf8e62`), so a figure is separated
from a background of ANY luminance — worst case 1.37, swept over every possible
value and pinned by `tests/test_palette.gd`.

That change was made *because of* the first generated image. It scored well on
everything asked of it — 1.736 ratio, 0% of pixels in the old dead band, cream
and rust within a hair of the game's own pigments — and a rust-shirted passenger
still vanished into a rust door at **1.07**. Only two colours in the whole
palette cleared all nine figure colours, so constraining the art meant boxing
every future image into teal-or-tan. Outlining the figures was one draw pass and
freed the art permanently.

**What remains, as guidance rather than law:** keep the composition calm behind
the characters. The outline guarantees they are *visible*; it does not stop a
busy background from being noisy. Large flat areas still read better than
detail, and darks still work best under about a quarter of the frame.

## Shared style block

Paste this above every subject line.

```
Flat 1950s mid-century travel-poster illustration, screen-print look. Bold
simple shapes, hard edges, no gradients, no photorealism, no lighting effects,
no drop shadows, no texture or paper grain. Limited flat colour palette drawn
ONLY from: cream #f7eed1, pale cream #fbf4dc, tan #e7d5ad, teal #649a8c, deep
teal #306b65, near-black teal #1f3f3c, rust #9d4227, light rust #c76d48, gold
#cc9737, vermilion #c4462c, dark brown #2b1a0c.

The image is a BACKGROUND. Composition must be calm and mostly empty, weighted
to the left and bottom, with the centre and upper area left as plain flat cream
so that foreground characters drawn on top remain readable. Prefer large flat
areas over detail, and keep the dark colours to roughly a quarter of the image
or less — the characters stand along the bottom and the picture should stay calm
behind them.

SCALE IS THE THING MOST LIKELY TO GO WRONG. A standing adult is about 37% of
the image height, and everything must be drawn to that. Use these:

  interior door      43% of image height
  bookcase           39%
  filing cabinet     29%
  window sill        24%
  counter top        22%
  desk or table top  16%
  chair seat         10%

Furniture and doors that fill more than about half the frame height are WRONG,
however good they look alone -- the characters stand in front of them and will
look like children.

Wide landscape format, aspect ratio 26:15. Edge to edge, full bleed, no border,
no frame, no vignette.

ABSOLUTELY NO: people, figures, humans, silhouettes of people, text, letters,
numbers, signage with words, logos, watermarks, UI elements, arrows, icons,
sparkles, stars, glints, lens flares, light rays, glow.

It is a side-on cutaway view of one floor of a building interior, as if the wall
has been removed — a flat elevation, straight on, no perspective, no vanishing
point. The floor line runs along the bottom edge.
```

---

**Scale was the first real failure.** The first three generations came back
consistently ~1.4x oversized — apartment doors at 54% of frame height where 43%
is right, office desks at 24% where 16% is. People looked like children standing
in a giant's office. The figures were bumped 7% (26x41 -> 28x44, which is the
most the hall can give without dropping from eight people to three), and the
rest is the table above. **Check a generation against it before accepting.**

**Two artefacts seen so far, both worth pre-empting.** A small four-pointed
white sparkle appears near the lower right of every generation — hence the
negative list above. And a soft diagonal light-ray was baked into the shops
awning, which the "no lighting effects" line was meant to prevent; say it twice
if it recurs.

**Composition that worked:** the shops image weights everything into the left
half and leaves the right as open cream. That is the shape to aim for — the
figures stand along the bottom, spread across the full width, so a subject that
fills the centre (as the apartments doors do) sits directly behind them.

---

## The seven subjects

Append one of these to the style block.

**1. Apartments** (`apartments`)
```
Subject: a residential corridor. Three or four simple panelled apartment doors
in a row along the back wall, each with a small round handle and a plain
doorframe. A low side table with a potted plant near the left. Warm cream walls,
rust-coloured doors.
```

**2. Shops** (`shops`)
```
Subject: a small shopfront. A wide glass display window on the left with two
plain shelves of simple abstract goods — boxes, bottles, rounded forms — and an
open doorway on the right. A flat striped awning in rust and cream above the
window. Teal shop counter.
```

**3. Offices** (`office`)
```
Subject: an open-plan office. Two simple desks in profile with boxy monitors,
a swivel chair, and a tall filing cabinet on the right. A wide horizontal window
band along the back wall showing flat pale sky. Teal desks, gold chair.
```

**4. Gym** (`gym`)
```
Subject: a gym floor. A weight rack with three barbells on the left, a simple
bench in the middle, and a rolled exercise mat leaning on the right wall. A
horizontal mirror strip along the back wall. Rust equipment, teal mats.
```

**5. Law Firm** (`law_firm`)
```
Subject: a formal panelled office. A tall dark wooden bookcase full of flat
uniform book spines along the back wall, a heavy rectangular desk in profile
with a banker's lamp, and a single upholstered armchair. Dark brown panelling,
gold lamp, deep teal chair.
```

**6. Clinic** (`clinic`)
```
Subject: a clinic waiting area. A row of three simple moulded chairs against the
back wall, a low table with a stack of flat magazines, and a reception counter
on the right with a frosted glass panel. Pale cream walls, teal chairs, a small
vermilion cross on the counter front.
```

**7. Vacant — the construction shell** (no tenant)
```
Subject: an unfinished concrete shell. Two bare structural columns, a stack of
three cement bags on the left, a folded step ladder leaning against the right
column, a coil of cable and a small pile of timber on the floor. Exposed
concrete in flat pale tan, no walls, no fittings, no finishes. Sparse and
obviously incomplete.
```

---

## After generating

1. **Downsample to 416 × 240.** Generate large (1024-wide or more) and scale
   down — it averages away any residual edge noise, which is what makes flat
   art key cleanly even when no keying is involved.
2. **Check it is calm, not that it is legal.** The outline handles legibility;
   what it cannot fix is a background so busy that eight people standing on it
   read as clutter. Squint at it.
3. **Put a person on it before committing to the set.** The whole point is that
   figures stay readable; one screenshot with a pale-skinned figure over the
   busiest image settles it faster than any amount of sampling.
4. **Keep the sources.** `brand/art/` is excluded from the export preset
   (`5ab8ac4`), so full-size originals can live there without shipping. Only the
   downsampled 416 × 240 files go anywhere the game imports from.
