extends RefCounted
## Исторические модели танков по реальным размерам (в метрах, ×UPM в единицы карты).
## Корпус, ходовая и мелкие детали каждого узла сливаются в одну сетку: цвет вершины задаёт
## материал детали (резина, сталь, дерево...), альфа — долю камуфляжной окраски.
## Катки и звёздочки вращаются в вершинном шейдере (UV.x = 1/радиус, UV.y = борт, UV2 = центр).
## Модель смотрит вдоль +X, ось Y — вверх, +Z — правый борт.

const D = preload("res://scripts/data.gd")
const Geo = preload("res://scripts/geo.gd")
const U := D.UPM

# Цвета неокрашенных деталей (альфа 0 — без камуфляжа).
const K := {
	"paint": Color(1, 1, 1, 1), "steel": Color(0.2, 0.2, 0.19, 0), "rubber": Color(0.07, 0.07, 0.065, 0),
	"rust": Color(0.27, 0.17, 0.11, 0), "wood": Color(0.36, 0.27, 0.17, 0), "glass": Color(0.32, 0.36, 0.38, 0),
	"slit": Color(0.03, 0.03, 0.03, 0), "olive": Color(0.25, 0.27, 0.16, 0), "rope": Color(0.3, 0.28, 0.22, 0),
}

const PAINT_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D camo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grime : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.03;
uniform vec4 dust_color : source_color = vec4(0.55, 0.5, 0.4, 1.0);
uniform float dust_amount = 0.6;
uniform float ground_y = 0.0;
uniform float tank_h = 20.0;
uniform float burnt = 0.0;
uniform float travel_l = 0.0;
uniform float travel_r = 0.0;
varying vec3 opos;
varying vec3 onrm;
varying float wy;

vec3 tri3(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void vertex() {
	// катки и звёздочки крутятся вокруг своих осей, пропорционально пройденному гусеницей пути
	if (UV.x > 0.0) {
		float travel = UV.y > 0.0 ? travel_r : travel_l;
		float a = -travel * UV.x;
		float cs = cos(a);
		float sn = sin(a);
		vec2 p = VERTEX.xy - UV2;
		VERTEX.xy = UV2 + vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
		NORMAL.xy = vec2(NORMAL.x * cs - NORMAL.y * sn, NORMAL.x * sn + NORMAL.y * cs);
	}
	opos = VERTEX;
	onrm = NORMAL;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 camo_c = tri3(camo, opos * tex_scale, onrm);
	float g = tri3(grime, opos * tex_scale * 2.7, onrm).r;
	vec3 c = mix(COLOR.rgb, camo_c, COLOR.a);
	// потёки и выцветание
	c *= 0.84 + 0.3 * g;
	// грязь и пыль снизу корпуса, на гусеничных полках
	float h = clamp((wy - ground_y) / tank_h, 0.0, 1.0);
	float dirt = smoothstep(0.5, 0.06, h + (g - 0.5) * 0.3) * dust_amount;
	dirt += smoothstep(0.7, 1.0, onrm.y) * 0.18 * dust_amount;
	c = mix(c, dust_color.rgb * (0.78 + 0.35 * g), clamp(dirt, 0.0, 0.85));
	// обгоревший корпус
	c = mix(c, vec3(0.06, 0.055, 0.05) * (0.5 + g), burnt);
	ALBEDO = c;
	ROUGHNESS = mix(0.68, 0.95, clamp(dirt + burnt, 0.0, 1.0)) - (1.0 - COLOR.a) * 0.15;
	SPECULAR = 0.3;
}
"""

# Размеры в метрах. hull — боковой профиль корпуса (x от кормы -L/2 до носа +L/2, y вверх).
# th — высота верхней ветви гусеницы; tw — ширина гусеницы; up_w — ширина верхнего корпуса;
# wheels — x катков; wr — радиус катка; spr/idl — звёздочка и ленивец [x, y, r];
# rollers — x поддерживающих роликов; tur_x — центр погона; tpoly — башня сверху; tur_h — высота.
const SPECS := {
	"t34": {
		"L": 6.1, "W": 3.0, "tw": 0.5, "th": 0.92, "up_w": 3.0, "camo": "green", "emblem": "ussr",
		"hull": [[-3.05, 0.62], [-2.76, 1.44], [1.6, 1.5], [3.05, 0.76], [2.88, 0.42], [-2.85, 0.42]],
		"wheels": [1.85, 0.88, -0.14, -1.12, -2.08], "wr": 0.415, "wheel": "spoked",
		"spr": [-2.74, 0.6, 0.36], "idl": [2.62, 0.58, 0.33], "rollers": [],
		"tur_x": 0.42, "tpoly": ["oval", 1.02, 1.6, 1.08], "tur_h": 0.86, "tur_top": 0.8, "smooth": true,
		"mant": "cast", "gun_len": 4.3, "gun_r": [0.085, 0.064], "brake": "none",
		"cupola": [-0.85, -0.46, 0.3, 0.3]},
	"tiger": {
		"L": 6.32, "W": 3.56, "tw": 0.725, "th": 0.98, "up_w": 3.42, "camo": "german", "emblem": "germany",
		"hull": [[-3.16, 0.52], [-3.16, 1.76], [2.36, 1.86], [2.36, 1.24], [3.16, 1.12], [3.16, 0.62], [2.92, 0.46], [-2.92, 0.46]],
		"wheels": [2.12, 1.5, 0.88, 0.26, -0.36, -0.98, -1.6, -2.22], "wr": 0.4, "wheel": "interleaved",
		"spr": [2.86, 0.86, 0.42], "idl": [-2.94, 0.84, 0.33], "rollers": [],
		"tur_x": 0.25, "tpoly": ["horseshoe", 0.95, 1.25, 1.12], "tur_h": 0.94, "tur_top": 0.98, "smooth": false,
		"mant": "plate", "gun_len": 4.75, "gun_r": [0.1, 0.075], "brake": "double",
		"cupola": [-0.72, -0.56, 0.37, 0.3]},
	"is2": {
		"L": 6.77, "W": 3.07, "tw": 0.65, "th": 0.86, "up_w": 3.07, "camo": "green", "emblem": "ussr",
		"hull": [[-3.38, 0.6], [-3.2, 1.56], [1.75, 1.62], [3.38, 0.84], [3.12, 0.44], [-3.05, 0.44]],
		"wheels": [2.42, 1.48, 0.54, -0.4, -1.34, -2.28], "wr": 0.28, "wheel": "double",
		"spr": [-3.02, 0.7, 0.34], "idl": [3.02, 0.64, 0.3], "rollers": [1.55, -0.1, -1.75],
		"tur_x": 0.55, "tpoly": ["oval", 1.12, 1.55, 1.2], "tur_h": 0.96, "tur_top": 0.74, "smooth": true,
		"mant": "cast_big", "gun_len": 4.95, "gun_r": [0.11, 0.085], "brake": "double_big",
		"cupola": [-0.78, -0.48, 0.3, 0.32]},
	"pz4": {
		"L": 5.89, "W": 2.88, "tw": 0.4, "th": 0.82, "up_w": 2.88, "camo": "german", "emblem": "germany",
		"hull": [[-2.95, 0.5], [-2.95, 1.55], [1.38, 1.6], [1.42, 1.22], [2.42, 1.14], [2.95, 1.0], [2.95, 0.6], [2.7, 0.4], [-2.75, 0.4]],
		"wheels": [1.98, 1.6, 0.84, 0.46, -0.3, -0.68, -1.44, -1.82], "wr": 0.235, "wheel": "double",
		"spr": [2.56, 0.64, 0.34], "idl": [-2.7, 0.56, 0.3], "rollers": [1.6, 0.4, -0.75, -1.9],
		"tur_x": 0.05, "tpoly": ["pz4", 1.0, 1.0, 1.0], "tur_h": 0.82, "tur_top": 0.86, "smooth": false,
		"mant": "box", "gun_len": 3.75, "gun_r": [0.075, 0.06], "brake": "ball",
		"cupola": [-0.98, 0.0, 0.33, 0.3], "skirts": true},
	"chaffee": {
		"L": 5.03, "W": 2.95, "tw": 0.41, "th": 0.88, "up_w": 2.95, "camo": "olive", "emblem": "usa",
		"hull": [[-2.52, 0.62], [-2.52, 1.58], [0.62, 1.64], [2.52, 0.86], [2.4, 0.5], [-2.32, 0.5]],
		"wheels": [1.62, 0.86, 0.1, -0.66, -1.42], "wr": 0.32, "wheel": "double",
		"spr": [2.2, 0.76, 0.33], "idl": [-2.24, 0.7, 0.3], "rollers": [1.25, -0.05, -1.05],
		"tur_x": 0.32, "tpoly": ["oval", 0.92, 1.08, 0.95], "tur_h": 0.74, "tur_top": 0.8, "smooth": true,
		"mant": "rounded", "gun_len": 2.95, "gun_r": [0.07, 0.056], "brake": "none",
		"cupola": [-0.38, -0.45, 0.26, 0.26]},
}

static var _cache := {}


# ---------- Текстуры ----------

## Камуфляж: однотонный 4БО (СССР), оливковый (США) или тёмно-жёлтый с полосами (Германия).
static func camo_texture(kind: String) -> ImageTexture:
	var key := "camo_" + kind
	if _cache.has(key):
		return _cache[key]
	var S := 256
	var n1 := FastNoiseLite.new()
	n1.seed = 11
	n1.frequency = 0.011
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = 37
	n2.frequency = 0.015
	n2.fractal_octaves = 3
	var n3 := FastNoiseLite.new()
	n3.seed = 5
	n3.frequency = 0.25
	var a := n1.get_seamless_image(S, S)
	var b := n2.get_seamless_image(S, S)
	var g := n3.get_seamless_image(S, S)
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var base := Color("3f4c2b")
	if kind == "olive":
		base = Color("464a2f")
	elif kind == "german":
		base = Color("a8956a")
	for y in S:
		for x in S:
			var va := a.get_pixel(x, y).r
			var vb := b.get_pixel(x, y).r
			var vg := g.get_pixel(x, y).r
			var c := base
			if kind == "german":
				# извилистые полосы оливкового и красно-коричневого, нанесённые пульверизатором
				var s1 := smoothstep(0.075, 0.035, absf(va - 0.5))
				var s2 := smoothstep(0.06, 0.025, absf(vb - 0.44))
				c = c.lerp(Color("4f5935"), s1 * 0.9)
				c = c.lerp(Color("5e3b26"), s2 * 0.85)
			else:
				c = c.darkened((va - 0.5) * 0.22)
				c = c.lightened(clampf((vb - 0.7) * 0.6, 0.0, 0.12))
			c = c.lightened((vg - 0.5) * 0.08)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func grime_texture() -> ImageTexture:
	if _cache.has("grime"):
		return _cache["grime"]
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.04
	n.fractal_octaves = 4
	var img := n.get_seamless_image(256, 256)
	# вертикальные потёки
	var out := Image.create(256, 256, false, Image.FORMAT_L8)
	for x in 256:
		var streak := 0.0
		for y in 256:
			var v := img.get_pixel(x, y).r
			streak = maxf(streak * 0.97, v - 0.55)
			out.set_pixel(x, y, Color(clampf(v - streak * 0.8, 0, 1), 0, 0))
	out.generate_mipmaps()
	var t := ImageTexture.create_from_image(out)
	_cache["grime"] = t
	return t


## Траки: звенья с грунтозацепами, проушинами и блестящими от трения гребнями.
static func track_texture() -> ImageTexture:
	if _cache.has("track"):
		return _cache["track"]
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color("1f1f1c"))
	for x0 in [0, 32]:
		img.fill_rect(Rect2i(x0 + 1, 1, 30, 30), Color("34332e"))
		img.fill_rect(Rect2i(x0 + 4, 2, 6, 28), Color("4d4b43"))
		img.fill_rect(Rect2i(x0 + 5, 2, 2, 28), Color("77736a"))
		img.fill_rect(Rect2i(x0 + 18, 2, 6, 28), Color("4d4b43"))
		img.fill_rect(Rect2i(x0 + 19, 2, 2, 28), Color("77736a"))
		img.fill_rect(Rect2i(x0 + 12, 13, 4, 6), Color("5d5a50"))
		img.fill_rect(Rect2i(x0 + 29, 0, 3, 32), Color("141412"))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["track"] = t
	return t


## Опознавательный знак: красная звезда, белая звезда в круге или балочный крест.
static func emblem_texture(kind: String) -> ImageTexture:
	var key := "em_" + kind
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "germany":
		img.fill_rect(Rect2i(46, 6, 36, 116), Color("ece8dc"))
		img.fill_rect(Rect2i(6, 46, 116, 36), Color("ece8dc"))
		img.fill_rect(Rect2i(53, 13, 22, 102), Color("141414"))
		img.fill_rect(Rect2i(13, 53, 102, 22), Color("141414"))
	else:
		var star := PackedVector2Array()
		for i in 10:
			var r := 60.0 if i % 2 == 0 else 24.0
			var ang := -PI / 2 + TAU * i / 10.0
			star.append(Vector2(64, 67) + Vector2(cos(ang), sin(ang)) * r)
		var col := Color("a8231b") if kind == "ussr" else Color("e8e6dd")
		for y in 128:
			for x in 128:
				var p := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.is_point_in_polygon(p, star):
					img.set_pixel(x, y, col)
				elif kind == "usa":
					var d := (p - Vector2(64, 67)).length()
					if d > 59.0 and d < 64.0:
						img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _blob() -> GradientTexture2D:
	if _cache.has("blob"):
		return _cache["blob"]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.65))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_cache["blob"] = t
	return t


static func paint_material(camo: String) -> ShaderMaterial:
	if not _cache.has("shader"):
		var sh := Shader.new()
		sh.code = PAINT_SHADER
		_cache["shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache["shader"]
	m.set_shader_parameter("camo", camo_texture(camo))
	m.set_shader_parameter("grime", grime_texture())
	return m


# ---------- Построение ----------

## Преобразование: позиция и масштаб в метрах → единицы карты.
static func T3(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale * U), pos * U)


class Builder:
	var g := Geo.Group.new()
	var m: Material

	func _init(mat: Material) -> void:
		m = mat
		g.extra = true

	func put(mesh: Mesh, xf: Transform3D, kind := "paint", flat := false) -> void:
		g.add(mesh, xf, m, flat, K[kind], Vector2.ZERO, Vector2.ZERO)

	## Вращающаяся деталь ходовой: центр (x, y) в метрах, радиус, борт.
	func wheel(mesh: Mesh, xf: Transform3D, kind: String, cx: float, cy: float, r: float, side: float) -> void:
		g.add(mesh, xf, m, false, K[kind], Vector2(cx, cy) * U, Vector2(1.0 / (r * U), side))


static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(p[0], p[1]))
	return out


static func _clip(poly: PackedVector2Array, y0: float, y1: float) -> PackedVector2Array:
	var band := PackedVector2Array([Vector2(-99, y0), Vector2(99, y0), Vector2(99, y1), Vector2(-99, y1)])
	var res := Geometry2D.intersect_polygons(poly, band)
	return res[0] if res.size() > 0 else PackedVector2Array()


static func _turret_poly(spec: Array) -> PackedVector2Array:
	var kind: String = spec[0]
	var f: float = spec[1]
	var b: float = spec[2]
	var hw: float = spec[3]
	match kind:
		"horseshoe":
			var pts := PackedVector2Array([Vector2(f * 0.82, hw)])
			for i in 15:
				var a := PI / 2 + PI * i / 14.0
				pts.append(Vector2(cos(a) * b, sin(a) * hw))
			pts.append(Vector2(f * 0.82, -hw))
			pts.append(Vector2(f, -hw * 0.72))
			pts.append(Vector2(f, hw * 0.72))
			return pts
		"pz4":
			return _pts([[0.88, 0.5], [0.3, 0.86], [-1.18, 0.8], [-1.3, 0.0], [-1.18, -0.8], [0.3, -0.86], [0.88, -0.5]])
	return Geo.oval(f, b, hw, 22)


static func _cyl_x(r1: float, r2: float, l: float, seg := 12) -> Array:
	# цилиндр вдоль оси X (ствол, бочка): сетка и поворот
	return [Geo.cyl(r1, r2, l, seg), Vector3(0, 0, -PI / 2)]


## Строит модель в root. Возвращает узлы корпуса, башни, орудия, материалы и размеры (в единицах).
static func build(root: Node3D, key: String, shadows: bool) -> Dictionary:
	var S: Dictionary = SPECS[key]
	var L: float = S.L
	var W: float = S.W
	var tw: float = S.tw
	var th: float = S.th
	var paint := paint_material(S.camo)
	var hull := Node3D.new()
	root.add_child(hull)
	var hb := Builder.new(paint)

	# --- корпус: низ между гусеницами, верх над гусеницами с наклоном бортов
	var prof := _pts(S.hull)
	var roof := 0.0
	for p in prof:
		roof = maxf(roof, p.y)
	var lower := _clip(prof, -1.0, th + 0.02)
	var upper := _clip(prof, th - 0.04, 9.0)
	var side_k := tan(deg_to_rad(float(D.TYPES[key].side_slope)))
	var up_w: float = S.up_w
	if not lower.is_empty():
		hb.put(Geo.loft(lower, 0.0, W - tw * 2.0 + 0.04, 9.0, W - tw * 2.0 + 0.04), T3(Vector3.ZERO), "paint", true)
	if not upper.is_empty():
		hb.put(Geo.loft(upper, th, up_w, roof, up_w - 2.0 * (roof - th) * side_k), T3(Vector3.ZERO), "paint", true)

	# --- ходовая
	var wr: float = S.wr
	var tz := W / 2 - tw / 2
	var belt_pts := PackedVector2Array()
	var spr: Array = S.spr
	var idl: Array = S.idl
	for s: float in [1.0, -1.0]:
		var z := s * tz
		# катки
		for i in S.wheels.size():
			var x: float = S.wheels[i]
			var cy := wr + 0.04
			match S.wheel:
				"interleaved":
					var zo := s * (tw * 0.22 if i % 2 == 0 else -tw * 0.22)
					_wheel_disc(hb, x, cy, z + zo, wr, tw * 0.3, s, false)
				"spoked":
					_wheel_spoked(hb, x, cy, z, wr, tw * 0.8, s)
				_:
					_wheel_disc(hb, x, cy, z + s * tw * 0.22, wr, tw * 0.3, s, true)
					_wheel_disc(hb, x, cy, z - s * tw * 0.22, wr, tw * 0.3, s, true)
			if s > 0:
				for k in 10:
					var a := TAU * k / 10.0
					belt_pts.append(Vector2(x + cos(a) * (wr + 0.02), cy + sin(a) * (wr + 0.02)))
		# звёздочка (с зубьями) и ленивец
		_sprocket(hb, spr[0], spr[1], z, spr[2], tw * 0.7, s)
		_wheel_disc(hb, idl[0], idl[1], z, idl[2], tw * 0.6, s, false)
		for x in S.rollers:
			var ry := th - 0.12
			hb.wheel(Geo.cyl(0.11, 0.11, tw * 0.5, 10), T3(Vector3(x, ry, z), Vector3(PI / 2, 0, 0)), "rubber", x, ry, 0.11, s)
			if s > 0:
				belt_pts.append(Vector2(x, ry + 0.12))
		# надгусеничная полка
		hb.put(Geo.box(Vector3(L * 0.97, 0.03, tw + 0.08)), T3(Vector3(0, th + 0.05, s * (tz + 0.02))), "paint", true)
	for a in [spr, idl]:
		for k in 12:
			var ang := TAU * k / 12.0
			belt_pts.append(Vector2(a[0] + cos(ang) * (a[2] + 0.03), a[1] + sin(ang) * (a[2] + 0.03)))
	var outline := Geometry2D.convex_hull(belt_pts)
	if outline.size() > 1 and outline[0] == outline[outline.size() - 1]:
		outline.remove_at(outline.size() - 1)
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(p * U)
	var trk_l := _track_mat()
	var trk_r := _track_mat()
	var tg := Geo.Group.new()
	tg.add(Geo.belt(scaled, tw * U, 0.09 * U, 0.24 * U), Transform3D(Basis.IDENTITY, Vector3(0, 0, tz * U)), trk_r)
	tg.add(Geo.belt(scaled, tw * U, 0.09 * U, 0.24 * U), Transform3D(Basis.IDENTITY, Vector3(0, 0, -tz * U)), trk_l)
	tg.commit(hull, shadows)

	# --- детали корпуса
	_hull_details(hb, key, S, roof)
	hb.g.commit(hull, shadows)

	# опознавательные знаки на бортах корпуса (Германия, США)
	if S.emblem != "ussr":
		_emblems(hull, S.emblem, Vector3(-L * 0.08, roof * 0.72, up_w / 2 + 0.02), 0.7, 0.0)

	# пятно тени под танком
	var blob := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(L * 1.25, W * 1.35) * U
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = _blob()
	bm.disable_receive_shadows = true
	blob.mesh = bq
	blob.material_override = bm
	blob.rotation = Vector3(-PI / 2, 0, 0)
	blob.position.y = 0.05 * U
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.add_child(blob)

	# --- башня
	var tur := Node3D.new()
	tur.position = Vector3(float(S.tur_x), roof - 0.02, 0) * U
	hull.add_child(tur)
	var tb := Builder.new(paint)
	var tpoly := _turret_poly(S.tpoly)
	var tur_h: float = S.tur_h
	tb.put(Geo.frustum(tpoly, tur_h, S.tur_top, 0.0, S.smooth), T3(Vector3.ZERO), "paint", not S.smooth)
	var front: float = S.tpoly[1]
	var gun_y := tur_h * 0.46
	var trunnion := Vector3(front * 0.9, gun_y, 0)
	_turret_details(tb, key, S, front, tur_h)
	tb.g.commit(tur, shadows)
	if S.emblem == "ussr":
		var hw: float = S.tpoly[3]
		var tilt := atan2(hw * (1.0 - float(S.tur_top)), tur_h)
		_emblems(tur, "ussr", Vector3(-0.2, tur_h * 0.5, hw * (1.0 + float(S.tur_top)) / 2.0 + 0.03), 0.55, tilt)

	# --- орудие на оси возвышения
	var gun := Node3D.new()
	gun.position = trunnion * U
	tur.add_child(gun)
	var gb := Builder.new(paint)
	var glen: float = S.gun_len
	var gr: Array = S.gun_r
	var c := _cyl_x(gr[1], gr[0], glen, 14)
	gb.put(c[0], T3(Vector3(glen / 2, 0, 0), c[1]), "paint")
	match S.brake:
		"double", "double_big":
			var big := 1.25 if S.brake == "double_big" else 1.0
			var r: float = float(gr[1]) * 1.9 * big
			var bl := 0.5 * big
			var cb := _cyl_x(r, r, bl, 14)
			gb.put(cb[0], T3(Vector3(glen + bl / 2 - 0.05, 0, 0), cb[1]), "paint")
			gb.put(Geo.box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + 0.06, 0, 0)), "paint", true)
			gb.put(Geo.box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + bl - 0.1, 0, 0)), "paint", true)
			gb.put(Geo.box(Vector3(bl * 0.7, r * 1.0, r * 2.95)), T3(Vector3(glen + bl / 2, 0, 0)), "slit", true)
		"ball":
			gb.put(Geo.sphere(14, 8), T3(Vector3(glen + 0.12, 0, 0), Vector3.ZERO, Vector3(0.42, float(gr[1]) * 3.2, float(gr[1]) * 3.2)), "paint")
			gb.put(Geo.box(Vector3(0.16, float(gr[1]) * 2.2, float(gr[1]) * 3.4)), T3(Vector3(glen + 0.12, 0, 0)), "slit", true)
		_:
			var cm := _cyl_x(float(gr[1]) * 1.25, float(gr[1]) * 1.25, 0.18, 14)
			gb.put(cm[0], T3(Vector3(glen - 0.09, 0, 0), cm[1]), "paint")
	# дульный срез
	var hole := _cyl_x(float(gr[1]) * 0.55, float(gr[1]) * 0.55, 0.02, 10)
	var tip := glen + (0.5 if S.brake.begins_with("double") else 0.0)
	gb.put(hole[0], T3(Vector3(tip + 0.005, 0, 0), hole[1]), "slit")
	gb.g.commit(gun, shadows)

	return {"hull": hull, "tur": tur, "gun": gun, "barrel": tip * U, "paint": paint, "tracks": [trk_l, trk_r],
		"hh": roof * U, "tur_h": tur_h * U, "tz": float(S.tpoly[3]) * U, "tur_f": front * U,
		"tur_b": float(S.tpoly[2]) * U, "height": (roof + tur_h + 0.3) * U, "th": th * U}


static func _track_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = track_texture()
	m.roughness = 0.75
	m.metallic = 0.45
	return m


## Каток со сплошным диском: резиновый бандаж, окрашенный диск, ступица и болты.
static func _wheel_disc(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float, rubber: bool) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r, r, w, 18), T3(Vector3(x, y, z), rot), "rubber" if rubber else "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.82, r * 0.86, w * 1.08, 18), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.3, r * 0.34, w * 1.25, 12), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 6:
		var a := TAU * k / 6.0
		var bx := x + cos(a) * r * 0.5
		var by := y + sin(a) * r * 0.5
		b.wheel(Geo.cyl(r * 0.06, r * 0.06, w * 1.16, 6), T3(Vector3(bx, by, z), rot), "steel", x, y, r, s)


## Каток Т-34: большой, с резиновым бандажом и облегчающими отверстиями-спицами.
static func _wheel_spoked(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r, r, w, 22), T3(Vector3(x, y, z), rot), "rubber", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.84, r * 0.84, w * 1.06, 22), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.26, r * 0.3, w * 1.2, 12), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 8:
		var a := TAU * k / 8.0
		b.wheel(Geo.cyl(r * 0.13, r * 0.13, w * 1.12, 8), T3(Vector3(x + cos(a) * r * 0.56, y + sin(a) * r * 0.56, z), rot), "slit", x, y, r, s)


## Ведущая звёздочка с зубьями.
static func _sprocket(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r * 0.85, r * 0.85, w, 16), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.35, r * 0.4, w * 1.3, 10), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 12:
		var a := TAU * k / 12.0
		var tp := Vector3(x + cos(a) * r * 0.92, y + sin(a) * r * 0.92, z)
		b.wheel(Geo.box(Vector3(0.09, 0.07, w * 0.9)), T3(tp, Vector3(0, 0, a)), "steel", x, y, r, s)


## Точка на линии профиля между двумя вершинами (для деталей на наклонных листах).
static func _on_edge(prof: Array, i: int, t: float) -> Array:
	var a := Vector2(prof[i][0], prof[i][1])
	var b := Vector2(prof[i + 1][0], prof[i + 1][1])
	var p := a.lerp(b, t)
	return [p, atan2(b.y - a.y, b.x - a.x)]


static func _hull_details(b: Builder, key: String, S: Dictionary, roof: float) -> void:
	var L: float = S.L
	var W: float = S.W
	var up_w: float = S.up_w
	var prof: Array = S.hull
	match key:
		"t34":
			# люк механика-водителя и шаровая установка пулемёта на лобовом листе
			var e := _on_edge(prof, 2, 0.45)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.5, 0.08, 0.6)), T3(Vector3(p.x, p.y + 0.03, -0.55), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.12, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.06, -0.55), Vector3(0, 0, e[1])), "slit", true)
			var e2 := _on_edge(prof, 2, 0.5)
			var p2: Vector2 = e2[0]
			b.put(Geo.sphere(12, 8), T3(Vector3(p2.x, p2.y, 0.62), Vector3.ZERO, Vector3(0.32, 0.32, 0.32)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.4, 6)
			b.put(mg[0], T3(Vector3(p2.x + 0.25, p2.y - 0.1, 0.62), mg[1] + Vector3(0, 0, -0.3)), "steel")
			# фара, буксирные крюки
			b.put(Geo.cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.55, 1.0, -1.15), Vector3(0, 0, -PI / 2)), "glass")
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.18, 0.1, 0.08)), T3(Vector3(3.08, 0.55, s * 0.9)), "steel", true)
			# бочки с топливом на корме и выхлопные трубы
			for s: float in [1.0, -1.0]:
				var drum := _cyl_x(0.3, 0.3, 0.95, 14)
				b.put(drum[0], T3(Vector3(-2.15, 1.38, s * 1.22), drum[1]), "paint")
				b.put(Geo.box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-1.75, 1.38, s * 1.22)), "steel", true)
				b.put(Geo.box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-2.55, 1.38, s * 1.22)), "steel", true)
				var ex := _cyl_x(0.09, 0.09, 0.3, 8)
				b.put(ex[0], T3(Vector3(-3.05, 0.95, s * 0.55), ex[1]), "rust")
			# запасные траки на лобовом листе
			for k in 3:
				var ek := _on_edge(prof, 2, 0.72 + k * 0.08)
				var pk: Vector2 = ek[0]
				b.put(Geo.box(Vector3(0.2, 0.05, 0.5)), T3(Vector3(pk.x, pk.y + 0.03, 0.55), Vector3(0, 0, ek[1])), "steel", true)
			# решётки моторного отделения
			b.put(Geo.box(Vector3(1.1, 0.04, 1.2)), T3(Vector3(-1.9, 1.47, 0)), "slit", true)
			for k in 6:
				b.put(Geo.box(Vector3(1.1, 0.05, 0.06)), T3(Vector3(-1.9, 1.49, -0.5 + k * 0.2)), "paint", true)
		"tiger":
			# смотровой прибор механика и курсовой пулемёт на вертикальном лобовом листе
			b.put(Geo.box(Vector3(0.14, 0.18, 0.55)), T3(Vector3(2.4, 1.6, -0.75)), "paint", true)
			b.put(Geo.box(Vector3(0.05, 0.05, 0.4)), T3(Vector3(2.48, 1.6, -0.75)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(2.38, 1.55, 0.78), Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.35, 6)
			b.put(mg[0], T3(Vector3(2.6, 1.55, 0.78), mg[1]), "steel")
			# фары «Бош», передние крылья, буксирные тросы вдоль бортов
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.1, 0.12, 0.2, 10), T3(Vector3(2.3, 1.95, s * 1.45), Vector3(0, 0, -PI / 2)), "paint")
				b.put(Geo.box(Vector3(0.55, 0.03, 0.72)), T3(Vector3(3.3, 1.07, s * (1.78 - 0.36)), Vector3(0, 0, -0.25)), "paint", true)
				var rope := _cyl_x(0.03, 0.03, 4.2, 6)
				b.put(rope[0], T3(Vector3(-0.3, 1.45, s * 1.73), rope[1]), "rope")
				# выхлопные трубы с кожухами
				b.put(Geo.cyl(0.08, 0.08, 0.75, 10), T3(Vector3(-3.25, 1.75, s * 0.45)), "rust")
				b.put(Geo.cyl(0.13, 0.13, 0.5, 10), T3(Vector3(-3.25, 1.62, s * 0.45)), "paint")
				# воздухозаборники на корме
				b.put(Geo.cyl(0.32, 0.32, 0.06, 14), T3(Vector3(-2.2, 1.78, s * 0.9)), "paint")
			# решётки моторного отделения и инструмент
			b.put(Geo.box(Vector3(1.2, 0.04, 1.0)), T3(Vector3(-2.2, 1.79, 0)), "slit", true)
			b.put(Geo.box(Vector3(1.6, 0.06, 0.12)), T3(Vector3(-0.5, 1.88, 1.4)), "wood", true)
			b.put(Geo.box(Vector3(1.2, 0.06, 0.1)), T3(Vector3(-0.4, 1.88, -1.45)), "wood", true)
		"is2":
			var e := _on_edge(prof, 2, 0.4)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.45, 0.1, 0.55)), T3(Vector3(p.x, p.y + 0.04, 0), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.1, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.08, 0), Vector3(0, 0, e[1])), "slit", true)
			b.put(Geo.cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.8, 1.2, -1.15), Vector3(0, 0, -PI / 2)), "glass")
			for s: float in [1.0, -1.0]:
				# наружные топливные баки на кормовых полках
				b.put(Geo.box(Vector3(1.15, 0.45, 0.42)), T3(Vector3(-1.9, th_top(S) + 0.25, s * (up_w / 2 - 0.22))), "paint", true)
				b.put(Geo.box(Vector3(1.0, 0.47, 0.06)), T3(Vector3(-1.9, th_top(S) + 0.25, s * (up_w / 2 - 0.05))), "steel", true)
				var ex := _cyl_x(0.1, 0.1, 0.3, 8)
				b.put(ex[0], T3(Vector3(-3.3, 1.1, s * 0.6), ex[1]), "rust")
				var rope := _cyl_x(0.03, 0.03, 3.6, 6)
				b.put(rope[0], T3(Vector3(0.2, 1.52, s * 1.5), rope[1]), "rope")
			for k in 3:
				var ek := _on_edge(prof, 2, 0.62 + k * 0.1)
				var pk: Vector2 = ek[0]
				b.put(Geo.box(Vector3(0.18, 0.05, 0.6)), T3(Vector3(pk.x, pk.y + 0.03, 0.9), Vector3(0, 0, ek[1])), "steel", true)
			b.put(Geo.box(Vector3(1.4, 0.04, 1.4)), T3(Vector3(-2.2, 1.6, 0)), "slit", true)
			for k in 7:
				b.put(Geo.box(Vector3(1.4, 0.05, 0.07)), T3(Vector3(-2.2, 1.62, -0.6 + k * 0.2)), "paint", true)
		"pz4":
			# смотровой прибор механика, курсовой пулемёт
			b.put(Geo.box(Vector3(0.12, 0.16, 0.42)), T3(Vector3(1.42, 1.45, -0.62)), "paint", true)
			b.put(Geo.box(Vector3(0.04, 0.04, 0.32)), T3(Vector3(1.48, 1.45, -0.62)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(1.42, 1.4, 0.55), Vector3.ZERO, Vector3(0.26, 0.26, 0.26)), "paint")
			# запасные катки на лобовом листе и траки на носу
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.235, 0.235, 0.1, 16), T3(Vector3(2.62, 1.12, s * 0.8), Vector3(0, 0, -0.25)), "rubber")
				b.put(Geo.cyl(0.19, 0.19, 0.12, 16), T3(Vector3(2.63, 1.13, s * 0.8), Vector3(0, 0, -0.25)), "paint")
				b.put(Geo.cyl(0.07, 0.07, 0.6, 8), T3(Vector3(-3.0, 0.95, s * 0.5), Vector3(0, 0, PI / 2)), "rust")
			for k in 5:
				b.put(Geo.box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, -0.6 + (k % 2) * 0.05)), "steel", true)
				b.put(Geo.box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, 0.6 - (k % 2) * 0.05)), "steel", true)
			# бортовые экраны «шюрцен» на кронштейнах
			for s: float in [1.0, -1.0]:
				var rail := _cyl_x(0.025, 0.025, 4.6, 6)
				b.put(rail[0], T3(Vector3(-0.1, 1.48, s * (W / 2 + 0.16)), rail[1]), "steel")
				for k in 5:
					var px := -2.15 + k * 0.98
					b.put(Geo.box(Vector3(0.94, 0.95, 0.03)), T3(Vector3(px, 1.0, s * (W / 2 + 0.18)), Vector3(0.03 * s, 0, 0.01 * (k - 2))), "paint", true)
			b.put(Geo.box(Vector3(1.0, 0.04, 1.1)), T3(Vector3(-2.2, 1.57, 0)), "slit", true)
		"chaffee":
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.08, 0.08, 0.12, 10), T3(Vector3(2.3, 1.02, s * 1.1), Vector3(0, 0, -PI / 2 - 0.5)), "glass")
				b.put(Geo.box(Vector3(0.9, 0.35, 0.3)), T3(Vector3(-1.3, 1.08, s * (W / 2 - 0.15))), "paint", true)
				var muf := _cyl_x(0.11, 0.11, 0.6, 10)
				b.put(muf[0], T3(Vector3(-2.65, 0.95, s * 0.6), muf[1] + Vector3(PI / 2, 0, 0)), "rust")
			var e := _on_edge(prof, 2, 0.3)
			var p: Vector2 = e[0]
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.5, 0.06, 0.5)), T3(Vector3(p.x, p.y + 0.03, s * 0.55), Vector3(0, 0, e[1])), "paint", true)
			# большие решётки моторного отделения
			b.put(Geo.box(Vector3(1.6, 0.04, 1.6)), T3(Vector3(-1.6, 1.6, 0)), "slit", true)
			for k in 9:
				b.put(Geo.box(Vector3(1.6, 0.05, 0.06)), T3(Vector3(-1.6, 1.62, -0.75 + k * 0.19)), "paint", true)


static func th_top(S: Dictionary) -> float:
	return float(S.th) + 0.06


static func _turret_details(b: Builder, key: String, S: Dictionary, front: float, h: float) -> void:
	var hw: float = S.tpoly[3]
	var back: float = S.tpoly[2]
	var top: float = S.tur_top
	# маска орудия
	match S.mant:
		"cast":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.9, h * 0.46, 0), Vector3.ZERO, Vector3(0.5, 0.6, 0.95)), "paint")
			b.put(Geo.box(Vector3(0.4, 0.5, 0.82)), T3(Vector3(front * 0.82, h * 0.46, 0)), "paint")
		"cast_big":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.92, h * 0.46, 0), Vector3.ZERO, Vector3(0.62, 0.66, 1.15)), "paint")
			b.put(Geo.box(Vector3(0.5, 0.58, 1.0)), T3(Vector3(front * 0.82, h * 0.46, 0)), "paint")
		"plate":
			b.put(Geo.box(Vector3(0.26, 0.78, 1.55)), T3(Vector3(front + 0.12, h * 0.46, 0)), "paint", true)
			b.put(Geo.cyl(0.18, 0.18, 0.4, 12), T3(Vector3(front + 0.4, h * 0.46, 0), Vector3(0, 0, -PI / 2)), "paint")
			# смотровой прибор и спаренный пулемёт в маске
			b.put(Geo.box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, h * 0.6, -0.35)), "slit", true)
			b.put(Geo.box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, h * 0.4, 0.38)), "slit", true)
		"box":
			b.put(Geo.box(Vector3(0.3, 0.48, 0.62)), T3(Vector3(front + 0.1, h * 0.46, 0)), "paint", true)
			b.put(Geo.cyl(0.13, 0.15, 0.35, 12), T3(Vector3(front + 0.35, h * 0.46, 0), Vector3(0, 0, -PI / 2)), "paint")
		"rounded":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.92, h * 0.46, 0), Vector3.ZERO, Vector3(0.4, 0.5, 0.8)), "paint")
	# командирская башенка со смотровыми щелями и открытым люком
	var cp: Array = S.cupola
	var cx: float = cp[0]
	var cz: float = cp[1]
	var cr: float = cp[2]
	var ch: float = cp[3]
	b.put(Geo.cyl(cr, cr * 1.05, ch, 16), T3(Vector3(cx, h * top + ch / 2 - 0.02, cz)), "paint")
	b.put(Geo.cyl(cr * 1.01, cr * 1.01, 0.05, 16), T3(Vector3(cx, h * top + ch * 0.55, cz)), "slit")
	b.put(Geo.cyl(cr * 0.88, cr * 0.92, 0.07, 16), T3(Vector3(cx, h * top + ch + 0.01, cz)), "paint")
	b.put(Geo.box(Vector3(0.1, 0.05, 0.04)), T3(Vector3(cx + cr * 0.4, h * top + ch + 0.06, cz)), "steel", true)
	# люк заряжающего
	b.put(Geo.box(Vector3(0.5, 0.05, 0.45)), T3(Vector3(-0.1, h * top + 0.02, -cz * 0.9 if cz != 0.0 else 0.4)), "paint", true)
	match key:
		"t34":
			for s: float in [1.0, -1.0]:
				# поручни и перископы
				var rail := _cyl_x(0.02, 0.02, 1.1, 6)
				b.put(rail[0], T3(Vector3(-0.35, h * 0.7, s * (hw * 0.93 + 0.04)), rail[1]), "steel")
				b.put(Geo.box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.25, h * top + 0.05, s * 0.45)), "paint", true)
			# грибки вентиляторов
			for z: float in [-0.25, 0.25]:
				b.put(Geo.sphere(12, 6), T3(Vector3(-1.05, h * top, z), Vector3.ZERO, Vector3(0.32, 0.18, 0.32)), "paint")
		"tiger":
			for s: float in [1.0, -1.0]:
				# дымовые мортирки по три на борт
				for k in 3:
					b.put(Geo.cyl(0.05, 0.05, 0.22, 8), T3(Vector3(front * 0.55 - k * 0.12, h * 0.78, s * (hw + 0.05)), Vector3(s * 0.7, 0, 0)), "paint")
				# запасные траки на бортах башни
				for k in 3:
					b.put(Geo.box(Vector3(0.16, 0.36, 0.035)), T3(Vector3(-0.25 - k * 0.2, h * 0.42, s * (hw + 0.02))), "steel", true)
			# ящик «Роммеля» на корме башни
			b.put(Geo.box(Vector3(0.5, 0.45, 1.2)), T3(Vector3(-back - 0.18, h * 0.5, 0)), "paint", true)
		"is2":
			# ДШК на командирской башенке, кормовой пулемёт, поручни
			var dshk := _cyl_x(0.03, 0.03, 1.4, 6)
			b.put(dshk[0], T3(Vector3(cx + 0.6, h * top + ch + 0.35, cz), dshk[1] + Vector3(0, 0, 0.1)), "steel")
			b.put(Geo.box(Vector3(0.2, 0.18, 0.12)), T3(Vector3(cx, h * top + ch + 0.25, cz)), "steel", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(-back * 0.98, h * 0.48, 0), Vector3.ZERO, Vector3(0.28, 0.28, 0.28)), "paint")
			for s: float in [1.0, -1.0]:
				var rail := _cyl_x(0.02, 0.02, 1.3, 6)
				b.put(rail[0], T3(Vector3(-0.3, h * 0.72, s * (hw * 0.86 + 0.05)), rail[1]), "steel")
		"pz4":
			# экраны вокруг башни
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(1.55, 0.66, 0.03)), T3(Vector3(-0.35, h * 0.5, s * (hw + 0.24)), Vector3(0, 0, 0)), "paint", true)
				b.put(Geo.box(Vector3(0.12, 0.04, 0.24)), T3(Vector3(-0.35, h * 0.75, s * (hw + 0.12))), "steel", true)
				b.put(Geo.box(Vector3(0.45, 0.4, 0.05)), T3(Vector3(-0.1, h * 0.45, s * 0.84)), "paint", true)
			b.put(Geo.box(Vector3(0.03, 0.66, 1.9)), T3(Vector3(-1.52, h * 0.5, 0)), "paint", true)
		"chaffee":
			# крупнокалиберный пулемёт на турели в корме крыши
			var m2 := _cyl_x(0.03, 0.03, 1.5, 6)
			b.put(m2[0], T3(Vector3(-0.55, h * top + 0.55, 0.35), m2[1] + Vector3(0, 0, 0.08)), "steel")
			b.put(Geo.box(Vector3(0.28, 0.15, 0.12)), T3(Vector3(-0.85, h * top + 0.48, 0.35)), "steel", true)
			b.put(Geo.cyl(0.03, 0.03, 0.45, 6), T3(Vector3(-0.85, h * top + 0.22, 0.35)), "steel")
			b.put(Geo.box(Vector3(0.12, 0.1, 0.12)), T3(Vector3(0.3, h * top + 0.05, 0.4)), "paint", true)


static func _emblems(parent: Node3D, kind: String, pos: Vector3, size: float, tilt: float) -> void:
	var em := StandardMaterial3D.new()
	em.albedo_texture = emblem_texture(kind)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	em.roughness = 0.8
	var g := Geo.Group.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size) * U
	for s: float in [1.0, -1.0]:
		var bs := Basis(Vector3.RIGHT, -tilt) if s > 0 else Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -tilt)
		g.add(q, Transform3D(bs, Vector3(pos.x, pos.y, s * pos.z) * U), em)
	g.commit(parent, false)
