class_name Markers
extends RefCounted
## 3D marker builders: beacons, checkpoint gates, depots, landmarks and base camp props.


static func beam_material(col: Color, alpha: float = 0.32) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func glow_material(col: Color, energy: float = 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func beam(col: Color, height: float = 70.0, radius: float = 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius * 0.6
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	mi.material_override = beam_material(col)
	mi.position.y = height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Beam"
	return mi


static func label(text: String, height: float, col: Color = Color.WHITE, size: int = 72) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position.y = height
	l.no_depth_test = false
	l.fixed_size = false
	l.name = "Label"
	return l


static func checkpoint_gate(col: Color, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.4
	torus.outer_radius = 6.0
	torus.rings = 24
	torus.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = glow_material(col, 1.2)
	ring.rotation = Vector3(PI * 0.5, 0, 0)
	ring.position.y = 3.6
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "Ring"
	var pivot := Node3D.new()
	pivot.add_child(ring)
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.1:
		pivot.rotation.y = atan2(flat.x, flat.z)
	root.add_child(pivot)
	root.add_child(beam(col, 60.0, 0.7))
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = MeshKit.cyl(0.15, 0.15, 3.2, 6)
		post.material_override = glow_material(col, 0.6)
		post.position = Vector3(side * 5.7, 1.6, 0).rotated(Vector3.UP, pivot.rotation.y)
		root.add_child(post)
	return root


static func depot(col: Color, title: String) -> Node3D:
	var root := Node3D.new()
	var pad := MeshInstance3D.new()
	pad.mesh = MeshKit.combine([
		[MeshKit.box(Vector3(14, 1.8, 14)), MeshKit.at(Vector3(0, -0.78, 0)), Color("4b4a46")],
		[MeshKit.box(Vector3(14.2, 0.27, 0.5)), MeshKit.at(Vector3(0, 0.06, -6.9)), col],
		[MeshKit.box(Vector3(14.2, 0.27, 0.5)), MeshKit.at(Vector3(0, 0.06, 6.9)), col],
		[MeshKit.box(Vector3(0.5, 0.27, 14.2)), MeshKit.at(Vector3(-6.9, 0.06, 0)), col],
		[MeshKit.box(Vector3(0.5, 0.27, 14.2)), MeshKit.at(Vector3(6.9, 0.06, 0)), col],
	])
	root.add_child(pad)
	var crates := MeshInstance3D.new()
	crates.mesh = MeshKit.combine([
		[MeshKit.box(Vector3(1.2, 1.2, 1.2)), MeshKit.at(Vector3(8.4, 0.6, -5.0)), Color("9a7148")],
		[MeshKit.box(Vector3(1.2, 1.2, 1.2)), MeshKit.at(Vector3(8.4, 0.6, -3.6)), Color("8a6440")],
		[MeshKit.box(Vector3(1.2, 1.2, 1.2)), MeshKit.at(Vector3(8.4, 1.8, -4.3), Vector3(0, 0.3, 0)), Color("a37a4e")],
		[MeshKit.cyl(0.12, 0.12, 5.0, 6), MeshKit.at(Vector3(-8.0, 2.5, 6.0)), Color("5b5b5b")],
		[MeshKit.box(Vector3(2.4, 1.2, 0.12)), MeshKit.at(Vector3(-8.0, 4.4, 6.0)), col.darkened(0.2)],
	])
	root.add_child(crates)
	root.add_child(beam(col, 50.0, 1.0))
	root.add_child(label(title, 6.5, col.lightened(0.3), 96))
	# Crates and post are solid; the pad is drivable.
	var body := StaticBody3D.new()
	body.add_to_group("winch_anchor")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.3, 2.4, 2.8)
	cs.shape = bx
	cs.position = Vector3(8.4, 1.2, -4.3)
	body.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.2
	cy.height = 5.0
	cs2.shape = cy
	cs2.position = Vector3(-8.0, 2.5, 6.0)
	body.add_child(cs2)
	root.add_child(body)
	return root


static func landmark(col: Color) -> Node3D:
	var root := Node3D.new()
	var stone := Color("8b8780")
	var cairn := MeshInstance3D.new()
	cairn.mesh = MeshKit.combine([
		[MeshKit.sphere(1.3, 6, 3), MeshKit.at(Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), stone],
		[MeshKit.sphere(1.0, 6, 3), MeshKit.at(Vector3(0.1, 1.3, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), stone.darkened(0.1)],
		[MeshKit.sphere(0.7, 6, 3), MeshKit.at(Vector3(-0.05, 1.95, 0.05), Vector3.ZERO, Vector3(1, 0.7, 1)), stone.lightened(0.05)],
		[MeshKit.cyl(0.05, 0.05, 3.5, 5), MeshKit.at(Vector3(0, 3.6, 0)), Color("4a4038")],
	], 0.1, 5)
	root.add_child(cairn)
	var flag := MeshInstance3D.new()
	flag.mesh = MeshKit.box(Vector3(1.2, 0.7, 0.04))
	flag.position = Vector3(0.62, 4.95, 0)
	flag.material_override = glow_material(col, 0.4)
	flag.name = "Flag"
	root.add_child(flag)
	root.add_child(beam(col, 45.0, 0.6))
	var body := StaticBody3D.new()
	body.add_to_group("winch_anchor")
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.3
	cs.shape = sp
	cs.position.y = 0.8
	body.add_child(cs)
	root.add_child(body)
	return root


static func base_camp(col: Color) -> Node3D:
	var root := Node3D.new()
	var wood := Color("7a5a3e")
	var roof := Color("4a4e55")
	var shed := MeshInstance3D.new()
	shed.mesh = MeshKit.combine([
		[MeshKit.box(Vector3(9, 4, 7)), MeshKit.at(Vector3(0, 2, 0)), wood],
		[MeshKit.box(Vector3(9.6, 0.3, 4.4)), MeshKit.at(Vector3(0, 4.6, -1.8), Vector3(0.45, 0, 0)), roof],
		[MeshKit.box(Vector3(9.6, 0.3, 4.4)), MeshKit.at(Vector3(0, 4.6, 1.8), Vector3(-0.45, 0, 0)), roof],
		[MeshKit.box(Vector3(5, 3.2, 0.1)), MeshKit.at(Vector3(0, 1.6, 3.52)), Color("3a3633")],
		[MeshKit.box(Vector3(1.6, 0.9, 0.9)), MeshKit.at(Vector3(5.6, 0.45, 2.0)), Color("b23b2e")],
		[MeshKit.cyl(0.45, 0.45, 1.1, 8), MeshKit.at(Vector3(5.6, 0.55, -1.4)), Color("3e6a8a")],
		[MeshKit.cyl(0.45, 0.45, 1.1, 8), MeshKit.at(Vector3(6.6, 0.55, -1.0)), Color("3e6a8a")],
	])
	root.add_child(shed)
	var body := StaticBody3D.new()
	body.add_to_group("winch_anchor")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(9, 5, 7)
	cs.shape = bx
	cs.position.y = 2.5
	body.add_child(cs)
	root.add_child(body)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffcf8a")
	lamp.light_energy = 1.4
	lamp.omni_range = 14.0
	lamp.position = Vector3(0, 3.6, 4.2)
	root.add_child(lamp)
	root.add_child(label("Base Camp", 7.0, col, 110))
	return root
