> Generated: 2026-08-03 | Token-lean format for LLM context

# tests/ — GUT suite (headless, run in CI and locally). 441 tests, 26 scripts.

Every file `extends GutTest`, broadly 1:1 with `sim/`.

| Command | |
|---|---|
| `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` | whole suite |
| `... -gtest=res://tests/test_x.gd -gexit` | one FILE (`-gdir` takes a directory, not a file) |
| `... -gunit_test_name=test_name` | one TEST (there is no `-ginclude`) |

CI (`deploy.yml`) runs the whole suite before building. Local GUT must pass before merging.

## Mapping
| Test file | Covers |
|---|---|
| test_smoke.gd | GUT wiring |
| test_building.gd | add floor/shaft, enqueue, take_boardable FIFO, MAX_FLOORS cap |
| test_elevator_car.gd | movement, doors, dispatch, answer_call, spring/commit |
| test_car_doors.gd | door phase split (opening/dwell/closing) |
| test_passenger.gd | patience, expiry boundary (exactly 0 = live), wait, source_floor |
| test_traffic_spawner.gd | draw count independent of source count, lobby collapse, fare from kind+class, **spawn threshold is one bucket not one real minute** |
| test_tenant_catalog.gd | kind/class parse, bad-catalog refusal, saturation headroom vs TICKS_PER_SIM_MINUTE |
| test_fitout.gd | per-floor class tier, revision |
| test_tenancy.gd | satisfaction, move-out, lease, no-fail guarantee |
| test_economy.gd | delivery/combo, expiry + streak, stairs penalty, no-negative-cash |
| test_game_state.gd | tick order, **deliver-beats-expiry at 0**, dispatch bounds, buy/lease/policy gating, source rebuild on revision |
| test_save_codec.gd | round-trip, refusals, v1 migration, **v2→v3 floor rename migration** (fixture is a REAL device save) |
| test_upgrades.gd | defs, purchase, hardware install, zero-delta refusal, purchasable-vs-structural cap, call_direction one-shot |
| test_dispatch_policy.gd / test_auto_dispatch.gd | orthogonal policy, presets, hardware requirements |
| test_sim_clock.gd | 20Hz accumulator, sim-minute bucket boundary, integer arithmetic |
| test_metrics.gd | rolling buckets, average_wait sentinel |
| test_coords.gd / test_coords_scroll.gd | floor↔y round-trip, scrolling/grounding |
| test_gesture.gd / test_pan_gesture.gd | tap vs pan |
| test_board_input.gd | real scene + synthetic input; scroll, ghost floor, **call-direction arrow gate** |
| test_chip_grid.gd | crowd packing (its `rows` are layout rows) |
| test_day_sparkline.gd | bar heights and directional segment shares |
| test_number_format.gd | compact formatting |
| test_safe_area.gd | insets |

## Invariants pinned on purpose — do not weaken
* `ElevatorCar.floors_per_tick` must equal `Upgrades.SPEED_BASE`.
* Tick order, especially **deliver before expire**.
* The spawner's Bernoulli denominator must equal the clock's bucket length —
  moving one without the other nets exactly zero change.
* `MAX_FLOORS x largest_bucket` must stay under `TICKS_PER_SIM_MINUTE`.
* Purchasable floor cap (20) is **below** the structural cap (40), deliberately.
* A waiting chip shows no direction until `call_direction` is fitted — the
  default-state test is the one guarding the feature; the three arrow tests
  would still pass if the gate were deleted.

## Environment notes (`test_board_input.gd` header)
game_root anchors full-rect and resizes to GUT's parent, so the board is pinned
to 720x1280 explicitly. The headless viewport is 0x0, so `push_input(event, true)`
is required (the transform inverse otherwise multiplies every coordinate by 20).
The board sits on a canvas layer above GUT's own runner GUI, which otherwise
eats taps at x ≥ 643.
