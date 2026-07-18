class_name UIKit
# Helpers UI partagés — palette, polices, widgets

const COL_GROUND := Color("0E131C")
const COL_PANEL := Color("161D2A")
const COL_PANEL2 := Color("1B2434")
const COL_LINE := Color("232D3F")
const COL_TEXT := Color("E9EEF6")
const COL_MUTED := Color("7B8798")
const COL_ACCENT := Color("FF4655")
const COL_ACCENT2 := Color("57D4FF")
const COL_OK := Color("7CE38B")

static var _mono: SystemFont

static func mono() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])
	return _mono

static func label(txt: String, size: int, col: Color, use_mono: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if use_mono:
		l.add_theme_font_override("font", mono())
	return l

static func panel_style(bg: Color, border: Color, radius: int = 12, margin: int = 28) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

static func btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 11
	sb.content_margin_bottom = 11
	return sb

static func btn(txt: String, primary: bool, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", mono())
	b.add_theme_font_size_override("font_size", font_size)
	if primary:
		b.add_theme_stylebox_override("normal", btn_style(COL_ACCENT, COL_ACCENT))
		b.add_theme_stylebox_override("hover", btn_style(COL_ACCENT.lightened(0.12), COL_ACCENT))
		b.add_theme_stylebox_override("pressed", btn_style(COL_ACCENT.darkened(0.15), COL_ACCENT))
		for s in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(s, Color.WHITE)
	else:
		b.add_theme_stylebox_override("normal", btn_style(COL_PANEL2, COL_LINE))
		b.add_theme_stylebox_override("hover", btn_style(COL_PANEL2, COL_MUTED))
		b.add_theme_stylebox_override("pressed", btn_style(COL_GROUND, COL_LINE))
		for s in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(s, COL_TEXT)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func set_btn_selected(b: Button, selected: bool) -> void:
	if selected:
		b.add_theme_stylebox_override("normal", btn_style(COL_PANEL2, COL_ACCENT))
		b.add_theme_color_override("font_color", COL_TEXT)
	else:
		b.add_theme_stylebox_override("normal", btn_style(COL_PANEL2, COL_LINE))
		b.add_theme_color_override("font_color", COL_MUTED)

static func input(val: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = val
	e.add_theme_font_override("font", mono())
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", COL_TEXT)
	e.add_theme_stylebox_override("normal", btn_style(COL_GROUND, COL_LINE))
	e.add_theme_stylebox_override("focus", btn_style(COL_GROUND, COL_ACCENT2))
	e.add_theme_stylebox_override("read_only", btn_style(COL_GROUND, COL_LINE))
	e.custom_minimum_size = Vector2(120, 0)
	return e

static func center_wrap(inner: Control) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(inner)
	return c

# Overlay plein écran : fond assombri + contenu centré (menus de jeu)
static func overlay_wrap(inner: Control, dim: float = 0.62) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cr := ColorRect.new()
	cr.color = Color(0.02, 0.032, 0.052, dim)
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cr)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(inner)
	root.add_child(cc)
	return root
