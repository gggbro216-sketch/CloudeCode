extends Node
## Звуки, синтезированные при старте: выстрел, попадание, взрыв, захват точки.

const RATE := 22050

var streams := {}
var players: Array = []
var next := 0
var muted := false


func _ready() -> void:
	streams["shot"] = _wav(_shot())
	streams["hit"] = _wav(_hit())
	streams["boom"] = _wav(_boom())
	streams["cap"] = _wav(_cap())
	streams["crack"] = _wav(_crack())
	streams["rico"] = _wav(_rico())
	streams["nopen"] = _wav(_nopen())
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func play(id: String, vol: float) -> void:
	if muted or vol < 0.03 or not streams.has(id):
		return
	var p: AudioStreamPlayer = players[next]
	next = (next + 1) % players.size()
	p.stream = streams[id]
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	p.play()


func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * sec))
	return b


## Низкий «бум» с падающей частотой и шум с фильтром.
func _shot() -> PackedFloat32Array:
	var b := _buf(0.5)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 150.0 * pow(38.0 / 150.0, minf(t / 0.25, 1.0))
		ph += TAU * f / RATE
		lp += (randf() * 2.0 - 1.0 - lp) * 0.3
		b[i] = sin(ph) * 0.75 * exp(-t * 7.0) + lp * 1.1 * exp(-t * 11.0)
	return b


func _hit() -> PackedFloat32Array:
	var b := _buf(0.18)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (320.0 - 900.0 * t) / RATE
		var sq := 1.0 if sin(ph) > 0 else -1.0
		b[i] = sq * 0.2 * exp(-t * 25.0) + (randf() * 2.0 - 1.0) * 0.45 * exp(-t * 30.0)
	return b


func _boom() -> PackedFloat32Array:
	var b := _buf(1.1)
	var lp := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (randf() * 2.0 - 1.0 - lp) * 0.08
		ph += TAU * (90.0 * exp(-t * 3.0) + 25.0) / RATE
		b[i] = lp * 3.2 * exp(-t * 3.2) + sin(ph) * 0.5 * exp(-t * 4.0)
	return b


func _cap() -> PackedFloat32Array:
	var b := _buf(0.32)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 660.0 if t < 0.13 else 990.0
		ph += TAU * f / RATE
		var env := exp(-fmod(t, 0.13) * 12.0)
		b[i] = (2.0 * absf(fmod(ph / TAU, 1.0) * 2.0 - 1.0) - 1.0) * 0.3 * env
	return b


## Треск ломающегося дерева.
func _crack() -> PackedFloat32Array:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		var burst := 1.0 if randf() < 0.08 * exp(-t * 6.0) else 0.0
		b[i] = (randf() * 2.0 - 1.0) * (0.25 * exp(-t * 9.0) + burst * 0.6)
	return b


## Рикошет: звенящий свист с падающим тоном.
func _rico() -> PackedFloat32Array:
	var b := _buf(0.45)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (2400.0 - 2600.0 * t) / RATE
		b[i] = sin(ph) * 0.3 * exp(-t * 6.0) + (randf() * 2.0 - 1.0) * 0.3 * exp(-t * 40.0)
	return b


## Непробитие: глухой металлический удар.
func _nopen() -> PackedFloat32Array:
	var b := _buf(0.35)
	var p1 := 0.0
	var p2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		p1 += TAU * 610.0 / RATE
		p2 += TAU * 873.0 / RATE
		b[i] = (sin(p1) + sin(p2) * 0.7) * 0.25 * exp(-t * 14.0) + (randf() * 2.0 - 1.0) * 0.4 * exp(-t * 50.0)
	return b
