# Call Direction Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate the hall-call direction arrow behind a $400 one-shot `call_direction` upgrade, so an un-upgraded waiting chip reveals only that someone is waiting.

**Architecture:** Presentation-only. `Passenger.direction()` and every dispatch policy keep reading direction exactly as now; only `view/floor_row.gd` stops *rendering* it until `Upgrades.is_installed("call_direction")`. The upgrade joins the existing one-shot hardware family (`growth: 1.0`, `max_level: 1`).

**Tech Stack:** Godot 4.7, GDScript, GUT test framework.

## Global Constraints

- Views never mutate sim state. `building_view` reads `upgrades` and passes a bool down; nothing flows back.
- `data/` holds numeric coefficients only — never expression strings.
- The upgrade must stay **out** of `Upgrades.has_effect()`; see Task 1, Step 4.
- Run the suite with: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Local GUT must pass before merging.

---

### Task 1: The upgrade exists and can be bought

**Files:**
- Modify: `data/upgrades.json`
- Modify: `sim/upgrades.gd:109`, `sim/upgrades.gd:147`
- Test: `tests/test_upgrades.gd`

**Interfaces:**
- Produces: upgrade id `"call_direction"`, purchasable via
  `Upgrades.purchase("call_direction", economy, building) -> bool` and readable
  via `Upgrades.is_installed("call_direction") -> bool`. Task 2 consumes the
  latter.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_upgrades.gd`:

```gdscript
func test_call_direction_is_a_one_shot_that_installs() -> void:
	assert_eq(up.level_of("call_direction"), 0, "not fitted on a fresh building")
	assert_false(up.is_installed("call_direction"))
	econ.accrue(1000.0)
	assert_true(up.purchase("call_direction", econ, b), "bought at $400")
	assert_true(up.is_installed("call_direction"))

func test_call_direction_cannot_be_bought_twice() -> void:
	econ.accrue(1000.0)
	assert_true(up.purchase("call_direction", econ, b))
	assert_false(up.purchase("call_direction", econ, b),
		"max_level 1 stops a second purchase")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_upgrades.gd -gexit -ginclude="test_call_direction_is_a_one_shot_that_installs"`
Expected: FAIL — the id does not exist, so `purchase` returns false.

- [ ] **Step 3: Add the definition**

In `data/upgrades.json`, insert between the `row` and `hall_buttons` entries:

```json
  {
   "id": "call_direction",
   "name": "Hall Call Direction",
   "base": 400.0,
   "growth": 1.0,
   "max_level": 1,
   "note": "a waiting passenger's arrow shows which way they are going"
  },
```

- [ ] **Step 4: Register it as controller hardware**

Two edits in `sim/upgrades.gd`.

Line 109's `match` arm gains the id, so a purchase resolves to "nothing on a car
changes":

```gdscript
		"hall_buttons", "car_buttons", "load_sensor", "lobby_parking",
		"call_direction":
			return true          # sensors and controller features, not car parts
```

Line 147's `HARDWARE` const gains it:

```gdscript
const HARDWARE := ["hall_buttons", "car_buttons", "load_sensor", "lobby_parking",
	"spring", "call_direction"]
```

**Do not add it to `has_effect()`.** That is deliberate, not an oversight:
`is_zero_delta()` returns early for anything without an effect, which is the
correct answer for a one-shot whose `max_level` already blocks a second
purchase. Adding it there would make `is_zero_delta` reason about a level curve
that does not exist.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_upgrades.gd -gexit`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS. `tests/test_save_codec.gd` round-trips the levels dictionary
generically, so a new id needs no codec change — if it fails here, that
assumption was wrong and the codec needs looking at before continuing.

- [ ] **Step 7: Commit**

```bash
git add data/upgrades.json sim/upgrades.gd tests/test_upgrades.gd
git commit -m "Add the call_direction upgrade

A $400 one-shot joining the controller-hardware family. Buys nothing yet --
the view gate lands next."
```

---

### Task 2: The arrow is hidden until it is bought

**Files:**
- Modify: `view/floor_row.gd:24-25` (add constant), `view/floor_row.gd:97`, `view/floor_row.gd:118`
- Modify: `view/building_view.gd:346`
- Modify: `tests/test_board_input.gd`
- Modify: `docs/superpowers/backlog.md`

**Interfaces:**
- Consumes: `Upgrades.is_installed("call_direction")` from Task 1.
- Produces: `FloorRow.CALL_UNKNOWN` (String, `""`) and the new signature
  `FloorRow.set_waiting(passengers: Array, show_direction: bool) -> void`.

- [ ] **Step 1: Write the failing test for the default**

This is the test that actually guards the feature. Without it, deleting the gate
entirely would still pass the suite.

Add to `tests/test_board_input.gd`, in the hall-call section near line 350:

```gdscript
func fit(id: String) -> void:
	# test_auto_dispatch.gd has its own fit() against that suite's `gs`; this
	# file drives the real scene and reaches state through root.state. The
	# accrue is load-bearing: a fresh GameState holds $0, so buy() would fail
	# and the arrow would stay hidden for the wrong reason entirely.
	root.state.economy.accrue(1e12)
	assert_true(root.state.buy(id), "fitted %s" % id)

func test_a_waiting_passenger_hides_its_direction_until_the_upgrade() -> void:
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	var sprite: PassengerSprite = view._rows[2]._sprites[0]
	assert_true(sprite.visible, "the chip is still drawn -- someone IS waiting")
	assert_eq(sprite.label_text(), FloorRow.CALL_UNKNOWN,
		"which way they are going is not readable until it is bought")

func test_buying_call_direction_reveals_the_arrow() -> void:
	fit("call_direction")
	root.state.building.enqueue(Passenger.new(2, 5, 900, 4.0, 2))
	view.refresh()
	assert_eq(view._rows[2]._sprites[0].label_text(), FloorRow.CALL_UP)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_board_input.gd -gexit -ginclude="test_a_waiting_passenger_hides_its_direction_until_the_upgrade"`
Expected: FAIL — `FloorRow.CALL_UNKNOWN` does not exist yet (parse error), and
the arrow is currently unconditional.

- [ ] **Step 3: Add the constant**

In `view/floor_row.gd`, after line 25:

```gdscript
## Waiting, direction withheld. The empty string rather than a glyph: the chip's
## colour already carries patience, so a "?" would add no information and reads
## as an error state rather than as information not yet bought.
const CALL_UNKNOWN := ""
```

- [ ] **Step 4: Thread the flag through `set_waiting`**

In `view/floor_row.gd`, line 97 becomes:

```gdscript
func set_waiting(passengers: Array, show_direction: bool) -> void:
```

and the sprite call becomes (`show_as` when this was written; the live method
is `show_waiting`, which also carries the tint key):

```gdscript
			_sprites[i].show_waiting(p.patience_fraction(),
				(CALL_DOWN if p.direction() < 0 else CALL_UP) if show_direction
				else CALL_UNKNOWN,
				PersonSprite.key_for(p.origin_floor, p.destination_floor,
					p.source_floor))
```

The parameter is required rather than defaulted to `true`. A default would let a
future caller silently opt out of the gate, which is the same class of bug the
`note_expiry(fare)` default caused (see the tenant-kinds spec, section 2).

- [ ] **Step 5: Pass the installed state from the view**

In `view/building_view.gd`, line 346 becomes:

```gdscript
		_rows[i].set_waiting(waiting,
			_state.upgrades.is_installed("call_direction"))
```

- [ ] **Step 6: Run to verify the new tests pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/test_board_input.gd -gexit -ginclude="test_a_waiting_passenger_hides_its_direction_until_the_upgrade"`
Expected: PASS. Then the same with
`-ginclude="test_buying_call_direction_reveals_the_arrow"`. Expected: PASS.

- [ ] **Step 7: Fix the three tests that assume a free arrow**

Each of these asserts an arrow that is now gated. Add `fit("call_direction")` as
the first line of each body:

- `test_a_waiting_passenger_shows_its_call_direction_not_its_floor` (line 352)
- `test_a_downward_call_shows_a_downward_arrow` (line 365)
- `test_waiting_passengers_show_their_own_directions` (line 369)

- [ ] **Step 8: Run the full suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: PASS.

If any *other* view test fails on the `set_waiting` arity, that is a caller Step
5 missed. Find them with:
`grep -rn "set_waiting" --include="*.gd" . | grep -v addons`

- [ ] **Step 9: Retire the backlog entry**

Delete the "Call direction visible only after an upgrade" section from
`docs/superpowers/backlog.md` (added in `dd9d9e8`, around line 359). It is now
built, and a backlog that lists shipped work stops being readable.

- [ ] **Step 10: Commit**

```bash
git add view/floor_row.gd view/building_view.gd tests/test_board_input.gd docs/superpowers/backlog.md
git commit -m "Hide the hall-call arrow until call_direction is fitted

A waiting chip now shows only that someone is waiting; which way they are going
costs \$400. Presentation-only -- Passenger.direction() is untouched and every
dispatch policy still reads it.

Retires the backlog entry."
```

---

### Task 3: Confirm it reads correctly on the phone

An empty label is a design decision that only a real screen can validate. The
chip is 14pt on a 393pt-wide board.

- [ ] **Step 1: Build and run on device**

Run: `ios/build.sh --launch`

- [ ] **Step 2: Check the un-upgraded state**

A fresh save has no `call_direction`. Confirm waiting chips are legible as
*occupied* — that the patience tint still reads at a glance and an empty chip is
not mistaken for a rendering fault.

- [ ] **Step 3: Buy it and check the upgraded state**

Confirm the arrows return and that the management panel lists "Hall Call
Direction" at $400 without layout overflow — the name is longer than most.

- [ ] **Step 4: If the empty chip reads as a bug rather than as withheld
      information**

Fall back to a dimmed dot by changing `CALL_UNKNOWN` to `"·"` in
`view/floor_row.gd`. That is a one-constant change and needs no test edits, as
every test refers to the constant rather than its value. Re-run the suite, and
record the change in the spec's section 4 so the rejected reasoning is not
silently lost.
