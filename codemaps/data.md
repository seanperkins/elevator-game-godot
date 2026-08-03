> Generated: 2026-08-02 | Token-lean format for LLM context

# data/ — JSON config (loaded at runtime; no expression strings)

## traffic_walkup.json → TrafficSpawner
Daily spawn curve, one bucket per simulated hour.
`minutes_per_day=24` (a sim day = 24 real minutes @20Hz), `base_patience_ticks=900`, `base_fare=4.0`. 24 buckets: overnight trough 0.4–0.8, morning peak 4.0@min 7, midday dip, evening 4.4@min 18. **Curve describes a 6-row building** (`REFERENCE_ROWS`).

## upgrades.json → Upgrades
`cost = base * growth^level`, effects applied by id in code. `max_level:1` = hardware (yes/no).

| id | name | base | growth | max | note |
|---|---|---|---|---|---|
| doors | Faster Doors | 25 | 1.55 | 12 | → DOOR_TICKS_MIN floor |
| speed | Stronger Motor | 40 | 1.60 | 12 | → rows_per_tick |
| capacity | Bigger Car | 120 | 1.90 | 8 | → car.capacity |
| shaft | New Shaft | 500 | 3.20 | 7 | |
| row | Build a Floor | 200 | 1.45 | 34 | |
| auto | Auto-Dispatch | 750 | 2.60 | 8 | licences = level |
| hall_buttons | Hall Call Buttons | 1200 | 1.0 | 1 | dispatch Source.WAITING |
| car_buttons | Car Call Buttons | 2000 | 1.0 | 1 | Source.RIDERS |
| load_sensor | Load Weighing | 4500 | 1.0 | 1 | bypass_when_full |
| lobby_parking | Lobby Parking | 6000 | 1.0 | 1 | WhenIdle.LOBBY |
| spring | Lobby Launch Spring | 9000 | 1.0 | 1 | launch trip |

## tenants.json → currently DEAD (repurposed by Spec A)
Describes `rent_per_minute` for deli/dentist/accountants — an income source removed when rent was. *Nothing loads it.*
Spec A ("tenant kinds and floor class") redefines it to `classes` (tier/`cost`/`fare_multiplier`: 1.00/1.35/1.80) + `kinds` (id/name/...) — see sim/save_codec notes.
