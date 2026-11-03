extends Control
## Рентген попадания, как в War Thunder: после выстрела игрока по танку или попадания по игроку в углу
## появляется окошко. В нём — прозрачная модель цели в тот момент, экипаж и модули внутри, снаряд влетает
## по своей траектории, рвётся (если взрыватель взведён), разлетаются осколки брони; пострадавшие модули
## и члены экипажа окрашиваются: жёлтый — повреждён или ранен, красный — уничтожен или выбыл.
## Рикошет — снаряд отскакивает от брони, непробитие — снаряд остаётся снаружи.
##
## Окно рисует отдельный мир (SubViewport с own_world_3d): копии мешей цели делят те же ресурсы мешей,
## поэтому на видеокарте ничего нового не заводится; линии и вспышки — масштабируемые общие фигуры.
## Цифры (броня, угол, пробитие) приходят событием EV_XRAY из C++.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Gfx = preload("res://scripts/gfx.gd")
const TankScript = preload("res://scripts/tank.gd")

const VW := 516  # размер картинки в пикселях
const VH := 290
const PW := 344.0  # размер окна на экране
const VIEW_H := 193.0
const HEAD := 26.0
const PH := 330.0  # высота окна
const FR_N := 16  # осколков брони
const T_APPROACH := 0.6  # снаряд подлетает
const T_INSIDE := 1.0  # путь внутри (или отскок)
const T_HOLD := 1.7  # держим картинку
const T_FADE := 0.35

const ITEM_COL := {"engine": Color(0.95, 0.6, 0.25), "fuel": Color(0.85, 0.8, 0.3), "ammo": Color(0.95, 0.5, 0.15),
	"gun": Color(0.8, 0.85, 0.92), "turret": Color(0.6, 0.72, 0.85), "optics": Color(0.4, 0.8, 0.95)}
const COL_CREW := Color(0.45, 0.92, 0.5)
const COL_HURT := Color(1.0, 0.88, 0.2)
const COL_DEAD := Color(1.0, 0.22, 0.15)
const SHADER_GHOST := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 col : source_color = vec3(0.55, 0.75, 0.95);
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = col * (0.45 + 0.9 * f);
	ALPHA = (0.07 + 0.55 * f) * fade;
}
"""
## Внутренности и эффекты: рисуются поверх прозрачной оболочки, без проверки глубины.
const SHADER_ITEM := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.5);
	ALBEDO = col.rgb * (0.7 + 0.5 * f);
	ALPHA = col.a * (0.55 + 0.4 * f);
}
"""
const SHADER_GLOW := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() {
	float f = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	ALBEDO = col.rgb;
	ALPHA = col.a * (0.35 + 0.65 * f);
}
"""

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var ghost: Node3D
var inner: Node3D
var m_box: BoxMesh
var m_ball: SphereMesh
var m_line: CylinderMesh
var m_shell: CapsuleMesh
var sh_ghost: Shader
var sh_item: Shader
var sh_glow: Shader
var mat_ghost: ShaderMaterial
var shell_mi: MeshInstance3D
var trail_mi: MeshInstance3D
var path_mi: MeshInstance3D
var burst_mi: MeshInstance3D
var flash_mi: MeshInstance3D
var frag_mis: Array = []
var mat_shell: ShaderMaterial
var mat_trail: ShaderMaterial
var mat_burst: ShaderMaterial
var mat_flash: ShaderMaterial
var mat_frag: ShaderMaterial
var items: Array = []  # {mi, mat, name, crew, base, to, t}

var active := false
var t := 0.0
var skip := false  # идёт показ другого попадания — это не нужно
var rec := {}  # собирается из событий попадания
var cur := {}  # показываемое сейчас попадание
var cam_c := Vector3.ZERO
var cam_r := 20.0
var cam_az := 0.0
var cam_base := Vector3.ZERO
var cap := 0.0  # прозрачность всего окна 0–1
var sb_win: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	size = Vector2(PW, PH)
	sb_win = UI.box("0a0c08", UI.LINE, 1, 8, 0.84, 0.0)
	vp = SubViewport.new()
	vp.size = Vector2i(VW, VH)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.disable_3d = false
	add_child(vp)
	world = Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.06, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 1.0
	cam.far = 3000.0
	world.add_child(cam)
	cam.current = true
	ghost = Node3D.new()
	world.add_child(ghost)
	inner = Node3D.new()
	world.add_child(inner)
	m_box = BoxMesh.new()
	m_box.size = Vector3.ONE
	m_ball = SphereMesh.new()
	m_ball.radius = 0.5
	m_ball.height = 1.0
	m_ball.radial_segments = 14
	m_ball.rings = 7
	m_line = CylinderMesh.new()
	m_line.top_radius = 0.5
	m_line.bottom_radius = 0.5
	m_line.height = 1.0
	m_line.radial_segments = 6
	m_line.rings = 1
	m_line.cap_top = false
	m_line.cap_bottom = false
	m_shell = CapsuleMesh.new()
	m_shell.radius = 0.5
	m_shell.height = 2.2
	m_shell.radial_segments = 10
	m_shell.rings = 3
	sh_ghost = Shader.new()
	sh_ghost.code = SHADER_GHOST
	sh_item = Shader.new()
	sh_item.code = SHADER_ITEM
	sh_glow = Shader.new()
	sh_glow.code = SHADER_GLOW
	mat_ghost = ShaderMaterial.new()
	mat_ghost.shader = sh_ghost
	mat_ghost.render_priority = 0
	mat_shell = _mat(sh_glow, Color(1.0, 0.95, 0.75, 1.0), 4)
	mat_trail = _mat(sh_glow, Color(1.0, 0.6, 0.2, 0.55), 3)
	mat_burst = _mat(sh_glow, Color(1.0, 0.55, 0.15, 0.5), 3)
	mat_flash = _mat(sh_glow, Color(1.0, 0.95, 0.7, 0.9), 5)
	mat_frag = _mat(sh_glow, Color(1.0, 0.7, 0.3, 0.8), 3)
	shell_mi = _node(m_shell, mat_shell)
	trail_mi = _node(m_line, mat_trail)
	path_mi = _node(m_line, _mat(sh_glow, Color(0.5, 0.7, 1.0, 0.25), 2))
	burst_mi = _node(m_ball, mat_burst)
	flash_mi = _node(m_ball, mat_flash)
	for i in FR_N:
		frag_mis.append(_node(m_line, mat_frag))
	_hide_fx()


func _mat(sh: Shader, c: Color, prio: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", c)
	m.render_priority = prio
	return m


func _node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi


func _hide_fx() -> void:
	for n in [shell_mi, trail_mi, path_mi, burst_mi, flash_mi]:
		n.visible = false
	for f in frag_mis:
		f.visible = false


# ---------- Сбор попадания ----------

## Началось новое попадание (по событию рикошета, непробития или пробития): снимок цели.
func begin(tk: TankScript, by: TankScript, hp: Vector3, dir: Vector3, outcome: int, cal: float) -> void:
	skip = active and t < T_APPROACH + T_INSIDE * 0.9
	rec = {}
	if skip:
		return
	rec = {"tk": tk, "by": by, "outcome": outcome, "cal": cal, "hurt": [], "dead": [], "mods": {}, "fire": false, "rico": Vector3.ZERO,
		"mine": by.is_player}
	_clear()
	var hull := tk.hull_node
	var inv := hull.global_transform.affine_inverse()
	rec.p = inv * hp
	rec.d = (inv.basis * dir).normalized()
	# копии мешей цели в осях корпуса: ту же форму и тот же ресурс, другой материал
	var aabb := AABB()
	var first := true
	var stack: Array = [hull]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh is QuadMesh or not mi.visible:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var g := MeshInstance3D.new()
		g.mesh = mi.mesh
		g.material_override = mat_ghost
		g.transform = xf
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(g)
		var bb: AABB = xf * mi.mesh.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	if first:
		aabb = AABB(Vector3(-20, 0, -10), Vector3(40, 15, 20))
	cam_c = aabb.get_center()
	cam_r = maxf(aabb.size.length() * 0.5, 12.0)
	# внутренности: экипаж шарами, модули коробками (как в раскладке попаданий)
	var up_xf: Transform3D = inv * tk.up_node.global_transform if tk.up_node else Transform3D.IDENTITY
	for it: Dictionary in tk.layout:
		var nm: String = it.name
		var crew: bool = TankScript.CREW.has(nm)
		if crew and not tk.crew_has.get(nm, true):
			continue
		var ctr: Vector3 = it.c if it.part == "hull" else up_xf * Vector3(it.c)
		var base: Color = COL_CREW if crew else ITEM_COL.get(nm, Color(0.7, 0.7, 0.7))
		var dead_before: bool = (crew and not tk.crew_ok.get(nm, true)) or (not crew and tk.mod_state(nm) == 0)
		if dead_before:
			base = COL_DEAD.darkened(0.45)
		var m := _mat(sh_item, Color(base.r, base.g, base.b, 0.9), 1)
		var mi2 := MeshInstance3D.new()
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi2.material_override = m
		if it.has("r"):
			mi2.mesh = m_ball
			mi2.transform = Transform3D(Basis.from_scale(Vector3.ONE * float(it.r) * 2.0), ctr)
		else:
			mi2.mesh = m_box
			var bs: Basis = Basis.from_scale(Vector3(it.h) * 2.0)
			if it.part != "hull":
				bs = up_xf.basis * bs
			mi2.transform = Transform3D(bs, ctr)
		inner.add_child(mi2)
		items.append({"mi": mi2, "mat": m, "name": nm, "crew": crew, "base": base, "to": base, "t": 1e9, "ctr": ctr})


func note_module(tank: TankScript, name: String, now: int) -> void:
	if skip or rec.is_empty() or rec.tk != tank:
		return
	var prev: int = rec.mods.get(name, 2)
	rec.mods[name] = mini(prev, now)


func note_crew(tank: TankScript, role: String, out: bool) -> void:
	if skip or rec.is_empty() or rec.tk != tank:
		return
	if out:
		rec.dead.append(role)
	elif not rec.hurt.has(role):
		rec.hurt.append(role)


func note_fire(tank: TankScript) -> void:
	if not skip and not rec.is_empty() and rec.tk == tank:
		rec.fire = true


func note_rico(vel: Vector3) -> void:
	if skip or rec.is_empty():
		return
	var tk: TankScript = rec.tk
	var inv := tk.hull_node.global_transform.affine_inverse()
	rec.rico = (inv.basis * vel).normalized()


## Итог попадания пришёл из C++ (EV_XRAY): цифры, и показ начинается.
func finish(armor: float, eff: float, pen: float, ang: float, stop_len: float, burst_r: float, frags: int, armed: bool) -> void:
	if skip or rec.is_empty():
		rec = {}
		return
	rec.armor = armor
	rec.eff = eff
	rec.pen = pen
	rec.ang = ang
	rec.stop = stop_len
	rec.burst_r = burst_r
	rec.frags = frags
	rec.armed = armed
	var tk: TankScript = rec.tk
	# что пострадало: по событиям; когда окрасится — когда до него долетит снаряд или рванёт
	var d: Vector3 = rec.d
	var p: Vector3 = rec.p
	var reach := maxf(float(rec.stop), 1.0)
	for e: Dictionary in items:
		var st := -1  # 0 цел, 1 ранен или повреждён, 2 выбыл или уничтожен
		var nm: String = e.name
		if e.crew:
			if rec.dead.has(nm):
				st = 2
			elif rec.hurt.has(nm):
				st = 1
		elif rec.mods.has(nm):
			var now: int = rec.mods[nm]
			st = 2 if now == 0 else 1 if now == 1 else 0
		if st <= 0:
			continue
		e.to = COL_DEAD if st == 2 else COL_HURT
		var along := clampf((e.ctr - p).dot(d) / reach, 0.0, 1.0)
		e.t = T_APPROACH + T_INSIDE * (0.15 + 0.7 * along)
	# осколки брони: конус около 20° от места пробития, длина около 2,4 м
	if rec.outcome == 2:
		var u := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
		u = (u - d * u.dot(d)).normalized()
		var w := d.cross(u)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(p.x * 10.0), int(p.y * 10.0), int(p.z * 10.0)])
		rec.frag_dirs = []
		for i in mini(frags, FR_N):
			var a := rng.randf() * TAU
			var rr := tan(deg_to_rad(20.0)) * sqrt(rng.randf())
			rec.frag_dirs.append((d + u * cos(a) * rr + w * sin(a) * rr).normalized())
			rec.frag_len = 2.4 * D.UPM
	elif rec.outcome == 1 or rec.outcome == 0:
		# искры у брони: веер отскочивших осколков
		var u2 := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([int(p.x * 10.0), int(p.z * 10.0)])
		rec.frag_dirs = []
		for i in 7:
			var v := Vector3(rng2.randf_range(-1, 1), rng2.randf_range(-0.2, 1), rng2.randf_range(-1, 1)).normalized()
			rec.frag_dirs.append(v)
		rec.frag_len = 0.7 * D.UPM
	_start()


func _start() -> void:
	cur = rec
	t = 0.0
	active = true
	cap = 1.0
	visible = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mat_ghost.set_shader_parameter("fade", 0.0)
	# камера: сбоку от линии выстрела и немного сверху, так видно и вход, и путь внутри
	var dh := Vector3(cur.d.x, 0.0, cur.d.z)
	dh = dh.normalized() if dh.length() > 0.05 else Vector3.RIGHT
	var side := 1.0 if (cur.p.z * cur.d.x - cur.p.x * cur.d.z) >= 0.0 else -1.0
	cam_az = 0.0
	cam_base = (-dh).rotated(Vector3.UP, deg_to_rad(52.0) * side)
	_place_cam(0.0)
	_hide_fx()
	_set_items(0.0)
	queue_redraw()


func _place_cam(az: float) -> void:
	var dirv := cam_base.rotated(Vector3.UP, az)
	var dist := cam_r * 1.75
	var pos := cam_c + dirv * dist + Vector3.UP * dist * 0.4
	cam.global_position = pos
	cam.look_at(cam_c + Vector3(0, cam_r * 0.05, 0), Vector3.UP)


func _clear() -> void:
	for c in ghost.get_children():
		c.queue_free()
	for c in inner.get_children():
		c.queue_free()
	items.clear()


func stop_now() -> void:
	active = false
	cur = {}
	visible = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hide_fx()


# ---------- Анимация ----------

func _line(mi: MeshInstance3D, a: Vector3, b: Vector3, w: float) -> void:
	var l := a.distance_to(b)
	if l < 0.01:
		mi.visible = false
		return
	var d := (b - a) / l
	var bs := Basis(Quaternion(Vector3.UP, d)) * Basis.from_scale(Vector3(w, l, w))
	mi.transform = Transform3D(bs, (a + b) * 0.5)
	mi.visible = true


func _set_items(now: float) -> void:
	for e: Dictionary in items:
		var k := clampf((now - float(e.t)) / 0.25, 0.0, 1.0)
		var c: Color = (e.base as Color).lerp(e.to, k)
		if k > 0.0 and k < 1.0:
			c = c.lerp(Color.WHITE, 0.5 * sin(k * PI))
		(e.mat as ShaderMaterial).set_shader_parameter("col", Color(c.r, c.g, c.b, 0.92))


func _process(delta: float) -> void:
	if not active:
		return
	t += delta
	var total := T_APPROACH + T_INSIDE + T_HOLD + T_FADE
	if t >= total:
		stop_now()
		return
	cap = 1.0 - clampf((t - (total - T_FADE)) / T_FADE, 0.0, 1.0)
	modulate.a = cap
	queue_redraw()
	mat_ghost.set_shader_parameter("fade", clampf(t / 0.3, 0.0, 1.0) * cap)
	cam_az += delta * 0.16
	_place_cam(cam_az)
	_set_items(t)
	var U := D.UPM
	var p: Vector3 = cur.p
	var d: Vector3 = cur.d
	var cal: float = cur.cal
	var k_cal := clampf(cal / 85.0, 0.6, 1.8)
	var shell_w := 0.34 * U * k_cal
	var shell_l := 1.3 * U * k_cal
	var approach := 7.0 * U
	_hide_fx()
	if t < T_APPROACH:
		# подлёт
		var f := t / T_APPROACH
		var pos := p - d * approach * (1.0 - f)
		_shell_at(pos, d, shell_w, shell_l)
		_line(trail_mi, p - d * approach, pos, shell_w * 0.35)
		return
	var te := t - T_APPROACH  # время после касания брони
	# вспышка в месте попадания
	if te < 0.4:
		var fk := te / 0.4
		flash_mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * (1.0 + 4.0 * fk) * 0.6 * U * k_cal), p)
		mat_flash.set_shader_parameter("col", Color(1.0, 0.92, 0.6, 0.9 * (1.0 - fk)))
		flash_mi.visible = true
	# подводящая линия остаётся бледной
	_line(path_mi, p - d * approach, p, shell_w * 0.2)
	match int(cur.outcome):
		2:
			var stop: float = maxf(float(cur.stop), 1.0)
			var f := clampf(te / T_INSIDE, 0.0, 1.0)
			var ease := 1.0 - pow(1.0 - f, 2.0)
			var head := p + d * stop * ease
			if f < 1.0 or not cur.armed:
				_shell_at(head, d, shell_w, shell_l * (1.0 if f < 1.0 else maxf(0.0, 1.0 - (te - T_INSIDE) * 2.5)))
			_line(trail_mi, p, head, shell_w * 0.5)
			# разрыв: шар до радиуса поражения
			if cur.armed and te >= T_INSIDE:
				var bk := clampf((te - T_INSIDE) / 0.35, 0.0, 1.0)
				var fade := 1.0 - clampf((te - T_INSIDE - 0.35) / 1.0, 0.0, 1.0)
				var br: float = maxf(float(cur.burst_r), 1.0)
				burst_mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * br * 2.0 * (0.25 + 0.75 * sqrt(bk))), p + d * stop)
				mat_burst.set_shader_parameter("col", Color(1.0, 0.55, 0.15, 0.45 * fade))
				burst_mi.visible = true
			_frags(p, te, 0.45, 1.1)
		1:
			# остался снаружи: сплющивается у брони
			var f1 := clampf(te / 0.35, 0.0, 1.0)
			_shell_at(p - d * shell_l * 0.5 * (1.0 - f1 * 0.5), d, shell_w * (1.0 + f1 * 0.4), shell_l * (1.0 - f1 * 0.45) * (1.0 - clampf((te - 0.9) / 0.5, 0.0, 1.0)))
			_frags(p, te, 0.3, 0.7)
		0:
			# рикошет: отскакивает по отражённому направлению
			var rd: Vector3 = cur.rico if cur.rico.length() > 0.1 else (d - 2.0 * d.dot(Vector3.UP) * Vector3.UP).normalized()
			var f2 := clampf(te / 0.9, 0.0, 1.0)
			var head2 := p + rd * 9.0 * U * f2
			_shell_at(head2, rd, shell_w, shell_l * (1.0 - f2 * 0.5))
			_line(trail_mi, p, head2, shell_w * 0.4)
			_frags(p, te, 0.25, 0.6)


func _shell_at(pos: Vector3, dir: Vector3, w: float, l: float) -> void:
	if l <= 0.01:
		return
	var bs := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(w, l / 2.2, w))
	shell_mi.transform = Transform3D(bs, pos)
	shell_mi.visible = true


## Осколки: лучи из точки пробития, растут за start секунд после касания и гаснут к end.
func _frags(p: Vector3, te: float, grow: float, life: float) -> void:
	if not cur.has("frag_dirs"):
		return
	var dirs: Array = cur.frag_dirs
	var fl: float = cur.frag_len
	var gk := clampf(te / grow, 0.0, 1.0)
	var al := 1.0 - clampf((te - life) / 0.6, 0.0, 1.0)
	if al <= 0.0:
		return
	mat_frag.set_shader_parameter("col", Color(1.0, 0.72, 0.3, 0.85 * al))
	for i in mini(dirs.size(), FR_N):
		var fm: MeshInstance3D = frag_mis[i]
		_line(fm, p, p + (dirs[i] as Vector3) * fl * gk, D.UPM * 0.07)


# ---------- Окно ----------

func _draw() -> void:
	if not active or cur.is_empty():
		return
	var a := 1.0  # окно целиком гаснет через modulate
	Gfx.box(self, sb_win, Rect2(Vector2.ZERO, Vector2(PW, PH)))
	var font := ThemeDB.fallback_font
	var tk: TankScript = cur.tk
	var mine: bool = cur.mine
	var head_col := Color(D.AMBER) if mine else Color("ff8a6a")
	draw_string(font, Vector2(10, 18), "ВАШ ВЫСТРЕЛ" if mine else "ПО ВАМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(head_col, a))
	var tname: String = D.TYPES[tk.type_key].tag if D.TYPES.has(tk.type_key) else tk.type_key
	draw_string(font, Vector2(PW - 10 - 220, 18), tname, HORIZONTAL_ALIGNMENT_RIGHT, 220, 14, Color(UI.TEXT, a))
	draw_texture_rect(vp.get_texture(), Rect2(Vector2(4, HEAD), Vector2(PW - 8, VIEW_H)), false, Color(1, 1, 1, a))
	var y := HEAD + VIEW_H + 18.0
	var te := t - T_APPROACH
	if te < 0.0:
		return
	var out_name: String = ["РИКОШЕТ", "НЕ ПРОБИЛ", "ПРОБИТИЕ"][int(cur.outcome)]
	var out_col: Color = [Color("cfd3d8"), Color("e8d27a"), Color("ff6a4a")][int(cur.outcome)]
	draw_string(font, Vector2(10, y), out_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(out_col, a))
	var num := "броня %d мм, угол %d° → %d мм" % [roundi(cur.armor), roundi(cur.ang), roundi(cur.eff)]
	draw_string(font, Vector2(10, y + 17), num, HORIZONTAL_ALIGNMENT_LEFT, PW - 16, 12, Color(UI.DIM, a))
	draw_string(font, Vector2(PW - 10 - 120, y), "пробитие %d мм" % roundi(cur.pen), HORIZONTAL_ALIGNMENT_RIGHT, 120, 13, Color(UI.TEXT, a))
	# что пострадало, по мере того как снаряд до этого долетает
	var lines: Array = []
	for e: Dictionary in items:
		if te + T_APPROACH >= float(e.t) and e.to != e.base:
			var nm: String = TankScript.NAMES.get(e.name, e.name)
			lines.append([nm + (" — выбыл" if e.crew and e.to == COL_DEAD else " — ранен" if e.crew else " ✕" if e.to == COL_DEAD else " — повр."), e.to])
	if cur.fire and te > T_INSIDE * 0.6:
		lines.append(["ПОЖАР", Color("ff9a4a")])
	if cur.outcome == 2 and cur.armed and te >= T_INSIDE:
		lines.append(["Снаряд разорвался внутри", Color("ffb36a")])
	elif cur.outcome == 2 and not cur.armed and te > 0.3:
		lines.append(["Взрыватель не взвёлся — снаряд прошил насквозь", Color(UI.DIM)])
	elif cur.outcome == 2 and te > 0.3 and lines.is_empty():
		lines.append(["За бронёй ничего не задето", Color(UI.DIM)])
	var yy := y + 38.0
	var col_x := [10.0, PW * 0.5 + 2.0]
	var row := 0
	var colm := 0
	for ln: Array in lines:
		var txt := String(ln[0])
		var wide := txt.length() > 24
		if wide and colm == 1:
			row += 1
			colm = 0
		if row >= 4:
			break
		draw_string(font, Vector2(col_x[colm], yy + float(row) * 15.0), txt, HORIZONTAL_ALIGNMENT_LEFT, PW - 16 if wide else PW * 0.5 - 8, 12, ln[1])
		if wide:
			row += 1
			colm = 0
		else:
			colm += 1
			if colm == 2:
				colm = 0
				row += 1
