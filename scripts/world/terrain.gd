class_name Terrain
extends Node3D
## Deterministic heightmap terrain with carved trails, surface types and collision.

const RES := 257
const SPACING := 4.0
const SIZE := (RES - 1) * SPACING
const HALF := SIZE * 0.5
const CHUNK := 32
const ROAD_CORE := 6.0
const ROAD_OUTER := 14.0
const ROAD_PAINT := 4.6
const TRAIL_STEP := 8.0

enum Surf { BASE, ROAD, SPECIAL, ROCK, WATER }

var def: Dictionary
var heights := PackedFloat32Array()
var surf := PackedByteArray()
var road_w := PackedFloat32Array()
var trails: Array[PackedVector3Array] = []
var hub := Vector3.ZERO
var water_level := -1000.0

var _rng := RandomNumberGenerator.new()
var _n_base := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_special := FastNoiseLite.new()
var _n_tint := FastNoiseLite.new()
var _carve_h := PackedFloat32Array()
var _carve_w := PackedFloat32Array()
var _road_before := PackedFloat32Array()


func generate(d: Dictionary) -> void:
	def = d
	var s: int = d["seed"]
	_rng.seed = s
	_setup_noise(s)
	water_level = float(d["water_level"])
	var n := RES * RES
	heights.resize(n)
	surf.resize(n)
	road_w.resize(n)
	_carve_h.resize(n)
	road_w.fill(0.0)
	for j in RES:
		for i in RES:
			var p := grid_to_world(i, j)
			heights[j * RES + i] = _base_height(p.x, p.y)
	var hub2: Vector2 = d["hub"]
	_flatten_circle(hub2, 36.0)
	_make_trails(hub2)
	_classify()
	hub = Vector3(hub2.x, height_at(hub2.x, hub2.y), hub2.y)
	_build_mesh()
	_build_collision()
	_build_walls()
	if has_water():
		_build_water()


func has_water() -> bool:
	return water_level > -999.0


# ---------------------------------------------------------------- noise and shape

func _setup_noise(s: int) -> void:
	_n_base.seed = s
	_n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.0028
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 4
	_n_detail.seed = s + 11
	_n_detail.frequency = 0.022
	_n_detail.fractal_octaves = 2
	_n_ridge.seed = s + 23
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.frequency = 0.0032
	_n_ridge.fractal_octaves = 3
	_n_special.seed = s + 37
	_n_special.frequency = 0.012
	_n_special.fractal_octaves = 2
	_n_tint.seed = s + 51
	_n_tint.frequency = 0.03
	_n_tint.fractal_octaves = 2


func _base_height(x: float, z: float) -> float:
	var h := 0.0
	match str(def["kind"]):
		"canyon":
			var v := _n_ridge.get_noise_2d(x, z)
			var canyon := 1.0 - smoothstep(0.02, 0.34, absf(v))
			canyon = canyon * canyon * (3.0 - 2.0 * canyon)
			var plateau := 26.0 + _n_base.get_noise_2d(x, z) * 12.0
			plateau = lerpf(plateau, _terrace(plateau, 7.0), 0.7)
			var dunes := (sin(x * 0.04 + z * 0.012 + _n_detail.get_noise_2d(x, z) * 3.0) * 0.5 + 0.5) * 2.0
			h = lerpf(plateau + dunes * 0.4, 6.0 + dunes, canyon)
		"mountain":
			var c := Vector2(x - 40.0, z + 20.0).length()
			var peak := 150.0 * exp(-pow(c / 290.0, 2.0))
			var ridge := (1.0 - absf(_n_ridge.get_noise_2d(x, z))) * 22.0 * (peak / 150.0)
			h = 8.0 + peak + _n_base.get_noise_2d(x, z) * 20.0 + ridge + _n_detail.get_noise_2d(x, z) * 1.6
		_:
			h = 6.0 + (_n_base.get_noise_2d(x, z) * 0.5 + 0.5) * 42.0 + _n_detail.get_noise_2d(x, z) * 1.8
			if has_water():
				var rx := sin(z * 0.0055 + 0.7) * 170.0 + sin(z * 0.013) * 38.0 + 90.0
				var dist := absf(x - rx)
				var bank := 1.0 - smoothstep(9.0, 58.0, dist)
				h = lerpf(h, water_level - 2.4, bank)
	# Raised rim so the edge of the map feels natural.
	var edge := minf(HALF - absf(x), HALF - absf(z))
	var rim := 1.0 - smoothstep(16.0, 95.0, edge)
	h += rim * rim * 60.0
	return h


func _terrace(h: float, step: float) -> float:
	var t := h / step
	var f := floorf(t)
	var frac := t - f
	return (f + smoothstep(0.15, 0.85, frac)) * step


func _flatten_circle(center: Vector2, radius: float) -> void:
	var acc := [0.0, 0]
	_for_cells_in_radius(center, radius, func(idx: int, _d: float):
		acc[0] += heights[idx]
		acc[1] += 1)
	if acc[1] == 0:
		return
	var target: float = acc[0] / float(acc[1])
	if has_water():
		target = maxf(target, water_level + 1.5)
	_for_cells_in_radius(center, radius + ROAD_OUTER * 2.0, func(idx: int, d: float):
		var w := 1.0 - smoothstep(radius, radius + ROAD_OUTER * 2.0, d)
		heights[idx] = lerpf(heights[idx], target, w)
		if d < radius:
			road_w[idx] = 1.0)


func _for_cells_in_radius(center: Vector2, radius: float, fn: Callable) -> void:
	var ci := int(round((center.x + HALF) / SPACING))
	var cj := int(round((center.y + HALF) / SPACING))
	var r := int(ceil(radius / SPACING)) + 1
	for j in range(maxi(cj - r, 0), mini(cj + r, RES - 1) + 1):
		for i in range(maxi(ci - r, 0), mini(ci + r, RES - 1) + 1):
			var p := grid_to_world(i, j)
			var d := p.distance_to(center)
			if d <= radius:
				fn.call(j * RES + i, d)


# ---------------------------------------------------------------- trails

func _make_trails(start: Vector2) -> void:
	var count := 5
	var base_heading := _rng.randf() * TAU
	var raw: Array[PackedVector2Array] = []
	for t in count:
		var heading := base_heading + TAU * t / count + _rng.randf_range(-0.3, 0.3)
		raw.append(_walk_trail(start, heading, _rng.randi_range(95, 140), raw))
	_carve_w.resize(RES * RES)
	# Carve one trail at a time so later trails follow roads already cut (no ridges where they meet).
	for pts in raw:
		_carve_w.fill(0.0)
		_road_before = road_w.duplicate()
		var ph := _trail_heights(pts)
		_carve(pts, ph)
		for idx in heights.size():
			if _carve_w[idx] > 0.0:
				# Leave roads that were already cut alone so junctions stay flush.
				var keep := smoothstep(0.3, 0.9, _road_before[idx])
				heights[idx] = lerpf(heights[idx], _carve_h[idx], _carve_w[idx] * (1.0 - keep))
	_smooth_roads(10)
	trails.clear()
	for pts in raw:
		var line := PackedVector3Array()
		for p in pts:
			line.append(Vector3(p.x, height_at(p.x, p.y), p.y))
		trails.append(line)


func _walk_trail(start: Vector2, heading: float, steps: int, others: Array) -> PackedVector2Array:
	var pts := PackedVector2Array([start])
	var pos := start
	var hd := heading
	for s in steps:
		hd += _rng.randf_range(-0.06, 0.06)
		var best_score := INF
		var best_hd := hd
		for k in 9:
			var cand := hd + (k - 4) * 0.1
			var np := pos + Vector2(cos(cand), sin(cand)) * TRAIL_STEP
			var score := absf(_height_raw(np) - _height_raw(pos)) / TRAIL_STEP * 5.0
			score += absf(cand - hd) * 0.5
			var edge := minf(HALF - absf(np.x), HALF - absf(np.y))
			if edge < 120.0:
				score += (120.0 - edge) * 0.06
			if has_water() and _height_raw(np) < water_level + 0.3:
				score += 0.6
			# Do not curl back onto ourselves or hug another trail.
			if s > 6:
				for q in range(0, pts.size() - 10, 3):
					if pts[q].distance_squared_to(np) < 900.0:
						score += 3.0
						break
				# Keep away from other trails once clear of base camp, so junctions are rare.
			if np.distance_to(start) > 70.0:
				for other in others:
					var o: PackedVector2Array = other
					for q in range(4, o.size(), 2):
						var dd := o[q].distance_squared_to(np)
						if dd < 1225.0:
							score += 6.0
							break
						elif dd < 3600.0:
							score += 0.6
							break
			score += _rng.randf() * 0.2
			if score < best_score:
				best_score = score
				best_hd = cand
		hd = best_hd
		pos += Vector2(cos(hd), sin(hd)) * TRAIL_STEP
		# Reaching another trail: finish with a clean T-junction onto it.
		if pos.distance_to(start) > 180.0:
			var join := _nearest_on(others, pos, 22.0)
			if join.x < INF and join.distance_to(start) > 150.0:
				pts.append(join)
				break
		pts.append(pos)
		if minf(HALF - absf(pos.x), HALF - absf(pos.y)) < 80.0:
			break
	return pts


## Relaxes the heightfield on trail surfaces only, ironing out steps where trails meet.
func _smooth_roads(iterations: int) -> void:
	var idxs := PackedInt32Array()
	for j in range(1, RES - 1):
		for i in range(1, RES - 1):
			if road_w[j * RES + i] > 0.05:
				idxs.append(j * RES + i)
	for it in iterations:
		var src := heights.duplicate()
		for idx in idxs:
			var avg := (src[idx - 1] + src[idx + 1] + src[idx - RES] + src[idx + RES]) * 0.25
			heights[idx] = lerpf(src[idx], avg, 0.6 * road_w[idx])


func _nearest_on(others: Array, p: Vector2, radius: float) -> Vector2:
	var best := Vector2(INF, INF)
	var bd := radius * radius
	for other in others:
		var o: PackedVector2Array = other
		for q in o:
			var d := q.distance_squared_to(p)
			if d < bd:
				bd = d
				best = q
	return best


## A spot at `radius` from base camp, as far as possible from every trail and from `avoid`.
func find_hub_spot(radius: float, avoid: Array = []) -> Vector3:
	var best := hub
	var best_clear := -INF
	for k in 36:
		var a := TAU * k / 36.0
		var c := Vector2(hub.x + cos(a) * radius, hub.z + sin(a) * radius)
		var clear := INF
		for line in trails:
			for p in line:
				clear = minf(clear, Vector2(p.x, p.z).distance_to(c))
		for v in avoid:
			clear = minf(clear, Vector2((v as Vector3).x, (v as Vector3).z).distance_to(c) - 6.0)
		if clear > best_clear:
			best_clear = clear
			best = ground_point(c.x, c.y)
	return best


func _trail_heights(pts: PackedVector2Array) -> PackedFloat32Array:
	var ph := PackedFloat32Array()
	var pinned := PackedByteArray()
	for p in pts:
		ph.append(_height_raw(p))
		# Points on an existing road (or base camp) keep that road's height exactly.
		pinned.append(1 if _road_before_at(p) > 0.6 else 0)
	for pass_i in 10:
		var copy := ph.duplicate()
		for i in range(1, ph.size() - 1):
			if pinned[i]:
				continue
			var a := maxi(i - 2, 0)
			var b := mini(i + 2, ph.size() - 1)
			var sum := 0.0
			for k in range(a, b + 1):
				sum += copy[k]
			ph[i] = sum / (b - a + 1)
	var g := TRAIL_STEP * 0.2
	# Alternate passes until the grade limit holds both ways (the start is pinned to camp).
	for it in 4:
		for i in range(ph.size() - 2, -1, -1):
			if not pinned[i]:
				ph[i] = clampf(ph[i], ph[i + 1] - g, ph[i + 1] + g)
		for i in range(1, ph.size()):
			if not pinned[i]:
				ph[i] = clampf(ph[i], ph[i - 1] - g, ph[i - 1] + g)
	# Round off crests and dips left by the grade clamp so trails do not launch trucks.
	for pass_j in 6:
		var c2 := ph.duplicate()
		for i in range(1, ph.size() - 1):
			if not pinned[i]:
				ph[i] = (c2[i - 1] + c2[i] * 2.0 + c2[i + 1]) * 0.25
	if has_water():
		for i in ph.size():
			ph[i] = maxf(ph[i], water_level - 0.6)
	return ph


func _road_before_at(p: Vector2) -> float:
	var i := clampi(int(round((p.x + HALF) / SPACING)), 0, RES - 1)
	var j := clampi(int(round((p.y + HALF) / SPACING)), 0, RES - 1)
	return _road_before[j * RES + i]


func _carve(pts: PackedVector2Array, ph: PackedFloat32Array) -> void:
	# Densify to 2 m so the road surface has no gaps between samples.
	for i in range(pts.size() - 1):
		var sub := 4
		for k in sub:
			var t := float(k) / sub
			var p := pts[i].lerp(pts[i + 1], t)
			var h := lerpf(ph[i], ph[i + 1], t)
			_for_cells_in_radius(p, ROAD_OUTER, func(idx: int, d: float):
				var w := 1.0 - smoothstep(ROAD_CORE, ROAD_OUTER, d)
				if w > _carve_w[idx]:
					_carve_w[idx] = w
					_carve_h[idx] = h
				var rw := 1.0 - smoothstep(ROAD_PAINT - 1.0, ROAD_PAINT + 2.5, d)
				if rw > road_w[idx]:
					road_w[idx] = rw)


func _height_raw(p: Vector2) -> float:
	return height_at(p.x, p.y)


# ---------------------------------------------------------------- surfaces

func _classify() -> void:
	var kind := str(def["kind"])
	for j in RES:
		for i in RES:
			var idx := j * RES + i
			var p := grid_to_world(i, j)
			var h := heights[idx]
			var slope := _grid_slope(i, j)
			var n := _n_special.get_noise_2d(p.x, p.y)
			var s := Surf.BASE
			if road_w[idx] > 0.55:
				s = Surf.ROAD
				if kind == "hills" and n > 0.42:
					s = Surf.SPECIAL
				elif kind == "mountain" and n > 0.5:
					s = Surf.SPECIAL
			elif has_water() and h < water_level - 0.15:
				s = Surf.WATER
			elif slope > 0.8:
				s = Surf.ROCK
			elif slope < 0.4:
				match kind:
					"hills":
						if n > 0.26 or (has_water() and h < water_level + 1.0):
							s = Surf.SPECIAL
					"mountain":
						if n > 0.3 and h < 70.0:
							s = Surf.SPECIAL
					"canyon":
						if n > 0.12 and h < 18.0:
							s = Surf.SPECIAL
			surf[idx] = s


func _grid_slope(i: int, j: int) -> float:
	var hl := heights[j * RES + maxi(i - 1, 0)]
	var hr := heights[j * RES + mini(i + 1, RES - 1)]
	var hd := heights[maxi(j - 1, 0) * RES + i]
	var hu := heights[mini(j + 1, RES - 1) * RES + i]
	return Vector2(hr - hl, hu - hd).length() / (2.0 * SPACING)


func grip_at(x: float, z: float) -> float:
	return float(def["grip"][_surf_key(surface_at(x, z))])


func drag_at(x: float, z: float) -> float:
	return float(def["drag"][_surf_key(surface_at(x, z))])


func surface_name(x: float, z: float) -> String:
	match surface_at(x, z):
		Surf.ROAD: return "Trail"
		Surf.SPECIAL: return str(def["special_surface_name"])
		Surf.ROCK: return "Rock"
		Surf.WATER: return "Water"
	return str(def["base_surface_name"])


func _surf_key(s: int) -> String:
	match s:
		Surf.ROAD: return "road"
		Surf.SPECIAL: return "special"
		Surf.ROCK: return "rock"
		Surf.WATER: return "water"
	return "base"


# ---------------------------------------------------------------- queries

func grid_to_world(i: int, j: int) -> Vector2:
	return Vector2(i * SPACING - HALF, j * SPACING - HALF)


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / SPACING, 0.0, RES - 1.001)
	var fz := clampf((z + HALF) / SPACING, 0.0, RES - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * RES + i]
	var h10 := heights[j * RES + i + 1]
	var h01 := heights[(j + 1) * RES + i]
	var h11 := heights[(j + 1) * RES + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func surface_at(x: float, z: float) -> int:
	var i := clampi(int(round((x + HALF) / SPACING)), 0, RES - 1)
	var j := clampi(int(round((z + HALF) / SPACING)), 0, RES - 1)
	return surf[j * RES + i]


func road_weight_at(x: float, z: float) -> float:
	var i := clampi(int(round((x + HALF) / SPACING)), 0, RES - 1)
	var j := clampi(int(round((z + HALF) / SPACING)), 0, RES - 1)
	return road_w[j * RES + i]


func normal_at(x: float, z: float) -> Vector3:
	var e := SPACING
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func slope_at(x: float, z: float) -> float:
	var n := normal_at(x, z)
	return sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(n.y, 0.01)


func is_inside(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) < HALF - margin and absf(z) < HALF - margin


func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Returns {"pos": Vector3, "dir": Vector3, "trail": int, "index": int} of the closest trail point.
func nearest_trail_point(pos: Vector3) -> Dictionary:
	var best := INF
	var out := {"pos": hub, "dir": Vector3.FORWARD, "trail": 0, "index": 0}
	for t in trails.size():
		var line := trails[t]
		for i in line.size():
			var d := Vector2(line[i].x - pos.x, line[i].z - pos.z).length_squared()
			if d < best:
				best = d
				var a := line[maxi(i - 1, 0)]
				var b := line[mini(i + 1, line.size() - 1)]
				var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
				out = {"pos": line[i], "dir": dir if dir.length() > 0.1 else Vector3.FORWARD, "trail": t, "index": i}
	return out


# ---------------------------------------------------------------- building

func _vertex_color(i: int, j: int) -> Color:
	var idx := j * RES + i
	var c: Dictionary = def["colors"]
	var p := grid_to_world(i, j)
	var h := heights[idx]
	var tint := _n_tint.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var base: Color = (c["base"] as Color).lerp(c["base2"], tint)
	var kind := str(def["kind"])
	if kind == "hills":
		base = base.lerp(c["high"], smoothstep(30.0, 50.0, h) * 0.6)
	elif kind == "canyon":
		base = base.lerp(c["high"], smoothstep(20.0, 40.0, h) * 0.5)
	elif kind == "mountain":
		base = base.lerp(c["high"], smoothstep(90.0, 140.0, h))
	var col := base
	match surf[idx]:
		Surf.ROCK:
			col = (c["rock"] as Color).lerp(c["rock2"], tint)
		Surf.SPECIAL:
			col = (c["special"] as Color).lerp(base, 0.15 + tint * 0.15)
		Surf.WATER:
			col = (c["special"] as Color).darkened(0.25)
	var slope := _grid_slope(i, j)
	# The raised rim at the map edge keeps the map's ground colour instead of turning to rock.
	var edge := minf(HALF - absf(p.x), HALF - absf(p.y))
	if edge < 100.0 and surf[idx] == Surf.ROCK:
		col = col.lerp(base.darkened(0.18), 1.0 - smoothstep(60.0, 100.0, edge))
	if surf[idx] != Surf.ROCK and slope > 0.55:
		col = col.lerp(c["rock"], smoothstep(0.55, 0.8, slope) * 0.7)
	var rw := smoothstep(0.35, 0.9, road_w[idx])
	if rw > 0.0 and surf[idx] != Surf.SPECIAL:
		var road: Color = (c["road"] as Color).lerp((c["road"] as Color).darkened(0.12), tint)
		col = col.lerp(road, rw)
	return col


func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.96
	mat.metallic_specular = 0.2
	var colors := PackedColorArray()
	colors.resize(RES * RES)
	var normals := PackedVector3Array()
	normals.resize(RES * RES)
	for j in RES:
		for i in RES:
			var idx := j * RES + i
			colors[idx] = _vertex_color(i, j)
			var hl := heights[j * RES + maxi(i - 1, 0)]
			var hr := heights[j * RES + mini(i + 1, RES - 1)]
			var hd := heights[maxi(j - 1, 0) * RES + i]
			var hu := heights[mini(j + 1, RES - 1) * RES + i]
			normals[idx] = Vector3(hl - hr, 2.0 * SPACING, hd - hu).normalized()
	var chunks := (RES - 1) / CHUNK
	for cj in chunks:
		for ci in chunks:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idxs := PackedInt32Array()
			for j in range(cj * CHUNK, cj * CHUNK + CHUNK + 1):
				for i in range(ci * CHUNK, ci * CHUNK + CHUNK + 1):
					var idx := j * RES + i
					var p := grid_to_world(i, j)
					verts.append(Vector3(p.x, heights[idx], p.y))
					norms.append(normals[idx])
					cols.append(colors[idx])
			var w := CHUNK + 1
			for j in CHUNK:
				for i in CHUNK:
					var a := j * w + i
					var b := a + 1
					var cc := a + w
					var dd := cc + 1
					# Match the heightmap collision diagonal.
					idxs.append_array([a, b, cc, b, dd, cc])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = idxs
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "Chunk_%d_%d" % [ci, cj]
			add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	body.physics_material_override = pm
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	var data := PackedFloat32Array()
	data.resize(RES * RES)
	for k in heights.size():
		data[k] = heights[k] / SPACING
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * SPACING
	body.add_child(cs)
	add_child(body)


func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	for k in 4:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(SIZE + 40.0, 600.0, 20.0)
		cs.shape = box
		cs.rotation.y = (PI * 0.5) * k
		cs.position = Vector3(0, 200, -HALF - 6.0).rotated(Vector3.UP, (PI * 0.5) * k)
		body.add_child(cs)
	add_child(body)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(def["colors"]["water"], 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.1
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position.y = water_level
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A shaded overview image for the map screen.
func build_map_image() -> Image:
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	for j in RES:
		for i in RES:
			var idx := j * RES + i
			var col := _vertex_color(i, j)
			if surf[idx] == Surf.WATER:
				col = def["colors"]["water"]
			var hl := heights[j * RES + maxi(i - 1, 0)]
			var hr := heights[j * RES + mini(i + 1, RES - 1)]
			var hd := heights[maxi(j - 1, 0) * RES + i]
			var hu := heights[mini(j + 1, RES - 1) * RES + i]
			var nrm := Vector3(hl - hr, 2.0 * SPACING, hd - hu).normalized()
			var shade := clampf(nrm.dot(light) * 1.1, 0.35, 1.15)
			img.set_pixel(i, j, Color(col.r * shade, col.g * shade, col.b * shade))
	return img
