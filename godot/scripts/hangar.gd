extends Node3D
## Ангар: танк на поворотном круге в светлом танкоремонтном цеху. Внизу — карусель своих танков,
## слева — характеристики, модули и снаряжение, справа — режим и карта, сверху — серебро, опыт
## и дерево исследований.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const TankScript = preload("res://scripts/tank.gd")
const Geo = preload("res://scripts/geo.gd")
const TexLib = preload("res://scripts/textures.gd")
const Native = preload("res://scripts/native.gd")

# Места танков в дереве исследования: [столбец (уровень − 3), строка].
const TREE_POS := {
	"allies": {"stuart": [0, 0.55], "lee": [1, 0], "sherman": [2, 0], "firefly": [3, 0], "m10": [2, 0.9], "easy8": [3, 0.9],
		"pershing": [5, 0.9], "matilda": [1, 1.8], "crusader": [1, 2.7], "cromwell": [2, 2.7], "churchill": [3, 1.8],
		"comet": [4, 2.7], "chaffee": [2, 3.6], "t70": [0, 4.9], "t34_76": [2, 4.5], "t34": [3, 4.5], "su100": [4, 4.5],
		"su85": [3, 5.4], "kv1": [3, 6.3], "kv2": [4, 6.3], "is2": [5, 6.3], "isu152": [5, 5.4]},
	"axis": {"l6_40": [0, 0], "m13_40": [0, 0.9], "m15_42": [1, 0.45], "p26": [2, 0.45], "pz3": [1, 1.8], "pz4": [2, 1.8],
		"pz4f2": [2, 2.7], "tiger": [3, 1.8], "tiger2": [5, 1.35], "tiger_p": [4, 1.8], "ferdinand": [5, 2.25],
		"panther": [4, 2.9], "stug": [2, 3.6], "jagdpanther": [4, 3.9], "jagdtiger": [5, 3.9], "pz38t": [0, 4.5],
		"luchs": [1, 4.5], "turan": [1, 5.4], "hetzer": [1, 3.6], "nashorn": [3, 4.6]},
}
const NATION_COL := {"СССР": "b04a3c", "Германия": "8d8a7c", "США": "6d8650", "Великобритания": "a08650", "Италия": "4f8f5c",
	"Венгрия": "8f7a3a"}
const GREEN := "7bc65a"
const BLUE := "6fa8d6"

var main  # main.gd
var cam: Camera3D
var preview: TankScript
var orbit := 0.75
var tilt := 0.26
var idle := 10.0  # секунд без касаний: камера снова медленно облетает танк
var root: Control
var margin: MarginContainer
var silver_lbl: Label
var free_lbl: Label
var tier_lbl: Label
var name_lbl: Label
var info_lbl: Label
var tank_bars: TankBars
var xp_lbl: Label
var mods_btn: Button
var cons_btns := {}
var cons_desc: Label
var mode_desc: Label
var map_desc: Label
var qual_btn: Button
var res_btn: Button
var eco_btn: Button
var hist_btn: Button
var go_btn: Button
var map_btns := {}
var car_box: HBoxContainer
var cards := {}
var toast: Label
var toast_t := 0.0
var modal: Control  # открытое окно (дерево, модули, авторы)
var tree_side := "allies"
var tree_sel := ""


## Полоски характеристик выбранного танка.
class TankBars extends Control:
	var T: Dictionary = {}
	var font: Font

	func _ready() -> void:
		font = ThemeDB.fallback_font
		custom_minimum_size = Vector2(0, 175)

	func _draw() -> void:
		if T.is_empty():
			return
		var A: Array = T.armor
		var rows := [
			["Прочность", "%d" % int(T.hp), float(T.hp) / 1800.0],
			["Урон / пробитие", "%d / %d мм" % [int(T.dmg), int(T.pen)], float(T.pen) / 230.0],
			["Броня лба", "%d / %d мм" % [A[0], A[3]], float(A[0]) / 150.0],
			["Скорость", "%d км/ч" % roundi(float(T.kmh) * D.SPEED_K), float(T.kmh) / 58.0],
			["Мощность", "%d л.с. · %.1f т" % [int(T.power), float(T.mass)], float(T.power) / float(T.mass) / 16.0],
			["Перезарядка", "%.1f с" % float(T.reload), 2.0 / float(T.reload)],
			["Обзор", "%d м" % roundi(float(T.spot) * D.SPOT_K), float(T.spot) * D.SPOT_K / 100.0],
		]
		var y := 0.0
		for r in rows:
			draw_string(font, Vector2(0, y + 14), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UI.DIM))
			draw_string(font, Vector2(0, y + 14), r[1], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, Color(UI.TEXT))
			draw_rect(Rect2(0, y + 18, size.x, 4), Color(0.05, 0.06, 0.04))
			draw_rect(Rect2(0, y + 18, size.x * clampf(r[2], 0.05, 1.0), 4), Color(GREEN))
			y += 25.0


## Карточка танка: уровень, нация, класс, название. Касание без сдвига — выбор (сдвиг листает ленту).
class TankCard extends Control:
	signal picked(key: String)
	var key := ""
	var tier := ""
	var tag := ""
	var cls := ""
	var nation := Color.WHITE
	var state := ""  # подпись внизу (для дерева исследования)
	var border := Color(UI.LINE)
	var selected := false
	var dim := false
	var font: Font
	var _down := Vector2.ZERO
	var _pressed := false

	func _ready() -> void:
		font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var e := event as InputEventScreenTouch
			if e.pressed:
				_down = e.position
				_pressed = true
			elif _pressed:
				_pressed = false
				if e.position.distance_to(_down) < 14.0:
					picked.emit(key)
		elif event is InputEventScreenDrag:
			var e := event as InputEventScreenDrag
			if e.position.distance_to(_down) >= 14.0:
				_pressed = false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bc := Color(D.AMBER) if selected else border
		draw_style_box(UI.box("1d2318" if not dim else "15180f", bc.to_html(false), 3 if selected else 2, 8, 0.94, 0.0), r)
		draw_rect(Rect2(3, 3, 6, size.y - 6), nation)
		var tc := Color(UI.TEXT) if not dim else Color(UI.DIM)
		draw_string(font, Vector2(15, 22), tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(D.AMBER) if not dim else Color(UI.DIM))
		draw_string(font, Vector2(0, 21), cls, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 12, Color(UI.DIM))
		draw_string(font, Vector2(15, 46), tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 16, tc)
		if state != "":
			draw_string(font, Vector2(15, size.y - 9), state, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 12, border)


func _ready() -> void:
	_build_scene()
	_build_ui()
	_fill_carousel()
	_select_tank(main.save.tank)
	_show_last()


# ---------- Цех ----------

var _mats := {}


func _mat(col: String, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var k := "%s_%s_%s" % [col, rough, metal]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col)
		m.roughness = rough
		m.metallic = metal
		_mats[k] = m
	return _mats[k]


## Светящееся стекло окон и фонарей крыши: переплёт из тёмных брусков, за ним — светлое небо.
static func _glass_tex() -> ImageTexture:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tint := {}
	for y in S:
		for x in S:
			var cx := x / 32
			var cy := y / 32
			if not tint.has(cy * 8 + cx):
				tint[cy * 8 + cx] = rng.randf_range(-0.06, 0.04)
			var c := Color("dfe9ee").lerp(Color("f6f4ea"), float(y) / S).lightened(tint[cy * 8 + cx])
			if x % 32 < 3 or y % 32 < 3:
				c = Color("2e3431")
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Жёлто-чёрные косые полосы — разметка опасных мест и балка крана.
static func _hazard_tex() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color("d8a21c") if ((x + y) / 16) % 2 == 0 else Color("1d1b17"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Танкоремонтный цех: бетонный пол с разметкой, кирпичные стены с рядами окон, стальные фермы
## под двускатной крышей с фонарями, кран-балка, открытые ворота во двор, верстак, бочки, ящики.
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("c9d5dc")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dfe4e6")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("c9d1d3")
	env.fog_depth_begin = 300.0
	env.fog_depth_end = 1400.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_m := TexLib.world_mat("concrete", Vector3.ONE / 36.0, 0.0, 0.22, Color(1.08, 1.06, 1.02))
	var brick_m := TexLib.world_mat("brick", Vector3.ONE / 26.0, 0.0, 0.18, Color(1.0, 0.95, 0.92))
	var wall_m := TexLib.world_mat("concrete", Vector3.ONE / 50.0, 0.0, 0.12, Color(1.12, 1.18, 1.12))
	var roof_m := _mat("575d58", 0.9)
	var steel := _mat("6c766e", 0.6, 0.25)
	var dark := _mat("3b403c", 0.6, 0.3)
	var line_m := _mat("d6a62a", 0.7)
	var joint := _mat("6a6760", 0.95)
	var glass := StandardMaterial3D.new()
	var gt := _glass_tex()
	glass.albedo_texture = gt
	glass.emission_enabled = true
	glass.emission_texture = gt
	glass.emission_energy_multiplier = 1.25
	var hz := StandardMaterial3D.new()
	hz.albedo_texture = _hazard_tex()
	hz.uv1_scale = Vector3(6, 1, 1)
	hz.roughness = 0.7

	var g := Geo.Group.new()  # здание: без теней (солнце «светит в окна»)
	var p := Geo.Group.new()  # оборудование и мелочи с тенями
	const HX := 300.0
	const HZ := 220.0
	const EAVE := 140.0
	const RIDGE := 178.0
	# пол: плиты со швами, жёлтая рамка стоянки танка и проезд к воротам
	g.add(Geo.box(Vector3(HX * 2 + 260, 2, HZ * 2 + 20)), Geo.xf(Vector3(110, -1, 0)), floor_m)
	for k in range(-6, 7):
		g.add(Geo.box(Vector3(HX * 2, 0.2, 0.7)), Geo.xf(Vector3(0, 0.05, k * 36.0)), joint)
	for k in range(-8, 9):
		g.add(Geo.box(Vector3(0.7, 0.2, HZ * 2)), Geo.xf(Vector3(k * 36.0, 0.05, 0)), joint)
	for s: float in [-1.0, 1.0]:
		g.add(Geo.box(Vector3(200, 0.3, 2.4)), Geo.xf(Vector3(0, 0.12, s * 78.0)), line_m)
		g.add(Geo.box(Vector3(2.4, 0.3, 158)), Geo.xf(Vector3(s * 100.0, 0.12, 0)), line_m)
		g.add(Geo.box(Vector3(190, 0.3, 1.6)), Geo.xf(Vector3(200, 0.12, s * 92.0)), line_m)
	# поворотный круг
	p.add(Geo.cyl(64, 66, 1.6, 64), Geo.xf(Vector3(0, 0.8, 0)), _mat("70746f", 0.5, 0.45))
	for k in 40:
		var a := TAU * k / 40.0
		var mat := line_m if k % 2 == 0 else _mat("1d1b17", 0.7)
		p.add(Geo.box(Vector3(10.2, 0.4, 2.2)), Transform3D(Basis(Vector3.UP, -a + PI / 2), Vector3(cos(a), 0, sin(a)) * 64.5 + Vector3(0, 1.75, 0)), mat)
	# стены: внизу кирпич, выше — крашеная штукатурка с рядом окон
	for s: float in [-1.0, 1.0]:
		g.add(Geo.box(Vector3(HX * 2, 36, 6)), Geo.xf(Vector3(0, 18, s * HZ)), brick_m)
		g.add(Geo.box(Vector3(HX * 2, EAVE - 36, 4)), Geo.xf(Vector3(0, 36 + (EAVE - 36) / 2, s * (HZ + 1))), wall_m)
		for k in 6:
			var x := -250.0 + k * 100.0
			_window(g, Vector3(x, 86, s * (HZ - 2.5)), Vector2(70, 58), Basis(Vector3.UP, 0.0 if s > 0 else PI), glass, dark)
		# колонны и фермы
		for k in 9:
			var x := -HX + 4.0 + k * 74.0
			g.add(Geo.box(Vector3(4, EAVE, 5)), Geo.xf(Vector3(x, EAVE / 2, s * (HZ - 6))), steel)
	# торец без ворот: кирпич целиком, высокие окна
	g.add(Geo.box(Vector3(6, 36, HZ * 2)), Geo.xf(Vector3(-HX, 18, 0)), brick_m)
	g.add(Geo.box(Vector3(4, EAVE - 36, HZ * 2)), Geo.xf(Vector3(-HX - 1, 36 + (EAVE - 36) / 2, 0)), wall_m)
	for k in 4:
		_window(g, Vector3(-HX + 2.5, 86, -150.0 + k * 100.0), Vector2(62, 58), Basis(Vector3.UP, -PI / 2), glass, dark)
	_gable(g, -HX - 1, EAVE, RIDGE, HZ, wall_m)
	# торец с воротами: проём во двор, створки откачены
	const DOOR := 96.0
	const DOOR_H := 118.0
	for s: float in [-1.0, 1.0]:
		var w := HZ - DOOR
		g.add(Geo.box(Vector3(6, EAVE, w)), Geo.xf(Vector3(HX, EAVE / 2, s * (DOOR + w / 2))), wall_m)
		g.add(Geo.box(Vector3(6.5, 36, w)), Geo.xf(Vector3(HX, 18, s * (DOOR + w / 2))), brick_m)
		# створка ворот: рама и обшивка
		var dz := s * (DOOR + 52.0)
		p.add(Geo.box(Vector3(3, DOOR_H, 100)), Geo.xf(Vector3(HX - 7, DOOR_H / 2, dz)), _mat("4f5c4a", 0.75, 0.2))
		for k in 5:
			p.add(Geo.box(Vector3(3.6, 2.4, 100)), Geo.xf(Vector3(HX - 7, 12.0 + k * 24.0, dz)), dark)
	g.add(Geo.box(Vector3(6, EAVE - DOOR_H, DOOR * 2)), Geo.xf(Vector3(HX, DOOR_H + (EAVE - DOOR_H) / 2, 0)), wall_m)
	g.add(Geo.box(Vector3(8, 6, DOOR * 2 + 8)), Geo.xf(Vector3(HX - 4, DOOR_H + 1, 0)), hz)
	g.add(Geo.box(Vector3(9, 3, DOOR * 2 + 10)), Geo.xf(Vector3(HX - 4, DOOR_H + 6, 0)), dark)
	_gable(g, HX + 1, EAVE, RIDGE, HZ, wall_m)
	# крыша: два ската, фонари вдоль конька, фермы
	var slope := atan2(RIDGE - EAVE, HZ)
	var span := sqrt(HZ * HZ + (RIDGE - EAVE) * (RIDGE - EAVE))
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0, (EAVE + RIDGE) / 2 + 2, s * HZ / 2)
		var b := Basis(Vector3.RIGHT, s * slope)
		g.add(Geo.box(Vector3(HX * 2 + 12, 3, span + 6)), Transform3D(b, c), roof_m)
		for k in 5:
			var x := -232.0 + k * 116.0
			g.add(Geo.box(Vector3(70, 1, 34)), Transform3D(b, c + b * Vector3(x, -1.8, -s * span * 0.28)), glass)
	for k in 9:
		var x := -HX + 4.0 + k * 74.0
		_truss(g, x, EAVE, RIDGE, HZ, steel)
	# кран-балка: подкрановые пути вдоль стен, мост поперёк, тележка и крюк над стоянкой
	for s: float in [-1.0, 1.0]:
		g.add(Geo.box(Vector3(HX * 2, 6, 4)), Geo.xf(Vector3(0, 120, s * (HZ - 12))), dark)
	g.add(Geo.box(Vector3(8, 9, HZ * 2 - 24)), Geo.xf(Vector3(-118, 114, 0)), hz)
	g.add(Geo.box(Vector3(14, 8, 16)), Geo.xf(Vector3(-118, 106, 24)), _mat("c99a2a", 0.7))
	g.add(Geo.cyl(0.5, 0.5, 34, 6), Geo.xf(Vector3(-118, 85, 24)), dark)
	g.add(Geo.box(Vector3(6, 7, 4)), Geo.xf(Vector3(-118, 65, 24)), _mat("c99a2a", 0.7))
	g.add(Geo.cyl(2.2, 1.0, 5, 8), Geo.xf(Vector3(-118, 59, 24)), dark)
	# подвесные лампы над стоянкой
	for lp: Vector3 in [Vector3(-48, 0, -40), Vector3(48, 0, -40), Vector3(-48, 0, 40), Vector3(48, 0, 40)]:
		g.add(Geo.cyl(0.4, 0.4, 30, 5), Geo.xf(Vector3(lp.x, EAVE - 15, lp.z)), dark)
		g.add(Geo.cyl(2.2, 9.5, 6, 18), Geo.xf(Vector3(lp.x, EAVE - 33, lp.z)), _mat("2f4434", 0.5, 0.2))
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color("fff1cf")
		bulb.emission_enabled = true
		bulb.emission = Color("ffe6b0")
		bulb.emission_energy_multiplier = 3.0
		g.add(Geo.sphere(10, 6), Geo.xf(Vector3(lp.x, EAVE - 36.5, lp.z), Vector3.ZERO, Vector3.ONE * 5.0), bulb)
	_props(p)
	# двор за воротами: бетонная площадка, трава, соседние цеха
	var yard := _mat("8a8f77", 0.95)
	g.add(Geo.box(Vector3(1600, 1, 2000)), Geo.xf(Vector3(1300, -1.6, 0)), yard)
	for k in 4:
		var z := -520.0 + k * 340.0
		g.add(Geo.box(Vector3(160, 110, 240)), Geo.xf(Vector3(1100, 55, z)), wall_m)
		g.add(Geo.box(Vector3(170, 6, 250)), Geo.xf(Vector3(1100, 112, z)), roof_m)
	g.commit(self, false)
	p.commit(self, true)
	# «ЦЕХ 3» на кирпичном торце и номер стоянки на полу
	var plate := Label3D.new()
	plate.text = "ЦЕХ  3"
	plate.font_size = 260
	plate.pixel_size = 0.12
	plate.modulate = Color("e9e3d2")
	plate.outline_size = 0
	plate.position = Vector3(-HX + 3.5, 112, 0)
	plate.rotation = Vector3(0, PI / 2, 0)
	plate.shaded = true
	add_child(plate)
	var bay := Label3D.new()
	bay.text = "3"
	bay.font_size = 300
	bay.pixel_size = 0.1
	bay.modulate = Color("d6a62a")
	bay.outline_size = 0
	bay.position = Vector3(84, 0.4, 0)
	bay.rotation = Vector3(-PI / 2, PI / 2, 0)
	bay.shaded = true
	add_child(bay)

	# свет: солнце из окон (тени только от танка и вещей), тёплые лампы над стоянкой
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.5
	add_child(sun)
	for lp: Vector3 in [Vector3(-48, EAVE - 40, 0), Vector3(48, EAVE - 40, 0)]:
		var spot := SpotLight3D.new()
		spot.position = lp
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.spot_angle = 55.0
		spot.spot_range = 190.0
		spot.light_energy = 2.2
		spot.light_color = Color("ffe2b8")
		add_child(spot)
	cam = Camera3D.new()
	cam.fov = 38
	cam.far = 3000.0
	add_child(cam)
	cam.current = true


## Окно: светлое стекло в стальном переплёте, подоконник.
func _window(g: Geo.Group, c: Vector3, sz: Vector2, b: Basis, glass: Material, frame: Material) -> void:
	g.add(Geo.box(Vector3(sz.x, sz.y, 0.6)), Transform3D(b, c), glass)
	g.add(Geo.box(Vector3(sz.x + 4, 3, 2.4)), Transform3D(b, c + b * Vector3(0, sz.y / 2 + 1.5, 0)), frame)
	g.add(Geo.box(Vector3(sz.x + 6, 2.4, 4)), Transform3D(b, c + b * Vector3(0, -sz.y / 2 - 1.2, -1)), frame)
	for sx: float in [-1.0, 1.0]:
		g.add(Geo.box(Vector3(3, sz.y, 2.4)), Transform3D(b, c + b * Vector3(sx * (sz.x / 2 + 1.5), 0, 0)), frame)


## Щипец торцевой стены — треугольник под коньком.
func _gable(g: Geo.Group, x: float, eave: float, ridge: float, hz: float, m: Material) -> void:
	var prof := PackedVector2Array([Vector2(-hz, 0), Vector2(hz, 0), Vector2(0, ridge - eave)])
	var mesh := Geo.prism(prof, 4.0)
	g.add(mesh, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, eave, 0)), m)


## Стальная ферма поперёк цеха: нижний пояс, верхние пояса по скатам, стойки и раскосы.
func _truss(g: Geo.Group, x: float, eave: float, ridge: float, hz: float, m: Material) -> void:
	g.add(Geo.box(Vector3(2.5, 2.5, hz * 2)), Geo.xf(Vector3(x, eave, 0)), m)
	var rise := ridge - eave
	var len := sqrt(hz * hz + rise * rise)
	for s: float in [-1.0, 1.0]:
		var b := Basis(Vector3.RIGHT, s * atan2(rise, hz))
		g.add(Geo.box(Vector3(2.5, 2.5, len)), Transform3D(b, Vector3(x, eave + rise / 2, s * hz / 2)), m)
		for k in range(1, 6):
			var z := s * hz * (1.0 - k / 6.0)
			var h := rise * k / 6.0
			g.add(Geo.box(Vector3(1.6, h, 1.6)), Geo.xf(Vector3(x, eave + h / 2, z)), m)
			var z2 := s * hz * (1.0 - (k + 1) / 6.0)
			var h2 := rise * (k + 1) / 6.0
			var d := Vector2(z2 - z, h2)
			var mid := Vector3(x, eave + h2 / 2, (z + z2) / 2)
			g.add(Geo.box(Vector3(1.2, d.length(), 1.2)), Transform3D(Basis(Vector3.RIGHT, atan2(d.x, d.y)), mid), m)


## Оборудование цеха вдоль стен: верстак с тисками и щитом инструментов, бочки, ящики, запасные
## катки и траки, стеллаж, пожарный щит, накрытый брезентом танк, лестница.
func _props(p: Geo.Group) -> void:
	var wood := TexLib.world_mat("wood", Vector3.ONE / 14.0, 0.0, 0.2)
	var dark := _mat("3b403c", 0.6, 0.3)
	var olive := _mat("4d5435", 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	# верстак у северной стены и щит с инструментами над ним
	var wb := Vector3(-170, 0, -200)
	p.add(Geo.box(Vector3(60, 3, 16)), Geo.xf(wb + Vector3(0, 13, 0)), wood)
	for sx: float in [-27.0, 27.0]:
		for sz: float in [-6.0, 6.0]:
			p.add(Geo.box(Vector3(2, 12, 2)), Geo.xf(wb + Vector3(sx, 6, sz)), dark)
	p.add(Geo.box(Vector3(56, 1.5, 14)), Geo.xf(wb + Vector3(0, 4, 0)), wood)
	p.add(Geo.box(Vector3(6, 5, 5)), Geo.xf(wb + Vector3(-22, 17, 2)), _mat("2f5072", 0.5, 0.4))
	p.add(Geo.box(Vector3(64, 30, 1.5)), Geo.xf(wb + Vector3(0, 40, -9)), _mat("77705e", 0.9))
	for k in 9:
		var tx := -26.0 + k * 6.5
		p.add(Geo.box(Vector3(1.4, rng.randf_range(8, 16), 1.2)), Geo.xf(wb + Vector3(tx, 40, -7.8), Vector3(0, 0, rng.randf_range(-0.3, 0.3))), dark)
	p.add(Geo.box(Vector3(14, 8, 8)), Geo.xf(wb + Vector3(18, 18.5, 0)), _mat("8b2a22", 0.6, 0.3))
	# бочки группами
	var drum_cols := ["4d5435", "6b2a22", "3e4a52", "4d5435", "7a6a3a"]
	for grp: Vector3 in [Vector3(-60, 0, -198), Vector3(220, 0, 196), Vector3(-270, 0, 120)]:
		for k in 5:
			var off := Vector3((k % 3) * 9.5 - 9.5, 0, (k / 3) * 9.5)
			var dm := _mat(drum_cols[(k + int(grp.x)) % drum_cols.size()], 0.6, 0.35)
			p.add(Geo.cyl(4.2, 4.2, 12, 16), Geo.xf(grp + off + Vector3(0, 6, 0)), dm)
			for ry: float in [3.0, 9.0]:
				p.add(Geo.cyl(4.35, 4.35, 0.6, 16), Geo.xf(grp + off + Vector3(0, ry, 0)), dm)
	# ящики со снарядами штабелем
	for k in 7:
		var c := Vector3(70 + (k % 3) * 15.0, 4.5 + (k / 3) * 9.0, -196)
		if k / 3 == 2:
			c.x += 7.0
		p.add(Geo.box(Vector3(14, 8.6, 9)), Geo.xf(c, Vector3(0, rng.randf_range(-0.05, 0.05), 0)), olive)
		p.add(Geo.box(Vector3(14.4, 1.2, 9.4)), Geo.xf(c + Vector3(0, 2.0, 0)), dark)
	# запасные катки, прислонённые к стене, и траки
	for k in 4:
		p.add(Geo.cyl(5.2, 5.2, 2.6, 18), Geo.xf(Vector3(150 + k * 7.5, 5.4, -205), Vector3(PI / 2 - 0.18, 0, 0)), olive)
		p.add(Geo.cyl(2, 2, 3.4, 10), Geo.xf(Vector3(150 + k * 7.5, 5.4, -205), Vector3(PI / 2 - 0.18, 0, 0)), dark)
	for k in 8:
		p.add(Geo.box(Vector3(5, 1.4, 4.4)), Geo.xf(Vector3(196 + (k % 4) * 5.4, 0.7 + (k / 4) * 1.4, -196), Vector3(0, 0.1, 0)), dark)
	# стеллаж с ящиками у южной стены
	var sh := Vector3(-190, 0, 206)
	for sx: float in [-30.0, 30.0]:
		p.add(Geo.box(Vector3(2, 46, 2)), Geo.xf(sh + Vector3(sx, 23, 0)), dark)
	for k in 4:
		p.add(Geo.box(Vector3(62, 1.4, 12)), Geo.xf(sh + Vector3(0, 4.0 + k * 13.0, 0)), wood)
		for j in 3:
			if rng.randf() < 0.75:
				var bh := rng.randf_range(5, 9)
				p.add(Geo.box(Vector3(rng.randf_range(10, 16), bh, 9)), Geo.xf(sh + Vector3(-18 + j * 18, 4.7 + k * 13.0 + bh / 2, 0)), olive if j % 2 == 0 else wood)
	# пожарный щит: красная доска, огнетушители, ведро
	var fp := Vector3(-HX_PROPS + 5, 0, -90)
	p.add(Geo.box(Vector3(1.2, 26, 30)), Geo.xf(fp + Vector3(0, 30, 0)), _mat("9a2b22", 0.7))
	for k in 2:
		p.add(Geo.cyl(1.8, 1.8, 9, 10), Geo.xf(fp + Vector3(2.5, 26, -7 + k * 14)), _mat("b8322a", 0.5, 0.2))
	p.add(Geo.cyl(3, 2.2, 5, 10), Geo.xf(fp + Vector3(2.5, 36, 0)), _mat("b8322a", 0.5, 0.2))
	# лестница
	var ld := Vector3(-HX_PROPS + 8, 0, 60)
	for sz: float in [-5.0, 5.0]:
		p.add(Geo.box(Vector3(1.4, 70, 1.4)), Geo.xf(ld + Vector3(6, 34, sz), Vector3(0, 0, 0.18)), wood)
	for k in 11:
		p.add(Geo.box(Vector3(1, 1, 10)), Geo.xf(ld + Vector3(6 - k * 0.55 + 3.0, 4 + k * 6.0, 0), Vector3(0, 0, 0.18)), wood)
	# танк под брезентом на соседней стоянке
	var tarp := _mat("5b5a42", 1.0)
	var tp := Vector3(150, 0, 170)
	p.add(Geo.box(Vector3(46, 10, 22)), Geo.xf(tp + Vector3(0, 9, 0)), dark)
	p.add(Geo.box(Vector3(52, 14, 30)), Geo.xf(tp + Vector3(0, 13, 0), Vector3(0.02, 0, 0.03)), tarp)
	p.add(Geo.box(Vector3(26, 10, 22)), Geo.xf(tp + Vector3(-3, 24, 0), Vector3(0.04, 0.1, -0.05)), tarp)
	p.add(Geo.cyl(1.4, 2.2, 28, 8), Geo.xf(tp + Vector3(22, 24, 0), Vector3(0, 0, PI / 2 - 0.04)), tarp)
	for k in 6:
		p.add(Geo.box(Vector3(9, 6, 6)), Geo.xf(tp + Vector3(rng.randf_range(-24, 24), 3, rng.randf_range(-16, 16)), Vector3(0, rng.randf() * TAU, 0)), olive)
	# канистры у ворот
	for k in 6:
		p.add(Geo.box(Vector3(3.4, 6.4, 4.8)), Geo.xf(Vector3(255 + (k % 3) * 4.2, 3.2, -130 + (k / 3) * 5.6)), _mat("4a5a3a" if k % 2 == 0 else "5f2a22", 0.7, 0.2))


const HX_PROPS := 300.0


func _process(delta: float) -> void:
	idle += delta
	if idle > 4.0:
		orbit += delta * 0.12
		tilt = lerpf(tilt, 0.26, delta * 0.5)
	if preview:
		preview.tur = preview.hull + sin(orbit * 1.6) * 0.5
		preview.gun_pitch = 0.04 + sin(orbit * 2.4) * 0.04
		preview.sync_node()
	var dist := 118.0
	cam.position = Vector3(cos(orbit) * cos(tilt), sin(tilt), sin(orbit) * cos(tilt)) * dist + Vector3(0, 6, 0)
	cam.look_at(Vector3(0, 12, 0), Vector3.UP)
	var s := UI.safe(root)
	margin.add_theme_constant_override("margin_left", int(16 + s.x))
	margin.add_theme_constant_override("margin_top", int(10 + s.y))
	margin.add_theme_constant_override("margin_right", int(16 + s.z))
	margin.add_theme_constant_override("margin_bottom", int(10 + s.w))
	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t, 0.0, 1.0)
		toast.visible = toast_t > 0.0


## Свайп по свободному месту крутит камеру вокруг танка.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and modal == null:
		var e := event as InputEventScreenDrag
		orbit += e.relative.x * 0.006
		tilt = clampf(tilt + e.relative.y * 0.004, 0.06, 0.75)
		idle = 0.0


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	layer.add_child(root)
	margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# верх: название, серебро и свободный опыт, исследования, графика, авторы
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	for t in [["СТАЛЬНОЙ", UI.TEXT], ["ШТУРМ", D.AMBER]]:
		var tl := UI.label(t[0], 30, t[1])
		tl.add_theme_constant_override("outline_size", 8)
		tl.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.05, 0.85))
		head.add_child(tl)
	# версия и чем считаются тяжёлые части: C++ (библиотека загрузилась) или GDScript
	var native := Native.available()
	var vl := UI.label("v%s\n%s" % [ProjectSettings.get_setting("application/config/version", ""), "C++" if native else "GDScript"],
		13, GREEN if native else UI.DIM)
	vl.add_theme_constant_override("outline_size", 6)
	vl.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.05, 0.85))
	head.add_child(vl)
	head.add_child(_spacer())
	silver_lbl = _chip(head, "СЕРЕБРО")
	free_lbl = _chip(head, "СВОБОДНЫЙ ОПЫТ")
	var rb := Button.new()
	rb.text = "ИССЛЕДОВАНИЯ"
	rb.custom_minimum_size = Vector2(0, 48)
	UI.accent(rb, 18)
	rb.pressed.connect(func(): _show_tree(D.TYPES[main.save.tank].side))
	head.add_child(rb)
	qual_btn = _small_btn(head, "", func():
		main.save.hq = not main.save.hq
		main.persist()
		_update_qual())
	_update_qual()
	res_btn = _small_btn(head, "", func():
		main.cycle_res()
		_update_res_btn())
	_update_res_btn()
	eco_btn = _small_btn(head, "", func():
		main.toggle_eco()
		_update_eco())
	_update_eco()
	_small_btn(head, "АВТОРЫ", _show_credits)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 12)
	vb.add_child(body)

	# слева: танк, характеристики, модули, снаряжение
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 5)
	left.add_child(lv)
	tier_lbl = UI.label("", 13, UI.DIM)
	lv.add_child(tier_lbl)
	name_lbl = UI.label("", 19, D.AMBER)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(270, 0)
	lv.add_child(name_lbl)
	tank_bars = TankBars.new()
	lv.add_child(tank_bars)
	xp_lbl = UI.label("", 13, UI.DIM)
	lv.add_child(xp_lbl)
	mods_btn = Button.new()
	mods_btn.custom_minimum_size = Vector2(0, 42)
	mods_btn.add_theme_font_size_override("font_size", 16)
	mods_btn.pressed.connect(_show_modules)
	lv.add_child(mods_btn)
	lv.add_child(UI.label("СНАРЯЖЕНИЕ В БОЙ", 12, UI.DIM))
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 6)
	lv.add_child(cr)
	for c in D.CONSUMABLES:
		var b := Button.new()
		b.text = D.CONSUMABLES[c].name
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 12)
		b.button_pressed = main.save.cons.has(c)
		b.pressed.connect(func():
			main.toggle_cons(c)
			_update_cons(c))
		cr.add_child(b)
		cons_btns[c] = b
	cons_desc = UI.label("", 12, UI.DIM)
	cons_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cons_desc.custom_minimum_size = Vector2(270, 0)
	lv.add_child(cons_desc)
	_update_cons("")

	# центр — свободен: там танк, свайпом крутится камера; уведомление о прошлом бое
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(center)
	toast = UI.label("", 17, UI.TEXT)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_stylebox_override("normal", UI.box("0f120c", D.AMBER, 2, 10, 0.86, 12.0))
	toast.visible = false
	center.add_child(toast)

	# справа: режим, карта, кнопка боя
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	rv.add_child(UI.label("РЕЖИМ", 12, UI.DIM))
	var mg := ButtonGroup.new()
	for key in D.MODES:
		var b := Button.new()
		b.text = D.MODES[key].name
		b.toggle_mode = true
		b.button_group = mg
		b.button_pressed = key == main.save.mode
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_select_mode.bind(key))
		rv.add_child(b)
	mode_desc = UI.label("", 12, UI.DIM)
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(mode_desc)
	rv.add_child(UI.label("КАРТА", 12, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rv.add_child(grid)
	var pg := ButtonGroup.new()
	var map_keys: Array = D.MAPS.keys()
	map_keys.append("random")
	for key in map_keys:
		var b := Button.new()
		b.text = D.MAPS[key].name if D.MAPS.has(key) else "Случайная"
		b.toggle_mode = true
		b.button_group = pg
		b.button_pressed = key == main.save.map
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_select_map.bind(key))
		grid.add_child(b)
		map_btns[key] = b
	map_desc = UI.label("", 12, UI.DIM)
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_desc.custom_minimum_size = Vector2(270, 0)
	rv.add_child(map_desc)
	hist_btn = Button.new()
	hist_btn.add_theme_font_size_override("font_size", 15)
	hist_btn.custom_minimum_size = Vector2(0, 36)
	hist_btn.pressed.connect(func():
		main.save.history = not main.save.history
		main.persist()
		_refresh())
	rv.add_child(hist_btn)
	rv.add_child(_spacer(true))
	go_btn = Button.new()
	go_btn.text = "В БОЙ"
	go_btn.custom_minimum_size = Vector2(0, 62)
	UI.accent(go_btn, 30)
	go_btn.pressed.connect(func(): main.start_battle())
	rv.add_child(go_btn)
	_select_mode(main.save.mode)

	# низ: карусель своих танков
	var car := PanelContainer.new()
	car.add_theme_stylebox_override("panel", UI.box("0f120c", UI.LINE, 1, 10, 0.78, 6.0))
	vb.add_child(car)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 74)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	car.add_child(sc)
	car_box = HBoxContainer.new()
	car_box.add_theme_constant_override("separation", 6)
	sc.add_child(car_box)


func _spacer(vertical := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _chip(parent: Control, title: String) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.LINE, 1, 8, 0.85, 10.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	var v := UI.label("0", 19)
	col.add_child(v)
	col.add_child(UI.label(title, 10, UI.DIM))
	pc.add_child(col)
	parent.add_child(pc)
	return v


func _small_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Карусель: свои танки по уровням, выбранный подсвечен.
func _fill_carousel() -> void:
	for c in car_box.get_children():
		c.queue_free()
	cards.clear()
	var keys: Array = main.save.owned.duplicate()
	keys.sort_custom(func(a, b):
		if D.tier(a) != D.tier(b):
			return D.tier(a) < D.tier(b)
		if D.TYPES[a].side != D.TYPES[b].side:
			return D.TYPES[a].side == "allies"
		return String(a) < String(b))
	for key in keys:
		var cd := _card(key)
		cd.custom_minimum_size = Vector2(136, 70)
		cd.picked.connect(_select_tank)
		car_box.add_child(cd)
		cards[key] = cd
	var plus := Button.new()
	plus.text = "+ НОВЫЙ\nТАНК"
	plus.custom_minimum_size = Vector2(110, 70)
	plus.add_theme_font_size_override("font_size", 14)
	plus.pressed.connect(func(): _show_tree(D.TYPES[main.save.tank].side))
	car_box.add_child(plus)


func _card(key: String) -> TankCard:
	var T: Dictionary = D.TYPES[key]
	var cd := TankCard.new()
	cd.key = key
	cd.tier = D.ROMAN[int(T.tier)]
	cd.tag = T.tag
	cd.cls = T.short
	cd.nation = Color(NATION_COL.get(T.nation, "888888"))
	return cd


func _update_qual() -> void:
	qual_btn.text = "ГРАФИКА:\nВЫСОКАЯ" if main.save.hq else "ГРАФИКА:\nБЫСТРАЯ"


func _update_eco() -> void:
	eco_btn.text = "ЭКОНОМИЯ:\n30 FPS" if main.save.eco else "ЭКОНОМИЯ:\nВЫКЛ"


func _update_res_btn() -> void:
	res_btn.text = "ЧЁТКОСТЬ:\n%d %%" % roundi(float(main.save.res) * 100.0)


func _update_res() -> void:
	silver_lbl.text = _num(main.save.silver)
	free_lbl.text = _num(main.save.free_xp)


func _update_cons(last: String) -> void:
	var c := last if last != "" else "repair"
	var C: Dictionary = D.CONSUMABLES[c]
	var on: bool = main.save.cons.has(c)
	cons_desc.text = "%s: %s. Перезарядка %d с, %s серебра за бой, если пригодится.%s" % [C.name, C.desc, int(C.cd),
		_num(D.cons_price(c, D.tier(main.save.tank))), "" if on else " Не берётся."]


## Карта, по которой показываем танк: выбранная или (для случайной) первая, где он воевал.
func _view_map(key: String) -> String:
	var m: String = main.save.map
	if D.MAPS.has(m):
		return m
	var maps := D.maps_for(key, true)
	return maps[0] if not maps.is_empty() else ""


## Год, модификацию которого показываем (Pz IV G/H/J, Panther D/A/G).
func _map_year(key: String) -> int:
	var m := _view_map(key)
	return D.MAPS[m].year if m != "" else int(D.TYPES[key].year)


## Воевал ли танк на выбранной карте (при свободных составах — всегда).
func _available(key: String) -> bool:
	if not main.save.history:
		return true
	var m: String = main.save.map
	if m == "random":
		return not D.maps_for(key, true).is_empty()
	return D.MAPS[m].roster[D.TYPES[key].side].has(key)


func _select_tank(key: String) -> void:
	if not main.save.owned.has(key):
		return
	main.save.tank = key
	main.persist()
	for k in cards:
		(cards[k] as TankCard).selected = k == key
		(cards[k] as TankCard).queue_redraw()
	_show_tank_info()
	_update_cons("")
	_refresh()
	_show_preview()


func _show_tank_info() -> void:
	var key: String = main.save.tank
	var T := D.spec(key, _map_year(key), main.top_config(key))
	var B: Dictionary = D.TYPES[key]
	tier_lbl.text = "УРОВЕНЬ %s · %s · %s" % [D.ROMAN[int(B.tier)], String(B.cls).to_upper(), String(B.nation).to_upper()]
	name_lbl.text = String(T.name).to_upper()
	tank_bars.T = T
	tank_bars.queue_redraw()
	xp_lbl.text = "Опыт танка: %s" % _num(main.txp(key))
	var slots: Dictionary = D.MODULES.get(key, {})
	var done := 0
	for s in slots:
		if main.module_researched(key, s):
			done += 1
	mods_btn.text = "МОДУЛИ  %d / %d" % [done, slots.size()] if not slots.is_empty() else "МОДУЛИ"
	_update_res()


func _show_preview() -> void:
	if preview:
		preview.queue_free()
	var key: String = main.save.tank
	var vm := _view_map(key)
	var tk: TankScript = TankScript.new()
	add_child(tk)
	tk.setup(key, 0, Vector2.ZERO, "", false, true, _map_year(key), D.paint(key, vm, main.save.history) if vm != "" else {},
		main.top_config(key))
	tk.hull = 0.35
	tk.tur = 0.35
	tk.set_dust(Color("8a7c5c"), 0.18)
	tk.sync_node()
	preview = tk


## Подписи и доступность: где воевал танк, кто воюет на карте, можно ли в бой.
func _refresh() -> void:
	var key: String = main.save.tank
	var T: Dictionary = D.TYPES[key]
	var hist: bool = main.save.history
	for m in map_btns:
		var ok: bool = m == "random" or not hist or D.MAPS[m].roster[T.side].has(key)
		(map_btns[m] as Button).modulate.a = 1.0 if ok else 0.45
	hist_btn.text = "Составы: исторические" if hist else "Составы: свободные"
	var can := _available(key)
	go_btn.disabled = not can
	go_btn.text = "В БОЙ" if can else "НЕ ВОЕВАЛ ЗДЕСЬ"
	UI.accent(go_btn, 30 if can else 20)
	go_btn.modulate.a = 1.0 if can else 0.6
	var m: String = main.save.map
	if D.MAPS.has(m):
		var M: Dictionary = D.MAPS[m]
		map_desc.text = "%s · %s против %s. %s." % [M.date, M[T.side], M[D.foe_side(T.side) + "_g"], M.desc]
	else:
		var names: Array = []
		for mk in D.maps_for(key, true):
			names.append(D.MAPS[mk].name)
		if hist:
			map_desc.text = "Где воевал танк: %s." % ", ".join(names) if not names.is_empty() else "Карт периода этого танка пока нет — только свободные составы."
		else:
			map_desc.text = "Любая из пяти карт"


func _select_mode(key: String) -> void:
	main.save.mode = key
	main.persist()
	mode_desc.text = D.MODES[key].desc


func _select_map(key: String) -> void:
	(map_btns[key] as Button).button_pressed = true
	main.save.map = key
	main.persist()
	_select_tank(main.save.tank)


## Итог прошлого боя — коротко, на несколько секунд.
func _show_last() -> void:
	var L: Dictionary = main.save.last
	if L.is_empty():
		return
	var res: String = {"win": "ПОБЕДА", "lose": "ПОРАЖЕНИЕ"}.get(L.result, "НИЧЬЯ")
	toast.text = "%s на «%s»: +%s опыта, %s%s серебра" % [res, D.TYPES[L.tank].tag, _num(L.xp),
		"+" if int(L.silver) >= 0 else "−", _num(absi(int(L.silver)))]
	toast_t = 7.0
	toast.visible = true
	main.save.last = {}
	main.persist()


static func _num(v) -> String:
	var n := absi(int(v))
	var t := str(n)
	var out := ""
	while t.length() > 3:
		out = " " + t.right(3) + out
		t = t.left(t.length() - 3)
	return ("-" if int(v) < 0 else "") + t + out


# ---------- Окна ----------

## Окно поверх ангара: затемнение, панель с заголовком и кнопкой «Закрыть». Возвращает содержимое.
func _modal(title: String) -> VBoxContainer:
	_close_modal()
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.LINE, 2, 12, 0.97, 14.0))
	pc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var s := UI.safe(root)
	pc.offset_left = 24 + s.x
	pc.offset_right = -24 - s.z
	pc.offset_top = 14 + s.y
	pc.offset_bottom = -14 - s.w
	modal.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.name = "Head"
	v.add_child(head)
	head.add_child(UI.label(title, 22, D.AMBER))
	head.add_child(_spacer())
	return v


func _close_btn(head: Control) -> void:
	var b := Button.new()
	b.text = "ЗАКРЫТЬ"
	b.custom_minimum_size = Vector2(130, 44)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(_close_modal)
	head.add_child(b)


func _close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null


## Окно с авторами моделей и звуков (CC-BY требует указывать их).
func _show_credits() -> void:
	var v := _modal("АВТОРЫ")
	_close_btn(v.get_node("Head"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var txt := "Карты, окружение, ангар и «Крусейдер» — процедурная генерация.\n\n"
	for path in ["res://assets/models/CREDITS.txt", "res://assets/sfx/CREDITS.txt"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			txt += f.get_as_text() + "\n"
	var l := UI.label(txt, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(l)


# ---------- Модули ----------

## Модули выбранного танка: что стоит, что даёт исследование, переключение стокового и нового.
func _show_modules() -> void:
	var key: String = main.save.tank
	var v := _modal("МОДУЛИ · " + String(D.TYPES[key].name).to_upper())
	var head: Control = v.get_node("Head")
	var xpl := _chip(head, "ОПЫТ ТАНКА")
	xpl.text = _num(main.txp(key))
	var fl := _chip(head, "СВОБОДНЫЙ ОПЫТ")
	fl.text = _num(main.save.free_xp)
	var sl := _chip(head, "СЕРЕБРО")
	sl.text = _num(main.save.silver)
	_close_btn(head)
	var slots: Dictionary = D.MODULES.get(key, {})
	if slots.is_empty():
		v.add_child(UI.label("У этого танка нет сменных модулей.", 16, UI.DIM))
		return
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var year := _map_year(key)
	for slot in D.SLOTS:
		if not slots.has(slot):
			continue
		var M: Array = slots[slot]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.box(UI.PANEL2, UI.LINE, 1, 8, 0.9, 12.0))
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		h.add_child(info)
		info.add_child(UI.label(String(D.SLOT_NAMES[slot]).to_upper(), 12, UI.DIM))
		info.add_child(UI.label("%s  →  %s" % [M[0], M[1]], 17))
		var lo := D.spec(key, year, {slot: false})
		var hi := D.spec(key, year, {slot: true})
		var eff := UI.label(_effect(slot, lo, hi), 13, GREEN)
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(eff)
		if main.module_researched(key, slot):
			var on: bool = main.module_on(key, slot)
			var g := ButtonGroup.new()
			for top: bool in [false, true]:
				var b := Button.new()
				b.text = "СТОКОВЫЙ" if not top else "НОВЫЙ"
				b.toggle_mode = true
				b.button_group = g
				b.button_pressed = on == top
				b.custom_minimum_size = Vector2(120, 44)
				b.add_theme_font_size_override("font_size", 14)
				b.pressed.connect(func():
					main.set_module(key, slot, top)
					_show_tank_info()
					_show_preview())
				h.add_child(b)
		else:
			var xp := D.module_xp(key, slot)
			var price := D.module_price(key, slot)
			var ok: bool = main.txp(key) + int(main.save.free_xp) >= xp and int(main.save.silver) >= price
			var b := Button.new()
			b.text = "ИССЛЕДОВАТЬ\n%s опыта · %s серебра" % [_num(xp), _num(price)]
			b.custom_minimum_size = Vector2(250, 52)
			b.add_theme_font_size_override("font_size", 14)
			if ok:
				UI.accent(b, 14)
			else:
				b.disabled = true
			b.pressed.connect(func():
				if main.research_module(key, slot):
					_show_tank_info()
					_show_preview()
					_show_modules())
			h.add_child(b)


## Что меняет исследованный модуль, в цифрах.
static func _effect(slot: String, lo: Dictionary, hi: Dictionary) -> String:
	match slot:
		"gun":
			return "Урон %d → %d, пробитие %d → %d мм, перезарядка %.1f → %.1f с" % [lo.dmg, hi.dmg, lo.pen, hi.pen, lo.reload, hi.reload]
		"turret":
			return "Броня лба башни %d → %d мм, поворот %d → %d °/с, прочность %d → %d" % [lo.armor[3], hi.armor[3], lo.tspd, hi.tspd, lo.hp, hi.hp]
		"engine":
			return "Мощность %d → %d л.с.: быстрее разгон и подъём в гору" % [lo.power, hi.power]
	return "Поворот корпуса %d → %d °/с" % [roundi(float(lo.turn)), roundi(float(hi.turn))]


# ---------- Дерево исследования ----------

func _show_tree(side: String) -> void:
	tree_side = side
	var v := _modal("ИССЛЕДОВАНИЯ")
	var head: Control = v.get_node("Head")
	var sg := ButtonGroup.new()
	for s in ["allies", "axis"]:
		var b := Button.new()
		b.text = String(D.SIDES[s].name).to_upper()
		b.toggle_mode = true
		b.button_group = sg
		b.button_pressed = s == side
		b.custom_minimum_size = Vector2(130, 44)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_show_tree.bind(s))
		head.add_child(b)
	var fl := _chip(head, "СВОБОДНЫЙ ОПЫТ")
	fl.text = _num(main.save.free_xp)
	var sl := _chip(head, "СЕРЕБРО")
	sl.text = _num(main.save.silver)
	_close_btn(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var view := TreeView.new()
	view.hangar = self
	view.side = side
	sc.add_child(view)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.name = "Bar"
	v.add_child(bar)
	if tree_sel == "" or D.TYPES[tree_sel].side != side:
		tree_sel = ""
		for k in TREE_POS[side]:
			if main.can_research(k) or (main.save.researched.has(k) and not main.save.owned.has(k)):
				tree_sel = k
				break
	_tree_bar(bar)


## Состояние танка в дереве: в ангаре, исследован (можно купить), можно исследовать, закрыт.
func tree_state(key: String) -> Array:
	if main.save.owned.has(key):
		return ["В АНГАРЕ", Color(GREEN)]
	if main.save.researched.has(key):
		return ["%s серебра" % _num(D.price(key)), Color(BLUE)]
	if main.can_research(key):
		return ["%s опыта" % _num(D.research_xp(key)), Color(D.AMBER)]
	return ["закрыт", Color(UI.LINE)]


func tree_pick(key: String) -> void:
	tree_sel = key
	if modal:
		var bar: HBoxContainer = modal.find_child("Bar", true, false)
		if bar:
			_tree_bar(bar)
		var tv: TreeView = modal.find_child("TreeView", true, false)
		if tv:
			tv.refresh()


## Нижняя строка дерева: о выбранном танке и что с ним можно сделать.
func _tree_bar(bar: HBoxContainer) -> void:
	for c in bar.get_children():
		c.queue_free()
	if tree_sel == "":
		bar.add_child(UI.label("Выберите танк в дереве", 15, UI.DIM))
		return
	var key := tree_sel
	var T: Dictionary = D.TYPES[key]
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	bar.add_child(info)
	info.add_child(UI.label("%s %s · %s · %s" % [D.ROMAN[int(T.tier)], T.name, T.cls, T.nation], 17))
	var ps: Array = []
	for p in D.parents(key):
		ps.append(D.TYPES[p].tag)
	var sub := ""
	if main.save.owned.has(key):
		sub = "В ангаре. Опыт танка: %s." % _num(main.txp(key))
	elif main.save.researched.has(key):
		sub = "Исследован. Цена %s серебра, у вас %s." % [_num(D.price(key)), _num(main.save.silver)]
	elif main.can_research(key):
		sub = "Опыт на исследование: %s. Доступно: %s (опыт «%s» и свободный)." % [_num(D.research_xp(key)),
			_num(main.research_pool(key)), "», «".join(ps)]
	else:
		sub = "Сначала исследуйте: %s." % ", ".join(ps) if not ps.is_empty() else ""
	var sl := UI.label(sub, 13, UI.DIM)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sl)
	var b := Button.new()
	b.custom_minimum_size = Vector2(240, 54)
	b.add_theme_font_size_override("font_size", 16)
	bar.add_child(b)
	if main.save.owned.has(key):
		b.text = "В АНГАР"
		UI.accent(b, 18)
		b.pressed.connect(func():
			_close_modal()
			_select_tank(key))
	elif main.save.researched.has(key):
		b.text = "КУПИТЬ · %s" % _num(D.price(key))
		if int(main.save.silver) >= D.price(key):
			UI.accent(b, 18)
		else:
			b.disabled = true
		b.pressed.connect(func():
			if main.buy(key):
				_fill_carousel()
				_close_modal()
				_select_tank(key))
	elif main.can_research(key):
		b.text = "ИССЛЕДОВАТЬ · %s" % _num(D.research_xp(key))
		if main.research_pool(key) >= D.research_xp(key):
			UI.accent(b, 18)
		else:
			b.disabled = true
		b.pressed.connect(func():
			if main.research(key):
				_update_res()
				_show_tree(tree_side))
	else:
		b.text = "ЗАКРЫТ"
		b.disabled = true


## Дерево: карточки танков по уровням (столбцы) и стрелки «что что открывает».
class TreeView extends Control:
	var hangar
	var side := "allies"
	var nodes := {}
	const CW := 168.0
	const CH := 70.0
	const GX := 196.0
	const GY := 86.0
	const PAD := Vector2(12, 26)

	func _ready() -> void:
		name = "TreeView"
		mouse_filter = Control.MOUSE_FILTER_PASS
		var pos: Dictionary = TREE_POS[side]
		var maxr := 0.0
		for k in pos:
			maxr = maxf(maxr, float(pos[k][1]))
			var cd: TankCard = hangar._card(k)
			cd.position = PAD + Vector2(float(pos[k][0]) * GX, float(pos[k][1]) * GY)
			cd.size = Vector2(CW, CH)
			cd.picked.connect(hangar.tree_pick)
			add_child(cd)
			nodes[k] = cd
		custom_minimum_size = PAD * 2 + Vector2(5 * GX + CW, maxr * GY + CH)
		refresh()

	func refresh() -> void:
		for k in nodes:
			var st: Array = hangar.tree_state(k)
			var cd: TankCard = nodes[k]
			cd.state = st[0]
			cd.border = st[1]
			cd.dim = st[0] == "закрыт"
			cd.selected = k == hangar.tree_sel
			cd.queue_redraw()
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for t in range(3, 9):
			draw_string(font, PAD + Vector2((t - 3) * GX + 6, -8), "УРОВЕНЬ " + D.ROMAN[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UI.DIM))
		for k in nodes:
			for ch in D.TREE.get(k, []):
				if not nodes.has(ch):
					continue
				var a: Vector2 = nodes[k].position + Vector2(CW, CH / 2)
				var b: Vector2 = nodes[ch].position + Vector2(0, CH / 2)
				var open: bool = hangar.main.save.researched.has(ch)
				var col := Color(GREEN) if open else Color(UI.LINE)
				var mx := (a.x + b.x) / 2
				draw_polyline(PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b]), col, 3.0 if open else 2.0, true)
				draw_colored_polygon(PackedVector2Array([b, b + Vector2(-9, -6), b + Vector2(-9, 6)]), col)
