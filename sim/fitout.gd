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
## Indexes its dense array through the building's shared FloorIndex, exactly as
## Tenancy does.
##
## A shared index object was once considered and REJECTED here, and that was
## right at the time: in a building whose bottom floor is always 0 the mapping is
## the identity, so it earned nothing. Digging deleted that precondition.
##
## What the old rejection got right, and what FloorIndex is shaped by, is the
## second half of its argument: a COPIED offset converts a container-size desync
## from a loud out-of-range access into a silent valid-but-wrong index that an
## "the containers agree" test would pass through. Sharing ONE instance is what
## makes that unrepresentable rather than something to test for.

const BASE_TIER := 1

var _tier: PackedInt32Array = PackedInt32Array()
var _revision: int = 0
## Shared BY REFERENCE with Building and Tenancy.
var _index: FloorIndex

func _init(index: FloorIndex) -> void:
	_index = index
	for i in range(maxi(index.size(), 0)):
		_tier.append(BASE_TIER)

## A floor dug below the lobby, at the base tier. Front insertion: the basement
## is dense from the bottom and this is the new deepest floor.
func dig() -> void:
	_tier.insert(0, BASE_TIER)
	_revision += 1

func floors() -> int:
	return _tier.size()

func add_floor() -> void:
	_tier.append(BASE_TIER)
	_revision += 1

func tier_at(floor_index: int) -> int:
	return _tier[_index.slot(floor_index)] if _valid(floor_index) else BASE_TIER

## Moves the revision, because a cached TrafficSource carries this floor's fare
## multiplier. Without that a class upgrade on a TENANTED floor would leave the
## stale multiplier cached until the next tenancy event -- which on a
## well-served floor may be never, making the purchase inert.
func set_tier(floor_index: int, tier: int) -> void:
	if not _valid(floor_index):
		return
	_tier[_index.slot(floor_index)] = tier
	_revision += 1

func revision() -> int:
	return _revision

## The BUILDING's floor range, not the array's bounds -- see FloorIndex.
func _valid(floor_index: int) -> bool:
	return _index != null and _index.holds(floor_index)
