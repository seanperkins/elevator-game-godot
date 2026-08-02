class_name ElevatorCar
extends RefCounted

## Deliberately fake physics: position lerps toward the target stop. The sim
## must run hundreds of passengers, not be accurate. Door dwell dominates trip
## time early on, which is what makes "faster doors" a strong first purchase.

enum State { IDLE, MOVING, DOORS }

var position_row: float
var target_row: int
var state: int = State.IDLE
var riders: Array[Passenger] = []

var capacity: int = 4
var rows_per_tick: float = 0.1
var door_ticks: int = 20

var _door_remaining: int = 0

func _init(start_row: int) -> void:
	position_row = float(start_row)
	target_row = start_row

func dispatch_to(row: int) -> void:
	target_row = row
	if is_equal_approx(position_row, float(row)):
		position_row = float(row)
		_open_doors()
	else:
		state = State.MOVING

func step(delta_ticks: int) -> void:
	match state:
		State.MOVING:
			_step_moving(delta_ticks)
		State.DOORS:
			_step_doors(delta_ticks)
		_:
			pass

func _step_moving(delta_ticks: int) -> void:
	var travel := rows_per_tick * float(delta_ticks)
	var remaining := float(target_row) - position_row
	if absf(remaining) <= travel:
		position_row = float(target_row)   # snap; never overshoot
		_open_doors()
	else:
		position_row += signf(remaining) * travel

func _step_doors(delta_ticks: int) -> void:
	_door_remaining -= delta_ticks
	if _door_remaining <= 0:
		_door_remaining = 0
		state = State.IDLE

func _open_doors() -> void:
	state = State.DOORS
	_door_remaining = door_ticks

func current_row() -> int:
	return int(roundf(position_row))

## Boarding and alighting happen only while the doors are open.
func is_available() -> bool:
	return state == State.DOORS

func board(p: Passenger) -> bool:
	if not is_available() or riders.size() >= capacity:
		return false
	p.boarded = true
	riders.append(p)
	return true

## Removes and returns the riders whose destination is the current row.
func take_arrivals() -> Array[Passenger]:
	var out: Array[Passenger] = []
	if not is_available():
		return out
	var row := current_row()
	var staying: Array[Passenger] = []
	for p in riders:
		if p.destination_row == row:
			out.append(p)
		else:
			staying.append(p)
	riders = staying
	return out
