class_name BuildingDay
extends RefCounted

## The whole building's day, as one 24-bucket curve.
##
## A kind's curve answers "what is this tenant like". This answers "what is
## about to happen to ME", which is a different and more useful question: it is
## the sum of every tenanted floor, so a tower of offices has one brutal spike
## and a mixed one is smoother but never quiet.
##
## It is derived from the SAME TrafficSource array the spawner consumes, and
## sums it the same way (`sim/traffic_spawner.gd`'s `total += s.rate_at(minute)`),
## so the picture cannot drift from what actually spawns. That is the whole
## reason this lives in sim/ rather than being computed in the widget.

## Trips per simulated minute for each hour, ABSOLUTE -- not normalised. The
## widget normalises for drawing; a caller asking "how busy is 08:00" wants the
## real number.
static func rates(sources: Array[TrafficSource]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for hour in range(TenantKind.BUCKETS):
		var total := 0.0
		for s in sources:
			total += s.rate_at(hour)
		out.append(total)
	return out

## The busiest hour's rate, or 0.0 when nothing is tenanted. Separate from
## rates() because "the day is empty" is a state the caller has to handle and a
## max of zero is the honest way to say it.
static func peak(sources: Array[TrafficSource]) -> float:
	var top := 0.0
	for r in rates(sources):
		top = maxf(top, r)
	return top

## (inbound, outbound, interfloor) shares of one hour across the whole building,
## summing to 1 when anything is generating and ZERO when nothing is.
##
## Weighted by each floor's RATE at that hour, not by floor count: a floor
## generating ten trips a minute must dominate one generating a tenth of that,
## or the mix describes a building nobody is in.
##
## `lobby_tenanted` mirrors the spawner exactly. A trip needs a usable lobby to
## be inbound or outbound at all, and the spawner's rule is
## `lobby_tenanted and chosen.floor_index != LOBBY` -- so a tenant ON floor 0
## collapses to interfloor even when the lobby is occupied, because its lobby
## trips would run lobby -> lobby.
static func mix(sources: Array[TrafficSource], hour: int,
		lobby_tenanted: bool) -> Vector3:
	var inbound := 0.0
	var outbound := 0.0
	var interfloor := 0.0
	for s in sources:
		var r := s.rate_at(hour)
		if r <= 0.0:
			continue
		if not lobby_tenanted or s.floor_index == DispatchPolicy.LOBBY:
			interfloor += r
			continue
		var i := s.kind.inbound_at(hour)
		var o := s.kind.outbound_at(hour)
		inbound += r * i
		outbound += r * o
		interfloor += r * maxf(1.0 - i - o, 0.0)
	var total := inbound + outbound + interfloor
	if total <= 0.0:
		return Vector3.ZERO
	return Vector3(inbound / total, outbound / total, interfloor / total)
