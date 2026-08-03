> Generated: 2026-08-02 | Token-lean format for LLM context

# tests/ — GUT suite (headless, run in CI and locally)

Every file `extends GutTest`, one file per module under test, 1:1 with `sim/`.
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
(Ci `deploy.yml` runs the same before building.)

## Mapping
| Test file | Covers |
|---|---|
| test_smoke.gd | GUT wiring (2+2=4) |
| test_building.gd | add row/shaft, enqueue, take_boardable FIFO |
| test_elevator_car.gd | movement, doors, dispatch, answer_call, spring/commit |
| test_passenger.gd | patience, expiry boundary (exactly 0 = live), wait, source_row |
| test_traffic_spawner.gd | curve, per-tick Bernoulli, occupancy |
| test_tenancy.gd | satisfaction, move-out, relet no-fail guarantee |
| test_economy.gd | delivery/combo, expiry (costs/streak), stairs penalty, no-negative-cash |
| test_game_state.gd | tick order, **deliver-beats-expiry at 0**, dispatch bounds, buy/relet/set_auto, policy gating |
| test_save_codec.gd | encode⇄decode round-trip, version/refusal |
| test_upgrades.gd | defs, purchase, hardware install, zero-delta refusal, _sync_car |
| test_dispatch_policy.gd / test_auto_dispatch.gd | orthogonal policy, presets, hardware requirements |
| test_sim_clock.gd | 20Hz accumulator, minute offset |
| test_metrics.gd | buckets, average_wait sentinel |
| test_coords.gd / test_coords_scroll.gd | boardcoords round-trip, scrolling/grounding |
| test_gesture.gd / test_pan_gesture.gd | tap vs pan |
| test_board_input.gd | input → dispatch wiring |
| test_chip_grid.gd | crowd packing |
| test_save_… , test_number_format.gd | formatting/coerce util (`game/util/number_format.gd`) |
| test_safe_area.gd | insets |

Note: several tests pin **cross-module invariants** on purpose (e.g. `rows_per_tick`
must equal `Upgrades.SPEED_BASE`; `GameState`-level expiry/cash assertions) — do not
weaken these when refactoring; they exist because the sim is order-dependent.
