extends Node2D
## Эффекты боя: трассеры, вспышки выстрелов, разрывы, искры, дым (в т. ч. закрывающий обзор),
## горящие остовы и снаряды в полёте (список снарядов ведёт battle.gd).

const MapT = preload("res://scripts/map.gd")

var battle
var tracers: Array = []
var flashes: Array = []
var booms: Array = []
var sparks: Array = []
var smokes: Array = []
var fires: Array = []
var wind := Vector2(1.2, -0.5)


func step(dt: float) -> void:
	for a in [tracers, flashes, booms, sparks]:
		for e in a:
			e.t += dt
	tracers = tracers.filter(func(e): return e.t < e.life)
	flashes = flashes.filter(func(e): return e.t < e.life)
	booms = booms.filter(func(e): return e.t < e.life)
	for s in sparks:
		s.p += s.v * dt
		s.v *= 1.0 - minf(1.0, dt * 3.0)
	sparks = sparks.filter(func(e): return e.t < e.life)
	for s in smokes:
		s.t += dt
		s.p += (wind * s.drift + s.v) * dt
		s.v *= 1.0 - minf(1.0, dt * 1.5)
		var f: float = s.t / s.life
		s.r = lerpf(s.r0, s.r1, minf(1.0, f * 3.0))
		if s.blocks:
			s.dens = s.dens0 * clampf((1.0 - f) * 4.0, 0.0, 1.0)
	smokes = smokes.filter(func(e): return e.t < e.life)
	for f in fires:
		f.t -= dt
		f.life -= dt
		if f.t <= 0.0:
			f.t = randf_range(0.35, 0.7) if f.life > 0.0 else randf_range(1.5, 3.0)
			if f.life > -60.0:
				var big: bool = f.life > 0.0
				puff(f.p + Vector2(randf_range(-1, 1), randf_range(-1, 1)), 1.5, 6.0 if big else 4.0,
					randf_range(7.0, 11.0), Color(0.12, 0.11, 0.1, 0.55) if big else Color(0.3, 0.3, 0.3, 0.3), 0.0, 1.0)
	fires = fires.filter(func(e): return e.life > -60.0)
	queue_redraw()


func tracer(a: Vector2, b: Vector2, col: Color, w := 0.18, speed := 600.0) -> void:
	if tracers.size() > 220:
		return
	tracers.append({"a": a, "b": b, "t": 0.0, "life": maxf(0.08, a.distance_to(b) / speed), "col": col, "w": w})


func flash(p: Vector2, ang: float, s: float) -> void:
	flashes.append({"p": p, "a": ang, "s": s, "t": 0.0, "life": 0.09 + s * 0.02})


func boom(p: Vector2, r: float) -> void:
	booms.append({"p": p, "r": r, "t": 0.0, "life": 0.35 + r * 0.03})
	var n := int(clampf(r * 1.2, 4, 16))
	for i in n:
		sparks.append({"p": p, "v": Vector2.from_angle(randf() * TAU) * randf_range(r * 1.5, r * 4.0),
			"t": 0.0, "life": randf_range(0.3, 0.8), "col": Color(0.25, 0.2, 0.14)})
	for i in int(clampf(r * 0.4, 2, 6)):
		puff(p + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.4, r * 0.5, r * 1.3,
			randf_range(3.0, 6.0) + r * 0.3, Color(0.45, 0.40, 0.33, 0.6), 0.0, 0.4)


func hit_spark(p: Vector2, col := Color(1.0, 0.8, 0.4)) -> void:
	for i in 6:
		sparks.append({"p": p, "v": Vector2.from_angle(randf() * TAU) * randf_range(6.0, 18.0),
			"t": 0.0, "life": randf_range(0.15, 0.4), "col": col})


func dust(p: Vector2) -> void:
	if smokes.size() > 260:
		return
	puff(p, 0.4, 1.2, randf_range(0.8, 1.4), Color(0.5, 0.45, 0.35, 0.5), 0.0, 0.1)


func puff(p: Vector2, r0: float, r1: float, life: float, col: Color, dens := 0.0, drift := 1.0) -> void:
	if smokes.size() > 320 and dens <= 0.0:
		return
	smokes.append({"p": p, "r0": r0, "r1": r1, "r": r0, "t": 0.0, "life": life, "col": col, "dens0": dens,
		"dens": dens, "blocks": dens > 0.0, "drift": drift, "v": Vector2.ZERO})


func smoke_screen(p: Vector2) -> void:
	for i in 5:
		var q := p + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		puff(q, 3.0, randf_range(11.0, 15.0), randf_range(45.0, 60.0), Color(0.82, 0.82, 0.80, 0.55), 0.085, 0.25)


func burn(p: Vector2, life: float) -> void:
	fires.append({"p": p, "t": 0.0, "life": life})


## Дым, закрывающий видимость (для линии видимости).
func blocking_smokes() -> Array:
	var out: Array = []
	for s in smokes:
		if s.blocks and s.dens > 0.005:
			out.append(s)
	return out


func _draw() -> void:
	# снаряды в полёте
	if battle != null:
		for pr in battle.proj:
			var f: float = clampf(pr.t / pr.dur, 0.0, 1.0)
			var p: Vector2 = (pr.a as Vector2).lerp(pr.b, f)
			match pr.vis:
				"arc":
					var h := sin(f * PI)
					draw_circle(p + Vector2(h * 3.0, h * 4.0), 0.4, Color(0, 0, 0, 0.3))
					draw_circle(p - Vector2(0, h * 14.0), 0.35 + h * 0.4, Color(0.15, 0.15, 0.12))
				"shell":
					var dir: Vector2 = ((pr.b - pr.a) as Vector2).normalized()
					draw_line(p - dir * 4.0, p, Color(1.0, 0.75, 0.35, 0.9), 0.35)
				"rocket":
					var dir: Vector2 = ((pr.b - pr.a) as Vector2).normalized()
					draw_line(p - dir * 1.2, p, Color(0.3, 0.3, 0.25), 0.3)
					draw_circle(p - dir * 1.3, 0.35, Color(1.0, 0.7, 0.3))
				"nade":
					var h := sin(f * PI)
					draw_circle(p - Vector2(0, h * 3.0), 0.25, Color(0.15, 0.17, 0.12))
	for tr in tracers:
		var f: float = tr.t / tr.life
		var a: Vector2 = tr.a
		var b: Vector2 = tr.b
		var p1 := a.lerp(b, minf(1.0, f + 0.12))
		var p0 := a.lerp(b, maxf(0.0, f - 0.05))
		draw_line(p0, p1, tr.col, tr.w)
	for fl in flashes:
		var k: float = 1.0 - fl.t / fl.life
		var s: float = fl.s
		var dir := Vector2.from_angle(fl.a)
		var nrm := dir.orthogonal()
		var p: Vector2 = fl.p
		var pts := PackedVector2Array([p + nrm * s * 0.3, p + dir * s * 2.0 * (0.6 + k * 0.4), p - nrm * s * 0.3])
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.4, k))
		draw_circle(p, s * 0.45 * k, Color(1.0, 0.95, 0.7, k))
	for s in sparks:
		var k: float = 1.0 - s.t / s.life
		var c: Color = s.col
		c.a = k
		draw_circle(s.p, 0.25, c)
	for b in booms:
		var f: float = b.t / b.life
		var r: float = b.r * (0.5 + f * 0.8)
		draw_circle(b.p, r, Color(1.0, 0.55 + 0.3 * (1.0 - f), 0.2, (1.0 - f) * 0.85))
		draw_circle(b.p, r * 0.55, Color(1.0, 0.95, 0.75, (1.0 - f) * (1.0 - f)))
	for s in smokes:
		var f: float = s.t / s.life
		var c: Color = s.col
		c.a *= clampf((1.0 - f) * 2.5, 0.0, 1.0) * clampf(s.t * 4.0, 0.0, 1.0)
		MapT.blob(self, s.p, s.r, c, 9, s.r0 * 3.0)
