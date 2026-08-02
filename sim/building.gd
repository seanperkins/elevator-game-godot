class_name Building
extends RefCounted

## Board constants are design inputs, not incidental limits (spec §3).
## 40 rows because the board never scrolls; 8 shafts because a 44pt column at
## a 720-unit base width is ~80.6 units, so ~8.9 columns fit edge to edge.

const MAX_ROWS := 40
const MAX_SHAFTS := 8

var row_count: int
var cars: Array[ElevatorCar] = []
var waiting: Array = []          # Array of Array[Passenger], one per row

func _init(p_row_count: int, shaft_count: int) -> void:
	row_count = clampi(p_row_count, 1, MAX_ROWS)
	for i in range(row_count):
		waiting.append([] as Array[Passenger])
	for i in range(clampi(shaft_count, 0, MAX_SHAFTS)):
		cars.append(ElevatorCar.new(0))

func add_shaft() -> bool:
	if cars.size() >= MAX_SHAFTS:
		return false
	cars.append(ElevatorCar.new(0))
	return true

func add_row() -> bool:
	if row_count >= MAX_ROWS:
		return false
	row_count += 1
	waiting.append([] as Array[Passenger])
	return true

func enqueue(p: Passenger) -> void:
	if p.origin_row < 0 or p.origin_row >= row_count:
		return
	waiting[p.origin_row].append(p)

func waiting_at(row: int) -> Array[Passenger]:
	if row < 0 or row >= row_count:
		return [] as Array[Passenger]
	return waiting[row]

func total_waiting() -> int:
	var n := 0
	for queue in waiting:
		n += queue.size()
	return n

## FIFO: the longest-waiting passenger boards first.
func take_boardable(row: int, limit: int) -> Array[Passenger]:
	var out: Array[Passenger] = []
	if limit <= 0 or row < 0 or row >= row_count:
		return out
	var queue: Array[Passenger] = waiting[row]
	var take := mini(limit, queue.size())
	for i in range(take):
		out.append(queue.pop_front())
	return out
