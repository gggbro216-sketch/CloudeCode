extends Node3D
## Звук боя: 3D-источники с затуханием и приглушением верхов на расстоянии (слушатель — камера),
## петли двигателя, гусениц и привода башни у танков, фон поля боя.
## Файлы лежат в res://assets/sfx/ и созданы tools/gen_sfx.py; любой можно заменить записью.

const DIR := "res://assets/sfx/"
const ONE_SHOTS := ["gun_75", "gun_88", "gun_122", "explosion", "hit_pen", "hit_nopen", "ricochet",
	"impact_ground", "impact_stone", "reload", "tree", "track_break", "capture", "whiz", "distant"]
const LOOPS := ["engine_diesel", "engine_petrol", "tracks", "turret", "wind", "fire"]
# громкость (дБ) и «размер» источника (на каком расстоянии звук начинает затухать, единицы карты)
const MIX := {
	"gun_75": [0.0, 120.0], "gun_88": [1.0, 130.0], "gun_122": [2.0, 150.0], "explosion": [3.0, 160.0],
	"hit_pen": [-1.0, 70.0], "hit_nopen": [-3.0, 60.0], "ricochet": [-4.0, 60.0], "impact_ground": [-4.0, 70.0],
	"impact_stone": [-4.0, 60.0], "tree": [-6.0, 40.0], "track_break": [-3.0, 45.0], "whiz": [-4.0, 25.0],
}

var streams := {}
var pool: Array = []
var next := 0
var muted := false
var ui: AudioStreamPlayer
var wind: AudioStreamPlayer
var distant_t := 8.0


func _ready() -> void:
	for id in ONE_SHOTS:
		var s = _load(id, false)
		if s:
			streams[id] = s
	for id in LOOPS:
		var s = _load(id, true)
		if s:
			streams[id] = s
	for i in 18:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = 3000.0
		p.attenuation_filter_cutoff_hz = 3500.0
		p.attenuation_filter_db = -18.0
		p.panning_strength = 0.8
		add_child(p)
		pool.append(p)
	ui = AudioStreamPlayer.new()
	add_child(ui)
	wind = AudioStreamPlayer.new()
	wind.stream = streams.get("wind")
	wind.volume_db = -20.0
	add_child(wind)
	if wind.stream:
		wind.play()


func _load(id: String, loop: bool):
	var path := DIR + id + (".wav" if loop else ".ogg")
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if loop and s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate) - 1
	return s


func _process(delta: float) -> void:
	# далёкая канонада для атмосферы
	distant_t -= delta
	if distant_t <= 0.0:
		distant_t = randf_range(14.0, 35.0)
		if not muted and streams.has("distant"):
			ui.stream = streams["distant"]
			ui.volume_db = randf_range(-22.0, -14.0)
			ui.pitch_scale = randf_range(0.85, 1.1)
			ui.play()


func set_muted(v: bool) -> void:
	muted = v
	AudioServer.set_bus_mute(0, v)


## Звук в точке мира.
func play3d(id: String, at: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if muted or not streams.has(id):
		return
	var p: AudioStreamPlayer3D = pool[next]
	next = (next + 1) % pool.size()
	var mix: Array = MIX.get(id, [0.0, 60.0])
	p.stream = streams[id]
	p.global_position = at
	p.unit_size = mix[1]
	p.volume_db = float(mix[0]) + vol
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


## Звук «в голове» игрока (интерфейс, своя перезарядка).
func play2d(id: String, vol := 0.0) -> void:
	if muted or not streams.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[id]
	p.volume_db = vol
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func gun(caliber: float, at: Vector3) -> void:
	var id := "gun_75" if caliber < 80.0 else ("gun_88" if caliber < 100.0 else "gun_122")
	play3d(id, at)


## Петля, привязанная к узлу (двигатель, гусеницы, башня, пожар).
func attach_loop(node: Node3D, id: String, unit: float, vol := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.get(id)
	p.unit_size = unit
	p.max_distance = 1400.0
	p.attenuation_filter_cutoff_hz = 3000.0
	p.attenuation_filter_db = -20.0
	p.volume_db = vol
	node.add_child(p)
	if p.stream and not muted:
		p.play()
	return p
