extends Node3D
## Бой: рельеф и карта, физика танков, баллистика, броня и модули, засвет, ИИ, камера и звук.
##
## Физика танка: импульс центра масс (скорость не обязана совпадать с курсом — в поворотах и на
## боковом склоне корпус чуть сносит), тяга по удельной мощности, сопротивление грунта, сила
## тяжести вдоль склона, инерция поворота, удары о препятствия и тараны с обменом импульсом.
## Снаряды летят по баллистической траектории; броня считается с учётом угла встречи,
## нормализации и перекрытия калибром; гусеницы, двигатель и боеукладка повреждаются.

signal ended(stats: Dictionary)
signal leave(again: bool)

const D = preload("res://scripts/data.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const Terrain = preload("res://scripts/terrain.gd")
const TankScript = preload("res://scripts/tank.gd")
const HudScript = preload("res://scripts/hud.gd")
const FxScript = preload("res://scripts/fx.gd")
const SfxScript = preload("res://scripts/sfx.gd")

const TRK := 1600  # следов гусениц одновременно
const SCORCH := 160  # пятен от разрывов
const SENS_X := 0.0045  # поворот камеры, рад на точку свайпа
const SENS_Y := 0.003
const MASK_WORLD := 3  # рельеф + постройки
const TRACK_REPAIR := 7.0  # сколько стоит танк с перебитой гусеницей, с
const FIRE_TIME := 6.0  # сколько горит двигатель, с

var mode := "standard"
var map_key := "prokhorovka"
var hq := true
var player_type := "t34"

var terra: Terrain
var obst: Array = []
var bushes: Array = []
var props: Array = []
var falling: Array = []
var zones: Array = []
var tanks: Array = []
var shells: Array = []
var texts: Array = []
var bush_mat: ShaderMaterial
var grip_base := 0.85

var player: TankScript
var watch: TankScript
var cam: Camera3D
var cam_yaw := -PI / 2
var cam_pitch := 0.07
var sniper := false
var aim_point := Vector3.ZERO
var gun_point = null  # Vector3 или null — куда реально упадёт снаряд
var pen_hint := -1  # -1 нет цели, 0 не пробьёт, 1 возможно, 2 пробьёт
var gun_limited := false  # орудие упёрлось в предел склонения или возвышения
var shake := 0.0
var clock := 0.0
var spot_t := 0.0
var paused := false
var over := false
var over_t := 0.0
var result_shown := false
var speed := 1
var result := ""
var reason := ""
var score := [0.0, 0.0]
var kills := 0
var dmg_done := 0.0
var hits := 0
var shots := 0
var stat := {"pen": 0, "nopen": 0, "rico": 0, "miss": 0, "ram": 0, "track": 0, "fire": 0, "ammo": 0}

var hud: HudScript
var fx: FxScript
var sfx: SfxScript
var trk_mm: MultiMesh
var trk_i := 0
var scorch_mm: MultiMesh
var scorch_i := 0
var shell_mesh: BoxMesh
var shell_mat: StandardMaterial3D
var loops := {}  # танк -> [двигатель, гусеницы, башня]
var reload_cue := false


func setup(cfg: Dictionary) -> void:
	mode = cfg.mode
	map_key = cfg.map
	hq = cfg.hq
	player_type = cfg.tank


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	grip_base = D.MAPS[map_key].grip
	zones = MapGen.make_zones(mode)
	var data := MapGen.generate(map_key, zones, rng)
	obst = data.obst
	bushes = data.bushes
	props = data.props
	terra = Terrain.new()
	terra.generate(map_key, zones, obst, data.craters, data.roads)
	terra.build(self, map_key, hq)
	var built := MapGen.build(self, data, map_key, zones, terra, hq)
	bush_mat = built.bush_mat
	_make_env()
	fx = FxScript.new()
	add_child(fx)
	fx.set_dust(Color(D.MAPS[map_key].dust))
	for s in built.smokes:
		fx.smoke_column(s, false)
	for i in 3:
		var a := randf() * TAU
		var p := Vector2(D.WS / 2, D.WS / 2) + Vector2.from_angle(a) * randf_range(1300.0, 1500.0)
		fx.smoke_column(Vector3(p.x, terra.height(p.x, p.y), p.y), true)
	sfx = SfxScript.new()
	add_child(sfx)
	trk_mm = _decal_mm(TRK, Vector2(3.2, 2.6), Color(0.48, 0.52, 0.56, 0.45) if map_key == "stalingrad" else Color(0.18, 0.15, 0.1, 0.4), false)
	scorch_mm = _decal_mm(SCORCH, Vector2(1, 1), Color(0.05, 0.045, 0.04, 0.75), true)
	shell_mesh = BoxMesh.new()
	shell_mesh.size = Vector3(0.9, 0.9, 22)
	shell_mat = MapGen.mat(Color(1.0, 0.78, 0.4), true)
	shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spawn()
	cam = Camera3D.new()
	cam.near = 0.5
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	layer.add_child(hud)
	hud.add_feed([["%s · %s" % [D.MODES[mode].name, D.MAPS[map_key].name], Color(D.AMBER)]])
	for tk: TankScript in tanks:
		_suspend(tk, 1.0)
		tk.sync_node()
	_update_spotting()
	_sync(0.0)


func _make_env() -> void:
	var M: Dictionary = D.MAPS[map_key]
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(M.sky_top)
	sky_mat.sky_horizon_color = Color(M.sky_hor)
	sky_mat.ground_horizon_color = Color(M.sky_hor)
	sky_mat.ground_bottom_color = Color(M.g1).darkened(0.3)
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(M.sky_hor).lerp(Color.WHITE, 0.25)
	env.ambient_light_energy = M.amb
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(M.fog)
	env.fog_depth_begin = 380.0 if map_key == "stalingrad" else 520.0
	env.fog_depth_end = 1500.0 if map_key == "stalingrad" else 1900.0
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -42, 0) if map_key != "stalingrad" else Vector3(-48, 20, 0)
	sun.light_color = Color(M.sun)
	sun.light_energy = M.sun_e
	sun.shadow_enabled = hq
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 520.0
	sun.directional_shadow_split_1 = 0.18
	sun.shadow_blur = 1.2
	add_child(sun)


## Плоские отметки на земле (следы, гарь) в одной MultiMesh.
func _decal_mm(count: int, size: Vector2, col: Color, soft: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = size
	mm.mesh = q
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
	var m := MapGen.mat(col, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if soft:
		m.albedo_texture = fx.soft
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _ground_basis(x: float, z: float) -> Basis:
	return Basis(Quaternion(Vector3.UP, terra.normal(x, z)))


func _spawn() -> void:
	var ws := D.WS
	var keys: Array = D.TYPES.keys()
	var names: Array = D.NAMES.duplicate()
	names.shuffle()
	player = _add_tank(player_type, 0, Vector2(ws / 2, ws - 300), "Вы", true)
	watch = player
	for i in 4:
		var side := -1.0 if i < 2 else 1.0
		var b := _add_tank(keys[randi() % keys.size()], 0, Vector2(ws / 2 + side * (150.0 + (i % 2) * 160.0), ws - 310.0 - (i % 2) * 30.0), names.pop_back(), false)
		if i == 0:
			b.role = "def"
	for i in 5:
		var b := _add_tank(keys[randi() % keys.size()], 1, Vector2(ws / 2 + (i - 2) * 160.0, 300.0 + (i % 2) * 30.0), names.pop_back(), false)
		if i == 0:
			b.role = "def"


func _add_tank(key: String, team: int, p: Vector2, nm: String, is_player: bool) -> TankScript:
	var tk: TankScript = TankScript.new()
	add_child(tk)
	tk.setup(key, team, p, nm, is_player, hq)
	tk.set_dust(Color(D.MAPS[map_key].dust), 0.75 if map_key == "alamein" else 0.55)
	tk.smoke = fx.damage_smoke(tk, tk.hh)
	tanks.append(tk)
	var engine := "engine_" + String(tk.T.engine)
	loops[tk] = [sfx.attach_loop(tk, engine, 26.0 if is_player else 20.0, -2.0 if is_player else -6.0),
		sfx.attach_loop(tk, "tracks", 22.0, -40.0),
		sfx.attach_loop(tk, "turret", 8.0, -80.0) if is_player else null]
	return tk


# ---------- Геометрия и лучи ----------

static func ang_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


static func turn_toward(cur: float, target: float, step: float) -> float:
	var d := ang_diff(target, cur)
	return target if absf(d) <= step else cur + signf(d) * step


func in_rect(p: Vector2):
	for o in obst:
		if (o.r as Rect2).has_point(p):
			return o
	return null


func in_bush(p: Vector2):
	for b in bushes:
		if p.distance_squared_to(b.pos) < float(b.r) * float(b.r):
			return b
	return null


func blocked_at(p: Vector2, r: float) -> bool:
	if p.x < r or p.y < r or p.x > D.WS - r or p.y > D.WS - r:
		return true
	for o in obst:
		if (o.r as Rect2).grow(r).has_point(p):
			return true
	return false


func ray(from: Vector3, to: Vector3, mask := MASK_WORLD) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)


func clear_line(a: Vector3, b: Vector3) -> bool:
	return ray(a, b).is_empty()


## Пересечение отрезка с параллелепипедом в локальных координатах: [t, нормаль грани] или [].
static func slab(o: Vector3, d: Vector3, mn: Vector3, mx: Vector3) -> Array:
	var tmin := 0.0
	var tmax := 1.0
	var nrm := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 1e-6:
			if o[a] < mn[a] or o[a] > mx[a]:
				return []
		else:
			var t1 := (mn[a] - o[a]) / d[a]
			var t2 := (mx[a] - o[a]) / d[a]
			var s := -1.0
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
				s = 1.0
			if t1 > tmin:
				tmin = t1
				nrm = Vector3.ZERO
				nrm[a] = s
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return []
	return [tmin, nrm]


## Луч по танкам (корпус и башня как коробки). Возвращает ближайшее попадание.
func ray_tanks(from: Vector3, to: Vector3, exclude: TankScript) -> Dictionary:
	var best := {}
	var bt := 2.0
	var seg := to - from
	for tk: TankScript in tanks:
		if tk == exclude:
			continue
		var c := tk.center()
		var cl := Geometry3D.get_closest_point_to_segment(c, from, to)
		if cl.distance_to(c) > float(tk.T.L) * 0.8:
			continue
		var L: float = tk.T.L
		var W: float = tk.T.W
		var parts := [
			["hull", tk.hull_node.global_transform, Vector3(-L / 2, 0.35 * D.UPM, -W / 2), Vector3(L / 2, tk.hh, W / 2)],
			["turret", tk.tur_node.global_transform, Vector3(-tk.tur_b, 0, -tk.tz), Vector3(tk.tur_f, tk.tur_h, tk.tz)],
		]
		for part in parts:
			var xf: Transform3D = part[1]
			var inv := xf.affine_inverse()
			var r := slab(inv * from, inv.basis * seg, part[2], part[3])
			if r.is_empty() or r[0] >= bt:
				continue
			bt = r[0]
			var n: Vector3 = r[1]
			if n == Vector3.ZERO:
				n = -(inv.basis * seg).normalized()
			best = {"t": bt, "tank": tk, "part": part[0], "n_local": n, "xf": xf, "pos": from + seg * bt}
	return best


## Баллистическая трасса: куда упадёт снаряд, выпущенный из from со скоростью v.
func trace(from: Vector3, v: Vector3, exclude: TankScript, max_t := 1.2) -> Dictionary:
	var p := from
	var vel := v
	var steps := 16
	var dt := max_t / steps
	for i in steps:
		var nv := vel + Vector3(0, -D.GRAVITY * dt, 0)
		var np := p + (vel + nv) * 0.5 * dt
		var wh := ray(p, np)
		var th := ray_tanks(p, np, exclude)
		var tw := 2.0
		if not wh.is_empty():
			tw = p.distance_to(wh.position) / maxf(p.distance_to(np), 0.001)
		if not th.is_empty() and th.t <= tw:
			th["vel"] = nv
			return th
		if not wh.is_empty():
			return {"pos": wh.position, "vel": nv}
		p = np
		vel = nv
	return {"pos": p, "vel": vel}


## Броня в точке попадания: [толщина, нормаль в мире, зона].
func armor_at(tk: TankScript, hitd: Dictionary) -> Array:
	var A: Array = tk.T.armor
	var n: Vector3 = hitd.n_local
	var xf: Transform3D = hitd.xf
	var turret: bool = hitd.part == "turret"
	var thick: float
	var nl := n
	var zone := "side"
	if n.x > 0.5:
		thick = A[3] if turret else A[0]
		var sl: float = 0.25 if turret else float(tk.T.slope)
		nl = Vector3(cos(sl), sin(sl), 0)
		zone = "front"
	elif n.x < -0.5:
		thick = A[5] if turret else A[2]
		zone = "rear"
	elif n.y > 0.5:
		thick = float(A[4] if turret else A[1]) * 0.45
		zone = "roof"
	elif n.y < -0.5:
		thick = float(A[1]) * 0.4
		zone = "floor"
	else:
		thick = A[4] if turret else A[1]
		if not turret:
			var ss: float = tk.T.side_slope
			nl = Vector3(0, sin(ss), cos(ss) * signf(n.z))
	return [thick, (xf.basis * nl).normalized(), zone]


func grip_at(p: Vector2) -> float:
	var m := terra.mask
	var px := clampi(int((p.x - Terrain.ORIGIN) / Terrain.SIZE * m.get_width()), 0, m.get_width() - 1)
	var pz := clampi(int((p.y - Terrain.ORIGIN) / Terrain.SIZE * m.get_height()), 0, m.get_height() - 1)
	var c := m.get_pixel(px, pz)
	return lerpf(grip_base, 1.0, clampf(c.r * 1.2, 0.0, 1.0)) * (1.0 - c.g * 0.12)


# ---------- Физика танка ----------

static func radius(tk: TankScript) -> float:
	return float(tk.T.W) * 0.62


## Выталкивает танк из построек; возвращает вектор выталкивания.
func resolve(tk: TankScript) -> Vector2:
	var r := radius(tk)
	var before := tk.pos
	for o in obst:
		var R: Rect2 = o.r
		var c := Vector2(clampf(tk.pos.x, R.position.x, R.end.x), clampf(tk.pos.y, R.position.y, R.end.y))
		var d := tk.pos - c
		var d2 := d.length_squared()
		if d2 >= r * r:
			continue
		if d2 > 0.0001:
			var dl := sqrt(d2)
			tk.pos += d * ((r - dl) / dl)
		else:
			var l := tk.pos.x - R.position.x
			var rr := R.end.x - tk.pos.x
			var tp := tk.pos.y - R.position.y
			var bt := R.end.y - tk.pos.y
			var m := minf(minf(l, rr), minf(tp, bt))
			if m == l:
				tk.pos.x = R.position.x - r
			elif m == rr:
				tk.pos.x = R.end.x + r
			elif m == tp:
				tk.pos.y = R.position.y - r
			else:
				tk.pos.y = R.end.y + r
	tk.pos = tk.pos.clamp(Vector2(r, r), Vector2(D.WS - r, D.WS - r))
	return tk.pos - before


## Деревья и заборы: тяжёлый или быстрый танк их валит, медленный упирается.
func _props_collide(tk: TankScript) -> void:
	var r := radius(tk)
	for pr in props:
		if not pr.alive:
			continue
		var d: Vector2 = tk.pos - pr.pos
		var mn: float = r + float(pr.r)
		if d.length_squared() >= mn * mn:
			continue
		var spd := tk.vel.length()
		if spd > 12.0 or float(tk.T.mass) > 40.0:
			pr.alive = false
			pr.fall = 0.02
			pr.fall_dir = tk.vel.normalized() if spd > 1.0 else -d.normalized()
			falling.append(pr)
			tk.vel *= 0.85
			sfx.play3d("tree", Vector3(pr.pos.x, pr.y + 5.0, pr.pos.y))
			fx.debris(Vector3(pr.pos.x, pr.y + 6.0, pr.pos.y), Color(0.3, 0.24, 0.16))
		else:
			var l := d.length()
			if l > 0.001:
				tk.pos += d / l * (mn - l)
				var nrm := d / l
				var vn := tk.vel.dot(nrm)
				if vn < 0:
					tk.vel -= nrm * vn


## Ходовая: газ/тормоз и поворот как у гусеничной машины, всё через импульс корпуса.
func drive(tk: TankScript, dt: float, thr: float, steer: float) -> void:
	var T := tk.T
	if tk.track_broken > 0.0:
		thr = 0.0
		steer = 0.0
	thr = clampf(thr, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	tk.throttle = thr
	var g := D.GRAVITY
	var grip := grip_at(tk.pos)
	var vmax: float = float(T.speed) * grip
	var vrev: float = float(T.rev_speed) * grip
	var fwd := Vector2.from_angle(tk.hull)
	var v_f := tk.vel.dot(fwd)
	# инерция поворота: угловая скорость набирается не мгновенно
	var rev := v_f < -1.0 or thr < -0.05
	var want_turn: float = float(T.turn) * steer * (-1.0 if rev else 1.0) * (1.0 - clampf(absf(v_f) / maxf(vmax, 1.0), 0.0, 1.0) * 0.3)
	tk.yaw_rate = move_toward(tk.yaw_rate, want_turn, float(T.turn) * 3.0 * dt)
	tk.hull = wrapf(tk.hull + tk.yaw_rate * dt, -PI, PI)
	# скорость остаётся в мировых осях — в повороте часть её становится боковой и гасится сцеплением
	fwd = Vector2.from_angle(tk.hull)
	var right := Vector2(-fwd.y, fwd.x)
	v_f = tk.vel.dot(fwd)
	var v_l := tk.vel.dot(right)
	var e := 4.0
	var grad := Vector2(terra.height(tk.pos.x + e, tk.pos.y) - terra.height(tk.pos.x - e, tk.pos.y),
		terra.height(tk.pos.x, tk.pos.y + e) - terra.height(tk.pos.x, tk.pos.y - e)) / (2.0 * e)
	var slope_f := grad.dot(fwd)
	var slope_l := grad.dot(right)
	var a := 0.0
	if absf(thr) > 0.05:
		var target := thr * (vmax if thr > 0 else vrev) * (1.0 - absf(steer) * 0.25)
		var push: float = float(T.accel) * grip * (1.0 - clampf(absf(v_f) / maxf(vmax, 1.0), 0.0, 1.0) * 0.6)
		a = clampf((target - v_f) * 2.5, -push * 2.5, push)
	else:
		a = -signf(v_f) * minf(absf(v_f) * 3.0, 0.4 * g)  # торможение двигателем и фрикционами
	a -= g * slope_f / sqrt(1.0 + slope_f * slope_f)  # составляющая веса вдоль корпуса
	v_f += a * dt
	# сопротивление качению (на мягком грунте больше)
	v_f = move_toward(v_f, 0.0, g * (0.03 + (1.0 - grip) * 0.08) * dt)
	if absf(thr) <= 0.05 and absf(v_f) < 1.5 and absf(slope_f) < 0.55:
		v_f = 0.0
	v_f = clampf(v_f, -vrev * 1.15, vmax * 1.15)
	# поперёк гусеницы держат крепко, но на боковом склоне и в резком повороте корпус сносит
	v_l -= g * slope_l / sqrt(1.0 + slope_l * slope_l) * dt
	v_l = move_toward(v_l, 0.0, 0.85 * g * grip * dt)
	tk.accel = a
	tk.vel = fwd * v_f + right * v_l
	tk.sp = v_f
	var old := tk.pos
	tk.pos += tk.vel * dt
	var pushv := resolve(tk)
	if pushv.length_squared() > 0.0001:
		var nrm := pushv.normalized()
		var vn := tk.vel.dot(nrm)
		if vn < 0:
			tk.vel -= nrm * vn * 1.2  # удар о стену гасит скорость в сторону стены
			if -vn > 25.0:
				sfx.play3d("impact_stone", tk.center(), -6.0)
				if tk == watch:
					shake = maxf(shake, clampf(-vn * 0.08, 2.0, 8.0))
				tk.pitch_v -= signf(tk.vel.dot(fwd) + 0.01) * 0.6
	_props_collide(tk)
	var moved := tk.pos.distance_to(old)
	tk.dist_travel += moved
	# путь гусениц: в повороте внешняя бежит быстрее
	var half_w: float = float(T.W) * 0.5
	tk.travel[0] += (v_f + tk.yaw_rate * half_w) * dt
	tk.travel[1] += (v_f - tk.yaw_rate * half_w) * dt
	if tk.dist_travel - tk.mark > 6.0 and (absf(v_f) > 6.0 or absf(tk.yaw_rate) > 0.25):
		tk.mark = tk.dist_travel
		var side := right * (float(T.W) * 0.39)
		for s: float in [1.0, -1.0]:
			var p := tk.pos + side * s
			var b := _ground_basis(p.x, p.y) * Basis(Vector3.UP, -tk.hull) * Basis.from_scale(Vector3(1, 1, float(T.W) / 30.0))
			trk_mm.set_instance_transform(trk_i, Transform3D(b, Vector3(p.x, terra.height(p.x, p.y) + 0.3, p.y)))
			trk_i = (trk_i + 1) % TRK
		if absf(v_f) > 35.0 and randf() < 0.5 and tk.pos.distance_to(watch.pos) < 900.0:
			var back := tk.pos - fwd * float(T.L) * 0.5
			fx.track_dust(Vector3(back.x, tk.ground + 2.0, back.y))
	# выхлоп при резком разгоне
	if thr > 0.6 and v_f < vmax * 0.5 and randf() < dt * 6.0 and tk.pos.distance_to(watch.pos) < 700.0:
		var ex := tk.pos - fwd * float(T.L) * 0.45
		fx.exhaust(Vector3(ex.x, tk.ground + tk.hh + 1.0, ex.y), fwd)


## Подвеска: корпус ложится по рельефу и раскачивается от разгона, поворота и выстрела.
func _suspend(tk: TankScript, dt: float) -> void:
	var T := tk.T
	var lx: float = float(T.L) * 0.42
	var lz: float = float(T.W) * 0.42
	var f := Vector2.from_angle(tk.hull)
	var r := Vector2(-f.y, f.x)
	var hf := terra.height(tk.pos.x + f.x * lx, tk.pos.y + f.y * lx)
	var hb := terra.height(tk.pos.x - f.x * lx, tk.pos.y - f.y * lx)
	var hr := terra.height(tk.pos.x + r.x * lz, tk.pos.y + r.y * lz)
	var hl := terra.height(tk.pos.x - r.x * lz, tk.pos.y - r.y * lz)
	tk.ground = maxf((hf + hb + hr + hl) * 0.25, terra.height(tk.pos.x, tk.pos.y) - 1.0)
	var tp := atan2(hf - hb, 2.0 * lx) + clampf(tk.accel * 0.0006, -0.035, 0.035)
	var tr := -atan2(hr - hl, 2.0 * lz) - clampf(tk.yaw_rate * tk.sp * 0.0004, -0.04, 0.04)
	if dt >= 1.0:
		tk.pitch = tp
		tk.roll = tr
		return
	tk.pitch_v += ((tp - tk.pitch) * 70.0 - tk.pitch_v * 14.0) * dt
	tk.roll_v += ((tr - tk.roll) * 70.0 - tk.roll_v * 14.0) * dt
	tk.pitch += tk.pitch_v * dt
	tk.roll += tk.roll_v * dt


## Столкновения танков: упругий обмен импульсом по массам; на скорости — урон тараном.
func separate() -> void:
	var n := tanks.size()
	for i in n:
		var a: TankScript = tanks[i]
		for j in range(i + 1, n):
			var b: TankScript = tanks[j]
			if not a.alive and not b.alive:
				continue
			var d := b.pos - a.pos
			var mn := radius(a) + radius(b)
			var l := d.length()
			if l >= mn or l < 0.001:
				continue
			var nrm := d / l
			var ma: float = float(a.T.mass) * (1.0 if a.alive else 1.5)
			var mb: float = float(b.T.mass) * (1.0 if b.alive else 1.5)
			var push := mn - l
			a.pos -= nrm * push * mb / (ma + mb)
			b.pos += nrm * push * ma / (ma + mb)
			resolve(a)
			resolve(b)
			var closing := (a.vel - b.vel).dot(nrm)
			if closing <= 0.0:
				continue
			var j_imp := (1.0 + 0.15) * closing / (1.0 / ma + 1.0 / mb)
			if a.alive:
				a.vel -= nrm * j_imp / ma
			if b.alive:
				b.vel += nrm * j_imp / mb
			if closing > 22.0 and a.team != b.team and a.alive and b.alive:
				stat.ram += 1
				var e := closing * closing * 0.006
				_damage(b, roundf(e * ma / (ma + mb) * 2.0), a, "ТАРАН")
				_damage(a, roundf(e * mb / (ma + mb) * 0.8), b, "ТАРАН")
				sfx.play3d("hit_pen", (a.center() + b.center()) * 0.5, -3.0, 0.8)
				if a == watch or b == watch:
					shake = maxf(shake, 7.0)


# ---------- Стрельба и броня ----------

func _update_disp(tk: TankScript, dt: float) -> void:
	var base: float = tk.T.disp
	var floor_d := base + absf(tk.sp) / float(tk.T.speed) * 0.03 + absf(tk.yaw_rate) * 0.02 + tk.tur_rate * 0.018
	if tk.disp > floor_d:
		tk.disp = lerpf(tk.disp, floor_d, 1.0 - exp(-dt * 2.6 / float(tk.T.aim)))
	else:
		tk.disp = floor_d


## Наведение башни и орудия на точку с поправкой на падение снаряда.
func _aim_at(tk: TankScript, target: Vector3, dt: float) -> void:
	var before := tk.tur
	var want := (Vector2(target.x, target.z) - tk.pos).angle()
	tk.tur = turn_toward(tk.tur, want, float(tk.T.tspd) * dt)
	tk.tur_rate = absf(ang_diff(tk.tur, before)) / maxf(dt, 0.001)
	var local := tk.tur_node.global_transform.affine_inverse() * target
	var gp := tk.gun_pos0
	var dx := Vector2(local.x - gp.x, local.z).length()
	var e := atan2(local.y - gp.y, dx)
	var tf := dx / float(tk.T.shell_v)
	e += atan2(0.5 * D.GRAVITY * tf * tf, dx)
	var lim: Array = tk.T.elev
	tk.gun_target = clampf(e, lim[0], lim[1])
	tk.gun_pitch = move_toward(tk.gun_pitch, tk.gun_target, 0.35 * dt)


func shoot(tk: TankScript) -> void:
	var dir := tk.gun_dir()
	var u := dir.cross(Vector3.UP).normalized()
	var v := u.cross(dir).normalized()
	var spread := tan(tk.disp)
	var g := Vector2(randfn(0.0, 0.45), randfn(0.0, 0.45)).limit_length(1.0) * spread
	dir = (dir + u * g.x + v * g.y).normalized()
	var p := tk.muzzle()
	var mi := MeshInstance3D.new()
	mi.mesh = shell_mesh
	mi.material_override = shell_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(dir), p)
	shells.append({"pos": p, "vel": dir * float(tk.T.shell_v), "dmg": float(tk.T.dmg), "pen": float(tk.T.pen),
		"cal": float(tk.T.caliber), "owner": tk, "dist": 0.0, "rico": 0, "dead": false, "node": mi, "whiz": false})
	tk.rl = float(tk.T.reload) * (1.0 if tk.is_player else 1.15)
	tk.recoil = 1.0
	tk.disp += 0.035
	# отдача раскачивает корпус: сильнее у крупного калибра и лёгкой машины
	var kick: float = float(tk.T.caliber) / 85.0 * 30.0 / float(tk.T.mass)
	var rel := ang_diff(tk.tur, tk.hull)
	tk.pitch_v += cos(rel) * 0.5 * kick
	tk.roll_v -= sin(rel) * 0.5 * kick
	tk.vel -= Vector2.from_angle(tk.tur) * kick * 2.0
	if tk.team == 1:
		tk.lit = maxf(tk.lit, 2.0)
	fx.muzzle(p, dir, float(tk.T.caliber))
	fx.shot_dust(Vector3(tk.pos.x, tk.ground + 2.0, tk.pos.y))
	if tk.is_player:
		shake = maxf(shake, 3.0 + float(tk.T.caliber) / 40.0)
		shots += 1
		reload_cue = true
	sfx.gun(float(tk.T.caliber), p)


func _update_shells(dt: float) -> void:
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	for s in shells:
		var p0: Vector3 = s.pos
		var v: Vector3 = s.vel
		var nv := v + Vector3(0, -D.GRAVITY * dt, 0)
		var p1 := p0 + (v + nv) * 0.5 * dt
		v = nv
		# свист снаряда, пролетающего рядом с камерой
		if not s.whiz and not (s.owner as TankScript).is_player:
			var cl := Geometry3D.get_closest_point_to_segment(cam_pos, p0, p1)
			if cl.distance_to(cam_pos) < 45.0:
				s.whiz = true
				sfx.play3d("whiz", cl)
		var wh := ray(p0, p1)
		var th := ray_tanks(p0, p1, s.owner if s.rico == 0 else null)
		var tw := 2.0
		if not wh.is_empty():
			tw = p0.distance_to(wh.position) / maxf(p0.distance_to(p1), 0.001)
		if not th.is_empty() and th.t <= tw:
			_shell_hits_tank(s, th, v)
		elif not wh.is_empty():
			s.dead = true
			var hp: Vector3 = wh.position
			var on_ground: bool = wh.collider is StaticBody3D and (wh.collider as StaticBody3D).collision_layer == 1
			fx.impact(hp, on_ground)
			if on_ground:
				_scorch(hp, randf_range(7.0, 11.0))
			sfx.play3d("impact_ground" if on_ground else "impact_stone", hp)
		else:
			s.pos = p1
			s.vel = v
			s.dist += p0.distance_to(p1)
			if s.dist > D.RANGE:
				s.dead = true
				stat.miss += 1
		var node: Node3D = s.node
		if s.dead:
			node.queue_free()
		else:
			node.global_transform = Transform3D(Basis.looking_at(v.normalized()), s.pos)
	shells = shells.filter(func(x): return not x.dead)


func _shell_hits_tank(s: Dictionary, th: Dictionary, v: Vector3) -> void:
	var tk: TankScript = th.tank
	var by: TankScript = s.owner
	var hp: Vector3 = th.pos
	var dir := v.normalized()
	s.dead = true
	if not tk.alive or tk.team == by.team:
		fx.hit_sparks(hp)
		sfx.play3d("hit_nopen", hp, -4.0)
		return
	var arm := armor_at(tk, th)
	var thick: float = arm[0]
	var n: Vector3 = arm[1]
	var zone: String = arm[2]
	var cos_a := clampf(-dir.dot(n), 0.0, 1.0)
	var ang := maxf(0.0, acos(cos_a) - deg_to_rad(5.0))  # нормализация
	# бронепробиваемость падает с дистанцией
	var pen: float = float(s.pen) * (1.0 - 0.18 * clampf(float(s.dist) / D.RANGE, 0.0, 1.0)) * randf_range(0.8, 1.2)
	var overmatch: bool = float(s.cal) > thick * 3.0
	if ang > deg_to_rad(70.0) and not overmatch and s.rico == 0:
		# рикошет: снаряд отражается и летит дальше
		s.dead = false
		s.rico = 1
		s.pos = hp + n * 0.5
		s.vel = (v - 2.0 * v.dot(n) * n) * 0.7
		s.dist = D.RANGE - 250.0
		stat.rico += 1
		fx.hit_sparks(hp)
		_popup(tk, "РИКОШЕТ", Color("cfd3d8"), by)
		sfx.play3d("ricochet", hp)
		return
	var eff := thick / maxf(cos(ang), 0.12)
	# попадание в ходовую: гусеница принимает удар на себя и может слететь
	var local := (th.xf as Transform3D).affine_inverse() * hp
	var track_zone: bool = th.part == "hull" and local.y < tk.th * 1.05 and (zone == "side" or zone == "front" or zone == "rear")
	if track_zone and randf() < 0.7:
		if tk.track_broken <= 0.0:
			stat.track += 1
			_popup(tk, "ГУСЕНИЦА СБИТА", Color("ffd37a"), by)
			sfx.play3d("track_break", hp)
		tk.track_broken = TRACK_REPAIR
		tk.vel *= 0.3
	if pen < eff:
		stat.nopen += 1
		fx.hit_sparks(hp)
		if not track_zone:
			_popup(tk, "НЕ ПРОБИЛ", Color("cfd3d8"), by)
		sfx.play3d("hit_nopen", hp)
		if by.team == 0 and tk.team == 1:
			tk.lit = maxf(tk.lit, 2.0)
		return
	stat.pen += 1
	var dmg := roundf(float(s.dmg) * randf_range(0.75, 1.25) * (0.5 if track_zone else 1.0))
	fx.hit_sparks(hp)
	fx.pen_fire(hp)
	if by.is_player:
		hits += 1
	sfx.play3d("hit_pen", hp)
	# пожар от попадания в моторное отделение, редкая детонация боеукладки
	if zone == "rear" and th.part == "hull" and randf() < 0.3 and tk.fire <= 0.0:
		stat.fire += 1
		tk.fire = FIRE_TIME
		tk.set_meta("fire_by", by)
		if tk.fire_fx == null:
			tk.fire_fx = fx.deck_fire(tk, Vector3(-float(tk.T.L) * 0.35, tk.hh + 1.0, 0))
		tk.fire_fx.emitting = true
		_popup(tk, "ПОЖАР", Color("ff9a4a"), by)
	if (zone == "side" or zone == "rear") and not track_zone and randf() < 0.035:
		stat.ammo += 1
		_popup(tk, "БОЕУКЛАДКА", Color("ff6a4a"), by)
		dmg = tk.hp + 1.0
	_damage(tk, dmg, by, "")


func _popup(tk: TankScript, text: String, col: Color, by: TankScript) -> void:
	if by.is_player or tk == watch:
		texts.append({"pos": tk.top() + Vector3(0, 14, 0), "s": text, "col": col, "life": 1.4})


func _damage(tk: TankScript, amount: float, by: TankScript, tag: String) -> void:
	if not tk.alive or amount <= 0:
		return
	var real := minf(amount, ceilf(tk.hp))
	tk.hp -= amount
	if by.team == 0 and tk.team == 1:
		tk.lit = maxf(tk.lit, 2.0)
	if by.is_player:
		dmg_done += real
	if tag != "fire":
		for z in zones:
			if in_zone(tk, z) and z.prog[tk.team] > 0:
				z.prog[tk.team] = maxf(0.0, z.prog[tk.team] - 40.0)
		var col := Color("ff8a6a") if tk.is_player else Color.WHITE
		var label := ("%s -%d" % [tag, int(amount)]) if tag != "" else "-%d" % int(amount)
		texts.append({"pos": tk.top() + Vector3(0, 8, 0), "s": label, "col": col, "life": 1.2})
		if tk == watch:
			shake = maxf(shake, 8.0)
	if tk.hp <= 0:
		kill(tk, by)


func _scorch(p: Vector3, size: float) -> void:
	var b := _ground_basis(p.x, p.z) * Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(size, 1, size))
	scorch_mm.set_instance_transform(scorch_i, Transform3D(b, Vector3(p.x, terra.height(p.x, p.z) + 0.25, p.z)))
	scorch_i = (scorch_i + 1) % SCORCH


func kill(tk: TankScript, by: TankScript) -> void:
	tk.alive = false
	tk.hp = 0
	tk.sp = 0
	tk.vel = Vector2.ZERO
	tk.fire = 0.0
	tk.make_wreck(randf() < 0.45)
	var at := tk.center() + Vector3(0, tk.hh * 0.5, 0)
	fx.explosion(at)
	fx.wreck_fire(at)
	_scorch(Vector3(tk.pos.x, 0, tk.pos.y), float(tk.T.L) * 1.4)
	sfx.play3d("explosion", at)
	var lp: Array = loops.get(tk, [])
	for p in lp:
		if p:
			(p as AudioStreamPlayer3D).stop()
	var burn := sfx.attach_loop(tk, "fire", 14.0, -8.0)
	get_tree().create_timer(25.0, false).timeout.connect(burn.queue_free)
	if by.is_player:
		kills += 1
	if mode == "supremacy":
		score[by.team] += 25.0
	if tk == watch:
		shake = 20.0
	hud.add_feed([[by.callsign, hud.team_color(by.team)], ["  ▸  ", Color("cfd3c0")], [tk.callsign, hud.team_color(tk.team)]])
	if tk.is_player:
		sniper = false
		hud.show_dead(true)


func nearest_foe(tk: TankScript, max_d: float, cone: float, dir_a: float) -> TankScript:
	var best: TankScript = null
	var bd := max_d
	for o: TankScript in tanks:
		if not o.alive or o.team == tk.team or not o.vis[tk.team]:
			continue
		var d := o.pos.distance_to(tk.pos)
		if cone > 0 and absf(ang_diff((o.pos - tk.pos).angle(), dir_a)) > cone:
			continue
		if d < bd:
			bd = d
			best = o
	return best


func lead_point(from: TankScript, tg: TankScript) -> Vector3:
	var tf := from.pos.distance_to(tg.pos) / float(from.T.shell_v) * 0.9
	var p := tg.pos + tg.vel * tf
	return Vector3(p.x, tg.ground + tg.hh * 0.7, p.y)


# ---------- Засвет ----------

## Видимость по прямой: рельеф и дома закрывают обзор, кусты прячут неподвижный танк.
func _update_spotting() -> void:
	for e: TankScript in tanks:
		if not e.alive:
			continue
		for team in 2:
			if team == e.team:
				e.vis[team] = true
				continue
			var seen := e.lit > 0
			if not seen:
				var bush: bool = in_bush(e.pos) != null
				for o: TankScript in tanks:
					if not o.alive or o.team != team:
						continue
					var d := o.pos.distance_to(e.pos)
					if d > (110.0 if bush else float(o.T.spot)):
						continue
					var eye := o.top() + Vector3(0, 2, 0)
					if clear_line(eye, e.top()) or clear_line(eye, e.center()):
						seen = true
						break
			e.vis[team] = seen


# ---------- Игрок ----------

func _cam_dir() -> Vector3:
	return Vector3(cos(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), sin(cam_yaw) * cos(cam_pitch))


func _player(p: TankScript, dt: float) -> void:
	var s: Vector2 = hud.move
	if Input.is_key_pressed(KEY_W):
		s.y -= 1
	if Input.is_key_pressed(KEY_S):
		s.y += 1
	if Input.is_key_pressed(KEY_A):
		s.x -= 1
	if Input.is_key_pressed(KEY_D):
		s.x += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		cam_yaw -= 1.6 * dt
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_RIGHT):
		cam_yaw += 1.6 * dt
	if Input.is_key_pressed(KEY_UP):
		cam_pitch -= 0.6 * dt
	if Input.is_key_pressed(KEY_DOWN):
		cam_pitch += 0.6 * dt
	var zoom := 0.3 if sniper else 1.0
	var dv: Vector2 = hud.take_cam_delta()
	cam_yaw = wrapf(cam_yaw + dv.x * SENS_X * zoom, -PI, PI)
	cam_pitch = clampf(cam_pitch + dv.y * SENS_Y * zoom, -0.3, 0.45)
	if sniper:
		# в прицеле нельзя опустить взгляд ниже, чем опускается пушка (с учётом наклона корпуса)
		var rel := ang_diff(p.tur, p.hull)
		var tilt := p.pitch * cos(rel) - p.roll * sin(rel)
		var lim: Array = p.T.elev
		cam_pitch = clampf(cam_pitch, -float(lim[1]) - tilt, -float(lim[0]) - tilt - 0.005)
	var thr := -s.y if absf(s.y) > 0.2 else 0.0
	var steer := s.x if absf(s.x) > 0.15 else 0.0
	drive(p, dt, thr, steer)
	# точка прицеливания: луч из камеры
	var o := _cam_origin(p)
	var dir := _cam_dir()
	var far := o + dir * 1800.0
	var wh := ray(o, far)
	var th := ray_tanks(o, far, p)
	aim_point = far
	var tw := 2.0
	if not wh.is_empty():
		aim_point = wh.position
		tw = o.distance_to(wh.position) / 1800.0
	if not th.is_empty() and th.t < tw:
		aim_point = th.pos
	if hud.auto_aim and not hud.dragging:
		var f := nearest_foe(p, 900.0, 0.3, cam_yaw)
		if f and clear_line(p.top(), f.center()):
			var lp := lead_point(p, f)
			var want_yaw := (Vector2(lp.x, lp.z) - Vector2(o.x, o.z)).angle()
			cam_yaw = turn_toward(cam_yaw, want_yaw, 1.4 * dt)
			var want_pitch := -atan2(lp.y - o.y, Vector2(lp.x, lp.z).distance_to(Vector2(o.x, o.z)))
			cam_pitch = move_toward(cam_pitch, clampf(want_pitch, -0.3, 0.45), 0.6 * dt)
	_aim_at(p, aim_point, dt)
	var lim2: Array = p.T.elev
	gun_limited = absf(p.gun_target - float(lim2[0])) < 0.0005 or absf(p.gun_target - float(lim2[1])) < 0.0005
	_update_disp(p, dt)
	# куда на самом деле упадёт снаряд (по баллистике) и пробьёт ли
	var tr := trace(p.muzzle(), p.gun_dir() * float(p.T.shell_v), p)
	gun_point = tr.pos
	pen_hint = -1
	if tr.has("tank"):
		var tg: TankScript = tr.tank
		if tg.alive and tg.team != p.team:
			var arm := armor_at(tg, tr)
			var vdir: Vector3 = (tr.vel as Vector3).normalized()
			var cos_a := clampf(-vdir.dot(arm[1]), 0.0, 1.0)
			var ang := maxf(0.0, acos(cos_a) - deg_to_rad(5.0))
			var eff: float = float(arm[0]) / maxf(cos(ang), 0.12)
			var pen: float = float(p.T.pen) * (1.0 - 0.18 * clampf(p.pos.distance_to(tg.pos) / D.RANGE, 0.0, 1.0))
			if ang > deg_to_rad(70.0) and float(p.T.caliber) < float(arm[0]) * 3.0:
				pen_hint = 0
			elif pen > eff * 1.2:
				pen_hint = 2
			elif pen > eff * 0.8:
				pen_hint = 1
			else:
				pen_hint = 0
	if (hud.fire_req or hud.fire_held()) and p.rl <= 0:
		shoot(p)
	hud.fire_req = false
	# звук досылания снаряда перед готовностью
	if reload_cue and p.rl < 0.9 and p.rl > 0.0:
		reload_cue = false
		sfx.play2d("reload", -8.0)


func _cam_origin(w: TankScript) -> Vector3:
	if sniper and w.alive:
		# прицел наводчика — рядом с осью орудия, поэтому без параллакса
		return w.gun_node.global_transform * Vector3(0.2 * D.UPM, 0.45 * D.UPM, 0.0)
	var pivot := Vector3(w.pos.x, w.ground + w.height + 7.0, w.pos.y)
	var dir := _cam_dir()
	var want: float = 70.0 + float(w.T.L) * 0.55
	var o := pivot - dir * want
	var hit := ray(pivot, o)
	if not hit.is_empty():
		o = hit.position + (pivot - hit.position).normalized() * 2.5
	o.y = maxf(o.y, terra.height(o.x, o.z) + 3.0)
	return o


# ---------- ИИ ----------

func _roam(b: TankScript) -> void:
	b.b_zone = null
	var lo := 380.0 if b.team == 0 else D.WS - 1000.0
	b.b_goal = Vector2(randf_range(260.0, D.WS - 260.0), randf_range(lo, lo + 620.0))
	b.b_gt = randf_range(10.0, 18.0)


func _go_zone(b: TankScript, z) -> void:
	b.b_zone = z
	b.b_goal = z.pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, float(z.r) * 0.5)
	b.b_gt = 3.0


func _pick_goal(b: TankScript) -> void:
	var my := b.team
	var en := 1 - my
	if mode == "standard":
		var own = zones[0] if zones[0].side == my else zones[1]
		var foe = zones[1] if own == zones[0] else zones[0]
		if own.prog[en] > 0 and (b.role == "def" or b.pos.distance_to(own.pos) < 900):
			_go_zone(b, own)
			return
		if b.role == "def" and clock < 150:
			b.b_zone = null
			b.b_goal = own.pos + Vector2(randf_range(-400.0, 400.0), (-1.0 if my == 0 else 1.0) * randf_range(250.0, 550.0))
			b.b_gt = randf_range(6.0, 10.0)
			return
		if clock > 100 or alive_count(en) <= 2:
			_go_zone(b, foe)
		else:
			_roam(b)
		return
	if mode == "encounter":
		_go_zone(b, zones[0])
		return
	var best = null
	var bd := 1e9
	for z in zones:
		var d: float = b.pos.distance_to(z.pos)
		if z.side == my:
			d += -200.0 if z.n[en] > 0 else 1500.0
		if d < bd:
			bd = d
			best = z
	if best != null:
		_go_zone(b, best)
	else:
		_roam(b)


func _bot(b: TankScript, dt: float) -> void:
	var T := b.T
	var mv := Vector2.ZERO
	var tg := nearest_foe(b, 1e9, 0.0, 0.0)
	b.b_st -= dt
	if b.b_st <= 0:
		b.b_strafe *= -1.0
		b.b_st = randf_range(2.0, 4.5)
	b.b_los_t -= dt
	if tg:
		var d := b.pos.distance_to(tg.pos)
		var ang := (tg.pos - b.pos).angle()
		var pref: float = T.pref
		if b.b_los_t <= 0:
			b.b_los = clear_line(b.muzzle(), tg.center())
			b.b_los_t = 0.3
		var fwd := 1.0 if d > pref + 70.0 or not b.b_los else (-1.0 if d < pref - 100.0 else 0.0)
		var strafe := 0.6
		if b.b_los and b.rl < 1.2:
			strafe = 0.0  # перед выстрелом останавливается, чтобы свестись
		if b.b_zone != null and in_zone(b, b.b_zone) and b.b_zone.side != b.team:
			fwd = 0.0
		mv = Vector2.from_angle(ang) * fwd + Vector2.from_angle(ang + PI / 2) * b.b_strafe * strafe
		var lp := lead_point(b, tg)
		_aim_at(b, lp, dt)
		var aligned := absf(ang_diff((Vector2(lp.x, lp.z) - b.pos).angle(), b.tur)) < 0.03 and absf(b.gun_pitch - b.gun_target) < 0.015
		if b.rl <= 0 and d < D.RANGE * 0.85 and aligned and b.b_los and b.disp < float(T.disp) * 3.0:
			shoot(b)
	else:
		b.b_gt -= dt
		if b.b_gt <= 0 or (b.b_zone == null and b.pos.distance_to(b.b_goal) < 120.0):
			_pick_goal(b)
		var dv := b.b_goal - b.pos
		var l := dv.length()
		if not (b.b_zone != null and l < 30.0):
			mv = dv / maxf(l, 0.001)
		var look := b.pos + (mv if mv.length() > 0.1 else Vector2.from_angle(b.tur)) * 200.0
		_aim_at(b, Vector3(look.x, b.ground + b.hh, look.y), dt)
	var m := mv.length()
	if m > 0.1:
		var a := mv.angle()
		var r := radius(b)
		if b.b_av <= 0 and blocked_at(b.pos + Vector2.from_angle(a) * 60.0, r):
			var f1 := not blocked_at(b.pos + Vector2.from_angle(a + 0.9) * 60.0, r)
			var f2 := not blocked_at(b.pos + Vector2.from_angle(a - 0.9) * 60.0, r)
			if f1 and not f2:
				b.b_av_dir = 1.0
			elif f2 and not f1:
				b.b_av_dir = -1.0
			else:
				b.b_av_dir = 1.0 if randf() < 0.5 else -1.0
			b.b_av = 1.2
		if b.b_av > 0:
			b.b_av -= dt
			a += b.b_av_dir * 1.1
			mv = Vector2.from_angle(a)
	b.b_pt -= dt
	if b.b_pt <= 0:
		if m > 0.3 and b.pos.distance_to(b.b_last) < 6.0 and b.track_broken <= 0.0:
			b.b_av = 1.8
			b.b_av_dir *= -1.0
		b.b_last = b.pos
		b.b_pt = 1.5
	_drive_vec(b, dt, mv)
	_update_disp(b, dt)


func _drive_vec(tk: TankScript, dt: float, mv: Vector2) -> void:
	var m := minf(1.0, mv.length())
	if m < 0.12:
		drive(tk, dt, 0.0, 0.0)
		return
	var want := mv.angle()
	var d := ang_diff(want, tk.hull)
	var dir := 1.0
	if absf(d) > PI * 0.6:
		d = ang_diff(want + PI, tk.hull)
		dir = -1.0
	var steer := clampf(d / 0.35, -1.0, 1.0)
	drive(tk, dt, dir * m * maxf(0.1, cos(d)), steer * dir)


# ---------- Режимы ----------

static func in_zone(tk: TankScript, z) -> bool:
	return tk.pos.distance_squared_to(z.pos) < float(z.r) * float(z.r)


func _zones_update(dt: float) -> void:
	for z in zones:
		z.n = [0, 0]
		for tk: TankScript in tanks:
			if tk.alive and in_zone(tk, z):
				z.n[tk.team] += 1
		for side in 2:
			var other := 1 - side
			if z.side != side and z.n[side] > 0 and z.n[other] == 0:
				z.prog[side] = minf(100.0, z.prog[side] + dt * D.CAP_RATE * mini(3, z.n[side]))
			elif z.n[side] == 0:
				z.prog[side] = maxf(0.0, z.prog[side] - dt * 3.0)
			if z.prog[side] >= 100.0:
				if mode == "supremacy":
					z.side = side
					z.prog = [0.0, 0.0]
					hud.add_feed([["Точка %s захвачена" % z.label, hud.team_color(side)]])
					sfx.play2d("capture", -6.0)
				elif not over:
					if mode == "encounter":
						finish("win" if side == 0 else "lose", "Вы захватили базу" if side == 0 else "Противник захватил базу")
					else:
						finish("win" if side == 0 else "lose", "База противника захвачена" if side == 0 else "Ваша база захвачена")
	if mode == "supremacy":
		for z in zones:
			if z.side >= 0:
				score[z.side] += dt * 2.0
		if not over:
			if score[0] >= D.SUP_GOAL:
				finish("win", "Набрано 600 очков")
			elif score[1] >= D.SUP_GOAL:
				finish("lose", "Противник набрал 600 очков")


func finish(res: String, why: String) -> void:
	over = true
	result = res
	reason = why
	over_t = 0.0
	speed = 1


func alive_count(team: int) -> int:
	var n := 0
	for tk: TankScript in tanks:
		if tk.alive and tk.team == team:
			n += 1
	return n


# ---------- Шаг симуляции ----------

func _update(dt: float) -> void:
	clock += dt
	spot_t -= dt
	if spot_t <= 0:
		_update_spotting()
		spot_t = 0.25
	for tk: TankScript in tanks:
		if not tk.alive:
			tk.update_pop(dt)
			tk.sync_node()
			continue
		tk.rl = maxf(0.0, tk.rl - dt)
		tk.lit = maxf(0.0, tk.lit - dt)
		tk.recoil = maxf(0.0, tk.recoil - dt * 3.0)
		tk.track_broken = maxf(0.0, tk.track_broken - dt)
		if tk.fire > 0.0:
			tk.fire -= dt
			var by: TankScript = tk.get_meta("fire_by", tk)
			_damage(tk, float(tk.max_hp) * 0.018 * dt, by, "fire")  # 1,8% прочности в секунду
			if tk.fire <= 0.0 and tk.fire_fx:
				tk.fire_fx.emitting = false
			if not tk.alive:
				continue
		if over:
			drive(tk, dt, 0.0, 0.0)
		elif tk.is_player:
			_player(tk, dt)
		else:
			_bot(tk, dt)
		tk.smoke_on(tk.hp < tk.max_hp * 0.35)
	separate()
	for tk: TankScript in tanks:
		_suspend(tk, dt)
		tk.sync_node()
	_update_shells(dt)
	for pr in falling:
		pr.fall = minf(1.0, pr.fall + dt * 1.4)
		MapGen.place_prop(pr)
	falling = falling.filter(func(x): return x.fall < 1.0)
	for tx in texts:
		tx.life -= dt
	texts = texts.filter(func(x): return x.life > 0)
	_zones_update(dt)
	if not player.alive and not over and (watch == player or not watch.alive):
		var best: TankScript = null
		var bd := 1e9
		for tk: TankScript in tanks:
			if tk.alive and tk.team == 0 and tk.pos.distance_to(player.pos) < bd:
				bd = tk.pos.distance_to(player.pos)
				best = tk
		if best:
			watch = best
	if not player.alive and watch != player:
		cam_yaw = turn_toward(cam_yaw, watch.tur, 2.0 * dt)
		cam_pitch = move_toward(cam_pitch, 0.07, dt)
	shake = maxf(0.0, shake - dt * 30.0)
	if not over:
		var a := alive_count(0)
		var e := alive_count(1)
		if e == 0:
			finish("win", "Все противники уничтожены")
		elif a == 0:
			finish("lose", "Ваша команда уничтожена")
		elif clock >= D.TIME_LIMIT:
			if mode == "supremacy":
				var res := "draw"
				if score[0] > score[1]:
					res = "win"
				elif score[0] < score[1]:
					res = "lose"
				finish(res, "Время вышло")
			else:
				finish("draw", "Время вышло")
	else:
		over_t += dt


func _physics_process(delta: float) -> void:
	if paused:
		return
	var dt := minf(delta, 0.05)
	for i in speed:
		_update(dt)
	if over and over_t > 1.8 and not result_shown:
		_show_result()


func _process(delta: float) -> void:
	_sync(minf(delta, 0.05))


## Прогон симуляции без отрисовки (для проверок).
func simulate(steps: int) -> void:
	for i in steps:
		if over:
			return
		_update(1.0 / 30.0)


func set_paused(v: bool) -> void:
	if over:
		return
	paused = v
	hud.show_pause(v)
	get_tree().paused = false
	for k in loops:
		for p in loops[k]:
			if p:
				(p as AudioStreamPlayer3D).stream_paused = v


func toggle_speed() -> void:
	speed = 1 if speed > 1 else 4


func toggle_sniper() -> void:
	if player.alive:
		sniper = not sniper


func _show_result() -> void:
	result_shown = true
	var silver := roundi(dmg_done * 0.8 + kills * 150 + (500 if result == "win" else (150 if result == "draw" else 0)))
	var stats := {
		"result": result, "reason": reason, "kills": kills, "dmg": roundi(dmg_done),
		"acc": roundi(100.0 * hits / shots) if shots > 0 else 0, "time": clock, "silver": silver,
		"mode": D.MODES[mode].name, "map": D.MAPS[map_key].name,
	}
	ended.emit(stats)
	hud.show_result(stats)


# ---------- Отображение ----------

func _sync(dt: float) -> void:
	var w := watch
	var o := _cam_origin(w)
	var off := Vector3.ZERO
	if shake > 0 and not sniper:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.35
	cam.global_transform = Transform3D(Basis.looking_at(_cam_dir()), o + off)
	var vs := get_viewport().get_visible_rect().size
	var fov := 74.0 if vs.x < vs.y else 56.0
	cam.fov = fov / 3.5 if sniper else fov
	for tk: TankScript in tanks:
		tk.visible = (not tk.alive or tk.team == 0 or tk.vis[0]) and not (sniper and tk == w)
		_sync_sound(tk)
	bush_mat.set_shader_parameter("fade_a", w.center())
	bush_mat.set_shader_parameter("fade_b", cam.global_position)
	for z in zones:
		var c := Color.WHITE
		if z.side == 0:
			c = Color(D.ALLY)
		elif z.side == 1:
			c = Color(D.FOE)
		var ring := c
		if z.prog[0] > 0 and z.side != 0:
			ring = Color("9ae07a")
		elif z.prog[1] > 0 and z.side != 1:
			ring = Color("ff8a6a")
		z.ring_mat.albedo_color = ring
		var dc := c
		dc.a = 0.1
		z.disc_mat.albedo_color = dc
		z.flag_mat.albedo_color = c
		z.flag.rotation.y = sin(clock * 2.0 + z.pos.x) * 0.25


## Обороты двигателя и лязг гусениц следуют за газом и скоростью.
func _sync_sound(tk: TankScript) -> void:
	var lp: Array = loops.get(tk, [])
	if lp.is_empty() or not tk.alive:
		return
	var v := clampf(absf(tk.sp) / float(tk.T.speed), 0.0, 1.0)
	var eng_load := clampf(absf(tk.throttle), 0.0, 1.0)
	var eng: AudioStreamPlayer3D = lp[0]
	var rpm := 0.75 + v * 0.75 + eng_load * 0.35 + absf(tk.yaw_rate) * 0.15
	eng.pitch_scale = lerpf(eng.pitch_scale, rpm, 0.1)
	var base := -2.0 if tk.is_player else -6.0
	eng.volume_db = base + eng_load * 4.0 - (10.0 if speed > 1 else 0.0)
	var trk: AudioStreamPlayer3D = lp[1]
	var tv := clampf(maxf(absf(tk.sp), absf(tk.yaw_rate) * float(tk.T.W) * 0.5) / float(tk.T.speed), 0.0, 1.0)
	trk.pitch_scale = 0.6 + tv * 0.9
	trk.volume_db = linear_to_db(maxf(tv, 0.001)) - 2.0 - (10.0 if speed > 1 else 0.0)
	if lp[2] != null:
		var turp: AudioStreamPlayer3D = lp[2]
		var tr := clampf(tk.tur_rate / maxf(float(tk.T.tspd), 0.01), 0.0, 1.0)
		turp.volume_db = linear_to_db(maxf(tr, 0.001)) - 6.0
		turp.pitch_scale = 0.8 + tr * 0.4
