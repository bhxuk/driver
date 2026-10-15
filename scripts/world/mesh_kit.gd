class_name MeshKit
extends RefCounted
## Builds simple low-poly meshes from primitives, baked into one vertex-coloured surface.
## These are the placeholders used until Quaternius (or any) models are dropped into assets/.

static var _shared_material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = true
		_shared_material.roughness = 0.9
	return _shared_material


## parts: Array of [PrimitiveMesh, Transform3D, Color]
static func combine(parts: Array, jitter: float = 0.0, seed: int = 0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for part in parts:
		var prim: Mesh = part[0]
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var arr := prim.surface_get_arrays(0)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var basis_n := xf.basis.inverse().transposed()
		for k in pv.size():
			var v := xf * pv[k]
			if jitter > 0.0:
				# Same jitter for identical positions so seams stay closed.
				var h := hash(Vector3i(roundi(pv[k].x * 100), roundi(pv[k].y * 100), roundi(pv[k].z * 100)) + Vector3i(seed, 0, 0))
				var r := RandomNumberGenerator.new()
				r.seed = h
				v += Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)) * jitter
			verts.append(v)
			norms.append((basis_n * pn[k]).normalized())
			cols.append(col)
		if pi.is_empty():
			for k in pv.size():
				idxs.append(base + k)
		else:
			for k in pi.size():
				idxs.append(base + pi[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(top: float, bottom: float, height: float, segments: int = 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, segments: int = 7, rings: int = 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 8
	m.rings = 2
	return m


static func at(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot).scaled(scl)
	return Transform3D(b, pos)


# ---------------------------------------------------------------- prop library
## Each prop returns {"mesh": ArrayMesh, "shape": "cyl"/"sphere", "radius": float, "height": float}

static func prop(type: String, variant: int) -> Dictionary:
	match type:
		"pine", "pine_snow":
			var snow := type == "pine_snow"
			var green := Color("2f5a34") if not snow else Color("335a45")
			var tip := green.lightened(0.12) if not snow else Color("e9f0f4")
			var trunk := Color("5a4030")
			var h := 7.5 + variant * 1.2
			var parts := [[cyl(0.22, 0.3, 2.0, 6), at(Vector3(0, 1.0, 0)), trunk]]
			var y := 1.6
			for k in 3:
				var r := 2.2 - k * 0.55
				var ch := 2.8 - k * 0.3
				parts.append([cyl(0.0, r, ch, 7), at(Vector3(0, y + ch * 0.5, 0)), green if k < 2 or not snow else tip])
				y += ch * 0.62
			if snow:
				parts.append([cyl(0.0, 1.2, 1.2, 7), at(Vector3(0, y + 0.4, 0)), tip])
			var mesh := combine(parts)
			return {"mesh": mesh, "shape": "cyl", "radius": 0.45, "height": h}
		"broadleaf":
			var leaf: Color = [Color("4f7d32"), Color("5d8a37"), Color("6b8f2e")][variant % 3]
			var parts2 := [
				[cyl(0.25, 0.35, 3.4, 6), at(Vector3(0, 1.7, 0)), Color("604634")],
				[sphere(2.3, 7, 4), at(Vector3(0, 4.6, 0), Vector3.ZERO, Vector3(1.0, 0.85, 1.0)), leaf],
				[sphere(1.5, 6, 3), at(Vector3(1.2, 4.0, 0.4)), leaf.darkened(0.08)],
				[sphere(1.4, 6, 3), at(Vector3(-1.0, 4.3, -0.6)), leaf.lightened(0.05)],
			]
			return {"mesh": combine(parts2, 0.12, variant), "shape": "cyl", "radius": 0.5, "height": 6.5}
		"bush":
			var bc := Color("4e7a34").lerp(Color("6d8c3a"), variant * 0.3)
			var parts3 := [
				[sphere(0.9, 6, 3), at(Vector3(0, 0.6, 0)), bc],
				[sphere(0.7, 6, 3), at(Vector3(0.7, 0.45, 0.2)), bc.darkened(0.1)],
				[sphere(0.6, 6, 3), at(Vector3(-0.5, 0.4, -0.4)), bc.lightened(0.06)],
			]
			return {"mesh": combine(parts3, 0.08, variant), "shape": "none", "radius": 0.0, "height": 1.4}
		"rock", "boulder":
			var big := type == "boulder"
			var rc := Color("8a857c").lerp(Color("6f6a62"), variant * 0.33)
			var r := 1.0
			var parts4 := [[sphere(r, 6, 4), at(Vector3(0, 0.25, 0), Vector3(0, 0, 0), Vector3(1.3, 0.8, 1.0)), rc]]
			if big:
				parts4.append([sphere(0.7, 5, 3), at(Vector3(0.8, 0.5, 0.3)), rc.darkened(0.08)])
			return {"mesh": combine(parts4, 0.18, variant + (17 if big else 3)), "shape": "sphere", "radius": 0.95, "height": 1.6}
		"cactus":
			var cc := Color("4f7a3d")
			var parts5 := [
				[capsule(0.32, 4.2), at(Vector3(0, 2.1, 0)), cc],
				[capsule(0.22, 1.6), at(Vector3(0.6, 2.4, 0)), cc.darkened(0.05)],
				[capsule(0.22, 0.9), at(Vector3(0.35, 2.0, 0), Vector3(0, 0, PI * 0.5)), cc.darkened(0.05)],
			]
			if variant % 2 == 0:
				parts5.append([capsule(0.2, 1.3), at(Vector3(-0.55, 2.9, 0)), cc.lightened(0.04)])
				parts5.append([capsule(0.2, 0.8), at(Vector3(-0.3, 2.6, 0), Vector3(0, 0, PI * 0.5)), cc.lightened(0.04)])
			return {"mesh": combine(parts5), "shape": "cyl", "radius": 0.4, "height": 4.4}
		"dead_tree":
			var wood := Color("7a6450")
			var parts6 := [
				[cyl(0.14, 0.28, 4.0, 6), at(Vector3(0, 2.0, 0)), wood],
				[cyl(0.06, 0.12, 2.0, 5), at(Vector3(0.5, 3.4, 0), Vector3(0, 0, -0.7)), wood],
				[cyl(0.05, 0.1, 1.6, 5), at(Vector3(-0.4, 3.0, 0.2), Vector3(0.3, 0, 0.8)), wood],
			]
			return {"mesh": combine(parts6), "shape": "cyl", "radius": 0.3, "height": 4.5}
	return {"mesh": combine([[box(Vector3.ONE), Transform3D.IDENTITY, Color.MAGENTA]]), "shape": "sphere", "radius": 0.5, "height": 1.0}
