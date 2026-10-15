class_name Lobby
extends Control
## Co-op lobby: player list, host address info, map choice and start.

var _players_box: VBoxContainer
var _maps_box: VBoxContainer
var _start: Button
var _info: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = MainMenu._backdrop()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	var p := UI.panel(Vector2(980, 560))
	var v := UI.vbox(18)
	p.add_child(v)
	var head := UI.hbox()
	var t := UI.label("Co-op lobby", 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.label("Up to %d players" % Net.MAX_PLAYERS, 16, UI.MUTED))
	v.add_child(head)
	var cols := UI.hbox(28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 380
	left.add_child(UI.label("Players", 20, UI.ACCENT))
	_players_box = UI.vbox(8)
	left.add_child(_players_box)
	left.add_child(UI.spacer(10))
	_info = UI.label("", 15, UI.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 360
	left.add_child(_info)
	cols.add_child(left)
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UI.label("Map", 20, UI.ACCENT))
	_maps_box = UI.vbox(8)
	right.add_child(_maps_box)
	cols.add_child(right)
	var row := UI.hbox()
	row.add_child(UI.button("Leave", func(): Net.leave()))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	_start = UI.button("Start", func(): Net.start_game(Net.lobby_map), true)
	_start.custom_minimum_size.x = 200
	row.add_child(_start)
	v.add_child(row)
	add_child(UI.centered(p))
	Net.players_changed.connect(_refresh)
	Net.lobby_map_changed.connect(func(_m): _refresh())
	_refresh()
	if Net.is_host():
		_start.grab_focus.call_deferred()


func _refresh() -> void:
	if not is_inside_tree():
		return
	for c in _players_box.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var h := UI.hbox(12)
		h.add_child(UI.color_swatch(Net.player_color(id), 18))
		var tag := "  (host)" if id == 1 else ""
		if id == Net.my_id():
			tag += "  (you)"
		h.add_child(UI.label(Net.player_name(id) + tag, 19))
		_players_box.add_child(h)
	for i in range(ids.size(), Net.MAX_PLAYERS):
		_players_box.add_child(UI.label("Open slot", 17, UI.MUTED.darkened(0.3)))
	for c in _maps_box.get_children():
		c.queue_free()
	for id in MapDefs.IDS:
		var d := MapDefs.get_def(id)
		var selected: bool = id == Net.lobby_map
		var b := UI.button(("> " if selected else "") + "%s\n%s" % [d["name"], d["tagline"]], func(): Net.set_lobby_map(id), selected)
		b.custom_minimum_size.y = 74
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Net.is_host()
		_maps_box.add_child(b)
	_start.visible = Net.is_host()
	if Net.is_host():
		var lines := ["Share one of these with your friends:"]
		var addrs := Net.local_addresses()
		if addrs.is_empty():
			lines.append("  (no network address found)")
		for a in addrs:
			var kind := "Tailscale" if Net.is_tailscale(a) else "LAN"
			lines.append("  %s   %s" % [a, kind])
		lines.append("Port %d (UDP)" % Settings.last_port)
		_info.text = "\n".join(lines)
	else:
		_info.text = "Waiting for the host to pick a map and start."
