class_name TruckRemote
extends AnimatableBody3D
## A friend's truck. Follows the owner's snapshots with interpolation; solid so you can bump
## into it, push it around with your own winch, or winch onto it.

const INTERP_DELAY := 0.1
const MAX_EXTRAPOLATE := 0.3

var peer_id := 0
var world: Node
var visual: TruckVisual
var audio: EngineAudio
var wheel_pivots: Array[Node3D] = []
var _spin_nodes: Array[Node3D] = []

var _buffer: Array = []  # [time, state]
var _spin_angle := 0.0
var _last := []
var winch_peer := -1
var winch_anchor := Vector3.ZERO
var speed := 0.0


func setup(id: int, w: Node, col: Color, pname: String) -> void:
	peer_id = id
	world = w
	name = "Truck_%d" % id
	sync_to_physics = false
	add_to_group("truck")
	add_to_group("winch_anchor")
	set_meta("peer_id", id)
	for spec in [[Vector3(2.0, 0.55, 4.5), Vector3(0, 0.62, 0)], [Vector3(1.8, 0.8, 1.6), Vector3(0, 1.3, -0.2)]]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		cs.shape = b
		cs.position = spec[1]
		add_child(cs)
	visual = TruckVisual.new()
	visual.build(col, pname, true)
	add_child(visual)
	var wheel_mesh := TruckVisual.make_wheel_mesh()
	for k in 4:
		var pivot := Node3D.new()
		pivot.position = TruckVisual.WHEEL_POSITIONS[k] + Vector3(0, -0.4, 0)
		var spin := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = wheel_mesh
		spin.add_child(mi)
		pivot.add_child(spin)
		add_child(pivot)
		wheel_pivots.append(pivot)
		_spin_nodes.append(spin)
	audio = EngineAudio.new()
	audio.position = Vector3(0, 0.8, -1.5)
	audio.volume = 0.7
	add_child(audio)


func push_state(state: Array) -> void:
	if state.size() < 9:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _buffer.is_empty():
		global_transform = Transform3D(Basis(state[1] as Quaternion), state[0])
	_buffer.append([now, state])
	while _buffer.size() > 20:
		_buffer.pop_front()
	_last = state
	var flags: int = state[6]
	visual.set_lights(flags & 1 != 0)
	visual.set_braking(flags & 2 != 0)
	visual.set_cargo(flags & 4 != 0)
	winch_peer = int(state[7])
	winch_anchor = state[8]


func set_horn(on: bool) -> void:
	audio.horn = on


func _physics_process(delta: float) -> void:
	if _buffer.is_empty():
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var a: Array = _buffer[0]
	var b: Array = _buffer[0]
	for i in range(_buffer.size() - 1, -1, -1):
		if _buffer[i][0] <= render_t:
			a = _buffer[i]
			b = _buffer[mini(i + 1, _buffer.size() - 1)]
			break
	var sa: Array = a[1]
	var sb: Array = b[1]
	var pos: Vector3
	var rot: Quaternion
	if a == b:
		# Ahead of our data: extrapolate a little using velocity.
		var dt := clampf(render_t - float(a[0]), 0.0, MAX_EXTRAPOLATE)
		pos = (sa[0] as Vector3) + (sa[2] as Vector3) * dt
		rot = sa[1]
	else:
		var span := maxf(float(b[0]) - float(a[0]), 0.001)
		var t := clampf((render_t - float(a[0])) / span, 0.0, 1.0)
		pos = (sa[0] as Vector3).lerp(sb[0], t)
		rot = (sa[1] as Quaternion).slerp(sb[1], t)
	global_transform = Transform3D(Basis(rot), pos)
	# Wheels.
	var steer: float = sb[3]
	var spin: float = sb[4]
	var offsets: PackedFloat32Array = sb[5]
	_spin_angle = fmod(_spin_angle + spin * delta, TAU)
	for k in 4:
		var pv := wheel_pivots[k]
		var off := offsets[k] if k < offsets.size() else -0.4
		pv.position = TruckVisual.WHEEL_POSITIONS[k] + Vector3(0, off, 0)
		pv.rotation.y = steer if k < 2 else 0.0
		_spin_nodes[k].rotation.x = _spin_angle
	var vel: Vector3 = sb[2]
	speed = vel.dot(-global_basis.z)
	audio.rpm = clampf(absf(speed) / 25.0, 0.0, 1.0) * 0.8 + 0.1
	audio.throttle = clampf(absf(speed) / 25.0, 0.0, 1.0) * 0.6
	# Cable.
	if winch_peer >= 0:
		var to := winch_anchor
		if winch_peer > 0:
			var other: Node3D = world.trucks.get(winch_peer)
			if other == null:
				visual.update_cable(Vector3.ZERO, Vector3.ZERO, false)
				return
			to = other.to_global(winch_anchor)
		visual.update_cable(to_global(TruckVisual.WINCH_POINT), to, true)
	else:
		visual.update_cable(Vector3.ZERO, Vector3.ZERO, false)


func is_stale() -> bool:
	return _buffer.is_empty() or Time.get_ticks_msec() / 1000.0 - float(_buffer[-1][0]) > 5.0
