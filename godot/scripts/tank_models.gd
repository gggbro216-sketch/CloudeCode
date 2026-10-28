extends RefCounted
## Исторические модели танков из процедурной геометрии: силуэт корпуса и башни,
## ходовая с катками и лентами траков, характерные детали, камуфляж и опознавательные знаки.
## Модель смотрит вдоль +X, ось Y — вверх, Z — борт.

const D = preload("res://scripts/data.gd")
const Geo = preload("res://scripts/geo.gd")

# hh — высота корпуса в долях ширины; hull — боковой профиль (x: доля длины, y: доля высоты корпуса).
# wr — радиус катка в долях высоты корпуса; tur_* — башня: ширина, вынос вперёд/назад, высота, сужение.
const SPECS := {
	"chaffee": {"hh": 0.44, "hull": [[-0.5, 0.3], [-0.49, 0.9], [0.08, 1.0], [0.5, 0.42], [0.47, 0.2], [-0.46, 0.2]],
		"wheels": 5, "wr": 0.24, "inter": false, "rollers": 3, "camo": "olive", "emblem": "usa",
		"tur": "round", "tur_w": 0.33, "tur_f": 1.0, "tur_b": 1.15, "tur_h": 0.22, "tur_top": 0.8, "tur_x": 0.05,
		"gun": 0.66, "gun_r": 0.032, "brake": "none", "mant": "box"},
	"t34": {"hh": 0.47, "hull": [[-0.5, 0.25], [-0.47, 0.78], [-0.4, 1.0], [0.2, 1.0], [0.5, 0.32], [0.47, 0.16], [-0.45, 0.16]],
		"wheels": 5, "wr": 0.3, "inter": false, "rollers": 0, "camo": "green", "emblem": "ussr",
		"tur": "round", "tur_w": 0.35, "tur_f": 0.95, "tur_b": 1.35, "tur_h": 0.25, "tur_top": 0.78, "tur_x": 0.1,
		"gun": 0.74, "gun_r": 0.04, "brake": "none", "mant": "round"},
	"pz4": {"hh": 0.46, "hull": [[-0.5, 0.22], [-0.5, 0.92], [0.27, 0.95], [0.34, 0.95], [0.4, 0.68], [0.5, 0.6], [0.5, 0.26], [0.45, 0.16], [-0.45, 0.16]],
		"wheels": 8, "wr": 0.19, "inter": false, "rollers": 4, "camo": "german", "emblem": "germany",
		"tur": "pz4", "tur_w": 0.31, "tur_f": 1.0, "tur_b": 1.0, "tur_h": 0.25, "tur_top": 0.82, "tur_x": 0.02,
		"gun": 0.74, "gun_r": 0.03, "brake": "ball", "mant": "box", "skirts": true},
	"tiger": {"hh": 0.43, "hull": [[-0.5, 0.18], [-0.5, 0.97], [0.4, 1.0], [0.44, 0.86], [0.5, 0.8], [0.5, 0.26], [0.45, 0.14], [-0.45, 0.14]],
		"wheels": 8, "wr": 0.33, "inter": true, "rollers": 0, "camo": "german", "emblem": "germany",
		"tur": "tiger", "tur_w": 0.34, "tur_f": 1.0, "tur_b": 1.0, "tur_h": 0.24, "tur_top": 0.97, "tur_x": 0.0,
		"gun": 0.8, "gun_r": 0.034, "brake": "double", "mant": "tiger"},
	"is2": {"hh": 0.44, "hull": [[-0.5, 0.2], [-0.47, 0.95], [0.18, 1.0], [0.36, 0.84], [0.5, 0.55], [0.5, 0.3], [0.45, 0.14], [-0.45, 0.14]],
		"wheels": 6, "wr": 0.24, "inter": false, "rollers": 3, "camo": "green", "emblem": "ussr",
		"tur": "is2", "tur_w": 0.36, "tur_f": 0.9, "tur_b": 1.3, "tur_h": 0.27, "tur_top": 0.72, "tur_x": 0.06,
		"gun": 0.76, "gun_r": 0.04, "brake": "double", "mant": "round_big"},
}

static var _tex := {}


static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Камуфляж: однотонный 4БО (СССР), оливковый (США) или тёмно-жёлтый с пятнами (Германия).
static func camo_texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var n1 := FastNoiseLite.new()
	n1.seed = 11
	n1.frequency = 0.03
	var n2 := FastNoiseLite.new()
	n2.seed = 37
	n2.frequency = 0.05
	n2.fractal_octaves = 2
	var grain := FastNoiseLite.new()
	grain.seed = 5
	grain.frequency = 0.35
	var a := n1.get_seamless_image(128, 128)
	var b := n2.get_seamless_image(128, 128)
	var g := grain.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var base := Color("4b5a33")
	if kind == "olive":
		base = Color("515636")
	elif kind == "german":
		base = Color("b09a62")
	for y in 128:
		for x in 128:
			var va := a.get_pixel(x, y).r
			var vb := b.get_pixel(x, y).r
			var vg := g.get_pixel(x, y).r
			var c := base
			if kind == "german":
				# извилистые полосы оливкового и красно-коричневого
				var s1 := smoothstep(0.08, 0.0, absf(va - 0.5))
				var s2 := smoothstep(0.06, 0.0, absf(vb - 0.45))
				c = c.lerp(Color("5c6436"), s1 * 0.95)
				c = c.lerp(Color("6b4329"), s2 * 0.9)
			else:
				c = c.darkened((va - 0.5) * 0.25)
			# грязь и потёртости
			c = c.darkened(clampf((vb - 0.62) * 1.2, 0.0, 0.25))
			c = c.lightened((vg - 0.5) * 0.12)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func track_texture() -> ImageTexture:
	if _tex.has("track"):
		return _tex["track"]
	var img := Image.create(32, 16, false, Image.FORMAT_RGB8)
	img.fill(Color("2b2b27"))
	img.fill_rect(Rect2i(0, 0, 32, 16), Color("2b2b27"))
	for x in [2, 18]:
		img.fill_rect(Rect2i(x, 1, 5, 14), Color("4a4a42"))
		img.fill_rect(Rect2i(x + 1, 1, 2, 14), Color("5c5b52"))
	img.fill_rect(Rect2i(0, 7, 32, 2), Color("1c1c19"))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["track"] = t
	return t


## Опознавательный знак: красная звезда, белая звезда или балочный крест.
static func emblem_texture(kind: String) -> ImageTexture:
	var key := "em_" + kind
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "germany":
		img.fill_rect(Rect2i(24, 4, 16, 56), Color.WHITE)
		img.fill_rect(Rect2i(4, 24, 56, 16), Color.WHITE)
		img.fill_rect(Rect2i(27, 7, 10, 50), Color("151515"))
		img.fill_rect(Rect2i(7, 27, 50, 10), Color("151515"))
	else:
		var star := PackedVector2Array()
		for i in 10:
			var r := 30.0 if i % 2 == 0 else 12.0
			var ang := -PI / 2 + TAU * i / 10.0
			star.append(Vector2(32, 33) + Vector2(cos(ang), sin(ang)) * r)
		var col := Color("b3261e") if kind == "ussr" else Color("eeeeea")
		for y in 64:
			for x in 64:
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), star):
					img.set_pixel(x, y, col)
		if kind == "usa":
			# белая звезда в круге
			for y in 64:
				for x in 64:
					var d := Vector2(x - 32, y - 33).length()
					if d > 30.0 and d < 32.5:
						img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func _paint(kind: String) -> StandardMaterial3D:
	var m := _mat(Color.WHITE, 0.82)
	m.albedo_texture = camo_texture(kind)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.035, 0.035, 0.035)
	return m


static func _track_mat() -> StandardMaterial3D:
	var m := _mat(Color.WHITE, 0.9)
	m.albedo_texture = track_texture()
	m.metallic = 0.3
	return m


static func _blob() -> GradientTexture2D:
	if _tex.has("blob"):
		return _tex["blob"]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.6))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_tex["blob"] = t
	return t


static func _poly(pts: Array, sx: float, sy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0] * sx, p[1] * sy))
	return out


static func _clip(poly: PackedVector2Array, y0: float, y1: float) -> PackedVector2Array:
	var band := PackedVector2Array([Vector2(-999, y0), Vector2(999, y0), Vector2(999, y1), Vector2(-999, y1)])
	var res := Geometry2D.intersect_polygons(poly, band)
	return res[0] if res.size() > 0 else PackedVector2Array()


static func _turret_poly(style: String, tz: float, f: float, b: float) -> PackedVector2Array:
	match style:
		"tiger":
			var pts := PackedVector2Array([Vector2(tz * 0.72, tz * 0.95)])
			for i in 13:
				var a := PI / 2 + PI * i / 12.0
				pts.append(Vector2(-tz * 0.1 + cos(a) * tz * 1.1, sin(a) * tz * 0.98))
			pts.append(Vector2(tz * 0.72, -tz * 0.95))
			return pts
		"pz4":
			return _poly([[0.6, 0.5], [0.15, 0.95], [-0.95, 0.85], [-1.08, 0.0], [-0.95, -0.85], [0.15, -0.95], [0.6, -0.5]], tz, tz)
	return Geo.oval(tz * f, tz * b, tz, 18)


## Собирает модель в root. Возвращает узлы корпуса, башни и орудия, материалы и размеры.
static func build(root: Node3D, key: String, shadows: bool) -> Dictionary:
	var T: Dictionary = D.TYPES[key]
	var S: Dictionary = SPECS[key]
	var L: float = T.L
	var W: float = T.W
	var hh: float = W * float(S.hh)
	var tw := W * 0.22
	var th := hh * 0.6
	var paint := _paint(S.camo)
	var steel := _mat(Color("3d3f37"), 0.55)
	steel.metallic = 0.4
	var dark := _mat(Color("25261f"), 0.9)
	var rubber := _mat(Color("1b1b18"), 0.95)
	var trk_l := _track_mat()
	var trk_r := _track_mat()
	var em := _mat(Color.WHITE, 0.8)
	em.albedo_texture = emblem_texture(S.emblem)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR

	var hull := Node3D.new()
	root.add_child(hull)
	var g := Geo.Group.new()

	# корпус: верх над гусеницами во всю ширину, низ между гусеницами
	var prof := _poly(S.hull, L, hh)
	var upper := _clip(prof, th * 0.92, hh * 2.0)
	var lower := _clip(prof, -1.0, th * 0.95)
	if not upper.is_empty():
		g.add(Geo.prism(upper, W * 0.96), Transform3D.IDENTITY, paint)
	if not lower.is_empty():
		g.add(Geo.prism(lower, W - tw * 2.0 + 0.6), Transform3D.IDENTITY, paint)
	# надгусеничные полки
	for s: float in [1.0, -1.0]:
		g.add(Geo.box(Vector3(L * 0.98, 0.7, tw + 0.6)), Geo.xf(Vector3(0, th + 0.2, s * (W / 2 - tw / 2))), paint)

	# ходовая: катки, ленивец, звёздочка, поддерживающие катки, лента
	var wr: float = hh * float(S.wr)
	var n: int = S.wheels
	var wheel := Geo.cyl(wr, wr, tw * 0.78, 14)
	var hub := Geo.cyl(wr * 0.45, wr * 0.45, tw * 0.84, 10)
	var x0 := -L / 2 + wr + 5.0
	var x1 := L / 2 - wr - 5.0
	for s: float in [1.0, -1.0]:
		var zc := s * (W / 2 - tw / 2)
		for i in n:
			var x := lerpf(x0, x1, float(i) / max(1, n - 1))
			var zoff := 0.0
			if S.inter:
				zoff = (tw * 0.18) * (1.0 if i % 2 == 0 else -1.0)
			var rot := Vector3(PI / 2, 0, 0)
			g.add(wheel, Geo.xf(Vector3(x, wr + 0.8, zc + zoff), rot), rubber)
			g.add(hub, Geo.xf(Vector3(x, wr + 0.8, zc + zoff), rot), steel)
		var sprocket := Geo.cyl(wr * 0.8, wr * 0.8, tw * 0.7, 12)
		g.add(sprocket, Geo.xf(Vector3(L / 2 - wr * 0.8 - 1.0, th - wr * 0.85, zc), Vector3(PI / 2, 0, 0)), steel)
		g.add(sprocket, Geo.xf(Vector3(-L / 2 + wr * 0.8 + 1.0, th - wr * 0.85, zc), Vector3(PI / 2, 0, 0)), steel)
		for i in int(S.rollers):
			var rx := lerpf(x0 + 3.0, x1 - 3.0, float(i) / max(1, int(S.rollers) - 1))
			g.add(Geo.cyl(1.0, 1.0, tw * 0.5, 8), Geo.xf(Vector3(rx, th - 1.6, zc), Vector3(PI / 2, 0, 0)), steel)
		var belt_prof := PackedVector2Array([
			Vector2(-L / 2 + 2.5, th), Vector2(L / 2 - 2.5, th), Vector2(L / 2, th - 2.5), Vector2(L / 2, th * 0.55),
			Vector2(L / 2 - 5.5, 0.5), Vector2(-L / 2 + 5.5, 0.5), Vector2(-L / 2, th * 0.5), Vector2(-L / 2, th - 2.5)])
		g.add(Geo.belt(belt_prof, tw, 1.5, 3.2), Geo.xf(Vector3(0, 0, zc)), trk_l if s > 0 else trk_r)
		# экраны Pz.IV
		if S.get("skirts", false):
			for i in 5:
				var px := lerpf(-L * 0.38, L * 0.34, i / 4.0)
				g.add(Geo.box(Vector3(L * 0.15, th * 0.75, 0.5)), Geo.xf(Vector3(px, th * 0.62, s * (W / 2 + 0.6)), Vector3(0, 0, 0.02 * i)), paint)

	# характерные детали корпуса
	var front_y := hh * 0.7
	match key:
		"t34":
			for s: float in [1.0, -1.0]:
				g.add(Geo.cyl(2.2, 2.2, 9.0, 10), Geo.xf(Vector3(-L * 0.36, hh + 2.0, s * W * 0.36), Vector3(0, 0, PI / 2)), paint)
				g.add(Geo.cyl(0.9, 0.9, 3.0, 8), Geo.xf(Vector3(-L / 2 - 0.5, hh * 0.65, s * W * 0.22), Vector3(0, 0, PI / 2)), dark)
			for i in 3:
				g.add(Geo.box(Vector3(3.0, 0.8, W * 0.18)), Geo.xf(Vector3(L * 0.38 - i * 2.4, hh * 0.62 + i * 1.6, W * 0.12), Vector3(0, 0, -1.0)), dark)
			g.add(Geo.sphere(8, 5), Geo.xf(Vector3(L * 0.33, hh * 0.78, W * 0.16), Vector3.ZERO, Vector3(2.4, 2.4, 2.4)), paint)
		"tiger":
			for s: float in [1.0, -1.0]:
				g.add(Geo.cyl(1.0, 1.0, 5.0, 8), Geo.xf(Vector3(-L / 2 + 1.5, hh + 2.0, s * W * 0.15)), dark)
				g.add(Geo.box(Vector3(5.0, 0.6, tw)), Geo.xf(Vector3(L / 2 + 1.5, th + 0.4, s * (W / 2 - tw / 2)), Vector3(0, 0, -0.3)), paint)
			g.add(Geo.sphere(8, 5), Geo.xf(Vector3(L / 2, hh * 0.86, W * 0.24), Vector3.ZERO, Vector3(2.2, 2.2, 2.2)), paint)
			g.add(Geo.box(Vector3(1.2, 1.6, 5.0)), Geo.xf(Vector3(L / 2 + 0.2, hh * 0.86, -W * 0.18)), steel)
		"pz4":
			for s: float in [1.0, -1.0]:
				g.add(Geo.cyl(wr, wr, 1.5, 12), Geo.xf(Vector3(L / 2 - 1.0, hh * 0.45, s * W * 0.3), Vector3(0, 0, PI / 2)), rubber)
			for i in 4:
				g.add(Geo.box(Vector3(0.8, 2.6, W * 0.5)), Geo.xf(Vector3(L * 0.36, hh * 0.72 - i * 0.2, 0), Vector3(0, 0, -0.5 + i * 0.02)).translated(Vector3(0, -i * 1.4, 0)), dark)
			g.add(Geo.box(Vector3(1.0, 2.2, 3.0)), Geo.xf(Vector3(L * 0.34, hh * 0.82, -W * 0.22)), steel)
		"is2":
			for s: float in [1.0, -1.0]:
				g.add(Geo.box(Vector3(10.0, 3.6, 3.4)), Geo.xf(Vector3(-L * 0.33, th + 2.0, s * (W / 2 - 1.8))), paint)
				g.add(Geo.cyl(0.8, 0.8, 3.0, 8), Geo.xf(Vector3(-L / 2 - 0.5, hh * 0.6, s * W * 0.25), Vector3(0, 0, PI / 2)), dark)
			g.add(Geo.cyl(1.0, 1.2, 1.4, 8), Geo.xf(Vector3(L * 0.42, hh * 0.8, -W * 0.3), Vector3(0, 0, -PI / 2)), steel)
		"chaffee":
			g.add(Geo.box(Vector3(5.0, 2.4, W * 0.6)), Geo.xf(Vector3(-L / 2 + 1.5, hh * 0.85, 0)), paint)
			for s: float in [1.0, -1.0]:
				g.add(Geo.cyl(0.9, 1.1, 1.4, 8), Geo.xf(Vector3(L * 0.43, hh * 0.62, s * W * 0.3), Vector3(0, 0, -PI / 2)), steel)
			g.add(Geo.sphere(8, 5), Geo.xf(Vector3(L * 0.3, hh * 0.75, W * 0.18), Vector3.ZERO, Vector3(2.0, 2.0, 2.0)), paint)
	g.commit(hull, shadows)

	# опознавательные знаки на бортах корпуса (Германия, США)
	if S.emblem != "ussr":
		var eg := Geo.Group.new()
		var q := QuadMesh.new()
		q.size = Vector2(6.0, 6.0)
		for s: float in [1.0, -1.0]:
			var bs := Basis.IDENTITY if s > 0 else Basis(Vector3.UP, PI)
			eg.add(q, Transform3D(bs, Vector3(-L * 0.05, hh * 0.78, s * (W * 0.48 + 0.08))), em)
		eg.commit(hull, false)

	# пятно тени под танком (держит модель «на земле» и без теней)
	var blob := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(L * 1.25, W * 1.35)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = _blob()
	bm.disable_receive_shadows = true
	blob.mesh = bq
	blob.material_override = bm
	blob.rotation = Vector3(-PI / 2, 0, 0)
	blob.position.y = 0.35
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.add_child(blob)

	# башня
	var tz: float = W * float(S.tur_w)
	var tur_h: float = W * float(S.tur_h)
	var tur := Node3D.new()
	tur.position = Vector3(L * float(S.tur_x), hh - 0.3, 0)
	hull.add_child(tur)
	var tg := Geo.Group.new()
	var tpoly := _turret_poly(S.tur, tz, S.tur_f, S.tur_b)
	tg.add(Geo.frustum(tpoly, tur_h, S.tur_top), Transform3D.IDENTITY, paint)
	var front_x := tz * float(S.tur_f) * 0.92
	if S.tur == "tiger":
		front_x = tz * 0.75
	elif S.tur == "pz4":
		front_x = tz * 0.62
	var gun_y := tur_h * 0.48
	match S.mant:
		"round":
			tg.add(Geo.cyl(tur_h * 0.36, tur_h * 0.36, tz * 0.8, 12), Geo.xf(Vector3(front_x, gun_y, 0), Vector3(PI / 2, 0, 0)), paint)
		"round_big":
			tg.add(Geo.sphere(12, 6), Geo.xf(Vector3(front_x - 0.5, gun_y, 0), Vector3.ZERO, Vector3(tur_h * 0.9, tur_h * 0.8, tz * 1.0)), paint)
		"tiger":
			tg.add(Geo.box(Vector3(3.6, tur_h * 0.78, tz * 1.35)), Geo.xf(Vector3(front_x + 1.2, gun_y, 0)), paint)
		_:
			tg.add(Geo.box(Vector3(2.6, tur_h * 0.6, tz * 0.85)), Geo.xf(Vector3(front_x + 0.8, gun_y, 0)), paint)
	# командирская башенка и люки
	var cup_r := tz * 0.22
	tg.add(Geo.cyl(cup_r, cup_r * 1.05, 2.6, 12), Geo.xf(Vector3(-tz * 0.45, tur_h + 1.1, -tz * 0.32)), paint)
	tg.add(Geo.cyl(cup_r * 0.9, cup_r * 0.9, 0.6, 12), Geo.xf(Vector3(-tz * 0.45, tur_h + 2.5, -tz * 0.32)), steel)
	tg.add(Geo.box(Vector3(tz * 0.5, 0.5, tz * 0.45)), Geo.xf(Vector3(-tz * 0.2, tur_h + 0.2, tz * 0.3)), steel)
	match key:
		"tiger":
			for s: float in [1.0, -1.0]:
				for i in 3:
					tg.add(Geo.cyl(0.45, 0.45, 2.4, 6), Geo.xf(Vector3(tz * 0.55 - i * 0.9, tur_h * 0.75, s * (tz * 0.92 + 0.5 + i * 0.1)), Vector3(0.6 * s, 0, 0)), steel)
			tg.add(Geo.box(Vector3(5.5, 2.4, tz * 1.3)), Geo.xf(Vector3(-tz * 1.15, tur_h * 0.45, 0)), paint)
		"is2":
			tg.add(Geo.sphere(8, 5), Geo.xf(Vector3(-tz * 1.28, tur_h * 0.45, 0), Vector3.ZERO, Vector3(2.0, 2.0, 2.0)), paint)
			for s: float in [1.0, -1.0]:
				tg.add(Geo.box(Vector3(tz * 1.4, 0.4, 0.4)), Geo.xf(Vector3(-tz * 0.2, tur_h * 0.85, s * tz * 0.82)), steel)
		"chaffee":
			tg.add(Geo.cyl(0.35, 0.35, 9.0, 6), Geo.xf(Vector3(-tz * 0.3, tur_h + 3.0, tz * 0.3), Vector3(0, 0, -PI / 2 + 0.15)), steel)
			tg.add(Geo.box(Vector3(1.2, 2.4, 0.5)), Geo.xf(Vector3(-tz * 0.6, tur_h + 1.6, tz * 0.3)), steel)
		"t34":
			for s: float in [1.0, -1.0]:
				tg.add(Geo.box(Vector3(tz * 1.2, 0.35, 0.35)), Geo.xf(Vector3(-tz * 0.3, tur_h * 0.7, s * tz * 0.9)), steel)
		"pz4":
			for s: float in [1.0, -1.0]:
				tg.add(Geo.box(Vector3(tz * 0.45, tur_h * 0.6, 0.4)), Geo.xf(Vector3(-tz * 0.2, tur_h * 0.45, s * tz * 0.93)), steel)
	tg.commit(tur, shadows)

	# звёзды на бортах башни (СССР)
	if S.emblem == "ussr":
		var eg := Geo.Group.new()
		var q := QuadMesh.new()
		q.size = Vector2(5.0, 5.0)
		var tilt := atan2(tz * (1.0 - float(S.tur_top)), tur_h)
		for s: float in [1.0, -1.0]:
			var bs := Basis(Vector3.RIGHT, -tilt) if s > 0 else Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -tilt)
			eg.add(q, Transform3D(bs, Vector3(-tz * 0.35, tur_h * 0.5, s * (tz * (1.0 + float(S.tur_top)) / 2.0 + 0.15))), em)
		eg.commit(tur, false)

	# орудие на оси возвышения
	var gun := Node3D.new()
	gun.position = Vector3(front_x, gun_y, 0)
	tur.add_child(gun)
	var gg := Geo.Group.new()
	var barrel: float = L * float(S.gun)
	var blen := barrel - front_x - L * float(S.tur_x)
	var gr: float = W * float(S.gun_r)
	gg.add(Geo.cyl(gr * 0.85, gr * 1.1, blen, 10), Geo.xf(Vector3(blen / 2, 0, 0), Vector3(0, 0, -PI / 2)), steel)
	match S.brake:
		"double":
			gg.add(Geo.cyl(gr * 1.7, gr * 1.7, 3.2, 10), Geo.xf(Vector3(blen - 1.6, 0, 0), Vector3(0, 0, -PI / 2)), steel)
			gg.add(Geo.box(Vector3(1.0, gr * 1.6, gr * 4.2)), Geo.xf(Vector3(blen - 1.0, 0, 0)), steel)
		"ball":
			gg.add(Geo.sphere(10, 6), Geo.xf(Vector3(blen - 0.6, 0, 0), Vector3.ZERO, Vector3(2.6, gr * 2.8, gr * 2.8)), steel)
		_:
			gg.add(Geo.cyl(gr * 1.15, gr * 1.15, 1.4, 10), Geo.xf(Vector3(blen - 0.7, 0, 0), Vector3(0, 0, -PI / 2)), steel)
	gg.commit(gun, shadows)

	return {"hull": hull, "tur": tur, "gun": gun, "barrel": blen, "paints": [paint, em], "tracks": [trk_l, trk_r],
		"hh": hh, "tur_h": tur_h, "tz": tz, "height": hh + tur_h + 2.0}
