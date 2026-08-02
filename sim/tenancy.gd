class_name Tenancy
extends RefCounted

## Per-row tenants. Satisfaction tracks recent service and scales rent
## continuously; below a threshold a visible countdown starts, giving the
## player a chance to recover it.
##
## NO FAIL STATE, guaranteed by ONE rule: re-leasing is free whenever the
## player holds zero tenanted rows. Any row, including the lobby, may vacate.
## A second rule ("the lobby never vacates") would make this guard unreachable
## and would make the recovery test unwritable, because its setup would be
## forbidden.

const MOVE_OUT_THRESHOLD := 0.2
const MOVE_OUT_TICKS := 1200          # one simulated minute of grace
const BASE_RENT_PER_MINUTE := 6.0
const RELET_COST := 40.0

const _DELIVERY_GAIN := 0.02
const _EXPIRY_LOSS := 0.05

var _satisfaction: PackedFloat32Array = PackedFloat32Array()
var _vacant: Array[bool] = []
var _move_out_left: PackedInt32Array = PackedInt32Array()

func _init(row_count: int) -> void:
	for i in range(row_count):
		_append_row()

func _append_row() -> void:
	_satisfaction.append(1.0)
	_vacant.append(false)
	_move_out_left.append(0)

func add_row() -> void:
	_append_row()

## How many rows tenancy covers. Callers that grow the building need this to
## know how far behind tenancy has fallen -- is_vacant() cannot answer it,
## because an out-of-range row reports vacant rather than absent.
func rows() -> int:
	return _satisfaction.size()

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

## Advances move-out countdowns and returns this tick's total rent.
func accrue_for_tick() -> float:
	var total := 0.0
	for row in range(_satisfaction.size()):
		if _vacant[row]:
			continue
		if _move_out_left[row] > 0:
			_move_out_left[row] -= 1
			if _move_out_left[row] <= 0:
				_vacant[row] = true
				continue
		total += rent_at(row) / float(SimClock.TICKS_PER_MINUTE)
	return total

func satisfaction_at(row: int) -> float:
	return _satisfaction[row] if _valid(row) else 0.0

func rent_at(row: int) -> float:
	if not _valid(row) or _vacant[row]:
		return 0.0
	return BASE_RENT_PER_MINUTE * _satisfaction[row]

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

## Free when nothing is tenanted -- this is the whole no-fail guarantee.
func relet_cost(_row: int) -> float:
	return 0.0 if tenanted_count() == 0 else RELET_COST

func relet(row: int) -> void:
	if not _valid(row):
		return
	_vacant[row] = false
	_satisfaction[row] = 1.0
	_move_out_left[row] = 0

func _valid(row: int) -> bool:
	return row >= 0 and row < _satisfaction.size()
