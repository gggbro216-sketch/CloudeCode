extends RefCounted
## Общие элементы интерфейса: тема, кнопки, отступы под вырез экрана.

const BG := Color(0.08, 0.09, 0.07, 0.88)
const BTN := Color(0.15, 0.17, 0.12, 0.94)
const BTN_ON := Color(0.33, 0.42, 0.18, 0.97)
const EDGE := Color(0.42, 0.46, 0.30)
const TEXT := Color(0.93, 0.92, 0.84)
const ACCENT := Color(0.95, 0.78, 0.38)


static func box(col: Color, edge := EDGE, radius := 6, border := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 19
	th.set_stylebox("normal", "Button", box(BTN))
	th.set_stylebox("hover", "Button", box(BTN.lightened(0.08)))
	th.set_stylebox("pressed", "Button", box(BTN_ON))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.09, 0.8), Color(0.25, 0.25, 0.22)))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", TEXT)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.45))
	th.set_stylebox("panel", "PanelContainer", box(BG, Color(0.3, 0.33, 0.22), 8))
	th.set_stylebox("panel", "Panel", box(BG, Color(0.3, 0.33, 0.22), 8))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return th


static func btn(text: String, cb: Callable, min_size := Vector2(0, 54)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func set_on(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", box(BTN_ON, ACCENT))
		b.add_theme_stylebox_override("hover", box(BTN_ON, ACCENT))
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_stylebox_override("hover")


static func label(text: String, size := 19, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Отступы безопасной зоны (вырез камеры, скругления) в координатах вьюпорта: x — слева, y — сверху, z — справа, w — снизу.
static func safe(c: Control) -> Vector4:
	var ws := Vector2(DisplayServer.window_get_size())
	if ws.x <= 0.0 or ws.y <= 0.0:
		return Vector4.ZERO
	var sa := DisplayServer.get_display_safe_area()
	var vs := c.get_viewport_rect().size
	var k := vs / ws
	if sa.size.x <= 0 or sa.size.x > ws.x + 1 or sa.size.y > ws.y + 1:
		return Vector4.ZERO
	return Vector4(sa.position.x * k.x, sa.position.y * k.y, (ws.x - sa.end.x) * k.x, (ws.y - sa.end.y) * k.y)
