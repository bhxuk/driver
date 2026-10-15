class_name Hud
extends Control
## In-game overlay: compass, objectives, players, speed, prompts and toasts.

var world: Node
var _compass: Control
var _obj: Label
var _players: VBoxContainer
var _speed: Label
var _unit: Label
var _surface: Label
var _prompt: Label
var _flip_bar: ProgressBar
var _toasts: VBoxContainer
var _help: PanelContainer
var _help_timer := 14.0
var _players_dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Compass.
	_compass = Compass.new()
	_compass.hud = self
	_compass.custom_minimum_size = Vector2(720, 46)
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-360, 16)
	_compass.size = Vector2(720, 46)
	add_child(_compass)
	# Toasts under the compass.
	_toasts = UI.vbox(6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position = Vector2(-360, 74)
	_toasts.size = Vector2(720, 10)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)
	# Objectives (top left).
	var op := PanelContainer.new()
	op.add_theme_stylebox_override("panel", _glass())
	op.position = Vector2(20, 18)
	_obj = UI.label("", 17)
	op.add_child(_obj)
	add_child(op)
	# Players (top right).
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", _glass())
	pp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pp.position = Vector2(-20, 18)
	_players = UI.vbox(4)
	pp.add_child(_players)
	add_child(pp)
	# Speed (bottom right).
	var sp := VBoxContainer.new()
	sp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	sp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sp.position = Vector2(-40, -30)
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.add_theme_constant_override("separation", 0)
	_speed = UI.shadow_label("0", 76)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unit = UI.shadow_label("mph", 20, UI.ACCENT)
	_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_surface = UI.shadow_label("", 16, UI.MUTED)
	_surface.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sp.add_child(_speed)
	sp.add_child(_unit)
	sp.add_child(UI.spacer(4))
	sp.add_child(_surface)
	add_child(sp)
	# Prompt (bottom centre).
	var pv := UI.vbox(6)
	pv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pv.position = Vector2(-300, -110)
	pv.size = Vector2(600, 80)
	pv.alignment = BoxContainer.ALIGNMENT_END
	_prompt = UI.shadow_label("", 19)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flip_bar = ProgressBar.new()
	_flip_bar.custom_minimum_size = Vector2(240, 10)
	_flip_bar.show_percentage = false
	_flip_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_flip_bar.max_value = 1.0
	var fb := StyleBoxFlat.new()
	fb.bg_color = UI.ACCENT
	fb.set_corner_radius_all(4)
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0, 0, 0, 0.5)
	bgsb.set_corner_radius_all(4)
	_flip_bar.add_theme_stylebox_override("fill", fb)
	_flip_bar.add_theme_stylebox_override("background", bgsb)
	_flip_bar.visible = false
	pv.add_child(_prompt)
	pv.add_child(_flip_bar)
	add_child(pv)
	# Controls help (bottom left).
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _glass())
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.position = Vector2(20, -20)
	var hl := UI.label(_help_text(), 15, UI.TEXT)
	_help.add_child(hl)
	add_child(_help)
	Net.players_changed.connect(func(): _players_dirty = true)
	Net.toast_received.connect(toast)


func _help_text() -> String:
	var rows := [
		["Drive", "%s %s %s %s" % [_k("throttle"), _k("steer_left"), _k("brake"), _k("steer_right")]],
		["Handbrake", _k("handbrake")],
		["Winch", "%s attach, %s in, %s out" % [_k("winch"), _k("winch_in"), _k("winch_out")]],
		["Flip upright", "hold " + _k("flip")],
		["Respawn", _k("respawn")],
		["Lights / horn", "%s / %s" % [_k("lights"), _k("horn")]],
		["Map", _k("map")],
		["Camera", "mouse, %s to switch" % _k("camera_toggle")],
	]
	var out := ""
	for r in rows:
		out += "%s:  %s\n" % [r[0], r[1]]
	return out + "F1: show / hide this"


func _k(action: String) -> String:
	return OS.get_keycode_string(int(Settings.binds[action]["key"]))


func _glass() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.055, 0.05, 0.62)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(12)
	return s


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_help.visible = not _help.visible
		_help_timer = -1.0


func _process(delta: float) -> void:
	if world == null:
		return
	if _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_help.visible = false
	var truck: TruckBody = world.local_truck
	var obj: Objectives = world.objectives
	if truck:
		_speed.text = Settings.speed_text(truck.speed)
		_unit.text = Settings.unit_label()
		_surface.text = truck.surface_label + ("   Lights on" if truck.lights_on else "")
		_flip_bar.visible = truck.flip_progress > 0.0
		_flip_bar.value = truck.flip_progress
		var prompt := truck.winch_status()
		if prompt == "" and truck.global_basis.y.y < 0.3:
			prompt = "Hold %s to flip upright" % _k("flip")
		if prompt == "" and obj:
			prompt = obj.pad_prompt()
		_prompt.text = prompt
	if obj:
		_obj.text = _objective_text(obj, truck)
	if _players_dirty:
		_players_dirty = false
		_refresh_players()
	_compass.queue_redraw()


func _objective_text(obj: Objectives, truck: TruckBody) -> String:
	var lines := []
	var st := obj.state
	var r: int = st.get("route", -1)
	if r >= 0:
		var route: Dictionary = obj.routes[r]
		var count: int = route["points"].size()
		var cp: int = st["cp"]
		lines.append("%s   %s" % [route["name"], Settings.format_time(obj.route_elapsed())])
		if cp >= count - 1:
			var fin: Array = st.get("finishers", [])
			if Net.players.size() > 1:
				lines.append("  Head to the finish (%d/%d there)" % [fin.size(), Net.players.size()])
			else:
				lines.append("  Head to the finish")
		else:
			lines.append("  Checkpoint %d of %d" % [cp, count - 1])
	else:
		lines.append("Routes: stop in a yellow gate")
	var job := obj.my_job()
	if not job.is_empty():
		var dest: Dictionary = obj.depots[int(job["to"])]
		var dist := 0.0
		if truck:
			dist = truck.global_position.distance_to(dest["pos"])
		var cond := truck.cargo_condition if truck else 100.0
		lines.append("Cargo to %s   %d m" % [dest["name"], roundi(dist)])
		lines.append("  Condition %d%%   Pays up to $%d" % [roundi(cond), int(job["reward"])])
	else:
		lines.append("Jobs: stop on a blue depot pad")
	lines.append("Landmarks %d / %d" % [obj.found_count(), obj.landmarks.size()])
	lines.append("Team earnings $%d   Deliveries %d" % [int(st.get("earnings", 0)), int(st.get("deliveries", 0))])
	return "\n".join(lines)


func _refresh_players() -> void:
	for c in _players.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var h := UI.hbox(8)
		h.add_child(UI.color_swatch(Net.player_color(id), 14))
		h.add_child(UI.label(Net.player_name(id) + (" (you)" if id == Net.my_id() else ""), 16))
		_players.add_child(h)


func toast(text: String, col: Color = Color.WHITE) -> void:
	var l := UI.shadow_label(text, 20, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


class Compass extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.world == null:
			return
		var cam: Camera3D = hud.world.camera
		if cam == null:
			return
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.06, 0.055, 0.05, 0.55))
		var fwd := -cam.global_basis.z
		var yaw := atan2(fwd.x, -fwd.z)  # 0 = north (-Z), clockwise positive
		var span := deg_to_rad(110.0)
		var font := get_theme_default_font()
		for deg in range(0, 360, 15):
			var a := deg_to_rad(float(deg))
			var dx := wrapf(a - yaw, -PI, PI)
			if absf(dx) > span * 0.5:
				continue
			var x := w * 0.5 + dx / span * w
			var major := deg % 90 == 0
			draw_line(Vector2(x, h - (16 if major else 8)), Vector2(x, h - 2), Color(1, 1, 1, 0.7 if major else 0.35), 2.0)
			if major:
				var letter: String = ["N", "E", "S", "W"][deg / 90]
				draw_string(font, Vector2(x - 6, 20), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.ACCENT if letter == "N" else UI.TEXT)
		var origin := cam.global_position
		var marks: Array = hud.world.objectives.markers() if hud.world.objectives else []
		for id in hud.world.trucks.keys():
			if id != Net.my_id():
				marks.append({"pos": (hud.world.trucks[id] as Node3D).global_position, "color": Net.player_color(id), "kind": "player"})
		for m in marks:
			var p: Vector3 = m["pos"]
			var d := Vector2(p.x - origin.x, p.z - origin.z)
			if d.length() < 1.0:
				continue
			var a2 := atan2(d.x, -d.y)
			var dx2 := wrapf(a2 - yaw, -PI, PI)
			var clamped := clampf(dx2, -span * 0.5, span * 0.5)
			var x2 := w * 0.5 + clamped / span * w
			var col: Color = m["color"]
			if absf(dx2) > span * 0.5:
				col.a = 0.45
			var y := 30.0
			if m["kind"] == "player":
				draw_circle(Vector2(x2, y), 6.0, col)
			elif m["kind"] in ["landmark", "depot"]:
				draw_rect(Rect2(x2 - 4, y - 4, 8, 8), col)
			else:
				var pts := PackedVector2Array([Vector2(x2, y - 8), Vector2(x2 + 7, y + 5), Vector2(x2 - 7, y + 5)])
				draw_colored_polygon(pts, col)
			if m["kind"] in ["route", "dest"]:
				draw_string(font, Vector2(x2 + 10, y + 6), "%d m" % roundi(d.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 8), UI.ACCENT, 3.0)
