class_name TruckBody
extends VehicleBody3D
## The player's own truck. Simulated locally (responsive driving) and broadcast to friends.

signal cargo_lost
signal message(text: String)

const ENGINE_PER_WHEEL := 2400.0
const REVERSE_PER_WHEEL := 1100.0
const TOP_SPEED := 23.0          # m/s, about 51 mph
const REVERSE_SPEED := 9.0
const MAX_STEER := 0.56
const MIN_STEER := 0.17
const BRAKE := 38.0
const HANDBRAKE := 90.0
const BASE_SLIP := 3.2
const FLIP_HOLD := 0.6
const WINCH_MAX := 45.0
const WINCH_REEL_SPEED := 3.5
const SEND_RATE := 1.0 / 30.0

var peer_id := 1
var world: Node
var terrain: Terrain
var visual: TruckVisual
var wheels: Array[VehicleWheel3D] = []
var audio: EngineAudio

var input_enabled := true
var lights_on := false
var horn_on := false
var speed := 0.0
var flip_progress := 0.0
var surface_label := ""
var grounded_wheels := 0

var has_cargo := false
var cargo_condition := 100.0
var _upside_time := 0.0
var _last_vel := Vector3.ZERO
var _teleported := 0

# Winch: target_peer -1 = none, 0 = static anchor (world point), >0 = another player's truck.
var winch_peer := -1
var winch_anchor := Vector3.ZERO
var winch_length := 0.0
var _winch_tension := 0.0

var _ext_force := Vector3.ZERO
var _ext_point := Vector3.ZERO
var _ext_time := 0.0
var _send_timer := 0.0
var _braking := false
var _reversing := false

# Test hooks: when set, these replace player input.
var bot_throttle := -1.0
var bot_steer := 0.0
var bot_brake := 0.0


func setup(id: int, w: Node, t: Terrain, col: Color, pname: String) -> void:
	peer_id = id
	world = w
	terrain = t
	name = "Truck_%d" % id
	mass = 1600.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.12, 0.05)
	angular_damp = 0.4
	linear_damp = 0.02
	can_sleep = false
	continuous_cd = true
	add_to_group("truck")
	set_meta("peer_id", id)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	_add_box(Vector3(2.0, 0.55, 4.5), Vector3(0, 0.62, 0))
	_add_box(Vector3(1.8, 0.8, 1.6), Vector3(0, 1.3, -0.2))
	visual = TruckVisual.new()
	visual.name = "Visual"
	visual.build(col, pname, false)
	add_child(visual)
	var wheel_mesh := TruckVisual.make_wheel_mesh()
	for k in 4:
		var wh := VehicleWheel3D.new()
		wh.name = "Wheel%d" % k
		wh.position = TruckVisual.WHEEL_POSITIONS[k]
		wh.use_as_steering = k < 2
		wh.use_as_traction = true
		wh.wheel_radius = TruckVisual.WHEEL_RADIUS
		wh.wheel_rest_length = 0.45
		wh.suspension_travel = 0.42
		wh.suspension_stiffness = 36.0
		wh.suspension_max_force = 16000.0
		wh.damping_compression = 1.7
		wh.damping_relaxation = 2.3
		wh.wheel_friction_slip = BASE_SLIP
		wh.wheel_roll_influence = 0.22
		var mi := MeshInstance3D.new()
		mi.mesh = wheel_mesh
		wh.add_child(mi)
		add_child(wh)
		wheels.append(wh)
	audio = EngineAudio.new()
	audio.position = Vector3(0, 0.8, -1.5)
	add_child(audio)
	Net.winch_force_received.connect(_on_winch_force)


func _add_box(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	add_child(cs)


func _exit_tree() -> void:
	if Net.winch_force_received.is_connected(_on_winch_force):
		Net.winch_force_received.disconnect(_on_winch_force)
	if horn_on:
		Net.send_horn(false)


# ---------------------------------------------------------------- input (non-physics)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("lights"):
		lights_on = not lights_on
		visual.set_lights(lights_on)
	elif event.is_action_pressed("winch"):
		if winch_peer >= 0:
			release_winch("Winch released")
		else:
			_try_attach_winch()
	elif event.is_action_pressed("respawn"):
		respawn()
	if event.is_action("horn"):
		var on := Input.is_action_pressed("horn")
		if on != horn_on:
			horn_on = on
			audio.horn = on
			Net.send_horn(on)


# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	var steer_in := 0.0
	var throttle_in := 0.0
	var brake_in := 0.0
	var hand := false
	if bot_throttle >= 0.0:
		throttle_in = bot_throttle
		steer_in = bot_steer
		brake_in = bot_brake
	elif input_enabled:
		steer_in = Input.get_axis("steer_right", "steer_left")
		throttle_in = Input.get_action_strength("throttle")
		brake_in = Input.get_action_strength("brake")
		hand = Input.is_action_pressed("handbrake")

	# Steering: tighter at low speed, gentler at speed.
	var max_steer := lerpf(MAX_STEER, MIN_STEER, clampf(absf(speed) / TOP_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_in * max_steer, delta * 2.8)

	# Drive and brakes, per wheel.
	var engine := 0.0
	var brake_v := 0.0
	_reversing = false
	if throttle_in > 0.05:
		if speed < -1.0:
			brake_v = BRAKE * throttle_in
		else:
			var curve := 1.0 - pow(clampf(speed / TOP_SPEED, 0.0, 1.0), 2.0)
			engine = ENGINE_PER_WHEEL * throttle_in * maxf(curve, 0.0)
	elif brake_in > 0.05:
		if speed > 1.0:
			brake_v = BRAKE * brake_in
		else:
			_reversing = true
			if speed > -REVERSE_SPEED:
				engine = -REVERSE_PER_WHEEL * brake_in
	else:
		brake_v = 1.5 if absf(speed) > 0.6 else 6.0
	_braking = brake_v > 5.0 and absf(speed) > 0.6

	grounded_wheels = 0
	var drag := 0.0
	var grip_sum := 0.0
	for k in wheels.size():
		var wh := wheels[k]
		var p := wh.global_position
		var grip := terrain.grip_at(p.x, p.z)
		var rear := k >= 2
		var slip := BASE_SLIP * grip
		if hand and rear:
			slip *= 0.55
		wh.wheel_friction_slip = slip
		# VehicleBody3D drives toward +Z; our trucks face -Z, so the force is negated.
		wh.engine_force = -engine
		wh.brake = HANDBRAKE if (hand and rear) else brake_v
		if wh.is_in_contact():
			grounded_wheels += 1
			drag += terrain.drag_at(p.x, p.z)
			grip_sum += grip
	surface_label = terrain.surface_name(global_position.x, global_position.z)

	# Soft ground and water drag.
	var horiz := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if grounded_wheels > 0 and drag > 0.0:
		apply_central_force(-horiz * drag * mass * 0.06)
	if terrain.has_water() and global_position.y < terrain.water_level + 0.4:
		apply_central_force(-linear_velocity * mass * 0.5)

	# Stability assist: gently resist rolling over while on the ground.
	var up := global_basis.y
	if grounded_wheels >= 2:
		var n := terrain.normal_at(global_position.x, global_position.z)
		var axis := up.cross(n)
		var roll := axis.dot(fwd)
		apply_torque(fwd * roll * 2600.0 - fwd * angular_velocity.dot(fwd) * 300.0)
	elif grounded_wheels == 0:
		# Airborne: gently level out (forgiving landings) plus a little air control.
		var level := up.cross(Vector3.UP)
		apply_torque(level * 5200.0 - angular_velocity * 650.0)
		var right := global_basis.x
		var pitch_in := throttle_in - brake_in
		apply_torque((-right * pitch_in * 1600.0) + (fwd * -steer_in * 1300.0))

	_update_flip(delta)
	_update_winch(delta)
	if _ext_time > 0.0:
		apply_force(_ext_force, _ext_point - global_position)
		_ext_time -= delta
	_update_cargo(delta)

	visual.set_braking(_braking)
	audio.rpm = clampf(absf(speed) / TOP_SPEED, 0.0, 1.0) * 0.75 + throttle_in * 0.25
	audio.throttle = maxf(throttle_in, brake_in if _reversing else 0.0)

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_RATE
		Net.send_truck_state(pack_state())


func _update_flip(delta: float) -> void:
	var upside := global_basis.y.y < 0.3
	_upside_time = _upside_time + delta if upside else 0.0
	if input_enabled and Input.is_action_pressed("flip"):
		flip_progress += delta / FLIP_HOLD
		if flip_progress >= 1.0:
			flip_progress = 0.0
			flip_upright()
	else:
		flip_progress = 0.0


func flip_upright() -> void:
	var f := -global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = global_basis.y
		f.y = 0.0
	if f.length() < 0.1:
		f = Vector3.FORWARD
	var pos := global_position
	pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z)) + 1.6
	_teleport(pos, f.normalized())


func respawn() -> void:
	var rp: Dictionary = world.objectives.respawn_point(global_position)
	var pos: Vector3 = rp["pos"]
	_teleport(Vector3(pos.x, terrain.height_at(pos.x, pos.z) + 1.4, pos.z), rp["dir"])
	message.emit("Respawned")


func place_at(pos: Vector3, dir: Vector3) -> void:
	_teleport(pos, dir)


func _teleport(pos: Vector3, dir: Vector3) -> void:
	var b := Basis.looking_at(dir, Vector3.UP)
	global_transform = Transform3D(b, pos)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering = 0.0
	_teleported = 3
	if winch_peer >= 0:
		release_winch("")


# ---------------------------------------------------------------- cargo

func load_cargo() -> void:
	has_cargo = true
	cargo_condition = 100.0
	visual.set_cargo(true)


func unload_cargo() -> void:
	has_cargo = false
	visual.set_cargo(false)


func _update_cargo(delta: float) -> void:
	var dv := (linear_velocity - _last_vel).length()
	_last_vel = linear_velocity
	if _teleported > 0:
		_teleported -= 1
		return
	if not has_cargo:
		return
	if dv > 4.0:
		cargo_condition = maxf(cargo_condition - (dv - 4.0) * 7.0, 0.0)
		message.emit("Cargo %d%%" % roundi(cargo_condition))
	if _upside_time > 2.0 or cargo_condition <= 0.0:
		has_cargo = false
		visual.set_cargo(false)
		cargo_lost.emit()
	if delta < 0.0:
		pass


# ---------------------------------------------------------------- winch

func winch_point() -> Vector3:
	return to_global(TruckVisual.WINCH_POINT)


func winch_world_anchor() -> Vector3:
	if winch_peer > 0:
		var other: Node3D = world.trucks.get(winch_peer)
		if other:
			return other.to_global(winch_anchor)
	return winch_anchor


func _try_attach_winch() -> void:
	var hit: Dictionary = world.find_winch_anchor(self)
	if hit.is_empty():
		message.emit("No tree, rock or truck in winch range")
		return
	winch_peer = int(hit["peer"])
	winch_anchor = hit["anchor"]
	winch_length = winch_point().distance_to(hit["point"]) + 0.3
	message.emit("Winch attached. Hold %s to reel in" % Settings.key_label("winch_in"))


func release_winch(msg: String) -> void:
	winch_peer = -1
	_winch_tension = 0.0
	if msg != "":
		message.emit(msg)


func _update_winch(delta: float) -> void:
	if winch_peer < 0:
		visual.update_cable(Vector3.ZERO, Vector3.ZERO, false)
		return
	if winch_peer > 0 and not world.trucks.has(winch_peer):
		release_winch("Winch released")
		return
	var wp := winch_point()
	var anchor := winch_world_anchor()
	if input_enabled:
		if Input.is_action_pressed("winch_in"):
			winch_length = maxf(winch_length - WINCH_REEL_SPEED * delta, 2.0)
		elif Input.is_action_pressed("winch_out"):
			winch_length = minf(winch_length + WINCH_REEL_SPEED * 1.3 * delta, WINCH_MAX)
	var d := wp.distance_to(anchor)
	_winch_tension = 0.0
	if d > winch_length and d > 0.01:
		var dir := (anchor - wp) / d
		var stretch := d - winch_length
		var closing := linear_velocity.dot(dir)
		var f := clampf(stretch * 9000.0 - closing * 2600.0, 0.0, 32000.0)
		_winch_tension = f
		apply_force(dir * f, wp - global_position)
		if winch_peer > 0:
			Net.send_winch_force(winch_peer, -dir * f * 0.85, anchor)
		if stretch > 12.0:
			release_winch("Winch cable snapped")
			return
	visual.update_cable(wp, anchor, true)


func winch_status() -> String:
	if winch_peer < 0:
		return ""
	var d := winch_point().distance_to(winch_world_anchor())
	var target := "anchor"
	if winch_peer > 0:
		target = Net.player_name(winch_peer)
	var strain := " (pulling)" if _winch_tension > 500.0 else ""
	return "Winch: %s, %.0f m%s" % [target, d, strain]


func _on_winch_force(force: Vector3, point: Vector3) -> void:
	_ext_force = force
	_ext_point = point
	_ext_time = 0.15


# ---------------------------------------------------------------- network

func pack_state() -> Array:
	var offsets := PackedFloat32Array()
	var spin := 0.0
	for k in wheels.size():
		offsets.append(wheels[k].position.y - TruckVisual.WHEEL_POSITIONS[k].y)
		spin += wheels[k].get_rpm()
	spin = -spin / 4.0 * TAU / 60.0
	var flags := 0
	if lights_on:
		flags |= 1
	if _braking:
		flags |= 2
	if has_cargo:
		flags |= 4
	return [
		global_position, global_basis.get_rotation_quaternion(), linear_velocity,
		steering, spin, offsets, flags, winch_peer, winch_anchor,
	]
