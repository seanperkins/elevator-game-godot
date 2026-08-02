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

var _preset: PackedInt32Array = PackedInt32Array()
var _policy: Array = []
var _direction: PackedInt32Array = PackedInt32Array()

func _grow_to(count: int) -> void:
	while _preset.size() < count:
		_preset.append(DispatchPolicy.Preset.MANUAL)
		_policy.append(null)
		_direction.append(1)          # a new car sweeps upward first

func is_enabled(shaft: int) -> bool:
	return preset_of(shaft) != DispatchPolicy.Preset.MANUAL

func preset_of(shaft: int) -> int:
	if shaft < 0 or shaft >= _preset.size():
		return DispatchPolicy.Preset.MANUAL
	return _preset[shaft]

func enabled_count() -> int:
	var n := 0
	for p in _preset:
		if p != DispatchPolicy.Preset.MANUAL:
			n += 1
	return n

## The resolved policy is passed in rather than built here: which blocks are
## available depends on installed hardware, which GameState knows and this does
## not.
func set_policy(shaft: int, preset: int, policy: DispatchPolicy) -> void:
	if shaft < 0:
		return
	_grow_to(shaft + 1)
	_preset[shaft] = preset
	_policy[shaft] = policy

func set_enabled(shaft: int, on: bool) -> void:
	set_policy(shaft,
		DispatchPolicy.Preset.EVERY_FLOOR if on else DispatchPolicy.Preset.MANUAL,
		DispatchPolicy.preset_policy(DispatchPolicy.Preset.EVERY_FLOOR) if on else null)

## Sends every idle enabled car to the next floor in its sweep. Cars bought
## later are covered because the pools grow to the building.
func step(building: Building) -> void:
	_grow_to(building.cars.size())
	var waiting := _waiting_floors(building)
	for i in range(building.cars.size()):
		var policy: DispatchPolicy = _policy[i]
		if policy == null:
			continue
		var car: ElevatorCar = building.cars[i]
		if car.state != ElevatorCar.State.IDLE:
			continue
		var result := policy.choose(car.current_row(), building.row_count,
			waiting, _rider_floors(car), _direction[i],
			car.riders.size() >= car.capacity)
		_direction[i] = result.y
		if result.x == DispatchPolicy.STAY_PUT or result.x == car.current_row():
			continue
		if ElevatorCar.is_spring_trip(car.current_row(), result.x, building.row_count) \
				and car.spring_multiplier > 1.0:
			car.launch_to(result.x)
		else:
			car.dispatch_to(result.x)

## Which floors have somebody on them. This is what hall call buttons report --
## a policy without them never receives this list.
func _waiting_floors(building: Building) -> PackedInt32Array:
	var out := PackedInt32Array()
	for row in range(building.row_count):
		if not building.waiting_at(row).is_empty():
			out.append(row)
	return out

## Where the people already aboard want to go: the car call buttons.
func _rider_floors(car: ElevatorCar) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in car.riders:
		out.append(p.destination_row)
	return out
