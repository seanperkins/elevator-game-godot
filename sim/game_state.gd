class_name GameState
extends RefCounted

## Owns the whole simulation and runs one tick in a FIXED, WRITTEN order.
## Determinism is meaningless without a stated order, and the order is
## player-visible: deliver-before-expire decides whether a passenger reaching
## exactly 0.0 patience as the doors open pays and extends the combo, or
## expires and breaks it.
##
##   advance metrics -> spawn -> move/doors -> deliver -> auto-dispatch
##     -> expire -> advance tenancy -> update combo
##
## Metrics advances FIRST so the bucket a tick's events land in is the bucket
## that tick just rolled into, and no event is written to a bucket about to be
## cleared.
##
## This class never touches the scene tree. It talks to the view by signal only.

signal passenger_spawned(p: Passenger)
signal passenger_delivered(p: Passenger, paid: float)
signal passenger_expired(p: Passenger)
signal car_arrived(shaft_index: int, floor_index: int)

var clock: SimClock
var building: Building
var spawner: TrafficSpawner
var economy: Economy
var tenancy: Tenancy
var fitout: Fitout
var catalog: TenantCatalog
var upgrades: Upgrades
var metrics: Metrics
var auto: AutoDispatch

var _source_cache: Array[TrafficSource] = []
var _entrance_cache: PackedInt32Array = PackedInt32Array()
## The building's day, cached against the SAME revision as the sources it is
## derived from. Recomputing it per frame would be 24 x floors of arithmetic at
## 60Hz on a threadless export, for a curve that only moves when somebody leases.
var _day_rates: PackedFloat32Array = PackedFloat32Array()
var _day_mixes: Array[Vector3] = []
var _day_revision: int = -1
var _source_revision: int = -1

## The starting assignment: six kind ids, one per floor from the lobby up. NOT
## the catalog's length -- adding a seventh KIND must not tenant a seventh ROW.
## Both the tenanted-floor count and those floors' kinds derive from this one list,
## so they cannot drift.
const DEFAULT_ROSTER: Array[String] = ["shops", "apartments", "apartments",
	"apartments", "apartments", "apartments"]

## The size and seed a building BEGINS at. They live here rather than in
## game_root because game/game_root.gd has no class_name (line 1 is a bare
## `extends Control`), and sim/ must not reach into game/ regardless.
const BASE_FLOORS := 6
const BASE_SHAFTS := 1
const BASE_SEED := 20260802

## The persistent half of the game. GameState READS it and never writes it --
## crediting is Prestige's job and spending is Meta.buy's.
var meta: Meta

## Kept rather than consumed and dropped, so Prestige.demolish can rebuild
## against the same catalogs this run used instead of silently reverting to the
## shipped ones and defeating every override.
var _catalog_path: String = ""
var _blueprints_path: String = ""

## Defaults to FALSE and is set true as the LAST statement of _init.
##
## Verified on Godot 4.7: a constructor that errors returns a HALF-BUILT object
## -- every field below the abort point at its declared default -- and the
## caller resumes normally rather than unwinding. So `var _valid := true` hands
## back a GameState whose clock or catalog may be null and whose is_valid()
## says yes. This is the single enforcement point for the fatal-shipped-data
## rule, and a gate whose default is `pass` cannot do that job.
var _valid: bool = false

## Which file made this state invalid, so the boot path can name it on screen
## rather than on a console the player cannot see. Empty when valid.
var _invalid_what: String = ""
var _invalid_path: String = ""

## p_meta goes AFTER catalog_path because tests/test_game_state.gd pins the
## fourth position as the catalog path.
func _init(floors: int, shafts: int, p_seed: int,
		catalog_path := "res://data/tenants.json",
		p_meta: Meta = null,
		blueprints_path := "res://data/blueprints.json") -> void:
	_catalog_path = catalog_path
	_blueprints_path = blueprints_path

	meta = p_meta if p_meta != null else Meta.new()
	if p_meta == null:
		meta.load_defs(blueprints_path)
	# NOT conditional on p_meta. An injected Meta whose defs failed is exactly
	# the case a `p_meta == null` guard waves through, and after the salvage
	# rewiring no production path constructs with a null Meta at all -- so such
	# a guard would put the only enforcement of the fatal-data rule on a branch
	# nobody takes.
	if not meta.is_usable():
		_invalid_what = "blueprint catalog"
		_invalid_path = blueprints_path
		return

	clock = SimClock.new()
	# VERBATIM, and _init NEVER resizes: the Meta's starting size is applied by
	# the callers that BEGIN a run (Prestige.demolish and game_root's cold
	# boot), because on the decode path the SAVED size is the authority. Growing
	# past saved_floors.size() here trips the codec's refusal, starts a fresh
	# game, and lets the autosave overwrite the only copy.
	building = Building.new(floors, shafts)
	spawner = TrafficSpawner.new(p_seed)
	spawner.load_curve("res://data/traffic_walkup.json")
	economy = Economy.new()

	# Before Tenancy, which needs the roster length. Nothing constructed above
	# needs the catalog, so this slots in with no cycle.
	catalog = TenantCatalog.new()
	if not catalog.load_from(catalog_path):
		# No push_error here: GUT counts it as a test error, which turns the
		# malformed-catalog refusal test red for the wrong reason. is_valid() is
		# the contract, and the boot path draws the path on an error screen
		# instead of relying on a console line a player cannot see.
		_invalid_what = "tenant catalog"
		_invalid_path = catalog_path
		return

	var prefix := mini(building.floor_count, DEFAULT_ROSTER.size())
	# The SAME FloorIndex instance, not two copies of a number. See
	# sim/floor_index.gd: a duplicated offset makes a desync silent.
	tenancy = Tenancy.new(building.index, prefix)
	fitout = Fitout.new(building.index)
	for floor_index in range(prefix):
		tenancy.set_kind(floor_index, DEFAULT_ROSTER[floor_index])

	upgrades = Upgrades.new()
	upgrades.load_defs("res://data/upgrades.json")
	metrics = Metrics.new()
	auto = AutoDispatch.new()

	# Everything below is AFTER upgrades.load_defs: following the reading order
	# above (building -> set_max_level) writes a crash on an empty _defs.
	#
	# The budgets are measured against the BASE size, never the current one.
	# The other way round is a LEVEL budget measured against a FLOOR COUNT,
	# correct only at level 0 -- and on reload the codec rebuilds at the grown
	# size and restores the cumulative purchase count on top of it, so a player
	# who started at 6 with a cap of 20 and bought 7 floors would come back
	# permanently capped 7 floors below what they paid for.
	upgrades.set_max_level("floor", meta.height_cap() - BASE_FLOORS)
	upgrades.set_max_level("shaft", meta.shaft_cap() - BASE_SHAFTS)
	# No base subtraction, unlike floor and shaft: a building starts at depth 0,
	# so every level of `dig` is a purchase.
	upgrades.set_max_level("dig", meta.depth_cap())
	upgrades.grant_level("floor", building.floor_count - BASE_FLOORS, building)
	upgrades.grant_level("shaft", building.cars.size() - BASE_SHAFTS, building)
	upgrades.grant_level("dig", building.depth, building)
	for id in ["speed", "doors", "capacity"]:
		upgrades.grant_level(id, meta.starting_level(id), building)

	_valid = true

## RefCounted cannot fail in _init, so construction records the failure and the
## boot path checks it. SaveCodec.decode returns null rather than handing back a
## poisoned state.
func is_valid() -> bool:
	return _valid

## The kind of file that made this state invalid ("tenant catalog"), for the
## error screen. Empty when valid.
func invalid_what() -> String:
	return _invalid_what

## The path of the file that made this state invalid. Empty when valid.
func invalid_path() -> String:
	return _invalid_path

## The catalogs this run was built against, so a demolish rebuilds against the
## same ones rather than the shipped defaults.
func catalog_path() -> String:
	return _catalog_path

func blueprints_path() -> String:
	return _blueprints_path

## Buying a floor extends the board, so tenancy must grow with it.
##
## The guard reads tenancy.floors(), not a tenanted/vacant tally: is_vacant()
## reports true for a floor tenancy does not have, so counting vacancies over the
## NEW floor_count always equals it and the loop would never run.
func buy(id: String) -> bool:
	var ok := upgrades.purchase(id, economy, building)
	if ok:
		_grow_per_floor_containers(id == "dig")
		_resync_policies()
	return ok

## ONE loop for every per-floor container. Two identical loops is how a
## container gets forgotten; the historic desync this replaces is pinned by
## test_buying_a_row_grows_every_per_floor_container, and Spec B adds a third
## container to this function rather than a third loop beside it.
## `downward` says WHICH END grew: a dig inserts at the front, a floor appends.
## The comparison is against total_floors() -- floor_count alone stopped being
## the container size the day the first basement was dug.
func _grow_per_floor_containers(downward := false) -> void:
	while tenancy.floors() < building.total_floors():
		if downward:
			tenancy.dig()
		else:
			tenancy.add_floor()
	while fitout.floors() < building.total_floors():
		if downward:
			fitout.dig()
		else:
			fitout.add_floor()

## Lease a vacant floor to a chosen kind.
##
## The cost is read BEFORE tenancy is mutated: it derives from tenanted_count(),
## which leasing increments, so the order decides whether the last floor costs
## nothing or full price.
##
## Refused here rather than merely greyed in the view, because a disabled
## button is bypassed by two taps queued during a stalled frame.
func lease(floor_index: int, kind_id: String) -> bool:
	if not building.has_floor(floor_index):
		return false
	if not tenancy.is_vacant(floor_index):
		return false
	var k := catalog.kind(kind_id)
	if k == null or k.requires_class > fitout.tier_at(floor_index):
		return false
	# The sim's half of the picker filter. A refusal that lives only in the view
	# is a rule a save file can walk around.
	if k.where != _half_of(floor_index):
		return false
	var cost := lease_cost(floor_index, kind_id)
	if not economy.spend(cost):
		return false
	tenancy.lease(floor_index, kind_id)
	return true

## Below two tenants the CHEAPEST ELIGIBLE kind is free. Making every kind free
## would hand a floor already upgraded to class 3 a free Law Firm, which is a
## strategy rather than a safety net.
func lease_cost(floor_index: int, kind_id: String) -> float:
	var k := catalog.kind(kind_id)
	if k == null:
		return INF
	if tenancy.tenanted_count() >= Tenancy.MIN_FLOORS_FOR_TRAFFIC:
		return k.lease_cost
	var cheapest := catalog.cheapest_for_class(fitout.tier_at(floor_index),
		_half_of(floor_index))
	return 0.0 if cheapest != null and cheapest.id == kind_id else k.lease_cost

func available_kinds(floor_index: int) -> Array[TenantKind]:
	return catalog.available_for_class(fitout.tier_at(floor_index),
		_half_of(floor_index))

## Which half of the building a floor is in, for matching against a kind's
## `where`. The lobby line is the definition, not a convention.
func _half_of(floor_index: int) -> TenantKind.Where:
	return TenantKind.Where.BASEMENT if floor_index < 0 else TenantKind.Where.TOWER

## The fare multiplier is why this is not inert on a tenanted floor. Class
## gates leasing and leasing only happens on vacancy, so a purchase with no
## live effect would pay nothing until the tenant left -- a button you
## rationally never press except in a crisis.
func class_upgrade_cost(floor_index: int) -> float:
	var next := fitout.tier_at(floor_index) + 1
	if next > catalog.max_tier():
		return INF
	return catalog.class_cost(next)

func upgrade_class(floor_index: int) -> bool:
	if floor_index < 0 or floor_index >= building.floor_count:
		return false
	var next := fitout.tier_at(floor_index) + 1
	if next > catalog.max_tier():
		return false
	var cost := class_upgrade_cost(floor_index)
	if not economy.spend(cost):
		return false
	fitout.set_tier(floor_index, next)
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

func dispatch(shaft_index: int, floor_index: int) -> bool:
	if shaft_index < 0 or shaft_index >= building.cars.size():
		return false
	if floor_index < 0 or floor_index >= building.floor_count:
		return false
	var car: ElevatorCar = building.cars[shaft_index]
	if car.is_committed():
		return false                    # a launched car cannot be called off
	if ElevatorCar.is_spring_trip(car.current_floor(), floor_index, building.floor_count) \
			and car.spring_multiplier > 1.0:
		car.launch_to(floor_index)
	else:
		car.dispatch_to(floor_index)
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
	# The tenant left, so their visitors stop arriving. NOT charged as
	# expiries: the expiries that caused the move-out were already charged,
	# and charging again would double-penalise one failure.
	for floor_index in tenancy.accrue_for_tick():
		building.remove_waiting_from_source(floor_index)
	# update combo -- handled inside Economy on each delivery/expiry
	clock.note_ticks(1)

## Rebuilt when EITHER container's revision moves. Compared with != rather than
## >: both counters only increment today, so > would be correct -- but it stops
## working silently the moment any future path swaps a container into a live
## GameState and resets one to zero.
func _sources() -> Array[TrafficSource]:
	var revision := tenancy.revision() + fitout.revision()
	if revision != _source_revision:
		_source_cache = []
		_entrance_cache = PackedInt32Array()
		# EVERY floor, not every tower floor: entrance kinds live below zero.
		for floor_index in range(building.bottom_floor(), building.floor_count):
			if tenancy.is_vacant(floor_index):
				continue
			var k := catalog.kind(tenancy.kind_at(floor_index))
			if k == null:
				continue
			if k.entrance:
				# A door, not a source. As a TrafficSource it would also become
				# an interfloor DESTINATION in _destination_for's `others` pick,
				# double-counting the exit path _door_for already models.
				_entrance_cache.append(floor_index)
				continue
			_source_cache.append(TrafficSource.new(floor_index, k,
				catalog.fare_multiplier(fitout.tier_at(floor_index))))
		_source_revision = revision
	return _source_cache

## The leased garage floors -- the doors. Refreshed by the same revision as
## _sources(), which the call here guarantees is fresh.
func _entrances() -> PackedInt32Array:
	var _refresh := _sources()
	return _entrance_cache

## The whole building's traffic curve, for the HUD's day chart: 24 absolute
## rates and 24 directional mixes. Derived from the same TrafficSource array the
## spawner consumes, so the picture cannot disagree with what actually spawns.
func day_rates() -> PackedFloat32Array:
	_refresh_day()
	return _day_rates

func day_mixes() -> Array[Vector3]:
	_refresh_day()
	return _day_mixes

func _refresh_day() -> void:
	var revision := tenancy.revision() + fitout.revision()
	if revision == _day_revision:
		return
	var src := _sources()
	var doors := _entrances()
	_day_rates = BuildingDay.rates(src, doors.size())
	_day_mixes = []
	var lobby := not tenancy.is_vacant(0)
	for hour in range(TenantKind.BUCKETS):
		_day_mixes.append(BuildingDay.mix(src, hour, lobby, doors.size()))
	_day_revision = revision

func _spawn() -> void:
	for p in spawner.spawn_from_sources(clock.sim_minute(), _sources(),
			not tenancy.is_vacant(0), _entrances()):
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
			car_arrived.emit(i, car.current_floor())
		if not building.waiting_at(car.current_floor()).is_empty():
			car.answer_call()

## Alight first, then board -- riders leaving free the seats arrivals take.
func _deliver() -> void:
	for car in building.cars:
		if not car.is_available():
			continue
		for p in car.take_arrivals():
			var paid := economy.credit_delivery(p.fare)
			# The floor that GENERATED the trip, not the endpoint. Under
			# directional traffic most trips have the lobby at one end, so
			# endpoint attribution would credit floor 0 for everyone else's
			# service and leave an outbound-peak floor unable to recover.
			tenancy.note_delivery(p.source_floor)
			metrics.record_delivery(p.waited_ticks())
			passenger_delivered.emit(p, paid)
		var seats := car.capacity - car.riders.size()
		for p in building.take_boardable(car.current_floor(), seats):
			car.board(p)

## Waiting passengers decay. Riders aboard a car do not -- they are being
## served. Expiry runs AFTER delivery so the zero boundary favours the player.
func _expire() -> void:
	for floor_index in range(building.floor_count):
		var queue: Array[Passenger] = building.waiting[floor_index]
		var survivors: Array[Passenger] = []
		for p in queue:
			p.decay(1)
			if p.is_expired():
				economy.note_expiry(p.fare)
				tenancy.note_expiry(p.source_floor)
				metrics.record_expiry()
				passenger_expired.emit(p)
			else:
				survivors.append(p)
		building.waiting[floor_index] = survivors
