extends Control
## HUD боя: мультитач-управление, прицел, таблички над танками, миникарта, переговоры по рации,
## счёт и режим, а также окна брифинга, паузы, гибели и итогов боя.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
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

# раскладка (пересчитывается каждый кадр)
var margins := Vector4.ZERO
var fire_c := Vector2.ZERO
var fire_r := 76.0
var auto_rect := Rect2()
var pause_c := Vector2.ZERO
var zoom_c := Vector2.ZERO
var cons_c := {}  # снаряжение → центр кнопки

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
	_build_dead()
	_build_pause()
	_build_result()


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
		if not battle.player.alive:
			return  # наблюдение: касания достаются кнопке «Ускорить»
		if p.distance_to(fire_c) < fire_r + 14.0:
			fire_idx = e.index
			fire_req = true
			return
		if auto_rect.grow(10.0).has_point(p):
			auto_aim = not auto_aim
			return
		if p.distance_to(zoom_c) < 50.0:
			battle.toggle_sniper()
			return
		for c in cons_c:
			if p.distance_to(cons_c[c]) < 36.0:
				battle.use_cons(c)
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
		var keys := {KEY_1: "repair", KEY_2: "medkit", KEY_3: "ext"}
		if k.pressed and not k.echo and keys.has(k.keycode):
			battle.use_cons(keys[k.keycode])
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if e.index == move_idx:
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


func _process(delta: float) -> void:
	margins = UI.safe(self)
	var s := size
	var r := 18.0 + margins.z
	var bt := 14.0 + margins.w
	pause_c = Vector2(s.x - r - 32.0, 14.0 + margins.y + 32.0)
	fire_c = Vector2(s.x - r - 96.0, s.y - bt - 104.0)
	auto_rect = Rect2(fire_c.x - 60.0, fire_c.y - fire_r - 62.0, 120.0, 44.0)
	zoom_c = Vector2(fire_c.x - fire_r - 64.0, fire_c.y + 26.0)
	cons_c.clear()
	if battle and battle.player:
		var x := zoom_c.x - 84.0
		for c in ["ext", "medkit", "repair"]:
			if battle.player.cons.has(c):
				cons_c[c] = Vector2(x, s.y - bt - 36.0)
				x -= 66.0
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
		if tk.team == 1 and not tk.vis[0]:
			continue
		if tk.pos.distance_to(w.pos) > 1100.0:
			continue
		var s = _proj(tk.get_global_transform_interpolated().origin + Vector3(0, tk.height + 10.0, 0))
		if s == null:
			continue
		var col := team_color(tk.team)
		var bw := 58.0
		cv.draw_rect(Rect2(s.x - bw / 2 - 1, s.y - 1, bw + 2, 7), Color(0, 0, 0, 0.6))
		cv.draw_rect(Rect2(s.x - bw / 2, s.y, bw * clampf(tk.hp / tk.max_hp, 0.0, 1.0), 5), col)
		_text(Vector2(s.x, s.y - 6), tk.callsign, 16, col, true, 4)
		# маркер-треугольник команды
		cv.draw_colored_polygon(PackedVector2Array([s + Vector2(-6, 10), s + Vector2(6, 10), s + Vector2(0, 17)]), col)
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
	var w = battle.watch
	var cam: Camera3D = battle.cam
	var c := size / 2
	if battle.sniper:
		# оптика: затемнение по краям и сетка
		var r := minf(size.x, size.y) * 0.46
		var dark := Color(0.02, 0.02, 0.02, 0.92)
		cv.draw_rect(Rect2(0, 0, c.x - r, size.y), dark)
		cv.draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), dark)
		var ring := PackedVector2Array()
		for i in 49:
			ring.append(c + Vector2.from_angle(TAU * i / 48.0) * r)
		cv.draw_polyline(ring, dark, 40.0)
		cv.draw_line(c + Vector2(-r, 0), c + Vector2(-26, 0), Color(0, 0, 0, 0.7), 2.0)
		cv.draw_line(c + Vector2(26, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.7), 2.0)
		cv.draw_line(c + Vector2(0, 26), c + Vector2(0, r), Color(0, 0, 0, 0.7), 2.0)
		for k in range(1, 5):
			cv.draw_line(c + Vector2(-6, 26 + k * 18), c + Vector2(6, 26 + k * 18), Color(0, 0, 0, 0.7), 1.5)
	else:
		cv.draw_circle(c, 2.0, Color(1, 1, 1, 0.8))
	if not w.alive or battle.gun_point == null:
		return
	var s = _proj(battle.gun_point)
	if s == null:
		return
	var half_h := size.y / 2.0 / tan(deg_to_rad(cam.fov) / 2.0)
	var r := clampf(tan(float(w.disp)) * half_h, 7.0, size.y * 0.4)
	var col := Color.WHITE
	if battle.gun_limited:
		col = Color(0.7, 0.7, 0.7)
		_text(s + Vector2(0, r + 30), "ПРЕДЕЛ НАВОДКИ", 14, col, true, 3)
	else:
		col = _pen_color()
	cv.draw_arc(s, r, 0, TAU, 48, Color(0, 0, 0, 0.45), 4.0, true)
	cv.draw_arc(s, r, 0, TAU, 48, col, 2.0, true)
	if w.rl > 0:
		var k: float = 1.0 - w.rl / maxf(float(w.rl_max), 0.01)
		cv.draw_arc(s, r + 6, -PI / 2, -PI / 2 + TAU * k, 40, col_amber, 3.0, true)
	for v: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
		cv.draw_line(s + v * (r + 2), s + v * (r + 11), col, 2.0, true)
	cv.draw_circle(s, 1.8, col)


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
	cv.draw_style_box(sb_panel, Rect2(cx - 160, top, 320, 46))
	_text(Vector2(cx - 108, top + 34), str(battle.alive_count(0)), 30, col_ally, true, 0)
	_text(Vector2(cx - 40, top + 30), "ПРОТИВ", 14, col_dim, true, 0)
	_text(Vector2(cx + 28, top + 34), str(battle.alive_count(1)), 30, col_foe, true, 0)
	_text(Vector2(cx + 106, top + 31), _fmt_t(D.TIME_LIMIT - battle.clock), 20, col_text, true, 0)
	var y := top + 56
	if battle.mode == "supremacy":
		cv.draw_style_box(sb_panel, Rect2(cx - 130, y, 260, 44))
		_text(Vector2(cx - 98, y + 30), str(int(battle.score[0])), 20, col_ally, true, 0)
		_text(Vector2(cx + 98, y + 30), str(int(battle.score[1])), 20, col_foe, true, 0)
		for i in battle.zones.size():
			var z = battle.zones[i]
			var c := Vector2(cx + (i - 1) * 44.0, y + 22)
			var fill := Color(1, 1, 1, 0.15) if z.side < 0 else team_color(z.side)
			cv.draw_circle(c, 16, fill)
			cv.draw_arc(c, 16, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
			var pr: float = maxf(z.prog[0], z.prog[1])
			if pr > 0:
				var pc := col_ally if z.prog[0] > z.prog[1] else col_foe
				cv.draw_arc(c, 19, -PI / 2, -PI / 2 + TAU * pr / 100.0, 32, pc, 4.0, true)
			if z.n[0] > 0 and z.n[1] > 0 and int(battle.clock * 3) % 2 == 0:
				cv.draw_arc(c, 23, 0, TAU, 32, col_amber, 2.0, true)
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
			cv.draw_style_box(sb_panel, Rect2(cx - 160, y, 320, 34))
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


func _draw_minimap() -> void:
	var sz := 170.0
	var o := Vector2(14.0 + margins.x, 12.0 + margins.y)
	var k := sz / D.WS
	if mini_tex == null:
		_bake_minimap()
	cv.draw_texture_rect(mini_tex, Rect2(o, Vector2(sz, sz)), false)
	for z in battle.zones:
		var c := Color.WHITE if z.side < 0 else team_color(z.side)
		cv.draw_arc(o + z.pos * k, float(z.r) * k, 0, TAU, 24, c, 2.0, true)
		if z.label != "":
			_text(o + z.pos * k + Vector2(0, 5), z.label, 13, Color.WHITE, true, 3)
	var w = battle.watch
	var wp: Vector2 = o + w.pos * k
	var yaw: float = battle.cam_yaw
	var cone := PackedVector2Array([wp, wp + Vector2.from_angle(yaw - 0.5) * 42.0, wp + Vector2.from_angle(yaw + 0.5) * 42.0])
	cv.draw_colored_polygon(cone, Color(1, 1, 1, 0.16))
	for tk in battle.tanks:
		if not tk.alive or (tk.team == 1 and not tk.vis[0]):
			continue
		var c := team_color(tk.team)
		var tp: Vector2 = o + tk.pos * k
		if tk.is_player:
			cv.draw_circle(tp, 6.0, c)
			cv.draw_arc(tp, 6.0, 0, TAU, 16, Color.WHITE, 2.0, true)
		else:
			cv.draw_circle(tp, 4.5, c)
	cv.draw_rect(Rect2(o, Vector2(sz, sz)), Color(UI.LINE), false, 2.0)


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
	var cx := size.x / 2
	var y := size.y - 14.0 - margins.w - 52.0
	var f: float = clampf(p.hp / p.max_hp, 0.0, 1.0)
	var c := Color(UI.TEXT)
	if f > 0.5:
		c = Color("7bc65a")
	elif f > 0.25:
		c = col_amber
	else:
		c = col_foe
	_text(Vector2(cx, y), String(p.T.name).to_upper(), 14, col_dim, true, 3)
	cv.draw_rect(Rect2(cx - 150, y + 6, 300, 14), Color(0.04, 0.05, 0.03, 0.75))
	cv.draw_rect(Rect2(cx - 149, y + 7, 298 * f, 12), c)
	_text(Vector2(cx, y + 42), "%d / %d" % [ceili(maxf(p.hp, 0.0)), int(p.max_hp)], 20, col_text, true, 4)
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
	for cr in TankScript.CREW:
		if not p.crew_ok[cr]:
			items.append(["crew", TankScript.NAMES[cr], col_foe, -1.0])
	if items.is_empty():
		return
	var step := 58.0
	var x := cx - step * (items.size() - 1) / 2.0
	for it in items:
		var c := Vector2(x, y)
		var col: Color = it[2]
		cv.draw_style_box(UI.box("0a0c08", col.to_html(false), 2, 10, 0.72, 0.0), Rect2(c - Vector2(22, 22), Vector2(44, 44)))
		_icon(it[0], c, col)
		if it[3] >= 0.0:
			cv.draw_arc(c, 27, -PI / 2, -PI / 2 + TAU * clampf(it[3], 0.0, 1.0), 32, Color("9ad07a"), 3.0, true)
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
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 8), c + Vector2(-10, -3), c + Vector2(3, -7),
				c + Vector2(10, -1), c + Vector2(10, 8)]), col)
			cv.draw_rect(Rect2(c + Vector2(8, -3), Vector2(8, 3)), col)
		"optics":
			cv.draw_arc(c, 11, 0, TAU, 24, col, 2.5, true)
			cv.draw_circle(c, 4.5, col)
		"ammo":
			cv.draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 14)), col)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -3), c + Vector2(4, -3), c + Vector2(0, -12)]), col)
		"fuel":
			cv.draw_rect(Rect2(c + Vector2(-8, -7), Vector2(16, 18)), col)
			cv.draw_line(c + Vector2(-3, -11), c + Vector2(5, -11), col, 3.0)
		"track":
			cv.draw_arc(c + Vector2(-7, 2), 5, 0, TAU, 16, col, 2.0, true)
			cv.draw_arc(c + Vector2(7, 2), 5, 0, TAU, 16, col, 2.0, true)
			cv.draw_line(c + Vector2(-7, -5), c + Vector2(7, -5), col, 2.5)
			cv.draw_line(c + Vector2(-7, 9), c + Vector2(7, 9), col, 2.5)
		"fire":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(8, 0), c + Vector2(6, 10),
				c + Vector2(-6, 10), c + Vector2(-8, 0), c + Vector2(-3, -4)]), col)
		_:
			cv.draw_circle(c + Vector2(0, -6), 5.5, col)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 11), c + Vector2(-7, 1), c + Vector2(7, 1),
				c + Vector2(10, 11)]), col)


func _draw_controls() -> void:
	# пауза
	cv.draw_circle(pause_c, 30, Color(0.04, 0.05, 0.03, 0.6))
	cv.draw_arc(pause_c, 30, 0, TAU, 32, Color(UI.LINE), 2.0, true)
	cv.draw_rect(Rect2(pause_c.x - 8, pause_c.y - 10, 5, 20), col_text)
	cv.draw_rect(Rect2(pause_c.x + 3, pause_c.y - 10, 5, 20), col_text)
	var p = battle.player
	if not p.alive:
		return
	# джойстик движения
	if move_idx != -1:
		cv.draw_circle(move_o, SR, Color(1, 1, 1, 0.08))
		cv.draw_arc(move_o, SR, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0, true)
		cv.draw_circle(move_o + move * SR, 34, Color(1, 1, 1, 0.45))
	else:
		_text(Vector2(140 + margins.x, size.y - 30 - margins.w), "◀ ДВИЖЕНИЕ ▶", 13, Color(1, 1, 1, 0.35), true, 0)
	# огонь с кольцом перезарядки
	var ready: bool = p.rl <= 0 and p.can_fire()
	cv.draw_circle(fire_c, fire_r, Color(0.94, 0.72, 0.23, 0.28))
	if not ready and p.rl > 0:
		var k: float = 1.0 - p.rl / maxf(float(p.rl_max), 0.01)
		cv.draw_arc(fire_c, fire_r - 4, -PI / 2, -PI / 2 + TAU * k, 64, col_amber, 8.0, true)
	cv.draw_circle(fire_c, fire_r - 10, col_amber if ready else Color("6c5a2a"))
	var label := "ОГОНЬ" if ready else ("%.1f" % p.rl if p.rl > 0 else "РЕМОНТ")
	_text(fire_c + Vector2(0, 9), label, 24, Color("1b1405") if ready else col_text, true, 0)
	# автоприцел
	var ac := col_amber if auto_aim else col_dim
	cv.draw_style_box(UI.box("0a0c08", D.AMBER if auto_aim else UI.LINE, 2, 22, 0.6, 0.0), auto_rect)
	_text(auto_rect.get_center() + Vector2(0, 7), "АВТО", 18, ac, true, 0)
	# снайперский прицел
	var on: bool = battle.sniper
	cv.draw_circle(zoom_c, 40, Color(0.04, 0.05, 0.03, 0.62) if not on else Color(0.94, 0.72, 0.23, 0.85))
	cv.draw_arc(zoom_c, 40, 0, TAU, 40, col_amber if on else Color(UI.LINE), 2.0, true)
	var zc := Color("1b1405") if on else col_text
	cv.draw_arc(zoom_c + Vector2(-2, -4), 12, 0, TAU, 24, zc, 2.5, true)
	cv.draw_line(zoom_c + Vector2(6, 4), zoom_c + Vector2(14, 12), zc, 3.0, true)
	_text(zoom_c + Vector2(0, 30), "ПРИЦЕЛ", 11, zc, true, 0)
	_draw_cons(p)


## Кнопки снаряжения: жёлтая рамка — пора применить, кольцо и секунды — перезарядка.
func _draw_cons(p) -> void:
	for c in cons_c:
		var cc: Vector2 = cons_c[c]
		var cd: float = p.cons[c]
		var need: bool = cd <= 0.0 and p.cons_needed(c)
		cv.draw_circle(cc, 30, Color(0.04, 0.05, 0.03, 0.62))
		cv.draw_arc(cc, 30, 0, TAU, 40, col_amber if need else Color(UI.LINE), 3.0 if need else 2.0, true)
		var col := col_text if cd <= 0.0 else col_dim
		_cons_icon(c, cc, col)
		if cd > 0.0:
			var k: float = 1.0 - cd / float(D.CONSUMABLES[c].cd)
			cv.draw_arc(cc, 26, -PI / 2, -PI / 2 + TAU * k, 40, col_amber, 3.0, true)
			_text(cc + Vector2(0, 46), "%d" % ceili(cd), 13, col_dim, true, 3)
		else:
			_text(cc + Vector2(0, 46), ["1", "2", "3"][["repair", "medkit", "ext"].find(c)], 11, col_dim, true, 3)


func _cons_icon(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"repair":
			# гаечный ключ
			cv.draw_line(c + Vector2(-9, 9), c + Vector2(6, -6), col, 5.0, true)
			cv.draw_arc(c + Vector2(8, -8), 6, PI * 0.9, PI * 2.4, 16, col, 3.5, true)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("ЕЩЁ БОЙ", true, func(): battle.leave.emit(true)))
	row.add_child(_button("В АНГАР", false, func(): battle.leave.emit(false)))
	vb.add_child(row)


func show_result(st: Dictionary) -> void:
	dead_box.visible = false
	reset_input()
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
	res_reason.text = "%s. %s, карта «%s»." % [st.reason, st.mode, st.map]
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
	row.call("ИТОГО (+%s свободного опыта)" % _num(st.free_xp), "+" + _num(st.xp),
		("+" if int(st.silver) >= 0 else "−") + _num(absi(int(st.silver))), D.AMBER, 18)
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
