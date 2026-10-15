class_name ChaseCamera
extends Camera3D
## Third-person chase camera with mouse / right-stick orbit, plus a hood camera.

var target: Node3D
var terrain: Terrain
var mode := 0  # 0 chase, 1 hood
var yaw_offset := 0.0
var pitch := 0.32
var distance := 8.8
var _yaw := 0.0
var _idle := 0.0
var _initialised := false


func _ready() -> void:
	near = 0.1
	far = 1800.0
	current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		yaw_offset -= m.relative.x * 0.0035 * Settings.mouse_sensitivity
		var dy := m.relative.y * 0.0028 * Settings.mouse_sensitivity
		pitch += -dy if Settings.invert_y else dy
		_idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance - 0.6, 5.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + 0.6, 16.0)
	elif event.is_action_pressed("camera_toggle"):
		mode = 1 - mode
		yaw_offset = 0.0


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if stick.length() > 0.05:
		yaw_offset -= stick.x * delta * 2.6 * Settings.stick_sensitivity
		pitch += (stick.y if not Settings.invert_y else -stick.y) * delta * 1.6 * Settings.stick_sensitivity
		_idle = 0.0
	else:
		_idle += delta
	pitch = clampf(pitch, -0.2, 1.25)
	var spd := 0.0
	if "speed" in target:
		spd = absf(float(target.get("speed")))
	if Settings.auto_center_camera and _idle > 1.6 and spd > 3.0:
		yaw_offset = lerp_angle(yaw_offset, 0.0, delta * 1.8)
		pitch = lerpf(pitch, 0.32, delta * 1.2)
	var basis_t := target.global_basis
	var fwd := -basis_t.z
	var heading := atan2(-fwd.x, -fwd.z)
	if not _initialised:
		_yaw = heading
		_initialised = true
	_yaw = lerp_angle(_yaw, heading, clampf(delta * 3.5, 0.0, 1.0))
	fov = lerpf(fov, Settings.fov + clampf(spd * 0.35, 0.0, 10.0), delta * 2.0)
	if mode == 1:
		var p := target.to_global(Vector3(0, 1.85, -0.75))
		var hb := Basis(Vector3.UP, yaw_offset) * Basis.IDENTITY
		var look_basis := basis_t * hb
		global_transform = Transform3D(look_basis.rotated(look_basis.x, -0.05), p)
		return
	var y := _yaw + yaw_offset
	var offset := Vector3(sin(y) * cos(pitch), sin(pitch), cos(y) * cos(pitch)) * distance
	var focus := target.global_position + Vector3(0, 1.4, 0)
	var desired := focus + offset
	if terrain:
		desired.y = maxf(desired.y, terrain.height_at(desired.x, desired.z) + 1.0)
		if terrain.has_water():
			desired.y = maxf(desired.y, terrain.water_level + 0.5)
	global_position = global_position.lerp(desired, clampf(delta * 10.0, 0.0, 1.0)) if global_position.distance_to(desired) < 30.0 else desired
	look_at(focus, Vector3.UP)
