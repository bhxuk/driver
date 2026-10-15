class_name UI
extends RefCounted
## Theme and small builders shared by every screen.

const BG := Color("141210")
const PANEL := Color(0.105, 0.095, 0.085, 0.94)
const PANEL_LIGHT := Color("26221e")
const ACCENT := Color("e8772e")
const ACCENT_DARK := Color("b85a1f")
const TEXT := Color("f1ebe3")
const MUTED := Color("a49a8f")
const GOOD := Color("6ee07a")
const BAD := Color("f06a5a")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(22)
	panel.border_color = Color(1, 1, 1, 0.06)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = PANEL_LIGHT
	btn.set_corner_radius_all(7)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color("332d27")
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT_DARK
	var focus := btn.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("1c1916")
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, MUTED.darkened(0.3))
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	var line := StyleBoxFlat.new()
	line.bg_color = Color("0e0c0b")
	line.set_corner_radius_all(6)
	line.content_margin_left = 12
	line.content_margin_right = 12
	line.content_margin_top = 8
	line.content_margin_bottom = 8
	line.border_color = Color(1, 1, 1, 0.08)
	line.set_border_width_all(1)
	var line_focus := line.duplicate() as StyleBoxFlat
	line_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_color", "Label", TEXT)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color("0e0c0b")
	slider.set_corner_radius_all(4)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	var fill := slider.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var tab := btn.duplicate() as StyleBoxFlat
	tab.bg_color = Color("1c1916")
	var tab_sel := btn.duplicate() as StyleBoxFlat
	tab_sel.bg_color = ACCENT_DARK
	t.set_stylebox("tab_unselected", "TabBar", tab)
	t.set_stylebox("tab_hovered", "TabBar", hover)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_focus", "TabBar", focus)
	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", MUTED)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	var popup := panel.duplicate() as StyleBoxFlat
	popup.set_content_margin_all(8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var phover := btn.duplicate() as StyleBoxFlat
	phover.bg_color = ACCENT_DARK
	t.set_stylebox("hover", "PopupMenu", phover)
	return t


static func label(text: String, size: int = 18, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func shadow_label(text: String, size: int = 18, col: Color = TEXT) -> Label:
	var l := label(text, size, col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	b.custom_minimum_size = Vector2(0, 46)
	if primary:
		var s := StyleBoxFlat.new()
		s.bg_color = ACCENT
		s.set_corner_radius_all(7)
		s.content_margin_left = 18
		s.content_margin_right = 18
		var h := s.duplicate() as StyleBoxFlat
		h.bg_color = ACCENT.lightened(0.1)
		var p := s.duplicate() as StyleBoxFlat
		p.bg_color = ACCENT_DARK
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", Color("1a120b"))
		b.add_theme_color_override("font_hover_color", Color("1a120b"))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func field(caption: String, ctrl: Control) -> VBoxContainer:
	var v := vbox(4)
	v.add_child(label(caption, 14, MUTED))
	v.add_child(ctrl)
	return v


static func line_edit(text: String, placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 42)
	return e


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Full-screen dim backdrop that blocks clicks to whatever is behind.
static func dim(alpha: float = 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func color_swatch(col: Color, size: float = 16.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(size, size)
	return r


static func first_focus(node: Node) -> void:
	var b := _find_button(node)
	if b:
		b.grab_focus.call_deferred()


static func _find_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).visible and not (c as Button).disabled:
			return c
		var found := _find_button(c)
		if found:
			return found
	return null
