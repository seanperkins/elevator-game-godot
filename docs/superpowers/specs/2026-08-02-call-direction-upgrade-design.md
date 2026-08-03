# Call direction visible only after an upgrade

**Status:** agreed, not yet built.
Promoted from `docs/superpowers/backlog.md`, "Call direction visible only after
an upgrade". Delete that entry when this ships.

A waiting passenger always shows an up/down call arrow. This gates that glyph
behind a purchased upgrade: before it, a waiting chip reveals only that someone
is waiting; after it, it shows which way they are going.

It is the reader half of the destination-entry idea and sharpens the same
information asymmetry — until you pay, a hall call tells you *that* someone is
there, not *where they are headed*.

---

## 1. Presentation only

No sim behaviour changes. `Passenger.direction()` (`sim/passenger.gd:49`) keeps
working exactly as now and every dispatch policy keeps reading it. The only
change is that the **view stops rendering it** until the upgrade is installed.

This keeps the layering rule intact: `view/` reads `upgrades` state and renders;
nothing mutates sim.

## 2. Cost and tier

`data/upgrades.json` already has a one-shot hardware family — `growth: 1.0`,
`max_level: 1` — on an escalating ladder. The new upgrade joins it between `row`
and `hall_buttons`:

| id | cost |
| --- | --- |
| `row` | $200 base, 1.45^n |
| **`call_direction`** | **$400, one-shot** |
| `hall_buttons` | $1,200 |
| `car_buttons` | $2,000 |
| `load_sensor` | $4,500 |
| `lobby_parking` | $6,000 |
| `spring` | $9,000 |

$400 is deliberately the cheapest one-shot on the ladder. Unlike every other
upgrade, this one **starts by taking something away** — the arrow is visible in
the shipped game today, so this makes the default strictly less informative than
it is now. Pricing it early means the player buys the arrow back within the first
few minutes and reads it as a first information purchase rather than a
punishment, and it teaches the one-shot hardware family before the expensive
members appear.

```json
{ "id": "call_direction", "name": "Hall Call Direction", "base": 400.0,
  "growth": 1.0, "max_level": 1,
  "note": "a waiting passenger's arrow shows which way they are going" }
```

## 3. The change

**`sim/upgrades.gd`** — two one-word additions:

1. `"call_direction"` joins the `HARDWARE` const (line 147).
2. `"call_direction"` joins the `match` arm at line 109 that returns `true` for
   controller features that are not car parts.

It stays **out** of `has_effect()`. That is load-bearing rather than an omission:
`is_zero_delta()` returns early for anything without an effect, which is the
correct answer for a one-shot whose `max_level` already blocks a second purchase.

**`view/floor_row.gd`** — add a `CALL_UNKNOWN` constant and give
`set_waiting(passengers)` a `show_direction: bool` parameter, applied at the
`show_as` call on line 118:

```gdscript
_sprites[i].show_as(p.patience_fraction(),
    (CALL_DOWN if p.direction() < 0 else CALL_UP) if show_direction
    else CALL_UNKNOWN)
```

**`view/building_view.gd:346`** — pass
`_state.upgrades.is_installed("call_direction")`.

**`view/passenger_sprite.gd`** — unchanged. `show_as(fraction, text)` already
renders whatever string it is handed, which is why this feature needs no new
sprite state.

**The management panel** — unchanged. No file in `ui/` mentions `hall_buttons`,
so the upgrade list is generated from the catalog and this appears on its own.
`SaveCodec` is likewise generic over the levels dictionary.

## 4. `CALL_UNKNOWN` is the empty string

The un-upgraded chip shows `""` — a bare chip, still tinted by patience.

The alternative considered was a neutral glyph (`?` or a dot). Rejected: the
chip's colour already carries patience, so the glyph would add no information,
and `?` reads as an *error* state rather than as information withheld. An empty
label is the honest rendering of "you have not bought this yet".

## 5. Tests

Three tests in `tests/test_board_input.gd` assert an arrow that is now gated, so
each must buy the upgrade first:

- `test_a_waiting_passenger_shows_its_call_direction_not_its_floor` (line 352)
- `test_a_downward_call_shows_a_downward_arrow` (line 365)
- `test_waiting_passengers_show_their_own_directions` (line 369)

**`fit()` is not available in this file.** It is defined only in
`tests/test_auto_dispatch.gd:217`, against that suite's own `gs`. This file
drives the real scene and reaches state through `root.state`, so it needs its own
two-line helper:

```gdscript
func fit(id: String) -> void:
    root.state.economy.accrue(1e12)
    assert_true(root.state.buy(id), "fitted %s" % id)
```

The `accrue` is load-bearing: a fresh `GameState` holds $0, so `buy()` returns
false and the arrow would stay hidden — the tests would fail for the right
reason but the wrong cause, which is the slowest kind to diagnose.

Plus **one new test**, which is the one that actually guards the feature: a
waiting passenger renders `CALL_UNKNOWN` before any purchase. The three existing
tests only keep working; without the new one, deleting the gate entirely would
still pass the suite.
