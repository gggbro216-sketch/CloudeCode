extends Node2D
## Бой в реальном времени с активной паузой: подразделения, видимость и туман войны,
## стрельба и бронепробитие, артиллерия, точки захвата, условия победы, управление касаниями.

signal finished(result: Dictionary)

const Data = preload("res://scripts/data.gd")
const MapT = preload("res://scripts/map.gd")
const UnitT = preload("res://scripts/unit.gd")
const FxT = preload("res://scripts/fx.gd")
const DecalsT = preload("res://scripts/decals.gd")
const SfxT = preload("res://scripts/sfx.gd")
const AiT = preload("res://scripts/ai.gd")
const HudT = preload("res://scripts/hud.gd")
const OverlayT = preload("res://scripts/overlay.gd")

const FLAG_R := 35.0
const ARTY_DELAY := 12.0

var cfg: Dictionary
var map: MapT
var decals
var fx
var sfx
var hud
var overlay
var cam: Camera2D
var units_node: Node2D
var units: Array = []
var proj: Array = []
var barrages: Array = []
var vis := [{}, {}]
var ghosts := {}
var flags: Array = []
var phase := "deploy"
var paused := false
var speed := 1.0
var time_left := 900.0
var time_total := 900.0
var arty := [[2, 1], [2, 1]]
var losses := [{"cost": 0, "men": 0, "veh": 0, "units": 0}, {"cost": 0, "men": 0, "veh": 0, "units": 0}]
var ais: Array = []
var selection: Array = []
var order_mode := ""
var next_uid := 1
var vis_t := 0.0
var vis_pass := 0
var flag_t := 0.0
var end_t := 1.0
var hold_all := [0.0, 0.0]
var player_side := 0
var autoplay := false
var result := {}
var sim_time := 0.0
var factions := ["us", "de"]
var zoom := 3.0
var touches := {}
var pinch := {}
var drag_path := PackedVector2Array()


# ===================== Запуск =====================

func start(c: Dictionary) -> void:
	cfg = c
	autoplay = c.get("autotest", false)
	var sc: Dictionary = c.scenario
	time_total = c.get("time", sc.time)
	time_left = time_total
	factions = [c.faction, c.enemy_faction]
	map = MapT.new()
	add_child(map)
	map.generate(sc.map, c.seed, sc.mode)
	decals = DecalsT.new()
	add_child(decals)
	add_child(map.top)
	units_node = Node2D.new()
	add_child(units_node)
	fx = FxT.new()
	fx.battle = self
	add_child(fx)
	sfx = SfxT.new()
	add_child(sfx)
	sfx.muted = c.get("muted", false)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	var ol := CanvasLayer.new()
	ol.layer = 1
	add_child(ol)
	overlay = OverlayT.new()
	overlay.battle = self
	ol.add_child(overlay)
	var hl := CanvasLayer.new()
	hl.layer = 2
	add_child(hl)
	hud = HudT.new()
	hud.battle = self
	hl.add_child(hud)
	var names := ["A", "B", "C", "D"]
	for i in map.flags.size():
		var p := map.nearest_passable(map.flags[i], false)
		var owner := -1
		if sc.mode == "defend":
			owner = 0
		elif sc.mode == "attack":
			owner = 1
		flags.append({"p": p, "owner": owner, "prog": [-1.0, 1.0][owner] if owner >= 0 else 0.0,
			"name": names[i], "contested": false})
	var enemy_mode := "meeting"
	if sc.mode == "attack":
		enemy_mode = "defend"
	elif sc.mode == "defend":
		enemy_mode = "attack"
	_spawn_army(c.army, 0, sc.mode == "defend")
	_spawn_army(c.enemy_army, 1, enemy_mode == "defend")
	ais.append(AiT.new(self, 1, enemy_mode))
	if autoplay:
		ais.append(AiT.new(self, 0, sc.mode))
	var vp := get_viewport().get_visible_rect().size
	zoom = clampf(vp.y / 200.0, 2.2, 6.0)
	cam.zoom = Vector2(zoom, zoom)
	var z: Rect2 = map.zones[0]
	cam.position = Vector2(minf(z.end.x - 40.0, map.W * 0.3), map.H * 0.5)
	_clamp_cam()
	_update_visibility(0.0, true)
	hud.build()
	if autoplay:
		start_battle()
		speed = c.get("speed", 4.0)
	else:
		hud.msg("Расстановка: выберите отряд и коснитесь места в зелёной зоне.", Color(0.8, 1.0, 0.7))


func _spawn_army(ids: Array, side: int, defensive: bool) -> void:
	var zone: Rect2 = map.zones[side]
	var face := 0.0 if side == 0 else PI
	var inf: Array = []
	var veh: Array = []
	for id in ids:
		if Data.U[id].cat == "veh":
			veh.append(id)
		else:
			inf.append(id)
	var front_x := zone.end.x - 20.0 if side == 0 else zone.position.x + 20.0
	var back := -1.0 if side == 0 else 1.0
	var k := 0
	for gi in 2:
		var group: Array = inf if gi == 0 else veh
		var n: int = group.size()
		for i in n:
			var id: String = group[i]
			var is_v: bool = Data.U[id].cat == "veh"
			var pos: Vector2
			if defensive and not flags.is_empty():
				var f: Dictionary = flags[k % flags.size()]
				k += 1
				var off := Vector2(back * randf_range(10.0, 55.0), randf_range(-45.0, 45.0))
				if is_v:
					off.x = back * randf_range(40.0, 80.0)
				pos = map.find_cover_near(f.p + off, 20.0, is_v)
			else:
				var depth := 0.0 if gi == 0 else 55.0
				if Data.U[id].cat == "team" or Data.U[id].cat == "gun":
					depth = 25.0
				var y := zone.position.y + (i + 0.5) * zone.size.y / maxf(n, 1)
				pos = Vector2(front_x + back * (depth + randf_range(0.0, 12.0)), y + randf_range(-6.0, 6.0))
			pos = map.nearest_passable(map.clamp_in(pos), is_v)
			add_unit(id, side, pos, face)


func add_unit(id: String, side: int, pos: Vector2, face: float):
	var u := UnitT.new()
	u.battle = self
	u.map = map
	u.uid = next_uid
	next_uid += 1
	units_node.add_child(u)
	u.setup(id, side, pos, face)
	u._take_cover()
	units.append(u)
	return u


func start_battle() -> void:
	if phase != "deploy":
		return
	phase = "battle"
	paused = false
	order_mode = ""
	hud.msg("Бой начался!", Color(1.0, 0.85, 0.5))
	sfx.ui_sound("radio_1", -8.0)
	hud.refresh()


# ===================== Такт =====================

func _process(delta: float) -> void:
	if phase == "battle" and not paused:
		var dt := minf(delta, 0.05) * speed
		var steps := int(ceil(dt / 0.034))
		var sdt := dt / maxf(steps, 1)
		for i in steps:
			_step(sdt)
			if phase != "battle":
				break
	for u in units:
		if u.side != player_side:
			u.visible = (not u.alive and u.is_veh) or autoplay or is_spotted(player_side, u)
		elif not u.alive and not u.is_veh:
			u.visible = false
	overlay.queue_redraw()


func _step(dt: float) -> void:
	sim_time += dt
	time_left -= dt
	for u in units:
		u.tick(dt)
	_separate()
	_update_proj(dt)
	_update_barrages(dt)
	fx.step(dt)
	vis_t -= dt
	if vis_t <= 0.0:
		vis_t = 0.25
		_update_visibility(0.25)
	flag_t -= dt
	if flag_t <= 0.0:
		flag_t = 0.5
		_update_flags(0.5)
	for a in ais:
		a.tick(dt)
	for k in ghosts.keys():
		ghosts[k].t -= dt
		if ghosts[k].t <= 0.0:
			ghosts.erase(k)
	end_t -= dt
	if end_t <= 0.0:
		end_t = 1.0
		_check_end()


func _separate() -> void:
	for i in units.size():
		var a = units[i]
		if not a.is_veh or not a.alive:
			continue
		for j in units.size():
			if i == j:
				continue
			var b = units[j]
			if not b.is_veh:
				continue
			if b.alive and j < i:
				continue
			var d: Vector2 = a.position - b.position
			var need: float = (a.t.len + b.t.len) * 0.42
			var l := d.length()
			if l >= need or l < 0.001:
				continue
			var push := d / l * (need - l)
			if b.alive:
				var pa: Vector2 = a.position + push * 0.5
				var pb: Vector2 = b.position - push * 0.5
				if map.passable(pa, true):
					a.position = pa
				if map.passable(pb, true):
					b.position = pb
			else:
				var pa: Vector2 = a.position + push
				if map.passable(pa, true):
					a.position = pa


# ===================== Видимость =====================

func is_spotted(side: int, e) -> bool:
	return e.side == side or vis[side].has(e.uid)


func conceal(e) -> float:
	var c := 1.0 - map.cover_at(e.position) * 0.55
	if e.is_veh:
		c *= 1.5
		if e.t.get("low", false):
			c *= 0.85
		if e.moving:
			c *= 1.2
	else:
		c *= e.t.get("stealth", 1.0)
		if e.moving:
			c *= 1.3
		elif e.state != UnitT.ST_OK or e.suppression > 25.0:
			c *= 0.85
	if e.since_fire < 3.0:
		c *= 1.3 if e.t.get("stealth", 1.0) < 0.7 else 1.8
	return c


func _update_visibility(dt_pass: float, full := false) -> void:
	vis_pass += 1
	var smokes: Array = fx.blocking_smokes()
	var a_side: Array = []
	var b_side: Array = []
	for u in units:
		if not u.alive:
			continue
		if u.side == 0:
			a_side.append(u)
		else:
			b_side.append(u)
	# линия видимости: каждая пара пересчитывается через проход
	for u in a_side:
		for e in b_side:
			if not full and (u.uid + e.uid + vis_pass) % 2 != 0:
				continue
			var d: float = u.position.distance_to(e.position)
			var l := false
			if d < 720.0:
				l = map.los(u.position, e.position, smokes)
			u.los[e.uid] = l
			e.los[u.uid] = l
	for s in 2:
		var mine: Array = a_side if s == 0 else b_side
		var theirs: Array = b_side if s == 0 else a_side
		var seen := {}
		for e in theirs:
			var c := conceal(e)
			for u in mine:
				if not u.los.get(e.uid, false):
					continue
				var d: float = u.position.distance_to(e.position)
				var rng: float = u.t.spot * c
				if u.state == UnitT.ST_ROUT:
					rng *= 0.5
				if d <= maxf(rng, 40.0):
					seen[e.uid] = true
					break
		var v: Dictionary = vis[s]
		for uid in seen:
			v[uid] = 2.0
		for uid in v.keys():
			if seen.has(uid):
				continue
			v[uid] -= dt_pass
			if v[uid] <= 0.0:
				v.erase(uid)
				if s == player_side:
					var e = _unit_by_uid(uid)
					if e != null and e.alive:
						ghosts[uid] = {"p": e.position, "t": 25.0, "short": e.t.short, "veh": e.is_veh}
		if s == player_side:
			for uid in seen:
				ghosts.erase(uid)
	# погибшие больше не видны: их призраки убираем
	for uid in ghosts.keys():
		var e = _unit_by_uid(uid)
		if e == null or not e.alive:
			ghosts.erase(uid)


func _unit_by_uid(uid: int):
	for u in units:
		if u.uid == uid:
			return u
	return null


# ===================== Стрельба =====================

func _acc(sh, w: Dictionary, d: float) -> float:
	var f := clampf(d / float(w.range), 0.0, 1.0)
	var a := lerpf(w.acc0, w.acc1, pow(f, 0.8))
	if sh.moving:
		if sh.is_veh:
			a *= 0.5 if sh.t.get("stab", false) else 0.25
		else:
			a *= 0.45
	a *= 1.0 - sh.suppression / 100.0 * 0.6
	if sh.is_veh and sh.shaken > 0.0:
		a *= 0.7
	return a


func fire(sh, from: Vector2, wid: String, tgt, aim: Vector2, d: float) -> void:
	var w: Dictionary = Data.W[wid]
	var k: String = w.kind
	var ang := (aim - from).angle()
	match k:
		"sa":
			_fire_sa(sh, from, w, tgt, aim, d)
			fx.flash(from, ang, 0.45 if w.burst > 1 else 0.35)
		"ap":
			if tgt != null and tgt.is_veh:
				_launch_ap(sh, from, wid, w, tgt, d, "shell")
			else:
				_fire_sa(sh, from, w, tgt, aim, d)
			fx.flash(from, ang, 0.7)
			sfx.play("rifle", from, 4.0, 0.7)
		"gun":
			if tgt != null and tgt.is_veh:
				_launch_ap(sh, from, wid, w, tgt, d, "shell")
			else:
				_launch_he(sh, from, wid, w, aim, d, "shell")
			var big: float = w.get("he_r", 4.0)
			fx.flash(from, ang, 1.0 + big * 0.12)
			fx.puff(from, 1.0, 3.0 + big * 0.3, 2.5, Color(0.65, 0.62, 0.55, 0.45), 0.0, 0.3)
			sfx.play(w.snd, from)
		"rocket":
			if tgt != null and tgt.is_veh:
				_launch_ap(sh, from, wid, w, tgt, d, "rocket")
			else:
				_launch_he(sh, from, wid, w, aim, d, "rocket")
			fx.puff(from - Vector2.from_angle(ang) * 1.5, 0.8, 3.0, 2.0, Color(0.7, 0.7, 0.65, 0.5), 0.0, 0.2)
			sfx.play("rocket", from)
		"he":
			_launch_he(sh, from, wid, w, aim, d, "nade")
		"mortar":
			_launch_he(sh, from, wid, w, aim, d, "arc")
			fx.puff(from, 0.5, 2.0, 1.5, Color(0.7, 0.7, 0.65, 0.5), 0.0, 0.2)
			sfx.play("mortar", from)


func _fire_sa(sh, from: Vector2, w: Dictionary, tgt, aim: Vector2, d: float) -> void:
	var burst: int = w.get("burst", 1)
	var base := _acc(sh, w, d)
	var heavy := burst >= 4
	var col := Color(1.0, 0.75, 0.35, 0.9) if heavy else Color(1.0, 0.9, 0.6, 0.35)
	var width := 0.16 if heavy else 0.07
	if burst > 1:
		base *= 0.75  # очередь: каждая пуля менее точна
	var sup_total := 0.0
	for i in burst:
		var end_p := aim + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		if tgt != null and tgt.alive:
			if tgt.is_veh:
				end_p = tgt.position + Vector2(randf_range(-1, 1), randf_range(-1, 1))
				if tgt.t.get("open", false) and randf() < base * 0.1:
					_crew_loss(tgt, sh)
				elif w.get("pen", 0.0) > tgt.armor_toward(from) and randf() < base * 0.06:
					_veh_damage(tgt, sh, true)
				if i == 0:
					fx.hit_spark(end_p, Color(1.0, 0.9, 0.6))
			else:
				var m = _random_man(tgt)
				if m == null:
					break
				end_p = (m.p as Vector2) + Vector2(randf_range(-1.6, 1.6), randf_range(-1.6, 1.6))
				var cov := map.cover_at(m.p)
				if tgt.is_gun and absf(wrapf((from - tgt.position).angle() - tgt.turret, -PI, PI)) < 0.8:
					cov = minf(0.85, cov + 0.35)
				var p := base * (1.0 - cov * 0.8) * (0.6 if m.prone else 1.0) * (0.85 if tgt.moving else 1.0)
				var hit := randf() < p
				sup_total += w.sup * (1.0 - cov * 0.4) * (1.6 if hit else 1.0)
				if hit:
					tgt.kill_man(m, sh)
		else:
			# огонь по площади: подавление всех, кто рядом с точкой
			for e in units:
				if e.side == sh.side or not e.alive or e.is_veh:
					continue
				if e.position.distance_to(aim) < 16.0:
					e.add_sup(w.sup * 0.5)
					for m in e.men:
						if m.alive and (m.p as Vector2).distance_to(end_p) < 2.5 and randf() < 0.05 * (1.0 - map.cover_at(m.p)):
							e.kill_man(m, sh)
		if i < 2 or i % 2 == 0:
			fx.tracer(from, end_p, col, width, 700.0 if heavy else 900.0)
		if randf() < 0.3:
			fx.dust(end_p)
	if tgt != null and sup_total > 0.0:
		tgt.add_sup(sup_total)
	var snd: String = w.snd
	if burst > 1:
		sfx.burst(snd, from, mini(burst, 6), 0.06 if snd == "mg42" else 0.1)
	else:
		sfx.play(snd, from)


func _random_man(u):
	var alive_list: Array = []
	for m in u.men:
		if m.alive:
			alive_list.append(m)
	if alive_list.is_empty():
		return null
	return alive_list[randi() % alive_list.size()]


func _launch_ap(sh, from: Vector2, wid: String, w: Dictionary, tgt, d: float, vis_kind: String) -> void:
	var a := _acc(sh, w, d)
	var sz: float = tgt.t.len * tgt.t.wid
	a *= clampf(sz / 16.0, 0.6, 1.25)
	if tgt.moving:
		a *= 0.75
	var tt := map.terr_at(tgt.position)
	if tt == MapT.FOREST or tt == MapT.SCRUB:
		a *= 0.85
	var hit := randf() < a
	var b: Vector2 = tgt.position + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))
	if not hit:
		var dir := (b - from).normalized()
		b += dir.orthogonal() * randf_range(2.5, 7.0) * (1.0 if randf() < 0.5 else -1.0) + dir * randf_range(-8.0, 18.0)
	var spd: float = w.get("vel", 700.0)
	proj.append({"a": from, "b": b, "t": 0.0, "dur": maxf(0.05, from.distance_to(b) / spd), "vis": vis_kind,
		"w": wid, "sh": sh, "tgt": tgt, "hit": hit, "ap": true, "d": d, "from": from, "side": sh.side})


func _launch_he(sh, from: Vector2, wid: String, w: Dictionary, aim: Vector2, d: float, vis_kind: String) -> void:
	var scatter := 0.0
	var dur := 0.0
	var spd: float = w.get("vel", 600.0)
	match vis_kind:
		"arc":
			scatter = d * 0.06 * (1.0 + sh.suppression / 100.0)
			dur = 2.0 + d / spd
		"nade":
			scatter = 2.0 + d * 0.08
			dur = 0.9
		_:
			scatter = lerpf(1.0, 9.0, d / 1000.0) * (2.5 if sh.moving else 1.0)
			dur = d / spd
	var b := map.clamp_in(aim + Vector2.from_angle(randf() * TAU) * randf() * scatter)
	proj.append({"a": from, "b": b, "t": 0.0, "dur": maxf(0.05, dur), "vis": vis_kind, "w": wid, "sh": sh,
		"tgt": null, "hit": false, "ap": false, "d": d, "from": from, "side": sh.side})


func _update_proj(dt: float) -> void:
	if proj.is_empty():
		return
	var rest: Array = []
	var done: Array = []
	for pr in proj:
		pr.t += dt
		if pr.t >= pr.dur:
			done.append(pr)
		else:
			rest.append(pr)
		if pr.vis == "rocket" and randf() < 0.5:
			fx.puff((pr.a as Vector2).lerp(pr.b, pr.t / pr.dur), 0.4, 1.4, 1.2, Color(0.75, 0.75, 0.7, 0.4), 0.0, 0.2)
	proj = rest
	for pr in done:
		_impact(pr)


func _impact(pr: Dictionary) -> void:
	var w: Dictionary = Data.W[pr.w]
	if pr.ap:
		var tgt = pr.tgt
		if pr.hit and tgt != null:
			if tgt.alive:
				_resolve_pen(pr, tgt)
			else:
				fx.hit_spark(pr.b)
		else:
			fx.boom(pr.b, 1.5)
			sfx.play("impact_ground", pr.b)
		if w.kind == "rocket":
			_explode(pr.b, pr.w, pr.sh, false)
	else:
		_explode(pr.b, pr.w, pr.sh, true)


func _resolve_pen(pr: Dictionary, tgt) -> void:
	var from: Vector2 = pr.from
	var arm: float = tgt.armor_toward(from)
	var pen := Data.pen_at(pr.w, pr.d) * randf_range(0.88, 1.12)
	var p: Vector2 = pr.b
	if pen >= arm:
		sfx.play("hit_pen", p)
		fx.hit_spark(p, Color(1.0, 0.6, 0.2))
		fx.boom(p, 1.2)
		_veh_damage(tgt, pr.sh, false)
	else:
		sfx.play("ricochet" if randf() < 0.5 else "hit_nopen", p)
		fx.hit_spark(p, Color(1.0, 1.0, 0.85))
		tgt.shaken = maxf(tgt.shaken, 2.0)
		if tgt.side == player_side:
			unit_note(tgt, "рикошет")


func _veh_damage(v, killer, light: bool) -> void:
	if not v.alive:
		return
	var r := randf()
	if light:
		r = 0.55 + randf() * 0.45
	if r < 0.5:
		_destroy_veh(v, killer)
	elif r < 0.64:
		if not v.immobile:
			v.immobile = true
			v.path.clear()
			unit_note(v, "обездвижен!")
		else:
			_crew_loss(v, killer)
	elif r < 0.77 and v.t.gun != "":
		if not v.gun_broken:
			v.gun_broken = true
			unit_note(v, "орудие выведено из строя!")
		else:
			_crew_loss(v, killer)
	else:
		_crew_loss(v, killer)


func _crew_loss(v, killer) -> void:
	if not v.alive:
		return
	v.crew -= 1
	v.shaken = 6.0
	losses[v.side].men += 1
	if v.crew <= 1:
		unit_note(v, "экипаж покинул машину")
		v.die(killer)
	else:
		unit_note(v, "потери в экипаже")


func _destroy_veh(v, killer) -> void:
	v.die(killer)
	fx.burn(v.position, randf_range(25.0, 70.0))
	fx.boom(v.position, 5.0)
	decals.burn_mark(v.position, v.t.len * 0.6)
	sfx.play("explosion", v.position, 2.0, 0.9)


func _explode(p: Vector2, wid: String, src, hit_veh: bool) -> void:
	var w: Dictionary = Data.W[wid]
	var r: float = w.get("he_r", 3.0)
	var k: float = w.get("he_k", 0.3)
	fx.boom(p, r * 0.6)
	decals.crater(p, r * 0.22 + 0.5)
	if r >= 6.0:
		map.add_crater(p, r * 0.3)
	if r >= 6.0:
		sfx.play("explosion", p, minf(0.0, (r - 12.0) * 0.6), clampf(1.4 - r * 0.04, 0.8, 1.3))
	else:
		sfx.play("nade", p, -2.0)
	var src_side: int = src.side if src != null else -1
	var killer = src
	for u in units:
		if not u.alive:
			continue
		var d: float = u.position.distance_to(p)
		if d > r * 3.0 + 12.0:
			continue
		var kl = killer if u.side != src_side else null
		if u.is_veh:
			if not hit_veh:
				continue
			if d < u.radius() + r * 0.3:
				var hep: float = w.get("he_pen", r * 2.2)
				var arm: float = minf(u.t.armor[1], u.t.armor[2]) * 0.8
				if u.t.get("open", false) and randf() < k * 0.6:
					_crew_loss(u, kl)
				elif hep >= arm and randf() < 0.5:
					_veh_damage(u, kl, true)
				else:
					u.shaken = maxf(u.shaken, 3.0)
			continue
		var sup_add: float = w.sup * clampf(1.0 - d / (r * 3.0 + 12.0), 0.0, 1.0)
		u.add_sup(sup_add * (1.0 - map.cover_at(u.position) * 0.3))
		for m in u.men:
			if not m.alive:
				continue
			var dm: float = (m.p as Vector2).distance_to(p)
			if dm > r * 1.3:
				continue
			var cov := map.cover_at(m.p)
			var pk := k * (1.0 - dm / (r * 1.3)) * (1.0 - cov * 0.6) * (0.65 if m.prone else 1.0)
			if randf() < pk:
				u.kill_man(m, kl)


# ===================== Артиллерия =====================

func call_arty(side: int, p: Vector2, kind: String) -> bool:
	var idx := 0 if kind == "he" else 1
	if arty[side][idx] <= 0 or phase != "battle":
		return false
	arty[side][idx] -= 1
	barrages.append({"p": p, "side": side, "kind": kind, "delay": ARTY_DELAY if kind == "he" else 8.0,
		"n": 10 if kind == "he" else 6, "iv": 0.0})
	if side == player_side:
		hud.msg("Артиллерия: заявка принята, %d с до залпа." % int(ARTY_DELAY if kind == "he" else 8.0), Color(1.0, 0.85, 0.5))
		sfx.ui_sound("radio_2", -8.0)
	else:
		hud.msg("Противник вызвал артиллерию!", Color(1.0, 0.55, 0.45))
	return true


func _update_barrages(dt: float) -> void:
	for b in barrages:
		b.delay -= dt
		if b.delay > 0.0:
			continue
		b.iv -= dt
		if b.iv <= 0.0 and b.n > 0:
			b.iv = randf_range(0.4, 1.1)
			b.n -= 1
			var spread := 28.0 if b.kind == "he" else 16.0
			var q := map.clamp_in(b.p + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * spread)
			if b.kind == "he":
				proj.append({"a": q + Vector2(25, -70), "b": q, "t": 0.0, "dur": 0.45, "vis": "arc", "w": "art105",
					"sh": null, "tgt": null, "hit": false, "ap": false, "d": 0.0, "from": q, "side": b.side})
				sfx.play("whiz", q, 2.0)
			else:
				fx.smoke_screen(q)
				sfx.play("pop", q)
	barrages = barrages.filter(func(b): return b.n > 0)


# ===================== Точки и итог =====================

func _update_flags(dt: float) -> void:
	for f in flags:
		var c := [0, 0]
		for u in units:
			if u.effective() and u.position.distance_to(f.p) < FLAG_R:
				c[u.side] += 1
		f.contested = c[0] > 0 and c[1] > 0
		var dir := 0
		if c[0] > 0 and c[1] == 0:
			dir = -1
		elif c[1] > 0 and c[0] == 0:
			dir = 1
		if dir == 0:
			continue
		var n: int = c[0] if dir < 0 else c[1]
		f.prog = clampf(f.prog + dir * dt / 14.0 * (1.0 + mini(n - 1, 2) * 0.25), -1.0, 1.0)
		var was: int = f.owner
		if f.prog <= -1.0:
			f.owner = 0
		elif f.prog >= 1.0:
			f.owner = 1
		elif (f.owner == 0 and f.prog > 0.0) or (f.owner == 1 and f.prog < 0.0):
			f.owner = -1
		if was != f.owner:
			if f.owner >= 0:
				var mine: bool = f.owner == player_side
				hud.msg("Точка %s %s" % [f.name, "захвачена!" if mine else "потеряна — её занял противник!"],
					Color(0.6, 0.9, 1.0) if mine else Color(1.0, 0.55, 0.45))
				sfx.ui_sound("capture", -6.0)
			elif was == player_side:
				hud.msg("Точка %s: противник сбивает флаг!" % f.name, Color(1.0, 0.7, 0.5))


func flags_owned(side: int) -> int:
	var n := 0
	for f in flags:
		if f.owner == side:
			n += 1
	return n


func score(side: int) -> int:
	return flags_owned(side) * 150 + int(losses[1 - side].cost)


func _check_end() -> void:
	var eff := [0, 0]
	var alive_n := [0, 0]
	for u in units:
		if u.alive:
			alive_n[u.side] += 1
			if u.state != UnitT.ST_ROUT:
				eff[u.side] += 1
	if alive_n[1] == 0 or (eff[1] == 0 and sim_time > 30.0):
		_end(0, "Противник разгромлен")
		return
	if alive_n[0] == 0 or (eff[0] == 0 and sim_time > 30.0):
		_end(1, "Ваши силы разгромлены")
		return
	for s in 2:
		if flags_owned(s) == flags.size():
			hold_all[s] += 1.0
		else:
			hold_all[s] = 0.0
		if hold_all[s] >= 120.0:
			_end(s, "Все точки удерживаются две минуты")
			return
	if time_left <= 0.0:
		var a := score(0)
		var b := score(1)
		var mode: String = cfg.scenario.mode
		if mode == "defend" and flags_owned(0) > 0:
			_end(0, "Рубеж удержан до конца")
		elif a > b:
			_end(0, "Время вышло — перевес по очкам")
		elif b > a:
			_end(1, "Время вышло — противник набрал больше очков")
		else:
			_end(-1, "Время вышло — равный счёт")


func _end(winner: int, reason: String) -> void:
	if phase == "over":
		return
	phase = "over"
	paused = false
	result = {"winner": winner, "reason": reason, "score": [score(0), score(1)], "losses": losses,
		"flags": [flags_owned(0), flags_owned(1)], "time": sim_time,
		"start": [cfg.army.size(), cfg.enemy_army.size()]}
	var kills := 0
	for u in units:
		if u.side == 0:
			kills += u.kills
	result["kills"] = kills
	hud.show_result(result)
	sfx.ui_sound("radio_1", -6.0)


func surrender() -> void:
	_end(1, "Вы отступили с поля боя")


func leave() -> void:
	finished.emit(result)


# ===================== События подразделений =====================

func on_man_killed(u, m: Dictionary, _killer) -> void:
	decals.body(m.p, m.face + randf_range(-0.6, 0.6), u.fac.cloth)
	losses[u.side].men += 1
	u.add_sup(6.0)


func on_unit_destroyed(u, killer) -> void:
	losses[u.side].cost += int(u.t.cost)
	losses[u.side].units += 1
	if u.is_veh:
		losses[u.side].veh += 1
	if killer != null and killer.side != u.side:
		killer.kills += 1
	selection.erase(u)
	var mine: bool = u.side == player_side
	if mine or is_spotted(player_side, u) or u.is_veh:
		hud.msg(("Потерян: %s" if mine else "Уничтожен: %s") % u.t.name,
			Color(1.0, 0.55, 0.45) if mine else Color(0.65, 1.0, 0.6))
	hud.refresh()


func unit_note(u, text: String) -> void:
	if u.side == player_side:
		hud.msg("%s: %s" % [u.t.name, text], Color(1.0, 0.9, 0.6))
	elif is_spotted(player_side, u) and (u.is_veh or text.begins_with("отступ")):
		hud.msg("Противник (%s): %s" % [u.t.name, text], Color(0.75, 0.95, 0.7))


# ===================== Выделение и приказы =====================

func select_only(u) -> void:
	selection = [u]
	hud.refresh()


func toggle_select(u) -> void:
	if selection.has(u):
		selection.erase(u)
	else:
		selection.append(u)
	hud.refresh()


func select_all() -> void:
	selection = []
	for u in units:
		if u.side == player_side and u.alive:
			selection.append(u)
	hud.refresh()


func clear_selection() -> void:
	selection = []
	order_mode = ""
	hud.refresh()


func set_order_mode(m: String) -> void:
	order_mode = "" if order_mode == m else m
	hud.refresh()


func order_stop() -> void:
	for u in selection:
		u.order_stop()
	order_mode = ""
	hud.refresh()


func toggle_hold() -> void:
	var v := true
	for u in selection:
		if u.hold_fire:
			v = false
	for u in selection:
		u.hold_fire = v
	hud.msg("Режим засады: огонь только с близкой дистанции." if v else "Огонь по готовности.", Color(0.85, 0.95, 1.0))
	hud.refresh()


func _group_move(wp: Vector2, mode: int, pts := PackedVector2Array()) -> void:
	var c := Vector2.ZERO
	for u in selection:
		c += u.position
	c /= maxf(selection.size(), 1)
	var any := false
	for u in selection:
		var off := Vector2.ZERO
		if selection.size() > 1:
			off = u.position - c
			if off.length() > 35.0:
				off = off.normalized() * 35.0
		var m := mode
		if m == UnitT.MV_BACK and not u.is_veh:
			m = UnitT.MV_MOVE
		var ok: bool
		if pts.size() > 0:
			var shifted := PackedVector2Array()
			for p in pts:
				shifted.append(map.clamp_in(p + off))
			ok = u.order_path(shifted, m)
		else:
			ok = u.order_move(map.clamp_in(wp + off), m)
		if ok:
			u.forced = null
			u.area = Vector2.INF
			any = true
	if any:
		overlay.ping(wp, Color(0.5, 1.0, 0.5) if mode == UnitT.MV_MOVE else Color(1.0, 0.75, 0.3))


func _deploy_place(wp: Vector2) -> void:
	var z: Rect2 = map.zones[player_side]
	var c := Vector2.ZERO
	for u in selection:
		c += u.position
	c /= maxf(selection.size(), 1)
	for u in selection:
		var off: Vector2 = (u.position - c) if selection.size() > 1 else Vector2.ZERO
		if off.length() > 40.0:
			off = off.normalized() * 40.0
		var p := wp + off
		p.x = clampf(p.x, z.position.x + 2.0, z.end.x - 2.0)
		p.y = clampf(p.y, z.position.y + 2.0, z.end.y - 2.0)
		p = map.nearest_passable(p, u.is_veh)
		if not z.has_point(p):
			continue
		u.position = p
		u.path.clear()
		u._make_formation()
		u._take_cover()
		for i in u.men.size():
			u.men[i].p = u.men[i].slot
	overlay.ping(wp, Color(0.6, 1.0, 0.6))


# ===================== Камера и касания =====================

func vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func to_world(sp: Vector2) -> Vector2:
	return cam.position + (sp - vp_size() * 0.5) / zoom


func to_screen(wp: Vector2) -> Vector2:
	return (wp - cam.position) * zoom + vp_size() * 0.5


func _clamp_cam() -> void:
	cam.position.x = clampf(cam.position.x, 0.0, map.W)
	cam.position.y = clampf(cam.position.y, 0.0, map.H)


func zoom_limits() -> Vector2:
	var vp := vp_size()
	return Vector2(minf(vp.x / map.W, vp.y / map.H) * 0.95, 16.0)


func set_zoom(z: float, anchor: Vector2) -> void:
	var lim := zoom_limits()
	var before := to_world(anchor)
	zoom = clampf(z, lim.x, lim.y)
	cam.zoom = Vector2(zoom, zoom)
	cam.position += before - to_world(anchor)
	_clamp_cam()


func center_on(p: Vector2) -> void:
	cam.position = p
	_clamp_cam()


func _unhandled_input(ev: InputEvent) -> void:
	if map == null:
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.15, ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.15, ev.position)
		return
	if ev is InputEventScreenTouch:
		_touch(ev)
	elif ev is InputEventScreenDrag:
		_drag(ev)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_ESCAPE:
				clear_selection()


func _touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		if hud.blocks(ev.position):
			return
		touches[ev.index] = {"start": ev.position, "pos": ev.position, "t0": Time.get_ticks_msec(), "moved": 0.0,
			"mode": "tap"}
		if touches.size() >= 2:
			var ks := touches.keys()
			var a: Vector2 = touches[ks[0]].pos
			var b: Vector2 = touches[ks[1]].pos
			pinch = {"d0": maxf(a.distance_to(b), 1.0), "z0": zoom, "mid": (a + b) * 0.5}
			for k in touches:
				touches[k].mode = "pinch"
			drag_path = PackedVector2Array()
		elif phase != "over" and _own_selected_at(to_world(ev.position)):
			touches[ev.index].mode = "path_pending"
		return
	if not touches.has(ev.index):
		return
	var tc: Dictionary = touches[ev.index]
	touches.erase(ev.index)
	var wp := to_world(ev.position)
	match tc.mode:
		"tap", "path_pending":
			if tc.moved < 16.0:
				if Time.get_ticks_msec() - int(tc.t0) > 450:
					_long_press(wp)
				else:
					_tap(wp)
		"path":
			_finish_path()
	if touches.is_empty():
		pinch = {}


func _drag(ev: InputEventScreenDrag) -> void:
	if not touches.has(ev.index):
		return
	var tc: Dictionary = touches[ev.index]
	tc.pos = ev.position
	tc.moved = maxf(tc.moved, ev.position.distance_to(tc.start))
	if touches.size() >= 2 and not pinch.is_empty():
		var ks := touches.keys()
		var a: Vector2 = touches[ks[0]].pos
		var b: Vector2 = touches[ks[1]].pos
		var mid := (a + b) * 0.5
		var before := to_world(pinch.mid)
		set_zoom(pinch.z0 * a.distance_to(b) / pinch.d0, mid)
		cam.position += before - to_world(mid)
		_clamp_cam()
		pinch.mid = mid
		pinch.z0 = zoom
		pinch.d0 = maxf(a.distance_to(b), 1.0)
		return
	if tc.mode == "pinch":
		return
	if tc.mode == "path_pending" and tc.moved > 16.0:
		tc.mode = "path"
		drag_path = PackedVector2Array([to_world(tc.start)])
	if tc.mode == "path":
		var wp := to_world(ev.position)
		if drag_path.is_empty() or drag_path[drag_path.size() - 1].distance_to(wp) > 5.0:
			drag_path.append(map.clamp_in(wp))
	elif tc.moved > 16.0:
		tc.mode = "pan"
		cam.position -= ev.relative / zoom
		_clamp_cam()


func _own_selected_at(wp: Vector2) -> bool:
	if phase == "deploy":
		return false
	var u = _unit_at(wp, player_side)
	return u != null and selection.has(u)


func _finish_path() -> void:
	var pts := drag_path
	drag_path = PackedVector2Array()
	if pts.size() < 2 or selection.is_empty():
		return
	# прореживаем: точка каждые ~12 м
	var out := PackedVector2Array()
	var last := pts[0]
	for i in range(1, pts.size()):
		if pts[i].distance_to(last) > 12.0 or i == pts.size() - 1:
			out.append(pts[i])
			last = pts[i]
	var mode := UnitT.MV_MOVE
	if order_mode == "fast":
		mode = UnitT.MV_FAST
	elif order_mode == "back":
		mode = UnitT.MV_BACK
	_group_move(out[out.size() - 1], mode, out)
	if order_mode in ["fast", "back"]:
		order_mode = ""
	hud.refresh()


func _unit_at(wp: Vector2, side: int):
	var best = null
	var best_d := INF
	var pick := maxf(24.0 / zoom, 2.5)
	for u in units:
		if u.side != side or not u.alive:
			continue
		if side != player_side and not is_spotted(player_side, u):
			continue
		var d: float = u.position.distance_to(wp)
		var lim: float = maxf(u.radius() + 1.0, pick) if u.is_veh else maxf(8.0, pick)
		if not u.is_veh:
			for m in u.men:
				if m.alive:
					d = minf(d, (m.p as Vector2).distance_to(wp) + 2.0)
		if d < lim and d < best_d:
			best_d = d
			best = u
	return best


func _tap(wp: Vector2) -> void:
	if phase == "over":
		return
	if order_mode == "arty" or order_mode == "smoke":
		if call_arty(player_side, wp, "he" if order_mode == "arty" else "smoke"):
			overlay.ping(wp, Color(1.0, 0.4, 0.3))
		order_mode = ""
		hud.refresh()
		return
	var own = _unit_at(wp, player_side)
	if phase == "deploy":
		if own != null:
			select_only(own)
		elif not selection.is_empty():
			_deploy_place(wp)
		return
	var enemy = _unit_at(wp, 1 - player_side)
	if order_mode == "fire":
		for u in selection:
			if enemy != null:
				u.order_target(enemy)
			else:
				u.order_area(wp)
		overlay.ping(wp, Color(1.0, 0.35, 0.3))
		order_mode = ""
		hud.refresh()
		return
	if order_mode == "face":
		for u in selection:
			u.order_face(wp)
		overlay.ping(wp, Color(0.6, 0.85, 1.0))
		order_mode = ""
		hud.refresh()
		return
	if own != null:
		select_only(own)
		return
	if selection.is_empty():
		return
	if enemy != null:
		for u in selection:
			u.order_target(enemy)
		overlay.ping(enemy.position, Color(1.0, 0.35, 0.3))
		hud.refresh()
		return
	var mode := UnitT.MV_MOVE
	if order_mode == "fast":
		mode = UnitT.MV_FAST
	elif order_mode == "back":
		mode = UnitT.MV_BACK
	_group_move(wp, mode)
	if order_mode in ["fast", "back"]:
		order_mode = ""
	hud.refresh()


func _long_press(wp: Vector2) -> void:
	if phase == "over":
		return
	var own = _unit_at(wp, player_side)
	if own != null:
		toggle_select(own)
		return
	if phase == "battle" and not selection.is_empty():
		for u in selection:
			u.order_face(wp)
		overlay.ping(wp, Color(0.6, 0.85, 1.0))


func toggle_pause() -> void:
	if phase == "battle":
		paused = not paused
		hud.refresh()


func cycle_speed() -> void:
	speed = 2.0 if speed == 1.0 else (3.0 if speed == 2.0 else 1.0)
	hud.refresh()
