class_name SimClock
extends RefCounted

## Fixed-step clock. Physics runs at Godot's default 60 Hz; the sim runs at
## 20 Hz. One sim tick per _physics_process call would run the sim at 3x speed,
## so frames are accumulated instead.

const TICK_SECONDS := 0.05
const TICKS_PER_MINUTE := 1200        # 60 s / 0.05 s
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

## Integer arithmetic deliberately: a float accumulator lands just below the
## bucket boundary and selects the wrong traffic bucket for one tick.
func sim_minute() -> int:
	return ticks_executed / TICKS_PER_MINUTE
