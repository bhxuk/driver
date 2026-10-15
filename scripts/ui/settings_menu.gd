class_name SettingsMenu
extends Control
## Settings overlay: game, display, audio and control rebinding (keyboard and controller).

signal closed

var _tabs: TabContainer
var _capture_action := ""
var _capture_pad := false
var _capture_button: Button
var _bind_buttons := {}  # action -> [key_button, pad_button]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.dim(0.6))
	var p := UI.panel(Vector2(760, 620))
	var v := UI.vbox(14)
	p.add_child(v)
	var head := UI.hbox()
	var title := UI.label("Settings", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.button("Done", _close, true))
	v.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_game_tab())
	_tabs.add_child(_display_tab())
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_controls_tab())
	add_child(UI.centered(p))
	UI.first_focus(head)


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _scroll_page(page_name: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = page_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_right", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	sc.add_child(m)
	return [sc, v]


func _row(caption: String, ctrl: Control) -> HBoxContainer:
	var h := UI.hbox(16)
	var l := UI.label(caption, 17)
	l.custom_minimum_size.x = 240
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	return h


func _check(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(cb)
	return c


func _slider(minv: float, maxv: float, step: float, value: float, cb: Callable, fmt: String) -> HBoxContainer:
	var h := UI.hbox(12)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 28
	var l := UI.label(fmt % value, 16, UI.MUTED)
	l.custom_minimum_size.x = 60
	s.value_changed.connect(func(x: float):
		l.text = fmt % x
		cb.call(x))
	h.add_child(s)
	h.add_child(l)
	return h


func _game_tab() -> Control:
	var page := _scroll_page("Game")
	var v: VBoxContainer = page[1]
	var name_edit := UI.line_edit(Settings.player_name, "Your name")
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			Settings.player_name = t.strip_edges())
	v.add_child(_row("Player name", name_edit))
	var colors := OptionButton.new()
	for i in Net.COLOR_NAMES.size():
		colors.add_item(Net.COLOR_NAMES[i], i)
	colors.selected = clampi(Settings.preferred_color, 0, 3)
	colors.item_selected.connect(func(i: int): Settings.preferred_color = i)
	v.add_child(_row("Truck colour", colors))
	var units := OptionButton.new()
	units.add_item("mph", 0)
	units.add_item("km/h", 1)
	units.selected = 1 if Settings.units == "kmh" else 0
	units.item_selected.connect(func(i: int): Settings.units = "kmh" if i == 1 else "mph")
	v.add_child(_row("Speed units", units))
	v.add_child(_row("Mouse sensitivity", _slider(0.2, 3.0, 0.1, Settings.mouse_sensitivity, func(x): Settings.mouse_sensitivity = x, "%.1f")))
	v.add_child(_row("Stick sensitivity", _slider(0.2, 3.0, 0.1, Settings.stick_sensitivity, func(x): Settings.stick_sensitivity = x, "%.1f")))
	v.add_child(_row("Invert camera Y", _check(Settings.invert_y, func(b): Settings.invert_y = b)))
	v.add_child(_row("Camera returns behind", _check(Settings.auto_center_camera, func(b): Settings.auto_center_camera = b)))
	return page[0]


func _display_tab() -> Control:
	var page := _scroll_page("Display")
	var v: VBoxContainer = page[1]
	v.add_child(_row("Fullscreen", _check(Settings.fullscreen, func(b):
		Settings.fullscreen = b
		Settings.apply_display())))
	v.add_child(_row("V-Sync", _check(Settings.vsync, func(b):
		Settings.vsync = b
		Settings.apply_display())))
	v.add_child(_row("Shadows", _check(Settings.shadows, func(b):
		Settings.shadows = b
		Settings.apply_display())))
	v.add_child(_row("Render scale", _slider(0.5, 1.0, 0.05, Settings.render_scale, func(x):
		Settings.render_scale = x
		Settings.apply_display(), "%.2f")))
	v.add_child(_row("Field of view", _slider(55.0, 95.0, 1.0, Settings.fov, func(x): Settings.fov = x, "%d")))
	return page[0]


func _audio_tab() -> Control:
	var page := _scroll_page("Audio")
	var v: VBoxContainer = page[1]
	v.add_child(_row("Master volume", _slider(0.0, 1.0, 0.05, Settings.master_volume, func(x):
		Settings.master_volume = x
		Settings.apply_audio(), "%.2f")))
	return page[0]


func _controls_tab() -> Control:
	var page := _scroll_page("Controls")
	var v: VBoxContainer = page[1]
	var head := UI.hbox(16)
	var a := UI.label("Action", 14, UI.MUTED)
	a.custom_minimum_size.x = 240
	head.add_child(a)
	var k := UI.label("Keyboard", 14, UI.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	var pd := UI.label("Controller", 14, UI.MUTED)
	pd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(pd)
	v.add_child(head)
	for entry in Settings.ACTIONS:
		var action: String = entry[0]
		var h := UI.hbox(16)
		var l := UI.label(entry[1], 17)
		l.custom_minimum_size.x = 240
		h.add_child(l)
		var kb := Button.new()
		kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kb.pressed.connect(_start_capture.bind(action, false))
		var pb := Button.new()
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.pressed.connect(_start_capture.bind(action, true))
		h.add_child(kb)
		h.add_child(pb)
		_bind_buttons[action] = [kb, pb]
		v.add_child(h)
	v.add_child(UI.label("Camera: mouse or right stick. Scroll wheel zooms.", 14, UI.MUTED))
	var reset := UI.button("Reset to defaults", func():
		Settings.reset_binds()
		_refresh_binds())
	v.add_child(reset)
	_refresh_binds()
	return page[0]


func _refresh_binds() -> void:
	for action in _bind_buttons.keys():
		var pair: Array = _bind_buttons[action]
		(pair[0] as Button).text = Settings.key_label(action)
		(pair[1] as Button).text = Settings.pad_label(action)


func _start_capture(action: String, pad: bool) -> void:
	_capture_action = action
	_capture_pad = pad
	_capture_button = _bind_buttons[action][1 if pad else 0]
	_capture_button.text = "Press a button..." if pad else "Press a key..."


func _input(event: InputEvent) -> void:
	if _capture_action == "":
		if event.is_action_pressed("menu_back") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_close()
		return
	if _capture_pad:
		if event is InputEventJoypadButton and event.pressed:
			Settings.set_pad(_capture_action, event)
			_end_capture()
		elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
			Settings.set_pad(_capture_action, event)
			_end_capture()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_end_capture()
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.physical_keycode
			if code == KEY_ESCAPE and _capture_action != "pause":
				_end_capture()
			else:
				Settings.set_key(_capture_action, code)
				_end_capture()
	get_viewport().set_input_as_handled()


func _end_capture() -> void:
	_capture_action = ""
	_refresh_binds()
