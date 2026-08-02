class_name AutoDispatch
extends RefCounted

## The first dispatch policy: a shaft set to sweep visits every floor in turn,
## reversing at the ends.
##
## It only ever commands an IDLE car. A car in transit is committed to the trip
## it was given, and a car with its doors open is boarding -- taking either
## would read as sabotage, and stealing a boarding car would silently undo the
## rule that a parked car answers calls at its own floor.
##
## A manual dispatch therefore always wins: the player's trip runs to its end
## and the sweep picks up from wherever the car came to rest. The policy is a
## floor under the player, not a replacement for them.
##
## WHICH shafts may sweep is licensed by the Auto-Dispatch upgrade, and that is
## enforced in GameState.set_auto rather than here. This class is the mechanism;
## the gate belongs with the thing that knows what has been bought.

var _enabled: Array[bool] = []
var _direction: PackedInt32Array = PackedInt32Array()

func _grow_to(count: int) -> void:
	while _enabled.size() < count:
		_enabled.append(false)
		_direction.append(1)          # a new car sweeps upward first

func is_enabled(shaft: int) -> bool:
	return shaft >= 0 and shaft < _enabled.size() and _enabled[shaft]

func enabled_count() -> int:
	var n := 0
	for on in _enabled:
		if on:
			n += 1
	return n

func set_enabled(shaft: int, on: bool) -> void:
	if shaft < 0:
		return
	_grow_to(shaft + 1)
	_enabled[shaft] = on

## Sends every idle enabled car to the next floor in its sweep. Cars bought
## later are covered because the pools grow to the building.
func step(building: Building) -> void:
	_grow_to(building.cars.size())
	for i in range(building.cars.size()):
		if not _enabled[i]:
			continue
		var car: ElevatorCar = building.cars[i]
		if car.state != ElevatorCar.State.IDLE:
			continue
		var next := _next_row(car.current_row(), i, building.row_count)
		if next != car.current_row():
			car.dispatch_to(next)

## Reverses at the ends rather than walking out of the building. A one-floor
## building has nowhere to go and says so by returning where it already is,
## instead of cycling the doors forever on the spot.
func _next_row(from: int, shaft: int, row_count: int) -> int:
	if row_count <= 1:
		return from
	var step_to := from + _direction[shaft]
	if step_to < 0 or step_to >= row_count:
		_direction[shaft] = -_direction[shaft]
		step_to = from + _direction[shaft]
	return clampi(step_to, 0, row_count - 1)
