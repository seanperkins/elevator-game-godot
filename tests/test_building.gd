extends GutTest

var b: Building

func before_each() -> void:
	b = Building.new(6, 1)

func test_starts_with_the_requested_shape() -> void:
	assert_eq(b.row_count, 6)
	assert_eq(b.cars.size(), 1)
	assert_eq(b.waiting.size(), 6, "one queue per row")

func test_add_shaft_adds_a_car() -> void:
	assert_true(b.add_shaft())
	assert_eq(b.cars.size(), 2)

func test_shafts_stop_at_the_board_cap() -> void:
	# The 44pt touch guarantee caps columns at 8; growth past that is
	# cars-per-shaft, speed, capacity and doors -- not more columns.
	for i in range(Building.MAX_SHAFTS - 1):
		assert_true(b.add_shaft(), "shaft %d" % (i + 2))
	assert_eq(b.cars.size(), Building.MAX_SHAFTS)
	assert_false(b.add_shaft(), "must refuse past the cap")
	assert_eq(b.cars.size(), Building.MAX_SHAFTS, "and must not add one anyway")

func test_add_row_extends_the_board_and_the_queues() -> void:
	assert_true(b.add_row())
	assert_eq(b.row_count, 7)
	assert_eq(b.waiting.size(), 7)

func test_rows_stop_at_the_board_cap() -> void:
	while b.row_count < Building.MAX_ROWS:
		assert_true(b.add_row())
	assert_eq(b.row_count, Building.MAX_ROWS)
	assert_false(b.add_row(), "the board never scrolls")

func test_enqueue_places_the_passenger_on_its_origin_row() -> void:
	b.enqueue(Passenger.new(3, 5, 100, 1.0, 3))
	assert_eq(b.waiting_at(3).size(), 1)
	assert_eq(b.waiting_at(5).size(), 0)

func test_remove_waiting_from_source_clears_every_queue() -> void:
	# Inbound trips wait in the LOBBY queue, so a source-scoped sweep must reach
	# across queues, not just "that floor's" queue.
	b.enqueue(Passenger.new(0, 4, 900, 4.0, 4))    # lobby queue, belongs to 4
	b.enqueue(Passenger.new(4, 0, 900, 4.0, 4))    # queue 4, belongs to 4
	b.enqueue(Passenger.new(0, 2, 900, 4.0, 2))    # lobby queue, belongs to 2
	assert_eq(b.remove_waiting_from_source(4), 2, "counts what it removed")
	assert_eq(b.total_waiting(), 1, "another floor's visitors survive")
	assert_eq(b.waiting_at(3).size(), 0, "cleared from the lobby too")

func test_total_waiting_counts_every_row() -> void:
	b.enqueue(Passenger.new(0, 5, 100, 1.0, 0))
	b.enqueue(Passenger.new(3, 5, 100, 1.0, 3))
	b.enqueue(Passenger.new(3, 1, 100, 1.0, 3))
	assert_eq(b.total_waiting(), 3)

func test_take_boardable_removes_up_to_the_limit() -> void:
	for i in range(5):
		b.enqueue(Passenger.new(2, 4, 100, 1.0, 2))
	var got := b.take_boardable(2, 3)
	assert_eq(got.size(), 3, "limited by the seats offered")
	assert_eq(b.waiting_at(2).size(), 2, "the rest stay waiting")

func test_take_boardable_is_fifo() -> void:
	var first := Passenger.new(2, 4, 100, 1.0, 2)
	var second := Passenger.new(2, 9, 100, 1.0, 2)
	b.enqueue(first)
	b.enqueue(second)
	var got := b.take_boardable(2, 1)
	assert_eq(got[0].destination_row, 4, "longest waiting boards first")

func test_take_boardable_on_an_empty_row_is_empty() -> void:
	assert_eq(b.take_boardable(1, 4).size(), 0)

func test_take_boardable_with_zero_seats_takes_nobody() -> void:
	b.enqueue(Passenger.new(2, 4, 100, 1.0, 2))
	assert_eq(b.take_boardable(2, 0).size(), 0)
	assert_eq(b.waiting_at(2).size(), 1)
