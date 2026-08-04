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

## 96 held two lines of type and a clock. It now holds two lines at the larger
## sizes plus the day strip -- and 96 was already overflowing: a font-38 cash
## line from y 10 reaches y 57, where the rate line used to start at 48.
const HUD_HEIGHT := 132.0
## The day chart's band inside the HUD, full width less the side margins.
const DAY_STRIP_TOP := 96.0
const DAY_STRIP_HEIGHT := 28.0
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
var _prestige: PrestigePanel
## A test-facing seam for hall selection: the hall tap sets this, which is what
## lets the input tests observe it.
var last_selected_floor: int = -1
var _cash_label: Label
var _rate_label: Label
var _day_strip: DaySparkline
var _view_button: Button
var _dev_button: Button
var _dev: DevPanel
var _pager_label: Label

## Seven taps on the cash readout reveal the dev panel. The WINDOW matters: the
## flag persists forever once set, so without it seven idle taps spread across a
## long session would arm the panel by accident, with no way back but wiping the
## save.
const DEV_TAPS := 7
const DEV_TAP_WINDOW := 2.0
var _dev_taps: int = 0
var _dev_last_tap: float = 0.0

## Runs each granted tick n times. Session-only -- a persisted 4x is a bug report
## waiting to happen.
var _speed: int = 1
var _last_shape := Vector2i.ZERO

func _ready() -> void:
	# FIRST, and on the root, so every Label and Button in the game inherits the
	# palette's ink rather than Godot's stock white; nodes needing something
	# else override themselves and win. Ahead of the catalog checks on purpose:
	# the error screens below are built and RETURNED from inside this function,
	# so anything set after them leaves exactly the screen a player sees when
	# something is broken as the one screen that never got themed.
	theme = Palette.build_theme()

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
	bg.color = Palette.APP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 38)
	_cash_label.position = Vector2(16 + _safe.x, 10 + _safe.y)
	# Label defaults to MOUSE_FILTER_IGNORE, so it receives nothing today. The
	# minimum size is the touch target, not the text: the glyphs still draw
	# top-left so NOTHING moves on screen, but the tappable region becomes 88
	# tall rather than 39. The rate and clock labels sit inside that rect and
	# keep IGNORE, so their taps fall through to here rather than being eaten.
	_cash_label.mouse_filter = Control.MOUSE_FILTER_STOP
	# 86, not 88: the label starts at y=10 and the board is added at
	# HUD_HEIGHT (96) as a LATER sibling, so it wins picking below that line.
	# Claiming 88 would hand two units of the tap target to the board, where a
	# stray tap dispatches a car.
	_cash_label.custom_minimum_size = Vector2(200, HUD_HEIGHT - 10.0)
	_cash_label.size = Vector2(200, HUD_HEIGHT - 10.0)
	_cash_label.gui_input.connect(_on_cash_input)
	add_child(_cash_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 22)
	_rate_label.position = Vector2(16 + _safe.x, 60 + _safe.y)
	add_child(_rate_label)

	# Third line of the left column. Cash occupies y 10-44 and the rate 48-68,
	# so 72-92 is the last free band inside HUD_HEIGHT (96) -- nothing moves to
	# make room. Dimmed to the pager's grey: the hour is context, not a number
	# the player acts on.
	# The clock was a bare "09:00", which said what time it was and nothing about
	# what that MEANT. The strip below is the same fact plus the one that decides
	# anything: the whole building's traffic across the day, with a playhead on
	# the hour now running. A quiet building and a broken one no longer look the
	# same, which is the thing a bare clock could never fix.
	_day_strip = DaySparkline.new()
	_day_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_day_strip)

	_rebuild_views()

	# The pager BUTTONS are gone. They existed because "paging the shaft strip is
	# a tap, never a swipe -- any horizontal read on the board itself would steal
	# the primary verb", and that stopped being true: BuildingView connects every
	# shaft column's pan_requested to pan_board_by, and Gesture already separates
	# a tap (dispatch) from a drag past DRAG_THRESHOLD (pan).
	# test_a_sideways_drag_pans_across_the_shafts and
	# test_a_sideways_pan_does_not_dispatch pin both halves.
	#
	# The LABEL stays: it is the only thing on screen saying that shafts exist
	# off the right edge, and a drag affordance you have not discovered yet
	# cannot tell you that.
	_pager_label = Label.new()
	_pager_label.add_theme_font_size_override("font_size", 19)
	_pager_label.add_theme_color_override("font_color", Palette.INK_MUTED)
	_pager_label.position = Vector2(328 + _safe.x, 38 + _safe.y)
	_pager_label.size = Vector2(88, 20)
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pager_label)

	# Top-right is the worst reach on the phone, deliberately: a floating button
	# in the thumb zone would overlay the bottom-right of the board, and at eight
	# shafts that is a dispatch target.
	_view_button = Button.new()
	_view_button.text = "MANAGE"
	_view_button.add_theme_font_size_override("font_size", 27)
	_view_button.size = Vector2(200, TOUCH_MIN)
	_view_button.position = Vector2(size.x - 208 - _safe.z, 4 + _safe.y)
	_view_button.pressed.connect(_on_toggle_view)
	add_child(_view_button)

	# In the space the pager buttons vacated. Hidden until seven taps on the
	# cash readout reveal it, and then hidden again only by a save reset.
	_dev_button = Button.new()
	_dev_button.text = "DEV"
	_dev_button.add_theme_font_size_override("font_size", 22)
	_dev_button.size = Vector2(TOUCH_MIN, TOUCH_MIN)
	_dev_button.position = Vector2(_view_button.position.x - TOUCH_MIN - 8.0,
		4 + _safe.y)
	_dev_button.pressed.connect(func() -> void: _dev.open(state))
	add_child(_dev_button)
	_refresh_dev_button()

	# Anchor the shaft readout off DEV rather than off its own +_safe.x origin.
	# The two used OPPOSITE inset conventions -- the label at 328 + _safe.x, DEV
	# derived from _view_button's (size.x - 208 - _safe.z) -- so at the 16-unit
	# minimum inset SafeArea floors to, they overlapped by 32 units on every
	# real phone while sitting exactly adjacent at the zero insets a headless
	# test sees. Relative positioning cannot drift that way.
	_pager_label.position.x = _dev_button.position.x - 8.0 - _pager_label.size.x

	# AFTER the HUD exists: the call inside _rebuild_views ran before these
	# controls were built, so without this the overlays sit under them until the
	# first demolish rebuilds the views.
	_restack()

	_last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
	_refresh_pager()

## Screenshot and device testing need boards that cost 1.36e8 to reach by play.
## This is a command-line override, NOT an edit to START_FLOORS: an unreverted
## edit would ship every new player a forty-floor building.
##   godot -- --board=40x8
##
## The old "known limit" here -- a debug board priced the FIRST shaft rather
## than the next one, because level_of("shaft") stayed 0 -- is fixed:
## GameState._init now grant_level()s the size it was handed, so a board that
## starts with N shafts has consumed N-1 rungs of the price ladder.
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

func _on_buy_shaft() -> void:
	if state.buy("shaft"):
		_view.scroll_to_end()   # show the shaft that was just paid for

func _on_hall_floor_selected(floor_index: int) -> void:
	last_selected_floor = floor_index
	panel.show_floor(state, floor_index)

func _on_lease_requested(floor_index: int, kind_id: String) -> void:
	if state.lease(floor_index, kind_id):
		panel.show_floor(state, floor_index)   # reflect the new tenant and close the picker

## Builds the four views that hold a GameState, replacing any that exist.
##
## They have to be REPLACED rather than rebound: BuildingView.bind(),
## ManagementView.bind() and FloorPanel.bind() all add_child unconditionally --
## they are constructors wearing an accessor's name -- so calling any of them a
## second time stacks a whole UI on top of the old one. Only
## BuildingView.rebuild() frees first, and it never re-reads _state.
##
## It covers exactly those four. It must NOT include the pager buttons or
## _view_button, which also add_child unconditionally and would duplicate on
## every rebuild: the very trap this function is about.
func _rebuild_views() -> void:
	for old in [_view, _management, panel, _prestige, _dev]:
		if old == null:
			continue
		# queue_free() is DEFERRED to end of frame, so without this the freed
		# views remain children while the new ones are added, and input in that
		# window reaches both trees.
		old.hide()
		remove_child(old)
		old.queue_free()

	_view = BuildingView.new()
	_view.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_view.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	add_child(_view)
	_view.bind(state)
	# Resolved through `self` at call time, so it follows a state swap rather
	# than capturing the dead sim.
	_view.floor_purchase_requested.connect(func() -> void: state.buy("floor"))
	_view.shaft_purchase_requested.connect(_on_buy_shaft)
	_view.hall_floor_selected.connect(_on_hall_floor_selected)
	_view.prestige_requested.connect(_on_prestige_requested)

	_management = ManagementView.new()
	_management.position = Vector2(_safe.x, HUD_HEIGHT + _safe.y)
	_management.size = Vector2(size.x - _safe.x - _safe.z,
		size.y - HUD_HEIGHT - _safe.y - _safe.w)
	_management.visible = false
	add_child(_management)
	_management.bind(state)
	_management.prestige_requested.connect(_on_prestige_requested)

	panel = FloorPanel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.bind(state)
	panel.lease_requested.connect(_on_lease_requested)
	panel.upgrade_requested.connect(_on_upgrade_requested)

	_prestige = PrestigePanel.new()
	_prestige.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_prestige)
	_prestige.bind(state)
	# It covers the whole screen, HUD band included, so it is the one surface
	# that has to inset itself rather than living inside an already-inset board.
	_prestige.set_insets(_safe)
	_prestige.node_purchase_requested.connect(_on_node_purchase)
	_prestige.demolish_requested.connect(_on_demolish)

	_dev = DevPanel.new()
	_dev.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dev)
	_dev.bind(state)
	_dev.set_insets(_safe)
	_dev.set_speed(_speed)
	_dev.cash_requested.connect(_on_dev_cash)
	_dev.earnings_requested.connect(_on_dev_earnings)
	_dev.blueprints_requested.connect(_on_dev_blueprints)
	_dev.speed_requested.connect(_on_dev_speed)
	_dev.unlock_requested.connect(_on_dev_unlock)
	_dev.reset_requested.connect(_on_dev_reset)

	_restack()

## Sibling order decides both drawing and input, and the two kinds of surface
## want OPPOSITE answers.
##
## FloorPanel is a bottom SHEET: the sim runs behind it and the HUD must stay
## reachable, so MANAGE and the shaft readout sit ABOVE it.
##
## PrestigePanel and DevPanel are full-screen OVERLAYS, so they go above the HUD
## in turn. Left among the views they draw underneath MANAGE, which then sits on
## top of their content -- and once they are last, nothing can draw through them
## either.
##
## Called from BOTH _rebuild_views and the end of _ready, and that is the point:
## _ready builds the views BEFORE the HUD, so a call from _rebuild_views alone
## finds _view_button still null, skips it, and leaves the HUD above the panels
## on the very first boot -- which is the state a player actually starts in.
func _restack() -> void:
	for later in [_pager_label, _view_button, _dev_button]:
		if later != null:
			move_child(later, get_child_count() - 1)
	for overlay in [_prestige, _dev]:
		if overlay != null:
			move_child(overlay, get_child_count() - 1)

## Seven taps reveals the dev panel, counted on RELEASE and reset when the gap
## exceeds DEV_TAP_WINDOW.
##
## Counting on release does NOT filter out drags: Godot routes the release to
## whichever control took the press, so press-here, drag away, release still
## counts. Harmless, because no draggable surface starts in the HUD band -- but
## the window is what actually does the work, not the release.
func _on_cash_input(event: InputEvent) -> void:
	if not PointerEvents.is_release(event):
		return
	if state == null or state.meta == null or state.meta.dev_unlocked:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_dev_taps = 1 if now - _dev_last_tap > DEV_TAP_WINDOW else _dev_taps + 1
	_dev_last_tap = now
	if _dev_taps < DEV_TAPS:
		return
	_dev_taps = 0
	state.meta.dev_unlocked = true
	_refresh_dev_button()
	save_now()                       # persistent state, so it is written at once

func _refresh_dev_button() -> void:
	if _dev_button != null:
		_dev_button.visible = state != null and state.meta != null \
			and state.meta.dev_unlocked

# --- the dev panel's actions ------------------------------------------------

## Cash ONLY. It must never call Economy.accrue(), which also raises
## lifetime_earnings -- the exact field Prestige.yield_for consumes. Routing dev
## money through accrue would mint Blueprints on every use.
func _on_dev_cash(amount: float) -> void:
	state.economy.cash += amount

## The prestige tester, and the one row that deliberately moves the yield.
func _on_dev_earnings(amount: float) -> void:
	state.economy.cash += amount
	state.economy.lifetime_earnings += amount

func _on_dev_blueprints(amount: int) -> void:
	# Clamped exactly as Prestige.demolish clamps, so the in-memory and on-disk
	# bounds stay one statement.
	state.meta.blueprints = mini(state.meta.blueprints + amount, Meta.MAX_BLUEPRINTS)
	save_now()
	_dev.refresh()

func _on_dev_speed(multiplier: int) -> void:
	_speed = maxi(multiplier, 1)
	_dev.set_speed(_speed)

## Grants levels without charging for them. `floor` and `shaft` are SKIPPED, and
## not for tidiness: grant_level deliberately never calls _apply, so granting
## `floor` would claim floors had been bought while the building still had six,
## and the next autosave makes that desync durable. ManagementView skips exactly
## these two ids for the same underlying reason -- they are bought on the board.
func _on_dev_unlock(level: int) -> void:
	for id in state.upgrades.ids():
		if id == "floor" or id == "shaft":
			continue
		# maxi, because grant_level ASSIGNS rather than raises. "Fit everything
		# to Lv1" on a run that had bought speed to Lv3 would otherwise DEMOTE
		# it and write the slower value onto every car -- the button reads as a
		# floor, so it behaves as one.
		state.upgrades.grant_level(id, maxi(level, state.upgrades.level_of(id)),
			state.building)
	_management.refresh()

func _on_dev_reset() -> void:
	# A delete is strictly more destructive than a write, so it needs at least
	# the same gate. Without this, `godot -- --board=40x8` -- a session whose
	# whole point is that "taking a screenshot cannot cost somebody their
	# building" -- can still reach DEV (seven taps arm it in memory even though
	# save_now() correctly no-ops) and wipe the real save AND its backup, since
	# SaveStore.clear() removes BACKUP_PATH too. There is no recovery from that.
	if not _saving_enabled:
		return
	# Read the catalogs off the OUTGOING run before replacing it, so a reset
	# rebuilds against the same files this session was started with rather than
	# silently reverting to the shipped ones and defeating the overrides.
	var catalog := state.catalog_path()
	var blueprints := state.blueprints_path()
	SaveStore.clear()
	# Reset the autosave timer too. Without it, a reset that lands with
	# _since_save already past AUTOSAVE_SECONDS is undone on the very next
	# frame: _physics_process fires save_now() and writes the fresh state
	# straight back out, so "Reset save" leaves a save behind.
	_since_save = 0.0
	_speed = 1
	# Built into a LOCAL and validated BEFORE `state` is overwritten. Assigning
	# first and returning on the error path skips _rebuild_views(), leaving the
	# old panels visible, still wired to their handlers, and now pointing at a
	# GameState whose _init returned early before constructing `economy` -- and
	# the error screen's ColorRect is MOUSE_FILTER_IGNORE, so it draws over them
	# without swallowing the tap.
	var fresh := GameState.new(GameState.BASE_FLOORS, GameState.BASE_SHAFTS,
		GameState.BASE_SEED, catalog, null, blueprints)
	if not fresh.is_valid():
		_show_error_screen(fresh.invalid_what(), fresh.invalid_path())
		_saving_enabled = false
		set_physics_process(false)
		return
	state = fresh
	last_selected_floor = -1
	_rebuild_views()
	_view_button.text = "MANAGE"
	_refresh_dev_button()
	_last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
	_refresh_pager()

func _on_prestige_requested() -> void:
	_prestige.open(state)

## Replaces the run. The WRITE COMES FIRST and its result is checked: swapping
## state and then saving would show the player the new run while the durable
## file still held the old, still-demolish-eligible one -- reload and the same
## earnings pay a second time, and the ten-second autosave would retry against
## the same broken condition. Fixing SaveStore's atomicity does not fix this; it
## is an ordering bug, not a file-replacement bug.
func _on_demolish() -> void:
	var next := Prestige.demolish(state)
	if next == null:
		return                       # the gate refused; NOTHING has changed
	if not save_now(next):
		_show_save_failed()          # old run and Meta intact, on disk and in memory
		return
	state = next
	last_selected_floor = -1         # a stale index into a building that just shrank
	_rebuild_views()
	# It lives outside the rebuilt range, so it would otherwise still read
	# "BOARD" while the board is showing.
	_view_button.text = "MANAGE"
	_last_shape = Vector2i(state.building.floor_count, state.building.cars.size())
	# Early-returns on `if _management.visible`, so it must run after the new
	# (hidden) management view exists.
	_refresh_pager()

## Permits retry rather than latching: the staged-Meta design makes a retry safe
## because nothing was credited. But it must not silently re-arm the autosave
## against the OLD state while the player believes the demolish happened, so the
## old run stays authoritative and the next explicit REBUILD tries again.
func _show_save_failed() -> void:
	_prestige.close()
	_cash_label.text = "SAVE FAILED — try REBUILD again"

## A node purchase mutates PERSISTENT state, so it is written immediately rather
## than waiting for the ten-second autosave. That is why it routes through a
## signal like FloorPanel.lease_requested instead of ManagementView's direct
## _state.buy().
func _on_node_purchase(id: String) -> void:
	if state.meta.buy(id, state.upgrades):
		save_now()
		_prestige.refresh()

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
	bg.color = Palette.APP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_error_label = Label.new()
	_error_label.text = "No valid %s\n\n%s\n\nCannot start." % [what, path]
	_error_label.add_theme_font_size_override("font_size", 27)
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
	# Still hidden entirely while every slot fits: a readout for something you
	# can already see is noise on a 393pt-wide phone.
	var pageable := _view.max_scroll() > 0
	_pager_label.visible = pageable
	if not pageable:
		return
	var first := _view.first_visible_shaft()
	var last := mini(first + _view.visible_shafts(), total)
	_pager_label.text = "shafts %d-%d of %d" % [first + 1, maxi(last, first + 1), total]

## Saving on a timer AND on the way out. iOS suspends an app without warning,
## and NOTIFICATION_APPLICATION_PAUSED is the last moment anything runs.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_EXIT_TREE:
			save_now()

## Takes an OPTIONAL GameState so a demolish can write the NEW run before
## swapping to it, and returns whether the write succeeded -- the old version
## discarded SaveStore.save()'s bool, so no branch could observe a failure.
##
## The parameter is optional rather than required because two existing tests
## call save_now() with no argument.
func save_now(s: GameState = null) -> bool:
	var target := s if s != null else state
	if not _saving_enabled or target == null:
		return false
	return SaveStore.save(target)

func _physics_process(delta: float) -> void:
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		_since_save = 0.0
		save_now()

	# The multiplier scales the DELTA handed to the clock, not the granted count.
	#
	# An earlier version multiplied the granted count and justified it with
	# arithmetic that was wrong three ways: it claimed the sim wants ~3.33 ticks
	# per frame at 60fps. Ticks per frame is frame_seconds / TICK_SECONDS =
	# (1/60) / 0.05 = 0.333 -- a 20Hz sim under a 60Hz callback, exactly as this
	# file's own header says. So take_ticks(delta * 4) asks for int(1.333) = 1
	# and the accumulator CARRIES the remainder, averaging a true 4x; the clamp
	# binds only when delta * speed > 0.4s, i.e. below 10fps.
	#
	# Multiplying the granted count instead defeats the clamp it claimed to
	# respect: MAX_TICKS_PER_FRAME (8) exists so "a hitch cannot spiral", and
	# 8 * 4 = 32 ticks in the frame AFTER a hitch is the spiral. Measured, not
	# reasoned: test_a_hitch_is_still_clamped_at_speed ran 32 against a clamp of
	# 8 before this change.
	var ticks := state.clock.take_ticks(delta * float(_speed))
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
	_day_strip.position = Vector2(16 + _safe.x, DAY_STRIP_TOP + _safe.y)
	_day_strip.size = Vector2(size.x - 32 - _safe.x - _safe.z, DAY_STRIP_HEIGHT)
	_day_strip.show_series(state.day_rates(), state.day_mixes())
	_day_strip.set_now(state.clock.hour_of_day())
