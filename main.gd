extends Control

## Milestone 0: pipeline check.
##
## This is not the game. It exists to prove the whole chain works on a real
## iPhone before any game code is written: Godot 4.7 -> threadless web export
## -> GitHub Actions -> GitHub Pages -> mobile Safari.
##
## It exercises exactly the things the game will depend on and nothing else:
## rendering, an animation driven by the frame loop, touch input, text layout,
## and persistence to user:// (which is IndexedDB on web, and the single most
## likely thing to be broken on iOS).

var _taps := 0
var _elapsed := 0.0
var _car: ColorRect
var _readout: RichTextLabel
var _persist_status := "not tested"


func _ready() -> void:
	_build_ui()
	_test_persistence()


func _process(delta: float) -> void:
	_elapsed += delta
	# A car sliding up and down a shaft: the exact motion the game needs.
	var t := (sin(_elapsed * 0.9) + 1.0) * 0.5
	_car.position.y = lerpf(8.0, _car.get_parent().size.y - _car.size.y - 8.0, t)
	_readout.text = _readout_text()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	root.offset_left = 24
	root.offset_top = 24
	root.offset_right = -24
	root.offset_bottom = -24
	add_child(root)

	var title := Label.new()
	title.text = "PIPELINE CHECK"
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	# Shaft with a moving car.
	var shaft := Panel.new()
	shaft.custom_minimum_size = Vector2(0, 320)
	shaft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(shaft)

	_car = ColorRect.new()
	_car.color = Color("4cc2ff")
	_car.size = Vector2(72, 56)
	_car.position = Vector2(24, 8)
	shaft.add_child(_car)

	# Touch target.
	var button := Button.new()
	button.text = "TAP ME"
	button.custom_minimum_size = Vector2(0, 88)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(_on_tap)
	root.add_child(button)

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_readout.add_theme_font_size_override("normal_font_size", 20)
	root.add_child(_readout)


func _on_tap() -> void:
	_taps += 1
	_test_persistence()


func _readout_text() -> String:
	var vp := get_viewport_rect().size
	return "\n".join([
		"godot      %s" % Engine.get_version_info().string,
		"renderer   %s" % RenderingServer.get_video_adapter_name(),
		"platform   %s" % OS.get_name(),
		"viewport   %d x %d" % [vp.x, vp.y],
		"dpi scale  %.2f" % DisplayServer.screen_get_scale(),
		"fps        %d" % Engine.get_frames_per_second(),
		"taps       %d" % _taps,
		"user:// rw %s" % _persist_status,
	])


## user:// on web is IndexedDB and is the likeliest thing to fail on iOS,
## so the check writes and reads back rather than assuming.
func _test_persistence() -> void:
	var path := "user://pipeline_check.save"
	var payload := {"taps": _taps}
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_persist_status = "WRITE FAILED (%d)" % FileAccess.get_open_error()
		return
	out.store_string(JSON.stringify(payload))
	out.close()

	var inp := FileAccess.open(path, FileAccess.READ)
	if inp == null:
		_persist_status = "READ FAILED (%d)" % FileAccess.get_open_error()
		return
	var parsed: Variant = JSON.parse_string(inp.get_as_text())
	inp.close()
	if typeof(parsed) == TYPE_DICTIONARY and parsed.get("taps") == _taps:
		_persist_status = "ok"
	else:
		_persist_status = "ROUND-TRIP MISMATCH"
