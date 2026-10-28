extends Node
## Корень игры: переключает ангар и бой, хранит прогресс игрока.

const D = preload("res://scripts/data.gd")
const HangarScript = preload("res://scripts/hangar.gd")
const BattleScript = preload("res://scripts/battle.gd")
const SAVE_PATH := "user://save.json"

var save := {
	"battles": 0, "wins": 0, "kills": 0, "best_dmg": 0, "silver": 0,
	"tank": "medium", "mode": "standard", "map": "random", "hq": true,
}
var hangar: Node
var battle: Node


func _ready() -> void:
	_load()
	show_hangar()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			if save.has(k):
				save[k] = d[k]
	# защита от устаревших значений
	if not D.TYPES.has(save.tank):
		save.tank = "medium"
	if not D.MODES.has(save.mode):
		save.mode = "standard"
	if save.map != "random" and not D.MAPS.has(save.map):
		save.map = "random"


func persist() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


func show_hangar() -> void:
	if battle:
		battle.queue_free()
		battle = null
	if hangar:
		hangar.queue_free()
	hangar = HangarScript.new()
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
		var keys: Array = D.MAPS.keys()
		map_key = keys[randi() % keys.size()]
	battle = BattleScript.new()
	battle.setup({"mode": save.mode, "map": map_key, "hq": save.hq, "tank": save.tank})
	battle.ended.connect(_on_ended)
	battle.leave.connect(_on_leave)
	add_child(battle)


func _on_ended(st: Dictionary) -> void:
	save.battles += 1
	if st.result == "win":
		save.wins += 1
	save.kills += st.kills
	save.best_dmg = maxi(int(save.best_dmg), int(st.dmg))
	save.silver += st.silver
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
