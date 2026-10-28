extends Node3D
## Бой: карта, танки, снаряды, зоны захвата, ИИ ботов и камера за танком.
## Вся логика идёт на плоскости карты (Vector2); 3D-узлы только отображают её.

signal ended(stats: Dictionary)
signal leave(again: bool)

const D = preload("res://scripts/data.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const TankScript = preload("res://scripts/tank.gd")
const HudScript = preload("res://scripts/hud.gd")
const FxScript = preload("res://scripts/fx.gd")
const SfxScript = preload("res://scripts/sfx.gd")

const TRK := 1200  # следов гусениц одновременно
const SENS := 0.0045  # поворот камеры, рад на точку свайпа

var mode := "standard"
var map_key := "meadow"
var hq := true
var player_type := "medium"

var obst: Array = []
var bushes: Array = []
var zones: Array = []
var tanks: Array = []
var shells: Array = []
var texts: Array = []

var player: TankScript
var watch: TankScript
var cam: Camera3D
var cam_yaw := -PI / 2
var cam_d := 80.0
var shake := 0.0
var clock := 0.0
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

var hud: HudScript
var fx: FxScript
var sfx: SfxScript
var trk_mm: MultiMesh
var trk_i := 0
var shell_mesh: BoxMesh
var shell_mat: StandardMaterial3D


func setup(cfg: Dictionary) -> void:
	mode = cfg.mode
	map_key = cfg.map
	hq = cfg.hq
	player_type = cfg.tank


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	zones = MapGen.make_zones(mode)
	var data := MapGen.generate(map_key, zones, rng)
	obst = data.obst
	bushes = data.bushes
	MapGen.build(self, data, map_key, zones, hq)
	_make_env()
	fx = FxScript.new()
	add_child(fx)
	fx.set_dust(Color(D.MAPS[map_key].dust))
	sfx = SfxScript.new()
	add_child(sfx)
	_make_tracks()
	shell_mesh = BoxMesh.new()
	shell_mesh.size = Vector3(12, 1.6, 1.6)
	shell_mat = MapGen.mat(Color(1, 0.9, 0.63), true)
	_spawn()
	cam = Camera3D.new()
	cam.near = 1.0
	cam.far = 2600.0
	add_child(cam)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	layer.add_child(hud)
	hud.add_feed([["%s · %s" % [D.MODES[mode].name, D.MAPS[map_key].name], Color(D.AMBER)]])
	_sync(0.0)


func _make_env() -> void:
	var M: Dictionary = D.MAPS[map_key]
	var sky := Color(M.sky)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sky.lerp(Color.WHITE, 0.4)
	env.ambient_light_energy = 0.55 if map_key == "winter" else 0.45
	# линейный туман по глубине: вблизи цвета чистые, к горизонту тают в небе
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = sky
	env.fog_depth_begin = 380.0 if map_key == "winter" else 450.0
	env.fog_depth_end = 1300.0 if map_key == "winter" else 1500.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color("fff0d0") if map_key == "desert" else Color.WHITE
	sun.light_energy = 0.7 if map_key == "winter" else 0.8
	sun.shadow_enabled = hq
	sun.directional_shadow_max_distance = 450.0
	add_child(sun)


func _make_tracks() -> void:
	trk_mm = MultiMesh.new()
	trk_mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(3.2, 2.6)
	trk_mm.mesh = q
	trk_mm.instance_count = TRK
	for i in TRK:
		trk_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -50, 0)))
	var m := MapGen.mat(Color(0.48, 0.52, 0.56, 0.4) if map_key == "winter" else Color(0.2, 0.17, 0.11, 0.35), true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = trk_mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _spawn() -> void:
	var ws := D.WS
	var keys: Array = D.TYPES.keys()
	var names: Array = D.NAMES.duplicate()
	names.shuffle()
	player = _add_tank(player_type, 0, Vector2(ws / 2, ws - 300), "Вы", true)
	watch = player
	for i in 4:
		var side := -1.0 if i < 2 else 1.0
		var b := _add_tank(keys[randi() % 3], 0, Vector2(ws / 2 + side * (150.0 + (i % 2) * 160.0), ws - 310.0 - (i % 2) * 30.0), names.pop_back(), false)
		if i == 0:
			b.role = "def"
	for i in 5:
		var b := _add_tank(keys[randi() % 3], 1, Vector2(ws / 2 + (i - 2) * 160.0, 300.0 + (i % 2) * 30.0), names.pop_back(), false)
		if i == 0:
			b.role = "def"


func _add_tank(key: String, team: int, p: Vector2, nm: String, is_player: bool) -> TankScript:
	var tk: TankScript = TankScript.new()
	add_child(tk)
	tk.setup(key, team, p, nm, is_player, hq)
	tk.smoke = fx.damage_smoke(tk, tk.turret_y())
	tanks.append(tk)
	return tk


# ---------- Геометрия ----------

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


func los(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / 22.0)
	for i in range(1, n):
		if in_rect(a.lerp(b, float(i) / n)) != null:
			return false
	return true


static func in_zone(tk: TankScript, z) -> bool:
	return tk.pos.distance_squared_to(z.pos) < float(z.r) * float(z.r)


func vol_at(p: Vector2) -> float:
	if watch == null:
		return 0.5
	var v := clampf(1.0 - p.distance_to(watch.pos) / 1200.0, 0.06, 1.0)
	return v * (0.3 if speed > 1 else 1.0)


# ---------- Движение ----------

func resolve(tk: TankScript) -> void:
	var r: float = tk.T.r
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


## Управление как в Blitz: thr — газ вперёд/назад, steer — поворот корпуса.
func drive(tk: TankScript, dt: float, thr: float, steer: float) -> void:
	var T := tk.T
	thr = clampf(thr, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	var rev := thr < -0.05
	tk.hull += steer * float(T.turn) * dt * (-1.0 if rev else 1.0)
	var tg := thr * float(T.speed) * (0.6 if thr < 0 else 1.0) * (1.0 - absf(steer) * 0.25)
	tk.sp += (tg - tk.sp) * minf(1.0, dt * (5.0 if absf(tg) < 1.0 else 2.6))
	tk.vel = Vector2.from_angle(tk.hull) * tk.sp
	var old := tk.pos
	tk.pos += tk.vel * dt
	resolve(tk)
	tk.dist_travel += tk.pos.distance_to(old)
	if tk.dist_travel - tk.mark > 7.0 and absf(tk.sp) > 15.0:
		tk.mark = tk.dist_travel
		var wd: float = T.W
		var side := Vector2.from_angle(tk.hull).orthogonal() * (wd * 0.37)
		var basis := Basis(Vector3.UP, -tk.hull) * Basis.from_scale(Vector3(1, 1, wd / 30.0))
		for s: float in [1.0, -1.0]:
			var p := tk.pos + side * s
			trk_mm.set_instance_transform(trk_i, Transform3D(basis, Vector3(p.x, 0.35, p.y)))
			trk_i = (trk_i + 1) % TRK


## Для ботов: ехать в направлении вектора, при необходимости задним ходом.
func drive_vec(tk: TankScript, dt: float, mv: Vector2) -> void:
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


func separate() -> void:
	var n := tanks.size()
	for i in n:
		var a: TankScript = tanks[i]
		for j in range(i + 1, n):
			var b: TankScript = tanks[j]
			if not a.alive and not b.alive:
				continue
			var d := b.pos - a.pos
			var mn: float = float(a.T.r) + float(b.T.r)
			var l := d.length()
			if l < mn and l > 0.001:
				var k := (mn - l) / l
				var wi := 0.0
				if a.alive:
					wi = 0.5 if b.alive else 1.0
				a.pos -= d * k * wi
				b.pos += d * k * (1.0 - wi)
				resolve(a)
				resolve(b)


# ---------- Стрельба ----------

func seen_by(e: TankScript, team: int) -> bool:
	if e.lit > 0:
		return true
	var bush: bool = in_bush(e.pos) != null
	for o: TankScript in tanks:
		if not o.alive or o.team != team:
			continue
		var lim: float = 110.0 if bush else float(o.T.spot)
		if o.pos.distance_to(e.pos) < lim:
			return true
	return false


func shoot(tk: TankScript, err: float) -> void:
	var a := tk.tur + err
	var dir := Vector2.from_angle(a)
	var sp: Vector2 = tk.pos + dir * float(tk.T.barrel)
	var h := tk.barrel_y()
	var mi := MeshInstance3D.new()
	mi.mesh = shell_mesh
	mi.material_override = shell_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = -a
	mi.position = Vector3(sp.x, h, sp.y)
	add_child(mi)
	shells.append({"pos": sp, "vel": dir * D.SHELL, "h": h, "dmg": float(tk.T.dmg), "team": tk.team, "owner": tk, "dist": 0.0, "dead": false, "node": mi})
	tk.rl = float(tk.T.reload) * (1.0 if tk.is_player else 1.2)
	tk.recoil = 1.0
	if tk.team == 1:
		tk.lit = maxf(tk.lit, 1.8)
	fx.muzzle(Vector3(sp.x, h, sp.y), a)
	fx.shot_dust(Vector3(tk.pos.x, 2, tk.pos.y))
	if tk.is_player:
		shake = maxf(shake, 3.0)
		shots += 1
	sfx.play("shot", vol_at(tk.pos))


func _update_shells(dt: float) -> void:
	var steps := maxi(1, ceili(D.SHELL * dt / 8.0))
	var sd := dt / steps
	for s in shells:
		var pos: Vector2 = s.pos
		var vel: Vector2 = s.vel
		var dist: float = s.dist
		var h: float = s.h
		var dead := false
		for k in steps:
			pos += vel * sd
			dist += D.SHELL * sd
			if dist > D.RANGE or pos.x < 0 or pos.y < 0 or pos.x > D.WS or pos.y > D.WS:
				dead = true
				break
			if in_rect(pos) != null:
				dead = true
				fx.impact(Vector3(pos.x, h, pos.y))
				sfx.play("hit", vol_at(pos) * 0.7)
				break
			var target: TankScript = null
			for tk: TankScript in tanks:
				var rr: float = float(tk.T.r) + 3.0
				if tk.alive and tk.team != s.team and tk.pos.distance_squared_to(pos) < rr * rr:
					target = tk
					break
			if target:
				s.pos = pos
				hit(target, s)
				dead = true
				break
		s.pos = pos
		s.dist = dist
		s.dead = dead
		var node: Node3D = s.node
		if dead:
			node.queue_free()
		else:
			node.position = Vector3(pos.x, h, pos.y)
	shells = shells.filter(func(x): return not x.dead)


func hit(tk: TankScript, s: Dictionary) -> void:
	var vel: Vector2 = s.vel
	var by: TankScript = s.owner
	var from := atan2(-vel.y, -vel.x)
	var rel := absf(ang_diff(from, tk.hull))
	var armor := 0.78 if rel < PI / 4 else (1.35 if rel > PI * 0.75 else 1.0)
	var raw := roundf(float(s.dmg) * randf_range(0.85, 1.15) * armor)
	var real := minf(raw, ceilf(tk.hp))
	tk.hp -= raw
	if by.team == 0 and tk.team == 1:
		tk.lit = maxf(tk.lit, 2.0)
	if by.is_player:
		dmg_done += real
		hits += 1
	for z in zones:
		if in_zone(tk, z) and z.prog[tk.team] > 0:
			z.prog[tk.team] = maxf(0.0, z.prog[tk.team] - 40.0)
	var h: float = s.h
	var hp: Vector2 = s.pos
	var col := Color("ff8a6a") if tk.is_player else (Color("ffd37a") if armor > 1 else Color.WHITE)
	texts.append({"pos": tk.pos, "h": tk.barrel_y() + 18.0, "s": "-%d" % int(raw), "col": col, "life": 1.1})
	if by.is_player and armor > 1:
		texts.append({"pos": tk.pos, "h": tk.barrel_y() + 32.0, "s": "В КОРМУ", "col": Color("ffd37a"), "life": 1.1})
	fx.hit_sparks(Vector3(hp.x, h, hp.y))
	if tk == watch:
		shake = maxf(shake, 8.0)
	sfx.play("hit", vol_at(tk.pos))
	if tk.hp <= 0:
		kill(tk, by)


func kill(tk: TankScript, by: TankScript) -> void:
	tk.alive = false
	tk.hp = 0
	tk.sp = 0
	tk.make_wreck(randf() < 0.45)
	var at := Vector3(tk.pos.x, tk.turret_y(), tk.pos.y)
	fx.explosion(at)
	fx.wreck_fire(at)
	sfx.play("boom", vol_at(tk.pos))
	if by.is_player:
		kills += 1
	if mode == "supremacy":
		score[by.team] += 25.0
	if tk == watch:
		shake = 20.0
	hud.add_feed([[by.callsign, hud.team_color(by.team)], ["  ▸  ", Color("cfd3c0")], [tk.callsign, hud.team_color(tk.team)]])
	if tk.is_player:
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


func lead(from: TankScript, tg: TankScript) -> float:
	var tl := from.pos.distance_to(tg.pos) / D.SHELL * 0.8
	return (tg.pos + tg.vel * tl - from.pos).angle()


# ---------- Игрок ----------

func player_think(p: TankScript, dt: float) -> void:
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
		cam_yaw -= 2.2 * dt
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_RIGHT):
		cam_yaw += 2.2 * dt
	cam_yaw = wrapf(cam_yaw + hud.take_cam_dx() * SENS, -PI, PI)
	var thr := -s.y if absf(s.y) > 0.2 else 0.0
	var steer := s.x if absf(s.x) > 0.15 else 0.0
	drive(p, dt, thr, steer)
	if hud.auto_aim and not hud.dragging:
		var f := nearest_foe(p, 760.0, 0.55, cam_yaw)
		if f and los(p.pos, f.pos):
			cam_yaw = turn_toward(cam_yaw, lead(p, f), 2.6 * dt)
	p.tur = turn_toward(p.tur, cam_yaw, float(p.T.tspd) * dt)
	if (hud.fire_req or hud.fire_held()) and p.rl <= 0:
		shoot(p, 0.0)
	hud.fire_req = false


# ---------- ИИ ----------

func _roam(b: TankScript) -> void:
	b.b_zone = null
	var lo := 380.0 if b.team == 0 else D.WS - 1000.0
	b.b_goal = Vector2(randf_range(260.0, D.WS - 260.0), randf_range(lo, lo + 620.0))
	b.b_gt = randf_range(8.0, 14.0)


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
		var foes_left := 0
		for tk: TankScript in tanks:
			if tk.alive and tk.team == en:
				foes_left += 1
		if clock > 80 or foes_left <= 2:
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


func bot_think(b: TankScript, dt: float) -> void:
	var T := b.T
	var mv := Vector2.ZERO
	var aim := 0.0
	var has_aim := false
	var tg := nearest_foe(b, 1e9, 0.0, 0.0)
	b.b_st -= dt
	if b.b_st <= 0:
		b.b_strafe *= -1.0
		b.b_st = randf_range(1.5, 3.5)
	if tg:
		var d := b.pos.distance_to(tg.pos)
		var ang := (tg.pos - b.pos).angle()
		var pref: float = T.pref
		var fwd := 1.0 if d > pref + 70.0 else (-1.0 if d < pref - 100.0 else 0.0)
		if b.b_zone != null and in_zone(b, b.b_zone) and b.b_zone.side != b.team:
			fwd = 0.0  # не бросать захват
		mv = Vector2.from_angle(ang) * fwd + Vector2.from_angle(ang + PI / 2) * b.b_strafe * 0.7
		aim = lead(b, tg)
		has_aim = true
		if b.rl <= 0 and d < 720.0 and absf(ang_diff(aim, b.tur)) < 0.07 and los(b.pos, tg.pos):
			shoot(b, (randf() - 0.5) * 0.08 * (1.0 + d / 500.0))
	else:
		b.b_gt -= dt
		if b.b_gt <= 0 or (b.b_zone == null and b.pos.distance_to(b.b_goal) < 120.0):
			_pick_goal(b)
		var dv := b.b_goal - b.pos
		var l := dv.length()
		if not (b.b_zone != null and l < 30.0):
			mv = dv / maxf(l, 0.001)
	var m := mv.length()
	if m > 0.1:
		var a := mv.angle()
		var r: float = T.r
		if b.b_av <= 0 and blocked_at(b.pos + Vector2.from_angle(a) * 72.0, r):
			var f1 := not blocked_at(b.pos + Vector2.from_angle(a + 0.9) * 72.0, r)
			var f2 := not blocked_at(b.pos + Vector2.from_angle(a - 0.9) * 72.0, r)
			if f1 and not f2:
				b.b_av_dir = 1.0
			elif f2 and not f1:
				b.b_av_dir = -1.0
			else:
				b.b_av_dir = 1.0 if randf() < 0.5 else -1.0
			b.b_av = 0.8
		if b.b_av > 0:
			b.b_av -= dt
			a += b.b_av_dir * 1.1
			mv = Vector2.from_angle(a)
	b.b_pt -= dt
	if b.b_pt <= 0:
		if m > 0.3 and b.pos.distance_to(b.b_last) < 8.0:
			b.b_av = 1.3
			b.b_av_dir *= -1.0
		b.b_last = b.pos
		b.b_pt = 1.0
	drive_vec(b, dt, mv)
	var ta := b.tur
	if has_aim:
		ta = aim
	elif m > 0.1:
		ta = mv.angle()
	b.tur = turn_toward(b.tur, ta, float(T.tspd) * dt * 0.85)


# ---------- Режимы ----------

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
					sfx.play("cap", 0.8)
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
	for tk: TankScript in tanks:
		if tk.alive:
			tk.vis[0] = tk.team == 0 or seen_by(tk, 0)
			tk.vis[1] = tk.team == 1 or seen_by(tk, 1)
	for tk: TankScript in tanks:
		if not tk.alive:
			tk.update_pop(dt)
			continue
		tk.rl = maxf(0.0, tk.rl - dt)
		tk.lit = maxf(0.0, tk.lit - dt)
		tk.recoil = maxf(0.0, tk.recoil - dt * 3.0)
		if over:
			drive(tk, dt, 0.0, 0.0)
			continue
		if tk.is_player:
			player_think(tk, dt)
		else:
			bot_think(tk, dt)
		tk.smoke_on(tk.hp < tk.max_hp * 0.35)
	separate()
	_update_shells(dt)
	for tx in texts:
		tx.h += 24.0 * dt
		tx.life -= dt
	texts = texts.filter(func(x): return x.life > 0)
	_zones_update(dt)
	# после гибели наблюдаем за ближайшим союзником
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


func _process(delta: float) -> void:
	if paused:
		return
	var dt := minf(delta, 0.05)
	for i in speed:
		_update(dt)
	if over and over_t > 1.8 and not result_shown:
		_show_result()
	_sync(dt)


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


func toggle_speed() -> void:
	speed = 1 if speed > 1 else 4


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
	var T := w.T
	var dir := Vector2.from_angle(cam_yaw)
	# камера сзади, подъезжает ближе, если позади стена
	var want: float = 74.0 + float(T.L) * 0.5
	var d := 8.0
	while d < want and in_rect(w.pos - dir * d) == null:
		d += 5.0
	var target_d := maxf(14.0, d - 6.0)
	cam_d += (target_d - cam_d) * minf(1.0, dt * (14.0 if target_d < cam_d else 3.0)) if dt > 0 else target_d - cam_d
	var hgt: float = 30.0 + float(T.W) * 0.3 + (90.0 - cam_d) * 0.06
	var off := Vector3.ZERO
	if shake > 0:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.4
	cam.position = Vector3(w.pos.x - dir.x * cam_d, hgt, w.pos.y - dir.y * cam_d) + off
	cam.look_at(Vector3(w.pos.x + dir.x * 90.0, w.barrel_y() + 12.0, w.pos.y + dir.y * 90.0), Vector3.UP)
	var vs := get_viewport().get_visible_rect().size
	cam.fov = 78.0 if vs.x < vs.y else 58.0
	for tk: TankScript in tanks:
		tk.sync_node()
		tk.visible = not tk.alive or tk.team == 0 or tk.vis[0]
	# куст, в котором стоит наш танк или камера, становится полупрозрачным
	var cp := Vector2(cam.position.x, cam.position.z)
	for b in bushes:
		var br: float = b.r
		var see: bool = w.pos.distance_to(b.pos) < br + 10.0 or cp.distance_to(b.pos) < br + 6.0
		if see != b.see:
			b.see = see
			for mi: MeshInstance3D in b.meshes:
				if see:
					var m: StandardMaterial3D = mi.material_override.duplicate()
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color.a = 0.35
					mi.set_meta("solid", mi.material_override)
					mi.material_override = m
				elif mi.has_meta("solid"):
					mi.material_override = mi.get_meta("solid")
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
		dc.a = 0.12
		z.disc_mat.albedo_color = dc
		z.flag_mat.albedo_color = c
		z.flag.rotation.y = sin(clock * 2.0 + z.pos.x) * 0.25
