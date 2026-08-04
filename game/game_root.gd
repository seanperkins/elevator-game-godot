extends Control

## Owns the sim and pumps it. Physics stays at Godot's default 60 Hz and the
## clock accumulates to 20 Hz -- one tick per callback would run the sim 3x fast.
##
## Two views, one button. It reads MANAGE on the board and BOARD in management;
## never CLOSE, because a view is not a sheet. The sim runs in both.

## The sim owns these now: a run that BEGINS is the sim's idea, and
## Prestige.demolish starts one without going through this file.
const START_FLOORS := GameState.BASE_FLOORS
const START_SHAFTS := GameState.BASE_SHAFTS
const START_SEED := GameState.BASE_SEED
const DEFAULT_CATALOG := "res://data/tenants.json"
const DEFAULT_BLUEPRINTS := "res://data/blueprints.json"

## Test seam: when non-empty, _ready constructs its GameState against this
## catalog path instead of the shipped one. Lets a test hand in a missing file
## and assert the boot path does the right thing.
var catalog_path_override: String = ""
## The same seam for the blueprint catalog, so a malformed-data test never has
## to mutate the shipped file.
var blueprints_path_override: String = ""

var _error_label: Label = null

const HUD_HEIGHT := 96.0
const TOUCH_MIN := 88.0          # 48pt at the 0.546 iPhone scale

## Insets the hardware has already claimed -- Dynamic Island, home indicator,
## rounded corners. Zero on desktop and on the web build in a browser tab.
var _safe: Vector4 = Vector4.ZERO

## Real seconds between autosaves. Frequent enough that a crash costs a few
## seconds, rare enough that a phone is not writing JSON every frame.
const AUTOSAVE_SECONDS := 10.0
var _since_save := 0.0
var _saving_enabled := true

var state: GameState
var _view: BuildingView
var _management: ManagementView
var panel: FloorPanel
## A test-facing seam for hall selection: the hall tap sets this, which is what
## lets the input tests observe it.
var last_selected_floor: int = -1
var _cash_label: Label
var _rate_label: Label
var _clock_label: Label
var _view_button: Button
var _prev_shaft: Button
var _next_shaft: Button
var _pager_label: Label
var _last_shape := Vector2i.ZERO

func _ready() -> void:
	_safe = SafeArea.current(size)
	var floors := START_FLOORS
	var shafts := START_SHAFTS
	var override := _debug_board_override()
	if override != Vector2i.ZERO:
		floors = override.x
		shafts = override.y
	# A debug board is a throwaway: it neither loads a save nor overwrites one,
	# so taking a screenshot cannot cost somebody their building.
	var catalog_path := catalog_path_override
	if catalog_path.is_empty():
		catalog_path = DEFAULT_CATALOG
	var blueprints_path := blueprints_path_override
	if blueprints_path.is_empty():
		blueprints_path = DEFAULT_BLUEPRINTS
	if override != Vector2i.ZERO:
		_saving_enabled = false
		state = GameState.new(floors, shafts, START_SEED, catalog_path, null,
			blueprints_path)
	else:
		# ONE source selection, so the run and the tree can never come from
		# different files -- the autosave would commit that mixture ten seconds
		# later as one perfectly valid payload.
		var loaded := SaveStore.load_all(catalog_path, blueprints_path)
		state = loaded["state"]
		if state == null:
			# A refused run must not take the tech tree down with it.
			var salvaged: Meta = loaded["meta"]
			if salvaged == null:
				# A bare `return` here would skip the guard below just as surely
				# as an abort would, because that branch sits BELOW this code
				# inside _ready. So this draws the screen itself.
				_show_error_screen("blueprint catalog", blueprints_path)
				_saving_enabled = false
				set_physics_process(false)
				return
			# The Meta's starting size is applied by the callers that BEGIN a
			# run, and this is one of them: a salvaged `shafts` L3 could never
			# have been applied by a branch that constructed with START_SHAFTS.
			state = GameState.new(GameState.BASE_FLOORS, salvaged.starting_shafts(),
				GameState.BASE_SEED + salvaged.runs_completed,
				catalog_path, salvaged, blueprints_path)

	# A malformed shipped tenants.json is a build error a player can hit. A
	# blank board with a console message they cannot see is indistinguishable
	# from a hang, so a bad catalog is a named error screen, not a silent freeze.
	if state == null or not state.is_valid():
		if state == null:
			_show_error_screen("tenant catalog", catalog_path)
		else:
			_show_error_screen(state.invalid_what(), state.invalid_path())
		_saving_enabled = false
		set_physics_process(false)
		return

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 28)
	_cash_label.position = Vector2(16 + _safe.x, 10 + _safe.y)
	add_child(_cash_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.position = Vector2(16 + _safe.x, 48 + _safe.y)
	add_child(_rate_label)

	# Third line of the left column. Cash occupies y 10-44 and the rate 48-68,
	# so 72-92 is the last free band inside HUD_HEIGHT (96) -- nothing moves to
	# make room. Dimmed to the pager's grey: the hour is context, not a number
	# the player acts on.
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 16)
	_clock_label.add_theme_color_override("font_color", Color("7c8899"))
	_clock_label.position = Vector2(16 + _safe.x, 72 + _safe.y)
	add_child(_clock_label)

	_view = BuildingView.new()
	_view.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_view.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	add_child(_view)
	_view.bind(state)
	_view.floor_purchase_requested.connect(func() -> void: state.buy("floor"))
	_view.shaft_purchase_requested.connect(_on_buy_shaft)
	_view.hall_floor_selected.connect(_on_hall_floor_selected)

	_management = ManagementView.new()
	_management.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_management.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	_management.visible = false
	add_child(_management)
	_management.bind(state)

	panel = FloorPanel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.bind(state)
	panel.lease_requested.connect(_on_lease_requested)
	panel.upgrade_requested.connect(_on_upgrade_requested)

	# Paging the shaft strip is a tap, never a swipe: the dispatch drag is
	# vertical and arcs sideways by more than half a column (§2.1), so any
	# horizontal read on the board itself would steal the primary verb.
	_prev_shaft = _pager_button("<", 236.0 + _safe.x, func() -> void: _view.scroll_by(-1))
	_next_shaft = _pager_button(">", 420.0 + _safe.x, func() -> void: _view.scroll_by(1))

	_pager_label = Label.new()
	_pager_label.add_theme_font_size_override("font_size", 14)
	_pager_label.add_theme_color_override("font_color", Color("7c8899"))
	_pager_label.position = Vector2(328 + _safe.x, 38 + _safe.y)
	_pager_label.size = Vector2(88, 20)
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pager_label)

	# Top-right is the worst reach on the phone, deliberately: a floating button
	# in the thumb zone would overlay the bottom-right of the board, and at eight
	# shafts that is a dispatch target.
	_view_button = Button.new()
	_view_button.text = "MANAGE"
	_view_button.add_theme_font_size_override("font_size", 20)
	_view_button.size = Vector2(200, TOUCH_MIN)
	_view_button.position = Vector2(size.x - 208 - _safe.z, 4 + _safe.y)
	_view_button.pressed.connect(_on_toggle_view)
	add_child(_view_button)

	_last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
	_refresh_pager()

## Screenshot and device testing need boards that cost 1.36e8 to reach by play.
## This is a command-line override, NOT an edit to START_FLOORS: an unreverted
## edit would ship every new player a forty-floor building.
##   godot -- --board=40x8
##
## Known limit: it starts GameState with N shafts while Upgrades.level_of
## ("shaft") stays 0, so the ghost slot prices the FIRST shaft rather than the
## next one. Harmless for screenshots, which is all this is for.
func _debug_board_override() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--board="):
			continue
		var spec := arg.substr("--board=".length()).split("x")
		if spec.size() != 2:
			continue
		return Vector2i(
			clampi(int(spec[0]), 1, Building.MAX_FLOORS),
			clampi(int(spec[1]), 1, Building.MAX_SHAFTS))
	return Vector2i.ZERO

func _pager_button(label: String, x: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 24)
	b.size = Vector2(TOUCH_MIN, TOUCH_MIN)
	b.position = Vector2(x, 4 + _safe.y)
	b.pressed.connect(on_press)
	b.pressed.connect(_refresh_pager)
	add_child(b)
	return b

func _on_buy_shaft() -> void:
	if state.buy("shaft"):
		_view.scroll_to_end()   # show the shaft that was just paid for

func _on_hall_floor_selected(floor_index: int) -> void:
	last_selected_floor = floor_index
	panel.show_floor(state, floor_index)

func _on_lease_requested(floor_index: int, kind_id: String) -> void:
	if state.lease(floor_index, kind_id):
		panel.show_floor(state, floor_index)   # reflect the new tenant and close the picker

func _on_upgrade_requested(floor_index: int) -> void:
	if state.upgrade_class(floor_index):
		panel.show_floor(state, floor_index)   # reflect the new class and its newly freed kinds

## A named refusal to start: the file is the offence, so it is on the screen.
##
## Parameterised on WHAT the file is, not just its path. There is more than one
## fatal shipped-data file now, and a screen hardcoded to "No valid tenant
## catalog" would announce every one of them under the wrong name.
func _show_error_screen(what: String, path: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_error_label = Label.new()
	_error_label.text = "No valid %s\n\n%s\n\nCannot start." % [what, path]
	_error_label.add_theme_font_size_override("font_size", 20)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error_label.set_anchors_preset(Control.PRESET_CENTER)
	_error_label.size = Vector2(size.x, 200)
	add_child(_error_label)

func error_screen_visible() -> bool:
	return _error_label != null and _error_label.visible

## The text seam the boot tests read: asserting the screen is merely VISIBLE
## would pass with the wrong file named on it.
func error_screen_text() -> String:
	return "" if _error_label == null else _error_label.text

func sim_running() -> bool:
	return is_physics_processing()

func _on_toggle_view() -> void:
	var showing_board := _management.visible
	_management.visible = not showing_board
	_view.visible = showing_board
	_view_button.text = "BOARD" if _management.visible else "MANAGE"
	if _management.visible:
		_prev_shaft.visible = false
		_next_shaft.visible = false
		_pager_label.visible = false
	else:
		_refresh_pager()

## Hidden entirely while every slot -- including the trailing ghost -- fits. A
## disabled control the player has never needed is noise on a 393pt-wide phone.
## The label counts SHAFTS, not slots, so the ghost is excluded from its totals.
func _refresh_pager() -> void:
	if _management.visible:
		return
	var total := state.building.cars.size()
	var pageable := _view.max_scroll() > 0
	_prev_shaft.visible = pageable
	_next_shaft.visible = pageable
	_pager_label.visible = pageable
	if not pageable:
		return
	var first := _view.first_visible_shaft()
	var last := mini(first + _view.visible_shafts(), total)
	_prev_shaft.disabled = first <= 0
	_next_shaft.disabled = first >= _view.max_scroll()
	_pager_label.text = "shafts %d-%d of %d" % [first + 1, maxi(last, first + 1), total]

## Saving on a timer AND on the way out. iOS suspends an app without warning,
## and NOTIFICATION_APPLICATION_PAUSED is the last moment anything runs.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_EXIT_TREE:
			save_now()

func save_now() -> void:
	if _saving_enabled and state != null:
		SaveStore.save(state)

func _physics_process(delta: float) -> void:
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		_since_save = 0.0
		save_now()

	var ticks := state.clock.take_ticks(delta)
	if ticks > 0:
		state.tick(ticks)

	var shape := Vector2i(state.building.floor_count, state.building.cars.size())
	if shape != _last_shape:
		_view.rebuild()
		if shape.y > _last_shape.y:
			_view.scroll_to_end()
		_last_shape = shape
		_refresh_pager()

	if _management.visible:
		_management.refresh()
	else:
		_view.refresh()

	_cash_label.text = "$" + NumberFormat.compact(state.economy.cash)
	# Riders delivered in the rolling minute, not rent: there is no rent, and
	# this is the number the player is actually paid for.
	_rate_label.text = "%s riders/min   combo %.2fx" % [
		Metrics.format_rate(state.metrics.deliveries()), state.economy.combo]
	# A bucket is 30 real seconds, so this advances about two hours a minute --
	# enough to read the rush coming rather than just noticing it arrived.
	_clock_label.text = "%02d:00" % state.clock.hour_of_day()
