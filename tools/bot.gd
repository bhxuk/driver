class_name TestBot
extends RefCounted
## Simple trail-following driver for automated tests: steers to a look-ahead point and
## slows for bends like a person would.
static func drive(t, line: PackedVector3Array, idx: int) -> int:
	while idx < line.size() - 1 and Vector2(line[idx].x - t.global_position.x, line[idx].z - t.global_position.z).length() < 12.0:
		idx += 1
	var local = t.global_basis.inverse() * (line[idx] - t.global_position)
	t.bot_steer = clampf(-local.x / maxf(-local.z, 2.0) * 2.0, -1.0, 1.0)
	var bend := 0.0
	for k in range(idx, mini(idx + 4, line.size() - 2)):
		var a: Vector3 = line[k] - line[k - 1]
		var b: Vector3 = line[k + 1] - line[k]
		a.y = 0; b.y = 0
		bend = maxf(bend, a.angle_to(b))
	var target := lerpf(21.0, 7.0, clampf(bend / 0.6, 0.0, 1.0))
	if t.speed > target + 2.0:
		t.bot_throttle = 0.0
		t.bot_brake = 0.6
	else:
		t.bot_throttle = 0.85 if t.speed < target else 0.3
		t.bot_brake = 0.0
	return idx
