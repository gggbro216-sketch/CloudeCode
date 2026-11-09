extends Node
## Экран кампании «Дороги войны»: выбор стороны, лента операций, линия фронта, миссии операции,
## выбор танка из парка и «В бой». Логика и сохранение — campaign.gd.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const C = preload("res://scripts/campaign_data.gd")
const Camp = preload("res://scripts/campaign.gd")

var main: Node
var root: Control
var body: VBoxContainer
var pick := ""  # выбранный танк


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(UI.BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var s := UI.safe(root)
	for side in [["left", s.x], ["right", s.z], ["top", s.y], ["bottom", s.w]]:
		m.add_theme_constant_override("margin_" + String(side[0]), 16 + int(side[1]))
	root.add_child(m)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	m.add_child(body)
	_refresh()


func _clear() -> void:
	for c in body.get_children():
		c.queue_free()


func _btn(text: String, cb: Callable, w := 0.0, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 48)
	b.add_theme_font_size_override("font_size", 16)
	if accent:
		UI.accent(b, 20)
	b.pressed.connect(cb)
	return b


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _head(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	body.add_child(h)
	h.add_child(UI.label(title, 26, D.AMBER))
	h.add_child(_spacer())
	return h


func _refresh() -> void:
	_clear()
	if not Camp.active(main.save):
		_choose_side()
	elif bool(main.save.campaign.get("done", false)):
		_final()
	else:
		_operation()


## Начало: за кого воевать.
func _choose_side() -> void:
	var h := _head("КАМПАНИЯ «ДОРОГИ ВОЙНЫ»")
	h.add_child(_btn("В АНГАР", func(): main.show_hangar(), 150))
	var intro := UI.label("Девять операций по хронологии войны — от Халхин-Гола до Берлина, по три миссии в каждой: атака позиций, "
		+ "оборона рубежа, встречные бои и танковые сражения. Победы двигают линию фронта операции. Танки дают из парка "
		+ "операции — любые машины своего времени; подбитый уходит в ремонт, взорванный — потерян до конца операции. "
		+ "Опыт и серебро идут в общий прогресс (×%s), экипажи учатся." % String.num(C.REWARD_K, 2).replace(".", ","), 16, UI.DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for side in ["allies", "axis"]:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		pc.add_child(v)
		v.add_child(UI.label("ЗА СОЮЗНИКОВ" if side == "allies" else "ЗА ОСЬ", 24))
		var who := UI.label("СССР, Франция, Великобритания, США" if side == "allies" else "Германия, Япония, Италия, Венгрия", 15, UI.DIM)
		v.add_child(who)
		var first: Dictionary = C.OPS[0][side][0]
		var t := UI.label("Первая миссия: «%s». %s" % [first.title, first.brief], 14)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(t)
		var sd: String = side
		v.add_child(_btn("НАЧАТЬ", func():
			Camp.start(main.save, sd)
			main.persist()
			_refresh(), 0, true))


## Текущая операция: лента операций, фронт, миссии, парк и «В бой».
func _operation() -> void:
	var cs: Dictionary = main.save.campaign
	var op := Camp.op_of(cs)
	var h := _head("%s · %s" % [String(op.name).to_upper(), op.date])
	h.add_child(UI.label("ЗА СОЮЗНИКОВ" if cs.side == "allies" else "ЗА ОСЬ", 15, UI.DIM))
	h.add_child(_btn("НАЧАТЬ ЗАНОВО", _confirm_restart, 170))
	h.add_child(_btn("В АНГАР", func(): main.show_hangar(), 140))
	var last: Dictionary = cs.get("last", {})
	if not last.is_empty():
		var ll := UI.label(String(last.msg), 15, "7bc65a" if last.result == "win" else ("e2563c" if last.result == "lose" else UI.AMBER))
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(ll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	# слева: лента операций
	var lp := PanelContainer.new()
	lp.custom_minimum_size = Vector2(250, 0)
	row.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 3)
	lp.add_child(lv)
	lv.add_child(UI.label("ОПЕРАЦИИ", 13, UI.DIM))
	for i in C.OPS.size():
		var o: Dictionary = C.OPS[i]
		var mark := "▸ " if i == int(cs.op) else "   "
		var col := UI.TEXT if i == int(cs.op) else UI.DIM
		var tail := ""
		if i < cs.ops.size():
			tail = " — выиграна" if bool(cs.ops[i].won) else " — проиграна"
			col = "7bc65a" if bool(cs.ops[i].won) else "e2563c"
		lv.add_child(UI.label("%s%s, %s%s" % [mark, o.name, String(o.date).split(" ")[-1], tail], 14, col))
	# справа: фронт, миссии, задача, парк
	var rp := PanelContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(sc)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 8)
	sc.add_child(rv)
	rv.add_child(_front_bar(int(cs.front)))
	var missions: Array = op[cs.side]
	for i in missions.size():
		var mm: Dictionary = missions[i]
		var st := "сейчас" if i == int(cs.mi) else ("пройдена" if i < int(cs.mi) else "впереди")
		rv.add_child(UI.label("%d. %s — «%s» (%s)" % [i + 1, C.KIND_NAMES[mm.kind], mm.title, st], 15,
			UI.AMBER if i == int(cs.mi) else (UI.DIM if i > int(cs.mi) else UI.TEXT)))
	var m := Camp.mission_of(cs)
	var br := UI.label(String(m.brief), 15)
	br.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(br)
	var task := UI.label("Задача: " + String(C.KINDS[m.kind].task), 14, UI.AMBER)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(task)
	# парк операции
	rv.add_child(UI.label("ПАРК ОПЕРАЦИИ — выберите танк", 13, UI.DIM))
	var ready := Camp.ready_tanks(cs)
	if pick == "" or not ready.has(pick):
		pick = ready[0] if not ready.is_empty() else ""
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	rv.add_child(flow)
	for k in Camp.park(cs):
		var state := Camp.tank_state(cs, k)
		var T: Dictionary = D.TYPES[k]
		var b := Button.new()
		var note: String = {"ready": "готов", "repair": "в ремонте", "lost": "потерян"}[state]
		if state != "ready" and ready.has(k):
			note = "из резерва"  # всё в ремонте или потеряно — машину дают из резерва
		b.text = "%s %s\n%s" % [["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][clampi(D.tier(k), 0, 8)], T.tag, note]
		b.custom_minimum_size = Vector2(118, 52)
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = not ready.has(k)
		if k == pick:
			b.modulate = Color(1.0, 0.86, 0.5)
		var kk: String = k
		b.pressed.connect(func():
			pick = kk
			_refresh())
		flow.add_child(b)
	var go := HBoxContainer.new()
	body.add_child(go)
	var info := UI.label("Танк: %s%s" % [D.TYPES[pick].name if pick != "" else "—",
		"" if pick == "" or main.save.owned.has(pick) else " (из парка, опыт — в свободный)"], 15, UI.DIM)
	go.add_child(info)
	go.add_child(_spacer())
	var gb := _btn("В БОЙ", func(): main.start_mission(pick), 220, true)
	gb.disabled = pick == ""
	go.add_child(gb)


func _front_bar(v: int) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UI.label("ЛИНИЯ ФРОНТА: %d из 100 (операция выиграна, если к концу не ниже %d)" % [v, C.FRONT_WIN], 14, UI.DIM))
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = v
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("7bc65a") if v >= C.FRONT_WIN else (Color(UI.AMBER) if v >= 40 else Color("e2563c"))
	bar.add_theme_stylebox_override("fill", fill)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.05, 0.06, 0.04)
	bar.add_theme_stylebox_override("background", bgs)
	box.add_child(bar)
	return box


func _confirm_restart() -> void:
	_clear()
	_head("НАЧАТЬ КАМПАНИЮ ЗАНОВО?")
	body.add_child(UI.label("Весь путь кампании будет сброшен. Опыт, серебро и экипажи, заработанные в ней, останутся.", 16, UI.DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	row.add_child(_btn("ДА, ЗАНОВО", func():
		main.save.campaign = {}
		main.persist()
		_refresh(), 220, true))
	row.add_child(_btn("НЕТ", _refresh, 160))


## Конец кампании: итог по операциям и бонус серебра (один раз).
func _final() -> void:
	var cs: Dictionary = main.save.campaign
	var won := Camp.ops_won(cs)
	if int(cs.get("bonus", 0)) == 0:
		cs.bonus = maxi(1, won * C.FINAL_BONUS)
		main.save.silver = int(main.save.silver) + won * C.FINAL_BONUS
		main.persist()
	var h := _head("КАМПАНИЯ ОКОНЧЕНА")
	h.add_child(_btn("В АНГАР", func(): main.show_hangar(), 150))
	body.add_child(UI.label("Выиграно операций: %d из %d. Бонус: %s серебра." % [won, C.OPS.size(), str(won * C.FINAL_BONUS)], 22))
	for i in mini(cs.ops.size(), C.OPS.size()):
		var o: Dictionary = C.OPS[i]
		body.add_child(UI.label("%s, %s — %s (фронт %d)" % [o.name, o.date, "выиграна" if bool(cs.ops[i].won) else "проиграна",
			int(cs.ops[i].front)], 16, "7bc65a" if bool(cs.ops[i].won) else "e2563c"))
	body.add_child(_btn("НОВАЯ КАМПАНИЯ", func():
		main.save.campaign = {}
		main.persist()
		_refresh(), 260, true))
