class_name Props
extends Node3D
## Scatters trees, rocks and so on. Same seed on every peer, so everyone sees the same world.
## Visuals are MultiMeshes; collision is one static body (tagged as a winch anchor).

const VARIANTS := 3
const TARGET_HEIGHT := {
	"pine": 9.0, "pine_snow": 9.0, "broadleaf": 7.0, "bush": 1.5, "rock": 1.8,
	"boulder": 3.0, "cactus": 4.5, "dead_tree": 5.0,
}

var terrain: Terrain
var anchors: StaticBody3D
var placed: Array = []  # [Vector3 position, radius] for spacing checks


func build(t: Terrain, def: Dictionary, avoid: Array) -> void:
	terrain = t
	anchors = StaticBody3D.new()
	anchors.name = "PropColliders"
	anchors.add_to_group("winch_anchor")
	add_child(anchors)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(def["seed"]) * 31 + 7
	for spec in def["props"]:
		_scatter(spec, rng, avoid)


func _scatter(spec: Dictionary, rng: RandomNumberGenerator, avoid: Array) -> void:
	var type: String = spec["type"]
	var count: int = spec["count"]
	var max_slope: float = spec.get("max_slope", 0.7)
	var max_height: float = spec.get("max_height", 9999.0)
	var models := AssetLib.models_for(type)
	var n_variants := models.size() if not models.is_empty() else VARIANTS
	var buckets := []  # per variant: Array[Transform3D]
	for v in n_variants:
		buckets.append([])
	var big := type == "boulder"
	var attempts := count * 4
	var made := 0
	while made < count and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-Terrain.HALF + 30.0, Terrain.HALF - 30.0)
		var z := rng.randf_range(-Terrain.HALF + 30.0, Terrain.HALF - 30.0)
		var s := terrain.surface_at(x, z)
		if s == Terrain.Surf.WATER:
			continue
		if terrain.road_weight_at(x, z) > 0.02:
			continue
		if terrain.slope_at(x, z) > max_slope:
			continue
		var y := terrain.height_at(x, z)
		if y > max_height:
			continue
		if terrain.has_water() and y < terrain.water_level + 0.4:
			continue
		var blocked := false
		for a in avoid:
			var ap: Vector3 = a[0]
			if Vector2(ap.x - x, ap.z - z).length() < float(a[1]):
				blocked = true
				break
		if blocked:
			continue
		var scl := rng.randf_range(0.8, 1.3)
		if type == "rock":
			scl = rng.randf_range(0.6, 2.4)
		elif big:
			scl = rng.randf_range(2.0, 4.0)
		var variant := rng.randi() % n_variants
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl)
		if type in ["rock", "boulder"]:
			basis = Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), yaw, rng.randf_range(-0.3, 0.3))).scaled(
				Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.1), rng.randf_range(0.8, 1.2)) * scl)
		var sink := 0.15 * scl if type in ["rock", "boulder"] else 0.1
		var xf := Transform3D(basis, Vector3(x, y - sink, z))
		buckets[variant].append(xf)
		_add_collider(type, Vector3(x, y, z), scl)
		made += 1
	for v in n_variants:
		var list: Array = buckets[v]
		if list.is_empty():
			continue
		if models.is_empty():
			var p := MeshKit.prop(type, v)
			_make_multimesh(p["mesh"], null, list, Transform3D.IDENTITY)
		else:
			var model: Dictionary = models[v]
			var fit := AssetLib.fit_transform(model["aabb"], TARGET_HEIGHT.get(type, 3.0) * (0.55 if type in ["rock", "boulder"] else 1.0))
			for part in model["parts"]:
				_make_multimesh(part[0], part[2], list, fit * (part[1] as Transform3D))


func _make_multimesh(mesh: Mesh, mat: Material, list: Array, local: Transform3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for k in list.size():
		mm.set_instance_transform(k, (list[k] as Transform3D) * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.visibility_range_end = 650.0
	mmi.visibility_range_end_margin = 50.0
	add_child(mmi)


func _add_collider(type: String, pos: Vector3, scl: float) -> void:
	var cs := CollisionShape3D.new()
	match type:
		"bush":
			cs.free()
			return
		"rock", "boulder":
			if scl < 1.0:
				cs.free()
				return
			var sp := SphereShape3D.new()
			sp.radius = 0.95 * scl
			cs.shape = sp
			cs.position = pos + Vector3(0, 0.1 * scl, 0)
		_:
			var cy := CylinderShape3D.new()
			cy.radius = 0.45 * scl
			cy.height = 6.0 * scl
			cs.shape = cy
			cs.position = pos + Vector3(0, cy.height * 0.5 - 0.5, 0)
	anchors.add_child(cs)
