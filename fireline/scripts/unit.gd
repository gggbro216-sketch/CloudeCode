extends Node2D
## Подразделение: отделение пехоты, расчёт, буксируемое орудие или машина.
## Позиция узла — точка командира (по ней идёт движение); бойцы держатся своих мест в строю,
## а на остановке сами расходятся по ближайшим укрытиям.

const Data = preload("res://scripts/data.gd")
const MapT = preload("res://scripts/map.gd")

enum { ST_OK, ST_PINNED, ST_ROUT }
enum { MV_NONE, MV_MOVE, MV_FAST, MV_BACK }

var battle
var map: MapT
var t: Dictionary
var tid := ""
var side := 0
var uid := 0
var fac: Dictionary
var is_veh := false
var is_gun := false
var alive := true
var men: Array = []
var start_men := 0
var crew := 0
var start_crew := 0
var facing := 0.0
var turret := 0.0
var path := PackedVector2Array()
var path_i := 0
var move_mode := MV_NONE
var face_to := Vector2.INF
var hold_fire := false
var forced = null
var area := Vector2.INF
var target = null
var mg_target = null
var suppression := 0.0
var state := ST_OK
var rout_t := 0.0
var since_hit := 99.0
var since_fire := 99.0
var moving := false
var main_cd := 0.0
var mg_cd: Array = []
var nade_cd := 0.0
var immobile := false
var gun_broken := false
var shaken := 0.0
var kills := 0
var los: Dictionary = {}
var retarget := 0.0
var recoil := 0.0
var wpns: Array = []
var max_range := 0.0
var form_off: Array = []
var ai := {}
var speed_now := 0.0
var bob := 0.0


func setup(type_id: String, s: int, pos: Vector2, face: float) -> void:
	tid = type_id
	t = Data.U[type_id]
	fac = Data.FACTIONS[t.f]
	side = s
	is_veh = t.cat == "veh"
	is_gun = t.cat == "gun"
	position = pos
	facing = face
	turret = face
	if is_veh:
		crew = t.crew
		start_crew = crew
		if t.gun != "":
			wpns.append(t.gun)
		for m in t.mg:
			mg_cd.append(randf())
			if not wpns.has(m):
				wpns.append(m)
	else:
		for pair in t.men:
			for i in int(pair[1]):
				men.append({"p": pos, "slot": pos, "w": pair[0], "cd": randf() * 2.0, "alive": true,
					"face": face, "prone": false})
				if pair[0] != "crew" and not wpns.has(pair[0]):
					wpns.append(pair[0])
		start_men = men.size()
		if is_gun:
			wpns.append(t.gun)
		if t.get("nade", false):
			wpns.append("grenade")
	for wid in wpns:
		max_range = maxf(max_range, Data.W[wid].range)
	_make_formation()
	for i in men.size():
		men[i].p = _slot_pos(i)
		men[i].slot = men[i].p
	main_cd = randf() * 2.0


# ===================== Состояние =====================

func alive_men() -> int:
	var n := 0
	for m in men:
		if m.alive:
			n += 1
	return n


func strength() -> float:
	if is_veh:
		return float(crew) / start_crew
	return float(alive_men()) / maxf(start_men, 1)


func effective() -> bool:
	return alive and state != ST_ROUT


func radius() -> float:
	return t.len * 0.5 if is_veh else 7.0


func status_text() -> String:
	if not alive:
		return "уничтожен"
	var s: PackedStringArray = []
	if state == ST_ROUT:
		s.append("отступает")
	elif state == ST_PINNED:
		s.append("прижат огнём")
	elif suppression > 30.0:
		s.append("под огнём")
	if immobile:
		s.append("обездвижен")
	if gun_broken:
		s.append("орудие повреждено")
	if shaken > 0.0:
		s.append("экипаж оглушён")
	if hold_fire:
		s.append("засада")
	if s.is_empty():
		if moving:
			s.append("в движении")
		elif target != null:
			s.append("ведёт огонь")
		else:
			s.append("готов")
	return ", ".join(s)


func armor_toward(from: Vector2) -> float:
	var a := absf(wrapf((from - position).angle() - facing, -PI, PI))
	if a < 0.9:
		return t.armor[0]
	if a > PI - 0.75:
		return t.armor[2]
	return t.armor[1]


func pick_point() -> Vector2:
	if is_veh or men.is_empty():
		return position
	var alive_list: Array = []
	for m in men:
		if m.alive:
			alive_list.append(m)
	if alive_list.is_empty():
		return position
	return alive_list[randi() % alive_list.size()].p


func add_sup(v: float) -> void:
	if not alive:
		return
	suppression = minf(100.0, suppression + v)
	since_hit = 0.0


# ===================== Приказы =====================

func order_move(dest: Vector2, mode: int, internal := false) -> bool:
	if not alive or (state == ST_ROUT and not internal):
		return false
	if is_veh and immobile:
		return false
	var p := map.find_path(position, dest, is_veh)
	if p.size() < 2:
		if position.distance_to(dest) < 4.0:
			return false
		p = PackedVector2Array([position, map.nearest_passable(dest, is_veh)])
	path = p
	path_i = 1
	move_mode = mode
	face_to = Vector2.INF
	if not internal:
		ai["hold_t"] = 0.0
	return true


func order_path(pts: PackedVector2Array, mode: int) -> bool:
	if not alive or state == ST_ROUT or (is_veh and immobile) or pts.size() < 1:
		return false
	var full := PackedVector2Array([position])
	var cur := position
	for p in pts:
		var seg := map.find_path(cur, p, is_veh)
		if seg.size() < 2:
			continue
		for i in range(1, seg.size()):
			full.append(seg[i])
		cur = seg[seg.size() - 1]
	if full.size() < 2:
		return false
	path = full
	path_i = 1
	move_mode = mode
	face_to = Vector2.INF
	return true


func order_stop() -> void:
	path.clear()
	path_i = 0
	move_mode = MV_NONE
	forced = null
	area = Vector2.INF
	if not is_veh:
		_take_cover()


func order_target(e) -> void:
	forced = e
	area = Vector2.INF
	retarget = 0.0


func order_area(p: Vector2) -> void:
	forced = null
	area = p
	target = null


func order_face(p: Vector2) -> void:
	if moving:
		face_to = p
	else:
		face_to = p
		_apply_face()


func _apply_face() -> void:
	if face_to == Vector2.INF:
		return
	if is_veh or is_gun:
		return  # машина/орудие доворачивает постепенно в tick
	facing = (face_to - position).angle()
	_make_formation()
	_take_cover()
	face_to = Vector2.INF


# ===================== Такт =====================

func tick(dt: float) -> void:
	if not alive:
		return
	since_hit += dt
	since_fire += dt
	shaken = maxf(0.0, shaken - dt)
	recoil = maxf(0.0, recoil - dt * 2.0)
	_morale(dt)
	_move(dt)
	retarget -= dt
	if retarget <= 0.0:
		retarget = randf_range(0.5, 0.9)
		_pick_target()
	if state != ST_ROUT:
		if is_veh:
			_fire_veh(dt)
		elif is_gun:
			_fire_gun(dt)
			_fire_inf(dt)
		else:
			_fire_inf(dt)
	if not is_veh:
		_update_men(dt)
	queue_redraw()


func _morale(dt: float) -> void:
	if is_veh:
		suppression = maxf(0.0, suppression - 25.0 * dt)
		return
	if since_hit > 1.5:
		suppression = maxf(0.0, suppression - (9.0 if state == ST_OK else 6.0) * dt)
	var str_r := strength()
	match state:
		ST_OK:
			if suppression >= 60.0:
				state = ST_PINNED
				battle.unit_note(self, "прижат огнём")
		ST_PINNED:
			if suppression >= 92.0 and randf() < dt * (0.25 + (1.0 - str_r) * 1.2):
				_start_rout()
			elif suppression < 35.0:
				state = ST_OK
		ST_ROUT:
			rout_t -= dt
			if rout_t <= 0.0 and suppression < 45.0 and path_i >= path.size():
				state = ST_OK
				suppression = 40.0
				battle.unit_note(self, "приходит в себя")
	# потери ломают боевой дух
	if state != ST_ROUT and str_r < 0.3 and suppression > 70.0 and randf() < dt * 0.3:
		_start_rout()


func _start_rout() -> void:
	state = ST_ROUT
	rout_t = randf_range(14.0, 22.0)
	forced = null
	area = Vector2.INF
	target = null
	var back := Vector2(-1.0 if side == 0 else 1.0, randf_range(-0.4, 0.4)).normalized()
	var dest := map.find_cover_near(map.clamp_in(position + back * randf_range(70.0, 110.0)), 30.0, false)
	order_move(dest, MV_FAST, true)
	battle.unit_note(self, "отступает!")


func move_speed() -> float:
	var base: float = t.speed
	var tm := map.speed_at(position, is_veh)
	if tm <= 0.0:
		tm = 0.3
	match move_mode:
		MV_FAST:
			base *= 1.25 if is_veh else 1.9
		MV_BACK:
			base *= 0.45
	if state == ST_ROUT:
		base *= 1.9 if not is_veh else 1.0
	if not is_veh:
		base *= lerpf(1.0, 0.6, suppression / 100.0)
	elif crew < start_crew:
		base *= 0.85
	return base * tm


func _move(dt: float) -> void:
	moving = false
	speed_now = 0.0
	if path_i >= path.size() or path.is_empty():
		if move_mode != MV_NONE:
			_arrived()
		if (is_veh or is_gun) and face_to != Vector2.INF and target == null:
			var want := (face_to - position).angle()
			var turn: float = deg_to_rad(t.get("turn", 20.0))
			facing = _rot(facing, want, turn * dt)
			if absf(wrapf(want - facing, -PI, PI)) < 0.02:
				face_to = Vector2.INF
		return
	if state == ST_PINNED:
		return
	if is_veh and immobile:
		path.clear()
		return
	var tgt := path[path_i]
	var to := tgt - position
	var d := to.length()
	var spd := move_speed()
	var arrive := 2.5 if is_veh else 1.0
	if path_i == path.size() - 1:
		arrive = 1.2 if is_veh else 0.6
	if d <= arrive:
		path_i += 1
		if path_i >= path.size():
			_arrived()
		return
	moving = true
	if is_veh:
		var want := to.angle()
		if move_mode == MV_BACK:
			want += PI
		var diff := wrapf(want - facing, -PI, PI)
		facing = _rot(facing, want, deg_to_rad(t.turn) * dt)
		var k := 0.0
		if absf(diff) < 0.6:
			k = maxf(0.25, cos(diff))
		else:
			k = 0.05
		var dir := Vector2.from_angle(facing) * (-1.0 if move_mode == MV_BACK else 1.0)
		var step := minf(d, spd * k * dt)
		var np := position + dir * step
		if map.passable(np, true):
			position = np
		elif map.passable(position + to / d * step, true):
			position += to / d * step
		speed_now = step / maxf(dt, 0.0001)
		if not t.turret:
			turret = facing
	else:
		var step := minf(d, spd * dt)
		position += to / d * step
		facing = lerp_angle(facing, to.angle(), minf(1.0, dt * 6.0))
		speed_now = spd
		bob += dt * spd * 3.0


func _arrived() -> void:
	path.clear()
	path_i = 0
	move_mode = MV_NONE
	if not is_veh:
		if face_to != Vector2.INF and not is_gun:
			facing = (face_to - position).angle()
			face_to = Vector2.INF
		_make_formation()
		_take_cover()


static func _rot(from: float, to: float, step: float) -> float:
	var d := wrapf(to - from, -PI, PI)
	if absf(d) <= step:
		return to
	return from + signf(d) * step


# ===================== Бойцы =====================

func _make_formation() -> void:
	form_off.clear()
	var n := men.size()
	if is_gun:
		for i in n:
			form_off.append(Vector2(-2.5 - (i % 2) * 1.6, (i - n * 0.5) * 1.4))
		return
	var per_row := 5 if n > 6 else n
	for i in n:
		var row := i / maxi(per_row, 1)
		var col := i % maxi(per_row, 1)
		var cnt := mini(per_row, n - row * per_row)
		var y := (col - (cnt - 1) * 0.5) * 3.2
		var x := -row * 3.6 - absf(y) * 0.25
		form_off.append(Vector2(x, y))


func _slot_pos(i: int) -> Vector2:
	if i >= form_off.size():
		return position
	var p := position + (form_off[i] as Vector2).rotated(facing)
	if not map.passable(p, false):
		return position
	return p


func _take_cover() -> void:
	if is_gun:
		for i in men.size():
			men[i].slot = _slot_pos(i)
		return
	var used := {}
	for i in men.size():
		var m: Dictionary = men[i]
		if not m.alive:
			continue
		m.slot = map.cover_spot(_slot_pos(i), 5.0, used)


func _update_men(dt: float) -> void:
	var sp := maxf(speed_now, 1.6) * 1.2 + 0.4
	var prone := state != ST_OK or suppression > 25.0
	for i in men.size():
		var m: Dictionary = men[i]
		if not m.alive:
			continue
		var slot: Vector2 = _slot_pos(i) if moving else m.slot
		var d: float = (slot - m.p).length()
		var k := 2.5 if d > 10.0 else 1.0
		m.p = (m.p as Vector2).move_toward(slot, sp * k * dt)
		m.prone = prone and not moving
		if moving and d > 0.3:
			m.face = lerp_angle(m.face, ((slot - m.p) as Vector2).angle(), minf(1.0, dt * 6.0))
		elif target == null and not moving:
			m.face = lerp_angle(m.face, facing, minf(1.0, dt * 2.0))


# ===================== Цели =====================

func eff_single(wid: String, e, d: float) -> float:
	var w: Dictionary = Data.W[wid]
	if d > w.range:
		return 0.0
	var k: String = w.kind
	if k == "mortar" and d < w.min:
		return 0.0
	if e.is_veh:
		match k:
			"gun", "rocket", "ap":
				var arm: float = e.armor_toward(position)
				var pen := Data.pen_at(wid, d)
				if pen >= arm * 1.05:
					return 3.0
				if pen >= arm * 0.8:
					return 1.2
				return 0.05
			"sa":
				if e.t.get("open", false) or w.get("pen", 0.0) > e.t.armor[1]:
					return 0.5
				return 0.0
			"mortar", "he":
				return 0.3 if e.t.get("open", false) else 0.0
		return 0.0
	match k:
		"sa":
			return 1.4 if w.burst >= 4 else 1.0
		"he", "mortar":
			return 1.2
		"gun":
			return 1.3 if w.he_r >= 5.0 else 0.7
		"rocket":
			return 0.4 if map.cover_at(e.position) > 0.5 else 0.0
		"ap":
			return 0.3
	return 0.0


func eff_vs(e, d: float, direct: bool) -> float:
	var best := 0.0
	for wid in wpns:
		if not direct and Data.W[wid].kind != "mortar":
			continue
		best = maxf(best, eff_single(wid, e, d))
	return best


func _pick_target() -> void:
	target = null
	mg_target = null
	if state == ST_ROUT:
		return
	if forced != null:
		if not is_instance_valid(forced) or not forced.alive:
			forced = null
		elif battle.is_spotted(side, forced):
			var d := position.distance_to(forced.position)
			if eff_vs(forced, d, los.get(forced.uid, false)) > 0.0:
				target = forced
	var best := 0.0
	var cand = null
	var best_inf := INF
	for e in battle.units:
		if e.side == side or not e.alive:
			continue
		if not battle.is_spotted(side, e):
			continue
		var d := position.distance_to(e.position)
		if d > max_range + 10.0:
			continue
		if hold_fire and d > 90.0 and e != forced:
			continue
		var direct: bool = los.get(e.uid, false)
		if is_veh and direct and not e.is_veh and d < 600.0 and d < best_inf:
			best_inf = d
			mg_target = e
		var s := eff_vs(e, d, direct)
		if s <= 0.06:
			continue
		s /= (1.0 + d / 250.0)
		if e.target == self:
			s *= 1.3
		if e.state == ST_ROUT:
			s *= 0.5
		if s > best:
			best = s
			cand = e
	if target == null:
		target = cand
	if is_veh and target != null and not target.is_veh:
		mg_target = target


# ===================== Огонь =====================

func _fire_inf(dt: float) -> void:
	nade_cd -= dt
	var tgt = target
	if tgt != null and not is_instance_valid(tgt):
		tgt = null
		target = null
	var mult := 1.0 + suppression / 100.0 * 1.5
	if move_mode == MV_FAST and moving:
		return
	for m in men:
		if not m.alive:
			continue
		m.cd -= dt
		if m.cd > 0.0 or m.w == "crew":
			continue
		var wid: String = m.w
		var w: Dictionary = Data.W[wid]
		if tgt != null:
			var d: float = (m.p as Vector2).distance_to(tgt.position)
			if d > w.range:
				continue
			if w.kind == "mortar":
				if d < w.min or moving:
					continue
			elif not los.get(tgt.uid, false):
				continue
			if eff_single(wid, tgt, d) <= 0.06:
				continue
			m.cd = w.reload * randf_range(0.8, 1.25) * mult
			m.face = (tgt.position - m.p).angle()
			battle.fire(self, m.p, wid, tgt, tgt.pick_point(), d)
			since_fire = 0.0
		elif area != Vector2.INF:
			var d: float = (m.p as Vector2).distance_to(area)
			if d > w.range or (w.kind == "mortar" and (d < w.min or moving)) or w.kind == "rocket" or w.kind == "ap":
				continue
			m.cd = w.reload * randf_range(0.9, 1.4) * mult
			m.face = (area - m.p).angle()
			battle.fire(self, m.p, wid, null, area + Vector2(randf_range(-6, 6), randf_range(-6, 6)), d)
			since_fire = 0.0
	if t.get("nade", false) and nade_cd <= 0.0 and tgt != null and not tgt.is_veh and los.get(tgt.uid, false):
		var d := position.distance_to(tgt.position)
		if d < 32.0 and state == ST_OK:
			nade_cd = randf_range(12.0, 20.0)
			var th := pick_point()
			battle.fire(self, th, "grenade", tgt, tgt.pick_point(), d)


func _fire_gun(dt: float) -> void:
	main_cd -= dt
	var n := 0
	for m in men:
		if m.alive:
			n += 1
	if n < 2 or moving:
		return
	var aim := Vector2.INF
	var tg = null
	if target != null and is_instance_valid(target) and los.get(target.uid, false):
		tg = target
		aim = target.position
	elif area != Vector2.INF:
		aim = area
	if aim == Vector2.INF:
		turret = _rot(turret, facing, 0.4 * dt)
		return
	var want := (aim - position).angle()
	var diff := wrapf(want - facing, -PI, PI)
	if absf(diff) > 0.5:
		facing = _rot(facing, want, deg_to_rad(14.0) * dt)
		_take_cover()
	var lim := clampf(wrapf(want - facing, -PI, PI), -0.5, 0.5)
	turret = _rot(turret, facing + lim, deg_to_rad(20.0) * dt)
	var d := position.distance_to(aim)
	if main_cd <= 0.0 and absf(wrapf(want - turret, -PI, PI)) < 0.03 and d <= Data.W[t.gun].range:
		if tg != null and eff_single(t.gun, tg, d) <= 0.06:
			return
		main_cd = Data.W[t.gun].reload * float(start_men) / n * randf_range(0.9, 1.15)
		recoil = 1.0
		since_fire = 0.0
		var muzzle := position + Vector2.from_angle(turret) * 3.2
		battle.fire(self, muzzle, t.gun, tg, tg.pick_point() if tg != null else aim, d)


func _fire_veh(dt: float) -> void:
	if crew <= 0:
		return
	var rmult := 1.0
	if shaken > 0.0:
		rmult = 1.7
	if crew < start_crew:
		rmult *= 1.3
	main_cd -= dt / rmult
	var tgt = target
	if tgt != null and not is_instance_valid(tgt):
		tgt = null
	var aim := Vector2.INF
	if tgt != null and los.get(tgt.uid, false):
		aim = tgt.position
	else:
		tgt = null
		if area != Vector2.INF:
			aim = area
	var gun: String = t.gun
	if gun != "" and not gun_broken:
		var tt: float = deg_to_rad(t.tturn) if t.turret else 0.0
		if aim != Vector2.INF:
			var want := (aim - position).angle()
			if t.turret:
				turret = _rot(turret, want, tt * dt)
			else:
				var diff := wrapf(want - facing, -PI, PI)
				if not moving and absf(diff) > 0.15 and not immobile:
					facing = _rot(facing, want, deg_to_rad(t.turn) * dt)
				turret = facing + clampf(wrapf(want - facing, -PI, PI), -0.17, 0.17)
			var d := position.distance_to(aim)
			var ok_ang := absf(wrapf(want - turret, -PI, PI)) < 0.03
			if main_cd <= 0.0 and ok_ang and d <= Data.W[gun].range:
				if tgt == null or eff_single(gun, tgt, d) > 0.06:
					main_cd = Data.W[gun].reload * randf_range(0.9, 1.15)
					recoil = 1.0
					since_fire = 0.0
					var L: float = t.len
					var muzzle := position + Vector2.from_angle(turret) * (L * 0.5 + 1.5)
					battle.fire(self, muzzle, gun, tgt, tgt.pick_point() if tgt != null else aim, d)
		elif t.turret:
			turret = _rot(turret, facing, tt * 0.5 * dt)
		else:
			turret = facing
	# пулемёты: спаренный идёт за башней, курсовой — в переднем секторе
	var mt = mg_target
	if mt != null and (not is_instance_valid(mt) or not mt.alive or not los.get(mt.uid, false)):
		mt = null
	for i in mg_cd.size():
		mg_cd[i] -= dt
		if mg_cd[i] > 0.0:
			continue
		var wid: String = t.mg[i]
		var w: Dictionary = Data.W[wid]
		var p := Vector2.INF
		if mt != null:
			p = mt.position
		elif area != Vector2.INF:
			p = area
		if p == Vector2.INF:
			continue
		var d := position.distance_to(p)
		if d > w.range:
			continue
		if i == 1 and absf(wrapf((p - position).angle() - facing, -PI, PI)) > 0.8:
			continue
		mg_cd[i] = w.reload * randf_range(0.85, 1.3) * rmult
		since_fire = 0.0
		var L2: float = t.len
		var origin := position + Vector2.from_angle(facing) * L2 * 0.3
		battle.fire(self, origin, wid, mt, mt.pick_point() if mt != null else p + Vector2(randf_range(-5, 5), randf_range(-5, 5)), d)


# ===================== Повреждения =====================

func kill_man(m: Dictionary, killer) -> void:
	if not m.alive:
		return
	m.alive = false
	battle.on_man_killed(self, m, killer)
	if alive_men() == 0:
		die(killer)


func die(killer) -> void:
	if not alive:
		return
	alive = false
	path.clear()
	target = null
	forced = null
	battle.on_unit_destroyed(self, killer)
	queue_redraw()


# ===================== Отрисовка =====================

func _draw() -> void:
	if is_veh:
		_draw_veh()
	else:
		if is_gun:
			_draw_gun()
		_draw_men()


func _draw_men() -> void:
	var cloth: Color = fac.cloth
	var helm: Color = fac.helmet
	var dark := Color(0.08, 0.08, 0.06)
	for m in men:
		if not m.alive:
			continue
		var lp: Vector2 = m.p - position
		draw_set_transform(lp, m.face)
		var wcol := Color(0.15, 0.12, 0.09)
		var wl := 1.1
		var ww := 0.14
		match m.w:
			"lmg", "hmg", "mg42", "mg50":
				wl = 1.4
				ww = 0.2
			"smg":
				wl = 0.75
			"bazooka", "pschreck":
				wl = 1.6
				ww = 0.32
				wcol = Color(0.25, 0.27, 0.2)
			"ptrd":
				wl = 2.0
				ww = 0.16
			"mort60", "mort8":
				wl = 0.0
			"crew":
				wl = 0.0
		if m.prone:
			draw_rect(Rect2(-1.3, -0.36, 1.6, 0.72), dark)
			draw_rect(Rect2(-1.2, -0.28, 1.45, 0.56), cloth)
			if wl > 0.0:
				draw_line(Vector2(0.2, 0.12), Vector2(0.2 + wl, 0.12), wcol, ww)
			draw_circle(Vector2(0.35, 0.0), 0.3, helm)
		else:
			var b := sin(bob + m.p.x) * 0.06 if moving else 0.0
			draw_rect(Rect2(-0.3, -0.55 + b, 0.6, 1.1), dark)
			draw_rect(Rect2(-0.24, -0.48 + b, 0.48, 0.96), cloth)
			if wl > 0.0:
				draw_line(Vector2(0.1, 0.3), Vector2(0.1 + wl, 0.25), wcol, ww)
			draw_circle(Vector2(0.02, 0.0), 0.36, dark)
			draw_circle(Vector2(0.02, 0.0), 0.3, helm)
		if m.w == "mort60" or m.w == "mort8":
			draw_circle(Vector2(1.2, 0.0), 0.35, Color(0.2, 0.2, 0.18))
			draw_line(Vector2(1.2, 0.0), Vector2(1.9, 0.0), Color(0.25, 0.25, 0.22), 0.25)
	draw_set_transform(Vector2.ZERO, 0.0)


func _draw_gun() -> void:
	var col: Color = fac.paint.darkened(0.15)
	var dk := col.darkened(0.5)
	# станины назад
	draw_set_transform(Vector2.ZERO, facing)
	draw_line(Vector2(0, -0.4), Vector2(-3.2, -1.2), dk, 0.35)
	draw_line(Vector2(0, 0.4), Vector2(-3.2, 1.2), dk, 0.35)
	draw_rect(Rect2(-0.3, -1.1, 0.6, 0.3), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(-0.3, 0.8, 0.6, 0.3), Color(0.1, 0.1, 0.1))
	draw_set_transform(Vector2.ZERO, turret)
	draw_rect(Rect2(0.3, -1.1, 0.25, 2.2), dk)
	draw_rect(Rect2(0.35, -1.0, 0.15, 2.0), col)
	var bl := 3.2 - recoil * 0.5
	draw_line(Vector2(-0.6, 0), Vector2(bl, 0), dk, 0.32)
	draw_line(Vector2(-0.4, 0), Vector2(bl - 0.1, 0), col, 0.2)
	draw_set_transform(Vector2.ZERO, 0.0)


func _draw_veh() -> void:
	var L: float = t.len
	var Wd: float = t.wid
	var paint: Color = fac.paint
	var dead := not alive
	if dead:
		paint = Color(0.16, 0.14, 0.12)
	var dk := paint.darkened(0.45)
	var trk := Color(0.13, 0.12, 0.11) if not dead else Color(0.08, 0.07, 0.07)
	var ht: bool = t.kind == "ht"
	# тень
	draw_set_transform(Vector2(0.6, 0.8), facing)
	draw_rect(Rect2(-L * 0.5, -Wd * 0.5, L, Wd), Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, facing)
	# гусеницы / колёса
	var tw := Wd * 0.22
	if ht:
		draw_rect(Rect2(-L * 0.5, -Wd * 0.5, L * 0.62, tw), trk)
		draw_rect(Rect2(-L * 0.5, Wd * 0.5 - tw, L * 0.62, tw), trk)
		draw_rect(Rect2(L * 0.3, -Wd * 0.5, L * 0.12, tw * 0.9), trk)
		draw_rect(Rect2(L * 0.3, Wd * 0.5 - tw * 0.9, L * 0.12, tw * 0.9), trk)
	else:
		draw_rect(Rect2(-L * 0.5, -Wd * 0.5, L, tw), trk)
		draw_rect(Rect2(-L * 0.5, Wd * 0.5 - tw, L, tw), trk)
		var x := -L * 0.5 + 0.35
		while x < L * 0.5:
			draw_line(Vector2(x, -Wd * 0.5), Vector2(x, -Wd * 0.5 + tw), trk.lightened(0.15), 0.08)
			draw_line(Vector2(x, Wd * 0.5 - tw), Vector2(x, Wd * 0.5), trk.lightened(0.15), 0.08)
			x += 0.45
	# корпус
	var hw := Wd * 0.5 - tw * 0.55
	if ht:
		draw_rect(Rect2(-L * 0.5 + 0.1, -hw, L * 0.95, hw * 2.0), dk)
		draw_rect(Rect2(-L * 0.5 + 0.2, -hw + 0.1, L * 0.92, hw * 2.0 - 0.2), paint)
		draw_rect(Rect2(L * 0.15, -hw + 0.15, L * 0.28, hw * 2.0 - 0.3), paint.lightened(0.08))
		draw_rect(Rect2(-L * 0.45, -hw + 0.3, L * 0.55, hw * 2.0 - 0.6), Color(0.1, 0.09, 0.08))
		for i in 3:
			draw_circle(Vector2(-L * 0.35 + i * 0.9, (i % 2) * 0.6 - 0.3), 0.25, fac.helmet)
	else:
		draw_rect(Rect2(-L * 0.48, -hw, L * 0.96, hw * 2.0), dk)
		draw_rect(Rect2(-L * 0.46, -hw + 0.12, L * 0.92, hw * 2.0 - 0.24), paint)
		draw_rect(Rect2(L * 0.28, -hw + 0.12, L * 0.18, hw * 2.0 - 0.24), paint.lightened(0.1))
		# решётки моторного отделения
		for i in 4:
			var gx := -L * 0.44 + i * 0.32
			draw_line(Vector2(gx, -hw * 0.6), Vector2(gx, hw * 0.6), dk, 0.12)
		if t.get("open", false):
			draw_rect(Rect2(-L * 0.25, -hw + 0.3, L * 0.45, hw * 2.0 - 0.6), Color(0.1, 0.09, 0.08))
	if not dead:
		_draw_mark(Vector2(-L * 0.1, 0.0) if ht else Vector2(-L * 0.32, 0.0), minf(0.7, Wd * 0.2))
	# башня или рубка
	var gun_len := 0.0
	if t.gun != "":
		var pen0: float = Data.W[t.gun].get("pen0", 60.0)
		gun_len = clampf(L * 0.35 + pen0 * 0.012, 2.0, 5.2)
	if t.turret:
		var tc := Vector2(L * 0.04, 0.0)
		draw_set_transform(tc.rotated(facing), turret)
		var tr := Wd * 0.33
		if t.get("open", false):
			_poly_circle(Vector2.ZERO, tr, dk, 8)
			_poly_circle(Vector2.ZERO, tr * 0.75, Color(0.12, 0.11, 0.1), 8)
		else:
			_poly_circle(Vector2(0.15, 0.15), tr, Color(0, 0, 0, 0.3), 8)
			_poly_circle(Vector2.ZERO, tr, dk, 8)
			_poly_circle(Vector2.ZERO, tr * 0.9, paint.lightened(0.05), 8)
			draw_circle(Vector2(-tr * 0.35, -tr * 0.3), tr * 0.25, dk)
		var bl := gun_len - recoil * 0.6
		draw_line(Vector2(tr * 0.6, 0), Vector2(tr + bl, 0), dk, 0.34)
		draw_line(Vector2(tr * 0.6, 0), Vector2(tr + bl - 0.05, 0), paint.darkened(0.2), 0.2)
		if gun_len > 3.5:
			draw_rect(Rect2(tr + bl - 0.35, -0.2, 0.35, 0.4), dk)
	elif t.gun != "":
		draw_set_transform(Vector2.ZERO, facing)
		var cw := hw * 1.6
		if t.get("open", false):
			draw_rect(Rect2(-L * 0.35, -cw * 0.5, L * 0.4, cw), dk)
			draw_rect(Rect2(-L * 0.32, -cw * 0.5 + 0.15, L * 0.34, cw - 0.3), Color(0.12, 0.11, 0.1))
		else:
			draw_rect(Rect2(-L * 0.2, -cw * 0.5, L * 0.5, cw), dk)
			draw_rect(Rect2(-L * 0.18, -cw * 0.5 + 0.12, L * 0.46, cw - 0.24), paint.lightened(0.06))
		draw_set_transform(Vector2(L * 0.25, 0).rotated(facing), turret)
		var bl := gun_len - recoil * 0.6
		draw_line(Vector2(0, 0), Vector2(bl, 0), dk, 0.32)
	draw_set_transform(Vector2.ZERO, 0.0)
	if immobile and alive:
		draw_set_transform(Vector2.ZERO, facing)
		draw_line(Vector2(-L * 0.5, -Wd * 0.5), Vector2(-L * 0.5 - 1.2, -Wd * 0.5 - 0.6), trk, tw)
		draw_set_transform(Vector2.ZERO, 0.0)


func _draw_mark(p: Vector2, s: float) -> void:
	match t.f:
		"us":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				var r := s if i % 2 == 0 else s * 0.4
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0.92, 0.92, 0.88))
		"su":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				var r := s if i % 2 == 0 else s * 0.4
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0.75, 0.15, 0.12))
		"de":
			draw_rect(Rect2(p - Vector2(s, s * 0.3), Vector2(s * 2, s * 0.6)), Color(0.95, 0.95, 0.95))
			draw_rect(Rect2(p - Vector2(s * 0.3, s), Vector2(s * 0.6, s * 2)), Color(0.95, 0.95, 0.95))
			draw_rect(Rect2(p - Vector2(s * 0.8, s * 0.15), Vector2(s * 1.6, s * 0.3)), Color(0.05, 0.05, 0.05))
			draw_rect(Rect2(p - Vector2(s * 0.15, s * 0.8), Vector2(s * 0.3, s * 1.6)), Color(0.05, 0.05, 0.05))


func _poly_circle(c: Vector2, r: float, col: Color, seg: int) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg + PI / seg
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
