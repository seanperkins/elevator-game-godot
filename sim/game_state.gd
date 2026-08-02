class_name GameState
extends RefCounted

## Owns the whole simulation and runs one tick in a FIXED, WRITTEN order.
## Determinism is meaningless without a stated order, and the order is
## player-visible: deliver-before-expire decides whether a passenger reaching
## exactly 0.0 patience as the doors open pays and extends the combo, or
## expires and breaks it.
##
##   spawn -> move/doors -> deliver -> expire -> accrue rent -> update combo
##
## This class never touches the scene tree. It talks to the view by signal only.

signal passenger_spawned(p: Passenger)
signal passenger_delivered(p: Passenger, paid: float)
signal passenger_expired(p: Passenger)
signal car_arrived(shaft_index: int, row: int)

var clock: SimClock
var building: Building
var spawner: TrafficSpawner
var economy: Economy

func _init(rows: int, shafts: int, p_seed: int) -> void:
	clock = SimClock.new()
	building = Building.new(rows, shafts)
	spawner = TrafficSpawner.new(p_seed)
	spawner.load_curve("res://data/traffic_walkup.json")
	economy = Economy.new()

func dispatch(shaft_index: int, row: int) -> bool:
	if shaft_index < 0 or shaft_index >= building.cars.size():
		return false
	if row < 0 or row >= building.row_count:
		return false
	building.cars[shaft_index].dispatch_to(row)
	return true

func tick(n: int) -> void:
	for i in range(n):
		_tick_once()

func _tick_once() -> void:
	_spawn()
	_move_and_doors()
	_deliver()
	_expire()
	# accrue rent -- Milestone 2 (tenancy)
	# update combo -- handled inside Economy on each delivery/expiry
	clock.note_ticks(1)

func _spawn() -> void:
	for p in spawner.spawn_for_tick(clock.sim_minute(), building.row_count):
		building.enqueue(p)
		passenger_spawned.emit(p)

func _move_and_doors() -> void:
	for i in range(building.cars.size()):
		var car: ElevatorCar = building.cars[i]
		var was_moving := car.state == ElevatorCar.State.MOVING
		car.step(1)
		if was_moving and car.state == ElevatorCar.State.DOORS:
			car_arrived.emit(i, car.current_row())

## Alight first, then board -- riders leaving free the seats arrivals take.
func _deliver() -> void:
	for car in building.cars:
		if not car.is_available():
			continue
		for p in car.take_arrivals():
			var paid := economy.credit_delivery(p.fare)
			passenger_delivered.emit(p, paid)
		var seats := car.capacity - car.riders.size()
		for p in building.take_boardable(car.current_row(), seats):
			car.board(p)

## Waiting passengers decay. Riders aboard a car do not -- they are being
## served. Expiry runs AFTER delivery so the zero boundary favours the player.
func _expire() -> void:
	for row in range(building.row_count):
		var queue: Array[Passenger] = building.waiting[row]
		var survivors: Array[Passenger] = []
		for p in queue:
			p.decay(1)
			if p.is_expired():
				economy.note_expiry()
				passenger_expired.emit(p)
			else:
				survivors.append(p)
		building.waiting[row] = survivors
