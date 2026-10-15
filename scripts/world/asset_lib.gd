class_name AssetLib
extends RefCounted
## Optional model overrides. Drop .glb / .gltf / .tscn files into
##   res://assets/props/<type>/      (pine, pine_snow, broadleaf, bush, rock, boulder, cactus, dead_tree)
##   res://assets/vehicles/truck/    (truck body, wheels stay generated)
## and they replace the generated placeholders. Models are scaled to fit automatically.

const EXTS := ["glb", "gltf", "tscn", "scn", "obj"]

static var _cache: Dictionary = {}


static func list_models(dir: String) -> Array[String]:
	var out: Array[String] = []
	var names := PackedStringArray()
	if ResourceLoader.has_method("list_directory"):
		names = ResourceLoader.call("list_directory", dir)
	else:
		var d := DirAccess.open(dir)
		if d:
			names = d.get_files()
	for n in names:
		var f := str(n).trim_suffix(".import").trim_suffix(".remap")
		if f.get_extension().to_lower() in EXTS and not (dir.path_join(f) in out):
			out.append(dir.path_join(f))
	out.sort()
	return out


## Returns an array of model entries: {"parts": [[Mesh, Transform3D]], "aabb": AABB}
static func models_for(type: String) -> Array:
	if _cache.has(type):
		return _cache[type]
	var out := []
	for path in list_models("res://assets/props/%s" % type):
		var entry := load_model(path)
		if not entry.is_empty():
			out.append(entry)
	_cache[type] = out
	return out


static func load_model(path: String) -> Dictionary:
	var res: Resource = load(path)
	var root: Node3D = null
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		if inst is Node3D:
			root = inst
		elif inst:
			inst.free()
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		root = Node3D.new()
		root.add_child(mi)
	if root == null:
		return {}
	var parts := []
	var aabb := AABB()
	var first := true
	for mi in _mesh_instances(root):
		var xf := _relative_transform(mi, root)
		parts.append([mi.mesh, xf, mi.material_override])
		var box: AABB = xf * mi.mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	root.free()
	if parts.is_empty():
		return {}
	return {"parts": parts, "aabb": aabb}


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_mesh_instances(c))
	return out


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Transform that scales a model so its height matches target_height and its base sits at y = 0.
static func fit_transform(aabb: AABB, target_height: float) -> Transform3D:
	var h := maxf(aabb.size.y, 0.001)
	var s := target_height / h
	var center := aabb.get_center()
	var offset := Vector3(-center.x, -aabb.position.y, -center.z) * s
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), offset)
