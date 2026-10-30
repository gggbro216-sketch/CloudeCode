extends Node3D
## Танк: характеристики, физическое состояние (импульс, подвеска, наклон по рельефу, сведение),
## модули и экипаж, следы попаданий и связь с 3D-моделью. Положение на карте — pos (x, z), высота — ground.

const D = preload("res://scripts/data.gd")
const Models = preload("res://scripts/tank_models.gd")

## Модули: прочность 0–100. Больше 50 — исправен, 1–50 — повреждён, 0 — уничтожен.
const MODS := ["engine", "gun", "turret", "optics", "ammo", "fuel"]
const CREW := ["commander", "gunner", "loader", "driver"]
const NAMES := {"engine": "ДВИГАТЕЛЬ", "gun": "ОРУДИЕ", "turret": "ПОГОН", "optics": "ПРИБОРЫ",
	"ammo": "БОЕУКЛАДКА", "fuel": "БАКИ", "commander": "КОМАНДИР", "gunner": "НАВОДЧИК",
	"loader": "ЗАРЯЖАЮЩИЙ", "driver": "МЕХВОД"}
## Полевой ремонт уничтоженного модуля до «повреждён», с. Двигатель не чинится: танк встаёт.
const REPAIR := {"gun": 10.0, "turret": 8.0, "optics": 8.0, "ammo": 12.0}
const MARKS := 8  # следов попаданий на каждой части

var T: Dictionary = {}  # исходные характеристики + производные в единицах карты
var type_key := ""
var team := 0
var pos := Vector2.ZERO
var hull := 0.0  # курс корпуса
var tur := 0.0  # курс башни (мировой)
var hp := 0.0
var max_hp := 0.0
var rl := 0.0  # до перезарядки, с
var rl_max := 1.0  # полное время текущей перезарядки, с
var alive := true
var is_player := false
var callsign := ""
var nation := ""  # чья армия ведёт танк в этом бою
var lit := 0.0  # засвечен выстрелом/попаданием, с
var vis := [true, true]  # виден ли команде 0 / 1
var recoil := 0.0
var dist_travel := 0.0

# физика
var vel := Vector2.ZERO  # скорость центра масс
var sp := 0.0  # проекция скорости на курс
var accel := 0.0
var yaw_rate := 0.0
var throttle := 0.0
var ground := 0.0
var pitch := 0.0  # наклон корпуса по рельефу
var roll := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var body_p := 0.0  # раскачка корпуса на подвеске поверх наклона по рельефу
var body_r := 0.0
var body_pv := 0.0
var body_rv := 0.0
var spring_k := 60.0  # жёсткость и демпфирование подвески (тяжёлый танк качается медленнее)
var spring_c := 5.0
var gun_pitch := 0.0
var gun_target := 0.0
var disp := 0.05  # текущий разброс, рад
var tur_rate := 0.0
var travel := [0.0, 0.0]  # путь левой и правой гусеницы
var travel_prev := [0.0, 0.0]  # он же на прошлом шаге логики (для сглаживания на экране)
var press := 1.0  # удельное давление на грунт относительно среднего (узкие гусеницы вязнут сильнее)
var slip := 0.0  # пробуксовка гусениц, 0–1
var soft := 0.0  # мягкость грунта под танком, 0–1

# следы гусениц
var track_w := 4.0  # ширина гусеницы и расстояние от оси, ед.
var track_z := 9.0
var last_mark := [Vector2(-1e6, 0), Vector2(-1e6, 0)]  # где кончился след левой и правой
var mark_v := [0.0, 0.0]  # пройдено вдоль следа (рисунок траков идёт непрерывно)
var dust_fx: GPUParticles3D
var mud_fx: GPUParticles3D

# счётчики боя
var shots_fired := 0
var hits_taken := 0
var pens_taken := 0
var dmg_dealt := 0.0

# повреждения
var track_broken := 0.0  # сколько ещё стоит с перебитой гусеницей, с
var fire := 0.0  # сколько ещё горит, с
var fire_fx: GPUParticles3D
var engine_fx: GPUParticles3D  # дым разбитого моторного отделения
var mod_hp := {}
var mod_fix := {}  # уничтоженный модуль → секунд до полевого ремонта
var crew_ok := {}
var layout: Array = []  # места модулей и экипажа: {name, part ("hull" | "top"), c, h (полуразмеры) | r}
var speed_k := 1.0  # множители характеристик от повреждений и потерь экипажа
var accel_k := 1.0
var turn_k := 1.0
var tspd_k := 1.0
var reload_k := 1.0  # множитель времени перезарядки
var aim_k := 1.0  # множитель времени сведения
var disp_k := 1.0
var spot_k := 1.0
var immobile := false  # двигатель уничтожен: танк стоит до конца боя (если нет ремкомплекта)
var cmd := false  # C++-физика: на этом шаге задана команда хода (газ, поворот)
var cmd_thr := 0.0
var cmd_steer := 0.0
var aim_cmd := false  # и навести башню на aim_target
var aim_target := Vector3.ZERO
var disp_cmd := false  # и пересчитать разброс
var idx := -1  # номер в Battle.tanks (для C++)
var b_cons_acc := 0.0  # бот: накопленное время до проверки снаряжения
var gy_set := -1e9  # ground_y, последний отданный шейдеру

# снаряжение: что взято в бой → секунд до готовности; что пускали в ход
var cons := {}
var cons_used := {}

# состояние бота
var role := "atk"
var b_av := 0.0
var b_av_dir := 1.0
var b_strafe := 1.0
var b_st := 1.0
var b_goal := Vector2.ZERO
var b_gt := 0.0
var b_zone = null
var b_last := Vector2.ZERO
var b_pt := 1.0
var b_los := false
var b_los_t := 0.0
var b_cons_t := {}  # снаряжение → через сколько секунд бот его применит
var b_tg = null  # цель бота (танк)
var b_tg_t := 0.0
var b_side := 1.0  # фланг (и в какую сторону ставить ромб): -1 левый, 1 правый
var b_lane := "mid"  # направление атаки группы: hill, mid, town
var b_cls := "СТ"  # ЛТ, СТ, ТТ, ПТ
var b_off := Vector2.ZERO  # место в строю на рубеже, чтобы группа не стояла в одной точке
var b_path := PackedVector2Array()  # маршрут A*
var b_pi := 0
var b_path_to := Vector2(-1e6, -1e6)
var b_path_safe := false
var b_path_t := 0.0
var b_path_wait := false  # маршрут ищется в фоновом потоке
var b_think := 0.0  # решения бот принимает 5 раз в секунду, а рулит и целится каждый кадр
var b_spot = null  # Vector2: укрытие, позиция «корпус за гребнем» или куст засады
var b_spot_kind := ""  # cover, hull, bush
var b_spot_t := 0.0
var b_peek = null  # Vector2: откуда последний раз видел цель — туда выезжать после перезарядки
var b_back_t := 0.0  # разведчик после засвета отходит до этого времени боя
var b_wait := 0.0  # под огнём на открытом месте: сколько ещё переждать в укрытии
var hit_t := -100.0  # когда в танк последний раз попали
var b_act := ""  # что бот делает: route — едет по маршруту, spot — к укрытию, fight — бой, hold — стоит
var b_adv := true  # можно ли сближаться с целью (под огнём на открытом месте — нет)
var b_hold := false  # засада: не стрелять, чтобы не выдать себя

# модель
var hull_node: Node3D
var tur_node: Node3D
var gun_node: Node3D
var gun_pos0 := Vector3.ZERO
var tur_pos0 := Vector3.ZERO
var paint: ShaderMaterial  # материал корпуса
var paints: Array = []  # материалы корпуса, башни и орудия (у каждой части свои следы попаданий)
var mark_mats := {}  # часть → материал
var mark_nodes := {}  # часть → узел, в чьих координатах лежат вершины её сетки
var marks := {}  # часть → [места и радиусы, вид и направление] (PackedVector4Array)
var mark_i := {}
var tracks: Array = []
var barrel := 30.0
var hh := 12.0
var tur_h := 7.0
var tz := 8.0
var tur_f := 8.0
var tur_b := 9.0
var th := 7.0
var height := 20.0
var casemate := false  # САУ: орудие в неподвижной рубке, наводка только в секторе
var up_node: Node3D  # башня или рубка — верхняя коробка попаданий
var up_min := Vector3.ZERO
var up_max := Vector3.ZERO
var smoke: GPUParticles3D

# башня, сорванная детонацией боеукладки
var popping := false
var pop_h := 0.0
var pop_vh := 0.0
var pop_off := Vector2.ZERO
var pop_v := Vector2.ZERO
var pop_spin := Vector2.ZERO


## year — год сражения (модификация и бортовые экраны), paint — окраска и знаки стороны.
## top — какие модули стоят исследованные ({слот: true/false}, без слота — исследованный).
func setup(key: String, tm: int, p: Vector2, nm: String, player: bool, shadows: bool, year := 1944, paint_cfg := {},
		top := {}) -> void:
	type_key = key
	T = D.spec(key, year, top)
	T.merge(D.derived(T), true)
	team = tm
	pos = p
	b_last = p
	callsign = nm
	is_player = player
	hull = -PI / 2 if team == 0 else PI / 2
	tur = hull
	hp = T.hp
	max_hp = T.hp
	rl = randf_range(0.5, T.reload)
	rl_max = T.reload
	b_strafe = 1.0 if randf() < 0.5 else -1.0
	b_st = randf_range(1.0, 3.0)
	disp = float(T.disp) * 4.0
	var m := Models.build(self, key, shadows, year, paint_cfg)
	hull_node = m.hull
	tur_node = m.tur
	gun_node = m.gun
	gun_pos0 = gun_node.position
	tur_pos0 = tur_node.position
	paints = m.paints
	paint = paints[0]
	tracks = m.tracks
	barrel = m.barrel
	hh = m.hh
	tur_h = m.tur_h
	tz = m.tz
	tur_f = m.tur_f
	tur_b = m.tur_b
	th = m.th
	height = m.height
	track_w = m.track_w
	track_z = m.track_z
	casemate = bool(T.casemate)
	up_node = m.sup
	up_min = m.sup_min
	up_max = m.sup_max
	set_param("tank_h", height)
	for part in m.parts:
		var nm2: String = part.part
		mark_mats[nm2] = part.mat
		mark_nodes[nm2] = part.node
		var pa := PackedVector4Array()
		pa.resize(MARKS)
		var ka := PackedVector4Array()
		ka.resize(MARKS)
		marks[nm2] = [pa, ka]
		mark_i[nm2] = 0
		if part.shape != null:
			_collider(nm2, part.shape, part.node_col)
	# удельное давление гусениц на грунт: масса на площадь опоры, к среднему ~7,2 т/м²
	var S: Dictionary = Models.SPECS[key]
	press = clampf(float(T.mass) / (2.0 * float(S.tw) * 0.8 * float(S.L)) / 7.2, 0.8, 1.25)
	# подвеска: тяжёлая машина раскачивается медленнее и меньше
	spring_k = 58.0 * pow(30.0 / float(T.mass), 0.4)
	spring_c = 2.0 * 0.32 * sqrt(spring_k)
	_init_damage()
	sync_node()


## Коллизия по сетке модели — только для лучей, уточняющих место попадания (слой 8).
func _collider(part: String, shape: Shape3D, node: Node3D) -> void:
	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("tank", self)
	area.set_meta("part", part)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	area.add_child(cs)
	node.add_child(area)


func set_param(name: String, v) -> void:
	for m: ShaderMaterial in paints:
		m.set_shader_parameter(name, v)


func set_dust(c: Color, amount: float) -> void:
	set_param("dust_color", c)
	set_param("dust_amount", amount)


func center() -> Vector3:
	return Vector3(pos.x, ground + hh * 0.6, pos.y)


func top() -> Vector3:
	return Vector3(pos.x, ground + height - 2.0, pos.y)


func muzzle() -> Vector3:
	return gun_node.global_transform * Vector3(barrel, 0, 0)


func gun_dir() -> Vector3:
	return gun_node.global_transform.basis.x.normalized()


## Катки и траки между шагами логики: пройденный путь сглажен, чтобы они не крутились рывками.
func sync_travel(f: float) -> void:
	var l := lerpf(travel_prev[0], travel[0], f)
	var r := lerpf(travel_prev[1], travel[1], f)
	paint.set_shader_parameter("travel_l", l)
	paint.set_shader_parameter("travel_r", r)
	_track_offsets(l, r)


func sync_node() -> void:
	position = Vector3(pos.x, ground, pos.y)
	hull_node.basis = Basis(Vector3.UP, -hull) * Basis(Vector3.BACK, pitch + body_p) * Basis(Vector3.RIGHT, roll + body_r)
	if popping:
		tur_node.position = tur_pos0 + Vector3(pop_off.x, pop_h, pop_off.y)
	else:
		tur_node.rotation.y = -(tur - hull)
	gun_node.rotation.z = gun_pitch
	gun_node.position = gun_pos0 - Vector3(recoil * 0.35 * D.UPM, 0, 0)
	# высота грунта для пыли на корпусе — когда заметно сменилась
	if absf(ground - gy_set) > 0.25:
		gy_set = ground
		set_param("ground_y", ground)
	# ход гусениц у живого видимого танка каждый кадр ставит sync_travel (плавно), у невидимого не нужен
	if not alive:
		paint.set_shader_parameter("travel_l", travel[0])
		paint.set_shader_parameter("travel_r", travel[1])
		_track_offsets(travel[0], travel[1])


func _track_offsets(l: float, r: float) -> void:
	var link := 0.24 * D.UPM
	var m := tracks[0] as ShaderMaterial
	m.set_shader_parameter("off_l", -fmod(l / link, 1.0))
	m.set_shader_parameter("off_r", -fmod(r / link, 1.0))


func smoke_on(v: bool) -> void:
	if smoke and smoke.emitting != v:
		smoke.emitting = v


func make_wreck(pop: bool) -> void:
	set_param("burnt", 0.92)
	(tracks[0] as ShaderMaterial).set_shader_parameter("tint", Color(0.45, 0.4, 0.36))
	gun_pitch = float(T.elev[0])
	smoke_on(false)
	if fire_fx:
		fire_fx.emitting = false
	if engine_fx:
		engine_fx.emitting = false
	if dust_fx:
		dust_fx.emitting = false
	if mud_fx:
		mud_fx.emitting = false
	if pop and not casemate:
		popping = true
		pop_vh = randf_range(110.0, 160.0)
		pop_v = Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		pop_spin = Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))


func update_pop(dt: float) -> void:
	if not popping:
		return
	if pop_h > -hh * 0.6 or pop_vh > 0:
		pop_vh -= D.GRAVITY * 2.0 * dt
		pop_h += pop_vh * dt
		pop_off += pop_v * dt
		tur_node.rotation.x += pop_spin.x * dt
		tur_node.rotation.z += pop_spin.y * dt


## Толчок корпусу на подвеске: dp — по тангажу (+ — нос вверх), dr — по крену.
func kick(dp: float, dr: float) -> void:
	body_pv += dp
	body_rv += dr


## След попадания на поверхности части: kind 0 — рикошет, 1 — непробитие, 2 — пробитие.
## Места хранятся в координатах сетки части, поэтому след едет вместе с башней.
func add_mark(part: String, world_pos: Vector3, world_dir: Vector3, radius: float, kind: int) -> void:
	if not mark_nodes.has(part):
		return
	var node: Node3D = mark_nodes[part]
	var inv := node.global_transform.affine_inverse()
	var lp := inv * world_pos
	var ld := (inv.basis * world_dir).normalized()
	var lr := (inv.basis * Vector3(radius, 0, 0)).length()
	var i: int = mark_i[part]
	var pa: PackedVector4Array = marks[part][0]
	var ka: PackedVector4Array = marks[part][1]
	pa[i] = Vector4(lp.x, lp.y, lp.z, lr)
	ka[i] = Vector4(kind, ld.x, ld.y, ld.z)
	marks[part] = [pa, ka]
	mark_i[part] = (i + 1) % MARKS
	var mat: ShaderMaterial = mark_mats[part]
	mat.set_shader_parameter("marks", pa)
	mat.set_shader_parameter("mark_k", ka)


# ---------- Модули и экипаж ----------

## Модули по местам: двигатель и баки сзади, боеукладка на полу, мехвод спереди слева,
## в башне — орудие, погон, приборы, наводчик, командир и заряжающий. Всё в единицах карты.
func _init_damage() -> void:
	for m in MODS:
		mod_hp[m] = 100.0
	for c in CREW:
		crew_ok[c] = true
	var U := D.UPM
	var L: float = float(T.len) * U
	var W: float = float(T.wid) * U
	layout = [
		{"name": "engine", "part": "hull", "c": Vector3(-0.31 * L, 0.5 * hh, 0), "h": Vector3(0.16 * L, 0.3 * hh, 0.3 * W)},
		{"name": "fuel", "part": "hull", "c": Vector3(-0.1 * L, 0.55 * hh, 0.36 * W), "h": Vector3(0.15 * L, 0.2 * hh, 0.09 * W)},
		{"name": "fuel", "part": "hull", "c": Vector3(-0.1 * L, 0.55 * hh, -0.36 * W), "h": Vector3(0.15 * L, 0.2 * hh, 0.09 * W)},
		{"name": "ammo", "part": "hull", "c": Vector3(0.02 * L, 0.32 * hh, 0), "h": Vector3(0.14 * L, 0.15 * hh, 0.26 * W)},
		{"name": "driver", "part": "hull", "c": Vector3(0.5 * L - 1.15 * U, 0.62 * hh, -0.42 * U), "r": 0.42 * U},
	]
	var f := up_max.x
	var b := -up_min.x
	var hw := up_max.z
	var h := up_max.y
	var gp: Vector3 = gun_pos0 if not casemate else tur_node.position - up_node.position
	layout.append({"name": "gun", "part": "top", "c": gp - Vector3(0.6 * U, 0, 0), "h": Vector3(0.55, 0.25, 0.25) * U})
	if not casemate:
		layout.append({"name": "turret", "part": "top", "c": Vector3(0, 0.08 * h, 0), "h": Vector3(0.45 * minf(f, b), 0.09 * h, 0.5 * hw)})
	layout.append({"name": "optics", "part": "top", "c": Vector3(-0.3 * b, 0.9 * h, -0.3 * hw), "h": Vector3(0.22, 0.14, 0.22) * U})
	layout.append({"name": "gunner", "part": "top", "c": Vector3(0.25 * f, 0.45 * h, -0.4 * hw), "r": 0.4 * U})
	layout.append({"name": "commander", "part": "top", "c": Vector3(-0.45 * b, 0.55 * h, -0.35 * hw), "r": 0.4 * U})
	layout.append({"name": "loader", "part": "top", "c": Vector3(0.0, 0.45 * h, 0.45 * hw), "r": 0.4 * U})
	recalc()


func mod_state(name: String) -> int:
	var v: float = mod_hp[name]
	return 2 if v > 50.0 else (1 if v > 0.0 else 0)


## Урон модулю; возвращает [состояние до, после].
func hit_module(name: String, amount: float) -> Array:
	var was := mod_state(name)
	mod_hp[name] = maxf(0.0, float(mod_hp[name]) - amount)
	var now := mod_state(name)
	if now == 0 and was > 0 and REPAIR.has(name):
		mod_fix[name] = REPAIR[name]
	if now != was:
		recalc()
	return [was, now]


## Член экипажа выбывает; false — уже выбыл.
func wound(role_name: String) -> bool:
	if not crew_ok[role_name]:
		return false
	crew_ok[role_name] = false
	recalc()
	return true


func crew_left() -> int:
	var n := 0
	for c in CREW:
		if crew_ok[c]:
			n += 1
	return n


## Полевой ремонт: уничтоженный модуль через время работает снова, но как повреждённый.
## Возвращает отремонтированные модули.
func update_repairs(dt: float) -> Array:
	var done: Array = []
	for name in mod_fix.keys():
		mod_fix[name] -= dt
		if mod_fix[name] <= 0.0:
			mod_fix.erase(name)
			mod_hp[name] = 30.0
			done.append(name)
	if not done.is_empty():
		recalc()
	return done


## Характеристики от состояния модулей и экипажа.
func recalc() -> void:
	var e := mod_state("engine")
	immobile = e == 0
	speed_k = [0.0, 0.55, 1.0][e]
	accel_k = [0.0, 0.5, 1.0][e]
	turn_k = [0.0, 0.7, 1.0][e]
	var g := mod_state("gun")
	disp_k = [1.0, 1.5, 1.0][g]
	aim_k = [1.0, 1.35, 1.0][g]
	tspd_k = 1.0 if casemate else [0.0, 0.5, 1.0][mod_state("turret")]
	spot_k = [0.5, 0.75, 1.0][mod_state("optics")]
	reload_k = [1.6, 1.25, 1.0][mod_state("ammo")]
	if not crew_ok.commander:
		spot_k *= 0.8
		reload_k *= 1.08
		aim_k *= 1.08
	if not crew_ok.gunner:
		aim_k *= 1.6
		disp_k *= 1.25
		tspd_k *= 0.75
	if not crew_ok.loader:
		reload_k *= 1.5
	if not crew_ok.driver:
		speed_k *= 0.85
		accel_k *= 0.6
		turn_k *= 0.7


## Снаряжение. Ремкомплект: гусеница сразу, уничтоженные модули — до «повреждён» (двигатель тоже),
## повреждённые — полностью; аптечка: экипаж снова в строю; огнетушитель: пожар потушен.
## false — нечего применять, снаряжения нет или оно ещё не готово.
func use_cons(name: String) -> bool:
	if not cons.has(name) or float(cons[name]) > 0.0 or not alive:
		return false
	match name:
		"repair":
			var any := track_broken > 0.0
			for m in MODS:
				if float(mod_hp[m]) < 100.0:
					any = true
					mod_hp[m] = 30.0 if float(mod_hp[m]) <= 0.0 else 100.0
			if not any:
				return false
			track_broken = 0.0
			mod_fix.clear()
			if engine_fx:
				engine_fx.emitting = false
		"medkit":
			if crew_left() == CREW.size():
				return false
			for c in CREW:
				crew_ok[c] = true
		"ext":
			if fire <= 0.0:
				return false
			fire = 0.0
			if fire_fx:
				fire_fx.emitting = false
	cons[name] = D.CONSUMABLES[name].cd
	cons_used[name] = true
	recalc()
	return true


## Нужен ли сейчас предмет снаряжения (для подсветки кнопки и для ботов).
func cons_needed(name: String) -> bool:
	match name:
		"repair":
			if track_broken > 0.0:
				return true
			for m in MODS:
				if mod_state(m) < 2:
					return true
		"medkit":
			return crew_left() < CREW.size()
		"ext":
			return fire > 0.0
	return false


## Уничтоженное орудие не стреляет до ремонта.
func can_fire() -> bool:
	return mod_state("gun") > 0


func reload_time() -> float:
	return float(T.reload) * reload_k * (1.0 if is_player else 1.15)
