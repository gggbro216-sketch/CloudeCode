extends RefCounted
## Генерация карт (препятствия, кусты, дороги, зоны) и постройка их 3D-окружения.
## Логика боя работает на плоскости: точка карты (x, y) — это (x, 0, y) в 3D.

const D = preload("res://scripts/data.gd")


class Obst:
	var r: Rect2
	var kind: String
	var ht: float

	func _init(rect: Rect2, k: String, h: float) -> void:
		r = rect
		kind = k
		ht = h


class Bush:
	var pos: Vector2
	var r: float
	var kind: String
	var subs: Array = []  # Vector3(dx, dy, радиус)
	var meshes: Array = []
	var see := false


class Zone:
	var pos: Vector2
	var r: float
	var side := -1  # чья база/точка: 0 — наша, 1 — врага, -1 — ничья
	var prog: Array = [0.0, 0.0]
	var n: Array = [0, 0]
	var label := ""
	var ring_mat: StandardMaterial3D
	var disc_mat: StandardMaterial3D
	var flag_mat: StandardMaterial3D
	var flag: Node3D


static func make_zones(mode: String) -> Array:
	var ws := D.WS
	var out: Array = []
	if mode == "standard":
		out.append(_zone(Vector2(ws / 2, ws - 160), 95.0, 0, ""))
		out.append(_zone(Vector2(ws / 2, 160), 95.0, 1, ""))
	elif mode == "encounter":
		out.append(_zone(Vector2(ws / 2, ws / 2), 110.0, -1, ""))
	else:
		out.append(_zone(Vector2(520, ws / 2), 100.0, -1, "A"))
		out.append(_zone(Vector2(ws / 2, ws / 2), 100.0, -1, "B"))
		out.append(_zone(Vector2(ws - 520, ws / 2), 100.0, -1, "C"))
	return out


static func _zone(p: Vector2, r: float, side: int, label: String) -> Zone:
	var z := Zone.new()
	z.pos = p
	z.r = r
	z.side = side
	z.label = label
	return z


# ---------- Данные карт ----------

static func generate(map_key: String, zones: Array, rng: RandomNumberGenerator) -> Dictionary:
	match map_key:
		"desert":
			return _desert(rng, zones)
		"winter":
			return _winter(rng, zones)
	return _meadow(rng, zones)


## Препятствие не залезает на зоны старта и зоны захвата.
static func excl_ok(r: Rect2, zones: Array, m: float) -> bool:
	var ws := D.WS
	if not (r.position.y > 420 and r.end.y < ws - 420 and r.position.x > 90 and r.end.x < ws - 90):
		return false
	for z in zones:
		var zp: Vector2 = z.pos
		var c := Vector2(clampf(zp.x, r.position.x, r.end.x), clampf(zp.y, r.position.y, r.end.y))
		if c.distance_to(zp) < float(z.r) + m:
			return false
	return true


static func _hits(r: Rect2, obst: Array, m: float) -> bool:
	var g := r.grow(m)
	for o in obst:
		if g.intersects(o.r):
			return true
	return false


static func add_bushes(rng: RandomNumberGenerator, out: Array, n: int, obst: Array, zones: Array, kind: String, area: Rect2) -> void:
	var tries := 0
	var left := n
	while left > 0 and tries < n * 30:
		tries += 1
		var c := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		if c.y < 330 or c.y > D.WS - 330:
			continue
		var bad := false
		for o in obst:
			if (o.r as Rect2).grow(55.0).has_point(c):
				bad = true
				break
		if not bad:
			for z in zones:
				if c.distance_to(z.pos) < float(z.r) * 0.6:
					bad = true
					break
		if not bad:
			for b in out:
				if c.distance_to(b.pos) < float(b.r) + 40.0:
					bad = true
					break
		if bad:
			continue
		var bush := Bush.new()
		bush.pos = c
		bush.kind = kind
		bush.r = 34.0 + rng.randf() * 10.0 if kind == "fir" else 44.0 + rng.randf() * 18.0
		var k := 2 + rng.randi() % 3 if kind == "fir" else 3 + rng.randi() % 3
		for i in k:
			var a := rng.randf() * TAU
			var d := rng.randf() * bush.r * 0.55
			bush.subs.append(Vector3(cos(a) * d, sin(a) * d, bush.r * (0.5 + rng.randf() * 0.3)))
		out.append(bush)
		left -= 1


static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(p0.bezier_interpolate(p1, p2, p3, t))
	return out


static func _meadow(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var bushes: Array = []
	var tries := 0
	while obst.size() < 30 and tries < 2000:
		tries += 1
		var k := rng.randf()
		var w: float
		var h: float
		var kind: String
		var ht: float
		if k < 0.35:
			var hz := rng.randf() < 0.5
			var ln := 140.0 + rng.randf() * 140.0
			w = ln if hz else 20.0
			h = 20.0 if hz else ln
			kind = "wall"
			ht = 15.0
		elif k < 0.72:
			w = 56.0 + rng.randf() * 44.0
			h = 48.0 + rng.randf() * 36.0
			kind = "house"
			ht = 20.0 + rng.randf() * 8.0
		else:
			w = 50.0 + rng.randf() * 70.0
			h = 50.0 + rng.randf() * 70.0
			kind = "block"
			ht = 24.0 + rng.randf() * 22.0
		var r := Rect2(110.0 + rng.randf() * (ws - 220.0 - w), 430.0 + rng.randf() * (ws - 860.0 - h), w, h)
		if not excl_ok(r, zones, 30.0) or _hits(r, obst, 70.0):
			continue
		obst.append(Obst.new(r, kind, ht))
	add_bushes(rng, bushes, 40, obst, zones, "bush", Rect2(120, 330, ws - 240, ws - 660))
	var roads := [
		{"pts": bezier(Vector2(ws / 2, ws), Vector2(ws / 2 + 300, ws * 0.7), Vector2(ws / 2 - 380, ws * 0.35), Vector2(ws / 2, 0)), "w": 70.0},
		{"pts": bezier(Vector2(0, ws * 0.55), Vector2(ws * 0.3, ws * 0.4), Vector2(ws * 0.6, ws * 0.65), Vector2(ws, ws * 0.45)), "w": 56.0},
	]
	return {"obst": obst, "bushes": bushes, "roads": roads}


static func _desert(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var bushes: Array = []
	var tries := 0
	while obst.size() < 26 and tries < 2000:
		tries += 1
		var w: float
		var h: float
		var ht: float
		if obst.size() < 5:
			var hz := rng.randf() < 0.5
			var ln := 200.0 + rng.randf() * 120.0
			w = ln if hz else 50.0
			h = 50.0 if hz else ln
			ht = 38.0 + rng.randf() * 14.0
		else:
			var s := 50.0 + rng.randf() * 100.0
			w = s * (0.8 + rng.randf() * 0.4)
			h = s * (0.8 + rng.randf() * 0.4)
			ht = 20.0 + rng.randf() * 30.0
		var r := Rect2(110.0 + rng.randf() * (ws - 220.0 - w), 430.0 + rng.randf() * (ws - 860.0 - h), w, h)
		if not excl_ok(r, zones, 30.0) or _hits(r, obst, 80.0):
			continue
		obst.append(Obst.new(r, "rock", ht))
	add_bushes(rng, bushes, 18, obst, zones, "shrub", Rect2(120, 330, ws - 240, ws - 660))
	var roads := [
		{"pts": bezier(Vector2(0, ws * 0.3), Vector2(ws * 0.35, ws * 0.15), Vector2(ws * 0.55, ws * 0.8), Vector2(ws, ws * 0.7)), "w": 34.0},
	]
	return {"obst": obst, "bushes": bushes, "roads": roads}


static func _winter(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var bushes: Array = []
	var parks: Array = []
	var cell := 300.0
	var street := 110.0
	var bs := cell - street
	for i in 8:
		for j in 8:
			var bx := -40.0 + i * cell + street / 2
			var by := -40.0 + j * cell + street / 2
			if rng.randf() < 0.22:
				parks.append(Rect2(bx, by, bs, bs))
				continue
			var parts: Array = []
			var q := rng.randf()
			if q < 0.5:
				parts.append(Rect2(bx + rng.randf() * 15, by + rng.randf() * 15, bs - 30, bs - 30))
			elif q < 0.75:
				var s := bs * (0.4 + rng.randf() * 0.2)
				parts.append(Rect2(bx, by, s - 20, bs))
				parts.append(Rect2(bx + s + 20, by, bs - s - 20, bs))
			else:
				var s := bs * (0.4 + rng.randf() * 0.2)
				parts.append(Rect2(bx, by, bs, s - 20))
				parts.append(Rect2(bx, by + s + 20, bs, bs - s - 20))
			for pr in parts:
				if excl_ok(pr, zones, 25.0):
					obst.append(Obst.new(pr, "tower", 45.0 + rng.randf() * 70.0))
	var tries := 0
	var walls := 0
	while walls < 10 and tries < 400:
		tries += 1
		var hz := rng.randf() < 0.5
		var r := Rect2(120.0 + rng.randf() * (ws - 240.0), 450.0 + rng.randf() * (ws - 900.0), 60.0 if hz else 16.0, 16.0 if hz else 60.0)
		if not excl_ok(r, zones, 30.0) or _hits(r, obst, 60.0):
			continue
		obst.append(Obst.new(r, "barrier", 9.0))
		walls += 1
	for p in parks:
		add_bushes(rng, bushes, 3, obst, zones, "fir", p)
	add_bushes(rng, bushes, 14, obst, zones, "fir", Rect2(120, 330, ws - 240, ws - 660))
	var roads: Array = []
	for i in 9:
		var c := -40.0 + i * cell
		roads.append({"pts": PackedVector2Array([Vector2(c, 0), Vector2(c, ws)]), "w": street - 16.0})
		roads.append({"pts": PackedVector2Array([Vector2(0, c), Vector2(ws, c)]), "w": street - 16.0})
	return {"obst": obst, "bushes": bushes, "roads": roads}


# ---------- 3D-окружение ----------

static func mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _mi(parent: Node3D, mesh: Mesh, m: Material, p: Vector3, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Гранёная (low-poly) сетка: копии базовой фигуры с плоскими нормалями, слитые в одну.
static func faceted(base: Mesh, xforms: Array) -> ArrayMesh:
	var arr := base.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for xf in xforms:
		var t: Transform3D = xf
		for i in range(0, idx.size(), 3):
			var a := t * verts[idx[i]]
			var b := t * verts[idx[i + 1]]
			var c := t * verts[idx[i + 2]]
			var nrm := (b - a).cross(c - a)
			if nrm.length_squared() < 1e-8:
				continue
			nrm = nrm.normalized()
			if nrm.dot((a + b + c) / 3.0 - t.origin) < 0:
				nrm = -nrm
			st.set_normal(nrm)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	return st.commit()


static func _sphere(radial: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func _cone() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 7
	c.rings = 1
	return c


static func _window_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color("8b8f94"))
	img.fill_rect(Rect2i(0, 56, 64, 8), Color("7a7e83"))
	for p in [Vector2i(10, 12), Vector2i(38, 12), Vector2i(10, 34), Vector2i(38, 34)]:
		var lit := randf() < 0.25
		img.fill_rect(Rect2i(p.x, p.y, 16, 14), Color("e8d79a") if lit else Color("3d4a58"))
		img.fill_rect(Rect2i(p.x, p.y + 14, 16, 2), Color("b9bec3"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func build(parent: Node3D, data: Dictionary, map_key: String, zones: Array, hq: bool) -> void:
	var ws := D.WS
	var M: Dictionary = D.MAPS[map_key]
	# земля: шум с цветовой растяжкой, повторённый по карте
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, Color(M.ground_a))
	grad.set_color(1, Color(M.ground_b))
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	nt.color_ramp = grad
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(5, 5, 1)
	gm.roughness = 1.0
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := PlaneMesh.new()
	plane.size = Vector2(ws, ws)
	_mi(parent, plane, gm, Vector3(ws / 2, 0, ws / 2), false)
	var outer := PlaneMesh.new()
	outer.size = Vector2(9000, 9000)
	_mi(parent, outer, mat(Color(M.ground_a).darkened(0.1)), Vector3(ws / 2, -0.6, ws / 2), false)

	# дороги: полосы из треугольников
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := 0.25
	for road in data.roads:
		_strip(st, road.pts, road.w, lift)
		lift += 0.05
	var rm := mat(Color(M.road))
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(parent, st.commit(), rm, Vector3.ZERO, false)

	# граница карты
	var edge := mat(Color("5d5a4e") if map_key == "meadow" else (Color("9c7b4e") if map_key == "desert" else Color("8c949a")))
	for e in [Vector4(ws / 2, -8, ws + 40, 16), Vector4(ws / 2, ws + 8, ws + 40, 16), Vector4(-8, ws / 2, 16, ws + 40), Vector4(ws + 8, ws / 2, 16, ws + 40)]:
		_mi(parent, _boxm(Vector3(e.z, 14, e.w)), edge, Vector3(e.x, 7, e.y), false)

	# постройки и скалы
	var mats := {
		"wall": mat(Color("8a8778")), "house": mat(Color("d8cfb8")), "roof": mat(Color("8b4a32")),
		"block": mat(Color("7e7f76")), "block_top": mat(Color("5f605a")), "rock": mat(Color("b08a5a")),
		"barrier": mat(Color("9aa0a4")), "snow": mat(Color("f4f8fb")),
	}
	var tower_mat := mat(Color.WHITE)
	tower_mat.albedo_texture = _window_texture()
	tower_mat.uv1_triplanar = true
	tower_mat.uv1_world_triplanar = true
	tower_mat.uv1_scale = Vector3(1.0 / 26.0, 1.0 / 22.0, 1.0 / 26.0)
	var rock_base := _sphere(7, 4)
	for o in data.obst:
		var r: Rect2 = o.r
		var ht: float = o.ht
		var c := Vector3(r.get_center().x, 0, r.get_center().y)
		match o.kind:
			"house":
				_mi(parent, _boxm(Vector3(r.size.x, ht, r.size.y)), mats.house, c + Vector3(0, ht / 2, 0), hq)
				var roof := PrismMesh.new()
				roof.size = Vector3(r.size.x + 4, 16, r.size.y + 4)
				_mi(parent, roof, mats.roof, c + Vector3(0, ht + 8, 0), hq)
			"rock":
				var xf := Transform3D(Basis(Vector3.UP, randf() * 0.4).scaled(Vector3(r.size.x * 1.12, ht * 1.7, r.size.y * 1.12)), Vector3.ZERO)
				_mi(parent, faceted(rock_base, [xf]), mats.rock, c + Vector3(0, ht * 0.3, 0), hq)
			"tower":
				_mi(parent, _boxm(Vector3(r.size.x, ht, r.size.y)), tower_mat, c + Vector3(0, ht / 2, 0), hq)
				_mi(parent, _boxm(Vector3(r.size.x + 2, 3, r.size.y + 2)), mats.snow, c + Vector3(0, ht + 1.5, 0), false)
			"barrier":
				_mi(parent, _boxm(Vector3(r.size.x, ht, r.size.y)), mats.barrier, c + Vector3(0, ht / 2, 0), hq)
				_mi(parent, _boxm(Vector3(r.size.x, 2, r.size.y)), mats.snow, c + Vector3(0, ht + 1, 0), false)
			"block":
				_mi(parent, _boxm(Vector3(r.size.x, ht, r.size.y)), mats.block, c + Vector3(0, ht / 2, 0), hq)
				_mi(parent, _boxm(Vector3(r.size.x - 8, 2, r.size.y - 8)), mats.block_top, c + Vector3(0, ht + 1, 0), false)
			_:
				_mi(parent, _boxm(Vector3(r.size.x, ht, r.size.y)), mats.wall, c + Vector3(0, ht / 2, 0), hq)

	# кусты и ели: на каждый куст две слитые сетки (тёмная и светлая)
	var bush_cols := {"bush": [Color("3b5f2a"), Color("4b7336")], "shrub": [Color("7d7a3e"), Color("948c4a")], "fir": [Color("2c4a30"), Color("f0f5f8")]}
	var ico := _sphere(7, 4)
	var cone := _cone()
	var bush_mats := {}
	for k in bush_cols:
		bush_mats[k] = [mat(bush_cols[k][0]), mat(bush_cols[k][1])]
	for b in data.bushes:
		var a_x: Array = []
		var b_x: Array = []
		for s in b.subs:
			var sv: Vector3 = s
			if b.kind == "fir":
				var h := sv.z * 1.6 + 20.0
				a_x.append(Transform3D(Basis.from_scale(Vector3(sv.z * 1.5, h, sv.z * 1.5)), Vector3(sv.x, h / 2, sv.y)))
				b_x.append(Transform3D(Basis.from_scale(Vector3(sv.z * 0.64, h * 0.32, sv.z * 0.64)), Vector3(sv.x, h * 0.86, sv.y)))
			else:
				var k := 0.75 if b.kind == "shrub" else 1.0
				a_x.append(Transform3D(Basis.from_scale(Vector3(sv.z * 1.5, sv.z * 1.2, sv.z * 1.5) * k), Vector3(sv.x, sv.z * 0.42 * k, sv.y)))
				b_x.append(Transform3D(Basis.from_scale(Vector3(sv.z * 0.8, sv.z * 0.76, sv.z * 0.8) * k), Vector3(sv.x - 3, sv.z * 0.75 * k, sv.y - 3)))
		var base: Mesh = cone if b.kind == "fir" else ico
		var bp: Vector2 = b.pos
		var m1 := _mi(parent, faceted(base, a_x), bush_mats[b.kind][0], Vector3(bp.x, 0, bp.y), hq)
		var m2 := _mi(parent, faceted(base, b_x), bush_mats[b.kind][1], Vector3(bp.x, 0, bp.y), false)
		b.meshes = [m1, m2]

	# трава или камешки для ощущения масштаба
	if map_key != "winter":
		var n := 900 if hq else 400
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var small: Mesh
		if map_key == "meadow":
			small = faceted(_cone(), [Transform3D(Basis.from_scale(Vector3(2.6, 5, 2.6)), Vector3.ZERO)])
		else:
			small = faceted(_sphere(5, 3), [Transform3D(Basis.from_scale(Vector3(3, 2, 3)), Vector3.ZERO)])
		mm.mesh = small
		mm.instance_count = n
		var placed := 0
		var tries := 0
		while placed < n and tries < n * 4:
			tries += 1
			var p := Vector2(randf() * ws, randf() * ws)
			var inside := false
			for o in data.obst:
				if (o.r as Rect2).has_point(p):
					inside = true
					break
			if inside:
				continue
			var s := randf_range(0.6, 1.4)
			mm.set_instance_transform(placed, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, 2.4 if map_key == "meadow" else 0.4, p.y)))
			placed += 1
		mm.visible_instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(Color("4d6a2c") if map_key == "meadow" else Color("9a7c52"))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

	# зоны захвата: кольцо, полупрозрачный круг и флаг
	for z in zones:
		var zp: Vector2 = z.pos
		var zr: float = z.r
		var ring := TorusMesh.new()
		ring.inner_radius = zr - 5
		ring.outer_radius = zr
		ring.rings = 56
		ring.ring_segments = 4
		z.ring_mat = mat(Color.WHITE, true)
		var rmi := _mi(parent, ring, z.ring_mat, Vector3(zp.x, 0.6, zp.y), false)
		rmi.scale = Vector3(1, 0.12, 1)
		var disc := CylinderMesh.new()
		disc.top_radius = zr - 5
		disc.bottom_radius = zr - 5
		disc.height = 0.2
		disc.radial_segments = 48
		z.disc_mat = mat(Color(1, 1, 1, 0.12), true)
		z.disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mi(parent, disc, z.disc_mat, Vector3(zp.x, 0.4, zp.y), false)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.8
		pole.bottom_radius = 0.8
		pole.height = 56
		_mi(parent, pole, mat(Color("3a3a36")), Vector3(zp.x, 28, zp.y), hq)
		var pivot := Node3D.new()
		pivot.position = Vector3(zp.x, 49, zp.y)
		parent.add_child(pivot)
		var q := QuadMesh.new()
		q.size = Vector2(22, 13)
		z.flag_mat = mat(Color.WHITE)
		z.flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi(pivot, q, z.flag_mat, Vector3(11, 0, 0), false)
		z.flag = pivot


static func _strip(st: SurfaceTool, pts: PackedVector2Array, w: float, y: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).normalized().orthogonal() * (w * 0.5)
		var a1 := Vector3(a.x + side.x, y, a.y + side.y)
		var a2 := Vector3(a.x - side.x, y, a.y - side.y)
		var b1 := Vector3(b.x + side.x, y, b.y + side.y)
		var b2 := Vector3(b.x - side.x, y, b.y - side.y)
		st.set_normal(Vector3.UP)
		for v in [a1, b1, b2, a1, b2, a2]:
			st.add_vertex(v)
