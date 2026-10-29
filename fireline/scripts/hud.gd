extends Control
## Интерфейс боя: верхняя панель (пауза, скорость, время, точки, артиллерия), приказы справа,
## карточки отрядов снизу, сводка по выбранным, лента сообщений, меню и итоги боя.

const UI = preload("res://scripts/ui.gd")
const Data = preload("res://scripts/data.gd")
const UnitT = preload("res://scripts/unit.gd")

const ORDERS := [["move", "Идти"], ["fast", "Бегом"], ["back", "Задним ходом"], ["fire", "Огонь по…"],
	["face", "Развернуть"], ["hold", "Засада"], ["stop", "Стоп"], ["all", "Выбрать всех"], ["none", "Снять выбор"]]


class Card extends Button:
	var u
	var hud

	func _draw() -> void:
		if u == null:
			return
		var f := get_theme_default_font()
		var w := size.x
		var alive: bool = u.alive
		var tc := Color(0.93, 0.92, 0.84) if alive else Color(0.5, 0.5, 0.46)
		var sel: bool = hud.battle.selection.has(u)
		if sel:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 1.0, 0.5), false, 3.0)
		draw_rect(Rect2(6, 6, 34, 16), Color(0.25, 0.48, 0.9) if alive else Color(0.3, 0.3, 0.3))
		draw_string(f, Vector2(6, 19), u.t.short, HORIZONTAL_ALIGNMENT_CENTER, 34, 12, Color.WHITE)
		var nm: String = u.t.name
		if nm.length() > 16:
			nm = nm.substr(0, 15) + "…"
		draw_string(f, Vector2(44, 20), nm, HORIZONTAL_ALIGNMENT_LEFT, w - 48, 13, tc)
		var st: float = u.strength() if alive else 0.0
		draw_rect(Rect2(6, 28, w - 12, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(6, 28, (w - 12) * st, 6), Color(1.0 - st, 0.3 + st * 0.6, 0.2))
		var line := ""
		if not alive:
			line = "потерян"
		elif u.is_veh:
			line = "экипаж %d/%d" % [u.crew, u.start_crew]
		else:
			line = "бойцов %d/%d" % [u.alive_men(), u.start_men]
		var sc := tc
		if alive:
			if u.state == UnitT.ST_ROUT:
				line = "отступает"
				sc = Color(1.0, 0.5, 0.4)
			elif u.state == UnitT.ST_PINNED:
				line = "прижат!"
				sc = Color(1.0, 0.85, 0.3)
			elif u.immobile:
				line = "обездвижен"
				sc = Color(1.0, 0.65, 0.4)
		draw_string(f, Vector2(6, 52), line, HORIZONTAL_ALIGNMENT_LEFT, w - 12, 13, sc)
		if alive and u.suppression > 5.0 and not u.is_veh:
			draw_rect(Rect2(6, 36, (w - 12) * u.suppression / 100.0, 3), Color(1.0, 0.85, 0.2))


var battle
var top: PanelContainer
var b_menu: Button
var b_pause: Button
var b_speed: Button
var l_time: Label
var l_flags: RichTextLabel
var l_score: Label
var b_arty: Button
var b_smoke: Button
var orders: PanelContainer
var ob := {}
var roster_panel: PanelContainer
var roster: HBoxContainer
var b_multi: Button
var multi := false
var cards: Array = []
var info: Label
var msgs: VBoxContainer
var hint: Label
var pause_lbl: Label
var deploy_btn: Button
var menu_pop: PanelContainer
var result_pop: PanelContainer
var b_sound: Button
var redraw_t := 0.0
var margins := Vector4.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.make_theme()


func build() -> void:
	# --- верхняя панель ---
	top = PanelContainer.new()
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	top.add_child(hb)
	b_menu = UI.btn("Меню", _open_menu, Vector2(84, 46))
	b_pause = UI.btn("Пауза", func(): battle.toggle_pause(), Vector2(96, 46))
	b_speed = UI.btn("×1", func(): battle.cycle_speed(), Vector2(60, 46))
	hb.add_child(b_menu)
	hb.add_child(b_pause)
	hb.add_child(b_speed)
	l_time = UI.label("15:00", 22, UI.ACCENT)
	l_time.custom_minimum_size = Vector2(76, 0)
	l_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l_time)
	l_flags = RichTextLabel.new()
	l_flags.bbcode_enabled = true
	l_flags.fit_content = true
	l_flags.scroll_active = false
	l_flags.autowrap_mode = TextServer.AUTOWRAP_OFF
	l_flags.custom_minimum_size = Vector2(150, 30)
	l_flags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l_flags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_flags.add_theme_font_size_override("normal_font_size", 20)
	l_flags.add_theme_font_size_override("bold_font_size", 20)
	hb.add_child(l_flags)
	l_score = UI.label("", 18)
	l_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l_score)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	b_arty = UI.btn("Артналёт", func(): battle.set_order_mode("arty"), Vector2(140, 46))
	b_smoke = UI.btn("Дым", func(): battle.set_order_mode("smoke"), Vector2(96, 46))
	hb.add_child(b_arty)
	hb.add_child(b_smoke)
	# --- приказы ---
	orders = PanelContainer.new()
	add_child(orders)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	orders.add_child(vb)
	for o in ORDERS:
		var id: String = o[0]
		var b := UI.btn(o[1], _order.bind(id), Vector2(168, 46))
		b.add_theme_font_size_override("font_size", 18)
		vb.add_child(b)
		ob[id] = b
	# --- карточки отрядов ---
	roster_panel = PanelContainer.new()
	add_child(roster_panel)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 6)
	roster_panel.add_child(rh)
	b_multi = UI.btn("+", _toggle_multi, Vector2(48, 62))
	b_multi.add_theme_font_size_override("font_size", 26)
	rh.add_child(b_multi)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rh.add_child(sc)
	roster = HBoxContainer.new()
	roster.add_theme_constant_override("separation", 6)
	sc.add_child(roster)
	var mine: Array = []
	for u in battle.units:
		if u.side == battle.player_side:
			mine.append(u)
	var order := {"inf": 0, "team": 1, "gun": 2, "veh": 3}
	mine.sort_custom(func(a, b): return order[a.t.cat] < order[b.t.cat])
	for u in mine:
		var c := Card.new()
		c.u = u
		c.hud = self
		c.custom_minimum_size = Vector2(150, 62)
		c.focus_mode = Control.FOCUS_NONE
		c.pressed.connect(_card.bind(u))
		roster.add_child(c)
		cards.append(c)
	# --- сводка и сообщения ---
	info = UI.label("", 16)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	info.add_theme_constant_override("outline_size", 5)
	add_child(info)
	msgs = VBoxContainer.new()
	msgs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(msgs)
	hint = UI.label("", 20, UI.ACCENT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	pause_lbl = UI.label("ПАУЗА — можно отдавать приказы", 22, Color(1, 1, 1, 0.85))
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pause_lbl.add_theme_constant_override("outline_size", 6)
	pause_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pause_lbl)
	deploy_btn = UI.btn("В БОЙ!", func(): battle.start_battle(), Vector2(200, 64))
	deploy_btn.add_theme_font_size_override("font_size", 26)
	deploy_btn.add_theme_stylebox_override("normal", UI.box(Color(0.45, 0.22, 0.12, 0.95), UI.ACCENT, 8, 2))
	add_child(deploy_btn)
	_build_menu()
	_layout()
	get_viewport().size_changed.connect(_layout)
	refresh()


func _build_menu() -> void:
	menu_pop = PanelContainer.new()
	add_child(menu_pop)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	menu_pop.add_child(vb)
	var t := UI.label("Меню боя", 26, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(UI.btn("Продолжить", _close_menu, Vector2(320, 58)))
	b_sound = UI.btn("Звук: вкл", _toggle_sound, Vector2(320, 58))
	vb.add_child(b_sound)
	vb.add_child(UI.btn("Подсказка по управлению", _show_help, Vector2(320, 58)))
	vb.add_child(UI.btn("Отступить (сдаться)", _surrender, Vector2(320, 58)))
	vb.add_child(UI.btn("Выйти в главное меню", func(): battle.leave(), Vector2(320, 58)))
	menu_pop.visible = false
	result_pop = PanelContainer.new()
	add_child(result_pop)
	result_pop.visible = false


func _layout() -> void:
	if top == null:
		return
	margins = UI.safe(self)
	var vs := get_viewport_rect().size
	var ml := maxf(margins.x, 6.0)
	var mr := maxf(margins.z, 6.0)
	top.position = Vector2(ml, 4)
	top.size = Vector2(vs.x - ml - mr, 56)
	orders.position = Vector2(vs.x - mr - 188, 68)
	orders.size = Vector2(188, 0)
	roster_panel.position = Vector2(ml, vs.y - 80)
	roster_panel.size = Vector2(vs.x - ml - mr - 196, 76)
	info.position = Vector2(ml + 6, vs.y - 112)
	info.size = Vector2(vs.x - ml - mr - 220, 28)
	msgs.position = Vector2(ml + 6, 68)
	msgs.size = Vector2(minf(620.0, vs.x * 0.5), 200)
	hint.position = Vector2(vs.x * 0.5 - 300, 70)
	hint.size = Vector2(600, 30)
	pause_lbl.position = Vector2(vs.x * 0.5 - 300, 104)
	pause_lbl.size = Vector2(600, 30)
	deploy_btn.position = Vector2(vs.x - mr - 210, vs.y - 80)
	deploy_btn.size = Vector2(204, 72)
	_center(menu_pop)
	_center(result_pop)


func _center(c: Control) -> void:
	c.reset_size()
	c.position = (get_viewport_rect().size - c.get_combined_minimum_size()) * 0.5


## Касание приходится на элемент интерфейса — карта его не получает.
func blocks(p: Vector2) -> bool:
	if menu_pop.visible or result_pop.visible:
		return true
	for c in [top, orders, roster_panel, deploy_btn]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false


func refresh() -> void:
	if top == null:
		return
	var b = battle
	var deploy: bool = b.phase == "deploy"
	var fighting: bool = b.phase == "battle"
	deploy_btn.visible = deploy
	orders.visible = fighting and not b.selection.is_empty()
	b_pause.disabled = not fighting
	b_pause.text = "Пуск" if b.paused else "Пауза"
	UI.set_on(b_pause, b.paused)
	b_speed.text = "×%d" % int(b.speed)
	b_arty.text = "Артналёт (%d)" % b.arty[b.player_side][0]
	b_smoke.text = "Дым (%d)" % b.arty[b.player_side][1]
	b_arty.disabled = not fighting or b.arty[b.player_side][0] <= 0
	b_smoke.disabled = not fighting or b.arty[b.player_side][1] <= 0
	UI.set_on(b_arty, b.order_mode == "arty")
	UI.set_on(b_smoke, b.order_mode == "smoke")
	var any_veh := false
	var all_hold: bool = not b.selection.is_empty()
	for u in b.selection:
		if u.is_veh:
			any_veh = true
		if not u.hold_fire:
			all_hold = false
	ob["back"].visible = any_veh
	UI.set_on(ob["move"], b.order_mode == "")
	for id in ["fast", "back", "fire", "face"]:
		UI.set_on(ob[id], b.order_mode == id)
	UI.set_on(ob["hold"], all_hold)
	UI.set_on(b_multi, multi)
	for c in cards:
		c.queue_redraw()
	match b.order_mode:
		"fast":
			hint.text = "Бегом: коснитесь точки или проведите путь от отряда"
		"back":
			hint.text = "Задним ходом: коснитесь точки (лоб остаётся к противнику)"
		"fire":
			hint.text = "Огонь: коснитесь врага или участка для обстрела по площади"
		"face":
			hint.text = "Коснитесь, куда развернуться"
		"arty":
			hint.text = "Артналёт: коснитесь цели (залп через %d с)" % 12
		"smoke":
			hint.text = "Дымовая завеса: коснитесь места"
		_:
			hint.text = "Расстановка: выберите отряд, затем коснитесь места в зелёной зоне" if deploy else ""


func _order(id: String) -> void:
	var b = battle
	match id:
		"move":
			b.order_mode = ""
			b.hud.refresh()
		"fast", "back", "fire", "face":
			b.set_order_mode(id)
		"hold":
			b.toggle_hold()
		"stop":
			b.order_stop()
		"all":
			b.select_all()
		"none":
			b.clear_selection()


func _card(u) -> void:
	if not u.alive:
		return
	if multi:
		battle.toggle_select(u)
		return
	if battle.selection.size() == 1 and battle.selection[0] == u:
		battle.center_on(u.position)
	else:
		battle.select_only(u)


func _toggle_multi() -> void:
	multi = not multi
	refresh()


func msg(text: String, col := Color(0.93, 0.92, 0.84)) -> void:
	if msgs == null:
		return
	var l := UI.label(text, 17, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.set_meta("t", 7.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msgs.add_child(l)
	while msgs.get_child_count() > 6:
		var c := msgs.get_child(0)
		msgs.remove_child(c)
		c.queue_free()


func _process(delta: float) -> void:
	if top == null:
		return
	var b = battle
	var tl := maxf(0.0, b.time_left)
	l_time.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	var fs := "Точки: "
	for f in b.flags:
		var c := "#c8c8c8"
		if f.owner == b.player_side:
			c = "#6fa8ff"
		elif f.owner >= 0:
			c = "#ff6a55"
		fs += "[color=%s][b]%s[/b][/color] " % [c, f.name]
	l_flags.text = fs
	l_score.text = "Очки %d : %d" % [b.score(b.player_side), b.score(1 - b.player_side)]
	pause_lbl.visible = b.paused and b.phase == "battle"
	for c in msgs.get_children():
		var t: float = c.get_meta("t") - delta
		c.set_meta("t", t)
		if t < 1.0:
			c.modulate.a = maxf(t, 0.0)
		if t <= 0.0:
			c.queue_free()
	redraw_t -= delta
	if redraw_t <= 0.0:
		redraw_t = 0.25
		for c in cards:
			c.queue_redraw()
		info.text = _info_text()


func _info_text() -> String:
	var sel: Array = battle.selection
	if sel.is_empty():
		return "Коснитесь своего отряда, чтобы выбрать. Долгое касание — добавить к выбору." if battle.phase == "battle" else ""
	if sel.size() > 1:
		return "Выбрано отрядов: %d. Коснитесь карты — двигаться, врага — атаковать." % sel.size()
	var u = sel[0]
	var parts: PackedStringArray = [u.t.name]
	if u.is_veh:
		parts.append("экипаж %d/%d" % [u.crew, u.start_crew])
		parts.append("броня %d/%d/%d" % [u.t.armor[0], u.t.armor[1], u.t.armor[2]])
		if u.t.gun != "":
			parts.append(Data.W[u.t.gun].name)
	else:
		parts.append("бойцов %d/%d" % [u.alive_men(), u.start_men])
		if u.is_gun:
			parts.append(Data.W[u.t.gun].name)
	parts.append(u.status_text())
	if u.kills > 0:
		parts.append("уничтожено: %d" % u.kills)
	return " · ".join(parts)


func _open_menu() -> void:
	if battle.phase == "over":
		result_pop.visible = true
		return
	menu_pop.set_meta("was_paused", battle.paused)
	battle.paused = true
	menu_pop.visible = true
	b_sound.text = "Звук: выкл" if battle.sfx.muted else "Звук: вкл"
	_center(menu_pop)
	refresh()


func _surrender() -> void:
	_close_menu()
	battle.surrender()


func _close_menu() -> void:
	menu_pop.visible = false
	battle.paused = menu_pop.get_meta("was_paused", false)
	refresh()


func _toggle_sound() -> void:
	battle.sfx.muted = not battle.sfx.muted
	b_sound.text = "Звук: выкл" if battle.sfx.muted else "Звук: вкл"
	var mn = get_tree().root.get_node_or_null("Main")
	if mn != null and mn.has_method("set_muted"):
		mn.set_muted(battle.sfx.muted)


func _show_help() -> void:
	msg("Касание отряда — выбрать, касание карты — идти, касание врага — атаковать.", Color(0.8, 0.95, 1.0))
	msg("Проведите пальцем от выбранного отряда — маршрут. Долгое касание: добавить отряд / развернуться.", Color(0.8, 0.95, 1.0))
	msg("Один палец по пустой карте — прокрутка, два пальца — масштаб. Пауза не мешает отдавать приказы.", Color(0.8, 0.95, 1.0))
	_close_menu()


func show_result(r: Dictionary) -> void:
	for c in result_pop.get_children():
		c.queue_free()
	menu_pop.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	result_pop.add_child(vb)
	var me: int = battle.player_side
	var title := "НИЧЬЯ"
	var tc := UI.ACCENT
	if r.winner == me:
		title = "ПОБЕДА"
		tc = Color(0.6, 1.0, 0.5)
	elif r.winner >= 0:
		title = "ПОРАЖЕНИЕ"
		tc = Color(1.0, 0.5, 0.4)
	var t := UI.label(title, 40, tc)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var rs := UI.label(r.reason, 20)
	rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(rs)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	vb.add_child(g)
	var L: Array = r.losses
	var rows := [["", "Вы", "Противник"],
		["Очки", str(r.score[me]), str(r.score[1 - me])],
		["Точки", str(r.flags[me]), str(r.flags[1 - me])],
		["Потеряно бойцов", str(L[me].men), str(L[1 - me].men)],
		["Потеряно техники", str(L[me].veh), str(L[1 - me].veh)],
		["Потеряно отрядов", "%d из %d" % [L[me].units, r.start[me]], "%d из %d" % [L[1 - me].units, r.start[1 - me]]],
		["Стоимость потерь", str(L[me].cost), str(L[1 - me].cost)]]
	for row in rows:
		for i in 3:
			var l := UI.label(row[i], 19, UI.ACCENT if i == 0 or row[0] == "" else UI.TEXT)
			g.add_child(l)
	var tm := UI.label("Длительность боя: %d:%02d" % [int(r.time) / 60, int(r.time) % 60], 17)
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tm)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	vb.add_child(row2)
	row2.add_child(UI.btn("Осмотреть поле", func(): result_pop.visible = false, Vector2(220, 58)))
	row2.add_child(UI.btn("В главное меню", func(): battle.leave(), Vector2(220, 58)))
	result_pop.visible = true
	await get_tree().process_frame
	_center(result_pop)
	refresh()
