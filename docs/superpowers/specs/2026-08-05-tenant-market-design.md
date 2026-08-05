# Tenant Market — design

**Date:** 2026-08-05
**Status:** approved
**Supersedes:** the lease picker (UI spec §4.3's FloorPanel picker; base design's
player-chosen tenancy). Move-out was already out of the player's hands; this
completes the loop so neither direction is chosen.

## Concept

Who occupies a floor is the **market's** decision, not the player's. The
player's levers are *encourage* (class upgrades draw better businesses) and
*unlock* (buying floors). The lease picker dies.

## 1. Market fill — new module `sim/market.gd`

- A vacant above-ground floor starts a fill countdown: **`FILL_TICKS = 600`**
  (30 s, half of `Tenancy.MOVE_OUT_TICKS`). When it expires, the market draws a
  kind and the floor is tenanted at full satisfaction. **No cash changes hands
  at move-in.**
- **Draw pool:** kinds with `requires_class <= fitout.tier_at(floor)`,
  excluding basement-only kinds (`where == "basement"`). The tier is read **at
  fill time**, not vacancy time, so upgrading a vacant floor improves the
  pending draw.
- **Weighting:** `weight = 3^(requires_class - 1)` per kind. On a Class 3
  floor that is 9/9/3/3/1/1 across the current catalog — ~69 % tier-3,
  occasionally lower. The base is a tunable constant.
- `Market` is `extends RefCounted`, owns per-floor countdowns and its **own**
  `RandomNumberGenerator`, seeded `state_seed + MARKET_SEED_OFFSET`. It must
  NOT share the spawner's rng: the spawner draws once per tick and any extra
  draw would shift the whole traffic sequence.
- **Tick order:** market fill runs immediately after tenancy's
  `accrue_for_tick()` vacate step — a floor vacated this tick starts counting
  this tick. The order is pinned by test like the deliver-before-expire
  boundary.
- Ownership boundary: `Tenancy` keeps who-is-where, satisfaction, and
  move-outs. `Market` owns only arrivals (countdowns + the draw) and writes
  through `tenancy.set_kind`.

## 2. Pricing out

Upgrading the class of an **occupied** floor starts the sitting tenant's
existing move-out countdown (`Tenancy.MOVE_OUT_TICKS`, 60 s). The tenant is
always below the new tier by construction (`requires_class <= old tier <
new tier`), so the rule is unconditional: **renovation evicts**. The real cost
of an upgrade is the sticker price plus ~90 s of that floor's lost traffic
(move-out + fill delay). A floor already moving out just keeps its clock.

## 3. What survives, what dies

| Thing | Fate |
| --- | --- |
| FloorPanel lease picker | **Deleted** for above-ground floors. Vacant state shows `NEW TENANT IN Ns` (real seconds, like the move-out label). |
| `GameState.lease()` / `lease_cost()` | **Kept, restricted to basement/parking.** Refuses above-ground floors. |
| `GameState.available_kinds()` | Deleted (or reduced to the parking path if the basement UI needs it). |
| `tenants.json` `lease_cost` on business kinds | Dead field, left in data. Parking's is live. Removes a $60–380 sink; class costs ($400/$2500) were always the real sink — no retune now, noted for the next balance pass. |
| No-fail guarantee (`lease free while < MIN_FLOORS_FOR_TRAFFIC`) | Deleted; the market refills for free unconditionally — a strictly stronger guarantee. `MIN_FLOORS_FOR_TRAFFIC` itself stays (still gates traffic). |
| Starting building | Untouched — `DEFAULT_ROSTER` is scripted via `set_kind`; the market only handles floors that *become* vacant. The tuned 47.4 trips/day start does not change. |
| Parking / basement lease flow | Untouched — parking remains a deliberate infrastructure purchase. |

## 4. Persistence

Per-floor fill countdown rides in **save v4** as a defaulted optional field
(same precedent as the basement block). A save missing the field restarts the
countdown at load — harmless. Market rng re-seeds from the state seed on
decode, like the spawner's; rng *state* is not persisted (existing precedent:
a save/load may diverge from a never-saved run, deterministically per seed).

## 5. Testing

- Fill: a vacated floor is tenanted exactly `FILL_TICKS` later; the countdown
  survives encode/decode; a save without the field refills anyway.
- Weighting: seeded statistical test — a Class 3 floor draws tier 3 at the
  expected rate; a Class 1 floor never draws above tier 1; basement kinds
  never appear above ground.
- Pricing out: upgrading an occupied floor starts move-out; upgrading a
  vacant floor changes the pending draw's pool; upgrading a moving-out floor
  does not reset the clock.
- Boundaries: parking still leases manually and only in the basement;
  `lease()` refuses above-ground floors; spawner seed sequence is identical
  with and without market draws (rng isolation).
- Tick order pin: vacate → fill within one tick.
