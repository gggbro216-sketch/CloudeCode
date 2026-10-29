extends Node3D
## Танк: характеристики, физическое состояние (импульс, подвеска, наклон по рельефу, сведение),
## повреждения модулей и связь с 3D-моделью. Положение на карте — pos (x, z), высота — ground.

const D = preload("res://scripts/data.gd")
const Models = preload("res://scripts/tank_models.gd")

var T: Dictionary = {}  # исходные характеристики + производные в единицах карты
var type_key := ""
var team := 0
var pos := Vector2.ZERO
var hull := 0.0  # курс корпуса
var tur := 0.0  # курс башни (мировой)
var hp := 0.0
var max_hp := 0.0
var rl := 0.0  # до перезарядки, с
var alive := true
var is_player := false
var callsign := ""
var nation := ""  # чья армия ведёт танк в этом бою
var lit := 0.0  # засвечен выстрелом/попаданием, с
var vis := [true, true]  # виден ли команде 0 / 1
var recoil := 0.0
var dist_travel := 0.0
var mark := 0.0

# физика
var vel := Vector2.ZERO  # скорость центра масс
var sp := 0.0  # проекция скорости на курс
var accel := 0.0
var yaw_rate := 0.0
var throttle := 0.0
var ground := 0.0
var pitch := 0.0
var roll := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var gun_pitch := 0.0
var gun_target := 0.0
var disp := 0.05  # текущий разброс, рад
var tur_rate := 0.0
var travel := [0.0, 0.0]  # путь левой и правой гусеницы

# счётчики боя
var shots_fired := 0
var hits_taken := 0
var pens_taken := 0
var dmg_dealt := 0.0

# повреждения
var track_broken := 0.0  # сколько ещё стоит с перебитой гусеницей, с
var fire := 0.0  # сколько ещё горит, с
var fire_fx: CPUParticles3D

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

# модель
var hull_node: Node3D
var tur_node: Node3D
var gun_node: Node3D
var gun_pos0 := Vector3.ZERO
var tur_pos0 := Vector3.ZERO
var paint: ShaderMaterial
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
var smoke: CPUParticles3D

# башня, сорванная детонацией боеукладки
var popping := false
var pop_h := 0.0
var pop_vh := 0.0
var pop_off := Vector2.ZERO
var pop_v := Vector2.ZERO
var pop_spin := Vector2.ZERO


## year — год сражения (модификация и бортовые экраны), paint — окраска и знаки стороны.
func setup(key: String, tm: int, p: Vector2, nm: String, player: bool, shadows: bool, year := 1944, paint_cfg := {}) -> void:
	type_key = key
	T = D.spec(key, year)
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
	b_strafe = 1.0 if randf() < 0.5 else -1.0
	b_st = randf_range(1.0, 3.0)
	disp = float(T.disp) * 4.0
	var m := Models.build(self, key, shadows, year, paint_cfg)
	hull_node = m.hull
	tur_node = m.tur
	gun_node = m.gun
	gun_pos0 = gun_node.position
	tur_pos0 = tur_node.position
	paint = m.paint
	tracks = m.tracks
	barrel = m.barrel
	hh = m.hh
	tur_h = m.tur_h
	tz = m.tz
	tur_f = m.tur_f
	tur_b = m.tur_b
	th = m.th
	height = m.height
	casemate = bool(T.casemate)
	up_node = m.sup
	up_min = m.sup_min
	up_max = m.sup_max
	paint.set_shader_parameter("tank_h", height)
	sync_node()


func set_dust(c: Color, amount: float) -> void:
	paint.set_shader_parameter("dust_color", c)
	paint.set_shader_parameter("dust_amount", amount)


func center() -> Vector3:
	return Vector3(pos.x, ground + hh * 0.6, pos.y)


func top() -> Vector3:
	return Vector3(pos.x, ground + height - 2.0, pos.y)


func muzzle() -> Vector3:
	return gun_node.global_transform * Vector3(barrel, 0, 0)


func gun_dir() -> Vector3:
	return gun_node.global_transform.basis.x.normalized()


func sync_node() -> void:
	position = Vector3(pos.x, ground, pos.y)
	hull_node.basis = Basis(Vector3.UP, -hull) * Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, roll)
	if popping:
		tur_node.position = tur_pos0 + Vector3(pop_off.x, pop_h, pop_off.y)
	else:
		tur_node.rotation.y = -(tur - hull)
	gun_node.rotation.z = gun_pitch
	gun_node.position = gun_pos0 - Vector3(recoil * 0.35 * D.UPM, 0, 0)
	paint.set_shader_parameter("ground_y", ground)
	paint.set_shader_parameter("travel_l", travel[0])
	paint.set_shader_parameter("travel_r", travel[1])
	var link := 0.24 * D.UPM
	(tracks[0] as StandardMaterial3D).uv1_offset.x = -fmod(travel[0] / link, 1.0)
	(tracks[1] as StandardMaterial3D).uv1_offset.x = -fmod(travel[1] / link, 1.0)


func smoke_on(v: bool) -> void:
	if smoke and smoke.emitting != v:
		smoke.emitting = v


func make_wreck(pop: bool) -> void:
	paint.set_shader_parameter("burnt", 0.92)
	for t in tracks:
		(t as StandardMaterial3D).albedo_color = Color(0.45, 0.4, 0.36)
	gun_pitch = float(T.elev[0])
	smoke_on(false)
	if fire_fx:
		fire_fx.emitting = false
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
