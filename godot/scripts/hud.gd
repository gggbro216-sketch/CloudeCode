extends Control
## HUD боя: мультитач-управление, прицел, таблички над танками, миникарта, переговоры по рации,
## счёт и режим, а также окна брифинга, паузы, гибели и итогов боя.

const Prof = preload("res://scripts/prof.gd")
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Gfx = preload("res://scripts/gfx.gd")
const XRayScript = preload("res://scripts/xray.gd")
const TankScript = preload("res://scripts/tank.gd")
const SR := 90.0  # радиус джойстика

var battle  # battle.gd (без типа, чтобы не было циклической загрузки)
var font: Font

# управление
var move := Vector2.ZERO
var move_idx := -1
var move_o := Vector2.ZERO
var move_p := Vector2.ZERO
var aim_idx := -1
var aim_last := Vector2.ZERO
var aim_start := Vector2.ZERO
var aim_t0 := 0
var aim_moved := 0.0
var cam_d := Vector2.ZERO
var dragging := false
var fire_idx := -1
var fire_req := false
var auto_aim := true
var abil_c := {}  # кнопки ударов и приказов: имя → центр
var range_r: Array = []  # «Реализм»: кнопки дальности [прямоугольник, шаг в метрах]

# раскладка (пересчитывается каждый кадр)
var margins := Vector4.ZERO
var fire_c := Vector2.ZERO
var fire_r := 76.0
var auto_rect := Rect2()
var pause_c := Vector2.ZERO
var zoom_c := Vector2.ZERO
var thr_rect := Rect2()  # самолёт: ползунок газа слева, как в War Thunder Mobile
var thr_idx := -1
var cons_c := {}  # снаряжение → центр кнопки
var ammo_r: Array = []  # кнопки снарядов: [прямоугольник, номер в боекомплекте]

var feed: Array = []
var radio_lines: Array = []  # {cs, text, tr, t}
var alerts: Array = []  # сообщения о повреждениях своего танка: {text, col, t}
var col_ally := Color(D.ALLY)
var col_foe := Color(D.FOE)
var col_amber := Color(D.AMBER)
var col_text := Color(UI.TEXT)
var col_dim := Color(UI.DIM)
var sb_panel := UI.box("0a0c08", UI.LINE, 1, 8, 0.62, 0.0)
var mini_tex: ImageTexture  # неподвижный слой миникарты, запекается один раз за бой
# Интерфейс в два слоя: быстрый (прицел, метки над танками, миникарта, кнопки) рисуется каждый кадр,
# медленный (счёт и таймер, лента событий, рация, прочность и модули) — 10 раз в секунду.
var cv: CanvasItem = self  # на чём сейчас рисуем
var slow: Control
var slow_t := 0.0
var xray: Control  # рентген попадания (xray.gd)

var brief_box: Control
var dead_box: Control
var ffwd_btn: Button
var pause_box: Control
var result_box: Control
var res_title: Label
var res_reason: Label
var res_stats: HBoxContainer
var res_table: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	font = ThemeDB.fallback_font
	slow = Control.new()
	slow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slow.draw.connect(_draw_slow)
	add_child(slow)
	xray = XRayScript.new()
	add_child(xray)
	Gfx.warm([sb_panel, _sb("0a0c08", D.AMBER, 2, 22, 0.6), _sb("0a0c08", UI.LINE, 2, 22, 0.6)])
	_build_dead()
	_build_pause()
	_build_result()


var _sbs := {}  # рамки, которые рисуются каждый кадр, — по одной на набор цветов


func _sb(bg: String, border: String, bw: int, radius: int, alpha: float) -> StyleBoxFlat:
	var k := "%s|%s|%d|%d|%s" % [bg, border, bw, radius, alpha]
	if not _sbs.has(k):
		_sbs[k] = UI.box(bg, border, bw, radius, alpha, 0.0)
	return _sbs[k]


func team_color(team: int) -> Color:
	return col_ally if team == 0 else col_foe


func add_feed(parts: Array) -> void:
	feed.append({"parts": parts, "t": 4.5})
	slow_t = 0.0
	while feed.size() > 4:
		feed.pop_front()


## Сообщение о своём танке («ДВИГАТЕЛЬ ПОВРЕЖДЁН») над полосой прочности.
func alert(text: String, col: Color) -> void:
	for a in alerts:
		if a.text == text:
			a.t = 2.8
			return
	alerts.append({"text": text, "col": col, "t": 2.8})
	slow_t = 0.0
	while alerts.size() > 3:
		alerts.pop_front()


## Переговоры: позывной, фраза на языке стороны и перевод (пустой для русского).
func add_radio(cs: String, text: String, tr: String) -> void:
	radio_lines.append({"cs": cs, "text": text, "tr": tr, "t": 7.0})
	slow_t = 0.0
	while radio_lines.size() > 3:
		radio_lines.pop_front()


func take_cam_delta() -> Vector2:
	var v := cam_d
	cam_d = Vector2.ZERO
	return v


func fire_held() -> bool:
	return fire_idx != -1 or Input.is_key_pressed(KEY_SPACE)


func reset_input() -> void:
	move_idx = -1
	thr_idx = -1
	aim_idx = -1
	fire_idx = -1
	move = Vector2.ZERO
	dragging = false
	fire_req = false
	cam_d = Vector2.ZERO


# ---------- Касания ----------

func _input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if not e.pressed:
			if e.index == move_idx:
				move_idx = -1
				move = Vector2.ZERO
			elif e.index == thr_idx:
				thr_idx = -1
			elif e.index == aim_idx:
				aim_idx = -1
				dragging = false
				if Time.get_ticks_msec() - aim_t0 < 240 and aim_moved < 14.0:
					fire_req = true
			elif e.index == fire_idx:
				fire_idx = -1
			return
		if battle.paused or battle.over:
			return
		var p := e.position
		if p.distance_to(pause_c) < 46.0:
			battle.set_paused(true)
			get_viewport().set_input_as_handled()
			return
		if not battle.player.alive and battle.fly_id < 0:
			return  # наблюдение: касания достаются кнопке «Ускорить»
		if p.distance_to(fire_c) < fire_r + 14.0:
			fire_idx = e.index
			fire_req = true
			return
		if battle.fly_id >= 0 and thr_rect.grow(34.0).has_point(p):
			thr_idx = e.index
			_thr_set(p.y)
			return
		for rr: Array in range_r:
			if (rr[0] as Rect2).grow(6.0).has_point(p):
				battle.range_set = clampf(battle.range_set + float(rr[1]), 50.0, 600.0)
				return
		if auto_rect.grow(10.0).has_point(p) and not battle.realism and battle.fly_id < 0:
			auto_aim = not auto_aim
			return
		for an in abil_c:
			if p.distance_to(abil_c[an]) < (52.0 if battle.fly_id >= 0 and an == "arty" else 32.0):
				if battle.fly_id >= 0:
					# в самолёте те же кнопки: бомбы, посадка по автопилоту, вернуться в танк
					match an:
						"arty":
							battle.fly_bomb = true
						"air":
							battle.fly_land = not battle.fly_land
						"follow":
							battle.fly_leave()
					return
				match an:
					"plane":
						battle.take_off(0, 15.0)
					"arty":
						battle.call_strike(0)
					"air":
						battle.call_strike(1)
					"follow":
						battle.give_order(1)
					"hold":
						battle.give_order(2)
					"attack":
						battle.give_order(3)
				return
		if p.distance_to(zoom_c) < 50.0 and battle.fly_id < 0:
			battle.toggle_sniper()
			return
		for c in cons_c:
			if p.distance_to(cons_c[c]) < 36.0:
				battle.use_cons(c)
				return
		for ab: Array in ammo_r:
			if (ab[0] as Rect2).grow(6.0).has_point(p):
				battle.pick_ammo(int(ab[1]))
				return
		if p.x < size.x * 0.5:
			if move_idx == -1:
				move_idx = e.index
				move_o = p
				move_p = p
				move = Vector2.ZERO
		elif aim_idx == -1:
			aim_idx = e.index
			aim_last = p
			aim_start = p
			aim_t0 = Time.get_ticks_msec()
			aim_moved = 0.0
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and not battle.paused and not battle.over:
			match k.keycode:
				KEY_G:
					battle.call_strike(0)
				KEY_H:
					battle.call_strike(1)
				KEY_Z:
					battle.give_order(1)
				KEY_X:
					battle.give_order(2)
				KEY_C:
					battle.give_order(3)
				KEY_BRACKETLEFT:
					battle.range_set = clampf(battle.range_set - 50.0, 50.0, 600.0)
				KEY_BRACKETRIGHT:
					battle.range_set = clampf(battle.range_set + 50.0, 50.0, 600.0)
		var keys := {KEY_1: "repair", KEY_2: "medkit", KEY_3: "ext"}
		if k.pressed and not k.echo and keys.has(k.keycode):
			battle.use_cons(keys[k.keycode])
		elif k.pressed and not k.echo and k.keycode >= KEY_4 and k.keycode <= KEY_8 and not battle.paused and not battle.over:
			battle.pick_ammo(k.keycode - KEY_4)
		elif k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.keycode == KEY_P):
			# пауза с клавиатуры (на ПК — в том числе в браузере)
			if battle.loaded and not battle.over and not battle.briefing:
				battle.set_paused(not battle.paused)
		elif k.pressed and not k.echo and k.keycode == KEY_SHIFT and not battle.paused and not battle.over:
			battle.toggle_sniper()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		# правая кнопка мыши — снайперский прицел
		if (event as InputEventMouseButton).pressed and not battle.paused and not battle.over and not battle.briefing:
			battle.toggle_sniper()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if e.index == thr_idx:
			_thr_set(e.position.y)
		elif e.index == move_idx:
			move_p = e.position
			var d := move_p - move_o
			if d.length() > SR:
				d = d.normalized() * SR
			move = d / SR
		elif e.index == aim_idx:
			cam_d += e.position - aim_last
			aim_last = e.position
			aim_moved = maxf(aim_moved, e.position.distance_to(aim_start))
			if aim_moved > 8.0:
				dragging = true


# Кружок прицела: точку падения снаряда логика считает 30 раз в секунду, а рисуется она каждый
# кадр — плавно догоняет новую точку, иначе при повороте пальцем кружок скачет ступеньками.
var gun_s := Vector3.ZERO
var gun_has := false
var disp_s := 0.0


func _process(delta: float) -> void:
	var _tp0 := Time.get_ticks_usec() if Prof.on else 0
	_process_body(delta)
	if Prof.on:
		Prof.add("hud._process", _tp0)


func _process_body(delta: float) -> void:
	if battle and battle.gun_point != null:
		var k := 1.0 - exp(-delta * 22.0)
		var gp: Vector3 = battle.gun_point
		if not gun_has or gun_s.distance_to(gp) > 600.0:
			gun_s = gp
			disp_s = float(battle.watch.disp)
		gun_s = gun_s.lerp(gp, k)
		disp_s = lerpf(disp_s, float(battle.watch.disp), k)
		gun_has = true
	else:
		gun_has = false
	margins = UI.safe(self)
	var s := size
	if xray.visible:
		xray.position = Vector2(s.x - xray.size.x - 14.0 - margins.z, 86.0 + margins.y)
	var r := 18.0 + margins.z
	var bt := 14.0 + margins.w
	pause_c = Vector2(s.x - r - 32.0, 14.0 + margins.y + 32.0)
	fire_c = Vector2(s.x - r - 96.0, s.y - bt - 104.0)
	auto_rect = Rect2(fire_c.x - 60.0, fire_c.y - fire_r - 62.0, 120.0, 44.0)
	zoom_c = Vector2(fire_c.x - fire_r - 64.0, fire_c.y + 26.0)
	ammo_r.clear()
	if battle and battle.ammo_list.size() > 1:
		# снаряды — ряд над кнопкой «АВТО», справа налево
		var bw := 66.0
		var x0 := s.x - r - 8.0 - bw
		for k in range(battle.ammo_list.size() - 1, -1, -1):
			ammo_r.append([Rect2(x0, auto_rect.position.y - 64.0, bw - 6.0, 44.0), k])
			x0 -= bw
	cons_c.clear()
	if battle and battle.player:
		var x := zoom_c.x - 84.0
		for c in ["ext", "medkit", "repair"]:
			if battle.player.cons.has(c):
				cons_c[c] = Vector2(x, s.y - bt - 36.0)
				x -= 66.0
	abil_c.clear()
	range_r.clear()
	if battle and battle.player and battle.core_world:
		# удары — продолжают ряд снаряжения; приказы — столбик слева под рацией
		var ax := zoom_c.x - 84.0
		# вызов звена штурмовиков убран: авиация — только собственный вылет («САМОЛЁТ»)
		abil_c["arty"] = Vector2(ax, s.y - bt - 36.0 - 84.0)
		var oy := 12.0 + margins.y + 170.0 + 150.0
		for o in ["follow", "hold", "attack", "plane"]:
			if o == "plane" and (battle.sorties <= 0 or battle.fly_id >= 0 or battle.fly_wait > 0.0):
				continue
			if battle.fly_id >= 0 and (o == "hold" or o == "attack"):
				continue  # в самолёте слева остаётся одна кнопка — вернуться в танк
			abil_c[o] = Vector2(14.0 + margins.x + 34.0, oy)
			oy += 58.0
		if battle.fly_id >= 0:
			# самолёт: справа — пушки (большая кнопка), бомбы и посадка; слева — «в танк» и ползунок газа
			ammo_r.clear()
			cons_c.clear()
			# пушки — под правым пальцем, бомбы — под левым (рядом с газом), как в War Thunder Mobile
			var top: float = (abil_c["follow"] as Vector2).y + 62.0 if abil_c.has("follow") else s.y * 0.42
			thr_rect = Rect2(14.0 + margins.x + 16.0, top, 46.0, maxf(120.0, s.y - bt - 34.0 - top))
			abil_c["arty"] = Vector2(thr_rect.end.x + 112.0, s.y - bt - 84.0)
			abil_c["air"] = Vector2(zoom_c.x - 10.0, zoom_c.y - 42.0)
		if battle.realism:
			auto_aim = false
			range_r.append([Rect2(auto_rect.position.x - 4.0, auto_rect.position.y, 56.0, 44.0), -50.0])
			range_r.append([Rect2(auto_rect.position.x + 68.0, auto_rect.position.y, 56.0, 44.0), 50.0])
	for f in feed:
		f.t -= delta
	feed = feed.filter(func(x): return x.t > 0)
	for rl in radio_lines:
		rl.t -= delta
	radio_lines = radio_lines.filter(func(x): return x.t > 0)
	for a in alerts:
		a.t -= delta
	alerts = alerts.filter(func(x): return x.t > 0)
	queue_redraw()
	slow_t -= delta
	if slow_t <= 0.0:
		slow_t = 0.1
		slow.queue_redraw()


# ---------- Рисование ----------

func _text(p: Vector2, s: String, fs: int, col: Color, center := false, outline := 4) -> void:
	var w := 800.0 if center else -1.0
	var pos := Vector2(p.x - 400.0, p.y) if center else p
	var al := HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	if outline > 0:
		cv.draw_string_outline(font, pos, s, al, w, fs, outline, Color(0, 0, 0, 0.7))
	cv.draw_string(font, pos, s, al, w, fs, col)


func _proj(p3: Vector3):
	var cam: Camera3D = battle.cam
	if cam.is_position_behind(p3):
		return null
	var s := cam.unproject_position(p3)
	# у самой плоскости камеры проекция улетает далеко за экран — рисовать там нечего
	if not Rect2(Vector2(-400, -400), size + Vector2(800, 800)).has_point(s):
		return null
	return s


func _draw() -> void:
	if battle == null or battle.cam == null:
		return
	cv = self
	_draw_world()
	_draw_crosshair()
	_draw_minimap()
	_draw_controls()


func _draw_slow() -> void:
	if battle == null or battle.cam == null:
		return
	cv = slow
	_draw_top()
	_draw_feed()
	_draw_radio()
	_draw_hp()
	if int(battle.G.get("fps_counter", 0)) != 0:
		var fps := Engine.get_frames_per_second()
		var fc := Color("9ad07a") if fps >= 50 else (Color("ffd37a") if fps >= 30 else Color("ff6a4a"))
		_text(Vector2(pause_c.x - 120.0, pause_c.y + 7.0), "%d FPS" % fps, 16, fc, false, 3)
	cv = self


func _draw_world() -> void:
	var w = battle.watch
	for z in battle.zones:
		var s = _proj(Vector3(z.pos.x, battle.terra.height(z.pos.x, z.pos.y) + 66.0, z.pos.y))
		if s == null:
			continue
		var lbl: String = z.label
		if lbl == "":
			if battle.mode == "encounter":
				lbl = "БАЗА"
			else:
				lbl = "НАША БАЗА" if z.side == 0 else "БАЗА ВРАГА"
		var c := col_text if z.side < 0 else team_color(z.side)
		_text(s, lbl, 22, c, true, 5)
	for tk in battle.tanks:
		if not tk.alive or tk == w:
			continue
		if tk.team == 1 and (not tk.vis[0] or battle.realism):
			continue
		if tk.pos.distance_to(_eye_xz()) > (2400.0 if battle.fly_id >= 0 else 1100.0):
			continue
		var s = _proj(tk.get_global_transform_interpolated().origin + Vector3(0, tk.height + 10.0, 0))
		if s == null:
			continue
		var col := team_color(tk.team)
		_text(Vector2(s.x, s.y - 6), tk.callsign, 16, col, true, 4)
		# маркер-треугольник команды
		Gfx.polygon(cv, PackedVector2Array([s + Vector2(-6, 10), s + Vector2(6, 10), s + Vector2(0, 17)]), col)
	if battle.fly_id < 0 and battle.player and battle.player.alive:
		var pl = battle.player
		var aa: bool = pl.T.get("aa", false)
		var me := Vector3(pl.pos.x, battle.terra.height(pl.pos.x, pl.pos.y) + 12.0, pl.pos.y)
		_air_marks(me, float(pl.T.shell_v), -1, aa)
	for tx in battle.texts:
		var s = _proj(tx.pos + Vector3(0, (1.3 - float(tx.life)) * 22.0, 0))
		if s == null:
			continue
		var c: Color = tx.col
		c.a = clampf(tx.life * 1.6, 0.0, 1.0)
		_text(s, tx.s, 22, c, true, 5)


## Перекрестие: точка — куда смотрит камера; круг сведения — куда смотрит ствол.
## Цвет круга: зелёный — пробьёт, жёлтый — как повезёт, красный — не пробьёт.
func _draw_crosshair() -> void:
	if battle.fly_id >= 0:
		_draw_flight_sights()  # в самолёте свои прицелы, каждый кадр
		return
	var w = battle.watch
	var cam: Camera3D = battle.cam
	var c := size / 2
	if battle.sniper:
		# оптика: затемнение по краям и сетка
		var r := minf(size.x, size.y) * 0.46
		var dark := Color(0.02, 0.02, 0.02, 0.92)
		cv.draw_rect(Rect2(0, 0, c.x - r, size.y), dark)
		cv.draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), dark)
		Gfx.arc(cv, c, r, 0.0, TAU, 96, dark, 40.0)
		cv.draw_line(c + Vector2(-r, 0), c + Vector2(-26, 0), Color(0, 0, 0, 0.7), 2.0)
		cv.draw_line(c + Vector2(26, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.7), 2.0)
		cv.draw_line(c + Vector2(0, 26), c + Vector2(0, r), Color(0, 0, 0, 0.7), 2.0)
		for k in range(1, 5):
			cv.draw_line(c + Vector2(-6, 26 + k * 18), c + Vector2(6, 26 + k * 18), Color(0, 0, 0, 0.7), 1.5)
		if battle.realism:
			_draw_reticle(c, r)
	else:
		Gfx.circle(cv, c, 2.0, Color(1, 1, 1, 0.8))
	if not w.alive or battle.gun_point == null or not gun_has:
		return
	var s = _proj(gun_s)
	if s == null:
		return
	if battle.realism:
		# без круга сведения и подсказки пробития: только метка, куда смотрит ствол, и перезарядка
		Gfx.arc(cv, s, 5.0, 0, TAU, 16, Color(1, 1, 1, 0.7), 1.5)
		if w.rl > 0:
			Gfx.arc(cv, s, 11.0, -PI / 2, -PI / 2 + TAU * (1.0 - w.rl / maxf(float(w.rl_max), 0.01)), 32, col_amber, 3.0)
		return
	var half_h := size.y / 2.0 / tan(deg_to_rad(cam.fov) / 2.0)
	var r := clampf(tan(disp_s) * half_h, 7.0, size.y * 0.4)
	var col := Color.WHITE
	if battle.gun_limited:
		col = Color(0.7, 0.7, 0.7)
		_text(s + Vector2(0, r + 30), "ПРЕДЕЛ НАВОДКИ", 14, col, true, 3)
	else:
		col = _pen_color()
	Gfx.arc(cv, s, r, 0, TAU, 48, Color(0, 0, 0, 0.45), 4.0)
	Gfx.arc(cv, s, r, 0, TAU, 48, col, 2.0)
	if w.rl > 0:
		var k: float = 1.0 - w.rl / maxf(float(w.rl_max), 0.01)
		Gfx.arc(cv, s, r + 6, -PI / 2, -PI / 2 + TAU * k, 40, col_amber, 3.0)
	for v: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
		cv.draw_line(s + v * (r + 2), s + v * (r + 11), col, 2.0, true)
	Gfx.circle(cv, s, 1.8, col)


## «Реализм»: сетка прицела по школе — немецкая (треугольники TZF), советская (шкала ТШ с угольниками),
## союзная (перекрестие с боковыми поправками). Справа — шкала дальности с указателем.
func _draw_reticle(c: Vector2, r: float) -> void:
	var ink := Color(0, 0, 0, 0.8)
	var nat := String(battle.player.nation)
	if nat in ["Германия", "Италия", "Япония", "Венгрия"]:
		Gfx.polygon(cv, PackedVector2Array([c, c + Vector2(-9, 20), c + Vector2(9, 20)]), ink)
		for k in range(1, 4):
			for sg in [-1.0, 1.0]:
				var b := c + Vector2(sg * (26.0 + k * 22.0), 0)
				Gfx.polygon(cv, PackedVector2Array([b, b + Vector2(-5, 11), b + Vector2(5, 11)]), ink)
	elif nat == "СССР":
		for k in range(0, 4):
			var y := c.y + k * 20.0
			cv.draw_line(Vector2(c.x - 10.0 + k * 1.5, y + 9), Vector2(c.x, y), ink, 2.0, true)
			cv.draw_line(Vector2(c.x + 10.0 - k * 1.5, y + 9), Vector2(c.x, y), ink, 2.0, true)
		for k in range(1, 5):
			for sg in [-1.0, 1.0]:
				cv.draw_line(c + Vector2(sg * k * 20.0, -5), c + Vector2(sg * k * 20.0, 5), ink, 1.5)
	else:
		cv.draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), ink, 2.0)
		cv.draw_line(c + Vector2(0, -14), c + Vector2(0, 14), ink, 2.0)
		for k in range(1, 5):
			for sg in [-1.0, 1.0]:
				cv.draw_line(c + Vector2(sg * k * 22.0, -4.0 - (k % 2) * 4.0), c + Vector2(sg * k * 22.0, 4.0 + (k % 2) * 4.0), ink, 1.5)
	# шкала дальности справа: деления через 50 м, цифры — сотни метров, указатель — выставленная дальность
	var x := c.x + r * 0.62
	var top := c.y - r * 0.55
	var hgt := r * 1.1
	cv.draw_line(Vector2(x, top), Vector2(x, top + hgt), ink, 1.5)
	for m in range(0, 601, 50):
		var y2 := top + hgt * float(m) / 600.0
		cv.draw_line(Vector2(x - (8.0 if m % 100 == 0 else 4.0), y2), Vector2(x, y2), ink, 1.5)
		if m % 200 == 0:
			_text(Vector2(x - 26.0, y2 + 5.0), str(m / 100), 12, ink, true, 0)
	var yr := top + hgt * float(battle.range_set) / 600.0
	Gfx.polygon(cv, PackedVector2Array([Vector2(x + 2, yr), Vector2(x + 14, yr - 6), Vector2(x + 14, yr + 6)]), ink)


func _pen_color() -> Color:
	var col := Color.WHITE
	match battle.pen_hint:
		0:
			col = col_foe
		1:
			col = col_amber
		2:
			col = Color("7bc65a")
	return col


func _draw_top() -> void:
	var cx := size.x / 2
	var top := 12.0 + margins.y
	Gfx.box(cv, sb_panel, Rect2(cx - 160, top, 320, 46))
	_text(Vector2(cx - 108, top + 34), str(battle.alive_count(0)), 30, col_ally, true, 0)
	_text(Vector2(cx - 40, top + 30), "ПРОТИВ", 14, col_dim, true, 0)
	_text(Vector2(cx + 28, top + 34), str(battle.alive_count(1)), 30, col_foe, true, 0)
	_text(Vector2(cx + 106, top + 31), _fmt_t(maxf(0.0, battle.time_limit - battle.clock)), 20, col_text, true, 0)
	var y := top + 56
	var obj: String = battle.objective()
	if obj != "":
		_text(Vector2(cx, y + 10), obj, 14, col_amber, true, 4)
		y += 22
	if battle.mode == "supremacy" or battle.mode == "breakthrough":
		Gfx.box(cv, sb_panel, Rect2(cx - 130, y, 260, 44))
		if battle.mode == "supremacy":
			_text(Vector2(cx - 98, y + 30), str(int(battle.score[0])), 20, col_ally, true, 0)
			_text(Vector2(cx + 98, y + 30), str(int(battle.score[1])), 20, col_foe, true, 0)
		else:
			_text(Vector2(cx - 98, y + 28), "АТАКА" if battle.bt_att == 0 else "ОБОРОНА", 13, col_ally, true, 0)
		for i in battle.zones.size():
			var z = battle.zones[i]
			var c := Vector2(cx + (i - 1) * 44.0, y + 22)
			var fill := Color(1, 1, 1, 0.15) if z.side < 0 else team_color(z.side)
			Gfx.circle(cv, c, 16, fill)
			Gfx.arc(cv, c, 16, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
			var pr: float = maxf(z.prog[0], z.prog[1])
			if pr > 0:
				var pc := col_ally if z.prog[0] > z.prog[1] else col_foe
				Gfx.arc(cv, c, 19, -PI / 2, -PI / 2 + TAU * pr / 100.0, 32, pc, 4.0)
			if z.n[0] > 0 and z.n[1] > 0 and int(battle.clock * 3) % 2 == 0:
				Gfx.arc(cv, c, 23, 0, TAU, 32, col_amber, 2.0)
			_text(c + Vector2(0, 7), z.label, 18, Color.WHITE if z.side < 0 else Color(0.08, 0.1, 0.05), true, 0)
		y += 52
	else:
		var bars: Array = []
		if battle.mode == "standard":
			if battle.zones[0].prog[1] > 0:
				bars.append(["ВАШУ БАЗУ ЗАХВАТЫВАЮТ", battle.zones[0].prog[1], col_foe])
			if battle.zones[1].prog[0] > 0:
				bars.append(["ЗАХВАТ БАЗЫ ПРОТИВНИКА", battle.zones[1].prog[0], col_ally])
		else:
			var z = battle.zones[0]
			if z.prog[0] > 0:
				bars.append(["ЗАХВАТ БАЗЫ", z.prog[0], col_ally])
			if z.prog[1] > 0:
				bars.append(["ПРОТИВНИК ЗАХВАТЫВАЕТ", z.prog[1], col_foe])
		for b in bars:
			var v: float = b[1]
			Gfx.box(cv, sb_panel, Rect2(cx - 160, y, 320, 34))
			_text(Vector2(cx, y + 18), "%s  %d%%" % [b[0], int(v)], 14, b[2], true, 0)
			cv.draw_rect(Rect2(cx - 150, y + 24, 300, 5), Color(1, 1, 1, 0.12))
			cv.draw_rect(Rect2(cx - 150, y + 24, 300 * v / 100.0, 5), b[2])
			y += 40
	var p = battle.player
	if p.alive and p.vis[1] and _enemy_near(p):
		var r := Rect2(cx - 100, y, 200, 28)
		cv.draw_rect(r, col_amber)
		_text(Vector2(cx, y + 20), "ВАС ОБНАРУЖИЛИ", 15, Color("1b1405"), true, 0)


func _enemy_near(p) -> bool:
	for tk in battle.tanks:
		if tk.alive and tk.team == 1 and tk.pos.distance_to(p.pos) < 900.0:
			return true
	return false


func _draw_feed() -> void:
	var x := pause_c.x - 50.0
	var y := 18.0 + margins.y
	for f in feed:
		var total := 0.0
		for part in f.parts:
			total += font.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var a := clampf(f.t, 0.0, 1.0)
		cv.draw_rect(Rect2(x - total - 10, y, total + 20, 26), Color(0.04, 0.05, 0.03, 0.6 * a))
		var px := x - total
		for part in f.parts:
			var c: Color = part[1]
			c.a = a
			cv.draw_string(font, Vector2(px, y + 19), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
			px += font.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		y += 30


## Неподвижный слой миникарты: рельеф с отмывкой склонов, дороги, постройки, изгороди, кусты и лес.
## Рисуется один раз в картинку — каждый кадр поверх неё только танки, зоны и конус обзора.
func _bake_minimap() -> void:
	var S := 340
	var k := float(S) / D.WS
	var M: Dictionary = D.MAPS[battle.map_key]
	var bg := Color(M.mini)
	var terra = battle.terra
	if battle.core:
		_bake_minimap_native(S, M, bg)
		return
	# отмывка склонов по узлам сетки рельефа (шаг 20 единиц), потом растянуть до размера карты;
	# свет с северо-запада: склоны к нему светлее, от него темнее
	var n0 := int(-terra.ORIGIN / terra.CELL)
	var cells := int(D.WS / terra.CELL)
	var row: int = terra.N + 1
	var h: PackedFloat32Array = terra.h
	var shade := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	for y in cells:
		for x in cells:
			var i := (n0 + y) * row + n0 + x
			var g: float = (h[i + 1] - h[i - 1]) + (h[i + row] - h[i - row])
			var c := bg.lightened(clampf(-g * 0.03, 0.0, 0.25)).darkened(clampf(g * 0.03, 0.0, 0.3))
			c.a = 0.88
			shade.set_pixel(x, y, c)
	shade.resize(S, S, Image.INTERPOLATE_BILINEAR)
	var img := shade
	var road := bg.lerp(Color(M.road), 0.6)
	road.a = 0.88
	var mask: Image = terra.mask
	var mk_k := 1024.0 / float(terra.SIZE)
	for y in S:
		var mz := clampi(int(((y + 0.5) / k - terra.ORIGIN) * mk_k), 0, 1023)
		for x in S:
			if mask.get_pixel(clampi(int(((x + 0.5) / k - terra.ORIGIN) * mk_k), 0, 1023), mz).r > 0.4:
				img.set_pixel(x, y, road)
	var oc := Color(0.12, 0.12, 0.1, 0.9) if not M.get("winter", false) else Color(0.28, 0.31, 0.35, 0.95)
	var hedge := Color(0.13, 0.24, 0.1, 0.95)
	for ob in battle.obst:
		var r: Rect2 = ob.r
		var pr := Rect2i(Vector2i(r.position * k), Vector2i((r.size * k).max(Vector2(2, 2)))).intersection(Rect2i(0, 0, S, S))
		img.fill_rect(pr, hedge if ob.kind == "hedgerow" else oc)
	var leaf := Color(0.15, 0.3, 0.12, 0.9)
	var _dot := func(p: Vector2, rad: float, col: Color) -> void:
		var c := p * k
		var rr := maxf(1.0, rad * k)
		for y in range(int(c.y - rr), int(c.y + rr) + 1):
			for x in range(int(c.x - rr), int(c.x + rr) + 1):
				if x >= 0 and y >= 0 and x < S and y < S and Vector2(x + 0.5, y + 0.5).distance_to(c) <= rr:
					img.set_pixel(x, y, col)
	for b in battle.bushes:
		_dot.call(b.pos, float(b.r), leaf)
	for pr in battle.props:
		if pr.kind == "tree" or pr.kind == "spruce" or pr.kind == "apple":
			_dot.call(pr.pos, 10.0, leaf.darkened(0.15))
	mini_tex = ImageTexture.create_from_image(img)


## То же в C++: отмывка, дороги, постройки, кусты и лес одним вызовом.
func _bake_minimap_native(S: int, M: Dictionary, bg: Color) -> void:
	var road := bg.lerp(Color(M.road), 0.6)
	road.a = 0.88
	var oc := Color(0.12, 0.12, 0.1, 0.9) if not M.get("winter", false) else Color(0.28, 0.31, 0.35, 0.95)
	var hedge := Color(0.13, 0.24, 0.1, 0.95)
	var leaf := Color(0.15, 0.3, 0.12, 0.9)
	var cols := PackedFloat32Array()
	for c: Color in [bg, road, oc, hedge, leaf, leaf.darkened(0.15)]:
		cols.append_array([c.r, c.g, c.b, c.a])
	var of := PackedFloat32Array()
	for ob in battle.obst:
		var r: Rect2 = ob.r
		of.append_array([r.position.x, r.position.y, r.size.x, r.size.y, 1.0 if ob.kind == "hedgerow" else 0.0])
	var df := PackedFloat32Array()
	for b in battle.bushes:
		df.append_array([b.pos.x, b.pos.y, float(b.r), 0.0])
	for pr in battle.props:
		if pr.kind == "tree" or pr.kind == "spruce" or pr.kind == "apple":
			df.append_array([pr.pos.x, pr.pos.y, 10.0, 1.0])
	var img := Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, battle.core.minimap(S, cols, of, df))
	mini_tex = ImageTexture.create_from_image(img)


func _draw_minimap() -> void:
	var sz := 170.0
	var o := Vector2(14.0 + margins.x, 12.0 + margins.y)
	var k := sz / D.WS
	if mini_tex == null:
		_bake_minimap()
	cv.draw_texture_rect(mini_tex, Rect2(o, Vector2(sz, sz)), false)
	for z in battle.zones:
		var c := Color.WHITE if z.side < 0 else team_color(z.side)
		Gfx.arc(cv, o + z.pos * k, float(z.r) * k, 0, TAU, 24, c, 2.0)
		if z.label != "":
			_text(o + z.pos * k + Vector2(0, 5), z.label, 13, Color.WHITE, true, 3)
	var w = battle.watch
	var wp: Vector2 = o + w.pos * k
	var yaw: float = battle.cam_yaw
	var cone := PackedVector2Array([wp, wp + Vector2.from_angle(yaw - 0.5) * 42.0, wp + Vector2.from_angle(yaw + 0.5) * 42.0])
	Gfx.polygon(cv, cone, Color(1, 1, 1, 0.16))
	for tk in battle.tanks:
		if not tk.alive or (tk.team == 1 and (not tk.vis[0] or battle.realism)):
			continue  # в реализме на миникарте только свои
		var c := team_color(tk.team)
		var tp: Vector2 = o + tk.pos * k
		if tk.is_player:
			Gfx.circle(cv, tp, 6.0, c)
			Gfx.arc(cv, tp, 6.0, 0, TAU, 16, Color.WHITE, 2.0)
		else:
			Gfx.circle(cv, tp, 4.5, c)
	if battle.inf:
		# самолёты — стрелками по курсу
		var ad: PackedFloat32Array = battle.inf.air_dots()
		for q in range(0, ad.size(), 4):
			if battle.realism and int(ad[q + 2]) != 0:
				continue
			var ap := o + Vector2(clampf(ad[q], 0.0, D.WS), clampf(ad[q + 1], 0.0, D.WS)) * k
			var fw := Vector2.from_angle(ad[q + 3])
			var sd := fw.orthogonal()
			Gfx.polygon(cv, PackedVector2Array([ap + fw * 7.0, ap - fw * 4.0 + sd * 4.5, ap - fw * 4.0 - sd * 4.5]), team_color(int(ad[q + 2])).lightened(0.25))
		var dots: PackedFloat32Array = battle.inf.dots()
		for q in range(0, dots.size(), 3):
			if battle.realism and int(dots[q + 2]) != 0:
				continue
			var dp := o + Vector2(dots[q], dots[q + 1]) * k
			cv.draw_rect(Rect2(dp.x - 1.5, dp.y - 1.5, 3.0, 3.0), team_color(int(dots[q + 2])))
	# рамка четырьмя заливными прямоугольниками: draw_rect(…, false, w) заводит новый буфер и VAO на каждый вызов
	var lc := Color(UI.LINE)
	cv.draw_rect(Rect2(o.x - 1.0, o.y - 1.0, sz + 2.0, 2.0), lc)
	cv.draw_rect(Rect2(o.x - 1.0, o.y + sz - 1.0, sz + 2.0, 2.0), lc)
	cv.draw_rect(Rect2(o.x - 1.0, o.y + 1.0, 2.0, sz - 2.0), lc)
	cv.draw_rect(Rect2(o.x + sz - 1.0, o.y + 1.0, 2.0, sz - 2.0), lc)


## Последние переговоры под миникартой: позывной и фраза, под ней перевод.
func _draw_radio() -> void:
	var x := 14.0 + margins.x
	var y := 12.0 + margins.y + 170.0 + 10.0
	for r in radio_lines:
		var a := clampf(float(r.t), 0.0, 1.0)
		var head := "%s: " % r.cs
		var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tw := font.get_string_size(r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var trw := font.get_string_size(r.tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if r.tr != "" else 0.0
		var h := 44.0 if r.tr != "" else 26.0
		cv.draw_rect(Rect2(x, y, maxf(hw + tw, trw) + 16, h), Color(0.04, 0.05, 0.03, 0.62 * a))
		cv.draw_rect(Rect2(x, y, 3, h), Color(col_ally, a))
		cv.draw_string(font, Vector2(x + 9, y + 18), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col_ally, a))
		cv.draw_string(font, Vector2(x + 9 + hw, y + 18), r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col_text, a))
		if r.tr != "":
			cv.draw_string(font, Vector2(x + 9, y + 37), r.tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col_dim, a))
		y += h + 4.0


func _draw_hp() -> void:
	var p = battle.player
	if battle.fly_id >= 0:
		_draw_flight()
		_draw_abilities()
		return
	var cx := size.x / 2
	var y := size.y - 14.0 - margins.w - 52.0
	_text(Vector2(cx, y), String(p.T.name).to_upper(), 14, col_dim, true, 3)
	_draw_crew(p, cx, y + 26)
	if not p.alive:
		return
	# скорость и состояние модулей
	var kmh := absf(p.sp) / D.UPM * 3.6
	_text(Vector2(cx - 200, y + 18), "%d км/ч" % int(round(kmh)), 18, col_text, true, 3)
	_draw_damage(p, cx, y - 62)
	var ay := y - 84
	for i in range(alerts.size() - 1, -1, -1):
		var a = alerts[i]
		var ac: Color = a.col
		ac.a = clampf(float(a.t) * 1.5, 0.0, 1.0)
		_text(Vector2(cx, ay), a.text, 19, ac, true, 5)
		ay -= 26


const CREW_SHORT := {"commander": "КОМ", "gunner": "НАВ", "loader": "ЗАР", "driver": "МЕХ", "radio": "РАД"}


## Экипаж (прочности нет): значок на каждое место. Зелёный — здоров, жёлтый — ранен, красный крест — выбыл,
## мигающий — пересаживается на место выбывшего. Под ним — нет наводчика / мехвода.
func _draw_crew(p, cx: float, y: float) -> void:
	var seats: Array = []
	for cr in TankScript.CREW:
		if p.crew_has.get(cr, false):
			seats.append(cr)
	var step := 46.0
	var x0 := cx - step * (seats.size() - 1) / 2.0
	cv.draw_rect(Rect2(x0 - 26, y - 22, step * (seats.size() - 1) + 52, 48), Color(0.04, 0.05, 0.03, 0.6))
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
	for i in seats.size():
		var cr: String = seats[i]
		var hp := float(p.crew_hp.get(cr, 100.0))
		var c := Vector2(x0 + i * step, y - 4)
		var col := Color("7bc65a")
		if hp == -2.0:
			col = col_amber if blink else Color(col_amber, 0.35)
		elif hp <= 0.0:
			col = col_foe
		elif hp < 60.0:
			col = col_amber
		# фигурка: голова и плечи
		Gfx.circle(cv, c + Vector2(0, -7), 5.5, col)
		Gfx.polygon(cv, PackedVector2Array([c + Vector2(-10, 9), c + Vector2(-7, 0), c + Vector2(7, 0), c + Vector2(10, 9)]), col)
		if hp == 0.0:
			cv.draw_line(c + Vector2(-11, -12), c + Vector2(11, 10), Color("ffffff"), 2.5)
			cv.draw_line(c + Vector2(11, -12), c + Vector2(-11, 10), Color("ffffff"), 2.5)
		elif hp > 0.0 and hp < 100.0:
			cv.draw_rect(Rect2(c.x - 12, c.y + 12, 24, 3), Color(0, 0, 0, 0.6))
			cv.draw_rect(Rect2(c.x - 12, c.y + 12, 24 * hp / 100.0, 3), col)
		_text(c + Vector2(0, 26), CREW_SHORT[cr], 10, col_dim, true, 3)
	if p.alive and not p.gun_crew:
		_text(Vector2(cx, y - 44), "НЕКОМУ СТРЕЛЯТЬ", 15, col_foe, true, 3)
	elif p.alive and not p.drive_crew:
		_text(Vector2(cx, y - 44), "НЕКОМУ ВЕСТИ", 15, col_foe, true, 3)


## Панель повреждений: только то, что не в порядке. Жёлтое — повреждено, красное — уничтожено
## или ранен; кольцо — полевой ремонт.
func _draw_damage(p, cx: float, y: float) -> void:
	var items: Array = []
	for m in TankScript.MODS:
		var st: int = p.mod_state(m)
		if st == 2:
			continue
		var fr := -1.0
		if p.mod_fix.has(m):
			fr = 1.0 - float(p.mod_fix[m]) / float(TankScript.REPAIR[m])
		items.append([m, TankScript.NAMES[m], col_foe if st == 0 else col_amber, fr])
	if p.track_broken > 0.0:
		items.append(["track", "ГУСЕНИЦА", col_amber, 1.0 - p.track_broken / 7.0])
	if p.fire > 0.0:
		items.append(["fire", "ПОЖАР", Color("ff7a3a"), -1.0])
	if items.is_empty():
		return
	var step := 58.0
	var x := cx - step * (items.size() - 1) / 2.0
	for it in items:
		var c := Vector2(x, y)
		var col: Color = it[2]
		Gfx.box(cv, _sb("0a0c08", col.to_html(false), 2, 10, 0.72), Rect2(c - Vector2(22, 22), Vector2(44, 44)))
		_icon(it[0], c, col)
		if it[3] >= 0.0:
			Gfx.arc(cv, c, 27, -PI / 2, -PI / 2 + TAU * clampf(it[3], 0.0, 1.0), 32, Color("9ad07a"), 3.0)
		_text(c + Vector2(0, 38), it[1], 10, col, true, 3)
		x += step


## Значки повреждений, нарисованные примитивами.
func _icon(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"engine":
			cv.draw_rect(Rect2(c + Vector2(-12, -3), Vector2(24, 13)), col)
			for i in 3:
				cv.draw_rect(Rect2(c + Vector2(-11 + i * 8, -11), Vector2(6, 7)), col)
		"gun":
			cv.draw_rect(Rect2(c + Vector2(-14, -2), Vector2(21, 4)), col)
			cv.draw_rect(Rect2(c + Vector2(5, -7), Vector2(9, 14)), col)
		"turret":
			Gfx.polygon(cv, PackedVector2Array([c + Vector2(-13, 8), c + Vector2(-10, -3), c + Vector2(3, -7),
				c + Vector2(10, -1), c + Vector2(10, 8)]), col)
			cv.draw_rect(Rect2(c + Vector2(8, -3), Vector2(8, 3)), col)
		"optics":
			Gfx.arc(cv, c, 11, 0, TAU, 24, col, 2.5)
			Gfx.circle(cv, c, 4.5, col)
		"ammo":
			cv.draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 14)), col)
			Gfx.polygon(cv, PackedVector2Array([c + Vector2(-4, -3), c + Vector2(4, -3), c + Vector2(0, -12)]), col)
		"fuel":
			cv.draw_rect(Rect2(c + Vector2(-8, -7), Vector2(16, 18)), col)
			cv.draw_line(c + Vector2(-3, -11), c + Vector2(5, -11), col, 3.0)
		"track":
			Gfx.arc(cv, c + Vector2(-7, 2), 5, 0, TAU, 16, col, 2.0)
			Gfx.arc(cv, c + Vector2(7, 2), 5, 0, TAU, 16, col, 2.0)
			cv.draw_line(c + Vector2(-7, -5), c + Vector2(7, -5), col, 2.5)
			cv.draw_line(c + Vector2(-7, 9), c + Vector2(7, 9), col, 2.5)
		"fire":
			Gfx.polygon(cv, PackedVector2Array([c + Vector2(0, -13), c + Vector2(8, 0), c + Vector2(6, 10),
				c + Vector2(-6, 10), c + Vector2(-8, 0), c + Vector2(-3, -4)]), col)
		_:
			Gfx.circle(cv, c + Vector2(0, -6), 5.5, col)
			Gfx.polygon(cv, PackedVector2Array([c + Vector2(-10, 11), c + Vector2(-7, 1), c + Vector2(7, 1),
				c + Vector2(10, 11)]), col)


func _draw_controls() -> void:
	# пауза
	Gfx.circle(cv, pause_c, 30, Color(0.04, 0.05, 0.03, 0.6))
	Gfx.arc(cv, pause_c, 30, 0, TAU, 32, Color(UI.LINE), 2.0)
	cv.draw_rect(Rect2(pause_c.x - 8, pause_c.y - 10, 5, 20), col_text)
	cv.draw_rect(Rect2(pause_c.x + 3, pause_c.y - 10, 5, 20), col_text)
	var p = battle.player
	if not p.alive:
		return
	if battle.fly_id >= 0:
		_draw_throttle()
		return
	# джойстик движения
	if move_idx != -1:
		Gfx.circle(cv, move_o, SR, Color(1, 1, 1, 0.08))
		Gfx.arc(cv, move_o, SR, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0)
		Gfx.circle(cv, move_o + move * SR, 34, Color(1, 1, 1, 0.45))
	else:
		_text(Vector2(140 + margins.x, size.y - 30 - margins.w), "◀ ДВИЖЕНИЕ ▶", 13, Color(1, 1, 1, 0.35), true, 0)
	# огонь с кольцом перезарядки
	var ready: bool = p.rl <= 0 and p.can_fire()
	Gfx.circle(cv, fire_c, fire_r, Color(0.94, 0.72, 0.23, 0.28))
	if not ready and p.rl > 0:
		var k: float = 1.0 - p.rl / maxf(float(p.rl_max), 0.01)
		Gfx.arc(cv, fire_c, fire_r - 4, -PI / 2, -PI / 2 + TAU * k, 64, col_amber, 8.0)
	Gfx.circle(cv, fire_c, fire_r - 10, col_amber if ready else Color("6c5a2a"))
	var label := "ОГОНЬ" if ready else ("%.1f" % p.rl if p.rl > 0 else "РЕМОНТ")
	_text(fire_c + Vector2(0, 9), label, 24, Color("1b1405") if ready else col_text, true, 0)
	# автоприцел
	var ac := col_amber if auto_aim else col_dim
	if not battle.realism:
		Gfx.box(cv, _sb("0a0c08", D.AMBER if auto_aim else UI.LINE, 2, 22, 0.6), auto_rect)
		_text(auto_rect.get_center() + Vector2(0, 7), "АВТО", 18, ac, true, 0)
	# снайперский прицел
	var on: bool = battle.sniper
	Gfx.circle(cv, zoom_c, 40, Color(0.04, 0.05, 0.03, 0.62) if not on else Color(0.94, 0.72, 0.23, 0.85))
	Gfx.arc(cv, zoom_c, 40, 0, TAU, 40, col_amber if on else Color(UI.LINE), 2.0)
	var zc := Color("1b1405") if on else col_text
	Gfx.arc(cv, zoom_c + Vector2(-2, -4), 12, 0, TAU, 24, zc, 2.5)
	cv.draw_line(zoom_c + Vector2(6, 4), zoom_c + Vector2(14, 12), zc, 3.0, true)
	_text(zoom_c + Vector2(0, 30), "ПРИЦЕЛ", 11, zc, true, 0)
	_draw_cons(p)
	_draw_abilities()
	_draw_ammo()


## Кнопки снарядов: заряженный — жёлтая рамка; под кнопкой — сколько осталось (у основного счёта нет).
func _draw_ammo() -> void:
	var st: PackedFloat32Array = battle.ammo_now
	var cur := int(st[0]) if st.size() > 0 else 0
	for ab: Array in ammo_r:
		var rc: Rect2 = ab[0]
		var k: int = ab[1]
		var q := 1 + k * 3
		var left := int(st[q + 1]) if q + 1 < st.size() else -1
		var on := k == cur
		var empty := left == 0
		Gfx.box(cv, _sb("0a0c08", D.AMBER if on else UI.LINE, 3 if on else 2, 10, 0.68), rc)
		var a: Dictionary = battle.ammo_list[k]
		var col: Color = col_dim if empty else (col_amber if on else col_text)
		_text(rc.get_center() + Vector2(0, 2), String(a.short), 17, col, true, 0)
		if left >= 0:
			_text(rc.get_center() + Vector2(0, 19), str(left), 11, col_dim, true, 0)


## Кнопки снаряжения: жёлтая рамка — пора применить, кольцо и секунды — перезарядка.
func _draw_cons(p) -> void:
	for c in cons_c:
		var cc: Vector2 = cons_c[c]
		var cd: float = p.cons[c]
		var need: bool = cd <= 0.0 and p.cons_needed(c)
		Gfx.circle(cv, cc, 30, Color(0.04, 0.05, 0.03, 0.62))
		Gfx.arc(cv, cc, 30, 0, TAU, 40, col_amber if need else Color(UI.LINE), 3.0 if need else 2.0)
		var col := col_text if cd <= 0.0 else col_dim
		_cons_icon(c, cc, col)
		if cd > 0.0:
			var k: float = 1.0 - cd / float(D.CONSUMABLES[c].cd)
			Gfx.arc(cv, cc, 26, -PI / 2, -PI / 2 + TAU * k, 40, col_amber, 3.0)
			_text(cc + Vector2(0, 46), "%d" % ceili(cd), 13, col_dim, true, 3)
		else:
			_text(cc + Vector2(0, 46), ["1", "2", "3"][["repair", "medkit", "ext"].find(c)], 11, col_dim, true, 3)


## Полёт: приборы, метка носа самолёта, подсказки. Метка прицела — центр экрана (туда доворачивает самолёт).
func _fly_air() -> int:
	var inf = battle.inf
	if inf == null or battle.fly_id < 0:
		return -1
	return inf.plane_at(battle.fly_id)


func _fly_bombs() -> int:
	var a := _fly_air()
	return int(battle.inf.air[a + 10]) if a >= 0 else 0


## Точка, от которой считаются метки на земле: самолёт в полёте, иначе свой танк.
func _eye_xz() -> Vector2:
	var a := _fly_air()
	if a >= 0:
		return Vector2(battle.inf.air[a], battle.inf.air[a + 2])
	return battle.watch.pos


func _thr_set(y: float) -> void:
	if thr_rect.size.y <= 0.0:
		return
	battle.fly_thr = clampf(1.0 - (y - thr_rect.position.y) / thr_rect.size.y, 0.0, 1.0)


## Ползунок газа (как в War Thunder Mobile): тянуть вверх-вниз, отпущенный остаётся на месте.
func _draw_throttle() -> void:
	var r := thr_rect
	if r.size.y <= 0.0:
		return
	var thr: float = battle.fly_thr
	cv.draw_rect(r, Color(0.04, 0.05, 0.03, 0.55))
	var fh := r.size.y * thr
	cv.draw_rect(Rect2(r.position.x, r.end.y - fh, r.size.x, fh), Color(0.94, 0.72, 0.23, 0.35 if thr_idx == -1 else 0.55))
	for k: float in [0.0, 0.5, 1.0]:
		var ty: float = r.end.y - r.size.y * k
		cv.draw_line(Vector2(r.end.x, ty), Vector2(r.end.x + 8.0, ty), col_dim, 2.0)
	var hy := r.end.y - fh
	cv.draw_rect(Rect2(r.position.x - 6.0, hy - 5.0, r.size.x + 12.0, 10.0), col_amber)
	_text(Vector2(r.get_center().x, r.position.y - 12.0), "ГАЗ", 13, col_dim, true, 3)
	_text(Vector2(r.end.x + 14.0, hy + 6.0), "%d%%" % int(thr * 100.0), 16, col_text, false, 3)


## Самолёт (медленный слой): кнопка пушек, приборы, подсказки.
func _draw_flight() -> void:
	var a := _fly_air()
	if a < 0:
		return
	var air: PackedFloat32Array = battle.inf.air
	var fl := int(air[a + 7])
	var rounds := int(air[a + 11])
	var on := rounds > 0
	Gfx.circle(cv, fire_c, fire_r, Color(0.94, 0.72, 0.23, 0.28))
	Gfx.circle(cv, fire_c, fire_r - 10, col_amber if on else Color("6c5a2a"))
	_text(fire_c + Vector2(0, 2), "ПУШКИ", 22, Color("1b1405") if on else col_text, true, 0)
	_text(fire_c + Vector2(0, 26), str(rounds), 16, Color("1b1405") if on else col_text, true, 0)
	# приборы — строкой под счётом: скорость, высота, планер
	var gh: float = battle.terra.height(air[a], air[a + 2])
	var kmh := air[a + 9] * 0.9  # приборная скорость (летит самолёт вдвое медленнее — масштаб карты)
	var alt := (air[a + 1] - gh) / D.UPM
	var hp := 100.0 * air[a + 8] / maxf(1.0, air[a + 14])
	var cx := size.x * 0.5
	var y := 14.0 + margins.y + 64.0
	var cells := [["СКОР.", "%d км/ч" % int(kmh), col_foe if kmh < 190.0 and (fl & 16) == 0 else col_text],
		["ВЫС.", "%d м" % int(alt), col_foe if alt < 12.0 and (fl & 16) == 0 else col_text],
		["ПЛАНЕР", "%d%%" % int(hp), col_text if hp > 40.0 else col_foe]]
	cv.draw_rect(Rect2(cx - 225.0, y - 20.0, 450.0, 30.0), Color(0.04, 0.05, 0.03, 0.55))
	var x := cx - 150.0
	for cl: Array in cells:
		_text(Vector2(x - 40.0, y), cl[0], 12, col_dim, true, 3)
		_text(Vector2(x + 25.0, y), cl[1], 17, cl[2], true, 3)
		x += 150.0
	var c := size / 2
	if (fl & 16) != 0:
		_text(c + Vector2(0, 110), "НА ПОЛОСЕ: СТОЯ — ПЕРЕЗАРЯДКА 10 с; ГАЗ ВВЕРХ — РАЗБЕГ, МЕТКУ ВЫШЕ ГОРИЗОНТА — ВЗЛЁТ", 15, col_amber, true, 4)
	elif (fl & 64) != 0 or kmh < 175.0:
		_text(c + Vector2(0, 110), "СРЫВ! ОТДАТЬ РУЧКУ: НОС ВНИЗ, ГАЗ", 18, col_foe, true, 4)
	elif (fl & 128) != 0:
		_text(c + Vector2(0, 110), "МОТОР ПОВРЕЖДЁН — ТЯГА СЛАБЕЕТ", 15, col_foe, true, 4)
	elif battle.fly_land:
		_text(c + Vector2(0, 110), "АВТОПИЛОТ: ЗАХОД НА ПОСАДКУ", 15, col_amber, true, 4)
	elif int(air[a + 10]) <= 0 and rounds <= 0:
		_text(c + Vector2(0, 110), "БОЕЗАПАС ПУСТ — САДИТЕСЬ НА СВОЙ АЭРОДРОМ («ПОСАДКА»)", 15, col_amber, true, 4)


## Прицелы самолёта (каждый кадр): метка курса, нос, точка попадания пушек, метка падения бомб, упреждение по самолётам.
func _draw_flight_sights() -> void:
	var a := _fly_air()
	if a < 0:
		return
	var inf = battle.inf
	var air: PackedFloat32Array = inf.air
	var c := size / 2
	# метка курса — куда ведёт палец; самолёт доворачивает на неё
	Gfx.arc(cv, c, 16.0, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0)
	Gfx.circle(cv, c, 2.0, Color(1, 1, 1, 0.9))
	var px: Array = inf.plane_xf(a, Engine.get_physics_interpolation_fraction())
	var me: Vector3 = px[0]
	var ns = _proj(me + (px[1] as Vector3) * 700.0)
	if ns != null:
		for v: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			cv.draw_line(ns + v * 6.0, ns + v * 15.0, col_amber, 2.5, true)
	var fl := int(air[a + 7])
	var sg: PackedFloat32Array = battle.fly_sight
	if sg.size() == 8 and (fl & 16) == 0:
		# пушки: где очередь встретит землю (до 1,4 км)
		if sg[7] > 0.0 and sg[7] < 1400.0 and int(air[a + 11]) > 0:
			var gp = _proj(Vector3(sg[4], sg[5] + 1.0, sg[6]))
			if gp != null:
				Gfx.arc(cv, gp, 11.0, 0, TAU, 24, Color("9ad07a"), 2.0)
				Gfx.circle(cv, gp, 2.5, Color("9ad07a"))
				_text(gp + Vector2(16, 5), "%d м" % int(sg[7] / D.UPM), 12, Color("9ad07a"), false, 3)
		# бомбы: точка падения с линией сброса от самолёта (CCIP)
		if int(air[a + 10]) > 0:
			var bp = _proj(Vector3(sg[0], sg[1] + 1.0, sg[2]))
			var pl = _proj(me + Vector3(0, -6.0, 0))
			if bp != null:
				var hit := false
				for tk in battle.tanks:
					if tk.alive and tk.team == 1 and tk.vis[0] and Vector2(tk.pos.x - sg[0], tk.pos.y - sg[2]).length() < 26.0:
						hit = true
						break
				var bc := Color("ff6a4a") if hit else Color(1, 1, 1, 0.9)
				if pl != null:
					cv.draw_dashed_line(pl, bp, Color(bc, 0.55), 2.0, 10.0)
				Gfx.arc(cv, bp, 18.0, 0, TAU, 32, bc, 2.5)
				for v: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					cv.draw_line(bp + v * 18.0, bp + v * 28.0, bc, 2.5, true)
				_text(bp + Vector2(0, 46), "СБРОС!" if hit else "БОМБЫ %.1f с" % sg[3], 14, bc, true, 3)
	_air_marks(me, 1900.0 + air[a + 9] * AIR_V, a, true)


const AIR_V := 0.35  # самолёт летит в AIR_V раз медленнее своей «приборной» скорости (как в air.inc)


## Самолёты противника: ромб с дальностью; lead — метка упреждения для снаряда со скоростью shot_v.
func _air_marks(me: Vector3, shot_v: float, skip: int, lead: bool) -> void:
	var inf = battle.inf
	if inf == null or battle.realism:
		return  # в реализме меток нет — самолёт ищут глазами
	var air: PackedFloat32Array = inf.air
	for q in range(0, air.size() - 1, 16):
		if q == skip or int(air[q + 6]) == 0 or (int(air[q + 7]) & 3) != 1 or (int(air[q + 7]) & 16) != 0:
			continue
		var pp := Vector3(air[q], air[q + 1], air[q + 2])
		var d := pp.distance_to(me)
		if d > 2000.0:
			continue
		var s = _proj(pp)
		if s == null:
			continue
		Gfx.arc(cv, s, 14.0, 0, TAU, 4, col_foe, 2.0)
		if lead and d < 1300.0:
			var yaw := air[q + 3]
			var pit := air[q + 4]
			var dv := Vector3(cos(yaw) * cos(pit), sin(pit), sin(yaw) * cos(pit)) * air[q + 9] * AIR_V
			var ld = _proj(pp + dv * (d / shot_v))
			if ld != null:
				cv.draw_line(s, ld, Color(col_foe, 0.5), 1.5, true)
				Gfx.arc(cv, ld, 8.0, 0, TAU, 20, col_foe, 2.0)
		_text(s + Vector2(0, -20), "%d м" % int(d / D.UPM), 12, col_foe, true, 3)


## Удары (артиллерия, штурмовик), приказы взводу и дальность «Реализма».
func _draw_abilities() -> void:
	for an in abil_c:
		var cc: Vector2 = abil_c[an]
		var strike: bool = an == "arty" or an == "air"
		var k := 0 if an == "arty" else 1
		var cd: float = battle.strike_cd[k] if strike else 0.0
		var on: bool = not strike and battle.order_cur == {"follow": 1, "hold": 2}.get(an, -1)
		var rr := 30.0 if strike else 26.0
		if battle.fly_id >= 0 and an == "arty":
			rr = 44.0
		Gfx.circle(cv, cc, rr, Color(0.04, 0.05, 0.03, 0.62))
		Gfx.arc(cv, cc, rr, 0, TAU, 40, col_amber if (on or (strike and cd <= 0.0)) else Color(UI.LINE), 3.0 if on else 2.0)
		var col := col_text if cd <= 0.0 else col_dim
		match an:
			"arty":
				# разрыв
				for a in 6:
					var v := Vector2.from_angle(-PI / 2 + (a - 2.5) * 0.42)
					cv.draw_line(cc + Vector2(0, 9) + v * 5.0, cc + Vector2(0, 9) + v * (15.0 + 4.0 * (a % 2)), col, 2.5, true)
				cv.draw_line(cc + Vector2(-13, 11), cc + Vector2(13, 11), col, 2.5, true)
			"air":
				# самолёт сверху
				cv.draw_line(cc + Vector2(0, -13), cc + Vector2(0, 12), col, 4.0, true)
				cv.draw_line(cc + Vector2(-15, -1), cc + Vector2(15, -1), col, 4.0, true)
				cv.draw_line(cc + Vector2(-6, 11), cc + Vector2(6, 11), col, 3.0, true)
			"follow":
				Gfx.polygon(cv, PackedVector2Array([cc + Vector2(-9, 8), cc + Vector2(0, -11), cc + Vector2(9, 8), cc + Vector2(0, 3)]), col)
			"hold":
				cv.draw_rect(Rect2(cc + Vector2(-9, -9), Vector2(18, 18)), col)
			"plane":
				cv.draw_line(cc + Vector2(0, -11), cc + Vector2(0, 10), col, 3.5, true)
				cv.draw_line(cc + Vector2(-13, -1), cc + Vector2(13, -1), col, 3.5, true)
				cv.draw_line(cc + Vector2(-5, 9), cc + Vector2(5, 9), col, 2.5, true)
			"attack":
				for dx in [-7.0, 5.0]:
					cv.draw_line(cc + Vector2(dx - 4, -9), cc + Vector2(dx + 5, 0), col, 3.0, true)
					cv.draw_line(cc + Vector2(dx + 5, 0), cc + Vector2(dx - 4, 9), col, 3.0, true)
		if strike and battle.fly_id >= 0:
			_text(cc + Vector2(0, rr + 16.0), ("БОМБЫ ×%d" % _fly_bombs()) if an == "arty" else ("ПОСАДКА: ВКЛ" if battle.fly_land else "ПОСАДКА"), 11, col_amber if (an == "air" and battle.fly_land) else col_dim, true, 3)
		elif strike and cd > 0.0:
			Gfx.arc(cv, cc, rr - 4.0, -PI / 2, -PI / 2 + TAU * (1.0 - cd / float(battle.STRIKE_CD[k])), 40, col_amber, 3.0)
			_text(cc + Vector2(0, 46), "%d" % ceili(cd), 13, col_dim, true, 3)
		elif strike and battle.fly_id >= 0:
			_text(cc + Vector2(0, rr + 16.0), ("БОМБЫ ×%d" % _fly_bombs()) if an == "arty" else ("ПОСАДКА: ВКЛ" if battle.fly_land else "ПОСАДКА"), 11, col_amber if (an == "air" and battle.fly_land) else col_dim, true, 3)
		elif strike:
			_text(cc + Vector2(0, 46), "АРТ" if an == "arty" else "АВИА", 11, col_dim, true, 3)
		else:
			var names := {"follow": "ЗА МНОЙ", "hold": "СТОЯТЬ", "attack": "В АТАКУ", "plane": "САМОЛЁТ ×%d" % battle.sorties}
			if battle.fly_id >= 0:
				names["follow"] = "В ТАНК" if battle.player.alive else "ПОКИНУТЬ"
			_text(cc + Vector2(34, 5), names[an], 12, col_amber if on else col_dim, false, 3)
	if battle.realism and not range_r.is_empty():
		var r0: Rect2 = range_r[0][0]
		var r1: Rect2 = range_r[1][0]
		for rr2: Rect2 in [r0, r1]:
			cv.draw_rect(rr2, Color(0.04, 0.05, 0.03, 0.62))
		_text(r0.get_center() + Vector2(0, 8), "−", 24, col_text, true, 3)
		_text(r1.get_center() + Vector2(0, 8), "+", 24, col_text, true, 3)
		_text(Vector2((r0.end.x + r1.position.x) * 0.5, r0.position.y - 8.0), "ДАЛЬНОСТЬ %d м" % int(battle.range_set), 14, col_amber, true, 3)


func _cons_icon(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"repair":
			# гаечный ключ
			cv.draw_line(c + Vector2(-9, 9), c + Vector2(6, -6), col, 5.0, true)
			Gfx.arc(cv, c + Vector2(8, -8), 6, PI * 0.9, PI * 2.4, 16, col, 3.5)
		"medkit":
			cv.draw_rect(Rect2(c + Vector2(-4, -12), Vector2(8, 24)), col)
			cv.draw_rect(Rect2(c + Vector2(-12, -4), Vector2(24, 8)), col)
		"ext":
			# огнетушитель
			cv.draw_rect(Rect2(c + Vector2(-6, -6), Vector2(12, 18)), col)
			cv.draw_rect(Rect2(c + Vector2(-3, -11), Vector2(6, 5)), col)
			cv.draw_line(c + Vector2(3, -9), c + Vector2(11, -12), col, 2.5, true)


static func _fmt_t(s: float) -> String:
	var n := maxi(0, ceili(s))
	return "%d:%02d" % [n / 60, n % 60]


# ---------- Окна ----------

func _overlay(dim: float) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.02, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	root.set_meta("box", vb)
	root.visible = false
	add_child(root)
	return root


func _button(text: String, accent: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 60)
	if accent:
		UI.accent(b, 24)
	else:
		b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b


## Брифинг перед боем: что за сражение, кто с кем воюет, составы команд и задача.
func show_brief(info: Dictionary) -> void:
	brief_box = _overlay(0.88)
	var vb: VBoxContainer = brief_box.get_meta("box")
	vb.add_theme_constant_override("separation", 10)
	var t := UI.label(String(info.title).to_upper(), 30, D.AMBER)
	vb.add_child(t)
	vb.add_child(UI.label(info.sub, 17, UI.TEXT))
	var txt := UI.label(info.text, 15, UI.DIM)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(minf(860.0, get_viewport_rect().size.x - 140.0), 0)
	vb.add_child(txt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	vb.add_child(row)
	for side in info.teams:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UI.label(side.head, 15, UI.TEXT))
		var lst := UI.label(side.list, 15, "7bc65a" if side.ours else "e2563c")
		lst.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(lst)
		row.add_child(col)
	var task := UI.label(info.task, 15, UI.TEXT)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(minf(860.0, get_viewport_rect().size.x - 140.0), 0)
	vb.add_child(task)
	var go := _button("В БОЙ", true, func():
		brief_box.visible = false
		battle.begin())
	vb.add_child(go)
	brief_box.visible = true


func _build_dead() -> void:
	dead_box = VBoxContainer.new()
	dead_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dead_box.position = Vector2(-170, 200)
	dead_box.custom_minimum_size = Vector2(340, 0)
	dead_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dead_box.add_theme_constant_override("separation", 8)
	var t := UI.label("ТАНК УНИЧТОЖЕН", 30, D.FOE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_box.add_child(t)
	var s := UI.label("Наблюдение за союзником", 18, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_box.add_child(s)
	dead_box.add_child(_button("В САМОЛЁТ", true, func(): battle.take_off(0, 15.0)))
	ffwd_btn = _button("УСКОРИТЬ ×4", false, func():
		battle.toggle_speed()
		ffwd_btn.text = "ОБЫЧНАЯ СКОРОСТЬ" if battle.speed > 1 else "УСКОРИТЬ ×4")
	dead_box.add_child(ffwd_btn)
	dead_box.visible = false
	add_child(dead_box)


func show_dead(v: bool) -> void:
	dead_box.visible = v
	reset_input()


func _build_pause() -> void:
	pause_box = _overlay(0.75)
	var vb: VBoxContainer = pause_box.get_meta("box")
	var t := UI.label("ПАУЗА", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_button("ПРОДОЛЖИТЬ", true, func(): battle.set_paused(false)))
	var snd := _button("ЗВУК: ВКЛ", false, func(): pass)
	snd.pressed.connect(func():
		battle.sfx.set_muted(not battle.sfx.muted)
		snd.text = "ЗВУК: ВЫКЛ" if battle.sfx.muted else "ЗВУК: ВКЛ")
	vb.add_child(snd)
	vb.add_child(_button("ПОКИНУТЬ БОЙ", false, func(): battle.leave.emit(false)))


func show_pause(v: bool) -> void:
	pause_box.visible = v
	reset_input()


func _build_result() -> void:
	result_box = _overlay(0.82)
	var vb: VBoxContainer = result_box.get_meta("box")
	res_title = UI.label("ПОБЕДА", 52)
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(res_title)
	res_reason = UI.label("", 18, UI.DIM)
	res_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(res_reason)
	res_stats = HBoxContainer.new()
	res_stats.add_theme_constant_override("separation", 8)
	vb.add_child(res_stats)
	res_table = GridContainer.new()
	res_table.columns = 3
	res_table.add_theme_constant_override("h_separation", 26)
	res_table.add_theme_constant_override("v_separation", 2)
	vb.add_child(res_table)
	# Яндекс Игры: реклама за награду — серебро за бой ещё раз
	res_reward = _button("", false, _on_reward)
	res_reward.custom_minimum_size = Vector2(612, 52)
	res_reward.add_theme_color_override("font_color", D.AMBER)
	res_reward.visible = false
	vb.add_child(res_reward)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	res_again = _button("ЕЩЁ БОЙ", true, func(): battle.leave.emit(true))
	row.add_child(res_again)
	res_home = _button("В АНГАР", false, func(): battle.leave.emit(false))
	row.add_child(res_home)
	vb.add_child(row)


var res_reward: Button
var res_again: Button
var res_home: Button
var _reward_amount := 0


func _on_reward() -> void:
	var yg := get_node_or_null("/root/Yandex")
	if yg == null or _reward_amount <= 0:
		return
	res_reward.disabled = true
	yg.show_rewarded(func(got: bool) -> void:
		if not is_instance_valid(res_reward):
			return
		if got:
			battle.get_parent().reward_silver(_reward_amount)
			res_reward.text = "ПОЛУЧЕНО +%s СЕРЕБРА" % _num(_reward_amount)
			_reward_amount = 0
		else:
			res_reward.disabled = false)


func show_result(st: Dictionary) -> void:
	dead_box.visible = false
	reset_input()
	var yg := get_node_or_null("/root/Yandex")
	_reward_amount = int(st.get("silver_gross", 0))
	res_reward.visible = yg != null and yg.rewarded_available() and _reward_amount > 0
	res_reward.disabled = false
	res_reward.text = "▶ РЕКЛАМА: ЕЩЁ +%s СЕРЕБРА" % _num(_reward_amount)
	# миссия кампании: свой заголовок, возврат — в кампанию
	var ms: bool = not battle.mission.is_empty()
	res_again.visible = not ms
	res_home.text = "В КАМПАНИЮ" if ms else "В АНГАР"
	match st.result:
		"win":
			res_title.text = "ПОБЕДА"
			res_title.add_theme_color_override("font_color", Color("7bc65a"))
		"lose":
			res_title.text = "ПОРАЖЕНИЕ"
			res_title.add_theme_color_override("font_color", col_foe)
		_:
			res_title.text = "НИЧЬЯ"
			res_title.add_theme_color_override("font_color", col_amber)
	if ms and st.result != "draw":
		res_title.text = "МИССИЯ ВЫПОЛНЕНА" if st.result == "win" else "МИССИЯ ПРОВАЛЕНА"
	res_reason.text = "%s. %s, карта «%s»." % [st.reason, st.mode, st.map]
	if ms:
		res_reason.text = "%s. «%s», карта «%s»." % [st.reason, battle.mission.title, st.map]
	for c in res_stats.get_children():
		c.queue_free()
	for item in [["Уничтожено", str(st.kills)], ["Урон", str(st.dmg)], ["Точность", "%d%%" % st.acc], ["Время", _fmt_t(st.time)]]:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(118, 0)
		var col := VBoxContainer.new()
		col.add_child(UI.label(item[1], 24))
		col.add_child(UI.label(String(item[0]).to_upper(), 12, UI.DIM))
		pc.add_child(col)
		res_stats.add_child(pc)
	# медали боя (в скобках — сколько раз получена всего)
	var mds: Array = st.get("medals", [])
	if not mds.is_empty():
		var names: Array = []
		for md: Array in mds:
			names.append("★ %s ×%d" % [md[0], int(st.get("medal_totals", {}).get(md[0], 1))])
		var pm := PanelContainer.new()
		var lm := UI.label("  ".join(names), 15, D.AMBER)
		lm.tooltip_text = "; ".join(mds.map(func(x): return "%s — %s" % [x[0], x[1]]))
		pm.add_child(lm)
		res_stats.add_child(pm)
	# за что сколько опыта и серебра
	for c in res_table.get_children():
		c.queue_free()
	var row := func(a: String, b: String, c: String, col: String, fs := 15) -> void:
		res_table.add_child(UI.label(a, fs, col))
		var lb := UI.label(b, fs, col)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_table.add_child(lb)
		var lc := UI.label(c, fs, col)
		lc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_table.add_child(lc)
	row.call("", "ОПЫТ", "СЕРЕБРО", UI.DIM, 12)
	for ln in st.lines:
		row.call(ln[0], _num(ln[1]), _num(ln[2]), UI.TEXT)
	if float(st.mult) > 1.0:
		row.call("Победа" if st.result == "win" else "Ничья", "×%s" % String.num(st.mult, 1).replace(".", ","),
			"×%s" % String.num(st.mult, 1).replace(".", ","), "7bc65a")
	if float(st.get("tier_mult", 1.0)) > 1.0:
		var tm := "×%s" % String.num(st.tier_mult, 1).replace(".", ",")
		row.call("Уровень танка", tm, tm, "7bc65a")
	if int(st.repair) > 0:
		row.call("Ремонт", "", "−" + _num(st.repair), "e2563c")
	if int(st.cons_cost) > 0:
		row.call("Снаряжение", "", "−" + _num(st.cons_cost), "e2563c")
	if int(st.get("ammo_cost", 0)) > 0:
		row.call("Особые снаряды", "", "−" + _num(st.ammo_cost), "e2563c")
	row.call("ИТОГО (+%s свободного опыта)" % _num(st.free_xp), "+" + _num(st.xp),
		("+" if int(st.silver) >= 0 else "−") + _num(absi(int(st.silver))), D.AMBER, 18)
	if float(st.get("campaign_k", 1.0)) > 1.0:
		row.call("Кампания (уже в итоге)" + (", опыт — в свободный" if st.get("xp_to_free", false) else ""),
			"×" + String.num(st.campaign_k, 2).replace(".", ","), "×" + String.num(st.campaign_k, 2).replace(".", ","), "7bc65a", 14)
	if String(st.get("campaign_msg", "")) != "":
		var cm := UI.label(String(st.campaign_msg), 14, D.AMBER)
		cm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		res_table.add_child(cm)
		res_table.add_child(Control.new())
		res_table.add_child(Control.new())
	if int(st.get("crew_xp", 0)) > 0:
		row.call("Опыт экипажа" + (" — новый уровень, есть очко навыка!" if st.get("crew_up", false) else ""),
			"+" + _num(st.crew_xp), "", "7bc65a", 14)
	result_box.visible = true


## Число с пробелами между разрядами: 12 345.
static func _num(v) -> String:
	var n := absi(int(v))
	var t := str(n)
	var out := ""
	while t.length() > 3:
		out = " " + t.right(3) + out
		t = t.left(t.length() - 3)
	return ("-" if int(v) < 0 else "") + t + out
