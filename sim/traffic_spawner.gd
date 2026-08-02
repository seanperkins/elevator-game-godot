class_name TrafficSpawner
extends RefCounted

## Passengers spawn against a PIECEWISE-CONSTANT curve bucketed by simulated
## minute. That shape is deliberate: it makes the live path and the offline
## catch-up integrator evaluate the same finite sum over whole minutes, which
## is what lets the two be compared exactly (spec §9.1 Test A).

var curve: PackedFloat32Array = PackedFloat32Array()
var base_patience_ticks: int = 900
var base_fare: float = 4.0

var _rng := RandomNumberGenerator.new()

func _init(p_seed: int) -> void:
	_rng.seed = p_seed

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
func spawn_for_tick(minute: int, row_count: int) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if row_count < 2 or curve.is_empty():
		return out
	var per_tick := rate_at_minute(minute) / float(SimClock.TICKS_PER_MINUTE)
	if _rng.randf() >= per_tick:
		return out
	var origin := _rng.randi_range(0, row_count - 1)
	var destination := _rng.randi_range(0, row_count - 2)
	if destination >= origin:
		destination += 1        # skip origin without rejection-looping
	out.append(Passenger.new(origin, destination, base_patience_ticks, base_fare))
	return out
