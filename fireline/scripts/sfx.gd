extends Node2D
## Звук боя: пул 2D-источников (слушатель — камера), записи из assets/sfx и синтезированные
## на лету выстрелы винтовок, пулемётов, миномётов и гранатомётов.

const DIR := "res://assets/sfx/"
const FILES := ["gun_75", "gun_88", "gun_122", "explosion", "hit_pen", "hit_nopen", "ricochet",
	"impact_ground", "whiz", "distant", "capture", "radio_1", "radio_2"]
const VOL := {"gun_75": -2.0, "gun_88": -1.0, "gun_122": 0.0, "explosion": 0.0, "hit_pen": -2.0,
	"hit_nopen": -4.0, "ricochet": -6.0, "impact_ground": -5.0, "whiz": -8.0, "rifle": -9.0, "smg": -11.0,
	"mg": -9.0, "mg42": -9.0, "mortar": -4.0, "rocket": -5.0, "pop": -8.0, "nade": -4.0, "gun_s": -3.0}

var streams := {}
var pool: Array = []
var ui: AudioStreamPlayer
var last := {}
var queue: Array = []
var muted := false
var distant_t := 10.0
var clock := 0.0


func _ready() -> void:
	for id in FILES:
		var path: String = DIR + id + ".ogg"
		if ResourceLoader.exists(path):
			streams[id] = load(path)
	for id in ["rifle", "mg", "mortar", "rocket", "pop"]:
		streams[id] = _synth(id)
	for i in 24:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 1100.0
		p.attenuation = 1.4
		p.panning_strength = 0.7
		add_child(p)
		pool.append(p)
	ui = AudioStreamPlayer.new()
	add_child(ui)


func play(id: String, pos: Vector2, gain := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var real := id
	match id:
		"smg":
			real = "mg"
			pitch *= 1.25
		"mg42":
			real = "mg"
			pitch *= 1.12
		"gun_s":
			real = "gun_75"
			pitch *= 1.35
		"nade":
			real = "explosion"
			pitch *= 1.5
	if not streams.has(real):
		return
	var key := id
	var now := clock
	var gap := 0.04 if id in ["rifle", "mg", "smg", "mg42"] else 0.07
	if last.has(key) and now - float(last[key]) < gap:
		return
	last[key] = now
	var best: AudioStreamPlayer2D = null
	for p in pool:
		if not p.playing:
			best = p
			break
	if best == null:
		return
	best.stream = streams[real]
	best.global_position = pos
	best.volume_db = float(VOL.get(id, -4.0)) + gain
	best.pitch_scale = pitch * randf_range(0.93, 1.07)
	best.play()


func burst(id: String, pos: Vector2, n: int, interval: float) -> void:
	for i in n:
		queue.append([clock + i * interval, id, pos])


func ui_sound(id: String, gain := -6.0) -> void:
	if muted or not streams.has(id):
		return
	ui.stream = streams[id]
	ui.volume_db = gain
	ui.play()


func _process(delta: float) -> void:
	clock += delta
	if not queue.is_empty():
		var rest: Array = []
		for q in queue:
			if q[0] <= clock:
				last.erase(q[1])
				play(q[1], q[2], -1.0)
			else:
				rest.append(q)
		queue = rest
	distant_t -= delta
	if distant_t <= 0.0:
		distant_t = randf_range(18.0, 40.0)
		if not muted and streams.has("distant"):
			ui.stream = streams["distant"]
			ui.volume_db = randf_range(-24.0, -16.0)
			ui.pitch_scale = randf_range(0.85, 1.1)
			ui.play()


static func _synth(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.45
	match kind:
		"mg":
			dur = 0.22
		"mortar":
			dur = 0.6
		"rocket":
			dur = 0.9
		"pop":
			dur = 0.35
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	for i in n:
		var tt := float(i) / rate
		var nz := rng.randf() * 2.0 - 1.0
		var v := 0.0
		match kind:
			"rifle":
				lp += (nz - lp) * 0.6
				lp2 += (nz - lp2) * 0.08
				v = lp * exp(-tt * 45.0) * 0.8 + lp2 * exp(-tt * 9.0) * 1.2 + sin(TAU * 90.0 * tt) * exp(-tt * 28.0) * 0.45
			"mg":
				lp += (nz - lp) * 0.5
				lp2 += (nz - lp2) * 0.1
				v = lp * exp(-tt * 60.0) * 0.8 + lp2 * exp(-tt * 18.0) * 1.0 + sin(TAU * 75.0 * tt) * exp(-tt * 40.0) * 0.5
			"mortar":
				lp += (nz - lp) * 0.08
				v = sin(TAU * (65.0 - 25.0 * tt) * tt) * exp(-tt * 7.0) * 0.8 + lp * exp(-tt * 12.0) * 1.5
			"rocket":
				lp += (nz - lp) * 0.25
				v = lp * minf(tt * 25.0, 1.0) * exp(-tt * 3.0) * 0.9 + sin(TAU * 140.0 * tt) * exp(-tt * 20.0) * 0.3
			"pop":
				lp += (nz - lp) * 0.2
				v = sin(TAU * 180.0 * tt) * exp(-tt * 22.0) * 0.5 + lp * exp(-tt * 10.0) * 0.8
		data.encode_s16(i * 2, clampi(int(clampf(v, -1.0, 1.0) * 30000.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
