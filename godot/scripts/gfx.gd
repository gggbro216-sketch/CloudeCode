extends RefCounted
## Рисование в Control._draw без полигонов.
##
## В режиме Compatibility каждый draw_circle / draw_arc / draw_polyline / draw_colored_polygon /
## draw_style_box со скруглением заводит на видеокарте новые буферы и VAO — при каждой перерисовке.
## HUD перерисовывается каждый кадр: ~90 буферов и ~60 VAO на кадр, то есть ~5000 в секунду и около
## миллиона за один бой. Мобильный драйвер (Mali) такую пересборку не переваривает: память растёт,
## интерфейс и сцена «рассыпаются», потом вылет — обычно в третьем бою.
## Здесь — замены, не создающие буферов вообще (проверено счётчиком вызовов GL): текстурные квадраты,
## draw_multiline / draw_line, draw_primitive и девять кусков текстуры для панелей.

static var _discs := {}  # размер текстуры → белый круг с мягким краем
static var _boxes := {}  # ключ стиля → [текстура, поле в пикселях текстуры, масштаб]
const SS := 3  # во сколько раз текстуры панелей чётче экранных пикселей


## Заготовить текстуры заранее (на экране загрузки), чтобы первый кадр боя не подвисал на их рисовании.
static func warm(boxes: Array) -> void:
	for n in [32, 96, 256]:
		_disc(n)
	for sb: StyleBoxFlat in boxes:
		_box_entry(sb)


## Закрашенный круг.
static func circle(cv: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.0 or col.a <= 0.0:
		return
	var tex := _disc(32 if r <= 6.0 else (96 if r <= 20.0 else 256))
	cv.draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


static func _disc(n: int) -> Texture2D:
	if _discs.has(n):
		return _discs[n]
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	var r := n * 0.5 - 1.0
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d + 0.5, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_discs[n] = t
	return t


## Дуга (или окружность, если a1 - a0 = TAU) толщиной w; n — число сегментов на полный круг для гладкости.
static func arc(cv: CanvasItem, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
	if col.a <= 0.0 or r <= 0.0:
		return
	var seg := maxi(4, int(ceil(float(n) * absf(a1 - a0) / TAU)))
	var step := (a1 - a0) / float(seg)
	if w <= 4.5:
		var pts := PackedVector2Array()
		pts.resize(seg * 2)
		var p := c + Vector2.from_angle(a0) * r
		for i in seg:
			var q := c + Vector2.from_angle(a0 + step * (i + 1)) * r
			pts[i * 2] = p
			pts[i * 2 + 1] = q
			p = q
		cv.draw_multiline(pts, col, w, true)
		return
	# толстая дуга: полоса четырёхугольников, стыки без щелей
	var r0 := maxf(r - w * 0.5, 0.0)
	var r1 := r + w * 0.5
	var cols := PackedColorArray([col, col, col, col])
	var d0 := Vector2.from_angle(a0)
	for i in seg:
		var d1 := Vector2.from_angle(a0 + step * (i + 1))
		cv.draw_primitive(PackedVector2Array([c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0]), cols, PackedVector2Array())
		d0 = d1


## Ломаная толщиной w.
static func polyline(cv: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() < 2 or col.a <= 0.0:
		return
	var seg := PackedVector2Array()
	seg.resize((pts.size() - 1) * 2)
	for i in pts.size() - 1:
		seg[i * 2] = pts[i]
		seg[i * 2 + 1] = pts[i + 1]
	cv.draw_multiline(seg, col, w, true)


## Закрашенный выпуклый многоугольник (веер от первой точки).
static func polygon(cv: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or col.a <= 0.0:
		return
	var cols := PackedColorArray([col, col, col])
	for i in range(1, pts.size() - 1):
		cv.draw_primitive(PackedVector2Array([pts[0], pts[i], pts[i + 1]]), cols, PackedVector2Array())


## Панель со скруглёнными углами и рамкой по параметрам StyleBoxFlat — девятью кусками одной текстуры.
static func box(cv: CanvasItem, sb: StyleBoxFlat, rect: Rect2) -> void:
	var e := _box_entry(sb)
	var tex: Texture2D = e[0]
	var m: int = e[1]  # поле в пикселях экрана
	var s := float(SS)
	var ms := m * SS
	var tw := tex.get_width()
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	var mw := minf(float(m), rect.size.x * 0.5)
	var mh := minf(float(m), rect.size.y * 0.5)
	var xs := [x0, x0 + mw, x1 - mw, x1]
	var ys := [y0, y0 + mh, y1 - mh, y1]
	var us := [0, ms, tw - ms, tw]
	for j in 3:
		for i in 3:
			var dr := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if dr.size.x <= 0.0 or dr.size.y <= 0.0:
				continue
			cv.draw_texture_rect_region(tex, dr, Rect2(us[i], us[j], us[i + 1] - us[i], us[j + 1] - us[j]))


static func _box_entry(sb: StyleBoxFlat) -> Array:
	var key: String = sb.get_meta("gfx_key", "")
	if key == "":
		key = "%s|%s|%d|%d" % [sb.bg_color.to_html(true), sb.border_color.to_html(true), int(sb.border_width_left), int(sb.corner_radius_top_left)]
		sb.set_meta("gfx_key", key)
	if not _boxes.has(key):
		_boxes[key] = _make_box(sb.bg_color, sb.border_color, int(sb.border_width_left), int(sb.corner_radius_top_left))
	return _boxes[key]


static func _make_box(bg: Color, border: Color, bw: int, rad: int) -> Array:
	var m := maxi(rad, bw) + 1
	var n := (m * 2 + 2) * SS
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n * 0.5
	var r_out := float(rad * SS)
	var r_in := maxf(float(rad - bw) * SS, 0.0)
	var inset := float(bw * SS)
	for y in n:
		for x in n:
			var px := absf(x + 0.5 - half)
			var py := absf(y + 0.5 - half)
			var a_out := _cov(px, py, half, r_out)
			var a_in := _cov(px, py, half - inset, r_in) if bw > 0 else a_out
			var ring := maxf(a_out - a_in, 0.0)
			var a := a_in * bg.a + ring * border.a
			if a <= 0.0001:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rgb := (Vector3(bg.r, bg.g, bg.b) * a_in * bg.a + Vector3(border.r, border.g, border.b) * ring * border.a) / a
			img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, a))
	return [ImageTexture.create_from_image(img), m]


## Покрытие пикселя скруглённым прямоугольником с полуразмером h и радиусом r (px, py — от центра).
static func _cov(px: float, py: float, h: float, r: float) -> float:
	var qx := px - (h - r)
	var qy := py - (h - r)
	var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
	return clampf(0.5 - d, 0.0, 1.0)
