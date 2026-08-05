class_name DispatchPolicy
extends RefCounted

## Where an idle car goes next, as three ORTHOGONAL choices rather than one
## algorithm:
##
##   WHERE TO LOOK   every floor / floors with someone waiting / floors a rider
##                   wants. A set, so they combine.
##   HOW TO CHOOSE   sweep (carry on the way you were going, turn round at the
##                   end) or nearest.
##   NOTHING TO DO   stay where you are, or go back to the lobby.
##   WHEN FULL       stop anyway, or pass hall calls you cannot serve.
##
## This shape is the point. What a player buys is HARDWARE -- call buttons, a
## load weigher -- and each piece of hardware is what makes a block possible,
## because a controller can only run the algorithm its sensors can feed. So the
## named presets below are just combinations of what is installed, and a later
## "build your own" screen is exposing blocks the player already owns rather
## than a new system.
##
## The teaching case: "every floor" needs NO sensors at all. That is precisely
## why it stops everywhere -- it cannot tell an empty floor from a busy one.
##
## The first policy, "every floor", is not special-cased: it is
## (EVERY_FLOOR, SWEEP, STAY) and falls out of the general rule. That it does is
## the check on whether the decomposition is honest.
##
## Pure: no Building, no scene tree. The caller hands it floor numbers and it
## returns a floor number, so every rule here is unit-tested headlessly.

enum Source { EVERY_FLOOR = 1, HALL_CALLS = 2, CAR_CALLS = 4 }
enum Order { SWEEP, NEAREST }
enum WhenIdle { STAY, RETURN_TO_LOBBY }

## Returned instead of a floor when the car should not move at all.
## "No floor at all." NOT -1: floor -1 EXISTS once something is dug, and a
## sentinel that is also a legal floor made the sweep structurally unable to
## say "go to the basement" -- _first_beyond finding floor -1 read as "nothing
## ahead", so the car turned round instead. The same bug the spawner's inbound
## flag had (traffic_spawner.gd), in a second home.
##
## INT32 min, not int64: choose() carries this through a Vector2i, whose
## components are 32-bit -- int64 min truncates to 0 in the packing, which
## reads as "go to the lobby".
const STAY_PUT := -2147483648

const LOBBY := 0

var sources: int = Source.EVERY_FLOOR
var order: int = Order.SWEEP
var when_idle: int = WhenIdle.STAY

## Load weighing. A real car with a full load passes hall calls rather than
## stopping to open its doors on people who cannot get in -- the stop costs a
## full dwell and serves nobody. Without the sensor the car cannot know, so it
## stops anyway. Not a preset: once installed it improves every call policy.
var bypass_when_full: bool = false

func _init(p_sources := Source.EVERY_FLOOR, p_order := Order.SWEEP,
		p_when_idle := WhenIdle.STAY) -> void:
	sources = p_sources
	order = p_order
	when_idle = p_when_idle

func uses(source: int) -> bool:
	return (sources & source) != 0

## Floors worth considering from `from`, sorted, never including `from` itself:
## a car does not travel to where it already is.
##
## `bottom` is the building's lowest floor, 0 until something is dug. The
## bound below used to be `f >= 0`, which silently DROPPED a hall call at -1 --
## a swept car would simply never answer the basement, with nothing raising.
func candidates(from: int, floor_count: int, waiting: PackedInt32Array,
		rider_floors: PackedInt32Array, car_is_full := false,
		bottom := 0) -> PackedInt32Array:
	var seen := {}
	if uses(Source.EVERY_FLOOR):
		for f in range(bottom, floor_count):
			seen[f] = true
	# A full car still has to deliver the people inside it, so car calls always
	# count; only the hall calls it cannot serve are passed.
	if uses(Source.HALL_CALLS) and not (car_is_full and bypass_when_full):
		for f in waiting:
			seen[f] = true
	if uses(Source.CAR_CALLS):
		for f in rider_floors:
			seen[f] = true
	var out := PackedInt32Array()
	for f in seen.keys():
		if f != from and f >= bottom and f < floor_count:
			out.append(f)
	out.sort()
	return out

## The next floor and the direction to carry forward, as (floor, direction).
## `floor` is STAY_PUT when there is nothing to do and nowhere to idle.
func choose(from: int, floor_count: int, waiting: PackedInt32Array,
		rider_floors: PackedInt32Array, direction: int,
		car_is_full := false, bottom := 0) -> Vector2i:
	if floor_count - bottom <= 1:
		return Vector2i(STAY_PUT, direction)
	var options := candidates(from, floor_count, waiting, rider_floors,
		car_is_full, bottom)
	if options.is_empty():
		# Homing is what stops a call-driven car from parking wherever it
		# happened to finish, which on a tall building is usually the worst
		# place to be when the next call arrives.
		if when_idle == WhenIdle.RETURN_TO_LOBBY and from != LOBBY:
			return Vector2i(LOBBY, -1)
		return Vector2i(STAY_PUT, direction)
	if order == Order.NEAREST:
		return _nearest(from, options, direction)
	return _sweep(from, options, direction)

## Carry on the way you were going and take the first one you meet; turn round
## only when there is nothing left ahead. This is what stops a car crossing the
## building for a call it is about to pass anyway.
func _sweep(from: int, options: PackedInt32Array, direction: int) -> Vector2i:
	var step := 1 if direction >= 0 else -1
	var ahead := _first_beyond(from, options, step)
	if ahead != STAY_PUT:
		return Vector2i(ahead, step)
	var back := _first_beyond(from, options, -step)
	if back != STAY_PUT:
		return Vector2i(back, -step)
	return Vector2i(STAY_PUT, direction)

## Nearest by distance; ties break the way the car is already pointing, so it
## does not dither between two equidistant floors.
func _nearest(from: int, options: PackedInt32Array, direction: int) -> Vector2i:
	var best := options[0]
	var best_gap := absi(best - from)
	for f in options:
		var gap := absi(f - from)
		if gap < best_gap or (gap == best_gap and signi(f - from) == signi(direction)):
			best = f
			best_gap = gap
	return Vector2i(best, signi(best - from))

func _first_beyond(from: int, options: PackedInt32Array, step: int) -> int:
	var best := STAY_PUT
	for f in options:
		if step > 0 and f > from and (best == STAY_PUT or f < best):
			best = f
		elif step < 0 and f < from and (best == STAY_PUT or f > best):
			best = f
	return best

# --- named combinations ----------------------------------------------------

## The presets a player can pick today. MANUAL is the absence of a policy rather
## than one, but it lives in the same list because the toggle cycles through it.
enum Preset { MANUAL, EVERY_FLOOR, ANSWER_CALLS, CALLS_THEN_LOBBY, NEAREST_CALL }

const PRESET_ORDER := [Preset.MANUAL, Preset.EVERY_FLOOR, Preset.ANSWER_CALLS,
	Preset.CALLS_THEN_LOBBY, Preset.NEAREST_CALL]

static func preset_name(preset: int) -> String:
	match preset:
		Preset.MANUAL: return "manual"
		Preset.EVERY_FLOOR: return "EVERY FLOOR"
		Preset.ANSWER_CALLS: return "ANSWER CALLS"
		Preset.CALLS_THEN_LOBBY: return "CALLS, THEN LOBBY"
		Preset.NEAREST_CALL: return "NEAREST CALL"
		_: return "manual"

## The HARDWARE a preset needs installed. Empty means it needs no sensors at
## all, which is the honest reason "every floor" is so wasteful.
##
## Knowing which floors are waiting is hall call buttons; knowing where riders
## want off is car call buttons. Neither is free, and an algorithm cannot be
## smarter than the sensors feeding it.
static func preset_requires(preset: int) -> PackedStringArray:
	var calls := PackedStringArray(["hall_buttons", "car_buttons"])
	match preset:
		Preset.ANSWER_CALLS: return calls
		Preset.NEAREST_CALL: return calls
		Preset.CALLS_THEN_LOBBY:
			var out := calls.duplicate()
			out.append("lobby_parking")
			return out
		_: return PackedStringArray()

static func preset_policy(preset: int) -> DispatchPolicy:
	var calls: int = Source.HALL_CALLS | Source.CAR_CALLS
	match preset:
		Preset.EVERY_FLOOR:
			return DispatchPolicy.new(Source.EVERY_FLOOR, Order.SWEEP, WhenIdle.STAY)
		Preset.ANSWER_CALLS:
			return DispatchPolicy.new(calls, Order.SWEEP, WhenIdle.STAY)
		Preset.CALLS_THEN_LOBBY:
			return DispatchPolicy.new(calls, Order.SWEEP, WhenIdle.RETURN_TO_LOBBY)
		Preset.NEAREST_CALL:
			return DispatchPolicy.new(calls, Order.NEAREST, WhenIdle.STAY)
		_:
			return null          # MANUAL has no policy
