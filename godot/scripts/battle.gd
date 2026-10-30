extends Node3D
## Бой: рельеф и карта, физика танков, баллистика, броня и модули, засвет, ИИ, камера и звук.
##
## Физика танка: импульс центра масс (скорость не обязана совпадать с курсом — в поворотах и на
## боковом склоне корпус чуть сносит), тяга по удельной мощности, сопротивление грунта, сила
## тяжести вдоль склона, инерция поворота, удары о препятствия и тараны с обменом импульсом.
## Снаряды летят по баллистической траектории; броня считается с учётом угла встречи,
## нормализации и перекрытия калибром; гусеницы, двигатель и боеукладка повреждаются.

signal ended(stats: Dictionary)
signal leave(again: bool)

const D = preload("res://scripts/data.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Native = preload("res://scripts/native.gd")
const TankScript = preload("res://scripts/tank.gd")
const HudScript = preload("res://scripts/hud.gd")
const FxScript = preload("res://scripts/fx.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const WeatherScript = preload("res://scripts/weather.gd")

const TRK := 4000  # отрезков следов гусениц одновременно
const SCORCH := 160  # пятен от разрывов
const SENS_X := 0.0045  # поворот камеры, рад на точку свайпа
const SENS_Y := 0.003
const MASK_WORLD := 3  # рельеф + постройки
const TRACK_REPAIR := 7.0  # сколько стоит танк с перебитой гусеницей, с
const FIRE_TIME := 6.0  # сколько горит двигатель, с
const MOD_MSG := {
	"engine": ["ДВИГАТЕЛЬ ПОВРЕЖДЁН", "ДВИГАТЕЛЬ УНИЧТОЖЕН — ТАНК ОБЕЗДВИЖЕН"],
	"gun": ["ОРУДИЕ ПОВРЕЖДЕНО", "ОРУДИЕ ВЫВЕДЕНО ИЗ СТРОЯ"],
	"turret": ["ПОГОН БАШНИ ПОВРЕЖДЁН", "БАШНЮ ЗАКЛИНИЛО"],
	"optics": ["ПРИБОРЫ НАБЛЮДЕНИЯ ПОВРЕЖДЕНЫ", "ПРИБОРЫ НАБЛЮДЕНИЯ РАЗБИТЫ"],
	"ammo": ["БОЕУКЛАДКА ПОВРЕЖДЕНА", "БОЕУКЛАДКА РАЗБИТА"],
	"fuel": ["ТОПЛИВНЫЕ БАКИ ПРОБИТЫ", "ТОПЛИВНЫЕ БАКИ РАЗБИТЫ"],
}
const CREW_MSG := {"commander": "КОМАНДИР РАНЕН", "gunner": "НАВОДЧИК РАНЕН", "loader": "ЗАРЯЖАЮЩИЙ РАНЕН",
	"driver": "МЕХВОД РАНЕН"}
const FIXED_MSG := {"gun": "ОРУДИЕ ВОССТАНОВЛЕНО", "turret": "ПОГОН БАШНИ ВОССТАНОВЛЕН",
	"optics": "ПРИБОРЫ ВОССТАНОВЛЕНЫ", "ammo": "БОЕУКЛАДКА ВОССТАНОВЛЕНА"}
# Следы гусениц: рисунок траков, глубже на мягком грунте; умножают цвет земли и медленно тают.
const TRACK_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tread : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.45, 0.37);
uniform float now = 0.0;
uniform float life = 75.0;
uniform float period = 1.6;
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;  // x — когда оставлен, y — глубина, z — путь вдоль следа, w — длина отрезка
}

void fragment() {
	float fade = 1.0 - smoothstep(life * 0.45, life, now - cd.x);
	float t = texture(tread, vec2(UV.y, (cd.z + UV.x * cd.w) / period)).r;
	float edge = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.88, UV.y) * smoothstep(0.0, 0.05, UV.x) * smoothstep(1.0, 0.95, UV.x);
	ALBEDO = mix(vec3(1.0), tint, t * edge * fade * cd.y);
}
"""

var mode := "standard"
var map_key := "prokhorovka"
var hq := true
var player_type := "t34_76"
var player_mods := {}  # модули танка игрока: {слот: true — исследованный}
var player_cons: Array = ["repair", "medkit", "ext"]  # снаряжение, взятое в бой
var history := true  # только машины, воевавшие на этой карте
var side := "allies"  # сторона игрока; команда 0 — его сторона, команда 1 — противник
var year := 1943
var teams: Array = [[], []]  # типы машин команд
var briefing := true  # бой стоит, пока игрок читает брифинг
var lang := "ru"  # язык переговоров своей стороны
var radio_last := -100.0
var radio_cd := {}
var radio_start := -1.0  # когда прозвучит команда «вперёд»
var reported := {}  # о каких врагах уже доложили
var said := {}

var terra: Terrain
var core: Object = null  # C++ этого боя (рельеф, препятствия, пути, видимость); null — всё на GDScript
var obst: Array = []
var bushes: Array = []
var props: Array = []
var lanes: Dictionary = {}  # x направлений атаки: hill — фланг с высотой, town — с застройкой, mid — центр
var falling: Array = []
var zones: Array = []
var tanks: Array = []
var shells: Array = []
var texts: Array = []
var bush_mat: ShaderMaterial
var surf := "grass"
var soft_base := 0.3  # мягкость грунта карты: 0 — плац, 1 — болото
var mu_base := 0.78  # сцепление гусениц с грунтом (доля веса)
var road_mu := 0.9
var trk_mat: ShaderMaterial
var weather: WeatherScript

var player: TankScript
var watch: TankScript
var cam: Camera3D
var cam_yaw := -PI / 2
var cam_pitch := 0.07
var sniper := false
var aim_point := Vector3.ZERO
var gun_point = null  # Vector3 или null — куда реально упадёт снаряд
var pen_hint := -1  # -1 нет цели, 0 не пробьёт, 1 возможно, 2 пробьёт
var gun_limited := false  # орудие упёрлось в предел склонения или возвышения
var shake := 0.0
var clock := 0.0
var spot_t := 0.0
var paused := false
var over := false
var over_t := 0.0
var result_shown := false
var speed := 1
var autopilot := false  # танком игрока управляет бот (для проверок)
var result := ""
var reason := ""
var score := [0.0, 0.0]
var kills := 0
var dmg_done := 0.0
var hits := 0
var shots := 0
var stat := {"pen": 0, "nopen": 0, "rico": 0, "miss": 0, "ram": 0, "track": 0, "fire": 0, "ammo": 0}
# заслуги игрока для опыта и серебра
var spot_dmg := 0.0  # урон союзников по врагам, которых засветил игрок
var spotted_n := 0  # сколько врагов засветил первым
var blocked := 0.0  # урон, принятый бронёй без пробития
var cap_pts := 0.0  # очки захвата
var def_pts := 0.0  # сбитый захват своей базы
var spotter := {}  # враг → танк, засветивший его первым

var hud: HudScript
var fx: FxScript
var sfx: SfxScript
var trk_mm: MultiMesh
var trk_i := 0
var scorch_mm: MultiMesh
var scorch_i := 0
# Трассеры снарядов рисует шейдер по формуле полёта: в данных экземпляра — точка и время вылета,
# скорость и время конца; процессор только проверяет попадания.
const SHELL_SLOTS := 64
const SHELL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform float now = 0.0;
uniform float grav = 73.6;

void vertex() {
	// MODEL_MATRIX: [3] — точка вылета, [0] — скорость, [1].x — время вылета, [1].y — время конца
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	float tau = now - MODEL_MATRIX[1].x;
	vec3 vel = v0 - vec3(0.0, grav * tau, 0.0);
	vec3 p = p0 + v0 * tau - vec3(0.0, 0.5 * grav * tau * tau, 0.0);
	vec3 f = normalize(vel);
	vec3 side = normalize(cross(f, abs(f.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, f);
	vec3 wp = p + side * VERTEX.x + up * VERTEX.y + f * VERTEX.z;
	if (tau < 0.0 || now > MODEL_MATRIX[1].y) {
		wp = vec3(0.0, -10000.0, 0.0);
	}
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(1.0, 0.78, 0.4);
}
"""
var shell_mm: MultiMesh
var shell_mat: ShaderMaterial
var shell_slot := 0
var loops := {}  # танк -> [двигатель, гусеницы, башня]
var reload_cue := false


## Замеры: раздел → [микросекунд всего, вызовов]. Дёшево, поэтому включены всегда.
var prof := {}


func _prof(k: String, t0: int) -> void:
	var e = prof.get(k)
	if e == null:
		prof[k] = [Time.get_ticks_usec() - t0, 1]
	else:
		e[0] += Time.get_ticks_usec() - t0
		e[1] += 1


func setup(cfg: Dictionary) -> void:
	mode = cfg.mode
	map_key = cfg.map
	hq = cfg.hq
	player_type = cfg.tank
	player_mods = cfg.get("mods", {})
	player_cons = cfg.get("cons", player_cons)
	history = cfg.get("history", true)
	side = D.TYPES[player_type].side


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var M0: Dictionary = D.MAPS[map_key]
	surf = M0.surf
	soft_base = clampf(2.0 * (1.0 - float(M0.grip)), 0.0, 0.8)
	mu_base = {"grass": 0.78, "sand": 0.62, "snow": 0.5, "urban": 0.85}.get(surf, 0.75)
	road_mu = 0.5 if surf == "snow" else 0.9
	year = D.MAPS[map_key].year
	zones = MapGen.make_zones(mode)
	var t0 := Time.get_ticks_usec()
	var data := MapGen.generate(map_key, zones, rng)
	_prof("load: расстановка", t0)
	obst = data.obst
	bushes = data.bushes
	props = data.props
	terra = Terrain.new()
	core = Native.make()
	terra.core = core
	var ao_pts: Array = []
	for b in bushes:
		ao_pts.append(Vector3(b.pos.x, b.pos.y, float(b.r) * 1.1))
	for pr in props:
		ao_pts.append(Vector3(pr.pos.x, pr.pos.y, 9.0 if pr.kind == "fence" else 14.0))
	t0 = Time.get_ticks_usec()
	terra.generate(map_key, zones, obst, data.craters, data.roads, ao_pts, data.hills)
	_prof("load: рельеф", t0)
	lanes = data.lanes
	t0 = Time.get_ticks_usec()
	_build_hash()
	_build_nav()
	_prof("load: сетка путей", t0)
	_start_nav_thread()
	t0 = Time.get_ticks_usec()
	terra.build(self, map_key, hq)
	_prof("load: сетка рельефа", t0)
	MapGen.TexLib.bump = hq
	t0 = Time.get_ticks_usec()
	var built := MapGen.build(self, data, map_key, zones, terra, hq)
	_prof("load: 3D карты", t0)
	if core:
		core.boxes_set(MapGen.phys_boxes)
	bush_mat = built.bush_mat
	_make_env()
	fx = FxScript.new()
	fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # вспышки и дым ставятся на месте
	add_child(fx)
	fx.set_dust(Color(D.MAPS[map_key].dust))
	for s in built.smokes:
		fx.smoke_column(s, false)
	# дальние пожары; над Берлином весной 1945-го дымов больше
	for i in (8 if map_key == "berlin" else 3):
		var a := randf() * TAU
		var p := Vector2(D.WS / 2, D.WS / 2) + Vector2.from_angle(a) * D.WS * randf_range(0.6, 0.7)
		fx.smoke_column(Vector3(p.x, terra.height(p.x, p.y), p.y), true)
	sfx = SfxScript.new()
	add_child(sfx)
	trk_mm = _track_mm()
	scorch_mm = _decal_mm(SCORCH, Vector2(1, 1), Color(0.05, 0.045, 0.04, 0.75), true)
	_make_shell_mm()
	t0 = Time.get_ticks_usec()
	_spawn()
	_prof("load: танки", t0)
	cam = Camera3D.new()
	# камеру двигаем каждый кадр сами, по сглаженному положению танка
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.5
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	weather = WeatherScript.new()
	weather.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # идёт за камерой
	add_child(weather)
	weather.setup(str(D.MAPS[map_key].get("weather", "")), self, hq)
	var layer := CanvasLayer.new()
	layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	layer.add_child(hud)
	var M: Dictionary = D.MAPS[map_key]
	hud.add_feed([["%s · %s" % [D.MODES[mode].name, M.name], Color(D.AMBER)]])
	hud.add_feed([["%s: %s против %s" % [M.date, M[side], M[D.foe_side(side) + "_g"]], Color("cfd3c0")]])
	hud.show_brief(_brief_info())
	for tk: TankScript in tanks:
		_suspend(tk, 1.0)
		tk.sync_node()
	_update_spotting()
	_sync(0.0)


const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 ground_color : source_color;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float cover = 0.5;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, -0.25, h));
	}
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR * (pow(sd, 900.0) * 6.0 + pow(sd, 12.0) * 0.18) * (1.0 - cover * 0.7);
	if (h > 0.005) {
		vec2 uv = d.xz / (h + 0.06) * 0.22 + vec2(TIME * 0.003, TIME * 0.001);
		float c = texture(clouds, uv).r * 0.7 + texture(clouds, uv * 2.7 + 0.3).r * 0.3;
		float k = smoothstep(1.0 - cover - 0.05, 1.0 - cover + 0.35, c) * smoothstep(0.0, 0.18, h);
		// освещённая верхушка и тёмное брюхо облака
		vec3 lit = mix(vec3(0.95, 0.95, 0.93), horizon_color, 0.25) + LIGHT0_COLOR * pow(sd, 6.0) * 0.3;
		vec3 dark = mix(vec3(0.55, 0.57, 0.6), horizon_color * 0.8, 0.3);
		vec3 cc = mix(lit, dark, smoothstep(0.55, 1.0, c) * cover);
		col = mix(col, cc, k * 0.92);
	}
	COLOR = col;
}
"""


func _make_env() -> void:
	var M: Dictionary = D.MAPS[map_key]
	var sky_sh := Shader.new()
	sky_sh.code = SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_sh
	sky_mat.set_shader_parameter("top_color", Color(M.sky_top))
	sky_mat.set_shader_parameter("horizon_color", Color(M.sky_hor))
	sky_mat.set_shader_parameter("ground_color", Color(M.g1).darkened(0.3))
	var cn := FastNoiseLite.new()
	cn.seed = randi()
	cn.frequency = 0.012
	cn.fractal_octaves = 5
	var cimg := cn.get_seamless_image(512, 512)
	cimg.generate_mipmaps()
	sky_mat.set_shader_parameter("clouds", ImageTexture.create_from_image(cimg))
	sky_mat.set_shader_parameter("cover", M.cover)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(M.sky_hor).lerp(Color.WHITE, 0.25)
	env.ambient_light_energy = M.amb
	# плёночная тональная кривая и приглушённые цвета вместо «открыточной» яркости
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.84
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(M.fog)
	env.fog_depth_begin = M.fog_near
	env.fog_depth_end = M.fog_far
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(M.sun_rot[0], M.sun_rot[1], 0)
	sun.light_color = Color(M.sun)
	sun.light_energy = M.sun_e
	sun.shadow_enabled = hq
	# один каскад теней на 300 единиц (≈40 м): дальше тени не видны, а их отрисовка дорогая
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_blur = 1.2
	add_child(sun)


## Плоские отметки на земле (следы, гарь) в одной MultiMesh.
func _decal_mm(count: int, size: Vector2, col: Color, soft: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = size
	mm.mesh = q
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
	var m := MapGen.mat(col, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if soft:
		m.albedo_texture = fx.soft
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## Следы гусениц: отрезки-полосы с рисунком траков в одной MultiMesh.
func _track_mm() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := PlaneMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = TRK
	for i in TRK:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		mm.set_instance_custom_data(i, Color(-1000, 0, 0, 1))
	# рисунок траков: грунтозацепы поперёк, канавка под гребни посередине
	var img := Image.create(32, 32, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in 32:
		for x in 32:
			var v := 0.5
			if y % 32 < 11:
				v = 1.0
			if x >= 14 and x <= 17:
				v = 0.35
			if x < 2 or x > 29:
				v *= 0.7
			img.set_pixel(x, y, Color(clampf(v + rng.randf_range(-0.08, 0.08), 0.0, 1.0), 0, 0))
	img.generate_mipmaps()
	var sh := Shader.new()
	sh.code = TRACK_SHADER
	trk_mat = ShaderMaterial.new()
	trk_mat.shader = sh
	trk_mat.set_shader_parameter("tread", ImageTexture.create_from_image(img))
	var tints := {"grass": Color(0.4, 0.36, 0.28), "sand": Color(0.7, 0.62, 0.5), "snow": Color(0.62, 0.68, 0.78),
		"urban": Color(0.8, 0.78, 0.75)}
	trk_mat.set_shader_parameter("tint", tints.get(surf, Color(0.5, 0.45, 0.37)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = trk_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _ground_basis(x: float, z: float) -> Basis:
	return Basis(Quaternion(Vector3.UP, terra.normal(x, z)))


func _spawn() -> void:
	var ws := D.WS
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# команды равного боевого веса из машин, воевавших здесь (или из всех машин стороны),
	# уровнем не дальше ±1 от танка игрока
	var tier := D.tier(player_type)
	var mine := D.pool(map_key, side, history, tier)
	var theirs := D.pool(map_key, D.foe_side(side), history, tier)
	teams = D.match_teams(mine, theirs, player_type, rng, year, tier)
	# позывные — по армии, которая ведёт машину
	var names := {}
	for nat in D.CALLSIGNS:
		var list: Array = D.CALLSIGNS[nat].duplicate()
		list.shuffle()
		names[nat] = list
	lang = D.LANG[D.operator(player_type, map_key, history)]
	for team in 2:
		var list: Array = teams[team]
		var y := ws - 300.0 if team == 0 else 300.0
		for i in list.size():
			# игрок в центре строя, остальные расходятся в стороны
			var slot := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
			var p := Vector2(ws / 2 + slot * 165.0, y + (-30.0 if team == 0 else 30.0) * (i % 2))
			var me := team == 0 and i == 0
			var nat := D.operator(list[i], map_key, history)
			var tk := _add_tank(list[i], team, p, "Вы" if me else names[nat].pop_back(), me)
			tk.nation = nat
			if me:
				player = tk
				watch = tk
			elif (team == 0 and i == 1) or (team == 1 and i == 0):
				tk.role = "def"
			tk.b_side = -1.0 if p.x < ws / 2 else 1.0
		_assign_lanes(team)


func _add_tank(key: String, team: int, p: Vector2, nm: String, is_player: bool) -> TankScript:
	var tk: TankScript = TankScript.new()
	add_child(tk)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var top: Dictionary = player_mods if is_player else D.random_mods(key, rng)
	tk.setup(key, team, p, nm, is_player, hq, year, D.paint(key, map_key, history), top)
	tk.sync_node()
	tk.reset_physics_interpolation()  # появился на месте, а не приехал из начала координат
	for c in (player_cons if is_player else D.CONSUMABLES.keys()):
		tk.cons[c] = 0.0
	tk.set_dust(Color(D.MAPS[map_key].dust), 0.75 if map_key == "alamein" else 0.55)
	tk.smoke = fx.damage_smoke(tk, tk.hh)
	match surf:
		"snow":
			tk.dust_fx = fx.trail("snow")
		"sand":
			tk.dust_fx = fx.trail("sand")
		"urban":
			tk.dust_fx = fx.trail("light")
		_:
			tk.dust_fx = fx.trail("light" if map_key == "normandy" else "dust")
			tk.mud_fx = fx.trail("mud")
	tanks.append(tk)
	var engine := "engine_" + String(tk.T.engine)
	loops[tk] = [sfx.attach_loop(tk, engine, 26.0 if is_player else 20.0, -2.0 if is_player else -6.0),
		sfx.attach_loop(tk, "tracks", 22.0, -40.0),
		sfx.attach_loop(tk, "turret", 8.0, -80.0) if is_player else null]
	return tk


# ---------- Геометрия и лучи ----------

static func ang_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


static func turn_toward(cur: float, target: float, step: float) -> float:
	var d := ang_diff(target, cur)
	return target if absf(d) <= step else cur + signf(d) * step


# Постройки, кусты и деревья разложены по клеткам 100 × 100: проверка точки смотрит
# только соседние клетки, а не всю карту.
const HCELL := 100.0
var h_obst := {}  # клетка → постройки
var h_bush := {}
var h_prop := {}


static func _hkey(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / HCELL), floori(p.y / HCELL))


static func _hput(h: Dictionary, r: Rect2, item) -> void:
	var a := _hkey(r.position)
	var b := _hkey(r.end)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var k := Vector2i(x, y)
			if not h.has(k):
				h[k] = []
			h[k].append(item)


func _build_hash() -> void:
	for o in obst:
		_hput(h_obst, o.r, o)
	for b in bushes:
		_hput(h_bush, Rect2(b.pos - Vector2(b.r, b.r), Vector2(b.r, b.r) * 2.0), b)
	for pr in props:
		_hput(h_prop, Rect2(pr.pos - Vector2(pr.r, pr.r), Vector2(pr.r, pr.r) * 2.0), pr)
	if core:
		var f := PackedFloat32Array()
		for o in obst:
			var r: Rect2 = o.r
			f.append_array([r.position.x, r.position.y, r.size.x, r.size.y, 1.0 if o.solid else 0.0])
		core.obst_set(f, HCELL)


## Всё, что лежит в клетках вокруг точки (предмет на стыке клеток может попасться дважды).
func _near(h: Dictionary, p: Vector2, r: float) -> Array:
	var a := _hkey(p - Vector2(r, r))
	var b := _hkey(p + Vector2(r, r))
	if a == b:
		return h.get(a, [])
	var out: Array = []
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			out.append_array(h.get(Vector2i(x, y), []))
	return out


func in_rect(p: Vector2):
	for o in h_obst.get(_hkey(p), []):
		if (o.r as Rect2).has_point(p):
			return o
	return null


func in_bush(p: Vector2):
	for b in h_bush.get(_hkey(p), []):
		if p.distance_squared_to(b.pos) < float(b.r) * float(b.r):
			return b
	return null


func blocked_at(p: Vector2, r: float) -> bool:
	if core:
		return core.blocked_at(p.x, p.y, r)
	if p.x < r or p.y < r or p.x > D.WS - r or p.y > D.WS - r:
		return true
	for o in _near(h_obst, p, r):
		if (o.r as Rect2).grow(r).has_point(p):
			return true
	return false


func ray(from: Vector3, to: Vector3, mask := MASK_WORLD) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)


## Прямая видимость по рельефу и постройкам (без танков). C++ считает по сетке высот и коробкам
## построек — без физического запроса.
func clear_line(a: Vector3, b: Vector3) -> bool:
	if core:
		return core.los(a, b)
	return ray(a, b).is_empty()


## Пересечение отрезка с параллелепипедом в локальных координатах: [t, нормаль грани] или [].
static func slab(o: Vector3, d: Vector3, mn: Vector3, mx: Vector3) -> Array:
	var tmin := 0.0
	var tmax := 1.0
	var nrm := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 1e-6:
			if o[a] < mn[a] or o[a] > mx[a]:
				return []
		else:
			var t1 := (mn[a] - o[a]) / d[a]
			var t2 := (mx[a] - o[a]) / d[a]
			var s := -1.0
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
				s = 1.0
			if t1 > tmin:
				tmin = t1
				nrm = Vector3.ZERO
				nrm[a] = s
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return []
	return [tmin, nrm]


## Луч по танкам (корпус и башня как коробки). Возвращает ближайшее попадание.
func ray_tanks(from: Vector3, to: Vector3, exclude: TankScript) -> Dictionary:
	var best := {}
	var bt := 2.0
	var seg := to - from
	for tk: TankScript in tanks:
		if tk == exclude:
			continue
		var c := tk.center()
		var cl := Geometry3D.get_closest_point_to_segment(c, from, to)
		if cl.distance_to(c) > float(tk.T.L) * 0.8:
			continue
		var L: float = tk.T.L
		var W: float = tk.T.W
		var parts := [
			["hull", tk.hull_node.global_transform, Vector3(-L / 2, 0.35 * D.UPM, -W / 2), Vector3(L / 2, tk.hh, W / 2)],
			["turret", tk.up_node.global_transform, tk.up_min, tk.up_max],
		]
		for part in parts:
			var xf: Transform3D = part[1]
			var inv := xf.affine_inverse()
			var r := slab(inv * from, inv.basis * seg, part[2], part[3])
			if r.is_empty() or r[0] >= bt:
				continue
			bt = r[0]
			var n: Vector3 = r[1]
			if n == Vector3.ZERO:
				n = -(inv.basis * seg).normalized()
			best = {"t": bt, "tank": tk, "part": part[0], "n_local": n, "xf": xf, "pos": from + seg * bt}
	return best


## Баллистическая трасса: куда упадёт снаряд, выпущенный из from со скоростью v.
func trace(from: Vector3, v: Vector3, exclude: TankScript, max_t := 1.2) -> Dictionary:
	var p := from
	var vel := v
	var steps := 16
	var dt := max_t / steps
	for i in steps:
		var nv := vel + Vector3(0, -D.GRAVITY * dt, 0)
		var np := p + (vel + nv) * 0.5 * dt
		var wh := ray(p, np)
		var th := ray_tanks(p, np, exclude)
		var tw := 2.0
		if not wh.is_empty():
			tw = p.distance_to(wh.position) / maxf(p.distance_to(np), 0.001)
		if not th.is_empty() and th.t <= tw:
			th["vel"] = nv
			return th
		if not wh.is_empty():
			return {"pos": wh.position, "vel": nv}
		p = np
		vel = nv
	return {"pos": p, "vel": vel}


## Броня в точке попадания: [толщина, нормаль в мире, зона].
func armor_at(tk: TankScript, hitd: Dictionary) -> Array:
	var A: Array = tk.T.armor
	var n: Vector3 = hitd.n_local
	var xf: Transform3D = hitd.xf
	var turret: bool = hitd.part == "turret"
	var thick: float
	var nl := n
	var zone := "side"
	if n.x > 0.5:
		thick = A[3] if turret else A[0]
		var sl: float = float(tk.T.tslope) if turret else float(tk.T.slope)
		nl = Vector3(cos(sl), sin(sl), 0)
		zone = "front"
	elif n.x < -0.5:
		thick = A[5] if turret else A[2]
		zone = "rear"
	elif n.y > 0.5:
		thick = float(A[4] if turret else A[1]) * 0.45
		zone = "roof"
	elif n.y < -0.5:
		thick = float(A[1]) * 0.4
		zone = "floor"
	else:
		thick = A[4] if turret else A[1]
		if not turret:
			var ss: float = tk.T.side_slope
			nl = Vector3(0, sin(ss), cos(ss) * signf(n.z))
	return [thick, (xf.basis * nl).normalized(), zone]


## Грунт под гусеницами: (сцепление — доля веса, мягкость 0–1). Дорога твёрдая; мягче пашня,
## рыхлая земля воронок, сырые низины (на снегу — сугробы, в пустыне — сыпучий песок),
## битый кирпич; выгоревшие проплешины твёрже. Пятна те же, что видны на земле.
func ground_at(p: Vector2) -> Vector2:
	var m := terra.mask
	var px := clampi(int((p.x - Terrain.ORIGIN) / Terrain.SIZE * m.get_width()), 0, m.get_width() - 1)
	var pz := clampi(int((p.y - Terrain.ORIGIN) / Terrain.SIZE * m.get_height()), 0, m.get_height() - 1)
	var c := m.get_pixel(px, pz)
	var road := clampf(c.r * 1.2, 0.0, 1.0)
	var wet := terra.patch(p, "damp")
	var dry := terra.patch(p, "dry")
	var soft := soft_base
	var mu := mu_base
	match surf:
		"snow":
			soft += wet * 0.4
			mu -= wet * 0.08
		"sand":
			soft += wet * 0.38 - dry * 0.2
		"urban":
			soft += c.b * 0.3
		_:
			soft += wet * 0.36 + c.b * 0.14 - dry * 0.1
			mu -= wet * 0.28
	soft += c.g * 0.22
	soft = lerpf(soft, 0.04, road)
	mu = lerpf(mu, road_mu, road)
	return Vector2(mu, clampf(soft, 0.0, 1.0))


# ---------- Физика танка ----------

static func radius(tk: TankScript) -> float:
	return float(tk.T.W) * 0.62


## Выталкивает танк из построек; возвращает вектор выталкивания.
func resolve(tk: TankScript) -> Vector2:
	var r := radius(tk)
	var before := tk.pos
	for o in _near(h_obst, tk.pos, r):
		var R: Rect2 = o.r
		var c := Vector2(clampf(tk.pos.x, R.position.x, R.end.x), clampf(tk.pos.y, R.position.y, R.end.y))
		var d := tk.pos - c
		var d2 := d.length_squared()
		if d2 >= r * r:
			continue
		if d2 > 0.0001:
			var dl := sqrt(d2)
			tk.pos += d * ((r - dl) / dl)
		else:
			var l := tk.pos.x - R.position.x
			var rr := R.end.x - tk.pos.x
			var tp := tk.pos.y - R.position.y
			var bt := R.end.y - tk.pos.y
			var m := minf(minf(l, rr), minf(tp, bt))
			if m == l:
				tk.pos.x = R.position.x - r
			elif m == rr:
				tk.pos.x = R.end.x + r
			elif m == tp:
				tk.pos.y = R.position.y - r
			else:
				tk.pos.y = R.end.y + r
	tk.pos = tk.pos.clamp(Vector2(r, r), Vector2(D.WS - r, D.WS - r))
	return tk.pos - before


## Деревья и заборы: тяжёлый или быстрый танк их валит, медленный упирается.
func _props_collide(tk: TankScript) -> void:
	var r := radius(tk)
	for pr in _near(h_prop, tk.pos, r + 10.0):
		if not pr.alive:
			continue
		var d: Vector2 = tk.pos - pr.pos
		var mn: float = r + float(pr.r)
		if d.length_squared() >= mn * mn:
			continue
		var spd := tk.vel.length()
		if spd > 12.0 or float(tk.T.mass) > 40.0:
			pr.alive = false
			pr.fall = 0.02
			pr.fall_dir = tk.vel.normalized() if spd > 1.0 else -d.normalized()
			falling.append(pr)
			tk.vel *= 0.85
			sfx.play3d("tree", Vector3(pr.pos.x, pr.y + 5.0, pr.pos.y))
			fx.debris(Vector3(pr.pos.x, pr.y + 6.0, pr.pos.y), Color(0.3, 0.24, 0.16))
		else:
			var l := d.length()
			if l > 0.001:
				tk.pos += d / l * (mn - l)
				var nrm := d / l
				var vn := tk.vel.dot(nrm)
				if vn < 0:
					tk.vel -= nrm * vn


## Ходовая: газ/тормоз и поворот как у гусеничной машины, всё через импульс корпуса.
## На мягком грунте медленнее разгон и поворот; тяга не больше сцепления — гусеницы буксуют,
## а на склоне круче, чем держит сцепление, танк сползает.
func drive(tk: TankScript, dt: float, thr: float, steer: float) -> void:
	var T := tk.T
	if tk.track_broken > 0.0 or tk.immobile:
		thr = 0.0
		steer = 0.0
	thr = clampf(thr, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	tk.throttle = thr
	var g := D.GRAVITY
	var gnd := ground_at(tk.pos)
	var mu: float = gnd.x
	tk.soft = gnd.y
	# узкие гусеницы тяжёлой машины вязнут сильнее
	var soft := minf(1.0, gnd.y * pow(tk.press, 1.3))
	var go := (1.0 - 0.5 * soft) * tk.speed_k
	var vmax: float = float(T.speed) * go
	var vrev: float = float(T.rev_speed) * go
	var fwd := Vector2.from_angle(tk.hull)
	var v_f := tk.vel.dot(fwd)
	var v0 := v_f
	# инерция поворота: угловая скорость набирается не мгновенно
	var rev := v_f < -1.0 or thr < -0.05
	var turn: float = float(T.turn) * tk.turn_k * (1.0 - 0.3 * soft)
	var want_turn: float = turn * steer * (-1.0 if rev else 1.0) * (1.0 - clampf(absf(v_f) / maxf(vmax, 1.0), 0.0, 1.0) * 0.3)
	tk.yaw_rate = move_toward(tk.yaw_rate, want_turn, float(T.turn) * 3.0 * dt)
	tk.hull = wrapf(tk.hull + tk.yaw_rate * dt, -PI, PI)
	# башня стоит на корпусе: поворот корпуса уносит её с собой, а механизм поворота башни
	# добавляет к этому свою скорость (в _aim_at)
	tk.tur = wrapf(tk.tur + tk.yaw_rate * dt, -PI, PI)
	# скорость остаётся в мировых осях — в повороте часть её становится боковой и гасится сцеплением
	fwd = Vector2.from_angle(tk.hull)
	var right := Vector2(-fwd.y, fwd.x)
	v_f = tk.vel.dot(fwd)
	var v_l := tk.vel.dot(right)
	var e := 4.0
	var grad := Vector2(terra.height(tk.pos.x + e, tk.pos.y) - terra.height(tk.pos.x - e, tk.pos.y),
		terra.height(tk.pos.x, tk.pos.y + e) - terra.height(tk.pos.x, tk.pos.y - e)) / (2.0 * e)
	var slope_f := grad.dot(fwd)
	var slope_l := grad.dot(right)
	var cos_f := 1.0 / sqrt(1.0 + slope_f * slope_f)
	var traction := g * mu * cos_f
	var a := 0.0
	tk.slip = 0.0
	if absf(thr) > 0.05:
		var target := thr * (vmax if thr > 0 else vrev) * (1.0 - absf(steer) * 0.25)
		var push: float = float(T.accel) * tk.accel_k * (1.0 - 0.55 * soft) * (1.0 - clampf(absf(v_f) / maxf(vmax, 1.0), 0.0, 1.0) * 0.6)
		# на подъёме выручает низкая передача: на малой скорости тяги хватает на склон,
		# пока его держит сцепление (на ровном месте разгон прежний)
		var up := slope_f * signf(thr)
		if up > 0.0:
			push += minf(g * up * cos_f, push * 1.5) * (1.0 - clampf(absf(v_f) / maxf(vmax, 1.0), 0.0, 1.0))
		a = clampf((target - v_f) * 2.5, -push * 2.5, push)
	else:
		a = -signf(v_f) * minf(absf(v_f) * 3.0, 0.4 * g)  # торможение двигателем и фрикционами
	# тяга и торможение — не больше сцепления: лишнее уходит в пробуксовку гусениц
	if absf(a) > traction:
		if absf(thr) > 0.05:
			tk.slip = clampf((absf(a) - traction) / absf(a), 0.0, 1.0)
		a = signf(a) * traction
	a -= g * slope_f * cos_f  # составляющая веса вдоль корпуса
	v_f += a * dt
	# сопротивление качению (на мягком грунте больше)
	v_f = move_toward(v_f, 0.0, g * (0.03 + soft * 0.07) * dt)
	# стоящий танк держат тормоза, пока склон не круче, чем позволяет сцепление
	if absf(thr) <= 0.05 and absf(v_f) < 1.5 and absf(slope_f) < mu * 0.95:
		v_f = 0.0
	v_f = clampf(v_f, -vrev * 1.15 - 25.0, vmax * 1.15 + 25.0) if absf(slope_f) > mu * 0.95 else clampf(v_f, -vrev * 1.15, vmax * 1.15)
	# поперёк гусеницы держит сцепление; на боковом склоне круче него корпус сползает
	v_l -= g * slope_l / sqrt(1.0 + slope_l * slope_l) * dt
	v_l = move_toward(v_l, 0.0, mu * g * 1.1 * dt)
	tk.accel = (v_f - v0) / maxf(dt, 0.001)
	tk.vel = fwd * v_f + right * v_l
	tk.sp = v_f
	var old := tk.pos
	tk.pos += tk.vel * dt
	var pushv := resolve(tk)
	if pushv.length_squared() > 0.0001:
		var nrm := pushv.normalized()
		var vn := tk.vel.dot(nrm)
		if vn < 0:
			tk.vel -= nrm * vn * 1.2  # удар о стену гасит скорость в сторону стены
			if -vn > 25.0:
				sfx.play3d("impact_stone", tk.center(), -6.0)
				if tk == watch:
					shake = maxf(shake, clampf(-vn * 0.08, 2.0, 8.0))
				tk.kick(-signf(tk.vel.dot(fwd) + 0.01) * 0.5, 0.0)
	_props_collide(tk)
	var moved := tk.pos.distance_to(old)
	tk.dist_travel += moved
	# путь гусениц: в повороте внешняя бежит быстрее, при пробуксовке обе крутятся быстрее хода
	var half_w: float = float(T.W) * 0.5
	var spin := tk.slip * signf(thr) * vmax * 0.6
	tk.travel[0] += (v_f + spin + tk.yaw_rate * half_w) * dt
	tk.travel[1] += (v_f + spin - tk.yaw_rate * half_w) * dt
	_track_marks(tk)
	_trail(tk, fwd, v_f)
	# выхлоп при резком разгоне
	if thr > 0.6 and v_f < vmax * 0.5 and randf() < dt * 6.0 and (tk.team == 0 or tk.vis[0]) and tk.pos.distance_to(watch.pos) < 700.0:
		var ex := tk.pos - fwd * float(T.L) * 0.45
		fx.exhaust(Vector3(ex.x, tk.ground + tk.hh + 1.0, ex.y), fwd)


## Следы гусениц: от прошлой точки каждой гусеницы до текущей — отрезок с рисунком траков;
## на мягком грунте глубже и темнее.
func _track_marks(tk: TankScript) -> void:
	var f := Vector2.from_angle(tk.hull)
	var r := Vector2(-f.y, f.x)
	# следы оставляют только видимые игроку машины недалеко от камеры (невидимого врага они бы выдали)
	var shown: bool = (tk.team == 0 or tk.vis[0]) and tk.pos.distance_to(watch.pos) < 750.0
	for s in 2:
		var p := tk.pos + r * tk.track_z * (-1.0 if s == 0 else 1.0)
		var last: Vector2 = tk.last_mark[s]
		var d := p.distance_to(last)
		if d > 40.0 or not shown:
			tk.last_mark[s] = p
			continue
		if d < 5.0:
			continue
		var h0 := terra.height(last.x, last.y)
		var h1 := terra.height(p.x, p.y)
		var along := Vector3(p.x - last.x, h1 - h0, p.y - last.y)
		var mid := (p + last) * 0.5
		var n := terra.normal(mid.x, mid.y)
		var across := n.cross(along).normalized()
		var len := along.length() + 0.5
		var b := Basis(along.normalized() * len, n, across * tk.track_w)
		trk_mm.set_instance_transform(trk_i, Transform3D(b, Vector3(mid.x, (h0 + h1) * 0.5 + 0.3, mid.y)))
		trk_mm.set_instance_custom_data(trk_i, Color(clock, clampf(0.45 + tk.soft * 0.9, 0.35, 1.0), tk.mark_v[s], len))
		tk.mark_v[s] = fmod(float(tk.mark_v[s]) + d, 1600.0)
		tk.last_mark[s] = p
		trk_i = (trk_i + 1) % TRK


## Шлейф за кормой на ходу: пыль, снег или комья грязи на мягком сыром грунте.
func _trail(tk: TankScript, fwd: Vector2, v_f: float) -> void:
	if tk.dust_fx == null:
		return
	var on: bool = (absf(v_f) > 10.0 or tk.slip > 0.3) and (tk.team == 0 or tk.vis[0]) and tk.pos.distance_to(watch.pos) < 1100.0
	var back := tk.pos - fwd * float(tk.T.L) * 0.45 * signf(v_f + 0.01)
	var at := Vector3(back.x, tk.ground + 1.2, back.y)
	var muddy := tk.mud_fx != null and tk.soft > 0.42
	_fx_on(tk.dust_fx, on and not muddy, at)
	if tk.mud_fx:
		_fx_on(tk.mud_fx, on and muddy, at)
		# комья летят назад-вверх: излучатель «смотрит» туда (направление частиц — вверх в его осях)
		var d := Vector3(-fwd.x * signf(v_f + 0.01), 1.4, -fwd.y * signf(v_f + 0.01)).normalized()
		tk.mud_fx.basis = Basis(Quaternion(Vector3.UP, d))


func _fx_on(p: GPUParticles3D, on: bool, at: Vector3) -> void:
	if on:
		p.global_position = at
	if p.emitting != on:
		p.emitting = on


## Подвеска: корпус ложится по рельефу, а на пружинах раскачивается — приседает при разгоне,
## клюёт носом при торможении, кренится в повороте, качается от выстрела и попаданий.
## Тяжёлая машина качается медленнее и меньше.
func _suspend(tk: TankScript, dt: float) -> void:
	var T := tk.T
	var lx: float = float(T.L) * 0.42
	var lz: float = float(T.W) * 0.42
	var f := Vector2.from_angle(tk.hull)
	var r := Vector2(-f.y, f.x)
	var hf := terra.height(tk.pos.x + f.x * lx, tk.pos.y + f.y * lx)
	var hb := terra.height(tk.pos.x - f.x * lx, tk.pos.y - f.y * lx)
	var hr := terra.height(tk.pos.x + r.x * lz, tk.pos.y + r.y * lz)
	var hl := terra.height(tk.pos.x - r.x * lz, tk.pos.y - r.y * lz)
	tk.ground = maxf((hf + hb + hr + hl) * 0.25, terra.height(tk.pos.x, tk.pos.y) - 1.0)
	var tp := atan2(hf - hb, 2.0 * lx)
	var tr := -atan2(hr - hl, 2.0 * lz)
	if dt >= 1.0:
		tk.pitch = tp
		tk.roll = tr
		return
	tk.pitch_v += ((tp - tk.pitch) * 70.0 - tk.pitch_v * 14.0) * dt
	tk.roll_v += ((tr - tk.roll) * 70.0 - tk.roll_v * 14.0) * dt
	tk.pitch += tk.pitch_v * dt
	tk.roll += tk.roll_v * dt
	if not tk.alive:
		tk.body_p = move_toward(tk.body_p, 0.0, dt * 0.2)
		tk.body_r = move_toward(tk.body_r, 0.0, dt * 0.2)
		return
	var bp_t := clampf(tk.accel * 0.0013, -0.065, 0.065)
	var br_t := clampf(-tk.yaw_rate * tk.sp * 0.0007, -0.06, 0.06)
	tk.body_pv += ((bp_t - tk.body_p) * tk.spring_k - tk.body_pv * tk.spring_c) * dt
	tk.body_rv += ((br_t - tk.body_r) * tk.spring_k - tk.body_rv * tk.spring_c) * dt
	tk.body_p = clampf(tk.body_p + tk.body_pv * dt, -0.14, 0.14)
	tk.body_r = clampf(tk.body_r + tk.body_rv * dt, -0.12, 0.12)


## Столкновения танков: упругий обмен импульсом по массам; на скорости — урон тараном.
func separate() -> void:
	var n := tanks.size()
	for i in n:
		var a: TankScript = tanks[i]
		for j in range(i + 1, n):
			var b: TankScript = tanks[j]
			if not a.alive and not b.alive:
				continue
			var d := b.pos - a.pos
			var mn := radius(a) + radius(b)
			var l := d.length()
			if l >= mn or l < 0.001:
				continue
			var nrm := d / l
			var ma: float = float(a.T.mass) * (1.0 if a.alive else 1.5)
			var mb: float = float(b.T.mass) * (1.0 if b.alive else 1.5)
			var push := mn - l
			a.pos -= nrm * push * mb / (ma + mb)
			b.pos += nrm * push * ma / (ma + mb)
			resolve(a)
			resolve(b)
			var closing := (a.vel - b.vel).dot(nrm)
			if closing <= 0.0:
				continue
			var j_imp := (1.0 + 0.15) * closing / (1.0 / ma + 1.0 / mb)
			if a.alive:
				a.vel -= nrm * j_imp / ma
			if b.alive:
				b.vel += nrm * j_imp / mb
			if closing > 22.0 and a.team != b.team and a.alive and b.alive:
				stat.ram += 1
				var e := closing * closing * 0.006
				_damage(b, roundf(e * ma / (ma + mb) * 2.0), a, "ТАРАН")
				_damage(a, roundf(e * mb / (ma + mb) * 0.8), b, "ТАРАН")
				sfx.play3d("hit_pen", (a.center() + b.center()) * 0.5, -3.0, 0.8)
				if a == watch or b == watch:
					shake = maxf(shake, 7.0)


# ---------- Стрельба и броня ----------

func _update_disp(tk: TankScript, dt: float) -> void:
	var base: float = float(tk.T.disp) * tk.disp_k
	# гиростабилизатор гасит раскачку орудия на ходу
	var move := (absf(tk.sp) / float(tk.T.speed) * 0.03 + absf(tk.yaw_rate) * 0.02) * (1.0 - float(tk.T.stab))
	var floor_d := base + move + tk.tur_rate * 0.018
	if tk.disp > floor_d:
		tk.disp = lerpf(tk.disp, floor_d, 1.0 - exp(-dt * 2.6 / (float(tk.T.aim) * tk.aim_k)))
	else:
		tk.disp = floor_d


## Наведение башни и орудия на точку с поправкой на падение снаряда.
func _aim_at(tk: TankScript, target: Vector3, dt: float) -> void:
	var before := tk.tur
	var want := (Vector2(target.x, target.z) - tk.pos).angle()
	if tk.casemate:
		# в рубке орудие ходит только в узком секторе, дальше доворачивают корпусом
		var lim: float = tk.T.trav
		want = tk.hull + clampf(ang_diff(want, tk.hull), -lim, lim)
	# скорость поворота — относительно корпуса (before уже учитывает поворот корпуса)
	tk.tur = turn_toward(tk.tur, want, float(tk.T.tspd) * tk.tspd_k * dt)
	if tk.casemate:
		tk.tur = tk.hull + clampf(ang_diff(tk.tur, tk.hull), -float(tk.T.trav), float(tk.T.trav))
	tk.tur_rate = absf(ang_diff(tk.tur, before)) / maxf(dt, 0.001)
	var local := tk.tur_node.global_transform.affine_inverse() * target
	var gp := tk.gun_pos0
	var dx := Vector2(local.x - gp.x, local.z).length()
	var e := atan2(local.y - gp.y, dx)
	var tf := dx / float(tk.T.shell_v)
	e += atan2(0.5 * D.GRAVITY * tf * tf, dx)
	var lim: Array = tk.T.elev
	tk.gun_target = clampf(e, lim[0], lim[1])
	tk.gun_pitch = move_toward(tk.gun_pitch, tk.gun_target, 0.35 * dt)


func shoot(tk: TankScript) -> void:
	var dir := tk.gun_dir()
	var u := dir.cross(Vector3.UP).normalized()
	var v := u.cross(dir).normalized()
	var spread := tan(tk.disp)
	var g := Vector2(randfn(0.0, 0.45), randfn(0.0, 0.45)).limit_length(1.0) * spread
	dir = (dir + u * g.x + v * g.y).normalized()
	var p := tk.muzzle()
	var sh := {"pos": p, "vel": dir * float(tk.T.shell_v), "dmg": float(tk.T.dmg), "pen": float(tk.T.pen),
		"cal": float(tk.T.caliber), "owner": tk, "dist": 0.0, "rico": 0, "dead": false, "slot": shell_slot, "whiz": false}
	shell_slot = (shell_slot + 1) % SHELL_SLOTS
	_shell_visual(sh, 1e9)
	shells.append(sh)
	tk.rl_max = tk.reload_time()
	tk.rl = tk.rl_max
	tk.shots_fired += 1
	tk.recoil = 1.0
	tk.disp += 0.035
	# отдача раскачивает корпус: сильнее у крупного калибра и лёгкой машины
	var kick: float = float(tk.T.caliber) / 85.0 * 30.0 / float(tk.T.mass)
	var rel := ang_diff(tk.tur, tk.hull)
	tk.kick(cos(rel) * 0.4 * kick, -sin(rel) * 0.4 * kick)
	tk.vel -= Vector2.from_angle(tk.tur) * kick * 2.0
	# вспышку выстрела видят враги поблизости
	for o: TankScript in tanks:
		if o.alive and o.team != tk.team and o.pos.distance_squared_to(tk.pos) < 800.0 * 800.0:
			tk.lit = maxf(tk.lit, 2.0)
			break
	fx.muzzle(p, dir, float(tk.T.caliber))
	fx.shot_dust(Vector3(tk.pos.x, tk.ground + 2.0, tk.pos.y))
	if tk.is_player:
		shake = maxf(shake, 3.0 + float(tk.T.caliber) / 40.0)
		shots += 1
		reload_cue = true
	sfx.gun(float(tk.T.caliber), p)


func _update_shells(dt: float) -> void:
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	for s in shells:
		var p0: Vector3 = s.pos
		var v: Vector3 = s.vel
		var nv := v + Vector3(0, -D.GRAVITY * dt, 0)
		var p1 := p0 + (v + nv) * 0.5 * dt
		v = nv
		# свист снаряда, пролетающего рядом с камерой
		if not s.whiz and not (s.owner as TankScript).is_player:
			var cl := Geometry3D.get_closest_point_to_segment(cam_pos, p0, p1)
			if cl.distance_to(cam_pos) < 45.0:
				s.whiz = true
				sfx.play3d("whiz", cl)
		var wh := ray(p0, p1)
		var th := ray_tanks(p0, p1, s.owner if s.rico == 0 else null)
		var tw := 2.0
		if not wh.is_empty():
			tw = p0.distance_to(wh.position) / maxf(p0.distance_to(p1), 0.001)
		if not th.is_empty() and th.t <= tw:
			_shell_hits_tank(s, th, v)
		elif not wh.is_empty():
			s.dead = true
			var hp: Vector3 = wh.position
			var on_ground: bool = wh.collider is StaticBody3D and (wh.collider as StaticBody3D).collision_layer == 1
			fx.impact(hp, on_ground)
			if on_ground:
				_scorch(hp, randf_range(7.0, 11.0))
			sfx.play3d("impact_ground" if on_ground else "impact_stone", hp)
		else:
			s.pos = p1
			s.vel = v
			s.dist += p0.distance_to(p1)
			if s.dist > D.RANGE:
				s.dead = true
				stat.miss += 1
		if s.dead:
			# трассер долетает до места попадания и гаснет
			_shell_end(s, clock + dt)
		elif s.rico == 1 and not s.has("rico_shown"):
			# отражённый снаряд — новый полёт из точки рикошета
			s.rico_shown = true
			_shell_visual(s, 1e9)
	shells = shells.filter(func(x): return not x.dead)


func _make_shell_mm() -> void:
	shell_mm = MultiMesh.new()
	shell_mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 22)
	shell_mm.mesh = box
	shell_mm.instance_count = SHELL_SLOTS
	shell_mm.custom_aabb = AABB(Vector3(-1500, -600, -1500), Vector3(D.WS + 3000, 3000, D.WS + 3000))
	for i in SHELL_SLOTS:
		shell_mm.set_instance_transform(i, Transform3D(Basis(Vector3.ZERO, Vector3(1e9, 0, 0), Vector3.ZERO), Vector3.ZERO))
	var sh := Shader.new()
	sh.code = SHELL_SHADER
	shell_mat = ShaderMaterial.new()
	shell_mat.shader = sh
	shell_mat.set_shader_parameter("grav", D.GRAVITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = shell_mm
	mmi.material_override = shell_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = shell_mm.custom_aabb
	add_child(mmi)


## Полёт снаряда для шейдера: откуда и с какой скоростью вылетел и когда (сейчас).
func _shell_visual(s: Dictionary, t_end: float) -> void:
	shell_mm.set_instance_transform(int(s.slot), Transform3D(Basis(s.vel, Vector3(clock, t_end, 0), Vector3.ZERO), s.pos))


func _shell_end(s: Dictionary, t_end: float) -> void:
	var xf := shell_mm.get_instance_transform(int(s.slot))
	xf.basis.y.y = t_end
	shell_mm.set_instance_transform(int(s.slot), xf)


func _shell_hits_tank(s: Dictionary, th: Dictionary, v: Vector3) -> void:
	var tk: TankScript = th.tank
	var by: TankScript = s.owner
	var hp: Vector3 = th.pos
	var dir := v.normalized()
	s.dead = true
	if not tk.alive or tk.team == by.team:
		fx.hit_sparks(hp)
		sfx.play3d("hit_nopen", hp, -4.0)
		return
	tk.hits_taken += 1
	var arm := armor_at(tk, th)
	var thick: float = arm[0]
	var n: Vector3 = arm[1]
	var zone: String = arm[2]
	var cal: float = s.cal
	var cos_a := clampf(-dir.dot(n), 0.0, 1.0)
	var ang := maxf(0.0, acos(cos_a) - deg_to_rad(5.0))  # нормализация
	# бронепробиваемость падает с дистанцией
	var pen: float = float(s.pen) * (1.0 - 0.18 * clampf(float(s.dist) / D.RANGE, 0.0, 1.0)) * randf_range(0.8, 1.2)
	var overmatch: bool = cal > thick * 3.0
	_hit_kick(tk, dir, cal, 0.12)
	if ang > deg_to_rad(70.0) and not overmatch and s.rico == 0:
		# рикошет: снаряд отражается и летит дальше
		s.dead = false
		s.rico = 1
		s.pos = hp + n * 0.5
		s.vel = (v - 2.0 * v.dot(n) * n) * 0.7
		s.dist = D.RANGE - 250.0
		stat.rico += 1
		if tk.is_player:
			blocked += float(s.dmg)
		fx.hit_sparks(hp)
		_popup(tk, "РИКОШЕТ", Color("cfd3d8"), by)
		sfx.play3d("ricochet", hp)
		_mark_hit(tk, hp, dir, 0, cal)
		return
	var eff := thick / maxf(cos(ang), 0.12)
	# попадание в ходовую: гусеница принимает удар на себя и может слететь
	var local := (th.xf as Transform3D).affine_inverse() * hp
	var track_zone: bool = th.part == "hull" and local.y < tk.th * 1.05 and (zone == "side" or zone == "front" or zone == "rear")
	if track_zone and randf() < 0.7:
		if tk.track_broken <= 0.0:
			stat.track += 1
			_popup(tk, "ГУСЕНИЦА СБИТА", Color("ffd37a"), by)
			sfx.play3d("track_break", hp)
			if tk.is_player:
				hud.alert("ГУСЕНИЦА СБИТА", Color(D.AMBER))
		tk.track_broken = TRACK_REPAIR
		tk.vel *= 0.3
	if pen < eff:
		stat.nopen += 1
		if tk.is_player:
			blocked += float(s.dmg)
		fx.hit_sparks(hp)
		if not track_zone:
			_popup(tk, "НЕ ПРОБИЛ", Color("cfd3d8"), by)
		sfx.play3d("hit_nopen", hp)
		if by.team == 0 and tk.team == 1:
			tk.lit = maxf(tk.lit, 2.0)
		tk.hit_t = clock
		_mark_hit(tk, hp, dir, 1, cal)
		_outer_damage(tk, by, th.part, local, zone, float(s.dmg))
		return
	stat.pen += 1
	tk.pens_taken += 1
	var dmg := roundf(float(s.dmg) * randf_range(0.75, 1.25) * (0.5 if track_zone else 1.0))
	fx.hit_sparks(hp)
	fx.pen_fire(hp)
	if by.is_player:
		hits += 1
	sfx.play3d("hit_pen", hp)
	_mark_hit(tk, hp, dir, 2, cal)
	_hit_kick(tk, dir, cal, 0.2)
	# за бронёй: модули и экипаж на пути снаряда, осколки
	if _internal_damage(tk, by, hp, dir, float(s.dmg) * (0.5 if track_zone else 1.0), th.part):
		stat.ammo += 1
		_popup(tk, "БОЕУКЛАДКА", Color("ff6a4a"), by)
		dmg = tk.hp + 1.0
	_damage(tk, dmg, by, "")
	if tk.alive and tk.crew_left() == 0:
		_popup(tk, "ЭКИПАЖ ВЫБЫЛ", Color("ff6a4a"), by)
		_damage(tk, tk.hp + 1.0, by, "")


## Толчок от попадания: корпус качается от удара (крупный калибр и лёгкая машина — сильнее).
func _hit_kick(tk: TankScript, dir: Vector3, cal: float, k: float) -> void:
	var l := tk.hull_node.global_transform.basis.inverse() * dir
	var m := cal / 85.0 * k * 30.0 / float(tk.T.mass)
	tk.kick(-l.x * m, l.z * m)


## След попадания точно на поверхности модели: луч вдоль полёта снаряда по коллизиям танка.
func _mark_hit(tk: TankScript, hp: Vector3, dir: Vector3, kind: int, cal: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(hp - dir * 3.0 * D.UPM, hp + dir * 4.0 * D.UPM, 8)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var col := r.collider as Node
	if col == null or col.get_meta("tank", null) != tk:
		return
	var rad := (0.42 if kind == 2 else 0.32) * D.UPM * clampf(cal / 85.0, 0.7, 1.5)
	tk.add_mark(String(col.get_meta("part")), r.position, dir, rad, kind)


## За бронёй снаряд летит ещё ~3 м и задевает модули и экипаж на своём пути (каждый следующий
## слабее); осколки брони иногда ранят соседей по отделению. true — взорвалась боеукладка.
func _internal_damage(tk: TankScript, by: TankScript, hp: Vector3, dir: Vector3, dmg: float, part: String) -> bool:
	var seg := dir * 3.0 * D.UPM
	var inv_h := tk.hull_node.global_transform.affine_inverse()
	var inv_t := tk.up_node.global_transform.affine_inverse()
	var on_path: Array = []
	for it: Dictionary in tk.layout:
		var inv: Transform3D = inv_h if it.part == "hull" else inv_t
		var o := inv * hp
		var d := inv.basis * seg
		var t := -1.0
		if it.has("r"):
			var cl := Geometry3D.get_closest_point_to_segment(it.c, o, o + d)
			if cl.distance_to(it.c) < float(it.r):
				t = o.distance_to(cl) / d.length()
		else:
			var hit := slab(o, d, it.c - it.h, it.c + it.h)
			if not hit.is_empty():
				t = hit[0]
		if t >= 0.0:
			on_path.append([t, it.name])
	on_path.sort_custom(func(x, y): return x[0] < y[0])
	var boom := false
	var energy := 1.0
	var hurt := {}
	for e in on_path:
		var name: String = e[1]
		if TankScript.CREW.has(name):
			if randf() < 0.75:
				hurt[name] = true
		else:
			if _module_hit(tk, by, name, dmg * 0.42 * energy * randf_range(0.8, 1.2)):
				boom = true
			energy *= 0.75
	var comp := "top" if part == "turret" else "hull"
	for it: Dictionary in tk.layout:
		if it.has("r") and it.part == comp and not hurt.has(it.name) and randf() < 0.06:
			hurt[it.name] = true
	for name in hurt:
		_crew_hit(tk, by, name)
	return boom


## Непробитие тоже калечит то, что снаружи: орудие у маски, погон под башней, приборы на крыше.
func _outer_damage(tk: TankScript, by: TankScript, part: String, local: Vector3, zone: String, dmg: float) -> void:
	if part != "turret":
		return
	var h := tk.up_max.y
	var gp: Vector3 = tk.gun_pos0 if not tk.casemate else tk.tur_node.position - tk.up_node.position
	if zone == "front" and absf(local.z - gp.z) < 0.5 * D.UPM and absf(local.y - gp.y) < 0.45 * D.UPM:
		if randf() < 0.4:
			_module_hit(tk, by, "gun", dmg * 0.25 * randf_range(0.8, 1.2))
	elif not tk.casemate and local.y < 0.18 * h:
		if randf() < 0.3:
			_module_hit(tk, by, "turret", dmg * 0.22 * randf_range(0.8, 1.2))
	elif local.y > 0.8 * h and randf() < 0.2:
		_module_hit(tk, by, "optics", dmg * 0.3 * randf_range(0.8, 1.2))


## Урон модулю и его последствия: пожар от двигателя и баков, обездвиживание, сообщения.
## true — боеукладка взорвалась.
func _module_hit(tk: TankScript, by: TankScript, name: String, amount: float) -> bool:
	var st: Array = tk.hit_module(name, amount)
	var was: int = st[0]
	var now: int = st[1]
	if name == "engine" and randf() < (0.15 if now > 0 else 0.3):
		_start_fire(tk, by)
	elif name == "fuel" and randf() < 0.35:
		_start_fire(tk, by)
	if now == was:
		return false
	if name == "ammo" and now == 0 and randf() < 0.6:
		return true
	if name == "engine" and now == 0:
		tk.vel *= 0.4
		if tk.engine_fx == null:
			tk.engine_fx = fx.engine_smoke(tk.hull_node, Vector3(-float(tk.T.L) * 0.33, tk.hh + 0.5, 0))
		tk.engine_fx.emitting = true
	if tk.is_player:
		hud.alert(MOD_MSG[name][0 if now == 1 else 1], Color(D.AMBER) if now == 1 else Color("ff6a4a"))
	if by.is_player:
		_popup(tk, TankScript.NAMES[name], Color("ffb04a"), by)
	return false


func _crew_hit(tk: TankScript, by: TankScript, role_name: String) -> void:
	if not tk.wound(role_name):
		return
	if tk.is_player:
		hud.alert(CREW_MSG[role_name], Color("ff6a4a"))
	if by.is_player:
		_popup(tk, TankScript.NAMES[role_name], Color("ff8a6a"), by)


func _start_fire(tk: TankScript, by: TankScript) -> void:
	if tk.fire > 0.0:
		return
	stat.fire += 1
	tk.fire = FIRE_TIME
	tk.set_meta("fire_by", by)
	if tk.fire_fx == null:
		tk.fire_fx = fx.deck_fire(tk.hull_node, Vector3(-float(tk.T.L) * 0.35, tk.hh + 1.0, 0))
	tk.fire_fx.emitting = true
	_popup(tk, "ПОЖАР", Color("ff9a4a"), by)
	if tk.is_player:
		hud.alert("ПОЖАР!", Color("ff9a4a"))


func _popup(tk: TankScript, text: String, col: Color, by: TankScript) -> void:
	if by.is_player or tk == watch:
		texts.append({"pos": tk.top() + Vector3(0, 14, 0), "s": text, "col": col, "life": 1.4})


func _damage(tk: TankScript, amount: float, by: TankScript, tag: String) -> void:
	if not tk.alive or amount <= 0:
		return
	var real := minf(amount, ceilf(tk.hp))
	tk.hp -= amount
	tk.hit_t = clock
	by.dmg_dealt += real
	if by.team == 0 and tk.team == 1:
		tk.lit = maxf(tk.lit, 2.0)
	if by.is_player:
		dmg_done += real
	elif by.team == 0 and tk.team == 1 and spotter.get(tk) == player:
		spot_dmg += real
	if tag != "fire":
		for z in zones:
			if in_zone(tk, z) and z.prog[tk.team] > 0:
				if by.is_player and z.side == 0:
					def_pts += minf(z.prog[tk.team], 40.0)
				z.prog[tk.team] = maxf(0.0, z.prog[tk.team] - 40.0)
		var col := Color("ff8a6a") if tk.is_player else Color.WHITE
		var label := ("%s -%d" % [tag, int(amount)]) if tag != "" else "-%d" % int(amount)
		texts.append({"pos": tk.top() + Vector3(0, 8, 0), "s": label, "col": col, "life": 1.2})
		if tk == watch:
			shake = maxf(shake, 8.0)
	if tk.hp <= 0:
		kill(tk, by)


func _scorch(p: Vector3, size: float) -> void:
	var b := _ground_basis(p.x, p.z) * Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(size, 1, size))
	scorch_mm.set_instance_transform(scorch_i, Transform3D(b, Vector3(p.x, terra.height(p.x, p.z) + 0.25, p.z)))
	scorch_i = (scorch_i + 1) % SCORCH


func kill(tk: TankScript, by: TankScript) -> void:
	tk.alive = false
	tk.hp = 0
	tk.sp = 0
	tk.vel = Vector2.ZERO
	tk.fire = 0.0
	tk.make_wreck(randf() < 0.45)
	var at := tk.center() + Vector3(0, tk.hh * 0.5, 0)
	fx.explosion(at)
	fx.wreck_fire(at)
	_scorch(Vector3(tk.pos.x, 0, tk.pos.y), float(tk.T.L) * 1.4)
	sfx.play3d("explosion", at)
	var lp: Array = loops.get(tk, [])
	for p in lp:
		if p:
			(p as AudioStreamPlayer3D).stop()
	var burn := sfx.attach_loop(tk, "fire", 14.0, -8.0)
	get_tree().create_timer(25.0, false).timeout.connect(burn.queue_free)
	if by.is_player:
		kills += 1
	if mode == "supremacy":
		score[by.team] += 25.0
	if tk == watch:
		shake = 20.0
	hud.add_feed([[by.callsign, hud.team_color(by.team)], ["  ▸  ", Color("cfd3c0")], [tk.callsign, hud.team_color(tk.team)]])
	if tk.team == 0 and not tk.is_player:
		say("ally_down", tk.callsign)
	elif tk.team == 1 and by.team == 0 and not by.is_player:
		say("enemy_down")
	if tk.is_player:
		sniper = false
		hud.show_dead(true)


func nearest_foe(tk: TankScript, max_d: float, cone: float, dir_a: float) -> TankScript:
	var best: TankScript = null
	var bd := max_d
	for o: TankScript in tanks:
		if not o.alive or o.team == tk.team or not o.vis[tk.team]:
			continue
		var d := o.pos.distance_to(tk.pos)
		if cone > 0 and absf(ang_diff((o.pos - tk.pos).angle(), dir_a)) > cone:
			continue
		if d < bd:
			bd = d
			best = o
	return best


func lead_point(from: TankScript, tg: TankScript) -> Vector3:
	var tf := from.pos.distance_to(tg.pos) / float(from.T.shell_v) * 0.9
	var p := tg.pos + tg.vel * tf
	return Vector3(p.x, tg.ground + tg.hh * 0.7, p.y)


# ---------- Засвет ----------

## Видимость по прямой: рельеф и дома закрывают обзор, кусты прячут неподвижный танк.
func _update_spotting() -> void:
	if core:
		_update_spotting_native()
		return
	for e: TankScript in tanks:
		if not e.alive:
			continue
		for team in 2:
			if team == e.team:
				e.vis[team] = true
				continue
			var seen := e.lit > 0
			if not seen:
				var bush: bool = in_bush(e.pos) != null or _trees_near(e.pos, 26.0) >= 2
				for o: TankScript in tanks:
					if not o.alive or o.team != team:
						continue
					var d := o.pos.distance_to(e.pos)
					if d > (110.0 if bush else float(o.T.spot) * o.spot_k):
						continue
					if _los(o, e):
						seen = true
						if team == 0 and not spotter.has(e):
							spotter[e] = o
							if o == player:
								spotted_n += 1
						break
			e.vis[team] = seen
			if seen:
				intel[team][e] = [e.pos, clock]
			if team == 0 and seen and not reported.has(e) and clock > 3.0:
				reported[e] = true
				say("spot_tiger" if e.type_key.begins_with("tiger") else "spot", "", _clock_of(watch, e.pos))


## Засвет в C++: все пары разом, без кэша (луч по сетке высот дешёвый).
func _update_spotting_native() -> void:
	var n := tanks.size()
	var f := PackedFloat32Array()
	f.resize(n * 16)
	for i in n:
		var t: TankScript = tanks[i]
		var top := t.top()
		var cen := t.center()
		var k := i * 16
		f[k] = t.team
		f[k + 1] = 1.0 if t.alive else 0.0
		if not t.alive:
			continue
		f[k + 2] = t.lit
		f[k + 3] = t.pos.x
		f[k + 4] = t.pos.y
		f[k + 5] = top.x
		f[k + 6] = top.y + 2.0
		f[k + 7] = top.z
		f[k + 8] = top.x
		f[k + 9] = top.y
		f[k + 10] = top.z
		f[k + 11] = cen.x
		f[k + 12] = cen.y
		f[k + 13] = cen.z
		f[k + 14] = float(t.T.spot) * t.spot_k
		f[k + 15] = 1.0 if in_bush(t.pos) != null or _trees_near(t.pos, 26.0) >= 2 else 0.0
	var res: PackedInt32Array = core.spot(f, 110.0)
	for i in n:
		var e: TankScript = tanks[i]
		if not e.alive:
			continue
		for team in 2:
			if team == e.team:
				e.vis[team] = true
				continue
			var s := res[i * 2 + team]
			var seen := s != -1
			if s >= 0 and team == 0 and not spotter.has(e):
				spotter[e] = tanks[s]
				if tanks[s] == player:
					spotted_n += 1
			e.vis[team] = seen
			if seen:
				intel[team][e] = [e.pos, clock]
			if team == 0 and seen and not reported.has(e) and clock > 3.0:
				reported[e] = true
				say("spot_tiger" if e.type_key.begins_with("tiger") else "spot", "", _clock_of(watch, e.pos))


## Прямая видимость наблюдателя o на цель e. Ответ хранится, пока оба сдвинулись меньше чем на 8 единиц
## и прошло меньше секунды: стоящие и медленные танки не гоняют лучи заново каждую четверть секунды.
var los_cache := {}  # [o, e] → [видно, где o, где e, когда]


func _los(o: TankScript, e: TankScript) -> bool:
	var key := [o, e]
	var c = los_cache.get(key)
	if c != null and clock - float(c[3]) < 1.0 and (c[1] as Vector2).distance_squared_to(o.pos) < 64.0 \
			and (c[2] as Vector2).distance_squared_to(e.pos) < 64.0:
		return c[0]
	var eye := o.top() + Vector3(0, 2, 0)
	var v := clear_line(eye, e.top()) or clear_line(eye, e.center())
	los_cache[key] = [v, o.pos, e.pos, clock]
	return v


# ---------- Игрок ----------

func _cam_dir() -> Vector3:
	return Vector3(cos(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), sin(cam_yaw) * cos(cam_pitch))


func _player(p: TankScript, dt: float) -> void:
	var s: Vector2 = hud.move
	if Input.is_key_pressed(KEY_W):
		s.y -= 1
	if Input.is_key_pressed(KEY_S):
		s.y += 1
	if Input.is_key_pressed(KEY_A):
		s.x -= 1
	if Input.is_key_pressed(KEY_D):
		s.x += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		cam_yaw -= 1.6 * dt
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_RIGHT):
		cam_yaw += 1.6 * dt
	if Input.is_key_pressed(KEY_UP):
		cam_pitch -= 0.6 * dt
	if Input.is_key_pressed(KEY_DOWN):
		cam_pitch += 0.6 * dt
	var zoom := 0.3 if sniper else 1.0
	var dv: Vector2 = hud.take_cam_delta()
	cam_yaw = wrapf(cam_yaw + dv.x * SENS_X * zoom, -PI, PI)
	cam_pitch = clampf(cam_pitch + dv.y * SENS_Y * zoom, -0.3, 0.45)
	if sniper:
		# в прицеле нельзя опустить взгляд ниже, чем опускается пушка (с учётом наклона корпуса)
		var rel := ang_diff(p.tur, p.hull)
		var tilt := p.pitch * cos(rel) - p.roll * sin(rel)
		var lim: Array = p.T.elev
		cam_pitch = clampf(cam_pitch, -float(lim[1]) - tilt, -float(lim[0]) - tilt - 0.005)
	var thr := -s.y if absf(s.y) > 0.2 else 0.0
	var steer := s.x if absf(s.x) > 0.15 else 0.0
	if p.casemate and steer == 0.0:
		# САУ: если прицел ушёл за сектор наводки, корпус сам доворачивает за ним
		var off := ang_diff((Vector2(aim_point.x, aim_point.z) - p.pos).angle(), p.hull)
		if absf(off) > float(p.T.trav) * 0.9:
			var rev := p.sp < -1.0 or thr < -0.05
			steer = clampf(off / 0.25, -1.0, 1.0) * (-1.0 if rev else 1.0)
	drive(p, dt, thr, steer)
	# точка прицеливания: луч из камеры
	var o := _cam_origin(p)
	var dir := _cam_dir()
	var far := o + dir * 1800.0
	var wh := ray(o, far)
	var th := ray_tanks(o, far, p)
	aim_point = far
	var tw := 2.0
	if not wh.is_empty():
		aim_point = wh.position
		tw = o.distance_to(wh.position) / 1800.0
	if not th.is_empty() and th.t < tw:
		aim_point = th.pos
	if hud.auto_aim and not hud.dragging:
		var f := nearest_foe(p, 900.0, 0.3, cam_yaw)
		if f and clear_line(p.top(), f.center()):
			var lp := lead_point(p, f)
			var want_yaw := (Vector2(lp.x, lp.z) - Vector2(o.x, o.z)).angle()
			cam_yaw = turn_toward(cam_yaw, want_yaw, 1.4 * dt)
			var want_pitch := -atan2(lp.y - o.y, Vector2(lp.x, lp.z).distance_to(Vector2(o.x, o.z)))
			cam_pitch = move_toward(cam_pitch, clampf(want_pitch, -0.3, 0.45), 0.6 * dt)
	_aim_at(p, aim_point, dt)
	var lim2: Array = p.T.elev
	gun_limited = absf(p.gun_target - float(lim2[0])) < 0.0005 or absf(p.gun_target - float(lim2[1])) < 0.0005
	if p.casemate:
		var off2 := ang_diff((Vector2(aim_point.x, aim_point.z) - p.pos).angle(), p.hull)
		gun_limited = gun_limited or absf(off2) > float(p.T.trav) + 0.01
	_update_disp(p, dt)
	# куда на самом деле упадёт снаряд (по баллистике) и пробьёт ли
	var tr := trace(p.muzzle(), p.gun_dir() * float(p.T.shell_v), p)
	gun_point = tr.pos
	pen_hint = -1
	if tr.has("tank"):
		var tg: TankScript = tr.tank
		if tg.alive and tg.team != p.team:
			var arm := armor_at(tg, tr)
			var vdir: Vector3 = (tr.vel as Vector3).normalized()
			var cos_a := clampf(-vdir.dot(arm[1]), 0.0, 1.0)
			var ang := maxf(0.0, acos(cos_a) - deg_to_rad(5.0))
			var eff: float = float(arm[0]) / maxf(cos(ang), 0.12)
			var pen: float = float(p.T.pen) * (1.0 - 0.18 * clampf(p.pos.distance_to(tg.pos) / D.RANGE, 0.0, 1.0))
			if ang > deg_to_rad(70.0) and float(p.T.caliber) < float(arm[0]) * 3.0:
				pen_hint = 0
			elif pen > eff * 1.2:
				pen_hint = 2
			elif pen > eff * 0.8:
				pen_hint = 1
			else:
				pen_hint = 0
	if (hud.fire_req or hud.fire_held()) and p.rl <= 0 and p.can_fire():
		shoot(p)
	hud.fire_req = false
	# звук досылания снаряда перед готовностью
	if reload_cue and p.rl < 0.9 and p.rl > 0.0:
		reload_cue = false
		sfx.play2d("reload", -8.0)


func _cam_origin(w: TankScript) -> Vector3:
	# логика идёт 30 раз в секунду, а на экране танк сглажен между шагами — камера берёт
	# сглаженное положение, иначе дёргалась бы относительно него
	if sniper and w.alive:
		# прицел наводчика — рядом с осью орудия, поэтому без параллакса
		return w.gun_node.get_global_transform_interpolated() * Vector3(0.2 * D.UPM, 0.45 * D.UPM, 0.0)
	var wo := w.get_global_transform_interpolated().origin
	var pivot := Vector3(wo.x, wo.y + w.height + 7.0, wo.z)
	var dir := _cam_dir()
	var want: float = 70.0 + float(w.T.L) * 0.55
	var o := pivot - dir * want
	var hit := ray(pivot, o)
	if not hit.is_empty():
		o = hit.position + (pivot - hit.position).normalized() * 2.5
	o.y = maxf(o.y, terra.height(o.x, o.z) + 3.0)
	return o


# ---------- ИИ: маршруты ----------
# Сетка 25 × 25 единиц: клетки у построек непроходимы, крутые склоны и лес дороже.
# Вторая сетка — для движения под огнём: открытое поле там втрое дороже клеток
# рядом с укрытием (дом, куст, лес).

const NAV := 25.0
const WOOD := {"tree": true, "spruce": true, "apple": true}
var nav: AStarGrid2D
var nav_safe: AStarGrid2D
var nav_n := 0
var nav_solid := PackedByteArray()  # 1 — клетка занята постройкой
var cover_cells := PackedByteArray()  # 1 — рядом есть укрытие


func _build_nav() -> void:
	nav_n = int(ceil(D.WS / NAV))
	if core:
		var trees := PackedVector2Array()
		for pr in props:
			if pr.alive and WOOD.has(pr.kind):
				trees.append(pr.pos)
		var bf := PackedFloat32Array()
		for b in bushes:
			bf.append_array([b.pos.x, b.pos.y, b.r])
		var res: Array = core.nav_build(NAV, trees, bf)
		nav_solid = res[0]
		cover_cells = res[1]
		return
	nav_solid.resize(nav_n * nav_n)
	nav = _new_grid()
	nav_safe = _new_grid()
	cover_cells.resize(nav_n * nav_n)
	for y in nav_n:
		for x in nav_n:
			var c := Vector2i(x, y)
			var p := _cell_pos(c)
			if blocked_at(p, 13.0):
				nav.set_point_solid(c)
				nav_safe.set_point_solid(c)
				nav_solid[y * nav_n + x] = 1
				continue
			var slope := 1.0 - terra.normal(p.x, p.y, 14.0).y
			var w := 1.0 + clampf((slope - 0.06) * 14.0, 0.0, 3.0)
			var trees := _trees_near(p, 30.0)
			var cov := trees >= 2 or in_bush(p) != null
			if not cov:
				for o in _near(h_obst, p, 45.0):
					if o.solid and (o.r as Rect2).grow(45.0).has_point(p):
						cov = true
						break
			cover_cells[y * nav_n + x] = 1 if cov else 0
			w += 0.3 * mini(trees, 3)
			nav.set_point_weight_scale(c, w)
			nav_safe.set_point_weight_scale(c, w * (1.0 if cov else 3.0))


func _new_grid() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, nav_n, nav_n)
	g.cell_size = Vector2(NAV, NAV)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	return g


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / NAV), 0, nav_n - 1), clampi(int(p.y / NAV), 0, nav_n - 1))


static func _cell_pos(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * NAV


## Есть ли рядом укрытие: дом, куст, лес.
func covered(p: Vector2) -> bool:
	var c := _cell_of(p)
	return cover_cells[c.y * nav_n + c.x] == 1


## Живые деревья (не голые стволы) в радиусе: лес прячет танк, как куст.
func _trees_near(p: Vector2, r: float) -> int:
	var n := 0
	for pr in _near(h_prop, p, r):
		if pr.alive and WOOD.has(pr.kind) and pr.pos.distance_squared_to(p) < r * r:
			n += 1
	return n


## Ближайшая к c проходимая клетка (если c занята постройкой).
func _free_cell(c: Vector2i) -> Vector2i:
	if not _solid(c):
		return c
	for r in range(1, 8):
		for k in range(-r, r + 1):
			for a: Vector2i in [Vector2i(c.x + k, c.y - r), Vector2i(c.x + k, c.y + r), Vector2i(c.x - r, c.y + k), Vector2i(c.x + r, c.y + k)]:
				if _in_nav(a) and not _solid(a):
					return a
	return c


func _in_nav(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < nav_n and c.y < nav_n


func _solid(c: Vector2i) -> bool:
	return nav_solid[c.y * nav_n + c.x] == 1


## Ближайшая клетка с укрытием в радиусе r; null — нет.
func _cover_near(p: Vector2, r: float):
	var c := _cell_of(p)
	var best = null
	var bd := 1e9
	var n := int(r / NAV)
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var a := Vector2i(c.x + dx, c.y + dy)
			if not _in_nav(a) or _solid(a) or cover_cells[a.y * nav_n + a.x] == 0:
				continue
			var q := _cell_pos(a)
			var d := q.distance_squared_to(p)
			if d < bd:
				bd = d
				best = q
	return best


## Можно ли проехать по прямой (с запасом на ширину танка).
func _straight(a: Vector2, b: Vector2, r: float) -> bool:
	if core:
		return core.straight(a, b, r)
	var n := int(a.distance_to(b) / 12.0) + 1
	for s in range(1, n + 1):
		if blocked_at(a.lerp(b, float(s) / n), r):
			return false
	return true


## Маршрут A*, спрямлённый: из цепочки клеток остаются точки, между которыми едут по прямой.
func nav_path(from: Vector2, to: Vector2, safe: bool, r: float) -> PackedVector2Array:
	if core:
		return core.nav_path(from, to, safe, r)
	var g := nav_safe if safe else nav
	var ids := g.get_id_path(_free_cell(_cell_of(from)), _free_cell(_cell_of(to)), true)
	var out := PackedVector2Array()
	if ids.size() < 2:
		out.append(to)
		return out
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(_cell_pos(id))
	if not blocked_at(to, r):
		pts[pts.size() - 1] = to
	var cur := from
	var k := 1
	while k < pts.size():
		var far := k
		for j in range(mini(pts.size() - 1, k + 14), k, -1):
			if _straight(cur, pts[j], r * 0.8):
				far = j
				break
		out.append(pts[far])
		cur = pts[far]
		k = far + 1
	return out


## Задать боту маршрут; не пересчитывается, пока цель та же и маршрут свежий. Сам поиск идёт
## в фоновом потоке: бот едет по старому маршруту, пока не придёт новый (обычно через кадр).
func _set_route(b: TankScript, to: Vector2, safe: bool) -> void:
	if b.b_path_wait:
		return
	if not b.b_path.is_empty() and b.b_path_to.distance_to(to) < 50.0 and safe == b.b_path_safe and clock < b.b_path_t:
		return
	if nav_sync:
		_apply_route(b, nav_path(b.pos, to, safe, radius(b)), to, safe)
		return
	b.b_path_wait = true
	nav_mx.lock()
	nav_jobs.append([b, b.pos, to, safe, radius(b)])
	nav_mx.unlock()
	nav_sem.post()


# Фоновый поток маршрутов: берёт заявки по одной (сетка A* не любит одновременных поисков).
var nav_thread: Thread
var nav_sem: Semaphore
var nav_mx: Mutex
var nav_jobs: Array = []  # [бот, откуда, куда, под огнём, радиус]
var nav_done: Array = []  # [бот, маршрут, куда, под огнём]
var nav_quit := false
var nav_sync := false  # прогоны без кадров (simulate): маршрут сразу, как в игре к следующему кадру


func _start_nav_thread() -> void:
	nav_sem = Semaphore.new()
	nav_mx = Mutex.new()
	nav_thread = Thread.new()
	nav_thread.start(_nav_worker)


func _nav_worker() -> void:
	while true:
		nav_sem.wait()
		nav_mx.lock()
		if nav_quit:
			nav_mx.unlock()
			return
		var job = nav_jobs.pop_front() if not nav_jobs.is_empty() else null
		nav_mx.unlock()
		if job == null:
			continue
		var path := nav_path(job[1], job[2], job[3], job[4])
		nav_mx.lock()
		nav_done.append([job[0], path, job[2], job[3]])
		nav_mx.unlock()


## Готовые маршруты из фонового потока — ботам (в начале шага логики).
func _take_routes() -> void:
	nav_mx.lock()
	var done := nav_done
	nav_done = []
	nav_mx.unlock()
	for r in done:
		_apply_route(r[0], r[1], r[2], r[3])


func _apply_route(b: TankScript, path: PackedVector2Array, to: Vector2, safe: bool) -> void:
	b.b_path = path
	b.b_pi = 0
	b.b_path_to = to
	b.b_path_safe = safe
	b.b_path_t = clock + randf_range(5.0, 8.0)
	b.b_path_wait = false


func _exit_tree() -> void:
	if nav_thread and nav_thread.is_started():
		nav_mx.lock()
		nav_quit = true
		nav_mx.unlock()
		nav_sem.post()
		nav_thread.wait_to_finish()


func _route_vec(b: TankScript) -> Vector2:
	if b.b_path.is_empty():
		return Vector2.ZERO
	while b.b_pi < b.b_path.size() - 1 and b.pos.distance_to(b.b_path[b.b_pi]) < 34.0:
		b.b_pi += 1
	var dv := b.b_path[b.b_pi] - b.pos
	var l := dv.length()
	if b.b_pi == b.b_path.size() - 1 and l < 22.0:
		return Vector2.ZERO
	return dv / l * minf(1.0, 0.35 + l / 60.0)


# ---------- ИИ: тактика команды ----------
# Команда делится на группы по трём направлениям. Группа идёт рубежами: на следующий —
# когда большинство дошло до текущего (отставших ждут, но не дольше 30 с) и своих там
# больше, чем замеченных врагов. Проигранное направление группа оставляет и отходит в центр,
# выигранное — разворачивается во фланг центру. Каждая команда помнит, где видела врагов.

const STAGES := [0.1, 0.27, 0.4, 0.5, 0.6, 0.74, 0.9]  # рубежи: доля пути от своего края к чужому
const LANE_PREF := {  # склонность классов к направлениям: высота, центр, застройка
	"ЛТ": {"hill": 0.6, "mid": 1.0, "town": 0.2}, "СТ": {"hill": 1.0, "mid": 0.8, "town": 0.5},
	"ТТ": {"hill": 0.35, "mid": 0.6, "town": 1.0}, "ПТ": {"hill": 1.0, "mid": 0.75, "town": 0.25}}
var squads := [{}, {}]  # команда → направление → {stage, t, n0}
var intel := [{}, {}]  # команда → враг → [где видели, когда]
var squad_t := 0.0


## Распределяет ботов по направлениям: каждый — куда склонен его класс,
## но одно направление не забивается, пока другие пусты.
func _assign_lanes(team: int) -> void:
	var cnt := {"hill": 0, "mid": 0, "town": 0}
	var bots: Array = []
	for tk: TankScript in tanks:
		if tk.team != team:
			continue
		tk.b_cls = "ПТ" if String(tk.T.short) == "САУ" else String(tk.T.short)
		tk.b_off = Vector2(randf_range(-90, 90), randf_range(-50, 50))
		if tk.is_player:
			cnt.mid += 1
		else:
			bots.append(tk)
	bots.shuffle()
	for tk: TankScript in bots:
		var best := "mid"
		var bs := -1e9
		var pref: Dictionary = LANE_PREF.get(tk.b_cls, LANE_PREF["СТ"])
		for ln in cnt:
			var sc: float = float(pref[ln]) - 0.55 * float(cnt[ln]) + randf_range(-0.2, 0.2)
			if sc > bs:
				bs = sc
				best = ln
		tk.b_lane = best
		tk.b_side = -1.0 if _lane_x(best) < D.WS * 0.5 else 1.0
		cnt[best] += 1
	for ln in cnt:
		squads[team][ln] = {"stage": 0, "t": 0.0, "n0": cnt[ln]}


func _lane_x(ln: String) -> float:
	return float(lanes.get(ln, D.WS * 0.5))


func _lane_of(x: float) -> String:
	var best := "mid"
	var bd := 1e9
	for ln in ["hill", "mid", "town"]:
		var d := absf(x - _lane_x(ln))
		if d < bd:
			bd = d
			best = ln
	return best


## Последний рубеж: в «Превосходстве» и встречном бою группы держатся у точек.
func _max_stage() -> int:
	return STAGES.size() - 1 if mode == "standard" else 4


## Точка рубежа направления для команды.
func stage_point(team: int, ln: String, stage: int) -> Vector2:
	var t: float = STAGES[clampi(stage, 0, STAGES.size() - 1)]
	var y := lerpf(D.WS - 300.0, 300.0, t) if team == 0 else lerpf(300.0, D.WS - 300.0, t)
	return Vector2(_lane_x(ln), y)


## Силы на направлении: боевой вес × прочность. Свои — по месту, враги — по памяти команды.
func _lane_power(team: int, ln: String) -> Vector2:
	var ours := 0.0
	var theirs := 0.0
	for tk: TankScript in tanks:
		if not tk.alive:
			continue
		var w := float(D.pts(tk.type_key, year)) * (0.4 + 0.6 * tk.hp / tk.max_hp)
		if tk.team == team:
			if (tk.b_lane if not tk.is_player or autopilot else _lane_of(tk.pos.x)) == ln:
				ours += w
		elif intel[team].has(tk):
			var it: Array = intel[team][tk]
			if clock - float(it[1]) < 25.0 and _lane_of((it[0] as Vector2).x) == ln:
				theirs += w
	return Vector2(ours, theirs)


## Раз в секунду: решает, идти ли группам вперёд, держаться или отходить.
func _squads_update() -> void:
	var late := clock > D.TIME_LIMIT * 0.6
	for team in 2:
		for ln in squads[team]:
			var sq: Dictionary = squads[team][ln]
			var mem: Array = []
			for tk: TankScript in tanks:
				if tk.alive and tk.team == team and (not tk.is_player or autopilot) and tk.b_lane == ln:
					mem.append(tk)
			if mem.is_empty():
				continue
			var pw := _lane_power(team, ln)
			sq.t += 1.0
			var sp := stage_point(team, ln, sq.stage)
			var near := 0
			for tk: TankScript in mem:
				if tk.pos.distance_to(sp + tk.b_off) < 190.0:
					near += 1
			var top := _max_stage()
			var losing: bool = (pw.y > pw.x * 1.7 and (mem.size() < int(sq.n0) or clock > 60.0)) or (pw.y > pw.x and mem.size() * 2 < int(sq.n0))
			if losing:
				# направление проиграно: отход на рубеж назад, с ближнего — в центр
				if sq.stage > 1 and sq.t > 6.0:
					sq.stage -= 1
					sq.t = 0.0
				elif ln != "mid" and sq.stage <= 1:
					_move_squad(team, ln, mem, int(sq.stage))
			elif sq.stage >= top and pw.y == 0.0 and ln != "mid" and mode == "standard":
				# направление взято: группа разворачивается во фланг центру
				_move_squad(team, ln, mem, top - 2)
			elif sq.stage < top and (near * 5 >= mem.size() * 3 or sq.t > (12.0 if late else 30.0)) \
					and (pw.y == 0.0 or pw.x >= pw.y * (0.85 if late else 1.25)):
				sq.stage += 1
				sq.t = 0.0


## Группа уходит в центр; если там никого, центр продолжает с её рубежа.
func _move_squad(team: int, from: String, mem: Array, stage: int) -> void:
	var msq: Dictionary = squads[team]["mid"]
	var alive := false
	for tk: TankScript in tanks:
		if tk.alive and tk.team == team and not tk.is_player and tk.b_lane == "mid":
			alive = true
	if not alive:
		msq.stage = maxi(0, stage)
		msq.t = 0.0
	for tk: TankScript in mem:
		tk.b_lane = "mid"
		tk.b_path_t = 0.0
	msq.n0 = int(msq.n0) + mem.size()
	squads[team][from].n0 = 0


## Видел ли кто-то из команды врага рядом недавно.
func _foe_near(b: TankScript, r: float) -> bool:
	for e in intel[b.team]:
		var it: Array = intel[b.team][e]
		if e.alive and clock - float(it[1]) < 15.0 and b.pos.distance_to(it[0]) < r:
			return true
	return false


## Последнее известное место ближайшего врага (туда бот заранее поворачивает башню).
func _foe_guess(b: TankScript):
	var best = null
	var bd := 1100.0
	for e in intel[b.team]:
		var it: Array = intel[b.team][e]
		if not e.alive or clock - float(it[1]) > 30.0:
			continue
		var d := b.pos.distance_to(it[0])
		if d < bd:
			bd = d
			best = it[0]
	return best


## Есть ли рядом с точкой союзник (кроме b).
func _ally_near(p: Vector2, team: int, r: float, b: TankScript) -> bool:
	for o: TankScript in tanks:
		if o != b and o.alive and o.team == team and o.pos.distance_squared_to(p) < r * r:
			return true
	return false


## Куст ближе всего к точке, в радиусе r, ещё не занятый своим.
func _bush_near(p: Vector2, r: float, b: TankScript):
	var best = null
	var bd := r * r
	for bsh in _near(h_bush, p, r):
		var d: float = p.distance_squared_to(bsh.pos)
		if d >= bd:
			continue
		var taken := false
		for o: TankScript in tanks:
			if o != b and o.alive and o.team == b.team and o.pos.distance_squared_to(bsh.pos) < 900.0:
				taken = true
				break
		if not taken:
			bd = d
			best = bsh.pos
	return best


func _lane_zone(ln: String):
	var best = null
	var bd := 1e9
	for z in zones:
		var d := absf(z.pos.x - _lane_x(ln))
		if d < bd:
			bd = d
			best = z
	return best


## Куда ехать без цели: защита базы, точки режима, рубеж своей группы, засада, разведка.
func _plan(b: TankScript) -> Vector2:
	var my := b.team
	var en := 1 - my
	var stage: int = squads[my].get(b.b_lane, {"stage": 0}).stage
	b.b_zone = null
	if mode == "standard":
		var own = zones[0] if zones[0].side == my else zones[1]
		var foe = zones[1] if own == zones[0] else zones[0]
		var d_own: float = b.pos.distance_to(own.pos)
		# захват своей базы сбивают ближние, а при сильном захвате — все, кто успеет
		if own.prog[en] > 0 and (b.role == "def" or d_own < 1100.0 or (own.prog[en] > 35.0 and d_own < 2100.0)):
			b.b_zone = own
			return own.pos + b.b_off * 0.4
		if b.role == "def" and clock < 150.0:
			return stage_point(my, "mid", 0) + b.b_off
		# к концу боя вся команда идёт на базу врага, чтобы не кончить ничьей
		if stage >= _max_stage() or alive_count(en) <= 1 or clock > D.TIME_LIMIT * 0.72:
			b.b_zone = foe
			return foe.pos + b.b_off * 0.4
	elif mode == "encounter":
		var z = zones[0]
		# на точку — не раньше, чем группы сойдутся в центре: первым минутам место для боя
		if (stage >= 3 and clock > 75.0) or z.prog[en] > 0 or alive_count(en) <= 1:
			b.b_zone = z
			return z.pos + b.b_off * 0.4
	else:
		for z in zones:
			if z.side == my and z.prog[en] > 0 and b.pos.distance_to(z.pos) < 900.0:
				b.b_zone = z
				return z.pos + b.b_off * 0.4
		var lz = _lane_zone(b.b_lane)
		if stage >= 3 and (lz.side != my or lz.n[en] > 0):
			b.b_zone = lz
			return lz.pos + b.b_off * 0.4
	if b.b_cls == "ЛТ":
		# разведчик: куст впереди группы; засветили — откатывается на рубеж назад
		if clock < b.b_back_t:
			return stage_point(my, b.b_lane, maxi(stage - 1, 0)) + b.b_off
		var fp := stage_point(my, b.b_lane, mini(stage + 1, 4))
		var bsh = _bush_near(fp, 280.0, b)
		return bsh if bsh != null else fp + b.b_off
	if b.b_cls == "ПТ":
		# ПТ: засада в кусте или в лесу на рубеж позади группы
		var op := stage_point(my, b.b_lane, maxi(stage - 1, 0))
		var bsh = _bush_near(op, 260.0, b)
		if bsh != null:
			return bsh
		var cv = _cover_near(op + b.b_off, 150.0)
		return cv if cv != null else op + b.b_off
	return stage_point(my, b.b_lane, stage) + b.b_off


# ---------- ИИ: бой ----------

## Приведённая толщина брони цели со стороны стрелка: лоб или борт — по тому, как цель к нему стоит.
static func _armor_toward(tg: TankScript, from: Vector2) -> float:
	var A: Array = tg.T.armor
	var off := absf(ang_diff((from - tg.pos).angle(), tg.hull))
	if off < 0.9:
		return float(A[0]) / cos(float(tg.T.slope)) / maxf(cos(off), 0.3)
	if off > PI - 0.9:
		return float(A[2])
	return float(A[1]) / cos(float(tg.T.side_slope)) / maxf(sin(off), 0.5)


## Выбор цели: ближе, слабее бронёй, меньше прочности; по тому, кого уже обстреливают свои, —
## охотнее (фокус огня); текущую цель бот не бросает без причины.
func _choose_target(b: TankScript) -> TankScript:
	var best: TankScript = null
	var bs := 1e9
	var pen: float = b.T.pen
	for o: TankScript in tanks:
		if not o.alive or o.team == b.team or not o.vis[b.team]:
			continue
		var d := o.pos.distance_to(b.pos)
		var sc := d / float(b.T.pref)
		if pen * 0.95 < _armor_toward(o, b.pos):
			sc += 1.6
		sc += o.hp / o.max_hp * 0.8
		for a: TankScript in tanks:
			if a != b and a.alive and a.team == b.team and a.b_tg == o:
				sc -= 0.3
		if o == b.b_tg:
			sc -= 0.4
		if sc < bs:
			bs = sc
			best = o
	return best


## Место рядом: hull — где цель видит только башню («корпус за гребнем»), иначе — где не видит
## танк вовсе. null — такого места нет.
func _find_spot(b: TankScript, eye: Vector3, hull: bool):
	var r := radius(b)
	var to := (Vector2(eye.x, eye.z) - b.pos).angle()
	var base := to if hull else to + PI
	var best = null
	var bd := 1e9
	for i in 13:
		var p := b.pos
		if i > 0:
			var a := base + (float(i) - 6.5) * (0.3 if hull else 0.45)
			p = b.pos + Vector2.from_angle(a) * (25.0 + float(i % 3) * 30.0)
			if p.x < 150.0 or p.y < 150.0 or p.x > D.WS - 150.0 or p.y > D.WS - 150.0 or blocked_at(p, r):
				continue
		var g := terra.height(p.x, p.y)
		var top := Vector3(p.x, g + b.height * 0.92, p.y)
		if hull:
			if not clear_line(eye, top) or clear_line(eye, Vector3(p.x, g + b.height * 0.42, p.y)):
				continue
		elif clear_line(eye, top):
			continue
		var d := b.pos.distance_to(p)
		if d < bd:
			bd = d
			best = p
		if i == 0:
			break
	return best


## Решения бота (5 раз в секунду): цель, укрытие, засада, маршрут.
func _think(b: TankScript) -> void:
	var T := b.T
	var en := 1 - b.team
	var nt := _choose_target(b)
	if nt != b.b_tg:
		b.b_peek = null
		b.b_spot = null
		b.b_spot_kind = ""
	b.b_tg = nt
	var tg: TankScript = nt
	var spotted: bool = b.vis[en]
	var danger := spotted and (clock - b.hit_t < 8.0 or _foe_near(b, 1000.0))
	b.b_hold = false
	b.b_adv = not danger or covered(b.pos)
	if b.b_cls == "ЛТ" and spotted and clock > b.b_back_t + 4.0 and _foe_near(b, 750.0):
		b.b_back_t = clock + randf_range(7.0, 11.0)
	if tg:
		b.b_los = clear_line(b.muzzle(), tg.center())
		if b.b_los and (b.b_peek == null or b.vel.length() < 4.0):
			b.b_peek = b.pos
	# разведчик после засвета откатывается, отстреливаясь, — решения о бое не принимает;
	# в конце стандартного боя все, кроме сцепившихся вплотную, едут на базу и стреляют на ходу
	var rush := mode == "standard" and clock > D.TIME_LIMIT * 0.72 and tg != null and tg.pos.distance_to(b.pos) > 250.0
	if tg and not (b.b_cls == "ЛТ" and clock < b.b_back_t) and not rush:
		var d := b.pos.distance_to(tg.pos)
		var eye := tg.top() + Vector3(0, 2, 0)
		var low := b.hp < b.max_hp * 0.3
		if b.b_zone != null and in_zone(b, b.b_zone) and b.b_zone.side != b.team:
			b.b_act = "hold"
			return
		# засада: ПТ и разведчик в кусте или в лесу стоят и не выдают себя дальними выстрелами
		var hidden := in_bush(b.pos) != null or _trees_near(b.pos, 26.0) >= 2
		if (b.b_cls == "ПТ" or b.b_cls == "ЛТ") and hidden and not spotted:
			# огонь открывает, когда цель подошла, добивает или уже бьётся с нашими, или когда захватывают базу
			var base_threat := false
			for z in zones:
				if z.side == b.team and z.prog[en] > 0:
					base_threat = true
			b.b_hold = not base_threat and d > (300.0 if b.b_cls == "ЛТ" else 450.0) and tg.hp > float(T.dmg) * 1.3 \
				and not _ally_near(tg.pos, b.team, 380.0, b)
			if b.b_los or _plan(b).distance_to(b.pos) < 200.0:
				b.b_act = "hold"
				return
		# перезарядка: за укрытие (лёгкая броня и долгая перезарядка, мало прочности или засвеченная ПТ)
		var hide: bool = b.b_los and d < 1000.0 and b.rl > 1.4 and not b.immobile and b.track_broken <= 0.0 \
			and (low or (float(T.reload) >= 3.5 and not T.armored and not b.casemate) or (b.b_cls == "ПТ" and spotted and float(T.reload) >= 4.0))
		if hide:
			if b.b_spot_kind != "cover" or clock > b.b_spot_t:
				b.b_spot = _find_spot(b, eye, false)
				b.b_spot_kind = "cover"
				b.b_spot_t = clock + 2.5
			if b.b_spot != null:
				b.b_act = "spot"
				return
		elif b.b_spot_kind == "cover":
			b.b_spot = null
			b.b_spot_kind = ""
		# корпус за гребнем: башенный танк ищет рядом место, откуда противнику видна только башня
		if b.b_los and not b.casemate and b.b_cls != "ЛТ" and d > 220.0 and not hide:
			if b.b_spot_kind != "hull" or clock > b.b_spot_t:
				b.b_spot = _find_spot(b, eye, true)
				b.b_spot_kind = "hull"
				b.b_spot_t = clock + 3.0
			if b.b_spot != null:
				b.b_act = "spot"
				return
		if b.b_los:
			b.b_act = "fight"
			return
		if d < float(T.pref) + 300.0:
			# из пушки цель не видна: выехать туда, откуда видел её, или подобраться маршрутом
			var to: Vector2 = tg.pos
			if b.b_peek != null and (b.b_peek as Vector2).distance_to(b.pos) > 25.0:
				to = b.b_peek
			_set_route(b, to, danger)
			b.b_act = "route"
			return
	if tg == null:
		b.b_los = false
	# без цели: план группы; под огнём на открытом месте — сначала в ближайшее укрытие
	var goal := _plan(b)
	b.b_goal = goal
	if danger and clock - b.hit_t < 6.0 and not covered(b.pos):
		var cv = _cover_near(b.pos, 175.0)
		if cv != null:
			goal = cv
	if b.pos.distance_to(goal) < 30.0:
		b.b_act = "hold"
	else:
		_set_route(b, goal, danger)
		b.b_act = "route"


func _bot(b: TankScript, dt: float) -> void:
	var T := b.T
	_bot_cons(b, dt)
	b.b_think -= dt
	if b.b_think <= 0.0:
		# далёкий от камеры бот, которого не видят и у которого нет цели, думает реже
		var calm: bool = b.b_tg == null and not b.vis[1 - b.team] and b.pos.distance_squared_to(watch.pos) > 1200.0 * 1200.0
		b.b_think = randf_range(0.5, 0.6) if calm else randf_range(0.18, 0.24)
		var t0 := Time.get_ticks_usec()
		_think(b)
		_prof("боты: решения", t0)
	var tg: TankScript = b.b_tg if b.b_tg != null and b.b_tg.alive else null
	var mv := Vector2.ZERO
	var facing := false
	var face_off := 0.0
	b.b_st -= dt
	if b.b_st <= 0:
		b.b_strafe *= -1.0
		b.b_st = randf_range(2.0, 4.5)
	match b.b_act:
		"route":
			mv = _route_vec(b)
		"spot":
			if b.b_spot != null:
				var dv: Vector2 = (b.b_spot as Vector2) - b.pos
				if dv.length() > 8.0:
					mv = dv.normalized() * clampf(dv.length() / 30.0, 0.4, 1.0)
		"fight":
			if tg:
				var d := b.pos.distance_to(tg.pos)
				var ang := (tg.pos - b.pos).angle()
				var pref: float = float(T.pref) + (180.0 if b.hp < b.max_hp * 0.3 else 0.0)
				var fwd := 1.0 if d > pref + 70.0 and b.b_adv else (-1.0 if d < pref - 100.0 else 0.0)
				var strafe := 0.6
				if b.rl < 1.2:
					strafe = 0.0  # перед выстрелом останавливается, чтобы свестись
				if b.casemate or T.armored:
					strafe = 0.0
				mv = Vector2.from_angle(ang) * fwd + Vector2.from_angle(ang + PI / 2) * b.b_strafe * strafe
	# стоя на месте, САУ держит цель в секторе наводки, а танк с толстым лбом встаёт ромбом
	if tg and mv.length() < 0.1 and (b.casemate or T.armored):
		var ang := (tg.pos - b.pos).angle()
		var off := ang_diff(ang, b.hull)
		var keep: float = float(T.trav) * 0.6 if b.casemate else 0.3
		if not b.casemate and b.b_los:
			off = ang_diff(ang + b.b_side * 0.42, b.hull)
			keep = 0.12
		if absf(off) > keep:
			facing = true
			face_off = off
	if tg:
		var d := b.pos.distance_to(tg.pos)
		# цель не пробить в лоб — бьёт по гусеницам, чтобы обездвижить
		var lp := lead_point(b, tg)
		if float(T.pen) * 1.1 < _armor_toward(tg, b.pos):
			lp.y = tg.ground + tg.th * 0.55
		_aim_at(b, lp, dt)
		var aligned := absf(ang_diff((Vector2(lp.x, lp.z) - b.pos).angle(), b.tur)) < 0.03 and absf(b.gun_pitch - b.gun_target) < 0.015
		if b.rl <= 0 and d < D.RANGE * 0.85 and aligned and b.b_los and not b.b_hold and b.disp < float(T.disp) * 3.0 and b.can_fire():
			shoot(b)
			b.b_peek = b.pos
	else:
		# башня — туда, где последний раз видели врага, иначе по ходу
		var guess = _foe_guess(b)
		var look: Vector2 = guess if guess != null else b.pos + (mv if mv.length() > 0.1 else Vector2.from_angle(b.tur)) * 200.0
		_aim_at(b, Vector3(look.x, terra.height(look.x, look.y) + b.hh, look.y), dt)
	var m := mv.length()
	if m > 0.1:
		var a := mv.angle()
		var r := radius(b)
		var probe := 60.0
		if b.b_act == "route" and not b.b_path.is_empty():
			probe = clampf(b.pos.distance_to(b.b_path[b.b_pi]), 20.0, 60.0)
		if b.b_av <= 0 and blocked_at(b.pos + Vector2.from_angle(a) * probe, r):
			var f1 := not blocked_at(b.pos + Vector2.from_angle(a + 0.9) * probe, r)
			var f2 := not blocked_at(b.pos + Vector2.from_angle(a - 0.9) * probe, r)
			if f1 and not f2:
				b.b_av_dir = 1.0
			elif f2 and not f1:
				b.b_av_dir = -1.0
			else:
				b.b_av_dir = 1.0 if randf() < 0.5 else -1.0
			b.b_av = 1.0
		if b.b_av > 0:
			b.b_av -= dt
			a += b.b_av_dir * 1.1
			mv = Vector2.from_angle(a) * maxf(m, 0.5)
	b.b_pt -= dt
	if b.b_pt <= 0:
		if m > 0.3 and b.pos.distance_to(b.b_last) < 6.0 and b.track_broken <= 0.0:
			# застрял: объезд и новый маршрут
			b.b_av = 1.8
			b.b_av_dir *= -1.0
			b.b_path_t = 0.0
		b.b_last = b.pos
		b.b_pt = 1.5
	if facing:
		drive(b, dt, 0.0, clampf(face_off / 0.3, -1.0, 1.0))
	else:
		_drive_vec(b, dt, mv)
	_update_disp(b, dt)


## Бот применяет снаряжение не сразу, а как экипаж сообразит: через 1–3 с после беды.
## Ремкомплект — на гусеницу и уничтоженный двигатель или орудие, аптечку — на наводчика,
## заряжающего и мехвода, огнетушитель — сразу на пожар.
func _bot_cons(b: TankScript, dt: float) -> void:
	for c in b.cons:
		var need := float(b.cons[c]) <= 0.0 and b.cons_needed(c)
		if need and c == "repair":
			need = b.track_broken > 0.0 or b.mod_state("engine") == 0 or b.mod_state("gun") == 0
		elif need and c == "medkit":
			need = not (b.crew_ok.gunner and b.crew_ok.loader and b.crew_ok.driver)
		if not need:
			b.b_cons_t.erase(c)
			continue
		if not b.b_cons_t.has(c):
			b.b_cons_t[c] = randf_range(0.6, 1.5) if c == "ext" else randf_range(1.0, 3.0)
		b.b_cons_t[c] -= dt
		if b.b_cons_t[c] <= 0.0:
			b.b_cons_t.erase(c)
			b.use_cons(c)


## Игрок применяет снаряжение (кнопка на экране или клавиши 1–3).
func use_cons(name: String) -> void:
	if over or not player.alive or not player.use_cons(name):
		return
	var msg := {"repair": "МОДУЛИ ОТРЕМОНТИРОВАНЫ", "medkit": "ЭКИПАЖ В СТРОЮ", "ext": "ПОЖАР ПОТУШЕН"}
	hud.alert(msg[name], Color("9ad07a"))
	sfx.play2d("reload", -10.0)


func _drive_vec(tk: TankScript, dt: float, mv: Vector2) -> void:
	var m := minf(1.0, mv.length())
	if m < 0.12:
		drive(tk, dt, 0.0, 0.0)
		return
	var want := mv.angle()
	var d := ang_diff(want, tk.hull)
	var dir := 1.0
	if absf(d) > PI * 0.6:
		d = ang_diff(want + PI, tk.hull)
		dir = -1.0
	var steer := clampf(d / 0.35, -1.0, 1.0)
	drive(tk, dt, dir * m * maxf(0.1, cos(d)), steer * dir)


# ---------- Режимы ----------

static func in_zone(tk: TankScript, z) -> bool:
	return tk.pos.distance_squared_to(z.pos) < float(z.r) * float(z.r)


func _zones_update(dt: float) -> void:
	for z in zones:
		z.n = [0, 0]
		for tk: TankScript in tanks:
			if tk.alive and in_zone(tk, z):
				z.n[tk.team] += 1
		for side in 2:
			var other := 1 - side
			if z.side != side and z.n[side] > 0 and z.n[other] == 0:
				z.prog[side] = minf(100.0, z.prog[side] + dt * D.CAP_RATE * mini(3, z.n[side]))
				if side == 0 and player.alive and in_zone(player, z):
					cap_pts += dt * D.CAP_RATE
			elif z.n[side] == 0:
				z.prog[side] = maxf(0.0, z.prog[side] - dt * 3.0)
			if z.prog[side] >= 100.0:
				if mode == "supremacy":
					z.side = side
					z.prog = [0.0, 0.0]
					hud.add_feed([["Точка %s захвачена" % z.label, hud.team_color(side)]])
					sfx.play2d("capture", -6.0)
				elif not over:
					if mode == "encounter":
						finish("win" if side == 0 else "lose", "Вы захватили базу" if side == 0 else "Противник захватил базу")
					else:
						finish("win" if side == 0 else "lose", "База противника захвачена" if side == 0 else "Ваша база захвачена")
	if mode == "supremacy":
		for z in zones:
			if z.side >= 0:
				score[z.side] += dt * 2.0
		if not over:
			if score[0] >= D.SUP_GOAL:
				finish("win", "Набрано 600 очков")
			elif score[1] >= D.SUP_GOAL:
				finish("lose", "Противник набрал 600 очков")


## Команда «вперёд» после брифинга, «нас мало», тревога о захвате базы.
func _radio_events() -> void:
	if radio_start >= 0.0 and clock >= radio_start:
		radio_start = -1.0
		say("start")
	if not said.has("last") and teams[0].size() >= 4 and alive_count(0) == 2 and alive_count(1) > 2:
		said["last"] = true
		say("last")
	for z in zones:
		if z.side == 0 and z.prog[1] > 6.0:
			say("our_base")
		elif z.side != 0 and z.prog[0] > 6.0:
			say("their_base")


func finish(res: String, why: String) -> void:
	over = true
	result = res
	reason = why
	over_t = 0.0
	speed = 1


func alive_count(team: int) -> int:
	var n := 0
	for tk: TankScript in tanks:
		if tk.alive and tk.team == team:
			n += 1
	return n


# ---------- Шаг симуляции ----------

func _update(dt: float) -> void:
	clock += dt
	_take_routes()
	for tk: TankScript in tanks:
		tk.travel_prev[0] = tk.travel[0]
		tk.travel_prev[1] = tk.travel[1]
	var t0 := Time.get_ticks_usec()
	spot_t -= dt
	if spot_t <= 0:
		_update_spotting()
		spot_t = 0.25
		_prof("засвет", t0)
	squad_t -= dt
	if squad_t <= 0.0:
		t0 = Time.get_ticks_usec()
		_squads_update()
		squad_t = 1.0
		_prof("группы", t0)
	var t_tanks := Time.get_ticks_usec()
	for tk: TankScript in tanks:
		if not tk.alive:
			tk.update_pop(dt)
			tk.sync_node()
			continue
		tk.rl = maxf(0.0, tk.rl - dt)
		tk.lit = maxf(0.0, tk.lit - dt)
		tk.recoil = maxf(0.0, tk.recoil - dt * 3.0)
		tk.track_broken = maxf(0.0, tk.track_broken - dt)
		for c in tk.cons:
			tk.cons[c] = maxf(0.0, float(tk.cons[c]) - dt)
		for name in tk.update_repairs(dt):
			if tk.is_player:
				hud.alert(FIXED_MSG[name], Color("9ad07a"))
		if tk.fire > 0.0:
			tk.fire -= dt
			var by: TankScript = tk.get_meta("fire_by", tk)
			_damage(tk, float(tk.max_hp) * 0.018 * dt, by, "fire")  # 1,8% прочности в секунду
			if tk.fire <= 0.0 and tk.fire_fx:
				tk.fire_fx.emitting = false
			if not tk.alive:
				continue
		if over:
			drive(tk, dt, 0.0, 0.0)
		elif tk.is_player and not autopilot:
			_player(tk, dt)
		else:
			_bot(tk, dt)
		# дым подбитого — только у видимых и не слишком далёких танков
		tk.smoke_on(tk.hp < tk.max_hp * 0.35 and (tk.team == 0 or tk.vis[0]) and tk.pos.distance_to(watch.pos) < 1400.0)
	_prof("танки (езда+боты)", t_tanks)
	t0 = Time.get_ticks_usec()
	separate()
	for tk: TankScript in tanks:
		_suspend(tk, dt)
		tk.sync_node()
	_prof("подвеска, столкновения", t0)
	t0 = Time.get_ticks_usec()
	_update_shells(dt)
	_prof("снаряды", t0)
	for pr in falling:
		pr.fall = minf(1.0, pr.fall + dt * 1.4)
		MapGen.place_prop(pr)
	falling = falling.filter(func(x): return x.fall < 1.0)
	for tx in texts:
		tx.life -= dt
	texts = texts.filter(func(x): return x.life > 0)
	_zones_update(dt)
	if not player.alive and not over and (watch == player or not watch.alive):
		var best: TankScript = null
		var bd := 1e9
		for tk: TankScript in tanks:
			if tk.alive and tk.team == 0 and tk.pos.distance_to(player.pos) < bd:
				bd = tk.pos.distance_to(player.pos)
				best = tk
		if best:
			watch = best
	if not player.alive and watch != player:
		cam_yaw = turn_toward(cam_yaw, watch.tur, 2.0 * dt)
		cam_pitch = move_toward(cam_pitch, 0.07, dt)
	shake = maxf(0.0, shake - dt * 30.0)
	_radio_events()
	if not over:
		var a := alive_count(0)
		var e := alive_count(1)
		if e == 0:
			finish("win", "Все противники уничтожены")
		elif a == 0:
			finish("lose", "Ваша команда уничтожена")
		elif clock >= D.TIME_LIMIT:
			if mode == "supremacy":
				var res := "draw"
				if score[0] > score[1]:
					res = "win"
				elif score[0] < score[1]:
					res = "lose"
				finish(res, "Время вышло")
			else:
				finish("draw", "Время вышло")
	else:
		over_t += dt


func _physics_process(delta: float) -> void:
	if paused or briefing:
		return
	var dt := minf(delta, 0.05)
	for i in speed:
		var t0 := Time.get_ticks_usec()
		_update(dt)
		_prof("шаг логики всего", t0)
	if over and over_t > 1.8 and not result_shown:
		_show_result()


func _process(delta: float) -> void:
	_sync(minf(delta, 0.05))


## Брифинг закрыт — бой начинается, через секунду командир даёт команду по рации.
func begin() -> void:
	briefing = false
	radio_start = clock + 1.0


## Текст брифинга: сражение, стороны, составы команд и задача режима.
func _brief_info() -> Dictionary:
	var M: Dictionary = D.MAPS[map_key]
	var teams_info: Array = []
	for team in 2:
		var s: String = side if team == 0 else D.foe_side(side)
		var counts := {}
		var order: Array = []
		for k in teams[team]:
			var tag: String = D.spec(k, year).tag
			if not counts.has(tag):
				order.append(tag)
			counts[tag] = counts.get(tag, 0) + 1
		var parts: Array = []
		for tag in order:
			parts.append("%s ×%d" % [tag, counts[tag]] if counts[tag] > 1 else tag)
		var head := "%s · %s" % [String(D.SIDES[s].name).to_upper(), M[s]]
		head += "  (ваша команда)" if team == 0 else "  (противник)"
		teams_info.append({"head": head, "list": "%s — боевой вес %d" % [", ".join(parts), D.team_pts(teams[team], year)], "ours": team == 0})
	var tasks := {
		"standard": "Задача: уничтожить противника или захватить его базу, не отдав свою.",
		"encounter": "Задача: захватить нейтральную базу в центре карты или уничтожить противника.",
		"supremacy": "Задача: держать точки A, B, C — каждая приносит очки. Победа — 600 очков или уничтожение противника.",
	}
	return {"title": "%s · %s" % [M.name, M.date], "sub": "%s против %s" % [M[side], M[D.foe_side(side) + "_g"]],
		"text": M.brief, "teams": teams_info, "task": tasks[mode]}


## Переговоры своей стороны: фраза случайного живого союзника на языке его армии.
## subject — позывной, о ком речь; h — направление «по часам».
func say(event: String, subject := "", h := 12) -> void:
	if over or hud == null:
		return
	var gap := {"start": 0.0, "spot": 9.0, "spot_tiger": 9.0, "ally_down": 3.0, "enemy_down": 5.0,
		"our_base": 25.0, "their_base": 25.0, "last": 999.0}
	if clock - radio_last < 2.2 or clock - float(radio_cd.get(event, -999.0)) < float(gap.get(event, 6.0)):
		return
	var who: Array = []
	for tk: TankScript in tanks:
		if tk.alive and tk.team == 0 and not tk.is_player:
			who.append(tk)
	if who.is_empty():
		return
	var sp: TankScript = who[randi() % who.size()]
	var lines: Array = D.RADIO[event][lang]
	var ln: Array = lines[randi() % lines.size()]
	var clock_ru := "%d %s" % [h, "час" if h == 1 else ("часа" if h <= 4 else "часов")]
	var fill := func(t: String) -> String:
		return t.replace("{cs}", subject if subject != "" else sp.callsign).replace("{h}", str(h)).replace("{clock}", clock_ru)
	hud.add_radio(sp.callsign, fill.call(ln[0]), fill.call(ln[1]) if ln[1] != "" else "")
	sfx.play2d("radio_%d" % (1 + randi() % 3), -9.0)
	radio_last = clock
	radio_cd[event] = clock


## Направление на точку «по часам» относительно корпуса наблюдателя (12 — прямо).
func _clock_of(from: TankScript, p: Vector2) -> int:
	var d := ang_diff((p - from.pos).angle(), from.hull)
	var h := posmod(int(roundf(d / (PI / 6.0))), 12)
	return 12 if h == 0 else h


## Прогон симуляции без отрисовки (для проверок).
func simulate(steps: int) -> void:
	nav_sync = true
	for i in steps:
		if over:
			return
		var t0 := Time.get_ticks_usec()
		_update(1.0 / 30.0)
		_prof("шаг логики всего", t0)


func set_paused(v: bool) -> void:
	if over:
		return
	paused = v
	hud.show_pause(v)
	get_tree().paused = false
	for k in loops:
		for p in loops[k]:
			if p:
				(p as AudioStreamPlayer3D).stream_paused = v


func toggle_speed() -> void:
	speed = 1 if speed > 1 else 4


func toggle_sniper() -> void:
	if player.alive:
		sniper = not sniper


func _show_result() -> void:
	result_shown = true
	var stats := {
		"result": result, "reason": reason, "kills": kills, "dmg": roundi(dmg_done),
		"acc": roundi(100.0 * hits / shots) if shots > 0 else 0, "time": clock,
		"mode": D.MODES[mode].name, "map": D.MAPS[map_key].name, "tank": player_type,
	}
	stats.merge(rewards())
	ended.emit(stats)
	hud.show_result(stats)


## Опыт и серебро за бой: урон, урон по засвету, принятый бронёй урон, уничтоженные, засвеченные,
## захват и защита базы, участие. Победа — ×1,5. Ремонт и снаряжение списываются с серебра.
func rewards() -> Dictionary:
	var tier := D.tier(player_type)
	var lines: Array = [
		["Урон", dmg_done * 0.5, dmg_done * 8.0],
		["Урон по вашему засвету", spot_dmg * 0.25, spot_dmg * 4.0],
		["Заблокировано бронёй", blocked * 0.1, blocked * 1.5],
		["Уничтожено", kills * 40.0, kills * 900.0],
		["Засвечено первым", spotted_n * 15.0, spotted_n * 300.0],
		["Захват базы", cap_pts, cap_pts * 30.0],
		["Защита базы", def_pts * 1.5, def_pts * 30.0],
		["Участие в бою", 20.0 + (30.0 if player.alive else 0.0), 1000.0 + tier * 400.0],
	]
	var xp := 0.0
	var silver := 0.0
	var shown: Array = []
	for ln in lines:
		xp += float(ln[1])
		silver += float(ln[2])
		if float(ln[1]) >= 1.0 or float(ln[2]) >= 1.0:
			shown.append([ln[0], roundi(ln[1]), roundi(ln[2])])
	var mult: float = {"win": 1.5, "draw": 1.1}.get(result, 1.0)
	# на высоких уровнях бой ценнее (как и ремонт дороже)
	var tk_mult := 1.0 + maxi(0, tier - 4) * 0.2
	xp = roundf(xp * mult * tk_mult)
	silver = roundf(silver * mult * tk_mult)
	var repair := roundi((1.0 - clampf(player.hp / player.max_hp, 0.0, 1.0)) * float(D.REPAIR_FULL[tier]))
	var cons_cost := 0
	for c in player.cons_used:
		cons_cost += D.cons_price(c, tier)
	return {"lines": shown, "mult": mult, "tier_mult": tk_mult, "xp": int(xp), "free_xp": roundi(xp * D.FREE_XP_SHARE),
		"silver_gross": int(silver), "repair": repair, "cons_cost": cons_cost, "silver": int(silver) - repair - cons_cost}


# ---------- Отображение ----------

func _sync(dt: float) -> void:
	var w := watch
	var o := _cam_origin(w)
	var off := Vector3.ZERO
	if shake > 0 and not sniper:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.35
	cam.global_transform = Transform3D(Basis.looking_at(_cam_dir()), o + off)
	var vs := get_viewport().get_visible_rect().size
	var fov := 74.0 if vs.x < vs.y else 56.0
	cam.fov = fov / 3.5 if sniper else fov
	for tk: TankScript in tanks:
		tk.visible = (not tk.alive or tk.team == 0 or tk.vis[0]) and not (sniper and tk == w)
		_sync_sound(tk)
	# время для шейдеров — между шагами логики, чтобы трассеры летели плавно
	var frac := Engine.get_physics_interpolation_fraction() if not (paused or briefing or over) else 0.0
	var now_v := clock + frac * speed / float(Engine.physics_ticks_per_second)
	trk_mat.set_shader_parameter("now", now_v)
	shell_mat.set_shader_parameter("now", now_v)
	for tk: TankScript in tanks:
		if tk.alive and tk.visible:
			tk.sync_travel(frac)
	bush_mat.set_shader_parameter("fade_a", w.center())
	bush_mat.set_shader_parameter("fade_b", cam.global_position)
	for z in zones:
		# перекрашиваем, только когда меняется владелец или начинается захват
		var cap := 1 if z.prog[0] > 0 and z.side != 0 else (2 if z.prog[1] > 0 and z.side != 1 else 0)
		var key: int = (z.side + 1) * 3 + cap
		if key == z.col_key:
			continue
		z.col_key = key
		var c := Color.WHITE
		if z.side == 0:
			c = Color(D.ALLY)
		elif z.side == 1:
			c = Color(D.FOE)
		z.ring_mat.albedo_color = [c, Color("9ae07a"), Color("ff8a6a")][cap]
		var dc := c
		dc.a = 0.1
		z.disc_mat.albedo_color = dc
		z.flag_mat.set_shader_parameter("col", c)


## Обороты двигателя и лязг гусениц следуют за газом и скоростью.
func _sync_sound(tk: TankScript) -> void:
	var lp: Array = loops.get(tk, [])
	if lp.is_empty() or not tk.alive:
		return
	# далёкие моторы не слышны: их петли стоят и не нагружают микшер
	var far := cam.global_position.distance_squared_to(tk.center()) > 1300.0 * 1300.0
	for p in lp:
		if p:
			(p as AudioStreamPlayer3D).stream_paused = far or paused
	if far:
		return
	var v := clampf(absf(tk.sp) / float(tk.T.speed), 0.0, 1.0)
	var eng_load := clampf(absf(tk.throttle), 0.0, 1.0)
	var eng: AudioStreamPlayer3D = lp[0]
	var rpm := 0.75 + v * 0.75 + eng_load * 0.35 + absf(tk.yaw_rate) * 0.15
	eng.pitch_scale = lerpf(eng.pitch_scale, rpm, 0.1)
	var base := -2.0 if tk.is_player else -6.0
	eng.volume_db = base + eng_load * 4.0 - (10.0 if speed > 1 else 0.0)
	var trk: AudioStreamPlayer3D = lp[1]
	var tv := clampf(maxf(absf(tk.sp), absf(tk.yaw_rate) * float(tk.T.W) * 0.5) / float(tk.T.speed), 0.0, 1.0)
	trk.pitch_scale = 0.6 + tv * 0.9
	trk.volume_db = linear_to_db(maxf(tv, 0.001)) - 2.0 - (10.0 if speed > 1 else 0.0)
	trk.stream_paused = paused or tv < 0.02
	if lp[2] != null:
		var turp: AudioStreamPlayer3D = lp[2]
		var tr := clampf(tk.tur_rate / maxf(float(tk.T.tspd), 0.01), 0.0, 1.0)
		turp.volume_db = linear_to_db(maxf(tr, 0.001)) - 6.0
		turp.pitch_scale = 0.8 + tr * 0.4
