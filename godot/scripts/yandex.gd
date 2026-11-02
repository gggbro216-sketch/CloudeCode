extends Node
## Яндекс Игры: связь с SDK площадки через JavaScriptBridge (мост YG в web/yandex_shell.html).
## Вне браузера или без SDK (Android, редактор, локальный сервер) всё работает как раньше: реклама
## не показывается, а действия «после рекламы» выполняются сразу.
##
## Что делает: сообщает площадке, что игра загрузилась (LoadingAPI.ready) и когда идёт бой
## (GameplayAPI start/stop); показывает полноэкранную рекламу между боями и рекламу за награду;
## на время рекламы и при уходе со вкладки выключает звук и ставит бой на паузу; хранит прогресс
## в облаке игрока (на другом устройстве он тот же).

signal sdk_ready  # SDK ответил (ok — есть ли реклама и облако)

var web := false  # игра в браузере и мост YG есть
var ok := false  # SDK Яндекс Игр загружен и проинициализирован
var lang := "ru"
var _yg: JavaScriptObject
var _cb: JavaScriptObject  # держим ссылку, иначе колбэк соберёт сборщик
var _ad_done: Callable  # что сделать после полноэкранной рекламы
var _rw_done: Callable  # что сделать после рекламы за награду (с флагом: досмотрел ли)
var _rw_got := false
var _ad_busy := false
var _sdk_pause := false  # SDK или браузер попросили паузу (вкладка скрыта, открыто окно)
var _ready_sent := false
var _hangar_shown := false
var _gameplay := false
var cloud_json := ""  # прогресс из облака (пусто — нет)
var cloud_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_yg = JavaScriptBridge.get_interface("YG")
	if _yg == null:
		return
	web = true
	_cb = JavaScriptBridge.create_callback(_on_event)
	_yg.onEvent = _cb
	_yg.attach()
	_yg.init()


func _on_event(args: Array) -> void:
	var name := String(args[0]) if args.size() > 0 else ""
	var data := String(args[1]) if args.size() > 1 and args[1] != null else ""
	match name:
		"init":
			var d = JSON.parse_string(data)
			if d is Dictionary:
				ok = bool(d.get("ok", false))
				lang = String(d.get("lang", "ru"))
			if ok:
				_yg.loadData()
			else:
				cloud_done = true
			_try_ready()
			sdk_ready.emit()
		"data":
			cloud_json = data
			cloud_done = true
			var main := _main()
			if main and main.has_method("cloud_loaded"):
				main.cloud_loaded(data)
		"pause":
			_sdk_pause = true
			_apply_pause()
		"resume":
			_sdk_pause = false
			_apply_pause()
		"ad_open", "rw_open":
			_ad_busy = true
			_apply_pause()
		"ad_close", "ad_error":
			_ad_busy = false
			_apply_pause()
			var cb := _ad_done
			_ad_done = Callable()
			if cb.is_valid():
				cb.call()
		"rw_reward":
			_rw_got = true
		"rw_close", "rw_error":
			_ad_busy = false
			_apply_pause()
			var cb := _rw_done
			_rw_done = Callable()
			if cb.is_valid():
				cb.call(_rw_got)
			_rw_got = false


## Звук и бой — на паузу, пока идёт реклама или вкладка скрыта.
func _apply_pause() -> void:
	var off := _ad_busy or _sdk_pause
	AudioServer.set_bus_mute(0, off)
	if off:
		var main := _main()
		if main and main.battle and main.battle.get("loaded") and not main.battle.over and not main.battle.paused:
			main.battle.set_paused(true)


func _main() -> Node:
	return get_tree().root.get_node_or_null("Main") if get_tree() else null


## Ангар показан впервые: игра готова — площадка убирает свой экран загрузки (Game Ready).
func hangar_shown() -> void:
	_hangar_shown = true
	_try_ready()


func _try_ready() -> void:
	if web and ok and _hangar_shown and not _ready_sent:
		_ready_sent = true
		_yg.loadingReady()


## Идёт ли бой (GameplayAPI): true — игрок играет, false — пауза, итоги, ангар.
func gameplay(on: bool) -> void:
	if not (web and ok) or on == _gameplay:
		return
	_gameplay = on
	if on:
		_yg.gameplayStart()
	else:
		_yg.gameplayStop()


## Полноэкранная реклама в логической паузе (между боями); после неё — done. Как часто её
## показывать, решает площадка (не чаще раза в минуту): если не время, done выполняется сразу.
func show_fullscreen(done: Callable) -> void:
	if not (web and ok) or _ad_busy:
		done.call()
		return
	_ad_done = done
	_yg.showFullscreen()


## Есть ли реклама за награду.
func rewarded_available() -> bool:
	return web and ok


## Реклама за награду: done(true) — досмотрел, награду дать.
func show_rewarded(done: Callable) -> void:
	if not (web and ok) or _ad_busy:
		done.call(false)
		return
	_rw_got = false
	_rw_done = done
	_yg.showRewarded()


## Прогресс в облако игрока: не чаще раза в 2 с (у облака ограничение на частоту записи),
## уходит последняя версия.
var _cloud_pending := ""
var _cloud_wait := false


func save_cloud(json: String) -> void:
	if not (web and ok):
		return
	_cloud_pending = json
	if _cloud_wait:
		return
	_cloud_wait = true
	await get_tree().create_timer(2.0, true, false, true).timeout
	_cloud_wait = false
	if _cloud_pending != "":
		_yg.saveData(_cloud_pending)
		_cloud_pending = ""
