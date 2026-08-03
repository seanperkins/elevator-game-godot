# A building you can actually finish

**Status:** agreed, implemented same day.

`data/upgrades.json` says `row.max_level` is 34. The building starts at six
floors, so the data promises a **40-floor building** — exactly
`Building.MAX_ROWS`. At `growth: 1.45` that fortieth floor costs **$136 million**
and arrives after roughly **32,000 hours**. The game's own stated ceiling is
unreachable by four orders of magnitude.

This retunes the two curves that decide the shape of a run so that the promise
and the economy agree.

---

## 1. Why it cannot be fixed by lowering one number

**Income per floor is flat.** Each apartment floor adds ~$1.93/min forever.
Cost is exponential and income is linear, so *any* growth above 1.0 eventually
outruns it — growth only decides how soon. Spec A's class tiers top out at 1.8x
fare, which shifts that curve once without changing its shape, so they are not
a rescue either.

**Supply per car falls as the building grows.** Longer round trips, same four
seats. Demand rises linearly while a single car's throughput *declines*:

| floors | demand | one car supplies | cars needed |
| --- | --- | --- | --- |
| 6 | 3.95/min | 11.43/min | 0.3 |
| 9 | 5.88/min | 7.62/min | 0.8 |
| **12** | **7.80/min** | **5.71/min** | **1.4** |
| 16 | 10.37/min | 4.29/min | 2.4 |
| 20 | 12.93/min | 3.43/min | 3.8 |

The building becomes **supply-limited at about floor 10**. Past that, income is
capped by delivery rather than by traffic, so a floor stops paying for itself no
matter what it costs. Every income figure quoted anywhere in these docs is a
100%-delivery ceiling; past floor 10 the real number is below it.

## 2. The change

Two numbers in `data/upgrades.json`. No code, no new rules.

| upgrade | field | from | to |
| --- | --- | --- | --- |
| `row` | `growth` | 1.45 | **1.10** |
| `row` | `max_level` | 34 | **14** |
| `shaft` | `growth` | 3.20 | **2.20** |

`row.max_level` 14 tops the building at **20 floors**.

## 3. The arc this produces

Simulated against the real data, with a player who buys a shaft when service can
no longer carry the building and a floor otherwise:

| milestone | reached at |
| --- | --- |
| 10 floors, 1 car | 1.3 h |
| 14 floors, 2 cars | 2.9 h |
| 17 floors, 3 cars | 4.4 h |
| **20 floors, 4 cars — complete** | **6.5 h** |

**The wall is now the cap, not the cost.** At growth 1.10 floors stay affordable
the whole way up, so a run ends because the building is *finished* rather than
because the next floor costs more than you earn. That is the better hand-off to
prestige (Spec C): "you built all twenty floors" reads as completion, where
"floors now cost more than you earn" reads as failure.

## 4. Why `shaft` moves too, and why the obvious reason is wrong

Shaft growth changes total arc length by about **3%** — across its entire range,
time-to-20-floors moves 43.7 h to 42.9 h at the old row growth. Floors are
bought fourteen times; shafts three times. Row growth dominates completely.

It earns its place for a different reason: **when** it bites.

| car | needed at | cost at 3.20 | wait | cost at 2.20 | wait |
| --- | --- | --- | --- | --- | --- |
| 2nd | floor 11 | $500 | 26 min | $500 | 26 min |
| 3rd | floor 15 | $1,600 | 57 min | $1,100 | 39 min |
| 4th | floor 18 | $5,120 | **145 min** | $2,420 | 69 min |

At 3.20 the fourth car is a two-and-a-half-hour stall arriving at exactly the
moment the building stops coping — the worst possible place for dead time. That
is a shape problem, not a duration problem, and it is the only thing this edit
fixes.

## 5. What deliberately does not change

- **`Building.MAX_ROWS` stays 40.** It is the structural limit and it feeds the
  spawner's saturation guard (`MAX_ROWS x largest_bucket` must stay under
  `SimClock.TICKS_PER_SIM_MINUTE`). What this spec lowers is the *purchasable*
  ceiling, not the structural one. They are now deliberately different numbers.
- **`shaft.max_level` stays 7.** Four cars is what a 20-floor building needs;
  the headroom above costs nothing to leave.
- **No rate or fare in `data/tenants.json`.** Changing income is the other way
  to attack this, and doing both would overshoot badly.

## 6. Verification

- The full GUT suite passes.
- The five board tests in `test_board_input.gd` that build a tall building buy
  **exactly 14 rows** ("taller than the screen, so it can scroll"). A
  `max_level` of 14 is therefore precisely what the existing UI tests already
  exercise — they neither need changing nor silently stop covering anything.
- `test_building.gd` walks to `Building.MAX_ROWS` via `add_row()` directly
  rather than through a purchase, so it is unaffected by the cap.
- **One test does change.** `test_upgrades.gd`'s
  `test_row_purchases_stop_at_the_board_cap` asserted that buying rows sixty
  times lands exactly on `Building.MAX_ROWS` — it pinned the two ceilings as
  equal, which is the assumption §5 deliberately breaks. It is rewritten as
  `test_row_purchases_stop_at_the_purchasable_cap`, asserting that purchases
  stop at `row.max_level` (20 floors) and that they never exceed the board cap.
  The safety property it existed to guard is preserved; only the claim that the
  two numbers are the same is dropped.

  This was missed when the spec was first written — §6 originally claimed no
  test needed changing. The suite caught it.
