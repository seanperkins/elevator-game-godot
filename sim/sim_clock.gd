class_name SimClock
extends RefCounted

## Fixed-step clock. Physics runs at Godot's default 60 Hz; the sim runs at
## 20 Hz. One sim tick per _physics_process call would run the sim at 3x speed,
## so frames are accumulated instead.

const TICK_SECONDS := 0.05
## Elapsed real time. sim/metrics.gd's window is the same length by its own
## construction, and tests use this to advance "a minute".
const TICKS_PER_REAL_MINUTE := 1200   # 60 s / 0.05 s
## One traffic bucket -- the unit data/tenants.json quotes its rates in. Split
## from the above because the spawner's Bernoulli denominator and the bucket
## length must move TOGETHER: changing either alone leaves trips-per-real-minute
## exactly unchanged, since the day and the day's traffic scale as one.
const TICKS_PER_SIM_MINUTE := 600     # one traffic bucket = 30 real seconds
const MAX_TICKS_PER_FRAME := 8

var ticks_executed: int = 0
var discarded_seconds: float = 0.0

var _accumulator: float = 0.0

## How many ticks to run this frame. Beyond the clamp, time is FORFEITED --
## the accumulator is drained rather than carried, so a hitch cannot spiral
## into an ever-growing backlog on the following frames.
func take_ticks(delta: float) -> int:
	_accumulator += delta
	var wanted := int(_accumulator / TICK_SECONDS)
	if wanted <= 0:
		return 0
	_accumulator -= float(wanted) * TICK_SECONDS
	var granted := mini(wanted, MAX_TICKS_PER_FRAME)
	discarded_seconds += float(wanted - granted) * TICK_SECONDS
	return granted

func note_ticks(n: int) -> void:
	ticks_executed += n

## Which simulated minute of the day it is, for indexing the traffic curve.
##
## The day opens at the MORNING RUSH, not midnight. The curve's first six
## buckets are the overnight trough -- 0.4, 0.3, 0.2, 0.2, 0.3, 0.8 spawns per
## simulated minute -- and a simulated minute is thirty real seconds, so a day
## starting at bucket 0 showed a new player an empty building for about three
## real minutes. A 900-tick patience is 45 seconds, so even the rare night
## passenger
## expired before anyone looked. That was the first thing anyone saw of the game.
##
## This is an offset on the READING, not on ticks_executed: the latter means
## "how long has the sim run", which the metrics window and every elapsed-time
## test depend on, and conflating it with time-of-day would corrupt both.
##
## Integer arithmetic deliberately: a float accumulator lands just below the
## bucket boundary and selects the wrong traffic bucket for one tick.
const START_MINUTE := 6

func sim_minute() -> int:
	return START_MINUTE + ticks_executed / TICKS_PER_SIM_MINUTE
