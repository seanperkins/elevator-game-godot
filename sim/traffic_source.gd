class_name TrafficSource
extends RefCounted

## One tenanted floor, as the spawner sees it: what it generates and what its
## trips are worth. Exists so the spawner never learns about Tenancy or Fitout
## -- it is handed a plain array and knows nothing about where it came from.

var floor_row: int
var kind: TenantKind
var fare_multiplier: float

func _init(p_floor: int, p_kind: TenantKind, p_multiplier: float) -> void:
	floor_row = p_floor
	kind = p_kind
	fare_multiplier = p_multiplier

func rate_at(minute: int) -> float:
	return kind.rate_at(minute)
