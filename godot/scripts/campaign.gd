extends RefCounted
## Кампания «Дороги войны»: состояние в save.campaign и переходы между миссиями и операциями.
## {side, op, mi, front, park: {танк: {repair, lost}}, ops: [{front, won}], last: {…итог миссии}, done, bonus}
## Экран — campaign_ui.gd, данные операций и миссий — campaign_data.gd.

const C = preload("res://scripts/campaign_data.gd")
const D = preload("res://scripts/data.gd")


static func active(save: Dictionary) -> bool:
	var cs = save.get("campaign")
	return cs is Dictionary and not (cs as Dictionary).is_empty()


static func start(save: Dictionary, side: String) -> void:
	save.campaign = {"side": side, "op": 0, "mi": 0, "front": 50, "park": {}, "ops": [], "last": {}, "done": false, "bonus": 0}


static func op_of(cs: Dictionary) -> Dictionary:
	return C.OPS[clampi(int(cs.op), 0, C.OPS.size() - 1)]


static func mission_of(cs: Dictionary) -> Dictionary:
	var missions: Array = op_of(cs)[cs.side]
	return missions[clampi(int(cs.mi), 0, missions.size() - 1)]


## Парк операции: машины её исторического состава за сторону игрока, от лёгких к тяжёлым.
static func park(cs: Dictionary) -> Array:
	var map_key: String = op_of(cs).map
	var year := int(D.MAPS[map_key].year)
	var keys: Array = []
	for k in D.MAPS[map_key].roster[cs.side]:
		if D.TYPES.has(k) and int(D.TYPES[k].get("year", 1939)) <= year + 1:
			keys.append(k)
	keys.sort_custom(func(a, b): return D.tier(a) < D.tier(b) or (D.tier(a) == D.tier(b) and String(a) < String(b)))
	return keys


## Состояние машины в парке: "ready", "repair" (пропускает следующую миссию) или "lost" (до конца операции).
static func tank_state(cs: Dictionary, key: String) -> String:
	var e = cs.park.get(key)
	if not (e is Dictionary):
		return "ready"
	if bool(e.get("lost", false)):
		return "lost"
	if int(e.get("repair", 0)) > 0:
		return "repair"
	return "ready"


## Готовые машины; если всё в ремонте или потеряно — самая лёгкая машина состава «из резерва».
static func ready_tanks(cs: Dictionary) -> Array:
	var out: Array = []
	for k in park(cs):
		if tank_state(cs, k) == "ready":
			out.append(k)
	if out.is_empty() and not park(cs).is_empty():
		out.append(park(cs)[0])
	return out


## Настройки боя для текущей миссии на танке tank (их читает battle.gd: cfg.mission).
static func mission_cfg(cs: Dictionary, tank: String) -> Dictionary:
	var m := mission_of(cs)
	var K: Dictionary = C.KINDS[m.kind]
	return {"kind": m.kind, "title": m.title, "brief": m.brief, "task": K.task, "time": K.time, "weight": K.weight,
		"waves": K.waves, "mode": K.mode, "map": op_of(cs).map, "tank": tank, "campaign": true}


## Итог миссии: фронт, парк (ремонт и потери), следующая миссия или операция. Возвращает строку для экрана.
static func apply_result(cs: Dictionary, result: String, tank: String, tank_alive: bool, ammo_boom: bool) -> String:
	var m := mission_of(cs)
	var steps: Array = C.FRONT_STEP.get(m.kind, [20, 0, -20])
	var d: int = int(steps[0]) if result == "win" else (int(steps[1]) if result == "draw" else int(steps[2]))
	cs.front = clampi(int(cs.front) + d, 0, 100)
	# ремонт идёт миссию: что было в ремонте — готово, подбитое сейчас — в ремонт, взорванное — потеряно
	for k in cs.park:
		var e: Dictionary = cs.park[k]
		e.repair = maxi(0, int(e.get("repair", 0)) - 1)
	var tank_note := ""
	if not tank_alive:
		var e: Dictionary = cs.park.get(tank, {"repair": 0, "lost": false})
		if ammo_boom:
			e.lost = true
			tank_note = " %s потерян: взрыв боеукладки." % D.TYPES[tank].name
		else:
			e.repair = 1
			tank_note = " %s подбит и уходит в ремонт на одну миссию." % D.TYPES[tank].name
		cs.park[tank] = e
	var res_name: String = {"win": "выполнена", "lose": "провалена"}.get(result, "ничья")
	var msg := "Миссия «%s» %s, фронт %s%d.%s" % [m.title, res_name, "+" if d >= 0 else "−", absi(d), tank_note]
	cs.mi = int(cs.mi) + 1
	var missions: Array = op_of(cs)[cs.side]
	if int(cs.mi) >= missions.size():
		var won := int(cs.front) >= C.FRONT_WIN
		(cs.ops as Array).append({"front": int(cs.front), "won": won})
		msg += " Операция «%s» %s (фронт %d)." % [op_of(cs).name, "выиграна" if won else "проиграна", int(cs.front)]
		cs.op = int(cs.op) + 1
		cs.mi = 0
		cs.front = 50
		cs.park = {}
		if int(cs.op) >= C.OPS.size():
			cs.done = true
			cs.op = C.OPS.size() - 1
			msg += " Кампания окончена."
	cs.last = {"msg": msg, "result": result}
	return msg


## Сколько операций выиграно.
static func ops_won(cs: Dictionary) -> int:
	var n := 0
	for o in cs.ops:
		if bool(o.get("won", false)):
			n += 1
	return n
