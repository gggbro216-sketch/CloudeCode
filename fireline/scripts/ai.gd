extends RefCounted
## ИИ стороны: распределяет подразделения по точкам, продвигается перебежками от укрытия к укрытию,
## держит огневую поддержку позади, останавливает технику для стрельбы, вызывает артиллерию.
## Видит только то же, что и обычный игрок (через общую систему обнаружения).

const UnitT = preload("res://scripts/unit.gd")
const Data = preload("res://scripts/data.gd")

var b
var side := 1
var mode := "meeting"  # роль этой стороны: meeting / attack / defend
var think_t := 0.0
var arty_t := 45.0
var smoke_t := 120.0


func _init(battle, s: int, m: String) -> void:
	b = battle
	side = s
	mode = m


func tick(dt: float) -> void:
	think_t -= dt
	arty_t -= dt
	smoke_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.5
	var known: Array = []
	for e in b.units:
		if e.side != side and e.alive and b.is_spotted(side, e):
			known.append(e)
	for u in b.units:
		if u.side == side and u.alive:
			_think(u, known)
	if arty_t <= 0.0:
		_arty(known)


func _dir_back() -> float:
	return -1.0 if side == 0 else 1.0


func _goal(u) -> Vector2:
	var flags: Array = b.flags
	if flags.is_empty():
		return u.position
	if mode == "defend":
		if not u.ai.has("flag"):
			var best := 0
			for i in flags.size():
				if flags[i].p.distance_to(u.position) < flags[best].p.distance_to(u.position):
					best = i
			u.ai["flag"] = best
		var f: Dictionary = flags[u.ai.flag]
		# потерянную точку отбиваем
		return f.p
	# наступление: ближайшая чужая точка, иначе — та, что ближе к противнику
	var best_f = null
	var best_s := INF
	for f in flags:
		var s: float = f.p.distance_to(u.position)
		if f.owner == side and not f.contested:
			s += 400.0
		if f.contested:
			s -= 80.0
		# распределяем: часть отрядов идёт к разным точкам
		s += float((u.uid * 7 + flags.find(f) * 13) % 5) * 25.0
		if s < best_s:
			best_s = s
			best_f = f
	return best_f.p


func _nearest(u, known: Array) -> Array:
	var best = null
	var bd := INF
	for e in known:
		var d: float = u.position.distance_to(e.position)
		if d < bd:
			bd = d
			best = e
	return [best, bd]


func _think(u, known: Array) -> void:
	if u.state != UnitT.ST_OK:
		return
	if not u.ai.has("delay"):
		u.ai["delay"] = 0.0 if mode == "defend" else randf_range(0.0, 12.0)
		u.ai["home"] = u.position
	u.ai.delay -= 1.5
	if u.ai.delay > 0.0:
		return
	var ne := _nearest(u, known)
	var near_e = ne[0]
	var nd: float = ne[1]
	if u.is_veh:
		_think_veh(u, known, near_e, nd)
	elif u.is_gun:
		_think_gun(u, nd)
	elif u.t.cat == "team":
		_think_support(u, near_e, nd)
	else:
		_think_inf(u, near_e, nd)


func _cover_move(u, p: Vector2, r: float, mode_mv: int) -> void:
	var c: Vector2 = b.map.find_cover_near(b.map.clamp_in(p), r, u.is_veh)
	if c.distance_to(u.position) > 4.0:
		u.order_move(c, mode_mv, true)


func _think_inf(u, near_e, nd: float) -> void:
	if u.target != null:
		if not u.moving and b.map.cover_at(u.position) < 0.25 and randf() < 0.4:
			var dir: Vector2 = (u.target.position - u.position).normalized()
			_cover_move(u, u.position + dir * 6.0, 22.0, UnitT.MV_FAST)
		elif not u.moving and mode != "defend" and nd > 200.0 and randf() < 0.3:
			var dir: Vector2 = (near_e.position - u.position).normalized()
			_cover_move(u, u.position + dir * 50.0, 20.0, UnitT.MV_FAST)
		return
	if u.moving:
		return
	var goal := _goal(u)
	var d: float = u.position.distance_to(goal)
	if mode == "defend":
		if d > 45.0:
			_cover_move(u, goal + Vector2(_dir_back() * randf_range(5, 30), randf_range(-30, 30)), 18.0,
				UnitT.MV_FAST if nd > 200.0 else UnitT.MV_MOVE)
		return
	if d > 25.0:
		var step := minf(d, randf_range(60.0, 110.0))
		var p: Vector2 = u.position + (goal - u.position).normalized() * step
		if d - step < 30.0:
			p = goal + Vector2(randf_range(-18, 18), randf_range(-18, 18))
		_cover_move(u, p, 18.0, UnitT.MV_FAST if nd > 260.0 else UnitT.MV_MOVE)


func _think_support(u, near_e, nd: float) -> void:
	var mortar := false
	for w in u.wpns:
		if Data.W[w].kind == "mortar":
			mortar = true
	if u.target != null or u.moving:
		return
	var goal := _goal(u)
	var d: float = u.position.distance_to(goal)
	if mortar:
		# миномёт держится в 250–450 м от цели
		if d > 450.0:
			var p: Vector2 = goal + (u.position - goal).normalized() * 330.0
			_cover_move(u, p, 25.0, UnitT.MV_MOVE)
		return
	if mode == "defend":
		if d > 120.0:
			_cover_move(u, goal + Vector2(_dir_back() * randf_range(30, 80), randf_range(-40, 40)), 25.0, UnitT.MV_MOVE)
		return
	# пулемёт и снайпер прикрывают: останавливаются в 90–160 м от точки
	var keep := randf_range(90.0, 160.0)
	if d > keep + 30.0:
		var step := minf(d - keep, randf_range(60.0, 100.0))
		var p: Vector2 = u.position + (goal - u.position).normalized() * step
		_cover_move(u, p, 22.0, UnitT.MV_FAST if nd > 300.0 else UnitT.MV_MOVE)


func _think_gun(u, nd: float) -> void:
	if u.target != null or u.moving:
		return
	if mode == "defend" or nd < 450.0:
		return
	var goal := _goal(u)
	var d: float = u.position.distance_to(goal)
	if d > 220.0:
		var p: Vector2 = goal + (u.position - goal).normalized() * 180.0
		var step: Vector2 = (p - u.position).limit_length(120.0)
		_cover_move(u, u.position + step, 20.0, UnitT.MV_MOVE)


func _think_veh(u, known: Array, near_e, nd: float) -> void:
	if u.immobile:
		return
	# опасная пехота с гранатомётом рядом — отходим задним ходом
	for e in known:
		if e.is_veh or e.alive == false:
			continue
		var has_at := false
		for w in e.wpns:
			if Data.W[w].kind == "rocket":
				has_at = true
		if has_at and e.position.distance_to(u.position) < 70.0:
			var away: Vector2 = (u.position - e.position).normalized()
			u.order_move(b.map.clamp_in(u.position + away * 45.0), UnitT.MV_BACK, true)
			return
	if u.target != null:
		if u.moving and u.path_i < u.path.size():
			var d: float = u.position.distance_to(u.target.position)
			if u.eff_vs(u.target, d, true) >= 1.2 or not u.target.is_veh:
				u.path.clear()
				u.path_i = 0
				u.move_mode = UnitT.MV_NONE
		return
	if u.moving:
		return
	var goal := _goal(u)
	var d: float = u.position.distance_to(goal)
	var stand := 15.0
	if nd < 400.0:
		stand = 70.0  # противник рядом — держимся за пехотой
	if mode == "defend":
		stand = 60.0
	if d > stand + 20.0:
		var step := minf(d - stand, randf_range(70.0, 130.0))
		var p: Vector2 = u.position + (goal - u.position).normalized() * step
		p = b.map.find_cover_near(b.map.clamp_in(p), 20.0, true)
		if u.order_move(p, UnitT.MV_MOVE, true):
			u.face_to = goal


func _arty(known: Array) -> void:
	arty_t = 20.0
	if b.arty[side][0] > 0 and b.sim_time > 60.0:
		var best = null
		var best_n := 0
		for e in known:
			if e.is_veh:
				continue
			var n := 1
			if e.is_gun or e.t.cat == "team":
				n += 1
			for o in known:
				if o != e and o.position.distance_to(e.position) < 45.0:
					n += 1
			# не бьём по своим
			for o in b.units:
				if o.side == side and o.alive and o.position.distance_to(e.position) < 60.0:
					n = -10
					break
			if n > best_n:
				best_n = n
				best = e
		if best != null and best_n >= 2:
			b.call_arty(side, best.position, "he")
			arty_t = 100.0
			return
	if mode != "defend" and b.arty[side][1] > 0 and smoke_t <= 0.0:
		var pinned := 0
		var pos := Vector2.ZERO
		for u in b.units:
			if u.side == side and u.alive and u.state == UnitT.ST_PINNED and u.target != null:
				pinned += 1
				pos = u.position.lerp(u.target.position, 0.45)
		if pinned >= 2:
			b.call_arty(side, pos, "smoke")
			smoke_t = 200.0
