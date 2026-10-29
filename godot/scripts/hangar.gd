extends Node3D
## Ангар: вращающаяся 3D-витрина танка и выбор танка, режима и карты.

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const TankScript = preload("res://scripts/tank.gd")
const Geo = preload("res://scripts/geo.gd")
const TexLib = preload("res://scripts/textures.gd")

var main  # main.gd
var cam: Camera3D
var preview: Node3D
var orbit := 0.7
var root: Control
var margin: MarginContainer
var stats_row: HBoxContainer
var tank_cls: Label
var tank_info: Label
var tank_bars: TankBars
var mode_desc: Label
var map_desc: Label
var qual_btn: Button
var hist_btn: Button
var go_btn: Button
var side_btns := {}
var tank_grid: GridContainer
var tank_btns := {}
var map_btns := {}


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
	# если сохранённый танк на выбранной карте не воевал, берём первый подходящий той же стороны
	_select_side(D.TYPES[main.save.tank].side, main.save.tank if _available(main.save.tank) else "")


## Интерьер ангара: бетонный пол, стены из профнастила, фермы перекрытия, лампы над танком.
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("15130f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4b0a4")
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("1d1a15")
	env.fog_depth_begin = 180.0
	env.fog_depth_end = 520.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var g := Geo.Group.new()
	var floor_m := TexLib.world_mat("concrete", Vector3(1, 1, 1) / 40.0, 0.0, 0.5, Color(0.75, 0.73, 0.68))
	var wall_m := TexLib.world_mat("rust", Vector3(1, 1, 1) / 30.0, 0.0, 0.3, Color(0.75, 0.78, 0.72))
	var beam_m := TexLib.world_mat("rust", Vector3(1, 1, 1) / 12.0, 0.0, 0.2, Color(0.55, 0.55, 0.52))
	var wood_m := TexLib.world_mat("wood", Vector3(1, 1, 1) / 14.0)
	var steel_m := TexLib.world_mat("concrete", Vector3(1, 1, 1) / 20.0, 0.0, 0.2, Color(0.45, 0.47, 0.45))
	g.add(Geo.box(Vector3(700, 2, 700)), Geo.xf(Vector3(0, -1, 0)), floor_m)
	# стены из профнастила: рёбра через каждые 6 единиц
	for side in 4:
		var bs := Basis(Vector3.UP, side * PI / 2)
		g.add(Geo.box(Vector3(500, 190, 4)), Transform3D(bs, bs * Vector3(0, 95, -250)), wall_m)
		for k in 80:
			g.add(Geo.box(Vector3(2.2, 190, 3)), Transform3D(bs, bs * Vector3(-240 + k * 6.1, 95, -247.5)), wall_m)
	# фермы перекрытия
	for k in 5:
		var z := -200.0 + k * 100.0
		g.add(Geo.box(Vector3(500, 5, 5)), Geo.xf(Vector3(0, 170, z)), beam_m)
		for x in range(-240, 241, 40):
			g.add(Geo.box(Vector3(3, 3, 60)), Geo.xf(Vector3(x, 158, z), Vector3(0.6, 0, 0)), beam_m)
	# поворотный стол и разметка
	g.add(Geo.cyl(66, 68, 2.4, 64), Geo.xf(Vector3(0, 1.2, 0)), steel_m)
	# ящики со снарядами и бочки у стен
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for k in 9:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(130, 200)
		var sz := Vector3(rng.randf_range(12, 20), rng.randf_range(8, 12), rng.randf_range(8, 12))
		g.add(Geo.box(sz), Geo.xf(p + Vector3(0, sz.y / 2, 0), Vector3(0, rng.randf() * TAU, 0)), wood_m)
		g.add(Geo.cyl(4.2, 4.2, 10, 14), Geo.xf(p + Vector3(16, 5, 6)), beam_m)
	g.commit(self, true)
	var ring := TorusMesh.new()
	ring.inner_radius = 64
	ring.outer_radius = 66
	ring.rings = 64
	ring.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(D.AMBER)
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.material_override = rm
	rmi.position.y = 2.5
	rmi.scale = Vector3(1, 0.15, 1)
	add_child(rmi)
	# подвесные лампы: тёплый конус света на танк и рассеянный по углам
	for p in [Vector3(-30, 150, 20), Vector3(40, 150, -25)]:
		var spot := SpotLight3D.new()
		spot.position = p
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.spot_angle = 42.0
		spot.spot_range = 260.0
		spot.light_energy = 8.0
		spot.light_color = Color("fff0dc")
		spot.shadow_enabled = true
		add_child(spot)
		var shade := MeshInstance3D.new()
		shade.mesh = Geo.cyl(3, 9, 6, 16)
		shade.material_override = beam_m
		shade.position = p + Vector3(0, 3, 0)
		add_child(shade)
		var bulb := MeshInstance3D.new()
		bulb.mesh = Geo.sphere(10, 6)
		bulb.scale = Vector3(4, 4, 4)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color("fff1c8")
		bulb.material_override = bm
		bulb.position = p
		add_child(bulb)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 90, 160)
	fill.light_color = Color("8fa0b0")
	fill.light_energy = 1.4
	fill.omni_range = 320
	add_child(fill)
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
	cam.position = Vector3(cos(orbit) * 96.0, 34.0, sin(orbit) * 96.0)
	cam.look_at(Vector3(0, 9, 0), Vector3.UP)
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

	# слева: сторона, танки и характеристики
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 7)
	left.add_child(lv)
	lv.add_child(UI.label("СТОРОНА", 14, UI.DIM))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 8)
	lv.add_child(sides)
	var sg := ButtonGroup.new()
	for key in D.SIDES:
		var b := Button.new()
		b.text = String(D.SIDES[key].name).to_upper()
		b.toggle_mode = true
		b.button_group = sg
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_select_side.bind(key, ""))
		sides.add_child(b)
		side_btns[key] = b
	lv.add_child(UI.label("ТАНК", 14, UI.DIM))
	tank_grid = GridContainer.new()
	tank_grid.columns = 2
	tank_grid.add_theme_constant_override("h_separation", 8)
	tank_grid.add_theme_constant_override("v_separation", 6)
	lv.add_child(tank_grid)
	tank_cls = UI.label("", 15, D.AMBER)
	tank_cls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tank_cls.custom_minimum_size = Vector2(300, 0)
	lv.add_child(tank_cls)
	tank_info = UI.label("", 13, UI.DIM)
	tank_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tank_info.custom_minimum_size = Vector2(300, 0)
	lv.add_child(tank_info)
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
		b.custom_minimum_size = Vector2(0, 44)
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
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(_select_map.bind(key))
		grid.add_child(b)
		map_btns[key] = b
	map_desc = UI.label("", 14, UI.DIM)
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_desc.custom_minimum_size = Vector2(300, 0)
	rv.add_child(map_desc)
	hist_btn = Button.new()
	hist_btn.add_theme_font_size_override("font_size", 16)
	hist_btn.custom_minimum_size = Vector2(0, 40)
	hist_btn.pressed.connect(func():
		main.save.history = not main.save.history
		main.persist()
		_refresh())
	rv.add_child(hist_btn)
	var rs := Control.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(rs)
	go_btn = Button.new()
	go_btn.text = "В БОЙ"
	go_btn.custom_minimum_size = Vector2(0, 66)
	UI.accent(go_btn, 30)
	go_btn.pressed.connect(func(): main.start_battle())
	rv.add_child(go_btn)
	_select_mode(main.save.mode)


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


## Сторона: в сетке остаются её машины; выбирается переданный танк или первый, воевавший на карте.
func _select_side(side: String, want: String) -> void:
	(side_btns[side] as Button).button_pressed = true
	for c in tank_grid.get_children():
		c.queue_free()
	tank_btns.clear()
	var tg := ButtonGroup.new()
	for key in D.TYPES:
		var T: Dictionary = D.TYPES[key]
		if T.side != side:
			continue
		var b := Button.new()
		b.text = "%s  %s" % [T.short, T.tag]
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = tg
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(_select_tank.bind(key))
		tank_grid.add_child(b)
		tank_btns[key] = b
	if want == "" or not tank_btns.has(want):
		want = ""
		for key in tank_btns:
			if _available(key):
				want = key
				break
		if want == "":
			want = tank_btns.keys()[0]
	_select_tank(want)


## Воевал ли танк на выбранной карте (при свободных составах — всегда).
func _available(key: String) -> bool:
	if not main.save.history:
		return true
	var m: String = main.save.map
	if m == "random":
		return not D.maps_for(key, true).is_empty()
	return D.MAPS[m].roster[D.TYPES[key].side].has(key)


func _select_tank(key: String) -> void:
	main.save.tank = key
	main.persist()
	(tank_btns[key] as Button).button_pressed = true
	var T: Dictionary = D.TYPES[key]
	tank_cls.text = ("%s · %s · %d" % [T.cls, T.nation, int(T.year)]).to_upper()
	tank_bars.T = T
	tank_bars.queue_redraw()
	_refresh()
	_show_preview()


func _show_preview() -> void:
	if preview:
		preview.queue_free()
	var m: String = main.save.map
	var tk: TankScript = TankScript.new()
	add_child(tk)
	tk.setup(main.save.tank, 0, Vector2.ZERO, "", false, true, D.MAPS[m].year if D.MAPS.has(m) else 1943)
	tk.hull = 0.4
	tk.tur = 0.4
	tk.sync_node()
	preview = tk


## Подписи и доступность: где воевал танк, кто воюет на карте, можно ли в бой.
func _refresh() -> void:
	var key: String = main.save.tank
	var T: Dictionary = D.TYPES[key]
	var hist: bool = main.save.history
	var maps := D.maps_for(key, true)
	var names: Array = []
	for m in maps:
		names.append(D.MAPS[m].name)
	var where := "Воевал: %s." % ", ".join(names) if not names.is_empty() else "В бою с %d г. — карт этого периода пока нет, доступен в свободных составах." % int(T.year)
	tank_info.text = "Боевой вес %d. %s" % [int(T.pts), where]
	for k in tank_btns:
		(tank_btns[k] as Button).modulate.a = 1.0 if _available(k) else 0.45
	for m in map_btns:
		var ok: bool = m == "random" or not hist or D.MAPS[m].roster[T.side].has(key)
		(map_btns[m] as Button).modulate.a = 1.0 if ok else 0.45
	hist_btn.text = "Составы: исторические" if hist else "Составы: свободные"
	var can := _available(key)
	go_btn.disabled = not can
	go_btn.text = "В БОЙ" if can else "НЕ ВОЕВАЛ ЗДЕСЬ"
	UI.accent(go_btn, 30 if can else 22)
	go_btn.modulate.a = 1.0 if can else 0.6
	var m: String = main.save.map
	if D.MAPS.has(m):
		var M: Dictionary = D.MAPS[m]
		map_desc.text = "%s · %s против %s. %s." % [M.date, M[T.side], M[D.foe_side(T.side) + "_g"], M.desc]
	else:
		map_desc.text = "Любая из карт, где воевал выбранный танк" if hist else "Любая из трёх карт"


func _select_mode(key: String) -> void:
	main.save.mode = key
	main.persist()
	mode_desc.text = D.MODES[key].desc


func _select_map(key: String) -> void:
	(map_btns[key] as Button).button_pressed = true
	main.save.map = key
	main.persist()
	_refresh()
	_show_preview()


func _update_qual() -> void:
	qual_btn.text = "Графика: высокая" if main.save.hq else "Графика: быстрая"
