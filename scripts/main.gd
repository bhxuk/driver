extends Node
## Top-level flow: title screen, lobby, loading and the world.
##
## Developer arguments (after "--"):
##   --map=forest|desert|snow   map for --solo / --host
##   --solo                     start single player straight away
##   --host[=port]              host straight away and start the map
##   --join=ip[:port]           join straight away
##   --bot                      drive forward on its own (testing)
##   --selftest                 run the automated checks, print results, quit
##   --screenshot=path          save a screenshot after loading, then quit
##   --quit-after=seconds       quit after this long

var ui_root: Control
var screen: Control
var world: World
var settings_overlay: SettingsMenu
var _args := {}
var _loading := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UI.make_theme()
	layer.add_child(ui_root)
	get_window().title = "Driver"
	get_window().min_size = Vector2i(1024, 600)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.join_failed.connect(_on_join_failed)
	Net.game_requested.connect(_on_game_requested)
	Net.lobby_requested.connect(_on_lobby_requested)
	_parse_args()
	show_main_menu()
	_run_dev_args()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a).trim_prefix("--")
		var parts := s.split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""


func _run_dev_args() -> void:
	if _args.has("quit-after"):
		get_tree().create_timer(float(_args["quit-after"])).timeout.connect(func(): get_tree().quit())
	var map: String = _args.get("map", "forest")
	if _args.has("ui-shot"):
		_ui_shot(str(_args["ui-shot"]), str(_args.get("ui", "menu")))
		return
	if _args.has("selftest") or _args.has("solo") or _args.has("screenshot"):
		Net.start_single()
		Net.start_game(map)
	elif _args.has("host"):
		var port := int(_args["host"]) if str(_args["host"]).is_valid_int() else Net.DEFAULT_PORT
		if Net.host(port) == OK:
			get_tree().create_timer(float(_args.get("start-delay", "0.5"))).timeout.connect(func(): Net.start_game(map))
	elif _args.has("join"):
		var target := str(_args["join"])
		var port2 := Net.DEFAULT_PORT
		if target.contains(":"):
			port2 = int(target.get_slice(":", 1))
			target = target.get_slice(":", 0)
		Settings.player_name = "Tester%d" % (randi() % 100)
		Net.join(target, port2)


# ---------------------------------------------------------------- screens

func _set_screen(c: Control) -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = c
	if c:
		ui_root.add_child(c)
		ui_root.move_child(c, 0)


func show_main_menu(msg: String = "") -> void:
	_free_world()
	var m := MainMenu.new()
	m.message = msg
	m.open_settings.connect(open_settings)
	_set_screen(m)


func show_lobby() -> void:
	_free_world()
	_set_screen(Lobby.new())


func open_settings() -> void:
	if settings_overlay and is_instance_valid(settings_overlay):
		return
	settings_overlay = SettingsMenu.new()
	ui_root.add_child(settings_overlay)


func _free_world() -> void:
	if world and is_instance_valid(world):
		world.queue_free()
	world = null


# ---------------------------------------------------------------- net events

func _on_session_started() -> void:
	if Net.online and not Net.in_game:
		show_lobby()


func _on_session_ended(reason: String) -> void:
	show_main_menu(reason)


func _on_join_failed(reason: String) -> void:
	show_main_menu(reason)


func _on_lobby_requested() -> void:
	show_lobby()


func _on_game_requested(map_id: String) -> void:
	if _loading:
		return
	_loading = true
	_free_world()
	var loading := ColorRect.new()
	loading.color = UI.BG
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := UI.vbox(8)
	v.add_child(UI.label("Loading %s" % MapDefs.display_name(map_id), 34))
	v.add_child(UI.label(str(MapDefs.get_def(map_id)["tagline"]), 18, UI.MUTED))
	var cc := UI.centered(v)
	loading.add_child(cc)
	_set_screen(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	if not Net.in_game or Net.current_map != map_id:
		_loading = false
		return
	var t0 := Time.get_ticks_msec()
	world = World.new()
	add_child(world)
	world.build(map_id, ui_root)
	print("[driver] built %s in %d ms" % [map_id, Time.get_ticks_msec() - t0])
	_set_screen(null)
	_loading = false
	_after_world_loaded()


# ---------------------------------------------------------------- test hooks

func _after_world_loaded() -> void:
	if _args.has("bot") and world.local_truck:
		world.local_truck.bot_throttle = 0.8
	if _args.has("screenshot"):
		_take_screenshot(str(_args["screenshot"]))
	if _args.has("selftest"):
		_selftest()
	if _args.has("nettest"):
		_nettest()


func _nettest() -> void:
	# Both sides: print what we see every few seconds. The client also sends some events.
	var client := not Net.is_host()
	if client:
		await get_tree().create_timer(2.0).timeout
		Net.report_event("found", {"index": 2})
		Net.report_event("pickup", {"depot": 0})
	for k in 6:
		await get_tree().create_timer(3.0).timeout
		var parts := []
		for id in world.trucks.keys():
			var t: Node3D = world.trucks[id]
			parts.append("%d:%s(%s)" % [id, "local" if t is TruckBody else "remote", str(t.global_position.snapped(Vector3.ONE * 0.1))])
		print("[driver] NET %s me=%d players=%d trucks=[%s] earnings=%d cargo=%s found=%d" % [
			"client" if client else "host", Net.my_id(), Net.players.size(), ", ".join(parts),
			int(world.objectives.state.get("earnings", 0)), str(world.objectives.state.get("cargo", {}).keys()), world.objectives.found_count()])


func _ui_shot(path: String, which: String) -> void:
	match which:
		"lobby":
			Net.host(Net.DEFAULT_PORT + 7)
			Net.players[2] = {"name": "Siobhan", "color": 1}
			Net.players[3] = {"name": "Mo", "color": 2}
			Net.players_changed.emit()
		"settings":
			open_settings()
		"join":
			(screen as MainMenu).show_join()
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[driver] screenshot saved: ", path)
	get_tree().quit()


func _take_screenshot(path: String) -> void:
	var truck := world.local_truck
	var view := str(_args.get("view", "chase"))
	if view == "drive":
		truck.bot_throttle = 0.7
		await get_tree().create_timer(4.0).timeout
		truck.bot_throttle = 0.0
	else:
		await get_tree().create_timer(2.0).timeout
	if view == "aerial":
		world.camera.set_physics_process(false)
		var c := world.terrain.hub + Vector3(-90, 70, 120)
		world.camera.global_position = c
		world.camera.look_at(world.terrain.hub + Vector3(40, 0, -60), Vector3.UP)
	elif view == "side":
		world.camera.yaw_offset = 2.1
		world.camera.pitch = 0.18
		world.camera.distance = 9.5
	if _args.has("hero"):
		world.camera.h_offset = -3.4
		world.camera.v_offset = 0.4
	if _args.has("no-hud"):
		world.hud.visible = false
	if _args.has("map-view"):
		world.open_map()
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[driver] screenshot saved: ", path)
	get_tree().quit()


func _selftest() -> void:
	var results := {}
	var truck := world.local_truck
	var terrain := world.terrain
	results["map"] = world.map_id
	results["trails"] = terrain.trails.size()
	results["routes"] = world.objectives.routes.size()
	results["route_checkpoints"] = [world.objectives.routes[0]["points"].size(), world.objectives.routes[1]["points"].size()]
	results["depots"] = world.objectives.depots.size()
	results["landmarks"] = world.objectives.landmarks.size()
	results["props"] = world.props.anchors.get_child_count()
	# Collision matches the visual heights.
	var space := world.get_world_3d().direct_space_state
	await get_tree().physics_frame
	var worst := 0.0
	for i in 20:
		var x := randf_range(-400, 400)
		var z := randf_range(-400, 400)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -100, z))
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["collider"] as Node).is_in_group("ground"):
			worst = maxf(worst, absf((hit["position"] as Vector3).y - terrain.height_at(x, z)))
	results["collision_height_error"] = snappedf(worst, 0.01)
	# Let the truck settle, then drive along the first trail.
	await get_tree().create_timer(2.0).timeout
	results["settle_upright"] = snappedf(truck.global_basis.y.y, 0.01)
	results["settle_height_above_ground"] = snappedf(truck.global_position.y - terrain.height_at(truck.global_position.x, truck.global_position.z), 0.01)
	var start := truck.global_position
	var line: PackedVector3Array = terrain.trails[0]
	var t_end := Time.get_ticks_msec() + 12000
	var max_speed := 0.0
	var idx := 2
	while Time.get_ticks_msec() < t_end:
		await get_tree().physics_frame
		while idx < line.size() - 1 and Vector2(line[idx].x - truck.global_position.x, line[idx].z - truck.global_position.z).length() < 12.0:
			idx += 1
		var to := line[idx] - truck.global_position
		var local := truck.global_basis.inverse() * to
		var steer := clampf(-local.x / maxf(-local.z, 2.0) * 2.0, -1.0, 1.0)
		truck.bot_throttle = 0.85
		truck.bot_steer = steer
		max_speed = maxf(max_speed, truck.speed)
	truck.bot_throttle = 0.0
	results["drove_m"] = snappedf(start.distance_to(truck.global_position), 0.1)
	results["trail_points_passed"] = idx
	results["max_speed_mph"] = roundi(max_speed * 2.23694)
	results["upright_after_drive"] = snappedf(truck.global_basis.y.y, 0.01)
	# Brake to a stop.
	await get_tree().create_timer(3.0).timeout
	results["speed_after_coast_mph"] = roundi(absf(truck.speed) * 2.23694)
	# Flip test: roll it over and use the flip helper.
	truck.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), truck.global_position + Vector3(0, 2, 0))
	await get_tree().create_timer(2.0).timeout
	results["upside_down_before_flip"] = truck.global_basis.y.y < 0.3
	truck.flip_upright()
	await get_tree().create_timer(2.0).timeout
	results["upright_after_flip"] = snappedf(truck.global_basis.y.y, 0.01)
	# Winch: aim at the nearest prop collider.
	var nearest := Vector3.ZERO
	var nd := INF
	for cs in world.props.anchors.get_children():
		var d := (cs as Node3D).global_position.distance_to(truck.global_position)
		if d < nd and d > 6.0:
			nd = d
			nearest = (cs as Node3D).global_position
	if nd < 200.0:
		var dir := nearest - truck.global_position
		dir.y = 0
		var near_pos := nearest - dir.normalized() * 14.0
		truck.place_at(Vector3(near_pos.x, terrain.height_at(near_pos.x, near_pos.z) + 1.3, near_pos.z), dir.normalized())
		await get_tree().create_timer(1.5).timeout
		world.camera.global_transform = Transform3D(truck.global_basis, truck.global_position + truck.global_basis.z * 8.0 + Vector3.UP * 3.0)
		var hit := world.find_winch_anchor(truck)
		results["winch_anchor_found"] = not hit.is_empty()
		if not hit.is_empty():
			truck._try_attach_winch()
			var before := truck.winch_point().distance_to(truck.winch_world_anchor())
			Input.action_press("winch_in")
			await get_tree().create_timer(3.0).timeout
			Input.action_release("winch_in")
			results["winch_pulled_m"] = snappedf(before - truck.winch_point().distance_to(truck.winch_world_anchor()), 0.1)
			truck.release_winch("")
	# Objective events through the host path.
	var obj := world.objectives
	Net.report_event("abandon")
	await get_tree().create_timer(0.2).timeout
	Net.report_event("route_start", {"route": 0})
	await get_tree().create_timer(0.3).timeout
	results["route_started"] = obj.state["route"] == 0
	var count: int = obj.routes[0]["points"].size()
	for i in range(1, count - 1):
		Net.report_event("checkpoint", {"route": 0, "index": i})
	Net.report_event("finish", {"route": 0})
	await get_tree().create_timer(0.3).timeout
	results["route_completed"] = obj.state["route"] == -1 and not obj.state["last_result"].is_empty()
	Net.report_event("pickup", {"depot": 0})
	await get_tree().create_timer(0.3).timeout
	var job := obj.my_job()
	results["job_assigned"] = not job.is_empty()
	if not job.is_empty():
		Net.report_event("deliver", {"depot": job["to"], "condition": 80.0})
		await get_tree().create_timer(0.3).timeout
	Net.report_event("found", {"index": 0})
	await get_tree().create_timer(0.3).timeout
	results["earnings"] = obj.state["earnings"]
	results["deliveries"] = obj.state["deliveries"]
	results["fps"] = Engine.get_frames_per_second()
	print("[driver] SELFTEST ", JSON.stringify(results))
	get_tree().quit()
