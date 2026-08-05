class_name Tenancy
extends RefCounted

## Per-floor tenants. Satisfaction tracks recent service and scales rent
## continuously; below a threshold a visible countdown starts, giving the
## player a chance to recover it.
##
## Tenants do not pay rent. ALL money comes from moving people, so the only
## thing a tenant is worth is the traffic they generate: a vacant floor is
## nobody to carry, and therefore nobody to charge. That is a sharper coupling
## than rent ever was -- bad service loses the tenant, and losing the tenant
## loses that floor's fares -- and it means the game pays nothing at all for
## doing nothing until automation is bought.
##
## NO FAIL STATE, guaranteed by ONE rule: the cheapest tenant eligible for a
## floor is FREE whenever the player cannot generate traffic. The pricing
## itself lives in GameState.lease_cost, which only charges while
## tenanted_count() >= MIN_FLOORS_FOR_TRAFFIC; Tenancy owns the threshold and
## the kind the lease writes.
##
## Any floor, including the lobby, may vacate. A second rule ("the lobby never
## vacates") would make this guard unreachable and the recovery test unwritable,
## because its setup would be forbidden.

const MOVE_OUT_THRESHOLD := 0.2
const MOVE_OUT_TICKS := 1200          # one simulated minute of grace

const _DELIVERY_GAIN := 0.02
const _EXPIRY_LOSS := 0.05

## Shared BY REFERENCE with Building and Fitout, so the three cannot disagree
## about which slot a floor is. See sim/floor_index.gd.
var _index: FloorIndex

var _satisfaction: PackedFloat32Array = PackedFloat32Array()
var _vacant: Array[bool] = []
var _move_out_left: PackedInt32Array = PackedInt32Array()
var _kind: PackedStringArray = PackedStringArray()
var _revision: int = 0

## `tenanted_prefix` is how many LEADING floors start with a tenant. Everything
## past it arrives vacant with no kind, so a constructed floor and a purchased
## one agree.
##
## The divergence is by floor INDEX, not by entry point. _append_floor is shared
## with add_floor, and flipping the append itself would make every floor of a new
## building vacant; vacating only in add_floor would leave a tall constructed
## building fully tenanted and kindless. So both callers vacate, by index.
func _init(index: FloorIndex, tenanted_prefix: int) -> void:
	_index = index
	for i in range(index.size()):
		_append_floor()
		if i >= tenanted_prefix:
			_vacant[i] = true

## A floor dug below the lobby: excavated, therefore VACANT. It goes to the
## FRONT of every array, because the basement is dense from the bottom and this
## is now the deepest floor.
func dig() -> void:
	_satisfaction.insert(0, 1.0)
	_vacant.insert(0, true)
	_move_out_left.insert(0, 0)
	_kind.insert(0, "")
	_revision += 1

func _append_floor() -> void:
	_satisfaction.append(1.0)
	_vacant.append(false)
	_move_out_left.append(0)
	_kind.append("")

func add_floor() -> void:
	_append_floor()
	_vacant[_vacant.size() - 1] = true
	_revision += 1

## How many floors tenancy covers. Callers that grow the building need this to
## know how far behind tenancy has fallen -- is_vacant() cannot answer it,
## because an out-of-range floor reports vacant rather than absent.
func floors() -> int:
	return _satisfaction.size()

## Monotonic revision bumping on every structural change. A cached TrafficSource
## list compares this against its last-seen baseline to learn it is stale.
func revision() -> int:
	return _revision

## Restores one floor from a save. Satisfaction scales rent and a vacancy is a
## debt, so neither can be inferred from anything else in the file.
func restore_floor(floor_index: int, satisfaction: float, vacant: bool, move_out_left: int,
		kind := "") -> void:
	if not _valid(floor_index):
		return
	_satisfaction[_index.slot(floor_index)] = clampf(satisfaction, 0.0, 1.0)
	_vacant[_index.slot(floor_index)] = vacant
	_move_out_left[_index.slot(floor_index)] = maxi(move_out_left, 0)
	_kind[_index.slot(floor_index)] = "" if vacant else kind
	_revision += 1

func kind_at(floor_index: int) -> String:
	return _kind[_index.slot(floor_index)] if _valid(floor_index) else ""

func set_kind(floor_index: int, kind_id: String) -> void:
	if not _valid(floor_index):
		return
	_kind[_index.slot(floor_index)] = kind_id
	_revision += 1

func note_delivery(floor_index: int) -> void:
	if not _valid(floor_index) or _vacant[_index.slot(floor_index)]:
		return
	_satisfaction[_index.slot(floor_index)] = clampf(_satisfaction[_index.slot(floor_index)] + _DELIVERY_GAIN, 0.0, 1.0)
	if _satisfaction[_index.slot(floor_index)] > MOVE_OUT_THRESHOLD:
		_move_out_left[_index.slot(floor_index)] = 0

func note_expiry(floor_index: int) -> void:
	if not _valid(floor_index) or _vacant[_index.slot(floor_index)]:
		return
	_satisfaction[_index.slot(floor_index)] = clampf(_satisfaction[_index.slot(floor_index)] - _EXPIRY_LOSS, 0.0, 1.0)
	if _satisfaction[_index.slot(floor_index)] <= MOVE_OUT_THRESHOLD and _move_out_left[_index.slot(floor_index)] <= 0:
		_move_out_left[_index.slot(floor_index)] = MOVE_OUT_TICKS

## Advances move-out countdowns and RETURNS the floors that vacated on this tick.
##
## The docstring this replaces said "returns nothing", meaning tenants are not
## an income source -- a rejection of rent, not of all return values. The floor
## identity is needed because a vacating floor's waiting passengers have to be
## removed by source, and a revision counter is floor-anonymous by
## construction: it reports that something changed, not which floor.
func accrue_for_tick() -> PackedInt32Array:
	var vacated := PackedInt32Array()
	# Iterates SLOTS and returns FLOORS. The two were the same number while the
	# bottom floor was 0; with a basement they diverge, and the caller uses the
	# result to remove that floor's waiting passengers.
	for slot in range(_satisfaction.size()):
		if _vacant[slot]:
			continue
		if _move_out_left[slot] > 0:
			_move_out_left[slot] -= 1
			if _move_out_left[slot] <= 0:
				_vacant[slot] = true
				_kind[slot] = ""
				_revision += 1
				vacated.append(_index.bottom + slot)
	return vacated

func satisfaction_at(floor_index: int) -> float:
	return _satisfaction[_index.slot(floor_index)] if _valid(floor_index) else 0.0

## The floors that generate trips. A vacant floor is nobody to carry: it is
## neither an origin nor a destination.
func occupied_floors() -> PackedInt32Array:
	var out := PackedInt32Array()
	# Slots in, FLOORS out -- see accrue_for_tick.
	for slot in range(_vacant.size()):
		if not _vacant[slot]:
			out.append(_index.bottom + slot)
	return out

func is_vacant(floor_index: int) -> bool:
	return _vacant[_index.slot(floor_index)] if _valid(floor_index) else true

func is_moving_out(floor_index: int) -> bool:
	return _valid(floor_index) and not _vacant[_index.slot(floor_index)] and _move_out_left[_index.slot(floor_index)] > 0

func move_out_ticks_left(floor_index: int) -> int:
	return _move_out_left[_index.slot(floor_index)] if _valid(floor_index) else 0

func tenanted_count() -> int:
	var n := 0
	for slot in range(_vacant.size()):
		if not _vacant[slot]:
			n += 1
	return n

## Free while the player cannot earn. Under directional traffic a lone tenant
## COULD generate lobby trips, so this is now a deliberate policy guard rather
## than arithmetic -- but the guarantee it protects is unchanged: there must
## always be something a $0 player can take.
const MIN_FLOORS_FOR_TRAFFIC := 2

func lease(floor_index: int, kind_id: String) -> void:
	if not _valid(floor_index):
		return
	_vacant[_index.slot(floor_index)] = false
	_satisfaction[_index.slot(floor_index)] = 1.0
	_move_out_left[_index.slot(floor_index)] = 0
	_kind[_index.slot(floor_index)] = kind_id
	_revision += 1

## The BUILDING's floor range, not the array's bounds. Checking the array would
## accept floor 0 on a two-deep building and hand back floor -2's slot: in
## range, wrong answer, nothing raised.
func _valid(floor_index: int) -> bool:
	return _index != null and _index.holds(floor_index)
