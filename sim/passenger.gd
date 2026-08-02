class_name Passenger
extends RefCounted

var origin_row: int
var destination_row: int
var patience_ticks: int
var fare: float
var boarded: bool = false

var _initial_patience: int

func _init(origin: int, destination: int, patience: int, p_fare: float) -> void:
	origin_row = origin
	destination_row = destination
	patience_ticks = patience
	_initial_patience = maxi(patience, 1)
	fare = p_fare

func decay(n: int) -> void:
	patience_ticks -= n

## Exactly zero is NOT expired. Deliver runs before expire in the tick order,
## so a passenger hitting 0 as the doors open pays and extends the combo.
func is_expired() -> bool:
	return patience_ticks < 0

func patience_fraction() -> float:
	return clampf(float(patience_ticks) / float(_initial_patience), 0.0, 1.0)

## Ticks this passenger spent waiting on its floor. No new field is needed:
## patience decays only while waiting (GameState._expire) and is frozen once
## aboard, so at delivery this is exactly the wait.
##
## Meaningful for an initial patience of at least 1. Below that _initial_patience
## is clamped to 1 and this reads one tick high; the spawner floors the data so
## no production passenger can be in that state.
func waited_ticks() -> int:
	return maxi(_initial_patience - patience_ticks, 0)

func direction() -> int:
	return signi(destination_row - origin_row)
