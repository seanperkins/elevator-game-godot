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
## tenanted_count() >= MIN_ROWS_FOR_TRAFFIC; Tenancy owns the threshold and
## the kind the lease writes.
##
## Any floor, including the lobby, may vacate. A second rule ("the lobby never
## vacates") would make this guard unreachable and the recovery test unwritable,
## because its setup would be forbidden.

const MOVE_OUT_THRESHOLD := 0.2
const MOVE_OUT_TICKS := 1200          # one simulated minute of grace

const _DELIVERY_GAIN := 0.02
const _EXPIRY_LOSS := 0.05

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
func _init(floor_count: int, tenanted_prefix: int) -> void:
	for i in range(floor_count):
		_append_floor()
		if i >= tenanted_prefix:
			_vacant[i] = true

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
	_satisfaction[floor_index] = clampf(satisfaction, 0.0, 1.0)
	_vacant[floor_index] = vacant
	_move_out_left[floor_index] = maxi(move_out_left, 0)
	_kind[floor_index] = "" if vacant else kind
	_revision += 1

func kind_at(floor_index: int) -> String:
	return _kind[floor_index] if _valid(floor_index) else ""

func set_kind(floor_index: int, kind_id: String) -> void:
	if not _valid(floor_index):
		return
	_kind[floor_index] = kind_id
	_revision += 1

func note_delivery(floor_index: int) -> void:
	if not _valid(floor_index) or _vacant[floor_index]:
		return
	_satisfaction[floor_index] = clampf(_satisfaction[floor_index] + _DELIVERY_GAIN, 0.0, 1.0)
	if _satisfaction[floor_index] > MOVE_OUT_THRESHOLD:
		_move_out_left[floor_index] = 0

func note_expiry(floor_index: int) -> void:
	if not _valid(floor_index) or _vacant[floor_index]:
		return
	_satisfaction[floor_index] = clampf(_satisfaction[floor_index] - _EXPIRY_LOSS, 0.0, 1.0)
	if _satisfaction[floor_index] <= MOVE_OUT_THRESHOLD and _move_out_left[floor_index] <= 0:
		_move_out_left[floor_index] = MOVE_OUT_TICKS

## Advances move-out countdowns and RETURNS the floors that vacated on this tick.
##
## The docstring this replaces said "returns nothing", meaning tenants are not
## an income source -- a rejection of rent, not of all return values. The floor
## identity is needed because a vacating floor's waiting passengers have to be
## removed by source, and a revision counter is floor-anonymous by
## construction: it reports that something changed, not which floor.
func accrue_for_tick() -> PackedInt32Array:
	var vacated := PackedInt32Array()
	for floor_index in range(_satisfaction.size()):
		if _vacant[floor_index]:
			continue
		if _move_out_left[floor_index] > 0:
			_move_out_left[floor_index] -= 1
			if _move_out_left[floor_index] <= 0:
				_vacant[floor_index] = true
				_kind[floor_index] = ""
				_revision += 1
				vacated.append(floor_index)
	return vacated

func satisfaction_at(floor_index: int) -> float:
	return _satisfaction[floor_index] if _valid(floor_index) else 0.0

## The floors that generate trips. A vacant floor is nobody to carry: it is
## neither an origin nor a destination.
func occupied_floors() -> PackedInt32Array:
	var out := PackedInt32Array()
	for floor_index in range(_vacant.size()):
		if not _vacant[floor_index]:
			out.append(floor_index)
	return out

func is_vacant(floor_index: int) -> bool:
	return _vacant[floor_index] if _valid(floor_index) else true

func is_moving_out(floor_index: int) -> bool:
	return _valid(floor_index) and not _vacant[floor_index] and _move_out_left[floor_index] > 0

func move_out_ticks_left(floor_index: int) -> int:
	return _move_out_left[floor_index] if _valid(floor_index) else 0

func tenanted_count() -> int:
	var n := 0
	for floor_index in range(_vacant.size()):
		if not _vacant[floor_index]:
			n += 1
	return n

## Free while the player cannot earn. Under directional traffic a lone tenant
## COULD generate lobby trips, so this is now a deliberate policy guard rather
## than arithmetic -- but the guarantee it protects is unchanged: there must
## always be something a $0 player can take.
const MIN_ROWS_FOR_TRAFFIC := 2

func lease(floor_index: int, kind_id: String) -> void:
	if not _valid(floor_index):
		return
	_vacant[floor_index] = false
	_satisfaction[floor_index] = 1.0
	_move_out_left[floor_index] = 0
	_kind[floor_index] = kind_id
	_revision += 1

func _valid(floor_index: int) -> bool:
	return floor_index >= 0 and floor_index < _satisfaction.size()
