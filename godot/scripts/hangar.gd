extends Node3D
## Ангар: вращающаяся 3D-витрина танка и выбор танка, режима и карты.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const TankScript = preload("res://scripts/tank.gd")

var main  # main.gd
var cam: Camera3D
var preview: Node3D
var orbit := 0.7
var root: Control
var margin: MarginContainer
var stats_row: HBoxContainer
var tank_cls: Label
var tank_bars: TankBars
var mode_desc: Label
var map_desc: Label
var qual_btn: Button


## Полоски характеристик выбранного танка.
class TankBars extends Control:
	var T: Dictionary = {}
	var font: Font

	func _ready() -> void:
		font = ThemeDB.fallback_font
		custom_minimum_size = Vector2(0, 158)

	func _draw() -> void:
		if T.is_empty():
			return
		var A: Array = T.armor
		var rows := [
			["Прочность", "%d" % int(T.hp), float(T.hp) / 1500.0],
			["Урон / пробитие", "%d / %d мм" % [int(T.dmg), int(T.pen)], float(T.pen) / 165.0],
			["Броня лба", "%d / %d мм" % [A[0], A[3]], float(A[0]) / 120.0],
			["Скорость", "%d км/ч" % int(T.kmh), float(T.kmh) / 56.0],
			["Мощность", "%d л.с. · %.1f т" % [int(T.power), float(T.mass)], float(T.power) / float(T.mass) / 16.0],
			["Перезарядка", "%.1f с" % float(T.reload), 2.4 / float(T.reload)],
		]
		var y := 0.0
		for r in rows:
			draw_string(font, Vector2(0, y + 15), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.DIM))
			draw_string(font, Vector2(0, y + 15), r[1], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, Color(UI.TEXT))
			draw_rect(Rect2(0, y + 19, size.x, 4), Color(0.05, 0.06, 0.04))
			draw_rect(Rect2(0, y + 19, size.x * clampf(r[2], 0.05, 1.0), 4), Color("7bc65a"))
			y += 26.0


func _ready() -> void:
	_build_scene()
	_build_ui()
	_select_tank(main.save.tank)


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1a1f15")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a9478")
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color("1a1f15")
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-40, 60, 50)
	lamp.light_color = Color("f0b73a")
	lamp.light_energy = 1.5
	lamp.omni_range = 160
	add_child(lamp)
	# площадка-поворотный круг
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color("2a3022")
	floor_m.roughness = 0.7
	var disc := CylinderMesh.new()
	disc.top_radius = 62
	disc.bottom_radius = 64
	disc.height = 3
	disc.radial_segments = 48
	var dmi := MeshInstance3D.new()
	dmi.mesh = disc
	dmi.material_override = floor_m
	dmi.position.y = -1.5
	add_child(dmi)
	var ring := TorusMesh.new()
	ring.inner_radius = 63
	ring.outer_radius = 65
	ring.rings = 64
	ring.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(D.AMBER)
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.material_override = rm
	rmi.scale = Vector3(1, 0.2, 1)
	add_child(rmi)
	var ground := PlaneMesh.new()
	ground.size = Vector2(1200, 1200)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("161a12")
	var gmi := MeshInstance3D.new()
	gmi.mesh = ground
	gmi.material_override = gm
	gmi.position.y = -3
	add_child(gmi)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true


func _process(delta: float) -> void:
	orbit += delta * 0.18
	if preview:
		preview.tur = 0.4 + sin(orbit * 2.0) * 0.6
		preview.gun_pitch = 0.05 + sin(orbit * 3.0) * 0.05
		preview.sync_node()
	cam.position = Vector3(cos(orbit) * 118.0, 44.0, sin(orbit) * 118.0)
	cam.look_at(Vector3(0, 10, 0), Vector3.UP)
	var s := UI.safe(root)
	margin.add_theme_constant_override("margin_left", int(24 + s.x))
	margin.add_theme_constant_override("margin_top", int(18 + s.y))
	margin.add_theme_constant_override("margin_right", int(24 + s.z))
	margin.add_theme_constant_override("margin_bottom", int(16 + s.w))


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
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	# заголовок и статистика
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	head.add_child(UI.label("СТАЛЬНОЙ", 40))
	head.add_child(UI.label("ШТУРМ", 40, D.AMBER))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	stats_row = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 6)
	head.add_child(stats_row)
	_fill_stats()

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 16)
	vb.add_child(body)

	# слева: танки и характеристики
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UI.label("ТАНК", 14, UI.DIM))
	var tg := ButtonGroup.new()
	for key in D.TYPES:
		var T: Dictionary = D.TYPES[key]
		var b := Button.new()
		b.text = "%s   %s" % [T.short, T.name]
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = tg
		b.button_pressed = key == main.save.tank
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(_select_tank.bind(key))
		lv.add_child(b)
	tank_cls = UI.label("", 15, D.AMBER)
	lv.add_child(tank_cls)
	tank_bars = TankBars.new()
	lv.add_child(tank_bars)
	qual_btn = Button.new()
	qual_btn.add_theme_font_size_override("font_size", 16)
	qual_btn.pressed.connect(func():
		main.save.hq = not main.save.hq
		main.persist()
		_update_qual())
	lv.add_child(qual_btn)
	_update_qual()

	# центр: витрина и подсказка
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(center)
	var cs := Control.new()
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(cs)
	var hint := UI.label("Левый палец: газ и поворот корпуса. Правый: свайп крутит камеру и поднимает прицел, тап стреляет. Круг прицела зелёный — пробьёт, красный — нет. Постой на месте, чтобы свестись.", 14, UI.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(hint)

	# справа: режим, карта, кнопка боя
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UI.label("РЕЖИМ", 14, UI.DIM))
	var mg := ButtonGroup.new()
	for key in D.MODES:
		var b := Button.new()
		b.text = D.MODES[key].name
		b.toggle_mode = true
		b.button_group = mg
		b.button_pressed = key == main.save.mode
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(_select_mode.bind(key))
		rv.add_child(b)
	mode_desc = UI.label("", 14, UI.DIM)
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(mode_desc)
	rv.add_child(UI.label("КАРТА", 14, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
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
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(_select_map.bind(key))
		grid.add_child(b)
	map_desc = UI.label("", 14, UI.DIM)
	rv.add_child(map_desc)
	var rs := Control.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(rs)
	var go := Button.new()
	go.text = "В БОЙ"
	go.custom_minimum_size = Vector2(0, 66)
	UI.accent(go, 30)
	go.pressed.connect(func(): main.start_battle())
	rv.add_child(go)
	_select_mode(main.save.mode)
	_select_map(main.save.map)


func _fill_stats() -> void:
	for c in stats_row.get_children():
		c.queue_free()
	var s: Dictionary = main.save
	for item in [["Боёв", s.battles], ["Побед", s.wins], ["Уничтожено", s.kills], ["Лучший урон", s.best_dmg], ["Серебро", s.silver]]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.LINE, 1, 8, 0.85, 10.0))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.add_child(UI.label(str(int(item[1])), 20))
		col.add_child(UI.label(String(item[0]).to_upper(), 11, UI.DIM))
		pc.add_child(col)
		stats_row.add_child(pc)


func _select_tank(key: String) -> void:
	main.save.tank = key
	main.persist()
	var T: Dictionary = D.TYPES[key]
	tank_cls.text = ("%s · %s" % [T.cls, T.nation]).to_upper()
	tank_bars.T = T
	tank_bars.queue_redraw()
	if preview:
		preview.queue_free()
	var tk: TankScript = TankScript.new()
	add_child(tk)
	tk.setup(key, 0, Vector2.ZERO, "", false, true)
	tk.hull = 0.4
	tk.tur = 0.4
	tk.sync_node()
	preview = tk


func _select_mode(key: String) -> void:
	main.save.mode = key
	main.persist()
	mode_desc.text = D.MODES[key].desc


func _select_map(key: String) -> void:
	main.save.map = key
	main.persist()
	map_desc.text = D.MAPS[key].desc if D.MAPS.has(key) else "Любая из трёх"


func _update_qual() -> void:
	qual_btn.text = "Графика: высокая" if main.save.hq else "Графика: быстрая"
