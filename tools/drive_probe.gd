extends Node
## Drives every trail of the current map with a simple bot and reports rollovers.
func _ready():
	await get_tree().create_timer(2.5).timeout
	var main = get_tree().root.get_node("Main")
	var t = main.world.local_truck
	var ter = main.world.terrain
	var report = []
	for ti in ter.trails.size():
		var line = ter.trails[ti]
		var d0 = line[3] - line[1]; d0.y = 0
		t.place_at(line[1] + Vector3(0, 1.4, 0), d0.normalized())
		await get_tree().create_timer(0.5).timeout
		var idx := 2
		var rolls := 0
		var steps := 0
		var vmax := 0.0
		while steps < 60 * 60 and idx < line.size() - 2:
			steps += 1
			await get_tree().physics_frame
			idx = TestBot.drive(t, line, idx)
			vmax = maxf(vmax, t.speed)
			if t.global_basis.y.y < 0.3:
				rolls += 1
				print("  trail %d rolled near idx %d at %s" % [ti, idx, t.global_position])
				t.flip_upright()
				await get_tree().create_timer(0.5).timeout
		report.append("trail %d: %d/%d pts, %d rolls, max %d mph, %.0fs" % [ti, idx, line.size(), rolls, roundi(vmax * 2.237), steps / 60.0])
	for r in report:
		print(r)
	get_tree().quit()
