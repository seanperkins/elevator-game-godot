class_name TrafficSpawner
extends RefCounted

## Turns a building's traffic sources into concrete passengers. It knows
## nothing about Tenancy or Fitout -- it is handed a plain Array[TrafficSource]
## and reads each floor's kind and fare there.

var base_patience_ticks: int = 900

## A duck-typed member rather than a RandomNumberGenerator subclass: declaring
## randf() on a subclass of a native class trips NATIVE_METHOD_OVERRIDE, and
## the draw-count test needs to swap in a counter.
var rng = RandomNumberGenerator.new()

const LOBBY := 0

var _seed: int = 0

func _init(p_seed: int) -> void:
	_seed = p_seed
	rng.seed = p_seed

## The seed a save has to record: traffic is deterministic from it, so a reload
## that forgot it would quietly become a different building.
func seed_value() -> int:
	return _seed

## Patience stays building-wide (spec §14): the curve file is the calibration
## reference for it, and only for it. The per-floor rate and fare come from the
## tenant catalog now, so the buckets are read no longer.
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
	# Floored at one tick: Passenger.waited_ticks()'s contract needs an initial
	# patience of at least 1, and this side of it is data.
	base_patience_ticks = maxi(int(parsed.get("base_patience_ticks", 900)), 1)
	return true

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
	if rng.randf() >= total / float(SimClock.TICKS_PER_SIM_MINUTE):
		return out

	var pick := rng.randf() * total
	var chosen: TrafficSource = sources[sources.size() - 1]
	var running := 0.0
	for s in sources:
		running += s.rate_at(minute)
		if pick < running:
			chosen = s
			break

	var origin := chosen.floor_index
	var answer := _destination_for(chosen, sources, minute, lobby_tenanted)
	var destination := answer.x
	# The inbound branch runs FIRST. An inbound answer's .x legitimately equals
	# the chosen floor -- that is the whole point, the trip ends there -- so the
	# self-trip refusal below would drop every inbound trip if it ran first.
	if answer.y == 1:
		origin = LOBBY
		destination = chosen.floor_index
	elif destination == chosen.floor_index:
		return out

	out.append(Passenger.new(origin, destination, base_patience_ticks,
		chosen.kind.base_fare * chosen.fare_multiplier, chosen.floor_index))
	return out

## The destination floor in `.x`, and `.y == 1` when this is an INBOUND trip, so
## the caller swaps the endpoints.
##
## The flag used to BE the return value: -1 meant inbound. That was safe exactly
## while the lowest floor was 0, and the first floor dug IS -1 -- a sentinel that
## is also a legal answer delivers inbound passengers into the basement with
## nothing raising anywhere. Collapses to interfloor whenever the lobby is not a
## usable endpoint for this source.
func _destination_for(chosen: TrafficSource, sources: Array[TrafficSource],
		minute: int, lobby_tenanted: bool) -> Vector2i:
	var lobby_usable := lobby_tenanted and chosen.floor_index != LOBBY
	var roll := rng.randf()
	if lobby_usable:
		if roll < chosen.kind.inbound_at(minute):
			return Vector2i(chosen.floor_index, 1)
		if roll < chosen.kind.inbound_at(minute) + chosen.kind.outbound_at(minute):
			return Vector2i(LOBBY, 0)
	var others: Array[TrafficSource] = []
	for s in sources:
		if s.floor_index != chosen.floor_index:
			others.append(s)
	if others.is_empty():
		return Vector2i(chosen.floor_index, 0)          # caller drops it
	return Vector2i(others[rng.randi_range(0, others.size() - 1)].floor_index, 0)
