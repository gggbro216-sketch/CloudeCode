extends RefCounted
## Полевой аэродром стороны: бетонная полоса (плиты, швы, осевая, «зебра» торцов, следы покрышек),
## рулёжка и перрон, ангары-арки, вышка КДП, палатки, бочки, ветроуказатель, огни по краям полосы,
## капониры зениток. Геометрия сливается в три меша на аэродром (полоса, грунтовые покрытия, постройки):
## десятки деталей — три вызова отрисовки.
## Ось полосы — вдоль X через (ws/2, zc), как в C++ (air_field): длина 3400, ширина 110 единиц.

const LEN := 3400.0
const WID := 110.0

static var _tex_strip: ImageTexture
static var _tex_key: ImageTexture


## Плита полосы: 128×256 пикселей на 110×220 единиц — швы, осевая, кромки, следы покрышек.
static func _strip_texture() -> ImageTexture:
	if _tex_strip:
		return _tex_strip
	var w := 128
	var h := 256
	var img := Image.create(w, h, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	for y in h:
		for x in w:
			var slab := (x / 32) * 7 + (y / 64) * 13
			var base := 0.62 + 0.03 * sin(float(slab) * 1.7) + rng.randf_range(-0.035, 0.035)
			# следы покрышек — темнее у оси
			var cx := absf(float(x) - w * 0.5) / (w * 0.5)
			if cx > 0.08 and cx < 0.42:
				base -= 0.07 * (1.0 - absf(cx - 0.25) / 0.17) * (0.6 + 0.4 * sin(float(y) * 0.05 + float(x) * 0.3))
			var c := Color(base, base * 0.985, base * 0.95)
			if x % 32 == 0 or y % 64 == 0:
				c = c.darkened(0.35)  # шов между плитами
			if (x < 3 or x >= w - 3):
				c = Color(0.78, 0.77, 0.72)  # кромка
			if absf(float(x) - w * 0.5) < 2.0 and (y % 128) < 72:
				c = Color(0.82, 0.81, 0.76)  # осевая штрихом
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex_strip = ImageTexture.create_from_image(img)
	return _tex_strip


## «Зебра» торца и цифры курса упрощённо: белые полосы на бетоне.
static func _key_texture() -> ImageTexture:
	if _tex_key:
		return _tex_key
	var img := Image.create(128, 64, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in 64:
		for x in 128:
			var b := 0.62 + rng.randf_range(-0.035, 0.035)
			var c := Color(b, b * 0.985, b * 0.95)
			var stripe := (x % 16) < 9 and x > 6 and x < 121 and y > 6 and y < 50
			if stripe:
				c = Color(0.84, 0.83, 0.78).darkened(rng.randf_range(0.0, 0.08))
			if y >= 56:
				c = Color(0.8, 0.79, 0.74)  # поперечная линия порога
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex_key = ImageTexture.create_from_image(img)
	return _tex_key


static func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.92
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # плоские участки с любым обходом вершин
	return m


## Прямоугольник на земле (по высоте рельефа в углах), UV — с повтором текстуры.
static func _quad(st: SurfaceTool, terra, x0: float, z0: float, x1: float, z1: float, lift: float, uv_x: float, uv_z: float, steps := 1) -> void:
	for k in steps:
		var a := x0 + (x1 - x0) * float(k) / steps
		var b := x0 + (x1 - x0) * float(k + 1) / steps
		var ua := uv_x * float(k) / steps
		var ub := uv_x * float(k + 1) / steps
		var p := [Vector3(a, terra.height(a, z0) + lift, z0), Vector3(b, terra.height(b, z0) + lift, z0),
			Vector3(b, terra.height(b, z1) + lift, z1), Vector3(a, terra.height(a, z1) + lift, z1)]
		var uv := [Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, uv_z), Vector2(ua, uv_z)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[i])
			st.add_vertex(p[i])


## Ящик постройки (вершинные цвета), основание — на самой низкой точке рельефа под ним.
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		[Vector3.UP, Vector3.FORWARD, Vector3.RIGHT]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var sh := 1.0 if n == Vector3.UP else (0.82 if absf(n.x) > 0.5 else 0.7)
		var cc := Color(col.r * sh, col.g * sh, col.b * sh)
		var o := n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o - du + dv, o + du + dv, o + du - dv]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(cc)
			st.set_normal(b * n)
			st.add_vertex(c + b * (q[i] as Vector3))


## Ангар-арка: полукруглая крыша вдоль своей оси, торцы — стены с тёмным проёмом ворот.
static func _hangar(st: SurfaceTool, c: Vector3, w: float, l: float, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var seg := 10
	var r := w * 0.5
	for i in seg:
		var a0 := PI * float(i) / seg
		var a1 := PI * float(i + 1) / seg
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		var n := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0)
		var rib := 0.92 if i % 2 == 0 else 1.0  # гофра
		var cc := Color(col.r * rib * (0.75 + 0.25 * n.y), col.g * rib * (0.75 + 0.25 * n.y), col.b * rib * (0.75 + 0.25 * n.y))
		var q := [p0 + Vector3(0, 0, -l * 0.5), p1 + Vector3(0, 0, -l * 0.5), p1 + Vector3(0, 0, l * 0.5), p0 + Vector3(0, 0, l * 0.5)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(cc)
			st.set_normal(b * n)
			st.add_vertex(c + b * (q[k] as Vector3))
	# торцы: стена и ворота
	for s in [-1.0, 1.0]:
		for i in seg:
			var a0 := PI * float(i) / seg
			var a1 := PI * float(i + 1) / seg
			var gate: bool = absf(cos((a0 + a1) * 0.5)) < 0.55 and s > 0.0
			var cc: Color = Color(0.08, 0.08, 0.07) if gate else col.darkened(0.25)
			var q := [Vector3(0, 0, s * l * 0.5), Vector3(cos(a0) * r, sin(a0) * r, s * l * 0.5), Vector3(cos(a1) * r, sin(a1) * r, s * l * 0.5)]
			var order: Array = [0, 1, 2] if s > 0.0 else [0, 2, 1]
			for k in order:
				st.set_color(cc)
				st.set_normal(b * Vector3(0, 0, s))
				st.add_vertex(c + b * (q[k] as Vector3))


## Аэродром стороны tm. Возвращает предметы для scatter: {имя модели: [[Transform3D, Color], …]}.
static func build(parent: Node3D, terra, ws: float, tm: int, sc: float) -> Dictionary:
	var zc := ws + 380.0 if tm == 0 else -380.0
	var out := 1.0 if tm == 0 else -1.0  # сторона «от поля боя»
	var cx := ws * 0.5
	var items := {}
	# --- полоса: плиты с повтором, торцы с «зеброй»
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var key_l := 160.0
	_quad(st, terra, cx - LEN * 0.5 + key_l, zc - WID * 0.5, cx + LEN * 0.5 - key_l, zc + WID * 0.5, 0.45, (LEN - 2.0 * key_l) / 220.0, 1.0, 24)
	var strip := MeshInstance3D.new()
	strip.mesh = st.commit()
	strip.material_override = _mat(_strip_texture())
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(strip)
	var sk := SurfaceTool.new()
	sk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(sk, terra, cx - LEN * 0.5, zc - WID * 0.5, cx - LEN * 0.5 + key_l, zc + WID * 0.5, 0.45, 1.0, 1.0, 2)
	_quad(sk, terra, cx + LEN * 0.5, zc + WID * 0.5, cx + LEN * 0.5 - key_l, zc - WID * 0.5, 0.45, 1.0, 1.0, 2)
	var keys := MeshInstance3D.new()
	keys.mesh = sk.commit()
	keys.material_override = _mat(_key_texture())
	keys.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(keys)
	# --- постройки, рулёжка, перрон, огни — вершинными цветами одним мешем
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gravel := Color(0.55, 0.52, 0.45)
	var tz := zc + out * 135.0
	# рулёжка вдоль полосы и два съезда
	_flat(sb, terra, cx - 1300.0, tz - 16.0, cx + 600.0, tz + 16.0, 0.3, gravel)
	for sx in [-1300.0, 400.0]:
		var ez := zc + out * WID * 0.5
		_flat(sb, terra, cx + sx - 16.0, minf(ez, tz), cx + sx + 16.0, maxf(ez, tz), 0.3, gravel)
	# перрон
	var az0 := tz + out * 16.0
	var az1 := tz + out * 140.0
	_flat(sb, terra, cx - 620.0, minf(az0, az1), cx + 120.0, maxf(az0, az1), 0.32, gravel.lightened(0.06))
	# огни по краям полосы
	var x := cx - LEN * 0.5 + 40.0
	while x < cx + LEN * 0.5:
		for s in [-1.0, 1.0]:
			var p := Vector3(x, terra.height(x, zc + s * (WID * 0.5 + 6.0)) + 1.2, zc + s * (WID * 0.5 + 6.0))
			_box(sb, p, Vector3(2.0, 2.4, 2.0), 0.0, Color(0.9, 0.88, 0.7))
		x += 170.0
	# ангары за перроном
	for k in 2:
		var hx := cx - 520.0 + k * 230.0
		var hz := zc + out * 255.0
		var hy: float = minf(terra.height(hx - 70.0, hz), terra.height(hx + 70.0, hz)) - 1.0
		_hangar(sb, Vector3(hx, hy, hz), 150.0, 120.0, 0.0 if out > 0 else PI, Color(0.42, 0.44, 0.36))
	# вышка КДП: два этажа, остеклённая будка, площадка
	var tx := cx + 260.0
	var tzz := zc + out * 210.0
	var ty: float = terra.height(tx, tzz)
	_box(sb, Vector3(tx, ty + 14.0, tzz), Vector3(38.0, 28.0, 38.0), 0.0, Color(0.55, 0.5, 0.42))
	_box(sb, Vector3(tx, ty + 34.0, tzz), Vector3(28.0, 12.0, 28.0), 0.0, Color(0.16, 0.2, 0.22))
	_box(sb, Vector3(tx, ty + 41.0, tzz), Vector3(34.0, 2.5, 34.0), 0.0, Color(0.3, 0.27, 0.24))
	_box(sb, Vector3(tx + 12.0, ty + 49.0, tzz + 12.0), Vector3(1.2, 14.0, 1.2), 0.0, Color(0.2, 0.2, 0.2))  # мачта
	# палатки и бочки
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + tm
	for k in 5:
		var px := cx + 340.0 + k * 52.0
		var pz := zc + out * (300.0 + rng.randf_range(-15.0, 15.0))
		var py: float = terra.height(px, pz)
		_tent(sb, Vector3(px, py, pz), 34.0, 26.0, 18.0, rng.randf() * 0.3, Color(0.4, 0.42, 0.3))
	for k in 18:
		var px := cx - 690.0 + float(k % 6) * 6.5
		var pz := zc + out * (60.0 + 60.0 + float(k / 6) * 6.5)
		_box(sb, Vector3(px, terra.height(px, pz) + 3.4, pz), Vector3(5.2, 6.8, 5.2), 0.0, Color(0.3, 0.33, 0.24) if k % 4 else Color(0.5, 0.18, 0.12))
	# ветроуказатель у торца
	var wx := cx + LEN * 0.5 - 260.0
	var wz := zc + out * (WID * 0.5 + 40.0)
	var wy: float = terra.height(wx, wz)
	_box(sb, Vector3(wx, wy + 15.0, wz), Vector3(1.4, 30.0, 1.4), 0.0, Color(0.85, 0.85, 0.82))
	for k in 4:
		_box(sb, Vector3(wx - 4.0 - k * 4.4, wy + 28.0 - k * 0.6, wz), Vector3(4.6, 3.6 - k * 0.5, 3.6 - k * 0.5), 0.0,
			Color(0.95, 0.45, 0.1) if k % 2 == 0 else Color(0.95, 0.93, 0.9))
	var bm := MeshInstance3D.new()
	bm.mesh = sb.commit()
	var mb := StandardMaterial3D.new()
	mb.vertex_color_use_as_albedo = true
	mb.roughness = 0.9
	mb.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.material_override = mb
	parent.add_child(bm)
	# зенитки в капонирах из мешков (модели пушек и мешков — общим MultiMesh)
	for k in 2:
		var gx := cx + (-900.0 if k == 0 else 800.0)
		var gz := zc + out * 190.0
		var gy: float = terra.height(gx, gz)
		_add(items, "gun_flak88", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(gx, gy, gz)))
		for j in 10:
			var a := TAU * float(j) / 10.0
			var p := Vector3(gx + cos(a) * 34.0, 0.0, gz + sin(a) * 34.0)
			p.y = terra.height(p.x, p.z)
			_add(items, "decor_sandbag", Transform3D(Basis(Vector3.UP, -a).scaled(Vector3.ONE * sc), p))
	return items


static func _add(items: Dictionary, nm: String, xf: Transform3D) -> void:
	if not items.has(nm):
		items[nm] = []
	(items[nm] as Array).append([xf, Color.WHITE])


## Плоский участок вершинными цветами (рулёжка, перрон), по рельефу сеткой.
static func _flat(st: SurfaceTool, terra, x0: float, z0: float, x1: float, z1: float, lift: float, col: Color) -> void:
	var nx := maxi(1, int(absf(x1 - x0) / 120.0))
	var nz := maxi(1, int(absf(z1 - z0) / 120.0))
	for i in nx:
		for j in nz:
			var a := x0 + (x1 - x0) * float(i) / nx
			var b := x0 + (x1 - x0) * float(i + 1) / nx
			var c := z0 + (z1 - z0) * float(j) / nz
			var d := z0 + (z1 - z0) * float(j + 1) / nz
			var p := [Vector3(a, terra.height(a, c) + lift, c), Vector3(b, terra.height(b, c) + lift, c),
				Vector3(b, terra.height(b, d) + lift, d), Vector3(a, terra.height(a, d) + lift, d)]
			var cc := col.darkened(0.04 * float((i + j) % 2))
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_color(cc)
				st.set_normal(Vector3.UP)
				st.add_vertex(p[k])


## Палатка: двускатная крыша на низких стенках.
static func _tent(st: SurfaceTool, c: Vector3, l: float, w: float, h: float, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var hl := l * 0.5
	var hw := w * 0.5
	var wall := h * 0.3
	var pts := {"a": Vector3(-hl, 0, -hw), "b": Vector3(hl, 0, -hw), "c": Vector3(hl, 0, hw), "d": Vector3(-hl, 0, hw),
		"a2": Vector3(-hl, wall, -hw), "b2": Vector3(hl, wall, -hw), "c2": Vector3(hl, wall, hw), "d2": Vector3(-hl, wall, hw),
		"r0": Vector3(-hl, h, 0), "r1": Vector3(hl, h, 0)}
	var tris := [["a2", "r0", "r1", 0.95], ["a2", "r1", "b2", 0.95], ["d2", "r1", "r0", 0.8], ["d2", "c2", "r1", 0.8],
		["a", "a2", "b2", 0.7], ["a", "b2", "b", 0.7], ["d", "c2", "d2", 0.7], ["d", "c", "c2", 0.7],
		["a", "r0", "a2", 0.75], ["d", "d2", "r0", 0.75], ["a", "d", "r0", 0.75], ["b", "b2", "r1", 0.75], ["c", "r1", "c2", 0.75], ["b", "r1", "c", 0.75]]
	for t: Array in tris:
		var p0: Vector3 = b * (pts[t[0]] as Vector3)
		var p1: Vector3 = b * (pts[t[1]] as Vector3)
		var p2: Vector3 = b * (pts[t[2]] as Vector3)
		var n := (p1 - p0).cross(p2 - p0).normalized()
		var sh: float = t[3]
		for p: Vector3 in [p0, p1, p2]:
			st.set_color(Color(col.r * sh, col.g * sh, col.b * sh))
			st.set_normal(n)
			st.add_vertex(c + p)
