class_name GameState
extends RefCounted

## Owns the whole simulation and runs one tick in a FIXED, WRITTEN order.
## Determinism is meaningless without a stated order, and the order is
## player-visible: deliver-before-expire decides whether a passenger reaching
## exactly 0.0 patience as the doors open pays and extends the combo, or
## expires and breaks it.
##
##   advance metrics -> spawn -> move/doors -> deliver -> auto-dispatch
##     -> expire -> accrue rent -> update combo
##
## Metrics advances FIRST so the bucket a tick's events land in is the bucket
## that tick just rolled into, and no event is written to a bucket about to be
## cleared.
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
var tenancy: Tenancy
var upgrades: Upgrades
var metrics: Metrics
var auto: AutoDispatch

func _init(rows: int, shafts: int, p_seed: int) -> void:
	clock = SimClock.new()
	building = Building.new(rows, shafts)
	spawner = TrafficSpawner.new(p_seed)
	spawner.load_curve("res://data/traffic_walkup.json")
	economy = Economy.new()
	tenancy = Tenancy.new(rows)
	upgrades = Upgrades.new()
	upgrades.load_defs("res://data/upgrades.json")
	metrics = Metrics.new()
	auto = AutoDispatch.new()

## Buying a row extends the board, so tenancy must grow with it.
##
## The guard reads tenancy.rows(), not a tenanted/vacant tally: is_vacant()
## reports true for a row tenancy does not have, so counting vacancies over the
## NEW row_count always equals it and the loop would never run.
func buy(id: String) -> bool:
	var ok := upgrades.purchase(id, economy, building)
	if ok:
		while tenancy.rows() < building.row_count:
			tenancy.add_row()
		_resync_policies()
	return ok

## Re-lease a vacant floor. Until now nothing in the game charged for this:
## Tenancy.relet() restores a tenant without touching Economy and
## Tenancy.relet_cost() had no caller outside tests, so wiring the view straight
## to tenancy would have made re-leasing free forever -- hollowing out §5.3's
## guarantee, which is that re-leasing is free CONDITIONALLY.
##
## The cost is read BEFORE the relet: relet_cost derives from tenanted_count,
## and relet() increments it, so the order decides whether the last row costs
## nothing or forty dollars.
func relet(row: int) -> bool:
	if row < 0 or row >= building.row_count:
		return false
	if not tenancy.is_vacant(row):
		return false
	var cost := tenancy.relet_cost(row)
	if not economy.spend(cost):
		return false
	tenancy.relet(row)
	return true

## Turning a sweep on needs a LICENCE: the Auto-Dispatch upgrade's level is how
## many shafts may run a policy at once. Enforced here rather than in the view,
## for the same reason the zero-delta refusal is -- a greyed-out button is
## bypassed by two taps queued during a stalled frame.
##
## Turning one OFF is always allowed, and hands the licence back.
func set_auto(shaft: int, on: bool) -> bool:
	return set_policy(shaft,
		DispatchPolicy.Preset.EVERY_FLOOR if on else DispatchPolicy.Preset.MANUAL)

## Puts a shaft on a named policy. Refused when the shaft does not exist, when
## the hardware the policy needs is not installed, or when every licence is
## already spent -- all in the sim, because a greyed-out button is bypassed by
## two taps queued during a stalled frame.
func set_policy(shaft: int, preset: int) -> bool:
	if shaft < 0 or shaft >= building.cars.size():
		return false
	if preset == DispatchPolicy.Preset.MANUAL:
		auto.set_policy(shaft, preset, null)
		return true
	if not is_preset_available(preset):
		return false
	if not auto.is_enabled(shaft) and auto.enabled_count() >= auto_licences():
		return false
	auto.set_policy(shaft, preset, _build_policy(preset))
	return true

## Every piece of hardware the preset needs has to be fitted. An algorithm
## cannot be smarter than the sensors feeding it.
func is_preset_available(preset: int) -> bool:
	if preset == DispatchPolicy.Preset.MANUAL:
		return true
	for id in DispatchPolicy.preset_requires(preset):
		if not upgrades.is_installed(id):
			return false
	return true

func available_presets() -> Array:
	var out := []
	for preset in DispatchPolicy.PRESET_ORDER:
		if is_preset_available(preset):
			out.append(preset)
	return out

## Hardware fitted after a policy was chosen still applies to it, which is why
## buying a load weigher improves shafts already running.
func _build_policy(preset: int) -> DispatchPolicy:
	var policy := DispatchPolicy.preset_policy(preset)
	if policy != null:
		policy.bypass_when_full = upgrades.is_installed("load_sensor")
	return policy

func _resync_policies() -> void:
	for shaft in range(building.cars.size()):
		var preset := auto.preset_of(shaft)
		if preset == DispatchPolicy.Preset.MANUAL:
			continue
		auto.set_policy(shaft, preset, _build_policy(preset))

## How many shafts may run a dispatch policy at once.
func auto_licences() -> int:
	return upgrades.level_of("auto")

func dispatch(shaft_index: int, row: int) -> bool:
	if shaft_index < 0 or shaft_index >= building.cars.size():
		return false
	if row < 0 or row >= building.row_count:
		return false
	var car: ElevatorCar = building.cars[shaft_index]
	if car.is_committed():
		return false                    # a launched car cannot be called off
	if ElevatorCar.is_spring_trip(car.current_row(), row, building.row_count) \
			and car.spring_multiplier > 1.0:
		car.launch_to(row)
	else:
		car.dispatch_to(row)
	return true

func tick(n: int) -> void:
	for i in range(n):
		_tick_once()

func _tick_once() -> void:
	metrics.advance()      # first: clears the bucket this tick will write into
	_spawn()
	_move_and_doors()
	_deliver()
	# After deliver, so a car that has just finished unloading is idle and can
	# be sent on this tick; and after move/doors, so a car answering a call at
	# its own floor gets first refusal before the policy moves it.
	auto.step(building)
	_expire()
	economy.accrue(tenancy.accrue_for_tick())
	# update combo -- handled inside Economy on each delivery/expiry
	clock.note_ticks(1)

func _spawn() -> void:
	for p in spawner.spawn_for_tick(clock.sim_minute(), building.row_count):
		building.enqueue(p)
		passenger_spawned.emit(p)

## Doors are owned by this phase, which is why answering a call happens here
## rather than in _deliver: a car that opens here is DOORS by the time boarding
## runs, exactly as an arriving car is, so both paths board on the same tick.
func _move_and_doors() -> void:
	for i in range(building.cars.size()):
		var car: ElevatorCar = building.cars[i]
		var was_moving := car.state == ElevatorCar.State.MOVING
		car.step(1)
		if was_moving and car.state == ElevatorCar.State.DOORS:
			car_arrived.emit(i, car.current_row())
		if not building.waiting_at(car.current_row()).is_empty():
			car.answer_call()

## Alight first, then board -- riders leaving free the seats arrivals take.
func _deliver() -> void:
	for car in building.cars:
		if not car.is_available():
			continue
		for p in car.take_arrivals():
			var paid := economy.credit_delivery(p.fare)
			# The destination row's tenant is the one whose visitor arrived.
			tenancy.note_delivery(p.destination_row)
			metrics.record_delivery(p.waited_ticks())
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
				tenancy.note_expiry(p.origin_row)
				metrics.record_expiry()
				passenger_expired.emit(p)
			else:
				survivors.append(p)
		building.waiting[row] = survivors
