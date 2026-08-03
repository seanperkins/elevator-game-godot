> Generated: 2026-08-03 | Token-lean format for LLM context

# data/ — JSON config (loaded at runtime; no expression strings)

## tenants.json → TenantCatalog  **(LIVE — this drives all traffic)**

Two sections. Rates are **per floor of that kind, per simulated minute, one
bucket per simulated hour**; a bucket lasts `SimClock.TICKS_PER_SIM_MINUTE`
(600 ticks = 30 real s), so summing a kind's 24 buckets gives its trips/day.

`classes` — tier / cost / fare_multiplier:

| tier | cost | fare x |
|---|---|---|
| 1 | 0 | 1.00 |
| 2 | 400 | 1.35 |
| 3 | 2500 | 1.80 |

`kinds` — `{id, name, requires_class, lease_cost, base_fare, rate[24], inbound[24], outbound[24]}`.
`inbound` = share running lobby→here, `outbound` = here→lobby, remainder is interfloor.

| id | class | lease | fare | trips/day | shape |
|---|---|---|---|---|---|
| apartments | 1 | 60 | 3.00 | 7.7 | outbound peak 1.2 @07, inbound peak 1.1 @18 |
| shops | 1 | 60 | 3.50 | 8.9 | dead overnight, midday-weighted |

**Starting building** (1 shops + 5 apartments) totals **47.4 trips/day**, the
figure design spec §5.6 targets. At a 12-real-minute day that is ~1.97 trips/min
average, ~6.1 at the bucket-7 peak.

**Saturation guard**: the spawner emits at most one passenger per tick, so
`Building.MAX_FLOORS (40) x largest rate bucket (1.2)` = 48 must stay under
`TICKS_PER_SIM_MINUTE` (600). Pinned by `test_tenant_catalog.gd`.

## upgrades.json → Upgrades
`cost = base * growth^level`; effects applied by id in `upgrades.gd`. `max_level: 1` = hardware (yes/no).

| id | name | base | growth | max | note |
|---|---|---|---|---|---|
| doors | Faster Doors | 25 | 1.55 | 12 | → DOOR_TICKS_MIN floor |
| speed | Stronger Motor | 40 | 1.60 | 12 | → floors_per_tick |
| capacity | Bigger Car | 120 | 1.90 | 8 | → car.capacity |
| shaft | New Shaft | 500 | **2.20** | 7 | 4th car is needed ~floor 18 |
| floor | Build a Floor | 200 | **1.10** | **14** | **purchasable cap = 20 floors** |
| auto | Auto-Dispatch | **200** | 2.60 | 8 | licences = level |
| call_direction | Hall Call Direction | **50** | 1.0 | 1 | reveals the ▲/▼ on waiting chips |
| hall_buttons | Hall Call Buttons | 1200 | 1.0 | 1 | Source.HALL_CALLS |
| car_buttons | Car Call Buttons | 2000 | 1.0 | 1 | Source.CAR_CALLS |
| load_sensor | Load Weighing | 4500 | 1.0 | 1 | bypass_when_full |
| lobby_parking | Lobby Parking | 6000 | 1.0 | 1 | WhenIdle.RETURN_TO_LOBBY |
| spring | Lobby Launch Spring | 9000 | 1.0 | 1 | launch trip |

The id is `floor`, not `row` (v3). A v2 save's `levels.row` migrates in `SaveCodec`.

**Arc**: a complete run is 20 floors / 4 cars in ~6.5 h. `floor.max_level` is
deliberately below `MAX_FLOORS` (40) — the gap is the room reserved for prestige.
See `docs/superpowers/specs/2026-08-03-building-cost-curve-design.md`.

## traffic_walkup.json → TrafficSpawner  **(mostly vestigial)**
Only **`base_patience_ticks` (900 = 45 real s)** is read. The `buckets` array and
`minutes_per_day` are the old building-wide curve, kept as the calibration
reference for patience only — per-floor rate and fare now come from the catalog.
Its comment still says a day is 24 real minutes; that predates the pacing change
(a day is 12).
