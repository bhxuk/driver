class_name PauseMenu
extends Control
## Esc menu. The game keeps running underneath (it is co-op).

signal resume
signal open_map
signal open_settings

var world: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.dim(0.5))
	var p := UI.panel(Vector2(420, 0))
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.label("Paused" if not Net.online else "Menu", 30))
	var sub := MapDefs.display_name(Net.current_map)
	if Net.online:
		sub += "   %d player%s" % [Net.players.size(), "" if Net.players.size() == 1 else "s"]
	v.add_child(UI.label(sub, 16, UI.MUTED))
	v.add_child(UI.spacer(6))
	v.add_child(UI.button("Resume", func(): resume.emit(), true))
	v.add_child(UI.button("Map", func(): open_map.emit()))
	v.add_child(UI.button("Settings", func(): open_settings.emit()))
	v.add_child(UI.button("Respawn on trail", func():
		if world.local_truck:
			world.local_truck.respawn()
		resume.emit()))
	if world.objectives and world.objectives.state.get("route", -1) >= 0 and Net.is_host():
		v.add_child(UI.button("Abandon route", func():
			world.objectives.abandon_route()
			resume.emit()))
	if Net.is_host() and Net.online:
		v.add_child(UI.button("Back to lobby (change map)", func(): Net.return_to_lobby()))
	if not Net.online:
		for id in MapDefs.IDS:
			if id != Net.current_map:
				var go := func(): Net.start_game(id)
				v.add_child(UI.button("Drive %s" % MapDefs.display_name(id), go))
	v.add_child(UI.button("Leave session" if Net.online else "Quit to title", func(): Net.leave()))
	v.add_child(UI.button("Quit game", func(): get_tree().quit()))
	add_child(UI.centered(p))
	UI.first_focus(v)
