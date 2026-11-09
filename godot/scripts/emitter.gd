extends Node3D
## Излучатель частиц (вместо GPUParticles3D): сам ничего не рисует и не считает на видеокарте —
## пока включён, рождает частицы в общей системе fx.gd (MultiMesh), а летят и гаснут они в шейдере.
## Свойство emitting меняют GDScript и C++ (Object.set): как у GPUParticles3D.

var fx: Node  # fx.gd — общая система частиц
var cfg: Array = []  # [группа, кол-во, жизнь, ряд палитры, vmin, vmax, разброс°, тяжесть, размер, рост, торможение, вращение]
var amount := 1
var lifetime := 1.0
var acc := 0.0  # накопленная доля следующей частицы
var last := Vector3.INF  # где был излучатель в прошлом кадре (частицы раскладываются по пути)
var emitting = false:
	set(v):
		var on := bool(v)
		if on == emitting:
			return
		emitting = on
		for ch in get_children():
			if ch.get_script() == get_script():
				ch.emitting = on
		if fx:
			fx.emitter_on(self, on)

