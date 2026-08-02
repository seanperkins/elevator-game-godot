# Tap to dispatch, drag to look: the scrolling board

**Status:** agreed, not yet built.
**Reverses:** §3.5 of the UI design spec ("the board never scrolls vertically")
and the geometry that follows from it.

## Why the old rule existed, and why it stops applying

§3.5 rejected vertical scrolling for one stated reason:

> Dispatch is an absolute drag onto a floor's band, so a vertically scrolled
> board can only dispatch to floors currently on screen, and "any floor is one
> short drag away" is the property §2.1's whole input model rests on.

That reasoning is sound **while dispatch is a drag**. It is not a defence of
non-scrolling for its own sake — it is a consequence of the input model. Once
dispatch is a *tap*, the premise is gone and the conclusion goes with it.

Tap-to-dispatch already ships. The drag is currently redundant with it for
anything on screen, so this change repurposes a gesture rather than replacing
one.

## What the old rule was costing

Fitting every floor on one screen forced `h = 1184 / (N + G)`, and everything
below is downstream of that single expression:

| Compromise | Cause |
| --- | --- |
| 29.6-unit rows — **16pt** — at the cap | 40 floors in 1184 units |
| the crowd-bar tier; sprites vanish past 28 floors | rows too short for a 30-unit chip |
| the seat rack collapsing to a text line | cars too short for a rank of seats |
| the re-lease confirm (the one 44pt exception) | a row cannot meet the touch floor |
| the 40-floor cap | a legibility limit, not a design one |
| a basement competing with the tower for rows | one fixed budget of screen height |

A fixed row height removes all six. They are not six problems; they are one
problem counted six times.

## The new model

- **Row height is a constant.** `ROW_HEIGHT = 88` units — 48pt, the same touch
  floor every other control uses.
- **The board scrolls** to whatever does not fit, vertically and horizontally.
- **Tap dispatches** to the floor tapped. **Drag pans.**
- **Floors are signed.** `min_floor` may be negative, which is what makes the
  basement free rather than a fight for rows.

### What is lost, and the answer to each

- **The preview.** A drag showed the rail marker and floor bubble before
  committing. A tap is instant. *Answer:* the target is 48pt rather than 16, so
  the mis-tap it protected against is far less likely; and a wrong dispatch
  costs seconds, not a run.
- **Cancel.** Dragging off the board aborted. *Answer:* re-tap. Cancel existed
  because a 16pt target invited errors.
- **One-gesture reach.** Any floor was one drag away; off-screen floors now need
  pan-then-tap. *Answer:* accepted. It is the price of unbounded height, and it
  is the same trade every map interface makes.

## Order of work

Each step lands green; the game is playable throughout.

1. **`BoardCoords`: fixed height, scroll offset, signed floors.** The one
   transform still has four consumers, which is what makes this survivable. The
   edge table stays — a fixed `h` makes `floor(y/h)` better behaved but not
   exact, and the round-trip guarantee is cheap to keep.
2. **`BuildingView`: lay out from the offset.** Rows positioned by the
   transform, clamped to content bounds. No scrolling input yet.
3. **Input: drag pans.** `Gesture` stops classifying dispatch and starts
   discriminating tap from pan. `ShaftColumn` forwards drags to the board.
4. **Retire what the old constraint forced.** Density tiers, the fit-to-screen
   divisor, and the shaft pager, which horizontal panning replaces.
5. **Basement.** `min_floor` below zero, a dig affordance under the lobby, and
   `DispatchPolicy.LOBBY` stops meaning "the bottom".

Steps 1–3 restore parity. Step 4 is subtraction. Step 5 is the thing this was
all for.

## What must not regress

The board is still bottom-up, and the mirrored-board tests in
`tests/test_board_input.gd` still catch a mirror that is self-consistent across
gesture, rail and car. Scrolling adds an offset to that check; it does not
remove the need for it.
