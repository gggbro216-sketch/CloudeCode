extends Node
## Корень игры: переключает ангар и бой, хранит прогресс игрока:
## серебро и опыт, исследованные и купленные танки, модули и снаряжение.

const D = preload("res://scripts/data.gd")
const HangarScript = preload("res://scripts/hangar.gd")
const BattleScript = preload("res://scripts/battle.gd")
const SAVE_PATH := "user://save.json"

var save := {
	"battles": 0, "wins": 0, "kills": 0, "best_dmg": 0, "silver": D.START_SILVER, "free_xp": 0,
	"tank": "t34_76", "mode": "standard", "map": "random", "hq": true, "history": true, "res": 0.75, "eco": false,
	"owned": [], "researched": [], "txp": {}, "mods": {}, "mods_res": {}, "cons": ["repair", "medkit", "ext"],
	"tstats": {}, "last": {},
}
var hangar: Node
var battle: Node


const RES_STEPS := [0.6, 0.75, 0.9, 1.0]  # доля разрешения экрана для 3D (интерфейс — всегда в полном)


func _ready() -> void:
	_load()
	_session_start()
	apply_res()
	apply_eco()
	show_hangar()


# ---------- Журнал сеанса: если игра оборвётся в бою, при следующем запуске ангар скажет, где ----------

const SESSION_PATH := "user://session.json"
var session := {"state": "hangar", "battles": 0}
var last_crash := {}  # прошлый запуск оборвался в бою: что о нём известно (показывает ангар)
var _session_t := 0.0


func _session_start() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
		if d is Dictionary and String(d.get("state", "")).begins_with("battle"):
			last_crash = d
	session_mark("hangar")


## Состояние сеанса и память — в файл (маленький, пишется при смене состояния и раз в 20 с в бою).
func session_mark(state: String, extra := {}) -> void:
	session.state = state
	session.merge(extra, true)
	session.ram_mb = roundi(OS.get_static_memory_usage() / 1048576.0)
	session.video_mb = roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	session.fps = roundi(Engine.get_frames_per_second())
	if battle:
		session.clock = roundi(battle.clock)
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))


func _process(delta: float) -> void:
	if battle and String(session.state).begins_with("battle"):
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


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

func show_hangar() -> void:
	if battle:
		battle.queue_free()
		battle = null
	session_mark("hangar")
	if hangar:
		hangar.queue_free()
	hangar = HangarScript.new()
	hangar.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # ангар живёт в кадрах, не в шагах физики
	hangar.main = self
	add_child(hangar)


func start_battle() -> void:
	if hangar:
		hangar.queue_free()
		hangar = null
	if battle:
		battle.queue_free()
	var map_key: String = save.map
	if map_key == "random":
		# случайная из карт, где воевал выбранный танк
		var keys: Array = D.maps_for(save.tank, save.history)
		if keys.is_empty():
			keys = D.MAPS.keys()
		map_key = keys[randi() % keys.size()]
	session.battles = int(session.battles) + 1
	session_mark("battle_loading", {"map": map_key, "mode": save.mode, "tank": save.tank, "clock": 0})
	_session_t = 5.0
	battle = BattleScript.new()
	battle.setup({"mode": save.mode, "map": map_key, "hq": save.hq, "tank": save.tank, "history": save.history,
		"mods": top_config(save.tank), "cons": save.cons.duplicate()})
	battle.ended.connect(_on_ended)
	battle.leave.connect(_on_leave)
	add_child(battle)


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


func _on_leave(again: bool) -> void:
	if again:
		start_battle.call_deferred()
	else:
		show_hangar.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# кнопка «Назад» на Android: пауза в бою
		if battle and not battle.over:
			battle.set_paused(not battle.paused)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if battle and not battle.over and not battle.paused:
			battle.set_paused(true)
		# свёрнутую игру система может закрыть — это не авария
		if what == NOTIFICATION_APPLICATION_PAUSED and String(session.state).begins_with("battle"):
			session_mark("background_" + String(session.state))
	elif what == NOTIFICATION_APPLICATION_RESUMED and String(session.state).begins_with("background_"):
		session_mark(String(session.state).trim_prefix("background_"))
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		session_mark("closed")
