class_name TruckVisual
extends Node3D
## Truck body, lights, cargo crates, name tag and winch cable. Shared by local and remote trucks.

const WHEEL_POSITIONS := [
	Vector3(-0.98, 0.15, -1.45), Vector3(0.98, 0.15, -1.45),
	Vector3(-0.98, 0.15, 1.45), Vector3(0.98, 0.15, 1.45),
]
const WHEEL_RADIUS := 0.5
const WINCH_POINT := Vector3(0, 0.55, -2.4)

var body_color := Color.ORANGE
var headlights: Array[SpotLight3D] = []
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var cargo_node: Node3D
var name_tag: Label3D
var cable: MeshInstance3D


func build(col: Color, player_label: String, show_tag: bool) -> void:
	body_color = col
	var dark := Color("2b2a29")
	var trim := col.darkened(0.25)
	var glass := Color("1d2730")
	var custom := AssetLib.list_models("res://assets/vehicles/truck")
	if custom.is_empty():
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = MeshKit.combine([
			[MeshKit.box(Vector3(2.05, 0.55, 4.5)), MeshKit.at(Vector3(0, 0.62, 0.0)), col],
			[MeshKit.box(Vector3(1.9, 0.28, 1.35)), MeshKit.at(Vector3(0, 1.0, -1.5), Vector3(-0.06, 0, 0)), trim],
			[MeshKit.box(Vector3(1.86, 0.88, 1.7)), MeshKit.at(Vector3(0, 1.32, -0.2)), col],
			[MeshKit.box(Vector3(1.72, 0.62, 0.06)), MeshKit.at(Vector3(0, 1.38, -1.07), Vector3(-0.32, 0, 0)), glass],
			[MeshKit.box(Vector3(0.06, 0.5, 1.2)), MeshKit.at(Vector3(-0.94, 1.42, -0.2)), glass],
			[MeshKit.box(Vector3(0.06, 0.5, 1.2)), MeshKit.at(Vector3(0.94, 1.42, -0.2)), glass],
			[MeshKit.box(Vector3(1.6, 0.45, 0.06)), MeshKit.at(Vector3(0, 1.45, 0.66)), glass],
			[MeshKit.box(Vector3(0.12, 0.42, 1.6)), MeshKit.at(Vector3(-0.97, 1.08, 1.4)), trim],
			[MeshKit.box(Vector3(0.12, 0.42, 1.6)), MeshKit.at(Vector3(0.97, 1.08, 1.4)), trim],
			[MeshKit.box(Vector3(2.0, 0.42, 0.12)), MeshKit.at(Vector3(0, 1.08, 2.2)), trim],
			[MeshKit.box(Vector3(2.15, 0.32, 0.3)), MeshKit.at(Vector3(0, 0.5, -2.32)), dark],
			[MeshKit.box(Vector3(2.15, 0.28, 0.25)), MeshKit.at(Vector3(0, 0.5, 2.32)), dark],
			[MeshKit.box(Vector3(0.5, 0.3, 0.3)), MeshKit.at(Vector3(0, 0.55, -2.45)), Color("3d3d3d")],
			[MeshKit.box(Vector3(1.7, 0.1, 1.5)), MeshKit.at(Vector3(0, 1.8, -0.2)), dark],
			[MeshKit.box(Vector3(2.3, 0.14, 1.2)), MeshKit.at(Vector3(0, 0.98, -1.45)), dark],
			[MeshKit.box(Vector3(2.3, 0.14, 1.2)), MeshKit.at(Vector3(0, 0.98, 1.45)), dark],
			[MeshKit.box(Vector3(0.2, 0.12, 1.4)), MeshKit.at(Vector3(-1.1, 0.45, 0)), dark],
			[MeshKit.box(Vector3(0.2, 0.12, 1.4)), MeshKit.at(Vector3(1.1, 0.45, 0)), dark],
		])
		add_child(body)
	else:
		var entry := AssetLib.load_model(custom[0])
		if not entry.is_empty():
			var aabb: AABB = entry["aabb"]
			var s := 4.6 / maxf(maxf(aabb.size.z, aabb.size.x), 0.01)
			var fit := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(-aabb.get_center().x * s, -aabb.position.y * s + 0.05, -aabb.get_center().z * s))
			for part in entry["parts"]:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				if part[2]:
					mi.material_override = part[2]
				mi.transform = fit * (part[1] as Transform3D)
				add_child(mi)
	# Lights.
	head_mat = Markers.glow_material(Color("fff3c4"), 0.2)
	tail_mat = Markers.glow_material(Color("c2261c"), 0.3)
	for side in [-1.0, 1.0]:
		var hl := MeshInstance3D.new()
		hl.mesh = MeshKit.box(Vector3(0.36, 0.18, 0.05))
		hl.material_override = head_mat
		hl.position = Vector3(side * 0.68, 0.88, -2.26)
		add_child(hl)
		var tl := MeshInstance3D.new()
		tl.mesh = MeshKit.box(Vector3(0.22, 0.2, 0.05))
		tl.material_override = tail_mat
		tl.position = Vector3(side * 0.88, 0.85, 2.27)
		add_child(tl)
		var spot := SpotLight3D.new()
		spot.light_color = Color("fff1d0")
		spot.light_energy = 0.0
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = false
		spot.position = Vector3(side * 0.68, 0.9, -2.3)
		spot.visible = false
		add_child(spot)
		headlights.append(spot)
	var bar := MeshInstance3D.new()
	bar.mesh = MeshKit.box(Vector3(1.3, 0.1, 0.12))
	bar.material_override = head_mat
	bar.position = Vector3(0, 1.88, -0.9)
	add_child(bar)
	# Cargo crates in the bed.
	cargo_node = Node3D.new()
	var crates := MeshInstance3D.new()
	crates.mesh = MeshKit.combine([
		[MeshKit.box(Vector3(0.8, 0.7, 0.8)), MeshKit.at(Vector3(-0.42, 1.2, 1.0)), Color("a37a4e")],
		[MeshKit.box(Vector3(0.8, 0.7, 0.8)), MeshKit.at(Vector3(0.42, 1.2, 1.1), Vector3(0, 0.2, 0)), Color("8f6a43")],
		[MeshKit.box(Vector3(0.8, 0.6, 0.7)), MeshKit.at(Vector3(0.0, 1.2, 1.85)), Color("b0875a")],
		[MeshKit.box(Vector3(0.7, 0.6, 0.7)), MeshKit.at(Vector3(-0.05, 1.85, 1.15), Vector3(0, -0.15, 0)), Color("9a7148")],
	])
	cargo_node.add_child(crates)
	cargo_node.visible = false
	add_child(cargo_node)
	if show_tag:
		name_tag = Markers.label(player_label, 2.9, col.lightened(0.25), 56)
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0015
		name_tag.no_depth_test = true
		add_child(name_tag)
	cable = MeshInstance3D.new()
	cable.mesh = MeshKit.cyl(0.035, 0.035, 1.0, 5)
	cable.material_override = Markers.glow_material(Color("cfcfcf"), 0.05)
	cable.top_level = true
	cable.visible = false
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cable)


func set_lights(on: bool) -> void:
	for s in headlights:
		s.visible = on
		s.light_energy = 2.2 if on else 0.0
	head_mat.emission_energy_multiplier = 3.0 if on else 0.2


func set_braking(on: bool) -> void:
	tail_mat.emission_energy_multiplier = 3.0 if on else 0.3


func set_cargo(on: bool) -> void:
	cargo_node.visible = on


func update_cable(from: Vector3, to: Vector3, attached: bool) -> void:
	if not attached:
		cable.visible = false
		return
	var d := from.distance_to(to)
	if d < 0.05:
		cable.visible = false
		return
	cable.visible = true
	var dir := (to - from) / d
	var up := dir
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up).normalized()
	cable.global_transform = Transform3D(Basis(side, up * d, fwd), (from + to) * 0.5)


static func make_wheel_mesh() -> ArrayMesh:
	var tire := Color("252321")
	var rim := Color("9a9894")
	return MeshKit.combine([
		[MeshKit.cyl(WHEEL_RADIUS, WHEEL_RADIUS, 0.42, 14), MeshKit.at(Vector3.ZERO, Vector3(0, 0, PI * 0.5)), tire],
		[MeshKit.cyl(0.3, 0.3, 0.44, 8), MeshKit.at(Vector3.ZERO, Vector3(0, 0, PI * 0.5)), rim],
		[MeshKit.box(Vector3(0.46, 0.12, 0.62)), MeshKit.at(Vector3.ZERO), rim.darkened(0.3)],
	])
