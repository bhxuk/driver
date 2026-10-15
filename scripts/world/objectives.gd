class_name Objectives
extends Node3D
## Routes, delivery jobs and landmarks. The host owns the team state and broadcasts it;
## every peer checks its own truck against the markers and reports what it reached.

signal local_toast(text: String, color: Color)

const ROUTE_NAMES := {
	"forest": ["Riverside Run", "Timber Trail"],
	"desert": ["Canyon Dash", "Mesa Loop"],
	"snow": ["Switchback Climb", "Glacier Line"],
}
const DEPOT_NAMES := {
	"forest": ["Base Camp", "Sawmill", "Ranger Hut", "Old Bridge"],
	"desert": ["Base Camp", "Mine Office", "Water Tower", "Trading Post"],
	"snow": ["Base Camp", "Weather Station", "Ski Lodge", "Radio Mast"],
}
const CHECKPOINT_RADIUS := 9.5
const DEPOT_RADIUS := 7.5
const LANDMARK_RADIUS := 14.0
const LANDMARK_COUNT := 6
const LANDMARK_REWARD := 150
const LOAD_TIME := 1.2

const COL_ROUTE := Color("f2c14e")
const COL_FINISH := Color("ffffff")
const COL_DEPOT := Color("4ea3f2")
const COL_DEST := Color("6ee07a")
const COL_LANDMARK := Color("b07cf2")
const COL_FOUND := Color("6ee07a")

var world: Node
var terrain: Terrain
var map_id := ""
var routes: Array = []     # {"name", "points": Array[Vector3], "dirs": Array[Vector3]}
var depots: Array = []     # {"name", "pos": Vector3}
var landmarks: Array = []  # Vector3

var state := {}
var _received_at := 0.0
var _host_route_start := 0.0
var _host_rng := RandomNumberGenerator.new()
var _last_result_id := -1

# Local detection bookkeeping.
var _reported := {}
var _pad_timer := 0.0
var _start_cooldown := 0.0
var _gate_timer := 0.0

# Marker nodes.
var _route_starts: Array[Node3D] = []
var _gate: Node3D
var _gate_route := -2
var _gate_cp := -2
var _depot_nodes: Array[Node3D] = []
var _landmark_nodes: Array[Node3D] = []


func setup(w: Node, t: Terrain, id: String) -> void:
	world = w
	terrain = t
	map_id = id
	_host_rng.randomize()
	_build_layout()
	_build_markers()
	state = _empty_state()
	_received_at = _now()
	Net.objectives_received.connect(_on_state)
	Net.objective_event_received.connect(_on_event)
	Net.players_changed.connect(_on_players_changed)
	if Net.is_host():
		_broadcast()


func _empty_state() -> Dictionary:
	var found := []
	for i in landmarks.size():
		found.append(false)
	return {
		"route": -1, "cp": 0, "elapsed": 0.0, "finishers": [],
		"found": found, "earnings": 0, "deliveries": 0,
		"cargo": {}, "last_result": {},
	}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------- layout

func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(terrain.def["seed"]) * 13 + 5
	var order := range(terrain.trails.size())
	order.sort_custom(func(a, b): return terrain.trails[a].size() > terrain.trails[b].size())
	var names: Array = ROUTE_NAMES.get(map_id, ["Route A", "Route B"])
	for r in 2:
		var line: PackedVector3Array = terrain.trails[order[r]]
		var pts: Array = []
		var dirs: Array = []
		var i := 5
		while i < line.size() - 3:
			pts.append(line[i])
			dirs.append(_dir_at(line, i))
			i += 10
		pts.append(line[line.size() - 2])
		dirs.append(_dir_at(line, line.size() - 2))
		routes.append({"name": names[r], "points": pts, "dirs": dirs})
	var dnames: Array = DEPOT_NAMES.get(map_id, ["Base Camp", "Depot B", "Depot C", "Depot D"])
	var hub := terrain.hub
	depots.append({"name": dnames[0], "pos": terrain.find_hub_spot(18.0)})
	# Other depots: trail ends first, then points along trails, kept well apart.
	var cands_d := []
	for idx in range(order.size()):
		var line2: PackedVector3Array = terrain.trails[order[idx]]
		cands_d.append(line2[maxi(line2.size() - 3, 0)])
	for idx in range(order.size()):
		var line2b: PackedVector3Array = terrain.trails[order[idx]]
		for f in [0.75, 0.5]:
			cands_d.append(line2b[int(line2b.size() * f)])
	for c in cands_d:
		if depots.size() >= dnames.size():
			break
		var ok_d := true
		for d in depots:
			if (d["pos"] as Vector3).distance_to(c) < 220.0:
				ok_d = false
				break
		for r in routes:
			for rp in r["points"]:
				if (rp as Vector3).distance_to(c) < 18.0:
					ok_d = false
		if ok_d:
			depots.append({"name": dnames[depots.size()], "pos": terrain.ground_point(c.x, c.z)})
	while depots.size() < 3:
		var line3: PackedVector3Array = terrain.trails[order[depots.size() % order.size()]]
		var p3 := line3[line3.size() / 3]
		depots.append({"name": dnames[depots.size()], "pos": terrain.ground_point(p3.x, p3.z)})
	# Landmarks: high, open spots away from trails and spread out.
	var cands := []
	for c in 600:
		var x := rng.randf_range(-Terrain.HALF + 90.0, Terrain.HALF - 90.0)
		var z := rng.randf_range(-Terrain.HALF + 90.0, Terrain.HALF - 90.0)
		if terrain.slope_at(x, z) > 0.5 or terrain.road_weight_at(x, z) > 0.0:
			continue
		if terrain.surface_at(x, z) == Terrain.Surf.WATER:
			continue
		if Vector2(x - hub.x, z - hub.z).length() < 130.0:
			continue
		cands.append(terrain.ground_point(x, z))
	cands.sort_custom(func(a, b): return a.y > b.y)
	for p in cands:
		if landmarks.size() >= LANDMARK_COUNT:
			break
		var ok := true
		for q in landmarks:
			if (q as Vector3).distance_to(p) < 170.0:
				ok = false
				break
		if ok:
			landmarks.append(p)
	# Fill any gap with lower spots if the map is very rough.
	for p in cands:
		if landmarks.size() >= LANDMARK_COUNT:
			break
		if not (p in landmarks):
			landmarks.append(p)


func _dir_at(line: PackedVector3Array, i: int) -> Vector3:
	var a := line[maxi(i - 1, 0)]
	var b := line[mini(i + 1, line.size() - 1)]
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _build_markers() -> void:
	for r in routes.size():
		var route: Dictionary = routes[r]
		var start := Markers.checkpoint_gate(COL_ROUTE, route["dirs"][0])
		start.position = route["points"][0]
		start.add_child(Markers.label(route["name"], 9.0, COL_ROUTE, 96))
		var best := Markers.label("", 8.0, Color(1, 1, 1, 0.85), 60)
		best.name = "Best"
		best.position.y = 7.6
		start.add_child(best)
		add_child(start)
		_route_starts.append(start)
	for d in depots:
		var n := Markers.depot(COL_DEPOT, d["name"])
		n.position = d["pos"]
		add_child(n)
		_depot_nodes.append(n)
	for p in landmarks:
		var n2 := Markers.landmark(COL_LANDMARK)
		n2.position = p
		add_child(n2)
		_landmark_nodes.append(n2)
	_refresh_markers()


# ---------------------------------------------------------------- host side

func _on_event(peer: int, kind: String, data: Dictionary) -> void:
	if not Net.is_host():
		return
	var who := Net.player_name(peer)
	match kind:
		"route_start":
			var r := int(data.get("route", -1))
			if state["route"] == -1 and r >= 0 and r < routes.size():
				state["route"] = r
				state["cp"] = 1
				state["finishers"] = []
				_host_route_start = _now()
				var msg := "%s started %s" % [who, routes[r]["name"]]
				if Net.players.size() > 1:
					msg += ". Everyone must reach the finish."
				Net.send_toast(msg, COL_ROUTE)
		"checkpoint":
			var r2 := int(data.get("route", -1))
			var count: int = routes[r2]["points"].size() if r2 >= 0 and r2 < routes.size() else 0
			if r2 == state["route"] and int(data.get("index", -1)) == state["cp"] and state["cp"] < count - 1:
				state["cp"] = int(state["cp"]) + 1
		"finish":
			var r3 := int(data.get("route", -1))
			if r3 == state["route"] and r3 >= 0:
				var count3: int = routes[r3]["points"].size()
				if int(state["cp"]) >= count3 - 1 and not (peer in state["finishers"]):
					state["finishers"].append(peer)
					if Net.players.size() > 1 and state["finishers"].size() < Net.players.size():
						Net.send_toast("%s reached the finish (%d/%d)" % [who, state["finishers"].size(), Net.players.size()], COL_FINISH)
					_check_route_complete()
		"abandon":
			if state["route"] >= 0:
				Net.send_toast("%s was abandoned" % routes[state["route"]]["name"], Color(0.9, 0.6, 0.4))
				state["route"] = -1
				state["finishers"] = []
		"found":
			var i := int(data.get("index", -1))
			if i >= 0 and i < landmarks.size() and not state["found"][i]:
				state["found"][i] = true
				state["earnings"] = int(state["earnings"]) + LANDMARK_REWARD
				var n := 0
				for f in state["found"]:
					if f:
						n += 1
				Net.send_toast("%s found a landmark (%d/%d)  +$%d" % [who, n, landmarks.size(), LANDMARK_REWARD], COL_LANDMARK)
		"pickup":
			var from := int(data.get("depot", -1))
			if from >= 0 and from < depots.size() and not state["cargo"].has(peer):
				var to := from
				while to == from:
					to = _host_rng.randi() % depots.size()
				var dist: float = (depots[from]["pos"] as Vector3).distance_to(depots[to]["pos"])
				var reward := int(round((150.0 + dist * 0.9) / 10.0) * 10)
				state["cargo"][peer] = {"from": from, "to": to, "reward": reward}
				Net.send_toast("%s loaded cargo for %s ($%d)" % [who, depots[to]["name"], reward], COL_DEPOT)
		"deliver":
			if state["cargo"].has(peer):
				var job: Dictionary = state["cargo"][peer]
				if int(data.get("depot", -1)) == int(job["to"]):
					var cond := clampf(float(data.get("condition", 100.0)), 0.0, 100.0)
					var pay := int(round(job["reward"] * cond / 100.0))
					state["earnings"] = int(state["earnings"]) + pay
					state["deliveries"] = int(state["deliveries"]) + 1
					state["cargo"].erase(peer)
					Net.send_toast("%s delivered to %s: $%d (%d%% intact)" % [who, depots[job["to"]]["name"], pay, roundi(cond)], COL_DEST)
		"cargo_lost":
			if state["cargo"].has(peer):
				state["cargo"].erase(peer)
				Net.send_toast("%s lost their cargo" % who, Color(0.95, 0.45, 0.4))
	_broadcast()


func _check_route_complete() -> void:
	var r: int = state["route"]
	if r < 0:
		return
	for id in Net.players.keys():
		if not (id in state["finishers"]):
			return
	var t := _now() - _host_route_start
	state["last_result"] = {"route": r, "time": t, "id": randi() % 1000000, "players": Net.players.size()}
	state["route"] = -1
	state["finishers"] = []
	Net.send_toast("%s complete in %s" % [routes[r]["name"], Settings.format_time(t)], COL_ROUTE)


func _on_players_changed() -> void:
	if not Net.is_host():
		return
	for id in state["cargo"].keys():
		if not Net.players.has(id):
			state["cargo"].erase(id)
	var fin: Array = state["finishers"]
	for id in fin.duplicate():
		if not Net.players.has(id):
			fin.erase(id)
	if state["route"] >= 0 and not fin.is_empty():
		_check_route_complete()
	_broadcast()


func _broadcast() -> void:
	if state["route"] >= 0:
		state["elapsed"] = _now() - _host_route_start
	Net.broadcast_objectives(state)


# ---------------------------------------------------------------- every peer

func _on_state(s: Dictionary) -> void:
	state = s
	_received_at = _now()
	var lr: Dictionary = state.get("last_result", {})
	if not lr.is_empty() and int(lr.get("id", -1)) != _last_result_id:
		_last_result_id = int(lr["id"])
		if not OS.get_cmdline_user_args().has("--selftest") and Settings.submit_time(map_id, int(lr["route"]), float(lr["time"])):
			local_toast.emit("New best time on %s!" % routes[int(lr["route"])]["name"], COL_ROUTE)
	_refresh_markers()


func route_elapsed() -> float:
	if state.get("route", -1) < 0:
		return 0.0
	return float(state["elapsed"]) + (_now() - _received_at)


func my_job() -> Dictionary:
	return state.get("cargo", {}).get(Net.my_id(), {})


func _refresh_markers() -> void:
	var active: int = state.get("route", -1)
	for r in _route_starts.size():
		var n := _route_starts[r]
		n.visible = active == -1
		var best := Settings.best_time(map_id, r)
		(n.get_node("Best") as Label3D).text = "Best %s" % Settings.format_time(best) if best > 0 else "Stop here to start"
	# Next checkpoint gate.
	var cp: int = state.get("cp", 0)
	if active != _gate_route or cp != _gate_cp:
		_gate_route = active
		_gate_cp = cp
		if _gate:
			_gate.queue_free()
			_gate = null
		if active >= 0:
			var route: Dictionary = routes[active]
			var count: int = route["points"].size()
			var finish := cp >= count - 1
			_gate = Markers.checkpoint_gate(COL_FINISH if finish else COL_ROUTE, route["dirs"][mini(cp, count - 1)])
			_gate.position = route["points"][mini(cp, count - 1)]
			_gate.add_child(Markers.label("FINISH" if finish else "%d / %d" % [cp, count - 1], 8.5, COL_FINISH if finish else COL_ROUTE, 90))
			add_child(_gate)
	# Depots: highlight my destination.
	var job := my_job()
	for i in _depot_nodes.size():
		var col := COL_DEPOT
		if not job.is_empty() and int(job["to"]) == i:
			col = COL_DEST
		var beam: MeshInstance3D = _depot_nodes[i].get_node("Beam")
		(beam.material_override as StandardMaterial3D).albedo_color = Color(col, 0.32)
		beam.visible = job.is_empty() or int(job["to"]) == i
	for i in _landmark_nodes.size():
		var found: bool = state.get("found", [])[i] if i < state.get("found", []).size() else false
		var n2 := _landmark_nodes[i]
		n2.get_node("Beam").visible = not found
		var flag: MeshInstance3D = n2.get_node("Flag")
		flag.material_override = Markers.glow_material(COL_FOUND if found else COL_LANDMARK, 0.4)


func _physics_process(delta: float) -> void:
	var truck: TruckBody = world.local_truck if world else null
	if truck == null or state.is_empty():
		return
	_start_cooldown = maxf(_start_cooldown - delta, 0.0)
	var pos := truck.global_position
	var me := Net.my_id()
	var active: int = state["route"]
	if active == -1:
		var in_gate := -1
		for r in routes.size():
			if _near(pos, routes[r]["points"][0], CHECKPOINT_RADIUS):
				in_gate = r
				break
		if in_gate >= 0 and truck.linear_velocity.length() < 2.5 and _start_cooldown <= 0.0:
			_gate_timer += delta
			if _gate_timer >= 1.0:
				Net.report_event("route_start", {"route": in_gate})
				_start_cooldown = 3.0
				_gate_timer = 0.0
				_reported.clear()
		else:
			_gate_timer = 0.0
	else:
		var route: Dictionary = routes[active]
		var count: int = route["points"].size()
		var cp: int = state["cp"]
		var target: Vector3 = route["points"][mini(cp, count - 1)]
		if _near(pos, target, CHECKPOINT_RADIUS):
			var key := "%d:%d" % [active, cp]
			if not _reported.has(key):
				_reported[key] = true
				if cp >= count - 1:
					Net.report_event("finish", {"route": active})
				else:
					Net.report_event("checkpoint", {"route": active, "index": cp})
	var found: Array = state["found"]
	for i in landmarks.size():
		if i < found.size() and not found[i] and _near(pos, landmarks[i], LANDMARK_RADIUS):
			var key2 := "lm:%d" % i
			if not _reported.has(key2):
				_reported[key2] = true
				Net.report_event("found", {"index": i})
	# Cargo.
	var job := my_job()
	if not job.is_empty() and not truck.has_cargo:
		truck.load_cargo()
	elif job.is_empty() and truck.has_cargo:
		truck.unload_cargo()
	var slow := truck.linear_velocity.length() < 3.0
	var on_pad := -1
	for i in depots.size():
		if _near(pos, depots[i]["pos"], DEPOT_RADIUS):
			on_pad = i
			break
	if on_pad >= 0 and slow:
		_pad_timer += delta
	else:
		_pad_timer = 0.0
	if _pad_timer >= LOAD_TIME:
		if job.is_empty():
			var key3 := "pick:%d:%d" % [on_pad, state["deliveries"]]
			if not _reported.has(key3):
				_reported[key3] = true
				Net.report_event("pickup", {"depot": on_pad})
		elif int(job["to"]) == on_pad:
			var key4 := "drop:%d:%d" % [on_pad, state["deliveries"]]
			if not _reported.has(key4):
				_reported[key4] = true
				Net.report_event("deliver", {"depot": on_pad, "condition": truck.cargo_condition})
		_pad_timer = 0.0
	if active == -1 and _reported.size() > 200:
		_reported.clear()
	if me == 0:
		return


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r and absf(a.y - b.y) < r * 1.5


func on_local_cargo_lost() -> void:
	if not my_job().is_empty():
		Net.report_event("cargo_lost")


func pad_prompt() -> String:
	var truck: TruckBody = world.local_truck if world else null
	if truck == null:
		return ""
	if state.get("route", -1) == -1:
		for r in routes.size():
			if _near(truck.global_position, routes[r]["points"][0], CHECKPOINT_RADIUS):
				return "Stop in the gate to start %s" % routes[r]["name"]
	var job := my_job()
	for i in depots.size():
		if _near(truck.global_position, depots[i]["pos"], DEPOT_RADIUS):
			if job.is_empty():
				return "Stop on the pad to load cargo at %s" % depots[i]["name"]
			if int(job["to"]) == i:
				return "Stop on the pad to unload"
			return "This is %s. Your cargo goes to %s" % [depots[i]["name"], depots[int(job["to"])]["name"]]
	return ""


## Where the local truck should respawn.
func respawn_point(pos: Vector3) -> Dictionary:
	var active: int = state.get("route", -1)
	if active >= 0:
		var cp: int = state["cp"]
		var route: Dictionary = routes[active]
		var i := clampi(cp - 1, 0, route["points"].size() - 1)
		return {"pos": route["points"][i], "dir": route["dirs"][i]}
	var t := terrain.nearest_trail_point(pos)
	return {"pos": t["pos"], "dir": t["dir"]}


## Markers for the compass and map: {"pos", "color", "label", "kind"}
func markers() -> Array:
	var out := []
	var active: int = state.get("route", -1)
	if active >= 0:
		var route: Dictionary = routes[active]
		var count: int = route["points"].size()
		var cp: int = mini(state["cp"], count - 1)
		out.append({"pos": route["points"][cp], "color": COL_FINISH if cp == count - 1 else COL_ROUTE,
			"label": "Finish" if cp == count - 1 else "Checkpoint %d" % cp, "kind": "route"})
	else:
		for r in routes.size():
			out.append({"pos": routes[r]["points"][0], "color": COL_ROUTE, "label": routes[r]["name"], "kind": "route_start"})
	var job := my_job()
	for i in depots.size():
		if not job.is_empty() and int(job["to"]) == i:
			out.append({"pos": depots[i]["pos"], "color": COL_DEST, "label": depots[i]["name"], "kind": "dest"})
		elif job.is_empty():
			out.append({"pos": depots[i]["pos"], "color": COL_DEPOT, "label": depots[i]["name"], "kind": "depot"})
	var found: Array = state.get("found", [])
	for i in landmarks.size():
		if i < found.size() and not found[i]:
			out.append({"pos": landmarks[i], "color": COL_LANDMARK, "label": "Landmark", "kind": "landmark"})
	return out


func found_count() -> int:
	var n := 0
	for f in state.get("found", []):
		if f:
			n += 1
	return n


func abandon_route() -> void:
	Net.report_event("abandon")
