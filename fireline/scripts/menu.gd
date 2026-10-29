extends Control
## Главное меню: титульный экран, подготовка боя (сценарий, сторона, состав по очкам) и справка.

const UI = preload("res://scripts/ui.gd")
const Data = preload("res://scripts/data.gd")

const MODES := {"meeting": "Встречный бой", "attack": "Наступление", "defend": "Оборона"}

var main
var page: Control
var sc_idx := 0
var faction := "us"
var army := {}
var sc_btns: Array = []
var f_btns := {}
var l_title: Label
var l_desc: Label
var l_info: Label
var l_enemy: Label
var l_budget: Label
var rows: VBoxContainer
var counts := {}
var start_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme()
	if main != null:
		faction = main.settings.get("faction", "us")
		sc_idx = clampi(int(main.settings.get("scenario", 0)), 0, Data.SCENARIOS.size() - 1)
	_title_page()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.09, 0.10, 0.07))
	# топографическая сетка и горизонтали — фон в духе штабной карты
	var c := Color(0.20, 0.24, 0.15, 0.35)
	var x := 0.0
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), c, 1.0)
		x += 64.0
	var y := 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), c, 1.0)
		y += 64.0
	for k in 7:
		var pts := PackedVector2Array()
		for i in 41:
			var t := float(i) / 40.0
			pts.append(Vector2(t * s.x, s.y * (0.15 + k * 0.12) + sin(t * 7.0 + k * 1.3) * 26.0 + sin(t * 17.0 + k) * 9.0))
		draw_polyline(pts, Color(0.35, 0.30, 0.18, 0.22), 2.0)


func _clear() -> void:
	if page != null:
		page.queue_free()
	page = MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := UI.safe(self)
	page.add_theme_constant_override("margin_left", int(maxf(m.x, 24.0)))
	page.add_theme_constant_override("margin_right", int(maxf(m.z, 24.0)))
	page.add_theme_constant_override("margin_top", 18)
	page.add_theme_constant_override("margin_bottom", 14)
	add_child(page)


# ===================== Титульный экран =====================

func _title_page() -> void:
	_clear()
	var cc := CenterContainer.new()
	page.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	var t := UI.label("ОГНЕВОЙ РУБЕЖ", 64, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 10)
	vb.add_child(t)
	var st := UI.label("Тактика Второй мировой в реальном времени с активной паузой", 21)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(st)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	vb.add_child(gap)
	for b in [["Новый бой", _setup_page], ["Как играть", _help_page], ["", _toggle_sound], ["Выход", func(): get_tree().quit()]]:
		var bt := UI.btn(b[0], b[1], Vector2(380, 64))
		bt.add_theme_font_size_override("font_size", 24)
		if b[0] == "":
			bt.text = _sound_text()
			bt.set_meta("sound", true)
		var row := CenterContainer.new()
		row.add_child(bt)
		vb.add_child(row)


func _sound_text() -> String:
	return "Звук: выкл" if main != null and main.muted else "Звук: вкл"


func _toggle_sound() -> void:
	if main != null:
		main.set_muted(not main.muted)
	_title_page()


# ===================== Подготовка боя =====================

func _setup_page() -> void:
	_clear()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	page.add_child(root)
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 12)
	root.add_child(hb)
	# сценарии
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	hb.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UI.label("Сценарий", 22, UI.ACCENT))
	sc_btns.clear()
	for i in Data.SCENARIOS.size():
		var b := UI.btn(Data.SCENARIOS[i].name, _pick_sc.bind(i), Vector2(0, 54))
		lv.add_child(b)
		sc_btns.append(b)
	# описание и сторона
	var mid := PanelContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mid)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mid.add_child(mv)
	l_title = UI.label("", 28, UI.ACCENT)
	mv.add_child(l_title)
	l_info = UI.label("", 17, Color(0.75, 0.8, 0.65))
	mv.add_child(l_info)
	l_desc = UI.label("", 19)
	l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_desc.custom_minimum_size = Vector2(200, 0)
	mv.add_child(l_desc)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(sp)
	mv.add_child(UI.label("Ваша сторона", 21, UI.ACCENT))
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 8)
	mv.add_child(fh)
	f_btns.clear()
	for f in ["us", "su", "de"]:
		var b := UI.btn(Data.FACTIONS[f].name, _pick_faction.bind(f), Vector2(120, 54))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fh.add_child(b)
		f_btns[f] = b
	l_enemy = UI.label("", 18)
	mv.add_child(l_enemy)
	# состав
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	hb.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	l_budget = UI.label("", 21, UI.ACCENT)
	rv.add_child(l_budget)
	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scr)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scr.add_child(rows)
	var ab := HBoxContainer.new()
	ab.add_theme_constant_override("separation", 8)
	rv.add_child(ab)
	var auto := UI.btn("Авто-состав", _auto_army, Vector2(0, 50))
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab.add_child(auto)
	var clr := UI.btn("Очистить", _clear_army, Vector2(0, 50))
	clr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab.add_child(clr)
	# низ
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 12)
	root.add_child(bot)
	bot.add_child(UI.btn("Назад", _title_page, Vector2(180, 60)))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp2)
	start_btn = UI.btn("В БОЙ!", _start, Vector2(260, 60))
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.add_theme_stylebox_override("normal", UI.box(Color(0.45, 0.22, 0.12, 0.95), UI.ACCENT, 8, 2))
	bot.add_child(start_btn)
	_pick_sc(sc_idx)


func _pick_sc(i: int) -> void:
	sc_idx = i
	for k in sc_btns.size():
		UI.set_on(sc_btns[k], k == i)
	var sc: Dictionary = Data.SCENARIOS[i]
	l_title.text = sc.name
	l_desc.text = sc.desc
	l_info.text = "%s · %d мин · бюджет %d очков" % [MODES[sc.mode], int(sc.time / 60.0), sc.budget]
	_pick_faction(faction)


func _pick_faction(f: String) -> void:
	faction = f
	for k in f_btns:
		UI.set_on(f_btns[k], k == f)
	var en := "Германия" if f != "de" else "США или СССР (случайно)"
	var sc: Dictionary = Data.SCENARIOS[sc_idx]
	var mult: float = sc.enemy
	var tail := ""
	if mult > 1.05:
		tail = " — превосходит вас на %d%%" % int((mult - 1.0) * 100.0)
	elif mult < 0.95:
		tail = " — слабее, но в укрытиях"
	l_enemy.text = "Противник: %s%s" % [en, tail]
	_rebuild_rows()
	_auto_army()


func _auto_army() -> void:
	var sc: Dictionary = Data.SCENARIOS[sc_idx]
	army.clear()
	for id in Data.auto_army(faction, sc.budget, sc.get("armor", false)):
		army[id] = int(army.get(id, 0)) + 1
	_update_army()


func _clear_army() -> void:
	army.clear()
	_update_army()


func _rebuild_rows() -> void:
	for c in rows.get_children():
		c.queue_free()
	counts.clear()
	for id in Data.faction_units(faction):
		var u: Dictionary = Data.U[id]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		rows.add_child(r)
		var nm := UI.label("%s" % u.name, 17)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(150, 0)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(nm)
		var cost := UI.label(str(u.cost), 17, UI.ACCENT)
		cost.custom_minimum_size = Vector2(40, 0)
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(cost)
		r.add_child(UI.btn("-", _change.bind(id, -1), Vector2(48, 44)))
		var n := UI.label("0", 20)
		n.custom_minimum_size = Vector2(30, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(n)
		counts[id] = n
		r.add_child(UI.btn("+", _change.bind(id, 1), Vector2(48, 44)))


func _army_list() -> Array:
	var out: Array = []
	for id in Data.faction_units(faction):
		for i in int(army.get(id, 0)):
			out.append(id)
	return out


func _change(id: String, d: int) -> void:
	var sc: Dictionary = Data.SCENARIOS[sc_idx]
	var n := int(army.get(id, 0)) + d
	if n < 0:
		return
	if d > 0 and Data.army_cost(_army_list()) + int(Data.U[id].cost) > int(sc.budget):
		return
	army[id] = n
	_update_army()


func _update_army() -> void:
	var sc: Dictionary = Data.SCENARIOS[sc_idx]
	var cost := Data.army_cost(_army_list())
	l_budget.text = "Состав: %d / %d очков" % [cost, sc.budget]
	for id in counts:
		counts[id].text = str(army.get(id, 0))
	start_btn.disabled = _army_list().is_empty()


func _start() -> void:
	var sc: Dictionary = Data.SCENARIOS[sc_idx]
	var ef := Data.enemy_of(faction)
	var cfg := {
		"scenario": sc, "faction": faction, "enemy_faction": ef, "army": _army_list(),
		"enemy_army": Data.auto_army(ef, int(sc.budget * float(sc.enemy)), sc.get("armor", false)),
		"seed": randi(), "muted": main.muted if main != null else false,
	}
	if main != null:
		main.settings["faction"] = faction
		main.settings["scenario"] = sc_idx
		main.save_settings()
		main.start_battle(cfg)


# ===================== Справка =====================

func _help_page() -> void:
	_clear()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	page.add_child(vb)
	vb.add_child(UI.label("Как играть", 30, UI.ACCENT))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("normal_font_size", 19)
	t.add_theme_font_size_override("bold_font_size", 19)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.text = HELP
	sc.add_child(t)
	vb.add_child(UI.btn("Назад", _title_page, Vector2(200, 58)))


const HELP := """[b][color=#f2c766]Цель боя.[/color][/b] На карте три точки (A, B, C). Удерживайте их своими отрядами — каждая приносит 150 очков к концу боя, плюс очки за уничтоженного противника. Бой заканчивается по времени, при разгроме одной из сторон или если кто-то удерживает все точки две минуты подряд.

[b][color=#f2c766]Расстановка.[/color][/b] Перед боем выберите отряд (касанием на карте или карточкой внизу) и коснитесь места в зелёной зоне. Когда готовы — «В БОЙ!».

[b][color=#f2c766]Управление.[/color][/b]
• Касание своего отряда — выбрать. Долгое касание — добавить к выбору (или кнопка «+» у карточек).
• Касание карты — идти туда. Касание видимого врага — атаковать его.
• Проведите пальцем от выбранного отряда — он пройдёт по нарисованному маршруту.
• Долгое касание пустой карты — развернуться в эту сторону.
• Один палец по пустой карте — прокрутка, два пальца — масштаб.
• Кнопки справа: «Бегом» (быстрее, но без стрельбы), «Задним ходом» (техника держит лоб к врагу), «Огонь по…» (по цели или по площади), «Развернуть», «Засада» (огонь только с близкой дистанции), «Стоп».
• «Пауза» останавливает бой, но приказы отдавать можно. «×1/×2/×3» — скорость.
• «Артналёт» и «Дым» — заявка на огонь батареи по точке на карте (через несколько секунд).

[b][color=#f2c766]Как устроен бой.[/color][/b]
• Туман войны: враг виден, только пока его замечает хоть один ваш отряд. Лес, изгороди, дома и дым закрывают обзор. Неподвижный отряд в укрытии заметить труднее, стреляющий — легче.
• Укрытия: бойцы сами расходятся по ближайшим укрытиям. Дом, изгородь и лес резко снижают потери. На открытом поле пехота уязвима.
• Подавление: под огнём отряд сначала залегает и стреляет хуже («!»), а при больших потерях отступает («<<»). Пулемёты подавляют сильнее всего.
• Броня: у техники лоб, борт и корма. Снаряд либо пробивает броню (жёлтые искры), либо рикошетит. Заходите во фланг и бейте в борт. Пехота с винтовками танку не страшна — нужны гранатомёты, противотанковые ружья и пушки.
• Миномёты стреляют навесом по любой цели, которую видит кто-то из ваших отрядов.
• Синие маркеры — ваши отряды, красные — замеченный противник, «?» — последнее известное место врага."""
