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

## Extra inbound arrivals per LEASED entrance floor, as a fraction of the
## building's base rate.
##
## MEASURED 2026-08-04 (10 floors, NEAREST_CALL, 3 seeds x 3 sim days): at this
## value depth 1 on a two-shaft run is near-neutral, depth 2 on a THREE-shaft
## run earns +37% over never digging, and depth 2 on two shafts collapses --
## which is why Meta.BASE_DEPTH_CAP is 1. The lever that decides whether
## digging pays is the shaft count, not this number: sweeping it 0.06-0.15
## moved earnings a few percent while the shaft pairing moved them by a third.
const PARK_BONUS := 0.15

## One Bernoulli trial per tick against the SUMMED rate, then a weighted pick
## of which source produced it. The alternative -- a trial per occupied floor
## -- would be forty draws a tick at the cap and would make the seed sequence
## depend on building height. Entrances scale the rate INSIDE that one trial
## for the same reason: a trial per entrance would make the sequence depend on
## how deep the building is.
##
## `lobby_tenanted` decides whether the lobby is a usable DOOR. When floor 0 is
## vacant it is neither an origin nor a destination -- the same collapse applied
## to a tenant ON floor 0, whose lobby trips would otherwise be lobby -> lobby.
## `entrances` are the leased garage floors, and they are doors too: a source
## whose lobby is unusable but who has a garage still takes inbound and outbound
## trips, through the garage. Only a source with NO usable door collapses to
## interfloor. That is the exception that keeps a building with a vacant lobby
## and a leased basement earning -- a second way out of the no-fail-state hole,
## not a loophole in it.
func spawn_from_sources(minute: int, sources: Array[TrafficSource],
		lobby_tenanted: bool, entrances: PackedInt32Array) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if sources.size() < 2:
		return out
	var total := 0.0
	for s in sources:
		total += s.rate_at(minute)
	if total <= 0.0:
		return out
	# The scaled total feeds the TRIAL only. The weighted pick below runs on the
	# base total, so which tenant generates a trip is unaffected by how deep you
	# have dug -- depth changes how many visitors there are and which door they
	# use, never whose visitors they are.
	var park := PARK_BONUS * float(entrances.size())
	if rng.randf() >= total * (1.0 + park) / float(SimClock.TICKS_PER_SIM_MINUTE):
		return out

	var pick := rng.randf() * total
	var chosen: TrafficSource = sources[sources.size() - 1]
	var running := 0.0
	for s in sources:
		running += s.rate_at(minute)
		if pick < running:
			chosen = s
			break

	var lobby_usable := lobby_tenanted and chosen.floor_index != LOBBY
	var origin := chosen.floor_index
	var answer := _destination_for(chosen, sources, minute, lobby_tenanted,
		not entrances.is_empty())
	var destination := answer.x
	# The door branches run FIRST. An inbound answer's .x legitimately equals
	# the chosen floor -- that is the whole point, the trip ends there -- so the
	# self-trip refusal below would drop every inbound trip if it ran first.
	if answer.y == 1:
		origin = _door_for(entrances, park, lobby_usable)
		destination = chosen.floor_index
	elif answer.y == 2:
		destination = _door_for(entrances, park, lobby_usable)
	elif destination == chosen.floor_index:
		return out

	out.append(Passenger.new(origin, destination, base_patience_ticks,
		chosen.kind.base_fare * chosen.fare_multiplier, chosen.floor_index))
	return out

## Which door a lobby-endpoint trip actually uses: an arrival's origin, a
## leaver's destination -- the SAME draw, because people go out the way they
## came in.
##
## Uniform among garages is deliberate and is the whole diminishing return: the
## fourth garage adds the same arrivals as the first, but they are further from
## where they are going, so depth costs more car time per trip it buys.
##
## The empty early-out is load-bearing for determinism: with no entrances this
## must consume NO draws, or a building that never dug would replay a different
## seed sequence than it did before this feature existed.
func _door_for(entrances: PackedInt32Array, park: float, lobby_usable: bool) -> int:
	if entrances.is_empty():
		return LOBBY
	if lobby_usable and rng.randf() >= park / (1.0 + park):
		return LOBBY
	return entrances[rng.randi_range(0, entrances.size() - 1)]

## The destination floor in `.x`; `.y` says what kind of trip it is:
##   0 -- a concrete destination (interfloor), or the chosen floor, meaning drop
##   1 -- INBOUND: the caller draws the door and swaps the endpoints
##   2 -- OUTBOUND: the caller draws the door as the destination
##
## The flag used to BE the return value: -1 meant inbound. That was safe exactly
## while the lowest floor was 0, and the first floor dug IS -1 -- a sentinel that
## is also a legal answer delivers inbound passengers into the basement with
## nothing raising anywhere.
##
## Outbound is flagged rather than returned as LOBBY because "leaving the
## building" and "visiting the floor-0 tenant" both end at floor 0 -- but only
## the first may be rerouted through a garage when the lobby is vacant.
## Collapses to interfloor only when this source has NO usable door.
func _destination_for(chosen: TrafficSource, sources: Array[TrafficSource],
		minute: int, lobby_tenanted: bool, has_entrance: bool) -> Vector2i:
	var lobby_usable := (lobby_tenanted and chosen.floor_index != LOBBY) \
		or has_entrance
	var roll := rng.randf()
	if lobby_usable:
		if roll < chosen.kind.inbound_at(minute):
			return Vector2i(chosen.floor_index, 1)
		if roll < chosen.kind.inbound_at(minute) + chosen.kind.outbound_at(minute):
			return Vector2i(LOBBY, 2)
	var others: Array[TrafficSource] = []
	for s in sources:
		if s.floor_index != chosen.floor_index:
			others.append(s)
	if others.is_empty():
		return Vector2i(chosen.floor_index, 0)          # caller drops it
	return Vector2i(others[rng.randi_range(0, others.size() - 1)].floor_index, 0)
