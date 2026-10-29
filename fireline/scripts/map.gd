extends Node2D
## Боевая карта: сетка местности 2×2 м, генерация пяти типов карт, проходимость,
## укрытия, прямая видимость, поиск пути (A*) и отрисовка (растровая земля + векторные объекты).

enum { GRASS, ROAD, FOREST, BUILDING, HEDGE, WATER, FIELD, BRIDGE, RUBBLE, SCRUB, FORD }

const CS := 2.0
const INV_CS := 0.5
const TNAME := ["Луг", "Дорога", "Лес", "Здание", "Изгородь", "Вода", "Поле", "Мост", "Руины", "Кустарник", "Брод"]
const COVER := [0.05, 0.0, 0.45, 0.7, 0.5, 0.0, 0.15, 0.1, 0.45, 0.3, 0.0]
# непрозрачность на метр: 1.0 — глухая стена, 0.035 — ~30 м леса закрывают обзор
const OPAC := [0.0, 0.0, 0.035, 1.0, 0.45, 0.0, 0.006, 0.0, 0.05, 0.015, 0.0]
const SPD_I := [1.0, 1.1, 0.75, 0.7, 0.45, 0.0, 0.85, 1.1, 0.6, 0.8, 0.35]
const SPD_V := [1.0, 1.4, 0.3, 0.0, 0.2, 0.0, 0.85, 1.3, 0.0, 0.6, 0.25]
const BASE_COL := [Color(0.36, 0.45, 0.22), Color(0.55, 0.47, 0.33), Color(0.19, 0.27, 0.13),
	Color(0.32, 0.30, 0.27), Color(0.26, 0.36, 0.16), Color(0.20, 0.32, 0.40), Color(0.68, 0.60, 0.32),
	Color(0.45, 0.36, 0.25), Color(0.42, 0.40, 0.37), Color(0.30, 0.39, 0.19), Color(0.30, 0.42, 0.46)]

var W := 720.0
var H := 440.0
var GW := 360
var GH := 220
var terr := PackedByteArray()
var fidx := PackedByteArray()  # номер поля для раскраски
var opac := PackedFloat32Array()
var cover := PackedFloat32Array()
var cover_bonus := PackedFloat32Array()  # воронки
var rng := RandomNumberGenerator.new()
var kind := ""

var roads: Array = []      # PackedVector2Array
var rivers: Array = []     # [PackedVector2Array, ширина]
var bridges: Array = []    # {p, a, len, w}
var hedges: Array = []     # PackedVector2Array
var buildings: Array = []  # {r: Rect2, roof: Color, ridge_x: bool}
var trees: Array = []      # Vector3(x, y, r)
var fields: Array = []     # {r: Rect2, col: Color, dir: int}
var flags: Array = []      # Vector2
var zones: Array = [Rect2(), Rect2()]

var astar_i: AStarGrid2D
var astar_v: AStarGrid2D
var top: Node2D
var ground: Sprite2D


func _ready() -> void:
	top = Node2D.new()
	top.name = "MapTop"
	top.draw.connect(_draw_top)


# ===================== Генерация =====================

func generate(map_kind: String, seed_v: int, mode: String) -> void:
	kind = map_kind
	rng.seed = seed_v
	GW = int(W / CS)
	GH = int(H / CS)
	terr.resize(GW * GH)
	terr.fill(GRASS)
	fidx.resize(GW * GH)
	fidx.fill(0)
	roads.clear(); rivers.clear(); bridges.clear(); hedges.clear(); buildings.clear()
	trees.clear(); fields.clear(); flags.clear()
	match map_kind:
		"village": _gen_village()
		"forest": _gen_forest()
		"river": _gen_river()
		"bocage": _gen_bocage()
		_: _gen_steppe()
	# зоны развёртывания: игрок всегда слева
	var zw := 110.0
	zones[0] = Rect2(4, 4, zw, H - 8)
	zones[1] = Rect2(W - zw - 4, 4, zw, H - 8)
	if mode == "defend":
		zones[0] = Rect2(4, 4, W * 0.48, H - 8)
	elif mode == "attack":
		zones[1] = Rect2(W * 0.52, 4, W * 0.48 - 4, H - 8)
	_finalize()


func _finalize() -> void:
	opac.resize(GW * GH)
	cover.resize(GW * GH)
	cover_bonus.resize(GW * GH)
	cover_bonus.fill(0.0)
	for i in GW * GH:
		var t := terr[i]
		opac[i] = OPAC[t]
		cover[i] = COVER[t]
	# деревья: лес плотно, кустарник редко
	for y in GH:
		for x in GW:
			var t := terr[y * GW + x]
			var p := 0.0
			if t == FOREST:
				p = 0.16
			elif t == SCRUB:
				p = 0.07
			if p > 0.0 and rng.randf() < p:
				var c := Vector2((x + rng.randf()) * CS, (y + rng.randf()) * CS)
				var r := rng.randf_range(2.6, 4.6) if t == FOREST else rng.randf_range(1.5, 2.6)
				trees.append(Vector3(c.x, c.y, r))
	# одиночные деревья у дорог и на лугах (только украшение)
	for i in 70:
		var c := Vector2(rng.randf() * W, rng.randf() * H)
		if terr_at(c) == GRASS:
			trees.append(Vector3(c.x, c.y, rng.randf_range(2.5, 4.0)))
	_build_astar()
	_build_ground()
	queue_redraw()
	if top:
		top.queue_redraw()


func _idx(x: int, y: int) -> int:
	return y * GW + x


func _setc(x: int, y: int, t: int, over := true) -> void:
	if x < 0 or y < 0 or x >= GW or y >= GH:
		return
	var i := y * GW + x
	if not over and terr[i] != GRASS and terr[i] != FIELD:
		return
	terr[i] = t


func _fill_rect(r: Rect2, t: int, over := true) -> void:
	var x0 := int(floor(r.position.x * INV_CS))
	var y0 := int(floor(r.position.y * INV_CS))
	var x1 := int(ceil(r.end.x * INV_CS))
	var y1 := int(ceil(r.end.y * INV_CS))
	for y in range(maxi(y0, 0), mini(y1, GH)):
		for x in range(maxi(x0, 0), mini(x1, GW)):
			_setc(x, y, t, over)


func _disk(c: Vector2, r: float, t: int, mode := 0) -> void:
	# mode: 0 — перезаписать, 1 — только по лугу/полю, 2 — дорога (вода превращается в мост)
	var cx := int(c.x * INV_CS)
	var cy := int(c.y * INV_CS)
	var rc := int(ceil(r * INV_CS))
	for y in range(cy - rc, cy + rc + 1):
		for x in range(cx - rc, cx + rc + 1):
			if x < 0 or y < 0 or x >= GW or y >= GH:
				continue
			var p := Vector2((x + 0.5) * CS, (y + 0.5) * CS)
			if p.distance_squared_to(c) > r * r:
				continue
			var i := y * GW + x
			var cur := terr[i]
			if mode == 1 and cur != GRASS and cur != FIELD and cur != SCRUB:
				continue
			if mode == 2:
				if cur == WATER or cur == BRIDGE or cur == FORD:
					terr[i] = BRIDGE
					continue
				if cur == BUILDING:
					continue
			terr[i] = t


func _stroke(pts: PackedVector2Array, width: float, t: int, mode := 0) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var n := int(ceil(a.distance_to(b) / 1.0))
		for j in n + 1:
			_disk(a.lerp(b, float(j) / maxf(n, 1)), width * 0.5, t, mode)


func _wiggle(a: Vector2, b: Vector2, segs: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := (b - a)
	var nrm := d.orthogonal().normalized()
	var off := 0.0
	for i in segs + 1:
		var f := float(i) / segs
		if i > 0 and i < segs:
			off = clampf(off + rng.randf_range(-amp, amp), -amp * 2.0, amp * 2.0)
		else:
			off = 0.0 if i == 0 else off * 0.5
		pts.append(a + d * f + nrm * off)
	# сглаживание
	for it in 2:
		for i in range(1, pts.size() - 1):
			pts[i] = pts[i].lerp((pts[i - 1] + pts[i + 1]) * 0.5, 0.5)
	return pts


func _road(pts: PackedVector2Array, width := 7.0) -> void:
	roads.append(pts)
	_stroke(pts, width, ROAD, 2)


func _river(pts: PackedVector2Array, width: float) -> void:
	rivers.append([pts, width])
	_stroke(pts, width, WATER, 0)


func _noise_forest(freq: float, thr: float, bias: Callable, t := FOREST) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = freq
	nz.fractal_octaves = 3
	for y in GH:
		for x in GW:
			var p := Vector2((x + 0.5) * CS, (y + 0.5) * CS)
			var v := nz.get_noise_2d(p.x, p.y) + float(bias.call(p))
			if v > thr:
				var i := y * GW + x
				if terr[i] == GRASS or (t == SCRUB and terr[i] == FIELD):
					terr[i] = t


func _field(r: Rect2) -> void:
	var cols := [Color(0.72, 0.63, 0.33), Color(0.62, 0.54, 0.30), Color(0.47, 0.38, 0.26),
		Color(0.45, 0.52, 0.25), Color(0.76, 0.68, 0.40)]
	fields.append({"r": r, "col": cols[rng.randi() % cols.size()], "dir": rng.randi() % 2})
	var id := fields.size()
	var x0 := maxi(int(r.position.x * INV_CS), 0)
	var y0 := maxi(int(r.position.y * INV_CS), 0)
	for y in range(y0, mini(int(r.end.y * INV_CS), GH)):
		for x in range(x0, mini(int(r.end.x * INV_CS), GW)):
			var i := y * GW + x
			if terr[i] == GRASS:
				terr[i] = FIELD
				fidx[i] = id


func _hedge(a: Vector2, b: Vector2, gap_chance := 0.25) -> void:
	# изгородь с проходами: рисуем отрезками
	var n := maxi(1, int(a.distance_to(b) / 24.0))
	for k in n:
		var p0 := a.lerp(b, float(k) / n)
		var p1 := a.lerp(b, float(k + 1) / n)
		if rng.randf() < gap_chance:
			continue
		var pts := PackedVector2Array([p0, p1])
		hedges.append(pts)
		# 4-связная растеризация, чтобы линия видимости не проскакивала по диагонали
		var steps := int(ceil(p0.distance_to(p1) / 0.7))
		for j in steps + 1:
			var p := p0.lerp(p1, float(j) / maxf(steps, 1))
			var cx := int(p.x * INV_CS)
			var cy := int(p.y * INV_CS)
			for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var x: int = cx + o.x
				var y: int = cy + o.y
				if x >= 0 and y >= 0 and x < GW and y < GH:
					var t := terr[y * GW + x]
					if t == GRASS or t == FIELD or t == SCRUB:
						terr[y * GW + x] = HEDGE


func _area_free(r: Rect2, allow_field := true) -> bool:
	var x0 := int(floor(r.position.x * INV_CS))
	var y0 := int(floor(r.position.y * INV_CS))
	var x1 := int(ceil(r.end.x * INV_CS))
	var y1 := int(ceil(r.end.y * INV_CS))
	if x0 < 2 or y0 < 2 or x1 > GW - 2 or y1 > GH - 2:
		return false
	for y in range(y0, y1):
		for x in range(x0, x1):
			var t := terr[y * GW + x]
			if t == GRASS or t == SCRUB or t == FOREST or (allow_field and t == FIELD):
				continue
			return false
	return true


func _house(c: Vector2, sx: float, sy: float) -> bool:
	var r := Rect2(c - Vector2(sx, sy) * 0.5, Vector2(sx, sy))
	if not _area_free(r.grow(2.0)):
		return false
	var roofs := [Color(0.58, 0.27, 0.19), Color(0.50, 0.24, 0.18), Color(0.40, 0.40, 0.43),
		Color(0.62, 0.52, 0.32), Color(0.47, 0.30, 0.22)]
	buildings.append({"r": r, "roof": roofs[rng.randi() % roofs.size()], "ridge_x": sx >= sy})
	_fill_rect(r, BUILDING)
	# двор вокруг дома — без леса
	var yard := r.grow(3.0)
	for y in range(maxi(int(yard.position.y * INV_CS), 0), mini(int(yard.end.y * INV_CS), GH)):
		for x in range(maxi(int(yard.position.x * INV_CS), 0), mini(int(yard.end.x * INV_CS), GW)):
			if terr[y * GW + x] == FOREST or terr[y * GW + x] == SCRUB:
				terr[y * GW + x] = GRASS
	return true


func _village_along(pts: PackedVector2Array, center: Vector2, radius: float, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		var k := rng.randi() % (pts.size() - 1)
		var a := pts[k]
		var b := pts[k + 1]
		var p := a.lerp(b, rng.randf())
		if p.distance_to(center) > radius:
			continue
		var dir := (b - a).normalized()
		var horiz := absf(dir.x) > absf(dir.y)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var sx := rng.randf_range(8.0, 15.0)
		var sy := rng.randf_range(7.0, 11.0)
		if not horiz:
			var tmp := sx
			sx = sy
			sy = tmp
		var off := dir.orthogonal() * side * (rng.randf_range(5.5, 9.0) + (sy if horiz else sx) * 0.5)
		if _house(p + off, sx, sy):
			placed += 1


func _cluster(center: Vector2, count: int, spread: float) -> void:
	var placed := 0
	for i in count * 25:
		if placed >= count:
			break
		var p := center + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
		if _house(p, rng.randf_range(8.0, 16.0), rng.randf_range(7.0, 12.0)):
			placed += 1


func _rand_fields(n: int, avoid: Rect2 = Rect2()) -> void:
	for i in n:
		var r := Rect2(rng.randf_range(0, W - 80), rng.randf_range(0, H - 60),
			rng.randf_range(60, 150), rng.randf_range(45, 110))
		if avoid.size != Vector2.ZERO and r.intersects(avoid):
			continue
		_field(r)
		# изгороди по части краёв
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for e in 4:
			if rng.randf() < 0.45:
				_hedge(corners[e], corners[(e + 1) % 4], 0.3)


func _gen_village() -> void:
	var c := Vector2(W * 0.5 + rng.randf_range(-20, 20), H * 0.5 + rng.randf_range(-25, 25))
	_rand_fields(7, Rect2(c - Vector2(110, 110), Vector2(220, 220)))
	_noise_forest(0.012, 0.32, func(p: Vector2) -> float:
		return -0.6 if p.distance_to(c) < 120.0 else 0.0)
	var r1 := _wiggle(Vector2(-10, c.y + rng.randf_range(-60, 60)), Vector2(W + 10, c.y + rng.randf_range(-60, 60)), 9, 14.0)
	r1 = _through(r1, c)
	var r2 := _wiggle(Vector2(c.x + rng.randf_range(-80, 80), -10), Vector2(c.x + rng.randf_range(-80, 80), H + 10), 7, 12.0)
	r2 = _through(r2, c)
	_road(r1)
	_road(r2, 6.0)
	_village_along(r1, c, 120.0, 10)
	_village_along(r2, c, 110.0, 7)
	_cluster(c + Vector2(rng.randf_range(-60, 60), -140), 3, 25.0)
	_cluster(c + Vector2(rng.randf_range(-60, 60), 140), 3, 25.0)
	flags.append(c)
	flags.append(c + Vector2(rng.randf_range(-50, 50), -135))
	flags.append(c + Vector2(rng.randf_range(-50, 50), 135))


## Сдвигает ближайшую точку ломаной в c, чтобы дороги пересекались в центре деревни.
func _through(pts: PackedVector2Array, c: Vector2) -> PackedVector2Array:
	var best := 0
	for i in pts.size():
		if pts[i].distance_to(c) < pts[best].distance_to(c):
			best = i
	if best > 0 and best < pts.size() - 1:
		var d := c - pts[best]
		for i in pts.size():
			var f := maxf(0.0, 1.0 - absf(i - best) / 3.0)
			pts[i] += d * f
	return pts


func _gen_forest() -> void:
	_rand_fields(5, Rect2(W * 0.45, 0, W * 0.55, H))
	_noise_forest(0.015, 0.05, func(p: Vector2) -> float:
		return clampf((p.x / W - 0.5) * 2.2, -1.0, 0.6))
	var farm := Vector2(W * rng.randf_range(0.58, 0.66), H * rng.randf_range(0.35, 0.65))
	var r1 := _wiggle(Vector2(-10, H * rng.randf_range(0.3, 0.7)), Vector2(W + 10, H * rng.randf_range(0.3, 0.7)), 9, 16.0)
	r1 = _through(r1, farm + Vector2(0, 14))
	_road(r1, 6.0)
	# лесная просека
	var r2 := _wiggle(Vector2(farm.x + 10, farm.y), Vector2(farm.x + rng.randf_range(-40, 80), -10 if farm.y > H * 0.5 else H + 10), 5, 10.0)
	_road(r2, 5.0)
	_clear_disk(farm, 45.0)
	_cluster(farm, 4, 26.0)
	var fl := [farm]
	for side in [-1.0, 1.0]:
		var p := Vector2(W * rng.randf_range(0.55, 0.68), farm.y + side * rng.randf_range(110, 150))
		p.y = clampf(p.y, 40.0, H - 40.0)
		_clear_disk(p, 18.0)
		fl.append(p)
	flags = fl
	_cluster(Vector2(W * 0.2, H * rng.randf_range(0.2, 0.8)), 2, 20.0)


func _clear_disk(c: Vector2, r: float) -> void:
	var cx := int(c.x * INV_CS)
	var cy := int(c.y * INV_CS)
	var rc := int(r * INV_CS)
	for y in range(cy - rc, cy + rc + 1):
		for x in range(cx - rc, cx + rc + 1):
			if x < 0 or y < 0 or x >= GW or y >= GH:
				continue
			if Vector2(x - cx, y - cy).length() * CS > r:
				continue
			var i := y * GW + x
			if terr[i] == FOREST or terr[i] == SCRUB:
				terr[i] = GRASS


func _gen_river() -> void:
	var rx := W * 0.58
	_rand_fields(6)
	_noise_forest(0.014, 0.38, func(p: Vector2) -> float: return 0.0)
	var rv := _wiggle(Vector2(rx + rng.randf_range(-20, 20), -20), Vector2(rx + rng.randf_range(-20, 20), H + 20), 10, 14.0)
	_river(rv, 18.0)
	# брод для пехоты
	var fy := H * (0.1 if rng.randf() < 0.5 else 0.9)
	var fp := _point_on(rv, fy)
	for y in range(int((fy - 10) * INV_CS), int((fy + 10) * INV_CS)):
		for x in range(int((fp.x - 14) * INV_CS), int((fp.x + 14) * INV_CS)):
			if x >= 0 and y >= 0 and x < GW and y < GH and terr[_idx(x, y)] == WATER:
				terr[_idx(x, y)] = FORD
	var ya := H * rng.randf_range(0.25, 0.38)
	var yb := H * rng.randf_range(0.62, 0.75)
	var ra := _wiggle(Vector2(-10, ya + rng.randf_range(-30, 30)), Vector2(W + 10, ya + rng.randf_range(-30, 30)), 9, 10.0)
	var rb := _wiggle(Vector2(-10, yb + rng.randf_range(-30, 30)), Vector2(W + 10, yb + rng.randf_range(-30, 30)), 9, 10.0)
	_road(ra)
	_road(rb)
	for r in [ra, rb]:
		var bp := _cross(r, rv)
		var k := 0
		for i in r.size() - 1:
			if r[i].x <= bp.x and r[i + 1].x >= bp.x:
				k = i
		bridges.append({"p": bp, "a": (r[k + 1] - r[k]).angle(), "len": 30.0, "w": 9.0})
	var town := Vector2(rx - 95, (ya + yb) * 0.5)
	var rc := _wiggle(Vector2(town.x, ya), Vector2(town.x + rng.randf_range(-20, 20), yb), 4, 6.0)
	_road(rc, 6.0)
	_village_along(rc, town, 120.0, 8)
	_village_along(ra, Vector2(rx - 60, ya), 70.0, 3)
	_village_along(rb, Vector2(rx - 60, yb), 70.0, 3)
	_cluster(Vector2(rx + 120, H * 0.5), 3, 30.0)
	flags.append(Vector2(rx - 34, _point_on(ra, rx - 34).y + 14))
	flags.append(Vector2(rx - 34, _point_on(rb, rx - 34).y - 14))
	flags.append(town)


func _point_on(pts: PackedVector2Array, coord: float) -> Vector2:
	# точка ломаной: для вертикальной — по y, для горизонтальной — по x
	var last := pts[pts.size() - 1]
	var vertical := absf(last.y - pts[0].y) > absf(last.x - pts[0].x)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ca := a.y if vertical else a.x
		var cb := b.y if vertical else b.x
		if (coord - ca) * (coord - cb) <= 0.0 and ca != cb:
			return a.lerp(b, (coord - ca) / (cb - ca))
	return pts[0]


func _cross(road: PackedVector2Array, river: PackedVector2Array) -> Vector2:
	for i in road.size() - 1:
		for j in river.size() - 1:
			var p = Geometry2D.segment_intersects_segment(road[i], road[i + 1], river[j], river[j + 1])
			if p != null:
				return p
	return road[road.size() / 2]


func _gen_bocage() -> void:
	# сетка полей с изгородями
	var xs := [0.0]
	while xs[-1] < W:
		xs.append(xs[-1] + rng.randf_range(65, 105))
	var ys := [0.0]
	while ys[-1] < H:
		ys.append(ys[-1] + rng.randf_range(55, 95))
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var r := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if rng.randf() < 0.55:
				_field(r.grow(-3.0))
	_noise_forest(0.02, 0.42, func(p: Vector2) -> float: return 0.0)
	for i in range(1, xs.size() - 1):
		for j in ys.size() - 1:
			_hedge(Vector2(xs[i], ys[j]), Vector2(xs[i], ys[j + 1]), 0.12)
	for j in range(1, ys.size() - 1):
		for i in xs.size() - 1:
			_hedge(Vector2(xs[i], ys[j]), Vector2(xs[i + 1], ys[j]), 0.12)
	var lane := _wiggle(Vector2(-10, H * rng.randf_range(0.35, 0.65)), Vector2(W + 10, H * rng.randf_range(0.35, 0.65)), 8, 8.0)
	_road(lane, 6.0)
	var lane2 := _wiggle(Vector2(W * rng.randf_range(0.4, 0.6), -10), Vector2(W * rng.randf_range(0.4, 0.6), H + 10), 6, 8.0)
	_road(lane2, 5.0)
	var c := _cross(lane, lane2)
	_village_along(lane, c, 60.0, 4)
	_cluster(Vector2(W * 0.5 + rng.randf_range(-40, 40), H * 0.18), 2, 20.0)
	_cluster(Vector2(W * 0.5 + rng.randf_range(-40, 40), H * 0.82), 2, 20.0)
	flags.append(c)
	flags.append(Vector2(W * 0.5 + rng.randf_range(-60, 60), H * 0.2))
	flags.append(Vector2(W * 0.5 + rng.randf_range(-60, 60), H * 0.8))


func _gen_steppe() -> void:
	_rand_fields(5)
	_noise_forest(0.01, 0.48, func(p: Vector2) -> float: return 0.0)
	_noise_forest(0.03, 0.45, func(p: Vector2) -> float: return 0.0, SCRUB)
	var r1 := _wiggle(Vector2(-10, H * rng.randf_range(0.3, 0.7)), Vector2(W + 10, H * rng.randf_range(0.3, 0.7)), 8, 18.0)
	_road(r1, 6.0)
	var c := _point_on(r1, W * 0.5)
	_village_along(r1, c, 50.0, 4)
	flags.append(c)
	flags.append(Vector2(W * 0.5 + rng.randf_range(-80, 80), H * rng.randf_range(0.12, 0.22)))
	flags.append(Vector2(W * 0.5 + rng.randf_range(-80, 80), H * rng.randf_range(0.78, 0.88)))
	for f in [flags[1], flags[2]]:
		# небольшая роща у точки — ориентир и укрытие
		for k in 4:
			var p: Vector2 = f + Vector2(rng.randf_range(-45, 45), rng.randf_range(-35, 35))
			if p.distance_to(f) > 22.0:
				_disk(p, rng.randf_range(8, 15), FOREST, 1)


# ===================== Запросы =====================

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x * INV_CS), 0, GW - 1), clampi(int(p.y * INV_CS), 0, GH - 1))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CS, (c.y + 0.5) * CS)


func terr_at(p: Vector2) -> int:
	var c := cell_of(p)
	return terr[c.y * GW + c.x]


func cover_at(p: Vector2) -> float:
	var c := cell_of(p)
	var i := c.y * GW + c.x
	return minf(0.8, cover[i] + cover_bonus[i])


func speed_at(p: Vector2, veh: bool) -> float:
	var t := terr_at(p)
	return SPD_V[t] if veh else SPD_I[t]


func passable(p: Vector2, veh: bool) -> bool:
	if p.x < 1.0 or p.y < 1.0 or p.x > W - 1.0 or p.y > H - 1.0:
		return false
	return speed_at(p, veh) > 0.0


func in_bounds(p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x < W and p.y < H


func clamp_in(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 3.0, W - 3.0), clampf(p.y, 3.0, H - 3.0))


func nearest_passable(p: Vector2, veh: bool, max_r := 30) -> Vector2:
	p = clamp_in(p)
	if passable(p, veh):
		return p
	var c := cell_of(p)
	for r in range(1, max_r):
		var best := Vector2.INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := cell_center(Vector2i(c.x + dx, c.y + dy))
				if passable(q, veh) and q.distance_squared_to(p) < best.distance_squared_to(p):
					best = q
		if best != Vector2.INF:
			return best
	return p


## Лучшее укрытие в радиусе r от точки (для бойцов отделения). used — занятые клетки.
func cover_spot(p: Vector2, r: float, used: Dictionary) -> Vector2:
	var c := cell_of(p)
	var rc := int(ceil(r * INV_CS))
	var best := p
	var best_s := -INF
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 1 or y < 1 or x >= GW - 1 or y >= GH - 1:
				continue
			var i := y * GW + x
			if used.has(i) or SPD_I[terr[i]] <= 0.0:
				continue
			var q := Vector2((x + 0.5) * CS, (y + 0.5) * CS)
			var d := q.distance_to(p)
			if d > r:
				continue
			var s: float = cover[i] + cover_bonus[i] - d * 0.03
			if s > best_s:
				best_s = s
				best = q
	used[cell_of(best).y * GW + cell_of(best).x] = true
	return best + Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))


## Ищет клетку с лучшим укрытием возле точки — для ИИ.
func find_cover_near(p: Vector2, r: float, veh: bool) -> Vector2:
	var best := nearest_passable(p, veh)
	var best_s := -INF
	for i in 24:
		var q := clamp_in(p + Vector2.from_angle(randf() * TAU) * randf() * r)
		if not passable(q, veh):
			continue
		var t := terr_at(q)
		var s: float = (cover_at(q) if not veh else (0.4 if t == FOREST or t == SCRUB else 0.0)) - q.distance_to(p) / r * 0.15
		if s > best_s:
			best_s = s
			best = q
	return best


func los(a: Vector2, b: Vector2, smokes: Array) -> bool:
	return los_amount(a, b, smokes) < 1.0


func los_amount(a: Vector2, b: Vector2, smokes: Array) -> float:
	var d := a.distance_to(b)
	if d < 10.0:
		return 0.0
	var n := int(d * 0.5)
	var sx := (b.x - a.x) / n
	var sy := (b.y - a.y) / n
	var sl := d / n
	var skip := int(6.0 / sl) + 1
	var acc := 0.0
	var x := a.x + sx * skip
	var y := a.y + sy * skip
	for i in range(skip, n - skip + 1):
		var cx := int(x * INV_CS)
		var cy := int(y * INV_CS)
		if cx >= 0 and cy >= 0 and cx < GW and cy < GH:
			acc += opac[cy * GW + cx] * sl
			if acc >= 1.0:
				return acc
		x += sx
		y += sy
	for s in smokes:
		if s.dens <= 0.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(s.p, a, b)
		var r: float = s.r
		var dd: float = q.distance_to(s.p)
		if dd < r:
			acc += 2.0 * sqrt(r * r - dd * dd) * s.dens
			if acc >= 1.0:
				return acc
	return acc


func add_crater(p: Vector2, r: float) -> void:
	var c := cell_of(p)
	var rc := maxi(1, int(r * INV_CS))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x >= 0 and y >= 0 and x < GW and y < GH:
				var i := y * GW + x
				if terr[i] != BUILDING and terr[i] != WATER:
					cover_bonus[i] = minf(0.3, cover_bonus[i] + 0.12)


# ===================== Поиск пути =====================

func _build_astar() -> void:
	astar_i = _make_astar(false)
	astar_v = _make_astar(true)


func _make_astar(veh: bool) -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, GW, GH)
	a.cell_size = Vector2(CS, CS)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.update()
	var spd: Array = SPD_V if veh else SPD_I
	for y in GH:
		for x in GW:
			var s: float = spd[terr[y * GW + x]]
			var id := Vector2i(x, y)
			if s <= 0.0:
				a.set_point_solid(id, true)
			else:
				a.set_point_weight_scale(id, 1.0 / s)
	# у машин клетки возле зданий и воды дороже — чтобы не цеплять углы
	if veh:
		for y in range(1, GH - 1):
			for x in range(1, GW - 1):
				if a.is_point_solid(Vector2i(x, y)):
					continue
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if a.is_point_solid(Vector2i(x, y) + o):
						a.set_point_weight_scale(Vector2i(x, y), a.get_point_weight_scale(Vector2i(x, y)) * 2.5)
						break
	return a


func find_path(from: Vector2, to: Vector2, veh: bool) -> PackedVector2Array:
	var a := astar_v if veh else astar_i
	var s := cell_of(nearest_passable(from, veh, 8))
	var e := cell_of(nearest_passable(to, veh))
	if a.is_point_solid(s) or a.is_point_solid(e):
		return PackedVector2Array()
	var ids := a.get_id_path(s, e)
	if ids.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(cell_center(id))
	pts[pts.size() - 1] = nearest_passable(to, veh)
	return _smooth(pts, veh)


func _seg_cost_ok(a: Vector2, b: Vector2, veh: bool, max_w: float) -> bool:
	var n := int(a.distance_to(b)) + 1
	var spd: Array = SPD_V if veh else SPD_I
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var s: float = spd[terr_at(p)]
		if s <= 0.0 or 1.0 / s > max_w + 0.01:
			return false
		if veh:
			# запас по ширине корпуса
			var nrm := (b - a).orthogonal().normalized() * 2.0
			if speed_at(p + nrm, true) <= 0.0 or speed_at(p - nrm, true) <= 0.0:
				return false
	return true


func _smooth(pts: PackedVector2Array, veh: bool) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var spd: Array = SPD_V if veh else SPD_I
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := i + 1
		var max_w := 1.0 / maxf(spd[terr_at(pts[i])], 0.05)
		max_w = maxf(max_w, 1.0 / maxf(spd[terr_at(pts[j])], 0.05))
		while j + 1 < pts.size():
			var mw := maxf(max_w, 1.0 / maxf(spd[terr_at(pts[j + 1])], 0.05))
			if j + 1 - i > 40 or not _seg_cost_ok(pts[i], pts[j + 1], veh, mw):
				break
			max_w = mw
			j += 1
		out.append(pts[j])
		i = j
	return out


# ===================== Отрисовка =====================

func _build_ground() -> void:
	var w := int(W)
	var h := int(H)
	var n1 := FastNoiseLite.new()
	n1.seed = rng.randi()
	n1.frequency = 0.02
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.frequency = 0.25
	var img1 := n1.get_image(w, h)
	var img2 := n2.get_image(w, h)
	img1.convert(Image.FORMAT_L8)
	img2.convert(Image.FORMAT_L8)
	var d1 := img1.get_data()
	var d2 := img2.get_data()
	var out := PackedByteArray()
	out.resize(w * h * 3)
	var cols := []
	for c in BASE_COL:
		cols.append([c.r * 255.0, c.g * 255.0, c.b * 255.0])
	var fcols := [[0.0, 0.0, 0.0]]
	for f in fields:
		var c: Color = f.col
		fcols.append([c.r * 255.0, c.g * 255.0, c.b * 255.0, f.dir])
	var k := 0
	for y in h:
		var cy := mini(int(y * INV_CS), GH - 1) * GW
		for x in w:
			var ci := cy + mini(int(x * INV_CS), GW - 1)
			var t := terr[ci]
			var base: Array
			var m := 0.82 + d1[k] / 255.0 * 0.3 + (d2[k] / 255.0 - 0.5) * 0.12
			if t == FIELD and fidx[ci] > 0:
				base = fcols[fidx[ci]]
				var stripe := (x if base[3] == 0 else y) % 4
				if stripe < 2:
					m *= 0.9
			else:
				base = cols[t]
			var o := k * 3
			out[o] = clampi(int(base[0] * m), 0, 255)
			out[o + 1] = clampi(int(base[1] * m), 0, 255)
			out[o + 2] = clampi(int(base[2] * m), 0, 255)
			k += 1
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, out)
	# сглаживание ступенек сетки при увеличении
	img.resize(w * 2, h * 2, Image.INTERPOLATE_CUBIC)
	if ground == null:
		ground = Sprite2D.new()
		ground.centered = false
		ground.show_behind_parent = true
		ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ground.scale = Vector2(0.5, 0.5)
		add_child(ground)
	ground.texture = ImageTexture.create_from_image(img)


static func blob(ci: CanvasItem, c: Vector2, r: float, col: Color, seg := 9, phase := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := phase + TAU * i / seg
		var rr := r * (0.88 + 0.12 * sin(a * 3.0 + phase * 5.0))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


func _draw() -> void:
	# реки
	for rv in rivers:
		var pts: PackedVector2Array = rv[0]
		var w: float = rv[1]
		draw_polyline(pts, Color(0.30, 0.27, 0.18), w + 4.0)
		draw_polyline(pts, Color(0.17, 0.30, 0.38), w)
		draw_polyline(pts, Color(0.22, 0.38, 0.47), w * 0.55)
		for p in pts:
			blob(self, p, w * 0.5 + 2.0, Color(0.30, 0.27, 0.18), 10)
			blob(self, p, w * 0.5, Color(0.17, 0.30, 0.38), 10)
	# броды
	for i in GW * GH:
		if terr[i] == FORD:
			var x := i % GW
			var y := i / GW
			draw_rect(Rect2(x * CS, y * CS, CS, CS), Color(0.40, 0.48, 0.45, 0.8))
	# дороги
	for r in roads:
		var pts: PackedVector2Array = r
		draw_polyline(pts, Color(0.42, 0.36, 0.25), 7.5)
		draw_polyline(pts, Color(0.60, 0.52, 0.37), 6.0)
		for p in pts:
			draw_circle(p, 3.0, Color(0.60, 0.52, 0.37))
		var off := PackedVector2Array()
		var off2 := PackedVector2Array()
		for i in pts.size():
			var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized().orthogonal()
			off.append(pts[i] + d * 1.3)
			off2.append(pts[i] - d * 1.3)
		draw_polyline(off, Color(0.50, 0.43, 0.30), 0.6)
		draw_polyline(off2, Color(0.50, 0.43, 0.30), 0.6)
	# мосты
	for b in bridges:
		var tr := Transform2D(b.a, b.p)
		draw_set_transform_matrix(tr)
		var hl: float = b.len * 0.5
		var hw: float = b.w * 0.5
		draw_rect(Rect2(-hl - 1, -hw - 1.2, b.len + 2, b.w + 2.4), Color(0.25, 0.22, 0.18))
		draw_rect(Rect2(-hl, -hw, b.len, b.w), Color(0.50, 0.40, 0.28))
		var x := -hl
		while x < hl:
			draw_line(Vector2(x, -hw), Vector2(x, hw), Color(0.38, 0.30, 0.20), 0.25)
			x += 1.2
		draw_rect(Rect2(-hl, -hw - 0.6, b.len, 0.6), Color(0.30, 0.25, 0.18))
		draw_rect(Rect2(-hl, hw, b.len, 0.6), Color(0.30, 0.25, 0.18))
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_top() -> void:
	var ci := top
	# изгороди
	for hdg in hedges:
		var a: Vector2 = hdg[0]
		var b: Vector2 = hdg[1]
		ci.draw_line(a, b, Color(0.14, 0.22, 0.09), 2.6)
		var n := int(a.distance_to(b) / 1.6)
		for i in n + 1:
			var p := a.lerp(b, float(i) / maxf(n, 1))
			var r := 1.3 + 0.5 * absf(sin(p.x * 1.7 + p.y * 2.3))
			blob(ci, p + Vector2(0.4, 0.5), r, Color(0.08, 0.13, 0.05, 0.5), 7, p.x)
			blob(ci, p, r, Color(0.20, 0.31, 0.12), 7, p.y)
			blob(ci, p - Vector2(0.3, 0.3), r * 0.55, Color(0.27, 0.40, 0.16), 6, p.x)
	# здания
	for bd in buildings:
		var r: Rect2 = bd.r
		var roof: Color = bd.roof
		ci.draw_rect(Rect2(r.position + Vector2(1.6, 1.8), r.size), Color(0, 0, 0, 0.35))
		ci.draw_rect(r.grow(0.3), roof.darkened(0.5))
		if bd.ridge_x:
			var hh := r.size.y * 0.5
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x, hh)), roof.lightened(0.08))
			ci.draw_rect(Rect2(r.position + Vector2(0, hh), Vector2(r.size.x, hh)), roof.darkened(0.12))
			ci.draw_line(r.position + Vector2(0, hh), r.position + Vector2(r.size.x, hh), roof.darkened(0.35), 0.35)
			var x := r.position.x + 0.9
			while x < r.end.x:
				ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.08), 0.15)
				x += 0.9
		else:
			var hw := r.size.x * 0.5
			ci.draw_rect(Rect2(r.position, Vector2(hw, r.size.y)), roof.lightened(0.08))
			ci.draw_rect(Rect2(r.position + Vector2(hw, 0), Vector2(hw, r.size.y)), roof.darkened(0.12))
			ci.draw_line(r.position + Vector2(hw, 0), r.position + Vector2(hw, r.size.y), roof.darkened(0.35), 0.35)
			var y := r.position.y + 0.9
			while y < r.end.y:
				ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.08), 0.15)
				y += 0.9
		# труба
		var ch := r.position + r.size * Vector2(0.75, 0.3)
		ci.draw_rect(Rect2(ch, Vector2(0.9, 0.9)), Color(0.35, 0.25, 0.22))
	# деревья: тень, крона, блик
	for t in trees:
		var p := Vector2(t.x, t.y)
		blob(ci, p + Vector2(t.z * 0.35, t.z * 0.4), t.z, Color(0.03, 0.06, 0.02, 0.35), 8, t.x)
	for t in trees:
		var p := Vector2(t.x, t.y)
		var g := 0.85 + 0.3 * fmod(absf(t.x * 13.1 + t.y * 7.7), 1.0)
		blob(ci, p, t.z, Color(0.14 * g, 0.25 * g, 0.10 * g), 9, t.y)
		blob(ci, p - Vector2(t.z * 0.25, t.z * 0.25), t.z * 0.55, Color(0.20 * g, 0.33 * g, 0.13 * g), 7, t.x)
