extends Node3D
## Пехота: показывает бойцов, которых считает C++ (native/src/infantry.inc).
## Модели — готовые (Sketchfab, CC BY), запечены tools/import_units.py в assets/units/*.bin: позы лежат
## в текстуре (строка — поза, столбец — вершина), шейдер смешивает две позы на бойца. Один MultiMesh на вид бойца.

const D = preload("res://scripts/data.gd")
const DIR := "res://assets/units/"
const NATS := ["ger", "sov", "usa", "ally", "ally", "ally"]  # 4 — Япония, 5 — Италия: модель союзника в своём цвете
const TINT := [Color.WHITE, Color(0.78, 0.8, 0.72), Color.WHITE, Color.WHITE, Color(1.05, 0.98, 0.72), Color(0.82, 0.92, 0.86)]
const ROLES := ["rifle", "smg", "atr", "tube", "faust", "crew", "gun"]
const GUNS := ["m3", "pak40", "flak88"]  # модели пушек: лёгкая (37–47 мм), средняя (75–76 мм), 88-мм зенитка
# окраска пушек по нации (модель лёгкой — оливковая, средней — серая)
const GUN_TINT := [
	[Color(0.8, 0.84, 0.9), Color(0.85, 1.0, 0.7), Color.WHITE, Color(0.95, 0.95, 0.8), Color(1.05, 0.95, 0.65), Color(1.0, 0.95, 0.75)],
	[Color.WHITE, Color(0.62, 0.85, 0.45), Color(0.75, 0.82, 0.5), Color(0.8, 0.85, 0.55), Color(0.9, 0.85, 0.5), Color(0.9, 0.85, 0.6)],
	[Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]]
const CREW_AT := [Vector3(-0.85, 0, -1.1), Vector3(0.85, 0, -1.3), Vector3(0.1, 0, -2.6)]  # места расчёта у пушки, м
const VIEW := 9
const AIR_N := 16  # чисел на самолёт в air_view
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
var uof := PackedInt32Array()  # номер модели каждого бойца для inf_pose (−1 — не рисуется в C++)
var unit_names: Array = []  # модели бойцов по номерам (порядок units)
var _code_unit := {}  # код бойца → номер модели (−1 — пушка или нет модели)
var TINT_F := PackedFloat32Array()
var pose_a := PackedInt32Array()  # текущая «устойчивая» поза бойца и откуда в неё переходит
var pose_from := PackedInt32Array()
var pose_t := PackedFloat32Array()
var tracers: Array = []
var tracer_mm: MultiMesh
var snd_t := 0.0
var snd_n := 0
var plane_of := ["plane_il2", "plane_ju87"]  # самолёт каждой команды
var planes: Array = []  # (прежний пролёт по сценарию; теперь самолёты считает C++ — air)
var air := PackedFloat32Array()  # самолёты из C++: по 12 чисел (см. air_view)
var air_prev := PackedFloat32Array()
var air_snd := {}  # номер самолёта → когда последний раз звучал мотор
var air_clock := 0.0
var decor: Array = []
const PLANE_V := 520.0  # скорость пролёта, ед/с
var stat := {"shots": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "dead": [0, 0, 0]}  # выстрелов по видам, потерь по причинам


## rows — отделения для C++ (по 16 чисел, см. compose). Возвращает число бойцов.
func setup(b, c, rows: PackedFloat32Array, shadows: bool) -> int:
	battle = b
	core = c
	if core == null or not core.has_method("inf_init"):
		return 0
	count = int(core.inf_init(rows))
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
		var code := int(view[k * VIEW + 7])
		need[_unit_name(code)] = true
		if code % 8 == 6:
			need[_crew_name(code)] = true
	for nm in need:
		var u := _load_unit(nm, shadows)
		if not u.is_empty():
			units[nm] = u
	for pn in plane_of:
		if not units.has(pn):
			var pu := _load_unit(pn, false)
			if not pu.is_empty():
				units[pn] = pu
	unit_names = units.keys()
	TINT_F.clear()
	for tc: Color in TINT:
		TINT_F.append_array([tc.r, tc.g, tc.b, tc.a])
	_make_tracers()
	return count


## Неподвижные мелочи окружения (камни, трава, мешки): свой MultiMesh на модель, ставится один раз.
## items — [Transform3D, Color]. Возвращает, сколько поставлено.
func scatter(nm: String, items: Array, shadows: bool) -> int:
	if items.is_empty() or shader == null:
		return 0
	var u := _load_unit(nm, shadows)
	if u.is_empty():
		return 0
	var mm: MultiMesh = u.mm
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
		var ps := float(items[i][2]) if (items[i] as Array).size() > 2 else 0.0  # поза (у бойцов — павший)
		mm.set_instance_custom_data(i, Color(ps, ps, 0, 0))
	decor.append(u)
	return items.size()


## Самолёт по номеру: смещение в массиве air или −1.
func plane_at(id: int) -> int:
	for a in range(0, air.size() - 1, AIR_N):
		if int(air[a + 12]) == id and (int(air[a + 7]) & 1) != 0:
			return a
	return -1


## Положение и направление самолёта между шагами логики: [место, вперёд].
func plane_xf(a: int, frac: float) -> Array:
	var same := air_prev.size() == air.size() and int(air_prev[a + 12]) == int(air[a + 12])
	var pp := Vector3(air[a], air[a + 1], air[a + 2])
	var yaw := air[a + 3]
	var pitch := air[a + 4]
	if same:
		pp = Vector3(lerpf(air_prev[a], air[a], frac), lerpf(air_prev[a + 1], air[a + 1], frac), lerpf(air_prev[a + 2], air[a + 2], frac))
		yaw = lerp_angle(air_prev[a + 3], air[a + 3], frac)
		pitch = lerpf(air_prev[a + 4], air[a + 4], frac)
	return [pp, Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))]


## Самолёты для миникарты: [x, z, команда, курс].
func air_dots() -> PackedFloat32Array:
	var o := PackedFloat32Array()
	for a in range(0, air.size() - 1, AIR_N):
		if (int(air[a + 7]) & 1) != 0:
			o.append_array([air[a], air[a + 2], air[a + 6], air[a + 3]])
	return o


## Вооружение штурмовика по нации и году: [калибр пушки, пробитие, урон, выстрелов/с, снарядов, бомб, калибр бомбы, прочность].
static func air_weapon(nation: String, year: int) -> Array:
	match nation:
		"СССР":
			return [23.0, 26.0, 24.0, 9.0, 80.0, 4.0, 150.0, 150.0]  # Ил-2: ВЯ-23, ФАБ-100, бронекорпус
		"Германия", "Венгрия":
			if year >= 1943:
				return [37.0, 95.0, 70.0, 2.6, 24.0, 1.0, 200.0, 95.0]  # Ju 87 G: две 37-мм BK 3,7
			return [20.0, 20.0, 16.0, 10.0, 60.0, 3.0, 200.0, 95.0]  # Ju 87 D: MG 151/20, SC 250
		"США", "Великобритания", "Франция":
			return [12.7, 20.0, 10.0, 18.0, 220.0, 2.0, 180.0, 115.0]  # P-47: восемь 12,7-мм, две бомбы
	return [20.0, 20.0, 16.0, 8.0, 60.0, 2.0, 150.0, 90.0]


## Где стоят пушки: [x, z, курс, команда] — вокруг них battle ставит мешки с песком.
func gun_spots() -> Array:
	var out: Array = []
	for k in count:
		var q := k * VIEW
		if int(view[q + 7]) % 8 == 6:
			out.append([view[q], view[q + 2], view[q + 3], int(view[q + 6])])
	return out


## Штурмовик: пролёт над целью через delay секунд по курсу dir (x, z).
func add_plane(team: int, target: Vector3, dir: Vector2, delay: float) -> void:
	var nm: String = plane_of[clampi(team, 0, 1)]
	if not units.has(nm):
		return
	planes.append({"unit": nm, "t": -delay, "target": target, "dir": Vector3(dir.x, 0.0, dir.y).normalized(), "snd": false})


func _crew_name(code: int) -> String:
	return String(NATS[clampi((code / 8) % 64, 0, NATS.size() - 1)]) + "_crew"


func _unit_name(code: int) -> String:
	if code % 8 == 6:
		return "gun_" + String(GUNS[clampi(code / 512, 0, GUNS.size() - 1)])
	var nat: String = NATS[clampi((code / 8) % 64, 0, NATS.size() - 1)]
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
	mat.set_shader_parameter("tex", _atlas(nm if ResourceLoader.exists(DIR + nm + ".png") else nm.get_slice("_", 0)))
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
	return {"mm": mm, "np": np, "list": [], "extra": []}


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
	if core and core.has_method("air_view"):
		air_prev = air
		air = core.air_view()
		if air_prev.size() != air.size():
			air_prev = air
	if count <= 0:
		return
	prev = view
	view = core.inf_view()
	if view.size() > count * VIEW:
		kills = int(view[count * VIEW])


## Каждый кадр: положения между шагами логики, позы, трассы.
func frame(frac: float, dt: float) -> void:
	for nm in units:
		(units[nm].list as Array).clear()
		(units[nm].extra as Array).clear()
	# самолёты: положение и углы из C++ (между шагами — плавно), дым у сбитых, звук моторов
	air_clock += dt
	for a in range(0, air.size() - 1, AIR_N):
		var fl := int(air[a + 7])
		if (fl & 1) == 0:
			continue
		var nm: String = plane_of[clampi(int(air[a + 6]), 0, 1)]
		if not units.has(nm):
			continue
		var pp := Vector3(lerpf(air_prev[a], air[a], frac), lerpf(air_prev[a + 1], air[a + 1], frac), lerpf(air_prev[a + 2], air[a + 2], frac))
		var yaw := lerp_angle(air_prev[a + 3], air[a + 3], frac)
		var pitch := lerpf(air_prev[a + 4], air[a + 4], frac)
		var roll := lerp_angle(air_prev[a + 5], air[a + 5], frac)
		var fwd := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		var pb := Basis.looking_at(-fwd, Vector3.UP) * Basis(Vector3(0, 0, 1), roll)
		(units[nm].extra as Array).append([pp, pb.scaled(Vector3(SCALE, SCALE, SCALE)), 0, 0])
		var id := int(air[a + 12])
		var near: bool = pp.distance_squared_to(battle.cam.global_position) < 1800.0 * 1800.0
		if near and air_clock - float(air_snd.get(id, -99.0)) > 11.0:
			air_snd[id] = air_clock
			battle.sfx.play3d("plane", pp, 4.0)
		if (fl & 128) != 0 and (fl & 2) == 0 and near and randf() < dt * 6.0:
			battle.fx.emit(pp, 1, 1.4, "dark", 4, 14, Vector3.UP, 40, 1, 10.0, false, true, 0.8)  # дым из мотора
		if (fl & 2) != 0 and near and randf() < dt * 14.0:
			battle.fx.emit(pp, 2, 2.2, "dark", 5, 20, Vector3.UP, 60, 2, 16.0, false, true, 1.0)
		if (fl & 4) != 0 and near and randf() < dt * 10.0:
			battle.fx.emit(pp + fwd * 14.0, 2, 0.06, "fire", 20, 80, fwd, 12, 0, 3.0, true, false, 5)
	# бойцы: позы и матрицы — одним вызовом C++ (inf_pose), если он есть; пушки и запасной путь — здесь
	var native: bool = core != null and core.has_method("inf_pose") and not unit_names.is_empty()
	if native and uof.size() != count:
		uof.resize(count)
	for k in count:
		var q := k * VIEW
		var fl := int(view[q + 8])
		if native:
			uof[k] = -1
		if (fl & 1) == 0 or (fl & 2) != 0:  # павшие остаются лежать, живых врагов видно только засвеченных
			var code := int(view[q + 7])
			var ui: int = _code_unit.get(code, -2)
			if ui == -2:
				var nm0 := _unit_name(code)
				ui = unit_names.find(nm0) if units.has(nm0) and int(units[nm0].np) > 1 else -1
				_code_unit[code] = ui
			if native and ui >= 0:
				uof[k] = ui
			else:
				var nm := _unit_name(code)
				if units.has(nm):
					(units[nm].list as Array).append(k)
			if code % 8 == 6 and units.has(_crew_name(code)):
				# расчёт пушки: кто в строю — у орудия, выбывшие лежат рядом
				var left := int(view[q + 5]) if (fl & 1) != 0 else 0
				var gb := Basis(Vector3.UP, PI * 0.5 - view[q + 3])
				for ci in 3:
					var cp: Vector3 = Vector3(view[q], view[q + 1], view[q + 2]) + gb * (CREW_AT[ci] * SCALE)
					var pose := (P_CROUCH if ci != 2 else P_KNEEL) if ci < left else (P_DEAD_B if ci % 2 == 0 else P_DEAD_F)
					(units[_crew_name(code)].extra as Array).append([cp, view[q + 3] + (0.0 if ci < left else 1.3 * ci), pose, clampi((code / 8) % 64, 0, TINT.size() - 1)])
	var pose_buf := PackedFloat32Array()
	if native:
		pose_buf = core.inf_pose(view, prev, frac, dt, uof, unit_names.size(), TINT_F)
	var nb := unit_names.size()
	var at := nb
	for nm in units:
		var u: Dictionary = units[nm]
		var list: Array = u.list
		var mm: MultiMesh = u.mm
		var extra: Array = u.extra
		var ui := unit_names.find(nm)
		var nsol := int(pose_buf[ui]) if native and ui >= 0 and ui < nb and pose_buf.size() > nb else 0
		var total := nsol + list.size() + extra.size()
		if mm.instance_count < total:
			mm.instance_count = total + 8
		if nsol > 0:
			# готовый буфер бойцов из C++, остаток — нули (пушки и самолёты ставятся следом)
			var buf := pose_buf.slice(at, at + nsol * 20)
			buf.resize(mm.instance_count * 20)
			mm.buffer = buf
			at += nsol * 20
		mm.visible_instance_count = total
		var single: bool = int(u.np) <= 1
		var off := nsol
		for j in extra.size():
			var e: Array = extra[j]
			var eb: Basis = e[1] if e[1] is Basis else Basis(Vector3.UP, PI * 0.5 - float(e[1])).scaled(Vector3(SCALE, SCALE, SCALE))
			mm.set_instance_transform(off + list.size() + j, Transform3D(eb, e[0]))
			mm.set_instance_color(off + list.size() + j, TINT[int(e[3])])
			mm.set_instance_custom_data(off + list.size() + j, Color(float(e[2]), float(e[2]), 0.0, 0.0))
		for j in list.size():
			var k: int = list[j]
			var q := k * VIEW
			var x := lerpf(prev[q], view[q], frac)
			var y := lerpf(prev[q + 1], view[q + 1], frac)
			var z := lerpf(prev[q + 2], view[q + 2], frac)
			var yaw := lerp_angle(prev[q + 3], view[q + 3], frac)
			if single:
				# пушка: одна поза, окраска по нации; подбитая — завалена набок
				var code := int(view[q + 7])
				var gb := Basis(Vector3.UP, PI * 0.5 - yaw)
				if (int(view[q + 8]) & 1) == 0:
					gb = gb * Basis(Vector3.FORWARD, 0.22)
				mm.set_instance_transform(off + j, Transform3D(gb.scaled(Vector3(SCALE, SCALE, SCALE)), Vector3(x, y, z)))
				mm.set_instance_color(off + j, GUN_TINT[clampi(code / 512, 0, 2)][clampi((code / 8) % 64, 0, 5)])
				mm.set_instance_custom_data(off + j, Color(0.0, 0.0, 0.0, 0.0))
				continue
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
			mm.set_instance_transform(off + j, Transform3D(basis, Vector3(x, y, z)))
			mm.set_instance_color(off + j, TINT[clampi((int(view[q + 7]) / 8) % 64, 0, TINT.size() - 1)])
			mm.set_instance_custom_data(off + j, Color(float(a), float(b), bl, 0.0))
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
	stat.shots[clampi(kind, 0, 9)] += 1
	var at := Vector3(ev[q + 2], ev[q + 3], ev[q + 4])
	var dir := Vector3(ev[q + 5], ev[q + 6], ev[q + 7])
	var slot := int(ev[q + 8])
	var near: bool = at.distance_squared_to(battle.cam.global_position) < 900.0 * 900.0
	if kind == 6:
		battle.fx.impact(at, true)
		battle.fx.flash(at, Color(1, 0.7, 0.4), 4.0, 60.0)
		battle.sfx.play3d("grenade", at)
		return
	if kind == 9:
		# очередь авиапушки: настоящие снаряды — трассеры как у танков
		battle._slot_visual(slot, at, dir * ev[q + 9], 1e9)
		if snd_n < 3:
			snd_n += 1
			battle.sfx.play3d("mg", at, 5.0, 0.8)
		return
	if kind == 8:
		# снаряд артиллерии или бомба
		battle._slot_visual(slot, at, dir * ev[q + 9], 1e9)
		if snd_n < 3:
			snd_n += 1
			battle.sfx.play3d("whiz", at + dir * 300.0, 6.0, 0.7)
		return
	if kind == 7:
		# ПТ-пушка
		battle._slot_visual(slot, at, dir * ev[q + 9], 1e9)
		battle.fx.muzzle(at, dir, ev[q + 11])
		battle.fx.shot_dust(at - dir * 12.0 - Vector3(0, 6, 0))
		battle.sfx.gun(ev[q + 11], at)
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
		battle.sfx.play3d("mg" if kind == 5 else ("smg" if kind == 1 else ("rifle" if int(ev[q + 10]) % 2 == 0 else "rifle2")), at)


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
			# у кого нет гранатомётов — берут числом: второе ПТ-ружьё и ещё двое стрелков на отделение
			if not w.tube and not w.faust:
				n_at += 1
				rifles += 2
			rows.append_array([float(team), float(ln), x, y, 0.0, float(w.nat), float(rifles), float(smgs),
				float(n_at) if (w.atr and not w.tube) else (1.0 if w.atr and ln == 1 else 0.0),
				float(n_at) if w.tube else 0.0, (1.0 if ln == 1 else 0.0) if w.faust else 0.0,
				float(w.atr_pen), float(w.tube_pen), float(w.faust_pen), float(w.tube_cal), 0.0])
		# ПТ-пушки: у своего рубежа на флангах (и в центре — тяжёлая, если есть)
		var guns: Array = (w.guns as Array).slice(0, 2)  # поровну: по две пушки на сторону
		for gi in guns.size():
			if amount == 1 and gi > 0:
				break
			var g: Dictionary = guns[gi]
			var ln: int = [0, 2, 1][gi % 3]
			var gy := (ws - 300.0 - (ws - 600.0) * 0.2) if team == 0 else (300.0 + (ws - 600.0) * 0.2)
			rows.append_array([float(team), float(ln), float(lanes[ln]) + (-55.0 if gi % 2 == 0 else 55.0), gy, 1.0, float(w.nat),
				0.0, 0.0, 0.0, 0.0, 0.0, float(g.pen), float(g.v) * D.SHELL_SCALE, float(g.model), float(g.cal), 1.0])
	return rows


## Противотанковое оружие пехоты по нации и году: что было в войсках.
static func weapons(nation: String, year: int) -> Dictionary:
	var w := {"nat": 3, "smg": false, "atr": false, "tube": false, "faust": false, "atr_pen": 25.0, "tube_pen": 90.0,
		"faust_pen": 140.0, "tube_cal": 60.0, "guns": []}
	# пушки: model 0 — лёгкая, 1 — средняя, 2 — 88-мм; пробитие на 500 м, начальная скорость м/с
	var light := {"model": 0, "cal": 37.0, "pen": 48.0, "v": 760.0}
	var medium := {"model": 1, "cal": 75.0, "pen": 120.0, "v": 790.0}
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
			# PaK 36 → PaK 38 (в той же лёгкой модели) → PaK 40; с 1941-го в обороне бывает и 88-мм зенитка
			if year <= 1941:
				w.guns = [light, {"model": 0, "cal": 50.0, "pen": 75.0, "v": 820.0}]
			else:
				w.guns = [medium, {"model": 0, "cal": 50.0, "pen": 75.0, "v": 820.0}]
			# 88-мм зенитка встаёт вместо второй пушки в части боёв (чётный год карты)
			if year >= 1941 and year % 2 == 0:
				w.guns[1] = {"model": 2, "cal": 88.0, "pen": 150.0, "v": 820.0}
		"СССР":
			w.nat = 1
			w.smg = true
			w.atr = year >= 1941  # ПТРД / ПТРС
			w.atr_pen = 40.0
			# 45-мм 53-К / М-42, с 1942-го — 76-мм ЗиС-3
			var g45 := {"model": 0, "cal": 45.0, "pen": 50.0 if year < 1943 else 65.0, "v": 760.0}
			w.guns = [g45, g45] if year < 1942 else [{"model": 1, "cal": 76.0, "pen": 82.0, "v": 680.0}, g45]
		"США":
			w.nat = 2
			w.tube = year >= 1942  # базука
			w.tube_pen = 100.0 if year >= 1944 else 80.0
			# 37-мм M3, с 1943-го — 57-мм M1
			w.guns = [light, light] if year < 1943 else [{"model": 0, "cal": 57.0, "pen": 95.0, "v": 850.0}, light]
		"Япония":
			w.nat = 4
			w.atr = true  # Тип 97
			w.atr_pen = 30.0
			w.guns = [{"model": 0, "cal": 37.0, "pen": 35.0, "v": 700.0}, {"model": 0, "cal": 47.0, "pen": 60.0, "v": 830.0}]
		"Италия":
			w.nat = 5
			w.atr = true  # «Золотурн»
			w.atr_pen = 35.0
			w.guns = [{"model": 0, "cal": 47.0, "pen": 43.0, "v": 630.0}, {"model": 0, "cal": 47.0, "pen": 43.0, "v": 630.0}]
		_:
			w.nat = 3
			w.atr = year <= 1942  # «Бойс»
			w.atr_pen = 23.0
			w.tube = year >= 1943  # PIAT
			w.tube_pen = 100.0
			w.tube_cal = 83.0
			# 2-фунтовая, с 1942-го — 6-фунтовая
			w.guns = [light, light] if year < 1942 else [{"model": 0, "cal": 57.0, "pen": 95.0, "v": 850.0}, light]
	return w
