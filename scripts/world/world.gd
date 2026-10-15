class_name World
extends Node3D
## One loaded map: terrain, props, objectives, trucks, camera and in-game UI.

var map_id := ""
var def: Dictionary
var terrain: Terrain
var props: Props
var objectives: Objectives
var trucks: Dictionary = {}  # peer_id -> TruckBody / TruckRemote
var local_truck: TruckBody
var camera: ChaseCamera
var sun: DirectionalLight3D
var ui_parent: Control
var hud: Hud
var overlay: Control  # pause, map or settings currently open
var weather: GPUParticles3D
var _overlay_frame := 0


func build(id: String, ui: Control) -> void:
	map_id = id
	ui_parent = ui
	def = MapDefs.get_def(id)
	name = "World"
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(def)
	objectives = Objectives.new()
	objectives.name = "Objectives"
	add_child(objectives)
	objectives.setup(self, terrain, id)
	objectives.local_toast.connect(func(t, c): if hud: hud.toast(t, c))
	var camp := Markers.base_camp(UI.ACCENT)
	var depot0: Vector3 = objectives.depots[0]["pos"]
	camp.position = terrain.find_hub_spot(26.0, [depot0])
	var camp_dir := (camp.position - terrain.hub).normalized()
	camp.rotation.y = atan2(-camp_dir.x, -camp_dir.z)
	add_child(camp)
	var avoid := [[terrain.hub, 48.0], [camp.position, 14.0]]
	for d in objectives.depots:
		avoid.append([d["pos"], 16.0])
	for p in objectives.landmarks:
		avoid.append([p, 10.0])
	for r in objectives.routes:
		for p in r["points"]:
			avoid.append([p, 10.0])
	props = Props.new()
	props.name = "Props"
	add_child(props)
	props.build(terrain, def, avoid)
	camera = ChaseCamera.new()
	camera.terrain = terrain
	add_child(camera)
	_build_weather()
	hud = Hud.new()
	hud.world = self
	ui_parent.add_child(hud)
	Net.players_changed.connect(_sync_trucks)
	Net.truck_state_received.connect(_on_truck_state)
	Net.horn_received.connect(_on_horn)
	Settings.changed.connect(_apply_settings)
	_sync_trucks()
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("Welcome to %s" % def["name"], UI.ACCENT)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud and is_instance_valid(hud):
		hud.queue_free()
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = def["sky_top"]
	sky_mat.sky_horizon_color = def["sky_horizon"]
	sky_mat.ground_horizon_color = def["ground_horizon"]
	sky_mat.ground_bottom_color = (def["ground_horizon"] as Color).darkened(0.4)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = def["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = def["fog_color"]
	env.fog_density = def["fog_density"]
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = def["sun_color"]
	sun.light_energy = def["sun_energy"]
	sun.rotation_degrees = Vector3(def["sun_pitch"], def["sun_yaw"], 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func _build_weather() -> void:
	var kind := str(def.get("weather", "none"))
	if kind == "none":
		return
	weather = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 10, 40)
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if kind == "snow":
		pm.direction = Vector3(0.3, -1, 0.1)
		pm.spread = 15.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3(0.4, -1.0, 0.0)
		quad.size = Vector2(0.12, 0.12)
		mat.albedo_color = Color(1, 1, 1, 0.9)
		weather.amount = 2500
		weather.lifetime = 4.0
	else:
		pm.direction = Vector3(1, 0, 0.2)
		pm.spread = 25.0
		pm.initial_velocity_min = 6.0
		pm.initial_velocity_max = 10.0
		pm.gravity = Vector3(0, -0.2, 0)
		quad.size = Vector2(0.06, 0.06)
		mat.albedo_color = Color(0.92, 0.75, 0.55, 0.55)
		weather.amount = 900
		weather.lifetime = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = g
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	mat.albedo_texture = dot
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.0
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.6
	mat.distance_fade_max_distance = 3.0
	quad.material = mat
	weather.process_material = pm
	weather.draw_pass_1 = quad
	weather.visibility_aabb = AABB(Vector3(-50, -20, -50), Vector3(100, 40, 100))
	weather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(weather)


func _apply_settings() -> void:
	if sun:
		sun.shadow_enabled = Settings.shadows


# ---------------------------------------------------------------- trucks

func _sync_trucks() -> void:
	if not is_inside_tree():
		return
	for id in trucks.keys():
		if not Net.players.has(id):
			var t: Node = trucks[id]
			trucks.erase(id)
			t.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		if trucks.has(id):
			continue
		var col := Net.player_color(id)
		var pname := Net.player_name(id)
		if id == Net.my_id():
			var tb := TruckBody.new()
			tb.setup(id, self, terrain, col, pname)
			add_child(tb)
			tb.message.connect(func(m): if hud: hud.toast(m, UI.MUTED.lightened(0.3)))
			tb.cargo_lost.connect(objectives.on_local_cargo_lost)
			var slot := ids.find(id)
			var dir := terrain.trails[0][3] - terrain.trails[0][0] if terrain.trails.size() > 0 else Vector3.FORWARD
			dir.y = 0
			var a := slot * TAU / 4.0 + 0.4
			var p := terrain.hub + Vector3(cos(a), 0, sin(a)) * 9.0
			p.y = terrain.height_at(p.x, p.z) + 1.3
			tb.place_at(p, dir.normalized())
			trucks[id] = tb
			local_truck = tb
			camera.target = tb
		else:
			var tr := TruckRemote.new()
			tr.setup(id, self, col, pname)
			add_child(tr)
			tr.global_position = terrain.hub + Vector3(0, -50, 0)
			trucks[id] = tr


func _on_truck_state(peer_id: int, state: Array) -> void:
	var t: Variant = trucks.get(peer_id)
	if t is TruckRemote:
		(t as TruckRemote).push_state(state)


func _on_horn(peer_id: int, on: bool) -> void:
	var t: Variant = trucks.get(peer_id)
	if t is TruckRemote:
		(t as TruckRemote).set_horn(on)


## Finds something to winch to in front of (or around) the truck, aimed by the camera.
func find_winch_anchor(truck: TruckBody) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := truck.winch_point()
	var aim := -camera.global_basis.z
	aim.y = 0
	if aim.length() < 0.1:
		aim = -truck.global_basis.z
	aim = aim.normalized()
	var best := {}
	var best_d := INF
	for k in 13:
		var ang := deg_to_rad((k - 6) * 6.0)
		for lift in [-0.12, 0.05, 0.25, 0.55]:
			var dir := aim.rotated(Vector3.UP, ang)
			dir.y = lift
			dir = dir.normalized()
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * TruckBody.WINCH_MAX * 0.8)
			q.exclude = [truck.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var col: Object = hit["collider"]
			if not (col is Node) or not (col as Node).is_in_group("winch_anchor"):
				continue
			var d: float = origin.distance_to(hit["position"])
			if d < best_d and d > 1.0:
				best_d = d
				if (col as Node).is_in_group("truck"):
					var other := col as Node3D
					best = {"peer": int(other.get_meta("peer_id")), "point": hit["position"], "anchor": other.to_local(hit["position"])}
				else:
					best = {"peer": 0, "point": hit["position"], "anchor": hit["position"]}
	return best


# ---------------------------------------------------------------- overlays

func _unhandled_input(event: InputEvent) -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_pause()
	elif event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		open_map()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_overlay(c: Control) -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = c
	_overlay_frame = Engine.get_process_frames()
	if local_truck:
		local_truck.input_enabled = c == null
	if hud:
		hud.visible = c == null or c is PauseMenu
	if c:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		ui_parent.add_child(c)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_pause() -> void:
	var p := PauseMenu.new()
	p.world = self
	p.resume.connect(func(): _set_overlay(null))
	p.open_map.connect(open_map)
	p.open_settings.connect(open_settings)
	_set_overlay(p)


func open_map() -> void:
	var m := MapView.new()
	m.world = self
	m.closed.connect(func():
		overlay = null
		_set_overlay(null))
	_set_overlay(m)


func open_settings() -> void:
	var s := SettingsMenu.new()
	s.closed.connect(func():
		overlay = null
		open_pause())
	_set_overlay(s)


func _process(_delta: float) -> void:
	if weather and camera:
		weather.global_position = camera.global_position + Vector3(0, 8, 0)
	# Pause menu also closes on its own key (not on the frame it opened).
	if overlay is PauseMenu and Engine.get_process_frames() > _overlay_frame:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_back"):
			_set_overlay(null)
