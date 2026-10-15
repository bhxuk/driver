extends Node
## Reports any trail section steeper than 35% on the current map.
func _ready():
	await get_tree().create_timer(2.0).timeout
	var main = get_tree().root.get_node("Main")
	var ter = main.world.terrain
	for ti in ter.trails.size():
		var line = ter.trails[ti]
		var bad = []
		for i in range(line.size() - 1):
			var a = line[i]; var b = line[i + 1]
			var prev = ter.height_at(a.x, a.z)
			for k in range(1, 9):
				var q = a.lerp(b, k / 8.0)
				var h = ter.height_at(q.x, q.z)
				var gr = (h - prev) / 1.0
				prev = h
				if absf(gr) > 0.35:
					var near = []
					for tj in ter.trails.size():
						if tj == ti: continue
						for p2 in ter.trails[tj]:
							if Vector2(p2.x - q.x, p2.z - q.z).length() < 20:
								near.append(tj); break
					bad.append("idx%d grade=%.2f dist_hub=%.0f near=%s" % [i, gr, Vector2(q.x - ter.hub.x, q.z - ter.hub.z).length(), near])
					break
		print("trail %d (%d pts): %d steep spots %s" % [ti, line.size(), bad.size(), bad.slice(0, 6)])
	get_tree().quit()
