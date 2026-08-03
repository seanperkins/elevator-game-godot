class_name TrafficSpawner
extends RefCounted

## Passengers spawn against a PIECEWISE-CONSTANT curve bucketed by simulated
## minute. That shape is deliberate: it makes the live path and the offline
## catch-up integrator evaluate the same finite sum over whole minutes, which
## is what lets the two be compared exactly (spec §9.1 Test A).

var curve: PackedFloat32Array = PackedFloat32Array()
var base_patience_ticks: int = 900
var base_fare: float = 4.0

## The building size the curve's numbers describe. Six is the starting board, so
## a new game behaves exactly as the curve says and growth scales from there.
const REFERENCE_ROWS := 6

var _rng := RandomNumberGenerator.new()

## A duck-typed member rather than a RandomNumberGenerator subclass: declaring
## randf() on a subclass of a native class trips NATIVE_METHOD_OVERRIDE, and
## the draw-count test needs to swap in a counter.
var rng = RandomNumberGenerator.new()

const LOBBY := 0

var _seed: int = 0

func _init(p_seed: int) -> void:
	_seed = p_seed
	_rng.seed = p_seed

## The seed a save has to record: traffic is deterministic from it, so a reload
## that forgot it would quietly become a different building.
func seed_value() -> int:
	return _seed

func load_curve(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var buckets: Variant = parsed.get("buckets")
	if typeof(buckets) != TYPE_ARRAY or (buckets as Array).is_empty():
		return false
	curve = PackedFloat32Array()
	for v in (buckets as Array):
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		curve.append(float(v))
	# Floored at one tick: Passenger.waited_ticks()'s contract needs an initial
	# patience of at least 1, and this side of it is data.
	base_patience_ticks = maxi(int(parsed.get("base_patience_ticks", 900)), 1)
	base_fare = float(parsed.get("base_fare", 4.0))
	return true

func rate_at_minute(minute: int) -> float:
	if curve.is_empty():
		return 0.0
	return curve[posmod(minute, curve.size())]

## Spawns for a single tick. The per-minute rate is divided across the minute's
## ticks and drawn as a Bernoulli trial, so the expected count over a whole
## minute equals the bucket value exactly.
## `occupied` is the floors with a tenant on them. Traffic comes from tenants,
## so an empty floor is neither an origin nor a destination -- which is what
## makes losing a tenant cost money now that rent is gone.
func spawn_for_tick(minute: int, occupied: PackedInt32Array) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if occupied.size() < 2 or curve.is_empty():
		return out
	# Traffic scales with TENANTS, not with the hour alone. With rent gone, this
	# is the only thing that makes building a floor worth anything: a new tenant
	# is new people making trips. Without it a forty-floor tower carries exactly
	# as many riders as a six-floor one, only over longer distances.
	#
	# The curve is stated for a REFERENCE_ROWS-sized building, so the shipped
	# six-floor start is unchanged and the data file keeps its meaning.
	var scale := float(occupied.size()) / float(REFERENCE_ROWS)
	var per_tick := rate_at_minute(minute) * scale / float(SimClock.TICKS_PER_MINUTE)
	if _rng.randf() >= per_tick:
		return out
	var origin_index := _rng.randi_range(0, occupied.size() - 1)
	var destination_index := _rng.randi_range(0, occupied.size() - 2)
	if destination_index >= origin_index:
		destination_index += 1  # skip origin without rejection-looping
	out.append(Passenger.new(occupied[origin_index], occupied[destination_index],
		base_patience_ticks, base_fare, occupied[origin_index]))
	return out

## One Bernoulli trial per tick against the SUMMED rate, then a weighted pick
## of which source produced it. The alternative -- a trial per occupied floor
## -- would be forty draws a tick at the cap and would make the seed sequence
## depend on building height.
##
## `lobby_tenanted` decides whether the lobby is a usable endpoint. When floor 0
## is vacant it is neither an origin nor a destination, so every kind's inbound
## and outbound weights collapse into interfloor -- the same collapse applied to
## a tenant ON floor 0, whose lobby trips would otherwise be lobby -> lobby.
func spawn_from_sources(minute: int, sources: Array[TrafficSource],
		lobby_tenanted: bool) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if sources.size() < 2:
		return out
	var total := 0.0
	for s in sources:
		total += s.rate_at(minute)
	if total <= 0.0:
		return out
	if rng.randf() >= total / float(SimClock.TICKS_PER_MINUTE):
		return out

	var pick := rng.randf() * total
	var chosen: TrafficSource = sources[sources.size() - 1]
	var running := 0.0
	for s in sources:
		running += s.rate_at(minute)
		if pick < running:
			chosen = s
			break

	var origin := chosen.floor_row
	var destination := _destination_for(chosen, sources, minute, lobby_tenanted)
	if destination == chosen.floor_row:
		return out
	if destination == -1:
		origin = LOBBY
		destination = chosen.floor_row

	out.append(Passenger.new(origin, destination, base_patience_ticks,
		chosen.kind.base_fare * chosen.fare_multiplier, chosen.floor_row))
	return out

## Returns the destination floor, or -1 to mean "this is an inbound trip, so
## swap the endpoints". Collapses to interfloor whenever the lobby is not a
## usable endpoint for this source.
func _destination_for(chosen: TrafficSource, sources: Array[TrafficSource],
		minute: int, lobby_tenanted: bool) -> int:
	var lobby_usable := lobby_tenanted and chosen.floor_row != LOBBY
	var roll := rng.randf()
	if lobby_usable:
		if roll < chosen.kind.inbound_at(minute):
			return -1
		if roll < chosen.kind.inbound_at(minute) + chosen.kind.outbound_at(minute):
			return LOBBY
	var others: Array[TrafficSource] = []
	for s in sources:
		if s.floor_row != chosen.floor_row:
			others.append(s)
	if others.is_empty():
		return chosen.floor_row          # caller drops it
	return others[rng.randi_range(0, others.size() - 1)].floor_row
