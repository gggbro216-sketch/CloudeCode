extends Node3D
## Эффекты частиц: вспышки выстрелов, искры, пыль, дым и взрывы.
##
## Своя система частиц вместо GPUParticles3D (3.1). У GPUParticles3D в рендере Compatibility каждая
## включённая система каждый кадр перезаливает в драйвер свой буфер кадра (6 КБ, glBufferData) и
## делает отдельный проход видеокарты (transform feedback) — в бою их ~45 на кадр. На Mali (Pixel 7 Pro)
## куча процесса росла на ~4 МБ/с и не отдавалась. Здесь частица — экземпляр MultiMesh: при рождении
## процессор один раз пишет откуда, с какой скоростью, когда и на сколько она родилась, а полёт,
## рост, цвет и угасание считает вершинный шейдер по времени. Кадр без новых частиц ничего в драйвер
## не пишет (кроме одного числа «сейчас» на материал); экземпляры поделены на куски по 512, и
## перезаливается только кусок, куда пишут, а пустые куски не рисуются.

const TexLib = preload("res://scripts/textures.gd")
const Emitter = preload("res://scripts/emitter.gd")

var amount_k := 1.0  # доля частиц по настройке графики «Частицы»
var soft: GradientTexture2D
var ramps := {}  # имя палитры → Gradient
var rows := {}  # имя палитры → строка в текстуре палитр
const ROWS := 32
var ramp_img: Image
var ramp_tex: ImageTexture
var far := 1600.0  # дальше от камеры разовые эффекты не рождаются
const FLASHES := 6  # вспышек света одновременно
const FLASH_T := 0.14
var flashes: Array = []  # [OmniLight3D, сколько ещё светит, начальная яркость]

const CH := 512  # экземпляров в куске MultiMesh
const CHUNKS := [8, 4]  # кусков: [дым и пыль (смешивание), огонь и искры (сложение)]
var groups: Array = []  # на группу: {mat, chunks: [[MultiMesh, MultiMeshInstance3D, до какого времени есть живые]], cur}
var now := 0.0  # время частиц (стоит на паузе вместе с узлом)
var active: Array = []  # включённые излучатели
var spawned := 0  # сколько частиц родилось (для замеров)


const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
uniform float now = 0.0;
uniform sampler2D ramp : filter_linear, repeat_disable;
uniform sampler2D tex : source_color, filter_linear_mipmap;
varying vec4 col;

void vertex() {
	// MODEL_MATRIX: [3] — где родилась, [0] — начальная скорость, [1] — (когда, жизнь, размер),
	// [2] — (ускорение по вертикали, торможение, —);
	// INSTANCE_CUSTOM — (строка палитры, начальный угол, скорость вращения, разброс размера)
	vec3 a = MODEL_MATRIX[1].xyz;
	vec3 b = MODEL_MATRIX[2].xyz;
	float age = now - a.x;
	float k = age / a.y;
	if (age < 0.0 || k >= 1.0) {
		VERTEX = vec3(0.0, 0.0, 1e6);
		col = vec4(0.0);
	} else {
		vec3 v0 = MODEL_MATRIX[0].xyz;
		float s0 = length(v0);
		float dist = s0 * age;
		if (b.y > 0.0) {
			float ts = min(age, s0 / b.y);
			dist = s0 * ts - 0.5 * b.y * ts * ts;
		}
		vec3 p = MODEL_MATRIX[3].xyz + (s0 > 0.0 ? v0 * (dist / s0) : vec3(0.0)) + vec3(0.0, 0.5 * b.x * age * age, 0.0);
		float sc = a.z * INSTANCE_CUSTOM.w;  // размер постоянный (так выглядели частицы GPUParticles3D до 3.1)
		float ang = INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.z * age;
		vec2 c = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * VERTEX.xy * sc;
		VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz + vec3(c, 0.0);
		col = texture(ramp, vec2(k, INSTANCE_CUSTOM.x));
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * col.rgb;
	ALPHA = t.a * col.a;
}
"""


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft = GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	soft.width = 64
	soft.height = 64
	ramp_img = Image.create(64, ROWS, false, Image.FORMAT_RGBA8)
	_set_ramp("fire", [Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 0.9), Color(0.3, 0.1, 0.05, 0)])
	_set_ramp("spark", [Color(1, 0.85, 0.5, 1), Color(1, 0.5, 0.1, 0)])
	_set_ramp("smoke", [Color(0.42, 0.42, 0.4, 0.55), Color(0.3, 0.3, 0.29, 0)])
	_set_ramp("dark", [Color(0.12, 0.12, 0.11, 0.75), Color(0.1, 0.1, 0.1, 0)])
	_set_ramp("exhaust", [Color(0.32, 0.33, 0.36, 0.5), Color(0.4, 0.41, 0.44, 0)])
	_set_ramp("snow", [Color(0.94, 0.95, 0.98, 0.62), Color(0.94, 0.95, 0.98, 0)])
	_set_ramp("mud", [Color(0.2, 0.16, 0.11, 1), Color(0.18, 0.14, 0.1, 1), Color(0.18, 0.14, 0.1, 0)])
	_set_ramp("engine", [Color(0.16, 0.16, 0.15, 0.6), Color(0.22, 0.22, 0.21, 0)])
	set_dust(Color(0.55, 0.5, 0.4))
	ramp_tex = ImageTexture.create_from_image(ramp_img)
	for gi in 2:
		var sh := Shader.new()
		sh.code = PUFF_SHADER % ("blend_add" if gi == 1 else "blend_mix")
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("ramp", ramp_tex)
		m.set_shader_parameter("tex", soft if gi == 1 else TexLib.puff_texture())
		m.render_priority = 0 if gi == 1 else 1  # дым поверх огня (как ложились системы GPUParticles3D)
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var chunks: Array = []
		var dead := PackedFloat32Array()
		dead.resize(CH * 16)
		for i in CH:
			dead[i * 16 + 1] = -1e6  # родилась «давно»
			dead[i * 16 + 5] = 1.0
		for c in int(CHUNKS[gi]):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = q
			mm.instance_count = CH
			mm.buffer = dead
			mm.custom_aabb = AABB(Vector3(-4000, -1000, -4000), Vector3(12000, 6000, 12000))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = m
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.custom_aabb = mm.custom_aabb
			mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mmi.visible = false
			add_child(mmi)
			chunks.append([mm, mmi, -1.0])
		groups.append({"mat": m, "chunks": chunks, "cur": 0})


## Палитра цвета по жизни частицы — строка текстуры палитр.
func _set_ramp(name: String, cols: Array) -> void:
	var g := _ramp(cols)
	ramps[name] = g
	if not rows.has(name):
		if rows.size() >= ROWS:
			rows[name] = ROWS - 1  # мест нет: последняя строка (на практике палитр ~15)
		else:
			rows[name] = rows.size()
	var r: int = rows[name]
	for x in 64:
		ramp_img.set_pixel(x, r, g.sample(x / 63.0))
	if ramp_tex:
		ramp_tex.update(ramp_img)


func set_dust(c: Color) -> void:
	var a := c
	a.a = 0.55
	var b := c
	b.a = 0.0
	_set_ramp("dust", [a, b])


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
	g.offsets = offs
	g.colors = PackedColorArray(cols)
	return g


## Настройки частиц: [группа, кол-во, жизнь, строка палитры, vmin, vmax, разброс°, тяжесть, размер, рост, торможение, вращение]
func _cfg(amount: int, life: float, ramp: String, vmin: float, vmax: float, spread: float, grav: float, size: float,
		add: bool, grow: bool, damp: float) -> Array:
	return [1 if add else 0, amount, life, (float(rows.get(ramp, 0)) + 0.5) / ROWS, vmin, vmax, deg_to_rad(spread), grav, size,
		grow, damp, not add]


## Родить одну частицу. b — оси излучателя: частицы летят вдоль его «вверх» с разбросом.
func _spawn(c: Array, at: Vector3, b: Basis) -> void:
	var g: Dictionary = groups[int(c[0])]
	var chunks: Array = g.chunks
	var cur: int = g.cur
	g.cur = (cur + 1) % (chunks.size() * CH)
	var ch: Array = chunks[cur / CH]
	var i := cur % CH
	# разброс как у ParticleProcessMaterial: два угла, каждый равномерно в ±spread (гуще у оси)
	var s := float(c[6])
	var a1 := randf_range(-1.0, 1.0) * s
	var a2 := randf_range(-1.0, 1.0) * s
	var yz := cos(a2)
	yz = yz / maxf(0.0001, sqrt(absf(yz)))
	# в осях излучателя: ось — Y, «бинормаль» — Z, «нормаль» — −X (как у Godot для направления вверх)
	var dir := (b * Vector3(-sin(a2), cos(a1) * yz, sin(a1) * yz)).normalized()
	var v := dir * randf_range(float(c[4]), float(c[5]))
	var life := float(c[2]) * (1.0 - 0.4 * randf())
	var mm: MultiMesh = ch[0]
	mm.set_instance_transform(i, Transform3D(Basis(v, Vector3(now, life, float(c[8])),
		Vector3(float(c[7]), float(c[10]), 1.0 if c[9] else 0.0)), at))
	var rot: bool = c[11]
	mm.set_instance_custom_data(i, Color(float(c[3]), randf() * TAU if rot else 0.0,
		deg_to_rad(randf_range(-25.0, 25.0)) if rot else 0.0, randf_range(0.7, 1.2)))
	ch[2] = maxf(float(ch[2]), now + life)
	if not (ch[1] as MultiMeshInstance3D).visible:
		(ch[1] as MultiMeshInstance3D).visible = true
	spawned += 1


func emit(at: Vector3, amount: int, life: float, ramp: String, vmin: float, vmax: float, dir: Vector3, spread: float,
		grav: float, size: float, add: bool, grow: bool, damp := 0.0, one_shot := true, parent: Node3D = null) -> Emitter:
	amount = maxi(1, roundi(amount * amount_k))
	var c := _cfg(amount, life, ramp, vmin, vmax, spread, grav, size, add, grow, damp)
	if one_shot and parent == null:
		# разовый выброс: частицы рождаются разом, узла нет вовсе
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(at) > far:
			return null
		var b := _aim(dir)
		for k in amount:
			_spawn(c, at, b)
		return null
	var e := Emitter.new()
	e.fx = self
	e.cfg = c
	e.amount = amount
	e.lifetime = life
	if parent:
		parent.add_child(e)
		e.position = at
	else:
		add_child(e)
		e.global_position = at
	e.basis = _aim(dir)
	e.emitting = true
	return e


## Поворот излучателя, при котором его «вверх» смотрит по dir (частицы летят вверх в его осях).
static func _aim(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if d.y > 0.9999 or d == Vector3.ZERO:
		return Basis()
	if d.y < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


func emitter_on(e: Emitter, on: bool) -> void:
	if on:
		if not active.has(e):
			active.append(e)
			e.acc = randf()
			e.last = Vector3.INF
	else:
		active.erase(e)


## Непрерывные излучатели: amount частиц на время жизни, разложенные по пути излучателя за кадр.
func _emit_active(delta: float) -> void:
	for idx in range(active.size() - 1, -1, -1):
		var ev = active[idx]  # без типа: удалённый узел (остов убран) в типизированную переменную не присвоить
		if not is_instance_valid(ev) or not ev.emitting:
			active.remove_at(idx)
			continue
		var e: Emitter = ev
		if not e.is_inside_tree() or not e.is_visible_in_tree():
			e.last = Vector3.INF
			continue
		var gt := e.global_transform
		var at := gt.origin
		var from := at if e.last == Vector3.INF else e.last
		e.last = at
		e.acc += delta * float(e.amount) / maxf(e.lifetime, 0.05)
		var n := mini(int(e.acc), 64)
		if n <= 0:
			continue
		e.acc -= n
		var b := gt.basis.orthonormalized()
		for k in n:
			_spawn(e.cfg, from.lerp(at, (k + 1.0) / n), b)


func _process(delta: float) -> void:
	now += delta
	_emit_active(delta)
	for g: Dictionary in groups:
		var any := false
		for ch: Array in g.chunks:
			var mmi: MultiMeshInstance3D = ch[1]
			if mmi.visible and now > float(ch[2]):
				mmi.visible = false
			any = any or mmi.visible
		if any:
			(g.mat as ShaderMaterial).set_shader_parameter("now", now)
	for f: Array in flashes:
		if float(f[1]) <= 0.0:
			continue
		f[1] = float(f[1]) - delta
		var l: OmniLight3D = f[0]
		if float(f[1]) <= 0.0:
			l.visible = false
		else:
			l.light_energy = float(f[2]) * float(f[1]) / FLASH_T


func muzzle(at: Vector3, dir: Vector3, caliber := 85.0) -> void:
	var k := caliber / 85.0
	emit(at, 16, 0.14, "fire", 80, 300 * k, dir, 18, 0, 8.0 * k, true, false, 5)
	emit(at, 8, 0.12, "fire", 10, 60, Vector3.UP, 180, 0, 6.0 * k, true, false, 5)
	emit(at, 14, 1.8, "smoke", 20, 90 * k, dir, 30, 5, 18.0 * k, false, true, 2.5)
	flash(at, Color(1, 0.75, 0.4), 6.0 * k, 90.0)


## Сизый выхлоп из патрубков при резком разгоне.
func exhaust(at: Vector3, fwd: Vector2) -> void:
	emit(at, 5, 1.6, "exhaust", 6, 18, Vector3(-fwd.x, 0.8, -fwd.y).normalized(), 25, 4, 9, false, true, 1.5)


## Пожар в моторном отделении: пламя и чёрный дым, привязанные к корпусу.
func deck_fire(hull: Node3D, local: Vector3) -> Emitter:
	var p := emit(local, 18, 0.7, "fire", 8, 25, Vector3.UP, 20, 12, 7, true, false, 0, false, hull)
	var s := emit(local + Vector3(0, 3, 0), 10, 2.2, "dark", 10, 22, Vector3.UP, 15, 4, 16, false, true, 0, false, hull)
	s.reparent(p)
	p.emitting = false  # дым — дочерний: включается и гаснет вместе с огнём
	return p


func hit_sparks(at: Vector3) -> void:
	emit(at, 18, 0.35, "spark", 60, 180, Vector3.UP, 90, -220, 4, true, false)
	emit(at, 4, 0.8, "smoke", 5, 20, Vector3.UP, 60, 5, 12, false, true, 1)


## Попадание в землю — комья грунта и пыль; в постройку — каменная крошка.
func impact(at: Vector3, ground: bool) -> void:
	emit(at, 10, 0.4, "spark", 40, 120, Vector3.UP, 80, -200, 3, true, false)
	emit(at, 8, 1.2, "dust", 15, 55, Vector3.UP, 50, 4, 20, false, true, 2)
	debris(at, Color(0.24, 0.2, 0.15) if ground else Color(0.45, 0.43, 0.4))


func debris(at: Vector3, col: Color) -> void:
	var key := "deb_%s" % col.to_html()
	if not ramps.has(key):
		var c := col
		c.a = 1.0
		var e := col
		e.a = 0.0
		_set_ramp(key, [c, c, e])
	emit(at, 14, 1.0, key, 40, 110, Vector3.UP, 40, -260, 2.2, false, false)


func shot_dust(at: Vector3) -> void:
	emit(at, 6, 1.0, "dust", 25, 60, Vector3.UP, 85, 0, 28, false, true, 3)


## Шлейф за танком (включается на ходу): пыль, песок, снежная пыль или комья грязи.
func trail(kind: String) -> Emitter:
	var p: Emitter
	match kind:
		"snow":
			p = emit(Vector3.ZERO, 16, 1.5, "snow", 6, 18, Vector3.UP, 55, -4, 15, false, true, 1.5, false)
		"sand":
			p = emit(Vector3.ZERO, 16, 2.6, "dust", 6, 18, Vector3.UP, 60, 3, 26, false, true, 1.2, false)
		"mud":
			p = emit(Vector3.ZERO, 12, 0.9, "mud", 20, 40, Vector3.UP, 30, -170, 2.2, false, false, 0.4, false)
		"light":
			p = emit(Vector3.ZERO, 8, 1.4, "dust", 4, 12, Vector3.UP, 50, 3, 14, false, true, 1.5, false)
		_:
			p = emit(Vector3.ZERO, 12, 1.9, "dust", 5, 14, Vector3.UP, 55, 3, 19, false, true, 1.5, false)
	p.emitting = false
	return p


## Дым разбитого моторного отделения (танк обездвижен).
func engine_smoke(hull: Node3D, local: Vector3) -> Emitter:
	return emit(local, 10, 2.4, "engine", 8, 18, Vector3.UP, 18, 4, 15, false, true, 0.5, false, hull)


## Пробитие: короткий огненный выброс.
func pen_fire(at: Vector3) -> void:
	emit(at, 12, 0.45, "fire", 20, 70, Vector3.UP, 70, 10, 8, true, false, 2)
	flash(at, Color(1, 0.6, 0.3), 3.0, 50.0)


## Кратковременная вспышка света (источник из пула гаснет за FLASH_T и прячется до следующей).
func flash(at: Vector3, col: Color, energy: float, rng: float) -> void:
	var e: Array = []
	for f: Array in flashes:
		if float(f[1]) <= 0.0:
			e = f
			break
	if e.is_empty():
		if flashes.size() >= FLASHES:
			return
		var nl := OmniLight3D.new()
		nl.shadow_enabled = false
		add_child(nl)
		e = [nl, 0.0, 0.0]
		flashes.append(e)
	var l: OmniLight3D = e[0]
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.global_position = at
	l.visible = true
	e[1] = FLASH_T
	e[2] = energy


## Столб дыма над пожаром или вдали на горизонте.
func smoke_column(at: Vector3, big: bool) -> void:
	if big:
		emit(at + Vector3(0, 20, 0), 16, 9.0, "dark", 25, 40, Vector3.UP, 12, 2, 120, false, true, 0, false)
	else:
		emit(at, 10, 4.5, "dark", 14, 24, Vector3.UP, 10, 3, 26, false, true, 0, false)


func explosion(at: Vector3) -> void:
	emit(at, 46, 0.9, "fire", 40, 230, Vector3.UP, 180, 20, 14, true, false, 3)
	emit(at, 26, 2.8, "dark", 15, 60, Vector3.UP, 70, 12, 30, false, true, 1.5)


## Дым и огонь над подбитым танком: [дым, огонь]. Гасит их бой (Battle._wrecks_update):
## огонь горит ~20 с, дым ~60 с, вдали от камеры не рисуются вовсе.
func wreck_fire(at: Vector3) -> Array:
	var smoke := emit(at, 7, 2.4, "dark", 18, 30, Vector3.UP, 15, 4, 15, false, true, 0, false)
	var fire := emit(at, 5, 0.6, "fire", 20, 50, Vector3.UP, 20, 0, 6, true, false, 0, false)
	return [smoke, fire]


## Дымный шлейф повреждённого танка (включается, когда прочности мало).
func damage_smoke(tank: Node3D, y: float) -> Emitter:
	var p := emit(Vector3(0, y, 0), 14, 1.4, "smoke", 15, 25, Vector3.UP, 15, 4, 14, false, true, 0, false, tank)
	p.emitting = false
	return p
