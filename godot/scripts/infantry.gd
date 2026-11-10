extends Node3D
## Пехота: показывает бойцов, которых считает C++ (native/src/infantry.inc).
## Модели — готовые (Sketchfab, CC BY), запечены tools/import_units.py в assets/units/*.bin: позы лежат
## в текстуре (строка — поза, столбец — вершина), шейдер смешивает две позы на бойца. Один MultiMesh на вид бойца.

const D = preload("res://scripts/data.gd")
const DIR := "res://assets/units/"
const NATS := ["ger", "sov", "usa", "ally", "ally", "ally"]  # 4 — Япония, 5 — Италия: модель союзника в своём цвете
const TINT := [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color(1.05, 0.98, 0.72), Color(0.82, 0.92, 0.86)]
const ROLES := ["rifle", "smg", "atr", "tube", "faust", "crew"]
const VIEW := 9
const SCALE := 8.0  # метры модели → единицы карты (чуть крупнее 7,5, чтобы бойцов было видно)
# позы в запечённых файлах
const P_STAND := 0
const P_AIM := 1
const P_KNEEL := 2
const P_PRONE := 3
const P_RUN := 4
const P_CRAWL := 12
const P_FALL_B := 16
const P_DEAD_B := 17
const P_FALL_F := 18
const P_DEAD_F := 19
const P_THROW_A := 20
const P_THROW_B := 21
const P_CROUCH := 22

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform sampler2D vat : filter_nearest, repeat_disable;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform int poses = 23;
void vertex() {
	int vi = int(UV2.x + 0.5);
	int a = int(INSTANCE_CUSTOM.r + 0.5);
	int b = int(INSTANCE_CUSTOM.g + 0.5);
	float k = INSTANCE_CUSTOM.b;
	vec3 pa = texelFetch(vat, ivec2(vi, a), 0).rgb;
	vec3 pb = texelFetch(vat, ivec2(vi, b), 0).rgb;
	vec3 na = texelFetch(vat, ivec2(vi, a + poses), 0).rgb;
	vec3 nb = texelFetch(vat, ivec2(vi, b + poses), 0).rgb;
	VERTEX = mix(pa, pb, k);
	NORMAL = normalize(mix(na, nb, k));
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 0.92;
}
"""

var battle
var core
var units := {}  # имя → {mm, n_poses}
var atlases := {}
var shader: Shader
var view := PackedFloat32Array()
var prev := PackedFloat32Array()
var count := 0
var kills := 0
var pose_a := PackedInt32Array()  # текущая «устойчивая» поза бойца и откуда в неё переходит
var pose_from := PackedInt32Array()
var pose_t := PackedFloat32Array()
var tracers: Array = []
var tracer_mm: MultiMesh
var snd_t := 0.0
var snd_n := 0
var stat := {"shots": [0, 0, 0, 0, 0, 0, 0], "dead": [0, 0, 0]}  # выстрелов по видам, потерь по причинам


## rows — отделения для C++ (по 16 чисел, см. compose). Возвращает число бойцов.
func setup(b, c, rows: PackedFloat32Array, shadows: bool) -> int:
	battle = b
	core = c
	if core == null or not core.has_method("inf_init") or rows.is_empty():
		return 0
	count = int(core.inf_init(rows))
	if count <= 0:
		return 0
	shader = Shader.new()
	shader.code = SHADER
	view = core.inf_view()
	prev = view.duplicate()
	pose_a.resize(count)
	pose_from.resize(count)
	pose_t.resize(count)
	for k in count:
		pose_a[k] = P_STAND
		pose_from[k] = P_STAND
		pose_t[k] = 1.0
	# какие виды бойцов нужны
	var need := {}
	for k in count:
		need[_unit_name(int(view[k * VIEW + 7]))] = true
	for nm in need:
		var u := _load_unit(nm, shadows)
		if not u.is_empty():
			units[nm] = u
	_make_tracers()
	return count


func _unit_name(code: int) -> String:
	var nat: String = NATS[clampi(code / 8, 0, NATS.size() - 1)]
	var role: String = ROLES[clampi(code % 8, 0, ROLES.size() - 1)]
	var nm := nat + "_" + role
	if not FileAccess.file_exists(DIR + nm + ".bin"):
		nm = nat + "_rifle"
	return nm


func _atlas(nat: String) -> Texture2D:
	if atlases.has(nat):
		return atlases[nat]
	var t: Texture2D = load(DIR + nat + ".png")
	if t:
		var img := t.get_image()
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	atlases[nat] = t
	return t


func _load_unit(nm: String, shadows: bool) -> Dictionary:
	var f := FileAccess.open(DIR + nm + ".bin", FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 16 or raw.slice(0, 4).get_string_from_ascii() != "SUV1":
		return {}
	var jl := raw.decode_u32(4)
	var info = JSON.parse_string(raw.slice(8, 8 + jl).get_string_from_utf8())
	if not (info is Dictionary):
		return {}
	var nv := int(info.nv)
	var ni := int(info.ni)
	var np := (info.poses as Array).size()
	var o := 8 + jl
	var pos := raw.slice(o, o + nv * 12).to_float32_array()
	o += nv * 12
	var uvf := raw.slice(o, o + nv * 8).to_float32_array()
	o += nv * 8
	var idx := PackedInt32Array()
	idx.resize(ni)
	for i in ni:
		idx[i] = raw.decode_u16(o + i * 2)
	o += ni * 2
	var vat := raw.slice(o, o + 2 * np * nv * 6)
	if vat.size() < 2 * np * nv * 6:
		return {}
	# обход треугольников — под отсечение задних граней Godot (по нормалям стойки)
	var vote := 0
	var nrow := np * nv * 6
	for t in range(0, mini(ni, 600), 3):
		var a := Vector3(pos[idx[t] * 3], pos[idx[t] * 3 + 1], pos[idx[t] * 3 + 2])
		var b := Vector3(pos[idx[t + 1] * 3], pos[idx[t + 1] * 3 + 1], pos[idx[t + 1] * 3 + 2])
		var c := Vector3(pos[idx[t + 2] * 3], pos[idx[t + 2] * 3 + 1], pos[idx[t + 2] * 3 + 2])
		var q := nrow + idx[t] * 6
		var n := Vector3(vat.decode_half(q), vat.decode_half(q + 2), vat.decode_half(q + 4))
		vote += 1 if (b - a).cross(c - a).dot(n) > 0.0 else -1
	if vote > 0:
		for t in range(0, ni - 2, 3):
			var sw := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = sw
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	verts.resize(nv)
	norms.resize(nv)
	uv.resize(nv)
	uv2.resize(nv)
	for i in nv:
		verts[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
		norms[i] = Vector3.UP
		uv[i] = Vector2(uvf[i * 2], uvf[i * 2 + 1])
		uv2[i] = Vector2(float(i), 0.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 3, 4))
	var img := Image.create_from_data(nv, 2 * np, false, Image.FORMAT_RGBH, vat)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("vat", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("tex", _atlas(nm.get_slice("_", 0)))
	mat.set_shader_parameter("poses", np)
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-200, -300, -200), Vector3(D.WS + 400, 900, D.WS + 400))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mi)
	return {"mm": mm, "np": np, "list": []}


func _make_tracers() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 16.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.86, 0.5)
	box.material = m
	tracer_mm = MultiMesh.new()
	tracer_mm.transform_format = MultiMesh.TRANSFORM_3D
	tracer_mm.mesh = box
	tracer_mm.instance_count = 40
	tracer_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = tracer_mm
	mi.custom_aabb = AABB(Vector3(-200, -300, -200), Vector3(D.WS + 400, 900, D.WS + 400))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mi)


## После шага логики: новая сводка из C++.
func step() -> void:
	if count <= 0:
		return
	prev = view
	view = core.inf_view()
	if view.size() > count * VIEW:
		kills = int(view[count * VIEW])


## Каждый кадр: положения между шагами логики, позы, трассы.
func frame(frac: float, dt: float) -> void:
	if count <= 0:
		return
	for nm in units:
		(units[nm].list as Array).clear()
	for k in count:
		var q := k * VIEW
		var fl := int(view[q + 8])
		if (fl & 1) == 0 or (fl & 2) != 0:  # павшие остаются лежать, живых врагов видно только засвеченных
			var nm := _unit_name(int(view[q + 7]))
			if units.has(nm):
				(units[nm].list as Array).append(k)
	for nm in units:
		var u: Dictionary = units[nm]
		var list: Array = u.list
		var mm: MultiMesh = u.mm
		if mm.instance_count < list.size():
			mm.instance_count = maxi(list.size(), mini(count, mm.instance_count + 16))
		mm.visible_instance_count = list.size()
		for j in list.size():
			var k: int = list[j]
			var q := k * VIEW
			var x := lerpf(prev[q], view[q], frac)
			var y := lerpf(prev[q + 1], view[q + 1], frac)
			var z := lerpf(prev[q + 2], view[q + 2], frac)
			var yaw := lerp_angle(prev[q + 3], view[q + 3], frac)
			var st := int(view[q + 4])
			var ph := view[q + 5]
			var a := P_STAND
			var b := P_STAND
			var bl := 0.0
			var cyc := false
			match st:
				1:  # бег
					var f := fposmod(lerpf(prev[q + 5], ph, frac) if absf(ph - prev[q + 5]) < 0.5 else ph, 1.0) * 8.0
					a = P_RUN + int(f) % 8
					b = P_RUN + (int(f) + 1) % 8
					bl = f - floorf(f)
					cyc = true
				5:  # ползёт
					var f2 := fposmod(ph, 1.0) * 4.0
					a = P_CRAWL + int(f2) % 4
					b = P_CRAWL + (int(f2) + 1) % 4
					bl = f2 - floorf(f2)
					cyc = true
				6, 7:  # падает и лежит (ph — секунд с гибели)
					var fall := P_FALL_B if st == 6 else P_FALL_F
					var dead := P_DEAD_B if st == 6 else P_DEAD_F
					if ph < 0.22:
						a = pose_a[k]
						b = fall
						bl = ph / 0.22
					else:
						a = fall
						b = dead
						bl = smoothstep(0.0, 1.0, clampf((ph - 0.22) / 0.4, 0.0, 1.0))
					cyc = true
				8:  # бросок гранаты
					if ph < 0.45:
						a = P_THROW_A
						b = P_THROW_B
						bl = clampf((ph - 0.25) / 0.2, 0.0, 1.0)
					else:
						a = P_THROW_B
						b = P_STAND
						bl = clampf((ph - 0.6) / 0.4, 0.0, 1.0)
					cyc = true
				2:
					a = P_AIM
				3:
					a = P_KNEEL
				4:
					a = P_PRONE
				9:
					a = P_CROUCH
				_:
					a = P_STAND
			if not cyc:
				# плавный переход между устойчивыми позами
				if a != pose_a[k]:
					pose_from[k] = pose_a[k]
					pose_a[k] = a
					pose_t[k] = 0.0
				pose_t[k] = minf(1.0, pose_t[k] + dt * 4.5)
				b = a
				a = pose_from[k]
				bl = smoothstep(0.0, 1.0, pose_t[k])
			elif st == 1 or st == 5:
				pose_a[k] = a
				pose_t[k] = 1.0
			var basis := Basis(Vector3.UP, PI * 0.5 - yaw).scaled(Vector3(SCALE, SCALE, SCALE))
			mm.set_instance_transform(j, Transform3D(basis, Vector3(x, y, z)))
			mm.set_instance_color(j, TINT[clampi(int(view[q + 7]) / 8, 0, TINT.size() - 1)])
			mm.set_instance_custom_data(j, Color(float(a), float(b), bl, 0.0))
	# трассы пуль
	var n := 0
	var i := 0
	while i < tracers.size():
		var t: Dictionary = tracers[i]
		t.s += 2600.0 * dt
		if t.s >= t.len:
			tracers.remove_at(i)
			continue
		if n < tracer_mm.instance_count:
			var p: Vector3 = t.from + t.dir * t.s
			tracer_mm.set_instance_transform(n, Transform3D(Basis.looking_at(t.dir, Vector3.UP if absf(t.dir.y) < 0.95 else Vector3.RIGHT), p))
			n += 1
		i += 1
	tracer_mm.visible_instance_count = n
	snd_t -= dt
	if snd_t <= 0.0:
		snd_t = 0.12
		snd_n = 0


## Выстрел: вид (роль бойца, 5 — пулемёт танка, 6 — граната), откуда, направление, место трассера, скорость/дальность.
func on_shot(ev: PackedFloat32Array, q: int) -> void:
	var kind := int(ev[q + 1])
	stat.shots[clampi(kind, 0, 6)] += 1
	var at := Vector3(ev[q + 2], ev[q + 3], ev[q + 4])
	var dir := Vector3(ev[q + 5], ev[q + 6], ev[q + 7])
	var slot := int(ev[q + 8])
	var near: bool = at.distance_squared_to(battle.cam.global_position) < 900.0 * 900.0
	if kind == 6:
		battle.fx.impact(at, true)
		battle.fx.flash(at, Color(1, 0.7, 0.4), 4.0, 60.0)
		battle.sfx.play3d("grenade", at)
		return
	if slot >= 0:
		# ПТ-ружьё, гранатомёт, «фауст»: настоящий снаряд — трассер как у танков
		battle._slot_visual(slot, at, dir * ev[q + 9], 1e9)
		if kind == 2:
			battle.fx.muzzle(at, dir, 22.0)
			battle.sfx.play3d("atr", at)
		else:
			battle.fx.muzzle(at, dir, 30.0)
			battle.fx.emit(at - dir * 6.0, 10, 1.6, "smoke", 30, 110, -dir, 25, 4, 14.0, false, true, 2.5)
			battle.sfx.play3d("rocket", at)
		return
	if near and tracers.size() < 40 and (kind == 5 or kind == 1 or randf() < 0.5):
		tracers.append({"from": at, "dir": dir, "s": 0.0, "len": maxf(20.0, ev[q + 9])})
	if near:
		battle.fx.emit(at, 3, 0.07, "fire", 20, 90, dir, 14, 0, 2.2, true, false, 5)
	if snd_n < 3:
		snd_n += 1
		battle.sfx.play3d("mg" if kind == 5 else ("smg" if kind == 1 else "rifle"), at)


func on_dead(ev: PackedFloat32Array, q: int) -> void:
	stat.dead[clampi(int(ev[q + 3]), 0, 2)] += 1
	var at := Vector3(ev[q + 4], ev[q + 5] + 3.0, ev[q + 6])
	if at.distance_squared_to(battle.cam.global_position) < 700.0 * 700.0:
		battle.fx.emit(at, 4, 0.8, "dust", 8, 30, Vector3.UP, 60, 3, 9.0, false, true, 2)


## Точки для миникарты: [x, z, команда] живых бойцов (врагов — только видимых).
func dots() -> PackedFloat32Array:
	var o := PackedFloat32Array()
	for k in count:
		var q := k * VIEW
		var fl := int(view[q + 8])
		if (fl & 1) != 0 and (fl & 2) != 0:
			o.append(view[q])
			o.append(view[q + 2])
			o.append(view[q + 6])
	return o


func alive_of(team: int) -> int:
	var n := 0
	for k in count:
		if (int(view[k * VIEW + 8]) & 1) != 0 and int(view[k * VIEW + 6]) == team:
			n += 1
	return n


## Состав пехоты на бой: по отделению на направление каждой стороне. Оружие — по нации и году.
## lanes — x трёх направлений; sides — [нация команды 0, нация команды 1]; amount: 1 — меньше, 2 — полный.
static func compose(nats: Array, year: int, lanes: Array, ws: float, amount: int) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	if amount <= 0:
		return rows
	for team in 2:
		var w := weapons(String(nats[team]), year)
		for ln in 3:
			if amount == 1 and ln == 1:
				continue
			var y := (ws - 400.0) if team == 0 else 400.0
			var x := float(lanes[ln]) + (70.0 if ln % 2 == 0 else -70.0)
			var n_at := 1 if (w.atr or w.tube) else 0
			var rifles := 5 if amount > 1 else 4
			var smgs := (2 if amount > 1 else 1) if w.smg else 0
			if not w.smg:
				rifles += 1
			rows.append_array([float(team), float(ln), x, y, 0.0, float(w.nat), float(rifles), float(smgs),
				float(n_at) if (w.atr and not w.tube) else (1.0 if w.atr and ln == 1 else 0.0),
				float(n_at) if w.tube else 0.0, (1.0 if ln != 1 else 2.0) if w.faust else 0.0,
				float(w.atr_pen), float(w.tube_pen), float(w.faust_pen), float(w.tube_cal), 0.0])
	return rows


## Противотанковое оружие пехоты по нации и году: что было в войсках.
static func weapons(nation: String, year: int) -> Dictionary:
	var w := {"nat": 3, "smg": false, "atr": false, "tube": false, "faust": false, "atr_pen": 25.0, "tube_pen": 90.0,
		"faust_pen": 140.0, "tube_cal": 60.0}
	match nation:
		"Германия":
			w.nat = 0
			w.smg = true
			w.atr = year <= 1942  # PzB 39
			w.atr_pen = 30.0
			w.tube = year >= 1943  # «Панцершрек»
			w.tube_pen = 200.0 if year >= 1944 else 160.0
			w.tube_cal = 88.0
			w.faust = year >= 1943
			w.faust_pen = 200.0 if year >= 1944 else 140.0
		"СССР":
			w.nat = 1
			w.smg = true
			w.atr = year >= 1941  # ПТРД / ПТРС
			w.atr_pen = 40.0
		"США":
			w.nat = 2
			w.tube = year >= 1942  # базука
			w.tube_pen = 100.0 if year >= 1944 else 80.0
		"Япония":
			w.nat = 4
			w.atr = true  # Тип 97
			w.atr_pen = 30.0
		"Италия":
			w.nat = 5
			w.atr = true  # «Золотурн»
			w.atr_pen = 35.0
		_:
			w.nat = 3
			w.atr = year <= 1942  # «Бойс»
			w.atr_pen = 23.0
			w.tube = year >= 1943  # PIAT
			w.tube_pen = 100.0
			w.tube_cal = 83.0
	return w
