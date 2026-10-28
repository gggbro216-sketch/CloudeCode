extends Control
## HUD боя: мультитач-управление, прицел, таблички над танками, миникарта,
## счёт и режим, а также окна паузы, гибели и итогов боя.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
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
var cam_dx := 0.0
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

var feed: Array = []
var col_ally := Color(D.ALLY)
var col_foe := Color(D.FOE)
var col_amber := Color(D.AMBER)
var col_text := Color(UI.TEXT)
var col_dim := Color(UI.DIM)
var sb_panel := UI.box("0a0c08", UI.LINE, 1, 8, 0.62, 0.0)

var dead_box: Control
var ffwd_btn: Button
var pause_box: Control
var result_box: Control
var res_title: Label
var res_reason: Label
var res_stats: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	font = ThemeDB.fallback_font
	_build_dead()
	_build_pause()
	_build_result()


func team_color(team: int) -> Color:
	return col_ally if team == 0 else col_foe


func add_feed(parts: Array) -> void:
	feed.append({"parts": parts, "t": 4.5})
	while feed.size() > 4:
		feed.pop_front()


func take_cam_dx() -> float:
	var v := cam_dx
	cam_dx = 0.0
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
	cam_dx = 0.0


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
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if e.index == move_idx:
			move_p = e.position
			var d := move_p - move_o
			if d.length() > SR:
				d = d.normalized() * SR
			move = d / SR
		elif e.index == aim_idx:
			cam_dx += e.position.x - aim_last.x
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
	for f in feed:
		f.t -= delta
	feed = feed.filter(func(x): return x.t > 0)
	queue_redraw()


# ---------- Рисование ----------

func _text(p: Vector2, s: String, fs: int, col: Color, center := false, outline := 4) -> void:
	var w := 800.0 if center else -1.0
	var pos := Vector2(p.x - 400.0, p.y) if center else p
	var al := HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	if outline > 0:
		draw_string_outline(font, pos, s, al, w, fs, outline, Color(0, 0, 0, 0.7))
	draw_string(font, pos, s, al, w, fs, col)


func _proj(p3: Vector3):
	var cam: Camera3D = battle.cam
	if cam.is_position_behind(p3):
		return null
	return cam.unproject_position(p3)


func _draw() -> void:
	if battle == null or battle.cam == null:
		return
	_draw_world()
	_draw_crosshair()
	_draw_top()
	_draw_feed()
	_draw_minimap()
	_draw_hp()
	_draw_controls()


func _draw_world() -> void:
	var w = battle.watch
	for z in battle.zones:
		var s = _proj(Vector3(z.pos.x, 64, z.pos.y))
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
		if tk.pos.distance_to(w.pos) > 1000.0:
			continue
		var s = _proj(Vector3(tk.pos.x, tk.barrel_y() + 22.0, tk.pos.y))
		if s == null:
			continue
		var col := team_color(tk.team)
		var bw := 58.0
		draw_rect(Rect2(s.x - bw / 2 - 1, s.y - 1, bw + 2, 7), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(s.x - bw / 2, s.y, bw * clampf(tk.hp / tk.max_hp, 0.0, 1.0), 5), col)
		_text(Vector2(s.x, s.y - 6), tk.callsign, 16, col, true, 4)
	for tx in battle.texts:
		var s = _proj(Vector3(tx.pos.x, tx.h, tx.pos.y))
		if s == null:
			continue
		var c: Color = tx.col
		c.a = clampf(tx.life * 1.6, 0.0, 1.0)
		_text(s, tx.s, 24, c, true, 5)


func _draw_crosshair() -> void:
	var w = battle.watch
	if not w.alive:
		return
	var dir := Vector2.from_angle(w.tur)
	var d: float = w.T.barrel
	var on_foe := false
	while d < D.RANGE and not on_foe:
		var pt: Vector2 = w.pos + dir * d
		if battle.in_rect(pt) != null:
			break
		for o in battle.tanks:
			if o.alive and o.team != w.team and o.vis[0] and o.pos.distance_squared_to(pt) < pow(float(o.T.r), 2):
				on_foe = true
				break
		if not on_foe:
			d += 8.0
	var end: Vector2 = w.pos + dir * d
	var s = _proj(Vector3(end.x, w.barrel_y(), end.y))
	if s == null:
		return
	var col := col_foe if on_foe else Color.WHITE
	var r := 20.0
	draw_arc(s, r, 0, TAU, 40, Color(0, 0, 0, 0.5), 5.0, true)
	draw_arc(s, r, 0, TAU, 40, col, 2.5, true)
	if w.rl > 0:
		var k: float = 1.0 - w.rl / float(w.T.reload)
		draw_arc(s, r + 6, -PI / 2, -PI / 2 + TAU * k, 40, col_amber, 3.5, true)
	for v: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
		draw_line(s + v * (r + 4), s + v * (r + 14), col, 2.5, true)
	draw_circle(s, 2.2, col)


func _draw_top() -> void:
	var cx := size.x / 2
	var top := 12.0 + margins.y
	draw_style_box(sb_panel, Rect2(cx - 160, top, 320, 46))
	_text(Vector2(cx - 108, top + 34), str(battle.alive_count(0)), 30, col_ally, true, 0)
	_text(Vector2(cx - 40, top + 30), "ПРОТИВ", 14, col_dim, true, 0)
	_text(Vector2(cx + 28, top + 34), str(battle.alive_count(1)), 30, col_foe, true, 0)
	_text(Vector2(cx + 106, top + 31), _fmt_t(D.TIME_LIMIT - battle.clock), 20, col_text, true, 0)
	var y := top + 56
	if battle.mode == "supremacy":
		draw_style_box(sb_panel, Rect2(cx - 130, y, 260, 44))
		_text(Vector2(cx - 98, y + 30), str(int(battle.score[0])), 20, col_ally, true, 0)
		_text(Vector2(cx + 98, y + 30), str(int(battle.score[1])), 20, col_foe, true, 0)
		for i in battle.zones.size():
			var z = battle.zones[i]
			var c := Vector2(cx + (i - 1) * 44.0, y + 22)
			var fill := Color(1, 1, 1, 0.15) if z.side < 0 else team_color(z.side)
			draw_circle(c, 16, fill)
			draw_arc(c, 16, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
			var pr: float = maxf(z.prog[0], z.prog[1])
			if pr > 0:
				var pc := col_ally if z.prog[0] > z.prog[1] else col_foe
				draw_arc(c, 19, -PI / 2, -PI / 2 + TAU * pr / 100.0, 32, pc, 4.0, true)
			if z.n[0] > 0 and z.n[1] > 0 and int(battle.clock * 3) % 2 == 0:
				draw_arc(c, 23, 0, TAU, 32, col_amber, 2.0, true)
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
			draw_style_box(sb_panel, Rect2(cx - 160, y, 320, 34))
			_text(Vector2(cx, y + 18), "%s  %d%%" % [b[0], int(v)], 14, b[2], true, 0)
			draw_rect(Rect2(cx - 150, y + 24, 300, 5), Color(1, 1, 1, 0.12))
			draw_rect(Rect2(cx - 150, y + 24, 300 * v / 100.0, 5), b[2])
			y += 40
	var p = battle.player
	if p.alive and p.vis[1] and _enemy_near(p):
		var r := Rect2(cx - 100, y, 200, 28)
		draw_rect(r, col_amber)
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
		draw_rect(Rect2(x - total - 10, y, total + 20, 26), Color(0.04, 0.05, 0.03, 0.6 * a))
		var px := x - total
		for part in f.parts:
			var c: Color = part[1]
			c.a = a
			draw_string(font, Vector2(px, y + 19), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
			px += font.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		y += 30


func _draw_minimap() -> void:
	var sz := 170.0
	var o := Vector2(14.0 + margins.x, 12.0 + margins.y)
	var k := sz / D.WS
	var M: Dictionary = D.MAPS[battle.map_key]
	var bg := Color(M.mini)
	bg.a = 0.85
	draw_rect(Rect2(o, Vector2(sz, sz)), bg)
	var oc := Color(0.12, 0.12, 0.1, 0.8) if battle.map_key != "winter" else Color(0.28, 0.31, 0.35, 0.95)
	for ob in battle.obst:
		var r: Rect2 = ob.r
		draw_rect(Rect2(o + r.position * k, (r.size * k).max(Vector2(2, 2))), oc)
	for b in battle.bushes:
		draw_circle(o + b.pos * k, float(b.r) * k, Color(0.15, 0.3, 0.12, 0.85))
	for z in battle.zones:
		var c := Color.WHITE if z.side < 0 else team_color(z.side)
		draw_arc(o + z.pos * k, float(z.r) * k, 0, TAU, 24, c, 2.0, true)
		if z.label != "":
			_text(o + z.pos * k + Vector2(0, 5), z.label, 13, Color.WHITE, true, 3)
	var w = battle.watch
	var wp: Vector2 = o + w.pos * k
	var yaw: float = battle.cam_yaw
	var cone := PackedVector2Array([wp, wp + Vector2.from_angle(yaw - 0.5) * 42.0, wp + Vector2.from_angle(yaw + 0.5) * 42.0])
	draw_colored_polygon(cone, Color(1, 1, 1, 0.16))
	for tk in battle.tanks:
		if not tk.alive or (tk.team == 1 and not tk.vis[0]):
			continue
		var c := team_color(tk.team)
		var tp: Vector2 = o + tk.pos * k
		if tk.is_player:
			draw_circle(tp, 6.0, c)
			draw_arc(tp, 6.0, 0, TAU, 16, Color.WHITE, 2.0, true)
		else:
			draw_circle(tp, 4.5, c)
	draw_rect(Rect2(o, Vector2(sz, sz)), Color(UI.LINE), false, 2.0)


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
	draw_rect(Rect2(cx - 150, y + 6, 300, 14), Color(0.04, 0.05, 0.03, 0.75))
	draw_rect(Rect2(cx - 149, y + 7, 298 * f, 12), c)
	_text(Vector2(cx, y + 42), "%d / %d" % [ceili(maxf(p.hp, 0.0)), int(p.max_hp)], 20, col_text, true, 4)


func _draw_controls() -> void:
	# пауза
	draw_circle(pause_c, 30, Color(0.04, 0.05, 0.03, 0.6))
	draw_arc(pause_c, 30, 0, TAU, 32, Color(UI.LINE), 2.0, true)
	draw_rect(Rect2(pause_c.x - 8, pause_c.y - 10, 5, 20), col_text)
	draw_rect(Rect2(pause_c.x + 3, pause_c.y - 10, 5, 20), col_text)
	var p = battle.player
	if not p.alive:
		return
	# джойстик движения
	if move_idx != -1:
		draw_circle(move_o, SR, Color(1, 1, 1, 0.08))
		draw_arc(move_o, SR, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0, true)
		draw_circle(move_o + move * SR, 34, Color(1, 1, 1, 0.45))
	else:
		_text(Vector2(140 + margins.x, size.y - 30 - margins.w), "◀ ДВИЖЕНИЕ ▶", 13, Color(1, 1, 1, 0.35), true, 0)
	# огонь с кольцом перезарядки
	var ready: bool = p.rl <= 0
	draw_circle(fire_c, fire_r, Color(0.94, 0.72, 0.23, 0.28))
	if not ready:
		var k: float = 1.0 - p.rl / float(p.T.reload)
		draw_arc(fire_c, fire_r - 4, -PI / 2, -PI / 2 + TAU * k, 64, col_amber, 8.0, true)
	draw_circle(fire_c, fire_r - 10, col_amber if ready else Color("6c5a2a"))
	var label := "ОГОНЬ" if ready else "%.1f" % p.rl
	_text(fire_c + Vector2(0, 9), label, 24, Color("1b1405") if ready else col_text, true, 0)
	# автоприцел
	var ac := col_amber if auto_aim else col_dim
	draw_style_box(UI.box("0a0c08", D.AMBER if auto_aim else UI.LINE, 2, 22, 0.6, 0.0), auto_rect)
	_text(auto_rect.get_center() + Vector2(0, 7), "АВТО", 18, ac, true, 0)


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
		battle.sfx.muted = not battle.sfx.muted
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
	for item in [["Уничтожено", str(st.kills)], ["Урон", str(st.dmg)], ["Точность", "%d%%" % st.acc], ["Время", _fmt_t(st.time)], ["Серебро", "+%d" % st.silver]]:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(118, 0)
		var col := VBoxContainer.new()
		col.add_child(UI.label(item[1], 26))
		col.add_child(UI.label(String(item[0]).to_upper(), 12, UI.DIM))
		pc.add_child(col)
		res_stats.add_child(pc)
	result_box.visible = true
