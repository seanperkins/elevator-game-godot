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
