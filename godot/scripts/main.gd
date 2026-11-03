extends Node
## Корень игры: переключает ангар и бой, хранит прогресс игрока:
## серебро и опыт, исследованные и купленные танки, модули и снаряжение.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const HangarScript = preload("res://scripts/hangar.gd")
const BattleScript = preload("res://scripts/battle.gd")
const Native = preload("res://scripts/native.gd")
const SAVE_PATH := "user://save.json"

var save := {
	"battles": 0, "wins": 0, "kills": 0, "best_dmg": 0, "silver": D.START_SILVER, "free_xp": 0,
	"tank": "t34_76", "mode": "standard", "map": "random", "hq": true, "history": true, "res": 0.75, "eco": false,
	"owned": [], "researched": [], "txp": {}, "mods": {}, "mods_res": {}, "cons": ["repair", "medkit", "ext"],
	"tstats": {}, "last": {}, "ts": 0.0,
}
var hangar: Node
var battle: Node


const RES_STEPS := [0.6, 0.75, 0.9, 1.0]  # доля разрешения экрана для 3D (интерфейс — всегда в полном)


func _ready() -> void:
	_symbol_font()
	_load()
	_session_start()
	apply_res()
	apply_eco()
	show_hangar()


## Стрелки и треугольники (→ ▶ ▸ ◀) — из своего маленького шрифта: в браузере нет системных шрифтов,
## а во встроенном шрифте Godot этих знаков нет.
func _symbol_font() -> void:
	var fb: Font = ThemeDB.fallback_font
	var sym = load("res://assets/fonts/symbols.ttf")
	if fb and sym and not fb.fallbacks.has(sym):
		var arr: Array[Font] = fb.fallbacks.duplicate()
		arr.append(sym)
		fb.fallbacks = arr


# ---------- Журнал сеанса: если игра оборвётся, при следующем запуске ангар скажет, где и сколько было памяти ----------

const SESSION_PATH := "user://session.json"
var session := {"state": "hangar", "battles": 0, "hist": []}
var last_crash := {}  # прошлый запуск оборвался в бою: что о нём известно (показывает ангар)
var _session_t := 0.0
var _worst_frame := 0.0  # самый долгий кадр с прошлой отметки, с


func _session_start() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
		if d is Dictionary and (String(d.get("state", "")).begins_with("battle") or d.get("state") == "hangar_loading"):
			last_crash = d
	session_mark("hangar")


## Память всего процесса (вместе с драйвером видеокарты и C++), МБ; -1 — система не сообщает.
static func process_mb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1
	for i in 64:
		var l := f.get_line()
		if l.begins_with("VmRSS:"):
			return int(l.split(":")[1].strip_edges().split(" ")[0]) / 1024
		if f.eof_reached():
			break
	return -1


## Состояние сеанса и память — в файл (маленький, пишется при смене состояния и раз в 20 с в бою)
## и строкой в журнал движка (user://logs): по нему видно, росла ли память от боя к бою.
func session_mark(state: String, extra := {}) -> void:
	session.state = state
	session.merge(extra, true)
	session.ram_mb = roundi(OS.get_static_memory_usage() / 1048576.0)
	session.proc_mb = process_mb()
	session.video_mb = roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	var mi := OS.get_memory_info()
	session.free_mb = roundi(float(mi.get("available", -1048576)) / 1048576.0)
	session.fps = roundi(Engine.get_frames_per_second())
	session.worst_ms = roundi(_worst_frame * 1000.0)
	session.nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	session.objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nc: Object = Native.shared()
	session.cores = int(nc.cores_alive()) if nc and nc.has_method("cores_alive") else -1
	_worst_frame = 0.0
	if battle:
		session.clock = roundi(battle.clock)
	var hist: Array = session.hist
	if state == "battle" and not hist.is_empty():
		# пик памяти текущего боя
		var h: Array = hist[-1]
		h[3] = maxi(int(h[3]), int(session.proc_mb))
		h[4] = maxi(int(h[4]), int(session.ram_mb))
		h[5] = maxi(int(h[5]), int(session.video_mb))
	print("[сеанс] %s, бой %d, %d с: Godot %d МБ, процесс %d МБ, видео %d МБ, свободно в системе %d МБ, %d кадров/с, худший кадр %d мс, узлов %d, ядер C++ %d" % [
		state, int(session.battles), int(session.get("clock", 0)), session.ram_mb, session.proc_mb, session.video_mb,
		session.free_mb, session.fps, session.worst_ms, session.nodes, session.cores])
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))


## Новая строка истории боёв: [номер, карта, память процесса после загрузки, её пик, пик Godot, пик видео].
func _hist_begin(map_key: String) -> void:
	var hist: Array = session.hist
	hist.append([int(session.battles), map_key, process_mb(), 0, 0, 0])
	while hist.size() > 6:
		hist.pop_front()


func _process(delta: float) -> void:
	_worst_frame = maxf(_worst_frame, delta)
	if battle and String(session.state) == "battle":
		_session_t -= delta
		if _session_t <= 0.0:
			_session_t = 20.0
			session_mark("battle")


## 3D рисуется в уменьшенном разрешении и растягивается — главная экономия видеокарты на экране 1440p.
func apply_res() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(save.res)


## Режим экономии батареи: не больше 30 кадров в секунду — заметно меньше работы процессору и видеокарте.
func apply_eco() -> void:
	Engine.max_fps = 30 if save.eco else 0  # 0 — по частоте экрана, как раньше


func toggle_eco() -> void:
	save.eco = not save.eco
	apply_eco()
	persist()


func cycle_res() -> void:
	var i := RES_STEPS.find(float(save.res))
	save.res = RES_STEPS[(i + 1) % RES_STEPS.size()]
	apply_res()
	persist()


func _load() -> void:
	var fresh := true
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				fresh = not d.has("owned")
				for k in d:
					if save.has(k):
						save[k] = d[k]
	_migrate_keys()
	if fresh:
		# первый запуск или сохранение до появления исследований: стартовые танки и серебро на первую покупку
		save.silver = maxi(int(save.silver), D.START_SILVER)
	for k in D.STARTERS:
		if not save.owned.has(k):
			save.owned.append(k)
		if not save.researched.has(k):
			save.researched.append(k)
	# защита от устаревших значений
	save.owned = save.owned.filter(func(k): return D.TYPES.has(k))
	save.researched = save.researched.filter(func(k): return D.TYPES.has(k))
	save.cons = save.cons.filter(func(k): return D.CONSUMABLES.has(k))
	for k in save.owned:
		if not save.mods.has(k):
			save.mods[k] = {}
		if not save.mods_res.has(k):
			save.mods_res[k] = []
	if not save.owned.has(save.tank):
		save.tank = save.owned[0]
	if not D.MODES.has(save.mode):
		save.mode = "standard"
	if save.map != "random" and not D.MAPS.has(save.map):
		save.map = "random"
	if not RES_STEPS.has(float(save.res)):
		save.res = 0.75
	save.eco = save.eco == true


func persist() -> void:
	save["ts"] = Time.get_unix_time_from_system()
	var json := JSON.stringify(save)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json)
	var yg := get_node_or_null("/root/Yandex")
	if yg:
		yg.save_cloud(json)


## Машины, заменённые в 2.4 (для них не нашлось готовых свободных моделей): прогресс переходит на замену.
func _migrate_keys() -> void:
	for old in D.RENAMED:
		var nu: String = D.RENAMED[old]
		for list in ["owned", "researched"]:
			var i: int = save[list].find(old)
			if i >= 0:
				if save[list].has(nu):
					save[list].remove_at(i)
				else:
					save[list][i] = nu
		for dict in ["txp", "mods", "mods_res"]:
			if save[dict].has(old):
				if not save[dict].has(nu):
					save[dict][nu] = save[dict][old]
				save[dict].erase(old)
		if save.tank == old:
			save.tank = nu


## Яндекс Игры: прогресс из облака игрока. Новее местного — берём его (игра на другом устройстве).
func cloud_loaded(json: String) -> void:
	if json == "":
		return
	var d = JSON.parse_string(json)
	if not (d is Dictionary) or not d.has("owned"):
		return
	if float(d.get("ts", 0.0)) <= float(save.get("ts", 0.0)):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	_load()
	if hangar and not battle and not _switching:
		show_hangar()


## Награда за просмотр рекламы: серебро на счёт.
func reward_silver(amount: int) -> void:
	save.silver = int(save.silver) + amount
	persist()


# ---------- Прогресс ----------

func txp(key: String) -> int:
	return int(save.txp.get(key, 0))


## Опыт, которым можно заплатить за исследование танка: с лучшего из открывающих его танков и свободный.
func research_pool(key: String) -> int:
	var best := 0
	for p in D.parents(key):
		if save.researched.has(p):
			best = maxi(best, txp(p))
	return best + int(save.free_xp)


## Можно ли исследовать: открывающий танк исследован, сам танк — ещё нет.
func can_research(key: String) -> bool:
	if save.researched.has(key):
		return false
	for p in D.parents(key):
		if save.researched.has(p):
			return true
	return false


func research(key: String) -> bool:
	var cost := D.research_xp(key)
	if not can_research(key) or research_pool(key) < cost:
		return false
	var from := ""
	for p in D.parents(key):
		if save.researched.has(p) and (from == "" or txp(p) > txp(from)):
			from = p
	var take := mini(txp(from), cost)
	save.txp[from] = txp(from) - take
	save.free_xp = int(save.free_xp) - (cost - take)
	save.researched.append(key)
	persist()
	return true


func buy(key: String) -> bool:
	if not save.researched.has(key) or save.owned.has(key) or int(save.silver) < D.price(key):
		return false
	save.silver = int(save.silver) - D.price(key)
	save.owned.append(key)
	save.mods[key] = {}
	save.mods_res[key] = []
	persist()
	return true


## Модуль: исследован ли и стоит ли сейчас исследованный.
func module_researched(key: String, slot: String) -> bool:
	return (save.mods_res.get(key, []) as Array).has(slot)


func module_on(key: String, slot: String) -> bool:
	return module_researched(key, slot) and bool(save.mods.get(key, {}).get(slot, true))


## Исследовать и сразу установить модуль: опыт танка (не хватит — свободный) и серебро.
func research_module(key: String, slot: String) -> bool:
	var xp := D.module_xp(key, slot)
	var price := D.module_price(key, slot)
	if module_researched(key, slot) or txp(key) + int(save.free_xp) < xp or int(save.silver) < price:
		return false
	var take := mini(txp(key), xp)
	save.txp[key] = txp(key) - take
	save.free_xp = int(save.free_xp) - (xp - take)
	save.silver = int(save.silver) - price
	save.mods_res[key].append(slot)
	save.mods[key][slot] = true
	persist()
	return true


func set_module(key: String, slot: String, top: bool) -> void:
	if module_researched(key, slot):
		save.mods[key][slot] = top
		persist()


## Модули для боя: {слот: стоит ли исследованный}.
func top_config(key: String) -> Dictionary:
	var out := {}
	for slot in D.MODULES.get(key, {}):
		out[slot] = module_on(key, slot)
	return out


func toggle_cons(name: String) -> void:
	if save.cons.has(name):
		save.cons.erase(name)
	else:
		save.cons.append(name)
	persist()


# ---------- Ангар и бой ----------

var _switching := false  # идёт смена ангара и боя: повторное нажатие не начнёт вторую
var _load_layer: CanvasLayer
var _load_title: Label
var _load_sub: Label
var _load_stage: Label


## Старая сцена уходит целиком до того, как строится новая: в памяти никогда нет двух боёв
## (или ангара и боя) сразу, а их ресурсы движок и видеокарта успевают освободить за пару кадров.
func _clear_scene() -> void:
	if hangar == null and battle == null:
		return
	if hangar:
		hangar.queue_free()
		hangar = null
	if battle:
		battle.queue_free()
		battle = null
	await get_tree().process_frame
	await get_tree().process_frame


## Экран загрузки поверх всего: пока строится бой, игра показывает, что она жива и чем занята.
func _show_loading(title: String, sub: String) -> void:
	if _load_layer == null:
		_load_layer = CanvasLayer.new()
		_load_layer.layer = 100
		add_child(_load_layer)
		var bg := ColorRect.new()
		bg.color = Color(UI.BG)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		_load_layer.add_child(bg)
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_load_layer.add_child(cc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		cc.add_child(vb)
		_load_title = UI.label("", 34, D.AMBER)
		_load_sub = UI.label("", 18, UI.TEXT)
		_load_stage = UI.label("", 15, UI.DIM)
		for l: Label in [_load_title, _load_sub, _load_stage]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(l)
	_load_title.text = title
	_load_sub.text = sub
	_load_stage.text = ""
	_load_layer.visible = true


func _loading_stage(text: String) -> void:
	if _load_stage:
		_load_stage.text = text


func _hide_loading() -> void:
	if _load_layer:
		_load_layer.visible = false


func show_hangar() -> void:
	if _switching:
		return
	_switching = true
	if battle:
		_show_loading("АНГАР", "")
	await _clear_scene()
	session_mark("hangar_loading")
	hangar = HangarScript.new()
	hangar.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # ангар живёт в кадрах, не в шагах физики
	hangar.main = self
	add_child(hangar)
	session_mark("hangar")
	_hide_loading()
	_switching = false
	var yg := get_node_or_null("/root/Yandex")
	if yg:
		yg.hangar_shown()


func start_battle() -> void:
	if _switching:
		return
	_switching = true
	var map_key: String = save.map
	if map_key == "random":
		# случайная из карт, где воевал выбранный танк
		var keys: Array = D.maps_for(save.tank, save.history)
		if keys.is_empty():
			keys = D.MAPS.keys()
		map_key = keys[randi() % keys.size()]
	_show_loading("ЗАГРУЗКА БОЯ", "%s · %s" % [D.MODES[save.mode].name, D.MAPS[map_key].name])
	await _clear_scene()
	session.battles = int(session.battles) + 1
	session_mark("battle_loading", {"map": map_key, "mode": save.mode, "tank": save.tank, "clock": 0})
	_session_t = 20.0
	var b: Node = BattleScript.new()
	b.setup({"mode": save.mode, "map": map_key, "hq": save.hq, "tank": save.tank, "history": save.history,
		"mods": top_config(save.tank), "cons": save.cons.duplicate()})
	b.ended.connect(_on_ended)
	b.leave.connect(_on_leave)
	b.progress.connect(_loading_stage)
	battle = b
	add_child(b)
	if not b.loaded:
		await b.load_done
	_hist_begin(map_key)
	session_mark("battle")
	_hide_loading()
	_switching = false


func _on_ended(st: Dictionary) -> void:
	save.battles += 1
	if st.result == "win":
		save.wins += 1
	save.kills += st.kills
	save.best_dmg = maxi(int(save.best_dmg), int(st.dmg))
	save.silver = int(save.silver) + int(st.silver)
	var key: String = st.tank
	save.txp[key] = txp(key) + int(st.xp)
	save.free_xp = int(save.free_xp) + int(st.free_xp)
	var ts: Dictionary = save.tstats.get(key, {"battles": 0, "wins": 0, "dmg": 0})
	ts.battles = int(ts.battles) + 1
	ts.wins = int(ts.wins) + (1 if st.result == "win" else 0)
	ts.dmg = int(ts.dmg) + int(st.dmg)
	save.tstats[key] = ts
	save.last = {"tank": key, "xp": st.xp, "silver": st.silver, "result": st.result}
	persist()


var _leaving := false  # уход из боя уже начат (ждём рекламу)


func _on_leave(again: bool) -> void:
	if _leaving:
		return
	_leaving = true
	var go := func() -> void:
		_leaving = false
		if again:
			start_battle.call_deferred()
		else:
			show_hangar.call_deferred()
	# Яндекс Игры: полноэкранная реклама в паузе между боями (частоту ограничивает площадка)
	var yg := get_node_or_null("/root/Yandex")
	if yg and battle:
		battle.set_process(false)
		yg.show_fullscreen(go)
	else:
		go.call()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# кнопка «Назад» на Android: пауза в бою
		if battle and battle.loaded and not battle.over:
			battle.set_paused(not battle.paused)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if battle and battle.loaded and not battle.over and not battle.paused:
			battle.set_paused(true)
		# свёрнутую игру система может закрыть — это не авария
		if what == NOTIFICATION_APPLICATION_PAUSED and String(session.state).begins_with("battle"):
			session_mark("background_" + String(session.state))
	elif what == NOTIFICATION_APPLICATION_RESUMED and String(session.state).begins_with("background_"):
		session_mark(String(session.state).trim_prefix("background_"))
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		session_mark("closed")
