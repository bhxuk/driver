extends Node
## Player settings, input bindings and records. Saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"
const RECORDS_PATH := "user://records.cfg"

## Rebindable actions, in the order they appear in the controls menu.
const ACTIONS := [
	["throttle", "Accelerate"],
	["brake", "Brake / reverse"],
	["steer_left", "Steer left"],
	["steer_right", "Steer right"],
	["handbrake", "Handbrake"],
	["winch", "Winch attach / release"],
	["winch_in", "Winch reel in"],
	["winch_out", "Winch let out"],
	["flip", "Flip upright (hold)"],
	["respawn", "Respawn on trail"],
	["lights", "Headlights"],
	["horn", "Horn"],
	["camera_toggle", "Switch camera"],
	["map", "Map"],
	["pause", "Pause"],
]

## Pad binding format: {"t": "b", "i": button} or {"t": "a", "i": axis, "d": +1.0 / -1.0}
var DEFAULT_BINDS := {
	"throttle": {"key": KEY_W, "alt": KEY_UP, "pad": {"t": "a", "i": JOY_AXIS_TRIGGER_RIGHT, "d": 1.0}},
	"brake": {"key": KEY_S, "alt": KEY_DOWN, "pad": {"t": "a", "i": JOY_AXIS_TRIGGER_LEFT, "d": 1.0}},
	"steer_left": {"key": KEY_A, "alt": KEY_LEFT, "pad": {"t": "a", "i": JOY_AXIS_LEFT_X, "d": -1.0}},
	"steer_right": {"key": KEY_D, "alt": KEY_RIGHT, "pad": {"t": "a", "i": JOY_AXIS_LEFT_X, "d": 1.0}},
	"handbrake": {"key": KEY_SPACE, "pad": {"t": "b", "i": JOY_BUTTON_A}},
	"winch": {"key": KEY_F, "pad": {"t": "b", "i": JOY_BUTTON_Y}},
	"winch_in": {"key": KEY_G, "pad": {"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}},
	"winch_out": {"key": KEY_H, "pad": {"t": "b", "i": JOY_BUTTON_LEFT_SHOULDER}},
	"flip": {"key": KEY_R, "pad": {"t": "b", "i": JOY_BUTTON_X}},
	"respawn": {"key": KEY_BACKSPACE, "pad": {"t": "b", "i": JOY_BUTTON_BACK}},
	"lights": {"key": KEY_L, "pad": {"t": "b", "i": JOY_BUTTON_DPAD_UP}},
	"horn": {"key": KEY_E, "pad": {"t": "b", "i": JOY_BUTTON_LEFT_STICK}},
	"camera_toggle": {"key": KEY_C, "pad": {"t": "b", "i": JOY_BUTTON_RIGHT_STICK}},
	"map": {"key": KEY_M, "pad": {"t": "b", "i": JOY_BUTTON_DPAD_DOWN}},
	"pause": {"key": KEY_ESCAPE, "pad": {"t": "b", "i": JOY_BUTTON_START}},
}

var binds: Dictionary = {}

# Game
var player_name := "Driver"
var preferred_color := 0
var units := "mph"
var mouse_sensitivity := 1.0
var stick_sensitivity := 1.0
var invert_y := false
var auto_center_camera := true
# Display
var fullscreen := false
var vsync := true
var render_scale := 1.0
var shadows := true
var fov := 70.0
# Audio
var master_volume := 0.8
# Connection
var last_ip := "127.0.0.1"
var last_port := 24560

var records := ConfigFile.new()


func _ready() -> void:
	binds = DEFAULT_BINDS.duplicate(true)
	load_settings()
	_load_records()
	apply_inputs()
	apply_display()
	apply_audio()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		player_name = _default_name()
		return
	player_name = str(cfg.get_value("game", "player_name", _default_name())).strip_edges().left(16)
	if player_name == "":
		player_name = _default_name()
	preferred_color = int(cfg.get_value("game", "preferred_color", 0))
	units = str(cfg.get_value("game", "units", "mph"))
	mouse_sensitivity = float(cfg.get_value("game", "mouse_sensitivity", 1.0))
	stick_sensitivity = float(cfg.get_value("game", "stick_sensitivity", 1.0))
	invert_y = bool(cfg.get_value("game", "invert_y", false))
	auto_center_camera = bool(cfg.get_value("game", "auto_center_camera", true))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	vsync = bool(cfg.get_value("display", "vsync", true))
	render_scale = float(cfg.get_value("display", "render_scale", 1.0))
	shadows = bool(cfg.get_value("display", "shadows", true))
	fov = float(cfg.get_value("display", "fov", 70.0))
	master_volume = float(cfg.get_value("audio", "master_volume", 0.8))
	last_ip = str(cfg.get_value("net", "last_ip", "127.0.0.1"))
	last_port = int(cfg.get_value("net", "last_port", 24560))
	var saved: Variant = cfg.get_value("controls", "binds", {})
	if saved is Dictionary:
		for action in saved.keys():
			if binds.has(action) and saved[action] is Dictionary:
				var b: Dictionary = binds[action]
				var s: Dictionary = saved[action]
				if s.has("key"):
					b["key"] = int(s["key"])
				if s.has("pad") and s["pad"] is Dictionary:
					b["pad"] = s["pad"]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "player_name", player_name)
	cfg.set_value("game", "preferred_color", preferred_color)
	cfg.set_value("game", "units", units)
	cfg.set_value("game", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("game", "stick_sensitivity", stick_sensitivity)
	cfg.set_value("game", "invert_y", invert_y)
	cfg.set_value("game", "auto_center_camera", auto_center_camera)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "shadows", shadows)
	cfg.set_value("display", "fov", fov)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.set_value("net", "last_port", last_port)
	var out := {}
	for action in binds.keys():
		out[action] = {"key": binds[action]["key"], "pad": binds[action]["pad"]}
	cfg.set_value("controls", "binds", out)
	cfg.save(PATH)
	changed.emit()


func _default_name() -> String:
	var n := OS.get_environment("USERNAME")
	if n == "":
		n = OS.get_environment("USER")
	if n == "" or n == "root":
		n = "Driver"
	return n.left(16)


# ---------------------------------------------------------------- input

func apply_inputs() -> void:
	for entry in ACTIONS:
		var action: String = entry[0]
		_ensure_action(action, 0.25)
		InputMap.action_erase_events(action)
		var b: Dictionary = binds[action]
		InputMap.action_add_event(action, key_event(int(b["key"])))
		if b.has("alt"):
			InputMap.action_add_event(action, key_event(int(b["alt"])))
		var pe := pad_event(b["pad"])
		if pe:
			InputMap.action_add_event(action, pe)
	# Fixed camera look actions on the right stick.
	var look := {
		"look_left": [JOY_AXIS_RIGHT_X, -1.0],
		"look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
		"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	}
	for action in look.keys():
		_ensure_action(action, 0.2)
		InputMap.action_erase_events(action)
		var m := InputEventJoypadMotion.new()
		m.axis = look[action][0]
		m.axis_value = look[action][1]
		InputMap.action_add_event(action, m)
	# Menu helpers so the pad can drive menus too.
	_ensure_action("menu_back", 0.5)
	InputMap.action_erase_events("menu_back")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	InputMap.action_add_event("menu_back", back)


func _ensure_action(action: String, deadzone: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	else:
		InputMap.action_set_deadzone(action, deadzone)


static func key_event(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode as Key
	return e


static func pad_event(p: Variant) -> InputEvent:
	if not (p is Dictionary):
		return null
	var d: Dictionary = p
	if d.get("t", "") == "b":
		var e := InputEventJoypadButton.new()
		e.button_index = int(d["i"]) as JoyButton
		return e
	if d.get("t", "") == "a":
		var m := InputEventJoypadMotion.new()
		m.axis = int(d["i"]) as JoyAxis
		m.axis_value = float(d.get("d", 1.0))
		return m
	return null


func set_key(action: String, keycode: int) -> void:
	binds[action]["key"] = keycode
	binds[action].erase("alt")
	apply_inputs()
	save_settings()


func set_pad(action: String, event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		binds[action]["pad"] = {"t": "b", "i": event.button_index}
	elif event is InputEventJoypadMotion:
		binds[action]["pad"] = {"t": "a", "i": event.axis, "d": signf(event.axis_value)}
	apply_inputs()
	save_settings()


func reset_binds() -> void:
	binds = DEFAULT_BINDS.duplicate(true)
	apply_inputs()
	save_settings()


func key_label(action: String) -> String:
	var b: Dictionary = binds[action]
	var label := OS.get_keycode_string(int(b["key"]))
	if b.has("alt"):
		label += " / " + OS.get_keycode_string(int(b["alt"]))
	return label


func pad_label(action: String) -> String:
	return describe_pad(binds[action]["pad"])


static func describe_pad(p: Variant) -> String:
	if not (p is Dictionary):
		return "-"
	var d: Dictionary = p
	if d.get("t", "") == "b":
		var names := {
			JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_GUIDE: "Guide",
			JOY_BUTTON_LEFT_STICK: "LS click", JOY_BUTTON_RIGHT_STICK: "RS click",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
			JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
		}
		return names.get(int(d["i"]), "Button %d" % int(d["i"]))
	if d.get("t", "") == "a":
		var axis := int(d["i"])
		var dir := float(d.get("d", 1.0))
		match axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_LEFT_X: return "LS left" if dir < 0 else "LS right"
			JOY_AXIS_LEFT_Y: return "LS up" if dir < 0 else "LS down"
			JOY_AXIS_RIGHT_X: return "RS left" if dir < 0 else "RS right"
			JOY_AXIS_RIGHT_Y: return "RS up" if dir < 0 else "RS down"
		return "Axis %d" % axis
	return "-"


# ---------------------------------------------------------------- display / audio

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	get_viewport().scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	changed.emit()


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)


func speed_text(mps: float) -> String:
	if units == "kmh":
		return "%d" % roundi(absf(mps) * 3.6)
	return "%d" % roundi(absf(mps) * 2.23694)


func unit_label() -> String:
	return "km/h" if units == "kmh" else "mph"


# ---------------------------------------------------------------- records

func _load_records() -> void:
	records.load(RECORDS_PATH)


func best_time(map_id: String, route: int) -> float:
	return float(records.get_value(map_id, "route_%d" % route, -1.0))


func submit_time(map_id: String, route: int, seconds: float) -> bool:
	var best := best_time(map_id, route)
	if best < 0.0 or seconds < best:
		records.set_value(map_id, "route_%d" % route, seconds)
		records.save(RECORDS_PATH)
		return true
	return false


static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--"
	var m := int(seconds) / 60
	var s := fmod(seconds, 60.0)
	return "%d:%05.2f" % [m, s]
