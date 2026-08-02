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

## The lobby launch spring: a mechanical assist that throws the car from the
## lobby straight to the top. 1.0 means none fitted.
var spring_multiplier: float = 1.0

var _door_remaining: int = 0
var _launched: bool = false

func _init(start_row: int) -> void:
	position_row = float(start_row)
	target_row = start_row

## A spring trip is the lobby to the top floor and nothing else. Whoever
## dispatches decides, because the car does not know how tall the building is.
static func is_spring_trip(from: int, to: int, row_count: int) -> bool:
	return row_count > 1 and from == 0 and to == row_count - 1

## A launched car is COMMITTED: it cannot be stopped or redirected until it
## arrives. That is the trade the spring makes -- four times the speed, and no
## way off in between.
func is_committed() -> bool:
	return _launched and state == State.MOVING

func launch_to(row: int) -> void:
	dispatch_to(row, true)

## `express` is passed rather than set around the call: setting it beforehand
## and letting dispatch_to clear it is order-dependent, and it silently undid
## every launch.
func dispatch_to(row: int, express := false) -> void:
	if is_committed():
		return
	_launched = express
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
	var rate := rows_per_tick * (spring_multiplier if _launched else 1.0)
	var travel := rate * float(delta_ticks)
	var remaining := float(target_row) - position_row
	if absf(remaining) <= travel:
		position_row = float(target_row)   # snap; never overshoot
		_launched = false
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

## A stop has three phases: the doors slide open, people move, the doors slide
## shut. `door_ticks` is the WHOLE stop, and these split it.
##
## Boarding before the doors are open is a rule violation, not a cosmetic one --
## it was simply invisible until the doors were drawn, at which point passengers
## were seen stepping through shut panels.
##
## A quarter of the stop each end, but never so much that the open window
## vanishes: at a one-tick stop the doors are already open, because a stop
## nobody can board is worse than one with no animation.
func door_opening_ticks() -> int:
	return mini(maxi(door_ticks / 4, 1), maxi(door_ticks - 1, 0))

func door_closing_ticks() -> int:
	return clampi(door_ticks / 4, 0, maxi(door_ticks - door_opening_ticks() - 1, 0))

## Ticks since this stop began. Meaningful only while the doors are in play.
func door_elapsed_ticks() -> int:
	return door_ticks - _door_remaining

## A car parked at a floor answers a call there by opening its doors.
##
## It does NOT move, so this is not dispatch automation: choosing where the car
## goes stays the player's job. Without it a car sitting on a floor ignores
## somebody standing next to it until the player dispatches it to the floor it
## is already on, which reads as broken rather than as a rule.
##
## Refused when full, because cycling the doors for someone who cannot board
## costs dwell and shows an opening the player cannot use.
func answer_call() -> bool:
	if state != State.IDLE or riders.size() >= capacity:
		return false
	_open_doors()
	return true

func current_row() -> int:
	return int(roundf(position_row))

## Boarding and alighting happen only while the doors are OPEN -- not merely
## while the car is stopped. The window excludes the opening and closing slides,
## so what the player sees and what the sim allows are the same thing.
func is_available() -> bool:
	if state != State.DOORS:
		return false
	var elapsed := door_elapsed_ticks()
	return elapsed >= door_opening_ticks() \
		and elapsed < door_ticks - door_closing_ticks()

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
