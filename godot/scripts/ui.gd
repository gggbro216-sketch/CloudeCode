extends RefCounted
## Общая тема интерфейса и мелкие помощники для меню и HUD.

const BG := "12150f"
const PANEL := "1b2016"
const PANEL2 := "262e1d"
const LINE := "3b4530"
const TEXT := "e8ead9"
const DIM := "9aa38a"
const AMBER := "f0b73a"


static func box(bg: String, border: String, bw: int, radius: int, alpha := 1.0, pad := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var c := Color(bg)
	c.a = alpha
	s.bg_color = c
	s.border_color = Color(border)
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 20
	var normal := box(PANEL, LINE, 2, 10, 0.92)
	var sel := box(PANEL2, AMBER, 2, 10, 0.95)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", normal)
	th.set_stylebox("disabled", "Button", normal)
	th.set_stylebox("pressed", "Button", sel)
	th.set_stylebox("hover_pressed", "Button", sel)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for item in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(item, "Button", Color(TEXT))
	th.set_color("font_disabled_color", "Button", Color(DIM))
	th.set_color("font_color", "Label", Color(TEXT))
	th.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 2, 12, 0.88, 14.0))
	return th


## Крупная жёлтая кнопка действия.
static func accent(b: Button, size := 26) -> void:
	var n := box(AMBER, AMBER, 0, 10, 1.0, 18.0)
	var p := box("c99528", "c99528", 0, 10, 1.0, 18.0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	for item in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(item, Color("1b1405"))
	b.add_theme_font_size_override("font_size", size)


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	return l


## Отступы от выреза экрана и системных панелей (только на телефоне).
static func safe(ctrl: Control) -> Vector4:
	var os_name := OS.get_name()
	if os_name != "Android" and os_name != "iOS":
		return Vector4.ZERO
	var sa := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	if ws.x <= 0 or sa.size.x <= 0:
		return Vector4.ZERO
	var k := ctrl.get_viewport_rect().size.x / float(ws.x)
	return Vector4(sa.position.x * k, sa.position.y * k, (ws.x - sa.end.x) * k, (ws.y - sa.end.y) * k).clamp(Vector4.ZERO, Vector4(120, 80, 120, 80))
