class_name TenantCatalog
extends RefCounted

## The leasing domain: which kinds exist, and what a floor class costs and is
## worth. Both live in one file so a kind's `requires_class` is checked against
## the same ladder it is tuned against.
##
## A malformed file is refused WHOLE. This data controls probabilities and
## money, so shape checks are not enough -- see _validate.

var _kinds: Array[TenantKind] = []
var _by_id: Dictionary = {}
var _class_cost: Dictionary = {}          # tier -> float
var _class_multiplier: Dictionary = {}    # tier -> float
var _max_tier: int = 0

func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return _parse(parsed as Dictionary)

func _parse(data: Dictionary) -> bool:
	_kinds = []
	_by_id = {}
	_class_cost = {}
	_class_multiplier = {}
	_max_tier = 0

	var classes: Variant = data.get("classes")
	if typeof(classes) != TYPE_ARRAY or (classes as Array).is_empty():
		return false
	var expected_tier := 1
	for entry in (classes as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var e: Dictionary = entry
		if int(e.get("tier", -1)) != expected_tier:
			return false                      # tiers contiguous from 1
		var cost := float(e.get("cost", -1.0))
		var mult := float(e.get("fare_multiplier", 0.0))
		# A negative cost is free money, not a discount: can_afford(-400) is
		# cash >= -400 (true) and spend then runs cash -= -400.
		if not is_finite(cost) or cost < 0.0:
			return false
		if not is_finite(mult) or mult <= 0.0:
			return false
		_class_cost[expected_tier] = cost
		_class_multiplier[expected_tier] = mult
		_max_tier = expected_tier
		expected_tier += 1

	var kinds: Variant = data.get("kinds")
	if typeof(kinds) != TYPE_ARRAY or (kinds as Array).is_empty():
		return false
	for entry in (kinds as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var k := _parse_kind(entry as Dictionary)
		if k == null:
			return false
		if _by_id.has(k.id):
			return false                      # ids unique
		_by_id[k.id] = k
		_kinds.append(k)

	# Without a tier-1 kind the no-fail guarantee ("the cheapest eligible kind
	# is free") selects from an empty set and silently has no implementation.
	for k in _kinds:
		if k.requires_class == 1:
			return true
	return false

func _parse_kind(e: Dictionary) -> TenantKind:
	var k := TenantKind.new()
	k.id = str(e.get("id", ""))
	if k.id.is_empty():
		return null
	k.display_name = str(e.get("name", k.id))
	k.requires_class = int(e.get("requires_class", 0))
	if not _class_cost.has(k.requires_class):
		return null                           # requires a tier the ladder defines
	k.lease_cost = float(e.get("lease_cost", -1.0))
	k.base_fare = float(e.get("base_fare", 0.0))
	if not is_finite(k.lease_cost) or k.lease_cost < 0.0:
		return null
	if not is_finite(k.base_fare) or k.base_fare <= 0.0:
		return null
	k.rate = _floats(e.get("rate"))
	k.inbound = _floats(e.get("inbound"))
	k.outbound = _floats(e.get("outbound"))
	if k.rate.is_empty() or k.inbound.is_empty() or k.outbound.is_empty():
		return null
	for h in range(TenantKind.BUCKETS):
		# A negative interfloor remainder feeds a weighted pick, which is the
		# one malformed case that fails silently rather than crashing.
		if k.inbound[h] + k.outbound[h] > 1.0:
			return null
	return k

func _floats(v: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != TenantKind.BUCKETS:
		return out
	for x in (v as Array):
		if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
			return PackedFloat32Array()
		var f := float(x)
		if not is_finite(f) or f < 0.0:
			return PackedFloat32Array()
		out.append(f)
	return out

func kind(id: String) -> TenantKind:
	return _by_id.get(id, null)

func all_kinds() -> Array[TenantKind]:
	return _kinds

## Every kind at or below `tier`, in file order.
func available_for_class(tier: int) -> Array[TenantKind]:
	var out: Array[TenantKind] = []
	for k in _kinds:
		if k.requires_class <= tier:
			out.append(k)
	return out

## Lowest lease_cost among eligible kinds; ties break by FIRST APPEARANCE in
## the file, so the free recovery tenant (§9) and the save-restore fallback
## (§10) are deterministic rather than dependent on JSON ordering.
func cheapest_for_class(tier: int) -> TenantKind:
	var best: TenantKind = null
	for k in available_for_class(tier):
		if best == null or k.lease_cost < best.lease_cost:
			best = k
	return best

func class_cost(tier: int) -> float:
	return float(_class_cost.get(tier, INF))

func fare_multiplier(tier: int) -> float:
	return float(_class_multiplier.get(tier, 1.0))

func max_tier() -> int:
	return _max_tier

## The largest single rate bucket across every kind. MAX_ROWS x this is the
## worst-case summed rate, which must stay under TICKS_PER_MINUTE or the
## Bernoulli trial clips silently at p = 1.
func largest_bucket() -> float:
	var top := 0.0
	for k in _kinds:
		for h in range(TenantKind.BUCKETS):
			top = maxf(top, k.rate[h])
	return top
