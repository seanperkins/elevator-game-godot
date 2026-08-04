extends GutTest

## Dragging a list of buttons.
##
## A Button is MOUSE_FILTER_STOP, so it eats the press and the ScrollContainer
## under it never scrolls -- which is why the management screen only moved in
## the gaps between rows. These pin both halves of the fix: the drag scrolls,
## and the release that ends it does NOT press the button it landed on.

var scroll: ScrollContainer
var drag: DragScroll
var rect := Rect2(0, 0, 720, 1000)

func before_each() -> void:
	scroll = ScrollContainer.new()
	scroll.size = Vector2(720, 1000)
	add_child_autofree(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 3000)   # taller than the viewport
	scroll.add_child(box)
	drag = DragScroll.new(scroll)
	await wait_physics_frames(1)

func _press(y: float) -> InputEvent:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(360, y)
	return e

func _move(y: float) -> InputEvent:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(360, y)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e

func _release(y: float) -> InputEvent:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = Vector2(360, y)
	return e

func test_a_drag_scrolls_the_list() -> void:
	drag.handle(_press(800.0), rect)
	drag.handle(_move(700.0), rect)
	assert_gt(scroll.scroll_vertical, 0, "dragging up moved the content up")

func test_the_content_follows_the_thumb() -> void:
	# Drag up, list goes up. The inverted version is instantly wrong in the hand
	# and impossible to unsee.
	drag.handle(_press(800.0), rect)
	drag.handle(_move(700.0), rect)
	var down := scroll.scroll_vertical
	drag.handle(_release(700.0), rect)
	drag.handle(_press(700.0), rect)
	drag.handle(_move(800.0), rect)
	assert_lt(scroll.scroll_vertical, down, "dragging back down undoes it")

func test_thumb_wobble_is_not_a_drag() -> void:
	drag.handle(_press(800.0), rect)
	var consumed := drag.handle(_move(800.0 - DragScroll.THRESHOLD + 1.0), rect)
	assert_false(consumed, "under the threshold the button keeps its press")
	assert_eq(scroll.scroll_vertical, 0, "and nothing scrolled")

func test_the_release_that_ends_a_drag_is_swallowed() -> void:
	# The one that matters: these buttons spend money, and one demolishes the
	# building. A scroll must never also buy something.
	drag.handle(_press(800.0), rect)
	drag.handle(_move(600.0), rect)
	assert_true(drag.handle(_release(600.0), rect),
		"the release is consumed so the button under the thumb does not fire")

func test_a_tap_still_reaches_the_button() -> void:
	drag.handle(_press(800.0), rect)
	assert_false(drag.handle(_release(800.0), rect),
		"a press and release with no travel is a tap, and belongs to the button")

func test_a_press_outside_the_panel_is_not_ours() -> void:
	# The HUD is still live above the management screen.
	assert_false(drag.handle(_press(-50.0), rect))
	assert_false(drag.handle(_move(-200.0), rect), "and its drag is not either")
	assert_eq(scroll.scroll_vertical, 0)
