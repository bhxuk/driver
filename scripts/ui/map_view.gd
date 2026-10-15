class_name MapView
extends Control
## Full-screen overview map with trails, objectives and players.

signal closed

var world: Node
var _tex: ImageTexture
var _map_rect := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tex = ImageTexture.create_from_image(world.terrain.build_map_image())


func _process(_d: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map") or event.is_action_pressed("pause") or event.is_action_pressed("menu_back"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()


func _to_map(p: Vector3) -> Vector2:
	var u := (p.x + Terrain.HALF) / Terrain.SIZE
	var v := (p.z + Terrain.HALF) / Terrain.SIZE
	return _map_rect.position + Vector2(u, v) * _map_rect.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.035, 0.03, 0.88))
	var s := minf(size.x, size.y) - 140.0
	_map_rect = Rect2((size - Vector2(s, s)) * 0.5 + Vector2(0, 20), Vector2(s, s))
	draw_texture_rect(_tex, _map_rect, false)
	draw_rect(_map_rect, Color(1, 1, 1, 0.2), false, 2.0)
	var font := get_theme_default_font()
	var def: Dictionary = world.terrain.def
	draw_string(font, Vector2(_map_rect.position.x, _map_rect.position.y - 22), str(def["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UI.TEXT)
	draw_string(font, Vector2(_map_rect.end.x - 260, _map_rect.position.y - 22), "N is up.  %s to close" % OS.get_keycode_string(int(Settings.binds["map"]["key"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.MUTED)
	var obj: Objectives = world.objectives
	# Active route path.
	var r: int = obj.state.get("route", -1)
	if r >= 0:
		var pts: Array = obj.routes[r]["points"]
		for i in range(pts.size() - 1):
			draw_line(_to_map(pts[i]), _to_map(pts[i + 1]), Color(Objectives.COL_ROUTE, 0.7), 3.0)
	# Base camp.
	draw_circle(_to_map(world.terrain.hub), 7.0, UI.ACCENT)
	draw_string(font, _to_map(world.terrain.hub) + Vector2(10, -8), "Base Camp", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT)
	for m in obj.markers():
		var p := _to_map(m["pos"])
		var col: Color = m["color"]
		match str(m["kind"]):
			"landmark":
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col)
			"depot", "dest":
				draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), col)
				draw_string(font, p + Vector2(10, 5), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			_:
				draw_circle(p, 7.0, col)
				draw_string(font, p + Vector2(10, 5), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	for id in world.trucks.keys():
		var t: Node3D = world.trucks[id]
		var p2 := _to_map(t.global_position)
		var f := -t.global_basis.z
		var dir := Vector2(f.x, f.z).normalized()
		if dir.length() < 0.1:
			dir = Vector2.UP
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p2 + dir * 12.0, p2 - dir * 7.0 + side * 7.0, p2 - dir * 7.0 - side * 7.0])
		draw_colored_polygon(tri, Net.player_color(id))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 1.5)
		draw_string(font, p2 + Vector2(12, -10), Net.player_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Net.player_color(id).lightened(0.3))
	# Legend.
	var lx := _map_rect.position.x
	var ly := _map_rect.end.y + 28
	var items := [["Route", Objectives.COL_ROUTE], ["Depot", Objectives.COL_DEPOT], ["Your delivery", Objectives.COL_DEST], ["Landmark", Objectives.COL_LANDMARK]]
	for it in items:
		draw_rect(Rect2(lx, ly - 11, 12, 12), it[1])
		draw_string(font, Vector2(lx + 18, ly), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT)
		lx += 150
