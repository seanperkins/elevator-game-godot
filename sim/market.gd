class_name Market
extends RefCounted

## Who moves in is the MARKET's decision, not the player's. The player's
## levers are encourage (class upgrades weight the draw) and unlock (buying
## floors); the lease picker is gone. See the 2026-08-05 tenant-market spec.
##
## Owns per-floor fill countdowns and the weighted draw, nothing else:
## Tenancy keeps who-is-where, satisfaction and move-outs, and the market
## writes arrivals through tenancy.lease(). No cash changes hands at move-in
## -- refilling for free is what replaced the old free-below-two-tenants
## no-fail guarantee, and it is the stronger one.

## Half of Tenancy.MOVE_OUT_TICKS: 30 s of vacancy before someone moves in.
const FILL_TICKS := 600
## Added to the run seed. The market must NOT share the spawner's rng: the
## spawner draws once per tick and one extra draw would shift the whole
## traffic sequence.
const SEED_OFFSET := 7919
## weight = base ^ (requires_class - 1): a class 3 floor draws ~69% tier 3
## against the shipped catalog. The lever for how often an upgrade "wastes".
const TIER_WEIGHT_BASE := 3.0

var _rng := RandomNumberGenerator.new()
## floor_index -> ticks until move-in. Keyed by FLOOR, not slot: digging
## shifts slots but never renumbers floors, so this survives a dig untouched.
var _fill_left: Dictionary = {}

func _init(p_seed: int) -> void:
	_rng.seed = p_seed + SEED_OFFSET

## Scans TOWER floors only -- the basement (parking) stays a deliberate
## purchase. A vacant floor's first sighting arms the clock at FILL_TICKS and
## does not decrement it, so a fill lands exactly FILL_TICKS ticks later. A
## floor found occupied drops any stale countdown: the scan self-heals, which
## is also why a save missing the countdown field merely restarts the clock.
func step(tenancy: Tenancy, fitout: Fitout, catalog: TenantCatalog,
		floor_count: int) -> void:
	for floor_index in range(floor_count):
		if not tenancy.is_vacant(floor_index):
			_fill_left.erase(floor_index)
			continue
		if not _fill_left.has(floor_index):
			_fill_left[floor_index] = FILL_TICKS
			continue
		_fill_left[floor_index] -= 1
		if _fill_left[floor_index] <= 0:
			var id := draw_kind(fitout.tier_at(floor_index), catalog)
			if id.is_empty():
				_fill_left[floor_index] = FILL_TICKS
				continue
			tenancy.lease(floor_index, id)
			_fill_left.erase(floor_index)

## The tier is the caller's CURRENT tier -- read at fill time, so upgrading a
## vacant floor mid-countdown improves the pending draw.
func draw_kind(tier: int, catalog: TenantCatalog) -> String:
	var pool: Array[TenantKind] = []
	for k in catalog.available_for_class(tier, TenantKind.Where.TOWER):
		if not k.entrance:
			pool.append(k)
	var total := 0.0
	for k in pool:
		total += pow(TIER_WEIGHT_BASE, k.requires_class - 1)
	if total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for k in pool:
		roll -= pow(TIER_WEIGHT_BASE, k.requires_class - 1)
		if roll <= 0.0:
			return k.id
	return pool[pool.size() - 1].id

func fill_ticks_left(floor_index: int) -> int:
	return _fill_left.get(floor_index, 0)

## Resumes a saved countdown. Zero or negative means "no countdown", matching
## the encode side; step() re-arms a vacant floor on its next sighting anyway.
func restore_floor(floor_index: int, ticks: int) -> void:
	if ticks > 0:
		_fill_left[floor_index] = clampi(ticks, 1, FILL_TICKS)
