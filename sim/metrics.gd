class_name Metrics
extends RefCounted

## A rolling window of recent service quality, in 60 one-second buckets.
##
## The window is SECOND-ALIGNED, not exactly 60 seconds: it holds 1200 ticks
## only at the instant before a rollover and 1181 just after, so a rate reads up
## to 1.58% low, oscillating once a second. Per-tick buckets would buy exactness
## nobody can perceive at 60x the storage.
##
## Metrics owns its own tick counter and never reads SimClock: note_ticks() runs
## LAST in GameState._tick_once, so ticks_executed lags this advance for the
## whole body of a tick, and deriving the bucket from it would file every event
## one bucket behind.

const BUCKET_TICKS := 20        # one simulated second at 0.05 s per tick
const BUCKETS := 60             # ~60 s of history

var _delivered: PackedInt32Array = PackedInt32Array()
var _wait_ticks: PackedInt64Array = PackedInt64Array()
var _expired: PackedInt32Array = PackedInt32Array()

var _tick: int = 0
var _index: int = 0

func _init() -> void:
	_delivered.resize(BUCKETS)
	_wait_ticks.resize(BUCKETS)
	_expired.resize(BUCKETS)

## FIRST in the tick order. Rolls into the next bucket and clears it before
## anything in this tick writes to it.
func advance() -> void:
	var next := (_tick / BUCKET_TICKS) % BUCKETS
	if next != _index:
		_index = next
		_delivered[_index] = 0
		_wait_ticks[_index] = 0
		_expired[_index] = 0
	_tick += 1

func record_delivery(waited_ticks: int) -> void:
	_delivered[_index] += 1
	_wait_ticks[_index] += maxi(waited_ticks, 0)

func record_expiry() -> void:
	_expired[_index] += 1

func deliveries() -> int:
	var n := 0
	for v in _delivered:
		n += v
	return n

func expiries() -> int:
	var n := 0
	for v in _expired:
		n += v
	return n

## Mean seconds a delivered passenger spent waiting. Returns -1.0 -- a sentinel,
## not a value -- when the window holds no deliveries, so the caller renders the
## no-data case instead of dividing by zero into NaN.
func average_wait_seconds() -> float:
	var d := deliveries()
	if d <= 0:
		return -1.0
	var total := 0
	for v in _wait_ticks:
		total += v
	return (float(total) / float(d)) * SimClock.TICK_SECONDS

## Pure formatting, kept in sim/ so the no-data rule is testable headlessly.
static func format_wait(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	return "%ds" % int(seconds)

static func format_rate(count: int) -> String:
	return str(count)
