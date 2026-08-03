class_name Tenancy
extends RefCounted

## Per-row tenants. Satisfaction tracks recent service and scales rent
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
## NO FAIL STATE, guaranteed by ONE rule: re-leasing is free whenever the player
## cannot generate traffic, which is whenever FEWER THAN TWO rows are tenanted.
## A trip needs an origin and a destination, so a single tenanted floor earns
## exactly as much as none -- and charging for the re-lease that would fix it
## would strand the player with no income and no way back.
##
## Any row, including the lobby, may vacate. A second rule ("the lobby never
## vacates") would make this guard unreachable and the recovery test unwritable,
## because its setup would be forbidden.

const MOVE_OUT_THRESHOLD := 0.2
const MOVE_OUT_TICKS := 1200          # one simulated minute of grace
const RELET_COST := 40.0

const _DELIVERY_GAIN := 0.02
const _EXPIRY_LOSS := 0.05

var _satisfaction: PackedFloat32Array = PackedFloat32Array()
var _vacant: Array[bool] = []
var _move_out_left: PackedInt32Array = PackedInt32Array()
var _kind: PackedStringArray = PackedStringArray()
var _revision: int = 0

## `tenanted_prefix` is how many LEADING rows start with a tenant. Everything
## past it arrives vacant with no kind, so a constructed floor and a purchased
## one agree.
##
## The divergence is by row INDEX, not by entry point. _append_row is shared
## with add_row, and flipping the append itself would make every floor of a new
## building vacant; vacating only in add_row would leave a tall constructed
## building fully tenanted and kindless. So both callers vacate, by index.
func _init(row_count: int, tenanted_prefix: int) -> void:
	for i in range(row_count):
		_append_row()
		if i >= tenanted_prefix:
			_vacant[i] = true

func _append_row() -> void:
	_satisfaction.append(1.0)
	_vacant.append(false)
	_move_out_left.append(0)
	_kind.append("")

func add_row() -> void:
	_append_row()
	_vacant[_vacant.size() - 1] = true
	_revision += 1

## How many rows tenancy covers. Callers that grow the building need this to
## know how far behind tenancy has fallen -- is_vacant() cannot answer it,
## because an out-of-range row reports vacant rather than absent.
func rows() -> int:
	return _satisfaction.size()

## Monotonic revision bumping on every structural change. A cached TrafficSource
## list compares this against its last-seen baseline to learn it is stale.
func revision() -> int:
	return _revision

## Restores one row from a save. Satisfaction scales rent and a vacancy is a
## debt, so neither can be inferred from anything else in the file.
func restore_row(row: int, satisfaction: float, vacant: bool, move_out_left: int,
		kind := "") -> void:
	if not _valid(row):
		return
	_satisfaction[row] = clampf(satisfaction, 0.0, 1.0)
	_vacant[row] = vacant
	_move_out_left[row] = maxi(move_out_left, 0)
	_kind[row] = "" if vacant else kind
	_revision += 1

func kind_at(row: int) -> String:
	return _kind[row] if _valid(row) else ""

func set_kind(row: int, kind_id: String) -> void:
	if not _valid(row):
		return
	_kind[row] = kind_id
	_revision += 1

func note_delivery(row: int) -> void:
	if not _valid(row) or _vacant[row]:
		return
	_satisfaction[row] = clampf(_satisfaction[row] + _DELIVERY_GAIN, 0.0, 1.0)
	if _satisfaction[row] > MOVE_OUT_THRESHOLD:
		_move_out_left[row] = 0

func note_expiry(row: int) -> void:
	if not _valid(row) or _vacant[row]:
		return
	_satisfaction[row] = clampf(_satisfaction[row] - _EXPIRY_LOSS, 0.0, 1.0)
	if _satisfaction[row] <= MOVE_OUT_THRESHOLD and _move_out_left[row] <= 0:
		_move_out_left[row] = MOVE_OUT_TICKS

## Advances move-out countdowns and RETURNS the rows that vacated on this tick.
##
## The docstring this replaces said "returns nothing", meaning tenants are not
## an income source -- a rejection of rent, not of all return values. The row
## identity is needed because a vacating floor's waiting passengers have to be
## removed by source, and a revision counter is floor-anonymous by
## construction: it reports that something changed, not which floor.
func accrue_for_tick() -> PackedInt32Array:
	var vacated := PackedInt32Array()
	for row in range(_satisfaction.size()):
		if _vacant[row]:
			continue
		if _move_out_left[row] > 0:
			_move_out_left[row] -= 1
			if _move_out_left[row] <= 0:
				_vacant[row] = true
				_kind[row] = ""
				_revision += 1
				vacated.append(row)
	return vacated

func satisfaction_at(row: int) -> float:
	return _satisfaction[row] if _valid(row) else 0.0

## The floors that generate trips. A vacant floor is nobody to carry: it is
## neither an origin nor a destination.
func occupied_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	for row in range(_vacant.size()):
		if not _vacant[row]:
			out.append(row)
	return out

func is_vacant(row: int) -> bool:
	return _vacant[row] if _valid(row) else true

func is_moving_out(row: int) -> bool:
	return _valid(row) and not _vacant[row] and _move_out_left[row] > 0

func move_out_ticks_left(row: int) -> int:
	return _move_out_left[row] if _valid(row) else 0

func tenanted_count() -> int:
	var n := 0
	for row in range(_vacant.size()):
		if not _vacant[row]:
			n += 1
	return n

## Free while the player cannot earn. A trip needs two tenanted floors, so one
## tenant earns exactly what none does; charging to escape that would be a fail
## state with a price tag on the exit.
const MIN_ROWS_FOR_TRAFFIC := 2

func relet_cost(_row: int) -> float:
	return 0.0 if tenanted_count() < MIN_ROWS_FOR_TRAFFIC else RELET_COST

func relet(row: int) -> void:
	if not _valid(row):
		return
	_vacant[row] = false
	_satisfaction[row] = 1.0
	_move_out_left[row] = 0
	_revision += 1

func _valid(row: int) -> bool:
	return row >= 0 and row < _satisfaction.size()
