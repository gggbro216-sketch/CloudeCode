extends RefCounted
## Замер покадровых секций (только с переменной окружения STEEL_PROF): сумма, максимум, число вызовов.

static var on := OS.get_environment("STEEL_PROF") != ""
static var data := {}


static func add(k: String, t0: int) -> void:
	var d := Time.get_ticks_usec() - t0
	var r: Array = data.get(k, [0, 0, 0])
	r[0] += d
	r[1] = maxi(r[1], d)
	r[2] += 1
	data[k] = r


static func report() -> void:
	if not on:
		return
	var keys := data.keys()
	keys.sort_custom(func(a, b): return data[a][0] > data[b][0])
	for k in keys:
		var r: Array = data[k]
		printerr("ПРОФ %-22s среднее %6.3f мс, макс %6.2f мс, вызовов %d" % [k, float(r[0]) / maxi(1, r[2]) / 1000.0, r[1] / 1000.0, r[2]])
