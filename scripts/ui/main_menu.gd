class_name MainMenu
extends Control
## Title screen: single player, host, join, settings, quit.

signal open_settings

var _content: VBoxContainer
var _status: Label
var message := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = _backdrop()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 90)
	root.add_theme_constant_override("margin_top", 70)
	root.add_theme_constant_override("margin_bottom", 50)
	add_child(root)
	var col := UI.vbox(0)
	root.add_child(col)
	var title := UI.shadow_label("DRIVER", 112, UI.TEXT)
	title.add_theme_constant_override("line_spacing", -20)
	col.add_child(title)
	col.add_child(UI.shadow_label("Off-road. Solo or with up to three friends.", 22, UI.ACCENT))
	col.add_child(UI.spacer(36))
	_content = UI.vbox(12)
	_content.custom_minimum_size.x = 420
	_content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_content)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	_status = UI.shadow_label("", 18, UI.BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 600
	col.add_child(_status)
	col.add_child(UI.shadow_label("v%s" % Net.VERSION, 14, UI.MUTED))
	set_message(message)
	show_home()


func set_message(text: String, good: bool = false) -> void:
	message = text
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", UI.GOOD if good else UI.BAD)


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()


func show_home() -> void:
	_clear()
	_content.add_child(UI.button("Single player", show_single, true))
	_content.add_child(UI.button("Host co-op", show_host))
	_content.add_child(UI.button("Join co-op", show_join))
	_content.add_child(UI.button("Settings", func(): open_settings.emit()))
	_content.add_child(UI.button("Quit", func(): get_tree().quit()))
	UI.first_focus(_content)


func show_single() -> void:
	_clear()
	_content.add_child(UI.shadow_label("Choose a map", 26))
	for id in MapDefs.IDS:
		var d := MapDefs.get_def(id)
		var start := func():
			Net.start_single()
			Net.start_game(id)
		var b := UI.button("%s\n%s" % [d["name"], d["tagline"]], start)
		b.custom_minimum_size.y = 72
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_content.add_child(b)
	_content.add_child(UI.button("Back", show_home))
	UI.first_focus(_content)


func show_host() -> void:
	_clear()
	var p := UI.panel()
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.label("Host a co-op session", 24))
	var name_edit := UI.line_edit(Settings.player_name, "Your name")
	name_edit.max_length = 16
	v.add_child(UI.field("Your name", name_edit))
	var port_edit := UI.line_edit(str(Settings.last_port))
	v.add_child(UI.field("Port (UDP)", port_edit))
	v.add_child(UI.label("Friends join with your LAN or Tailscale IP.\nWindows may ask to allow Driver through the firewall: allow it.", 14, UI.MUTED))
	var row := UI.hbox()
	row.add_child(UI.button("Back", show_home))
	var do_host := func():
		_apply_name(name_edit.text)
		var port := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		Settings.last_port = port
		Settings.save_settings()
		var err := Net.host(port)
		if err != OK:
			set_message("Could not host on port %d (error %d). Is another copy running?" % [port, err])
	var go := UI.button("Start hosting", do_host, true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	v.add_child(row)
	_content.add_child(p)
	go.grab_focus.call_deferred()


func show_join() -> void:
	_clear()
	var p := UI.panel()
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.label("Join a co-op session", 24))
	var name_edit := UI.line_edit(Settings.player_name, "Your name")
	name_edit.max_length = 16
	v.add_child(UI.field("Your name", name_edit))
	var ip_edit := UI.line_edit(Settings.last_ip, "e.g. 192.168.1.20 or 100.x.y.z")
	v.add_child(UI.field("Host address", ip_edit))
	var port_edit := UI.line_edit(str(Settings.last_port))
	v.add_child(UI.field("Port", port_edit))
	var row := UI.hbox()
	row.add_child(UI.button("Back", show_home))
	var do_join := func():
		_apply_name(name_edit.text)
		var addr := ip_edit.text.strip_edges()
		if addr == "":
			set_message("Enter the host's IP address.")
			return
		var port := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		Settings.last_ip = addr
		Settings.last_port = port
		Settings.save_settings()
		var err := Net.join(addr, port)
		if err != OK:
			set_message("Could not start connecting (error %d)." % err)
		else:
			set_message("Connecting to %s:%d..." % [addr, port], true)
			_show_connecting()
	var go := UI.button("Join", do_join, true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	v.add_child(row)
	_content.add_child(p)
	go.grab_focus.call_deferred()


func _show_connecting() -> void:
	_clear()
	_content.add_child(UI.shadow_label("Connecting...", 26))
	_content.add_child(UI.button("Cancel", func():
		Net.leave()
		set_message("")
		show_home()))


func _apply_name(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		Settings.player_name = t.left(16)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_back") and get_parent() and get_parent().get_child_count() > 0:
		if get_parent().get_child(get_parent().get_child_count() - 1) == self:
			show_home()


static func _backdrop() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color("2a1d14"))
	g.set_color(1, Color("0d0c0b"))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.25, 0.2)
	gt.fill_to = Vector2(1.1, 1.1)
	gt.width = 512
	gt.height = 512
	return gt
