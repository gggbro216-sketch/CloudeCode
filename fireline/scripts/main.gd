extends Node
## Корень игры: переключает меню и бой, хранит настройки, запускает автотест (-- --autotest).

const MenuT = preload("res://scripts/menu.gd")
const BattleT = preload("res://scripts/battle.gd")
const Data = preload("res://scripts/data.gd")
const SETTINGS := "user://settings.cfg"

var menu
var battle
var muted := false
var settings := {}
var test := {}


func _ready() -> void:
	_load_settings()
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		_autotest(args)
		return
	show_menu()


func show_menu() -> void:
	if battle != null:
		battle.queue_free()
		battle = null
	menu = MenuT.new()
	menu.main = self
	add_child(menu)


func start_battle(cfg: Dictionary) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	battle = BattleT.new()
	add_child(battle)
	battle.finished.connect(_on_finished)
	battle.start(cfg)


func _on_finished(_r: Dictionary) -> void:
	show_menu.call_deferred()


func set_muted(v: bool) -> void:
	muted = v
	settings["muted"] = v
	save_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		for k in cf.get_section_keys("game"):
			settings[k] = cf.get_value("game", k)
	muted = settings.get("muted", false)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if battle != null and battle.hud != null:
			if battle.hud.menu_pop.visible:
				battle.hud._close_menu()
			else:
				battle.hud._open_menu()
		elif menu != null and menu.page != null:
			get_tree().quit()


# ===================== Автотест: ИИ против ИИ =====================
# godot --headless --fixed-fps 20 -- --autotest [--scenario N] [--runs K] [--time S] [--shot файл.png --at секунд]

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func _autotest(args: PackedStringArray) -> void:
	test = {"runs": int(_arg(args, "--runs", "1")), "sc": int(_arg(args, "--scenario", "-1")),
		"time": float(_arg(args, "--time", "0")), "shot": _arg(args, "--shot", ""), "at": float(_arg(args, "--at", "60")),
		"speed": float(_arg(args, "--speed", "6")), "n": 0, "results": [], "seed": int(_arg(args, "--seed", "0"))}
	_next_test()


func _next_test() -> void:
	if test.n >= test.runs:
		var w := [0, 0, 0]
		for r in test.results:
			w[r.winner + 1] += 1
		print("AUTOTEST DONE: runs=%d  side0=%d side1=%d draw=%d" % [test.runs, w[1], w[2], w[0]])
		get_tree().quit()
		return
	var si: int = test.sc if test.sc >= 0 else test.n % Data.SCENARIOS.size()
	var sc: Dictionary = Data.SCENARIOS[si]
	var fs := ["us", "su", "de"]
	var f: String = fs[test.n % 3]
	var ef := Data.enemy_of(f)
	var cfg := {"scenario": sc, "faction": f, "enemy_faction": ef,
		"army": Data.auto_army(f, sc.budget, sc.get("armor", false)),
		"enemy_army": Data.auto_army(ef, int(sc.budget * float(sc.enemy)), sc.get("armor", false)),
		"seed": test.seed + test.n * 7919 if test.seed != 0 else randi(), "autotest": true, "muted": true,
		"speed": test.speed}
	if test.time > 0.0:
		cfg["time"] = test.time
	test.n += 1
	test["t0"] = Time.get_ticks_msec()
	test["shot_done"] = false
	start_battle(cfg)
	battle.finished.disconnect(_on_finished)
	print("RUN %d: %s, %s vs %s, armies %d vs %d units" % [test.n, sc.name, f, ef, cfg.army.size(), cfg.enemy_army.size()])


func _process(_dt: float) -> void:
	if test.is_empty() or battle == null:
		return
	if test.shot != "" and not test.shot_done and battle.sim_time >= test.at:
		test.shot_done = true
		battle.speed = 0.0
		battle.paused = true
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(test.shot)
		print("SHOT saved ", test.shot)
		get_tree().quit()
		return
	if battle.phase == "over":
		var r: Dictionary = battle.result
		var L: Array = r.losses
		print("  result: winner=%d (%s) score %d:%d flags %d:%d  lost men %d:%d veh %d:%d  sim %.0fs real %.1fs" % [
			r.winner, r.reason, r.score[0], r.score[1], r.flags[0], r.flags[1], L[0].men, L[1].men, L[0].veh, L[1].veh,
			r.time, (Time.get_ticks_msec() - test.t0) / 1000.0])
		test.results.append(r)
		battle.queue_free()
		battle = null
		_next_test.call_deferred()
