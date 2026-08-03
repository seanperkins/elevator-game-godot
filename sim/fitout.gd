class_name Fitout
extends RefCounted

## What is built INTO a floor, as opposed to what a tenant brings with them.
## Today that is one thing -- the floor's class -- and later it is where
## amenities land without touching the tenancy loop.
##
## The split is the spec's headline rule made structural: things built into the
## floor persist, things built for the tenant leave with them. That is what
## makes replacing a tenant a real cost rather than a free re-roll.
##
## Indexes its dense array DIRECTLY, exactly as Tenancy does. A shared index
## object was considered and rejected: in a building whose bottom floor is
## always 0 the mapping is the identity, so it earns nothing, and it converts a
## container-size desync from a loud out-of-range access into a silent
## valid-but-wrong index that an "the containers agree" test would pass through.

const BASE_TIER := 1

var _tier: PackedInt32Array = PackedInt32Array()
var _revision: int = 0

func _init(row_count: int) -> void:
	for i in range(maxi(row_count, 0)):
		_tier.append(BASE_TIER)

func rows() -> int:
	return _tier.size()

func add_row() -> void:
	_tier.append(BASE_TIER)
	_revision += 1

func tier_at(row: int) -> int:
	return _tier[row] if _valid(row) else BASE_TIER

## Moves the revision, because a cached TrafficSource carries this floor's fare
## multiplier. Without that a class upgrade on a TENANTED floor would leave the
## stale multiplier cached until the next tenancy event -- which on a
## well-served floor may be never, making the purchase inert.
func set_tier(row: int, tier: int) -> void:
	if not _valid(row):
		return
	_tier[row] = tier
	_revision += 1

func revision() -> int:
	return _revision

func _valid(row: int) -> bool:
	return row >= 0 and row < _tier.size()
