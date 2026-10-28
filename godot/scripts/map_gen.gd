extends RefCounted
## Карты: расстановка объектов (Прохоровка, Эль-Аламейн, Сталинград) и постройка 3D-сцены.
## Логика боя работает на плоскости: точка карты (x, y) — это (x, высота рельефа, y) в 3D.
## Неподвижные объекты сливаются в одну сетку на материал; деревья и заборы — разрушаемые.

const D = preload("res://scripts/data.gd")
const Geo = preload("res://scripts/geo.gd")


class Obst:
	var r: Rect2
	var kind: String
	var ht: float
	var base := 0.0  # высота фундамента (ставит рельеф)
	var solid := true  # останавливает снаряды

	func _init(rect: Rect2, k: String, h: float, s := true) -> void:
		r = rect
		kind = k
		ht = h
		solid = s


class Bush:
	var pos: Vector2
	var r: float
	var kind: String
	var subs: Array = []  # Vector3(dx, dy, радиус)


## Разрушаемый объект: дерево или пролёт забора.
class Prop:
	var pos: Vector2
	var r: float
	var kind: String
	var rot := 0.0
	var scale := 1.0
	var alive := true
	var fall := 0.0
	var fall_dir := Vector2.RIGHT
	var y := 0.0
	var mms: Array = []  # [MultiMesh, индекс, локальное смещение]


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


# ---------- Расстановка ----------

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


static func _free_point(p: Vector2, obst: Array, zones: Array, props: Array, m: float) -> bool:
	if p.x < 100 or p.x > D.WS - 100 or p.y < 380 or p.y > D.WS - 380:
		return false
	for o in obst:
		if (o.r as Rect2).grow(m).has_point(p):
			return false
	for z in zones:
		if p.distance_to(z.pos) < float(z.r) + m * 0.5:
			return false
	for pr in props:
		if p.distance_to(pr.pos) < m * 0.6:
			return false
	return true


static func _place(rng: RandomNumberGenerator, obst: Array, zones: Array, w: float, h: float, kind: String, ht: float,
		area: Rect2, margin := 60.0, solid := true) -> Obst:
	for t in 60:
		var r := Rect2(area.position.x + rng.randf() * maxf(1.0, area.size.x - w), area.position.y + rng.randf() * maxf(1.0, area.size.y - h), w, h)
		if excl_ok(r, zones, 30.0) and not _hits(r, obst, margin):
			var o := Obst.new(r, kind, ht, solid)
			obst.append(o)
			return o
	return null


static func _bushes(rng: RandomNumberGenerator, out: Array, n: int, obst: Array, zones: Array, props: Array, kind: String, area: Rect2) -> void:
	var tries := 0
	var left := n
	while left > 0 and tries < n * 30:
		tries += 1
		var c := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		if not _free_point(c, obst, zones, props, 55.0):
			continue
		var near := false
		for b in out:
			if c.distance_to(b.pos) < float(b.r) + 40.0:
				near = true
				break
		if near:
			continue
		var bush := Bush.new()
		bush.pos = c
		bush.kind = kind
		bush.r = 34.0 + rng.randf() * 10.0 if kind == "fir" else 40.0 + rng.randf() * 16.0
		var k := 2 + rng.randi() % 3 if kind == "fir" else 3 + rng.randi() % 3
		for i in k:
			var a := rng.randf() * TAU
			var d := rng.randf() * bush.r * 0.55
			bush.subs.append(Vector3(cos(a) * d, sin(a) * d, bush.r * (0.5 + rng.randf() * 0.3)))
		out.append(bush)
		left -= 1


static func _prop(props: Array, kind: String, p: Vector2, rng: RandomNumberGenerator, r := 4.0) -> Prop:
	var pr := Prop.new()
	pr.kind = kind
	pr.pos = p
	pr.r = r
	pr.rot = rng.randf() * TAU
	pr.scale = rng.randf_range(0.8, 1.25)
	props.append(pr)
	return pr


static func _tree_line(rng: RandomNumberGenerator, props: Array, obst: Array, zones: Array, kind: String, a: Vector2, b: Vector2, step: float) -> void:
	var n := int(a.distance_to(b) / step)
	for i in n:
		var p := a.lerp(b, float(i) / maxf(1.0, n)) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		if _free_point(p, obst, zones, props, 22.0):
			_prop(props, kind, p, rng)


static func _craters(rng: RandomNumberGenerator, n: int, obst: Array, zones: Array, area: Rect2) -> Array:
	var out: Array = []
	for i in n * 4:
		if out.size() >= n:
			break
		var p := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		if _free_point(p, obst, zones, [], 30.0):
			out.append(Vector3(p.x, p.y, rng.randf_range(9.0, 20.0)))
	return out


static func _sandbag_nest(rng: RandomNumberGenerator, obst: Array, zones: Array, area: Rect2) -> void:
	var o := _place(rng, obst, zones, 46, 9, "sandbags", 5.0, area, 50.0)
	if o == null:
		return
	var r := o.r
	var s1 := Rect2(r.position.x - 9, r.end.y, 9, 30)
	var s2 := Rect2(r.end.x, r.end.y, 9, 30)
	if rng.randf() < 0.5:
		s1 = Rect2(r.position.x - 9, r.position.y - 30, 9, 30)
		s2 = Rect2(r.end.x, r.position.y - 30, 9, 30)
	for s in [s1, s2]:
		if excl_ok(s, zones, 20.0):
			obst.append(Obst.new(s, "sandbags", 5.0))


static func generate(map_key: String, zones: Array, rng: RandomNumberGenerator) -> Dictionary:
	match map_key:
		"alamein":
			return _alamein(rng, zones)
		"stalingrad":
			return _stalingrad(rng, zones)
	return _prokhorovka(rng, zones)


static func _prokhorovka(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	# две деревни: целые и разрушенные хаты
	for v in 2:
		var c := Vector2(rng.randf_range(500, ws - 500), rng.randf_range(800, ws - 800))
		for i in 7:
			var a := rng.randf() * TAU
			var d := rng.randf_range(60, 260)
			var w := rng.randf_range(52, 76)
			var h := rng.randf_range(40, 58)
			var p := c + Vector2(cos(a), sin(a)) * d
			var kind := "house" if rng.randf() < 0.5 else "ruin"
			_place(rng, obst, zones, w, h, kind, rng.randf_range(19, 25), Rect2(p - Vector2(30, 30), Vector2(60 + w, 60 + h)), 34.0)
		for i in 6:
			var fp := c + Vector2(rng.randf_range(-280, 280), rng.randf_range(-280, 280))
			var dir := Vector2.from_angle(rng.randf() * TAU)
			for k in 5:
				var p := fp + dir * (k * 22.0)
				if _free_point(p, obst, zones, props, 16.0):
					var f := _prop(props, "fence", p, rng, 9.0)
					f.rot = dir.angle()
					f.scale = 1.0
	for i in 3:
		_place(rng, obst, zones, 44, 36, "bunker", 11.0, mid, 70.0)
	for i in 5:
		_place(rng, obst, zones, 36, 22, "wreck_tank", 10.0, mid, 60.0)
	for i in 5:
		_sandbag_nest(rng, obst, zones, mid)
	for i in 4:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, 90.0 if hz else 12.0, 12.0 if hz else 90.0, "hedgehogs", 8.0, mid, 50.0, false)
	for i in 7:
		var a := Vector2(rng.randf_range(200, ws - 200), rng.randf_range(480, ws - 480))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(200, 420)
		_tree_line(rng, props, obst, zones, "tree", a, b, 30.0)
	for i in 24:
		var p := Vector2(rng.randf_range(150, ws - 150), rng.randf_range(420, ws - 420))
		if _free_point(p, obst, zones, props, 30.0):
			_prop(props, "tree", p, rng)
	_bushes(rng, bushes, 32, obst, zones, props, "bush", Rect2(120, 330, ws - 240, ws - 660))
	var road := Geo_bezier(Vector2(ws / 2, ws + 100), Vector2(ws / 2 + 320, ws * 0.7), Vector2(ws / 2 - 380, ws * 0.35), Vector2(ws / 2, -100))
	var roads := [{"pts": road, "w": 46.0},
		{"pts": Geo_bezier(Vector2(-100, ws * 0.55), Vector2(ws * 0.3, ws * 0.4), Vector2(ws * 0.6, ws * 0.66), Vector2(ws + 100, ws * 0.45)), "w": 36.0}]
	# телеграфные столбы вдоль большой дороги
	for i in range(0, road.size(), 2):
		var p := road[i] + Vector2(34, 0)
		if _free_point(p, obst, zones, props, 12.0):
			decor.append({"kind": "pole", "pos": p, "rot": 0.0})
	var craters := _craters(rng, 45, obst, zones, mid)
	return {"obst": obst, "bushes": bushes, "props": props, "decor": decor, "craters": craters, "roads": roads}


static func _alamein(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	for i in 4:
		var hz := rng.randf() < 0.5
		var ln := rng.randf_range(200, 320)
		_place(rng, obst, zones, ln if hz else 54.0, 54.0 if hz else ln, "rock", rng.randf_range(34, 48), mid, 90.0)
	for i in 20:
		var s := rng.randf_range(50, 140)
		_place(rng, obst, zones, s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.8, 1.2), "rock", rng.randf_range(18, 44), mid, 70.0)
	for i in 6:
		_sandbag_nest(rng, obst, zones, mid)
	for i in 6:
		var truck := rng.randf() < 0.4
		_place(rng, obst, zones, 34 if truck else 36, 16 if truck else 22, "wreck_truck" if truck else "wreck_tank", 10.0, mid, 60.0)
	for i in 3:
		_place(rng, obst, zones, 30, 24, "tent", 12.0, mid, 60.0)
	for i in 3:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, 90.0 if hz else 12.0, 12.0 if hz else 90.0, "hedgehogs", 8.0, mid, 50.0, false)
	# оазис с пальмами
	var oasis := Vector2(rng.randf_range(500, ws - 500), rng.randf_range(800, ws - 800))
	for i in 10:
		var p := oasis + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 140)
		if _free_point(p, obst, zones, props, 24.0):
			_prop(props, "palm", p, rng)
	for i in 8:
		var p := Vector2(rng.randf_range(150, ws - 150), rng.randf_range(420, ws - 420))
		if _free_point(p, obst, zones, props, 40.0):
			_prop(props, "palm", p, rng)
	for i in 10:
		var p := Vector2(rng.randf_range(150, ws - 150), rng.randf_range(420, ws - 420))
		if _free_point(p, obst, zones, props, 30.0):
			decor.append({"kind": "barrels", "pos": p, "rot": rng.randf() * TAU})
	_bushes(rng, bushes, 18, obst, zones, props, "shrub", Rect2(120, 330, ws - 240, ws - 660))
	var roads := [{"pts": Geo_bezier(Vector2(-100, ws * 0.3), Vector2(ws * 0.35, ws * 0.15), Vector2(ws * 0.55, ws * 0.8), Vector2(ws + 100, ws * 0.7)), "w": 30.0}]
	var craters := _craters(rng, 35, obst, zones, mid)
	return {"obst": obst, "bushes": bushes, "props": props, "decor": decor, "craters": craters, "roads": roads}


static func _stalingrad(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var cell := 300.0
	var street := 110.0
	var bs := cell - street
	var parks: Array = []
	for i in 8:
		for j in 8:
			var bx := -40.0 + i * cell + street / 2
			var by := -40.0 + j * cell + street / 2
			if rng.randf() < 0.2:
				parks.append(Rect2(bx, by, bs, bs))
				continue
			var parts: Array = []
			var q := rng.randf()
			if q < 0.45:
				parts.append(Rect2(bx + rng.randf() * 15, by + rng.randf() * 15, bs - 30, bs - 30))
			elif q < 0.72:
				var s := bs * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(bx, by, s - 20, bs))
				parts.append(Rect2(bx + s + 20, by, bs - s - 20, bs))
			else:
				var s := bs * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(bx, by, bs, s - 20))
				parts.append(Rect2(bx, by + s + 20, bs, bs - s - 20))
			for pr in parts:
				if excl_ok(pr, zones, 25.0):
					var kind := "ruin_tower" if rng.randf() < 0.75 else "tower"
					obst.append(Obst.new(pr, kind, rng.randf_range(45, 105)))
	var street_area := Rect2(120, 450, ws - 240, ws - 900)
	for i in 10:
		_place(rng, obst, zones, rng.randf_range(30, 50), rng.randf_range(24, 40), "rubble", 6.0, street_area, 30.0)
	for i in 7:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, 60.0 if hz else 12.0, 12.0 if hz else 60.0, "hedgehogs", 8.0, street_area, 40.0, false)
	for i in 5:
		_sandbag_nest(rng, obst, zones, street_area)
	for i in 6:
		var truck := rng.randf() < 0.4
		_place(rng, obst, zones, 34 if truck else 36, 16 if truck else 22, "wreck_truck" if truck else "wreck_tank", 10.0, street_area, 40.0)
	for p in parks:
		_bushes(rng, bushes, 2, obst, zones, props, "fir", p)
		for k in 3:
			var tp := Vector2(p.position.x + rng.randf() * p.size.x, p.position.y + rng.randf() * p.size.y)
			if _free_point(tp, obst, zones, props, 24.0):
				_prop(props, "bare", tp, rng)
	_bushes(rng, bushes, 10, obst, zones, props, "fir", Rect2(120, 330, ws - 240, ws - 660))
	var roads: Array = []
	for i in 9:
		var c := -40.0 + i * cell
		roads.append({"pts": PackedVector2Array([Vector2(c, -100), Vector2(c, ws + 100)]), "w": street - 20.0})
		roads.append({"pts": PackedVector2Array([Vector2(-100, c), Vector2(ws + 100, c)]), "w": street - 20.0})
	var craters := _craters(rng, 40, obst, zones, street_area)
	return {"obst": obst, "bushes": bushes, "props": props, "decor": decor, "craters": craters, "roads": roads}


static func Geo_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n := 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(p0.bezier_interpolate(p1, p2, p3, float(i) / n))
	return out


# ---------- 3D-сцена ----------

static func mat(c: Color, unshaded := false, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _window_texture(snowy: bool) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color("8a8378") if not snowy else Color("8c8f92"))
	img.fill_rect(Rect2i(0, 56, 64, 8), Color("6f6a62"))
	for p in [Vector2i(9, 12), Vector2i(37, 12), Vector2i(9, 34), Vector2i(37, 34)]:
		img.fill_rect(Rect2i(p.x, p.y, 17, 16), Color("1d1c1a"))
		img.fill_rect(Rect2i(p.x - 1, p.y + 16, 19, 2), Color("a9a49b"))
	# следы копоти и выбоины
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var c := Color(0.15, 0.14, 0.12) if rng.randf() < 0.6 else Color(0.62, 0.58, 0.52)
		img.fill_rect(Rect2i(rng.randi() % 62, rng.randi() % 62, 2 + rng.randi() % 3, 2 + rng.randi() % 3), c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


const BUSH_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 fade_a;
uniform vec3 fade_b;
varying vec2 center;
varying float rad;

void vertex() {
	center = UV2;
	rad = COLOR.a * 100.0;
}

void fragment() {
	// куст, в котором стоит наш танк или камера, становится «сетчатым»
	if (distance(center, fade_a.xz) < rad + 8.0 || distance(center, fade_b.xz) < rad + 4.0) {
		if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""


## Строит сцену карты. Возвращает материалы кустов (для полупрозрачности), MultiMesh разрушаемых
## объектов и точки для дымов.
static func build(parent: Node3D, data: Dictionary, map_key: String, zones: Array, terra, hq: bool) -> Dictionary:
	var winter := map_key == "stalingrad"
	var desert := map_key == "alamein"
	var g := Geo.Group.new()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	parent.add_child(body)
	var M := {
		"plaster": mat(Color("cfc4a8")), "brick": mat(Color("8b5a44")), "roof": mat(Color("6b4a30")),
		"concrete": mat(Color("85837a")), "concrete_d": mat(Color("5e5d57")), "wood": mat(Color("5d4630")),
		"steel": mat(Color("3a3a35"), false, 0.6), "rust": mat(Color("5a3a28")), "charred": mat(Color("2d2a26")),
		"sand": mat(Color("a8916a") if desert else Color("8d7f5c")), "rubble": mat(Color("7b736a") if not winter else Color("8a8784")),
		"rock": mat(Color("a98559")), "snow": mat(Color("eef3f6")), "canvas": mat(Color("8c8360")),
		"olive": mat(Color("4d5233")), "pole": mat(Color("4a3a2a")),
	}
	var win := mat(Color.WHITE)
	win.albedo_texture = _window_texture(winter)
	win.uv1_triplanar = true
	win.uv1_world_triplanar = true
	win.uv1_scale = Vector3(1.0 / 26.0, 1.0 / 22.0, 1.0 / 26.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var smokes: Array = []
	var rock_base := Geo.sphere(7, 4)
	var bag := Geo.box(Vector3(4.6, 2.2, 3.2))

	for o in data.obst:
		var r: Rect2 = o.r
		var c2 := r.get_center()
		var b: float = o.base
		var ht: float = o.ht
		var c := Vector3(c2.x, b, c2.y)
		var w := r.size.x
		var d := r.size.y
		match o.kind:
			"house":
				g.add(Geo.box(Vector3(w, ht + 4, d)), Geo.xf(c + Vector3(0, ht / 2 - 2, 0)), M.plaster)
				var roof := PrismMesh.new()
				var along_x := w >= d
				roof.size = Vector3((d if along_x else w) + 5, 15, (w if along_x else d) + 5)
				g.add(roof, Geo.xf(c + Vector3(0, ht + 7.5, 0), Vector3(0, PI / 2 if along_x else 0.0, 0)), M.roof, true)
				g.add(Geo.box(Vector3(4, 10, 4)), Geo.xf(c + Vector3(w * 0.25, ht + 10, d * 0.15)), M.brick)
				for s: float in [1.0, -1.0]:
					g.add(Geo.box(Vector3(6, 7, 0.6)), Geo.xf(c + Vector3(w * 0.2 * s, ht * 0.55, d / 2 + 0.2)), M.charred)
					g.add(Geo.box(Vector3(0.6, 7, 6)), Geo.xf(c + Vector3(w / 2 + 0.2, ht * 0.55, d * 0.2 * s)), M.charred)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht + 15, d))
			"ruin":
				var thick := 3.0
				var walls := [[Vector3(0, 0, -d / 2 + thick / 2), w, true], [Vector3(0, 0, d / 2 - thick / 2), w, true],
					[Vector3(-w / 2 + thick / 2, 0, 0), d, false], [Vector3(w / 2 - thick / 2, 0, 0), d, false]]
				for wl in walls:
					var segs := 3
					var ln: float = wl[1]
					for s in segs:
						if rng.randf() < 0.22:
							continue
						var sh := ht * rng.randf_range(0.3, 1.0)
						var off := (s - (segs - 1) / 2.0) * ln / segs
						var size := Vector3(ln / segs, sh, thick) if wl[2] else Vector3(thick, sh, ln / segs)
						var pos: Vector3 = c + wl[0] + (Vector3(off, sh / 2, 0) if wl[2] else Vector3(0, sh / 2, off))
						g.add(Geo.box(size), Geo.xf(pos), M.plaster if rng.randf() < 0.6 else M.brick)
						g.add(Geo.box(size * Vector3(1.02, 0.08, 1.02)), Geo.xf(pos + Vector3(0, sh / 2, 0)), M.charred)
						_phys(body, pos, size)
				for k in 6:
					g.add(Geo.box(Vector3(rng.randf_range(4, 10), rng.randf_range(2, 5), rng.randf_range(4, 9))),
						Geo.xf(c + Vector3(rng.randf_range(-w / 3, w / 3), 1.5, rng.randf_range(-d / 3, d / 3)), Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)), M.rubble)
				if rng.randf() < 0.4:
					smokes.append(c + Vector3(0, 4, 0))
			"bunker":
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), M.concrete)
				g.add(Geo.box(Vector3(w + 4, 2.5, d + 4)), Geo.xf(c + Vector3(0, ht + 1.0, 0)), M.concrete_d)
				g.add(Geo.box(Vector3(w * 0.5, 2.0, 1.0)), Geo.xf(c + Vector3(0, ht * 0.62, -d / 2 - 0.2)), M.charred)
				g.add(Geo.box(Vector3(w * 0.5, 2.0, 1.0)), Geo.xf(c + Vector3(0, ht * 0.62, d / 2 + 0.2)), M.charred)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht + 2, d))
			"sandbags":
				var horiz := w >= d
				var ln := w if horiz else d
				var n := int(ln / 4.6)
				for layer in 2:
					for i in n:
						var t := (i + 0.5 * layer) * ln / n - ln / 2 + 2.3
						if t > ln / 2 - 1.0:
							continue
						var p := Vector3(t, 1.1 + layer * 2.1, 0) if horiz else Vector3(0, 1.1 + layer * 2.1, t)
						g.add(bag, Geo.xf(c + p, Vector3(0, (0.0 if horiz else PI / 2) + rng.randf_range(-0.12, 0.12), rng.randf_range(-0.05, 0.05))), M.sand, true)
				_phys(body, c + Vector3(0, 2.5, 0), Vector3(w, 5, d))
			"hedgehogs":
				var horiz := w >= d
				var ln := w if horiz else d
				var n := maxi(1, int(ln / 16.0))
				for i in n:
					var t := (i + 0.5) * ln / n - ln / 2
					var p := c + (Vector3(t, 4.2, 0) if horiz else Vector3(0, 4.2, t))
					var spin := rng.randf() * TAU
					for k in 3:
						var bs := Basis(Vector3.UP, spin + k * TAU / 3.0) * Basis(Vector3.BACK, 0.62)
						g.add(Geo.box(Vector3(15, 1.3, 1.3)), Transform3D(bs, p), M.rust)
			"wreck_tank":
				var yaw := rng.randf() * TAU
				var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, rng.randf_range(-0.05, 0.05))
				g.add(Geo.box(Vector3(30, 8, 18)), Transform3D(bs, c + Vector3(0, 4, 0)), M.charred)
				g.add(Geo.box(Vector3(34, 5, 6)), Transform3D(bs, c + bs * Vector3(0, 2.5, 8)), M.rust)
				g.add(Geo.box(Vector3(34, 5, 6)), Transform3D(bs, c + bs * Vector3(0, 2.5, -8)), M.rust)
				var tb := bs * Basis(Vector3.UP, rng.randf_range(-1.2, 1.2)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
				var tp := c + bs * Vector3(rng.randf_range(-3, 3), 10.5, rng.randf_range(-2, 2))
				g.add(Geo.cyl(6.0, 7.0, 6.0, 10), Transform3D(tb, tp), M.charred)
				g.add(Geo.cyl(0.9, 1.1, 18, 8), Transform3D(tb * Basis(Vector3.BACK, -PI / 2 - 0.2), tp + tb * Vector3(12, -1.5, 0)), M.rust)
				_phys(body, c + Vector3(0, 6, 0), Vector3(w, 12, d), yaw)
				if rng.randf() < 0.5:
					smokes.append(c + Vector3(0, 10, 0))
			"wreck_truck":
				var yaw := rng.randf() * TAU
				var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
				g.add(Geo.box(Vector3(9, 8, 12)), Transform3D(bs, c + bs * Vector3(11, 5, 0)), M.rust)
				g.add(Geo.box(Vector3(20, 5, 13)), Transform3D(bs, c + bs * Vector3(-4, 4, 0)), M.charred)
				for wx: float in [11.0, -1.0, -9.0]:
					for s: float in [6.5, -6.5]:
						g.add(Geo.cyl(2.6, 2.6, 2.0, 10), Transform3D(bs * Basis(Vector3.RIGHT, PI / 2), c + bs * Vector3(wx, 2.4, s)), M.charred)
				_phys(body, c + Vector3(0, 5, 0), Vector3(w, 10, d), yaw)
			"tent":
				var tent := PrismMesh.new()
				tent.size = Vector3(d, ht, w)
				g.add(tent, Geo.xf(c + Vector3(0, ht / 2, 0), Vector3(0, PI / 2, 0)), M.canvas, true)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht, d))
			"rock":
				var xfm := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(w * 1.12, ht * 1.7, d * 1.12)), c + Vector3(0, ht * 0.3, 0))
				g.add(rock_base, xfm, M.rock, true)
				for k in 2:
					var sz := rng.randf_range(8, 16)
					g.add(rock_base, Transform3D(Basis.from_scale(Vector3(sz, sz * 0.7, sz)), c + Vector3(rng.randf_range(-w, w) * 0.6, sz * 0.15, rng.randf_range(-d, d) * 0.6)), M.rock, true)
				_phys(body, c + Vector3(0, ht * 0.55, 0), Vector3(w * 0.95, ht * 1.1, d * 0.95))
			"tower", "ruin_tower":
				var cols := 3 if w > 110 else 2
				var rows := 3 if d > 110 else 2
				for ix in cols:
					for iz in rows:
						var cw := w / cols
						var cd := d / rows
						var hgt := ht if o.kind == "tower" else ht * rng.randf_range(0.3, 1.0)
						var p := c + Vector3(-w / 2 + cw * (ix + 0.5), hgt / 2 - 3, -d / 2 + cd * (iz + 0.5))
						g.add(Geo.box(Vector3(cw, hgt + 6, cd)), Geo.xf(p), win)
						g.add(Geo.box(Vector3(cw + 1, 1.6, cd + 1)), Geo.xf(p + Vector3(0, hgt / 2 + 3.6, 0)), M.snow if winter else M.concrete_d)
						_phys(body, p + Vector3(0, 3, 0), Vector3(cw, hgt, cd))
						if o.kind == "ruin_tower":
							for k in 2:
								var jh := rng.randf_range(3, 12)
								g.add(Geo.box(Vector3(rng.randf_range(4, cw * 0.4), jh, rng.randf_range(4, cd * 0.4))),
									Geo.xf(p + Vector3(rng.randf_range(-cw, cw) * 0.3, hgt / 2 + 3 + jh / 2, rng.randf_range(-cd, cd) * 0.3)), win)
				if o.kind == "ruin_tower":
					for k in 5:
						var side := Vector3(rng.randf_range(-w, w) * 0.55, 0, (d / 2 + 6) * (1.0 if rng.randf() < 0.5 else -1.0))
						g.add(Geo.box(Vector3(rng.randf_range(5, 12), rng.randf_range(2, 5), rng.randf_range(5, 10))),
							Geo.xf(c + side + Vector3(0, 1.5, 0), Vector3(rng.randf() * 0.4, rng.randf() * TAU, 0)), M.rubble)
					if rng.randf() < 0.35:
						smokes.append(c + Vector3(0, ht * 0.5, 0))
			"rubble":
				for k in 8:
					var sz := Vector3(rng.randf_range(4, 12), rng.randf_range(2, 6), rng.randf_range(4, 10))
					g.add(Geo.box(sz), Geo.xf(c + Vector3(rng.randf_range(-w, w) * 0.35, sz.y * 0.4, rng.randf_range(-d, d) * 0.35),
						Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)), M.rubble if k % 3 else M.brick)
				_phys(body, c + Vector3(0, 3, 0), Vector3(w, 6, d))
			_:
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), M.concrete)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht, d))

	# мелочь без коллизии: столбы, бочки
	for dc in data.decor:
		var p: Vector2 = dc.pos
		var y: float = terra.height(p.x, p.y)
		if dc.kind == "pole":
			g.add(Geo.cyl(0.6, 0.8, 26, 6), Geo.xf(Vector3(p.x, y + 13, p.y)), M.pole)
			g.add(Geo.box(Vector3(0.6, 0.6, 9)), Geo.xf(Vector3(p.x, y + 24, p.y)), M.pole)
		else:
			for k in 5:
				var bp := p + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
				var lying := rng.randf() < 0.3
				g.add(Geo.cyl(1.6, 1.6, 4.2, 10), Geo.xf(Vector3(bp.x, terra.height(bp.x, bp.y) + (1.6 if lying else 2.1), bp.y), Vector3(PI / 2 if lying else 0.0, rng.randf() * TAU, 0)), M.olive if k % 2 else M.rust)

	# кусты и ели: одна сетка на тон, шейдер делает «сетку» вокруг нашего танка
	var bg := Geo.Group.new()
	bg.extra = true
	var sh := Shader.new()
	sh.code = BUSH_SHADER
	var bmat := ShaderMaterial.new()
	bmat.shader = sh
	var ico := Geo.sphere(7, 4)
	var cone := Geo.cyl(0.0, 0.5, 1.0, 7)
	var tones := {"bush": [Color("3b5f2a"), Color("4f7838")], "shrub": [Color("6f6a38"), Color("8a8448")], "fir": [Color("2a4630"), Color("e9eff2")]}
	for bsh in data.bushes:
		var bp: Vector2 = bsh.pos
		var by: float = terra.height(bp.x, bp.y)
		var cols: Array = tones[bsh.kind]
		var a: Color = cols[0]
		var l: Color = cols[1]
		a.a = float(bsh.r) / 100.0
		l.a = a.a
		for s in bsh.subs:
			var sv: Vector3 = s
			var base := Vector3(bp.x + sv.x, by, bp.y + sv.y)
			var tint := rng.randf_range(0.85, 1.12)
			var ca := Color(a.r * tint, a.g * tint, a.b * tint, a.a)
			if bsh.kind == "fir":
				var h := sv.z * 1.6 + 20.0
				bg.add(cone, Transform3D(Basis.from_scale(Vector3(sv.z * 1.5, h, sv.z * 1.5)), base + Vector3(0, h / 2, 0)), bmat, true, ca, bp)
				bg.add(cone, Transform3D(Basis.from_scale(Vector3(sv.z * 0.64, h * 0.32, sv.z * 0.64)), base + Vector3(0, h * 0.86, 0)), bmat, true, l, bp)
			else:
				var k := 0.75 if bsh.kind == "shrub" else 1.0
				bg.add(ico, Transform3D(Basis.from_scale(Vector3(sv.z * 1.5, sv.z * 1.15, sv.z * 1.5) * k), base + Vector3(0, sv.z * 0.4 * k, 0)), bmat, true, ca, bp)
				bg.add(ico, Transform3D(Basis.from_scale(Vector3(sv.z * 0.8, sv.z * 0.7, sv.z * 0.8) * k), base + Vector3(-3, sv.z * 0.72 * k, -3)), bmat, true, l, bp)
	bg.commit(parent, hq)

	# разрушаемые деревья и заборы: MultiMesh на часть (ствол, крона, забор)
	var parts := _prop_meshes(map_key, M)
	var mms := {}
	for pk in parts:
		var count := 0
		for pr in data.props:
			if pr.kind == pk:
				count += 1
		if count == 0:
			continue
		for part in parts[pk]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = count
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = part[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if hq else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			mms[part] = mm
	var counters := {}
	for pr in data.props:
		var i: int = counters.get(pr.kind, 0)
		counters[pr.kind] = i + 1
		pr.y = terra.height(pr.pos.x, pr.pos.y)
		for part in parts[pr.kind]:
			pr.mms.append([mms[part], i])
		place_prop(pr)

	# трава или камешки
	if not winter:
		var n := 1400 if hq else 600
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var tuft := Geo.Group.new()
		if desert:
			tuft.add(Geo.sphere(5, 3), Transform3D(Basis.from_scale(Vector3(3, 1.6, 2.6)), Vector3.ZERO), M.rock, true)
		else:
			for k in 3:
				tuft.add(Geo.cyl(0.0, 0.9, 4.5, 3), Transform3D(Basis(Vector3.UP, k * 2.1) * Basis(Vector3.BACK, 0.25), Vector3(cos(k * 2.1) * 0.8, 2.0, sin(k * 2.1) * 0.8)), M.rock, true)
		var tmp := Node3D.new()
		var made: Array = tuft.commit(tmp, false)
		mm.mesh = (made[0] as MeshInstance3D).mesh
		tmp.free()
		mm.instance_count = n
		var placed := 0
		for t in n * 3:
			if placed >= n:
				break
			var p := Vector2(rng.randf_range(-200, D.WS + 200), rng.randf_range(-200, D.WS + 200))
			var blocked := false
			for o in data.obst:
				if (o.r as Rect2).grow(4).has_point(p):
					blocked = true
					break
			if blocked:
				continue
			var s := rng.randf_range(0.6, 1.5)
			mm.set_instance_transform(placed, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, terra.height(p.x, p.y), p.y)))
			placed += 1
		mm.visible_instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(Color("55702f") if not desert else Color("9a7c52"))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

	# зоны захвата на ровных площадках
	for z in zones:
		var zp: Vector2 = z.pos
		var zr: float = z.r
		var zy: float = terra.height(zp.x, zp.y)
		var ring := TorusMesh.new()
		ring.inner_radius = zr - 4
		ring.outer_radius = zr
		ring.rings = 56
		ring.ring_segments = 4
		z.ring_mat = mat(Color.WHITE, true)
		var rmi := MeshInstance3D.new()
		rmi.mesh = ring
		rmi.material_override = z.ring_mat
		rmi.position = Vector3(zp.x, zy + 0.8, zp.y)
		rmi.scale = Vector3(1, 0.12, 1)
		parent.add_child(rmi)
		var disc := CylinderMesh.new()
		disc.top_radius = zr - 4
		disc.bottom_radius = zr - 4
		disc.height = 0.2
		disc.radial_segments = 48
		z.disc_mat = mat(Color(1, 1, 1, 0.1), true)
		z.disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var dmi := MeshInstance3D.new()
		dmi.mesh = disc
		dmi.material_override = z.disc_mat
		dmi.position = Vector3(zp.x, zy + 0.6, zp.y)
		dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(dmi)
		g.add(Geo.cyl(0.8, 0.8, 56), Geo.xf(Vector3(zp.x, zy + 28, zp.y)), M.steel)
		var pivot := Node3D.new()
		pivot.position = Vector3(zp.x, zy + 49, zp.y)
		parent.add_child(pivot)
		var q := QuadMesh.new()
		q.size = Vector2(22, 13)
		z.flag_mat = mat(Color.WHITE)
		z.flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var fmi := MeshInstance3D.new()
		fmi.mesh = q
		fmi.material_override = z.flag_mat
		fmi.position = Vector3(11, 0, 0)
		pivot.add_child(fmi)
		z.flag = pivot

	g.commit(parent, hq)
	return {"bush_mat": bmat, "smokes": smokes}


static func _phys(body: StaticBody3D, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	body.add_child(cs)


## Сетки разрушаемых объектов: для каждого вида — список [сетка, материал].
static func _prop_meshes(map_key: String, M: Dictionary) -> Dictionary:
	var out := {}
	var trunk := mat(Color("4b3a2a"))
	var leaves := mat(Color("3f6129"))
	var t := Geo.Group.new()
	t.add(Geo.cyl(0.8, 1.4, 20, 7), Geo.xf(Vector3(0, 10, 0)), trunk)
	var crown := Geo.Group.new()
	for k in 4:
		var a := k * 1.7
		crown.add(Geo.sphere(7, 4), Transform3D(Basis.from_scale(Vector3(13, 11, 13) * (1.0 - k * 0.08)), Vector3(cos(a) * 3.5, 22 + k * 2.5, sin(a) * 3.5)), leaves, true)
	out["tree"] = [[_one(t), trunk], [_one(crown), leaves]]
	var palm_t := Geo.Group.new()
	for k in 4:
		palm_t.add(Geo.cyl(0.7, 0.9, 8.5, 6), Geo.xf(Vector3(k * 0.6, 4 + k * 8, 0), Vector3(0, 0, -0.06 * k)), trunk)
	var fronds := Geo.Group.new()
	var green := mat(Color("4d6a2b"))
	for k in 7:
		var a := k * TAU / 7.0
		fronds.add(Geo.box(Vector3(12, 0.4, 3)), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.45), Vector3(2.4 + cos(a) * 5, 34, sin(a) * 5)), green)
	out["palm"] = [[_one(palm_t), trunk], [_one(fronds), green]]
	var bare := Geo.Group.new()
	var dark_wood := mat(Color("3a302a"))
	bare.add(Geo.cyl(0.6, 1.2, 22, 6), Geo.xf(Vector3(0, 11, 0)), dark_wood)
	for k in 5:
		var a := k * 1.3
		bare.add(Geo.cyl(0.2, 0.45, 9, 5), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.9), Vector3(cos(a) * 2.5, 14 + k * 1.6, sin(a) * 2.5)), dark_wood)
	out["bare"] = [[_one(bare), dark_wood]]
	var fence := Geo.Group.new()
	var plank := mat(Color("6e5a40"))
	for x: float in [-10.0, 10.0]:
		fence.add(Geo.box(Vector3(1.2, 9, 1.2)), Geo.xf(Vector3(x, 4.5, 0)), plank)
	for y: float in [3.0, 6.5]:
		fence.add(Geo.box(Vector3(22, 1.2, 0.5)), Geo.xf(Vector3(0, y, 0)), plank)
	out["fence"] = [[_one(fence), plank]]
	return out


static func _one(g: Geo.Group) -> Mesh:
	var tmp := Node3D.new()
	var made: Array = g.commit(tmp, false)
	var m: Mesh = (made[0] as MeshInstance3D).mesh
	tmp.free()
	return m


## Ставит (или наклоняет при падении) части разрушаемого объекта.
static func place_prop(pr: Prop) -> void:
	var base := Vector3(pr.pos.x, pr.y, pr.pos.y)
	var b := Basis(Vector3.UP, -pr.rot) * Basis.from_scale(Vector3(pr.scale, pr.scale, pr.scale))
	if pr.fall > 0.0:
		# ось up × направление падения: верх уходит в сторону толчка
		var axis := Vector3(pr.fall_dir.y, 0, -pr.fall_dir.x).normalized()
		var ang := minf(pr.fall, 1.0)
		b = Basis(axis, ang * ang * (PI / 2 - 0.15)) * b
	for e in pr.mms:
		(e[0] as MultiMesh).set_instance_transform(e[1], Transform3D(b, base))
