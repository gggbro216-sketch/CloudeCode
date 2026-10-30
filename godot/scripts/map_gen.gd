extends RefCounted
## Карты: расстановка объектов (Прохоровка, Эль-Аламейн, Сталинград, Нормандия, Берлин, Арденны)
## и постройка 3D-сцены. На каждой карте три направления: фланг с высотой, фланг с деревней
## или плотной застройкой и открытый центр.
## Логика боя работает на плоскости: точка карты (x, y) — это (x, высота рельефа, y) в 3D.
## Неподвижные объекты сливаются в одну сетку на материал; деревья и заборы — разрушаемые.

const D = preload("res://scripts/data.gd")
const Geo = preload("res://scripts/geo.gd")
const TexLib = preload("res://scripts/textures.gd")


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
		out.append(_zone(Vector2(ws * 0.24, ws / 2), 100.0, -1, "A"))
		out.append(_zone(Vector2(ws / 2, ws / 2), 100.0, -1, "B"))
		out.append(_zone(Vector2(ws * 0.76, ws / 2), 100.0, -1, "C"))
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
		# куст — неровная купа из нескольких крон разного размера
		var k := 2 + rng.randi() % 3 if kind == "fir" else 7 + rng.randi() % 4
		for i in k:
			var a := rng.randf() * TAU
			var d := rng.randf() * bush.r * (0.55 if kind == "fir" else 0.75)
			var sr := bush.r * (0.5 + rng.randf() * 0.3) if kind == "fir" else bush.r * (0.28 + rng.randf() * 0.22)
			bush.subs.append(Vector3(cos(a) * d, sin(a) * d, sr))
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
		"normandy":
			return _normandy(rng, zones)
		"berlin":
			return _berlin(rng, zones)
		"ardennes":
			return _ardennes(rng, zones)
	return _prokhorovka(rng, zones)


# ---------- Общее для карт ----------

## Три направления атаки: фланг с высотой, фланг с деревней или плотной застройкой и открытый
## центр между ними. Какой фланг какой — меняется от боя к бою.
static func _lanes(rng: RandomNumberGenerator) -> Dictionary:
	var ws := D.WS
	var left := rng.randf() < 0.5
	return {"hill": ws * (0.2 if left else 0.8), "town": ws * (0.8 if left else 0.2), "mid": ws * 0.5}


## Высота (h > 0) или овраг (h < 0) вдоль отрезка a–b: ровная вершина до core·r, дальше склон.
static func _hill(hills: Array, a: Vector2, b: Vector2, r: float, h: float, core := 0.3) -> void:
	hills.append({"a": a, "b": b, "r": r, "h": h, "core": core})


static func _result(obst: Array, bushes: Array, props: Array, decor: Array, craters: Array, roads: Array, hills: Array, lanes: Dictionary) -> Dictionary:
	return {"obst": obst, "bushes": bushes, "props": props, "decor": decor, "craters": craters, "roads": roads,
		"hills": hills, "lanes": lanes}


## Деревня: дома (kinds — из чего выбирать) вокруг центра, заборы вокруг дворов, деревья в садах.
static func _village(rng: RandomNumberGenerator, obst: Array, props: Array, zones: Array, roads: Array, c: Vector2, n: int,
		rad: float, kinds: Array, ht: Vector2, fences: int, tree: String) -> void:
	var placed := 0
	for t in n * 4:
		if placed >= n:
			break
		var a := rng.randf() * TAU
		var d := rng.randf_range(40, rad)
		var w := rng.randf_range(48, 72)
		var h := rng.randf_range(36, 52)
		var p := c + Vector2(cos(a), sin(a)) * d
		var kind: String = kinds[rng.randi() % kinds.size()]
		if _place_off_road(rng, obst, zones, roads, w, h, kind, rng.randf_range(ht.x, ht.y), Rect2(p - Vector2(30, 30), Vector2(60 + w, 60 + h)), 30.0) != null:
			placed += 1
	for i in fences:
		var fp := c + Vector2(rng.randf_range(-rad, rad), rng.randf_range(-rad, rad))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for k in 5:
			var p := fp + dir * (k * 22.0)
			if _free_point(p, obst, zones, props, 16.0) and _road_dist(p, roads) > 10.0:
				var f := _prop(props, "fence", p, rng, 9.0)
				f.rot = dir.angle()
				f.scale = 1.0
	if tree != "":
		for i in n:
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, rad * 1.1)
			if _free_point(p, obst, zones, props, 22.0) and _road_dist(p, roads) > 12.0:
				_prop(props, tree, p, rng)


## Лес: деревья в эллипсе (гуще к середине) и подлесок, в котором прячутся танки.
static func _forest(rng: RandomNumberGenerator, props: Array, bushes: Array, obst: Array, zones: Array, roads: Array,
		c: Vector2, rad: Vector2, n: int, tree: String, n_bush: int, bush: String) -> void:
	var placed := 0
	for t in n * 3:
		if placed >= n:
			break
		var a := rng.randf() * TAU
		var d := pow(rng.randf(), 0.7)
		var p := c + Vector2(cos(a) * rad.x, sin(a) * rad.y) * d
		if _free_point(p, obst, zones, props, 15.0) and _road_dist(p, roads) > 16.0:
			_prop(props, tree, p, rng)
			placed += 1
	_bushes(rng, bushes, n_bush, obst, zones, [], bush, Rect2(c - rad * 0.85, rad * 1.7))


## Кусты вдоль лесополосы или изгороди, по обе стороны на расстоянии off.
static func _bush_line(rng: RandomNumberGenerator, bushes: Array, obst: Array, zones: Array, kind: String, a: Vector2, b: Vector2, n: int, off: float) -> void:
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	for i in n:
		var p := a.lerp(b, rng.randf()) + nrm * off * (1.0 if rng.randf() < 0.5 else -1.0)
		_bushes(rng, bushes, 1, obst, zones, [], kind, Rect2(p - Vector2(12, 12), Vector2(24, 24)))


static func _wrecks(rng: RandomNumberGenerator, obst: Array, zones: Array, roads: Array, n: int, truck_k: float, area: Rect2, margin := 50.0) -> void:
	for i in n:
		var truck := rng.randf() < truck_k
		_place_off_road(rng, obst, zones, roads, 34 if truck else 36, 16 if truck else 22, "wreck_truck" if truck else "wreck_tank", 10.0, area, margin)


static func _hedgehogs(rng: RandomNumberGenerator, obst: Array, zones: Array, n: int, ln: float, area: Rect2) -> void:
	for i in n:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, ln if hz else 12.0, 12.0 if hz else ln, "hedgehogs", 8.0, area, 45.0, false)


static func _scatter(rng: RandomNumberGenerator, props: Array, obst: Array, zones: Array, roads: Array, kind: String, n: int, area: Rect2, m := 28.0) -> void:
	for i in n:
		var p := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		if _free_point(p, obst, zones, props, m) and _road_dist(p, roads) > 12.0:
			_prop(props, kind, p, rng)


static func _decor(rng: RandomNumberGenerator, decor: Array, obst: Array, zones: Array, props: Array, roads: Array, kind: String, n: int, area: Rect2) -> void:
	for i in n:
		var p := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		if _free_point(p, obst, zones, props, 26.0) and _road_dist(p, roads) > 12.0:
			decor.append({"kind": kind, "pos": p, "rot": rng.randf() * TAU})


static func _poles(decor: Array, obst: Array, zones: Array, props: Array, road: PackedVector2Array, off: float) -> void:
	for i in range(0, road.size(), 2):
		var p := road[i] + Vector2(off, 0)
		if _free_point(p, obst, zones, props, 12.0):
			decor.append({"kind": "pole", "pos": p, "rot": 0.0})


## Расстояние от точки до ближайшей дороги (за вычетом её полуширины).
static func _road_dist(p: Vector2, roads: Array) -> float:
	var best := 1e9
	for road in roads:
		var pts: PackedVector2Array = road.pts
		for i in pts.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, p.distance_to(c) - float(road.w) * 0.5)
	return best


## Ставит постройку, если она не на дороге.
static func _place_off_road(rng: RandomNumberGenerator, obst: Array, zones: Array, roads: Array, w: float, h: float, kind: String,
		ht: float, area: Rect2, margin := 40.0) -> Obst:
	for t in 40:
		var o := _place(rng, obst, zones, w, h, kind, ht, area, margin)
		if o == null:
			return null
		var r := o.r
		var ok := true
		for c in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
			if _road_dist(c, roads) < 12.0:
				ok = false
				break
		if ok:
			return o
		obst.erase(o)
	return null


# ---------- Карты ----------

## Прохоровка: высота 252,2 на одном фланге, совхоз у большой дороги на другом,
## в центре — поле с лесополосами, хутором и балкой.
static func _prokhorovka(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var hills: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	# высота: широкий холм и отрог к центру — за гребнем прячут корпус
	_hill(hills, Vector2(hx, ws * 0.42), Vector2(hx, ws * 0.58), 440.0, 44.0, 0.3)
	_hill(hills, Vector2(hx, ws * 0.5), Vector2(lerpf(hx, ws * 0.5, 0.62), ws * 0.5 + rng.randf_range(-160, 160)), 170.0, 20.0, 0.2)
	# балка: овраг через центр — скрытый подход
	var bx := ws * 0.5 + rng.randf_range(-140, 140)
	var tilt := rng.randf_range(-110, 110)
	_hill(hills, Vector2(bx - tilt, ws * 0.3), Vector2(bx + tilt, ws * 0.7), 80.0, -15.0, 0.25)
	var road := Geo_bezier(Vector2(tx, ws + 100), Vector2(tx + rng.randf_range(-220, 220), ws * 0.68),
		Vector2(tx + rng.randf_range(-220, 220), ws * 0.32), Vector2(tx + rng.randf_range(-150, 150), -100))
	var roads := [{"pts": road, "w": 46.0},
		{"pts": Geo_bezier(Vector2(-100, ws * 0.56), Vector2(ws * 0.3, ws * 0.42), Vector2(ws * 0.62, ws * 0.64), Vector2(ws + 100, ws * 0.46)), "w": 34.0}]
	# совхоз «Октябрьский» у большой дороги
	var vc := Vector2(tx, ws * 0.5 + rng.randf_range(-160, 160))
	_village(rng, obst, props, zones, roads, vc, 15, 420.0, ["house", "ruin"], Vector2(19, 25), 9, "tree")
	# хутор в центре: амбары, стога
	var farm := Vector2(ws * 0.5 + rng.randf_range(-260, 260), ws * 0.5 + rng.randf_range(-320, 320))
	for i in 2:
		_place_off_road(rng, obst, zones, roads, rng.randf_range(60, 76), rng.randf_range(36, 44), "barn", 22.0, Rect2(farm - Vector2(160, 160), Vector2(320, 320)), 24.0)
	_decor(rng, decor, obst, zones, props, roads, "hay", 5, Rect2(farm - Vector2(260, 260), Vector2(520, 520)))
	# окопы и дзоты на высоте
	var top := Rect2(Vector2(hx - 280, ws * 0.37), Vector2(560, ws * 0.26))
	for i in 5:
		_sandbag_nest(rng, obst, zones, top)
	for i in 2:
		_place(rng, obst, zones, 44, 36, "bunker", 11.0, top, 70.0)
	_scatter(rng, props, obst, zones, roads, "tree", 10, top, 34.0)
	_wrecks(rng, obst, zones, roads, 10, 0.2, mid, 60.0)
	for i in 4:
		_sandbag_nest(rng, obst, zones, mid)
	_hedgehogs(rng, obst, zones, 6, 90.0, mid)
	# лесополосы: поперёк поля с прогалом и вдоль, наискось к высоте
	for i in 2:
		var y := ws * (0.4 + 0.2 * i) + rng.randf_range(-40, 40)
		var x0 := ws * 0.33 + rng.randf_range(-60, 60)
		var x1 := ws * 0.67 + rng.randf_range(-60, 60)
		var gap := rng.randf_range(x0 + 140, x1 - 140)
		_tree_line(rng, props, obst, zones, "tree", Vector2(x0, y), Vector2(gap - 55, y + rng.randf_range(-20, 20)), 28.0)
		_tree_line(rng, props, obst, zones, "tree", Vector2(gap + 55, y), Vector2(x1, y + rng.randf_range(-20, 20)), 28.0)
		_bush_line(rng, bushes, obst, zones, "bush", Vector2(x0, y), Vector2(x1, y), 4, 44.0)
	for i in 4:
		var a := Vector2(rng.randf_range(ws * 0.3, ws * 0.7), rng.randf_range(ws * 0.25, ws * 0.65))
		var b := a + Vector2(rng.randf_range(-160, 160), rng.randf_range(260, 420))
		_tree_line(rng, props, obst, zones, "tree", a, b, 30.0)
		_bush_line(rng, bushes, obst, zones, "bush", a, b, 3, 44.0)
	_scatter(rng, props, obst, zones, roads, "tree", 30, Rect2(150, 420, ws - 300, ws - 840), 30.0)
	_bushes(rng, bushes, 44, obst, zones, props, "bush", Rect2(120, 330, ws - 240, ws - 660))
	_decor(rng, decor, obst, zones, props, roads, "hay", 8, mid)
	_decor(rng, decor, obst, zones, props, roads, "crates", 6, top)
	_decor(rng, decor, obst, zones, props, roads, "crates", 4, mid)
	_poles(decor, obst, zones, props, road, 34.0)
	var craters := _craters(rng, 70, obst, zones, mid)
	return _result(obst, bushes, props, decor, craters, roads, hills, L)


## Эль-Аламейн: каменистый хребет вдоль фланга, на другом — оазис с глинобитной деревней и лагерь,
## в центре — открытая пустыня с вади, скалами и минными полями.
static func _alamein(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var hills: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	var roads := [{"pts": Geo_bezier(Vector2(tx + rng.randf_range(-120, 120), ws + 100), Vector2(tx + rng.randf_range(-260, 260), ws * 0.66),
			Vector2(tx + rng.randf_range(-260, 260), ws * 0.34), Vector2(tx + rng.randf_range(-120, 120), -100)), "w": 30.0},
		{"pts": Geo_bezier(Vector2(-100, ws * 0.35), Vector2(ws * 0.35, ws * 0.2), Vector2(ws * 0.55, ws * 0.8), Vector2(ws + 100, ws * 0.66)), "w": 26.0}]
	# хребет: длинный гребень с выходами скал по верху
	var ra := Vector2(hx + rng.randf_range(-70, 70), ws * 0.27)
	var rb := Vector2(hx + rng.randf_range(-70, 70), ws * 0.73)
	_hill(hills, ra, rb, 290.0, 40.0, 0.22)
	for i in 10:
		var p := ra.lerp(rb, (i + rng.randf()) / 10.0) + Vector2(rng.randf_range(-110, 110), 0)
		var s := rng.randf_range(40, 90)
		_place(rng, obst, zones, s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.8, 1.3), "rock", rng.randf_range(18, 32), Rect2(p - Vector2(60, 60), Vector2(120, 120)), 45.0)
	for i in 4:
		_sandbag_nest(rng, obst, zones, Rect2(Vector2(hx - 300, ws * 0.3), Vector2(600, ws * 0.4)))
	# вади: сухое русло наискось через центр
	var s := 1.0 if rng.randf() < 0.5 else -1.0
	_hill(hills, Vector2(ws * 0.5 - s * 170, ws * 0.33), Vector2(ws * 0.5 + s * 170, ws * 0.67), 105.0, -17.0, 0.25)
	# оазис: глинобитные дома под пальмами, рядом — полевой лагерь
	var oc := Vector2(tx, ws * 0.5 + rng.randf_range(-220, 220))
	_village(rng, obst, props, zones, roads, oc, 9, 260.0, ["adobe", "adobe", "ruin"], Vector2(13, 18), 0, "palm")
	for i in 12:
		var p := oc + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 200)
		if _free_point(p, obst, zones, props, 24.0):
			_prop(props, "palm", p, rng)
	var camp := Rect2(Vector2(lerpf(tx, ws * 0.5, 0.45) - 220, oc.y - 300), Vector2(440, 600))
	for i in 5:
		_place(rng, obst, zones, 30, 24, "tent", 12.0, camp, 50.0)
	_wrecks(rng, obst, zones, roads, 4, 0.8, camp, 40.0)
	_decor(rng, decor, obst, zones, props, roads, "barrels", 10, camp)
	_decor(rng, decor, obst, zones, props, roads, "crates", 8, camp)
	# центр: скалы, подбитая техника, минные поля с ежами
	for i in 18:
		var sz := rng.randf_range(50, 130)
		_place(rng, obst, zones, sz * rng.randf_range(0.8, 1.2), sz * rng.randf_range(0.8, 1.2), "rock", rng.randf_range(16, 40), mid, 75.0)
	for i in 6:
		_sandbag_nest(rng, obst, zones, mid)
	_wrecks(rng, obst, zones, roads, 8, 0.4, mid, 60.0)
	_hedgehogs(rng, obst, zones, 5, 90.0, mid)
	_scatter(rng, props, obst, zones, roads, "palm", 8, Rect2(150, 420, ws - 300, ws - 840), 40.0)
	_decor(rng, decor, obst, zones, props, roads, "barrels", 8, mid)
	_bushes(rng, bushes, 30, obst, zones, props, "shrub", Rect2(120, 330, ws - 240, ws - 660))
	var craters := _craters(rng, 55, obst, zones, mid)
	return _result(obst, bushes, props, decor, craters, roads, hills, L)


## Сталинград: Мамаев курган на одном фланге, цеха Тракторного завода на другом,
## в центре — кварталы руин и площадь с фонтаном.
static func _stalingrad(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var hills: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var cell := 300.0
	var street := 110.0
	var bs := cell - street
	var n := int(ceil((ws + 80.0) / cell))
	var kurgan := Vector2(hx, ws * 0.5 + rng.randf_range(-120, 120))
	_hill(hills, kurgan - Vector2(0, 130), kurgan + Vector2(0, 130), 480.0, 50.0, 0.16)
	var plant := Rect2(Vector2(tx - ws * 0.165, ws * 0.29), Vector2(ws * 0.33, ws * 0.42))
	var square := Rect2(Vector2(ws * 0.5 - 180, ws * 0.5 - 180 + rng.randf_range(-160, 160)), Vector2(360, 360))
	var parks: Array = []
	for i in n:
		for j in n:
			var bx := -40.0 + i * cell + street / 2
			var by := -40.0 + j * cell + street / 2
			var block := Rect2(bx, by, bs, bs)
			if block.get_center().distance_to(kurgan) < 470.0 or block.intersects(plant.grow(30)) or block.intersects(square):
				continue
			if rng.randf() < 0.16:
				parks.append(block)
				continue
			var parts: Array = []
			var q := rng.randf()
			if q < 0.45:
				parts.append(Rect2(bx + rng.randf() * 15, by + rng.randf() * 15, bs - 30, bs - 30))
			elif q < 0.72:
				var sp := bs * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(bx, by, sp - 20, bs))
				parts.append(Rect2(bx + sp + 20, by, bs - sp - 20, bs))
			else:
				var sp := bs * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(bx, by, bs, sp - 20))
				parts.append(Rect2(bx, by + sp + 20, bs, bs - sp - 20))
			for pr in parts:
				if excl_ok(pr, zones, 25.0):
					var kind := "ruin_tower" if rng.randf() < 0.75 else "tower"
					obst.append(Obst.new(pr, kind, rng.randf_range(45, 105)))
	# Тракторный завод: цеха с пилообразной крышей в два ряда, между ними — заводские проезды, трубы
	var hall_w := plant.size.x * 0.4
	var hall_d := plant.size.y * 0.24
	for ci in 2:
		for ri in 3:
			var r := Rect2(plant.position + Vector2(plant.size.x * (0.05 + ci * 0.52), plant.size.y * (0.04 + ri * 0.33)), Vector2(hall_w, hall_d))
			r = r.grow_individual(0, 0, rng.randf_range(-30, 0), rng.randf_range(-20, 0))
			if excl_ok(r, zones, 25.0):
				obst.append(Obst.new(r, "factory", rng.randf_range(30, 40)))
	for i in 3:
		_place(rng, obst, zones, 18, 18, "chimney", rng.randf_range(110, 140), plant, 26.0)
	_wrecks(rng, obst, zones, [], 4, 0.6, plant, 30.0)
	_decor(rng, decor, obst, zones, props, [], "crates", 5, plant)
	for i in 4:
		_place(rng, obst, zones, rng.randf_range(30, 50), rng.randf_range(24, 40), "rubble", 6.0, plant, 30.0)
	# Мамаев курган: окопы, воронки, обломанные деревья, водонапорные баки на вершине
	var kz := Rect2(kurgan - Vector2(400, 400), Vector2(800, 800))
	for i in 2:
		_place(rng, obst, zones, 40, 40, "water_tank", 22.0, Rect2(kurgan - Vector2(140, 140), Vector2(280, 280)), 60.0)
	for i in 7:
		_sandbag_nest(rng, obst, zones, kz)
	_wrecks(rng, obst, zones, [], 3, 0.3, kz, 50.0)
	_scatter(rng, props, obst, zones, [], "bare", 26, kz, 26.0)
	_bushes(rng, bushes, 6, obst, zones, props, "fir", kz)
	# площадь: фонтан посередине
	var fc := square.get_center() + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
	obst.append(Obst.new(Rect2(fc - Vector2(17, 17), Vector2(34, 34)), "fountain", 5.0))
	var street_area := Rect2(120, 450, ws - 240, ws - 900)
	for i in 14:
		_place(rng, obst, zones, rng.randf_range(30, 50), rng.randf_range(24, 40), "rubble", 6.0, street_area, 30.0)
	_hedgehogs(rng, obst, zones, 9, 60.0, street_area)
	for i in 6:
		_sandbag_nest(rng, obst, zones, street_area)
	_wrecks(rng, obst, zones, [], 8, 0.4, street_area, 40.0)
	_decor(rng, decor, obst, zones, props, [], "crates", 6, street_area)
	_decor(rng, decor, obst, zones, props, [], "crates", 4, kz)
	for p in parks:
		_bushes(rng, bushes, 2, obst, zones, props, "fir", p)
		for k in 3:
			var tp := Vector2(p.position.x + rng.randf() * p.size.x, p.position.y + rng.randf() * p.size.y)
			if _free_point(tp, obst, zones, props, 24.0):
				_prop(props, "bare", tp, rng)
	_bushes(rng, bushes, 12, obst, zones, props, "fir", Rect2(120, 330, ws - 240, ws - 660))
	var roads: Array = []
	for i in n + 1:
		var c := -40.0 + i * cell
		roads.append({"pts": PackedVector2Array([Vector2(c, -100), Vector2(c, ws + 100)]), "w": street - 20.0})
		roads.append({"pts": PackedVector2Array([Vector2(-100, c), Vector2(ws + 100, c)]), "w": street - 20.0})
	var craters := _craters(rng, 36, obst, zones, kz)
	craters.append_array(_craters(rng, 40, obst, zones, street_area))
	return _result(obst, bushes, props, decor, craters, roads, hills, L)


## Нормандия: высота 112 с рощей на вершине, деревня с церковью у перекрёстка на другом фланге,
## между ними — бокаж.
static func _normandy(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var hills: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	var hill_top := Vector2(hx, ws * 0.5 + rng.randf_range(-120, 120))
	_hill(hills, hill_top - Vector2(0, 90), hill_top + Vector2(0, 90), 440.0, 40.0, 0.25)
	# просёлки: один через деревню, второй поперёк карты
	var cross := Vector2(tx, ws * 0.5 + rng.randf_range(-150, 150))
	var road1 := Geo_bezier(Vector2(tx + rng.randf_range(-150, 150), ws + 100), cross + Vector2(rng.randf_range(-120, 120), ws * 0.2),
		cross + Vector2(rng.randf_range(-120, 120), -ws * 0.2), Vector2(tx + rng.randf_range(-150, 150), -100))
	var road2 := Geo_bezier(Vector2(-100, cross.y + rng.randf_range(-200, 200)), Vector2(ws * 0.33, cross.y + rng.randf_range(-250, 250)),
		Vector2(ws * 0.66, cross.y + rng.randf_range(-250, 250)), Vector2(ws + 100, cross.y + rng.randf_range(-200, 200)))
	var roads := [{"pts": road1, "w": 34.0}, {"pts": road2, "w": 30.0}]
	# деревня с церковью у перекрёстка
	_place_off_road(rng, obst, zones, roads, 40, 84, "church", 34.0, Rect2(cross - Vector2(170, 170), Vector2(340, 340)), 30.0)
	var village := Rect2(cross - Vector2(340, 330), Vector2(680, 660))
	for i in 13:
		var w := rng.randf_range(44, 66)
		var h := rng.randf_range(34, 48)
		_place_off_road(rng, obst, zones, roads, w, h, "house" if rng.randf() < 0.6 else "ruin", rng.randf_range(18, 24), village, 26.0)
	# фермы на отшибе: дом, амбар, рядом яблоневый сад
	var orchards: Array = []
	for f in 5:
		var c := Vector2(rng.randf_range(300, ws - 300), rng.randf_range(650, ws - 650))
		if c.distance_to(cross) < 520.0 or c.distance_to(hill_top) < 380.0:
			continue
		var area := Rect2(c - Vector2(140, 140), Vector2(280, 280))
		_place_off_road(rng, obst, zones, roads, rng.randf_range(46, 60), rng.randf_range(34, 42), "house", 20.0, area, 24.0)
		_place_off_road(rng, obst, zones, roads, rng.randf_range(60, 76), rng.randf_range(36, 44), "barn", 22.0, area, 24.0)
		orchards.append(Rect2(c + Vector2(rng.randf_range(-260, 60), rng.randf_range(-260, 60)), Vector2(200, 200)))
	# бокаж: сетка полей, по границам — земляные валы с живой изгородью и проходами;
	# склоны высоты открыты, на вершине — роща
	var xs: Array = []
	var x := 90.0
	while x < ws - 200.0:
		x += rng.randf_range(300, 420)
		if x < ws - 200.0:
			xs.append(x)
	var ys: Array = [440.0]
	var y := 440.0
	while y < ws - 640.0:
		y += rng.randf_range(300, 400)
		ys.append(minf(y, ws - 440.0))
	if ys[-1] < ws - 440.0:
		ys.append(ws - 440.0)
	var edges: Array = []  # [начало, конец, крайняя ли] отрезков границ полей
	var gx: Array = [90.0] + xs + [ws - 90.0]
	for j in ys.size():
		for i in gx.size() - 1:
			var yy: float = ys[j] + rng.randf_range(-20, 20)
			edges.append([Vector2(gx[i], yy), Vector2(gx[i + 1], yy), j == 0 or j == ys.size() - 1])
	for i in xs.size():
		for j in ys.size() - 1:
			var xx: float = xs[i] + rng.randf_range(-20, 20)
			edges.append([Vector2(xx, ys[j]), Vector2(xx, ys[j + 1]), false])
	var buildings := obst.duplicate()
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var outer: bool = e[2]
		var on_hill := Geometry2D.get_closest_point_to_segment(hill_top, a, b).distance_to(hill_top) < 300.0
		if not outer and (rng.randf() < 0.16 or (on_hill and rng.randf() < 0.75)):
			continue  # снесённая изгородь: поле открыто
		var ln := a.distance_to(b)
		var dir := (b - a) / ln
		# проходы: на краях полосы старта — три, внутри — один-два
		var gaps: Array = []
		for g in (3 if outer else 1 + rng.randi() % 2):
			var gc := rng.randf_range(50, ln - 50)
			gaps.append([gc - rng.randf_range(32, 42), gc + rng.randf_range(32, 42)])
		var t := 0.0
		var piece_start := 0.0
		var step := 8.0
		var open := false
		while t <= ln:
			var p := a + dir * t
			var cut := _road_dist(p, roads) < 14.0 or p.distance_to(hill_top) < 190.0
			for g in gaps:
				if t > g[0] and t < g[1]:
					cut = true
			if cut or t + step > ln:
				var end_t := t if cut else ln
				if not open and end_t - piece_start > 24.0:
					var p0 := a + dir * piece_start
					var p1 := a + dir * end_t
					var r := Rect2(p0.min(p1), Vector2.ZERO).expand(p1.max(p0))
					r = r.grow_individual(7 if absf(dir.y) > 0.5 else 0, 7 if absf(dir.x) > 0.5 else 0, 7 if absf(dir.y) > 0.5 else 0, 7 if absf(dir.x) > 0.5 else 0)
					if excl_ok(r, zones, 20.0) and not _hits(r, buildings, 12.0):
						obst.append(Obst.new(r, "hedgerow", 19.0))
				open = cut
				piece_start = t
			elif open:
				open = false
				piece_start = t
			t += step
	# роща на вершине высоты
	_forest(rng, props, bushes, obst, zones, roads, hill_top, Vector2(170, 150), 48, "tree", 7, "bush")
	# сады: яблони рядами
	for orc in orchards:
		var r: Rect2 = orc
		var px := r.position.x
		while px < r.end.x:
			var py := r.position.y
			while py < r.end.y:
				var p := Vector2(px + rng.randf_range(-4, 4), py + rng.randf_range(-4, 4))
				if _free_point(p, obst, zones, props, 18.0) and _road_dist(p, roads) > 10.0:
					_prop(props, "apple", p, rng)
				py += 34.0
			px += 34.0
	# одиночные деревья у изгородей
	_scatter(rng, props, obst, zones, roads, "tree", 44, Rect2(150, 420, ws - 300, ws - 840), 26.0)
	# обломки: подбитые танки и грузовики, планёры «Хорса» после высадки
	_wrecks(rng, obst, zones, roads, 8, 0.4, mid, 50.0)
	for i in 3:
		_place_off_road(rng, obst, zones, roads, 70, 26, "glider", 9.0, mid, 60.0)
	for i in 4:
		_sandbag_nest(rng, obst, zones, mid)
	# стога сена и телеграфные столбы вдоль дороги
	_decor(rng, decor, obst, zones, props, roads, "hay", 20, Rect2(150, 420, ws - 300, ws - 840))
	_decor(rng, decor, obst, zones, props, roads, "crates", 8, mid)
	_poles(decor, obst, zones, props, road1, 30.0)
	_bushes(rng, bushes, 24, obst, zones, props, "bush", Rect2(120, 330, ws - 240, ws - 660))
	var craters := _craters(rng, 42, obst, zones, mid)
	return _result(obst, bushes, props, decor, craters, roads, hills, L)


## Берлин: Тиргартен с зенитной башней на одном фланге, плотные кварталы на другом,
## в центре — Рейхстаг с площадью перед ним; через весь город — проспект Восток — Запад.
static func _berlin(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var cell := 330.0
	var street := 130.0
	var bs := cell - street
	var n := int(ceil((ws + 120.0) / cell))
	var axis_y := ws * 0.5  # ось Восток — Запад: широкий проспект через весь город и парк
	var roads: Array = [{"pts": PackedVector2Array([Vector2(-100, axis_y), Vector2(ws + 100, axis_y)]), "w": 150.0}]
	var landmarks: Array = []
	var park := Rect2(Vector2(hx - ws * 0.15, ws * 0.28), Vector2(ws * 0.3, ws * 0.44))
	landmarks.append(park)
	# Рейхстаг — в центре на стороне обороны, перед ним — Королевская площадь
	var reich := Rect2(Vector2(ws * 0.5 - 160 + rng.randf_range(-120, 120), rng.randf_range(560, 700)), Vector2(320, 170))
	if excl_ok(reich, zones, 30.0):
		obst.append(Obst.new(reich, "reichstag", 40.0))
		landmarks.append(reich.grow_individual(60, 60, 60, 220))
	# зенитная башня «Зоо» — в Тиргартене
	var flak := Rect2(park.position + Vector2(rng.randf_range(60, park.size.x - 190), rng.randf_range(80, park.size.y - 210)), Vector2(130, 130))
	if absf(flak.get_center().y - axis_y) < 150.0:
		flak.position.y += 260.0 * (1.0 if rng.randf() < 0.5 else -1.0)
	if excl_ok(flak, zones, 30.0) and not _hits(flak, obst, 80.0):
		obst.append(Obst.new(flak, "flak_tower", 100.0))
	var parks: Array = []
	for i in n:
		for j in n:
			var bx := -60.0 + i * cell + street / 2
			var by := -60.0 + j * cell + street / 2
			var block := Rect2(bx, by, bs, bs)
			if absf(block.get_center().y - axis_y) < cell * 0.5:
				continue  # на месте проспекта
			var skip := false
			for lm in landmarks:
				if block.intersects(lm):
					skip = true
			if skip:
				continue
			var dense := absf(block.get_center().x - tx) < ws * 0.18
			if not dense and rng.randf() < 0.14:
				parks.append(block)
				continue
			# доходные дома по периметру квартала, внутри — двор
			var parts: Array = []
			var depth := bs * 0.32
			parts.append(Rect2(bx, by, bs, depth))
			parts.append(Rect2(bx, by + bs - depth, bs, depth))
			if dense or rng.randf() < 0.6:
				parts.append(Rect2(bx, by + depth + 12, depth, bs - 2 * depth - 24))
			if dense or rng.randf() < 0.6:
				parts.append(Rect2(bx + bs - depth, by + depth + 12, depth, bs - 2 * depth - 24))
			for pr in parts:
				if rng.randf() < (0.06 if dense else 0.12):
					continue  # разрушен до основания: только груда обломков
				if excl_ok(pr, zones, 25.0):
					var kind := "ruin_block" if rng.randf() < 0.55 else "block"
					obst.append(Obst.new(pr, kind, rng.randf_range(55, 85)))
	var street_area := Rect2(120, 450, ws - 240, ws - 900)
	var dense_area := Rect2(Vector2(tx - ws * 0.18, 450), Vector2(ws * 0.36, ws - 900))
	# баррикады поперёк улиц, трамваи, ежи, подбитая техника; в плотных кварталах баррикад больше
	for i in 14:
		_place(rng, obst, zones, rng.randf_range(30, 50), rng.randf_range(24, 40), "rubble", 6.0, street_area, 30.0)
	for i in 8:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, 64.0 if hz else 14.0, 14.0 if hz else 64.0, "barricade", 8.0, dense_area if i < 5 else street_area, 40.0)
	for i in 5:
		var hz := rng.randf() < 0.5
		_place(rng, obst, zones, 48.0 if hz else 12.0, 12.0 if hz else 48.0, "tram", 13.0, street_area, 40.0)
	_hedgehogs(rng, obst, zones, 8, 60.0, street_area)
	for i in 6:
		_sandbag_nest(rng, obst, zones, street_area)
	_wrecks(rng, obst, zones, [], 9, 0.5, street_area, 40.0)
	_decor(rng, decor, obst, zones, props, [], "crates", 8, street_area)
	# Тиргартен: изрытый воронками парк с обломанными деревьями, окопы
	_scatter(rng, props, obst, zones, roads, "bare", 70, park, 22.0)
	_bushes(rng, bushes, 12, obst, zones, props, "bush", park)
	for i in 5:
		_sandbag_nest(rng, obst, zones, park)
	_wrecks(rng, obst, zones, roads, 3, 0.5, park, 40.0)
	for p in parks:
		for k in 6:
			var tp := Vector2(p.position.x + rng.randf() * p.size.x, p.position.y + rng.randf() * p.size.y)
			if _free_point(tp, obst, zones, props, 22.0):
				_prop(props, "bare", tp, rng)
		_bushes(rng, bushes, 1, obst, zones, props, "bush", p)
	# деревья и фонари вдоль проспекта
	var xx := 120.0
	while xx < ws - 120.0:
		for sd: float in [-1.0, 1.0]:
			var p := Vector2(xx + rng.randf_range(-6, 6), axis_y + sd * 62.0)
			if _free_point(p, obst, zones, props, 16.0):
				if int(xx / 70.0) % 2 == 0:
					_prop(props, "bare", p, rng)
				else:
					decor.append({"kind": "lamp", "pos": p, "rot": 0.0})
		xx += 70.0
	for i in n + 1:
		var c := -60.0 + i * cell
		var vert := {"pts": PackedVector2Array([Vector2(c, -100), Vector2(c, ws + 100)]), "w": street - 20.0}
		var horz := {"pts": PackedVector2Array([Vector2(-100, c), Vector2(ws + 100, c)]), "w": street - 20.0}
		# в парке улиц нет: только аллея проспекта
		if c < park.position.x or c > park.end.x:
			roads.append(vert)
		else:
			roads.append({"pts": PackedVector2Array([Vector2(c, -100), Vector2(c, park.position.y)]), "w": street - 20.0})
			roads.append({"pts": PackedVector2Array([Vector2(c, park.end.y), Vector2(c, ws + 100)]), "w": street - 20.0})
		if c < park.position.y or c > park.end.y:
			roads.append(horz)
		else:
			roads.append({"pts": PackedVector2Array([Vector2(-100, c), Vector2(park.position.x, c)]), "w": street - 20.0})
			roads.append({"pts": PackedVector2Array([Vector2(park.end.x, c), Vector2(ws + 100, c)]), "w": street - 20.0})
	var craters := _craters(rng, 40, obst, zones, park)
	craters.append_array(_craters(rng, 36, obst, zones, street_area))
	return _result(obst, bushes, props, decor, craters, roads, [], L)


## Арденны: лесистый гребень на одном фланге, бельгийская деревня у перекрёстка на другом,
## в центре — заснеженные поля с рощами, линия надолбов «Западного вала».
static func _ardennes(rng: RandomNumberGenerator, zones: Array) -> Dictionary:
	var ws := D.WS
	var obst: Array = []
	var props: Array = []
	var bushes: Array = []
	var decor: Array = []
	var hills: Array = []
	var L := _lanes(rng)
	var hx: float = L.hill
	var tx: float = L.town
	var mid := Rect2(140, 440, ws - 280, ws - 880)
	var ra := Vector2(hx + rng.randf_range(-60, 60), ws * 0.29)
	var rb := Vector2(hx + rng.randf_range(-60, 60), ws * 0.71)
	_hill(hills, ra, rb, 340.0, 42.0, 0.3)
	# дороги: шоссе через деревню и лесная дорога через гребень к перекрёстку
	var cross := Vector2(tx, ws * 0.5 + rng.randf_range(-150, 150))
	var road1 := Geo_bezier(Vector2(tx + rng.randf_range(-150, 150), ws + 100), cross + Vector2(rng.randf_range(-140, 140), ws * 0.22),
		cross + Vector2(rng.randf_range(-140, 140), -ws * 0.22), Vector2(tx + rng.randf_range(-150, 150), -100))
	var ry := ws * 0.5 + rng.randf_range(-240, 240)
	var road2 := Geo_bezier(cross, Vector2(ws * 0.5, cross.y + rng.randf_range(-200, 200)), Vector2(hx, ry + rng.randf_range(-150, 150)),
		Vector2(-100.0 if hx < ws * 0.5 else ws + 100.0, ry))
	var roads := [{"pts": road1, "w": 38.0}, {"pts": road2, "w": 28.0}]
	# деревня: каменные дома под сланцем, церковь, амбары
	_place_off_road(rng, obst, zones, roads, 40, 84, "church", 34.0, Rect2(cross - Vector2(170, 170), Vector2(340, 340)), 30.0)
	_village(rng, obst, props, zones, roads, cross, 12, 360.0, ["house", "house", "ruin"], Vector2(18, 24), 8, "bare")
	for i in 3:
		_place_off_road(rng, obst, zones, roads, rng.randf_range(60, 76), rng.randf_range(36, 44), "barn", 22.0, Rect2(cross - Vector2(420, 420), Vector2(840, 840)), 26.0)
	# лес на гребне; «Западный вал» — доты на склоне, перед ним надолбы с проходами
	_forest(rng, props, bushes, obst, zones, roads, (ra + rb) * 0.5, Vector2(300, ws * 0.27), 240, "spruce", 26, "fir")
	var face := 1.0 if hx < ws * 0.5 else -1.0  # склон гребня, обращённый к центру
	for i in 2:
		_place(rng, obst, zones, 44, 36, "bunker", 11.0, Rect2(Vector2(hx + face * 200 - 80, ws * 0.35), Vector2(160, ws * 0.3)), 80.0)
	var tz := hx + face * 340.0
	var ty := ws * 0.5 + rng.randf_range(-200, 200)
	for k in 3:
		var a := Vector2(tz, ty + (k - 1) * 230.0 - 80.0)
		var r := Rect2(a, Vector2(26, 150))
		if excl_ok(r, zones, 20.0) and not _hits(r, obst, 20.0) and _road_dist(r.get_center(), roads) > 60.0:
			obst.append(Obst.new(r, "teeth", 7.0, false))
	# рощи в центре и у краёв поля
	for i in 5:
		var c := Vector2(rng.randf_range(ws * 0.3, ws * 0.7), rng.randf_range(ws * 0.22, ws * 0.78))
		if c.distance_to(cross) < 420.0:
			continue
		_forest(rng, props, bushes, obst, zones, roads, c, Vector2(rng.randf_range(80, 140), rng.randf_range(80, 140)), 26, "spruce", 3, "fir")
	# ольха и вязы вдоль шоссе
	for i in range(1, road1.size() - 1, 2):
		for sd: float in [-1.0, 1.0]:
			var p: Vector2 = road1[i] + Vector2(sd * 36.0, 0)
			if _free_point(p, obst, zones, props, 18.0):
				_prop(props, "bare", p, rng)
	# окопы, подбитые машины, стога
	for i in 6:
		_sandbag_nest(rng, obst, zones, mid)
	_wrecks(rng, obst, zones, roads, 8, 0.5, mid, 50.0)
	_decor(rng, decor, obst, zones, props, roads, "hay", 8, mid)
	_decor(rng, decor, obst, zones, props, roads, "crates", 4, Rect2(cross - Vector2(380, 380), Vector2(760, 760)))
	_decor(rng, decor, obst, zones, props, roads, "crates", 6, mid)
	_poles(decor, obst, zones, props, road1, 30.0)
	_scatter(rng, props, obst, zones, roads, "spruce", 30, Rect2(150, 420, ws - 300, ws - 840), 30.0)
	_bushes(rng, bushes, 28, obst, zones, props, "fir", Rect2(120, 330, ws - 240, ws - 660))
	var craters := _craters(rng, 40, obst, zones, mid)
	return _result(obst, bushes, props, decor, craters, roads, hills, L)


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


const BUSH_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 fade_a;
uniform vec3 fade_b;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying vec2 center;
varying float rad;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	center = UV2;
	rad = COLOR.a * 100.0;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = NORMAL;
}

void fragment() {
	// куст, в котором стоит наш танк или камера, становится «сетчатым»
	if (distance(center, fade_a.xz) < rad + 8.0 || distance(center, fade_b.xz) < rad + 4.0) {
		if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0) {
			discard;
		}
	}
	// листва пятнами: светлые верхушки, тёмная глубина и низ
	float n = texture(noise, wp.xz * 0.06 + wp.y * 0.05).r * 0.6 + texture(noise, wp.xz * 0.21 - wp.y * 0.13).r * 0.4;
	ALBEDO = COLOR.rgb * (0.62 + 0.62 * n) * (0.72 + 0.28 * clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 1.0;
}
"""


## Строит сцену карты. Возвращает материалы кустов (для полупрозрачности), MultiMesh разрушаемых
## объектов и точки для дымов.
static func build(parent: Node3D, data: Dictionary, map_key: String, zones: Array, terra, hq: bool) -> Dictionary:
	var winter: bool = D.MAPS[map_key].get("winter", false)
	var desert := map_key == "alamein"
	var g := Geo.Group.new()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	parent.add_child(body)
	var sn := 1.0 if winter else 0.0
	var Tx := func(kind: String, sc: float, tint := Color.WHITE) -> ShaderMaterial:
		return TexLib.world_mat(kind, Vector3(sc, sc, sc), sn, 0.25 if desert else 0.4, tint)
	var M := {
		"plaster": Tx.call("plaster", 1.0 / 15.0), "brick": Tx.call("brick", 1.0 / 15.0), "roof": Tx.call("roof", 1.0 / 22.0),
		"concrete": Tx.call("concrete", 1.0 / 30.0), "concrete_d": Tx.call("concrete", 1.0 / 30.0, Color(0.72, 0.72, 0.7)),
		"wood": Tx.call("wood", 1.0 / 16.0), "steel": Tx.call("rust", 1.0 / 14.0, Color(0.55, 0.58, 0.55)),
		"rust": Tx.call("rust", 1.0 / 12.0), "charred": Tx.call("charred", 1.0 / 20.0),
		"sand": Tx.call("sandbag", 1.0 / 8.0, Color(1.05, 1.0, 0.92) if desert else Color(0.9, 0.88, 0.8)),
		"rubble": Tx.call("rubble", 1.0 / 12.0), "rock": Tx.call("sandstone" if desert else "granite", 1.0 / 40.0),
		"snow": mat(Color("eef3f6")), "canvas": Tx.call("sandbag", 1.0 / 18.0, Color(0.95, 0.92, 0.75)),
		"olive": mat(Color("4d5233")), "pole": Tx.call("wood", 1.0 / 10.0, Color(0.7, 0.65, 0.6)),
	}
	M["earth"] = Tx.call("earth", 1.0 / 14.0)
	M["leaves"] = Tx.call("leaves", 1.0 / 12.0)
	M["hay"] = Tx.call("sandbag", 1.0 / 6.0, Color(1.25, 1.1, 0.7))
	M["adobe"] = Tx.call("sandstone", 1.0 / 20.0, Color(1.0, 0.86, 0.68))
	# снарядные ящики — по развёртке куба: каждая грань — целая текстура
	var crate := StandardMaterial3D.new()
	crate.albedo_texture = TexLib.get_tex("crate")
	crate.uv1_scale = Vector3(3, 2, 1)
	crate.roughness = 0.9
	if hq:
		crate.normal_enabled = true
		crate.normal_texture = TexLib.get_tex("crate_n")
	if winter:
		crate.albedo_color = Color(0.92, 0.94, 0.97)
	M["crate"] = crate
	if map_key == "normandy" or map_key == "ardennes":
		# нормандские и бельгийские дома и церкви — из светлого камня под сланцем
		M.plaster = Tx.call("stone", 1.0 / 18.0)
		M.brick = M.plaster
		M.roof = Tx.call("slate", 1.0 / 14.0)
	var win := TexLib.world_mat("windows", Vector3(1.0 / 52.0, 1.0 / 44.0, 1.0 / 52.0), sn, 0.45, Color(0.78, 0.78, 0.8) if winter else Color.WHITE)
	var facade := TexLib.world_mat("facade", Vector3(1.0 / 40.0, 1.0 / 40.0, 1.0 / 40.0), 0.0, 0.5)
	var hedge_blob := Geo.sphere(8, 4)
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
			"hedgerow":
				# земляной вал и живая изгородь поверх: сплошная стена кустов в два-три метра,
				# снаряд вязнет, танк не перелезет, из-за неё ничего не видно
				var horiz := w >= d
				var ln := w if horiz else d
				var th := d if horiz else w
				g.add(Geo.box(Vector3(w, 6.0, d)), Geo.xf(c + Vector3(0, 2.5, 0)), M.earth)
				var n := maxi(2, int(ln / 7.0))
				var along := Vector3(1, 0, 0) if horiz else Vector3(0, 0, 1)
				var across := Vector3(0, 0, 1) if horiz else Vector3(1, 0, 0)
				for i in n:
					var t := (i + 0.5) * ln / n - ln / 2 + rng.randf_range(-2.5, 2.5)
					# неровная стена: кусты разной высоты, то выпирают, то проседают
					var hgt := rng.randf_range(10, 21)
					var sz := along * rng.randf_range(10, 17) + Vector3(0, hgt, 0) + across * th * rng.randf_range(1.1, 1.6)
					var p := c + along * t + across * rng.randf_range(-2.0, 2.0) + Vector3(0, 4.0 + hgt * 0.42, 0)
					g.add(hedge_blob, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)).scaled(sz), p), M.leaves)
					if rng.randf() < 0.45:
						# второй ярус: молодая поросль сбоку и сверху
						var s2 := Vector3.ONE * rng.randf_range(6, 10)
						g.add(hedge_blob, Transform3D(Basis.from_scale(s2), p + across * rng.randf_range(-1, 1) * th * 0.6 + Vector3(rng.randf_range(-3, 3), hgt * 0.35, 0)), M.leaves)
					if rng.randf() < 0.06:
						# дерево, выросшее из изгороди: ствол и крона из нескольких частей
						g.add(Geo.cyl(0.7, 1.1, 18, 6), Geo.xf(p + Vector3(0, 6, 0)), M.wood)
						for k in 4:
							var cs := rng.randf_range(10, 15)
							g.add(hedge_blob, Transform3D(Basis.from_scale(Vector3(cs, cs * 0.8, cs)), p + Vector3(rng.randf_range(-5, 5), 18 + rng.randf_range(0, 7), rng.randf_range(-5, 5))), M.leaves)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht, d))
			"church":
				# сельская нормандская церковь: неф под сланцевой кровлей и колокольня со шпилем
				var along_y := d >= w
				var nave_l := (d if along_y else w) * 0.72
				var nave_w := (w if along_y else d) * 0.85
				var nave_c := c + (Vector3(0, 0, -(d - nave_l) / 2) if along_y else Vector3(-(w - nave_l) / 2, 0, 0))
				var nsize := Vector3(nave_w, 26, nave_l) if along_y else Vector3(nave_l, 26, nave_w)
				g.add(Geo.box(nsize), Geo.xf(nave_c + Vector3(0, 13, 0)), M.plaster)
				var roof := PrismMesh.new()
				roof.size = Vector3(nave_w + 4, 16, nave_l + 2)
				g.add(roof, Geo.xf(nave_c + Vector3(0, 34, 0), Vector3(0, 0.0 if along_y else PI / 2, 0)), M.roof, true)
				var tw := minf(w, d) * 0.62
				var tower_c := c + (Vector3(0, 0, d / 2 - tw / 2) if along_y else Vector3(w / 2 - tw / 2, 0, 0))
				var broken := rng.randf() < 0.5
				var th2 := 44.0 if broken else 52.0
				g.add(Geo.box(Vector3(tw, th2, tw)), Geo.xf(tower_c + Vector3(0, th2 / 2, 0)), M.plaster)
				g.add(Geo.box(Vector3(tw * 0.3, 7, 1.0)), Geo.xf(tower_c + Vector3(0, th2 - 10, tw / 2 + 0.2)), M.charred)
				if broken:
					# шпиль снесён снарядом: зубчатый обрез и обломки у подножия
					for k in 4:
						g.add(Geo.box(Vector3(tw * 0.3, rng.randf_range(3, 9), tw * 0.3)), Geo.xf(tower_c + Vector3(rng.randf_range(-1, 1) * tw * 0.35, th2 + 2, rng.randf_range(-1, 1) * tw * 0.35)), M.plaster)
					smokes.append(tower_c + Vector3(0, th2, 0))
				else:
					g.add(Geo.cyl(0.0, tw * 0.62, 30, 4), Transform3D(Basis(Vector3.UP, PI / 4), tower_c + Vector3(0, th2 + 15, 0)), M.roof, true)
				_phys(body, nave_c + Vector3(0, 17, 0), nsize + Vector3(0, 8, 0))
				_phys(body, tower_c + Vector3(0, th2 / 2, 0), Vector3(tw, th2, tw))
			"barn":
				# амбар: каменный низ, дощатый верх, высокая крыша, ворота
				g.add(Geo.box(Vector3(w, 9, d)), Geo.xf(c + Vector3(0, 4.5, 0)), M.plaster)
				g.add(Geo.box(Vector3(w - 1, ht - 9, d - 1)), Geo.xf(c + Vector3(0, 9 + (ht - 9) / 2, 0)), M.wood)
				var roof := PrismMesh.new()
				var along_x := w >= d
				roof.size = Vector3((d if along_x else w) + 4, 14, (w if along_x else d) + 4)
				g.add(roof, Geo.xf(c + Vector3(0, ht + 7, 0), Vector3(0, PI / 2 if along_x else 0.0, 0)), M.roof, true)
				g.add(Geo.box(Vector3(14, 14, 0.8)), Geo.xf(c + Vector3(0, 7, d / 2 + 0.3)), M.charred)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht + 12, d))
			"glider":
				# разбитый десантный планёр «Хорса»: фюзеляж переломлен, крыло лежит рядом
				var yaw := rng.randf() * TAU
				var bs := Basis(Vector3.UP, yaw)
				g.add(Geo.cyl(4.0, 4.0, 34, 10), Transform3D(bs * Basis(Vector3.BACK, PI / 2 - 0.06), c + bs * Vector3(-10, 4, 0)), M.olive)
				g.add(Geo.cyl(2.2, 4.0, 22, 10), Transform3D(bs * Basis(Vector3.UP, 0.5) * Basis(Vector3.BACK, PI / 2 + 0.12), c + bs * Vector3(18, 3, 4)), M.olive)
				g.add(Geo.box(Vector3(12, 1.2, 64)), Transform3D(bs * Basis(Vector3.RIGHT, 0.08), c + bs * Vector3(-6, 1.5, -6)), M.wood)
				g.add(Geo.box(Vector3(5, 8, 1)), Transform3D(bs, c + bs * Vector3(30, 7, 6)), M.olive)
				for k in 4:
					g.add(Geo.box(Vector3(1.2, rng.randf_range(4, 9), 0.6)), Transform3D(bs * Basis(Vector3.BACK, rng.randf_range(-0.6, 0.6)), c + bs * Vector3(-24 + k * 6, 4, 2)), M.charred)
				_phys(body, c + Vector3(0, 4, 0), Vector3(w * 0.8, 8, d * 0.8), yaw)
			"reichstag":
				# Рейхстаг: корпус с угловыми башнями, портик с колоннами и остов купола
				var stone: Material = M.concrete_d
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), stone)
				g.add(Geo.box(Vector3(w + 3, 3, d + 3)), Geo.xf(c + Vector3(0, ht + 1.5, 0)), M.concrete)
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						var tp := c + Vector3(sx * (w / 2 - 20), 0, sz * (d / 2 - 20))
						g.add(Geo.box(Vector3(44, ht + 22, 44)), Geo.xf(tp + Vector3(0, (ht + 22) / 2, 0)), stone)
						g.add(Geo.box(Vector3(48, 3, 48)), Geo.xf(tp + Vector3(0, ht + 23, 0)), M.concrete)
				# портик со стороны наступающих
				var pz := d / 2 + 10.0
				for k in 6:
					g.add(Geo.cyl(3.0, 3.4, ht - 4, 10), Geo.xf(c + Vector3(-40 + k * 16, (ht - 4) / 2, pz)), M.concrete)
				g.add(Geo.box(Vector3(96, 5, 20)), Geo.xf(c + Vector3(0, ht - 1.5, pz - 2)), stone)
				var ped := PrismMesh.new()
				ped.size = Vector3(96, 14, 20)
				g.add(ped, Geo.xf(c + Vector3(0, ht + 8, pz - 2)), stone, true)
				for k in 5:
					g.add(Geo.box(Vector3(10, 2, 10)), Geo.xf(c + Vector3(-40 + k * 20, 1, pz + 14)), M.concrete)
				# выгоревшие окна и пробоины
				for k in 14:
					var side := 1.0 if k % 2 == 0 else -1.0
					g.add(Geo.box(Vector3(7, 10, 1.0)), Geo.xf(c + Vector3(rng.randf_range(-w / 2 + 50, w / 2 - 50), rng.randf_range(10, ht - 8), side * (d / 2 + 0.3))), M.charred)
				# остов купола: стальные рёбра без стёкол
				var dome_c := c + Vector3(0, ht + 3, 0)
				for k in 12:
					var a := TAU * k / 12.0
					for sgm in 4:
						var a0 := PI / 2 * sgm / 4.0
						var a1 := PI / 2 * (sgm + 1) / 4.0
						var dr := 34.0
						var p0 := Vector3(cos(a) * dr * cos(a0), dr * 0.8 * sin(a0), sin(a) * dr * cos(a0))
						var p1 := Vector3(cos(a) * dr * cos(a1), dr * 0.8 * sin(a1), sin(a) * dr * cos(a1))
						var mid := (p0 + p1) / 2
						var dir := (p1 - p0)
						var bas := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT)
						g.add(Geo.box(Vector3(1.0, 1.0, dir.length() + 0.5)), Transform3D(bas, dome_c + mid), M.steel)
				for ring_h: float in [0.0, 0.45, 0.75]:
					var rr := 34.0 * cos(asin(ring_h))
					for k in 24:
						var a := TAU * k / 24.0
						var a2 := TAU * (k + 1) / 24.0
						var q0 := Vector3(cos(a) * rr, 34.0 * 0.8 * ring_h, sin(a) * rr)
						var q1 := Vector3(cos(a2) * rr, 34.0 * 0.8 * ring_h, sin(a2) * rr)
						g.add(Geo.box(Vector3(0.8, 0.8, q0.distance_to(q1) + 0.4)), Transform3D(Basis.looking_at((q1 - q0).normalized(), Vector3.UP), dome_c + (q0 + q1) / 2), M.steel)
				smokes.append(c + Vector3(rng.randf_range(-60, 60), ht, 0))
				_phys(body, c + Vector3(0, (ht + 22) / 2, 0), Vector3(w, ht + 22, d))
			"flak_tower":
				# зенитная башня: бетонная крепость с площадками для 128-мм спарок по углам
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), M.concrete)
				for k in 4:
					g.add(Geo.box(Vector3(w + 2, 2.5, d + 2)), Geo.xf(c + Vector3(0, ht * (0.25 + k * 0.2), 0)), M.concrete_d)
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						var tp := c + Vector3(sx * (w / 2 - 12), ht, sz * (d / 2 - 12))
						g.add(Geo.cyl(16, 16, 12, 16), Geo.xf(tp + Vector3(0, 6, 0)), M.concrete)
						g.add(Geo.box(Vector3(6, 4, 6)), Geo.xf(tp + Vector3(0, 14, 0)), M.steel)
						for gz: float in [-1.4, 1.4]:
							g.add(Geo.cyl(0.6, 0.6, 16, 6), Transform3D(Basis(Vector3.UP, sx * 0.7) * Basis(Vector3.BACK, -PI / 2 + 0.5), tp + Vector3(6, 18, gz)), M.steel)
				for k in 16:
					var side := Vector3(rng.randf_range(-w / 2 + 10, w / 2 - 10), rng.randf_range(15, ht - 10), (d / 2 + 0.3) * (1.0 if k % 2 == 0 else -1.0))
					g.add(Geo.box(Vector3(4, 4, 1)), Geo.xf(c + side), M.charred)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht, d))
			"tram":
				# сгоревший трамвай, поставленный поперёк улицы
				var horiz := w >= d
				var ln := w if horiz else d
				var bs := Basis(Vector3.UP, 0.0 if horiz else PI / 2) * Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
				g.add(Geo.box(Vector3(ln, 10, 9)), Transform3D(bs, c + Vector3(0, 6.5, 0)), M.rust)
				g.add(Geo.box(Vector3(ln - 4, 4, 9.3)), Transform3D(bs, c + Vector3(0, 8.5, 0)), M.charred)
				g.add(Geo.box(Vector3(ln + 1, 1.2, 9.5)), Transform3D(bs, c + Vector3(0, 11.8, 0)), M.steel)
				for k in 4:
					g.add(Geo.cyl(1.4, 1.4, 9.6, 8), Transform3D(bs * Basis(Vector3.RIGHT, PI / 2), c + bs * Vector3(-ln / 2 + 6 + k * (ln - 12) / 3.0, 1.4, 0)), M.steel)
				_phys(body, c + Vector3(0, 6.5, 0), Vector3(w, 13, d))
			"barricade":
				# баррикада: обломки, балки, перевёрнутая повозка
				var horiz := w >= d
				var ln := w if horiz else d
				for k in 10:
					var t := rng.randf_range(-ln / 2, ln / 2)
					var sz := Vector3(rng.randf_range(4, 10), rng.randf_range(2, 6), rng.randf_range(4, 9))
					var p := c + (Vector3(t, sz.y * 0.4, rng.randf_range(-3, 3)) if horiz else Vector3(rng.randf_range(-3, 3), sz.y * 0.4, t))
					g.add(Geo.box(sz), Geo.xf(p, Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)), M.rubble if k % 3 else M.brick)
				for k in 4:
					var t := rng.randf_range(-ln / 2, ln / 2) * 0.8
					var p := c + (Vector3(t, 5, 0) if horiz else Vector3(0, 5, t))
					g.add(Geo.box(Vector3(1.4, 1.4, 16)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.6)), p), M.wood)
				_phys(body, c + Vector3(0, 4, 0), Vector3(w, 8, d))
			"tower", "ruin_tower", "block", "ruin_block":
				var cols := 3 if w > 110 else 2
				var rows := 3 if d > 110 else 2
				for ix in cols:
					for iz in rows:
						var cw := w / cols
						var cd := d / rows
						var hgt := ht if not o.kind.begins_with("ruin") else ht * rng.randf_range(0.3, 1.0)
						var p := c + Vector3(-w / 2 + cw * (ix + 0.5), hgt / 2 - 3, -d / 2 + cd * (iz + 0.5))
						var wall: Material = facade if o.kind.ends_with("block") else win
						g.add(Geo.box(Vector3(cw, hgt + 6, cd)), Geo.xf(p), wall)
						g.add(Geo.box(Vector3(cw + 1, 1.6, cd + 1)), Geo.xf(p + Vector3(0, hgt / 2 + 3.6, 0)), M.snow if winter else M.concrete_d)
						_phys(body, p + Vector3(0, 3, 0), Vector3(cw, hgt, cd))
						if o.kind.begins_with("ruin"):
							for k in 2:
								var jh := rng.randf_range(3, 12)
								g.add(Geo.box(Vector3(rng.randf_range(4, cw * 0.4), jh, rng.randf_range(4, cd * 0.4))),
									Geo.xf(p + Vector3(rng.randf_range(-cw, cw) * 0.3, hgt / 2 + 3 + jh / 2, rng.randf_range(-cd, cd) * 0.3)), wall)
				if o.kind.begins_with("ruin"):
					for k in 5:
						var side := Vector3(rng.randf_range(-w, w) * 0.55, 0, (d / 2 + 6) * (1.0 if rng.randf() < 0.5 else -1.0))
						g.add(Geo.box(Vector3(rng.randf_range(5, 12), rng.randf_range(2, 5), rng.randf_range(5, 10))),
							Geo.xf(c + side + Vector3(0, 1.5, 0), Vector3(rng.randf() * 0.4, rng.randf() * TAU, 0)), M.rubble)
					if rng.randf() < 0.35:
						smokes.append(c + Vector3(0, ht * 0.5, 0))
			"factory":
				# заводской цех: кирпичные стены с пилястрами, ленточное остекление, пилообразная крыша;
				# у разбитых цехов часть пролётов обрушена и торчат фермы
				var along_x := w >= d
				var ln := w if along_x else d
				var wd := d if along_x else w
				var ruined := rng.randf() < 0.65
				var yaw := 0.0 if along_x else PI / 2
				var bs := Basis(Vector3.UP, yaw)
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), M.brick)
				var bays := maxi(3, int(ln / 34.0))
				var bl := ln / bays
				for sd: float in [-1.0, 1.0]:
					g.add(Geo.box(Vector3(ln - 12, ht * 0.32, 0.8)), Transform3D(bs, c + bs * Vector3(0, ht * 0.6, sd * (wd / 2 + 0.3))), M.charred)
					for k in bays + 1:
						g.add(Geo.box(Vector3(3.5, ht, 1.6)), Transform3D(bs, c + bs * Vector3(-ln / 2 + k * bl, ht / 2, sd * (wd / 2 + 0.6))), M.brick)
				for k in bays:
					var t := -ln / 2 + (k + 0.5) * bl
					if ruined and rng.randf() < 0.45:
						for q in 3:
							var bp := c + bs * Vector3(t + rng.randf_range(-0.3, 0.3) * bl, ht + 1.0, rng.randf_range(-0.35, 0.35) * wd)
							g.add(Geo.box(Vector3(1.2, 1.2, wd * 0.45)), Transform3D(bs * Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5), 0)), bp), M.steel)
						continue
					var tooth := PrismMesh.new()
					tooth.left_to_right = 0.0
					tooth.size = Vector3(bl, 11, wd)
					g.add(tooth, Transform3D(bs, c + bs * Vector3(t, ht + 5.5, 0)), M.roof, true)
					g.add(Geo.box(Vector3(0.6, 9, wd - 4)), Transform3D(bs, c + bs * Vector3(t - bl / 2 + 0.4, ht + 5, 0)), M.charred)
				if ruined:
					smokes.append(c + Vector3(rng.randf_range(-0.3, 0.3) * w, ht, rng.randf_range(-0.3, 0.3) * d))
					for k in 6:
						var sd := 1.0 if rng.randf() < 0.5 else -1.0
						g.add(Geo.box(Vector3(rng.randf_range(6, 14), rng.randf_range(2, 6), rng.randf_range(5, 10))),
							Transform3D(bs * Basis.from_euler(Vector3(rng.randf() * 0.4, rng.randf() * TAU, 0)), c + bs * Vector3(rng.randf_range(-0.45, 0.45) * ln, 1.5, sd * (wd / 2 + 6))), M.rubble if k % 2 else M.brick)
				_phys(body, c + Vector3(0, ht / 2 + 3, 0), Vector3(w, ht + 6, d))
			"chimney":
				# заводская труба: кирпичный конус с поясами, у некоторых верх снесён
				var top_h := ht if rng.randf() < 0.6 else ht * rng.randf_range(0.55, 0.8)
				g.add(Geo.box(Vector3(w + 6, 8, d + 6)), Geo.xf(c + Vector3(0, 4, 0)), M.brick)
				g.add(Geo.cyl(w * 0.32, w * 0.5, top_h, 12), Geo.xf(c + Vector3(0, top_h / 2, 0)), M.brick)
				for k in 3:
					var bh := top_h * (0.3 + k * 0.25)
					var br := lerpf(w * 0.5, w * 0.32, bh / top_h) + 0.6
					g.add(Geo.cyl(br, br, 1.6, 12), Geo.xf(c + Vector3(0, bh, 0)), M.charred)
				_phys(body, c + Vector3(0, top_h / 2, 0), Vector3(w, top_h, d))
			"water_tank":
				# водонапорный бак на вершине кургана, пробитый осколками
				g.add(Geo.cyl(w / 2, w / 2, ht, 18), Geo.xf(c + Vector3(0, ht / 2, 0)), M.concrete_d)
				g.add(Geo.cyl(w / 2 + 1.2, w / 2 + 1.2, 2.0, 18), Geo.xf(c + Vector3(0, ht, 0)), M.concrete)
				for k in 5:
					var a := rng.randf() * TAU
					g.add(Geo.box(Vector3(3.5, 3.5, 1.0)), Transform3D(Basis(Vector3.UP, -a + PI / 2), c + Vector3(cos(a) * (w / 2 + 0.2), rng.randf_range(4, ht - 3), sin(a) * (w / 2 + 0.2))), M.charred)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w * 0.9, ht, d * 0.9))
			"fountain":
				# фонтан на площади: чаша, в середине — хоровод фигурок вокруг крокодила
				g.add(Geo.cyl(w / 2, w / 2 + 1.0, ht, 24), Geo.xf(c + Vector3(0, ht / 2, 0)), M.concrete)
				g.add(Geo.cyl(w / 2 - 2.0, w / 2 - 2.0, 0.6, 24), Geo.xf(c + Vector3(0, ht + 0.1, 0)), M.snow if winter else M.charred)
				g.add(Geo.box(Vector3(9, 2.2, 2.6)), Geo.xf(c + Vector3(0, ht + 1.4, 0), Vector3(0, rng.randf() * TAU, 0)), M.steel)
				for k in 6:
					var a := TAU * k / 6.0
					var fp := c + Vector3(cos(a) * 6.5, ht, sin(a) * 6.5)
					g.add(Geo.cyl(0.6, 0.9, 4.2, 6), Geo.xf(fp + Vector3(0, 2.1, 0)), M.steel)
					g.add(Geo.sphere(6, 4), Transform3D(Basis.from_scale(Vector3(1.4, 1.4, 1.4)), fp + Vector3(0, 4.8, 0)), M.steel)
				_phys(body, c + Vector3(0, ht / 2, 0), Vector3(w, ht, d))
			"adobe":
				# глинобитный дом с плоской крышей и парапетом, тёмный дверной проём
				g.add(Geo.box(Vector3(w, ht, d)), Geo.xf(c + Vector3(0, ht / 2, 0)), M.adobe)
				for sd: float in [-1.0, 1.0]:
					g.add(Geo.box(Vector3(w, 2.4, 1.6)), Geo.xf(c + Vector3(0, ht + 1.2, sd * (d / 2 - 0.8))), M.adobe)
					g.add(Geo.box(Vector3(1.6, 2.4, d)), Geo.xf(c + Vector3(sd * (w / 2 - 0.8), ht + 1.2, 0)), M.adobe)
				g.add(Geo.box(Vector3(6, 9, 0.6)), Geo.xf(c + Vector3(rng.randf_range(-0.25, 0.25) * w, 4.5, d / 2 + 0.2)), M.charred)
				for sd: float in [-1.0, 1.0]:
					g.add(Geo.box(Vector3(3.2, 3.2, 0.6)), Geo.xf(c + Vector3(w * 0.3 * sd, ht * 0.62, -d / 2 - 0.2)), M.charred)
				for k in 3:
					g.add(Geo.cyl(0.25, 0.25, 6, 4), Transform3D(Basis(Vector3.RIGHT, PI / 2), c + Vector3(-w / 2 + (k + 1) * w / 4, ht - 1.5, d / 2 + 2.0)), M.wood)
				_phys(body, c + Vector3(0, ht / 2 + 1, 0), Vector3(w, ht + 2, d))
			"teeth":
				# надолбы «Западного вала»: ряды бетонных пирамид («зубы дракона»)
				var horiz := w >= d
				var ln := w if horiz else d
				var th := d if horiz else w
				var n := maxi(2, int(ln / 7.5))
				var rows := maxi(2, int(th / 8.5))
				for rw in rows:
					for i in n:
						var t := (i + 0.5 * (rw % 2)) * ln / n - ln / 2 + 3.0
						var q := -th / 2 + (rw + 0.5) * th / rows
						var p := c + (Vector3(t, 0, q) if horiz else Vector3(q, 0, t))
						var hgt := ht * (0.75 + 0.15 * rw)
						g.add(Geo.cyl(0.9, 3.0, hgt, 4), Geo.xf(p + Vector3(0, hgt / 2 - 0.4, 0), Vector3(0, PI / 4, 0)), M.concrete_d)
						if winter:
							g.add(Geo.cyl(0.0, 1.2, 1.4, 4), Geo.xf(p + Vector3(0, hgt - 0.1, 0), Vector3(0, PI / 4, 0)), M.snow)
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
		elif dc.kind == "lamp":
			# чугунный фонарь берлинского проспекта
			g.add(Geo.cyl(0.35, 0.6, 22, 6), Geo.xf(Vector3(p.x, y + 11, p.y)), M.steel)
			g.add(Geo.box(Vector3(5, 0.5, 0.5)), Geo.xf(Vector3(p.x, y + 21.5, p.y)), M.steel)
			for s: float in [-2.2, 2.2]:
				g.add(Geo.cyl(0.9, 0.5, 2.0, 6), Geo.xf(Vector3(p.x + s, y + 20.2, p.y)), M.charred)
		elif dc.kind == "crates":
			# штабель снарядных ящиков: нижний ряд и пара сверху
			var bs := Basis(Vector3.UP, float(dc.rot))
			var lower := 2 + rng.randi() % 2
			for k in lower + rng.randi() % 3:
				var top := k >= lower
				var lp := Vector3(rng.randf_range(-0.6, 0.6), 1.6, (k - (lower - 1) * 0.5) * 4.1) if not top \
					else Vector3(rng.randf_range(-0.8, 0.8), 4.7, ((k - lower) - 0.5) * 4.1)
				var cp := Vector3(p.x, y, p.y) + bs * lp
				g.add(Geo.box(Vector3(6.2, 3.1, 3.9)), Transform3D(bs * Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), cp), M.crate)
		elif dc.kind == "hay":
			# круглые тюки сена
			for k in 3:
				var hp := p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
				g.add(Geo.cyl(2.6, 2.6, 3.6, 12), Geo.xf(Vector3(hp.x, terra.height(hp.x, hp.y) + 2.6, hp.y), Vector3(PI / 2, rng.randf() * TAU, 0)), M.hay)
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
	bmat.set_shader_parameter("noise", TexLib.noise_texture())
	var ico := Geo.sphere(9, 5)
	var cone := Geo.cyl(0.0, 0.5, 1.0, 7)
	var tones := {"bush": [Color("424e33"), Color("5a6442")], "shrub": [Color("6f6a38"), Color("8a8448")], "fir": [Color("2a4630"), Color("e9eff2")]}
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
				var sq := rng.randf_range(0.75, 1.1)
				bg.add(ico, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sv.z * 2.0, sv.z * 1.5 * sq, sv.z * 1.7) * k), base + Vector3(0, sv.z * 0.55 * k * sq, 0)), bmat, false, ca, bp)
				bg.add(ico, Transform3D(Basis.from_scale(Vector3(sv.z * 1.1, sv.z * 0.9, sv.z * 1.1) * k), base + Vector3(rng.randf_range(-3, 3), sv.z * 1.05 * k * sq, rng.randf_range(-3, 3))), bmat, false, l, bp)
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
			mm.use_colors = true
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
		var tint := Color.from_hsv(rng.randf_range(0.12, 0.2), rng.randf_range(0.0, 0.12), rng.randf_range(0.82, 1.12))
		for part in parts[pr.kind]:
			pr.mms.append([mms[part], i])
			(mms[part] as MultiMesh).set_instance_color(i, tint)
		place_prop(pr)

	# камешки в пустыне
	if desert:
		var n := 1500 if hq else 680
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var tuft := Geo.Group.new()
		tuft.add(Geo.sphere(5, 3), Transform3D(Basis.from_scale(Vector3(3, 1.6, 2.6)), Vector3.ZERO), M.rock, true)
		mm.mesh = _one(tuft)
		mm.instance_count = n
		var placed := 0
		for t in n * 3:
			if placed >= n:
				break
			var p := Vector2(rng.randf_range(-200, D.WS + 200), rng.randf_range(-200, D.WS + 200))
			if _blocked(p, data.obst, 4.0):
				continue
			var s := rng.randf_range(0.6, 1.5)
			mm.set_instance_transform(placed, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, terra.height(p.x, p.y), p.y)))
			placed += 1
		mm.visible_instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = M.rock
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	# трава, качающаяся на ветру: участки с отсечением по дальности
	if hq or not winter:
		_grass(parent, data, terra, rng, map_key, hq)

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


static func _blocked(p: Vector2, obst: Array, m: float) -> bool:
	for o in obst:
		if (o.r as Rect2).grow(m).has_point(p):
			return true
	return false


const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
varying float hgt;

void vertex() {
	hgt = 1.0 - UV.y;
	vec3 o = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.8 + o.x * 0.08 + o.z * 0.06;
	VERTEX.x += sin(t) * 0.7 * hgt;
	VERTEX.z += cos(t * 1.3) * 0.5 * hgt;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb * (0.6 + 0.4 * hgt);
	// обе стороны травинки освещаются как земля, сверху
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.95;
}
"""

const FOLIAGE_SHADER := """
shader_type spatial;
render_mode diffuse_lambert;
uniform vec4 base : source_color = vec4(0.3, 0.42, 0.18, 1.0);
uniform float crown_from = 12.0;
uniform float sway = 0.5;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying float lh;
varying vec3 wp;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - crown_from, 0.0) / 20.0;
	float t = TIME * 1.1 + o.x * 0.05 + o.z * 0.07;
	VERTEX.x += sin(t) * sway * h * 2.0;
	VERTEX.z += cos(t * 0.8) * sway * h * 1.5;
	lh = VERTEX.y;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// нижняя часть кроны в тени
	float shade = clamp((lh - crown_from) / 18.0, 0.0, 1.0);
	float n = texture(noise, wp.xz * 0.09 + wp.y * 0.07).r * 0.6 + texture(noise, wp.xz * 0.3 - wp.y * 0.2).r * 0.4;
	ALBEDO = base.rgb * COLOR.rgb * (0.55 + 0.5 * shade) * (0.65 + 0.6 * n);
	ROUGHNESS = 0.9;
}
"""


static func _grass(parent: Node3D, data: Dictionary, terra, rng: RandomNumberGenerator, map_key: String, hq: bool) -> void:
	var dry := map_key != "prokhorovka" and map_key != "normandy"
	# на площади в 1,7 раза больше — травы столько же на квадратный метр
	var total: int = {"prokhorovka": 15000, "normandy": 17000, "stalingrad": 1500, "berlin": 1900, "ardennes": 1500}.get(map_key, 4200)
	if not hq:
		total /= 3
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", TexLib.grass_texture(dry))
	var tints := {"stalingrad": Color(0.92, 0.95, 0.85), "ardennes": Color(0.9, 0.93, 0.85), "prokhorovka": Color(1.0, 0.96, 0.8), "normandy": Color(0.92, 0.94, 0.85)}
	m.set_shader_parameter("tint", tints.get(map_key, Color.WHITE))
	var g := Geo.Group.new()
	var q := QuadMesh.new()
	q.size = Vector2(7, 4.6)
	for k in 3:
		g.add(q, Transform3D(Basis(Vector3.UP, k * PI / 3.0), Vector3(0, 2.3, 0)), m)
	var tuft := _one(g)
	var chunks := 10
	var cs := (D.WS + 200.0) / chunks
	var per := total / (chunks * chunks)
	for cx in chunks:
		for cz in chunks:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = tuft
			mm.instance_count = per
			var placed := 0
			for t in per * 3:
				if placed >= per:
					break
				var p := Vector2(-100.0 + (cx + rng.randf()) * cs, -100.0 + (cz + rng.randf()) * cs)
				if _blocked(p, data.obst, 3.0):
					continue
				var mk: Color = terra.mask.get_pixel(clampi(int((p.x - terra.ORIGIN) / terra.SIZE * 1024), 0, 1023), clampi(int((p.y - terra.ORIGIN) / terra.SIZE * 1024), 0, 1023))
				if mk.r > 0.35 or mk.g > 0.4:
					continue
				var s := rng.randf_range(0.7, 1.4)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
				mm.set_instance_transform(placed, Transform3D(b, Vector3(p.x, terra.height(p.x, p.y) - 0.2, p.y)))
				mm.set_instance_color(placed, Color.from_hsv(rng.randf_range(-0.04, 0.04), rng.randf_range(0.0, 0.2), rng.randf_range(0.8, 1.15)))
				placed += 1
			mm.visible_instance_count = placed
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = m
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 380.0
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			parent.add_child(mmi)


static func _foliage(c: Color, crown_from: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FOLIAGE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base", c)
	m.set_shader_parameter("crown_from", crown_from)
	m.set_shader_parameter("noise", TexLib.noise_texture())
	return m


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
	trunk.vertex_color_use_as_albedo = true
	var leaves := _foliage(Color("4a5634"), 12.0)
	var t := Geo.Group.new()
	t.add(Geo.cyl(0.8, 1.4, 20, 7), Geo.xf(Vector3(0, 10, 0)), trunk)
	for k in 3:
		var a := k * 2.1 + 0.4
		t.add(Geo.cyl(0.25, 0.55, 8, 5), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.7), Vector3(cos(a) * 2.0, 18.5, sin(a) * 2.0)), trunk)
	var crown := Geo.Group.new()
	var blobs := [[0.0, 0.0, 27.0, 14.0], [5.5, 1.0, 23.0, 11.0], [-5.0, 2.5, 23.5, 11.0], [1.5, -5.5, 22.5, 10.5],
		[-2.0, 5.5, 24.0, 10.5], [4.0, -2.5, 29.5, 9.0], [-3.5, -2.0, 30.0, 8.5]]
	for bl in blobs:
		crown.add(Geo.sphere(8, 5), Transform3D(Basis.from_scale(Vector3(bl[3], bl[3] * 0.82, bl[3])), Vector3(bl[0], bl[2], bl[1])), leaves, true)
	out["tree"] = [[_one(t), trunk], [_one(crown), leaves]]
	# яблоня нормандского сада: низкая, с широкой раскидистой кроной
	var at := Geo.Group.new()
	at.add(Geo.cyl(0.6, 1.0, 9, 6), Geo.xf(Vector3(0, 4.5, 0), Vector3(0, 0, 0.12)), trunk)
	for k in 3:
		var a := k * 2.1
		at.add(Geo.cyl(0.25, 0.5, 6, 5), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.9), Vector3(cos(a) * 1.8, 9.5, sin(a) * 1.8)), trunk)
	var acrown := Geo.Group.new()
	var aleaves := _foliage(Color("515d38"), 8.0)
	for bl in [[0.0, 0.0, 14.0, 9.0], [4.5, 1.5, 12.5, 7.0], [-4.0, 2.0, 13.0, 7.0], [1.0, -4.5, 12.0, 6.5], [-1.5, -3.0, 16.5, 6.0]]:
		acrown.add(Geo.sphere(8, 5), Transform3D(Basis.from_scale(Vector3(bl[3], bl[3] * 0.7, bl[3])), Vector3(bl[0], bl[2], bl[1])), aleaves, true)
	out["apple"] = [[_one(at), trunk], [_one(acrown), aleaves]]
	var palm_t := Geo.Group.new()
	for k in 4:
		palm_t.add(Geo.cyl(0.7, 0.9, 8.5, 6), Geo.xf(Vector3(k * 0.6, 4 + k * 8, 0), Vector3(0, 0, -0.06 * k)), trunk)
	var fronds := Geo.Group.new()
	var green := _foliage(Color("5a6634"), 28.0)
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
	# ель: ярусы хвои конусами, жёсткая — не качается; на зимних картах верх лап в снегу
	var sp_t := Geo.Group.new()
	sp_t.add(Geo.cyl(0.6, 1.3, 14, 6), Geo.xf(Vector3(0, 7, 0)), trunk)
	var needles := _foliage(Color("2e4632"), 6.0)
	needles.set_shader_parameter("sway", 0.0)
	var sp_c := Geo.Group.new()
	var sp_s := Geo.Group.new()
	var tiers := [[7.0, 13.5, 22.0], [19.0, 11.0, 19.0], [30.0, 8.5, 16.0], [40.0, 6.0, 13.0], [49.0, 3.6, 11.0]]  # низ яруса, радиус, высота
	for k in tiers.size():
		var tr: Array = tiers[k]
		sp_c.add(Geo.cyl(0.0, tr[1], tr[2], 9), Geo.xf(Vector3(0, tr[0] + tr[2] / 2, 0), Vector3(0, k * 0.7, 0)), needles)
		if D.MAPS[map_key].get("winter", false):
			# видимая полоса яруса — до низа следующего; снег на её верхних двух третях
			var y1: float = tiers[k + 1][0] if k + 1 < tiers.size() else tr[0] + tr[2]
			var y0: float = tr[0] + (y1 - tr[0]) * 0.35
			var r0: float = tr[1] * (1.0 - (y0 - tr[0]) / tr[2]) + 0.5
			var r1: float = tr[1] * (1.0 - (y1 - tr[0]) / tr[2]) + 0.5
			sp_s.add(Geo.cyl(r1, r0, y1 - y0, 9), Geo.xf(Vector3(0, (y0 + y1) / 2 + 0.3, 0), Vector3(0, k * 0.7, 0)), M.snow)
	out["spruce"] = [[_one(sp_t), trunk], [_one(sp_c), needles]]
	if D.MAPS[map_key].get("winter", false):
		out["spruce"].append([_one(sp_s), M.snow])
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
